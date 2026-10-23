"""
Chat providers — the LLM is pluggable, and there is a working default.

WHY A RULE-BASED PROVIDER IS THE DEFAULT
----------------------------------------
A lab HMI cannot depend on an outbound internet connection to answer "why is
Start greyed out?". The built-in provider answers the operational questions
deterministically, from live system context, with no network call, no API key
and no latency. It is the default and it always works.

An LLM provider is genuinely better at open-ended phrasing, so the interface
supports one. But it is opt-in, and when it is unreachable the service falls
back rather than failing.

ADDING A PROVIDER
-----------------
Subclass `ChatProvider`, implement `generate`, register it in `PROVIDERS`. The
service and the API do not change. Nothing outside this file knows which
provider is in use.

WHAT NO PROVIDER CAN DO
-----------------------
Providers receive the redacted context dict from `chat/context.py` and return
text. They are handed no callable, no service reference and no write path. A
provider cannot command the machine because it is never given anything that
could.
"""

from __future__ import annotations

import json
import logging
import os
import re
import time
from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional

log = logging.getLogger("chat.provider")


class ChatProvider(ABC):
    name = "base"
    requires_network = False

    @abstractmethod
    def generate(
        self, message: str, context: Dict[str, Any], history: List[dict]
    ) -> Dict[str, Any]:
        """Return {'text': str, 'provider': str, ...}. Must not raise."""

    def available(self) -> tuple:
        return True, ""


# ---------------------------------------------------------------------------
# built-in provider
# ---------------------------------------------------------------------------

class BuiltinProvider(ChatProvider):
    """
    Deterministic intent matching over live context.

    Not a language model, and it does not pretend to be. It recognises the
    questions an operator actually asks at a machine and answers them from
    current state. When it does not recognise a question it says so and lists
    what it can help with, rather than inventing an answer -- which for a
    control system matters more than sounding fluent.
    """

    name = "builtin"

    def generate(self, message: str, context: Dict[str, Any], history: List[dict]) -> Dict[str, Any]:
        text = (message or "").strip().lower()
        for matcher, handler in self._intents():
            if matcher(text):
                return {
                    "text": handler(context),
                    "provider": self.name,
                    "grounded": True,
                }
        return {"text": self._fallback(context), "provider": self.name, "grounded": True}

    # -- intents --------------------------------------------------------

    def _intents(self):
        """
        Ordered most-specific first.

        Ordering is load-bearing. "How do I start recording?" contains "start",
        so a broad cycle-start matcher placed first swallows it and answers the
        wrong question. Every compound topic therefore has to be tested before
        the single keyword it happens to contain.
        """
        def has(*words):
            return lambda t: any(w in t for w in words)

        def all_of(*words):
            return lambda t: all(w in t for w in words)

        def any_of(*matchers):
            return lambda t: any(m(t) for m in matchers)

        return [
            # -- compound topics first ---------------------------------
            (has("recording", "record ", "start record", "stop record",
                 "capture data", "log data"), self._recording),
            (has("snapshot", "save data", "save current", "save state",
                 "capture state"), self._snapshot),
            (has("data source", "active source", "which source",
                 "where is the data", "telemetry source",
                 "control source"), self._source),
            (has("emergency", "e-stop", "estop", "emergency stop",
                 "safety circuit", "interlock"), self._safety),
            (has("matlab", "simulink", "digital twin", "twin"), self._twin),
            (has("camera", "yolo", "vision", "detection"), self._camera),
            (has("history", "historical", "database", "sql",
                 "past cycles", "stored data"), self._history),

            # -- then single-topic keywords ----------------------------
            (any_of(
                all_of("start", "cycle"),
                has("cannot start", "can't start", "cant start",
                    "why is start", "greyed", "grayed", "start button"),
            ), self._start),
            (has("mode", "simulation mode", "plc mode"), self._mode),
            (has("plc", "snap7", "connection", "connected", "disconnect"), self._plc),
            (has("alarm", "fault", "error", "warning", "wrong", "problem"), self._alarms),
            (has("sequence", "step", "stuck", "stall", "waiting", "cycle"), self._sequence),
            (has("valve", "solenoid", "actuator", "conveyor",
                 "manual", "command", "control"), self._manual),
            (has("simulation", "simulate"), self._twin),
            (has("help", "what can you", "how do i", "commands",
                 "hello", "hi ", "hey"), self._help),
        ]

    # -- handlers -------------------------------------------------------

    def _mode(self, c) -> str:
        m = c["mode"]
        lines = [
            "**System mode: %s**" % m["systemMode"],
            "",
            "- Control mode: **%s**" % (m["controlMode"] or "unknown"),
            "- Control source: %s" % (m["controlSource"] or "none selected"),
            "- Telemetry source: %s" % (m["telemetrySource"] or "none"),
            "- Data quality: **%s**%s" % (
                m["dataQuality"], "  ⚠ values are stale" if m["stale"] else "",
            ),
        ]
        caps = c["capabilities"]
        lines += [
            "",
            "In this mode you can:",
            "- Start a cycle: %s" % ("yes" if caps["canStartCycle"] else "no"),
            "- Command valves: %s" % ("yes" if caps["canCommandValves"] else "no"),
            "- Write setpoints: %s" % ("yes" if caps["canWriteSetpoints"] else "no"),
        ]
        if not caps["canCommandValves"] and caps["valvesBlockedBecause"]:
            lines.append("")
            lines.append(caps["valvesBlockedBecause"])
        return "\n".join(lines)

    def _source(self, c) -> str:
        lines = ["**Data sources**", ""]
        for src in c["sources"]:
            role = []
            if src["controlActive"]:
                role.append("CONTROL")
            if not src["supportsControl"]:
                role.append("telemetry-only")
            lines.append(
                "- **%s** (%s) — %s, quality %s%s%s" % (
                    src["name"], src["kind"], src["state"], src["quality"],
                    "  ·  " + ", ".join(role) if role else "",
                    "  ·  last data %.1f s ago" % src["ageSeconds"]
                    if src["ageSeconds"] is not None else "",
                )
            )
            if src["lastError"]:
                lines.append("    error: %s" % src["lastError"])
        lines += [
            "",
            "Only one source can hold control at a time. Simulation sources are "
            "telemetry-only, so simulated values can never reach the PLC.",
        ]
        return "\n".join(lines)

    def _plc(self, c) -> str:
        conn = c["connection"]
        lines = [
            "**PLC connection: %s**%s" % (
                conn["plc"], "  (simulated)" if conn["plcSimulated"] else "",
            ),
            "",
            "- Data age: %s" % (
                "%.1f s" % conn["staleSeconds"] if conn["staleSeconds"] is not None
                else "no successful read yet"
            ),
            "- Average poll latency: %s ms" % conn["latencyMs"],
            "- Errors: %s   Reconnects: %s" % (conn["errorCount"], conn["reconnectCount"]),
        ]
        if conn["lastError"]:
            lines.append("- Last error: %s" % conn["lastError"])
        if conn["stale"]:
            lines += [
                "",
                "⚠ Values on screen are **stale** — the last good read is older "
                "than the freshness budget. They are kept and marked rather than "
                "blanked, so you can still see what the machine was doing.",
            ]
        lines += [
            "",
            "How it works: one background thread owns the single Snap7 client "
            "and reads the whole data block every poll. No web request ever "
            "touches the PLC — everything you see is served from that cache.",
        ]
        return "\n".join(lines)

    def _alarms(self, c) -> str:
        alarms = c["alarms"]
        faults = alarms["activeFaults"]
        findings = alarms["findings"]

        if not faults and not findings:
            return (
                "**No active alarms or findings.**\n\n"
                "Detectors are running for tag chatter, unheld commands, "
                "conveyor motion, pressure and data staleness."
            )

        lines = []
        if faults:
            lines.append("**Active faults (%d)**" % len(faults))
            lines.append("")
            for f in faults:
                lines.append("- **%s** — %s%s" % (
                    f["severity"], f["message"],
                    "  (acknowledged)" if f["acknowledged"] else "",
                ))
        if findings:
            lines.append("")
            lines.append("**Findings (%d)**" % len(findings))
            lines.append("")
            for f in findings:
                ref = "  [%s]" % f["issueRef"] if f.get("issueRef") else ""
                lines.append("- **%s**%s" % (f["title"], ref))
                lines.append("  %s" % f["detail"])
        lines += ["", "Full detail and history are on the **Diagnostics** page."]
        return "\n".join(lines)

    def _start(self, c) -> str:
        safety = c["safety"]
        if safety["canStartCycle"]:
            return (
                "**A cycle can be started now.** All interlocks are satisfied and "
                "the order is valid.\n\nSet the 25 mm / 50 mm quantities on the "
                "Overview page and press **Start cycle**."
            )
        lines = ["**Start is unavailable.** Reasons:", ""]
        for reason in safety["startBlockers"] or ["unknown"]:
            lines.append("- %s" % reason)
        if safety["unsatisfiedInterlocks"]:
            lines += ["", "Unsatisfied interlocks:", ""]
            for item in safety["unsatisfiedInterlocks"]:
                lines.append("- %s" % item)
        lines += [
            "",
            "The quantity rule (25 mm + 50 mm must be greater than zero) is "
            "enforced in the backend, not just in the UI, so it cannot be "
            "bypassed by a stale browser tab.",
        ]
        return "\n".join(lines)

    def _recording(self, c) -> str:
        r = c["recording"]
        if not r["databaseReady"]:
            return (
                "**The database is not available**, so recording is disabled. "
                "Check `db.enabled` and `db.path` in `config/config.json`."
            )
        if r["active"]:
            return (
                "**Recording is active.**\n\n"
                "- Session: %s\n- Samples stored: %s\n- Duration: %.0f s\n\n"
                "Press **Stop Recording** on the Data page to end it. Samples "
                "are interval-limited and deadbanded, so a steady signal writes "
                "nothing." % (
                    r["sessionLabel"], r["sampleCount"], r["durationSeconds"] or 0,
                )
            )
        return (
            "**Recording is not active.**\n\n"
            "Press **Start Recording** on the Data page. While it runs, tag "
            "values are sampled to the database at the configured interval with "
            "a deadband.\n\n"
            "Outside a recording session the system stores only events, alarms, "
            "state transitions, commands and cycle summaries — never a row per "
            "poll. That is deliberate: at 250 ms and 158 tags, storing "
            "everything would be about 54 million rows a day."
        )

    def _snapshot(self, c) -> str:
        r = c["recording"]
        return (
            "**Save Current Data Snapshot** stores the complete machine state at "
            "the moment you press it: mode, lifecycle, every sensor and valve, "
            "the sequence position, alarms and source status — one database row.\n\n"
            "Use it when you see something worth keeping and do not want a full "
            "recording.\n\n"
            "- Snapshots taken this session: %s\n"
            "- Button: **Save Snapshot** on the Data page\n\n"
            "Snapshots are never deleted by the retention sweep, because you "
            "asked for them explicitly." % r["snapshotCount"]
        )

    def _sequence(self, c) -> str:
        q = c["sequence"]
        lines = [
            "**Sequence position (inferred)**",
            "",
            "- Step %s: %s" % (q["stepIndex"], q["stepName"] or "--"),
            "- Guard: %s (%s)" % (q["guard"] or "--", q["guardKind"] or "--"),
            "- In this step for %.1f s" % (q["elapsedSeconds"] or 0),
        ]
        if q["awaitingOperator"]:
            lines += [
                "",
                "⏸ **Waiting for the operator.** This is a normal manual step, "
                "not a fault. Press **Engraving complete** on the Overview page "
                "when the engraving is finished.",
            ]
        elif q["stalled"]:
            lines += [
                "",
                "⚠ **The sequence is stalled**, waiting for: %s" % q["waitingFor"],
                "",
                "Check whether that signal is physically being made. The "
                "Diagnostics page shows its live state and last transition.",
            ]
        elif q["waitingFor"]:
            lines.append("- Waiting for: %s" % q["waitingFor"])
        lines += [
            "",
            "Note: the PLC publishes no step index — no such tag exists in the "
            "tag list. The step is inferred from ordered sensor transitions, so "
            "it is an inference, not a reading.",
        ]
        return "\n".join(lines)

    def _twin(self, c) -> str:
        t = c["twin"]
        sim = [s for s in c["sources"] if s["kind"] == "SIMULATION"]
        lines = ["**Digital twin / simulation**", ""]
        if sim:
            for s in sim:
                lines.append("- %s: %s (quality %s)" % (s["name"], s["state"], s["quality"]))
                if s["lastError"]:
                    lines.append("  %s" % s["lastError"])
        lines += [
            "",
            "- Reference trajectory: %s" % (
                "loaded" if t["available"] else "not loaded — %s" % (t["error"] or "")
            ),
        ]
        if t["mismatchCount"]:
            lines += [
                "- **%d mismatch(es)** between the machine and the model: %s"
                % (t["mismatchCount"], ", ".join(t["mismatches"])),
            ]
        lines += [
            "",
            "The MATLAB model is a batch simulator, so the twin comparison "
            "replays an exported nominal trajectory against the live cycle "
            "clock. A divergence means the two disagree — not that the machine "
            "is wrong. Most model parameters are still unmeasured.",
        ]
        return "\n".join(lines)

    def _camera(self, c) -> str:
        cam = c["camera"]
        return (
            "**Camera: %s**\n\n"
            "- Objects detected: %s\n- Frame age: %s\n\n"
            "The detector runs in its own process and publishes JSON. If it "
            "shows OFFLINE or STALE, start it with "
            "`python tools/camera_bridge.py`. Magazine counts are withheld "
            "rather than shown stale when the feed is old." % (
                cam["status"], cam["totalObjects"],
                "%.1f s" % cam["frameAgeSeconds"]
                if cam["frameAgeSeconds"] is not None else "no frame",
            )
        )

    def _safety(self, c) -> str:
        s = c["safety"]
        lines = ["**Safety status**", ""]
        if s["emergencyActive"]:
            lines += [
                "🛑 **EMERGENCY ACTIVE** — the hardware safety circuit reports "
                "unhealthy. All process commands are blocked.",
                "",
                "To recover: clear the physical E-Stop, then work through the "
                "restart checklist on the Overview page. The machine state at "
                "the moment of the stop has been preserved.",
                "",
            ]
        for label, key in [
            ("Hardware E-Stop healthy", "hardwareEStopHealthy"),
            ("Air pressure healthy", "airPressureHealthy"),
            ("All cylinders home", "allCylindersHome"),
            ("Engraving plate home", "engravingPlateHome"),
            ("Startup healthy", "startupHealthy"),
        ]:
            v = s[key]
            lines.append("- %s: %s" % (
                label, "✓" if v is True else "✗" if v is False else "unknown",
            ))
        lines += [
            "- Pressure: %s bar" % s["pressureBar"],
            "",
            "**Important:** the red button in the top bar is a *software stop*. "
            "It clears the start command. It does not remove power, vent air or "
            "open the safety circuit. Only the hardware E-Stop does that.",
        ]
        return "\n".join(lines)

    def _manual(self, c) -> str:
        caps = c["capabilities"]
        lines = ["**Manual control**", ""]
        if caps["canCommandValves"]:
            lines += [
                "You can command valves and conveyors now, on the **Manual** page.",
                "",
                "Each command shows the command bit and the output coil "
                "separately, and is only marked confirmed once an independent "
                "PLC read sees the value.",
            ]
        else:
            lines += [caps["valvesBlockedBecause"], ""]
        if not caps["canWriteSetpoints"]:
            lines.append(caps["setpointsBlockedBecause"])
        lines += [
            "",
            "I can explain the controls, but I cannot operate the machine. "
            "Commands only come from the UI, through the safety and "
            "authorisation checks.",
        ]
        return "\n".join(lines)

    def _history(self, c) -> str:
        return (
            "**Historical data**\n\n"
            "The **History** page queries the SQL database: events, alarms, "
            "state transitions, cycle summaries, commands, snapshots and "
            "recording sessions.\n\n"
            "What gets stored automatically:\n"
            "- every event and alarm\n"
            "- lifecycle, mode and source transitions\n"
            "- every command with its PLC read-back outcome\n"
            "- one summary row plus aggregates per cycle\n"
            "- transitions of watched tags (rate-limited)\n\n"
            "What does *not* get stored automatically: per-poll tag values. "
            "Those need an explicit recording session."
        )

    def _help(self, c) -> str:
        return (
            "I can explain what the system is doing and why. Try asking:\n\n"
            "- *What mode is the system in?*\n"
            "- *Why can't I start a cycle?*\n"
            "- *Is the PLC connected?*\n"
            "- *What alarms are active?*\n"
            "- *Why is the sequence stuck?*\n"
            "- *How do I start recording?*\n"
            "- *How do I save a snapshot?*\n"
            "- *What data source is active?*\n"
            "- *What's the digital twin status?*\n"
            "- *Why can't I command a valve?*\n\n"
            "I answer from live system state. I can't operate the machine — "
            "commands go through the UI and the safety checks, never through me."
        )

    def _fallback(self, c) -> str:
        mode = c["mode"]
        return (
            "I'm not sure how to answer that one.\n\n"
            "Right now: **%s**, machine is **%s**, data quality **%s**.\n\n"
            "%s" % (
                mode["systemMode"],
                c["machine"]["lifecycle"],
                mode["dataQuality"],
                self._help(c),
            )
        )


# ---------------------------------------------------------------------------
# LLM providers
# ---------------------------------------------------------------------------

SYSTEM_PROMPT = """You are the built-in help assistant for an industrial SCADA \
platform controlling a Siemens S7-1200 laboratory cell.

You have READ-ONLY access to a redacted system-state summary, supplied below as \
JSON. Answer operator questions about how to use the system and what it is \
currently doing.

Rules you must follow:
1. You cannot operate the machine. You have no command capability. If asked to \
start, stop, or move anything, explain which UI control does it instead.
2. Never invent PLC addresses, tag names or values. If the context does not \
contain something, say you do not have it.
3. Never suggest bypassing a safety interlock, a mode restriction, or the \
restart checklist.
4. The red "software stop" control is not a functional-safety stop. Never \
describe it as an emergency stop.
5. Be concise and concrete. Operators are standing at a machine.
6. If the context shows stale data, say so."""


class OpenAICompatibleProvider(ChatProvider):
    """
    Any OpenAI-compatible chat-completions endpoint.

    Covers OpenAI, Azure OpenAI, vLLM, LM Studio, Ollama's compat shim and
    others -- one implementation rather than one class per vendor. Uses
    urllib so no HTTP dependency is added.
    """

    name = "openai"
    requires_network = True

    def __init__(self, config: dict) -> None:
        self.base_url = config.get("base_url", "https://api.openai.com/v1")
        self.model = config.get("model", "gpt-4o-mini")
        self.api_key_env = config.get("api_key_env", "SCADA_CHAT_API_KEY")
        self.timeout = float(config.get("timeout", 20.0))
        self.max_tokens = int(config.get("max_tokens", 700))

    def available(self) -> tuple:
        if not os.environ.get(self.api_key_env):
            return False, (
                "Environment variable %s is not set." % self.api_key_env
            )
        return True, ""

    def generate(self, message: str, context: Dict[str, Any], history: List[dict]) -> Dict[str, Any]:
        import urllib.error
        import urllib.request

        api_key = os.environ.get(self.api_key_env, "")
        if not api_key:
            raise RuntimeError("%s is not set" % self.api_key_env)

        messages = [
            {"role": "system", "content": SYSTEM_PROMPT},
            {
                "role": "system",
                "content": "Current system state (JSON):\n"
                + json.dumps(context, default=str)[:12000],
            },
        ]
        for turn in history[-8:]:
            role = "assistant" if turn.get("role") == "assistant" else "user"
            messages.append({"role": role, "content": str(turn.get("text", ""))[:2000]})
        messages.append({"role": "user", "content": message})

        payload = json.dumps({
            "model": self.model,
            "messages": messages,
            "max_tokens": self.max_tokens,
            "temperature": 0.2,
        }).encode()

        req = urllib.request.Request(
            self.base_url.rstrip("/") + "/chat/completions",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "Authorization": "Bearer %s" % api_key,
            },
        )
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            body = json.loads(resp.read().decode())

        text = body["choices"][0]["message"]["content"]
        return {
            "text": text,
            "provider": self.name,
            "model": self.model,
            "grounded": False,
        }


class AnthropicProvider(ChatProvider):
    """Anthropic Messages API."""

    name = "anthropic"
    requires_network = True

    def __init__(self, config: dict) -> None:
        self.base_url = config.get("base_url", "https://api.anthropic.com/v1")
        self.model = config.get("model", "claude-sonnet-5")
        self.api_key_env = config.get("api_key_env", "ANTHROPIC_API_KEY")
        self.timeout = float(config.get("timeout", 20.0))
        self.max_tokens = int(config.get("max_tokens", 700))
        self.version = config.get("api_version", "2023-06-01")

    def available(self) -> tuple:
        if not os.environ.get(self.api_key_env):
            return False, "Environment variable %s is not set." % self.api_key_env
        return True, ""

    def generate(self, message: str, context: Dict[str, Any], history: List[dict]) -> Dict[str, Any]:
        import urllib.request

        api_key = os.environ.get(self.api_key_env, "")
        if not api_key:
            raise RuntimeError("%s is not set" % self.api_key_env)

        messages = []
        for turn in history[-8:]:
            role = "assistant" if turn.get("role") == "assistant" else "user"
            messages.append({"role": role, "content": str(turn.get("text", ""))[:2000]})
        messages.append({"role": "user", "content": message})

        payload = json.dumps({
            "model": self.model,
            "max_tokens": self.max_tokens,
            "temperature": 0.2,
            "system": SYSTEM_PROMPT
            + "\n\nCurrent system state (JSON):\n"
            + json.dumps(context, default=str)[:12000],
            "messages": messages,
        }).encode()

        req = urllib.request.Request(
            self.base_url.rstrip("/") + "/messages",
            data=payload,
            headers={
                "Content-Type": "application/json",
                "x-api-key": api_key,
                "anthropic-version": self.version,
            },
        )
        with urllib.request.urlopen(req, timeout=self.timeout) as resp:
            body = json.loads(resp.read().decode())

        text = "".join(
            block.get("text", "") for block in body.get("content", [])
            if block.get("type") == "text"
        )
        return {
            "text": text,
            "provider": self.name,
            "model": self.model,
            "grounded": False,
        }


PROVIDERS = {
    "builtin": BuiltinProvider,
    "openai": OpenAICompatibleProvider,
    "anthropic": AnthropicProvider,
}


def build_provider(config: dict) -> ChatProvider:
    name = (config or {}).get("provider", "builtin")
    cls = PROVIDERS.get(name)
    if cls is None:
        log.warning("unknown chat provider %r; using builtin", name)
        return BuiltinProvider()
    if cls is BuiltinProvider:
        return cls()
    return cls((config or {}).get(name, {}) or {})
