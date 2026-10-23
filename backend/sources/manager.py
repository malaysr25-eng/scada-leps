"""
SourceManager — one active control source, enforced rather than assumed.

THE PROPERTY THIS FILE GUARANTEES
---------------------------------
At most one adapter is the **control source** at any moment. Every write in the
application funnels through `SourceManager.write()`, which:

  1. refuses if the target adapter is not the control source;
  2. refuses if the adapter does not declare `supports_control`;
  3. only then hands the command to the adapter.

The simulation adapter sets `supports_control = False`, so a MATLAB value can
never reach the PLC. That is not a convention anyone has to remember — the
manager refuses to make such a source the control source at all, and the
adapter refuses the write independently.

TELEMETRY VS CONTROL, KEPT SEPARATE
-----------------------------------
These are different questions and are tracked separately:

* **Control source** — who may write to hardware. Exactly one, and it must be
  control-capable.
* **Telemetry source** — which source feeds the dashboards. Any healthy source.

Keeping them separate is what lets an engineer watch simulation telemetry while
the PLC remains the thing under control, without either display or command path
becoming ambiguous. The alternative — one "mode" flag — is how simulation values
end up silently labelled as plant data.

MODES
-----
The manager derives a system mode from the sources rather than storing one, so
the mode can never disagree with reality:

    PLC_CONNECTED       a healthy control-capable PLC source is active
    PLC_CONNECTING      the PLC source is coming up
    SIMULATION_RUNNING  telemetry is a running simulation
    SIMULATION_STOPPED  simulation selected but not producing
    DISCONNECTED        no source is producing usable data
    ERROR               the active source reports an error
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Any, Dict, List, Optional

from backend.sources.base import (
    HEALTHY_STATES,
    KIND_PLC,
    KIND_SIMULATION,
    QUALITY_BAD,
    SRC_CONNECTED,
    SRC_CONNECTING,
    SRC_ERROR,
    SRC_STOPPED,
    DataSourceAdapter,
    Sample,
)

log = logging.getLogger("sources")

MODE_PLC_CONNECTED = "PLC_CONNECTED"
MODE_PLC_CONNECTING = "PLC_CONNECTING"
MODE_SIMULATION_RUNNING = "SIMULATION_RUNNING"
MODE_SIMULATION_STOPPED = "SIMULATION_STOPPED"
MODE_DISCONNECTED = "DISCONNECTED"
MODE_ERROR = "ERROR"


class SourceManager:
    def __init__(self, event_log) -> None:
        self.events = event_log
        self._lock = threading.RLock()
        self._adapters: Dict[str, DataSourceAdapter] = {}
        self._order: List[str] = []
        self._control_source_id: Optional[str] = None
        self._telemetry_source_id: Optional[str] = None
        self._last_mode = MODE_DISCONNECTED
        self._switch_count = 0

    # ------------------------------------------------------------------
    # registration
    # ------------------------------------------------------------------

    def register(self, adapter: DataSourceAdapter) -> None:
        with self._lock:
            if adapter.source_id in self._adapters:
                raise ValueError("duplicate source id %r" % adapter.source_id)
            self._adapters[adapter.source_id] = adapter
            self._order.append(adapter.source_id)
        log.info(
            "registered source %s (%s, control=%s)",
            adapter.source_id, adapter.kind, adapter.supports_control,
        )

    def get(self, source_id: str) -> Optional[DataSourceAdapter]:
        return self._adapters.get(source_id)

    def adapters(self) -> List[DataSourceAdapter]:
        return [self._adapters[sid] for sid in self._order]

    # ------------------------------------------------------------------
    # selection
    # ------------------------------------------------------------------

    @property
    def control_source(self) -> Optional[DataSourceAdapter]:
        return self._adapters.get(self._control_source_id or "")

    @property
    def telemetry_source(self) -> Optional[DataSourceAdapter]:
        return self._adapters.get(
            self._telemetry_source_id or self._control_source_id or ""
        )

    def set_control_source(self, source_id: Optional[str], operator: str = "system") -> tuple:
        """
        Hand control to one source, or to none.

        Returns (ok, reason). Refusals are normal outcomes, not exceptions:
        the UI renders them.
        """
        with self._lock:
            if source_id is None:
                previous = self._control_source_id
                self._deactivate_all()
                self._control_source_id = None
                if previous:
                    self.events.command(
                        "source",
                        "Control released from %s. No source now has control." % previous,
                        source=operator,
                    )
                return True, ""

            adapter = self._adapters.get(source_id)
            if adapter is None:
                return False, "No such data source %r." % source_id

            if not adapter.supports_control:
                # The load-bearing refusal.
                return False, (
                    "%s is a telemetry-only source and can never take control of "
                    "the machine. This prevents simulated values from reaching "
                    "the PLC." % adapter.name
                )

            status = adapter.get_status()
            if not status.available:
                return False, "%s is unavailable: %s" % (
                    adapter.name, status.unavailable_reason or "not configured",
                )
            if status.state not in HEALTHY_STATES:
                return False, (
                    "%s is %s. Control can only be given to a source that is "
                    "actually connected." % (adapter.name, status.state)
                )

            if self._control_source_id == source_id:
                return True, ""

            previous = self._control_source_id
            self._deactivate_all()
            adapter.set_control_active(True)
            self._control_source_id = source_id
            self._switch_count += 1

            self.events.command(
                "source",
                "Control source changed %s -> %s"
                % (previous or "none", adapter.name),
                source=operator, previous=previous, sourceId=source_id,
            )
            log.info("control source: %s -> %s", previous, source_id)
            return True, ""

    def set_telemetry_source(self, source_id: str, operator: str = "system") -> tuple:
        """
        Choose which source feeds the dashboards. This grants no control.
        """
        with self._lock:
            adapter = self._adapters.get(source_id)
            if adapter is None:
                return False, "No such data source %r." % source_id

            status = adapter.get_status()
            if not status.available:
                return False, "%s is unavailable: %s" % (
                    adapter.name, status.unavailable_reason or "not configured",
                )

            if self._telemetry_source_id == source_id:
                return True, ""

            previous = self._telemetry_source_id
            self._telemetry_source_id = source_id
            self.events.info(
                "source",
                "Telemetry source changed %s -> %s (display only; control is "
                "unaffected)" % (previous or "none", adapter.name),
                source=operator,
            )
            return True, ""

    def _deactivate_all(self) -> None:
        for adapter in self._adapters.values():
            adapter.set_control_active(False)

    # ------------------------------------------------------------------
    # writes -- the single funnel
    # ------------------------------------------------------------------

    def write(self, tag_id: str, value: Any, **kwargs) -> tuple:
        """
        Route a write to the active control source.

        CommandGate has already authorised the *operator*. This decides whether
        the *source* may reach hardware. Both gates must pass.
        """
        with self._lock:
            adapter = self.control_source

        if adapter is None:
            return False, (
                "No active control source. Select a control source before "
                "issuing commands."
            )
        if not adapter.supports_control:
            return False, "%s cannot accept commands." % adapter.name

        return adapter.send_command(tag_id, value, **kwargs)

    # ------------------------------------------------------------------
    # data
    # ------------------------------------------------------------------

    def read_latest(self) -> Dict[str, Sample]:
        """Normalised samples from the telemetry source."""
        adapter = self.telemetry_source
        return {} if adapter is None else adapter.read_latest()

    def read_all_sources(self) -> Dict[str, Dict[str, Sample]]:
        """Every source's samples, for comparison views."""
        return {sid: a.read_latest() for sid, a in self._adapters.items()}

    # ------------------------------------------------------------------
    # derived mode
    # ------------------------------------------------------------------

    def mode(self) -> str:
        control = self.control_source
        telemetry = self.telemetry_source

        if control is not None:
            status = control.get_status()
            if status.state == SRC_ERROR:
                return MODE_ERROR
            if status.state == SRC_CONNECTING:
                return MODE_PLC_CONNECTING if control.kind == KIND_PLC else MODE_SIMULATION_STOPPED
            if status.state in HEALTHY_STATES:
                if control.kind == KIND_PLC:
                    return MODE_PLC_CONNECTED
                return MODE_SIMULATION_RUNNING

        if telemetry is not None and telemetry.kind == KIND_SIMULATION:
            status = telemetry.get_status()
            if status.state in HEALTHY_STATES:
                return MODE_SIMULATION_RUNNING
            return MODE_SIMULATION_STOPPED

        return MODE_DISCONNECTED

    def allowed_transitions(self) -> List[dict]:
        """
        Which control sources could be selected right now, and why not.

        Returned to the frontend so a disabled option can explain itself
        instead of being mysteriously greyed out.
        """
        out = []
        for adapter in self.adapters():
            status = adapter.get_status()
            allowed = True
            reason = ""

            if not adapter.supports_control:
                allowed = False
                reason = "Telemetry-only source. It cannot control the machine."
            elif not status.available:
                allowed = False
                reason = status.unavailable_reason or "Unavailable."
            elif status.state not in HEALTHY_STATES:
                allowed = False
                reason = "Source is %s." % status.state

            out.append({
                "sourceId": adapter.source_id,
                "name": adapter.name,
                "kind": adapter.kind,
                "allowed": allowed,
                "reason": reason,
                "isControl": adapter.source_id == self._control_source_id,
                "isTelemetry": adapter.source_id == (
                    self._telemetry_source_id or self._control_source_id
                ),
            })
        return out

    # ------------------------------------------------------------------
    # reporting
    # ------------------------------------------------------------------

    def describe(self) -> dict:
        control = self.control_source
        telemetry = self.telemetry_source
        mode = self.mode()

        if mode != self._last_mode:
            self.events.info(
                "source", "System mode %s -> %s" % (self._last_mode, mode),
            )
            self._last_mode = mode

        control_status = control.get_status() if control else None
        telemetry_status = telemetry.get_status() if telemetry else None

        return {
            "mode": mode,
            "controlSourceId": self._control_source_id,
            "controlSourceName": control.name if control else None,
            "telemetrySourceId": (
                self._telemetry_source_id or self._control_source_id
            ),
            "telemetrySourceName": telemetry.name if telemetry else None,
            "switchCount": self._switch_count,
            "sources": [a.describe() for a in self.adapters()],
            "transitions": self.allowed_transitions(),
            "lastDataAt": telemetry_status.last_data_at if telemetry_status else None,
            "quality": telemetry_status.quality() if telemetry_status else QUALITY_BAD,
            "stale": telemetry_status.stale if telemetry_status else True,
            "controlQuality": control_status.quality() if control_status else QUALITY_BAD,
            "canControlHardware": bool(
                control is not None
                and control.kind == KIND_PLC
                and control_status is not None
                and control_status.state in HEALTHY_STATES
            ),
            "note": (
                "Exactly one source may hold control. Telemetry-only sources "
                "(simulation) are structurally barred from control, so simulated "
                "values cannot reach the PLC."
            ),
        }

    def start_all(self) -> None:
        for adapter in self.adapters():
            try:
                adapter.start()
            except Exception:
                log.exception("failed to start source %s", adapter.source_id)

    def stop_all(self) -> None:
        for adapter in self.adapters():
            try:
                adapter.stop()
            except Exception:
                log.exception("failed to stop source %s", adapter.source_id)
