"""
The data-source adapter contract.

WHY THIS LAYER EXISTS
---------------------
Before this, the application core read `PlcService` directly. That was fine while
Snap7 was the only source of truth, but it means every consumer has to know
where a value came from. Adding MATLAB under that arrangement would have spread
`if source == "matlab"` branches through the core, the API and eventually React.

An adapter contract fixes that: the core consumes **normalised samples** and
never asks which driver produced them. Adding a future source is a new file
implementing this interface plus a config entry, with no core change.

WHAT NORMALISATION MEANS HERE
-----------------------------
Every sample carries its own provenance, because the alternative -- a bare
number -- is exactly how stale data gets displayed as live:

    value       the datum
    source      which adapter produced it
    timestamp   when the adapter observed it, not when we read the cache
    quality     GOOD / STALE / UNCERTAIN / BAD
    sequence    monotonic counter, so a consumer can detect a stalled feed
                even when the timestamp looks plausible

`quality` is the load-bearing field. A value can be recent and still be
UNCERTAIN (the link is degraded), and it can look reasonable while being BAD
(the tag decode failed). Consumers are expected to branch on quality, not to
assume a number is a number.

SAFETY NOTE
-----------
An adapter may implement `send_command`, but the adapter is **not** where
authorisation lives. Commands reach an adapter only after CommandGate has
approved them and only when SourceManager has confirmed the adapter is the
active control source. An adapter that is not active must refuse writes -- see
`SourceManager.write` and each adapter's `is_control_active` check.
"""

from __future__ import annotations

import time
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

# ---------------------------------------------------------------------------
# quality
# ---------------------------------------------------------------------------

QUALITY_GOOD = "GOOD"            # fresh, from a healthy link
QUALITY_STALE = "STALE"          # last known good, but past the freshness budget
QUALITY_UNCERTAIN = "UNCERTAIN"  # link degraded, value may lag
QUALITY_BAD = "BAD"              # decode failed or no value has ever arrived

# ---------------------------------------------------------------------------
# adapter connection lifecycle -- deliberately source-agnostic
# ---------------------------------------------------------------------------

SRC_DISCONNECTED = "DISCONNECTED"
SRC_CONNECTING = "CONNECTING"
SRC_CONNECTED = "CONNECTED"
SRC_DEGRADED = "DEGRADED"
SRC_RECONNECTING = "RECONNECTING"
SRC_STOPPED = "STOPPED"
SRC_ERROR = "ERROR"

HEALTHY_STATES = (SRC_CONNECTED, SRC_DEGRADED)

# ---------------------------------------------------------------------------
# source kinds
# ---------------------------------------------------------------------------

KIND_PLC = "PLC"
KIND_SIMULATION = "SIMULATION"
KIND_MOCK = "MOCK"


@dataclass
class Sample:
    """One normalised datum, with everything needed to judge whether to trust it."""

    value: Any
    source: str
    timestamp: float
    quality: str = QUALITY_GOOD
    sequence: int = 0
    unit: str = ""

    @property
    def trustworthy(self) -> bool:
        return self.quality == QUALITY_GOOD

    def to_dict(self) -> dict:
        return {
            "value": self.value,
            "source": self.source,
            "timestamp": self.timestamp,
            "quality": self.quality,
            "sequence": self.sequence,
            "unit": self.unit,
        }


@dataclass
class SourceStatus:
    """Everything the UI needs to describe a source without guessing."""

    source_id: str
    name: str
    kind: str
    state: str = SRC_DISCONNECTED
    connected: bool = False
    running: bool = False
    last_data_at: Optional[float] = None
    last_error: str = ""
    error_count: int = 0
    reconnect_count: int = 0
    latency_ms: float = 0.0
    sequence: int = 0
    stale_after: float = 3.0
    detail: Dict[str, Any] = field(default_factory=dict)
    can_control: bool = False
    available: bool = True
    unavailable_reason: str = ""

    @property
    def age_seconds(self) -> Optional[float]:
        if self.last_data_at is None:
            return None
        return time.time() - self.last_data_at

    @property
    def stale(self) -> bool:
        age = self.age_seconds
        return age is None or age > self.stale_after

    def quality(self) -> str:
        """The quality every sample from this source inherits right now."""
        if self.last_data_at is None:
            return QUALITY_BAD
        if self.state == SRC_DEGRADED:
            return QUALITY_UNCERTAIN
        if self.stale:
            return QUALITY_STALE
        if self.state in HEALTHY_STATES:
            return QUALITY_GOOD
        return QUALITY_STALE

    def to_dict(self) -> dict:
        age = self.age_seconds
        return {
            "sourceId": self.source_id,
            "name": self.name,
            "kind": self.kind,
            "state": self.state,
            "connected": self.connected,
            "running": self.running,
            "lastDataAt": self.last_data_at,
            "ageSeconds": None if age is None else round(age, 2),
            "stale": self.stale,
            "staleAfterSeconds": self.stale_after,
            "quality": self.quality(),
            "lastError": self.last_error,
            "errorCount": self.error_count,
            "reconnectCount": self.reconnect_count,
            "latencyMs": round(self.latency_ms, 1),
            "sequence": self.sequence,
            "canControl": self.can_control,
            "available": self.available,
            "unavailableReason": self.unavailable_reason,
            "detail": self.detail,
        }


class DataSourceAdapter(ABC):
    """
    Transport for one source of machine data.

    An adapter owns its connection and its decoding. It owns **no** policy: not
    authorisation, not mode, not interlocks. Those live in CommandGate and
    SourceManager, so that a new adapter cannot accidentally introduce a second,
    weaker safety path.
    """

    source_id: str = "unnamed"
    name: str = "Unnamed source"
    kind: str = KIND_MOCK

    #: Whether this adapter may ever be given control of the machine. A pure
    #: telemetry source (a read-only simulation feed) sets this False, and
    #: SourceManager will then refuse to make it the control source at all.
    supports_control: bool = False

    def __init__(self) -> None:
        self._control_active = False

    # -- lifecycle ------------------------------------------------------

    @abstractmethod
    def connect(self) -> bool:
        """Establish the transport. Return True on success. Must not raise."""

    @abstractmethod
    def disconnect(self) -> None:
        """Tear the transport down. Must be safe to call when already down."""

    def start(self) -> bool:
        """Begin producing data. Default: connect."""
        return self.connect()

    def stop(self) -> None:
        """Stop producing data. Default: disconnect."""
        self.disconnect()

    # -- data -----------------------------------------------------------

    @abstractmethod
    def get_status(self) -> SourceStatus:
        """Current health. Called frequently; must be cheap and non-blocking."""

    @abstractmethod
    def read_latest(self) -> Dict[str, Sample]:
        """
        The most recent normalised values, keyed by tag id.

        Must return cached data. An adapter must never perform blocking I/O
        here -- this is called from the composition path.
        """

    def read_raw(self) -> Dict[str, Any]:
        """Bare values, for consumers that do their own quality handling."""
        return {k: s.value for k, s in self.read_latest().items()}

    # -- control --------------------------------------------------------

    def set_control_active(self, active: bool) -> None:
        """Called by SourceManager. Only the active source may be written to."""
        self._control_active = active

    @property
    def is_control_active(self) -> bool:
        return self._control_active

    def send_command(self, tag_id: str, value: Any, **kwargs) -> tuple:
        """
        Write. Returns (accepted, detail).

        Default: refuse. An adapter must opt in by overriding, and must check
        `is_control_active` first. Defaulting to refusal means a new adapter is
        read-only until someone deliberately makes it otherwise.
        """
        return False, "%s does not accept commands" % self.name

    # -- introspection --------------------------------------------------

    def describe(self) -> dict:
        d = self.get_status().to_dict()
        d["supportsControl"] = self.supports_control
        d["controlActive"] = self.is_control_active
        return d


def make_sample(
    value: Any,
    source: str,
    quality: str = QUALITY_GOOD,
    timestamp: Optional[float] = None,
    sequence: int = 0,
    unit: str = "",
) -> Sample:
    return Sample(
        value=value,
        source=source,
        timestamp=timestamp if timestamp is not None else time.time(),
        quality=quality,
        sequence=sequence,
        unit=unit,
    )


def samples_from(
    values: Dict[str, Any],
    source: str,
    quality: str,
    timestamp: float,
    sequence: int,
) -> Dict[str, Sample]:
    """Bulk-wrap a plain value dict. One shared timestamp: they came from one read."""
    return {
        tag_id: Sample(value, source, timestamp, quality, sequence)
        for tag_id, value in values.items()
    }
