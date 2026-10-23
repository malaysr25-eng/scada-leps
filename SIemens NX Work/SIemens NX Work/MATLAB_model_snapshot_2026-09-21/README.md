# Factory Simulation — Digital Twin of a Multi-Station Shopfloor Lab Cell

A physics-based digital twin of a five-station automated assembly cell: a
workpiece is detected by a camera, transferred between three conveyors by five
pneumatic actuators, raised for laser engraving, and ejected into a bin. The
model reproduces the 42-step operating sequence defined in `Sequence.xlsx`.

**What makes it a twin rather than an animation:** the PLC advances only when a
simulated *physical sensor* confirms the commanded action actually happened.
Positions come from integrating equations of motion, not from interpolation.
Delete the visualiser and the simulation result is unchanged.

### The project goal is fidelity, not speed

The objective is to **mimic the physical apparatus as closely as possible**.
Wall-clock runtime is explicitly *not* a metric. A change that makes the model
faster but less faithful is a regression here, not an improvement. Two known
runtime speedups are documented and deliberately declined for exactly this
reason (`Project_Notes/HANDOFF.md` §5, issue 9).

Where the model stands against the real cell today:

| | Status |
|---|---|
| Sequencing driven by simulated physical sensors | **Faithful** — 18/18 guards physically true at transition, only 3 timed transitions, all of them manual operator steps |
| Pneumatics: polytropic chambers, ISO 6358 flow, meter-out control | **Faithful in form**, parameters provisional |
| PLC scan behaviour, including output latency | **Faithful in form** — `P.plc_io_delay` models the real read/execute/write cycle. Actual scan time **not measured** |
| Both execution paths agree | **Exact** — MATLAB and Simulink are bit-identical in final position |
| Dimensions and hardware | **Partly faithful.** `SCALE = 0.10` **confirmed four ways**. The **workpiece is measured and applied** — 100 × 100 × 40 mm of wood, 0.300 kg. Cylinder bores are the open gap: the CAD shows the cell runs **bore 8 and bore 32**, and the model assumes 20 |
| Operator timings | **Not yet faithful** — 12.5 s of the 75.65 s cycle is placeholder |
| Variability | **Not faithful, and now known to be structural** — the model is deterministic, but engraving ends when an **operator presses a button** (confirmed 2026-08-25). 12.5 s of the 75.65 s cycle is human-paced, so cycle time is not a predictable quantity. The honest prediction is **machine time, ~57.35 s to the point where the real recorder stops its clock** (63.15 s if the outfeed push and retract after that point are counted), with an operator distribution on top — and that distribution is now MEASURED: mean 13.98 s, range 5.95–28.65 s, stdev 7.83 s over seven real cycles |

The first four are structural and done. The last three need measurements from
the real cell — see **`INPUTS_REQUIRED.md`**.

---

> **Picking this up cold, or starting a new session?** Read
> **`Project_Notes/START_HERE.md`** — a 5-minute router that points you into the
> right section of `Project_Notes/HANDOFF.md`, which carries the full project
> state, every decision already made, and the open issues.
> `Project_Notes/ITERATION_LOG.md` has the history, newest first. None of those
> are needed to run anything; they are the working record, kept out of the
> simulation folder so it can be shared on its own.

## Contents

1. [What this model represents](#1-what-this-model-represents)
2. [Requirements](#2-requirements)
3. [Quick start](#3-quick-start)
4. [Repository structure](#4-repository-structure)
5. [How to run](#5-how-to-run)
6. [Outputs](#6-outputs)
7. [What each file does](#7-what-each-file-does)
8. [Architecture and data flow](#8-architecture-and-data-flow)
9. [Testing](#9-testing)
10. [Parameters and provenance](#10-parameters-and-provenance)
11. [Known limitations and assumptions](#11-known-limitations-and-assumptions)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. What this model represents

| Physical element | Modelled as |
|---|---|
| Compressor + receiver | Isothermal fixed-volume vessel with pressure-switch hysteresis and a safety relief |
| FRL air preparation | Ideal reducing valve, `P_supply = min(P_receiver, P_set)` |
| Distribution valve | 4-branch manifold with first-order spool dynamics |
| 11 pneumatic actuators on 13 coils | Polytropic chambers with moving boundary, ISO 6358 restriction flow, meter-out speed control, per-actuator bore. Two are double-solenoid latching valves |
| 3 conveyors | DC drivetrain referred to the pulley shaft, PI speed loop with ramp limiting |
| Engraving base | Position-controlled vertical axis with force and speed limits |
| Workpiece | Rigid body on a support surface, Hunt-Crossley contact, regularised Coulomb friction |
| Proximity / reed / height sensors | Pure functions of physical state, with a transport delay |
| PLC | 44-state scan-based sequencer, two routes (40 states engraved, 4 more for the SV11 bypass), 10 ms scan, sensor-guarded transitions |

**Cycle:** 75.65 s, of which 12.5 s is operator/engraving placeholder time and
63.15 s is machine time.

**Against the real cell, compare 69.85 s and 57.35 s instead.** The machine's
recorder stops its clock when the last outfeed push *starts* (S37). The 75.65 s
runs on 5.80 s through that push and its retract. To the same end point the
model's machine time is 57.35 s against a measured 64.03 s, so the model is
**about 1.12× too fast**. Over 2026-09-12/13 it went 1.23× (H1) → 1.07× (H2,
the start delay) → 1.10× (H3, belt 3) → 1.13× (H4, belt speeds) → 1.15× (H5,
push and belt together) → 1.13× (H6, the wait before cylinder A) → 1.12× (H7,
nameplate bores and strokes) → 1.12× (H8, room air 25 °C). H3–H5 made the
model faster, because the real cell's belts and handovers are quicker than the
drawing assumed. *(Until H8 this paragraph said the cycle "runs on 5.67 s"
past S37. That was right through H6 (74.93 − 69.26). H7 made it 5.81 s,
and the paragraph was not updated.)* `LOG.cycle_time_rec` and `LOG.machine_time_rec` carry
these two figures (plan H1, 2026-09-12).

### The sequence

```
Station 1                Station 2              Station 3
camera detect            S2A1 pushes to         S3A1 pushes to belt 3
A1 pushes to belt 1      engraving base         belt 3 transports
belt 1 transports        base raises            PX4 confirms
A6 pushes to belt 2      operator engraves      S3A2 ejects to bin
belt 2 transports        base lowers
```

Implicit retract states (`8i`, `16i`, `24i`, `30i`, `35i`, `42i`) are
engineering additions: `Sequence.xlsx` never commands a retract, but a rod left
extended physically blocks the next transport. They are flagged as additions
everywhere they appear.

---

## 2. Requirements

| Item | Required | Notes |
|---|---|---|
| MATLAB | R2018b or newer | Floor set by `yline` and `sgtitle`. (`Simulink.BlockDiagram.arrangeSystem` was the third reason until 2026-09-14, when `build_factory_model` stopped using it) |
| Simulink | Only for the Simulink path | `run_factory_simulation` needs base MATLAB alone |
| Stateflow | Optional, **installed** | `build_factory_model('PLC','stateflow')` builds and runs, and is **verified NOT equivalent** to `factory_plc` — a lead of exactly **26 scans** (63.160 s against 62.900 s). Measured four times now: 38, 49, 50, then 26 — it is *plant-dependent*, it went **down** on a change that made the cycle 28% longer, and it stays exactly whole-numbered, which is the finding. See `StateflowSequenceTest` |
| Simscape | **Installed**, not used | The pneumatics are hand-written ODEs. Simscape Fluids is the native alternative and a deliberate non-goal for now — see `Project_Notes/HANDOFF.md` §9 |
| Simulink Test / Coverage | **Installed and in use** | `tests/factory_cycle.feature` runs and passes via `model_test` |
| OPC / Industrial Communication | **Installed**, not yet connected | The PLC is not reachable from this workstation. This is what would make it a live twin |
| Python 3.8+ | Optional | Reference ports and the equivalence test |

Verified on MATLAB R2024b and R2026a.

Check your environment before anything else:

```matlab
check_environment
```

It reports MATLAB version, the 14 core files, whether parameters initialise,
whether the physics evaluates, and whether the folder is writable. Add
`check_environment('Simulink', true)` to include the Simulink path.

**Run the toolbox audit once:**

```matlab
check_environment('Toolboxes', true)
```

On 2026-08-24 it found **nine toolboxes licensed but not installed**, including
Stateflow, Simscape, Simulink Test and OPC. A licensed-but-absent toolbox is an
Add-On Manager download, not a purchase — and several of this project's recorded
limitations existed only because they were missing. **All nine were installed
the same day**, which is what made the first Simulink Test possible.

---

## 3. Quick start

**Every command in this README is typed at the MATLAB prompt**, unless the block
is explicitly marked as a terminal command. `cd` into the `Factory_Simulation`
folder in MATLAB first, then:

```matlab
LOG = run_factory_simulation; plot_factory_results(LOG)
```

That runs the whole cycle in base MATLAB in roughly 20–40 s and prints a
summary. No toolboxes, no model build, no setup.

For the full list of commands without leaving MATLAB:

```matlab
factory_help
```

> **`matlab -batch "..."` is a *terminal* command, not a MATLAB one.** Typing it
> at the MATLAB prompt gives `Execution of script matlab as a function is not
> supported`, because MATLAB resolves `matlab` to
> `toolbox/matlab/general/matlab.m`. If you are already in MATLAB, type only the
> inner command.

---

## 4. Repository structure

**`Factory_Simulation/` is self-contained.** Nothing inside it needs a file
outside it, and that is checked rather than assumed: the folder was copied to an
empty directory on its own and both suites were run there.

```
Digital Twin/Factory_Simulation/          the git repository
│
├── Factory_Simulation/   ==  THE SIMULATION.  Share this folder.
│   │
│   ├── README.md                    this file
│   ├── INPUTS_REQUIRED.md           complete intake checklist, every parameter
│   ├── Factory_Physics_Model.slx    the Simulink model
│   │
│   ├── The real machine  (OBSERVED FACTS, not assumptions)
│   │   ├── PlcTagList.m             all 121 PLC tags, mechanically transcribed
│   │   ├── factory_io_map.m         PLC tag -> model signal, with what is unknown
│   │   └── plc/                     the supplied artefacts: tag list, live snapshot
│   │
│   ├── Parameters and data
│   │   ├── JanaticsData.m           manufacturer register (single source of truth)
│   │   ├── FactoryParams.m          all engineering parameters
│   │   ├── initialize_factory.m     derived quantities, layout, state indices
│   │   ├── factory_params_cached.m  cached parameter build
│   │   ├── factory_operator_draw.m  draw one operator dwell from the 7 observed
│   │   ├── factory_operator_console.m  you as the operator: engrave? then ENG DONE
│   │   └── Janatics_Component_Register.csv
│   │
│   ├── Physics and control
│   │   ├── factory_derivatives.m    continuous-time equations of motion
│   │   ├── factory_sensors.m        sensor models
│   │   ├── factory_plc.m            44-state sequencer, two routes
│   │   ├── factory_plc_init.m       controller state
│   │   ├── factory_states.m         state table (name, Excel row, guard)
│   │   ├── factory_actuators.m      the 11 pneumatic actuators, 13 coils
│   │   ├── factory_cmd_bus.m        PLC -> plant command vector layout
│   │   └── support_region.m         which surface carries the workpiece
│   │
│   ├── Execution
│   │   ├── run_factory_simulation.m MATLAB-only path (RK4)
│   │   ├── run_simulink_model.m     Simulink path
│   │   ├── build_factory_model.m    constructs the .slx programmatically
│   │   ├── factory_plant_sfun.m     plant as a Level-2 S-function
│   │   ├── factory_plc_sfun.m       PLC as a Level-2 S-function
│   │   └── reset_factory.m          return to a clean state
│   │
│   ├── Verification
│   │   ├── verify_model.m           acceptance checks against reference values
│   │   ├── run_all_tests.m          MATLAB test suite runner
│   │   ├── compare_execution_paths.m  MATLAB vs Simulink, per state transition
│   │   ├── audit_provenance.m       counts/lists every tagged parameter
│   │   ├── operator_distribution.m  Monte Carlo cycle time from the real dwells
│   │   ├── sensitivity_sweep.m     which unmeasured parameters actually matter
│   │   ├── compare_to_recording.m  model interval vs measured, state by state
│   │   ├── parse_options.m          Name/Value parsing with real errors
│   │   ├── tests/                   matlab.unittest classes
│   │   └── export_equivalence_data.m  dumps MATLAB behaviour for cross-checking
│   │
│   ├── Help
│   │   ├── factory_help.m           every command, pasteable at the prompt
│   │   ├── factory_log.m            the current LOG, computed once and cached
│   │   └── check_environment.m      verify MATLAB/Simulink/paths
│   │
│   ├── Reference ports (Python)
│   │   ├── validate_physics.py      Iteration-01 reference
│   │   ├── janatics_physics.py      Iteration-02, Janatics-integrated
│   │   ├── validate_report.py       9-test acceptance suite
│   │   ├── compare_janatics.py      Iteration 01 vs 02 harness
│   │   ├── tools_static_check.py    static audit of the .m sources
│   │   └── test_*.py                Python test suites
│   │
│   └── Display
│       ├── plot_factory_results.m   static result plots
│       ├── visualize_factory.m      animated replay on the cell layout
│       ├── factory_view.m           the cell view, shared by replay and live
│       ├── visualize_processes.m    2-D physics of each process, end to end
│       └── draw_cell_layout.m       the static cell, shared by both
│
└── Project_Notes/     ==  THE MAINTAINER'S WORKING RECORD.
                          NOT DISTRIBUTED - see the note below.
```

**`Project_Notes/` is not in the repository.** It holds the working record —
the dated iteration log, the session handoff, the ranked list of what to measure
next, the printable intake sheet, and the scripts that read the vendor CAD. It
is where the work is recorded and it stays on the maintainer's disk; what is
published is the model. Documents below that cite `Project_Notes/…` are citing
that record, and you are not missing a file.

Two things deliberately did **not** stay there:

- **`Physics_Framework.xlsx`** moved into this folder. It holds hand-entered
  measurements that cannot be regenerated, and version control is its only
  backup.
- **`BITS_MCD_project/`** keeps its **STEP files** and nothing else. STEP is
  text, so it diffs and reads without SOLIDWORKS, which is what makes it usable
  evidence for the 27 `[CAD]` parameters. The Siemens NX and Parasolid
  originals are binary and are not published.


`INPUTS_REQUIRED.md` stays on the simulation side deliberately. It is not a
working note: `audit_provenance`, `factory_help` and `factory_io_map` all print
its name at the prompt, and it is what tells a reader which numbers are real
measurements and which are still assumptions. Shipping the model without it
would invite somebody to trust a placeholder.

`resources/` holds MATLAB project metadata and is not edited by hand.

---

## 5. How to run

### MATLAB-only path (recommended)

```matlab
LOG = run_factory_simulation
```

**Inputs:** none. Parameters come from `FactoryParams()`, the initial state
from `initialize_factory()`. Options: `'dt'`, `'t_max'`, `'Verbose'`.

**What happens:** parameters build → state initialises → loop at `dt = 0.5 ms`,
with the PLC scanned every 20th step (`t_scan = 10 ms`), the plant integrated by
explicit RK4 → stops at `S39_CYCLE_COMPLETE` or `t_max`.

### Simulink path

```matlab
out = run_simulink_model
```

Builds the model if absent, configures the solver, runs, and converts the
result into the same `LOG` format. Note it returns `out`, with the log at
`out.LOG`.

**Expect several minutes** — an interpreted S-function at a 0.5 ms fixed step.

To build without running:

```matlab
build_factory_model
```

The `.slx` is generated rather than stored, so the model is reproducible and
reviewable in version control.

### Replay the cycle visually

```matlab
LOG = run_factory_simulation; visualize_factory(LOG, 4)
```

Draws the cell layout — three conveyors, five actuators, the engraver, the three
station boundaries — and replays the workpiece at 4× speed. Display only: every
coordinate is read from `LOG`.

### The 2-D physics of each process, end to end

```matlab
LOG = run_factory_simulation('Plot', false); T = visualize_processes(LOG)
```

One panel per process — 11 of them, plus an end-to-end overview — showing the
path the workpiece actually took, the rods at the instant of peak load, and the
**force vectors acting on the part**:

| Arrow | Force |
|---|---|
| cyan | rod-tip contact, `F_rod` |
| orange | belt or plate friction, `F_fric` |
| red | locating-stop reaction, `F_stop` |
| green dashed | workpiece velocity |

It also returns a table of per-process duration, distance, peak speed, peak
force and driving mechanism.

**The forces are not recomputed for the picture.** `factory_derivatives` returns
the breakdown as an optional second output, `run_factory_simulation` logs it
from the *same* call that produces the logged acceleration, and the visualiser
only draws what is in `LOG`. So `F_rod + F_stop + F_fric = F_net` exactly and
`F_net = blk_m * blk_a`; `PhysicsTest` asserts both. The arrows cannot disagree
with the motion, and deleting this file changes no simulation result.

Arrow lengths are scaled **per panel**: a 0.23 N belt friction and a 30 N
contact force cannot share one scale. Every magnitude is printed.

**Works on either execution path.** `run_factory_simulation` logs the breakdown
directly; `run_simulink_model` reconstructs it by re-evaluating
`factory_derivatives` at each logged sample — exact, because the `.slx` logs
both the full plant state and the command vector. Until 2026-08-24 a Simulink
`LOG` was rejected outright and its `blk_a` was a column of zeros.

---

## 6. Outputs

`run_factory_simulation` returns a `LOG` struct:

| Field | Meaning |
|---|---|
| `t` | time vector, logged at 200 Hz |
| `blk`, `blk_v`, `blk_a` | workpiece position, velocity, acceleration |
| `rod`, `rod_v`, `rod_F` | per-cylinder rod position, velocity, force |
| `PA`, `PB`, `P_res`, `P_br` | chamber, receiver and branch pressures |
| `spool` | valve spool positions |
| `v_blt`, `T_mot` | belt speeds and motor torques |
| `base_z` | engraving base height |
| `m_air` | cumulative air mass consumed |
| `state`, `sens` | PLC state index and sensor history |
| `cycle_time`, `complete` | end-of-cycle summary |
| `blk_final`, `blk_target`, `pos_error` | placement accuracy |
| `air_kg`, `air_NL` | air per cycle |
| `P`, `plc` | parameter set and controller state |

Nominal reference values (faults inactive):

```
cycle time      75.65 s        final position   (1.28993, 0.23650) m
position error  0.07 mm        peak chamber A   5.32 bar
transitions     39             peak chamber B   5.52 bar
watchdog        none           air per cycle    9.43 NL
```

---

## 7. What each file does

### Parameters

- **`JanaticsData.m`** — the only file holding manufacturer figures. Every
  component records `.status` and `.src`. All are currently `PROVISIONAL`.
- **`FactoryParams.m`** — all engineering parameters, each carrying a
  provenance tag. Nothing physical may be hard-coded elsewhere.
- **`initialize_factory.m`** — converts the drawing layout to metres, sizes
  strokes, builds the state-index map `P.IX`, returns the initial state.
- **`factory_operator_draw.m`** — returns `P` with one operator dwell drawn at
  random from `P.OP.samples`, the seven real dwells recorded on the machine.
  It exists as a **separate function on purpose**: `FactoryParams` takes no
  arguments and must return the same struct every time it is called, because
  every pinned reference value in the project was measured on that struct and a
  parameter file that answered differently per call would be untraceable. The
  randomness has to be asked for. `OperatorDistributionTest` enforces this.
- **`factory_operator_console.m`** — the operator's side of a manual-input
  cycle, `run_factory_simulation('Operator','console')`: asks engrave or
  skip, waits the laser time in real time, then times your ENG DONE. See
  *You as the operator* below. `ManualInputTest` scripts its answers.

### Physics

- **`factory_derivatives.m`** — the right-hand side: receiver, branches,
  chambers, pistons, conveyor drivetrains, engraving axis, workpiece.
  Deterministic and free of side effects; RK4 calls it four times per step.
  `[ds, dbg] = factory_derivatives(...)` also returns the 2-D force breakdown on
  the workpiece for `visualize_processes`. It is assembled only when a second
  output is requested, and its accumulators run *parallel* to the force sum
  rather than replacing it, so `ds` is bit-identical either way — asserted by
  `PhysicsTest/diagnosticsDoNotChangeTheDerivative`.
- **`factory_sensors.m`** — camera, **all ten** proximity sensors in the
  machine's own numbering, per-cylinder reed switches, height comparators,
  pressure readings. A pure function of state.
- **`factory_sensor_bus.m`** — the one definition of the plant-to-PLC sensor
  vector. Its layout used to be written out by hand in three files that had to
  agree — the packing, the unpacking, and 27 literal indices inside generated
  Stateflow guard strings — with nothing checking that they did. Widening the
  proximity sensors from 4 to 10 shifted every channel after them by six, which
  is exactly the edit that gets one branch wrong and still compiles.
- **`factory_actuators.m`** — the one definition of the plant: **all eleven**
  pneumatic actuators in the machine's own numbering, on **thirteen** solenoid
  coils. Five magazine pushers, two conveyor transfers, cylinders A and B, and
  two outfeed stations. A and B are **double-solenoid**: two coils each, and
  the spool *holds* with both off, which is why the machine pulses them and why
  a spring-return valve could not express them. Carries each actuator's coils,
  valve type, supply branch, stroke geometry and diagram label.
- **`factory_cmd_bus.m`** — the one definition of the PLC-to-plant command
  vector, `[pump; dv(1:4); sol(1:13); conv(1:3); base]`. Same argument as the
  sensor bus, one bus later: the layout was written out by hand in four files,
  one of which encodes the indices inside *generated* Stateflow action strings.
- **`support_region.m`** — which surface carries the workpiece and how fast
  that surface is moving.

### Control

- **`factory_states.m`** — the 40-row state table: name, Excel row, guard.
- **`factory_plc.m`** — one scan: pressure switch, then the sequencer. Maps
  one-to-one onto Stateflow.

### Execution and verification

- **`run_factory_simulation.m`** — the reference execution path.
- **`build_factory_model.m`** — constructs the Simulink model: PLC, Plant, stop
  logic, bus tags, viewer scopes, `To Workspace` sinks. *Since 2026-09-14 the
  top level is drawn as the cell seen from above*, with the same geometry as
  `visualize_factory`: belts 1-3 in blue, the orange engraver, the grey bin,
  the camera and every placed actuator at its own position, inside the three
  station areas. Those blocks are display only; each taps a signal into a
  Terminator. Beside the cell, an engine panel holds what computes it all: the
  PLC and the Plant (one block, so Simulink and MATLAB still agree exactly),
  the command switch, the tags, the harness Outports, and the `Logging` and
  `Views` subsystems. Until then `arrangeSystem` stacked about 40 blocks into
  one column. `run_simulink_model('Animate', true)` replays a finished
  Simulink run on the cell picture. It is a replay, not a live view: the
  Simulink path runs about 6x slower than real time.
- **`verify_model.m`** — checks derived quantities and cycle results against
  reference values, plus a one-sided pressure-rating bound.
- **`run_all_tests.m`** — runs the `matlab.unittest` suite.
- **`operator_distribution.m`** — the predicted cycle-time **distribution**
  rather than a single number. It bootstraps the seven observed operator dwells
  (n = 7 is too few to fit a shape honestly) and adds each to the machine time.
  That addition is legitimate because machine time was measured to be
  independent of the dwell — 57.860 / 57.861 / 57.861 s across dwells of 5.95,
  13.98 and 28.65 s. That was to S39; to S37, the recorder's end point, which it
  has used since 2026-09-12, it is 52.190 / 52.191 s at the extremes. So
  10,000 samples are arithmetic instead of 10,000
  simulations. Pass `'Validate', true` to re-run the real simulations and
  confirm that shortcut still holds.
- **`compare_to_recording.m`** — completion criterion **C3**: compares each
  interval the recorder measures against the same interval in the model. The
  whole-cycle number hides everything, and this is not hypothetical — run
  2026-09-10 it found belt 2 running **1.8 s too fast** and belt 3 **2.1 s too
  slow**, errors that nearly cancel in the cycle total and had therefore been
  invisible. The interval-to-state mapping is not guessed: each entry was
  confirmed against the dwell wiring in `factory_plc` *and* the printed state
  trace, and every interval that could not be confirmed is listed as
  `UNMAPPED` rather than assumed. *Since 2026-09-15 it compares by route.*
  - `'Route', 'bypass'` runs the bypass and compares the SV11 route's
    intervals: belt 2 to prox 8, prox 8 to SV11, the SV11 pulse and belt 3.
  - A schema-3 extraction labels each cycle engraved, bypass or neither.
    Intervals before the split use every cycle; the rest use only the cycles
    that took the route being compared.
  - An older file without routes gives the same comparison as before, and
    says so.
- **`sensitivity_sweep.m`** — answers "which of the 78 unmeasured parameters
  actually change the answer?". It perturbs each `[PLH]`/`[ASM]`/`[EST]`
  parameter by 10%, re-runs the full cycle, and ranks them by the resulting
  change in machine time. Since 2026-09-12 that is taken to S37, the
  recorder's end point; the run quoted here was to S39, and it was repeated
  to S37 on 2026-09-13 (below). Corrected run, 2026-09-10: **four parameters move
  machine time by more than 1% — three independent levers, since `T_air` and
  `R_air` enter only as their product — sixteen move it by less, and forty-five
  not at all** (`T_air` has since been measured, 25 °C, and was applied on
  2026-09-13 as plan H8). A first run the same day reported five, with `P.z_top` the
  largest at +2.75%. That was an artefact: the sweep perturbed a parameter
  without recomputing the `[CAL]` values derived from it (here the platform jog
  speed). It now re-evaluates every `[CAL]` line after each perturbation, and
  corrected, `z_top` scores +0.05%.
  That is what criterion C5 asks for — not "measure all 78", but "no parameter
  that moves the answer by more than 1% is still a guess". The header documents
  four limits the ranking cannot see: it is one-at-a-time, local to a 10% step,
  scores machine time only, and reports derived parameters as `overwritten`
  rather than as insensitive.
  **Re-run 2026-09-13, to S37, after H1–H8** (baseline machine time 57.350 s):
  **no parameter moves machine time by more than 1%.** The largest are `R_air`
  and `rho0`, at −0.75% each. Both are standards (the gas constant and the ISO
  6358 reference density), not guesses. `P_ready` went from +2.21% to 0,
  because H2 replaced the ready-pressure charge with the start delay, and
  `T_air` is now measured. `P.SCALE` still breaks the cycle at +10%, so it
  cannot be scored. Seventeen move machine time by less than 1%, forty-six not
  at all, and thirteen could not be swept. One of those, `P.v_belt`, has been
  a vector per belt since H4, so it was swept by hand: belt 1 −0.42%, belt 2
  0.00%, belt 3 −0.07%.
- **`compare_execution_paths.m`** — runs both paths and reports their
  disagreement per PLC state transition, plus cycle time, final position and air
  consumption. This is the instrument that localised the historical Simulink
  divergence to a one-scan command latency, and it is the regression guard that
  keeps it closed. Run it after any change to the scheduling of either path.


### Display

- **`plot_factory_results.m`** — the static results dashboard.
- **`visualize_factory.m`** — animated replay of the cycle on the cell layout.
  A manual-input run replays with its operator line: the laser, the wait for
  ENG DONE, and when it was pressed.
- **`factory_view.m`** — the animated cell view itself, shared by
  `visualize_factory` (a replay of a finished `LOG`) and
  `run_factory_simulation('Live', true)` (drawn while the cycle runs), so the
  two cannot drift apart. Display only: a live run computes the same `LOG`,
  and `LiveViewTest` checks it.
- **`visualize_processes.m`** — the 2-D physics of each process, end to end: one
  panel per process showing the path taken, the rods at peak load, and the force
  vectors acting on the workpiece. The forces are read from `LOG`, not
  recomputed, so they cannot disagree with the motion.
- **`draw_cell_layout.m`** — the static cell geometry, shared by both
  visualisers so they cannot drift apart.

### The real machine

- **`PlcTagList.m`** — every tag the installed cell's Siemens S7 publishes, all
  121 of them, transcribed **mechanically** from `plc/PLC_Tag_List.xlsx`. The
  only file here holding observed facts rather than assumptions. If the model
  disagrees with it, the model is what is wrong.
- **`factory_io_map.m`** — relates each PLC tag to a model signal, and marks
  each row `CONFIRMED`, `PROVISIONAL` or `UNMAPPED`. 23 rows were `UNMAPPED`
  until 2026-08-30, when the machine's own PLC program was decoded and named
  every coil, every input address and the network that drives each. **No row
  is `UNMAPPED` now.** Eight are `PROVISIONAL`, and those are placement
  questions — where a sensor is bolted, which barrel is cylinder A — that a
  ladder diagram cannot answer. Run `factory_io_map('report')` to see them.

### Help and plumbing

- **`factory_help.m`** — every command in the project, ready to paste at the
  MATLAB prompt. Descriptions are commented out so a whole line is safe to copy.
- **`check_environment.m`** — verifies MATLAB, Simulink, the paths and that the
  physics evaluates, before anything else is attempted.
  `check_environment('Toolboxes', true)` additionally audits which toolboxes
  are **licensed but not installed**. Worth running once: on 2026-08-24 it
  found nine, including OPC — the one that would turn this from an offline
  simulation into a twin connected to the real machine.
- **`audit_provenance.m`** — counts and lists every provenance-tagged parameter.
  Assignment lines only; see `INPUTS_REQUIRED.md`.
- **`parse_options.m`** — Name/Value parsing for every entry point. Rejects an
  odd argument count and an unknown option name, instead of the old loop that
  indexed past the end on the first and silently accepted the second.
- **`factory_log.m`** — the current simulation result, computed once and
  cached, so the viewers take no argument: `visualize_processes`,
  `visualize_factory` and `plot_factory_results` all fetch or produce a `LOG`
  themselves. It caches a *result*, not parameters, so a parameter edit does
  not invalidate it — which is why `reset_factory` clears it and why running
  `reset_factory` after a parameter edit is mandatory.
- **`reset_factory.m`** — clears the parameter cache, the persistent PLC state
  and the cached `LOG`. Mandatory after editing `FactoryParams.m` or
  `JanaticsData.m`.

---

## 8. Architecture and data flow

```
JanaticsData ──► FactoryParams ──► initialize_factory ──► P, s0
                                          │
                                          ▼
    ┌──────────────────── simulation loop ────────────────────┐
    │                                                          │
    │   s ──► factory_sensors ──► y ──► factory_plc ──► u      │
    │   ▲                                              │       │
    │   │                                              ▼       │
    │   └────── RK4 integrate ◄── factory_derivatives(s,u,P)   │
    │                                                          │
    └──────────────────────────────────────────────────────────┘
                              │
                              ▼
                       LOG ──► plot_factory_results
                           └─► visualize_factory
```

The loop is closed through *physics*: commands change pressures, pressures move
rods, rods move the workpiece, the workpiece trips sensors, sensors advance the
PLC. There is no path from the sequencer back to position except through the
equations of motion.

---

## 9. Testing

### MATLAB suite

```matlab
run_all_tests
```

201 tests, about 10 minutes. The figures the tests draw stay hidden while it
runs: `DefaultFigureVisible` is `'off'` until the run ends, then put back.

If you are running a copy of this folder on its own, expect **200 / 201 passed
with one SKIPPED**, not a failure. `DocumentationTest` has one check that reads
`Project_Notes/HANDOFF.md`, a working-record file that lives outside this
folder and is deliberately not shipped with it. With nothing to read, that one
check declines to run rather than failing. Everything else is self-contained.

| Class | Covers |
|---|---|
| `ParametersTest` | parameter set, provenance chain, derived quantities, state layout, fault defaults |
| `PhysicsTest` | `factory_derivatives`, `factory_sensors`, `support_region` |
| `SequencerTest` | `factory_plc`, `factory_states`, pressure-switch hysteresis |
| `CycleRegressionTest` | full cycle, physical invariants, pinned reference values |
| `BypassRouteTest` | the SV11 bypass, `P.engrave_selected = false`: the states it walks, that SV11 fires while cylinders A and B and the platform never move, that the block still reaches the bin, and the sensor and stop placement that make it a route. Behaviour only — no bypass cycle has been recorded to pin against |
| `PlcIoTest` | the real PLC tag register, the model's mapping to it, and that `P.REAL` cannot drift from the register |
| `DocumentationTest` | that this README and the `run_all_tests` header still describe the suite and the files that actually exist — the count below is asserted, not maintained by hand |
| `DocumentationFactsTest` | that numbers written in **prose** match the model — the provenance table against a live `audit_provenance`, quoted parameter values against `FactoryParams`, and a blocklist of claims the project has since overturned. `DocumentationTest` checks the docs are *consistent*; this checks they are *true* |
| `ProcessViewTest` | `visualize_processes`: that the process table partitions every engraved-route state with no gap or overlap (the bypass has its own table), and that logged forces sum to `m*a` |
| `CompareToRecordingTest` | `compare_to_recording`: every mapped state pair is re-timed from the LOG's own conveyor and sensor edges, on the engraved and the bypass route; a route-labelled (schema 3) extraction feeds each route's intervals only from cycles that took it, and the shared ones from every cycle; a file without routes behaves as before |
| `OptionParsingTest` | Name/Value option handling on every entry point; that `factory_help` output is safe to paste whole |
| `ManualInputTest` | `run_factory_simulation('Operator','console')`: the engrave/skip question, the laser wait then ENG DONE in that order, that the dwell is laser + reaction + confirm, and that machine time does not move. Answers are scripted, so nothing waits on a keyboard |
| `LiveViewTest` | `run_factory_simulation('Live', true)` and `factory_view`: a live run computes the **same `LOG`** as a normal one, closing the figure does not stop the run, ENG DONE by a key on the figure (a modifier alone does not count) with the Command Window fallback, the engraved-colour rule (a bypassed part is never drawn green), and the operator line a replay shows |
| `PlcIoLatencyTest` | `P.plc_io_delay`: that delay 1 reproduces the historical Simulink numbers, that the shift is a whole number of scans, and that it accumulates |
| `SimulinkModelTest` | model build, run, sample times, and exact MATLAB agreement — tagged `Slow`, excluded by default |
| `StateflowSequenceTest` | the Stateflow chart against `factory_plc`. It is **not** equivalent; this pins the measured 38-scan divergence so it cannot drift — tagged `Slow` |

Include the Simulink tests (several minutes):

```matlab
run_all_tests('IncludeSlow', true)
```

### Python suite

```bash
python -m unittest discover -p "test_*.py"
```

**83 Python tests**, about 580 s, most of it the MATLAB export the equivalence test launches. Worded so it cannot be confused with the MATLAB count above — `DocumentationTest` pins that one against the live suite and requires it to appear exactly once.

| File | Covers |
|---|---|
| `test_janatics_physics.py` | the four closed-form primitives — `mdot_orifice`, `contact_hc`, `friction_2d`, `support_of` — asserted as **physical invariants rather than recorded outputs**, so they survive a re-baseline: ISO 6358 choking below `b_crit`, Hunt-Crossley force vanishing *continuously* at separation, friction saturating at `μ_k·N` |
| `test_janatics_dynamics.py` | integrated behaviour of the reference port |
| `test_bypass_route.py` | the SV11 bypass in the reference port: the route it walks and that the block reaches the bin; restores the engraved route afterwards, which `test_model_equivalence.py` needs |
| `test_model_equivalence.py` | that MATLAB and Python produce identical state-transition sequences. Skips cleanly when MATLAB is absent |

The invariant tests matter for the same reason `DocumentationFactsTest` does:
those four primitives were previously exercised only *indirectly*, through
full-cycle behaviour, which can stay green while a primitive is subtly wrong.

**Run both before considering any change done, and record the result in
`Project_Notes/ITERATION_LOG.md`.**

---

## 10. Parameters and provenance

Every parameter carries a tag:

| Tag | Meaning | Count |
|---|---|---|
| `[PLH]` | placeholder, must be replaced | 5 |
| `[ASM]` | engineering assumption — in no source | 38 |
| `[EST]` | engineering estimate | 35 |
| `[JAN]` | Janatics catalogue figure — provisional until confirmed | 7 |
| `[COMM]` | commissioning setting — read it off the machine | 5 |
| `[CAL]` | calculated from the above — recomputes itself | 16 |
| `[PLC]` | **observed** on the real machine’s PLC | 61 |
| `[MEAS]` | **measured** by hand, or read off a nameplate | 38 |
| `[CAD]` | **read from the vendor solid model** | 28 |
| | **total** | **233** |

**127 parameters are now facts about the real machine** — 61 read off the PLC,
38 measured by hand or read off a photograph or nameplate, and 28 read out of
the vendor CAD. Against that, **78 are still unmeasured**
(`PLH` + `ASM` + `EST`) and 7 Janatics figures are provisional.
*Corrected 2026-09-13 (plan H8). This sentence said 118 facts (58 / 32 / 28)
and 78 unmeasured after the table above had moved on. `DocumentationFactsTest`
checks the table, not this sentence, so the drift went unnoticed. Later the
same day the manual-input mode's laser placeholder, `P.OP.t_laser_50`
`[PLH]`, took the unmeasured count from 77 back to 78.*

`[MEAS]` more than doubled on 2026-09-07, 14 → 32, when three nameplates and a
filled intake sheet arrived: two Janatics barrel labels, a stepper motor label,
ten sensor positions, three cylinder strokes and the engraving axis's travel
time. **Only one of those 18 is applied** — `CYL_A`'s bore. The rest sit beside
the model on the same terms as §13B and §13C, and the unmeasured count went
*up* by one, because the A51's rod diameter is now an `[EST]` where before there
was no A51 in the register at all. A count of facts is not a count of applied
facts, and this table has never claimed to be.

These counts went 37/38 and back again over 2026-09-06–07. `P.v_belt` was
promoted to `[PLC]` on the strength of a recording that showed all three axes
at 0.150 m/s, and demoted to `[ASM]` again when that recording turned out to be
the SCADA application's **simulator**, seeded with this model's own 0.15. The
round trip is left visible on purpose — see `FactoryParams.m` §13I. On
2026-09-12 (plan H4) belts 1 and 2 were finally timed over measured
distances, belt 1 at 0.210 m/s `[PLC]` and belt 2 at 0.310 m/s `[MEAS]`, each
on a line of its own. Belt 3 is still the `[ASM]` 0.150.

The `[PLC]` count jumped from 12 to 37 on 2026-08-30 when the machine's TIA
Portal program listing was decoded and §13C was written. §13D followed on
2026-09-02 from photographs of the running cell and the Component Data drop.
Note what did *not* fall: the unmeasured count went **up**, 68 to 75, because
§13D also recorded seven candidate components that are named in a document
about a *different* machine in the same lab and are not confirmed to be
installed here. Nothing in §13C or §13D is applied — both are recorded beside
the model so the assumptions they contradict stay visible, on the same terms
as the CAD findings in §13B. Regenerate this table any time with `audit_provenance`;
`DocumentationFactsTest` fails if it drifts.

See `Project_Notes/NEXT_STEPS.md` for what to measure, ranked by measured
sensitivity.

---

## 11. Known limitations and assumptions

### Fully physical
Pneumatic charging and exhaust, piston dynamics, contact and friction,
conveyor drivetrain response, sensor triggering, sequence timing.

### The scale assumption — **resolved 2026-08-25**
The reference drawing labels its axes in metres and shows a 17 × 13 cell
holding a 0.6 "m" cube. Taken literally that is a 583 kg workpiece pushed by
20 mm pneumatic cylinders, which is not credible, so the drawing was treated as
a **schematic** with `SCALE = 0.10`, giving a 1.7 × 1.3 m cell.

That reading is now confirmed four ways, independently:

| Source | Measurement | Implied `SCALE` |
|---|---|---|
| Tape measure on conveyor 1 `[MEAS]` | 760 mm over 7.6 drawing units | **0.1000** |
| `conveyor.stp`, vendor CAD `[CAD]` | 775 mm overall | 0.1020 |
| `Conveyor1.STEP`, vendor CAD `[CAD]` | 780 mm overall | 0.1026 |
| `Conveyor2.STEP`, vendor CAD `[CAD]` | 750 mm overall | 0.0987 |

The two figures differ by about what you would expect from what each one spans:
a tape laid along the belt, against an overall extent that includes the end
frames. Every geometric quantity — strokes, conveyor lengths, cycle time,
actuator duty — inherits from `SCALE`, which is why this was the highest
priority open question for most of the project. It is closed.

### The workpiece — **100 × 100 × 40 mm, 0.300 kg**
Modelled for most of this project as a 60 mm aluminium cube at 2700 kg/m³:
0.583 kg, taken from the reference drawing. The real part is a **100 × 100 ×
40 mm wooden block — 0.300 kg**, and a cuboid rather than a cube.

- **100 × 100 mm** is read from the CAD. `Box_50MM.STEP` measures 100.00 ×
  100.00 mm in plan, and the magazine's five slots at 105–110 mm agree.
- **40 mm** is measured in the lab and takes precedence over the CAD's 50 mm
  block. The cell runs several thicknesses; 40 is the one on the machine.
- **750 kg/m³ confirmed by weighing** on 2026-08-26. A block came in at
  **0.300 kg**, and 0.300 ÷ (0.100 × 0.100 × 0.040) is 750 exactly. Density was
  the last unconfirmed part of the workpiece; one reading closed it.

`P.blk_a` became `blk_L` / `blk_W` / `blk_H`, because a single edge length
cannot describe a cuboid. The contact code picks the extent *along* the rod axis
for the face offset and the one *across* it for the alignment gate. The Python
reference port needed the same change — it had `0.3 * S` hard-coded as half a
cube edge.

**A 1.94× mass change moved cycle time by 0.13%** — 31.070 s to 31.030 s. The
pneumatics barely register it, because they are dominated by the cylinder rather
than by what it pushes. Solver step and contact stiffnesses are unchanged.

#### The plant re-model, 2026-09-02: 5 cylinders to 11 actuators

The model carried five spring-return cylinders. The machine has **eleven
pneumatic actuators on thirteen coils**, two of them double-solenoid. The plant
now carries all eleven, and `P.NS` went from 51 states to **81**.

Cycle time moved **31.030 s to 31.080 s** and air per cycle **4.94 to 6.09
normal litres**. The air is the change; everything else follows from it. Six
more rod-side chambers hang off the manifold and every one of them charges, so
branch 1 — which fed two chambers and now feeds six — takes longer to reach
`P_br_rdy`, and the `CHG` / `BR_RDY` waits in S05 and S12 gate later.

Most of that landed in one step (5.90 NL). The remaining 0.19 NL came later the
same day, when the machine's owner said what **cylinder B** is for — twice, and
the second time changed the answer.

**The double-solenoid valve model contributed none of that.** A latching valve
driven by *maintained* coils produces the same spool trajectory as a spring-
return one, which is precisely why the valve rewrite could be made without
disturbing the baseline and the air accounting could not. There is no way to put
six more real actuators on a shared manifold and keep the air dynamics
identical; a re-model that left them unchanged would be the fiction.

#### Cylinder B is a bypass, not a transfer — corrected by the owner

The model first assigned **CYL_B** (coils 9/10) the engraver→belt-3 transfer,
because the sequence needs that motion and the two double-solenoid cylinders
were the plausible pair. That was an assumption and it was **wrong**. The
machine's owner:

> cylinder B is energised when engraving is **not** to be done (50 mm is
> selected on the interface)

and then:

> solenoid 9 is for extending the cylinder and solenoid 10 is for retracting it
> **for engraving machine**

Read alone, the first statement suggested a diverter carrying the part past the
engraver, and the model was briefly built that way. The second places cylinder
B **at the engraving machine**: it actuates the *machine*, not the workpiece,
with coil 9 out and coil 10 back. Either way **solenoid 11** makes the
engraver→belt-3 move — the owner confirmed cylinders A and B both do not. Which is what its own PLC name said all along: `FC6 N15`
fires it on `Wp_move_cv3`. It is renamed `MOVE_TO_CV3`; `XFER_CV2_CV3` was this
model's guess at what it did, and the guess was the thing that was wrong.

This also gives the two products a consequence. §13C already recorded
`PRODUCT_HEIGHT` 50 and 25 with separate counters and noted the model has one
product against the machine's two — a 50 mm part that is *not* engraved is what
those counters are counting.

**What the cell actually does**, once cylinder B is placed:

| product | route |
|---|---|
| engraved | block stops at `c2_end`; **cylinder A** pushes it **+x** into the engraver; **solenoid 11** moves it down onto belt 3 |
| 50 mm, not engraved | block runs **further down conveyor 2** to belt-3 height; **cylinder B** pushes it **+x** straight onto belt 3, past the engraver |

A and B are a matched pair — same axis, same station, same push direction, one
above the other — and the geometry corroborates it: both travel 252.5 mm and
both round to the same 300 mm standard cylinder. Neither of the two earlier
readings produced that symmetry, which is a large part of why this one is
believed.

**Not yet modelled:** there is no product selection and no no-engrave branch,
so nothing ever commands CYL_B. It is fully placed and would push the workpiece
if it were fired. Question 3c asks what fires it and whether the 50 mm path
skips the platform raise as well.

> **Superseded twice.** 2026-09-08: the recording put cylinder B on the
> *engraved* path (below). 2026-09-10/11: the bypass is **solenoid 11**, and it
> is now modelled — see *Two routes* below. The table above had the route right
> and the barrel wrong.

The **second outfeed station** (coil 13) was in the same state and is not any
more. `FC6 N16` is symmetric — prox 9 runs a 5 s pulse to solenoid 12, prox 10
runs a 5 s pulse to solenoid 13 — and outfeed A stands at its own sensor, so
outfeed B stands at **PX10**. That is an inference from the program's structure
rather than from the layout, so it is `[ASM]`, and the station reads the same
waypoint its sensor does so the two cannot drift apart. *Placed at the
measured SV13 line on 2026-09-12 (plan H3): 55 cm along belt 3, downstream of
outfeed A rather than upstream as first assumed. A block that stops at outfeed
A never reaches it, which is why prox 10 has never tripped on the real cell.*

#### CYL_A's real bore, 2026-09-07 — the first parameter set from a nameplate

Six photographs taken at the cell carry three legible nameplates. Two are
Janatics barrels:

| Label | Series | Bore | Stroke |
|---|---|---|---|
| `A120323000` | A12, ISO 6431 profile | **32 mm** | 300 mm |
| `A510251600` | A51, ISO 6432 mini | **25 mm** | 160 mm |

`JanaticsData.m` §1B sets out the four independent corroborations of how those
ten-character codes are read — including that the vendor's own CAD folders are
named `Janatics-A27,A28` and `Janatics-A51,A52`, and that the large cylinder's
STEP `PRODUCT` strings read `JANATICS-DEFAULT_A12_*`.

**Bore 20 is now refuted, not merely doubted.** The model assumed it for all
six cylinders since Iteration 01. It appears in no source: not the CAD, which
measures 8 and 32, and not either nameplate.

The A12 is applied to `CYL_A`, and only to `CYL_A`. Three lines of evidence,
two of them independent of the photograph, say that is the right barrel: it is
the cell's large profile cylinder at the station that has to push; its stamped
300 mm stroke is the stroke **this model derived from the layout alone**, before
any label was read; and the intake sheet's hand-measured 290 mm agrees. The
other ten actuators keep the `[JAN]` bore 20 — known to be wrong, and still the
honest entry, because nobody has read those barrels. *Superseded 2026-09-13
(plan H7): every barrel now carries its nameplate bore and stroke. See
"Nameplate bores and strokes" below.*

Cycle time moved from **31.080 s to 33.840 s** and air per cycle **6.09 to 8.20
normal litres**. It is the same mechanism as the plant re-model above: a chamber
got bigger. `CYL_A`'s cap-side area went 314.2 → 804.2 mm² and its annulus
263.9 → 691.2 mm², so at an unchanged 300 mm stroke the barrel holds 2.6× the
air, branch 2 charges it more slowly, and the `CHG` / `BR_RDY` waits gate later.

Two things did **not** move, and both are checks rather than luck. Peak
pressures are unchanged to 3 mbar — the same regulator through the same
orifices; a bigger chamber changes how long it takes to fill, not what it fills
to. Final position moved 45 µm, because the locating stops are mechanical and a
stronger cylinder arrives at the same stop.

**It moved the right way, and that is weaker evidence than it looks.** Machine
time went 18.58 → 21.34 s against the real cell's ~62 s, so the gap closed from
3.35× to 2.91×. But roughly half of the 2.76 s is an **artefact**: rod speed is
set by the meter-out needle `P.C_ctrl_B`, a `[COMM]` figure chosen in Iteration
02 to give 0.20 m/s extend *on a bore-20 cylinder*. Venting a 2.6× larger
annulus through the same orifice gives 0.098 m/s, and no fitter would leave a
speed controller set for a cylinder that is no longer there. The needle is not
re-opened here, because inventing a second number to make the first comfortable
is the habit applying a nameplate is meant to break — `FactoryParams.m` §13J
§1B sets out the whole argument. **The bore stands on the stroke agreeing three
ways, not on the cycle time.** And one corrected parameter left 191% of the gap
in place; nine unread barrels will not close it on their own.

#### The engraving axis, 2026-09-08 — the largest single correction so far

Cycle time for that change went **33.840 s to 49.290 s**, machine time **21.34 → 36.79 s**,
and the gap against the real cell's ~62 s closed from **2.91× to 1.69×**. Nothing
was tuned: the only new number is a measured travel time.

The engraving platform was modelled as a stiff position PID driven to `z_top`,
which completed its whole travel in **0.225 s**. The machine does not do that.
The PLC listing has no position setpoint for this axis anywhere: `Axis_1` is
**jogged at a velocity until a limit switch trips** (`%I1.0` upper, `%I1.2`
lower), and in every recorded real cycle the two limit inputs are **7.7–8.3 s
apart in each direction**. The model was about **35× too fast**, twice per cycle.

It is now a velocity jog with hard stops at the limits — the limit switches in
`factory_sensors.m` were already position comparisons, so they needed no change,
which is a small sign the sensor layer was right. Air rose 2.9% because the
platform holds its load for longer; **peak pressures did not move at all**, the
check that the pneumatics were not disturbed.

Two things worth noting about the shape of this fix. The **size was predicted
before the change** — `NEXT_STEPS` F2 put it at ~15 s and it came out at 15.45 s.
And `P.t_max` had to go **45 → 90 s**: at 45 the cycle no longer fitted inside
the horizon and stalled in `S34`, which is the *horizon* stopping the run rather
than the plant. A model that had been quietly clipped would have looked like a
sequencing fault.

**What it does not close.** 1.69× is still 25 s unaccounted for. `NEXT_STEPS`
§4 puts ~11 s of that in the FC6 dwell timers, which are not implemented at all.

#### The measured cell, 2026-09-08 — pressure and the machine's own dwells

Ten real cycles came back from the machine's history database. Two things in
this model were set from measurement for the first time.

**The supply is 4.3 bar gauge, not 6.0.** 37 samples read 4.03–4.38, and all
four regulator faces agree. Lower supply means less force, slower rods and less
air: peak chamber pressures fell 1.7 bar and air per cycle fell 24%.

**And the machine's sequencer waits, where the model never did.** Four dwells
are now implemented — cylinder A's 8.059 s hold (n=7), the `T#5S` outfeed pulse
at 5.010 s (n=10), the `FC6 N4` transfer wait at 2.124 s (n=1) and `FC7 N2`'s
dispense TON at 2.021 s (n=1).

Cycle time then moved from **49.290 s to 63.160 s**, machine time 36.79 → 50.66 s
against a **measured 64.03 s**, so the gap closed from 1.69× to 1.26×.

**The temptation that was refused.** Cylinder A's interval measures 8.059 s
against the model's 2.72 s, and the obvious move is to close the meter-out
needle until the modelled rod is that slow. That would give the right cycle time
for the wrong reason: the machine has **no cylinder position feedback anywhere
in its 158 tags**, so it cannot be waiting for the rod — it is running a timer,
and the real rod almost certainly arrives early and then sits. The rod keeps its
speed; the sequencer waits.

**A coupling broke on the way, and is now structurally fixed.** Dropping the
regulator stalled the cycle outright — `P.P_br_rdy` was a free-standing absolute
*above* the new set point, so `BR_RDY` could never become true. It is now a
fraction of the regulated supply, which is what it always meant.

#### Cylinder B makes the engraver→belt-3 move, 2026-09-08

`solenoid_valve11` **never fires**. In the one real cycle recorded with all 158
tags watched it does not appear once, while cylinder B's coils rise at 80.751 s
and 88.950 s — held **8.199 s** — exactly in the slot where the block leaves the
engraver for belt 3. The model gave that move to solenoid 11 and completed it in
1.835 s.

The role and the geometry moved to `CYL_B`, and a fifth measured dwell went with
them. **Cycle time rose from 63.160 s to 70.370 s**, machine time 50.66 → 57.87 s
against a measured 64.03 s, so the gap closed from 1.26× to **1.11×**. *Correction, 2026-09-10: that ratio is not like for like. The
recorder ends a cycle when the last outfeed push STARTS; the model's total
includes the 5.66 s outfeed push and retract after it. Compared at the same
end point the model's machine time is about 52.2 s, roughly 1.23× short of the
measurement — see `Project_Notes/to_matlab/round2_2026-09-10/SEGMENT_BUDGET_2026-09-10.md`.*
*Applied 2026-09-12 (plan H1): to S37 the cycle is 64.70 s and machine time
52.20 s, 1.23×. `LOG.cycle_time_rec` carries it, and `CycleRegressionTest` and
`verify_model` pin it.*

The role swap **alone** moved the cycle 0.01 s, and that is the informative part:
the geometry was already correct and only the actuator was wrong. The 7.21 s is
the *dwell*, not the reassignment — but doing the swap first is what let the
dwell attach to the barrel that actually makes the move.

**This contradicts the machine's owner, and the contradiction is left standing.**
The owner said four times that cylinder B fires when engraving is *skipped*; the
recording shows it firing on the *engraved* path. Both cannot describe the same
cylinder. The owner's words are kept verbatim in `FactoryParams.m` §13E and are
not edited — what changed is which source the model follows for the engraving
path, and a transition log is an observation where a description is a memory.
**The bypass question is reopened**, and the five-minute panel test settles it.
*Answered 2026-09-10 at the panel and 2026-09-11 by the maintainer — see the
next section.*

#### Two routes: the SV11 bypass, 2026-09-11

The maintainer, at the cell:

> CYLINDER b FIRES WHEN ENGRAVING IS DONE AND IT PUSHES BLOCK TO BELT 3, SV11
> FIRES WHEN ENGRAVING IS SKIPPED

The first half is what the model has done since 2026-09-08. The second is new,
and the PLC listing says the same on its own terms: `FC6 N5` turns prox 8 into
`Wp_move_cv3`, and `FC6 N15` fires solenoid 11 on it as a `T#2S` pulse with
conveyor 3 on and conveyor 2 off. The model now runs both routes, chosen by
`P.engrave_selected` (`FactoryParams.m` §15):

| `P.engrave_selected` | route | states |
|---|---|---|
| `true` (default) | belt 2 stops on **prox 7**; cylinder A → engraver → platform → cylinder B → belt 3 | S00–S39, unchanged |
| `false` | the block runs on to **prox 8**; **SV11** pushes it straight across onto belt 3 | S00–S16, **S40–S43**, then S33–S39 |

```matlab
P = FactoryParams; P.engrave_selected = false;
LOG = run_factory_simulation('Params', P);
```

The bypass completes in **25.37 s** (29.74 s since H2–H8 went in on 2026-09-12/13; 23.94 s to S37), all of it machine time: no cylinder A or
B, no platform, no operator. The engraved cycle is unchanged at 70.370 s. Air
per cycle moved 6.413 → 6.452 NL, because SV11 now derives its own 300 mm
stroke instead of borrowing cylinder B's 250 mm, and its idle chamber is
charged every cycle. Two sensors moved with the route: **prox 7** now sits at
`c2_end` and ends the engraved belt-2 run (`FC7 N5` → `FC6 N7`), at the trip
point prox 8 used to supply, and **prox 8** sits at `c2_byp`, the bypass pickup
the operator named — which is why an engraved block never trips it on the real
cell.

**What is still open.** No bypass cycle has ever been recorded, so nothing pins
the bypass's times, and `BypassRouteTest` checks behaviour only. The layout
gives SV11 252.5 mm of travel against a stamped 160 mm stroke: the schematic is
too wide at that station, and that waits on the belt datums. And what the HMI
selects the skip *with* is not established.

#### The T#10S start delay, 2026-09-12

The machine waits **10 s** after START before the first magazine push, and it
checks no pressure while it does. `cmd_start` → SV1 is 9.987, 10.013, 10.026,
10.167 and 10.196 s over five recorded cycles. The PLC listing has a `T#10S`
beside `CMD_START` that was read in August as a cycle watchdog; the recordings
say it is a start delay. The model spent that window charging the receiver to
`P.P_ready`, a threshold the real supply never reaches, and moved on after
2.38 s.

S03 now holds for `P.PLC.t_start_delay`. It still waits for `P_READY` too, but
that is met long before and binds only if the supply fails. The magazine push
fires at 10.17 s. **Cycle time grew from 70.370 s to 78.020 s**. To S37, where
the recorder stops its clock, the cycle goes 64.70 → 72.35 s and machine time
52.20 → 59.85 s, against a measured 64.03 s: **1.07×, from 1.23×**. Air, peak
pressures, final position and the 39 transitions did not move, because the
wait is dead time.

The cylinder-home pulse the machine fires in that window (SV10 for ~2 s, SV8
for ~5 s) is not modelled. This model holds coils rather than pulsing them,
and both rods already start home, so the pulse would move nothing.

The SV11 bypass waits the same 10 s: 25.37 → 33.02 s, or 27.35 s to S37.

#### Belt 3 from the tape, 2026-09-12

The maintainer measured every station along belt 3 from the belt's own start:
SV11's drop 0 cm, cylinder B's drop 17 cm, SV12's push line 43 cm (px9 at 47)
and SV13's 55 cm (px10 at 60). The drawing and the tape share one point,
cylinder B's drop, and agree on it to 1.5 cm, which fixes the datum.

| Belt 3 | Model until today | Tape | Now |
|---|---|---|---|
| outfeed A (SV12), px9, end stop, bin | 65 cm | 43 cm | 43 cm |
| outfeed B (SV13), px10 | 46 cm, **upstream** of A | 55 cm, **downstream** | 55 cm |
| SV11's drop | 18.5 cm, shared with cylinder B | 0 cm | 5 cm (block centre) |

**Cycle time fell from 78.020 s to 76.550 s**: the belt-3 run went 3.10 → 1.64 s
(the one recorded real cycle has 1.02 s). To S37 the cycle is 70.88 s and machine
time 58.38 s, against a measured 64.03 s: **1.10×**. That is further from the
machine than H2 left it, and correctly so: belt 3 was too long, so fixing it
makes the model faster. What remains is H4–H6 in the plan.

Two things fell out of it:
- **Prox 10 never trips.** A block stopped at outfeed A never reaches outfeed B,
  and prox 10 has never tripped in any real cycle either (finding F4).
- **SV11's stroke conflict is gone.** Landing at belt 3's start takes 117.5 mm of
  travel, 125 mm on the stroke ladder. The old layout needed 252.5 mm from a
  barrel stamped 160.

The final position moved with the bin to (1.28984, 0.20000) m, error 0.16 mm.
Air per cycle went 6.45 → 6.30 NL, because SV11's idle chamber shrank.

Belt 2 did not move. Measured from its own start, the drawing already agrees
with the tape: px7 26.0 cm against 25, and px8 46.4 against 47. That holds
because the maintainer confirmed on 2026-09-12 that cylinder A pushes beside
px7, so the "0 cm" push line was measured to something else. The bypass cycle
is now 31.93 s (26.26 s to S37).

#### Belt speeds, 2026-09-12

Two of the three belts are now timed over measured distances. None is converted
from the drive's `Set_Velocity = 180`, whose unit nobody has confirmed.

| Belt | Was | Now | Evidence |
|---|---|---|---|
| 1 | 0.150 `[ASM]` | **0.210** `[PLC]` | leading edges over the 110 mm magazine pitch, four automatic cycles |
| 2 | 0.150 `[ASM]` | **0.310** `[MEAS]` | the maintainer's tape, 75 cm in ~2.4 s; the recorder bounds it at ≥ 0.27 |
| 3 | 0.150 `[ASM]` | 0.150 `[ASM]` | no usable recording; time it on Wednesday |

**Cycle time dropped from 76.550 s to 75.070 s**. The belt-1 run went 4.22 →
3.15 s against 3.08 s recorded, so it is now inside criterion C3. The belt-2 run
went 1.39 → 0.98 s against 2.70 s recorded, which is further out. That is not
the speed: the model's block rides 220 mm of belt 2, where the real one rides
from px6 to px7, 45 cm, with the transfer push and belt 2 starting together.
That geometry is H5. Machine time to S37 is now 56.90 s against 64.03 s:
**1.13×**. The bypass cycle is 29.75 s (24.08 s to S37).

#### Push and belt together, 2026-09-12

In every recorded cycle conveyor 2 starts in the **same sample** as the transfer
push (SV6): 19.651 s for both in C0003-180221. Conveyor 3 starts in the same
sample as cylinder B's retract (SV10): 88.950 s. The model used to finish each
push, bring the rod home, and only then start the next belt. Now belt 2 starts in
S13 with the push and belt 3 in S32 with the retract. No state was renumbered:
S15 and S33 find their belts already running.

| Handover | Model before | Model now | Recorded |
|---|---|---|---|
| px6 → belt 2 starts | 3.14 s | **2.14 s** | 2.12 s |
| cylinder B extends → belt 3 starts | 8.90 s | **8.21 s** | 8.20 s |

**Cycle time shortened from 75.070 s to 73.620 s**, and machine time to S37 from
56.90 to 55.45 s against a measured 64.03 s: **1.15×**. The block now lands on a
belt 3 that is already moving, so the final position shifts by 0.14 mm (error
0.30 mm). The bypass is 29.00 s (23.33 s to S37). `compare_to_recording` now
times the belt runs from the states that really start them (S13 and S32).

Belt 2 is still the model's clearest miss: 1.22 s from start to stop against
2.70 s recorded. The real block travels 45 cm to px7 (67 cm to px8), where the
model's travels 33 cm. The px6 "−20 cm" reading that would lengthen the model's
path is not applied: taken at face value it needs a 240 mm transfer push from a
barrel stamped 160 mm.

#### The wait before cylinder A, 2026-09-13

The machine fires cylinder A's extend coil (SV7) **1.31–1.58 s after conveyor 2
stops**: mean 1.463 s, spread 0.126, over seven recorded cycles. The model spent
0.17 s there. The round-2 handoff called this "not a timer", because it scatters,
and that stands. What is known since is the cause: SV7 rises in the same sample
the PLC's conveyor-2 axis finishes a position move, so the wait follows a motion
whose length depends on where the block stopped. The model has no such axis, so
S18 now waits the measured mean, `P.PLC.t_cylA_wait` `[PLC]`.

**Cycle time lengthened from 73.620 s to 74.930 s**. Conveyor 2 off → SV7 is now
1.48 s against 1.463 s recorded. Machine time to S37 is 56.76 s against 64.03 s:
**1.13×**, the first correction since H2 to move the model toward the machine.
Air per cycle rose 6.29 → 6.47 NL. The wait holds branch 2 selected for 1.46 s
longer and the model draws through it. That is observed, not traced further. The
bypass never passes S18 and is unchanged at 29.00 s.

#### Nameplate bores and strokes, 2026-09-13

Every barrel now carries what its label says. Until today only cylinder A did;
the other ten ran on a catalogue bore of 20 mm that nothing in the cell has.

| Barrels | Label | Bore / rod | Stroke |
|---|---|---|---|
| cylinder A | `A120323000` (A12) | 32 / 12 | 300 |
| cylinder B | `A280323000` (A28) | 32 / 12 (rod `[EST]`) | 300 |
| MAG1–5, xfer1, SV11, SV12 | `A510251600` (A51) | 25 / 10 (rod `[EST]`) | 160 |
| SV13 | `A520251600` (A52, magnetic) | 25 / 10 (rod `[EST]`) | 160 |

MAG1, 3, 4 and 5 were not photographed. The maintainer's statement that every
unique barrel was photographed covers them. Strokes are now the stamped ones: a
new `stroke_mm` column overrides the old rule of rounding the travel up the
catalogue ladder, and the model refuses a stamped stroke too short to reach its
own switch.

That check caught one thing. SV12 and SV13 pushed the block 186.5 mm into the
bin, which a 160 mm barrel cannot do. The bin is an `[ADD]` (the drawing has
none), so it moved up 36.5 mm. The push is now 150 mm, the switch trips at
155 mm, and the block still leaves belt 3 with room to spare.

**Cycle time went up from 74.930 s to 75.720 s**. Machine time to S37 is 57.41 s
against 64.03 s: **1.12×**. Air per cycle rose **6.47 → 9.57 NL**, because every
chamber got larger. The final position moved with the bin to (1.28983, 0.23650)
m. The meter-out needles were not re-opened for the bigger barrels, for the
reason given when cylinder A's bore went in. The bypass is 29.77 s (23.96 s to
S37).

#### Room air, 2026-09-13

Room air was measured at 25 °C at the cell on 2026-09-10. The model assumed
20 °C. `P.T_air` is now 298.15 K `[MEAS]`. It enters the physics only as R·T,
in every chamber, branch and the receiver. Warmer air carries less mass at the
same pressure, so every fill costs less air.

**Cycle time eased from 75.720 s to 75.650 s**. Machine time to S37 went
57.41 → 57.35 s, still **1.12×** against 64.03 s. Air per cycle fell **9.57 →
9.43 NL** (−1.5%). The sweep predicted −0.10 s at the 2026-09-10 baseline; at
today's it is −0.06 s. This is one reading on one afternoon, not a controlled
temperature, so a second reading on Wednesday is still worth taking. The
bypass is 29.74 s (23.94 s to S37).

#### The operator is a distribution, 2026-09-09

The model predicted the same cycle time every run. **The real cell does not.**
Seven real cycles put the operator's dwell at 5.95, 7.28, 8.97, 13.22, 16.25,
17.53 and 28.65 s — mean 13.98, **standard deviation 7.83**. The slowest cycle
took nearly five times the fastest.

Quoting a single cycle time was a category error, not a calibration error, and
no amount of lab data fixes it.

`operator_distribution` now reports a distribution:

| | mean | median | sd | min | max |
|---|---|---|---|---|---|
| ~~**predicted**, to S39~~ | ~~71.70~~ | ~~71.08~~ | ~~7.21~~ | ~~63.81~~ | ~~86.51~~ |
| ~~**predicted**, to S37 (H1, 2026-09-12)~~ | ~~66.03~~ | ~~65.41~~ | ~~7.21~~ | ~~58.14~~ | ~~80.84~~ |
| ~~**predicted**, to S37, with the start delay (H2, 2026-09-12)~~ | ~~73.68~~ | ~~73.06~~ | ~~7.21~~ | ~~65.79~~ | ~~88.49~~ |
| ~~**predicted**, to S37, after belt 3 (H3, 2026-09-12)~~ | ~~72.21~~ | ~~71.59~~ | ~~7.21~~ | ~~64.32~~ | ~~87.02~~ |
| ~~**predicted**, to S37, after the belt speeds (H4, 2026-09-12)~~ | ~~70.73~~ | ~~70.11~~ | ~~7.21~~ | ~~62.84~~ | ~~85.54~~ |
| ~~**predicted**, to S37, after the push/belt overlap (H5, 2026-09-12)~~ | ~~69.28~~ | ~~68.66~~ | ~~7.21~~ | ~~61.39~~ | ~~84.09~~ |
| ~~**predicted**, to S37, after the wait before cylinder A (H6, 2026-09-13)~~ | ~~70.59~~ | ~~69.97~~ | ~~7.21~~ | ~~62.70~~ | ~~85.40~~ |
| ~~**predicted**, to S37, after the nameplate bores and strokes (H7, 2026-09-13)~~ | ~~71.24~~ | ~~70.62~~ | ~~7.21~~ | ~~63.35~~ | ~~86.05~~ |
| **predicted**, to S37, after the room air (H8, 2026-09-13) | 71.18 | 70.56 | 7.21 | 63.29 | 85.99 |
| **observed** (n=6) | 79.35 | 77.57 | 9.04 | 70.22 | 90.24 |

~~**81% of the observed range is covered**, and the +7.6 s mean shift is the
already-tracked machine-time gap, not something new.~~ *Corrected 2026-09-12
(plan H1).* The struck row added the operator draw to machine time **to S39**,
but the observed cycles end at S37, when the last outfeed push starts. Like for
like, **53% of the observed range is covered** and the mean shift is **+13.3 s**.
That is the same machine-time gap (1.23×), measured at the right end point. The
method stands; the end point was wrong.
*After H2 the same day, with the `T#10S` start delay in the model, **91%** of
the observed range is covered and the mean shift is **+5.7 s**.*
*After H3, with belt 3 at the tape's length, **84%** is covered and the mean
shift is **+7.1 s**.*
*After H4, with the measured belt speeds, **77%** is covered and the mean shift
is **+8.6 s**.*
*After H5, with push and belt together, **69%** is covered and the mean shift
is **+10.1 s**.*
*After H6, with the wait before cylinder A, **76%** is covered and the mean
shift is **+8.8 s**.*
*After H7, with every barrel's nameplate, **79%** is covered and the mean shift
is **+8.1 s**.*
*After H8, with room air at 25 °C, **79%** is covered and the mean shift is
**+8.2 s**.*

**Three things are deliberately NOT claimed.** The draw is a **bootstrap over
the seven observations**, not a fitted lognormal — with n=7 a fitted shape
would be an artefact of seven points. The **split** between noticing and
engraving is still `[PLH]`: only the total dwell and the confirm delay were
measured, and one observation cannot support a ratio. And the predicted spread
is the measured operator spread arriving intact at the far end — the model
still predicts **zero** machine-time variance, where the real cell varied
61.25–63.24 s.

`FactoryParams` **never samples**. It takes no arguments and much of the project
calls it expecting the same struct; the draw lives in `factory_operator_draw`
and has to be asked for. `OperatorDistributionTest` holds that line.

#### You as the operator: manual input, 2026-09-13

`run_factory_simulation('Operator', 'console')` hands the cycle's two human
moments to a person at the MATLAB console, the way the real HMI does:

1. **Before the cycle:** engrave this part (the 50 mm job) or skip engraving?
   Skip sends it through the SV11 bypass.
2. **At S25, platform up:** the console waits `P.OP.t_laser_50` of **real
   time** while the laser runs, then asks for **ENG DONE** (press Enter). How
   long you take becomes the operator part of the dwell. The confirm after it
   is the measured 1.297 s from button to platform.

Only those waits run on the wall clock. The machine's motion is computed as
fast as ever, so the run's machine time is the automatic run's to within a
scan, and `ManualInputTest` pins that. The laser time is a **placeholder**
(4.65 s, `[PLH]`, the user's choice). The one piece of footage with the laser
visibly on (`Wood Carving.mp4`) implies about ≥ 3.0 s. The seven recorded
dwells cannot bound it, because the engraver was not working when they were
recorded. Only the 50 mm job is offered, since no 25 mm engraving has ever
been recorded. It runs on the MATLAB path only, and needs an interactive
session: `matlab -batch` has no keyboard. `LOG.operator` records what you
chose and how fast you pressed.

**Watch it live.** `run_factory_simulation('Operator','console','Live',true)`
draws the cell while the cycle runs, in real time (`'LiveSpeed'`, 1 by
default). At S25 the figure shows the laser, a violet mark and a countdown,
then waits for ENG DONE: **any key on the figure**. Shift, Ctrl or Alt alone
do not count. If you close the figure while it waits, the Command Window takes
over. The figure and the Command Window cannot both be listened to at once,
because MATLAB's `input()` blocks until Enter. The live view is display only,
and `LiveViewTest` checks that it computes the same `LOG`. `visualize_factory`
replays the same frames, with the same operator line, afterwards.

#### A units trap worth knowing about
The intake workbook asks for millimetres. The lab readings were taken in
**centimetres** — the conveyor went in as `76` where the tape had read 760 mm,
and the block as `10 × 10 × 4`. The workbook's derived-mass formula propagated
that faithfully into **0.300 grams**, and a complete re-baseline was built on it
before magazine geometry caught the error. Note the digits: 0.300 g against the
true 0.300 kg. The readings were never wrong; the unit was.

`Physics_Framework.xlsx` now stores those cells in millimetres,
with the original reading kept in a cell comment.

**It happened again on 2026-09-07**, on a sheet whose own printed instruction is
"Write millimetres, not centimetres". The ten sensor positions came back as
`0mm, 12cm, 23cm, 34cm, 46cm, …` — the writer switched to cm at the second row.
This time it was caught before anything was applied, and by the same method:
sensors 1–5 are the five magazine dispense confirms, so the gaps between them
*are* the magazine slot pitch. Read as cm they give 120, 110, 110, 120 mm
against the CAD's 105–110 mm. Read as mm they give a pitch of 11.5 mm — a
magazine narrower than the 100 mm block it holds. **Check a hand-entered
measurement against known geometry before believing it**; the geometry says
which unit it is, and no amount of care with the pen ever will.


### Simplified
- Isothermal receiver; polytropic chambers with a fixed index
- Ideal regulator with no droop
- First-order valve spool dynamics
- Rigid workpiece, **2 translational DOF only**. It is not a planar rigid
  body: there is no orientation state, `P.blk_J` is computed in
  `FactoryParams.m` and used nowhere, and every contact (rod tip, locating
  stop, belt friction) acts at the centroid, so no moment can arise. An
  off-centre rod strike pushes the part perfectly straight. `support_region`
  and the proximity sensors also test the centre point only, so part size
  never affects when a sensor trips or when a part transfers between
  surfaces. See `Project_Notes/NEXT_STEPS.md` 6.5
- Conveyor belts as rigid surfaces, no stretch

### Placeholder
`t_op_notice` (3.0 s), `t_engrave` (8.0 s), `t_op_confirm` (1.5 s) —
`Sequence.xlsx` gives no duration for the three manual operator steps. Together
they are 12.5 s of a 75.65 s cycle: **17% of the cycle is invented timing** — down from 40% two days ago, because the machine time around them grew to something closer to the truth rather than because the placeholders improved.

### Hardware provenance — **two components identified 2026-09-07**
This section read "No nameplate, BOM, purchase order or photograph of the
installed equipment has ever been supplied" from Iteration 01 until 2026-09-07,
and it is kept in that shape because it is why the register looks the way it
does: one provisional candidate per duty, never promoted by repetition.

**Three nameplates have now been read off photographs of the cell**:
`A120323000` and `A510251600`, the two Janatics barrels above, and
`JK42HS34-1334`, a NEMA 17 hybrid stepper — the first motor label this project
has ever had, and enough to retire the "generic 3-phase" description of the
conveyor drives for good.

Two of the eleven pneumatic actuators are identified and **nine are not**. One
of the two is tied to a specific actuator (`CYL_A`) and applied; the A51 cannot
be, because nothing yet says which of the remaining ten rows it belongs to —
that is a five-minute panel test, `INPUTS_REQUIRED.md` question 3b. The motor is
recorded and **not** applied: the photograph does not say which of the cell's
four stepper axes it was taken on, and `P.N_gear = 20` with `P.T_max = 0.050
N·m` is a self-consistent invented set that one real figure would make *less*
coherent, not more.

Every other Janatics component remains a technically compatible selection, not a
component known to be installed, and those catalogue figures are still
second-hand: the retrieval URLs and page numbers were never captured.

### Simulink vs MATLAB-only divergence — **resolved**
The two paths used to drift progressively: about 10 ms early in the cycle, about
300 ms by `S39_CYCLE_COMPLETE`, with a 0.49 mm final-position difference.

The cause was not integration. `factory_plc_sfun` ran its scan in `Update` but
emitted the result from `Outputs`, so the plant received every command exactly
one PLC scan late, and the lag accumulated once per physics-gated transition.
The giveaway was that every increment of the divergence was an exact multiple of
`P.t_scan` — integration error cannot be quantised to the PLC clock.

It is now `P.plc_io_delay`, honoured by both paths and defaulting to 0. The
paths agree to 2.7e-11 s on timing (floating-point time accumulation) and are
bit-identical in final position and air consumption. Check it yourself:

```matlab
R = compare_execution_paths
```

The remaining open question is physical, not numerical: the real cell's PLC scan
execution time has never been measured. See `INPUTS_REQUIRED.md` section 3.

### Not implemented
Compressed-air temperature effects, tube dynamics, belt stretch, workpiece
rotation, multi-part flow, vision processing, electrical loads, wear.

---

## 12. Troubleshooting

| Symptom | Cause and fix |
|---|---|
| `Undefined function 'FactoryParams'` | Not in the project folder. `cd` to it, or run `check_environment`. |
| Simulink build fails at the plant S-function | A port-based sample time was reintroduced in `factory_plant_sfun.m`. It must declare `block.SampleTimes` only. |
| `verify_model` reports a failure | Compare against the reference table. If a parameter changed deliberately, re-baseline `verify_model.m` **and** `CycleRegressionTest.m` together. |
| Cycle does not complete | Check `LOG.plc.timeouts` — a watchdog fired, meaning a sensor never confirmed. |
| Python tests skip everything | `matlab` is not on `PATH`, or `FACTORY_SKIP_MATLAB` is set. |
| Stale results after editing a `.py` | Clear `__pycache__`; a restore that moves mtime backwards makes Python reuse cached bytecode. |
| Figures left open / workspace dirty | `reset_factory` |

---

## Provenance of this document

This file replaces `README_SIMULATION.md`, which was removed on 2026-08-21 —
recover it from git history if you need the earlier wording. Project history is
in `Project_Notes/ITERATION_LOG.md` (the running log), with the fuller original
accounts in `Project_Notes/History/`.
