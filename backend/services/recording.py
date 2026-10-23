"""
Operator-controlled persistence: snapshots, recording sessions, cycle saves.

WHY THIS IS EXPLICIT RATHER THAN AUTOMATIC
------------------------------------------
The default ingestion policy stores events and cycle summaries, not samples.
That keeps the database small and the poll loop unblocked, but it means an
engineer chasing an intermittent fault has no high-resolution trace.

This module is the escape hatch: the operator says "record this", and only then
does per-tag data start flowing to disk — still sampled and deadbanded, still
through the same non-blocking queue.

Three operations, three different shapes of question:

* **Snapshot** — "what is the machine doing *right now*?" One row, the whole
  composed state as JSON. Cheap enough to press repeatedly.
* **Recording session** — "capture the next few minutes." Time-series rows,
  bounded by interval and deadband.
* **Save cycle** — "keep this particular cycle." The summary plus a snapshot,
  attached to the cycle id.

THREADING
---------
`tick()` runs on the PLC poll thread and does nothing but a deadband test and a
`queue.put_nowait`. Session start/stop run on HTTP threads and do the small
synchronous UPDATEs. No lock is held across an I/O call.
"""

from __future__ import annotations

import json
import logging
import threading
import time
import uuid
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

log = logging.getLogger("recording")

STATUS_ACTIVE = "ACTIVE"
STATUS_COMPLETED = "COMPLETED"
STATUS_ABORTED = "ABORTED"


@dataclass
class RecordingSession:
    session_uid: str
    label: str
    note: str
    operator: str
    started_at: float
    sample_interval: float
    deadband: float
    tag_filter: List[str] = field(default_factory=list)
    mode: str = ""
    source_id: str = ""
    sample_count: int = 0
    dropped_count: int = 0
    ended_at: Optional[float] = None
    status: str = STATUS_ACTIVE
    #: tag -> (last_ts, last_value). Per-session, so two sessions with
    #: different settings never interfere.
    _state: Dict[str, tuple] = field(default_factory=dict, repr=False)

    @property
    def active(self) -> bool:
        return self.status == STATUS_ACTIVE

    @property
    def duration(self) -> float:
        return (self.ended_at or time.time()) - self.started_at

    def to_dict(self) -> dict:
        return {
            "sessionUid": self.session_uid,
            "label": self.label,
            "note": self.note,
            "operator": self.operator,
            "startedAt": self.started_at,
            "endedAt": self.ended_at,
            "durationSeconds": round(self.duration, 1),
            "sampleInterval": self.sample_interval,
            "deadband": self.deadband,
            "tagFilter": self.tag_filter,
            "tagFilterCount": len(self.tag_filter),
            "mode": self.mode,
            "sourceId": self.source_id,
            "sampleCount": self.sample_count,
            "droppedCount": self.dropped_count,
            "status": self.status,
            "active": self.active,
        }


class RecordingService:
    def __init__(self, store, ingest, event_log, config: Optional[dict] = None) -> None:
        self.store = store
        self.ingest = ingest
        self.events = event_log
        cfg = config or {}

        self.max_session_seconds = float(cfg.get("max_session_seconds", 3600.0))
        self.max_session_samples = int(cfg.get("max_session_samples", 500000))
        self.snapshot_max_bytes = int(cfg.get("snapshot_max_bytes", 2_000_000))

        self._lock = threading.RLock()
        self._session: Optional[RecordingSession] = None
        self._snapshot_count = 0
        self._last_snapshot_at: Optional[float] = None

    # ------------------------------------------------------------------
    # snapshots
    # ------------------------------------------------------------------

    def save_snapshot(
        self,
        snapshot: dict,
        label: str = "",
        note: str = "",
        operator: str = "local",
        trigger: str = "manual",
    ) -> tuple:
        """Persist the composed machine state as one row. Returns (ok, detail)."""
        if not self.store.enabled or not self.store.ready:
            return False, "Database is not available; snapshot not saved."

        try:
            payload = json.dumps(snapshot, allow_nan=False, default=str)
        except (TypeError, ValueError) as exc:
            return False, "Snapshot could not be serialised: %s" % exc

        if len(payload) > self.snapshot_max_bytes:
            # A snapshot that large means something upstream is wrong; storing
            # it repeatedly would bloat the database quickly.
            return False, (
                "Snapshot is %.1f MB, above the %.1f MB limit."
                % (len(payload) / 1e6, self.snapshot_max_bytes / 1e6)
            )

        machine = snapshot.get("machine", {})
        connection = snapshot.get("connection", {})
        now = time.time()

        ok = self.store.write(
            "data_snapshots",
            ts=now,
            label=label or time.strftime("Snapshot %H:%M:%S", time.localtime(now)),
            note=note,
            operator=operator,
            trigger=trigger,
            mode=machine.get("mode"),
            lifecycle=machine.get("lifecycle"),
            source_id=(snapshot.get("dataSources") or {}).get("controlSourceId"),
            cycle_id=machine.get("cycleId"),
            quality=(snapshot.get("dataSources") or {}).get("quality"),
            payload=payload,
        )

        if not ok:
            return False, "Snapshot was dropped: the database queue is full."

        with self._lock:
            self._snapshot_count += 1
            self._last_snapshot_at = now

        self.events.command(
            "recording",
            "Snapshot saved%s (%s, %s)"
            % (
                " '%s'" % label if label else "",
                machine.get("lifecycle", "?"),
                "%.0f kB" % (len(payload) / 1000),
            ),
            source=operator, trigger=trigger,
        )
        return True, {
            "savedAt": now,
            "bytes": len(payload),
            "label": label,
            "trigger": trigger,
        }

    # ------------------------------------------------------------------
    # sessions
    # ------------------------------------------------------------------

    def start_session(
        self,
        label: str = "",
        note: str = "",
        operator: str = "local",
        sample_interval: Optional[float] = None,
        deadband: Optional[float] = None,
        tag_filter: Optional[List[str]] = None,
        mode: str = "",
        source_id: str = "",
    ) -> tuple:
        if not self.store.enabled or not self.store.ready:
            return False, "Database is not available; cannot start a recording."

        with self._lock:
            if self._session is not None and self._session.active:
                return False, (
                    "A recording is already active (%s). Stop it before starting "
                    "another." % self._session.label
                )

            session = RecordingSession(
                session_uid=uuid.uuid4().hex[:16],
                label=label or time.strftime("Recording %Y-%m-%d %H:%M:%S"),
                note=note,
                operator=operator,
                started_at=time.time(),
                sample_interval=(
                    self.ingest.default_sample_interval
                    if sample_interval is None else max(0.05, float(sample_interval))
                ),
                deadband=(
                    self.ingest.default_deadband
                    if deadband is None else max(0.0, float(deadband))
                ),
                tag_filter=list(tag_filter or []),
                mode=mode,
                source_id=source_id,
            )
            self._session = session

        self.store.write(
            "recording_sessions",
            session_uid=session.session_uid,
            label=session.label,
            note=session.note,
            operator=session.operator,
            started_at=session.started_at,
            mode=session.mode,
            source_id=session.source_id,
            sample_interval_s=session.sample_interval,
            deadband=session.deadband,
            tag_filter=json.dumps(session.tag_filter) if session.tag_filter else None,
            status=STATUS_ACTIVE,
        )

        self.events.command(
            "recording",
            "Recording started: %s (every %.2f s, deadband %.4f, %s)"
            % (
                session.label, session.sample_interval, session.deadband,
                "%d tags" % len(session.tag_filter) if session.tag_filter else "all tags",
            ),
            source=operator, sessionUid=session.session_uid,
        )
        return True, session.to_dict()

    def stop_session(self, operator: str = "local", status: str = STATUS_COMPLETED) -> tuple:
        with self._lock:
            session = self._session
            if session is None or not session.active:
                return False, "No recording is active."
            session.ended_at = time.time()
            session.status = status
            self._session = None
            snapshot = session.to_dict()

        # Synchronous: the response should report the final counts, and the
        # queued INSERTs for this session may still be draining.
        self.store.execute(
            "UPDATE recording_sessions SET ended_at = ?, status = ?, "
            "sample_count = ?, dropped_count = ? WHERE session_uid = ?",
            (
                session.ended_at, status, session.sample_count,
                session.dropped_count, session.session_uid,
            ),
        )

        self.events.command(
            "recording",
            "Recording stopped: %s — %d samples over %.0f s%s"
            % (
                session.label, session.sample_count, session.duration,
                ", %d dropped" % session.dropped_count if session.dropped_count else "",
            ),
            source=operator, sessionUid=session.session_uid,
        )
        return True, snapshot

    # ------------------------------------------------------------------
    # the poll-thread hook
    # ------------------------------------------------------------------

    def tick(self, samples: Dict[str, Any], source_id: str) -> None:
        """
        Called once per poll. Does a deadband test and enqueues; no I/O.

        Must stay cheap: this runs inside the control loop.
        """
        with self._lock:
            session = self._session
            if session is None or not session.active:
                return

            # Bound the session so a forgotten recording cannot fill the disk.
            if session.duration > self.max_session_seconds:
                log.info("recording %s hit the time limit", session.session_uid)
                threading.Thread(
                    target=self.stop_session, args=("auto-limit", STATUS_COMPLETED),
                    daemon=True,
                ).start()
                return
            if session.sample_count >= self.max_session_samples:
                log.info("recording %s hit the sample limit", session.session_uid)
                threading.Thread(
                    target=self.stop_session, args=("auto-limit", STATUS_COMPLETED),
                    daemon=True,
                ).start()
                return

            now = time.time()
            wanted = set(session.tag_filter) if session.tag_filter else None

            for tag_id, sample in samples.items():
                if wanted is not None and tag_id not in wanted:
                    continue

                value = sample.value if hasattr(sample, "value") else sample
                if value is None:
                    continue

                if not self.ingest.should_sample(
                    tag_id, value, now,
                    session.sample_interval, session.deadband, session._state,
                ):
                    continue

                num_value = None
                bool_value = None
                text_value = None
                if isinstance(value, bool):
                    bool_value = 1 if value else 0
                elif isinstance(value, (int, float)):
                    num_value = float(value)
                else:
                    text_value = str(value)

                ok = self.store.write(
                    "tag_samples",
                    session_uid=session.session_uid,
                    ts=now,
                    tag_id=tag_id,
                    num_value=num_value,
                    bool_value=bool_value,
                    text_value=text_value,
                    quality=getattr(sample, "quality", None),
                    source_id=source_id,
                )
                if ok:
                    session._state[tag_id] = (now, value)
                    session.sample_count += 1
                    self.ingest.note_sample()
                else:
                    session.dropped_count += 1

    # ------------------------------------------------------------------
    # cycles
    # ------------------------------------------------------------------

    def save_cycle(
        self,
        snapshot: dict,
        outcome: str = "COMPLETED",
        operator: str = "local",
        note: str = "",
    ) -> tuple:
        """Persist a cycle summary plus a snapshot pinned to that cycle."""
        machine = snapshot.get("machine", {})
        cycle_id = machine.get("cycleId")
        if not cycle_id:
            return False, "No cycle is currently identified."

        if not self.store.enabled or not self.store.ready:
            return False, "Database is not available; cycle not saved."

        inventory = snapshot.get("inventory", {})
        order = inventory.get("order", {})
        progress = inventory.get("progress", {})
        sequence = snapshot.get("sequence", {})
        diagnostics = snapshot.get("diagnostics", {})
        sources = snapshot.get("dataSources", {})

        started = machine.get("cycleStartedAt")
        ended = machine.get("cycleEndedAt") or time.time()

        self.ingest.on_cycle_complete({
            "cycle_id": cycle_id,
            "started_at": started or ended,
            "ended_at": ended,
            "duration_s": round(ended - started, 3) if started else None,
            "outcome": outcome,
            "qty_25mm": order.get("qty25"),
            "qty_50mm": order.get("qty50"),
            "products_done": progress.get("plcTotalProducts"),
            "mode": machine.get("mode"),
            "source_id": sources.get("controlSourceId"),
            "max_step_reached": sequence.get("lastConfirmedStep"),
            "fault_count": len(diagnostics.get("activeFaults", [])),
            "stall_count": 1 if sequence.get("stalled") else 0,
            "detail": json.dumps({
                "note": note,
                "operator": operator,
                "lifecycle": machine.get("lifecycle"),
                "waitingFor": sequence.get("waitingFor"),
            }, default=str),
        })

        self.save_snapshot(
            snapshot,
            label="Cycle %s" % cycle_id,
            note=note,
            operator=operator,
            trigger="cycle_end",
        )

        self.events.command(
            "recording", "Cycle %s saved (%s)" % (cycle_id, outcome), source=operator,
        )
        return True, {"cycleId": cycle_id, "outcome": outcome}

    # ------------------------------------------------------------------

    def status(self) -> dict:
        with self._lock:
            session = self._session
            return {
                "recording": session is not None and session.active,
                "session": session.to_dict() if session else None,
                "snapshotCount": self._snapshot_count,
                "lastSnapshotAt": self._last_snapshot_at,
                "limits": {
                    "maxSessionSeconds": self.max_session_seconds,
                    "maxSessionSamples": self.max_session_samples,
                },
            }
