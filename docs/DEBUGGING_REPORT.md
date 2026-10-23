# DEBUGGING REPORT

Every row of the `Errors` sheet in `Industry 4.0_5.0 Lab data.xlsx`, worked
through against the code.

## How to read the status column

| Status | Meaning |
|--------|---------|
| **Fixed** | Root cause found in software and corrected. Verifiable by test. |
| **Mitigated** | The software contribution is removed; a physical contribution may remain. |
| **Diagnosed** | Root cause identified with evidence, but the fix is not in software. |
| **Instrumented** | Cause not yet confirmed. The signals needed to confirm it are now visible and recorded. |
| **Needs hardware** | Cannot be resolved in software at all. |
| **Needs data** | Cannot be resolved until a measurement or a tag list is supplied. |

**A frontend change never fixes a mechanical fault.** Nine of these twenty are
mechanical or hardware-limited, and they are labelled as such. What changed for
those is that the evidence needed to diagnose them is now captured
automatically, with millisecond timestamps and command attribution, instead of
being lost the moment the screen stopped updating.

---

## Summary

| Status | Count | Issues |
|--------|-------|--------|
| Fixed | 5 | E-03, E-11, E-13, E-16, E-20 |
| Mitigated | 2 | E-05, E-18 |
| Diagnosed | 2 | E-15, E-17 |
| Instrumented | 7 | E-01, E-04, E-07, E-08, E-09, E-10, E-19 |
| Needs hardware | 2 | E-02, E-14 |
| Needs data | 2 | E-06, E-12 |

---

## E-01 — Camera did not sense all blocks reliably

*2026-08-06 · Auto · previously worked around by physically moving the camera*

**Relevant code:** `Final/camera_yolo.py:40,52`

**Findings.** Three separate contributions, all in software:

1. `CONFIDENCE = 0.05`. At that threshold the detector emits a large number of
   low-confidence boxes — the shipped `output_data.json` contains 13 objects
   with confidences of 0.16, 0.11, 0.11… Counting is then dominated by noise in
   both directions: spurious boxes inflate a column, and a genuine block at 0.04
   still vanishes.
2. Column assignment is `cx // COL_W` on a fixed 900 px frame divided into 5
   equal columns. This assumes the magazines are evenly spaced and the camera is
   perfectly square to them. Moving the camera "to match the frame" is exactly
   the symptom of a hard-coded grid that does not match the physical layout.
3. Counts were re-derived from scratch every frame with no temporal filtering,
   so a single bad frame changed the reported inventory.

**Changes.** `tools/camera_bridge.py` raises the default threshold to 0.25 and
makes it a flag. The backend applies a second display threshold and reports
`totalObjects` and `confidentObjects` separately, so threshold effects are
visible rather than hidden. Detection status, frame age and per-class counts are
on the Overview and Digital Twin pages. Camera counts and the PLC's own
`Comp_Status` bits are shown **side by side**; a disagreement raises a visible
mismatch instead of one silently winning.

**Not fixed.** The fixed 5-column grid remains, because the real magazine
geometry is not recorded anywhere. Proper fixes, in order of durability:
per-column ROIs calibrated once and stored in config; or a fiducial marker on
the magazine frame so the grid follows the camera.

**Status: Instrumented.** Threshold and reporting improved; geometry needs a
calibration step with the real cell.

---

## E-02 — Engraving plate stuck at the top

*2026-08-06 · Auto · vendor fixed it*

See **E-14**, the recurrence. Mechanical.

**Status: Needs hardware.**

---

## E-03 — Could not trigger parts of the machine on demand

*2026-08-14 · resolved at the time by building the PLC dashboard*

**Changes.** That capability is retained and improved, now inside the unified
application: Manual Control groups every commandable output by subsystem, shows
the command bit and the output coil separately, and confirms each write against
a subsequent PLC read.

**Not carried over:** the Axis_1 engraving-platform jog from
`app_platform_control (1).py`. It references DB1 tags (`en_mc_power`,
`exe_jogforward`, `exe_jogbackward`, `exe_jogvelocity`,
`pgm_upper_limit_switch`, `pgm_lower_limit_switch`, `mc_power_status`,
`mc_power_error`) that appear nowhere in the supplied `Tag_list (1).xlsx`. Its
`find_tag_index` returns `None` for all of them, so the route returns an error
in the supplied archive too. Inventing DB1 addresses is not acceptable; supply a
tag list containing them and the registry picks them up with no code change.

**Status: Fixed** (platform jog blocked pending tag data).

---

## E-04 — Actuator 11 did not move after the sensor detected the part

*2026-08-14 · Auto · unresolved*

**Findings.** Not reproducible from the supplied code, and **not diagnosable
with the current tag set**. The chain is:

```
sensor detects → PLC logic → solenoid coil → cylinder moves
```

Of those four links the tag list exposes the first (`Digital_Inputs`), the third
(`Digital_Outputs`), and nothing at all for the fourth. There is **no
reed-switch, end-of-stroke or position tag for any cylinder** in
`Tag_list (1).xlsx`. So "the coil energised but the rod did not move" and "the
coil never energised" are indistinguishable from the PLC data alone.

**Changes.** Everything observable is now captured and correlated:

- sensor transition with a millisecond timestamp, in the event stream;
- output coil state with its own transition history and count;
- the manual command bit shown separately from the coil;
- sequence stall detection naming the exact signal and the elapsed wait;
- a chatter detector on the coil.

The Manual Control page states plainly that cylinder motion cannot be confirmed,
rather than implying it can.

**To actually resolve this**, one of:
- add reed switches to the cylinders and publish them in a DB (the durable fix);
- or, with the machine safe, energise valve 11 from Manual Control and watch
  whether the rod moves — that alone separates "no command" from "command, no
  motion", which is the branch point.

**Status: Instrumented.** Requires hardware feedback for a real diagnosis.

---

## E-05 — Blocks come out of the 1st and 2nd slot only

*2026-08-11 · Auto · unresolved*

**Finding — a genuine software bug.** `Final/app.py:204-208`, on every START:

```python
write_bool_data(plc, "DB59.DBX118.0", True)   # Comp_Status.Comp1.Ok
write_bool_data(plc, "DB59.DBX120.0", True)   # Comp2.Ok
write_bool_data(plc, "DB59.DBX122.0", True)   # Comp3.Ok
write_bool_data(plc, "DB59.DBX124.0", True)   # Comp4.Ok
write_bool_data(plc, "DB59.DBX126.0", True)   # Comp5.Ok
```

The HMI unconditionally asserted that all five magazines were available,
overwriting whatever the PLC or the camera believed. If the sequencer chooses a
magazine from these bits, it was choosing from five permanently-true flags with
no relationship to actual contents — so which magazine feeds becomes a property
of the PLC's internal ordering, not of what is loaded.

That is consistent with the symptom, and it interacts with **E-15** (apparently
random block selection).

**Changes.** The unified platform **never** writes these bits during a cycle
start. `/api/cycle/start` writes exactly four addresses: `Productqty_25mm`,
`Productqty_50mm`, `MODE_HIGH_SPEED`, then `CMD_START` — quantities before the
start bit, so the PLC never sees a start with stale quantities. The `Comp_Status`
`.Ok` bits are classed `engineering`: writable only in MAINTENANCE mode with
explicit confirmation, and every write is logged and attributed.

Magazine state now shows the camera count and all three PLC bits together, per
magazine, with mismatches flagged.

**Status: Mitigated.** The software override is gone. Whether the PLC's selection
logic is also at fault needs a run with the magazine bits reflecting reality.

---

## E-06 — Actuator 7 and its sensor should be interchanged

*2026-08-14 · Auto · unresolved*

A physical layout change. Nothing in software can move a sensor.

**What blocks even documenting it:** the Errors sheet says "actuator 7", but no
supplied source maps actuator numbers to valve numbers or to stations. The
Sequencing sheet says "Actuator" with no number. So "actuator 7" cannot be tied
to `Solenoid_valve7` (`DB59.DBX130.6`) from the available data — that is an
assumption, and this platform does not encode assumptions as fact.

**Changes.** The schematic draws all 13 valves in an explicitly labelled tray:
*"station mapping not recorded in any source"*. Populating it is a short job at
the machine — energise one valve in Manual Control, note which cylinder moves,
record it in `layout.ts`.

**Status: Needs data** (the actuator-to-valve map), then hardware.

---

## E-07 — Conveyor 2 speed randomly stops responding to dashboard changes

*2026-08-14 · Auto · worked around by turning the physical knob*

**Findings.** The workaround is itself the diagnostic clue: if turning the
potentiometer works while the dashboard setpoint does not, the commanded value
and the actual drive output are decoupled somewhere between
`Pot_Control.Conv2.Set_Velocity` (`DB59.DBD210`) and the motor.

Two software contributions found:

1. **Neither legacy interface ever showed commanded and actual together.** The
   SCADA Hub showed `Current_Position_Fb` as "Deg" and a hard-coded `RPM: 0`.
   The dashboard showed `Set_Velocity` in a flat table hundreds of rows from
   `Current_Velocity_Fb`. Nobody could see the two numbers at once, so
   "responding" versus "not responding" was being judged by ear.
2. **Writes were never confirmed.** `app_fixed.py` patched its cache with the
   requested value on write, so a `Set_Velocity` the PLC ignored or overwrote
   still displayed as the current setpoint. The dashboard would show 0.40 while
   the PLC held something else entirely.

**Changes.**

- Conveyor panels show four values together: **commanded** (`Set_Velocity`),
  **run coil** (`Digital_Outputs.Conveyor2`), **encoder feedback**
  (`Current_Velocity_Fb`), and the **twin's predicted** speed.
- Setpoint writes are confirmed against an independent read-back; a value the
  PLC does not hold settles as `MISMATCH` with an explanation.
- A `run_without_motion` detector raises a FAULT when the run coil has been
  energised past a grace period with zero encoder feedback, naming the setpoint
  at that moment.
- The schematic stops animating a belt whose feedback is zero and marks it.

Verified against the simulator: `--sim-fault conveyor2_stall` raises
*"Conveyor 2: run output ON, no encoder motion — the run coil has been energised
for 2.0 s and Current_Velocity_Fb still reads 0."*

**Status: Instrumented.** Next run will show whether the setpoint fails to reach
the PLC, reaches it but is overwritten, or reaches the drive and is ignored —
three different faults that were indistinguishable before.

---

## E-08 — Actuator 12 moves partially and retracts without dropping the block

*2026-08-14 · Auto · vendor fixed it*

Mechanical: partial stroke suggests insufficient force, a flow restriction, or
binding. Not a software fault.

**Changes.** Same instrumentation as E-04. Additionally, pressure at the moment
of actuation is now recorded — the Errors sheet notes the lab data sheet's
measured receiver start pressure is **4.3 bar** against a model nominal of 5.5
bar, and a partial stroke is exactly what under-pressure produces. Coil state and
pressure are timestamped on the same event timeline.

**Status: Instrumented** (vendor-repaired; recurrence will now be evidenced).

---

## E-09 — Actuator 7 pushed a misaligned block into the T-slot

*2026-08-14 · Auto · worked around by careful alignment*

A physical alignment problem. There is no alignment sensor in the tag list, so
software cannot detect misalignment before the push.

**Changes.** Nothing that prevents it. The event timeline records the coil
transition and the surrounding sensor states, so a recurrence is timestamped
rather than reconstructed from memory.

**The real fix is hardware**: an alignment guide, or a sensor before the pusher
that the PLC interlocks against.

**Status: Needs hardware.**

---

## E-10 — Actuator 8 did not retract

*2026-08-14 · Auto · recovered by manually triggering from the dashboard*

**Finding.** The recovery is informative: a manual trigger *did* move it, so the
coil and cylinder were functional and the PLC simply did not command the
retract, or commanded it and lost it.

**A software contribution that made this invisible.** `app_fixed.py:275`:

```python
plc.db_write(DB_NUMBER, offset, data)
values_cache[index] = new_value      # ← optimistic
```

The cache was patched with the requested value immediately. If the PLC
overwrote the bit on its next scan, the dashboard still showed the requested
state. An operator could not tell "the command took" from "the command was
overwritten".

**Changes.** The cache is **never** optimistically patched. Every write is
confirmed against an independent subsequent read:

- `PENDING` → `WRITTEN` → `CONFIRMED`, or
- `MISMATCH`: *"wrote True, PLC still reads False after 2.0 s — the PLC program
  is probably driving this address."*

Command history shows requested, observed, outcome and latency per command. The
`command_not_reflected` detector surfaces mismatches as findings.

**Status: Fixed** (the observability defect). The underlying retract failure is
**Instrumented** — the next occurrence will show whether a retract was ever
commanded.

---

## E-11 — Manual website needed constant refreshing

*2026-08-14 · Manual · partly addressed by the stable PLC connection*

**Findings.** Two distinct causes:

1. **Backend:** every request read the PLC directly in the original `app.py`
   (`db_read` at lines 163, 177, 190, 240). With 121 tags and multiple browser
   tabs the PLC was being hammered; a slow or failed read produced a hung or
   empty page. `app_fixed.py` fixed this properly with the background poller.
2. **Frontend, unaddressed:** the page had no reconnection logic at all. A
   failed poll left the last rendered values on screen with no indication they
   were stale, and no recovery path except F5. The SCADA Hub's `fetchLiveData`
   swallowed errors silently.

**Changes.**

- SSE with `EventSource`, which reconnects automatically.
- Explicit link state — `connecting` / `open` / `reconnecting` / `closed` — shown
  in the top bar.
- A degraded 2 s REST fallback while the stream is down, so numbers keep
  arriving.
- Stale values are **retained and marked**, never blanked: the schematic
  desaturates, a "Stale — last known values" overlay appears, and write controls
  disable.
- PLC reconnection uses exponential backoff (1 s → 10 s) so a powered-off
  controller does not generate a connect storm.

**Status: Fixed.** No manual refresh is needed to recover monitoring.

---

## E-12 — Friction coefficient differs between conveyor 2 and the engraving plate

*2026-08-14 · Both · unresolved*

A digital-twin calibration input, not a control defect. `FactoryParams.m` carries
a single `mu_k = 0.35` / `mu_s = 0.4` pair tagged `[EST]` — engineering estimate,
one value for all surfaces.

**Changes.** The twin view labels every figure with the model's own provenance
code, so a friction-derived prediction is visibly `EST` and not mistaken for a
measurement. `INPUTS_REQUIRED.md` already specifies the measurement: a
constant-velocity pull test for `mu_k`, a tilt test for `mu_s` — **per surface
pair**, which is the part the current model does not represent.

Representing per-surface friction is a change to the physics model. Out of scope
here by design: the model is validated and this platform does not modify it.

**Status: Needs data** (two measurements), then a model change.

---

## E-13 — No communication between the manual and automatic websites

*2026-08-17 · Both · unresolved*

**The central architectural problem, and the reason for this project.**

**Findings.** Two Flask apps, each with its own Snap7 client, each with its own
idea of machine state, neither aware of the other. Nothing prevented the manual
dashboard from toggling `manual_commands.Solenoid_Valve7` while the SCADA Hub
had `CMD_START` high and the sequencer was mid-cycle. Add the reloader fork and
the JSON writer and there were four clients on one PLC.

**Changes.**

- **One application.** Automatic and manual operation are modes of a single
  program, not separate websites.
- **One PLC connection.** `PlcService` is the only Snap7 owner;
  `use_reloader=False` prevents a fork from creating a second.
- **One machine state.** Composed once per poll and pushed to every client, so
  two browsers cannot disagree.
- **Explicit ownership.** `CommandGate` refuses a manual write to a valve while
  `CMD_START` is high and the cycle is incomplete — even in MANUAL mode. Mode
  changes into MANUAL/MAINTENANCE are refused outright during a running cycle.

Verified: with a cycle running, `POST /api/tags/manual_commands.solenoid_valve8/write`
returns `409 auto_owns`.

**Status: Fixed.**

---

## E-14 — Engraving plate stuck at the top again

*2026-08-19 · Auto · unresolved (recurrence of E-02)*

Recurrence after a vendor repair points at a mechanical or pneumatic cause:
binding on the vertical axis, insufficient retract force, or a stuck valve.

**A relevant measurement:** the lab data sheet records receiver start pressure at
**4.3 bar** against the model's 5.5 bar nominal. Low supply pressure is a
credible contributor to a plate that rises but will not reliably come down.

**Changes.**

- `PGM_Up_Limit` and `PGM_Low_Limit` are both on the schematic at the engraving
  station, and the station reads PLATE UP / PLATE DOWN / **PLATE IN TRANSIT** —
  the third state, where neither limit is made, is the stuck condition and it is
  now explicit rather than being drawn as "not up".
- "Engraving plate at home position" is a required item on the restart
  checklist, with a note pointing at this issue.
- The sequence stalls visibly at step 28 (`S28_HEIGHT_BOTTOM`) naming
  `sensor.pgm_low_limit` and the elapsed wait, instead of the UI freezing.
- Pressure at the moment of the stall is on the same event timeline.
- Reproducible in the simulator: `--sim-fault plate_stuck_top`.

**Status: Needs hardware.** Diagnosis is now automatic and evidenced.

---

## E-15 — The machine randomly decides which block is engraved

*2026-08-19 · Auto · unresolved*

**Findings.** The selection logic lives in the PLC program, which was not
supplied — only the tag list. So the algorithm cannot be read directly. But the
HMI made it *look* random for a reason that is visible in the code:

`Final/app.py` forced all five `Comp_Status.CompN.Ok` bits TRUE on every START
(**E-05**). If the sequencer picks a magazine from those bits, it was picking
from five permanently-true flags carrying no information about actual contents.
The observable result is selection that appears to ignore what is loaded — which
is precisely the complaint.

**Changes.** The override is gone (E-05). Magazine state is displayed as the
camera sees it and as the PLC reports it, side by side, so the inputs to the
selection are visible for the first time. Every `Comp_Status` write is now
attributed and logged.

**Status: Diagnosed** — a strong, code-backed hypothesis for the apparent
randomness, with the software contribution removed. Confirming it needs one run
with the magazine bits reflecting reality, or a look at the PLC program.

---

## E-16 — Machine starts with both quantities at zero and never stops

*2026-08-19 · Auto · unresolved. Sheet proposes: start only when 25 mm + 50 mm > 0*

**Findings.** No validation existed anywhere:

- `ui.js:190` `machineStart()` reads the inputs and POSTs whatever it finds.
- `app.py:157` `/api/start` does `int(data.get('productqty_25mm', 0))` and writes
  it, then raises `CMD_START` unconditionally.

Nothing checked the total on either side.

**Changes.** Enforced in **both** places, as specified:

- **Frontend:** Start is disabled when `qty25 + qty50 <= 0`, with the reason
  spelled out — *"Select at least one product before starting the cycle."* — not
  left as a mystery grey button.
- **Backend:** `POST /api/cycle/start` returns `422 invalid_order` for any total
  ≤ 0, plus negatives and values beyond the S7 `Int` range. `System.CMD_START`
  is classed `protected`, so it cannot be raised through the generic tag-write
  endpoint either.

Backend validation is the control; the UI is courtesy. A stale tab or a curl
one-liner still cannot start a zero-quantity cycle.

Covered by four self-test checks (§2 of `tools/selftest.py`).

**Status: Fixed.**

---

## E-17 — Engraving coordinates are not manual and appear machine-decided

*2026-08-19 · Auto · unresolved*

**Findings.** Searched the full tag list for engraving position tags. What exists:

| Tag | Address | What it is |
|-----|---------|-----------|
| `System.Engraving_Completed` | `DB59.DBX112.3` | Operator acknowledgement |
| `IO Status...PGM_Up_Limit` | `DB59.DBX129.3` | Plate upper limit switch |
| `IO Status...PGM_Low_Limit` | `DB59.DBX129.2` | Plate lower limit switch |

**There is no engraving coordinate tag of any kind.** No X, no Y, no pattern
select, no job number. The three `Pot_Control` blocks are conveyor axes
(`Conv1`/`Conv2`/`Conv3`), not the engraver.

So the coordinates are either set inside the PLC program, or on the laser
engraver's own controller — neither of which is exposed through DB59. **Adding a
coordinate field to this HMI would require inventing an address**, which this
platform does not do.

**Changes.** All engraving state that *does* exist is surfaced: both limit
switches, the plate position state including IN TRANSIT, the operator
acknowledgement with its address, and the manual step marked in the sequence
timeline as unmeasured placeholder time.

**To make coordinates controllable**, the PLC program needs coordinate tags added
to a DB and published in the tag list. Once they appear there, they flow into the
registry automatically — annotate them in `config/tag_overlay.json` and they gain
a role, an access class and a UI control with no code change.

**Status: Diagnosed.** Needs a PLC-program change, not an HMI change.

---

## E-18 — `solenoid_valve_8` randomly turns on and off on the SCADA Hub

*2026-08-19 · Auto · unresolved*

**Root cause found. It is an address-mapping error, not a valve fault.**

`Final/data_on.json` — the map used in the default power mode — points the
sensor and valve labels at **DB59 bytes 266–269**:

```
266.0-266.7  proximity_sensor1..8
267.0-267.1  proximity_sensor9..10
267.2-267.4  pgm_low_limit, pgm_up_limit, emergency
267.5-267.7  solenoid_valve1..3      ← packed with no gap
268.0-268.7  solenoid_valve4..11
269.0-269.1  solenoid_valve12..13
269.2-269.4  conveyor1..3
```

`Tag_list (1).xlsx` documents these same signals at **128–131**, and **the tag
list ends at `DB59.DBX265.7`**. Nothing at 266 or beyond is documented at all.

Two independent problems:

1. **The region is undocumented.** 266–269 has the same shape as 128–131 shifted
   by +138 bytes, which looks like an IO mirror, but no supplied source confirms
   that.
2. **The packing is wrong even under that assumption.** The documented region has
   a struct boundary between `Digital_Inputs` (ends 129.4) and `Digital_Outputs`
   (starts 130.0). S7 aligns a struct to an even byte, leaving a 3-bit gap. The
   legacy map packs contiguously — `solenoid_valve1` at 267.5 immediately after
   `emergency` at 267.4 — so **every valve label is 3 bits off**.

Working it through: SCADA `solenoid_valve8` = `DBX268.4`. Under the +138 mirror,
`268.4 - 138 = 130.4` = **`Solenoid_valve5`**.

**The dashboard has been showing valve 5's activity under a label reading 8.**
Valve 5 cycling normally during a run is indistinguishable, on that screen, from
valve 8 misbehaving.

**Changes.**

- The HMI reads sensors and valves **only** from the documented 128–131 region.
- 266–269 is registered as `raw.*` tags: read-only, flagged `UNDOCUMENTED`,
  visible in the Tag Explorer (filter provenance = Undocumented) so the region
  can be checked against real hardware — and never used to drive an indicator.
- A chatter detector flags any tag toggling faster than a command rate could
  explain, **with attribution**: `operator` (we commanded it), `plc` (nothing of
  ours was pending), or `contested` (we asked for X, it went elsewhere).
- SV8 and its manual bit are pre-pinned to the watch list.

Verified: `--sim-fault valve8_chatter` produces *"SV 8 is toggling rapidly — 52
transitions in 30 s. Attribution: plc. No command from this application was in
flight, so the PLC program or the field wiring is driving it."*

**To confirm on hardware:** open Tag Explorer, compare
`io_status.digital_outputs.solenoid_valve8` (`DBX130.7`) against `raw.db59.x268_4`
while the cycle runs. If the raw bit tracks `Solenoid_valve5` (`DBX130.4`), the
+138 mirror is confirmed and the legacy map is the whole story.

**Status: Mitigated.** The HMI can no longer produce this artefact. The
hypothesis is testable in one run.

---

## E-19 — Block moves to the second actuator on conveyor 2 but is not pushed

*2026-08-19 · Auto · unresolved*

**Findings.** Same evidence gap as E-04: the tag list exposes the sensor and the
coil, but nothing about cylinder motion. Additionally, the actuator referred to
cannot be identified — no source maps "second actuator on conveyor 2" to a valve
number (see E-06).

Two candidate causes, now distinguishable:

1. The block stops short of the sensor, so the PLC never sees the arrival
   condition → the sensor never rises, and the sequence stalls at that guard.
2. The sensor rises but the PLC does not command the push → sensor rises, coil
   stays low.

**Changes.** The distinction is now directly readable:

- Sequence stall names the exact signal, the elapsed wait, the configured budget,
  and **the signal's current actual state**.
- The sensor event stream timestamps every edge to the millisecond.
- Coil state sits beside the sensor on the same timeline.

Case 1 shows a stall with the sensor reading OFF. Case 2 shows the sensor
confirmed, then a stall at the next guard with the coil low. Different pictures.

**Status: Instrumented.** Needs one occurrence with the platform running.

---

## E-20 — Cycle terminated by emergency: SCADA stops updating and cannot restart

*2026-08-19 · Auto · unresolved*

**Findings.** Three distinct defects.

1. **No state model.** The SCADA had no concept of machine lifecycle. It rendered
   tag values. With no state, there was nothing to display when the machine
   stopped — hence "just stops working".
2. **The E-Stop button did nothing.** `ui.js:263` POSTs to `/api/command`, a
   route that **does not exist** in `app.py`. The 404 lands in a `catch` that
   returns `{success: true, offline: true}` and logs *"Command sent (offline
   mode)"*. The button reported success while doing nothing.
3. **No recovery path.** Nothing read the start interlocks
   (`Air_Pressure_ok`, `ENGV_Plate_Home`, `All_Cylinders_Home`,
   `Emergency Healthy`, `Startup_Healthy` — all documented, all at `DB59.DBX0.x`
   and `DBX2.0`), so there was no way to know what was blocking a restart.

**Changes.**

- **Explicit lifecycle**, derived from PLC tags every poll:
  `DISCONNECTED · EMERGENCY_STOPPED · FAULT · RECOVERY_REQUIRED · RESETTING ·
  IDLE · READY · STARTING · AUTO_RUNNING · COMPLETED · MANUAL_MODE · MAINTENANCE`.
- **The UI never freezes.** On link loss the last known values are retained and
  marked stale; the emergency ribbon is unmistakable; commands are blocked with
  a stated reason.
- **Frozen context.** On entering EMERGENCY or FAULT the backend captures the
  sequence step, every sensor, every valve and every safety bit *as they were at
  that instant*, and displays it. The state that caused the stop survives the
  stop.
- **A restart checklist, not a dead button.** All six documented interlocks with
  live values and per-item detail:

  ```
  ✓ PLC connected
  ✓ Emergency circuit healthy
  ✓ Air pressure healthy
  ✓ All cylinders at home position
  ✗ Engraving plate at home position   ← named, with E-14 context
  ✓ Startup diagnostics healthy
  ```

- **A defined recovery flow:** clear the physical cause → interlocks return →
  `RECOVERY_REQUIRED` → checklist passes → Reset (`Cycle_Reset`, `DB59.DBX116.1`)
  → `READY`. An engineering override exists, requires explicit confirmation, and
  records the bypassed blockers in the event log.
- **Honest labelling.** The red control reads **SOFTWARE STOP** and clears
  `CMD_START`. It is not presented as a functional-safety stop, because it is
  not one.

**Status: Fixed.**

---

## Cross-cutting software defects found during the audit

Not in the Errors sheet, but real, and fixed:

| Defect | Evidence | Fix |
|--------|----------|-----|
| Four competing Snap7 clients | `app.py:22` + `debug=True`; `json_write_for_web_tag.py:20`; `app_fixed.py:34` | One `PlcService`; `use_reloader=False` |
| Non-atomic JSON writes → all tags blank for one frame | `json_write_for_web_tag.py:41`; `camera_yolo.py:81` | `os.replace` in `camera_bridge.py`; file IPC removed from the PLC path |
| Unthrottled poll loop with `except: continue` | `json_write_for_web_tag.py:24-45` | Fixed interval, typed exception handling, backoff |
| Any of 121 tags writable at any time | `app_fixed.py:1036` | Four access classes, enforced by `CommandGate` |
| Uninitialised PLC `Real` → `NaN` → invalid JSON breaks the stream | `codec.decode` | NaN/Inf normalised to `null`; `json.dumps(allow_nan=False)`; covered by a self-test |
| pandas required for a 121-row sheet | `app_fixed.py:4` | Stdlib `.xlsx` reader; verified identical parse |

---

## What still needs the machine

| # | Need | Why |
|---|------|-----|
| 1 | **Cylinder reed switches** | Without end-of-stroke feedback, E-04, E-08, E-10 and E-19 cannot be fully diagnosed. This is the single highest-value hardware addition. |
| 2 | **Actuator-to-valve map** | Blocks E-06, E-19 and the schematic placement. ~30 minutes with Manual Control. |
| 3 | **Confirm the 266–269 region** | Settles E-18 conclusively. One cycle with Tag Explorer open. |
| 4 | **A tag list including the DB1 Axis_1 tags** | Unblocks the engraving-platform jog (E-03). |
| 5 | **Engraving coordinate tags in the PLC program** | Required for E-17. |
| 6 | **Per-surface friction measurements** | E-12, and twin calibration. |
| 7 | **Camera ROI calibration** | E-01 geometry. |
