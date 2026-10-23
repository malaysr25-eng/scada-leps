# ARCHITECTURE

Unified SCADA, manual control and digital-twin platform for the S7-1200 lab cell.

---

## 1. What was there before

Three separate programs, four PLC connections, and a file on disk acting as the
integration bus.

```
┌────────────────────────┐   ┌──────────────────────────┐   ┌───────────────────────┐
│ Final/app.py           │   │ json_write_for_web_tag.py│   │ PLC_Dashboard/app*.py │
│ Flask, debug=True      │   │ tight loop, no sleep     │   │ Flask + pandas        │
│ snap7 client #1 (+#2   │   │ snap7 client #3          │   │ snap7 client #4       │
│ from the reloader)     │   │ bare except: continue    │   │ background poller     │
└──────────┬─────────────┘   └────────────┬─────────────┘   └───────────┬───────────┘
           │ writes                        │ writes                      │ r/w
           │                          data.json (non-atomic)             │
           │                               │                             │
           └───── reads per request ───────┘                             │
                                                                          │
                    ┌─────────────────────────────────────────────────────┘
                    ▼
             ┌──────────────┐        ┌──────────────────┐
             │  S7-1200 PLC │◀───────│ camera_yolo.py   │ products.json,
             │    DB59      │        │ snap7: none      │ output_data.json
             └──────────────┘        └──────────────────┘ (non-atomic, per frame)
```

### Findings from the audit

| # | Finding | Evidence |
|---|---------|----------|
| A1 | **Four competing Snap7 clients.** `Final/app.py` connects at import time *and* runs `app.run(debug=True)`, so the Werkzeug reloader forks a second process holding a second client. Plus the JSON writer and the dashboard. | `Final/app.py:22,255`; `json_write_for_web_tag.py:20`; `PLC_Dashboard/app_fixed.py:34` |
| A2 | **The SCADA never reads the PLC for display.** It reads `data.json`, written by a separate process. | `Final/app.py:56-79` |
| A3 | **Non-atomic file IPC.** `open(path,'w')` truncates before writing. A reader landing in that window gets a JSONDecodeError; `load_plc_data` catches it and returns `{}, {}, {}`, blanking every tag for one frame. | `json_write_for_web_tag.py:39-42`; `Final/app.py:80-82` |
| A4 | **Unthrottled poll loop with a bare `except: continue`.** No sleep, so it spins as fast as the network allows; any error becomes a busy-loop. | `json_write_for_web_tag.py:24-45` |
| A5 | **The E-Stop button was a no-op.** `ui.js` POSTs to `/api/command`, which does not exist in `app.py`. The 404 lands in a `catch` that returns `{success: true, offline: true}`. | `Final/static/js/ui.js:263`; no matching route in `app.py` |
| A6 | **No zero-quantity validation anywhere.** Neither `machineStart()` nor `/api/start` checks the total. | `Final/static/js/ui.js:190`; `Final/app.py:157` |
| A7 | **START forces all five magazine-available bits TRUE**, defeating the empty-magazine interlock. | `Final/app.py:204-208` |
| A8 | **Writes were never confirmed.** `app_fixed.py` optimistically patches its cache with the requested value, so a write the PLC overwrites still displays as successful. | `PLC_Dashboard/app_fixed.py:275,296,317` |
| A9 | **Any of 121 tags was writable at any time**, including while an automatic cycle ran. | `PLC_Dashboard/app_fixed.py:1036` |
| A10 | **The ON-mode tag map points at an undocumented region.** See §2. | `Final/data_on.json` vs `Tag_list (1).xlsx` |
| A11 | `DB.py` is a MySQL demo script unrelated to the dashboard. Dead code. | `PLC_Dashboard/DB.py` |
| A12 | `app_platform_control (1).py` references DB1 Axis_1 tags (`en_mc_power`, `exe_jogforward`, …) that **do not exist in the supplied tag list**, so its platform-jog route cannot resolve them. | `app_platform_control (1).py:1217-1230` |

### A10 in detail — the `solenoid_valve_8` mystery

`data_on.json` (the default power mode) maps sensors and valves to **DB59 bytes
266–269**. `Tag_list (1).xlsx` documents those same signals at **128–131**, and
the tag list ends entirely at `DB59.DBX265.7`.

The 266–269 map is also internally inconsistent with S7 layout rules. The
documented region has a struct boundary between `Digital_Inputs` (128.0–129.4)
and `Digital_Outputs` (130.0–131.7); S7 aligns a new struct to an even byte, so
there is a 3-bit gap after `Emergency` at 129.4. The legacy map packs the bits
contiguously — `solenoid_valve1` at 267.5, straight after `emergency` at 267.4 —
and so drifts by 3 bits.

Under the +138 mirror interpretation, the SCADA Hub's `solenoid_valve8`
(`DBX268.4`) is really `Solenoid_valve5` (`130.4 + 138`). **The dashboard has
been showing valve 5's activity under a label that says 8.**

This platform treats 266–269 as `raw.*` tags: read-only, flagged UNDOCUMENTED,
visible in the Tag Explorer for verification against real hardware, and never
used to drive an indicator. See `DEBUGGING_REPORT.md` E-18.

### What was worth keeping

`app_fixed.py` got the hard part right, and its shape is preserved:

- one Snap7 client, owned by one background thread;
- one large `db_read` per poll instead of 121 individual reads;
- Flask requests read a cache, never the PLC;
- a lock around all PLC I/O;
- connection recovery on error.

---

## 2. Target architecture

```
                        ┌───────────────────────────────────┐
                        │  FRONTEND — React 18 + TS + Vite  │
                        │  Unified SCADA / Manual / Twin    │
                        │  zustand store, selector-scoped   │
                        └───────────────┬───────────────────┘
                            SSE (state) │ REST (commands)
                        ┌───────────────▼───────────────────┐
                        │  Flask API  (backend/api)         │
                        │  /api/state  /api/stream          │
                        │  /api/cycle/* /api/tags/*/write   │
                        └───────────────┬───────────────────┘
                        ┌───────────────▼───────────────────┐
                        │  Core  (backend/core.py)          │
                        │  composes ONE snapshot per poll   │
                        └───┬──────────┬──────────┬─────────┘
             ┌──────────────┘          │          └──────────────┐
    ┌────────▼─────────┐   ┌───────────▼────────┐   ┌────────────▼────────┐
    │ CommandGate      │   │ Machine / Sequence │   │ Camera + Twin       │
    │ mode, interlocks │   │ Products / Events  │   │ adapters (read-only)│
    │ ownership, risk  │   │ History / Faults   │   │ JSON boundaries     │
    └────────┬─────────┘   └───────────┬────────┘   └────────────┬────────┘
             │  validated writes       │ reads cache              │ reads files
    ┌────────▼─────────────────────────▼──────────┐    ┌──────────▼─────────┐
    │  PlcService  — THE ONLY SNAP7 CLIENT        │    │ camera_bridge.py   │
    │  one thread · one db_read/poll · write queue│    │ (separate process) │
    │  write → next read confirms → CONFIRMED     │    │ export_twin_ref.m  │
    └────────────────────┬────────────────────────┘    │ (MATLAB, offline)  │
                         │                             └────────────────────┘
                  ┌──────▼──────┐
                  │  S7-1200    │
                  │  DB59       │
                  └─────────────┘
```

### The invariant

**One process, one Snap7 client, one poll thread.** Enforced structurally:

- `PlcService` is the only module that imports `snap7`, and it imports it lazily
  so simulation mode needs no driver.
- `run.py` starts Flask with `use_reloader=False`. Non-negotiable: the reloader
  forks, and a fork means a second client. This is exactly what
  `app.run(debug=True)` did in the legacy SCADA.
- Writes are issued **on the poll thread**, immediately after a fresh read, so a
  Bool read-modify-write can never interleave with another thread's read of the
  same byte.

### Write confirmation

```
frontend           CommandGate            PlcService              PLC
   │  POST write        │                     │                    │
   ├───────────────────►│                     │                    │
   │                    │ mode? interlocks?   │                    │
   │                    │ ownership? range?   │                    │
   │                    ├────────────────────►│  queue             │
   │  202 PENDING       │                     │                    │
   │◄───────────────────┴─────────────────────┤                    │
   │                                          ├── db_write ───────►│
   │  stream: WRITTEN                         │                    │
   │◄─────────────────────────────────────────┤                    │
   │                                          │◄── db_read ────────┤
   │  stream: CONFIRMED  (or MISMATCH)        │   independent      │
   │◄─────────────────────────────────────────┤   read-back        │
```

A command reaches `CONFIRMED` only when a **subsequent, independent poll** reads
the value back. If the PLC program overwrites the bit, the command settles as
`MISMATCH` with the explanation *"wrote True, PLC still reads False after 2.0 s
— the PLC program is probably driving this address."*

The cache is never optimistically patched. That single change is what makes
"actuator 8 did not retract" visible instead of silently green.

### Control ownership

| Mode | May write | Rationale |
|------|-----------|-----------|
| `AUTO` | nothing manual | The sequencer owns the machine. |
| `MANUAL` | `safe_manual` (the `manual_commands` struct) | Operator control of valves and conveyors. |
| `MAINTENANCE` | `safe_manual` + `engineering` | Setpoints, with confirmation. |
| any, during emergency | nothing | All process commands blocked. |

The backend refuses a manual write to a valve while `CMD_START` is high and the
cycle is not complete, **even in MANUAL mode**. Two writers on one coil is the
failure being removed (Errors sheet, 2026-08-17).

### Real-time data

| Path | Rate | Note |
|------|------|------|
| PLC poll | 250 ms (configurable) | One `db_read` of 280 bytes covers all 158 tags. |
| Snapshot compose | per poll | Runs on the poll thread; HTTP threads only read a finished object. |
| SSE push | per poll | Bounded queue per subscriber; oldest frame dropped rather than blocking the poll loop. |
| Browser fallback | 2 s | Only while the stream is down. Explicitly degraded, not a second update path. |

SSE rather than WebSockets: the flow is one-directional (state down, commands
over REST), it needs no `eventlet`/`gevent` monkey-patching on threaded Flask,
and `EventSource` reconnects on its own — which is the direct fix for *"manually
controlled website needed to be refreshed again and again"*.

Re-render scope is controlled by zustand selectors: a component subscribing to
`s.snapshot?.sensors` re-renders only when that slice changes identity, not on
every 4 Hz snapshot.

---

## 3. KEEP / REFACTOR / REPLACE / REMOVE

| Component | Verdict | Notes |
|-----------|---------|-------|
| `app_fixed.py` background-poller architecture | **KEEP** (conceptually) | Reimplemented in `backend/plc/service.py` with write confirmation, backoff and health metrics added. |
| `Tag_list (1).xlsx` | **KEEP** | The only authoritative address source. Loaded, never edited. |
| `Factory_Simulation/*` MATLAB model | **KEEP UNTOUCHED** | Not one file modified. A new read-only exporter was added under `scada_platform/tools/`. |
| `camera_yolo.py` detection logic | **REFACTOR** → `tools/camera_bridge.py` | Model and counting logic unchanged; atomic writes, heartbeat, throttling, retry and headless mode added. |
| `PLC_Dashboard` pandas dependency | **REPLACE** → `backend/util/xlsx.py` | ~60 MB of transitive deps replaced by 120 lines of stdlib. Verified to parse all 121 tags identically. |
| `Final/app.py` + `templates/` + `static/` | **REPLACE** | Superseded by the unified app. Left in place, unmodified, for reference and rollback. |
| `PLC_Dashboard/app.py`, `app_fixed.py`, `app_platform_control (1).py` | **REPLACE** | Superseded. Left in place. |
| `json_write_for_web_tag.py` | **REMOVE from the runtime path** | Its job — decoding DB59 into named tags — is now `PlcService` + the registry. Running it alongside the platform reintroduces a competing client. |
| `data.json`, `data_on.json`, `data_off.json` | **REMOVE from the runtime path** | Replaced by the registry + overlay. `data_on.json` is actively harmful (§2, A10). |
| `PLC_Dashboard/DB.py` | **REMOVE** | Unrelated MySQL demo script. |
| Axis_1 / engraving-platform jog | **BLOCKED — needs input** | `app_platform_control` references DB1 tags absent from the tag list. Not reimplemented; inventing DB1 addresses is not acceptable. See §6. |

Nothing in `Final/` or `PLC_Dashboard/` was modified or deleted. The new platform
lives in `Final/scada_platform/` and runs on its own port.

---

## 4. Backend layout

```
backend/
├── core.py              Core: owns every service, composes the snapshot
├── app.py               Flask factory, serves frontend/dist
├── plc/
│   ├── registry.py      tag registry from Excel + overlay; raw-block support
│   ├── codec.py         S7 encode/decode; NaN normalisation; value coercion
│   ├── service.py       THE Snap7 owner: poll, cache, write queue, confirm
│   └── simulator.py     offline PLC for development and demos
├── state/
│   ├── machine.py       lifecycle derivation, mode ownership, restart checklist
│   ├── sequence.py      42-step model + ordered counted-edge inference
│   ├── events.py        event ring buffer + latching faults
│   ├── history.py       per-tag change history with operator/PLC attribution
│   └── products.py      magazine view + cycle-scoped workpiece token
├── services/
│   ├── safety.py        CommandGate — the 8-step authorisation chain
│   ├── diagnostics.py   detectors, each tied to an Errors-sheet row
│   ├── camera.py        read-only JSON adapter with staleness detection
│   └── twin.py          reference-trajectory adapter + divergence detection
├── api/
│   ├── rest.py          REST endpoints
│   └── stream.py        SSE
└── util/xlsx.py         dependency-free .xlsx reader
```

### Machine lifecycle

Derived from PLC tags every poll; the HMI cannot set it.

```
              ┌──────────────┐
              │ DISCONNECTED │◄──── link lost (values retained, marked stale)
              └──────┬───────┘
                     ▼
  EMERGENCY_STOPPED ◄──── Emergency Healthy == FALSE
         │  (context frozen: step, sensors, valves, safety bits)
         ▼
  RECOVERY_REQUIRED ──── interlocks return ────► READY
         │                                          │
         │ Cycle_Reset                              │ /api/cycle/start
         ▼                                          ▼
     RESETTING                              STARTING → AUTO_RUNNING → COMPLETED
                                                              │
                                                              ▼
                                                            FAULT
```

`FAULT` does **not** stop the sequence or product trackers. "Running" is derived
from the PLC (`CMD_START && !Cycle_Completed`), not from the lifecycle enum,
because an operator most needs to see what the machine was doing at exactly the
moment it faulted.

### Sequence inference — and its limits

**The PLC publishes no step index.** No such tag exists in `Tag_list (1).xlsx`.
The active step is *inferred*, and the UI says so.

The tracker walks the 12 observable guards **in order**, matching **counted
rising edges** from the poll change list. Three properties, each earned from a
bug found during testing:

1. **Ordered** — scanning all guards and taking the furthest match let an
   unrelated signal teleport the timeline forward.
2. **Edges, not levels** — the plate low-limit switch is closed whenever the
   plate is parked down, so a level test satisfied step 28 on the first poll of
   every cycle.
3. **Counted, not sampled** — at 250 ms polling, PX1 rising and conveyor 1
   starting often land in the same poll. Sampling the level on arrival saw the
   belt already running and then waited forever for an edge that had passed.

Guards with no corresponding tag — every cylinder extend/retract, all four
distribution-branch pressures — are typed `unobservable` and can never produce a
confirmation. The timeline shows them greyed with *"no reed-switch tag"* rather
than a fabricated tick.

---

## 5. Frontend layout

```
frontend/src/
├── App.tsx                    shell; opens the ONE SSE connection
├── types/index.ts             mirrors the backend snapshot exactly
├── services/  api.ts          typed REST, discriminated ApiResult
│             realtime.ts      SSE + link state + degraded polling fallback
├── stores/machineStore.ts     zustand; one snapshot, selector-scoped reads
├── hooks/     useRealtime, useSequenceCatalogue
├── components/
│   ├── layout/     TopBar, NavRail
│   ├── common/     Primitives, Toasts, CameraPanel
│   ├── machine/    SequenceTimeline, RestartChecklist
│   ├── controls/   CycleControl, ManualControl
│   ├── sensors/    SensorPanel (board, stream, detail)
│   ├── digitalTwin/ FactorySchematic, layout.ts, TwinPanels
│   ├── diagnostics/ DiagnosticsPanels
│   └── tags/       TagExplorer
└── pages/  Overview · FactoryTwin · Sequence · ManualControl
         · Diagnostics · DigitalTwin · Tags
```

`Tri = boolean | null` runs through the whole type layer. `null` means *no value*
— the tag is missing, or no poll has succeeded. It is never rendered as OFF.
Drawing an unknown sensor as clear is how an HMI quietly misleads an operator.

Hash routing (`HashRouter`) so deep links and refreshes work from a plain static
handler with no server rewrite rules.

---

## 6. Safety boundaries

**This application provides no functional safety.** A web app on a
general-purpose PC over a general-purpose network cannot.

| Concern | Where it lives | How it is presented |
|---------|----------------|---------------------|
| Hardware E-Stop | Certified safety relay, outside this system | Read-only **status** in the top bar (`Start_interlocks.Emergency Healthy`). Never writable. |
| PLC emergency state | `DB59.DBX0.3`, `DB59.DBX129.4` | Drives `EMERGENCY_STOPPED`, freezes context, blocks commands. |
| Software stop | `/api/cycle/stop` → clears `CMD_START` | Labelled **SOFTWARE STOP** on its face, with the caveat in its tooltip and in the toast it raises. |

The red control in the top bar is deliberately *not* labelled "Emergency Stop".
It clears `CMD_START`. It does not remove power, vent air, or open the safety
circuit.

### Things this platform refuses to do

- **Invent a PLC address.** The Axis_1 platform jog is not implemented, because
  `en_mc_power`, `exe_jogforward`, `exe_jogbackward` and the limit switches
  appear nowhere in the supplied tag list. Supply a tag list containing them and
  the overlay picks them up with no code change.
- **Claim cylinder position.** No reed-switch tag exists for any cylinder.
- **Claim per-part identity.** The camera re-counts every frame with no object
  tracking; no PLC tag carries a part ID. Tracking is cycle-scoped.
- **Guess physical placement.** Schematic positions are drawn only where the
  Sequencing sheet supports them; the rest sit in labelled "unassigned" trays.

---

## 7. Migration

The new platform is additive. Nothing was modified or deleted.

1. **Stop the legacy processes.** In particular `json_write_for_web_tag.py` — it
   holds its own Snap7 client and will compete for the PLC.
2. `python run.py` (see `SETUP.md`). Default port 5000; the legacy apps also used
   5000, so run one at a time or change the port.
3. Verify with `python tools/selftest.py` — 47 checks, all backend-enforced.
4. Roll back by stopping `run.py` and restarting the legacy apps. They are
   untouched.

Run the platform against real hardware in **AUTO mode with no cycle started**
first: it is read-only in that state, so the poll rate, latency and tag decoding
can be verified before any write is attempted.

---

## 8. Decisions worth recording

| Decision | Why | Alternative rejected because |
|----------|-----|------------------------------|
| SSE, not WebSockets | One-directional; works on threaded Flask; browser auto-reconnect | WebSockets need `flask-sock` + an async worker, adding deployment fragility for a channel that never needs to be bidirectional |
| Reference trajectory, not MATLAB co-simulation | The model is a batch RK4 integrator with no stepping API; README states runtime is explicitly not a goal | MATLAB Engine would mean either rewriting the validated solver or blocking the HMI ~30 s per cycle |
| Stdlib `.xlsx` reader | `pip install flask python-snap7` is the whole dependency list; works offline | pandas + openpyxl for three columns of a 121-row sheet |
| Camera in a separate process, JSON bridge | Inference must never stall the PLC poll loop; the detector restarts independently | In-process YOLO couples camera health to control-system availability |
| Access classes on tags | An output-image mirror is not commandable; showing a Toggle beside it teaches operators the HMI lies | A uniform Toggle on all 121 tags, as before |
| Zero-quantity rule in the backend | A UI can be bypassed with curl or a stale tab | Frontend-only validation |
| `use_reloader=False`, always | A fork means a second Snap7 client | Convenience during development |
