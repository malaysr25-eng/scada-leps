"""
MATLAB / Simulink adapter.

CHOOSING A TRANSPORT — AND WHY THREE
------------------------------------
The brief says not to pick an integration method blindly, so here is the
reasoning rather than a bare choice.

The existing MATLAB integration in this project is a **batch export**:
`run_factory_simulation` solves a whole 31 s cycle with RK4 and returns a LOG
struct; `tools/export_twin_reference.m` dumps it to JSON. That path stays as-is
(see docs/DIGITAL_TWIN.md). What is new here is *live* simulation telemetry,
which the batch model cannot produce.

Rejected outright:

* **MATLAB Engine API for Python** — needs a MATLAB licence installed on the
  control PC and pulls a heavyweight process into the control path. It also
  cannot step the batch solver, so it would not actually deliver live data.
* **MQTT** — a broker to install, run and administer on a lab machine, for a
  single point-to-point link.
* **Simulink Real-Time / Coder** — forks the execution paths the simulation
  project works hard to keep bit-identical.

Implemented, all behind the same adapter so the core never knows which is in
use:

| transport | how MATLAB pushes | when to use |
|---|---|---|
| ``file`` | ``jsonencode`` + write + ``movefile`` (atomic) | offline PC, no networking, mirrors the camera bridge already in this project |
| ``tcp``  | ``tcpclient`` writing newline-delimited JSON | live streaming from a running Simulink model |
| ``mock`` | nothing — synthetic data generated here | development and CI, with no MATLAB anywhere |

`file` is the default because it needs no ports, survives either side
restarting, and is the pattern already proven by `tools/camera_bridge.py`.

HONESTY ABOUT WHAT HAS BEEN TESTED
----------------------------------
The `mock` transport is exercised by the self-test suite. The `file` transport
is exercised against a fixture written by `tools/matlab_sim_bridge.py`.

**The `tcp` transport and both real-MATLAB paths have NOT been tested against an
actual MATLAB or Simulink installation**, because no MATLAB licence is available
in this environment. The wire format is documented in
`tools/matlab_live_bridge.m` and is deliberately trivial — one JSON object per
line — but it is unverified against the real thing. Do not treat it as proven.

SAFETY
------
`supports_control` is **False**. This adapter can never become the active
control source, so a simulation value can never be written to the real PLC.
That is enforced in `SourceManager.set_control_source`, not merely documented.
"""

from __future__ import annotations

import json
import logging
import math
import os
import socket
import threading
import time
from typing import Any, Dict, Optional

from backend.sources.base import (
    KIND_SIMULATION,
    QUALITY_BAD,
    QUALITY_GOOD,
    QUALITY_STALE,
    QUALITY_UNCERTAIN,
    SRC_CONNECTED,
    SRC_DEGRADED,
    SRC_DISCONNECTED,
    SRC_ERROR,
    SRC_STOPPED,
    DataSourceAdapter,
    Sample,
    SourceStatus,
    samples_from,
)

log = logging.getLogger("src.matlab")

TRANSPORT_FILE = "file"
TRANSPORT_TCP = "tcp"
TRANSPORT_MOCK = "mock"


class MatlabSourceAdapter(DataSourceAdapter):
    source_id = "matlab"
    name = "MATLAB / Simulink"
    kind = KIND_SIMULATION

    # Telemetry only. A simulation must never drive real hardware.
    supports_control = False

    def __init__(self, config: dict, registry=None) -> None:
        super().__init__()
        self.config = config or {}
        self.registry = registry
        self.transport = self.config.get("transport", TRANSPORT_FILE)
        self.enabled = bool(self.config.get("enabled", True))
        self.stale_after = float(self.config.get("stale_after", 5.0))
        self.poll_interval = float(self.config.get("poll_interval", 0.5))

        # file transport
        self.data_path = self.config.get("data_path", "")

        # tcp transport
        self.host = self.config.get("host", "127.0.0.1")
        self.port = int(self.config.get("port", 5560))

        self._lock = threading.RLock()
        self._stop = threading.Event()
        self._worker: Optional[threading.Thread] = None
        self._server: Optional[socket.socket] = None

        self._values: Dict[str, Any] = {}
        self._meta: Dict[str, Any] = {}
        self._last_data_at: Optional[float] = None
        self._state = SRC_STOPPED
        self._last_error = ""
        self._error_count = 0
        self._sequence = 0
        self._running = False
        self._latency_ms = 0.0

    # ------------------------------------------------------------------
    # lifecycle
    # ------------------------------------------------------------------

    def connect(self) -> bool:
        return self.start()

    def start(self) -> bool:
        if not self.enabled:
            self._state = SRC_STOPPED
            self._last_error = "MATLAB source is disabled in config."
            return False

        if self._worker and self._worker.is_alive():
            return True

        self._stop.clear()
        self._worker = threading.Thread(
            target=self._run, name="matlab-source", daemon=True
        )
        self._worker.start()
        self._running = True
        log.info(
            "MATLAB source started (transport=%s%s)",
            self.transport,
            ", port=%d" % self.port if self.transport == TRANSPORT_TCP else "",
        )
        return True

    def stop(self) -> None:
        self._stop.set()
        if self._server is not None:
            try:
                self._server.close()
            except Exception:
                pass
            self._server = None
        if self._worker:
            self._worker.join(timeout=2.0)
        self._running = False
        self._state = SRC_STOPPED
        log.info("MATLAB source stopped")

    def disconnect(self) -> None:
        self.stop()

    # ------------------------------------------------------------------
    # worker
    # ------------------------------------------------------------------

    def _run(self) -> None:
        try:
            if self.transport == TRANSPORT_MOCK:
                self._run_mock()
            elif self.transport == TRANSPORT_TCP:
                self._run_tcp()
            else:
                self._run_file()
        except Exception as exc:
            log.exception("MATLAB source worker died")
            self._state = SRC_ERROR
            self._last_error = str(exc)
            self._error_count += 1

    # -- file -----------------------------------------------------------

    def _run_file(self) -> None:
        """
        Poll a JSON file MATLAB writes atomically.

        MATLAB side (see tools/matlab_live_bridge.m):

            fid = fopen(tmp,'w'); fwrite(fid, jsonencode(payload)); fclose(fid);
            movefile(tmp, target);      % atomic rename

        The rename matters: without it a reader lands mid-write and gets a
        truncated file. That exact defect is what made the legacy SCADA blank
        every tag for a frame.
        """
        if not self.data_path:
            self._state = SRC_ERROR
            self._last_error = "matlab.data_path is not configured."
            return

        last_mtime = 0.0
        while not self._stop.is_set():
            started = time.monotonic()
            try:
                if os.path.exists(self.data_path):
                    mtime = os.path.getmtime(self.data_path)
                    if mtime != last_mtime:
                        with open(self.data_path, "r", encoding="utf-8") as fh:
                            payload = json.load(fh)
                        self._ingest(payload)
                        last_mtime = mtime
                    elif self._last_data_at is not None:
                        self._refresh_state()
                else:
                    self._state = SRC_DISCONNECTED
                    self._last_error = "Waiting for %s" % self.data_path
            except (json.JSONDecodeError, OSError) as exc:
                # A malformed or half-written file is expected occasionally.
                # Keep the previous good values; do not blank the feed.
                self._error_count += 1
                self._last_error = str(exc)
                self._state = SRC_DEGRADED

            self._latency_ms = (time.monotonic() - started) * 1000.0
            self._stop.wait(self.poll_interval)

    # -- tcp ------------------------------------------------------------

    def _run_tcp(self) -> None:
        """
        Listen for a MATLAB `tcpclient` streaming newline-delimited JSON.

        UNTESTED against a real MATLAB session -- see the module docstring.
        """
        while not self._stop.is_set():
            try:
                self._server = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
                self._server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
                self._server.settimeout(1.0)
                self._server.bind((self.host, self.port))
                self._server.listen(1)
                self._state = SRC_DISCONNECTED
                self._last_error = "Listening on %s:%d for MATLAB" % (self.host, self.port)
                log.info("MATLAB TCP listener on %s:%d", self.host, self.port)

                while not self._stop.is_set():
                    try:
                        conn, addr = self._server.accept()
                    except socket.timeout:
                        continue
                    log.info("MATLAB connected from %s", addr)
                    self._serve_connection(conn)

            except OSError as exc:
                self._state = SRC_ERROR
                self._last_error = str(exc)
                self._error_count += 1
                log.warning("MATLAB TCP listener error: %s", exc)
                self._stop.wait(3.0)
            finally:
                if self._server is not None:
                    try:
                        self._server.close()
                    except Exception:
                        pass
                    self._server = None

    def _serve_connection(self, conn: socket.socket) -> None:
        conn.settimeout(1.0)
        buffer = b""
        try:
            while not self._stop.is_set():
                try:
                    chunk = conn.recv(65536)
                except socket.timeout:
                    self._refresh_state()
                    continue
                if not chunk:
                    break
                buffer += chunk
                while b"\n" in buffer:
                    line, buffer = buffer.split(b"\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        self._ingest(json.loads(line.decode("utf-8")))
                    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
                        self._error_count += 1
                        self._last_error = "bad frame: %s" % exc
        except OSError as exc:
            self._last_error = str(exc)
            self._error_count += 1
        finally:
            try:
                conn.close()
            except Exception:
                pass
            self._state = SRC_DISCONNECTED
            log.info("MATLAB disconnected")

    # -- mock -----------------------------------------------------------

    def _run_mock(self) -> None:
        """
        Synthetic telemetry, clearly labelled.

        Exists so the source manager, the mode UI, the recording pipeline and
        the 3-D twin can all be exercised with no MATLAB present. Every payload
        carries `synthetic: true`, and the UI renders the source name with a
        MOCK badge, so this cannot be mistaken for model output.
        """
        t0 = time.monotonic()
        cycle_time = float(self.config.get("mock_cycle_seconds", 31.08))

        while not self._stop.is_set():
            t = (time.monotonic() - t0) % cycle_time
            phase = t / cycle_time

            payload = {
                "timestamp": time.time(),
                "synthetic": True,
                "cycleTime": cycle_time,
                "elapsed": round(t, 3),
                "values": {
                    "sim.belt1_speed": round(0.15 * _pulse(phase, 0.10, 0.22), 5),
                    "sim.belt2_speed": round(0.15 * _pulse(phase, 0.34, 0.46), 5),
                    "sim.belt3_speed": round(0.15 * _pulse(phase, 0.78, 0.90), 5),
                    "sim.receiver_pressure": round(5.5 - 0.9 * phase, 4),
                    "sim.base_z": round(0.12 * _pulse(phase, 0.50, 0.72), 5),
                    "sim.block_x": round(1.5 * phase, 5),
                    "sim.rod1": round(_pulse(phase, 0.06, 0.12), 4),
                    "sim.rod2": round(_pulse(phase, 0.30, 0.36), 4),
                    "sim.rod3": round(_pulse(phase, 0.46, 0.52), 4),
                    "sim.rod4": round(_pulse(phase, 0.74, 0.80), 4),
                    "sim.rod5": round(_pulse(phase, 0.92, 0.98), 4),
                    "sim.cycle_phase": round(phase, 4),
                },
            }
            self._ingest(payload)
            self._stop.wait(self.poll_interval)

    # ------------------------------------------------------------------
    # ingestion
    # ------------------------------------------------------------------

    def _ingest(self, payload: dict) -> None:
        """
        Accept a payload from any transport.

        Two accepted shapes, because MATLAB users will reasonably produce
        either:

            {"values": {"name": 1.0, ...}, "timestamp": 1.7e9}
            {"name": 1.0, ...}                    # flat, timestamp optional
        """
        if not isinstance(payload, dict):
            self._last_error = "payload is not an object"
            self._error_count += 1
            return

        values = payload.get("values")
        if not isinstance(values, dict):
            values = {
                k: v for k, v in payload.items()
                if isinstance(v, (int, float, bool)) and k not in ("timestamp", "epoch")
            }

        ts = payload.get("timestamp") or payload.get("epoch") or time.time()
        try:
            ts = float(ts)
        except (TypeError, ValueError):
            ts = time.time()

        with self._lock:
            self._values = dict(values)
            self._meta = {
                k: v for k, v in payload.items() if k not in ("values",)
            }
            self._last_data_at = ts
            self._sequence += 1
            self._state = SRC_CONNECTED
            self._last_error = ""

    def _refresh_state(self) -> None:
        """Downgrade state when data stops arriving, without clearing values."""
        if self._last_data_at is None:
            self._state = SRC_DISCONNECTED
            return
        if (time.time() - self._last_data_at) > self.stale_after:
            self._state = SRC_DEGRADED

    # ------------------------------------------------------------------
    # contract
    # ------------------------------------------------------------------

    def _quality(self) -> str:
        with self._lock:
            if self._last_data_at is None:
                return QUALITY_BAD
            age = time.time() - self._last_data_at
            if self._state == SRC_ERROR:
                return QUALITY_BAD
            if age > self.stale_after:
                return QUALITY_STALE
            if self._state == SRC_DEGRADED:
                return QUALITY_UNCERTAIN
            return QUALITY_GOOD

    def get_status(self) -> SourceStatus:
        with self._lock:
            return SourceStatus(
                source_id=self.source_id,
                name=self.name + (" [MOCK]" if self.transport == TRANSPORT_MOCK else ""),
                kind=self.kind,
                state=self._state,
                connected=self._state == SRC_CONNECTED,
                running=self._running,
                last_data_at=self._last_data_at,
                last_error=self._last_error,
                error_count=self._error_count,
                latency_ms=self._latency_ms,
                sequence=self._sequence,
                stale_after=self.stale_after,
                can_control=False,
                available=self.enabled,
                unavailable_reason=(
                    "" if self.enabled else "Disabled in config (sources.matlab.enabled)"
                ),
                detail={
                    "transport": self.transport,
                    "synthetic": self.transport == TRANSPORT_MOCK
                    or bool(self._meta.get("synthetic")),
                    "dataPath": self.data_path if self.transport == TRANSPORT_FILE else None,
                    "endpoint": (
                        "%s:%d" % (self.host, self.port)
                        if self.transport == TRANSPORT_TCP else None
                    ),
                    "signalCount": len(self._values),
                    "meta": {
                        k: v for k, v in self._meta.items()
                        if k in ("cycleTime", "elapsed", "modelName", "simTime", "synthetic")
                    },
                    "controlNote": (
                        "Telemetry only. A simulation source can never become the "
                        "active control source, so its values cannot reach the PLC."
                    ),
                },
            )

    def read_latest(self) -> Dict[str, Sample]:
        with self._lock:
            values = dict(self._values)
            ts = self._last_data_at or 0.0
            seq = self._sequence
        return samples_from(values, self.source_id, self._quality(), ts, seq)

    def read_raw(self) -> Dict[str, Any]:
        with self._lock:
            return dict(self._values)

    def send_command(self, tag_id: str, value: Any, **kwargs) -> tuple:
        return False, (
            "MATLAB/Simulink is a telemetry source. It cannot accept commands, "
            "and it can never become the active control source."
        )


def _pulse(phase: float, start: float, end: float) -> float:
    """Smooth 0→1→0 bump between two cycle fractions. Mock data only."""
    if phase < start or phase > end:
        return 0.0
    span = max(end - start, 1e-9)
    return math.sin(math.pi * (phase - start) / span)
