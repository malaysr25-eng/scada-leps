# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

One interface shared by several roles on a laboratory laser-engraving cell (Siemens S7-1200, DB59):

- **Operators running cycles.** They place orders, start the automatic sequence, watch progress, and recover from faults. **When needs conflict, this role wins.** The run → monitor → recover loop comes first.
- **Students in lab sessions.** They learn SCADA, PLC and digital-twin concepts on a real cell, under supervision.
- **Instructors and lab engineers.** They commission and debug the cell: tag verification, fault diagnosis, checking the twin against the hardware, recording cycles.

There is **no separate teaching mode**. Explanation is kept to short labels and reasons (why a command was refused, why an interlock blocked Start). It never appears as paragraphs in operating panels. Long-form explanation belongs in `docs/` and the Assistant.

## Product Purpose

Cell Control is a **teaching platform** for automation and Industry 4.0 work, built on a real production-style cell. It replaces three legacy programs (SCADA Hub, PLC Dashboard, a JSON-writer script) with one application: one PLC connection, one machine state, one interface. That interface covers SCADA monitoring, gated manual control, sequence tracking, diagnostics, history/recording, and a digital twin (2-D schematic plus 3-D model).

Success: the cell can be run, taught on, and debugged from one screen whose readings can be trusted. A value shown is a value the PLC confirmed, and an unknown is shown as unknown.

## Positioning

An honest HMI. The legacy system showed false success: an E-Stop button that 404'd into `{success: true}`, valve 5's activity labelled as valve 8, writes "confirmed" by patching the cache. This platform is built so the screen cannot lie:

- writes go `PENDING → WRITTEN → CONFIRMED` (or `MISMATCH` with a reason), confirmed only by a later, independent read;
- live, estimated, simulated and stale data are always told apart;
- no address is ever invented, and missing tags mean missing features rather than guessed ones.

For teaching, that honesty is the lesson. The screen itself stays clean, professional and terse.

## Operating Context

- **Lab PC beside the machine.** Desktop monitor, mouse and keyboard. The operator glances between screen and cell.
- **Remote on the trusted lab network.** Laptops or office PCs. There is no authentication, so it must never be exposed beyond that network.
- **Projected or large display.** Demos and classes, read by a group from a distance.
- **Simulation mode** (`run.py --simulate`, plus scripted faults such as `valve8_chatter` and `conveyor2_stall`). Used for teaching and testing with no hardware. The UI labels it `SIMULATED` throughout.
- Lab visits follow a measurement route on paper: `Engraving_Cell_Intake_Sheet*.docx`. Readings are in millimetres.
- MATLAB / Siemens NX MCD feed the digital twin as read-only reference sources.

## Capabilities and Constraints

- Must stay as they are (2026-10-21): the Tags page, Machine 3D, the live sensor feed and the SOFTWARE STOP control.
- Pages: Overview, Manual Control, Sequence, Diagnostics, Digital Twin (2-D schematic), Machine 3D / Factory Twin, Tags (explorer), History, Data (SQL/recording), Assistant.
- Stack: Flask backend (only `flask` and `python-snap7`, so it installs offline), SQLite history, SSE stream. React 18 + TypeScript + Vite + Tailwind frontend, prebuilt `dist/` served by Flask, three.js twin code-split.
- **One Snap7 client.** No HTTP request reads the PLC. Everything serves one cached snapshot per poll.
- **`null` is not `false`.** An unknown signal renders `N/A`, never OFF.
- **The UI never freezes.** On link loss the last values are kept and marked stale.
- **Safety boundary.** The app provides no functional safety. The red control is a **SOFTWARE STOP** (it clears `CMD_START`). The hardware E-Stop *status* is shown beside it, read-only. Every safety rule is enforced server-side. Manual writes are gated by access class and machine mode.
- **The help assistant cannot operate the machine.** This is structural: it holds no write path, only read-only, redacted context.
- **A second assistant exists.** The Assistant page's chat (`AssistantChat`) is a client for the separate *cellchat* service (`predictive_maintenance/cellchat/web.py`, port 5052, lab-PC only). It **can** write to the cell after operator confirmation. Its source is not in this repo. Keep the two assistants distinct in labels and copy.
- **Conveyor speed** (`Set_Velocity`, High/Low profiles, `Set_HighSpeed`) is writable in MANUAL and MAINTENANCE, with confirmation and range checks. On the real cell a confirmed `Set_Velocity` write did not change belt speed (2026-10-21). The PLC holds the value, but whether FC6 feeds it to the stepper TO's `MC_Move*` Velocity input is unconfirmed, and that input is only latched at the start of a move.
- **Not implemented, deliberately:** engraving-platform jog. It is wanted, but deferred until the DB1 Axis_1 addresses (`en_mc_power`, `exe_jogforward`/`backward`, `exe_jogvelocity`, limit switches) are exported from TIA Portal and cylinder position (no reed-switch tag exists). DB59 bytes 266–269 are `raw.*` UNDOCUMENTED tags, read-only and never used to drive an indicator.
- Open: velocity unit scaling on the real drive (DIVERGENT twin comparisons); commissioned velocity limits; four PROVISIONAL solenoid roles awaiting physical confirmation.

## Brand Commitments

- Name: **Cell Control**. No institutional or lab branding is required.
- Voice (from the existing docs): plain, exact, evidence-first. It says what is not known rather than guessing. Labels state literal truth (`SOFTWARE STOP`, `SIMULATED`, `N/A`, `UNDOCUMENTED`).

## Evidence on Hand

- Engineering docs in `docs/` (architecture audit, debugging report E-01–E-20, tag map, twin mapping, test checklist) and dated handoffs `HANDOFF_2026-09-23.md` and `HANDOFF_2026-09-25.md`.
- Reference photographs of the real cell: `Reference_Images/` and `../Reference_images/`.
- Intake sheets: `Engraving_Cell_Intake_Sheet.docx` and `_PREFILLED.docx`.
- 203 automated checks (`tools/selftest.py`, `selftest_extended.py`, `check_twin_layout.py`).
- No user testimonials, usage metrics, or course outcomes exist. Do not fabricate them.

## Product Principles

1. **Never show a reading the system cannot back.** Confirmed, pending, stale, estimated, simulated and unknown are different states and must look different.
2. **The operating loop comes first.** Run, monitor and recover must stay fast and unobstructed. Explanation is one step away, never in the way.
3. **Terse and professional.** Every element must earn its place. Use a one-line reason instead of a paragraph and a label instead of a subtitle. No explanatory text boxes on operating pages.
4. **Safety is stated, not implied.** Never suggest that a software control is a safety function.
5. **Keep the evidence.** Link loss, faults and history are preserved and readable, because an operator or student diagnosing a problem needs them.

## Accessibility & Inclusion

- Colour is never the only channel. Every state carries a text label and usually an icon (an existing design rule).
- Critical state (mode, connection, stop/E-Stop status, active faults) must stay readable on a projected display from across a room, as well as on a desktop monitor.
