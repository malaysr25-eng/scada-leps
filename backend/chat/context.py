"""
The chatbot's view of the system — read-only, by construction.

THE SECURITY BOUNDARY
---------------------
This module is the *only* way the chat subsystem sees machine state, and it
returns plain dictionaries built from an already-composed snapshot. It holds no
reference to `PlcService`, `SourceManager`, `CommandGate` or the registry's
write path. There is no method here that could write, and none can be added
without deliberately importing something this module does not import.

That is the enforcement. Not "the prompt says don't", which a language model can
be argued out of — the capability is simply absent.

WHAT THE ASSISTANT MAY SEE
--------------------------
Operational state an operator standing at the machine could read off the screen:
mode, lifecycle, connection health, alarms, sequence position, recording status.

WHAT IT MAY NOT SEE
-------------------
* Raw tag values in bulk. A summary is provided instead. Dumping 158 addresses
  into a prompt invites the model to start reasoning about specific addresses,
  which is the first step toward suggesting writes to them.
* Anything that would let it construct a valid write request.
* File paths, config internals, credentials.

If chatbot-initiated *actions* are ever added, they must go through
`/api/cycle/*` and `CommandGate` exactly as the UI does. The correct shape is a
proposal the operator confirms in the normal UI, never a direct call.
"""

from __future__ import annotations

import time
from typing import Any, Dict, List, Optional


class ChatContext:
    """Builds a redacted, read-only description of current system state."""

    def __init__(self, core) -> None:
        # Deliberately NOT stored: core.plc, core.gate, core.sources.
        # This object reads composed snapshots and nothing else.
        self._core = core

    # ------------------------------------------------------------------

    def build(self) -> Dict[str, Any]:
        snapshot = self._core.snapshot()
        return {
            "generatedAt": time.time(),
            "mode": self._mode(snapshot),
            "machine": self._machine(snapshot),
            "safety": self._safety(snapshot),
            "connection": self._connection(snapshot),
            "sources": self._sources(snapshot),
            "sequence": self._sequence(snapshot),
            "alarms": self._alarms(snapshot),
            "recording": self._recording(snapshot),
            "inventory": self._inventory(snapshot),
            "twin": self._twin(snapshot),
            "camera": self._camera(snapshot),
            "capabilities": self._capabilities(snapshot),
            "tagSummary": self._tag_summary(snapshot),
        }

    # ------------------------------------------------------------------

    @staticmethod
    def _mode(s: dict) -> dict:
        sources = s.get("dataSources") or {}
        machine = s.get("machine") or {}
        return {
            "systemMode": sources.get("mode", "DISCONNECTED"),
            "controlMode": machine.get("mode"),
            "controlSource": sources.get("controlSourceName"),
            "telemetrySource": sources.get("telemetrySourceName"),
            "dataQuality": sources.get("quality"),
            "stale": sources.get("stale"),
        }

    @staticmethod
    def _machine(s: dict) -> dict:
        m = s.get("machine") or {}
        return {
            "lifecycle": m.get("lifecycle"),
            "previousLifecycle": m.get("previousLifecycle"),
            "inStateForSeconds": m.get("lifecycleElapsed"),
            "cycleId": m.get("cycleId"),
            "cycleElapsed": m.get("cycleElapsed"),
            "cycleCount": m.get("cycleCount"),
            "hasFrozenContext": bool(m.get("frozenContext")),
        }

    @staticmethod
    def _safety(s: dict) -> dict:
        sa = s.get("safety") or {}
        checklist = s.get("restartChecklist") or []
        can_start = s.get("canStart") or {}
        return {
            "emergencyActive": sa.get("emergencyActive"),
            "hardwareEStopHealthy": sa.get("hardwareEmergencyHealthy"),
            "airPressureHealthy": sa.get("airPressureHealthy"),
            "allCylindersHome": sa.get("allCylindersHome"),
            "engravingPlateHome": sa.get("engravingPlateHome"),
            "startupHealthy": sa.get("startupHealthy"),
            "pressureBar": sa.get("pressureBar"),
            "canStartCycle": can_start.get("allowed"),
            "startBlockers": can_start.get("reasons", []),
            "unsatisfiedInterlocks": [
                i.get("label") for i in checklist
                if i.get("required") and i.get("satisfied") is not True
            ],
        }

    @staticmethod
    def _connection(s: dict) -> dict:
        c = s.get("connection") or {}
        health = c.get("plcHealth") or {}
        return {
            "plc": c.get("plc"),
            "plcSimulated": c.get("plcSimulated"),
            "staleSeconds": c.get("staleSeconds"),
            "stale": c.get("stale"),
            "camera": c.get("camera"),
            "digitalTwin": c.get("digitalTwin"),
            "latencyMs": health.get("latencyAvgMs"),
            "errorCount": health.get("errorCount"),
            "reconnectCount": health.get("reconnectCount"),
            "lastError": health.get("lastError"),
        }

    @staticmethod
    def _sources(s: dict) -> List[dict]:
        sources = (s.get("dataSources") or {}).get("sources") or []
        return [
            {
                "name": src.get("name"),
                "kind": src.get("kind"),
                "state": src.get("state"),
                "quality": src.get("quality"),
                "supportsControl": src.get("supportsControl"),
                "controlActive": src.get("controlActive"),
                "lastError": src.get("lastError"),
                "ageSeconds": src.get("ageSeconds"),
            }
            for src in sources
        ]

    @staticmethod
    def _sequence(s: dict) -> dict:
        q = s.get("sequence") or {}
        step = q.get("step") or {}
        return {
            "stepIndex": q.get("stepIndex"),
            "stepName": step.get("name"),
            "guard": step.get("guardLabel"),
            "guardKind": step.get("guardKind"),
            "waitingFor": q.get("waitingFor"),
            "stalled": q.get("stalled"),
            "awaitingOperator": q.get("awaitingOperator"),
            "elapsedSeconds": q.get("elapsedSeconds"),
            "lastConfirmedStep": q.get("lastConfirmedStep"),
            "confidence": q.get("confidence"),
            "inferred": True,
        }

    @staticmethod
    def _alarms(s: dict) -> dict:
        d = s.get("diagnostics") or {}
        return {
            "activeFaults": [
                {
                    "key": f.get("key"),
                    "message": f.get("message"),
                    "severity": f.get("severity"),
                    "acknowledged": f.get("acknowledged"),
                    "raisedAt": f.get("raisedAt"),
                }
                for f in (d.get("activeFaults") or [])
            ],
            "findings": [
                {
                    "title": f.get("title"),
                    "detail": f.get("detail"),
                    "severity": f.get("severity"),
                    "issueRef": f.get("issueRef"),
                }
                for f in (d.get("findings") or [])
            ],
        }

    @staticmethod
    def _recording(s: dict) -> dict:
        r = s.get("recording") or {}
        session = r.get("session") or {}
        return {
            "active": r.get("recording", False),
            "sessionLabel": session.get("label"),
            "sampleCount": session.get("sampleCount"),
            "durationSeconds": session.get("durationSeconds"),
            "databaseReady": (s.get("database") or {}).get("ready"),
            "snapshotCount": r.get("snapshotCount"),
        }

    @staticmethod
    def _inventory(s: dict) -> dict:
        inv = s.get("inventory") or {}
        order = inv.get("order") or {}
        progress = inv.get("progress") or {}
        return {
            "qty25": order.get("qty25"),
            "qty50": order.get("qty50"),
            "totalOrdered": order.get("total"),
            "completed": progress.get("plcTotalProducts"),
            "magazineMismatches": [
                m.get("mismatch") for m in (inv.get("magazines") or [])
                if m.get("mismatch")
            ],
        }

    @staticmethod
    def _twin(s: dict) -> dict:
        t = s.get("digitalTwin") or {}
        return {
            "available": t.get("available"),
            "status": t.get("status"),
            "error": t.get("error"),
            "mismatchCount": len(t.get("mismatches") or []),
            "mismatches": [m.get("subject") for m in (t.get("mismatches") or [])],
        }

    @staticmethod
    def _camera(s: dict) -> dict:
        c = s.get("camera") or {}
        return {
            "status": c.get("status"),
            "totalObjects": c.get("totalObjects"),
            "frameAgeSeconds": c.get("frameAgeSeconds"),
        }

    @staticmethod
    def _capabilities(s: dict) -> dict:
        """What the operator can do *right now*, so the assistant can explain
        why a button is unavailable rather than guessing."""
        machine = s.get("machine") or {}
        mode = machine.get("mode")
        can_start = s.get("canStart") or {}
        sources = s.get("dataSources") or {}

        return {
            "canStartCycle": can_start.get("allowed", False),
            "startBlockedBecause": can_start.get("reasons", []),
            "canCommandValves": mode in ("MANUAL", "MAINTENANCE"),
            "valvesBlockedBecause": (
                "" if mode in ("MANUAL", "MAINTENANCE")
                else "The machine is in %s mode; the automatic sequencer owns "
                     "the outputs. Switch to MANUAL in the top bar." % mode
            ),
            "canWriteSetpoints": mode == "MAINTENANCE",
            "setpointsBlockedBecause": (
                "" if mode == "MAINTENANCE"
                else "Engineering setpoints require MAINTENANCE mode."
            ),
            "canControlHardware": sources.get("canControlHardware", False),
            "availableModes": ["AUTO", "MANUAL", "MAINTENANCE"],
            "sourceTransitions": sources.get("transitions", []),
        }

    @staticmethod
    def _tag_summary(s: dict) -> dict:
        """
        Counts, never the tag table.

        Bulk tag values are withheld on purpose: an assistant that has 158
        addresses in front of it will start reasoning about individual
        addresses, and the next step is suggesting writes to them.
        """
        sensors = s.get("sensors") or []
        actuators = s.get("actuators") or []
        conveyors = s.get("conveyors") or []
        return {
            "sensorCount": len(sensors),
            "sensorsActive": sum(1 for x in sensors if x.get("value") is True),
            "sensorsUnknown": sum(1 for x in sensors if x.get("value") is None),
            "valveCount": len(actuators),
            "valvesEnergised": sum(1 for a in actuators if a.get("state") is True),
            "conveyorCount": len(conveyors),
            "conveyorsRunning": sum(1 for c in conveyors if c.get("running") is True),
            "note": "Individual tag values are available in the Tag Explorer, "
                    "not through the assistant.",
        }
