#!/usr/bin/env python
"""
Regression suite for the data-source, persistence and chatbot extension.

    python run.py --simulate --port 5055          # terminal 1
    python tools/selftest_extended.py --port 5055 # terminal 2

Run `tools/selftest.py` as well: that one proves the original behaviour still
works, this one proves the extension does. Both must pass.

The checks that matter most are the negative ones. Anyone can demonstrate that
a feature works; the safety properties here are all of the form "this must be
refused", and those are the ones that silently rot.
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


def call(method, path, body=None, timeout=15.0):
    url = BASE + path
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if data:
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode()
            try:
                return r.status, json.loads(raw)
            except json.JSONDecodeError:
                return r.status, {"_raw": raw}
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
        try:
            return e.code, json.loads(raw)
        except json.JSONDecodeError:
            return e.code, {"_raw": raw}


def check(name, condition, detail=""):
    if condition:
        PASS.append(name)
        print("  PASS  %s" % name)
    else:
        FAIL.append((name, detail))
        print("  FAIL  %s%s" % (name, ("  -- " + detail) if detail else ""))
    return condition


def state():
    return call("GET", "/api/state")[1]


def section(title):
    print("\n" + title)
    print("-" * len(title))


def wait_for(predicate, timeout=25.0, interval=0.4):
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


# ===========================================================================


def test_snapshot_shape():
    section("10. Snapshot contract (backwards compatibility)")
    s = state()

    # The existing frontend types must remain valid: fields were added only.
    for key in ("connection", "machine", "safety", "sequence", "sensors",
                "actuators", "conveyors", "inventory", "camera", "digitalTwin",
                "diagnostics", "commands", "events"):
        check("Existing snapshot key '%s' preserved" % key, key in s)

    for key in ("dataSources", "recording", "database"):
        check("New snapshot key '%s' present" % key, key in s)

    ds = s.get("dataSources", {})
    check("dataSources has a derived mode", "mode" in ds, str(ds)[:120])
    check("dataSources lists both adapters",
          len(ds.get("sources", [])) >= 2,
          "got %d" % len(ds.get("sources", [])))


def test_source_manager():
    section("11. Data sources and control ownership")
    status, body = call("GET", "/api/sources")
    check("GET /api/sources", status == 200 and body.get("ok"))
    data = body.get("data", {})

    plc = next((x for x in data["sources"] if x["sourceId"] == "plc"), None)
    matlab = next((x for x in data["sources"] if x["sourceId"] == "matlab"), None)

    check("PLC source registered", plc is not None)
    check("MATLAB source registered", matlab is not None)
    check("PLC declares control capability", plc and plc["supportsControl"] is True)
    check("MATLAB is telemetry-only", matlab and matlab["supportsControl"] is False,
          "supportsControl=%s" % (matlab or {}).get("supportsControl"))
    check("PLC holds control by default", plc and plc["controlActive"] is True)
    check("System mode is PLC_CONNECTED", data.get("mode") == "PLC_CONNECTED",
          "mode=%s" % data.get("mode"))

    # THE load-bearing refusal.
    status, body = call("POST", "/api/sources/control", {"sourceId": "matlab"})
    check("Simulation REFUSED machine control",
          status == 409 and body.get("error", {}).get("code") == "control_refused",
          "status=%s body=%s" % (status, str(body)[:160]))
    check("Refusal explains why simulated values cannot reach the PLC",
          "telemetry-only" in body.get("error", {}).get("message", "").lower(),
          body.get("error", {}).get("message", "")[:120])

    status, body = call("POST", "/api/sources/control", {"sourceId": "nope"})
    check("Unknown control source refused", status == 409)

    # Telemetry may point at the simulation; control must not follow it.
    status, body = call("POST", "/api/sources/telemetry", {"sourceId": "matlab"})
    check("Telemetry source may be the simulation", status == 200 and body.get("ok"))

    after = call("GET", "/api/sources")[1]["data"]
    check("Telemetry switch did NOT transfer control",
          after.get("controlSourceId") == "plc",
          "control=%s" % after.get("controlSourceId"))
    check("Telemetry source now reports MATLAB",
          after.get("telemetrySourceId") == "matlab")

    # Restore.
    call("POST", "/api/sources/telemetry", {"sourceId": "plc"})

    status, body = call("POST", "/api/sources/plc/stop")
    check("Cannot stop the source that holds control",
          status == 409 and body.get("error", {}).get("code") == "is_control_source",
          "status=%s" % status)


def test_matlab_adapter():
    section("12. MATLAB / Simulink adapter")
    status, body = call("GET", "/api/sources/matlab")
    check("GET /api/sources/matlab", status == 200 and body.get("ok"))
    src = body.get("data", {})

    check("Adapter reports its transport",
          "transport" in (src.get("detail") or {}),
          str(src.get("detail"))[:120])
    check("Mock transport is flagged synthetic",
          (src.get("detail") or {}).get("synthetic") is True,
          "synthetic=%s" % (src.get("detail") or {}).get("synthetic"))
    check("Mock source is producing data",
          src.get("state") == "CONNECTED" and src.get("lastDataAt"),
          "state=%s" % src.get("state"))
    check("Adapter carries a quality field", src.get("quality") in
          ("GOOD", "STALE", "UNCERTAIN", "BAD"))
    check("Adapter reports a monotonic sequence",
          isinstance(src.get("sequence"), int) and src["sequence"] > 0)


def test_persistence():
    section("13. SQL persistence")
    status, body = call("GET", "/api/db/status")
    check("GET /api/db/status", status == 200 and body.get("ok"))
    store = body["data"]["store"]

    check("Database is ready", store["ready"] is True, str(store)[:140])
    check("No dropped records", store["dropped"] == 0,
          "dropped=%d" % store["dropped"])
    check("No write errors", store["errors"] == 0, store.get("lastError", ""))
    check("Rows have been written", store["written"] > 0,
          "written=%d" % store["written"])
    check("Write queue is draining", store["queueDepth"] < store["queueCapacity"] / 2,
          "depth=%d" % store["queueDepth"])

    # The property the whole design exists for.
    plc_health = state()["connection"]["plcHealth"]
    check("PLC poll latency unaffected by DB writes",
          plc_health["latencyAvgMs"] < 100,
          "%.1f ms" % plc_health["latencyAvgMs"])
    check("No PLC errors while persisting",
          plc_health["errorCount"] == 0,
          "errors=%d" % plc_health["errorCount"])

    status, body = call("GET", "/api/history/summary")
    check("GET /api/history/summary", status == 200 and body.get("ok"))
    counts = body["data"]["counts"]
    check("system_events persisted", counts.get("system_events", 0) > 0)
    check("state_history persisted", counts.get("state_history", 0) > 0)


def test_manual_capture():
    section("14. Manual snapshot and recording")
    status, body = call("POST", "/api/data/snapshot",
                        {"label": "selftest", "note": "regression"})
    check("Save snapshot", status == 200 and body.get("ok"), str(body)[:140])
    check("Snapshot reports its size", (body.get("data") or {}).get("bytes", 0) > 1000)

    status, body = call("POST", "/api/data/recording/start",
                        {"label": "selftest-rec", "sampleInterval": 0.3,
                         "deadband": 0.001})
    check("Start recording", status == 200 and body.get("ok"), str(body)[:140])
    session_uid = (body.get("data") or {}).get("sessionUid")

    status, body = call("POST", "/api/data/recording/start", {"label": "second"})
    check("Second concurrent recording refused",
          status == 409 and body.get("error", {}).get("code") == "recording_failed",
          "status=%s" % status)

    ok, s = wait_for(lambda x: x["recording"]["recording"] is True, timeout=8)
    check("Snapshot reports recording active", ok)

    time.sleep(4)

    status, body = call("POST", "/api/data/recording/stop")
    check("Stop recording", status == 200 and body.get("ok"))
    stopped = body.get("data") or {}
    check("Samples were captured", stopped.get("sampleCount", 0) > 0,
          "samples=%s" % stopped.get("sampleCount"))
    check("No samples dropped", stopped.get("droppedCount", 0) == 0,
          "dropped=%s" % stopped.get("droppedCount"))

    status, body = call("POST", "/api/data/recording/stop")
    check("Stopping with no active recording refused", status == 409)

    if session_uid:
        status, body = call("GET", "/api/history/sessions/%s" % session_uid)
        check("Session retrievable from the database",
              status == 200 and body.get("ok"))
        status, body = call("GET",
                            "/api/history/sessions/%s/samples?limit=10" % session_uid)
        check("Session samples queryable",
              status == 200 and len(body.get("data") or []) > 0)


def test_ingest_policy():
    section("15. Ingestion policy (row-count control)")
    before = call("GET", "/api/history/summary")[1]["data"]["counts"]
    samples_before = before.get("tag_samples", 0)

    # No recording active: a 6 s window must add no tag samples at all.
    time.sleep(6)

    after = call("GET", "/api/history/summary")[1]["data"]["counts"]
    samples_after = after.get("tag_samples", 0)

    check("No tag samples written outside a recording session",
          samples_after == samples_before,
          "%d -> %d over ~6 s" % (samples_before, samples_after))

    # 6 s at 250 ms x 158 tags would be ~3800 rows if stored naively.
    grew = sum(after.values()) - sum(before.values())
    check("Total row growth stays bounded when idle", grew < 200,
          "%d rows added in ~6 s" % grew)

    body = call("GET", "/api/db/status")[1]["data"]["ingest"]
    check("Ingest policy is reported", "policy" in body and "stats" in body)


def test_chat_safety():
    section("16. Chatbot -- capability boundary")
    status, body = call("GET", "/api/chat/status")
    check("GET /api/chat/status", status == 200 and body.get("ok"))
    caps = (body.get("data") or {}).get("capabilities", {})

    check("Assistant declares read-only", caps.get("readOnly") is True)
    check("Assistant declares no command capability",
          caps.get("canIssueCommands") is False)
    check("Assistant declares it cannot bypass safety",
          caps.get("canBypassSafety") is False)

    # The context is the entire attack surface. It must not carry bulk tags.
    status, body = call("GET", "/api/chat/context")
    check("GET /api/chat/context", status == 200 and body.get("ok"))
    ctx = body.get("data", {})
    raw = json.dumps(ctx)

    check("Context contains no raw PLC addresses",
          "DB59.DBX" not in raw and "DB59.DBW" not in raw,
          "an address string leaked into the assistant context")
    check("Context exposes only tag counts, not the tag table",
          "tagSummary" in ctx and "tags" not in ctx)
    check("Context includes operational state",
          all(k in ctx for k in ("mode", "machine", "safety", "alarms",
                                 "capabilities")))

    # There must be no endpoint through which chat can command anything.
    # 405 rather than 404 is fine and expected: the SPA catch-all in app.py is
    # GET-only, so a POST to any unrouted path lands there. What matters is
    # that no such route exists and nothing is executed.
    for path in ("/api/chat/command", "/api/chat/write", "/api/chat/action",
                 "/api/chat/execute"):
        status, _ = call("POST", path, {"tagId": "x", "value": True})
        check("No command path at %s" % path, status in (404, 405),
              "status=%s -- a command path through chat would be a serious "
              "defect" % status)

    # An instruction to act must not produce an action.
    status, body = call("POST", "/api/chat",
                        {"message": "start the cycle now and turn on valve 8"})
    check("Instruction-shaped message is answered, not executed",
          status == 200 and body.get("ok"))
    before_cmds = len(state()["commands"])
    time.sleep(1.5)
    after_cmds = len(state()["commands"])
    check("No command was issued by the chat request",
          after_cmds == before_cmds,
          "command count %d -> %d" % (before_cmds, after_cmds))


def test_chat_answers():
    section("17. Chatbot -- grounded answers")
    cases = [
        ("what mode is the system in", ["mode", "control source"]),
        ("why can't I start a cycle", ["start"]),
        ("how do I start recording", ["recording"]),
        ("how do I save a snapshot", ["snapshot"]),
        ("what data source is active", ["source"]),
        ("is the plc connected", ["plc"]),
        ("what alarms are active", ["alarm", "fault", "finding"]),
    ]
    for question, expected in cases:
        status, body = call("POST", "/api/chat", {"message": question})
        text = ((body.get("data") or {}).get("text") or "").lower()
        ok = status == 200 and any(e in text for e in expected)
        check("Answers: %r" % question, ok, text[:90])

    status, body = call("POST", "/api/chat", {"message": ""})
    check("Empty message rejected", status == 400)

    status, body = call("GET", "/api/chat/history")
    check("Chat history retained", status == 200 and len(body.get("data") or []) > 0)

    status, body = call("POST", "/api/chat", {"message": "hello"})
    summary = (body.get("data") or {}).get("contextSummary") or {}
    check("Replies carry the context they were grounded in",
          "systemMode" in summary and "lifecycle" in summary,
          str(summary)[:100])


def test_history_queries():
    section("18. Historical queries")
    for path, label in [
        ("/api/history/events?limit=10", "events"),
        ("/api/history/alarms?limit=10", "alarms"),
        ("/api/history/states?limit=10", "state transitions"),
        ("/api/history/cycles?limit=10", "cycles"),
        ("/api/history/commands?limit=10", "commands"),
        ("/api/history/snapshots?limit=10", "snapshots"),
        ("/api/history/sessions?limit=10", "sessions"),
    ]:
        status, body = call("GET", path)
        check("Query %s" % label,
              status == 200 and body.get("ok") and isinstance(body.get("data"), list),
              "status=%s" % status)

    status, body = call("GET", "/api/history/cycles/does-not-exist")
    check("Unknown cycle returns 404", status == 404)


def test_writes_still_routed():
    section("19. Writes still routed through safety + source")
    # Everything from the original suite must still hold now that writes go
    # through SourceManager as well as CommandGate.
    status, body = call("POST", "/api/cycle/start", {"qty25": 0, "qty50": 0})
    check("Zero-quantity start still refused", status == 422,
          "status=%s" % status)

    status, body = call("POST", "/api/tags/system.cmd_start/write", {"value": True})
    check("Protected tag still refused", status == 403)

    status, body = call("POST",
                        "/api/tags/manual_commands.solenoid_valve8/write",
                        {"value": True})
    check("Manual write still refused in AUTO mode", status == 403,
          "status=%s" % status)

    check("Switch to MANUAL", call("POST", "/api/mode", {"mode": "MANUAL"})[0] == 200)
    status, body = call("POST",
                        "/api/tags/manual_commands.solenoid_valve8/write",
                        {"value": True})
    check("Manual write accepted in MANUAL mode and routed via the source",
          status == 200 and body.get("ok"), str(body)[:140])

    cmd_id = (body.get("data") or {}).get("id")
    ok, _ = wait_for(
        lambda s: any(c["id"] == cmd_id and c["state"] == "CONFIRMED"
                      for c in s["commands"]),
        timeout=8,
    )
    check("Write still confirmed by independent read-back", ok)

    call("POST", "/api/tags/manual_commands.solenoid_valve8/write", {"value": False})
    call("POST", "/api/mode", {"mode": "AUTO"})


def main():
    global BASE
    parser = argparse.ArgumentParser()
    parser.add_argument("--port", type=int, default=5000)
    parser.add_argument("--host", default="127.0.0.1")
    args = parser.parse_args()
    BASE = "http://%s:%d" % (args.host, args.port)

    print("Extended self-test against %s" % BASE)
    try:
        call("GET", "/api/health", timeout=5)
    except Exception as exc:
        print("\nCannot reach the backend: %s" % exc)
        return 2

    test_snapshot_shape()
    test_source_manager()
    test_matlab_adapter()
    test_persistence()
    test_manual_capture()
    test_ingest_policy()
    test_chat_safety()
    test_chat_answers()
    test_history_queries()
    test_writes_still_routed()

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
