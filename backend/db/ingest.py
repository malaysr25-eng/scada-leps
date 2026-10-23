"""
Ingestion policy — what gets persisted, and what does not.

THE DEFAULT IS: ALMOST NOTHING
------------------------------
At 250 ms and 158 tags, naive persistence is 54 million rows/day. So the policy
is inverted from the obvious one. Instead of "store everything, prune later",
this stores *events that carry meaning* and nothing else, unless an operator has
explicitly asked for more.

Four ingestion paths, in increasing volume:

1. **Event-driven (always on, cheap).** Something happened that a human would
   want to read later: a fault latched, the lifecycle changed, a command was
   written, a cycle finished. Volume is set by the machine's behaviour, not by
   the poll rate — hundreds of rows a day.

2. **Watched-tag transitions (always on, bounded).** Only tags on the watch
   list, and only when they change. This is what makes "when did SV8 actually
   toggle, and was it us?" answerable after a restart. Bounded by the watch
   list size, and rate-limited per tag so a chattering signal cannot flood the
   queue — which is precisely the E-18 scenario, where a tag was toggling 52
   times in 30 s.

3. **Cycle summaries + aggregates (always on, one row per cycle).** Min/max/avg
   accumulated in memory during the cycle, written once at the end. This gives
   trendable history at a thousandth of the row cost of storing the samples.

4. **Recording sessions (operator-initiated, bounded).** Only while someone has
   pressed Start Recording, and even then with an interval and a deadband, so a
   steady signal writes nothing.

DEADBAND
--------
A `Real` that jitters in its last decimal place is not news. Numeric samples are
only stored when they move by more than the configured deadband, or when the
maximum interval has elapsed (so a flat trace still gets periodic anchor points
and does not look like missing data). Bools store on every change, because for a
Bool every change *is* the news.
"""

from __future__ import annotations

import json
import logging
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

log = logging.getLogger("db.ingest")


@dataclass
class TagAccumulator:
    """Running aggregate for one numeric tag within one cycle."""

    count: int = 0
    total: float = 0.0
    min_value: Optional[float] = None
    max_value: Optional[float] = None
    last_value: Optional[float] = None

    def add(self, value: float) -> None:
        self.count += 1
        self.total += value
        self.last_value = value
        if self.min_value is None or value < self.min_value:
            self.min_value = value
        if self.max_value is None or value > self.max_value:
            self.max_value = value

    @property
    def average(self) -> Optional[float]:
        return None if self.count == 0 else self.total / self.count

    def reset(self) -> None:
        self.count = 0
        self.total = 0.0
        self.min_value = None
        self.max_value = None
        self.last_value = None


class IngestPolicy:
    """
    Decides what reaches the DataStore. Holds no connection and does no I/O.

    Every method is called from the poll thread, so every method is cheap and
    non-blocking by construction.
    """

    def __init__(self, store, config: dict, event_log=None) -> None:
        self.store = store
        self.events = event_log
        cfg = config or {}

        # Watched-tag transition capture.
        self.persist_watched = bool(cfg.get("persist_watched_tags", True))
        self.watched_min_interval = float(cfg.get("watched_min_interval", 0.25))
        self.watched_burst_limit = int(cfg.get("watched_burst_limit", 20))
        self.watched_burst_window = float(cfg.get("watched_burst_window", 10.0))

        # Recording sessions.
        self.default_sample_interval = float(cfg.get("sample_interval", 1.0))
        self.default_deadband = float(cfg.get("deadband", 0.001))
        self.max_interval = float(cfg.get("max_interval", 30.0))

        # Aggregates.
        self.aggregate_roles = cfg.get("aggregate_roles") or [
            "pressure.value",
            "conveyor.1.velocity_fb", "conveyor.2.velocity_fb", "conveyor.3.velocity_fb",
            "conveyor.1.set_velocity", "conveyor.2.set_velocity", "conveyor.3.set_velocity",
            "conveyor.1.position_fb", "conveyor.2.position_fb", "conveyor.3.position_fb",
        ]

        self._lock = threading.RLock()
        self._last_written: Dict[str, float] = {}          # tag -> ts
        self._last_value: Dict[str, Any] = {}              # tag -> value
        self._burst: Dict[str, List[float]] = {}           # tag -> recent write ts
        self._suppressed: Dict[str, int] = {}              # tag -> suppressed count
        self._accumulators: Dict[str, TagAccumulator] = {}
        self._cycle_id: Optional[str] = None

        self.stats = {
            "eventsStored": 0,
            "transitionsStored": 0,
            "transitionsSuppressed": 0,
            "samplesStored": 0,
            "samplesSkippedDeadband": 0,
            "cyclesStored": 0,
        }

    # ------------------------------------------------------------------
    # 1. events
    # ------------------------------------------------------------------

    def on_event(self, event: dict, context: dict) -> None:
        """Persist one event. Called for every emitted event."""
        detail = event.get("detail") or {}
        self.store.write(
            "system_events",
            ts=event["at"],
            severity=event["severity"],
            category=event["category"],
            message=event["message"],
            source=event.get("source"),
            source_id=context.get("sourceId"),
            cycle_id=context.get("cycleId"),
            detail=json.dumps(detail, default=str) if detail else None,
        )
        self.stats["eventsStored"] += 1

    def on_alarm_raised(self, fault: dict, context: dict) -> None:
        self.store.write(
            "alarms",
            alarm_key=fault["key"],
            severity=fault["severity"],
            message=fault["message"],
            raised_at=fault["raisedAt"],
            acknowledged=1 if fault.get("acknowledged") else 0,
            occurrences=fault.get("occurrences", 1),
            issue_ref=(fault.get("detail") or {}).get("issueRef"),
            cycle_id=context.get("cycleId"),
            detail=json.dumps(fault.get("detail") or {}, default=str),
        )

    def on_alarm_cleared(self, fault: dict) -> None:
        # The most recent open row for this key. Synchronous because it is an
        # UPDATE and the queue only carries INSERTs; volume is negligible.
        self.store.execute(
            "UPDATE alarms SET cleared_at = ? "
            "WHERE id = (SELECT id FROM alarms WHERE alarm_key = ? "
            "AND cleared_at IS NULL ORDER BY raised_at DESC LIMIT 1)",
            (fault.get("clearedAt") or time.time(), fault["key"]),
        )

    def on_state_transition(
        self, kind: str, previous: Optional[str], current: str, context: dict
    ) -> None:
        self.store.write(
            "state_history",
            ts=time.time(),
            kind=kind,
            previous=previous,
            current=current,
            cycle_id=context.get("cycleId"),
            operator=context.get("operator"),
            source_id=context.get("sourceId"),
            detail=json.dumps(context.get("detail") or {}, default=str),
        )

    def on_command(self, command: dict, context: dict) -> None:
        """Persist a settled command — the request and what the PLC actually held."""
        self.store.write(
            "command_history",
            ts=command.get("createdAt", time.time()),
            command_id=command.get("id"),
            tag_id=command.get("tagId"),
            address=command.get("address"),
            requested=_text(command.get("requested")),
            observed=_text(command.get("observed")),
            dtype=command.get("dtype"),
            outcome=command.get("state"),
            latency_ms=command.get("latencyMs"),
            operator=command.get("operator"),
            origin=command.get("source"),
            source_id=context.get("sourceId"),
            cycle_id=context.get("cycleId"),
            error=command.get("error") or None,
        )

    # ------------------------------------------------------------------
    # 2. watched-tag transitions
    # ------------------------------------------------------------------

    def on_tag_changes(
        self, changes: List[dict], watch: List[str], context: dict
    ) -> None:
        """
        Persist transitions of watched tags only, rate-limited per tag.

        The rate limit is not an optimisation; it is protection. A tag toggling
        3 Hz — exactly the reported SV8 behaviour — would otherwise write a
        quarter of a million rows a day on its own. After the burst limit the
        tag is suppressed and the suppressed count is recorded, so the *fact*
        of the chatter is still preserved even though the individual edges are
        not.
        """
        if not self.persist_watched or not changes:
            return

        watched = set(watch)
        now = time.time()

        with self._lock:
            for change in changes:
                tag_id = change.get("tagId")
                if tag_id not in watched:
                    continue

                recent = self._burst.setdefault(tag_id, [])
                cutoff = now - self.watched_burst_window
                while recent and recent[0] < cutoff:
                    recent.pop(0)

                if len(recent) >= self.watched_burst_limit:
                    self._suppressed[tag_id] = self._suppressed.get(tag_id, 0) + 1
                    self.stats["transitionsSuppressed"] += 1
                    if self._suppressed[tag_id] == 1:
                        log.info(
                            "suppressing %s transitions: %d in %.0fs exceeds the "
                            "burst limit", tag_id, len(recent), self.watched_burst_window,
                        )
                    continue

                last = self._last_written.get(tag_id, 0.0)
                if now - last < self.watched_min_interval:
                    continue

                self.store.write(
                    "historical_tag_data",
                    ts=change.get("at", now),
                    tag_id=tag_id,
                    previous=_text(change.get("previous")),
                    value=_text(change.get("value")),
                    attribution=change.get("source"),
                    command_id=change.get("commandId"),
                    source_id=context.get("sourceId"),
                    cycle_id=context.get("cycleId"),
                )
                recent.append(now)
                self._last_written[tag_id] = now
                self.stats["transitionsStored"] += 1

    # ------------------------------------------------------------------
    # 3. aggregates
    # ------------------------------------------------------------------

    def accumulate(self, roles: Dict[str, Any], cycle_id: Optional[str]) -> None:
        """
        Fold this poll's numeric values into in-memory aggregates.

        No I/O. This is the mechanism that gives per-cycle min/max/avg without
        storing a single sample.
        """
        if cycle_id is None:
            return

        with self._lock:
            if cycle_id != self._cycle_id:
                self._accumulators.clear()
                self._cycle_id = cycle_id

            for role in self.aggregate_roles:
                value = roles.get(role)
                if isinstance(value, (int, float)) and not isinstance(value, bool):
                    self._accumulators.setdefault(role, TagAccumulator()).add(float(value))

    def flush_cycle_metrics(self, cycle_id: str) -> int:
        with self._lock:
            if cycle_id != self._cycle_id:
                return 0
            written = 0
            for metric, acc in self._accumulators.items():
                if acc.count == 0:
                    continue
                self.store.write(
                    "cycle_metrics",
                    cycle_id=cycle_id,
                    metric=metric,
                    min_value=acc.min_value,
                    max_value=acc.max_value,
                    avg_value=acc.average,
                    last_value=acc.last_value,
                    sample_count=acc.count,
                )
                written += 1
            self._accumulators.clear()
            self._cycle_id = None
            return written

    def on_cycle_complete(self, cycle: dict) -> None:
        self.store.write("cycle_history", **cycle)
        self.stats["cyclesStored"] += 1
        if cycle.get("cycle_id"):
            self.flush_cycle_metrics(cycle["cycle_id"])

    # ------------------------------------------------------------------
    # 4. recording sessions
    # ------------------------------------------------------------------

    def should_sample(
        self,
        tag_id: str,
        value: Any,
        now: float,
        interval: float,
        deadband: float,
        state: Dict[str, tuple],
    ) -> bool:
        """
        Interval + deadband test for one tag inside a recording session.

        `state` is owned by the caller (the recording session), so two
        concurrent sessions with different settings cannot interfere.
        """
        last = state.get(tag_id)
        if last is None:
            return True

        last_ts, last_value = last
        elapsed = now - last_ts

        # A flat signal still gets periodic anchors, so a gap in the data means
        # "not recorded" rather than being indistinguishable from "unchanged".
        if elapsed >= self.max_interval:
            return True
        if elapsed < interval:
            return False

        if isinstance(value, bool) or isinstance(last_value, bool):
            return value != last_value
        if isinstance(value, (int, float)) and isinstance(last_value, (int, float)):
            if abs(float(value) - float(last_value)) < deadband:
                self.stats["samplesSkippedDeadband"] += 1
                return False
            return True
        return value != last_value

    def note_sample(self) -> None:
        self.stats["samplesStored"] += 1

    # ------------------------------------------------------------------

    def suppressed_report(self) -> List[dict]:
        with self._lock:
            return [
                {"tagId": tag, "suppressed": count}
                for tag, count in sorted(
                    self._suppressed.items(), key=lambda kv: -kv[1]
                )[:10]
            ]

    def describe(self) -> dict:
        return {
            "stats": dict(self.stats),
            "suppressed": self.suppressed_report(),
            "policy": {
                "persistWatchedTags": self.persist_watched,
                "watchedMinInterval": self.watched_min_interval,
                "watchedBurstLimit": self.watched_burst_limit,
                "watchedBurstWindow": self.watched_burst_window,
                "defaultSampleInterval": self.default_sample_interval,
                "defaultDeadband": self.default_deadband,
                "maxInterval": self.max_interval,
                "aggregateRoles": self.aggregate_roles,
            },
            "note": (
                "Nothing is written per poll by default. Tag samples are only "
                "written inside an explicit recording session."
            ),
        }


def _text(value: Any) -> Optional[str]:
    if value is None:
        return None
    if isinstance(value, bool):
        return "true" if value else "false"
    return str(value)
