"""
PLC adapter — a thin wrapper over the existing PlcService.

DELIBERATELY THIN
-----------------
`PlcService` already does the hard and well-tested work: one Snap7 client, one
poll thread, one large db_read, a write queue, and read-back confirmation. None
of that is reimplemented here.

This adapter exists only to present that service through the common
`DataSourceAdapter` contract so the core can treat PLC and simulation
identically. It opens no connection of its own — doing so would recreate the
exact "four competing Snap7 clients" defect this project was built to remove.

CONTROL GATING
--------------
`send_command` refuses unless this adapter is the active control source. That is
a second, independent barrier: CommandGate has already decided the *operator*
may issue the command, and this decides the *source* is entitled to reach the
hardware. Both must agree. A simulation command can therefore never arrive at
the real PLC even if some future caller forgets to ask the manager first.
"""

from __future__ import annotations

import logging
from typing import Any, Dict

from backend.sources.base import (
    KIND_PLC,
    QUALITY_BAD,
    QUALITY_GOOD,
    QUALITY_STALE,
    QUALITY_UNCERTAIN,
    SRC_CONNECTED,
    SRC_CONNECTING,
    SRC_DEGRADED,
    SRC_DISCONNECTED,
    SRC_RECONNECTING,
    DataSourceAdapter,
    Sample,
    SourceStatus,
    samples_from,
)

log = logging.getLogger("src.plc")

# PlcService connection state -> adapter state. SIMULATED maps to CONNECTED
# because from the core's point of view the offline PLC stand-in behaves like a
# healthy controller; the *simulated* flag is surfaced separately in detail so
# the UI can label it without the core having to special-case it.
_STATE_MAP = {
    "DISCONNECTED": SRC_DISCONNECTED,
    "CONNECTING": SRC_CONNECTING,
    "CONNECTED": SRC_CONNECTED,
    "DEGRADED": SRC_DEGRADED,
    "RECONNECTING": SRC_RECONNECTING,
    "SIMULATED": SRC_CONNECTED,
}


class PlcSourceAdapter(DataSourceAdapter):
    source_id = "plc"
    name = "Siemens S7-1200 (Snap7)"
    kind = KIND_PLC
    supports_control = True

    def __init__(self, plc_service, stale_after: float = 3.0) -> None:
        super().__init__()
        self.plc = plc_service
        self.stale_after = stale_after
        self._sequence = 0
        self._last_poll_count = 0

    # -- lifecycle ------------------------------------------------------

    def connect(self) -> bool:
        """
        PlcService owns its own lifecycle and is started by Core.

        This does not call plc.start(): the poll thread must be started exactly
        once, by the owner, not by whichever adapter happens to be constructed.
        """
        return self.plc.is_live

    def disconnect(self) -> None:
        # Intentionally a no-op. Tearing down the shared PLC connection because
        # one adapter was deselected would break every other consumer, and the
        # PLC link is expected to stay up for monitoring even when control has
        # been handed to the simulator.
        pass

    # -- data -----------------------------------------------------------

    def _quality(self) -> str:
        if not self.plc.is_live:
            return QUALITY_BAD
        health = self.plc.snapshot()["health"]
        if health["lastSuccess"] is None:
            return QUALITY_BAD
        if self.plc.connection == "DEGRADED":
            return QUALITY_UNCERTAIN
        if self.plc.stale_seconds() > self.stale_after:
            return QUALITY_STALE
        return QUALITY_GOOD

    def get_status(self) -> SourceStatus:
        snap = self.plc.snapshot()
        health = snap["health"]

        # The poll counter is the honest liveness signal: a timestamp can look
        # recent while the worker thread is wedged.
        if health["pollCount"] != self._last_poll_count:
            self._last_poll_count = health["pollCount"]
            self._sequence += 1

        return SourceStatus(
            source_id=self.source_id,
            name=self.name,
            kind=self.kind,
            state=_STATE_MAP.get(self.plc.connection, SRC_DISCONNECTED),
            connected=self.plc.is_live,
            running=self.plc.is_live,
            last_data_at=health["lastSuccess"],
            last_error=health["lastError"],
            error_count=health["errorCount"],
            reconnect_count=health["reconnectCount"],
            latency_ms=health["latencyAvgMs"],
            sequence=self._sequence,
            stale_after=self.stale_after,
            can_control=self.is_control_active,
            detail={
                "simulated": snap["simulated"],
                "pollCount": health["pollCount"],
                "consecutiveErrors": health["consecutiveErrors"],
                "inflightCommands": snap["inflight"],
                "ip": self.plc.ip,
                "rack": self.plc.rack,
                "slot": self.plc.slot,
                "pollIntervalMs": round(self.plc.poll_interval * 1000),
            },
        )

    def read_latest(self) -> Dict[str, Sample]:
        status = self.get_status()
        return samples_from(
            self.plc.values(),
            self.source_id,
            self._quality(),
            status.last_data_at or 0.0,
            self._sequence,
        )

    def read_raw(self) -> Dict[str, Any]:
        return self.plc.values()

    # -- control --------------------------------------------------------

    def send_command(self, tag_id: str, value: Any, **kwargs) -> tuple:
        """
        Queue a write. Authorisation has already happened in CommandGate; this
        is the source-level gate only.
        """
        if not self.is_control_active:
            return False, (
                "The PLC is not the active control source. Switch control to "
                "the PLC before commanding hardware."
            )

        tag = self.plc.registry.get(tag_id)
        if tag is None:
            return False, "No tag %r in the registry." % tag_id

        try:
            cmd = self.plc.submit_write(
                tag,
                value,
                source=kwargs.get("source", "manual"),
                operator=kwargs.get("operator", "local"),
            )
        except ValueError as exc:
            return False, str(exc)

        return True, cmd
