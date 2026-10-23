# Cell Control — Unified SCADA, Manual Control & Digital Twin

One application replacing the separate SCADA Hub and PLC Dashboard for the
S7-1200 laboratory cell. One PLC connection, one machine state, one interface.

```bash
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe run.py --simulate      # no hardware needed
```

→ http://127.0.0.1:5000

Drop `--simulate` to talk to the real PLC (set the address in
`config/config.json` first).

### Windows launchers (any PC)

Double-click in this folder:

| Script | What it does |
|--------|--------------|
| `setup.bat` | One-time: builds `.venv` and installs requirements. Rebuilds a `.venv` copied from another PC. |
| `start_dashboard.bat` | Asks for the PLC IP (Enter keeps the saved one), tests the connection, starts the dashboard and opens the browser. `start_dashboard.bat 172.21.30.157` skips the prompt. |
| `test_plc.bat` | Connection check only: TCP port 102, then a Snap7 session. Don't run it while the dashboard is running. |
| `start_simulator.bat` | Dashboard with no PLC. |

The start scripts run `setup.bat` automatically if needed. The IP is saved to
`config/config.json`, so the same folder works on any PC on the PLC network.

---

## Documentation

| Document | What it covers |
|----------|----------------|
| [ARCHITECTURE.md](docs/ARCHITECTURE.md) | Audit of the legacy system, target design, KEEP/REFACTOR/REPLACE/REMOVE, safety boundaries |
| [PHASE1_ANALYSIS.md](docs/PHASE1_ANALYSIS.md) | State of the system before the data-source / SQL / chatbot extension |
| [DATA_SOURCES.md](docs/DATA_SOURCES.md) | Adapter contract, operating modes, MATLAB integration, control-vs-telemetry |
| [DATA_PERSISTENCE.md](docs/DATA_PERSISTENCE.md) | SQL schema, ingestion policy, recording, retention |
| [CHATBOT.md](docs/CHATBOT.md) | Help assistant, its capability boundary, providers |
| [TWIN_COMPONENT_MAPPING.md](docs/TWIN_COMPONENT_MAPPING.md) | Real machine vs digital component table, from the photographs |
| [DEBUGGING_REPORT.md](docs/DEBUGGING_REPORT.md) | All 20 rows of the Errors sheet, worked through against the code |
| [TAG_MAP.md](docs/TAG_MAP.md) | How DB59 is organised, and the four write-access classes |
| [DIGITAL_TWIN.md](docs/DIGITAL_TWIN.md) | MATLAB integration, and what is live vs estimated vs simulated |
| [SETUP.md](docs/SETUP.md) | Exact steps to run backend, frontend, camera and twin |
| [TEST_CHECKLIST.md](docs/TEST_CHECKLIST.md) | Reproducible tests, automated and manual |

---

## What this replaces, and why

The legacy system ran **four Snap7 clients** against one PLC — the SCADA app
connected at import time *and* ran with `debug=True`, so the Werkzeug reloader
forked a second process holding a second client; a separate script polled the DB
in an unthrottled loop; the dashboard held a fourth. State passed between them
through JSON files written non-atomically, so a reader landing mid-write got a
truncated file and every tag blanked to OFF for a frame.

Three findings from the audit worth reading before anything else:

- **The SCADA Hub's E-Stop button did nothing.** It POSTed to `/api/command`, a
  route that does not exist. The 404 landed in a `catch` that returned
  `{success: true}`.
- **`solenoid_valve_8` was never misbehaving.** The default tag map points at
  DB59 bytes 266–269 — undocumented in the tag list, which ends at 265.7 — and
  packs the bits ignoring S7 struct alignment, so every valve label is 3 bits
  off. The screen was showing valve 5's activity labelled as 8.
  ([E-18](docs/DEBUGGING_REPORT.md#e-18--solenoid_valve_8-randomly-turns-on-and-off-on-the-scada-hub))
- **Nothing validated the order quantity**, in either the UI or the backend,
  which is why the machine would start with 0 + 0 and never terminate.

---

## The design rules

1. **One Snap7 client.** `PlcService` is the only module that imports snap7, and
   `use_reloader=False` is non-negotiable — a fork means a second client.
2. **No HTTP request ever reads the PLC.** Everything serves a cached snapshot
   composed once per poll.
3. **A write is not done until a later, independent read confirms it.** The
   cache is never optimistically patched. `PENDING → WRITTEN → CONFIRMED`, or
   `MISMATCH` with an explanation.
4. **Never invent an address.** The engraving-platform jog is not implemented
   because its DB1 tags are absent from the supplied tag list. Cylinder position
   is not shown because no reed-switch tag exists.
5. **`null` is not `false`.** An unknown signal renders as `N/A`, never as OFF.
6. **Colour is never the only channel.** Every state carries a label and usually
   an icon.
7. **The UI never freezes.** On link loss the last known values are retained and
   marked stale — losing them destroys the evidence an operator needs.

---

## Layout

```
scada_platform/
├── run.py                  entry point
├── config/                 config.json, tag_overlay.json (generated)
├── backend/
│   ├── core.py             composes the one snapshot
│   ├── plc/                registry · codec · service (the Snap7 owner) · simulator
│   ├── sources/            adapter contract · PLC · MATLAB · SourceManager
│   ├── db/                 schema · store (non-blocking writer) · ingest · queries
│   ├── chat/               context (read-only) · providers · service
│   ├── state/              machine · sequence · events · history · products
│   ├── services/           safety · diagnostics · camera · twin · recording
│   ├── api/                rest · extended · stream (SSE)
│   └── util/xlsx.py        dependency-free .xlsx reader
├── frontend/               React 18 + TypeScript + Vite + Tailwind
│   ├── src/components/twin3d/   3-D machine model (three.js, code-split)
│   └── dist/               prebuilt; served directly by Flask
├── tools/
│   ├── build_tag_overlay.py       regenerate the overlay
│   ├── camera_bridge.py           YOLO detector, separate process
│   ├── export_twin_reference.m    MATLAB exporter (read-only)
│   ├── make_sample_twin_reference.py   synthetic fixture for testing
│   ├── selftest.py                47 checks — original behaviour
│   ├── selftest_extended.py       101 checks — sources, SQL, chatbot
│   └── check_twin_layout.py       55 checks — 3-D geometry sanity
├── data/                   JSON bridges + scada_history.db (generated)
└── docs/
```

Backend dependencies: `flask` and `python-snap7`. That is the whole list — the
tag list is parsed with a stdlib `.xlsx` reader and the database is stdlib
`sqlite3`, so it installs on an offline machine.

---

## Verify

```bash
python run.py --simulate --port 5055          # terminal 1

python tools/selftest.py --port 5055          # 47  — original behaviour
python tools/selftest_extended.py --port 5055 # 101 — sources, SQL, chatbot
python tools/check_twin_layout.py             # 55  — 3-D geometry
```

**203 checks.** Every safety rule is enforced server-side, so curl cannot
bypass it.

---

## Simulation mode

```bash
python run.py --simulate
```

A stand-in PLC drives the documented tag addresses through the real sequence, so
every screen exercises the same code path it will use against hardware. Writes
round-trip through an in-memory image, so write confirmation works too.

Scripted faults, for exercising the diagnostics:

```bash
python run.py --simulate --sim-fault valve8_chatter      # E-18
python run.py --simulate --sim-fault conveyor2_stall     # E-07
python run.py --simulate --sim-fault plate_stuck_top     # E-14
python run.py --simulate --sim-fault emergency           # E-20
python run.py --simulate --sim-fault air_pressure        # E-02
```

The connection indicator reads `SIMULATED` throughout and the UI labels it.

---

## Safety

**This application provides no functional safety.** The red control in the top
bar is labelled **SOFTWARE STOP** and clears `CMD_START`. It does not remove
power, vent air, or open the safety circuit.

The hardware E-Stop *status* is displayed beside it, read from
`Start_interlocks.Emergency Healthy`. Nothing here can drive that circuit, and no
button here substitutes for it.

There is no authentication. The command model is authorisation-ready — every
command carries an operator field and an access class — but no identity provider
is wired in. Do not expose this beyond a trusted lab network.

---

## Legacy code

Nothing in `Final/` or `PLC_Dashboard/` was modified or deleted. This platform
lives alongside them and can be rolled back by stopping `run.py` and restarting
the old apps.

**Do not run them at the same time.** In particular `json_write_for_web_tag.py`
holds its own Snap7 client and polls continuously.
