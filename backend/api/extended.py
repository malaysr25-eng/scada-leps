"""
Extended API: data sources, persistence, history and the help assistant.

A separate blueprint rather than more routes bolted onto `rest.py`, so the
original endpoints stay exactly as they were. Every route added here is new;
none replaces or shadows an existing one, and the frontend contract for
existing routes is unchanged.

Mounted under the same `/api` prefix.
"""

from __future__ import annotations

import time
from typing import Any

from flask import Blueprint, Response, current_app, jsonify, request

extended = Blueprint("extended", __name__, url_prefix="/api")


def _core():
    return current_app.config["CORE"]


def _ok(payload: Any = None, **extra):
    body = {"ok": True}
    if payload is not None:
        body["data"] = payload
    body.update(extra)
    return jsonify(body)


def _err(code: str, message: str, status: int = 400, **extra):
    return jsonify({"ok": False, "error": {"code": code, "message": message, **extra}}), status


# ===========================================================================
# data sources and operating mode
# ===========================================================================

@extended.get("/sources")
def list_sources():
    core = _core()
    return _ok(core.sources.describe())


@extended.get("/sources/<source_id>")
def get_source(source_id: str):
    adapter = _core().sources.get(source_id)
    if adapter is None:
        return _err("unknown_source", "No data source %r." % source_id, 404)
    return _ok(adapter.describe())


@extended.post("/sources/control")
def set_control_source():
    """
    Hand machine control to one source.

    Refusals are normal: a telemetry-only source can never take control, and a
    disconnected source cannot either. Both are reported with a reason.
    """
    core = _core()
    body = request.get_json(silent=True) or {}
    source_id = body.get("sourceId")
    operator = str(body.get("operator", "local"))

    if source_id is not None and not isinstance(source_id, str):
        return _err("invalid_source", "sourceId must be a string or null.")

    ok, reason = core.sources.set_control_source(source_id, operator)
    if not ok:
        return _err("control_refused", reason, 409)
    return _ok(core.sources.describe())


@extended.post("/sources/telemetry")
def set_telemetry_source():
    """Choose which source feeds the dashboards. Grants no control."""
    core = _core()
    body = request.get_json(silent=True) or {}
    source_id = body.get("sourceId")

    if not source_id:
        return _err("invalid_source", "sourceId is required.")

    ok, reason = core.sources.set_telemetry_source(
        source_id, str(body.get("operator", "local"))
    )
    if not ok:
        return _err("telemetry_refused", reason, 409)
    return _ok(core.sources.describe())


@extended.post("/sources/<source_id>/start")
def start_source(source_id: str):
    adapter = _core().sources.get(source_id)
    if adapter is None:
        return _err("unknown_source", "No data source %r." % source_id, 404)
    started = adapter.start()
    if not started:
        status = adapter.get_status()
        return _err(
            "start_failed",
            status.unavailable_reason or status.last_error or "Could not start.",
            409,
        )
    return _ok(adapter.describe())


@extended.post("/sources/<source_id>/stop")
def stop_source(source_id: str):
    core = _core()
    adapter = core.sources.get(source_id)
    if adapter is None:
        return _err("unknown_source", "No data source %r." % source_id, 404)

    if adapter.is_control_active:
        return _err(
            "is_control_source",
            "%s currently holds machine control. Move control elsewhere before "
            "stopping it." % adapter.name,
            409,
        )
    adapter.stop()
    return _ok(adapter.describe())


@extended.get("/mode")
def get_mode():
    """Everything the UI needs to render the mode banner in one call."""
    core = _core()
    snapshot = core.snapshot()
    sources = snapshot.get("dataSources") or {}
    machine = snapshot.get("machine") or {}
    connection = snapshot.get("connection") or {}

    return _ok({
        "systemMode": sources.get("mode"),
        "controlMode": machine.get("mode"),
        "lifecycle": machine.get("lifecycle"),
        "controlSourceId": sources.get("controlSourceId"),
        "controlSourceName": sources.get("controlSourceName"),
        "telemetrySourceId": sources.get("telemetrySourceId"),
        "telemetrySourceName": sources.get("telemetrySourceName"),
        "lastDataAt": sources.get("lastDataAt"),
        "quality": sources.get("quality"),
        "stale": sources.get("stale"),
        "canControlHardware": sources.get("canControlHardware"),
        "plcConnection": connection.get("plc"),
        "plcSimulated": connection.get("plcSimulated"),
        "transitions": sources.get("transitions", []),
        "allowedControlModes": ["AUTO", "MANUAL", "MAINTENANCE"],
    })


# ===========================================================================
# manual persistence
# ===========================================================================

@extended.post("/data/snapshot")
def save_snapshot():
    core = _core()
    body = request.get_json(silent=True) or {}
    ok, detail = core.recording.save_snapshot(
        core.snapshot(),
        label=str(body.get("label", ""))[:200],
        note=str(body.get("note", ""))[:2000],
        operator=str(body.get("operator", "local")),
        trigger="manual",
    )
    if not ok:
        return _err("snapshot_failed", str(detail), 409)
    return _ok(detail)


@extended.post("/data/recording/start")
def start_recording():
    core = _core()
    body = request.get_json(silent=True) or {}
    snapshot = core.snapshot()
    sources = snapshot.get("dataSources") or {}

    ok, detail = core.recording.start_session(
        label=str(body.get("label", ""))[:200],
        note=str(body.get("note", ""))[:2000],
        operator=str(body.get("operator", "local")),
        sample_interval=body.get("sampleInterval"),
        deadband=body.get("deadband"),
        tag_filter=body.get("tagFilter") or [],
        mode=(snapshot.get("machine") or {}).get("mode", ""),
        source_id=sources.get("telemetrySourceId") or "",
    )
    if not ok:
        return _err("recording_failed", str(detail), 409)
    return _ok(detail)


@extended.post("/data/recording/stop")
def stop_recording():
    core = _core()
    body = request.get_json(silent=True) or {}
    ok, detail = core.recording.stop_session(
        operator=str(body.get("operator", "local"))
    )
    if not ok:
        return _err("no_recording", str(detail), 409)
    return _ok(detail)


@extended.get("/data/recording/status")
def recording_status():
    return _ok(_core().recording.status())


@extended.post("/data/cycle/save")
def save_cycle():
    core = _core()
    body = request.get_json(silent=True) or {}
    ok, detail = core.recording.save_cycle(
        core.snapshot(),
        outcome=str(body.get("outcome", "MANUAL_SAVE")),
        operator=str(body.get("operator", "local")),
        note=str(body.get("note", ""))[:2000],
    )
    if not ok:
        return _err("cycle_save_failed", str(detail), 409)
    return _ok(detail)


@extended.get("/db/status")
def db_status():
    core = _core()
    return _ok({
        "store": core.store.stats(),
        "ingest": core.ingest.describe(),
        "summary": core.queries.summary() if core.store.ready else None,
    })


# ===========================================================================
# historical queries
# ===========================================================================

@extended.get("/history/events")
def history_events():
    q = _core().queries
    return _ok(q.events(
        since=request.args.get("since", type=float),
        until=request.args.get("until", type=float),
        severity=request.args.get("severity"),
        category=request.args.get("category"),
        limit=request.args.get("limit", type=int),
    ))


@extended.get("/history/alarms")
def history_alarms():
    q = _core().queries
    return _ok(q.alarms(
        since=request.args.get("since", type=float),
        active_only=request.args.get("activeOnly") == "true",
        limit=request.args.get("limit", type=int),
    ))


@extended.get("/history/states")
def history_states():
    q = _core().queries
    return _ok(q.state_history(
        kind=request.args.get("kind"),
        since=request.args.get("since", type=float),
        limit=request.args.get("limit", type=int),
    ))


@extended.get("/history/cycles")
def history_cycles():
    q = _core().queries
    return _ok(q.cycles(
        since=request.args.get("since", type=float),
        limit=request.args.get("limit", type=int),
    ))


@extended.get("/history/cycles/<cycle_id>")
def history_cycle_detail(cycle_id: str):
    detail = _core().queries.cycle_detail(cycle_id)
    if detail is None:
        return _err("unknown_cycle", "No cycle %r in the database." % cycle_id, 404)
    return _ok(detail)


@extended.get("/history/commands")
def history_commands():
    q = _core().queries
    return _ok(q.commands(
        since=request.args.get("since", type=float),
        tag_id=request.args.get("tagId"),
        outcome=request.args.get("outcome"),
        limit=request.args.get("limit", type=int),
    ))


@extended.get("/history/snapshots")
def history_snapshots():
    return _ok(_core().queries.snapshots(
        limit=request.args.get("limit", type=int)
    ))


@extended.get("/history/snapshots/<int:snapshot_id>")
def history_snapshot(snapshot_id: int):
    snap = _core().queries.snapshot(snapshot_id)
    if snap is None:
        return _err("unknown_snapshot", "No snapshot %d." % snapshot_id, 404)
    return _ok(snap)


@extended.get("/history/sessions")
def history_sessions():
    return _ok(_core().queries.sessions(
        limit=request.args.get("limit", type=int)
    ))


@extended.get("/history/sessions/<session_uid>")
def history_session(session_uid: str):
    q = _core().queries
    sessions = [s for s in q.sessions(limit=500) if s["session_uid"] == session_uid]
    if not sessions:
        return _err("unknown_session", "No session %r." % session_uid, 404)
    return _ok({"session": sessions[0], "tags": q.session_tags(session_uid)})


@extended.get("/history/sessions/<session_uid>/samples")
def history_session_samples(session_uid: str):
    return _ok(_core().queries.session_samples(
        session_uid,
        tag_id=request.args.get("tagId"),
        limit=request.args.get("limit", type=int),
    ))


@extended.get("/history/sessions/<session_uid>/export")
def export_session(session_uid: str):
    csv = _core().queries.export_session_csv(
        session_uid, tag_id=request.args.get("tagId")
    )
    return Response(
        csv,
        mimetype="text/csv",
        headers={
            "Content-Disposition": 'attachment; filename="recording_%s.csv"'
            % session_uid,
        },
    )


@extended.get("/history/tags/<path:tag_id>")
def history_tag(tag_id: str):
    return _ok(_core().queries.tag_history(
        tag_id,
        since=request.args.get("since", type=float),
        limit=request.args.get("limit", type=int),
    ))


@extended.get("/history/summary")
def history_summary():
    core = _core()
    if not core.store.ready:
        return _err("db_unavailable", "The database is not available.", 503)
    return _ok(core.queries.summary())


# ===========================================================================
# help assistant
# ===========================================================================

@extended.post("/chat")
def chat():
    """
    Ask the help assistant.

    The assistant has no command capability -- see backend/chat/context.py.
    This endpoint returns text and nothing else; it cannot cause a write.
    """
    core = _core()
    body = request.get_json(silent=True) or {}
    message = body.get("message")

    if not isinstance(message, str) or not message.strip():
        return _err("empty_message", "A 'message' string is required.")

    result = core.chat.ask(message, session_id=str(body.get("sessionId", "default")))
    if not result.get("ok"):
        return _err("chat_failed", result.get("error", "Chat failed."), 409)
    return _ok(result["message"], userMessage=result["userMessage"])


@extended.get("/chat/history")
def chat_history():
    return _ok(_core().chat.history(
        session_id=request.args.get("sessionId", "default"),
        limit=request.args.get("limit", 50, type=int),
    ))


@extended.post("/chat/clear")
def chat_clear():
    body = request.get_json(silent=True) or {}
    _core().chat.clear(session_id=str(body.get("sessionId", "default")))
    return _ok({"cleared": True})


@extended.get("/chat/status")
def chat_status():
    return _ok(_core().chat.status())


@extended.get("/chat/context")
def chat_context():
    """
    The exact redacted context the assistant sees.

    Exposed deliberately: an operator (or an auditor) can verify what the
    assistant is and is not given, rather than taking it on trust.
    """
    return _ok(_core().chat.context.build())
