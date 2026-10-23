# Today — Monday 21 September 2026, at the lab

**Two jobs, in this order:**
- **A. the cell and the SCADA PC**, because the recording can't be done any
  other day;
- **B. the first NX session** on the lab PC.

Everything you need is in this folder, and everything you bring back goes into
`COLLECT_TODAY/`.

---

## 0. Before you leave home (5 minutes)
- [ ] Copy this whole folder (`SIemens NX Work/`, about 100 MB) to the USB
      stick.
- [ ] Phone charged, with a stopwatch that does laps. Tape measure, torch, pen,
      and a spare 100 × 100 mm block.

## A. At the cell and the SCADA PC — do this first

**1. Start the recording (15 minutes).** On the SCADA PC:
1. Copy `Lab_Visit_2026-09-21/to_scada_pc_round4/` onto it.
2. Open Claude in that folder and paste the block from `PROMPT.txt`.
3. Check the dashboard: **not** `SIMULATED`, and pressure **about 4.3 bar**
   (exactly 6.2 bar means the simulator).
4. Start a **wide recording**: all tags, 0.1 s.
5. **Set a phone alarm for 55 minutes.** A recording stops after an hour.

**2. The lab jobs,** in the order of `Lab_Visit_2026-09-21/LAB_SHEET_2026-09-21.md`
§3. The printable version is the `.html` beside it.
- **Job 1 first — prox 7.**
  - Watch its LED as the block passes in an automatic cycle.
  - Note where along the belt the block is when the LED lights. A video
    settles it.
  - Then, in TIA Portal (read-only), open FC6. Read step 16, what commands
    SV7 and SV11, `engraving_power`, the `T#10S` and the product selection,
    plus D1–D3.
- **Jobs 5 and 5a** whenever the maintainer is free:
  - is OPC UA on at the CPU?
  - which valve drives which SV — and count the valves.
- **Job 2, if the engraver works:**
  - 5 or more engraved cycles;
  - the laser on → off timed 3 or more times **per job**, with the job
    written beside each time.
- **Job 3:** one bypass cycle, and write down which HMI setting selected it.
- **Job 4:** the compartment-4 dispense.
- **Job 4a:** belt 3, timed 3 times, and belt 2 **once in an automatic cycle**.

**3. Before you leave the SCADA PC.** Claude's step 5 packages the outbox. Copy
it into `COLLECT_TODAY/scada_outbox/`.

## B. At the lab PC with NX — then

**1. The four questions.** Write the answers in `COLLECT_TODAY/LAB_PC_FACTS.md`:
- MCD licence?
- Can Python run?
- Is port 4840 open on the network?
- Is PLCSIM Advanced installed?

**If there is no MCD licence, stop here and tell whoever runs the lab today.**
Everything else waits on it.

**2. Session S1** (full steps in
`Projects Notes/NX_LEARNING_AND_BUILD_PLAN.md`, week 1):
1. Copy `BITS_MCD_project/` to the PC's **local disk** — not the USB stick.
2. Open `Engraving/Engraving_Process_07-01-26_Additional.prt` and switch to
   MCD.
3. Fill in `COLLECT_TODAY/MCD_INVENTORY.md`: what the Physics Navigator already
   holds. Screenshot it into `COLLECT_TODAY/nx_screenshots/`.
4. `Save As` → `Engraving_Process_2026-09-21_build.prt`.
5. **Measure in the CAD** — belt 1 length, load → prox 6, and prox 7 → prox 8
   — into `MCD_INVENTORY.md`.
6. Make the block a **rigid body** (0.300 kg) with a **box collision body**.
   Give the belt tops collision bodies. Play.

   **Done when** the block rests on belt 1. Don't make the belts or the frame
   rigid bodies: they'd fall.

**3. If there's time: session S2.** Transport surfaces — belt 1 at 210 mm/s,
belt 2 at 310, belt 3 at 150. Load → prox 6 should take about 3.0 s.

**4. At the end, save your build copy** to `COLLECT_TODAY/nx_build/` on the USB
stick. The lab PC may be shared or wiped.

**5. Write one line** in `COLLECT_TODAY/BUILD_LOG.md`.

**Optional: run the MATLAB model at the lab PC,** if it has MATLAB. Open
MATLAB in `MATLAB_model_snapshot_2026-09-21/` and follow its
`SNAPSHOT_README.txt`. It is a copy for reading and running; don't edit it
there.

## C. Before you leave — tick everything

- [ ] **SCADA PC:** the outbox — db copy with its `-wal`,
      `cell_timings_2026-09-21.json`, and the filled `LAB_HOUR_LOG.md`.
- [ ] **Cell:** the lab sheet's tables, filled in or photographed:
      - laser times per job;
      - the bypass HMI setting;
      - belt timings;
      - the valve table;
      - where prox 7's LED lit.
- [ ] **TIA:** screenshots of FC6 around step 16, the OPC UA setting and the
      scan time.
- [ ] **Lab PC:** `LAB_PC_FACTS.md` and `MCD_INVENTORY.md` filled in, the NX
      screenshots, and your `.prt` build copy in `nx_build/`.
- [ ] **Photos and videos,** copied into `COLLECT_TODAY/` — not only sent in
      chat.

**Rules at the machine** are in the lab sheet §1:
- read-only on every computer;
- never type a password;
- latching valves need their retract;
- don't touch the needle valves;
- follow the lab's laser rules;
- manual tests go after the automatic cycles.
