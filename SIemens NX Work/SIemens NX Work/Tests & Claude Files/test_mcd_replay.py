"""
Tests for the NX MCD replay: the exported timelines, and the OPC UA server.

    python -m unittest test_mcd_replay -v

The timeline tests check the JSON that export_mcd_timeline.m writes. The server
test starts mcd_replay_server.py for real, connects an OPC UA client the way
MCD would, watches the coils switch, writes a proximity sensor back, and reads
the server's end-of-cycle check. It runs at x10 speed, about 10 s.
"""
import asyncio
import json
import os
import socket
import subprocess
import sys
import time
import unittest

HERE = os.path.dirname(os.path.abspath(__file__))
SCAN = 0.03   # a PLC scan to command, a scan to sense, and the log's step


def load(route):
    with open(os.path.join(HERE, "mcd_timeline_%s.json" % route), encoding="utf-8") as f:
        return json.load(f)


def level_at(edges, t):
    v = bool(edges[0][1])
    for et, ev in edges:
        if float(et) <= t:
            v = bool(ev)
    return v


def rises(edges):
    return [float(t) for t, v in edges if v and float(t) > 0]


def falls(edges):
    return [float(t) for t, v in edges if not v and float(t) > 0]


class TimelineTest(unittest.TestCase):

    def test_both_routes_exist_and_match_the_model(self):
        self.assertAlmostEqual(load("engraved")["cycle_time_s"], 75.65, places=2)
        self.assertAlmostEqual(load("bypass")["cycle_time_s"], 29.74, places=2)

    def test_every_output_starts_off_and_alternates(self):
        for route in ("engraved", "bypass"):
            for tag, edges in load(route)["outputs"].items():
                self.assertEqual(float(edges[0][0]), 0.0, tag)
                self.assertFalse(edges[0][1], "%s %s should start off" % (route, tag))
                vals = [bool(v) for _, v in edges]
                self.assertTrue(all(a != b for a, b in zip(vals, vals[1:])),
                                "%s %s has two edges the same way" % (route, tag))

    def test_the_latching_coils_never_fight(self):
        # SV7/SV8 and SV9/SV10 drive one double-solenoid valve each.
        o = load("engraved")["outputs"]
        times = sorted({float(t) for e in o.values() for t, _ in e})
        for a, b in (("Solenoid_valve7", "Solenoid_valve8"),
                     ("Solenoid_valve9", "Solenoid_valve10")):
            for t in times:
                self.assertFalse(level_at(o[a], t) and level_at(o[b], t),
                                 "%s and %s both on at %.2f s" % (a, b, t))

    def test_each_belt_stops_when_its_sensor_is_checked(self):
        # A belt stops within a scan of the LATER of (a) its sensor tripping and
        # (b) the sequencer reaching the state that checks that sensor. On the
        # engraved route belt 2 shows why (b) matters: the block reaches prox 7
        # at 19.90 s, but S16 is entered only when the transfer rod is home, at
        # 20.01 s, so the belt runs 0.13 s past the sensor. That is the model's
        # documented behaviour (ITERATION_LOG, plan H7), not a timing error.
        pairs = {"engraved": (("Conveyor1", "Proximity_sensor6", "S10_PROX2_CHECK"),
                              ("Conveyor2", "Proximity_sensor7", "S16_PROX3_CHECK"),
                              ("Conveyor3", "Proximity_sensor9", "S34_PROX4_FINAL")),
                 "bypass":   (("Conveyor1", "Proximity_sensor6", "S10_PROX2_CHECK"),
                              ("Conveyor2", "Proximity_sensor8", "S16_PROX3_CHECK"),
                              ("Conveyor3", "Proximity_sensor9", "S34_PROX4_FINAL"))}
        for route, ps in pairs.items():
            d = load(route)
            entered = {name: float(t) for t, name in d["states"]}
            for conv, prox, check in ps:
                stop = falls(d["outputs"][conv])[0]
                trip = rises(d["expected_sensors"][prox])[0]
                ready = max(trip, entered[check])
                self.assertGreaterEqual(stop, trip - 1e-9, "%s %s" % (route, conv))
                self.assertLessEqual(stop - ready, SCAN, "%s %s stops %.3f s after %s/%s"
                                     % (route, conv, stop - ready, prox, check))

    def test_the_routes_differ_where_they_should(self):
        e, b = load("engraved")["outputs"], load("bypass")["outputs"]
        self.assertTrue(rises(e["Solenoid_valve7"]) and not rises(b["Solenoid_valve7"]))
        self.assertTrue(rises(b["Solenoid_valve11"]) and not rises(e["Solenoid_valve11"]))
        self.assertTrue(rises(e["Engraving_Completed"]))
        self.assertFalse(rises(b["Engraving_Completed"]))

    def test_positions_are_sampled_at_20_hz(self):
        p = load("engraved")["positions"]
        self.assertEqual(len(p["rod_names"]), 11)
        dt = [b - a for a, b in zip(p["t"], p["t"][1:])]
        self.assertTrue(all(abs(x - 0.05) < 1e-6 for x in dt))
        self.assertEqual(len(p["Platform_z_mm"]), len(p["t"]))


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class ServerTest(unittest.TestCase):
    """The real server, a real client, at x10 speed."""

    SPEED = 10.0

    def test_a_client_sees_the_cycle_and_the_server_sees_the_client(self):
        port = free_port()
        proc = subprocess.Popen(
            [sys.executable, os.path.join(HERE, "mcd_replay_server.py"),
             "--port", str(port), "--speed", str(self.SPEED), "--start-delay", "2",
             "--exit-after"],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
        try:
            seen = asyncio.run(self._client(port))
            out, _ = proc.communicate(timeout=60)
        finally:
            if proc.poll() is None:
                proc.kill()
        self.assertEqual(proc.returncode, 0, out)

        # the order the model switches them in
        self.assertEqual(seen["Conveyor1"], [True, False], seen)
        self.assertEqual(seen["Solenoid_valve1"], [True, False], seen)
        self.assertEqual(seen["Solenoid_valve7"][:1], [True], seen)
        self.assertEqual(seen["Engraving_Completed"], [True], seen)
        # the server recorded the sensor the client wrote, and compared it
        line = [l for l in out.splitlines() if "Proximity_sensor6" in l]
        self.assertTrue(line, out)
        self.assertNotIn("did not write", line[-1])

    async def _client(self, port):
        from asyncua import Client
        url = "opc.tcp://127.0.0.1:%d/bits-mcd/" % port
        for _ in range(100):                        # wait for the server to come up
            try:
                client = Client(url)
                await client.connect()
                break
            except (OSError, asyncio.TimeoutError, ConnectionError):
                await asyncio.sleep(0.1)
        else:
            self.fail("server did not start on %s" % url)
        try:
            ns = await client.get_namespace_index("urn:bits-wilp:mcd-replay")
            watch = ["Conveyor1", "Solenoid_valve1", "Solenoid_valve7", "Engraving_Completed"]
            nodes = {t: client.get_node("ns=%d;s=%s" % (ns, t)) for t in watch}
            prox6 = client.get_node("ns=%d;s=Proximity_sensor6" % ns)
            t_node = client.get_node("ns=%d;s=Replay_Time_s" % ns)
            last = {t: False for t in watch}
            seen = {t: [] for t in watch}
            wrote = False
            deadline = time.monotonic() + 40
            while time.monotonic() < deadline:
                for t, n in nodes.items():
                    v = bool(await n.read_value())
                    if v != last[t]:
                        seen[t].append(v)
                        last[t] = v
                sim_t = float(await t_node.read_value())
                if not wrote and sim_t >= 16.5:          # act as MCD's sensor at belt 1's end
                    await prox6.write_value(True)
                    wrote = True
                if seen["Engraving_Completed"] and sim_t >= 60:
                    break
                await asyncio.sleep(0.01)
            return seen
        finally:
            await client.disconnect()


if __name__ == "__main__":
    unittest.main(verbosity=2)
