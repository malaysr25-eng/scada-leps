# TAG MAP

How the 121 documented tags of `DB59` are organised, and what the platform is
allowed to do with each.

**Authority.** `Tag_list (1).xlsx` is the only source of addresses. This document
and `config/tag_overlay.json` add grouping and access policy on top; neither ever
declares an address the workbook does not contain.

---

## 1. Access classes

Every tag carries exactly one. Enforced in `backend/services/safety.py`, shown on
every row of the Tag Explorer.

| Class | Writable in | Meaning |
|-------|-------------|---------|
| `read_only` | never | Reports state. The PLC drives it; writing achieves nothing and would be overwritten on the next scan. |
| `safe_manual` | MANUAL, MAINTENANCE | The sanctioned manual write path. Interlocked, and refused while the automatic sequencer owns the machine. |
| `engineering` | MAINTENANCE | Changes a setpoint the PLC program also writes. Requires explicit confirmation; every write is logged and attributed. |
| `protected` | never via the tag API | Safety or process critical. Reachable only through a dedicated endpoint that applies the relevant rule. |

### Why the output mirrors are read-only

`IO Status.Digital_Outputs.Solenoid_valveN` (`DBX130.0`–`131.7`) is the PLC's
**output image** — what the coil is doing. It is not a command register. The
supplied tag list provides a separate `manual_commands` struct (`DBX264.0`–
`265.7`) explicitly described as *"Manual activation toggle for Solenoid Valve
N"*, and that is the intended write path.

The old dashboard offered an identical Toggle button beside both, with nothing to
distinguish them. Toggling the output image appears to work for one poll and then
reverts, which teaches an operator that the HMI is unreliable. Hence: mirrors are
`read_only`, `manual_commands` is `safe_manual`.

---

## 2. Groups

| Group | Addresses | Count | Default access |
|-------|-----------|-------|----------------|
| Safety & Interlocks | `DBX0.0`–`0.3`, `DBX2.0`, `DBX129.4` | 6 | `read_only` |
| Cycle Control | `DBW108`, `DBW110`, `DBX112.x`, `DBW114`, `DBX116.x` | 8 | mixed |
| Magazines | `DBX118.x`–`DBX126.x` | 15 | mixed |
| Sensors | `DBX128.0`–`DBX129.3` | 12 | `read_only` |
| Actuator Outputs | `DBX130.0`–`DBX131.4` | 13 | `read_only` |
| Conveyor Outputs | `DBX131.5`–`DBX131.7` | 3 | `read_only` |
| Pneumatics / Pressure | `DBD132`–`DBX148.1` | 6 | `read_only` |
| Conveyor Motion | `DBX150.0`–`DBX262.0` | 42 | mixed |
| Manual Commands | `DBX264.0`–`DBX265.7` | 16 | `safe_manual` |
| Diagnostics / Raw | `DBX266.0`–`DBW278` | 37 | `read_only` (undocumented) |

**158 tags total: 121 documented + 37 raw.** One `db_read` of 280 bytes per poll
covers all of them.

---

## 3. Safety & Interlocks — read only

| Tag | Address | Role | Used for |
|-----|---------|------|----------|
| `Start_interlocks.Air_Pressure_ok` | `DBX0.0` | `safety.air_pressure_ok` | Restart checklist; sequence step 3 guard (level) |
| `Start_interlocks.ENGV_Plate_Home` | `DBX0.1` | `safety.engraving_plate_home` | Restart checklist (E-14) |
| `Start_interlocks.All_Cylinders_Home` | `DBX0.2` | `safety.all_cylinders_home` | Restart checklist |
| `Start_interlocks.Emergency Healthy` | `DBX0.3` | `safety.emergency_healthy` | **Drives `EMERGENCY_STOPPED`** |
| `System.Startup_Healthy` | `DBX2.0` | `safety.startup_healthy` | Restart checklist |
| `IO Status.Digital_Inputs.Emergency` | `DBX129.4` | `safety.emergency_input` | Local E-Stop feedback |

`Emergency Healthy` reports a **certified hardware safety circuit**. Nothing in
this application can drive it, and no button here substitutes for it. The top bar
shows it as status only.

---

## 4. Cycle Control

| Tag | Address | Type | Access | Note |
|-----|---------|------|--------|------|
| `System.Productqty_25mm` | `DBW108` | Int | `protected` | Written by `/api/cycle/start` only |
| `System.Productqty_50mm` | `DBW110` | Int | `protected` | Written by `/api/cycle/start` only |
| `System.MODE_HIGH_SPEED` | `DBX112.0` | Bool | `protected` | Written with the order |
| `System.CMD_START` | `DBX112.2` | Bool | `protected` | **Guarded by the quantity rule** |
| `System.Engraving_Completed` | `DBX112.3` | Bool | `safe_manual` | Operator acknowledgement, sequence row 29 |
| `System.Total products` | `DBW114` | Int | `read_only` | Progress source |
| `System.Cycle_Completed` | `DBX116.0` | Bool | `read_only` | Terminal sequence guard |
| `System.Cycle_Reset` | `DBX116.1` | Bool | `protected` | Recovery, behind the restart checklist |

**`DBX112.1` is not in the tag list.** The legacy `data_on.json` labelled it
`high_speed_active`; the workbook goes straight from `112.0` to `112.2`. It is
not registered.

### Start ordering

`/api/cycle/start` writes in this order, deliberately:

```
1. DBW108   Productqty_25mm
2. DBW110   Productqty_50mm
3. DBX112.0 MODE_HIGH_SPEED
4. DBX112.2 CMD_START      ← last
```

The start bit goes last so the PLC never observes a start with stale quantities.
Asserted by a self-test.

---

## 5. Magazines

`Comp_Status.CompN.{Ok,Low,Empty}` at `DBX118.x`, `120.x`, `122.x`, `124.x`,
`126.x`.

`.Ok` is `engineering`; `.Low` and `.Empty` are `read_only`.

**Why `.Ok` is not simply read-only:** the legacy `Final/app.py` wrote all five
`.Ok` bits TRUE on every START (`app.py:204-208`), overwriting the real magazine
state and defeating the empty-magazine interlock. That is a plausible cause of
both E-05 and E-15. The unified platform never writes them during a cycle start.
They remain writable under MAINTENANCE, with confirmation and logging, because
an engineer may legitimately need to force one during commissioning — but it is
now a deliberate, recorded act rather than a side effect of pressing Start.

---

## 6. Sensors — read only

| Tags | Addresses | Roles |
|------|-----------|-------|
| `Proximity_sensor1`–`8` | `DBX128.0`–`128.7` | `sensor.proximity.1`–`8` |
| `Proximity_sensor9`–`10` | `DBX129.0`–`129.1` | `sensor.proximity.9`–`10` |
| `PGM_Low_Limit` | `DBX129.2` | `sensor.pgm_low_limit` |
| `PGM_Up_Limit` | `DBX129.3` | `sensor.pgm_up_limit` |

Only PX1–PX4 and the two plate limits have a defensible physical placement, from
the Sequencing sheet:

| Sensor | Sequencing row | Placement |
|--------|----------------|-----------|
| PX1 | 9 | Conveyor 1 entry, after the feeder push |
| PX2 | 11 | Conveyor 1 exit, gates the belt-1 stop |
| PX3 | 18 | Conveyor 2, gates the belt-2 stop |
| PX4 | 37 | Conveyor 3, final position check |
| `PGM_Up_Limit` | 26 | Engraving station, vertical verification |
| `PGM_Low_Limit` | 30 | Engraving station, bottom verification |

**PX5–PX10 have no documented station.** The Sequencing sheet describes only four
position checks. They are drawn in an "unplaced sensors" tray rather than guessed
onto the belt.

---

## 7. Actuator & Conveyor Outputs — read only

`Digital_Outputs.Solenoid_valve1`–`13` at `DBX130.0`–`DBX131.4`;
`Conveyor1`–`3` at `DBX131.5`–`131.7`.

**No cylinder position feedback exists in the tag list.** No reed switch, no
end-of-stroke, no rod position, for any of the five cylinders. Consequences:

- The sequence's extend/retract guards are typed `unobservable` and can never
  produce a confirmation.
- Manual Control states that cylinder motion cannot be confirmed.
- E-04, E-08, E-10 and E-19 cannot be fully diagnosed from PLC data alone.

**No source maps actuator numbers to valve numbers.** The Errors sheet names
"actuator 7", "actuator 8", "actuator 11", "actuator 12"; the Sequencing sheet
says "Actuator" without a number. Assuming actuator N = `Solenoid_valveN` is not
supported by the supplied documents, so the schematic shows all 13 valves in a
tray labelled *"station mapping not recorded in any source"*.

**To populate it:** in MANUAL mode, energise one valve, note which cylinder
moves, record it in `frontend/src/components/digitalTwin/layout.ts`. About thirty
minutes for all thirteen.

---

## 8. Pneumatics / Pressure — read only

| Tag | Address | Type | Role |
|-----|---------|------|------|
| `Analog_inputs.Pressure.Value` | `DBD132` | Real | `pressure.value` |
| `Analog_inputs.Pressure.Normx` | `DBD136` | Real | `pressure.normx` |
| `Analog_inputs.Pressure.Low Value` | `DBD140` | Real | `pressure.low_limit` |
| `Analog_inputs.Pressure.High Value` | `DBD144` | Real | `pressure.high_limit` |
| `Analog_inputs.Pressure.Low Alarm` | `DBX148.0` | Bool | `pressure.low_alarm` |
| `Analog_inputs.Pressure.High Alarm` | `DBX148.1` | Bool | `pressure.high_alarm` |

An uninitialised PLC `Real` decodes as `NaN`, which `json.dumps` emits as bare
`NaN` — invalid JSON that silently kills `JSON.parse` in the browser and stalls
the whole stream. `codec.decode` normalises `NaN`/`Inf` to `null`, and the
serialiser runs with `allow_nan=False` so a regression fails loudly rather than
producing a mysteriously frozen UI. Covered by a self-test.

---

## 9. Conveyor Motion (`Pot_Control`)

Three identical blocks: `Conv1` from `DBX150.0`, `Conv2` from `DBX188.0`,
`Conv3` from `DBX226.0`.

| Member | Conv1 address | Access | Role suffix |
|--------|---------------|--------|-------------|
| `Set_HighSpeed` | `DBX150.0` | `engineering` | `.set_highspeed` |
| `HighSpeed_Position` | `DBD152` | `engineering` | `.highspeed_position` |
| `HighSpeed_Velocity` | `DBD156` | `engineering` | `.highspeed_velocity` |
| `LowSpeed_Position` | `DBD160` | `engineering` | `.lowspeed_position` |
| `LowSpeed_Velocity` | `DBD164` | `engineering` | `.lowspeed_velocity` |
| `Set_Position` | `DBD168` | `engineering` | `.set_position` |
| `Set_Velocity` | `DBD172` | `engineering` | `.set_velocity` |
| `Goto_Position` | `DBX176.0` | `engineering` | `.goto` (high risk) |
| `Set_Home` | `DBX176.1` | `engineering` | `.set_home` (high risk) |
| `Error_Fb` | `DBX176.2` | `read_only` | `.error_fb` |
| `Axis_Homed_Fb` | `DBX176.3` | `read_only` | `.homed_fb` |
| `Current_Position_Fb` | `DBD178` | `read_only` | `.position_fb` |
| `Current_Velocity_Fb` | `DBD182` | `read_only` | `.velocity_fb` |
| `Reset` | `DBX186.0` | `engineering` | `.reset` |

Conv2 offsets: `+38` bytes. Conv3: `+76`.

**The pair that matters for E-07:** `Set_Velocity` is the commanded value;
`Current_Velocity_Fb` is the encoder truth. Neither legacy interface showed them
together. The conveyor panel now shows commanded, run coil, feedback and twin
prediction side by side, and a detector raises a FAULT when the run coil is
energised past a grace period with zero feedback.

`Goto_Position` and `Set_Home` initiate axis motion, so they are classed high
risk and require confirmation. They are also interlocked against an active limit
switch — mirroring the guard already present in `app_platform_control (1).py`.

---

## 10. Manual Commands — the sanctioned write path

`manual_commands.Solenoid_Valve1`–`13` at `DBX264.0`–`DBX265.4`;
`Conveyor1`–`3` at `DBX265.5`–`265.7`.

All `safe_manual`. Writable in MANUAL or MAINTENANCE, and **refused while the
automatic sequencer owns the machine** (`CMD_START` high and cycle incomplete),
even in MANUAL mode. Two writers on one coil is the failure being removed
(E-13).

Every write goes through the full chain: mode → emergency → access class →
ownership → interlocks → type/range → confirmation → PLC → **independent
read-back**.

---

## 11. Diagnostics / Raw — undocumented, read only

**`Tag_list (1).xlsx` ends at `DB59.DBX265.7`.** Nothing at 266 or beyond is
documented anywhere in the supplied material.

The legacy `json_write_for_web_tag.py` read 281 bytes and `data_on.json` mapped
266–269 to sensor and valve names. That mapping is the root cause of E-18 — see
`DEBUGGING_REPORT.md` for the full derivation. In short: the region is
undocumented, *and* the legacy packing ignores S7 struct alignment, so its valve
labels are 3 bits off. Its `solenoid_valve8` (`DBX268.4`) corresponds to
`Solenoid_valve5` under a +138 mirror reading.

The platform registers this region as:

| Tags | Addresses | Provenance |
|------|-----------|------------|
| `raw.db59.x266_0` … `raw.db59.x269_7` | `DBX266.0`–`DBX269.7` | `undocumented` |
| `raw.db59.w270` … `raw.db59.w278` | `DBW270`–`DBW278` | `undocumented` |

All `read_only`, all flagged `UNDOC` in the Tag Explorer, none used to drive any
indicator. They exist so the region can be verified against real hardware.

**To settle it:** filter provenance = *Undocumented*, run a cycle, and compare
`raw.db59.x268_4` against `io_status.digital_outputs.solenoid_valve5`
(`DBX130.4`). If they track, the +138 mirror is confirmed.

---

## 12. Extending the registry

Adding a tag requires **no code change**:

1. Add the row to `Tag_list (1).xlsx` with its DB address and data type.
2. Annotate it in `tools/build_tag_overlay.py` — group, access class, role.
3. `python tools/build_tag_overlay.py`
4. Restart the backend.

The registry sizes its `db_read` from the tag extents automatically, so a tag at
a higher offset simply extends the read.

This is the route for the tags currently blocking work:

| Missing | Blocks | Where it must come from |
|---------|--------|-------------------------|
| Cylinder reed switches | E-04, E-08, E-10, E-19 | Hardware + PLC program |
| DB1 Axis_1 platform tags | E-03 platform jog | An extended tag list |
| Engraving coordinates | E-17 | PLC program |
| Branch pressure feedback | 4 unobservable sequence guards | PLC program |
