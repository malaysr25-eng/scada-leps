# DIGITAL TWIN INTEGRATION

How the MATLAB/Simulink physics model connects to the live HMI, what is real,
and what is not.

---

## 1. The integration, in one diagram

```
   MATLAB (offline, run on demand)                 Python backend (live)
  ┌──────────────────────────────────┐           ┌─────────────────────────┐
  │ run_factory_simulation()         │           │  PlcService  250 ms     │
  │   RK4, 200 Hz, full 31.08 s cycle│           │  real machine state     │
  │            │                     │           └───────────┬─────────────┘
  │            ▼                     │                       │
  │ LOG struct                       │           ┌───────────▼─────────────┐
  │            │                     │           │  TwinAdapter            │
  │            ▼                     │  JSON     │  aligns the reference   │
  │ tools/export_twin_reference.m    │──────────►│  to the live cycle clock│
  │   READ ONLY. Modifies nothing.   │           │  → predicted vs actual  │
  └──────────────────────────────────┘           └───────────┬─────────────┘
                                                             │ SSE
                                                 ┌───────────▼─────────────┐
                                                 │  Digital Twin page      │
                                                 │  every figure carries   │
                                                 │  a provenance tag       │
                                                 └─────────────────────────┘
```

---

## 2. Why a reference trajectory and not co-simulation

`run_factory_simulation` is a **batch integrator**. It solves an entire 31.08 s
cycle with RK4 and returns a `LOG` struct sampled at 200 Hz. There is no stepping
API, no server, no way to advance it by one control period.

`README.md` is explicit that this is deliberate:

> The objective is to mimic the physical apparatus as closely as possible.
> Wall-clock runtime is explicitly *not* a metric. A change that makes the model
> faster but less faithful is a regression here, not an improvement.

Driving a browser from a live MATLAB Engine session would therefore require one
of two unacceptable things:

1. **Rewrite the solver into a stepped one.** That changes the validated model,
   invalidates `CycleRegressionTest` and `compare_execution_paths`, and is
   forbidden by the brief.
2. **Block the HMI for ~30 s per cycle** while MATLAB integrates.

Exporting the nominal trajectory once gives the operator a real reference to
diverge from, costs nothing at runtime, needs no MATLAB licence on the lab PC,
and leaves every file of `Factory_Simulation/` untouched. The exporter only
*reads* `LOG`.

### Alternatives considered

| Approach | Rejected because |
|----------|------------------|
| MATLAB Engine API for Python | Requires a licence on the control PC, adds a heavyweight process to the control path, and still cannot step the batch solver |
| Simulink real-time / rapid accelerator | Needs Simulink Coder; the model is documented as base-MATLAB-runnable and this would fork the execution paths the project works hard to keep identical |
| Re-implement the physics in Python | A second implementation to keep in sync. `test_model_equivalence.py` exists precisely because that is expensive |
| CSV exchange | JSON matches the rest of the system's boundaries and carries structure natively |

---

## 3. What is exported

`tools/export_twin_reference.m` writes `data/twin_reference.json`:

| Field | Contents |
|-------|----------|
| `meta` | MATLAB version, state count, sample rate, position error, air per cycle |
| `cycleTime` | `LOG.cycle_time` (nominal 31.08 s) |
| `transitions` | Every PLC state change: `{t, index, state, excelRef, guard}` |
| `series` | Downsampled trajectories: `v_belt1..3`, `P_res`, `base_z`, `blk_x/y`, `rod1..n` |
| `parameters` | The tagged parameter list with provenance codes |
| `caveats` | The model's own stated limitations, carried through verbatim |

Series are downsampled from 200 Hz to 20 Hz. The HMI refreshes at 4 Hz against a
250 ms PLC poll, so shipping the full log would inflate the file roughly tenfold
to carry detail nothing downstream can use.

State indices are emitted 0-based, matching the convention `export_equivalence_data.m`
already uses, so the two records stay directly comparable.

---

## 4. What is compared

### Machine state

| Shown | Source |
|-------|--------|
| Real elapsed cycle time | Live, from the cycle start timestamp |
| Nominal cycle time | Twin reference, tagged `PLH` |
| Predicted twin state at this elapsed time | Reference transitions |
| Inferred real state | Sequence tracker (inferred, not read) |
| Agreement | AGREE / DIVERGENT / UNKNOWN |

### Conveyors

Four numbers per belt, which is the point:

| Value | Source | Provenance |
|-------|--------|------------|
| Commanded | `Pot_Control.ConvN.Set_Velocity` | `LIVE` |
| Run coil | `Digital_Outputs.ConveyorN` | `LIVE` |
| Feedback | `Pot_Control.ConvN.Current_Velocity_Fb` | `LIVE` |
| Predicted | Twin `v_beltN` at this elapsed time | `ASM` |

Status is `MISMATCH` when the run coil is on and feedback is zero, `DIVERGENT`
when commanded and feedback differ by more than the tolerance. This is the
instrumentation for E-07.

### Timing divergence

When the real cycle passes the twin's predicted time for the current state by
more than the tolerance, a mismatch is raised:

```
DIGITAL TWIN MISMATCH
Step 16 Block reaches position 3
Twin predicts this state at t=12.40 s; the real cycle is at
t=15.80 s (+3.40 s). Waiting for: Proximity sensor 3.
```

---

## 5. Provenance — what every number is actually based on

The model's documentation is unusually candid about its own calibration, and the
HMI honours that rather than papering over it. Codes come from the model's own
scheme in `FactoryParams.m`; they are not re-derived here, so the HMI and the
model cannot disagree about what has been measured.

| Code | Meaning | Count in the model |
|------|---------|--------------------|
| `LIVE` | Read from the PLC this poll | — |
| `MEA` | Measured on the real cell | few |
| `CAL` | Calculated from other parameters | 14 |
| `JAN` | Janatics catalogue — a *compatible candidate*, not a confirmed part | 7 |
| `COMM` | A commissioning setting read off the machine | 6 |
| `EST` | Engineering estimate from typical data | 27 |
| `ASM` | Engineering assumption, in no source | 39 |
| `PLH` | Placeholder, known to be wrong | 3 |

**69 of 97 tagged parameters are unmeasured** (`PLH` + `ASM` + `EST`).

Every twin figure in the UI carries its code as a small chip. `LIVE` and `MEA`
render green; `PLH` renders red; everything else renders in the twin's violet.
An operator can therefore see at a glance whether a "prediction" rests on a
measurement or an assumption.

### Caveats carried through to the screen

Displayed in amber at the top of the Digital Twin page, straight from the export:

- `SCALE` is recorded as **CONFIRMED INCORRECT** in the lab data sheet. All
  predicted positions inherit that error.
- Every Janatics component is a technically compatible candidate. No nameplate,
  BOM or photograph of the installed equipment has ever been supplied.
- **12.5 s of the 31.08 s nominal cycle is operator/engraving placeholder time**
  with no measured duration.
- The model is deterministic — no sensor noise, no actuation jitter, no
  part-to-part spread. It predicts zero cycle-time variation, so any real
  variation will read as divergence.
- PLC scan time is modelled in form but has never been measured.
- The model has **5 cylinders and 4 proximity sensors**; the real cell has **13
  solenoid valves and 10 proximity sensors**. The mapping between them is not
  recorded in any supplied source.

**A divergence means "these two disagree", never "the machine is wrong."**

---

## 6. What is live, simulated, estimated

| Quantity | Status | Source |
|----------|--------|--------|
| Sensor states | **Live** | `DB59.DBX128–129` |
| Valve output coils | **Live** | `DB59.DBX130–131` |
| Conveyor run coils | **Live** | `DB59.DBX131.5–7` |
| Conveyor commanded speed | **Live** | `Pot_Control.ConvN.Set_Velocity` |
| Conveyor actual speed | **Live** | `Pot_Control.ConvN.Current_Velocity_Fb` |
| Pressure | **Live** | `DBD132` |
| Magazine counts | **Live** (camera) | YOLO bridge, withheld when stale |
| Magazine status bits | **Live** (PLC) | `Comp_Status.CompN.*` |
| Cycle progress | **Live** | `System.Total products` |
| Sequence step | **Inferred** | Ordered sensor-edge matching. No step tag exists |
| Workpiece position | **Confirmed at sensors, estimated between** | Presence detectors only |
| Cylinder position | **Not available** | No reed-switch tag exists |
| Predicted belt speed | **Simulated** | Twin reference, `ASM` |
| Predicted pressure | **Simulated** | Twin reference, `ASM` |
| Predicted cycle time | **Simulated, part placeholder** | Twin reference, `PLH` |
| Friction | **Estimated** | `FactoryParams.m`, `EST`, one value for all surfaces |

---

## 7. Running it

```matlab
>> cd Factory_Simulation
>> addpath('E:\PS2 1st sem\WILP SMCC\Final\scada_platform\tools')
>> export_twin_reference
```

```
Running the factory simulation (this takes a moment)...
Cycle time: 31.080 s, complete: 1

Wrote .../scada_platform/data/twin_reference.json
  40 state transitions
  622 samples at 20 Hz (from 6216 at full rate)
```

Then **Digital Twin → Reload** in the HMI, or `POST /api/digital-twin/reload`.

Re-export whenever model parameters change — especially after supplying any of
the measurements in `INPUTS_REQUIRED.md`, since the whole point of the comparison
is to improve as the model is calibrated.

### Without MATLAB

```bash
python tools/make_sample_twin_reference.py
```

A **synthetic** reference for exercising the integration. State names are
transcribed from `factory_states.m` and are accurate; **every timing is
fabricated**. It is marked `meta.synthetic: true`, `meta.source` reads
"SYNTHETIC SAMPLE -- NOT FROM MATLAB", and the first caveat says so in full at
the top of the page. Test fixture only.

---

## 8. Mapping the model to the real cell

The twin is a **reduced model**. Where the two differ, the HMI says so rather
than forcing a correspondence.

| Twin | Real cell | Handling |
|------|-----------|----------|
| 5 cylinders (A1, A6, S2A1, S3A1, S3A2) | 13 solenoid valves | No mapping in any source. Valves shown in a labelled tray |
| 4 proximity sensors PX(1..4) | 10 proximity sensors | PX1–PX4 placed from the Sequencing sheet; PX5–PX10 in an "unplaced" tray |
| 3 conveyors | 3 conveyors | **Direct 1:1 mapping** — the one clean correspondence |
| Height sensors HS_TOP / HS_BOT | `PGM_Up_Limit` / `PGM_Low_Limit` | Direct mapping, supported by Sequencing rows 26 and 30 |
| Camera guard `CAM` | YOLO bridge | External to the PLC; marked as such |
| Reed switches EXT(n) / RET(n) | **none exist** | Guards typed `unobservable`; never confirmable |
| Branch pressure BR_RDY(n) | **none exist** | Guards typed `unobservable` |

Eight of the twin's forty states have guards with no real counterpart. They pass
through the timeline without confirmation, greyed, labelled *"no reed-switch
tag"*. The alternative — assuming a valve number and drawing a green tick — would
make the timeline look complete while being fiction.

### The sequence table is shared, not duplicated

`backend/state/sequence.py` transcribes `factory_states.m` directly: the same 40
states, the same Excel row references, the same guard names, including the
recorded anomaly at row 36 (the sheet says "Conveyor Stop" where the established
pattern implies START; the model implements START and records the discrepancy
rather than silently overwriting the sheet). Both sides therefore agree on what
the sequence *is*, and disagree only about timing — which is the thing worth
comparing.

---

## 9. Improving the comparison

The comparison is only as good as the model's calibration. In the order
`NEXT_STEPS.md` ranks by measured sensitivity:

| Priority | Input | Effect on cycle time |
|----------|-------|----------------------|
| **Blocking** | `SCALE` — one known distance in the real cell | Confirmed incorrect; everything inherits it |
| 1 | Cylinder bore, rod diameter (part number on the body) | 3.26 s |
| 2 | Receiver start pressure (gauge, before a cycle) | −1.98 s |
| 3 | Belt speed setpoint (tachometer, or time a marked block) | −1.23 s |
| 4 | Engraving duration (stopwatch, 5–10 cycles) | 1.6 s |
| 5 | Operator notice / confirm delays | 0.9 s combined |

The lab data sheet already records some of these — workpiece 10 × 10 × 4 cm at
750 kg/m³, receiver 4.3 bar, conveyors 76 cm, proximity range 125 mm. Those
belong in `FactoryParams.m`, then re-export.

Once real cycle-to-cycle timing data exists, the natural next step is replacing
the single nominal trajectory with a distribution, so the HMI can distinguish
"outside normal variation" from "different from one deterministic run". That
requires the model to have variability at all, which it currently does not.
