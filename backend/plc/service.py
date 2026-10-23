"""
PlcService -- the single owner of the Snap7 connection.

THE RULE THIS FILE EXISTS TO ENFORCE
------------------------------------
Exactly one Snap7 client exists in the process, exactly one thread performs
I/O on it, and no HTTP request ever calls ``db_read``/``db_write`` directly.
Everything else in the application reads a cached snapshot.

The legacy system violated this three ways at once:
  * ``Final/app.py`` opened a client at import time and wrote to the PLC from
    inside request handlers -- and ran with ``debug=True``, so the Werkzeug
    reloader forked a second process holding a second client.
  * ``json_write_for_web_tag.py`` opened a third client in a tight, unthrottled
    loop with a bare ``except: continue``.
  * ``PLC_Dashboard/app*.py`` opened a fourth.

WRITE CONFIRMATION
------------------
A write is not "done" when ``db_write`` returns. It is done when a subsequent
independent poll reads the value back. Commands therefore move through
PENDING -> WRITTEN -> CONFIRMED (or TIMEOUT / MISMATCH), and the cache is never
optimistically patched with the requested value. The old dashboard did patch it
(``values_cache[index] = new_value``), which made every write look successful
even when the PLC rejected or overwrote it -- precisely the class of bug behind
"actuator 8 did not retract" being invisible on screen.
"""

from __future__ import annotations

import logging
import threading
import time
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Tuple

from backend.plc import codec
from backend.plc.registry import Registry, Tag

log = logging.getLogger("plc")

# Connection lifecycle reported to the UI.
CONN_DISCONNECTED = "DISCONNECTED"
CONN_CONNECTING = "CONNECTING"
CONN_CONNECTED = "CONNECTED"
CONN_DEGRADED = "DEGRADED"       # connected, but polls are missing their deadline
CONN_RECONNECTING = "RECONNECTING"
CONN_SIMULATED = "SIMULATED"     # no PLC present; values come from the sim source

# Command lifecycle.
CMD_PENDING = "PENDING"
CMD_WRITTEN = "WRITTEN"
CMD_CONFIRMED = "CONFIRMED"
CMD_MISMATCH = "MISMATCH"
CMD_TIMEOUT = "TIMEOUT"
CMD_REJECTED = "REJECTED"
CMD_FAILED = "FAILED"


@dataclass
class Command:
    """One in-flight write, tracked from request to PLC read-back."""

    id: str
    tag_id: str
    address: str
    requested: Any
    dtype: str
    source: str                 # "manual" | "auto" | "recovery" | "system"
    operator: str = "local"
    state: str = CMD_PENDING
    created_at: float = field(default_factory=time.time)
    written_at: Optional[float] = None
    settled_at: Optional[float] = None
    observed: Any = None
    error: str = ""
    confirm_deadline: float = 0.0

    def to_dict(self) -> dict:
        return {
            "id": self.id,
            "tagId": self.tag_id,
            "address": self.address,
            "requested": self.requested,
            "observed": self.observed,
            "dtype": self.dtype,
            "source": self.source,
            "operator": self.operator,
            "state": self.state,
            "createdAt": self.created_at,
            "writtenAt": self.written_at,
            "settledAt": self.settled_at,
            "latencyMs": (
                round((self.settled_at - self.created_at) * 1000, 1)
                if self.settled_at
                else None
            ),
            "error": self.error,
        }


@dataclass
class PollHealth:
    last_success: float = 0.0
    last_attempt: float = 0.0
    last_error: str = ""
    latency_ms: float = 0.0
    latency_avg_ms: float = 0.0
    poll_count: int = 0
    error_count: int = 0
    reconnect_count: int = 0
    consecutive_errors: int = 0

    def to_dict(self) -> dict:
        return {
            "lastSuccess": self.last_success or None,
            "lastAttempt": self.last_attempt or None,
            "lastError": self.last_error,
            "latencyMs": round(self.latency_ms, 1),
            "latencyAvgMs": round(self.latency_avg_ms, 1),
            "pollCount": self.poll_count,
            "errorCount": self.error_count,
            "reconnectCount": self.reconnect_count,
            "consecutiveErrors": self.consecutive_errors,
        }


class PlcService:
    """
    Owns the connection, the poll loop, the value cache and the write queue.

    Thread-safety contract:
      * ``_io_lock`` serialises every Snap7 call. Only the worker thread and
        ``_drain_write_queue`` (which runs *on* the worker thread) take it.
      * ``_state_lock`` guards the cache and command tables, which HTTP threads
        read. It is never held across a PLC call.
    """

    def __init__(
        self,
        registry: Registry,
        config: dict,
        on_snapshot: Optional[Callable[[dict], None]] = None,
    ) -> None:
        self.registry = registry
        self.ip = config.get("plc_ip", "172.21.30.157")
        self.rack = int(config.get("rack", 0))
        self.slot = int(config.get("slot", 1))
        # ISO-on-TCP port. 102 on every real S7; another value only for a local
        # stand-in such as the fake cell (predictive_maintenance/tools/fake_cell.py).
        self.port = int(config.get("port", 102))
        self.poll_interval = float(config.get("poll_interval", 0.25))
        self.confirm_timeout = float(config.get("write_confirm_timeout", 2.0))
        self.simulate = bool(config.get("simulate", False))
        self.reconnect_backoff = float(config.get("reconnect_backoff", 1.0))
        self.reconnect_backoff_max = float(config.get("reconnect_backoff_max", 10.0))
        # A poll that lands later than this multiple of the interval marks the
        # link DEGRADED rather than pretending everything is fine.
        self.degraded_after = float(config.get("degraded_after", 3.0))

        self._client = None
        self._io_lock = threading.RLock()
        self._state_lock = threading.RLock()
        self._stop = threading.Event()
        self._worker: Optional[threading.Thread] = None

        self._buffers: Dict[int, bytearray] = {}
        self._values: Dict[str, Any] = {}
        self._value_ts: Dict[str, float] = {}
        self._connection = CONN_DISCONNECTED
        self._health = PollHealth()
        self._backoff = self.reconnect_backoff

        self._write_queue: List[Command] = []
        self._inflight: Dict[str, Command] = {}
        self._recent_commands: List[Command] = []
        self._command_seq = 0

        self._on_snapshot = on_snapshot
        self._change_listeners: List[Callable[[List[dict], dict], None]] = []

        # Read plan: one contiguous read per DB, sized from the registry.
        self._read_plan: List[Tuple[int, int]] = []
        for db, extent in sorted(registry.db_extents.items()):
            if extent > 0:
                self._read_plan.append((db, extent))

    # ------------------------------------------------------------------
    # lifecycle
    # ------------------------------------------------------------------

    def start(self) -> None:
        if self._worker and self._worker.is_alive():
            return
        self._stop.clear()
        self._worker = threading.Thread(
            target=self._run, name="plc-worker", daemon=True
        )
        self._worker.start()
        log.info(
            "PLC worker started: %s rack=%d slot=%d, plan=%s, interval=%.0f ms%s",
            self.ip, self.rack, self.slot, self._read_plan,
            self.poll_interval * 1000,
            " [SIMULATED]" if self.simulate else "",
        )

    def stop(self, timeout: float = 3.0) -> None:
        self._stop.set()
        if self._worker:
            self._worker.join(timeout=timeout)
        self._disconnect()

    def add_change_listener(self, fn: Callable[[List[dict], dict], None]) -> None:
        """Called on the worker thread with (changes, snapshot) after each poll."""
        self._change_listeners.append(fn)

    # ------------------------------------------------------------------
    # connection
    # ------------------------------------------------------------------

    def _connect(self) -> bool:
        if self.simulate:
            self._connection = CONN_SIMULATED
            return True

        with self._io_lock:
            try:
                if self._client is None:
                    import snap7  # imported lazily so sim mode needs no snap7

                    self._client = snap7.client.Client()

                if not self._client.get_connected():
                    self._connection = (
                        CONN_RECONNECTING
                        if self._health.poll_count
                        else CONN_CONNECTING
                    )
                    self._client.connect(self.ip, self.rack, self.slot, self.port)
                    self._health.reconnect_count += 1

                if self._client.get_connected():
                    self._connection = CONN_CONNECTED
                    self._backoff = self.reconnect_backoff
                    return True

            except Exception as exc:  # snap7 raises bare Snap7Exception
                self._health.last_error = str(exc)
                self._connection = CONN_DISCONNECTED
                self._safe_disconnect()

        return False

    def _safe_disconnect(self) -> None:
        try:
            if self._client is not None and self._client.get_connected():
                self._client.disconnect()
        except Exception:
            pass

    def _disconnect(self) -> None:
        with self._io_lock:
            self._safe_disconnect()
            self._connection = CONN_DISCONNECTED

    # ------------------------------------------------------------------
    # poll loop
    # ------------------------------------------------------------------

    def _run(self) -> None:
        while not self._stop.is_set():
            cycle_start = time.monotonic()
            self._health.last_attempt = time.time()

            if not self._connect():
                # Exponential backoff, so a PLC that is switched off does not
                # generate a connect storm on the network.
                self._stop.wait(self._backoff)
                self._backoff = min(self._backoff * 1.6, self.reconnect_backoff_max)
                self._publish(changes=[])
                continue

            try:
                buffers = self._read_all()
            except Exception as exc:
                self._health.error_count += 1
                self._health.consecutive_errors += 1
                self._health.last_error = str(exc)
                self._connection = CONN_DISCONNECTED
                log.warning("PLC read failed: %s", exc)
                self._disconnect()
                self._fail_inflight("PLC link lost during write confirmation")
                self._publish(changes=[])
                self._stop.wait(min(self._backoff, 1.0))
                continue

            latency_ms = (time.monotonic() - cycle_start) * 1000.0
            self._health.latency_ms = latency_ms
            self._health.latency_avg_ms = (
                latency_ms
                if self._health.poll_count == 0
                else self._health.latency_avg_ms * 0.9 + latency_ms * 0.1
            )
            self._health.poll_count += 1
            self._health.consecutive_errors = 0
            self._health.last_success = time.time()
            self._health.last_error = ""

            changes = self._decode_into_cache(buffers)
            self._settle_commands()

            # Writes are issued from the worker thread, immediately after a
            # fresh read, so a Bool read-modify-write can never interleave with
            # another thread's read of the same byte.
            self._drain_write_queue()

            if latency_ms > self.poll_interval * 1000 * self.degraded_after:
                self._connection = CONN_DEGRADED
            elif not self.simulate:
                self._connection = CONN_CONNECTED

            self._publish(changes)

            elapsed = time.monotonic() - cycle_start
            self._stop.wait(max(0.01, self.poll_interval - elapsed))

        self._disconnect()
        log.info("PLC worker stopped")

    def _read_all(self) -> Dict[int, bytearray]:
        if self.simulate:
            return {db: self._buffers.get(db, bytearray(size))
                    for db, size in self._read_plan}

        out: Dict[int, bytearray] = {}
        with self._io_lock:
            for db, size in self._read_plan:
                out[db] = bytearray(self._client.db_read(db, 0, size))
        return out

    def _decode_into_cache(self, buffers: Dict[int, bytearray]) -> List[dict]:
        """Decode every registered tag and return the list of changed ones."""
        now = time.time()
        changes: List[dict] = []
        new_values: Dict[str, Any] = {}

        for tag in self.registry.tags:
            buf = buffers.get(tag.db)
            if buf is None:
                continue
            try:
                value = codec.decode(buf, tag.byte, tag.bit, tag.dtype)
            except codec.DecodeError:
                # Registry extent should prevent this; record and carry on
                # rather than killing the whole poll for one bad tag.
                value = None
            new_values[tag.id] = value

        with self._state_lock:
            for tag_id, value in new_values.items():
                previous = self._values.get(tag_id, "__unset__")
                if previous == "__unset__":
                    self._values[tag_id] = value
                    self._value_ts[tag_id] = now
                    continue
                if previous != value:
                    changes.append({
                        "tagId": tag_id,
                        "previous": previous,
                        "value": value,
                        "at": now,
                    })
                    self._values[tag_id] = value
                    self._value_ts[tag_id] = now

            self._buffers = buffers

        return changes

    def _publish(self, changes: List[dict]) -> None:
        snapshot = self.snapshot()
        for fn in self._change_listeners:
            try:
                fn(changes, snapshot)
            except Exception:
                log.exception("change listener failed")
        if self._on_snapshot:
            try:
                self._on_snapshot(snapshot)
            except Exception:
                log.exception("snapshot callback failed")

    # ------------------------------------------------------------------
    # reads (called from HTTP threads -- cache only, never the PLC)
    # ------------------------------------------------------------------

    def value(self, tag_id: str, default: Any = None) -> Any:
        with self._state_lock:
            return self._values.get(tag_id, default)

    def role_value(self, role: str, default: Any = None) -> Any:
        tag = self.registry.role(role)
        return default if tag is None else self.value(tag.id, default)

    def values(self) -> Dict[str, Any]:
        with self._state_lock:
            return dict(self._values)

    def value_timestamps(self) -> Dict[str, float]:
        with self._state_lock:
            return dict(self._value_ts)

    @property
    def connection(self) -> str:
        return self._connection

    @property
    def is_live(self) -> bool:
        return self._connection in (CONN_CONNECTED, CONN_DEGRADED, CONN_SIMULATED)

    def stale_seconds(self) -> float:
        if not self._health.last_success:
            return float("inf")
        return time.time() - self._health.last_success

    def snapshot(self) -> dict:
        with self._state_lock:
            return {
                "connection": self._connection,
                "simulated": self.simulate,
                "health": self._health.to_dict(),
                "staleSeconds": round(self.stale_seconds(), 2)
                if self._health.last_success
                else None,
                "values": dict(self._values),
                "commands": [c.to_dict() for c in self._recent_commands[-40:]],
                "inflight": len(self._inflight) + len(self._write_queue),
            }

    # ------------------------------------------------------------------
    # writes
    # ------------------------------------------------------------------

    def submit_write(
        self,
        tag: Tag,
        value: Any,
        source: str,
        operator: str = "local",
    ) -> Command:
        """
        Queue a validated write. Returns immediately with a PENDING command;
        the caller polls ``command(id)`` or watches the stream for the outcome.

        Validation of *permission* (mode, interlocks, ownership) belongs to
        services/safety.py and must have happened before this is called.
        """
        coerced = codec.coerce(value, tag.dtype)

        with self._state_lock:
            self._command_seq += 1
            cmd = Command(
                id="cmd-%d" % self._command_seq,
                tag_id=tag.id,
                address=tag.address,
                requested=coerced,
                dtype=tag.dtype,
                source=source,
                operator=operator,
            )
            if not self.is_live:
                cmd.state = CMD_REJECTED
                cmd.error = "PLC is %s -- writes are blocked" % self._connection
                cmd.settled_at = time.time()
                self._remember(cmd)
                return cmd

            self._write_queue.append(cmd)
            self._inflight[cmd.id] = cmd
            self._remember(cmd)

        return cmd

    def _remember(self, cmd: Command) -> None:
        self._recent_commands.append(cmd)
        if len(self._recent_commands) > 400:
            del self._recent_commands[:-200]

    def _drain_write_queue(self) -> None:
        with self._state_lock:
            batch, self._write_queue = self._write_queue, []

        for cmd in batch:
            tag = self.registry.get(cmd.tag_id)
            if tag is None:
                cmd.state = CMD_FAILED
                cmd.error = "tag disappeared from registry"
                cmd.settled_at = time.time()
                self._inflight.pop(cmd.id, None)
                continue
            self._execute_write(cmd, tag)

    def _execute_write(self, cmd: Command, tag: Tag) -> None:
        try:
            if self.simulate:
                self._simulate_write(tag, cmd.requested)
            else:
                with self._io_lock:
                    if tag.dtype == "Bool":
                        # Read-modify-write a single byte. Safe here because
                        # this runs on the worker thread, so no concurrent
                        # read of the same byte can interleave.
                        current = bytearray(self._client.db_read(tag.db, tag.byte, 1))
                        current[0] = codec.set_bit(current[0], tag.bit, bool(cmd.requested))
                        self._client.db_write(tag.db, tag.byte, current)
                    else:
                        payload = codec.encode(cmd.requested, tag.dtype)
                        self._client.db_write(tag.db, tag.byte, payload)

            cmd.state = CMD_WRITTEN
            cmd.written_at = time.time()
            cmd.confirm_deadline = cmd.written_at + self.confirm_timeout
            log.debug("wrote %s = %r (%s)", tag.address, cmd.requested, cmd.source)

        except Exception as exc:
            cmd.state = CMD_FAILED
            cmd.error = str(exc)
            cmd.settled_at = time.time()
            self._inflight.pop(cmd.id, None)
            self._health.last_error = str(exc)
            log.warning("write to %s failed: %s", tag.address, exc)
            self._disconnect()

    def _simulate_write(self, tag: Tag, value: Any) -> None:
        """Apply a write to the in-memory buffer so sim mode round-trips."""
        buf = self._buffers.setdefault(
            tag.db, bytearray(self.registry.db_extents.get(tag.db, 512))
        )
        if tag.dtype == "Bool":
            buf[tag.byte] = codec.set_bit(buf[tag.byte], tag.bit, bool(value))
        else:
            payload = codec.encode(value, tag.dtype)
            buf[tag.byte:tag.byte + len(payload)] = payload

    def _settle_commands(self) -> None:
        """
        Confirm or fail in-flight writes against the value just read back.

        This is what makes 'PLC confirmed' mean something. A command only
        reaches CONFIRMED after an independent read observed the value.
        """
        if not self._inflight:
            return

        now = time.time()
        with self._state_lock:
            for cmd_id, cmd in list(self._inflight.items()):
                if cmd.state != CMD_WRITTEN:
                    continue

                observed = self._values.get(cmd.tag_id)
                cmd.observed = observed

                if codec.value_equal(cmd.requested, observed, cmd.dtype):
                    cmd.state = CMD_CONFIRMED
                    cmd.settled_at = now
                    self._inflight.pop(cmd_id, None)
                elif now >= cmd.confirm_deadline:
                    # The write went out but the PLC does not hold the value.
                    # Almost always means PLC logic is actively driving that
                    # bit -- exactly what the operator needs to be told.
                    cmd.state = CMD_MISMATCH
                    cmd.settled_at = now
                    cmd.error = (
                        "wrote %r, PLC still reads %r after %.1fs -- the PLC "
                        "program is probably driving this address"
                        % (cmd.requested, observed, self.confirm_timeout)
                    )
                    self._inflight.pop(cmd_id, None)

    def _fail_inflight(self, reason: str) -> None:
        now = time.time()
        with self._state_lock:
            for cmd_id, cmd in list(self._inflight.items()):
                cmd.state = CMD_TIMEOUT
                cmd.error = reason
                cmd.settled_at = now
                self._inflight.pop(cmd_id, None)

    def command(self, command_id: str) -> Optional[Command]:
        with self._state_lock:
            for cmd in reversed(self._recent_commands):
                if cmd.id == command_id:
                    return cmd
        return None

    def recent_commands(self, limit: int = 50) -> List[dict]:
        with self._state_lock:
            return [c.to_dict() for c in self._recent_commands[-limit:]][::-1]
