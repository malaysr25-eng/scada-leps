"""
Event and fault log.

One ring buffer holds everything that happened, in order, with a severity and
a source. The legacy system had no equivalent: when a cycle terminated midway
the screen simply stopped updating and the reason was gone forever.

Faults are events that latch. They stay ACTIVE until their condition clears,
then move to CLEARED but remain in the log, so an operator arriving after the
fact can still see what tripped and when.
"""

from __future__ import annotations

import itertools
import threading
import time
from dataclasses import dataclass, field
from typing import Dict, List, Optional

# Severities, ordered.
INFO = "INFO"
COMMAND = "COMMAND"
PLC = "PLC"
WARNING = "WARNING"
FAULT = "FAULT"
EMERGENCY = "EMERGENCY"

_SEVERITY_RANK = {
    INFO: 0, COMMAND: 1, PLC: 1, WARNING: 2, FAULT: 3, EMERGENCY: 4,
}


@dataclass
class Event:
    id: int
    at: float
    severity: str
    category: str
    message: str
    source: str = "system"
    detail: dict = field(default_factory=dict)

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "at": self.at,
            "severity": self.severity,
            "category": self.category,
            "message": self.message,
            "source": self.source,
            "detail": self.detail,
        }


@dataclass
class Fault:
    key: str
    severity: str
    message: str
    raised_at: float
    detail: dict = field(default_factory=dict)
    cleared_at: Optional[float] = None
    acknowledged: bool = False
    occurrences: int = 1

    @property
    def active(self) -> bool:
        return self.cleared_at is None

    def to_dict(self) -> dict:
        return {
            "key": self.key,
            "severity": self.severity,
            "message": self.message,
            "raisedAt": self.raised_at,
            "clearedAt": self.cleared_at,
            "active": self.active,
            "acknowledged": self.acknowledged,
            "occurrences": self.occurrences,
            "detail": self.detail,
        }


class EventLog:
    def __init__(self, capacity: int = 4000) -> None:
        self._lock = threading.RLock()
        self._events: List[Event] = []
        self._faults: Dict[str, Fault] = {}
        self._ids = itertools.count(1)
        self.capacity = capacity
        self._subscribers: List = []

    # -- events ---------------------------------------------------------

    def emit(
        self,
        severity: str,
        category: str,
        message: str,
        source: str = "system",
        **detail,
    ) -> Event:
        with self._lock:
            ev = Event(
                id=next(self._ids),
                at=time.time(),
                severity=severity,
                category=category,
                message=message,
                source=source,
                detail=detail,
            )
            self._events.append(ev)
            if len(self._events) > self.capacity:
                del self._events[: len(self._events) - self.capacity]
        return ev

    def info(self, category, message, source="system", **d):
        return self.emit(INFO, category, message, source, **d)

    def command(self, category, message, source="operator", **d):
        return self.emit(COMMAND, category, message, source, **d)

    def plc(self, category, message, source="plc", **d):
        return self.emit(PLC, category, message, source, **d)

    def warning(self, category, message, source="system", **d):
        return self.emit(WARNING, category, message, source, **d)

    def recent(self, limit: int = 200, min_severity: Optional[str] = None) -> List[dict]:
        floor = _SEVERITY_RANK.get(min_severity, -1) if min_severity else -1
        with self._lock:
            out = [
                e.to_dict()
                for e in reversed(self._events)
                if _SEVERITY_RANK.get(e.severity, 0) >= floor
            ]
        return out[:limit]

    def since(self, event_id: int, limit: int = 500) -> List[dict]:
        with self._lock:
            return [e.to_dict() for e in self._events if e.id > event_id][:limit]

    # -- faults ---------------------------------------------------------

    def raise_fault(
        self, key: str, message: str, severity: str = FAULT, **detail
    ) -> Optional[Fault]:
        """Latch a fault. Returns the Fault only when it is newly raised."""
        with self._lock:
            existing = self._faults.get(key)
            if existing and existing.active:
                return None
            if existing:
                existing.cleared_at = None
                existing.raised_at = time.time()
                existing.message = message
                existing.detail = detail
                existing.acknowledged = False
                existing.occurrences += 1
                fault = existing
            else:
                fault = Fault(
                    key=key,
                    severity=severity,
                    message=message,
                    raised_at=time.time(),
                    detail=detail,
                )
                self._faults[key] = fault

        self.emit(severity, "fault", message, source="diagnostics", faultKey=key, **detail)
        return fault

    def clear_fault(self, key: str, message: Optional[str] = None) -> bool:
        with self._lock:
            fault = self._faults.get(key)
            if not fault or not fault.active:
                return False
            fault.cleared_at = time.time()
        self.emit(
            INFO, "fault",
            message or ("Cleared: %s" % fault.message),
            source="diagnostics", faultKey=key,
        )
        return True

    def acknowledge(self, key: str) -> bool:
        with self._lock:
            fault = self._faults.get(key)
            if not fault:
                return False
            fault.acknowledged = True
        return True

    def faults(self, include_cleared: bool = True) -> List[dict]:
        with self._lock:
            items = list(self._faults.values())
        items.sort(key=lambda f: (not f.active, -f.raised_at))
        return [
            f.to_dict() for f in items if include_cleared or f.active
        ]

    def active_faults(self) -> List[dict]:
        return self.faults(include_cleared=False)

    def has_active(self, key: str) -> bool:
        with self._lock:
            f = self._faults.get(key)
            return bool(f and f.active)
