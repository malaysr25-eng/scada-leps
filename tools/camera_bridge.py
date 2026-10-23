#!/usr/bin/env python
"""
Camera / YOLO detection bridge.

Runs the existing detector in its own process and publishes results as JSON for
the backend to read. This is a refactor of ``Final/camera_yolo.py``, not a
rewrite: the model, the confidence handling and the column-counting logic are
unchanged. What changed is everything around them.

WHAT WAS FIXED, AND WHY EACH MATTERS
------------------------------------
1. **Atomic writes.** The original did ``open(path,'w')`` then ``json.dump``
   on every single frame. A reader landing between the truncate and the flush
   got a partial file and a JSONDecodeError. In the legacy SCADA that surfaced
   as every tag briefly reading OFF, because ``load_plc_data`` caught the
   exception and returned empty dicts. Here every file is written to a temp
   file in the same directory and then ``os.replace``d, which is atomic on
   Windows and POSIX alike.

2. **A heartbeat.** The original wrote no timestamp the consumer could trust,
   so a detector process that died three hours ago was indistinguishable from
   a live one -- its last JSON just sat there looking current. Every payload
   now carries an ``epoch`` field, and the backend marks the feed STALE past a
   configurable age.

3. **Throttled writes.** The original wrote two JSON files per frame, as fast
   as the camera produced frames. Writing ~60 files/second to publish data a
   4 Hz UI consumes is pure disk churn. Writes are now rate-limited, while
   inference still runs at full speed.

4. **Survivable failure.** A camera unplugged mid-run raised and killed the
   process. It now backs off and retries, publishing an explicit offline
   status in the meantime.

5. **Headless by default.** ``cv2.imshow`` requires a desktop session, which a
   lab PC running this as a service may not have. The preview window is opt-in
   via ``--show``.

USAGE
-----
    python tools/camera_bridge.py                     # default config paths
    python tools/camera_bridge.py --show              # with preview window
    python tools/camera_bridge.py --source 1          # a different camera
    python tools/camera_bridge.py --simulate          # no camera, synthetic data

``--simulate`` exists so the camera panel and the magazine mismatch logic can
be exercised without hardware.
"""

from __future__ import annotations

import argparse
import json
import os
import random
import signal
import sys
import time
from typing import Any, Dict, List, Optional

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_CONFIG = os.path.join(HERE, "config", "config.json")

_running = True


def _stop(_signum, _frame):
    global _running
    _running = False


def atomic_write_json(path: str, payload: Dict[str, Any]) -> None:
    """
    Write JSON so a concurrent reader never sees a partial file.

    The temp file must live in the same directory as the target: os.replace is
    only atomic within a single filesystem.
    """
    directory = os.path.dirname(os.path.abspath(path))
    os.makedirs(directory, exist_ok=True)
    tmp = os.path.join(directory, ".%s.tmp" % os.path.basename(path))

    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, allow_nan=False)
        fh.flush()
        os.fsync(fh.fileno())

    os.replace(tmp, path)


class Publisher:
    """Rate-limited, atomic publisher for the two JSON bridge files."""

    def __init__(self, detections_path: str, counts_path: str, interval: float):
        self.detections_path = detections_path
        self.counts_path = counts_path
        self.interval = interval
        self._last = 0.0

    def due(self) -> bool:
        return (time.monotonic() - self._last) >= self.interval

    def publish(
        self,
        objects: List[dict],
        counts: List[int],
        status: str,
        error: str = "",
    ) -> None:
        now = time.time()
        atomic_write_json(self.detections_path, {
            "epoch": now,
            "timestamp": time.strftime("%Y-%m-%d %H:%M:%S", time.localtime(now)),
            "status": status,
            "error": error,
            "total_objects": len(objects),
            "objects": objects,
        })
        atomic_write_json(self.counts_path, {
            "epoch": now,
            **{"c%d" % (i + 1): c for i, c in enumerate(counts)},
        })
        self._last = time.monotonic()


def load_paths(config_path: str) -> Dict[str, str]:
    with open(config_path, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)

    cam = cfg.get("camera", {})

    def resolve(p: str) -> str:
        return p if os.path.isabs(p) else os.path.normpath(os.path.join(HERE, p))

    return {
        "detections": resolve(cam.get("detections_path", "data/camera_detections.json")),
        "counts": resolve(cam.get("counts_path", "data/camera_counts.json")),
    }


# ---------------------------------------------------------------------------
# simulated source -- no camera required
# ---------------------------------------------------------------------------

def run_simulated(publisher: Publisher, columns: int) -> int:
    print("Camera bridge running in SIMULATED mode (no camera, synthetic data).")
    levels = [random.randint(1, 6) for _ in range(columns)]
    last_drain = time.monotonic()

    while _running:
        if time.monotonic() - last_drain > 12:
            # Slowly deplete a magazine so the empty/low logic gets exercised.
            candidates = [i for i, v in enumerate(levels) if v > 0]
            if candidates:
                levels[random.choice(candidates)] -= 1
            last_drain = time.monotonic()

        if publisher.due():
            objects = []
            for col, count in enumerate(levels):
                for n in range(count):
                    x = col * 180 + 20
                    y = 60 + n * 40
                    objects.append({
                        "class": "wood_block",
                        "confidence": round(random.uniform(0.45, 0.95), 2),
                        "bbox": [x, y, x + 140, y + 32],
                    })
            publisher.publish(objects, levels, "SIMULATED")

        time.sleep(0.1)

    return 0


# ---------------------------------------------------------------------------
# real camera
# ---------------------------------------------------------------------------

def run_camera(
    publisher: Publisher,
    model_path: str,
    source: int,
    confidence: float,
    columns: int,
    frame_w: int,
    frame_h: int,
    show: bool,
) -> int:
    try:
        import cv2
        from ultralytics import YOLO
    except ImportError as exc:
        print("Missing dependency: %s" % exc, file=sys.stderr)
        print(
            "\nInstall the detector dependencies, or run with --simulate:\n"
            "    pip install ultralytics opencv-python\n"
            "    python tools/camera_bridge.py --simulate",
            file=sys.stderr,
        )
        return 2

    if not os.path.exists(model_path):
        print("Model not found: %s" % model_path, file=sys.stderr)
        return 2

    print("Loading model: %s" % model_path)
    model = YOLO(model_path)

    cap: Optional[Any] = None
    col_w = frame_w // columns
    backoff = 1.0

    while _running:
        # ---- (re)open the camera, with backoff --------------------------
        if cap is None or not cap.isOpened():
            if cap is not None:
                cap.release()
            cap = cv2.VideoCapture(source, cv2.CAP_DSHOW)
            if not cap.isOpened():
                print("Camera %s unavailable; retrying in %.0fs" % (source, backoff))
                publisher.publish([], [0] * columns, "OFFLINE",
                                  "camera %s could not be opened" % source)
                time.sleep(backoff)
                backoff = min(backoff * 1.6, 15.0)
                continue
            print("Camera %s opened." % source)
            backoff = 1.0

        ok, frame = cap.read()
        if not ok:
            # A dropped frame is normal; a run of them means the camera went
            # away. Either way, do not crash the process.
            publisher.publish([], [0] * columns, "DEGRADED", "frame read failed")
            cap.release()
            cap = None
            time.sleep(0.5)
            continue

        frame = cv2.resize(frame, (frame_w, frame_h))
        results = model(frame, conf=confidence, verbose=False)[0]

        objects: List[dict] = []
        counts = [0] * columns

        if results.boxes is not None:
            for box in results.boxes:
                cls_id = int(box.cls[0])
                x1, y1, x2, y2 = map(int, box.xyxy[0])
                objects.append({
                    "class": model.names[cls_id],
                    "confidence": round(float(box.conf[0]), 3),
                    "bbox": [x1, y1, x2, y2],
                })
                col = ((x1 + x2) // 2) // col_w
                if 0 <= col < columns:
                    counts[col] += 1
                if show:
                    cv2.rectangle(frame, (x1, y1), (x2, y2), (0, 255, 0), 2)

        # Inference runs every frame; publishing is throttled.
        if publisher.due():
            publisher.publish(objects, counts, "ONLINE")

        if show:
            for i, c in enumerate(counts):
                cv2.putText(frame, "C%d: %d" % (i + 1, c),
                            (i * col_w + 16, 36), cv2.FONT_HERSHEY_SIMPLEX,
                            0.9, (0, 255, 0), 2)
            cv2.imshow("Camera bridge", frame)
            if cv2.waitKey(1) == 27:
                break

    if cap is not None:
        cap.release()
    if show:
        cv2.destroyAllWindows()
    return 0


# ---------------------------------------------------------------------------

def main() -> int:
    parser = argparse.ArgumentParser(description="Camera / YOLO detection bridge")
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument(
        "--model",
        default=os.path.join(HERE, "..", "Final", "runs", "detect", "train3", "weights", "best.pt"),
        help="Path to the trained YOLO weights.",
    )
    parser.add_argument("--source", type=int, default=0, help="Camera index.")
    parser.add_argument(
        "--confidence", type=float, default=0.25,
        help="Detection threshold. The legacy script used 0.05, which produced "
             "many spurious boxes; the backend also applies its own display "
             "threshold. See DEBUGGING_REPORT.md E-01.",
    )
    parser.add_argument("--columns", type=int, default=5)
    parser.add_argument("--width", type=int, default=900)
    parser.add_argument("--height", type=int, default=600)
    parser.add_argument(
        "--publish-interval", type=float, default=0.5,
        help="Seconds between JSON publishes. Inference is not throttled.",
    )
    parser.add_argument("--show", action="store_true", help="Show a preview window.")
    parser.add_argument("--simulate", action="store_true",
                        help="Synthetic detections; no camera or model needed.")
    args = parser.parse_args()

    signal.signal(signal.SIGINT, _stop)
    try:
        signal.signal(signal.SIGTERM, _stop)
    except (AttributeError, ValueError):
        pass

    if not os.path.exists(args.config):
        print("Config not found: %s" % args.config, file=sys.stderr)
        return 2

    paths = load_paths(args.config)
    publisher = Publisher(paths["detections"], paths["counts"], args.publish_interval)

    print("Publishing to:")
    print("  %s" % paths["detections"])
    print("  %s" % paths["counts"])

    try:
        if args.simulate:
            return run_simulated(publisher, args.columns)
        return run_camera(
            publisher,
            os.path.normpath(args.model),
            args.source,
            args.confidence,
            args.columns,
            args.width,
            args.height,
            args.show,
        )
    finally:
        # Mark the feed offline on the way out, so the HMI shows the detector
        # stopped rather than leaving a stale payload looking current.
        try:
            publisher.publish([], [0] * args.columns, "OFFLINE", "bridge stopped")
        except Exception:
            pass
        print("\nCamera bridge stopped.")


if __name__ == "__main__":
    raise SystemExit(main())
