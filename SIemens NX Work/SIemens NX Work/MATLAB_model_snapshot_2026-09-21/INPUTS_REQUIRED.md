# INPUTS_REQUIRED — the complete intake checklist

> **Where the files named here live.** This file, and everything that runs,
> sits in `Factory_Simulation/` — including `Physics_Framework.xlsx`, the
> fill-in workbook. Documents cited as `HANDOFF.md`, `NEXT_STEPS.md`,
> `ITERATION_LOG.md`, `START_HERE.md` and `PHYSICS_FRAMEWORK.md` belong to the
> maintainer's working record, which is **not published**. If one of those is
> not on your disk, you are not missing a file.

## 0. What I need from you, in priority order

Answer by number. Anything you cannot get, say so and I will keep it tagged as
an assumption rather than quietly inventing a value.

> **Most of what is left is now packaged.** The machine's own history database
> can answer the timing questions without anyone standing at the cell with a
> stopwatch. The maintainer's record carries a ready-to-copy folder for the
> PC running the SCADA dashboard - a brief and a read-only extraction script -
> and the reply is a single JSON file. The items below that it does **not**
> cover are the ones needing eyes or hands at the machine: the panel test
> (3b), the barrel labels (14), the sensor trip distances (4b) and the
> regulator faces.

### Received 2026-08-25 — nine measurements, and one overturned assumption

| # | What | Value | Consequence |
|---|---|---|---|
| **1** | Conveyor 1/2/3 length | **760 mm** each | **`SCALE = 0.760/7.6 = 0.1000` — the model was RIGHT all along.** Six sessions of "SCALE is confirmed wrong" were wrong about *what* was wrong |
| **2** | Workpiece | **100 × 100 × 40 mm, 750 kg/m³** | **SETTLED 2026-08-26.** L and W from `Box_50MM.STEP`; H measured in the lab. **0.300 kg** against the model's 0.583 kg — 1.94× too heavy. Applied. Density confirmed by weighing, item 15 |
| **10** | Receiver at cycle start | **4.3 bar** | Matches the PLC's own 4.315 reading. Model assumes 5.5 |
| **–** | Proximity sensor | **125 mm rated max** | A component *rating*, not the trip distance for a 10×10×4 mm wooden target — see below |

**The scale was never the problem.** The reasoning that produced `SCALE = 0.10`
— that a 0.6-unit block at 1:1 would be a 583 kg workpiece, which is absurd —
was sound and reached the correct answer. What the drawing gets wrong is the
**block**: it draws a 0.6-unit part that would be 60 mm, where the real one is
**100 × 100 × 50 mm**, and the drawing simply does not draw the block to scale.
A 780 mm conveyor carrying a 100 mm block is entirely sensible; one carrying a
60 mm cube of aluminium at 0.583 kg is what the model had been simulating.

**A correction worth keeping.** This section first recorded the block as
10 × 10 × 4 mm, 0.300 g, and a complete re-baseline was built on it — it
validated green at 143/143 and 55/55 before magazine geometry overturned it.
The rule that came out of it: **a measurement that forces a solver change is
suspicious.** At 0.300 g the model diverges at every `dt` from 5e-4 down to
2e-5, and none of that was a defect in the physics. What the 10 × 10 × 4 mm
actually measured is still unestablished.

All of this is now **applied** (2026-08-26). `P.blk_a` became
`blk_L`/`blk_W`/`blk_H`, because a single edge cannot describe a cuboid, and
both pinned reference files were re-baselined. The knock-on was small: cycle
time moved 0.1% on a 1.55× mass change, and the solver step and contact
stiffnesses did not need to change at all. See `NEXT_STEPS.md` §0B.

**On the 125 mm.** That is what the sensor *can* do. What the model needs is
the distance at which a real **100 × 100 × 50 mm wooden block** actually trips
it, which is a different and still unknown number. The type is now confirmed
**capacitive** (2026-08-26), which is consistent with a wooden target — but 125
mm does not sit comfortably with the M18 barrel in the CAD, which for a
capacitive sensor would typically range a few mm to about 20. Worth resolving
at the machine.

### Answered 2026-08-27, extended 2026-08-30, by the PLC program listing (`plc/abc.pdf`)

The 113-page TIA Portal "Program blocks" export was decoded — it has no usable
text layer, so see `Project_Notes/tools/read_pdf_text.py`. The first pass read
the I/O tables. The second pass traced the sequence networks, and that is what
closed the mapping.

**The complete physical I/O map — 13 inputs, 22 outputs:**

| Address | Signal |
|---|---|
| `%I0.0`–`%I1.5` | `Proximity_Sensor_1`…`_10`, plus `_11`/`_12` and `Emergency` |
| `%Q3.1, 3.0, 2.7, 2.6, 2.2, 0.2, 3.6, 2.0, 2.5, 2.4, 2.3, 0.1, 2.1` | `solenoid_valve_1`…`_13` |
| `%Q3.2, 3.3, 3.4` | `conveyor_1/2/3` |
| `%Q3.5` | `engraving_power` |
| `%Q0.0, 0.3, 0.5, 1.0, 1.1` | `pot_1_pulse+`, `pot_1_dir+`, `pot_2_dir+`, `pul+`, `dir+` |

**Sensors 11 and 12 are not extra sensors.** `%I1.2` is
`pgm_lower_limit_switch` and `%I1.0` is `pgm_upper_limit_switch` — the engraving
platform's limit switches, already mapped `CONFIRMED` in `factory_io_map.m`. So
12 wired inputs = 10 proximity sensors + 2 platform limits, reconciling exactly
with the register's 10. There was no discrepancy.

#### The solenoid to actuator map. All 13.

`FC3 solenoid_manual` is the **only** network that writes an output coil, so
what it writes is not an inference. `FC8 Fc_IO` mirrors the same addresses to
the HMI and agrees exactly, which is what makes the decode trustworthy here —
a single reading would not have been.

| # | Address | Written by | What fires it |
|---|---|---|---|
| 1 | `%Q3.1` | `pgm_solenoid_valve_1` | magazine compartment **1** pusher |
| 2 | `%Q3.0` | `pgm_solenoid_valve_2` | compartment **2** |
| 3 | `%Q2.7` | `pgm_solenoid_valve_3` | compartment **3** |
| 4 | `%Q2.6` | `pgm_solenoid_valve_4` | compartment **4** |
| 5 | `%Q2.2` | `pgm_solenoid_valve_5` | compartment **5** |
| 6 | `%Q0.2` | `pgm_solenoid_valve_6` | FC6 N4, 2 s TON after `wp_in_cv1_end` — conveyor 1 to 2 transfer |
| **7** | `%Q3.6` | **`pgm_cylA_Ext`** | **cylinder A extend** |
| **8** | `%Q2.0` | **`pgm_cylA_Ret`** | **cylinder A retract** |
| **9** | `%Q2.5` | **`pgm_cylB_Ext`** | **cylinder B extend** |
| **10** | `%Q2.4` | **`pgm_cylB_Ret`** | **cylinder B retract** |
| 11 | `%Q2.3` | `pgm_solenoid_valve_11` | FC6 N15, 2 s TP on `Wp_move_cv3` — conveyor 2 to 3 transfer |
| 12 | `%Q0.1` | `pgm_solenoid_valve_12` | FC6 N16, 5 s TP after prox 9 |
| 13 | `%Q2.1` | `pgm_solenoid_valve_13` | FC6 N16, 5 s TP after prox 10 |

**Solenoids 1–5 are five magazine pushers, one per compartment.** `FC7 N3`
says it outright: `mag_push_on AND workpiece_choice = N` drives solenoid *N*.
Since `Comp1`…`Comp5` were already `CONFIRMED` by name, the two numberings are
the same numbering.

**Solenoids 7–10 are four coils on *two* cylinders.** Cylinders A and B are
**double-solenoid** — one coil each way — so a rod holds position with both
coils de-energised. This is the structural finding of the whole pass.

> **MODELLED 2026-09-02.** The sentence that stood here said the model "gives
> each of its five cylinders a single spring-return valve and cannot represent
> that". It now can, and does: the plant carries all **11** actuators on **13**
> coils, `FACTORY_ACTUATORS` declares the valve type, and
> `FACTORY_DERIVATIVES` latches the spool so it *holds* with both coils off.
> What is still open is not the mechanism but the identity — **which physical
> barrel is A** — which is question 3b and one row of that table.

> ~~**Solenoid 6 is the magazine pusher.** The cycle runs `MAG PUSH ON` to
> `CONVEYOR 1 ON` to `SOLENOID VALVE 6 ON`, and a separate `mag push clear`
> network drives it too. That is 1 of 13 identified.~~
>
> **SUPERSEDED 2026-08-30 — wrong.** Written from the network *titles* before
> the networks themselves were read. `MAG PUSH ON` sets the flag `mag_push_on`;
> it is `FC7 N3`, two blocks away, that turns that flag into a coil, and the
> coil it turns it into is **solenoid 1–5**, whichever compartment
> `workpiece_choice` selected. Solenoid 6 fires *later*, after
> `wp_in_cv1_end`, gated on prox 7 and 8 — a transfer, not the pusher.
> Recorded rather than deleted, per `CLAUDE.md` rule 3: reading a network
> title as if it were the network is a mistake that will otherwise be made
> again on the next block.

#### The proximity sensors. All 10.

| # | Address | Role, from the program |
|---|---|---|
| 1–5 | `%I0.3, 0.7, 0.0, 0.1, 1.1` | `FC7 N2`: prox *N* **and** `workpiece_choice = N`, then a 2 s TON, sets `wp_in_cv1`. Compartment *N* dispense confirm |
| 6 | `%I1.5` | clears mag push, gates conveyor 1 |
| 7 | `%I0.4` | `FC7 N5`, the network is titled **WP IN CV2 MID** |
| 8 | `%I0.6` | `FC6 N5`: 400 ms TP sets `Wp_move_cv3`. End of conveyor 2 |
| 9 | `%I0.2` | `FC6 N14` sets `STOP_CONV3`; N16 runs a 5 s TP to solenoid 12 |
| 10 | `%I0.5` | `FC6 N16`: 5 s TP to solenoid 13. A **second** outfeed station |

#### The cycle the machine actually runs (`FC6 void_main`, 17 networks)

1. `CYCLE START` — `CMD_START` and `Startup_Healthy`, T#10S watchdog
2. `MAG PUSH ON` — sets `mag_push_on`; FC7 N3 fires compartment *N*'s pusher
3. `CONVEYOR 1 ON`
4. `SOLENOID VALVE 6 ON` — transfer to conveyor 2
5. prox 8, then a 400 ms TP, sets `Wp_move_cv3`; conveyor 2 runs
6. `CYLA EXT` — sets `Cyla_Moved to Plate` (`%M3.6`)
7. engraving platform **jogged up** (see below), `pgm_engraving_completed`, jogged down
8. `pgm_cylA_Ret`, then `pgm_cylB_Ext` and `pgm_cylB_Ret`
9. `SOLENOID VALVE 11` — transfer to conveyor 3
10. prox 9 fires solenoid 12, or prox 10 fires solenoid 13, each on a 5 s TP
11. `Cycle_Completed`, `Product_Number` and `Total products` incremented

`cylA_extended` and `cylA_retracted` are **derived latches** set from the
commands (`FC7 N6`/`N7`), not sensor inputs. **Cylinder A has no position
feedback on the real machine.** The model's `y.EXT`/`y.RET` are computed from
simulated rod position, which is more information than the PLC has.

**Real timer presets**, against the model's invented placeholders:

| Preset | Attached to |
|---|---|
| `T#10S` | cycle start watchdog, `pgm_cylA_Ext` |
| `T#12S` | `pgm_cylA_Ret`, `pgm_cylB_Ret` |
| `T#2S` | solenoid 6, `CYLA EXT`, solenoid 11, magazine dispense confirm |
| `T#5S` | outfeed, after prox 9 and prox 10 |
| `T#1S` | `exe_mc_moverelative` |
| `t#400ms` | prox 8 to `Wp_move_cv3` |
| `T#0.1S` | `mag_push_on` |

All of these are recorded in `FactoryParams.m` §13C as `P.PLC.t_*`, **not
applied**. Most are watchdogs, not process durations — a `T#12S` on a rod that
strokes in under a second is a fault timer. They bound the real timings; they
do not state them.

**The analogue pressure transmitter.** `FC8 N1` normalises `%IW64`
(`ktf_a10_raw`) over **2765 … 13520** counts and scales to **0 … 10**, so the
HMI's `Pressure.Value` is in **bar gauge** and the instrument is a 0–10 bar
unit. §4's receiver pressures are all still `[ASM]`; this says which gauge
would settle them and in what units it reads.

**The product recipe is not the block on the bench.** `FC9 N4` moves a
`PRODUCT_HEIGHT` of **50** or **25** per compartment, and the register carries
`Productqty_25mm` and `Productqty_50mm` as separate counters. The block
measured in the lab is **40 mm**. The cell is configured for two products that
are neither — see question 16 below. Which compartment holds which is not
readable from the flattened export.

**Three structural facts the model does not represent:**

1. **Three stepper axes plus the platform axis.** `pot_1/pot_2/pot_3`, driven
   by pulse-and-direction outputs through `MC_Power`, `MC_Home`,
   `MC_MoveRelative`, `MC_MoveAbsolute` and `MC_MoveJog`. The engraving
   platform is *jogged* on `Axis_1` at velocity `72.0` until a limit switch
   trips — **not driven to a position**. §8 already models the base as an
   electric axis, which is right in kind; what it does not model is that the
   stroke is terminated by a switch rather than commanded.
2. **The conveyor run commands are plain on/off coils.** The PLC never writes
   a speed to `%Q3.2/3.3/3.4`. The model runs a PI speed loop with ramp
   limiting, gearbox and rotor inertias — that models the *drive's* internals,
   not anything the PLC does. Separately, `Pot_Control.Conv1/2/3` are three
   **position** axes with their own high- and low-speed setpoints; whether
   those drive the belts or something else at each station is not readable
   from the listing.
3. **`engraving_power` is a discrete output**, so the modelled engraving state
   has a real signal behind it.

**A caution on anything read out of that PDF.** The decoder reconstructs word
spacing from kerning numbers and resolves subset-font glyph codes through
ToUnicode maps, so a character can be wrong silently where two fonts share a
code. The addresses above survive that because two independent networks give
them identically. A figure that appears only *once* in the listing has had no
such cross-check — treat it as located, not read.

### Answered 2026-09-02 by photographs, the Component Data drop, and a model change

**All ten proximity sensors are now in the model**, in the machine's own
numbering, and all ten fire in simulation. `factory_sensors.m` computes every
one from the workpiece position; `factory_sensor_bus.m` is the single
definition of the plant→PLC vector that carries them.

The four trip points the sequence gates on **did not move** — that is why the
pinned baseline survived unchanged: 31.030 s, (1.509300, 0.200003), 0.70 mm,
39 transitions. Only the numbers changed, onto the machine's:

| Was | Is | Role, from `FC6`/`FC7` |
|---|---|---|
| `PX(1)` | `PX(1)` | magazine compartment 1 dispense confirm |
| `PX(2)` | `PX(6)` | conveyor 1 |
| `PX(3)` | `PX(8)` | conveyor 2 end |
| `PX(4)` | `PX(9)` | conveyor 3, outfeed station A |

The other six — compartments 2–5, conveyor 2 mid, outfeed B — are **modelled
and logged but guard nothing**, because the model's sequence is
`Sequence.xlsx`'s and the machine's is `FC6`'s, and those are not the same
sequence. Reconciling them is the plant re-model.

#### What the photographs confirm

Four photographs of the running cell, 2026-09-02. Read against the program
text rather than instead of it:

- **Five acrylic magazine compartments, five Janatics cylinders behind them,
  five M18 barrels on brackets along the belt below.** That is `FC7 N3` —
  `mag_push_on AND workpiece_choice = N → solenoid N` — seen on the machine
  instead of read out of the program. Two unrelated sources, both five.
- **The barrels are Janatics**, confirmed on the machine rather than only in
  the CAD folder. Two labels are partly legible: **`MAX PR. 10 bar`** and
  **`MAGNETIC`**. The model number begins `A6` and does not resolve further;
  it is *not* transcribed.
- The blocks are **dark brown hardwood**, not the pale timber 750 kg/m³
  suggests. The density was confirmed by weighing and is not in doubt; the
  species is unrecorded and is now a line on the intake sheet.

**`MAGNETIC` is the finding worth passing to whoever owns the cell.** A
magnetic piston is what a reed or Hall switch senses, so these cylinders are
*built* to take position feedback — and the PLC reads none, latching
`pgm_cylA_Ext` instead (`FC7 N6`/`N7`). The missing feedback is a wiring and
program choice, not a hardware limit. Two switches would make cylinder A
genuinely observable.

#### A trap in the Component Data folder — read this before mining it

`Component Data/Components and Sensors.docx` and `Control Flow.docx` describe
a **five-station training kit**: feeder, inspection, buffer, drilling,
sorting — with a suction gripper, a rotary actuator, an RFID reader, metal and
plastic detectors and an SP-1523D drilling machine. Its sensors are named
`B1`, `1B1`, `2B2` and its cylinders `1A`, `2A`, `3A`.

**That is not this cell.** None of it appears in this machine's PLC program:
no RFID, no suction, no metal detector, no drill.

The folder says so itself. `Laser Engraving Work/abc.pdf` is **byte-identical**
to `plc/abc.pdf` (md5 `31512bc6b9a1b84584a21105839693f4`), so the laser cell is
*one subfolder* of a wider lab and the rest documents the rig beside it.

Both are Janatics, both are Siemens, both are in the same room. Reading the
training kit's component list as a bill of materials for this cell is exactly
the inference that has cost this project sessions before. Everything taken
from it is recorded in `FactoryParams.m` §13D as a **CANDIDATE**:

| Candidate | What it would settle | Why it is not applied |
|---|---|---|
| Vexta `AXHM450K-GFH`, 50 W, 100–3000 rpm | `P.J_mot`, `P.T_max`, `P.N_gear`, belt speed | named in the *other* machine's document |
| Janatics `FRC136134` / `PS0102504` / `DC36W` | FRL and valve conductances | same |
| "maintains the total required 6 bar" | corroborates `P.P_set` | mild — one regulator setting across a whole lab is unremarkable |

`AXH Series.pdf`, `Limit Switches.pdf`, `Photosensor - SICK.pdf` and
`SP-1523D_Leaflet.pdf` are vendor datasheets for that kit. They have a real
text layer, unlike `abc.pdf`, so they decode directly — but they document
components not yet shown to be here.

#### The SCADA platform was carrying overturned claims to an operator

`new_scada/scada_platform` reads this model and shows its output on an
operator HMI. Its hard-coded caveat list still said:

- SCALE is recorded as "CONFIRMED INCORRECT" — overturned 2026-08-26. SCALE
  is confirmed **correct**, four independent ways. This is the exact README §11
  failure `DocumentationFactsTest` exists to catch, living on in a file that
  test does not read.
- *"The mapping between them is not recorded in any supplied source"* —
  overturned 2026-08-30.
- Counts and cycle time from three baselines ago.

All corrected, and the numeric ones now generated from the live model rather
than typed. `data/twin_reference.json` was a **synthetic sample with invented
timings** (`29.78 s`, `"source": "SYNTHETIC SAMPLE -- NOT FROM MATLAB"`); it
has been regenerated from `run_factory_simulation` and now carries the real
31.030 s cycle, 39 transitions and 12 trajectories.

### Answered 2026-09-07 — three nameplates and a filled intake sheet

Six photographs taken at the cell, plus the intake sheet with its hand-entered
columns filled in. **One item is applied and the rest are recorded**, on the
same terms as the CAD and PLC findings — `FactoryParams.m` §13J holds all of it.

| What arrived | What it settles | Applied? |
|---|---|---|
| `A120323000` — Janatics A12, **bore 32**, stroke 300, 10 bar | Question 14, for one barrel. **Bore 20 is refuted**: it is in no source | **Yes** — `CYL_A` now carries 32 / 12. Cycle 31.080 → 33.840 s, air 6.09 → 8.20 NL |
| `A510251600` — Janatics A51, **bore 25**, stroke 160, 10 bar | A second real barrel, and it supersedes §13D's "the model number begins A6… and does not resolve" | ~~No — nothing says which actuator it is~~ **Yes, 2026-09-13 (plan H7)**: xfer1, MAG1–5, SV11 and SV12 carry 25 / 10 / 160 |
| `JK42HS34-1334` — NEMA 17 hybrid stepper | The drives are **steppers**, confirming the PLC's Technology Objects and the owner's account. "Generic 3-phase" is dead | No — see question 19; the axis is unidentified and §7's ratio is invented |
| Ten proximity-sensor **positions**, 0–1720 mm along the path | Question 4b's first half. Six land within 25 mm of the model's own layout | No — and two of the three misses are confirmed by the recorder. See below |
| Cylinder strokes: A 290, B 170, pusher 200 mm | `CYL_A` = 300 mm three ways. The pushers are a **third**, unread barrel | Partly — it is one of the three reasons the A12 went to `CYL_A` |
| The engraving platform's drive, photographed | The axis is electric and **screw-driven** — a threaded rod in a bronze flange nut. §8's inference from Sequence.xlsx is confirmed by looking at it | No — a photograph gives a thread *form*, not a lead |

**Two sensor findings are worth more than their row.** `PX09` measures 204 mm
into a 465 mm conveyor-3 run, and the recorder independently times it at 1.02 s
after that belt starts — 153–204 mm at plausible belt speeds. **Two instruments,
different days, different means, same answer**: PX09 is near the *start* of belt
3, and the model has it at the end. And `PX08` measures 140 mm *past* `c2_end`,
on the bypass run — which explains why the recorder never saw it trip, since an
engraved block stops before reaching it. Both are recorded rather than applied
because moving PX09 moves the outfeed station, the bin and the support region
with it: that is a layout change and it deserves its own iteration. *Applied
for belt 3 on 2026-09-12 (plan H3): PX09 and outfeed A now stand at 43 cm
along belt 3, PX10 and outfeed B at 55 cm, downstream.*

**And the sheet used centimetres again**, in a column headed millimetres, on a
sheet that prints "Write millimetres, not centimetres". Caught before anything
was applied, by checking the magazine sensor spacing against the CAD's slot
pitch — see README §11 *A units trap worth knowing about*.

### Still blocking

| # | What | How | Goes into |
|---|---|---|---|
| ~~3~~ | ~~Which cylinder each of the 13 solenoids drives~~ | **ANSWERED 2026-08-30 by the PLC listing.** All 13 coils are mapped by address and by driving command. What is left is **3b** | `factory_io_map.m` |
| **3b** | **Which physical barrel is "cylinder A" and which is "cylinder B"** — *and, since 2026-09-10, whether "cylinder 3" is a third* | **Cylinder A is now identified by a hand label at the cell (the A12).** **ANSWERED THE SAME AFTERNOON by the SCADA-side panel test (round-2 handoff §4.4b):** cylinder A pushes belt 2 → the engraver, and cylinder B pushes the block out of the engraver → belt 3 — reading R1. The no-engrave bypass is **SV11**, a different actuator. *Was open:* the maintainer names a "cylinder 3" that pushes engraver → belt 3, and separately labels an A28 barrel "Cylinder B" — one barrel or two? Energise `%Q2.5` (SV9) and `%Q2.3` (SV11) one at a time and note **which labelled barrel** moves and where it pushes. See `FactoryParams` §13M, 2026-09-10 note. *Original ask:* energise `%Q3.6` and `%Q2.5` one at a time from the manual-command page and watch which rod moves. Two coils, two answers | `factory_io_map.m` |
| ~~4~~ | ~~What each of the 10 proximity sensors watches~~ | **ANSWERED IN ROLE 2026-08-30.** 1–5 are the five compartment dispense sensors, 6–10 sit along the transport. What is left is **4b** | `factory_io_map.m` |
| **4b** | **~~Where each of the ten is bolted~~, and the trip distance** | **RE-MEASURED PER BELT 2026-09-10**, from each belt's start: belt 1 px1–6 at 13/24/35/46/57/73 cm (the 46 cm sensor is PLC input 5 and the 57 cm one input 4); belt 2 px6 −20, px7 25, px8 47, cylinder A line 0, SV11 line 51; belt 3 cylinder B drop 17, SV11 drop 0, SV12 line 43, px9 47, SV13 line 55, px10 60; each belt 75 cm. `Project_Notes/to_matlab/round2_2026-09-10/PROX_POSITIONS_MEASURED_2026-09-10.md`. *Earlier:* **POSITIONS MEASURED 2026-09-07**, all ten, as path distance from the compartment-1 load point: 0, 120, 230, 340, 460, 560, 860, 1100, 1620, 1720 mm. Six land within 25 mm of the model's own layout. Three do not, and two of those are corroborated by the recorder: **PX09 is near the START of conveyor 3, not its end**, and **PX08 sits past `c2_end` on the bypass run**, which is why it never tripped. *(Modelled 2026-09-11: PX08 at `c2_byp`, the bypass pickup, and PX07 now ends the engraved belt-2 run at `c2_end`.)* Recorded, not applied — moving PX09 moves the outfeed station with it. *(Belt 3 applied 2026-09-12, plan H3; belt 2 already agreed with the tape when measured from its own start.)* What is still needed is the **belt-by-belt datum** (where each belt starts) so cumulative path distance can be mapped onto cell coordinates, and the **trip distance** against a real 100 × 100 mm block — the sheet's trip-distance column was filled with positions instead, so `P.prox_rng` is still `[EST]` at 30 mm | `factory_io_map.m`, `FactoryParams.m` §13J |
| **14** | **Read the remaining nine barrel labels** | **APPLIED 2026-09-13 (plan H7): every barrel now carries its nameplate bore and stroke** (A51/A52 25 / 160, A28 32 / 300; MAG1/3/4/5 on the maintainer's statement). *Was:* **2026-09-10: SIX MORE PHOTOGRAPHED and hand-labelled at the cell, none applied.** Cylinder A = A12 (confirms the applied row); Cylinder B = `A280323000`, A28, bore 32, stroke 300; xfer·1 and the SV-2 magazine pusher = A51, bore 25, stroke 160; plus one unlabelled A51 and one unlabelled `A520251600`, A52, magnetic. Two codes are new to the project and both were anticipated by the vendor's CAD folder names. See `FactoryParams` §13J addendum and `Project_Notes/CYLINDER_PHOTOS_2026-09-10.md`. **TWO ANSWERED 2026-09-07, and one is applied.** Nameplates photographed at the cell read `A120323000` — Janatics A12, **bore 32, stroke 300**, MAX.PR 10 bar — and `A510251600` — A51, **bore 25, stroke 160**. Bore 20 is now *refuted*, not merely doubted: it appears in no source. The A12 is applied to `CYL_A` (see §13J for the three-way stroke agreement that made that safe); the A51 **cannot be applied until the panel test says which actuator it is**. ~~Nine barrels are still unread, including all five magazine pushers, whose 200 mm measured stroke matches neither nameplate — so they are a **third** barrel~~ *(superseded 2026-09-10: the SV-2 pusher is stamped A51, stroke 160 — the 200 mm reading does not survive the stamp; MAG1 and MAG3–5 are still unread)* | `JanaticsData.m` §1B, `factory_actuators.m` |
| ~~15~~ | ~~Weigh one block~~ | **ANSWERED 2026-08-26.** A block weighed **0.300 kg**, and 0.300 ÷ (0.1 × 0.1 × 0.04) = **750 kg/m³** exactly. Density is confirmed; the workpiece is now fully measured | `FactoryParams.m` |
| **16** | **Which product the cell is set up to run** | `FC9 N4` carries `PRODUCT_HEIGHT` = **50** and **25**; the bench block is **40 mm**. Read `Product Data[...].PRODUCT_HEIGHT` per compartment off the HMI, and note what is physically loaded in each of the five | `FactoryParams.m` §3, §13C |
| **17** | **Are cylinders A and B really double-solenoid** | Look at the two valve bodies. A double-solenoid 5/2 has a coil at each end and no spring. The PLC drives four coils (`%Q3.6/2.0/2.5/2.4`) as two extend/retract pairs, which only makes sense if they are. **The model now assumes yes** and latches the spool accordingly; a "no" here is one column of `factory_actuators.m` | `factory_actuators.m` |
| **18** | **Which rig do the four vendor datasheets in `Component Data/Components/` belong to** | `AXH Series.pdf`, `Limit Switches.pdf`, `Photosensor - SICK.pdf`, `SP-1523D_Leaflet.pdf`. They sit beside a document that describes the **training rig**, so the default assumption is that they do too — and they are not applied. Two would matter if they were this cell: **AXH** is an Oriental Motor brushless DC range, and every conveyor drivetrain figure is `[EST]`/`[ASM]`; and a **SICK photosensor** is photoelectric, where this cell's proximity sensors were confirmed *capacitive*, a finding `factory_sensors.m` depends on | `FactoryParams.m` §13E2 |
| ~~**3c**~~ | ~~**What fires cylinder B, and does the 50 mm path skip the platform raise**~~ | **ANSWERED AND BUILT 2026-09-11.** The maintainer: “CYLINDER b FIRES WHEN ENGRAVING IS DONE AND IT PUSHES BLOCK TO BELT 3, SV11 FIRES WHEN ENGRAVING IS SKIPPED”. Both routes are modelled and `P.engrave_selected` (`FactoryParams.m` §15) picks one: the skip runs states S40–S43 — the block runs on to prox 8, SV11 pushes it `c2_byp` → `c3_load` on its `T#2S` pulse, and the cycle rejoins at S33. The skip never reaches the platform. **Still open:** what the HMI selects the skip with (the owner's “50 mm” link; *2026-09-12: the legacy SCADA page filmed in `LEPS_Showcase_master.mp4` offers only 25 mm / 50 mm order quantities and no skip control, `Project_Notes/VIDEO_REFERENCE.md` §7*), and a recorded bypass cycle to check it against. *Earlier:* **2026-09-10: the bypass is SV11** (`%Q2.3`, belt 2 → belt 3 directly), stated by the operator at the cell; cylinder B makes the engraver → belt 3 move (observed at the panel). SV13 is a second outfeed piston into the same bin. The model had neither route yet *(the SV11 route was built 2026-09-11)*. *Earlier:* **PLACEMENT ANSWERED 2026-09-02 by the owner**, in four statements ending with the position marked on a drawing: cylinder B sits beside conveyor 2 at belt-3 height and pushes **+x** onto belt 3 when cylinder A does not push into the engraver, i.e. on the 50 mm no-engrave path. Modelled and drawn. What is still missing is the **sequence**: the model has no product selection and no no-engrave branch, so nothing ever commands it. Also unknown: whether the 50 mm path skips the platform raise as well as the engraving | `factory_actuators.m`, `factory_plc.m` |
| ~~**17b**~~ | ~~**Where is the conveyor 2→3 transfer (coil 11)**~~ | **ANSWERED 2026-09-02.** The owner confirmed cylinders A and B both do *not* make the engraver→belt-3 move, which leaves solenoid 11 — and that is what its own PLC name said: `FC6 N15` fires it on `Wp_move_cv3`, "workpiece move to conveyor 3". It is renamed `MOVE_TO_CV3`, placed on the `engrave`→`c3_load` stroke, and no longer borrows anything. *(Superseded: on 2026-09-08 the recording gave the engraver → belt 3 move to cylinder B; on 2026-09-11 solenoid 11 became the bypass, placed `c2_byp` → `c3_load`.)* `XFER_CV2_CV3` was the model's guess at what it did, and the guess was the thing that was wrong | — |
| **17d** | **Is the second outfeed station really at proximity sensor 10** | The model now assumes it is, by symmetry with outfeed A and prox 9 in `FC6 N16`. Stand at PX10 and check a cylinder is bolted there. If it is somewhere else, that is one waypoint (`c3_out_b`) | `initialize_factory.m` |
| **17c** | **Does the engraving platform hold or fall when its drive is disabled** | Press the E-Stop with the platform raised and watch. The model leaves `plc.base` where the sequence put it, because inventing either behaviour is worse than leaving it | `factory_plc.m` |
| **19** | **The conveyor motor nameplate — *and which axis it is on*, and the gear ratio** | **HALF-ANSWERED 2026-09-07 and it was not enough.** A motor nameplate at the cell reads `JK42HS34-1334`, a NEMA 17 hybrid stepper. That **confirms the drives are steppers** — §7's "generic 3-phase" is wrong, and the Vexta `AXHM450K-GFH` candidate from the training-kit document is dead. It settles nothing numerically, for two reasons: the photograph does not say which of the cell's **four** stepper axes it was taken on, and `P.N_gear = 20` with `P.T_max = 0.050 N·m` is a *self-consistent invented set* — a real 0.28 N·m motor through an invented 20:1 gives 5.6 N·m at a pulley carrying a 0.3 kg block. Needed: which axis, the gear ratio, and the pulley radius, together | `FactoryParams.m` §7, §13J |
| **20** | **Are position switches fitted to cylinders A and B** | The barrels read `MAGNETIC`, so they can take them; the PLC reads none. Worth reporting to whoever owns the cell | `factory_io_map.m` |
| **18** | **What `Pot_Control.Conv1/2/3` actually move** | Three `MC_MoveAbsolute` position axes named after the conveyors, separate from the three on/off conveyor coils. Watch what moves when each is jogged | `FactoryParams.m` §7 |

**3b, 4b, 14, 16, 17 and 18 are one walk around the cell** — and it is now a
much shorter walk than it was. Before the PLC listing was traced, items 3 and 4
were "identify 23 signals from scratch". They are now "confirm 8 placements and
read 6 labels", because the program text already named every coil, every input
address and every network that fires them.

**What the listing could not close, and why.** It fixes each signal's *role in
the sequence*. It says nothing about where a sensor is bolted, which barrel is
which, or what a stepper axis is bolted to — none of that is in a ladder
diagram. Those are the rows still marked `PROVISIONAL` in `factory_io_map.m`,
and `factory_io_map('report')` lists them.

**Item 4's structural doubt is closed — the sensors are CAPACITIVE**
(confirmed 2026-08-26). This mattered more than a parameter. `factory_sensors.m`
computes every `y.PX` from the **workpiece** position, and an inductive sensor
cannot detect wood at all — had they been inductive they would have to be
watching metal, and the sensor model would have needed **rewriting rather than
re-tuning**. Capacitive sensors do detect wood. The model is structurally
correct as written. Note the CAD file named `Inductive Proximity Sensor
Assembly` is simply mislabelled.

What remains on item 4b is ordinary: **where each of the ten sits**, plus the
trip distance against a real 100 × 100 mm block. One oddity worth resolving
while you are there: `P.MEAS.prox_rated_mm = 125` does not sit comfortably with
an M18 capacitive barrel, which typically ranges a few mm to about 20 — either
the 125 belongs to something else, or the sensor is not the M18 that appears in
the CAD.

**The engraving sequence is confirmed correct** (2026-08-26). A base platform
raises the block, the operator engraves by manual input, then the platform
lowers. That is exactly what states `S22_BASE_UP` → `S23_HEIGHT_TOP` →
`S24_OPERATOR_NOTICE` → `S25_ENGRAVE_MANUAL` → `S26_ENGRAVE_CONFIRM` →
`S27_BASE_DOWN` → `S28_HEIGHT_BOTTOM` already model. The DAJA laser raised a
doubt that the platform motion was fictitious; it is not. What stays open is
only the **durations**, which are `[PLH]`.


**Item 14 was answered in part, and the answer was bigger than the question.**
It used to read *"which cylinders are bore 32 and which are bore 20"*. The CAD
says that choice was wrong: the cell contains bore **32** and bore **8**, and
`JanaticsData.m`'s bore 20 / rod 8 matches **neither**. At 6 bar that is 30 N
against 482 N — a factor of 16 between the two real cylinders, and the model
sits between them at 188 N. What remains open is only which cylinder is where,
and that is read off six barrels.

### Answered 2026-08-25 — and item 5 corrects a wrong assumption

| # | Question | Answer |
|---|---|---|
| **5** | What do 25 mm and 50 mm refer to? | **ENGRAVING LENGTH, not workpiece size.** See below — this changes the model |
| **7** | Magazine capacity | **30 in total, 6 per column, 5 columns** — confirmed |
| **9a** | Does a sensor detect engraving completion, or a person? | **The operator presses a button.** See below — this decides what the model can honestly predict |

**Item 5 was a wrong assumption of mine and it matters.** I had read
`Productqty_25mm` / `Productqty_50mm` as two *product sizes*, and wrote in
`P.REAL.product_mm` that they were "the first real length anywhere in this
project". They are not. They are **how much engraving is done** — the engraving
length — so they say nothing about the workpiece dimensions and do **not** help
settle `SCALE`. (`SCALE` was settled instead by measuring conveyor 1; item 2,
the workpiece, was settled by measuring the part. Both landed 2026-08-25.)

What it does tell us is more useful than what I thought it did:

- `P.t_engrave = 8.0 s` `[PLH]` is a **single** invented duration, but the
  machine runs **two engraving jobs of different length**. A 50 mm engrave
  cannot take the same time as a 25 mm one.
- The right model is not two timers either. The PLC publishes
  `Engraving_Completed`, so the correct fix is to make the state
  **sensor-driven** and let the duration fall out — exactly as every other
  state in the sequence already works.

**Item 7:** confirmed as **6 per column, 30 total**, consistent with the
snapshot (`c1:1, c2:3, c3:6, c4:3, c5:0` — largest seen is 6).

**Item 9a matters more than it looks.** `Engraving_Completed` is set by a
**person pressing a button**, not by the machine detecting anything. So the
engraving duration is not a machine property at all — it is human work time,
and human work time has *spread*.

Three consequences, and the third is the uncomfortable one:

1. `P.t_engrave = 8.0 s` should not be one number. It is at minimum two, since
   a 50 mm engrave takes longer than a 25 mm one.
2. Even two numbers are only means. What the model needs is **mean and spread
   for each engraving length**, which is why item 9 asks for both.
3. **The model cannot predict cycle time, and should stop implying it can.**
   12.5 s of the 33.84 s cycle is operator-paced. The honest quantity to
   predict is *machine time* — 21.34 s — with an operator distribution on top.
   The `README` fidelity table already lists determinism as "not faithful";
   this is the concrete reason why.

### Still needed

### Item 6, elaborated — and it is the same measurement as item 1

**What I am looking at.** Your PLC publishes, for each conveyor:

```
"DB_Global".Pot_Control.Conv1.Current_Position_Fb     Real     DB59.DBD178.0
```

In the snapshot you supplied it reads **exactly 30.0**, and so do Conv2 and
Conv3. It is a *number with no unit attached*, and the tag list does not say
what the unit is.

**Why it blocks the model.** Your conveyors are not simple belts. The PLC drives
them as **position-controlled axes** — the same block has `Goto_Position`,
`Set_Home`, `Axis_Homed_Fb` and encoder feedback. The model currently treats
them as free-running belts told to go at 0.15 m/s (0.21 / 0.31 / 0.15 since
2026-09-12, timed rather than converted). To model what the machine
actually does, I have to be able to turn "go to position 30" into "move the
part this many millimetres". Right now I cannot, because 30.0 could be
millimetres, centimetres, motor steps, encoder counts, or revolutions — and
those imply cells of wildly different size.

**How to find out, in four steps.** Roughly ten minutes at the machine:

| | Do this |
|---|---|
| 1 | Put a pencil mark on conveyor 1's belt, and a mark on the frame beside it |
| 2 | On the dashboard, note `Conv1.Current_Position_Fb` — call it **P1** |
| 3 | Jog or run conveyor 1 so the belt moves a noticeable distance, then stop |
| 4 | Note the new reading **P2**, and measure with a tape how far the belt mark moved, in **mm** |

Then send me **P1**, **P2**, and the **millimetres moved**. One unit of that
number equals `mm_moved / (P2 - P1)`.

> **Item 1 is already settled** by the 760 mm conveyor measurement, so this is
> now only about the position *unit*. Ten minutes, and it is the last thing
> standing between the model and a faithful position-controlled conveyor.

**One oddity worth checking while you are there.** All three conveyors read
*exactly* 30.0 in the snapshot. That is either because all three were homed and
parked at the same place, or because 30.0 is a default that was never written.
If the number does not change when a belt moves, tell me — that changes the
interpretation completely.

### High value, cheap to obtain

| # | What | How |
|---|---|---|
| **8** | **Bore, rod and stroke for each of the 11 actuators** | Photograph the body stamps. `D_bore` is the single most sensitive parameter in the model, +20% costs +3.26 s of cycle |
| **9** | **Operator notice, engrave and confirm durations** | Stopwatch over 5–10 cycles, **mean and spread**. These are 12.5 s of a 33.84 s cycle, all currently invented |
| ~~10~~ | ~~Receiver pressure at cycle start~~ | **ANSWERED: 4.3 bar**, matching the PLC's own 4.315 reading |
| **11** | **Belt speed setpoint** | Drive parameter, or time a marked block over a known distance. **Belts 1 and 2 timed, 2026-09-12:** 0.21 m/s (recorded sensor pitches) and 0.31 m/s (tape). **Belt 3 is still open**: time it on Wednesday |
| **12** | **PLC scan time, and whether I/O is written at end-of-scan or immediately** | Your PLC software reports scan time directly |

### Access, not measurement

| # | What |
|---|---|
| **13** | **Get OPC UA access to the PLC.** Step by step in the new **`PLC Access`** worksheet of `Physics_Framework.xlsx` — 19 yellow cells to fill in. `opcuaserverinfo('192.168.0.102')` currently finds nothing from this workstation, which blocks the live link, and the live link is what makes this a twin rather than a simulation |

**What "access" means, in one paragraph.** Three things have to be true, in
order, and the worksheet walks each one. First the **network**: this PC must be
able to reach 192.168.0.102 on TCP port 4840. Second the **server**: an S7 does
not serve OPC UA until it is ticked on in TIA Portal, given a runtime licence,
and *downloaded* — activating it without a download does nothing. Third the
**endpoint and security**: I need the URL that worked, whether it demands a
login, and the namespace index for `DB_Global` (the register suggests 4).

> **Do not type a password into the workbook.** It is committed to git. The
> sheet asks only *whether* a login is required; send the credential separately.

**If you can only do one trip:** items 1, 3, 4 and 8. That is a tape measure, a
phone camera and the HMI, and it closes both blockers plus the largest
sensitivity in the model.

---


Every quantity the model needs from the real cell, in one place, so that when
the data arrives nothing has to be re-derived or guessed.

- **`NEXT_STEPS.md`** says *what to measure first* — it ranks by measured
  sensitivity (each parameter perturbed +20% and the cycle re-run).
- **This file** says *what to supply in total* — it is exhaustive, not ranked.
- **`PHYSICS_FRAMEWORK.md`** says *which equation consumes each input*.

**Provenance tags** are carried on every parameter in `FactoryParams.m` and
`JanaticsData.m` and are never removed:

| Tag | Meaning | Count | Needs real data? |
|---|---|---|---|
| `[PLH]` | placeholder, must be replaced | 3 | **Yes — blocking** |
| `[ASM]` | engineering assumption, in no source | 39 | **Yes** |
| `[EST]` | engineering estimate from typical data | 27 | **Yes** |
| `[JAN]` | Janatics catalogue figure | 7 | **Yes — provisional, see below** |
| `[COMM]` | commissioning setting (a knob, not a part) | 6 | Yes — read off the machine |
| `[CAL]` | calculated from the above | 14 | No — recomputes itself |
| `[REF]` | from the reference layout script | 1 | Inherits `SCALE` |
| `[PLC]` | **observed on the real machine's PLC** | 9 | **No — this IS real data** |
| | **total tagged** | **106** | |

**69 parameters are unmeasured** (`PLH` + `ASM` + `EST`). Regenerate these
counts at any time with the audit in section 7.

> **2026-08-24 — real PLC data arrived.** `PLC_Dashboard/` and `Final/` supplied
> the machine's actual tag register, a live PLC snapshot, the magazine inventory
> and 1002 photographs. What it settled and what it did not is section 5. The
> short version: it answered several long-standing questions, contradicted the
> model's I/O counts, and introduced one new blocking unknown — **which solenoid
> drives which cylinder, and where each of the 10 proximity sensors sits**.

> **The `[JAN]` figures are not confirmed.** No nameplate, purchase order,
> machine BOM or photograph of the installed equipment has ever been supplied.
> Every Janatics component in the model is a *technically compatible candidate
> selected to suit the implied duty*, not a component known to be installed.
> `JanaticsData.m` records this per component in `J.<comp>.status`. Repetition
> must not be allowed to turn a candidate into an actual.

---

## 1. What a photograph can and cannot settle

A photo set is genuinely useful, but only for some of this. Being precise about
which, so effort goes where it pays.

### A photograph settles these outright

| Input | What the photo must show |
|---|---|
| **Cylinder part numbers** (the single most sensitive input in the model) | Close-up of the body stamp / label on each of the 11 actuators, legible |
| **Valve and FRL part numbers** | Close-up of the manifold labels and the FRL body |
| **Motor / gearbox nameplates** | Close-up of each conveyor drive nameplate |
| **Sensor types** | Close-up of a proximity sensor and a reed switch body |
| **Regulator set pressure** | The FRL gauge face, readable |
| **Receiver pressure at rest** | The receiver gauge face, readable |
| **Cell topology confirmation** | One wide shot showing all three conveyors and five actuators |
| **Workpiece shape** | The part next to a ruler or a known object |

### A photograph settles these only with a scale reference in frame

Put a **tape measure or a 300 mm steel rule in the shot**, in the same plane as
the thing being measured. Without it a photo cannot give a dimension.

| Input | Needs |
|---|---|
| `SCALE` (**blocking**, section 2) | Tape along conveyor 1, full length, readable |
| Workpiece dimensions | Rule against all three faces |
| Conveyor lengths and spacing | Tape along each belt |
| Cylinder stroke | Rule against the extended rod |

### A photograph cannot settle these — they need an instrument

Timings, speeds, pressures under load, friction, and every dynamic quantity.
No image gives these. See sections 4.6 and 4.7.

**If you can only do one thing:** photograph the five cylinder body stamps and
put a tape measure along conveyor 1. That closes the two largest error sources
in the model — `D_bore` (+3.26 s cycle sensitivity) and `SCALE` (which scales
every dimensional result).

---

## 2. Blocking inputs — nothing dimensional is trustworthy until these land

### 2.1 `SCALE` — CONFIRMED CORRECT, closed 2026-08-25

`P.SCALE = 0.10` `[ASM]` — and it was right all along.

This section argued for six sessions that `SCALE` was wrong and that nothing
dimensional could be trusted until it was replaced. That was mistaken, and the
mistake is left visible here rather than deleted, because it shaped a lot of
earlier reasoning.

Three independent sources now agree:

| Source | Distance | Implied `SCALE` |
|---|---|---|
| Tape measure on conveyor 1 `[MEAS]` | 760 mm over 7.6 drawing units | **0.1000** |
| `conveyor.stp` in the vendor CAD `[CAD]` | 775 mm | 0.1020 |
| `base_40.stp` cell footprint `[CAD]` | 1.61 x 1.57 m | consistent with the assumed 1.70 x 1.30 m |

The original reasoning — that a 0.6-unit block read literally would be a 583 kg
workpiece, which is absurd — was sound, and it produced the right answer.

**What was actually wrong is the workpiece**, which the drawing simply does not
draw to scale. See 2.2. Nothing is blocked on `SCALE`.

### 2.2 Workpiece — material and all three dimensions

`P.blk_a` `[REF]:54`, `P.blk_rho = 2700` `[ASM]:55`

Confirmed as a **small wooden cuboid**, not the aluminium cube modelled
(2700 kg/m^3, likely nearer 500). Deliberately **not changed**: the density and
all three dimensions are unknown, and editing `blk_rho` moves every pinned
reference value in `verify_model.m` and `tests/CycleRegressionTest.m`.

**Supply:** length x width x height in mm, and either the wood species or the
measured mass in grams. Mass plus dimensions is best — it gives density
directly and avoids a species lookup.

> The model currently treats the part as a **cube** (single edge `blk_a`).
> Three distinct dimensions require a small change to the geometry and contact
> code, not just a parameter edit. Flagged so it is not mistaken for a
> drop-in value.

---

## 3. Newly exposed input — PLC output latency

`P.plc_io_delay = 0` `[ASM]` `FactoryParams.m:176`

**New in session 8.** This was previously not a parameter at all: it was
hard-coded inconsistently, at 0 on the MATLAB path and at 1 on the Simulink
path, which was the entire cause of the historical 0.300 s / 0.486 mm
disagreement between them (former open issue 3, now closed).

A real PLC scan is read-inputs, execute, write-outputs, all inside one scan
period, so the true latency is `T_exec / t_scan` and lies in `[0, 1]`:

| Value | Meaning |
|---|---|
| `0` | outputs land in the same scan the inputs were read (`T_exec -> 0`) — **current default** |
| `1` | outputs land at the start of the next scan (`T_exec -> t_scan`) |

**Supply:** the PLC's actual scan execution time, and its I/O update mode
(synchronous end-of-scan vs immediate write). Most PLC engineering software
reports scan time directly. Also confirm `P.t_scan = 0.010` `[ASM]:152` — the
scan *period* is likewise assumed.

Default stays `0` because every pinned reference value was baselined on it.

---

## 4. Complete register, by subsystem

Line numbers are `FactoryParams.m` unless prefixed `JD:` for `JanaticsData.m`.

### 4.1 Pneumatic cylinders — highest sensitivity in the model

| Param | Line | Tag | Supply |
|---|---|---|---|
| `P.D_bore` | 84 | `[JAN]` | **Bore diameter per cylinder, mm** — from the body stamp. One assumed 20 mm is currently applied to all five. **+20% gives +3.26 s cycle** |
| `P.d_rod` | 85 | `[JAN]` | Rod diameter per cylinder, mm — same source |
| `P.strokes` | 90 | `[JAN]` | Stroke per cylinder, mm — measure the extended rod |
| `P.p_max` | 91 | `[JAN]` | Max working pressure from the datasheet |
| `P.m_pist` / `J.CYL.m_moving` | 88 / JD:72 | `[EST]` | Piston + rod moving mass — not published; weigh a spare or accept the estimate |
| `P.V_dead` / `J.CYL.V_dead` | 89 / JD:73 | `[EST]` | Port + cushion dead volume |
| `P.F_coul0` | 108 | `[EST]` | Breakaway friction, unpressurised — push the rod with a spring gauge |
| `P.c_visc` | 109 | `[EST]` | Viscous friction coefficient |
| `P.f_loss` | 107 | `[JAN]` | Load-proportional loss factor |
| `P.gap_app` | 111 | `[ASM]` | Rod-tip to workpiece approach gap, mm |

### 4.2 Valves and air preparation

| Param | Line | Tag | Supply |
|---|---|---|---|
| `P.P_set` / `J.FRL.p_set` | 78 / JD:127 | `[COMM]` | **Regulator set pressure** — read the FRL gauge |
| `P.C_dv` | 79 | `[JAN]` | FRL + supply line sonic conductance |
| `P.C_sup` | 99 | `[JAN]` | DS2 + GR check conductance, in series |
| `P.C_ctrl_B` | 100 | `[COMM]` | Flow-control needle setting, **extend** speed |
| `P.C_ctrl_A` | 101 | `[COMM]` | Flow-control needle setting, **retract** speed |
| `P.tau_sv` / `J.VAL.tau` | 102 / JD:91 | `[EST]` | 5/2 spool travel time — **not published by Janatics** |
| `P.tau_dv` | 80 | `[EST]` | Distribution valve response time |
| `P.V_branch` | 81 | `[EST]` | Branch manifold + tubing volume — from tube diameter and run lengths |

Needle valve settings are the two knobs that set actuator speed. If they have
never been indexed, record the current turns-open from fully closed.

### 4.3 Compressor and receiver

| Param | Line | Tag | Supply |
|---|---|---|---|
| `P.P_res_0` | 65 | `[ASM]` | **Receiver pressure at cycle start** — gauge. **+20% gives -1.98 s** |
| `P.P_cut_in` | 66 | `[ASM]` | Compressor pressure switch, cut-in |
| `P.P_cut_out` | 67 | `[ASM]` | Compressor pressure switch, cut-out |
| `P.V_res` | 64 | `[EST]` | Receiver volume — stamped on the tank |
| `P.mdot_pump` | 68 | `[EST]` | Compressor delivery, from the nameplate |
| `P.P_relief` | 71 | `[ASM]` | Relief valve set point |
| `P.C_relief` | 72 | `[EST]` | Relief valve conductance |
| `P.P_ready` | 69 | `[ASM]` | "Ready" threshold used by the sequence |
| `P.P_br_rdy` | 70 | `[ASM]` | Branch-charged threshold |

### 4.4 Conveyors and drivetrain

| Param | Line | Tag | Supply |
|---|---|---|---|
| `P.v_belt` | 192 | `[ASM]` | **Belt speed setpoint, m/s — 1x3, one per conveyor.** The machine really does carry three independent axis setpoints, so the *structure* is observed; the *value* is not. 0.150 was briefly tagged `[PLC]` on 2026-09-06 and reverted on 2026-09-07 — the recording behind it was the SCADA **simulator**, which seeds 0.15 because that is this model's own number (§13I). The real axes read `Set_Velocity = 180.0` in an unstated unit. **+20% gives -1.23 s.** Only a belt timed over a measured distance settles it |
| `P.a_belt` | 134 | `[ASM]` | Accel/decel ramp limit |
| `P.r_pul` | 123 | `[ASM]` | Drive pulley radius — measure |
| `P.N_gear` | 124 | `[ASM]` | Gearbox ratio — nameplate |
| `P.eta_gb` | 125 | `[EST]` | Gearbox efficiency |
| `P.J_mot` | 126 | `[EST]` | Motor rotor inertia — datasheet |
| `P.J_pul` | 127 | `[EST]` | Pulley + belt inertia |
| `P.T_max` | 128 | `[EST]` | Motor torque limit |
| `P.b_visc` | 129 | `[EST]` | Drivetrain viscous friction |
| `P.T_coul` | 130 | `[EST]` | Drivetrain Coulomb friction |
| `P.Kp_cv`, `P.Ki_cv` | 131-132 | `[ASM]` | Speed-loop gains — from the drive parameters |
| `P.om_eps` | 135 | `[ASM]` | Numerical regularisation — no measurement needed |

### 4.5 Engraving base axis

| Param | Line | Tag | Supply |
|---|---|---|---|
| `P.z_top` | 249 | `[ASM]` | **Engraving platform stroke, mm.** **Measured ~45 mm at the cell 2026-09-10** (model 50). Applied consistently it moves machine time by −0.03 s, exactly as this row predicted. *Was:* still unmeasured, and the *only* unknown in the axis: the travel TIME is observed, so `z_top` and `v_base_jog` move together and the 8 s stays right whatever the stroke turns out to be. One tape measure between the two limit switches settles it |
| `P.m_base` | 141 | `[EST]` | Moving base mass, kg |
| `P.t_base_travel` | 250 | `[PLC]` | **Limit-to-limit travel, 8.0 s EACH way.** Observed from `%I1.0`/`%I1.2` in every recorded real cycle (7.7–8.3 s). This is what makes the axis faithful; see §F2 |
| `P.v_base_jog` | 251 | `[CAL]` | `z_top / t_base_travel` — the jog speed. Recomputes itself |
| `P.Ki_bz`, `P.Kd_bz` | 252-253 | `[ASM]` | Velocity-loop gains — from the drive |
| `P.Kp_bz` | 254 | `[ASM]` | **Historical only.** The superseded position loop, kept so `PlcIoLatencyTest` can rebuild the pre-2026-09-08 axis. Not used by any normal run |
| `P.F_ax_max` | 146 | `[EST]` | Axis force limit |

`Sequence.xlsx` names no Janatics component for this axis. Confirm what it
physically is: pneumatic cylinder, electric actuator, or a manual stage.

### 4.6 Operator timings — the three `[PLH]` values

| Param | Line | Tag | Supply |
|---|---|---|---|
| `P.t_op_notice` | 181 | `[PLH]` | Operator reaction to notification, s. **+20% gives +0.60 s** |
| `P.t_engrave` | 182 | `[PLH]` | Manual engraving duration, s. **+20% gives +1.60 s** |
| `P.t_op_confirm` | 183 | `[PLH]` | Confirm-finish delay, s. **+20% gives +0.30 s** |
| `P.OP.t_laser_50` | 437 | `[PLH]` | **Laser time, 50 mm job, s: manual-input mode only** (added 2026-09-13). The console waits this long before asking for ENG DONE. 4.65 s is the user's choice. The only laser-on footage (`Wood Carving.mp4`) implies about ≥ 3.0 s, and the recorded dwells cannot bound it, because the engraver was not working when they were recorded. **Supply:** stopwatch the laser on → off at the cell, per job, **several engravings of each** (25 mm has never been recorded). *2026-09-15, the user: the laser time varies with the job, so it stays an assumption until a spread is recorded.* The automatic run does not read it |

These are the **only** time-based transitions in the model; everything else is
sensor-driven. `Sequence.xlsx` rows 27-29 are manual operator actions and give
no duration at all.

**Supply:** stopwatch over 5-10 real cycles. Report **mean and spread** — the
spread is what tells us whether cycle time is operator-limited. Together these
are 12.5 s of the modelled 33.84 s cycle, i.e. **37% of it is placeholder**.

### 4.7 Sensors, friction, contact

| Param | Line | Tag | Supply |
|---|---|---|---|
| `P.prox_rng` | 149 | `[EST]` | Proximity sensor sensing range — datasheet |
| `P.z_tol` | 150 | `[EST]` | Height sensor tolerance |
| `P.ext_tol` / `J.REED.repeat` | 151 / JD:142 | `[EST]` | Reed switch repeatability window |
| `P.mu_s`, `P.mu_k` | 58-59 | `[EST]` | Static / kinetic friction, workpiece on belt — **changes with wood**; a tilt test gives `mu_s` |
| `P.k_end`, `P.lam_end` | 115-116 | `[ASM]` | Cylinder end-stop stiffness / damping |
| `P.k_ct`, `P.lam_ct` | 117-118 | `[ASM]` | Rod/workpiece contact stiffness / damping |
| `P.k_stop`, `P.lam_stop` | 119-120 | `[ASM]` | Locating-stop stiffness / damping |
| `P.v_creep`, `P.v_eps` | 60, 110 | `[ASM]` | Friction regularisation — numerical, no measurement needed |

Contact stiffnesses are numerical softening parameters. They need real values
only if impact forces or bounce are to be trusted; they barely affect cycle
time.

### 4.8 Environment and solver — no measurement needed

`P.g`, `P.T_air`, `P.R_air`, `P.n_poly`, `P.P_atm`, `P.rho0`, `P.b_crit`
(37-43), `P.dt` (191), `P.t_max` (192), `P.t_timeout` (184).

**Room temperature measured 25 °C at the cell, 2026-09-10** (model 20 °C): −0.10 s machine time, air 6.41 → 6.32 NL. Recorded, not applied. **Applied 2026-09-13 (plan H8):**
`P.T_air` = 298.15 K `[MEAS]`. At the H7 baseline it moved machine time to S37
by −0.06 s (57.41 → 57.35 s) and air per cycle 9.57 → 9.43 NL. Standard constants and numerical settings. `P.T_air` and `P.P_atm` are worth
confirming if the cell is not near 20 C / sea level. `P.dt` is `[CAL]` and
justified in `NEXT_STEPS.md`.

---

## 5. What the real PLC data settled — and what it did not

Supplied 2026-08-24 in `PLC_Dashboard/` and `Final/`. The machine is a Siemens
S7, read over snap7 / OPC UA, every tag in DB59. All 121 tags are transcribed
mechanically into `PlcTagList.m` — the only file in this project holding
observed facts rather than assumptions.

### 5.1 Answered

| Question | Answer | Where it now lives |
|---|---|---|
| Is the workpiece wood? | **Yes.** YOLO class `wood_block`, 1002 photographs | confirmed |
| Is there more than one product? | **Yes, two: 25 mm and 50 mm** — separate PLC batch counters | `P.REAL.product_mm` |
| Must engraving stay a timer? | **No.** The PLC publishes `Engraving_Completed` | `P.REAL.engrave_has_done_signal` |
| How is supply pressure sensed? | Analog transducer with scaling and Low/High alarms. Live reading **4.315 bar** | `P.REAL.P_supply_bar` |
| How are the conveyors driven? | **Steppers under position control** — `Goto_Position`, `Set_Home`, encoder feedback, high/low speed profiles. Not free-running belts | `P.REAL.axis_position_controlled` |
| How is the part fed? | **5 magazine compartments** with Ok / Low / Empty inventory | `P.REAL.n_magazine` |
| Are there interlocks? | **Four**, plus E-Stop and a safety relay | `P.REAL.interlocks` |

### 5.2 Contradicted — the model is wrong, not the machine

| | Model | Machine |
|---|---|---|
| ~~Proximity sensors~~ | ~~4~~ | **AGREES since 2026-09-02** — all **10**, in the machine's numbering |
| ~~Solenoid valves~~ | ~~5 station + 4 branch~~ | **AGREES since 2026-09-02** — the command vector carries all **13** coils |
| ~~Pneumatic actuators~~ | ~~5 cylinders~~ | **AGREES since 2026-09-02** — the model carries all **11**: 5 magazine pushers, 2 transfers, cylinders A and B, 2 outfeed |
| ~~Valve type~~ | ~~5 single spring-return~~ | **AGREES since 2026-09-02** — CYL_A and CYL_B are double-solenoid and latch |
| Cylinder position feedback | `y.EXT`/`y.RET` from rod position | **none** — the PLC latches its own commands |
| Conveyors | 3 | 3 — agrees |
| Products | 1 | **2**, `PRODUCT_HEIGHT` 50 and 25 |
| Feed | implicit single point | **5 magazines**, one pusher each |
| Engrave completion | `t_engrave = 8.0 s` `[PLH]` | **a signal** |

The last five rows were added 2026-08-30 from the PLC program listing. They are
not new disagreements — they were always there; nothing had read the program.

`PlcIoTest/theModelStillDisagreesWithTheMachine` pins this. When the plant is
rebuilt, that test fails and must be updated to assert agreement.

### 5.3 The I/O mapping — closed in role, open in placement

> ~~**23 of the 63 mapped rows are `UNMAPPED`.** The tag list gives counts and
> names; it does **not** say which solenoid drives which cylinder, or where
> each of the 10 proximity sensors sits. The dashboard UI is a flat list with
> no station grouping, and the photographs have no calibration. Nothing
> supplied records the topology.~~
>
> **SUPERSEDED 2026-08-30.** True of everything *supplied* — but the PLC
> program itself had not been read. Decoding `plc/abc.pdf` and tracing the
> sequence networks mapped all 23. Kept because the reasoning was sound and
> the lesson is not: "nothing supplied records it" was a statement about the
> documents, and it was quietly treated as a statement about the machine.

**No row is `UNMAPPED` any more.** `FC3 solenoid_manual` names the coil behind
every solenoid address; `FC7 N2`/`N3` name the compartment behind proximity
sensors 1–5 and solenoids 1–5; `FC6 void_main` places 6–13 in the cycle. **Eight**
rows remain `PROVISIONAL`, and those are placement questions a ladder diagram
cannot answer.

It was still not guessed at any point. Guessing is how the `[JAN]` figures
became "provisional candidates repeated until they looked like facts", which
`JanaticsData.m` warns against in its own header. See where it stands:

```matlab
factory_io_map('report')
```

**What closes the remainder — a short walk at the machine:**

| # | Do this | Closes |
|---|---|---|
| 5.3.1 | Walk the cell with the address list; note where **prox 6, 8, 9 and 10** are bolted | 4 `PROVISIONAL` rows |
| 5.3.2 | Energise **`%Q0.2`, `%Q2.3`, `%Q0.1`, `%Q2.1`** one at a time from the manual-command page; note what each moves | the other 4 |
| 5.3.3 | Energise `%Q3.6` then `%Q2.5`; note which rod is cylinder A and which is B | question 3b |
| 5.3.4 | Measure the trip distance of one sensor against a real 100 × 100 mm block | `P.prox_rng` |

Both are recorded by editing **`factory_io_map.m` only** — one file, one table.

The plant topology can now be rebuilt against real addresses. What placement
still decides is *geometry* — where along each conveyor a sensor trips — not
which signal is which.

---

## 5A. Which file each input goes into

The single most common question. Every input has exactly one home.

| Input | Edit this file | Field |
|---|---|---|
| Cell scale | `FactoryParams.m` | `P.SCALE` |
| Workpiece size, density | `FactoryParams.m` | `P.blk_a`, `P.blk_rho` |
| Cylinder bore, rod, stroke, pressure rating | **`JanaticsData.m`** | `J.CYL.*` — never write manufacturer figures straight into `FactoryParams.m` |
| Valve and FRL conductances, spool time | **`JanaticsData.m`** | `J.VAL.*`, `J.FRL.*`, `J.C.*` |
| Regulator set pressure, needle settings | `FactoryParams.m` | `P.P_set`, `P.C_ctrl_A`, `P.C_ctrl_B` |
| Receiver volume, compressor delivery, switch settings | `FactoryParams.m` | `P.V_res`, `P.mdot_pump`, `P.P_cut_in/out` |
| Belt speed, ramp, pulley, gearbox, motor | `FactoryParams.m` | `P.v_belt`, `P.a_belt`, `P.r_pul`, `P.N_gear`, `P.J_mot`, `P.T_max` |
| Engraving axis stroke, mass, gains | `FactoryParams.m` | `P.z_top`, `P.m_base`, `P.t_base_travel`, `P.Ki_bz`, `P.Kd_bz` |
| Operator timings | `FactoryParams.m` | `P.t_op_notice`, `P.t_engrave`, `P.t_op_confirm` |
| PLC scan period and output latency | `FactoryParams.m` | `P.t_scan`, `P.plc_io_delay` |
| Sensor ranges and tolerances | `FactoryParams.m` | `P.prox_rng`, `P.z_tol`, `P.ext_tol` |
| Friction and contact stiffness | `FactoryParams.m` | `P.mu_s`, `P.mu_k`, `P.k_ct`, `P.k_stop` |
| **Which physical barrel is cylinder A / B** | **`factory_io_map.m`** | the `PROVISIONAL` solenoid rows |
| **Where each proximity sensor is bolted** | **`factory_io_map.m`** | the `PROVISIONAL` sensor rows |
| A new or changed PLC tag | **`plc/PLC_Tag_List.xlsx`**, then regenerate `PlcTagList.m` | never hand-edit the register |
| Observed machine facts (counts, live readings) | `FactoryParams.m` | `P.REAL.*`, tagged `[PLC]` |
| Sequence order or step meaning | `factory_states.m` + `factory_plc.m` | keep the two in step |
| Pinned expected results | `verify_model.m` **and** `tests/CycleRegressionTest.m` | **both**, or they disagree |

After any edit: `reset_factory`, then `run_all_tests`.

---

## 6. What happens when the inputs arrive

The model is built so this is a parameter edit, not a rewrite. In order:

1. **Enter the values.** Manufacturer figures go in `JanaticsData.m`; everything
   else in `FactoryParams.m`. Keep the provenance tag and change it to reflect
   the new source. Never write a manufacturer figure directly into
   `FactoryParams.m` — the chain is `JanaticsData.m -> FactoryParams.m -> physics`.
2. **Clear the cache.** `reset_factory` — or the Simulink path silently keeps
   the old numbers.
3. **Expect the pinned tests to fail.** `verify_model.m` and
   `tests/CycleRegressionTest.m` pin the Iteration-03 baseline. A failure there
   after a deliberate parameter change is a prompt to re-baseline, not a bug.
4. **Re-baseline both places.** The reference values live in **two** files.
   Update both and record the change in `ITERATION_LOG.md`.
5. **Re-run everything.** At the MATLAB prompt:
   ```matlab
   run_all_tests('IncludeSlow', true)
   ```
   Then, in a terminal (not the MATLAB prompt):
   ```bash
   python -m unittest discover -p "test_*.py"
   ```
6. **Confirm the two paths still agree.** `compare_execution_paths` must still
   report about zero divergence. If it does not, the scheduling contract has
   been disturbed, not the physics.

### If the workpiece becomes a true cuboid

Three distinct dimensions is a **code** change, not a parameter change:
`P.blk_a` is a single edge used by the mass, inertia, contact and support-region
calculations. Budget for edits to `FactoryParams.m`, `factory_derivatives.m`,
`support_region.m` and `visualize_factory.m`, plus a re-baseline.

---

## 7. Regenerate this register

The counts above are derived, not hand-maintained. Re-derive them after any
parameter edit:

At the MATLAB prompt:

```matlab
audit_provenance
```

To list every tagged parameter, not just the counts:

```matlab
audit_provenance('List', true)
```

To work with the result as data:

```matlab
T = audit_provenance;
T(strcmp(T.Tag, 'PLH'), :)
```

`audit_provenance` counts **assignment lines only**. That restriction is
load-bearing: a plain text search for the tags also matches the seven-line tag
legend in each file header and overcounts every tag.

---

## 8. See also

| File | Role |
|---|---|
| `../Project_Notes/NEXT_STEPS.md` | The same inputs ranked by **measured sensitivity** — read this to decide what to do first |
| `../Project_Notes/PHYSICS_FRAMEWORK.md` | Which governing equation consumes each input |
| `Physics_Framework.xlsx` | Fill-in workbook with live derived formulas |
| `Janatics_Component_Register.csv` | Per-component provenance, with the source columns still to be completed |
| `../Project_Notes/HANDOFF.md` | Session-to-session context |
| `README.md` | How to run the model these inputs feed |
