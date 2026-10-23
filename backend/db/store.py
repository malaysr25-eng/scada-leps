"""
DataStore — SQL persistence that cannot block the PLC.

THE ONE PROPERTY THAT MATTERS
-----------------------------
The PLC poll thread must never wait on a disk write. Ever. A 250 ms control
loop that occasionally blocks for a 40 ms fsync is a control loop with a
40 ms jitter spike, and the whole point of this platform is that the poll
cadence is trustworthy.

So the poll thread's entire interaction with the database is:

    self._queue.put_nowait(record)      # O(1), never blocks

A separate writer thread owns the sqlite3 connection. sqlite3 objects are not
thread-safe across threads, and rather than pass `check_same_thread=False`
around and hope, the connection is *created inside* the writer thread and never
escapes it. Readers get their own short-lived connections.

BACKPRESSURE: DROP, DON'T BLOCK
-------------------------------
The queue is bounded. When it fills — a slow disk, a huge recording, a stalled
writer — the store **drops the record and increments a counter** that is
surfaced in the UI. It does not block, and it does not grow without limit until
the process dies.

That is the right trade for this system: the database holds diagnostic history,
and losing some of it is annoying. Stalling the control loop, or exhausting
memory, is dangerous. The dropped-record count makes the loss visible instead
of silent.

BATCHING
--------
The writer drains up to `batch_size` records and commits them in one
transaction. One commit per record would fsync per record; one commit per batch
amortises that across the batch, which is what makes recording sessions cheap.
"""

from __future__ import annotations

import json
import logging
import os
import queue
import sqlite3
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

from backend.db.schema import (
    DEFAULT_RETENTION,
    PRAGMAS,
    RETENTION_TIME_COLUMN,
    SCHEMA_VERSION,
    STATEMENTS,
)

log = logging.getLogger("db")


@dataclass
class WriteRecord:
    """One pending insert. `table` + `values` keeps the writer generic."""

    table: str
    values: Dict[str, Any]
    at: float = field(default_factory=time.time)


@dataclass
class StoreStats:
    enqueued: int = 0
    written: int = 0
    dropped: int = 0
    batches: int = 0
    errors: int = 0
    last_error: str = ""
    last_write_at: Optional[float] = None
    last_batch_size: int = 0
    max_queue_depth: int = 0
    sweep_deleted: int = 0
    write_ms_avg: float = 0.0

    def to_dict(self, queue_depth: int, capacity: int) -> dict:
        return {
            "enqueued": self.enqueued,
            "written": self.written,
            "dropped": self.dropped,
            "batches": self.batches,
            "errors": self.errors,
            "lastError": self.last_error,
            "lastWriteAt": self.last_write_at,
            "lastBatchSize": self.last_batch_size,
            "queueDepth": queue_depth,
            "queueCapacity": capacity,
            "maxQueueDepth": self.max_queue_depth,
            "sweepDeleted": self.sweep_deleted,
            "writeMsAvg": round(self.write_ms_avg, 2),
            "healthy": self.dropped == 0 and self.errors == 0,
        }


class DataStore:
    def __init__(self, config: dict, event_log=None) -> None:
        cfg = config or {}
        self.enabled = bool(cfg.get("enabled", True))
        self.path = cfg.get("path", "data/scada_history.db")
        self.batch_size = int(cfg.get("batch_size", 200))
        self.flush_interval = float(cfg.get("flush_interval", 1.0))
        self.queue_capacity = int(cfg.get("queue_capacity", 20000))
        self.retention_days = dict(DEFAULT_RETENTION)
        self.retention_days.update(cfg.get("retention_days", {}) or {})
        self.sweep_interval = float(cfg.get("sweep_interval", 3600.0))

        self.events = event_log
        self._queue: "queue.Queue[WriteRecord]" = queue.Queue(maxsize=self.queue_capacity)
        self._stop = threading.Event()
        self._worker: Optional[threading.Thread] = None
        self._stats = StoreStats()
        self._stats_lock = threading.Lock()
        self._ready = threading.Event()
        self._last_sweep = 0.0
        self._init_error = ""

    # ------------------------------------------------------------------
    # lifecycle
    # ------------------------------------------------------------------

    def start(self) -> bool:
        if not self.enabled:
            log.info("database disabled in config")
            return False
        if self._worker and self._worker.is_alive():
            return True

        directory = os.path.dirname(os.path.abspath(self.path))
        if directory:
            os.makedirs(directory, exist_ok=True)

        self._stop.clear()
        self._worker = threading.Thread(target=self._run, name="db-writer", daemon=True)
        self._worker.start()

        # Wait briefly for schema creation so the first API call after startup
        # does not race an empty database. Bounded: a failure here must not
        # prevent the control system from starting.
        if not self._ready.wait(timeout=5.0):
            log.warning("database did not become ready within 5 s")
        return self._ready.is_set()

    def stop(self, timeout: float = 5.0) -> None:
        if not self._worker:
            return
        self._stop.set()
        self._worker.join(timeout=timeout)

    @property
    def ready(self) -> bool:
        return self._ready.is_set()

    # ------------------------------------------------------------------
    # enqueue -- the only thing the poll thread ever calls
    # ------------------------------------------------------------------

    def write(self, table: str, **values) -> bool:
        """
        Queue one insert. Returns False if it was dropped.

        Never blocks. Never raises. Callers on the poll thread rely on both.
        """
        if not self.enabled or not self._ready.is_set():
            return False

        try:
            self._queue.put_nowait(WriteRecord(table, values))
        except queue.Full:
            with self._stats_lock:
                self._stats.dropped += 1
                if self._stats.dropped == 1 or self._stats.dropped % 1000 == 0:
                    log.warning(
                        "database queue full; dropped %d records so far",
                        self._stats.dropped,
                    )
            return False

        with self._stats_lock:
            self._stats.enqueued += 1
            depth = self._queue.qsize()
            if depth > self._stats.max_queue_depth:
                self._stats.max_queue_depth = depth
        return True

    def write_many(self, table: str, rows: List[dict]) -> int:
        return sum(1 for row in rows if self.write(table, **row))

    # ------------------------------------------------------------------
    # writer thread
    # ------------------------------------------------------------------

    def _run(self) -> None:
        conn = None
        try:
            # Created here, on purpose: this connection must never be touched
            # by another thread.
            conn = sqlite3.connect(self.path, timeout=10.0)
            for pragma in PRAGMAS:
                conn.execute(pragma)
            for statement in STATEMENTS:
                conn.execute(statement)
            conn.execute(
                "INSERT OR REPLACE INTO schema_meta(key, value) VALUES(?, ?)",
                ("schema_version", str(SCHEMA_VERSION)),
            )
            conn.commit()
            self._ready.set()
            log.info("database ready at %s (schema v%d)", self.path, SCHEMA_VERSION)
        except Exception as exc:
            self._init_error = str(exc)
            log.exception("database initialisation failed")
            if self.events:
                self.events.warning(
                    "database",
                    "Database unavailable: %s. The control system continues; "
                    "history will not be persisted." % exc,
                )
            return

        while not self._stop.is_set():
            batch = self._drain(self.batch_size, self.flush_interval)
            if batch:
                self._flush(conn, batch)
            self._maybe_sweep(conn)

        # Final drain, so a clean shutdown does not lose queued records.
        remaining = self._drain(self.queue_capacity, 0.0)
        if remaining:
            self._flush(conn, remaining)

        try:
            conn.close()
        except Exception:
            pass
        log.info("database writer stopped")

    def _drain(self, limit: int, wait: float) -> List[WriteRecord]:
        batch: List[WriteRecord] = []
        deadline = time.monotonic() + wait

        try:
            first = self._queue.get(timeout=wait) if wait > 0 else self._queue.get_nowait()
            batch.append(first)
        except queue.Empty:
            return batch

        while len(batch) < limit:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                break
            try:
                batch.append(self._queue.get_nowait())
            except queue.Empty:
                break
        return batch

    def _flush(self, conn: sqlite3.Connection, batch: List[WriteRecord]) -> None:
        started = time.monotonic()

        # Group by table so identical inserts share one executemany.
        grouped: Dict[str, List[WriteRecord]] = {}
        for record in batch:
            grouped.setdefault(record.table, []).append(record)

        try:
            for table, records in grouped.items():
                # Column sets can differ between records for the same table
                # (optional fields), so sub-group by column signature.
                by_columns: Dict[tuple, List[WriteRecord]] = {}
                for record in records:
                    by_columns.setdefault(tuple(sorted(record.values)), []).append(record)

                for columns, rows in by_columns.items():
                    placeholders = ", ".join("?" for _ in columns)
                    sql = "INSERT OR IGNORE INTO %s (%s) VALUES (%s)" % (
                        table, ", ".join(columns), placeholders,
                    )
                    conn.executemany(
                        sql,
                        [tuple(_encode(r.values[c]) for c in columns) for r in rows],
                    )
            conn.commit()

            elapsed_ms = (time.monotonic() - started) * 1000.0
            with self._stats_lock:
                self._stats.written += len(batch)
                self._stats.batches += 1
                self._stats.last_batch_size = len(batch)
                self._stats.last_write_at = time.time()
                self._stats.write_ms_avg = (
                    elapsed_ms if self._stats.batches == 1
                    else self._stats.write_ms_avg * 0.9 + elapsed_ms * 0.1
                )

        except Exception as exc:
            try:
                conn.rollback()
            except Exception:
                pass
            with self._stats_lock:
                self._stats.errors += 1
                self._stats.last_error = str(exc)
            log.warning("database batch failed (%d records): %s", len(batch), exc)

    # ------------------------------------------------------------------
    # retention
    # ------------------------------------------------------------------

    def _maybe_sweep(self, conn: sqlite3.Connection) -> None:
        now = time.monotonic()
        if now - self._last_sweep < self.sweep_interval:
            return
        self._last_sweep = now

        deleted = 0
        try:
            for table, days in self.retention_days.items():
                column = RETENTION_TIME_COLUMN.get(table)
                if not column or not days:
                    continue
                cutoff = time.time() - float(days) * 86400.0
                # LIMIT keeps one sweep bounded so it cannot hold the write
                # lock for long on a database that has gone unswept for weeks.
                cur = conn.execute(
                    "DELETE FROM %s WHERE rowid IN "
                    "(SELECT rowid FROM %s WHERE %s < ? LIMIT 20000)"
                    % (table, table, column),
                    (cutoff,),
                )
                deleted += cur.rowcount or 0
            if deleted:
                conn.commit()
                with self._stats_lock:
                    self._stats.sweep_deleted += deleted
                log.info("retention sweep removed %d rows", deleted)
        except Exception as exc:
            log.warning("retention sweep failed: %s", exc)

    # ------------------------------------------------------------------
    # reads -- short-lived connections, owned by the calling thread
    # ------------------------------------------------------------------

    def query(self, sql: str, params: tuple = ()) -> List[dict]:
        if not self.enabled or not self._ready.is_set():
            return []
        conn = None
        try:
            conn = sqlite3.connect(self.path, timeout=5.0)
            conn.row_factory = sqlite3.Row
            cur = conn.execute(sql, params)
            return [dict(row) for row in cur.fetchall()]
        except Exception as exc:
            log.warning("query failed: %s", exc)
            return []
        finally:
            if conn is not None:
                conn.close()

    def query_one(self, sql: str, params: tuple = ()) -> Optional[dict]:
        rows = self.query(sql, params)
        return rows[0] if rows else None

    def execute(self, sql: str, params: tuple = ()) -> bool:
        """
        Synchronous write, for the rare case that must complete before the HTTP
        response returns -- closing a recording session, updating its counters.

        Called from HTTP threads only, never the poll thread.
        """
        if not self.enabled or not self._ready.is_set():
            return False
        conn = None
        try:
            conn = sqlite3.connect(self.path, timeout=5.0)
            conn.execute(sql, params)
            conn.commit()
            return True
        except Exception as exc:
            with self._stats_lock:
                self._stats.errors += 1
                self._stats.last_error = str(exc)
            log.warning("execute failed: %s", exc)
            return False
        finally:
            if conn is not None:
                conn.close()

    # ------------------------------------------------------------------

    def stats(self) -> dict:
        with self._stats_lock:
            d = self._stats.to_dict(self._queue.qsize(), self.queue_capacity)
        d["enabled"] = self.enabled
        d["ready"] = self._ready.is_set()
        d["path"] = self.path
        d["initError"] = self._init_error
        d["retentionDays"] = self.retention_days
        return d

    def size_bytes(self) -> int:
        try:
            return os.path.getsize(self.path)
        except OSError:
            return 0


def _encode(value: Any) -> Any:
    """Adapt Python values to what sqlite3 accepts."""
    if isinstance(value, bool):
        return 1 if value else 0
    if isinstance(value, (dict, list, tuple)):
        return json.dumps(value, allow_nan=False, default=str)
    if value is None or isinstance(value, (int, float, str, bytes)):
        return value
    return str(value)
