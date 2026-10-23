# Building the cell in NX MCD — plan, steps, and the numbers to type in

Written 2026-09-18, for a lab visit on **Monday 2026-09-21**. You build in NX
on the college PC; this file carries the numbers, the order of work, and the
resources. **The MATLAB model stays the physics of record.** NX MCD adds 3-D
motion, collision and a credible visual, and it is where you learn
virtual-commissioning tooling.

---

## 0. Before you touch NX (15 minutes, at the lab PC)

- [ ] **NX version and licence.** Help → About NX. Then the Application tab:
      is **Mechatronics Concept Designer** listed? It is a separate licence
      bundle. If it is greyed out, nothing below works, and that is the first
      thing to ask the lab for.
- [ ] **Copy the project to the PC**, do not work off a USB stick:
      `SIemens NX Work/BITS_MCD_project/` (moved there from the repository on 2026-09-19), 172 `.prt` files.
- [ ] **Open** `Engraving/Engraving_Process_07-01-26_Additional.prt`, the
      newest of the eight versions, and switch to the MCD application.
- [ ] **Write down what is already there**, from the Physics Navigator. A text
      scan of that file says roughly **2 rigid bodies, 2 collision bodies, 4
      sliding joints, 4 signal adapters, 17 signals**, and an OPC UA client
      pointed at `opc.tcp://172.21.30.157`, the cell's own PLC address. The
      signal names already include `Proximity_sensor1..10`, `Conveyor1..3`,
      `Solenoid_valve1..12`, `Engraving_Completed`, `Current_Position_Fb` and
      `MODE_HIGH_SPEED`.
- [ ] **Decide where to build.** Recommended: `Save As` a working copy,
      `Engraving_Process_2026-09-21_build.prt`, and build there so the
      original stays as a reference.

**What that inventory means.** The *signal* side of the earlier work is worth
keeping: those names match the real PLC tags, and MCD can map signals to an
OPC server automatically when the names match. The *mechanics* are one station
at best. The cell has **11 actuators, 3 conveyors and 10 sensors**, so most of
the building is ahead of you.

---

## 1. What you are building, in one paragraph

A block leaves a magazine, rides belt 1, is pushed onto belt 2, stops at
prox 7, and cylinder A pushes it into the engraver. The platform lifts it, the
operator engraves and presses ENG DONE, the platform lowers, cylinder B pushes
it to belt 3, belt 3 carries it to prox 9, and outfeed A ejects it into the
bin. A second product skips engraving: at prox 8, SV11 pushes it straight
across to belt 3.

In MCD that is **one rigid body** (the block), **three transport surfaces**
(the belts), **eleven sliding joints** (the rods) plus **one** for the
engraving platform, **ten collision sensors** (the proximity sensors), and
**signals named after the PLC's tags**.

---

## 2. The order of work, and why

MCD punishes building in the wrong order: a joint on a body that is not rigid
does nothing, and a sensor with no collision body never trips.

| # | Step | You can check it by |
|---|---|---|
| 1 | Rigid body: the block | Play — it falls |
| 2 | Collision bodies: block, belt tops, stops | Play — it lands and stays |
| 3 | Transport surfaces on the three belts | Play — it rides |
| 4 | Sliding joints for the 11 rods and the platform | Drag the joint in the navigator |
| 5 | Position control on each joint | Type a target, Play, watch it move |
| 6 | Collision sensors for the 10 proximity sensors | Play — the sensor trips as the block passes |
| 7 | Signals, named after the PLC tags | The Runtime Inspector shows them change |
| 8 | Signal adapters: sensor → signal, signal → actuator | A signal drives the rod |
| 9 | Sequence Editor: the cycle | The whole cycle runs by itself |
| 10 | External signals over OPC UA, later | MCD follows the PLC, or a replay server |

**Steps 1–3 are "basic physics", 4–5 are kinematics, 6–8 are automation, and 9
makes it run without a PLC.** Learn them in that order; the tutorials in §6 are
organised the same way.

---

## 3. The numbers to type in

All from the validated MATLAB model, dumped 2026-09-18. Positions are in the
model's plan view: origin at the magazine end, **x along belt 1, y across the
cell**. Use them as relative distances, since the NX geometry has its own
origin.

### 3.1 The workpiece and the belts

| Item | Value | Where it comes from |
|---|---|---|
| Block | 100 × 100 × 40 mm, **0.300 kg** | measured and weighed |
| Belt 1 speed | **210 mm/s** | PLC recordings, 4 cycles |
| Belt 2 speed | **310 mm/s** | tape on a manual run — being re-checked Monday |
| Belt 3 speed | **150 mm/s** | assumption, still unmeasured |
| Engraving platform | **50 mm** travel (measured ~45 mm); up 7.63 s, down 8.01 s | model and recorder |
| Proximity sensing range | **30 mm** | estimate |

The PLC's own conveyor setpoint reads **180 mm/s**, and the earlier MCD author
used 180 mm/s. Type the measured numbers above, and note the disagreement in
your report.

### 3.2 The eleven rods

**Stroke** is the barrel's nameplate stroke: use it as the sliding joint's
limit. **Travel** is how far the rod actually pushes in the cycle: use it as
the position-control target. **Speed** is what the model's pneumatics produce:
type it as the position-control speed.

| # | Name | Coils | Axis | Stroke (mm) | Travel (mm) | Speed (mm/s) | Other coordinate (mm) |
|---|---|---|---|---|---|---|---|
| 1 | MAG1_PUSH | SV1 | −y | 160 | 82 | 148 | x 160 |
| 2 | MAG2_PUSH | SV2 | −y | 160 | 82 | 148 | x 270 |
| 3 | MAG3_PUSH | SV3 | −y | 160 | 82 | 148 | x 380 |
| 4 | MAG4_PUSH | SV4 | −y | 160 | 82 | 148 | x 490 |
| 5 | MAG5_PUSH | SV5 | −y | 160 | 82 | 148 | x 600 |
| 6 | XFER_CV1_CV2 | SV6 | −y | 160 | 108 | 131 | x 792 |
| 7 | CYL_A, into the engraver | SV7 out, SV8 back | +x | 300 | 252 | 78 | y 590 |
| 8 | CYL_B, engraver → belt 3 | SV9 out, SV10 back | −y | 300 | 204 | 97 | x 1045 |
| 9 | MOVE_TO_CV3, the bypass | SV11 | +x | 160 | 118 | 146 | y 387 |
| 10 | OUTFEED_A, to the bin | SV12 | −y | 160 | 150 | 135 | x 1290 |
| 11 | OUTFEED_B | SV13 | −y | 160 | 150 | 135 | x 1410 |

SV7/SV8 and SV9/SV10 are **double-solenoid latching** valves: a coil at each
end, no spring. In MCD that is still **one** sliding joint. The two signals set
its target; they do not each get a joint.

### 3.3 The ten proximity sensors

Collision sensors, 30 mm range, at these positions:

| Sensor | x (mm) | y (mm) | What it watches |
|---|---|---|---|
| Proximity_sensor1–5 | 160, 270, 380, 490, 600 | 918 | each magazine dispense |
| Proximity_sensor6 | 792 | 918 | the end of belt 1 |
| Proximity_sensor7 | 792 | 590 | belt 2, the engraving stop |
| Proximity_sensor8 | 792 | 387 | belt 2, the bypass stop |
| Proximity_sensor9 | 1290 | 387 | belt 3, outfeed A |
| Proximity_sensor10 | 1410 | 387 | belt 3, outfeed B |

Belt centre lines: **belt 1 at y 918**, **belt 2 at x 792**, **belt 3 at
y 387**. The waypoints the block passes: load 160/1000, belt-1 end 792/918,
belt-2 stop 792/590, engraver 1045/590, belt-3 load 1045/387, outfeed
1290/387, bin 1290/237.

### 3.4 The cycle, for checking your build

Model times for the engraved route, from t = 0 at camera detect. Your MCD
cycle should land near these if you typed the same numbers.

| t (s) | What happens |
|---|---|
| 0.00 | the block is detected |
| 10.24 | SV1, magazine pusher out (the PLC's `T#10S` start delay) |
| 13.29 | belt 1 on |
| 16.44 | prox 6; belt 1 off |
| 18.58 | SV6 transfer push, and belt 2 on with it |
| 20.02 | prox 7; belt 2 off |
| 21.50 | SV7, cylinder A into the engraver |
| 29.56 | SV8, cylinder A back |
| 31.51 | the platform rises |
| 39.15 | the platform is at the top |
| 39.15–51.67 | the operator: notice, laser, ENG DONE (12.5 s, a placeholder) |
| 51.67 | the platform lowers |
| 59.69 | the platform is at the bottom |
| 59.87 | SV9, cylinder B pushes to belt 3 |
| 68.07 | SV10 back; belt 3 on |
| 69.72 | prox 9; belt 3 off |
| 69.85 | SV12, the outfeed pushes to the bin, held 5.02 s (the PLC's `T#5S`) |
| 75.64 | the cycle is complete |

The bypass route: belt 2 runs on to prox 8 (1.97 s), SV11 pushes across (held
2.00 s), belt 3 to prox 9, then the outfeed. Whole cycle **29.74 s**.

---

## 4. The weekend, session by session

Each session is self-contained, so stopping early still leaves something that
runs.

### Friday evening, 1 to 2 hours: get MCD moving
1. The checklist in §0.
2. Make the block a **rigid body**, give it and the belt tops **collision
   bodies**, Play, and watch it sit on the belt.
3. Add a **transport surface** to belt 1 at 210 mm/s. Play. The block rides.
4. Stop when that works. That is the whole of "basic physics"; everything
   after it is repetition.

### Saturday, 3 to 4 hours: station 1, end to end
1. **Sliding joints** for the five magazine pushers, limits 0–160 mm.
2. **Position control** on each: speed 148 mm/s, target 82 mm.
3. **Collision sensors** for prox 1–6, at the positions in §3.3.
4. **Signals**: `Solenoid_valve1..6`, `Conveyor1`, `Proximity_sensor1..6`,
   named exactly like that.
5. **Signal adapters**: each prox sensor → its signal; `Solenoid_valve1` →
   pusher 1's position target; `Conveyor1` → belt 1's transport surface speed.
6. Check against §3.4: pusher out at 10.24 s, belt 1 on at 13.29, prox 6 at
   16.44.

### Sunday, 3 to 4 hours: stations 2 and 3
1. Transport surfaces for belts 2 and 3, at 310 and 150 mm/s.
2. Sliding joints and position control for SV6, cylinder A, cylinder B, SV11,
   SV12 and SV13, from the table.
3. The **engraving platform**: a sliding joint in **+z**, 50 mm, rising in
   7.63 s (about 6.6 mm/s).
4. Collision sensors for prox 7–10.
5. The rest of the signals and adapters.
6. **Sequence Editor**: build the cycle from §3.4 and run it with no PLC at
   all. That is your demonstration.

### Monday at the lab
- The measurements on `LAB_VISIT_2026-09-16.md`. The visit moved to Monday;
  the sheet is otherwise unchanged.
- **Job 5 decides the live route:** is OPC UA switched on at the CPU? If it
  is, MCD's existing OPC UA client can point at the real PLC and the model
  follows the machine.
- If NX is on a lab PC, do §5 there while the cell is running.

---

## 5. Connecting it to something, later

Three ways, cheapest first.

1. **The Sequence Editor.** MCD drives itself. No PLC, no extra licence, works
   today. Use this for the report and the viva.
2. **A replay server.** I can write a small OPC UA server here that publishes
   the cell's tag names and plays back a validated MATLAB cycle. In NX you
   point the **existing** OPC UA client at it instead of the PLC, and MCD maps
   the signals automatically because the names already match. That gives 3-D
   motion driven by the calibrated physics, with no machine involved. **Say
   the word and I will build it before Monday.**
3. **The real PLC over OPC UA**, the same client pointed at
   `opc.tcp://172.21.30.157`, once OPC UA is enabled on the CPU. Blocked on
   job 5.

**A mapping tip worth knowing before you start:** MCD can map external signals
to MCD signals **automatically when the names match**. That is why every
signal you create should carry the PLC's own tag name — `Solenoid_valve7`, not
`CylA_out`.

---

## 6. The course to follow, and the rest of the resources

Checked 2026-09-18. **The FH Aachen link does not resolve** — not from here
either, so it is not just your browser. Use the Siemens material instead; it is
better suited to this project anyway, because it teaches MCD *with* a PLC.

### The one course: Siemens SCE learning packages

Siemens' own free teaching material, written for exactly this — a 3-D cell in
NX MCD driven by a real PLC program. The packages bundle **interactive videos,
theory documents and project files**.

**Link status checked from this machine on 2026-09-18** (`curl`, browser
user-agent). The support portal answers 403 to any automated tool; that is bot
protection, and the pages open normally in a browser. Downloads ask for a free
Siemens ID.

| What | Link | Checked |
|---|---|---|
| **Basic course: TIA factory automation with SIMIT and NX MCD** — the one to start with | <https://support.industry.siemens.com/cs/document/109816550/?lc=en-ww> | 403 to curl, browser only |
| … its direct download | <https://support.industry.siemens.com/cs/attachments/109816550/lp-sce-fa-basic-course-simit-mcd-lm-17-en.zip> | 403 to curl, browser only |
| **Advanced course: Digital Twin** — virtual commissioning, the next step | <https://support.industry.siemens.com/cs/document/109816686/?lc=en-WW> | 403 to curl, browser only |
| The SCE catalogue page these come from | <https://www.siemens.com/global/en/company/sustainability/education/sce/learning-training-documents/digital-twin.html> | **200 OK** |
| SCE guide to the whole library (3.8 MB PDF) | <https://assets.new.siemens.com/siemens/assets/api/uuid:c718963e-8c5a-4eab-8aa5-43e0a505af32/sce-guide-learn-training-guide-en.pdf> | **200 OK, downloads** |

**The old `sce-150-00x` PDFs are gone.** The
`automation.siemens.com/sce-static/...` links that search engines still show
return a genuine **404** — Siemens moved this material into the packages above.
Don't chase them.

**If a package asks for a login you don't have:** the catalogue page and the
SCE guide are open, and the videos below cover the same ground.

### Short videos, when you want to see a command done

1. **Basic physics** (rigid body, collision body, transport surface):
   <https://www.youtube.com/watch?v=KIx1exS6arw>
2. **Joints**: <https://www.youtube.com/watch?v=UeqBTeIFAoM>
3. **Signals and connections**: <https://www.youtube.com/watch?v=cv2Yjcx4lEk>
4. **A whole conveyor and pick-and-place cell**, the closest to this one:
   <https://www.youtube.com/watch?v=x3ncDZdelRY>
5. **Siemens' own MCD tips**:
   <https://blogs.sw.siemens.com/nx-design/nx-tips-and-tricks-mechatronics-concept-designer/>

### If you want a formal, certificated course

Siemens Xcelerator Academy runs MCD courses for beginners and for users. They
are paid, and the college may already have access:
<https://training.plm.automation.siemens.com/ilt/iltdescription.cfm?pID=DE-TR-PES2-10_NX___1926.0_B9>

### Reference, when you are stuck

- Siemens community group, NX MCD:
  <https://community.sw.siemens.com/s/topic/0TO4O000000MkeDWAS/nx-mechatronics-concept-designer>
- OPC signal mapping, from an older NX help mirror:
  <http://www2.me.rochester.edu/courses/ME204/nx_help/en_US/tdocExt/content/8/xid461708.xml>
- MCD Player, to show the model to someone with no NX:
  <https://community.sw.siemens.com/s/article/mechatronics-concept-designer-mcd-player>

**For the report**, a peer-reviewed paper doing exactly this — a sorting cell
as a digital twin in NX MCD:
<https://mfr.edp-open.org/articles/mfreview/full_html/2024/01/mfreview240009/mfreview240009.html>

### Practising at home

**NX Student Edition** is a free single-user download, but it is a CAD/CAM
licence and **nothing I found says MCD is included** — expect it not to be.
Treat the college PC as the only place the build happens, and check the
student edition only if you want CAD practice:
<https://blogs.sw.siemens.com/designcenter/nx-student-edition-free-download/>

---

## 7. What to write down as you go

For the report, and so the next session can pick it up:

- which NX version and which MCD licence the lab PC has;
- for every MCD object you create, the number you typed and where it came from
  — this file, or your own measurement;
- anything MCD would not let you do, and the message it gave;
- a screen recording of the finished cycle. It is the deliverable a viva
  actually sees.

**The rule that has served this project:** if you had to guess a number, mark
it as a guess in your notes. Do not let it become a fact by being typed twice.
