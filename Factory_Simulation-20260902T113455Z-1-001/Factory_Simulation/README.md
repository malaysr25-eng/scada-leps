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
| Operator timings | **Not yet faithful** — 12.5 s of the 31.08 s cycle is placeholder |
| Variability | **Not faithful, and now known to be structural** — the model is deterministic, but engraving ends when an **operator presses a button** (confirmed 2026-08-25). 12.5 s of the 31.08 s cycle is human-paced, so cycle time is not a predictable quantity. The honest prediction is **machine time, ~18.58 s**, with an operator distribution on top |

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
| 5 pneumatic cylinders | Polytropic chambers with moving boundary, ISO 6358 restriction flow, meter-out speed control |
| 3 conveyors | DC drivetrain referred to the pulley shaft, PI speed loop with ramp limiting |
| Engraving base | Position-controlled vertical axis with force and speed limits |
| Workpiece | Rigid body on a support surface, Hunt-Crossley contact, regularised Coulomb friction |
| Proximity / reed / height sensors | Pure functions of physical state, with a transport delay |
| PLC | 40-state scan-based sequencer, 10 ms scan, sensor-guarded transitions |

**Cycle:** 31.08 s, of which 12.5 s is operator/engraving placeholder time and
18.58 s is machine time.

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
| MATLAB | R2018b or newer | Floor set by `yline`, `sgtitle`, `Simulink.BlockDiagram.arrangeSystem` |
| Simulink | Only for the Simulink path | `run_factory_simulation` needs base MATLAB alone |
| Stateflow | Optional, **installed** | `build_factory_model('PLC','stateflow')` builds and runs; its sequence is unverified against `factory_plc` |
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
│   │   └── Janatics_Component_Register.csv
│   │
│   ├── Physics and control
│   │   ├── factory_derivatives.m    continuous-time equations of motion
│   │   ├── factory_sensors.m        sensor models
│   │   ├── factory_plc.m            40-state sequencer
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
cycle time      31.08 s        final position   (1.50938, 0.20000) m
position error  0.62 mm        peak chamber A   7.01 bar
transitions     39             peak chamber B   7.24 bar
watchdog        none           air per cycle    4.96 NL
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
  logic, bus tags, viewer scopes, `To Workspace` sinks.
- **`verify_model.m`** — checks derived quantities and cycle results against
  reference values, plus a one-sided pressure-rating bound.
- **`run_all_tests.m`** — runs the `matlab.unittest` suite.
- **`compare_execution_paths.m`** — runs both paths and reports their
  disagreement per PLC state transition, plus cycle time, final position and air
  consumption. This is the instrument that localised the historical Simulink
  divergence to a one-scan command latency, and it is the regression guard that
  keeps it closed. Run it after any change to the scheduling of either path.


### Display

- **`plot_factory_results.m`** — the static results dashboard.
- **`visualize_factory.m`** — animated replay of the cycle on the cell layout.
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

151 tests, about 165 s.

If you are running a copy of this folder on its own, expect **150 / 151 passed
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
| `PlcIoTest` | the real PLC tag register, the model's mapping to it, and that `P.REAL` cannot drift from the register |
| `DocumentationTest` | that this README and the `run_all_tests` header still describe the suite and the files that actually exist — the count below is asserted, not maintained by hand |
| `DocumentationFactsTest` | that numbers written in **prose** match the model — the provenance table against a live `audit_provenance`, quoted parameter values against `FactoryParams`, and a blocklist of claims the project has since overturned. `DocumentationTest` checks the docs are *consistent*; this checks they are *true* |
| `ProcessViewTest` | `visualize_processes`: that the process table partitions all 40 PLC states with no gap or overlap, and that logged forces sum to `m*a` |
| `OptionParsingTest` | Name/Value option handling on every entry point; that `factory_help` output is safe to paste whole |
| `PlcIoLatencyTest` | `P.plc_io_delay`: that delay 1 reproduces the historical Simulink numbers, that the shift is a whole number of scans, and that it accumulates |
| `SimulinkModelTest` | model build, run, sample times, and exact MATLAB agreement — tagged `Slow`, excluded by default |

Include the Simulink tests (several minutes):

```matlab
run_all_tests('IncludeSlow', true)
```

### Python suite

```bash
python -m unittest discover -p "test_*.py"
```

**78 Python tests**, about 60 s. Worded so it cannot be confused with the MATLAB count above — `DocumentationTest` pins that one against the live suite and requires it to appear exactly once.

| File | Covers |
|---|---|
| `test_janatics_physics.py` | the four closed-form primitives — `mdot_orifice`, `contact_hc`, `friction_2d`, `support_of` — asserted as **physical invariants rather than recorded outputs**, so they survive a re-baseline: ISO 6358 choking below `b_crit`, Hunt-Crossley force vanishing *continuously* at separation, friction saturating at `μ_k·N` |
| `test_janatics_dynamics.py` | integrated behaviour of the reference port |
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
| `[PLH]` | placeholder, must be replaced | 3 |
| `[ASM]` | engineering assumption — in no source | 38 |
| `[EST]` | engineering estimate | 34 |
| `[JAN]` | Janatics catalogue figure — provisional until confirmed | 7 |
| `[COMM]` | commissioning setting — read it off the machine | 6 |
| `[CAL]` | calculated from the above — recomputes itself | 14 |
| `[PLC]` | **observed** on the real machine’s PLC | 37 |
| `[MEAS]` | **measured** by hand on the machine | 14 |
| `[CAD]` | **read from the vendor solid model** | 27 |
| | **total** | **180** |

**78 parameters are now facts about the real machine** — 37 read off the PLC,
14 measured by hand or read off a photograph of the running cell, and 27 read
out of the vendor CAD. Against that, **75 are still unmeasured**
(`PLH` + `ASM` + `EST`) and 7 Janatics figures are provisional.

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

**Not yet modelled:** there is no product selection and no no-engrave branch,
so nothing ever commands CYL_B. It stands at the engraver, borrows CYL_A's
stroke — the other half of the same double-solenoid pair — and claims no travel
of its own, because what it moves has not been stated. Its rod is barred from
touching the workpiece (`contact = false`), which on this reading is simply the
physics: a cylinder belonging to the engraving machine does not push the part.

That bar also fixed a real defect under the first reading, which is worth
keeping. Placed as a diverter at the *end* of conveyor 2 pushing in −y, it was
collinear with that belt's own travel: its retracted tip sat in the path of the
block coming down it, the contact model read the approach as interference, and
the cycle diverged to `NaN` and timed out at transition 10.

An actuator can therefore be in one of **three** states, not two — fully placed,
**positioned with no path** (CYL_B), or unplaced. Question 3c asks what
cylinder B actually moves and how far.

The **second outfeed station** (coil 13) was in the same state and is not any
more. `FC6 N16` is symmetric — prox 9 runs a 5 s pulse to solenoid 12, prox 10
runs a 5 s pulse to solenoid 13 — and outfeed A stands at its own sensor, so
outfeed B stands at **PX10**. That is an inference from the program's structure
rather than from the layout, so it is `[ASM]`, and the station reads the same
waypoint its sensor does so the two cannot drift apart.

#### A units trap worth knowing about
The intake workbook asks for millimetres. The lab readings were taken in
**centimetres** — the conveyor went in as `76` where the tape had read 760 mm,
and the block as `10 × 10 × 4`. The workbook's derived-mass formula propagated
that faithfully into **0.300 grams**, and a complete re-baseline was built on it
before magazine geometry caught the error. Note the digits: 0.300 g against the
true 0.300 kg. The readings were never wrong; the unit was.

`Physics_Framework.xlsx` now stores those cells in millimetres,
with the original reading kept in a cell comment.


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
they are 12.5 s of a 31.08 s cycle: **40% of the cycle is invented timing.**

### Hardware provenance
No nameplate, BOM, purchase order or photograph of the installed equipment has
ever been supplied. Every Janatics component is a technically compatible
selection, not a component known to be installed. Catalogue figures are
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
