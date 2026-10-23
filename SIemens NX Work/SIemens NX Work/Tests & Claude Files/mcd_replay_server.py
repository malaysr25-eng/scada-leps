#!/usr/bin/env python3
"""
mcd_replay_server.py - play the validated MATLAB cycle to NX MCD over OPC UA.

    python mcd_replay_server.py                       engraved route, real time, this PC only
    python mcd_replay_server.py --route bypass
    python mcd_replay_server.py --host 0.0.0.0        let another PC (the one with NX) connect
    python mcd_replay_server.py --loop --speed 2      repeat forever at twice real time
    python mcd_replay_server.py --positions           also publish rod and platform positions

WHAT IT DOES
------------
It stands in for the PLC. It publishes the signals a PLC drives, named exactly
as the cell's real tags, and switches them on and off at the times the MATLAB
model switched them:

    Conveyor1..3, Solenoid_valve1..13, Engraving_Completed      (read by MCD)

MCD's own collision sensors are the other half. The server offers writable
Proximity_sensor1..10 variables; if MCD's signal mapping writes its sensors
back, the server records when each one tripped and, at the end of the cycle,
prints them beside the times the MATLAB model expects. That is the check that
your MCD build moves like the model.

The times come from mcd_timeline_<route>.json, written by
export_mcd_timeline.m from a real model run. Nothing in here is hand-typed.

CONNECTING NX MCD
-----------------
Endpoint:  opc.tcp://<host>:<port>/bits-mcd/     (default opc.tcp://127.0.0.1:4840/bits-mcd/)
Security:  None, anonymous. This is a local test server; do not expose it
           beyond the lab network.
Nodes:     ns=<n>;s=<TagName>, e.g. ns=2;s=Solenoid_valve7. MCD's automatic
           mapping matches by name, so MCD signals named like the PLC tags map
           without manual work.

The cycle starts --start-delay seconds (default 10) after launch, so there is
time to connect MCD and press Play. Ctrl+C stops it.

Needs: pip install asyncua  (tested with 2.0.1). Python 3.8+.
"""
import argparse
import asyncio
import json
import logging
import os
import sys
import time

from asyncua import Server, ua

HERE = os.path.dirname(os.path.abspath(__file__))
SENSORS = ["Proximity_sensor%d" % i for i in range(1, 11)]
log = logging.getLogger("mcd-replay")


def load_timeline(route, folder):
    path = os.path.join(folder, "mcd_timeline_%s.json" % route)
    if not os.path.exists(path):
        sys.exit("No %s. Run export_mcd_timeline in MATLAB first." % path)
    with open(path, encoding="utf-8") as f:
        return json.load(f), path


def output_events(outputs):
    """[(t, tag, value)] for every change after t = 0, in time order."""
    ev = []
    for tag, edges in outputs.items():
        for t, v in edges[1:]:
            ev.append((float(t), tag, bool(v)))
    ev.sort(key=lambda e: e[0])
    return ev


def first_rises(edges):
    return [float(t) for t, v in edges if v and float(t) > 0]


async def run(args):
    doc, path = load_timeline(args.route, args.timeline_dir)
    outputs = doc["outputs"]
    events = output_events(outputs)
    cycle = float(doc["cycle_time_s"])
    pos = doc["positions"] if args.positions else None

    server = Server()
    await server.init()
    endpoint = "opc.tcp://%s:%d/bits-mcd/" % (args.host, args.port)
    server.set_endpoint(endpoint)
    server.set_server_name("BITS MCD replay - validated MATLAB cycle")
    server.set_security_policy([ua.SecurityPolicyType.NoSecurity])
    idx = await server.register_namespace("urn:bits-wilp:mcd-replay")
    plc = await server.nodes.objects.add_object(ua.NodeId("PLC", idx), "PLC")

    nodes = {}
    for tag, edges in outputs.items():
        nodes[tag] = await plc.add_variable(ua.NodeId(tag, idx), tag, bool(edges[0][1]))
    sensor_nodes = {}
    for tag in SENSORS:
        n = await plc.add_variable(ua.NodeId(tag, idx), tag, False)
        await n.set_writable()
        sensor_nodes[tag] = n
    pos_nodes = {}
    if pos:
        keys = ["Platform_z_mm"] + ["Rod%d_mm" % i for i in range(1, len(pos["rod_names"]) + 1)]
        for k in keys:
            pos_nodes[k] = await plc.add_variable(ua.NodeId(k, idx), k, float(pos[k][0]))
    t_node = await plc.add_variable(ua.NodeId("Replay_Time_s", idx), "Replay_Time_s", 0.0)
    r_node = await plc.add_variable(ua.NodeId("Replay_Route", idx), "Replay_Route", args.route)

    log.info("Timeline  %s (%s, cycle %.2f s, model commit %s)", os.path.basename(path),
             args.route, cycle, doc["source"].get("commit", "?"))
    log.info("Endpoint  %s   namespace ns=%d   security None", endpoint, idx)

    async with server:
        n_cycle = 0
        while True:
            n_cycle += 1
            for tag, edges in outputs.items():                 # back to the start
                await nodes[tag].write_value(bool(edges[0][1]))
            for n in sensor_nodes.values():
                await n.write_value(False)
            if args.start_delay > 0:
                log.info("Cycle %d starts in %.0f s - connect MCD and press Play.",
                         n_cycle, args.start_delay)
                await asyncio.sleep(args.start_delay)
            log.info("Cycle %d: %s route, %.2f s at x%.2f speed", n_cycle, args.route,
                     cycle, args.speed)
            seen = await play(events, nodes, sensor_nodes, pos, pos_nodes, t_node,
                              cycle, args.speed)
            report(doc["expected_sensors"], seen)
            if not args.loop:
                break
        if args.exit_after:
            return
        log.info("Cycle finished. Holding the final values; Ctrl+C to stop.")
        while True:
            await asyncio.sleep(1)


async def play(events, nodes, sensor_nodes, pos, pos_nodes, t_node, cycle, speed):
    """Fire each edge at its time; poll MCD's sensor writes; return their rises."""
    seen = {tag: [] for tag in sensor_nodes}
    last = {tag: False for tag in sensor_nodes}
    t0 = time.monotonic()
    i, next_pos = 0, 0.0
    while True:
        t = (time.monotonic() - t0) * speed
        while i < len(events) and events[i][0] <= t:
            et, tag, v = events[i]
            await nodes[tag].write_value(v)
            log.info("  %7.2f s  %-20s %s", et, tag, "ON" if v else "off")
            i += 1
        if pos and t >= next_pos:
            k = min(int(round(t / 0.05)), len(pos["t"]) - 1)
            for name, node in pos_nodes.items():
                await node.write_value(float(pos[name][k]))
            next_pos += 0.05
        for tag, node in sensor_nodes.items():
            v = bool(await node.read_value())
            if v and not last[tag]:
                seen[tag].append(t)
            last[tag] = v
        await t_node.write_value(float(t))
        if t >= cycle and i >= len(events):
            return seen
        await asyncio.sleep(0.005)


def report(expected, seen):
    log.info("Sensor check - MCD's trips against the MATLAB model's (first rise):")
    log.info("  %-20s %10s %10s %9s", "sensor", "model (s)", "MCD (s)", "diff (s)")
    for tag in SENSORS:
        exp = first_rises(expected.get(tag, []))
        got = seen.get(tag, [])
        e = "%10.2f" % exp[0] if exp else "%10s" % "-"
        g = "%10.2f" % got[0] if got else "%10s" % "-"
        d = "%+9.2f" % (got[0] - exp[0]) if exp and got else "%9s" % ""
        note = "" if got else ("   MCD did not write it" if exp else "")
        log.info("  %-20s %s %s %s%s", tag, e, g, d, note)


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--route", choices=["engraved", "bypass"], default="engraved")
    ap.add_argument("--speed", type=float, default=1.0, help="1 = real time")
    ap.add_argument("--host", default="127.0.0.1",
                    help="127.0.0.1 = this PC only (default); 0.0.0.0 = the network")
    ap.add_argument("--port", type=int, default=4840)
    ap.add_argument("--start-delay", type=float, default=10.0,
                    help="seconds before each cycle starts (default 10)")
    ap.add_argument("--loop", action="store_true", help="repeat the cycle")
    ap.add_argument("--positions", action="store_true",
                    help="also publish Rod1_mm..Rod11_mm and Platform_z_mm at 20 Hz")
    ap.add_argument("--timeline-dir", default=HERE)
    ap.add_argument("--exit-after", action="store_true",
                    help="exit when the cycle ends (used by the tests)")
    args = ap.parse_args()
    if args.speed <= 0:
        ap.error("--speed must be positive")
    logging.basicConfig(level=logging.INFO, format="%(asctime)s %(message)s",
                        datefmt="%H:%M:%S")
    logging.getLogger("asyncua").setLevel(logging.WARNING)
    try:
        asyncio.run(run(args))
    except KeyboardInterrupt:
        log.info("Stopped.")


if __name__ == "__main__":
    main()
