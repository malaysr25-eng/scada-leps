"""
Camera / YOLO adapter.

The detector stays in its own OS process. This module only *reads* what that
process publishes, so a slow inference pass, a dropped USB camera or a crashed
ultralytics import can never stall the PLC poll loop -- which is the single
most important property here.

TRANSPORT
---------
The detector writes one JSON file; this reads it. That was already the shape of
the legacy system, and it is genuinely the right call for a lab PC: no broker,
no socket to leak, and the detector can be restarted independently.

What is fixed relative to the legacy version:

* **Atomic writes.** ``camera_yolo.py`` did ``open(path,'w')`` + ``json.dump``
  every frame. A reader landing between truncate and flush got a partial file
  and a JSONDecodeError. ``tools/camera_bridge.py`` writes to a temp file and
  ``os.replace``s it, which is atomic on Windows and POSIX alike.
* **Staleness is detected.** The legacy SCADA had no way to tell a live camera
  from one whose process died three hours ago holding the last JSON. Anything
  older than ``stale_after`` is reported OFFLINE and its counts are withheld
  rather than shown as current.
* **Read failures are survivable.** A malformed file yields the previous good
  payload plus a warning, not an exception into the request handler.
"""

from __future__ import annotations

import json
import os
import re
import threading
import time
from typing import Any, Dict, List, Optional

# Magazine column keys in the counts payload: c1, c2, ... Anything else in the
# file (the epoch heartbeat) is metadata, not a magazine.
_COLUMN_KEY = re.compile(r"^c\d+$")

OFFLINE = "OFFLINE"
ONLINE = "ONLINE"
STALE = "STALE"
DEGRADED = "DEGRADED"


class CameraService:
    def __init__(self, config: dict, event_log) -> None:
        self.events = event_log
        self.detections_path = config.get("detections_path", "")
        self.counts_path = config.get("counts_path", "")
        self.frame_path = config.get("frame_path", "")
        self.stale_after = float(config.get("stale_after", 5.0))
        self.poll_interval = float(config.get("poll_interval", 1.0))
        self.min_confidence = float(config.get("min_confidence", 0.25))

        self._lock = threading.RLock()
        self._stop = threading.Event()
        self._worker: Optional[threading.Thread] = None

        self._detections: Dict[str, Any] = {}
        self._counts: Dict[str, Any] = {}
        self._last_good: Optional[float] = None
        self._last_error = ""
        self._status = OFFLINE
        self._read_errors = 0
        self._announced_offline = False

    # ------------------------------------------------------------------

    def start(self) -> None:
        if self._worker and self._worker.is_alive():
            return
        self._stop.clear()
        self._worker = threading.Thread(
            target=self._run, name="camera-reader", daemon=True
        )
        self._worker.start()

    def stop(self, timeout: float = 2.0) -> None:
        self._stop.set()
        if self._worker:
            self._worker.join(timeout=timeout)

    def _run(self) -> None:
        while not self._stop.is_set():
            self._refresh()
            self._stop.wait(self.poll_interval)

    # ------------------------------------------------------------------

    @staticmethod
    def _read_json(path: str) -> Optional[dict]:
        if not path or not os.path.exists(path):
            return None
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)

    def _refresh(self) -> None:
        detections = None
        counts = None
        error = ""

        try:
            detections = self._read_json(self.detections_path)
        except (json.JSONDecodeError, OSError) as exc:
            error = "detections: %s" % exc

        try:
            counts = self._read_json(self.counts_path)
        except (json.JSONDecodeError, OSError) as exc:
            error = (error + "; " if error else "") + "counts: %s" % exc

        now = time.time()
        with self._lock:
            if detections is not None:
                self._detections = detections
            if counts is not None:
                self._counts = counts

            if error:
                self._read_errors += 1
                self._last_error = error
            else:
                self._last_error = ""

            # Prefer the timestamp the detector stamped; fall back to mtime.
            produced_at = self._payload_timestamp(detections)
            if produced_at is None and self.detections_path:
                try:
                    produced_at = os.path.getmtime(self.detections_path)
                except OSError:
                    produced_at = None

            if produced_at is not None:
                self._last_good = produced_at

            previous = self._status
            if self._last_good is None:
                self._status = OFFLINE
            elif now - self._last_good > self.stale_after:
                self._status = STALE
            elif error:
                self._status = DEGRADED
            else:
                self._status = ONLINE

            if previous != self._status:
                self._announce(previous, self._status)

    def _announce(self, previous: str, current: str) -> None:
        if current == ONLINE:
            self.events.info("camera", "Camera detection service is online.")
        elif current in (STALE, OFFLINE) and previous == ONLINE:
            self.events.warning(
                "camera",
                "Camera detection service went %s -- no fresh frame for more "
                "than %.0f s. Magazine counts are withheld." % (current, self.stale_after),
            )

    @staticmethod
    def _payload_timestamp(payload: Optional[dict]) -> Optional[float]:
        if not payload:
            return None
        # The bridge writes an epoch float; the legacy file wrote a local string.
        if isinstance(payload.get("epoch"), (int, float)):
            return float(payload["epoch"])
        raw = payload.get("timestamp")
        if isinstance(raw, (int, float)):
            return float(raw)
        if isinstance(raw, str):
            for fmt in ("%Y-%m-%d %H:%M:%S", "%Y-%m-%dT%H:%M:%S"):
                try:
                    return time.mktime(time.strptime(raw, fmt))
                except ValueError:
                    continue
        return None

    # ------------------------------------------------------------------

    @property
    def online(self) -> bool:
        return self._status == ONLINE

    def counts(self) -> Dict[str, Any]:
        """
        Magazine counts, or empty when the feed is not trustworthy.

        Only ``cN`` keys are returned. The payload also carries an ``epoch``
        heartbeat, and passing that through unfiltered would render it as a
        sixth magazine holding 1.7 billion blocks.
        """
        with self._lock:
            if self._status != ONLINE:
                return {}
            return {
                k: v for k, v in self._counts.items()
                if _COLUMN_KEY.match(k)
            }

    def state(self) -> dict:
        with self._lock:
            detections = self._detections or {}
            objects: List[dict] = detections.get("objects", []) or []
            confident = [
                o for o in objects
                if float(o.get("confidence", 0)) >= self.min_confidence
            ]
            classes: Dict[str, int] = {}
            for o in objects:
                classes[o.get("class", "unknown")] = classes.get(o.get("class", "unknown"), 0) + 1

            age = None if self._last_good is None else round(time.time() - self._last_good, 2)

            return {
                "status": self._status,
                "online": self._status == ONLINE,
                "lastFrameAt": self._last_good,
                "frameAgeSeconds": age,
                "staleAfterSeconds": self.stale_after,
                "lastError": self._last_error,
                "readErrors": self._read_errors,
                "totalObjects": len(objects),
                "confidentObjects": len(confident),
                "minConfidence": self.min_confidence,
                "classes": classes,
                "objects": objects[:40],
                "counts": {k: v for k, v in self._counts.items()
                           if _COLUMN_KEY.match(k)} if self._status == ONLINE else {},
                "framePath": self.frame_path or None,
                "detectionsPath": self.detections_path,
                "note": (
                    "Detection confidence in the shipped model is low "
                    "(camera_yolo.py ran at conf=0.05). Counts are indicative, "
                    "not authoritative -- see DEBUGGING_REPORT.md E-01."
                ),
            }
