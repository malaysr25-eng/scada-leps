#!/usr/bin/env python
"""
End-to-end self-test against a running backend.

    python run.py --simulate --port 5055        # terminal 1
    python tools/selftest.py --port 5055        # terminal 2

Every check corresponds to a row in docs/TEST_CHECKLIST.md. The suite proves
the safety rules hold at the *backend*, which is the point: a frontend can be
bypassed with curl, so these must not be UI-only.

Exit code 0 = all passed.
"""

from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.error
import urllib.request

BASE = "http://127.0.0.1:5000"

PASS, FAIL = [], []


def call(method: str, path: str, body=None, timeout: float = 10.0):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode())


def check(name: str, condition: bool, detail: str = "") -> bool:
    if condition:
        PASS.append(name)
        print("  PASS  %s" % name)
    else:
        FAIL.append((name, detail))
        print("  FAIL  %s%s" % (name, ("  -- " + detail) if detail else ""))
    return condition


def state() -> dict:
    return call("GET", "/api/state")[1]


def wait_for(predicate, timeout: float = 25.0, interval: float = 0.4):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = state()
        try:
            if predicate(last):
                return True, last
        except (KeyError, TypeError):
            pass
        time.sleep(interval)
    return False, last


def section(title: str) -> None:
    print("\n" + title)
    print("-" * len(title))


# ---------------------------------------------------------------------------


def test_connectivity():
    section("1. Connectivity and registry")
    status, body = call("GET", "/api/health")
    check("API responds", status == 200 and body.get("ok"))
    data = body.get("data", {})
    check("Tag registry populated", data.get("tags", 0) >= 121,
          "got %s tags" % data.get("tags"))
    check("No registry warnings", not data.get("registryWarnings"),
          str(data.get("registryWarnings")))

    s = state()
    check("Snapshot has every top-level section",
          all(k in s for k in (
              "connection", "machine", "safety", "sequence", "sensors",
              "actuators", "conveyors", "inventory", "camera", "digitalTwin",
              "diagnostics", "events")))
    check("Sensor list complete (10 proximity + 2 limits)",
          len(s["sensors"]) == 12, "got %d" % len(s["sensors"]))
    check("Actuator list complete (13 valves)",
          len(s["actuators"]) == 13, "got %d" % len(s["actuators"]))


def test_zero_quantity_rule():
    section("2. Zero-quantity start rule (Errors sheet E-16)")
    for qty25, qty50 in ((0, 0), (-1, 1), (0, -3)):
        status, body = call("POST", "/api/cycle/start",
                            {"qty25": qty25, "qty50": qty50})
        check("Start refused for qty25=%s qty50=%s" % (qty25, qty50),
              status == 422 and not body.get("ok"),
              "status=%s body=%s" % (status, body))

    s = state()
    check("canStart reports the reason",
          s["canStart"]["allowed"] is False
          and any("at least one product" in r for r in s["canStart"]["reasons"]),
          str(s["canStart"]))


def test_protected_tags():
    section("3. Protected and read-only tags cannot be written")
    cases = [
        ("system.cmd_start", True, "CMD_START (protected)"),
        ("system.productqty_25mm", 5, "Productqty_25mm (protected)"),
        ("system.cycle_reset", True, "Cycle_Reset (protected)"),
        ("io_status.digital_outputs.solenoid_valve8", True, "SV8 output mirror (read-only)"),
        ("io_status.digital_inputs.proximity_sensor1", True, "PX1 input (read-only)"),
        ("system.start_interlocks.emergency_healthy", True, "E-Stop healthy (read-only)"),
    ]
    for tag_id, value, label in cases:
        status, body = call("POST", "/api/tags/%s/write" % tag_id, {"value": value})
        check("Write refused: %s" % label,
              status == 403 and body.get("error", {}).get("code") == "not_writable",
              "status=%s body=%s" % (status, body))


def test_mode_ownership():
    section("4. Auto/manual control ownership")
    # Right after boot the simulator has not seeded its image (the emergency
    # bit reads False) and no control source is selected yet. Wait both out
    # so the gate answers on mode alone.
    wait_for(lambda x: x["machine"]["lifecycle"] == "READY"
             and (x.get("dataSources") or {}).get("controlSourceId"),
             timeout=15)
    status, body = call("POST", "/api/tags/manual_commands.solenoid_valve8/write",
                        {"value": True})
    check("Manual valve write refused while in AUTO mode",
          status == 403 and body.get("error", {}).get("code") == "wrong_mode",
          "status=%s body=%s" % (status, body))

    check("Switch to MANUAL", call("POST", "/api/mode", {"mode": "MANUAL"})[0] == 200)

    status, body = call("POST", "/api/tags/manual_commands.solenoid_valve8/write",
                        {"value": True})
    check("Manual valve write accepted in MANUAL mode",
          status == 200 and body.get("ok"), "status=%s body=%s" % (status, body))

    command_id = (body.get("data") or {}).get("id")
    ok, _ = wait_for(
        lambda s: any(c["id"] == command_id and c["state"] == "CONFIRMED"
                      for c in s["commands"]),
        timeout=8.0,
    )
    check("Write confirmed by an independent PLC read-back", ok,
          "command %s never reached CONFIRMED" % command_id)

    status, body = call("POST", "/api/tags/pot_control.conv2.set_velocity/write",
                        {"value": 0.2})
    check("Conveyor speed in MANUAL still needs confirmation",
          status == 409
          and body.get("error", {}).get("code") == "confirmation_required",
          "status=%s body=%s" % (status, body))

    status, body = call("POST", "/api/tags/pot_control.conv2.set_home/write",
                        {"value": True, "confirm": True})
    check("Other engineering setpoints refused in MANUAL mode",
          status == 403 and body.get("error", {}).get("code") == "wrong_mode",
          "status=%s body=%s" % (status, body))

    check("Switch to MAINTENANCE",
          call("POST", "/api/mode", {"mode": "MAINTENANCE"})[0] == 200)

    status, body = call("POST", "/api/tags/pot_control.conv2.set_velocity/write",
                        {"value": 0.2})
    check("Engineering setpoint needs confirmation in MAINTENANCE",
          status == 409
          and body.get("error", {}).get("code") == "confirmation_required",
          "status=%s body=%s" % (status, body))

    status, body = call("POST", "/api/tags/pot_control.conv2.set_velocity/write",
                        {"value": 0.2, "confirm": True})
    check("Engineering setpoint accepted once confirmed",
          status == 200 and body.get("ok"), "status=%s body=%s" % (status, body))

    # Put the valve back and return to AUTO.
    call("POST", "/api/mode", {"mode": "MANUAL"})
    call("POST", "/api/tags/manual_commands.solenoid_valve8/write", {"value": False})
    check("Return to AUTO", call("POST", "/api/mode", {"mode": "AUTO"})[0] == 200)


def test_value_validation():
    section("5. Value validation")
    call("POST", "/api/mode", {"mode": "MANUAL"})

    status, body = call("POST", "/api/tags/manual_commands.solenoid_valve1/write",
                        {"value": "banana"})
    check("Nonsense Bool value rejected",
          status == 400 and body.get("error", {}).get("code") == "invalid_value",
          "status=%s body=%s" % (status, body))

    status, body = call("POST", "/api/tags/manual_commands.solenoid_valve1/write", {})
    check("Missing value field rejected",
          status == 400 and body.get("error", {}).get("code") == "missing_value")

    status, body = call("POST", "/api/tags/does.not.exist/write", {"value": True})
    check("Unknown tag rejected", status == 404)

    call("POST", "/api/mode", {"mode": "AUTO"})


def test_full_cycle():
    section("6. Full automatic cycle")
    ok, s = wait_for(lambda x: x["machine"]["lifecycle"] == "READY", timeout=15)
    check("Machine reaches READY with interlocks satisfied", ok,
          "lifecycle=%s" % (s or {}).get("machine", {}).get("lifecycle"))

    status, body = call("POST", "/api/cycle/start", {"qty25": 1, "qty50": 0})
    check("Valid order accepted", status == 200 and body.get("ok"),
          "status=%s body=%s" % (status, body))

    commands = (body.get("data") or {}).get("commands", [])
    check("Start writes quantities before the start bit",
          [c["address"] for c in commands][:3]
          == ["DB59.DBW108.0", "DB59.DBW110.0", "DB59.DBX112.0"]
          and commands[-1]["address"] == "DB59.DBX112.2",
          str([c["address"] for c in commands]))

    ok, s = wait_for(lambda x: x["machine"]["lifecycle"] == "AUTO_RUNNING", timeout=10)
    check("Lifecycle becomes AUTO_RUNNING", ok)
    check("Cycle id assigned", bool((s or {}).get("machine", {}).get("cycleId")))

    ok, s = wait_for(
        lambda x: x["sequence"]["lastConfirmedStep"] is not None
        and x["sequence"]["lastConfirmedStep"] >= 7,
        timeout=15,
    )
    check("Sequence advances on a confirmed sensor (PX1)", ok,
          "lastConfirmedStep=%s" % (s or {}).get("sequence", {}).get("lastConfirmedStep"))
    check("Sequence does not teleport past the engraving step",
          (s or {})["sequence"]["lastConfirmedStep"] < 28,
          "lastConfirmedStep=%s" % (s or {})["sequence"]["lastConfirmedStep"])

    ok, s = wait_for(lambda x: any(e["label"] == "PX 1" and e["transitions"] > 0
                                   for e in x["sensors"]), timeout=15)
    check("Sensor transition recorded with a timestamp", ok)

    ok, s = wait_for(lambda x: x["inventory"]["activeToken"] is not None, timeout=15)
    check("Workpiece token created for the cycle", ok)

    # The engraving step is a genuine manual hold.
    ok, s = wait_for(
        lambda x: x["sequence"]["waitingRole"] == "cmd.engraving_completed",
        timeout=30,
    )
    check("Cycle waits for the operator engraving acknowledgement", ok,
          "waitingRole=%s" % (s or {}).get("sequence", {}).get("waitingRole"))

    status, body = call("POST", "/api/engraving/complete", {})
    check("Engraving acknowledgement accepted", status == 200 and body.get("ok"),
          str(body))

    ok, s = wait_for(lambda x: x["machine"]["lifecycle"] == "COMPLETED", timeout=40)
    check("Cycle reaches COMPLETED", ok,
          "lifecycle=%s" % (s or {}).get("machine", {}).get("lifecycle"))
    check("Completed workpiece recorded",
          len((s or {})["inventory"]["completedTokens"]) >= 1)


def test_recovery():
    section("7. Reset and recovery")
    status, body = call("POST", "/api/cycle/reset", {})
    check("Reset accepted when prerequisites are met",
          status == 200 and body.get("ok"), str(body))

    ok, _ = wait_for(lambda x: x["sequence"]["lastConfirmedStep"] is None, timeout=8)
    check("Sequence tracker cleared by reset", ok)


def test_stream():
    section("8. Real-time stream")
    try:
        req = urllib.request.Request(BASE + "/api/stream")
        with urllib.request.urlopen(req, timeout=8) as r:
            check("SSE content type",
                  r.headers.get("Content-Type", "").startswith("text/event-stream"),
                  r.headers.get("Content-Type"))
            chunk = r.read(120).decode("utf-8", "replace")
            check("First SSE frame is a state event", chunk.startswith("event: state"),
                  chunk[:60])
    except Exception as exc:
        check("SSE stream reachable", False, str(exc))


def test_no_nan():
    section("9. JSON safety")
    raw = urllib.request.urlopen(BASE + "/api/state", timeout=10).read().decode()
    check("Snapshot contains no bare NaN/Infinity",
          "NaN" not in raw and "Infinity" not in raw)
    try:
        json.loads(raw)
        check("Snapshot parses as strict JSON", True)
    except json.JSONDecodeError as exc:
        check("Snapshot parses as strict JSON", False, str(exc))


def main() -> int:
    global BASE
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    BASE = "http://%s:%d" % (args.host, args.port)

    print("Self-test against %s" % BASE)

    try:
        call("GET", "/api/health", timeout=4)
    except Exception as exc:
        print("\nCannot reach the backend at %s: %s" % (BASE, exc))
        print("Start it first:  python run.py --simulate --port %d" % args.port)
        return 2

    test_connectivity()
    test_zero_quantity_rule()
    test_protected_tags()
    test_mode_ownership()
    test_value_validation()
    test_full_cycle()
    test_recovery()
    test_stream()
    test_no_nan()

    print("\n" + "=" * 58)
    print("  %d passed, %d failed" % (len(PASS), len(FAIL)))
    if FAIL:
        print("=" * 58)
        for name, detail in FAIL:
            print("  FAILED: %s" % name)
            if detail:
                print("          %s" % detail)
    print("=" * 58)
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
