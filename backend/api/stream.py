"""
Server-Sent Events: the push channel that replaces browser polling.

WHY SSE AND NOT WEBSOCKETS
--------------------------
The data flow here is strictly one-directional -- the PLC pushes state, the
browser sends commands over ordinary REST. SSE covers that exactly, works on
plain threaded Flask with no eventlet/gevent monkey-patching, and the browser's
own ``EventSource`` reconnects automatically after a dropped connection.

That last property matters more than it sounds: the Errors sheet records
"manually controlled website needed to be refreshed again and again"
(2026-08-14). With EventSource the browser re-establishes the stream by itself
and the UI resumes live updates without anyone touching F5.

BACKPRESSURE
------------
Each subscriber gets a bounded queue. When a browser tab is slow or suspended,
``Core._publish`` drops that subscriber's oldest frame rather than blocking.
The PLC poll loop must never be held up by a browser.
"""

from __future__ import annotations

import json
import logging
import queue
import time

from flask import Blueprint, Response, current_app, stream_with_context

log = logging.getLogger("stream")

stream = Blueprint("stream", __name__, url_prefix="/api")

QUEUE_DEPTH = 4
HEARTBEAT_S = 10.0


@stream.get("/stream")
def state_stream():
    core = current_app.config["CORE"]

    def generate():
        q: "queue.Queue[dict]" = queue.Queue(maxsize=QUEUE_DEPTH)
        core.subscribe(q)
        log.info("SSE subscriber attached (%d total)", core.subscriber_count())

        try:
            # Send the current snapshot immediately so a fresh tab paints at
            # once instead of waiting for the next poll.
            yield _frame("state", core.snapshot())
            last_beat = time.monotonic()

            while True:
                try:
                    snapshot = q.get(timeout=1.0)
                    yield _frame("state", snapshot)
                    last_beat = time.monotonic()
                except queue.Empty:
                    # A comment line keeps proxies from closing an idle stream
                    # and lets the client notice a dead server.
                    if time.monotonic() - last_beat >= HEARTBEAT_S:
                        yield ": heartbeat\n\n"
                        last_beat = time.monotonic()

        except GeneratorExit:
            pass
        except Exception:
            log.exception("SSE generator failed")
        finally:
            core.unsubscribe(q)
            log.info("SSE subscriber detached (%d remain)", core.subscriber_count())

    response = Response(stream_with_context(generate()), mimetype="text/event-stream")
    response.headers["Cache-Control"] = "no-cache, no-transform"
    response.headers["X-Accel-Buffering"] = "no"   # disable nginx buffering
    response.headers["Connection"] = "keep-alive"
    return response


def _frame(event: str, payload: dict) -> str:
    # allow_nan=False: a NaN from an uninitialised PLC Real would emit bare
    # NaN, which JSON.parse rejects, silently killing the stream in the browser.
    body = json.dumps(payload, allow_nan=False, default=_fallback)
    return "event: %s\ndata: %s\n\n" % (event, body)


def _fallback(obj):
    return str(obj)
