# MATLAB / Simulink → SCADA portal — integration handoff

**For the session working on `Factory_Simulation/` (the MATLAB model).**
Written from the portal side (`new_scada/scada_platform`), 2026-09-07.

You do not need the portal's source to act on this. Everything the portal
consumes is specified here as JSON, with the exact producer commands. Nothing in
this document asks you to change the physics — only to emit what already exists,
in a shape the portal already reads.

Two things are worth reading before the spec: §6 lists real machine data that
landed since the model was last calibrated, and §7 lists strings the model
currently exports that are known to be wrong and are being shown to an operator.

---

## 1. There are two integrations, not one

| | Path A — reference export | Path B — live telemetry |
|---|---|---|
| What it is | one batch run of the model, exported as a nominal trajectory | a running MATLAB session pushing values every ~0.5 s |
| Producer | `tools/export_twin_reference.m` | `tools/matlab_live_bridge.m` |
| Consumer | `TwinAdapter` — the Digital Twin page | `MatlabSourceAdapter` — the Data Sources page |
| Status | **working, in use today** | **implemented, never run against real MATLAB** |
| Can it command the machine? | no | no, and it is structurally prevented |

**Do Path A first.** It is the one the portal actually compares against, it needs
no networking, and it is already proven end to end. Path B is a nice-to-have and
its TCP half has never seen a real `tcpclient`.

Why there is no co-simulation: `run_factory_simulation` is a batch RK4 integrator
with no stepping API. Driving a browser from it would mean either rewriting the
solver (which invalidates `CycleRegressionTest` and `compare_execution_paths`) or
blocking the HMI for a whole cycle. Exporting the nominal trajectory once gives
the operator a real reference to diverge from and leaves the model untouched.

---

## 2. Path A — the reference export

### Run it

```matlab
>> cd Factory_Simulation
>> addpath('<repo>/new_scada/scada_platform/tools')
>> export_twin_reference
```

Non-interactively:

```bash
matlab -batch "cd('Factory_Simulation'); addpath('../new_scada/scada_platform/tools'); export_twin_reference"
```

It writes `scada_platform/data/twin_reference.json`. The portal reads that path
from `config/config.json → digital_twin.reference_path`. If MATLAB runs on
another machine, write the file anywhere and copy it to that path — the portal
only ever opens the file.

Then, on the portal: **Digital Twin → Reload**, or

```bash
curl -X POST http://<portal-host>:5000/api/digital-twin/reload
curl      http://<portal-host>:5000/api/digital-twin/reference   # verify
```

### The exact schema the portal reads

```json
{
  "schemaVersion": 1,
  "exportedAt": 1788266045.5,
  "exportedAtLocal": "2026-09-07 13:50:00",
  "cycleTime": 31.030,
  "complete": true,
  "transitions": [
    {"t": 0.0,   "index": 0,  "state": "S00_INIT",     "excelRef": "row 2",  "guard": ""},
    {"t": 1.12,  "index": 4,  "state": "S04_DV_READY", "excelRef": "row 6",  "guard": "BR_RDY(1)"}
  ],
  "series": {
    "t":       [0.0, 0.05, 0.10, "..."],
    "v_belt1": [0.0, 0.0,  0.02, "..."],
    "v_belt2": ["..."],
    "v_belt3": ["..."],
    "P_res":   [5.5, 5.49, "..."],
    "base_z":  ["..."],
    "blk_x":   ["..."],
    "blk_y":   ["..."],
    "rod1":    ["..."]
  },
  "parameters": [{"name": "D_bore", "tag": "JAN"}],
  "caveats": ["..."],
  "meta": {
    "source": "run_factory_simulation",
    "matlabVersion": "...",
    "stateCount": 40,
    "sampleCount": 622,
    "sampleRateHz": 20,
    "originalSamples": 6216,
    "positionErrorM": 0.0007,
    "airPerCycleNL": 0.0
  }
}
```

### What is load-bearing, and what is decoration

These are consumed by code and will break the comparison if they change:

| Field | Consumed by | Contract |
|---|---|---|
| `series.t` | nearest-sample lookup | **strictly ascending seconds from cycle start.** Flat array, not an array of 1-element arrays (`roundvec` already forces a row vector — keep it) |
| `series.v_belt1` / `v_belt2` / `v_belt3` | the conveyor real-vs-predicted panel | **these exact names.** m/s. Same length as `t` |
| `series.P_res` | the receiver-pressure panel | **bar gauge**, not Pa. The exporter's `/1e5` is doing that conversion — keep it, the PLC reads bar |
| `transitions[].t` | timing-divergence alarm | seconds from cycle start |
| `transitions[].state` | state agreement | **must equal the portal's `STEPS[].twin_state`** — see below |
| `transitions[].index` | display | **0-based**, matching `export_equivalence_data.m` |
| `cycleTime` | the nominal figure on screen | seconds |
| `caveats[]` | rendered verbatim, in amber, at the top of the operator's page | see §7 — these are currently wrong |

Everything else (`base_z`, `blk_x/y`, `rod*`, `parameters`, `meta`) is carried
and displayed but nothing computes against it. Adding a new series key is safe:
it appears in `predicted.*` and is ignored by anything that does not ask for it.

### The state-name contract

`backend/state/sequence.py` transcribes `factory_states.m` — same 40 states, same
Excel row references, same guard names. Agreement is a **string comparison**
between `transitions[].state` and the portal's `STEPS[].twin_state`:

```
S00_INIT, S01_CAMERA_DETECT, S02_PUMP_CMD, S03_PRESSURE_PREP, S04_DV_READY,
S05_DV_SEL_FEEDER, S06_A…, S07_PROX…, S08_A…, S09_CONV…, S10_PROX…, S11_CONV…,
S12_DV_SEL_FEEDER, S13_A…, S14_A…, S15_CONV…, S16_PROX…, S17_CONV…,
S18_DV_SEL_SECOND, S19_S…, S20_S…, S21_S…, S22_BASE_UP, S23_HEIGHT_TOP,
S24_OPERATOR_NOTICE, S25_ENGRAVE_MANUAL, S26_ENGRAVE_CONFIRM, S27_BASE_DOWN,
S28_HEIGHT_BOTTOM, …
```

**If you rename or renumber a state in `factory_states.m`, tell the portal side
in the same breath** — the two files have to move together or every state reads
`DIVERGENT` while both sides are individually correct.

### Without MATLAB

`python tools/make_sample_twin_reference.py` writes a synthetic reference for
exercising the plumbing. State names are real, **every timing is fabricated**,
and it self-labels `meta.synthetic: true`. Test fixture only.

> **Read this before anything else.** The file sitting at
> `data/twin_reference.json` on the portal right now **is that synthetic
> sample** — `cycleTime: 29.78`, 40 transitions, and
> `meta.source: "SYNTHETIC SAMPLE -- NOT FROM MATLAB"`. `INPUTS_REQUIRED.md`
> records it as having been regenerated from `run_factory_simulation` with the
> real 31.030 s cycle; that is not what is on disk. So the Digital Twin page is
> currently comparing a live machine against invented timings. **Producing a
> real export is the first job on this list**, and it is worth more than
> anything else in this document.

---

## 3. Path B — live telemetry

### Configuration (portal side, `config/config.json`)

```json
"sources": {
  "matlab": {
    "enabled": true,
    "transport": "mock",              // ← currently mock; set to "file" or "tcp"
    "data_path": "data/matlab_live.json",
    "host": "127.0.0.1",
    "port": 5560,
    "poll_interval": 0.5,
    "stale_after": 5.0,
    "mock_cycle_seconds": 31.08
  }
}
```

The adapter auto-starts with the backend when `enabled` is true. It can also be
driven through `POST /api/sources/matlab/start` · `/stop`, and shown on the
dashboards with `POST /api/sources/telemetry {"sourceId":"matlab"}`.

### Wire format — either shape is accepted

```json
{"timestamp": 1788266045.5, "modelName": "Factory_Physics_Model",
 "values": {"sim_belt1_speed": 0.15, "sim_receiver_pressure": 5.4}}
```

```json
{"sim_belt1_speed": 0.15, "sim_receiver_pressure": 5.4}
```

`timestamp` must be **the time the values were sampled**, POSIX seconds UTC — the
adapter ages the feed against it and marks it `STALE` past `stale_after`. Signal
names are free-form; nothing maps them into the twin comparison. They show on the
Data Sources page and go into recordings.

### MATLAB side

```matlab
% file transport — the default, and the one to prefer
vals = @() struct( ...
    'sim_belt1_speed',       get_param('Factory_Physics_Model/Belt1','RuntimeObject').OutputPort(1).Data, ...
    'sim_receiver_pressure', evalin('base','P_res_now'));

matlab_live_bridge('transport','file', ...
                   'path','<...>/scada_platform/data/matlab_live.json', ...
                   'values', vals, 'rate', 2);
```

```matlab
% tcp transport — UNTESTED against a real MATLAB
matlab_live_bridge('transport','tcp','host','127.0.0.1','port',5560,'values',vals);
```

**The atomic write is not optional.** Write to `<target>.tmp` in the same
directory, then `movefile`. Writing straight to the target lets the reader land
between `fopen` (which truncates) and `fclose` and get a half-written file —
that exact defect is what made the legacy SCADA blank every tag for a frame.
`matlab_live_bridge.m` already does this; do not "simplify" it.

### What is proven and what is not

| | status |
|---|---|
| `mock` transport | tested (`selftest_extended.py` §12) |
| `file` transport | tested against a fixture |
| `tcp` transport | **never run against a real MATLAB** |
| a real Simulink model streaming either way | **never run** |

So the first live attempt is a test, not a deployment. Check, in order: does
`data/matlab_live.json` appear and change; does `GET /api/sources/matlab` show
`state: CONNECTED` with a rising `sequence` and a non-zero `signalCount`; does
the Data Sources page label it. If `tcp` misbehaves, fall back to `file` — the
adapter's TCP half expects **one JSON object per line, newline-terminated,
UTF-8**, and a missing newline will simply buffer forever.

### The safety property, so you can rely on it

`MatlabSourceAdapter.supports_control = False`. Three independent barriers:
`SourceManager.set_control_source('matlab')` refuses with a 409,
`send_command()` refuses on its own, and `SourceManager.write()` only ever routes
to the active *control* source. **A simulated value cannot reach the PLC.** You
do not need to defend against that in the model.

---

## 4. Where the portal lives, concretely

| | |
|---|---|
| Repo | `C:\Users\DELL\Desktop\new_scada\scada_platform` |
| Start | `python run.py` (`--simulate` for no hardware). Never enable the reloader — it forks a second Snap7 client |
| Binds | `0.0.0.0:5000`. Note an unrelated Werkzeug app currently holds `127.0.0.1:5000` on this PC, so reach the portal on the machine's LAN address (e.g. `http://172.21.30.25:5000`), not loopback |
| PLC | Siemens S7 at `172.21.30.157`, rack 0 slot 1, snap7, 250 ms poll, 158 tags, all in DB59 |
| Health | `GET /api/health` → `{"plc":"CONNECTED","plcSimulated":false,"tags":158}` |
| Twin | `GET /api/digital-twin/state`, `GET /api/digital-twin/reference`, `POST /api/digital-twin/reload` |
| Sources | `GET /api/sources`, `POST /api/sources/telemetry`, `POST /api/sources/<id>/start` |
| History | `data/scada_history.db` (SQLite) — cycles, events, tag samples, recordings |

---

## 5. Which file each input goes into (unchanged, restated so nothing drifts)

- Manufacturer figures → `JanaticsData.m`. Never straight into `FactoryParams.m`.
- Everything else measured → `FactoryParams.m`, keeping the provenance tag and
  changing it to reflect the new source.
- Placement, which coil drives which barrel → `factory_io_map.m`.
- After any edit: `reset_factory`, then `run_all_tests`, then **re-export** the
  twin reference and reload it on the portal. The pinned baselines in
  `verify_model.m` **and** `tests/CycleRegressionTest.m` both need updating after
  a deliberate parameter change — a failure there is a prompt to re-baseline.

---

## 6. Real machine data that landed since the model was last calibrated

All of this came off the real cell through the portal, and none of it is in the
model yet. Sources: the live PLC read at 13:50 on 2026-09-07, and five real
cycles in `data/scada_history.db` (`cycle_history`, `historical_tag_data`,
`tag_samples`) recorded 09-01, 09-03 and 09-07. Every one of those cycles ran the
**50 mm product** from **compartment 1**.

**The headline: machine time is ~62.6 s, not 18.58 s.**
Subtract the operator's dwell at the engraving platform from each recorded cycle
and the remainder is **61.3, 63.0, 63.4, 63.2, 62.2 s** — two seconds of spread
across five cycles on three days. The model's machine time is 18.58 s. That is
3.4×, and it is not operator variance. Whole cycles ran 68.9–90.0 s against the
model's 31.08 s nominal.

**Correction to carry into the record:** the 18.146 s and 17.732 s cycles
recorded in `INPUTS_REQUIRED.md` as the real cell are **not** the cell. Both ran
while the portal's connection state was `SIMULATED` (the built-in PLC stand-in),
and it shows: pressure pinned at exactly 6.2 bar, belt velocities of exactly
0.150 and 0.200 m/s — the model's own parameters — and not one proximity sensor
or magazine pusher transition in either cycle. The "within 5%" agreement was the
model agreeing with itself.

**Timings measured off the recorded cycles** (1 Hz sampling, so ±1 s):

| Interval | Real | Model |
|---|---|---|
| Magazine pusher SV1 energised | 2.77 s | — |
| Conveyor 1 run, pusher → prox 6 | 4.77 s | — |
| Conveyor 2 run (prox 7 at 2.62 s) | 3.15 s | — |
| Cylinder A extend coil energised | 8.13 s | — |
| Cylinder A retract coil energised | 11.99 s (≈ the T#12S preset) | — |
| Platform travel, limit to limit | 7.7–8.3 s, both directions | — |
| Operator dwell at the top | 28.7 / 6.0 / 8.8 / 7.3 / 17.5 s | 8.0 s `[PLH]` |
| Confirm press → platform moves | 1.3 s | 1.5 s `[PLH]` |
| Conveyor 3 run → prox 9 | 1.02 s | — |
| Outfeed pulse SV12 | 4.94 s (the T#5S preset) | — |
| Whole cycle | 90.0 / 68.9 / 72.1 / 70.5 / 79.7 s | 31.08 s |

**Sequence facts that contradict the model's structure:**

- **Solenoid 11 never fired** in any real cycle. The engrave → conveyor 3 move
  was done by **cylinder B (coils 9/10)**, which fires *after* the platform
  lowers and *before* conveyor 3 runs. `FACTORY_ACTUATORS` assigns that role to
  `eng_out` on cylinder B already; what this does contradict is the owner's
  statement that cylinder B fires only when engraving is *skipped*. Both cannot
  be true — treat the recording as the stronger evidence for the engraving path,
  and leave the bypass question open.
- **Solenoid 13 and proximity sensor 10 never fired.** Outfeed B is unexercised;
  the model's "second outfeed at 60% along conveyor 3" is still invention.
- **Proximity sensor 8 never tripped.** The part reached the platform via prox 7
  and cylinder A, so the `FC6 N5` path did not run in the recorded cycle.
- Conveyor 1 stops on prox 6 in the same scan it trips → prox 6 is at the belt
  **end**. Prox 9 trips 1.02 s after conveyor 3 starts → near the **start** of
  conveyor 3, not the far end. Prox 7 trips at 2.62 s of a 3.15 s run → nearer
  the end than the midpoint, despite the `WP IN CV2 MID` network title.

**Live PLC readings, 2026-09-07:**

| Quantity | Real | Model |
|---|---|---|
| Supply pressure | 4.379 bar; 4.03–4.38 through a cycle, no 6/8 bar sawtooth | `P_res_0` 5.5, cut-in/out 6.0/8.0 `[ASM]` |
| Pressure alarm limits | 1.0 / 5.0 bar | — |
| Axis `Set_Velocity`, all three | 180.0 (unit unstated); high- and low-speed both 180.0 | `v_belt` 0.150 m/s `[ASM]` |
| `Current_Position_Fb` | **not a stuck default** — Conv1 reads 25.0 and swept 2.0 → 25.0 during a cycle; Conv2 1.8 → 30.0; Conv3 2.0 → 30.15 | not modelled |
| `Set_Position` | Conv1 25.0, Conv2/3 30.0; `HighSpeed_Position` 30 / 150 / 150 | — |
| Product selection | `qty_50mm = 1`, `qty_25mm = 0` | model has one product |
| Magazine | all five compartments `Ok` | 5 modelled |
| Cylinder position feedback | **none** — 158 tags, no reed-switch input anywhere | `y.EXT`/`y.RET` computed from rod position |

**Cylinder bore, still the largest single sensitivity:** the CAD says this cell
contains ⌀32/rod 12 (part `1202510000`, folders A27/A28, Parasolid parts labelled
`Ø32 FEC` / `Ø32 REC`) and ⌀8/rod 4 (part `1501160000`, folders A51/A52).
`JanaticsData.m`'s ⌀20/rod 8 matches neither, and `A53/A54` appears nowhere in
the CAD. At 6 bar that is 30 N vs 482 N against the model's 188 N. Which barrel
is cylinder A and which is B is still an unanswered panel test.

None of the above is applied to the model — it is reported so you can decide what
to apply and in what order, and so no one re-derives it.

---

## 7. Strings the model exports that are wrong, and are on an operator's screen

`export_twin_reference.m` hard-codes a `caveats` list that the portal renders
verbatim, in amber, at the top of the Digital Twin page. Three entries are known
to be overturned:

1. `"SCALE ... is recorded as CONFIRMED INCORRECT"` — **overturned 2026-08-26.**
   SCALE = 0.1000 is confirmed *correct*, four independent ways.
2. `"The model has 5 cylinders and 4 proximity sensors ... The mapping between
   them is not recorded in any supplied source"` — **overturned.** The model
   carries 11 actuators on 13 coils and all 10 proximity sensors, and the PLC
   listing mapped every address on 2026-08-30.
3. `"12.5 s of the 31.08 s nominal cycle"` — the operator share is real, but the
   figures are stale against the measurements in §6.

A fourth, of the same family: `INPUTS_REQUIRED.md` says
`data/twin_reference.json` "has been regenerated from `run_factory_simulation`
and now carries the real 31.030 s cycle, 39 transitions and 12 trajectories."
The file on the portal is the synthetic sample — 29.78 s, and it says so in its
own `meta.source`. Whatever regeneration happened did not reach this disk.

This is exactly the failure `DocumentationFactsTest` exists to catch, living on
in a file that test does not read. Worth fixing in the exporter (and worth a test
that reads it), because the portal deliberately does not edit these — it shows
what the model says about itself.

Two dangling references, neither of which is a missing file on your side:
`matlab_source.py`'s docstring cites `tools/matlab_sim_bridge.py`, and the
engraving intake sheet cites `Project_Notes/tools/widen_scada_watch.py`. Neither
exists in this repo.

---

## 8. Checklist

Path A, in order:

1. `run_all_tests` green on the model as it stands.
2. `export_twin_reference` → confirm the console prints a transition count and a
   sample count, and that `cycleTime` is what you expect. This replaces a
   synthetic sample that is live on the operator's screen today — check
   `meta.source` reads `run_factory_simulation` in the file you produce.
3. Copy `twin_reference.json` to `scada_platform/data/` if MATLAB is elsewhere.
4. `POST /api/digital-twin/reload`, then `GET /api/digital-twin/reference` and
   check `transitions` is non-empty and `series` lists `v_belt1..3` and `P_res`.
5. Watch one real cycle on the Digital Twin page. Expect large timing divergence
   — §6 says why — and expect state agreement to hold. If states read
   `DIVERGENT` while timings look sane, the state-name contract has drifted.

Path B, only after A:

6. Set `sources.matlab.transport` to `file`, restart the portal, run
   `matlab_live_bridge` with a real `values` handle, confirm `GET
   /api/sources/matlab` shows `CONNECTED`, a rising `sequence`, and your signal
   count. Report back whether it worked — nobody has run this yet.

Back to the portal side, when convenient: whether you renamed any state, whether
`cycleTime` moved, and which of §6 you applied — the portal's own text about the
model needs to move with it.
