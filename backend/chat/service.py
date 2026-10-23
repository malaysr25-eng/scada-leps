"""
ChatService — the help assistant, with its safety boundary made structural.

WHAT THIS SERVICE CAN AND CANNOT REACH
--------------------------------------
It holds exactly two references: a `ChatContext` (read-only, redacted) and a
`ChatProvider` (text in, text out). It has no reference to `PlcService`,
`SourceManager`, `CommandGate` or the tag registry's write path.

So the assistant cannot command the machine for the same reason a calculator
cannot: the capability is not present. That matters more than a prompt
instruction, which a model can be talked out of.

If chatbot-initiated actions are ever wanted, the correct shape is a
*suggestion* the operator confirms in the normal UI — never a call from here
into a command path. `suggest_action()` below returns exactly that: a
description of which control to press, and nothing that executes.

PROVIDER FALLBACK
-----------------
If a configured LLM provider is unreachable or errors, the service answers with
the built-in provider rather than failing. An operator asking "why is Start
greyed out?" during a fault must get an answer whether or not an API is up.
"""

from __future__ import annotations

import itertools
import logging
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from backend.chat.context import ChatContext
from backend.chat.providers import BuiltinProvider, ChatProvider, build_provider

log = logging.getLogger("chat")

MAX_MESSAGE_CHARS = 2000
MAX_HISTORY = 40


@dataclass
class ChatMessage:
    id: int
    role: str            # "user" | "assistant" | "system"
    text: str
    at: float
    provider: str = ""
    grounded: bool = True
    error: str = ""
    context_summary: Dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "role": self.role,
            "text": self.text,
            "at": self.at,
            "provider": self.provider,
            "grounded": self.grounded,
            "error": self.error,
            "contextSummary": self.context_summary,
        }


class ChatService:
    def __init__(self, core, config: Optional[dict] = None) -> None:
        cfg = config or {}
        self.enabled = bool(cfg.get("enabled", True))
        self.config = cfg

        # The only two things this service can touch.
        self.context = ChatContext(core)
        self.provider: ChatProvider = build_provider(cfg)
        self.fallback = BuiltinProvider()

        self._lock = threading.RLock()
        self._history: List[ChatMessage] = []
        self._ids = itertools.count(1)
        self._sessions: Dict[str, List[ChatMessage]] = {}
        self._provider_errors = 0
        self._last_provider_error = ""

    # ------------------------------------------------------------------

    def ask(self, message: str, session_id: str = "default") -> dict:
        if not self.enabled:
            return {
                "ok": False,
                "error": "The help assistant is disabled in config (chat.enabled).",
            }

        text = (message or "").strip()
        if not text:
            return {"ok": False, "error": "Empty message."}
        if len(text) > MAX_MESSAGE_CHARS:
            text = text[:MAX_MESSAGE_CHARS]

        with self._lock:
            history = self._sessions.setdefault(session_id, [])
            user_msg = ChatMessage(
                id=next(self._ids), role="user", text=text, at=time.time(),
            )
            history.append(user_msg)

        # Built fresh per question: the operator is asking about *now*.
        context = self.context.build()
        prior = [m.to_dict() for m in history[-8:] if m.role in ("user", "assistant")]

        reply_text = ""
        provider_name = self.provider.name
        grounded = True
        error = ""

        try:
            available, reason = self.provider.available()
            if not available:
                raise RuntimeError(reason)
            result = self.provider.generate(text, context, prior)
            reply_text = result.get("text", "")
            provider_name = result.get("provider", provider_name)
            grounded = result.get("grounded", False)
            if not reply_text.strip():
                raise RuntimeError("provider returned an empty response")

        except Exception as exc:
            # Falling back is the right behaviour: an unreachable API must not
            # leave an operator without an answer.
            self._provider_errors += 1
            self._last_provider_error = str(exc)
            log.warning("chat provider %s failed: %s", self.provider.name, exc)
            result = self.fallback.generate(text, context, prior)
            reply_text = result["text"]
            provider_name = "builtin (fallback)"
            grounded = True
            error = "Provider '%s' unavailable: %s" % (self.provider.name, exc)

        with self._lock:
            reply = ChatMessage(
                id=next(self._ids),
                role="assistant",
                text=reply_text,
                at=time.time(),
                provider=provider_name,
                grounded=grounded,
                error=error,
                context_summary=self._summarise(context),
            )
            history.append(reply)
            if len(history) > MAX_HISTORY:
                del history[: len(history) - MAX_HISTORY]

        return {
            "ok": True,
            "message": reply.to_dict(),
            "userMessage": user_msg.to_dict(),
        }

    # ------------------------------------------------------------------

    @staticmethod
    def _summarise(context: dict) -> dict:
        """
        The context chips shown under an assistant reply.

        Displaying what the answer was grounded in lets an operator judge
        whether it is current, instead of trusting an unattributed claim.
        """
        mode = context.get("mode", {})
        machine = context.get("machine", {})
        alarms = context.get("alarms", {})
        return {
            "systemMode": mode.get("systemMode"),
            "lifecycle": machine.get("lifecycle"),
            "quality": mode.get("dataQuality"),
            "stale": mode.get("stale"),
            "activeFaults": len(alarms.get("activeFaults") or []),
            "at": context.get("generatedAt"),
        }

    def history(self, session_id: str = "default", limit: int = 50) -> List[dict]:
        with self._lock:
            return [m.to_dict() for m in self._sessions.get(session_id, [])[-limit:]]

    def clear(self, session_id: str = "default") -> None:
        with self._lock:
            self._sessions[session_id] = []

    # ------------------------------------------------------------------

    def suggest_action(self, intent: str) -> dict:
        """
        Map an intent to the UI control that performs it. Executes nothing.

        This is the sanctioned shape for any future "the assistant can help me
        do X": it names the control, and the operator presses it through the
        normal validated path.
        """
        catalogue = {
            "start_cycle": {
                "label": "Start cycle",
                "where": "Overview → Automatic cycle",
                "note": "Set a quantity first; the backend refuses a zero-quantity start.",
            },
            "stop": {
                "label": "Software stop",
                "where": "Top bar",
                "note": "Clears CMD_START. This is not a functional-safety stop.",
            },
            "reset": {
                "label": "Reset cycle",
                "where": "Top bar, or Overview → Restart checklist",
                "note": "Blocked until the restart checklist passes.",
            },
            "manual_mode": {
                "label": "Manual",
                "where": "Top bar → mode selector",
                "note": "Refused while an automatic cycle is running.",
            },
            "record": {
                "label": "Start Recording",
                "where": "Data page",
                "note": "Samples are interval-limited and deadbanded.",
            },
            "snapshot": {
                "label": "Save Snapshot",
                "where": "Data page",
                "note": "Stores the complete current state as one row.",
            },
        }
        action = catalogue.get(intent)
        if not action:
            return {"ok": False, "error": "No such action %r." % intent}
        return {
            "ok": True,
            "action": action,
            "executed": False,
            "note": (
                "The assistant does not operate the machine. Use the control "
                "named above; it goes through the normal safety checks."
            ),
        }

    # ------------------------------------------------------------------

    def status(self) -> dict:
        available, reason = self.provider.available()
        return {
            "enabled": self.enabled,
            "provider": self.provider.name,
            "providerAvailable": available,
            "providerReason": reason,
            "requiresNetwork": self.provider.requires_network,
            "fallbackProvider": self.fallback.name,
            "providerErrors": self._provider_errors,
            "lastProviderError": self._last_provider_error,
            "capabilities": {
                "readOnly": True,
                "canIssueCommands": False,
                "canBypassSafety": False,
                "note": (
                    "The assistant reads a redacted snapshot and returns text. "
                    "It holds no reference to the PLC service, the command gate "
                    "or the source manager, so it has no command capability to "
                    "misuse."
                ),
            },
        }
