"""
HTTP API.

DESIGN RULES
------------
* No route ever touches the PLC. Every read is served from the cached snapshot,
  every write goes through CommandGate -> PlcService queue.
* Cycle control has its own endpoints with their own validation. The generic
  tag-write endpoint refuses PROTECTED tags outright, so a client cannot start
  a cycle by POSTing to /api/tags/system.cmd_start/write and bypassing the
  quantity rule.
* Errors are structured: ``{"ok": false, "error": {...}}`` with a machine
  readable ``code``, so the UI can react rather than print a string.
"""

from __future__ import annotations

import time
from typing import Any

from flask import Blueprint, current_app, jsonify, request

from backend.plc.registry import ACCESS_PROTECTED, ACCESS_READ_ONLY
from backend.state.machine import VALID_MODES

api = Blueprint("api", __name__, url_prefix="/api")


def _core():
    return current_app.config["CORE"]


def _ok(payload: Any = None, **extra):
    body = {"ok": True}
    if payload is not None:
        body["data"] = payload
    body.update(extra)
    return jsonify(body)


def _route_write(core, tag, value, source: str, operator: str):
    """
    Every write goes through SourceManager, never straight to PlcService.

    Two independent gates must both pass: CommandGate has already decided the
    *operator* may issue this command; the manager decides whether the active
    *source* may reach hardware. Calling PlcService directly would skip the
    second one, which is how a simulation command could reach the PLC.
    """
    ok, result = core.sources.write(
        tag.id, value, source=source, operator=operator,
    )
    if not ok:
        return None, str(result)
    return result, ""


def _err(code: str, message: str, status: int = 400, **extra):
    return jsonify({
        "ok": False,
        "error": {"code": code, "message": message, **extra},
    }), status


# ---------------------------------------------------------------------------
# state
# ---------------------------------------------------------------------------

@api.get("/state")
def get_state():
    return jsonify(_core().snapshot())


@api.get("/health")
def get_health():
    core = _core()
    return _ok({
        "uptimeSeconds": round(time.time() - core.started_at, 1),
        "plc": core.plc.connection,
        "plcSimulated": core.plc.simulate,
        "tags": len(core.registry.tags),
        "subscribers": core.subscriber_count(),
        "registryWarnings": core.registry.warnings,
    })


@api.get("/sequence")
def get_sequence():
    core = _core()
    snap = core.snapshot()
    return _ok({
        "catalogue": core.sequence_catalogue(),
        "live": snap.get("sequence"),
    })


# ---------------------------------------------------------------------------
# tags
# ---------------------------------------------------------------------------

@api.get("/tags")
def list_tags():
    core = _core()
    values = core.plc.values()
    timestamps = core.plc.value_timestamps()

    group = request.args.get("group")
    dtype = request.args.get("type")
    access = request.args.get("access")
    query = (request.args.get("q") or "").strip().lower()
    changed_within = request.args.get("changedWithin", type=float)
    provenance = request.args.get("provenance")

    now = time.time()
    out = []
    for tag in core.registry.tags:
        if group and tag.group != group:
            continue
        if dtype and tag.dtype != dtype:
            continue
        if access and tag.access != access:
            continue
        if provenance and tag.provenance != provenance:
            continue
        if query and query not in (
            tag.name.lower() + " " + tag.short.lower()
            + " " + tag.address.lower() + " " + tag.description.lower()
        ):
            continue

        last = core.history.last_change(tag.id)
        if changed_within is not None:
            if not last or (now - last["at"]) > changed_within:
                continue

        entry = tag.to_dict()
        entry["value"] = values.get(tag.id)
        entry["updatedAt"] = timestamps.get(tag.id)
        entry["lastChangeAt"] = last["at"] if last else None
        entry["lastChangeFrom"] = last["previous"] if last else None
        entry["lastChangeSource"] = last["source"] if last else None
        entry["transitions"] = core.history.transition_count(tag.id)
        entry["watched"] = tag.id in core.history.watch()
        out.append(entry)

    return _ok({
        "tags": out,
        "groups": core.registry.groups(),
        "total": len(out),
        "registryWarnings": core.registry.warnings,
    })


@api.get("/tags/<path:tag_id>")
def get_tag(tag_id: str):
    core = _core()
    tag = core.registry.get(tag_id)
    if not tag:
        return _err("unknown_tag", "No tag with id %r." % tag_id, 404)

    entry = tag.to_dict()
    entry["value"] = core.plc.value(tag_id)
    entry["history"] = core.history.for_tag(tag_id, limit=80)
    entry["transitions"] = core.history.transition_count(tag_id)
    entry["watched"] = tag_id in core.history.watch()

    roles = core.machine.roles()
    decision = core.gate.evaluate(tag, entry["value"], roles, confirmed=False)
    entry["writePreview"] = decision.to_dict()
    return _ok(entry)


@api.post("/tags/<path:tag_id>/write")
def write_tag(tag_id: str):
    core = _core()
    body = request.get_json(silent=True) or {}

    if "value" not in body:
        return _err("missing_value", "Body must contain a 'value' field.")

    tag = core.registry.get(tag_id)
    if not tag:
        return _err("unknown_tag", "No tag with id %r." % tag_id, 404)

    if tag.access in (ACCESS_READ_ONLY, ACCESS_PROTECTED):
        return _err(
            "not_writable",
            "%s is classed '%s' and cannot be written through the tag API."
            % (tag.short, tag.access),
            403,
        )

    roles = core.machine.roles()
    decision = core.gate.evaluate(
        tag, body["value"], roles, confirmed=bool(body.get("confirm")),
    )
    if not decision.allowed:
        return _err(
            decision.code or "rejected", decision.reason,
            409 if decision.requires_confirmation else 403,
            decision=decision.to_dict(),
        )

    cmd, error = _route_write(
        core, tag, body["value"], "manual", str(body.get("operator", "local")),
    )
    if cmd is None:
        code = "source_refused" if "control source" in error else "invalid_value"
        return _err(code, error, 409 if code == "source_refused" else 400)

    core.history.note_command(tag.id, cmd.id, cmd.requested)
    core.events.command(
        "manual",
        "Manual write: %s = %s (%s)" % (tag.short, cmd.requested, tag.address),
        source=cmd.operator, tagId=tag.id, commandId=cmd.id,
    )
    return _ok(cmd.to_dict(), warnings=decision.warnings or [])


@api.get("/commands")
def list_commands():
    return _ok(_core().plc.recent_commands(limit=request.args.get("limit", 60, type=int)))


@api.get("/commands/<command_id>")
def get_command(command_id: str):
    cmd = _core().plc.command(command_id)
    if not cmd:
        return _err("unknown_command", "No command %r." % command_id, 404)
    return _ok(cmd.to_dict())


# ---------------------------------------------------------------------------
# watch list
# ---------------------------------------------------------------------------

@api.get("/watch")
def get_watch():
    return _ok(_core().snapshot().get("diagnostics", {}).get("watch", []))


@api.post("/watch")
def post_watch():
    core = _core()
    body = request.get_json(silent=True) or {}
    action = body.get("action", "add")
    tag_id = body.get("tagId")

    if action == "set":
        ids = [t for t in (body.get("tagIds") or []) if core.registry.get(t)]
        return _ok(core.history.set_watch(ids))

    if not tag_id or not core.registry.get(tag_id):
        return _err("unknown_tag", "No tag with id %r." % tag_id, 404)

    if action == "remove":
        return _ok(core.history.remove_watch(tag_id))
    return _ok(core.history.add_watch(tag_id))


# ---------------------------------------------------------------------------
# mode + cycle control
# ---------------------------------------------------------------------------

@api.post("/mode")
def set_mode():
    core = _core()
    body = request.get_json(silent=True) or {}
    mode = str(body.get("mode", "")).upper()

    if mode not in VALID_MODES:
        return _err("invalid_mode", "Mode must be one of %s." % (VALID_MODES,))

    ok, reason = core.machine.set_mode(mode, str(body.get("operator", "local")))
    if not ok:
        return _err("mode_refused", reason, 409)
    return _ok(core.gate.describe_mode())


@api.post("/cycle/start")
def cycle_start():
    """
    The guarded start path. This is the ONLY way to raise CMD_START.

    Enforces, in order: mode, quantity rule, start interlocks, then writes
    quantities and mode before the start bit -- so the PLC never sees a start
    with stale quantities.
    """
    core = _core()
    body = request.get_json(silent=True) or {}
    operator = str(body.get("operator", "local"))

    if core.machine.state.mode != "AUTO":
        return _err(
            "wrong_mode",
            "Cycle start requires AUTO mode; current mode is %s."
            % core.machine.state.mode, 409,
        )

    qty25 = body.get("qty25", body.get("productqty_25mm", 0))
    qty50 = body.get("qty50", body.get("productqty_50mm", 0))

    ok, reason = core.machine.validate_order(qty25, qty50, core.max_total_qty)
    if not ok:
        core.events.warning(
            "cycle", "Cycle start refused: %s" % reason, source=operator,
            qty25=qty25, qty50=qty50,
        )
        return _err("invalid_order", reason, 422, qty25=qty25, qty50=qty50)

    roles = core.machine.roles()
    can_restart, blockers = core.machine.can_restart(roles)
    if not can_restart:
        return _err(
            "interlocks_blocked",
            "Start interlocks are not satisfied.", 409,
            blockers=[b.to_dict() for b in blockers],
        )

    if roles.get("cmd.start") is True and roles.get("status.cycle_completed") is not True:
        return _err("already_running", "A cycle is already running.", 409)

    high_speed = bool(body.get("highSpeed", body.get("mode_high_speed", False)))

    plan = [
        ("order.qty_25mm", int(qty25)),
        ("order.qty_50mm", int(qty50)),
        ("cmd.mode_high_speed", high_speed),
        ("cmd.start", True),
    ]

    issued = []
    for role, value in plan:
        tag = core.registry.role(role)
        if not tag:
            return _err(
                "missing_tag",
                "Role %r is not present in the tag list; cannot start safely." % role,
                500,
            )
        cmd, error = _route_write(core, tag, value, "auto", operator)
        if cmd is None:
            return _err("source_refused", error, 409, partial=issued)
        core.history.note_command(tag.id, cmd.id, cmd.requested)
        issued.append(cmd.to_dict())

    core.products.set_order(int(qty25), int(qty50))
    core.events.command(
        "cycle",
        "Cycle start requested: %d x 25 mm, %d x 50 mm, %s speed"
        % (int(qty25), int(qty50), "HIGH" if high_speed else "NORMAL"),
        source=operator, qty25=int(qty25), qty50=int(qty50), highSpeed=high_speed,
    )
    return _ok({"commands": issued})


@api.post("/cycle/reset")
def cycle_reset():
    """
    Recovery. Requires the restart checklist to pass unless explicitly forced
    by an engineer, in which case the override is recorded as an event.
    """
    core = _core()
    body = request.get_json(silent=True) or {}
    operator = str(body.get("operator", "local"))
    force = bool(body.get("force"))

    roles = core.machine.roles()
    can_restart, blockers = core.machine.can_restart(roles)

    if not can_restart and not force:
        return _err(
            "interlocks_blocked",
            "Restart prerequisites are not satisfied.", 409,
            blockers=[b.to_dict() for b in blockers],
        )

    tag = core.registry.role("cmd.cycle_reset")
    if not tag:
        return _err("missing_tag", "No Cycle_Reset tag in the registry.", 500)

    cmd, error = _route_write(core, tag, True, "recovery", operator)
    if cmd is None:
        return _err("source_refused", error, 409)
    core.history.note_command(tag.id, cmd.id, cmd.requested)
    core.machine.mark_reset_pending(2.0)
    core.sequence.reset("operator reset")

    for fault in core.events.active_faults():
        if fault["key"].startswith("sequence.stalled."):
            core.events.clear_fault(fault["key"], "Cleared by operator reset.")

    core.events.command(
        "cycle",
        "Cycle reset issued%s" % (" (FORCED past blockers)" if force and not can_restart else ""),
        source=operator, forced=force and not can_restart,
        blockers=[b.key for b in blockers],
    )
    return _ok(cmd.to_dict())


@api.post("/cycle/stop")
def cycle_stop():
    """
    Controlled software stop: drop CMD_START.

    THIS IS NOT AN EMERGENCY STOP. It asks the PLC program to stop starting new
    work; it does not remove power, vent air, or open the safety circuit. The
    hardware E-Stop is the only functional-safety stop on this machine.
    """
    core = _core()
    body = request.get_json(silent=True) or {}
    operator = str(body.get("operator", "local"))

    tag = core.registry.role("cmd.start")
    if not tag:
        return _err("missing_tag", "No CMD_START tag in the registry.", 500)

    cmd, error = _route_write(core, tag, False, "manual", operator)
    if cmd is None:
        return _err("source_refused", error, 409)
    core.history.note_command(tag.id, cmd.id, cmd.requested)
    core.events.command(
        "cycle",
        "Software stop requested (CMD_START cleared). This is not a "
        "functional-safety stop.",
        source=operator,
    )
    return _ok(cmd.to_dict())


@api.post("/engraving/complete")
def engraving_complete():
    """Operator acknowledgement for sequence step 29 (the old ENG DONE button)."""
    core = _core()
    body = request.get_json(silent=True) or {}
    operator = str(body.get("operator", "local"))

    tag = core.registry.role("cmd.engraving_completed")
    if not tag:
        return _err("missing_tag", "No Engraving_Completed tag in the registry.", 500)

    roles = core.machine.roles()
    decision = core.gate.evaluate(tag, True, roles, confirmed=True, intent="internal")
    if not decision.allowed:
        return _err(decision.code or "rejected", decision.reason, 403,
                    decision=decision.to_dict())

    cmd, error = _route_write(core, tag, True, "manual", operator)
    if cmd is None:
        return _err("source_refused", error, 409)
    core.history.note_command(tag.id, cmd.id, cmd.requested)
    core.events.command("engraving", "Engraving completion acknowledged.", source=operator)
    return _ok(cmd.to_dict(), warnings=decision.warnings or [])


# ---------------------------------------------------------------------------
# events / faults / diagnostics
# ---------------------------------------------------------------------------

@api.get("/events")
def get_events():
    core = _core()
    since = request.args.get("since", type=int)
    if since is not None:
        return _ok(core.events.since(since, limit=request.args.get("limit", 500, type=int)))
    return _ok(core.events.recent(
        limit=request.args.get("limit", 200, type=int),
        min_severity=request.args.get("minSeverity"),
    ))


@api.get("/faults")
def get_faults():
    core = _core()
    include_cleared = request.args.get("includeCleared", "true") != "false"
    return _ok(core.events.faults(include_cleared=include_cleared))


@api.post("/faults/<path:key>/acknowledge")
def ack_fault(key: str):
    core = _core()
    if not core.events.acknowledge(key):
        return _err("unknown_fault", "No fault %r." % key, 404)
    core.events.info("fault", "Fault acknowledged: %s" % key, source="operator")
    return _ok({"key": key, "acknowledged": True})


@api.get("/diagnostics")
def get_diagnostics():
    core = _core()
    snap = core.snapshot()
    return _ok({
        "findings": core.diagnostics.findings(),
        "faults": core.events.faults(),
        "watch": snap.get("diagnostics", {}).get("watch", []),
        "chatter": core.history.chatter_report(),
        "changes": core.history.recent(limit=200),
        "commands": core.plc.recent_commands(limit=60),
        "registryWarnings": core.registry.warnings,
    })


@api.get("/history/<path:tag_id>")
def get_history(tag_id: str):
    core = _core()
    if not core.registry.get(tag_id):
        return _err("unknown_tag", "No tag with id %r." % tag_id, 404)
    return _ok(core.history.for_tag(tag_id, limit=request.args.get("limit", 100, type=int)))


# ---------------------------------------------------------------------------
# camera + twin
# ---------------------------------------------------------------------------

@api.get("/camera/state")
def camera_state():
    return _ok(_core().camera.state())


@api.get("/digital-twin/state")
def twin_state():
    core = _core()
    return _ok(core.snapshot().get("digitalTwin"))


@api.get("/digital-twin/reference")
def twin_reference():
    return _ok(_core().twin.reference_meta())


@api.post("/digital-twin/reload")
def twin_reload():
    core = _core()
    ok = core.twin.load()
    if not ok:
        return _err("twin_unavailable", core.twin._error, 409)
    return _ok(core.twin.reference_meta())
