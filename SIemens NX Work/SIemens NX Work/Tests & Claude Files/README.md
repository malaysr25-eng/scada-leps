# Tests & Claude Files — the NX MCD replay

This folder lets NX MCD run the **validated MATLAB cycle** with no PLC and no
machine. A small OPC UA server stands in for the PLC. It switches the cell's
real tags — `Conveyor1..3`, `Solenoid_valve1..13`, `Engraving_Completed` — on
and off at the times the model does, and MCD's existing OPC UA client follows
it.

Written 2026-09-19. The physics stays in MATLAB; MCD shows it in 3-D and
checks it against its own collision sensors.

| File | What it is |
|---|---|
| `export_mcd_timeline.m` | Runs the model on both routes and writes the two timelines below. **Every time comes from a real run**, none is typed by hand |
| `mcd_timeline_engraved.json` | The engraved cycle, 75.65 s: every output edge, the model's sensor edges, rods and platform at 20 Hz, every state |
| `mcd_timeline_bypass.json` | The SV11 bypass, 29.74 s, same layout |
| `mcd_replay_server.py` | The OPC UA server that plays a timeline |
| `test_mcd_replay.py` | 7 tests: the timelines, and the server end to end with a real OPC UA client |

## Running it

**1. Regenerate the timelines** (only after the model changes), at the MATLAB
prompt, from this folder:

```matlab
export_mcd_timeline
```

**2. Start the server**, in a terminal, from this folder:

```bash
python mcd_replay_server.py
```

| Option | Does |
|---|---|
| `--route bypass` | the bypass cycle instead of the engraved one |
| `--host 0.0.0.0` | allow another PC to connect. The default, `127.0.0.1`, is this PC only |
| `--speed 2` | run at twice real time |
| `--loop` | repeat the cycle |
| `--positions` | also publish `Rod1_mm..Rod11_mm` and `Platform_z_mm` at 20 Hz |
| `--start-delay 20` | seconds before the cycle starts (default 10), so you can press Play in MCD |

It prints its endpoint, `opc.tcp://127.0.0.1:4840/bits-mcd/`, and every edge as
it fires.

**3. In NX MCD**, in External Signal Configuration → OPC UA:
- add the server at that endpoint, with security **None**;
- map the signals. **MCD maps by name**, so signals named like the PLC tags
  map without manual work;
- set `Proximity_sensor1..10` as outputs from MCD **to** the server. The
  server then prints, at the end of each cycle, when each of your sensors
  tripped beside when the model's did. That is the check that your MCD build
  moves like the model.

**4. Run the tests** (about 12 s):

```bash
python -m unittest test_mcd_replay -v
```

## Things the timelines show that are worth knowing

- **Belt 2 runs 0.13 s past prox 7** on the engraved route. The sequencer
  checks prox 7 only once the transfer rod is home (state S16). That is the
  model's documented behaviour (plan H7), and the tests allow for it.
- **The model holds a latching valve's opposite coil on.** Once SV8 retracts
  cylinder A it stays energised to the end of the cycle, and the same goes
  for SV10. The real PLC pulses these coils for 2 s (`T#2S`). For a latching
  valve both give the same motion. In MCD, treat SV7/SV8 as "the last one
  switched on wins".
- **`Engraving_Completed` rises at 50.17 s**, when the operator confirms (S26).
  The platform starts down 1.5 s later, at 51.67 s. The model has no reset for
  it, so it stays high to the end of the cycle.
- **Only magazine 1 fires** in a one-part cycle; SV2–SV5 stay off.

## Needs

- Python 3.8+ and `asyncua` (tested with 2.0.1): `pip install asyncua`
- MATLAB, only to regenerate the timelines. It uses `LOG.cmd_sol`, the coil
  log added to `run_factory_simulation` on 2026-09-19.
