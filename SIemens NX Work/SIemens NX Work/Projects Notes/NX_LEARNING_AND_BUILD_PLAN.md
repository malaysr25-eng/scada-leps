# Learning NX MCD and building the twin — 19 September to the first week of November

Written 2026-09-19. **Seven weeks, finishing by Friday 6 November 2026.**

- **Your starting point:** basic NX CAD, no MCD.
- **Your time:** more in **weeks 1–3** — this plan assumes about **4 NX
  sessions a week** there, with the core ones marked ★ so that 3 a week still
  works — then 1–2 a week. NX is only on the college PC.
- **Front-loaded on purpose** (revised 2026-09-19): both milestones now land by
  **11 October**, leaving four lighter weeks as buffer for when you are busier.
- **The detailed build steps and every number to type in** are in
  `NX_MCD_BUILD_PLAN.md`, beside this file. This plan says *when* to do each
  part and *what to learn first*.

---

## What "finished" means in November

1. **The MCD model runs the whole cell by itself:** the engraved route (75.65 s)
   and the bypass (29.74 s), with every rod, belt, the platform and all ten
   sensors.
2. **It is checked against the MATLAB model.** MCD's sensor trip times sit beside
   the model's in a table, and each difference is explained.
3. **It runs over OPC UA**, driven by the replay server (`Tests & Claude
   Files/mcd_replay_server.py`). If OPC UA gets switched on at the PLC, it also
   runs from the real machine.
4. **A screen recording** of both routes, and a report chapter.

Items 1, 2 and 4 depend only on you and NX. Item 3's live-PLC half depends on
the lab (job 5 on the lab sheet), so the plan does not wait for it.

**This is your WILP project**, so check its calendar for review or submission
dates before 6 November. From **4 October** you can show MCD running both
routes by itself; from **11 October**, the OPC UA run and the validation
table as well. Both are complete, showable states.

---

## The software, and why each one is on the list

| Software | Why the twin needs it | How deep | Where |
|---|---|---|---|
| **NX MCD** | The twin itself | **Deep** — most of the seven weeks | College PC |
| NX CAD (assemblies) | Placing and constraining parts before MCD can use them | Refresh only | College PC |
| **OPC UA** (the concept) | How MCD talks to the replay server, or the PLC | Understand the ideas: server, client, nodes, mapping | Home |
| **UaExpert** (a free OPC UA client from Unified Automation) | To *look inside* an OPC UA server before trusting MCD's view of it | Enough to browse and watch values | Laptop (free registration) |
| **TIA Portal** | Reading the cell's PLC program (lab job 1) and checking whether OPC UA is enabled (job 5) | Read-only: open blocks, read networks, find tags | Lab PC |
| Python | Running the replay server | Run one command | Laptop |
| **PLCSIM Advanced** (stretch) | Running the *real PLC program* against your model, without the machine | Only if a licence is available | College PC |
| MATLAB | The physics of record; re-exports timelines after a model change | You already know it | Laptop |

**UaExpert** is worth having before week 5. When MCD shows nothing, it tells
you whether the fault is in the server or in MCD's mapping.

---

## The plan, week by week

Each NX session is about 2–3 hours. **Every session ends with something that
runs**, so a missed session costs one step, not the plan. ★ = core: if a week
gives you only three sessions, do the ★ ones and fold the fourth into the next
week.

### Weekend, 19–20 September — prepare, and try OPC UA already (no NX)
- Read `NX_MCD_BUILD_PLAN.md` §0–§3 (40 min): the order of work and the numbers.
- Watch **basic physics** and **joints** (videos 1–2 in §Resources).
- Register a free Siemens ID; download the SCE basic course with NX MCD
  (109816550) in a browser.
- **OPC UA, hands on (1 h):**
  1. install UaExpert on the laptop;
  2. run `python mcd_replay_server.py` in `Tests & Claude Files/`;
  3. connect UaExpert to `opc.tcp://127.0.0.1:4840/bits-mcd/`, and watch
     `Conveyor1` and `Solenoid_valve1` switch.

  You'll have seen the whole OPC UA idea before NX is involved.

### Week 1, 21–27 September — lab visit, then station 1 (4 sessions)
**Mon 21, the lab visit.** Do the lab sheet, and ask whoever runs the college
PC four questions. Each one removes a risk before it can cost a week:
1. Does its NX have the **MCD licence**? If not, escalate that day.
2. Can Python run on it? That decides where the replay server runs.
3. Is it on the same network as your laptop, with port 4840 open?
4. Is PLCSIM Advanced installed? This only matters for the week 5 stretch.

**S1 ★ — open, take stock, first physics**
- Check the licence. Copy `SIemens NX Work/BITS_MCD_project/` to the PC's disk and open
  `Engraving/Engraving_Process_07-01-26_Additional.prt` in MCD.
- Write down what the Physics Navigator already holds. A scan of the file says
  about 2 rigid bodies, 2 collision bodies, 4 sliding joints, 4 signal
  adapters and 17 signals.
- `Save As` your build copy.
- **CAD refresh, 15 minutes.**
  - In the Assembly Navigator, show and hide parts.
  - *Measure* the belt 1 length, belt 1 to prox 6, and prox 7 to prox 8.
  - Compare them with the plan's numbers (§3.3). Write down every difference:
    the CAD and the tape may disagree.
- Make the block a **rigid body** (0.300 kg) with a **box collision body**.
  Give the belt tops collision bodies. Play.
- **Done when:** the block rests on belt 1 without sinking or bouncing.
- **Watch out:** don't make the belts or the frame rigid bodies. Anything rigid
  falls under gravity.

**S2 ★ — three belts carry the block**
- Add **transport surfaces**:
  - belt 1: 210 mm/s, +x;
  - belt 2: 310 mm/s, −y;
  - belt 3: 150 mm/s, +x.
- Make the end stops static collision bodies.
- Put a block on each belt and Play.
- **Check:** from load (x 160) to prox 6 (x 792) is 632 mm, so about
  **3.0 s** at 210 mm/s. The model's belt-1 run, including the start, is
  3.15 s.
- **Watch out:** get the transport-surface direction vector right, and use
  mm/s.

**S3 ★ — the five magazine pushers**
- Five rods as rigid bodies. Give each:
  - a **sliding joint**: axis −y, limits 0–160 mm;
  - a **position control**: 148 mm/s, target 82 mm.
- Change the targets in the Runtime Inspector and watch each rod push a block
  onto belt 1.
- **Done when:** each pusher extends 82 mm in about 0.55 s.
- **Watch out:** give only the rod *tip* a collision body, not the whole
  barrel, or the rod collides with its own barrel.

**S4 — station 1's sensors and signals**
- **Collision sensors** for prox 1–6 at the §3.3 positions, sized to reach
  30 mm into the block's path.
- **Signals**, named exactly as the PLC tags: `Solenoid_valve1..6`,
  `Conveyor1..3`, `Proximity_sensor1..6`.
- **Signal adapters:**
  - each sensor → its `Proximity_sensorN`;
  - `Solenoid_valveN` → the pusher's target (82 when on, 0 when off);
  - `ConveyorN` → the belt's transport-surface speed (its speed when on, 0 when
    off).

  MCD's formula editor has an if/else form; check its syntax in the dialog.
- Drive it by hand in the Runtime Inspector: `Solenoid_valve1` on → block out →
  `Conveyor1` on → `Proximity_sensor6` goes true → `Conveyor1` off.

**Home, week 1:**
- the SCE basic course, its MCD theory;
- video 3, signals and connections;
- OPC UA concepts, one hour: server, client, namespace, node, subscription;
- start the build log.

✅ **Checkpoint:** station 1 runs from its signals.

### Week 2, 28 September – 4 October — stations 2 and 3 (4 sessions)

**S5 ★ — transfer and belt 2**
- **SV6 transfer:** −y, limits 0–160, target 108 mm, 131 mm/s. It pushes from
  belt 1's end onto belt 2.
- Belt 2 carries the block to **prox 7** (x 792, y 590).
- **Check:** conveyor 2 on → prox 7 is **1.31 s** in the model.

**S6 ★ — cylinder A and the engraving platform**
- **Cylinder A:** +x, limits 0–300, target 252 mm, 78 mm/s (about 3.2 s). It
  pushes the block from the belt-2 stop into the engraver (x 1045, y 590).
- **Platform:** a rigid body with a sliding joint in **+z**, 0–50 mm. It rises
  in 7.63 s (≈ 6.6 mm/s) and lowers in 8.01 s (≈ 6.2 mm/s), and the block rides
  it.
- **Watch out:** the platform needs a collision body the block can rest on.
  Check the block doesn't slide off while the platform moves.

**S7 ★ — cylinder B, belt 3, the outfeeds and the bypass**
- **Cylinder B:** −y, target 204 mm, 97 mm/s. It pushes the block from the
  engraver to belt 3's load point (x 1045, y 387).
- Belt 3 carries the block to **prox 9** (x 1290).
- **Outfeed A:** −y, 150 mm, 135 mm/s, into the bin (y 237). **Outfeed B**
  sits at x 1410.
- **SV11 bypass:** +x, 118 mm, 146 mm/s, from the belt-2 bypass stop (prox 8,
  x 792, y 387) onto belt 3.
- Collision sensors for prox 7–10.

**S8 — every signal, and a walk through the cell by hand**
- Add the remaining signals: `Solenoid_valve7..13`, `Proximity_sensor7..10`,
  `Engraving_Completed`.
- Add one MCD-only signal for the platform, e.g. `Platform_Up`. It is not a PLC
  tag: the real PLC moves the platform through an axis.
- **Cylinder A's target:** 252 while `Solenoid_valve7` is on, 0 otherwise.
  - That is enough for now, because the replay keeps SV7 on for the whole
    extend.
  - The real PLC pulses SV7/SV8 for 2 s, which needs a latch. That is the
    week 5 stretch.
  - Treat cylinder B (SV9/SV10) the same way.
- Walk one block through the whole cell by switching signals by hand.

**Home, week 2:**
- **TIA Portal theory** (the SCE TIA course): what an FC, a network and a tag
  are. It makes lab job 1 and PLCSIM readable.
- Video 4, a whole conveyor cell.
- Read the Manufacturing Review paper, for the report.

✅ **Checkpoint:** every station moves by its own signals, and one block goes
end to end by hand.

### Week 3, 5–11 October — the cycle by itself, then over OPC UA (4 sessions)

**S9 ★ — the Sequence Editor, engraved route**
- Build it the way the PLC runs, **event-driven**: each step waits for a
  sensor. For example, when `Proximity_sensor6` is true, `Conveyor1` goes off
  and `Solenoid_valve6` and `Conveyor2` go on.
- Use fixed times only where the PLC uses timers:
  - the 10 s start;
  - the 1.46 s wait before SV7;
  - the operator dwell (12.5 s, a placeholder);
  - SV12's 5 s;
  - SV11's 2 s.
- Play, then compare against §3.4 of the build plan.

**S10 ★ — the bypass, and the first recording**
- Add the bypass route in the Sequence Editor.
- Record both routes.

🟧 **Milestone 1** (was week 4): MCD runs both routes by itself.

**S11 ★ — over OPC UA**
- Switch the Sequence Editor's operations off, in a copy of the part, so the
  signals drive the cell.
- **External Signal Configuration → OPC UA**: add the replay server's
  endpoint. Run the server on the PC if Python runs there; otherwise on the
  laptop with `--host 0.0.0.0`.
- Map by name. Start the server and watch MCD run the model's cycle.

**S12 — the sensor check, and validation table v1**
- Let MCD write `Proximity_sensor1..10` back to the server.
- Run a full cycle and read the server's **sensor check**.
- Put MCD and the model side by side in a table. Explain every difference over
  about 0.3 s.

🟧 **Milestone 2** (was week 5): MCD driven over OPC UA, with a validation
table.

**Home, week 3:**
- the SCE advanced course, Digital Twin (virtual commissioning);
- draft the report's "what MCD models" and "method" sections.

### Week 4, 12–18 October — fix and record (1–2 sessions)
- **S13:** fix the biggest mismatches from the sensor check.
- **S14:** second recordings of both routes.
- **Home:** the report outline, and the validation table written up.

### Week 5, 19–25 October — the stretch (1–2 sessions)
**S15**, whichever the lab allows:
- **the live PLC** at `opc.tcp://172.21.30.157`, if OPC UA is on — read-only,
  with the maintainer present;
- **PLCSIM Advanced**, if it is licensed;
- **a latch for SV7/SV8 and SV9/SV10**, so MCD also follows the real PLC's 2 s
  pulses.

If none of them is possible, polish. Nothing is lost.

### Week 6, 26 October – 1 November — the evidence (1–2 sessions)
- **S16:** final recordings and screenshots.
- **Home:** the report chapter. Structure: what MCD models, what the MATLAB
  model models, the validation table, and what is still assumed.

### Finish week, 2–6 November — buffer and viva
- **S17–S18:** fixes only. Nothing new.
- Viva preparation. Where the cause isn't known — 180 vs 210 mm/s — saying so
  is the right answer.
- ✅ **Done by Friday 6 November.**

---

## Checkpoints, with numbers

Model times from camera detect, for the MCD build to land near. The complete
table is in `NX_MCD_BUILD_PLAN.md` §3.4, and the replay server prints the
sensor comparison for you.

| Check | Model | Week |
|---|---|---|
| SV1 pusher out | 10.24 s | 1 |
| prox 6 trips; belt 1 stops | 16.43 / 16.44 s | 1 |
| prox 7 trips | 19.90 s (belt 2 stops at 20.02 s, when S16 checks it) | 2–3 |
| platform at top | 39.15 s | 3 |
| `Engraving_Completed` | 50.17 s | 3 |
| prox 9 trips | 69.72 s | 3 |
| cycle complete | 75.65 s engraved, 29.74 s bypass | 3 |

---

## What can stop the plan, and what to do

| Risk | Sign | Do |
|---|---|---|
| **No MCD licence** on the college PC | MCD is greyed out in the Application tab | Asked on Mon 21 September (week 1's four questions). Without it there is no NX twin |
| **Python not allowed** on the college PC | install blocked | Run the server on your laptop with `--host 0.0.0.0`, on the same network as the PC |
| **Firewall** between laptop and PC | MCD cannot connect | Test with UaExpert from the PC first; ask the lab to allow port 4840 |
| **The imported CAD fights MCD** (CREO → NX parts) | bodies fall through, or joints jam | Use simple collision shapes (box, cylinder), not the full meshes |
| **A missed week** | — | Each week ends runnable, and weeks 4–6 are buffer. Drop week 5's stretch first |
| **OPC UA never enabled at the PLC** | job 5's answer is no | The replay covers it. Say so plainly in the report |

---

## Resources, in the order this plan uses them

All checked on 2026-09-18/19.
- **"403 in a browser?"** Siemens' support portal answers 403 to automated
  tools, not to people; it opens normally in a browser with a free Siemens ID.

| When | Resource | Link |
|---|---|---|
| Weekend | Video · basic physics | <https://www.youtube.com/watch?v=KIx1exS6arw> |
| Weekend | Video · joints | <https://www.youtube.com/watch?v=UeqBTeIFAoM> |
| Week 1 | Video · signals and connections | <https://www.youtube.com/watch?v=cv2Yjcx4lEk> |
| Week 1 | SCE basic course · TIA factory automation with SIMIT **and NX MCD** | <https://support.industry.siemens.com/cs/document/109816550/?lc=en-ww> |
| Week 2 | SCE basic course · TIA factory automation with SIMIT (the TIA side) | <https://support.industry.siemens.com/cs/document/109813980/?lc=en-ww> |
| Week 2 | Video · a whole conveyor and pick-and-place cell | <https://www.youtube.com/watch?v=x3ncDZdelRY> |
| Any | Siemens' MCD tips | <https://blogs.sw.siemens.com/nx-design/nx-tips-and-tricks-mechatronics-concept-designer/> |
| Week 3 | SCE advanced course · Digital Twin | <https://support.industry.siemens.com/cs/document/109816686/?lc=en-WW> |
| Week 3 | The SCE catalogue, and its guide to the whole library | <https://www.siemens.com/global/en/company/sustainability/education/sce/learning-training-documents/digital-twin.html> |
| When stuck | Siemens community group, NX MCD | <https://community.sw.siemens.com/s/topic/0TO4O000000MkeDWAS/nx-mechatronics-concept-designer> |
| Report | A sorting-cell digital twin in NX MCD (Manufacturing Review, 2024) | <https://mfr.edp-open.org/articles/mfreview/full_html/2024/01/mfreview240009/mfreview240009.html> |

**UaExpert** is not linked here because I have not checked its download page
from this machine. Search "UaExpert Unified Automation" and download it from
their own site.

---

## Keep a build log

One line per session, in this folder: the date, what you built, the numbers you
typed (and where they came from), what failed and the message it gave. It turns
straight into the report chapter, and it is what the next session picks up
from.
