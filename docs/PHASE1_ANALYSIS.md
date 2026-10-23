# PHASE 1 — ARCHITECTURE ANALYSIS (before extension)

State of the system as it exists *before* the data-source, SQL, chatbot and
3D-twin work. Written from inspection of the running code, not from memory.

---

## 1. Current system architecture

```
Browser (React 18 + TS + Vite, 6 171 LOC)
   │  SSE  /api/stream        REST  /api/*
   ▼
Flask (threaded, use_reloader=False)
   ├── backend/api/rest.py      REST endpoints
   └── backend/api/stream.py    SSE fan-out, bounded queue per subscriber
   ▼
backend/core.py  ── Core: composes ONE snapshot per poll
   ├── plc/service.py      PlcService — the only Snap7 owner (596 LOC)
   ├── plc/registry.py     158 tags from Tag_list.xlsx + overlay
   ├── plc/simulator.py    offline PLC stand-in
   ├── state/machine.py    lifecycle + mode ownership
   ├── state/sequence.py   42-step inference
   ├── state/events.py     ring buffer + latching faults   ← IN MEMORY ONLY
   ├── state/history.py    per-tag change history          ← IN MEMORY ONLY
   ├── state/products.py   magazine view + cycle token
   ├── services/safety.py  CommandGate — 8-step authorisation
   ├── services/diagnostics.py
   ├── services/camera.py  reads JSON written by a separate process
   └── services/twin.py    replays an exported MATLAB trajectory
   ▼
S7-1200 DB59 (280 bytes, one db_read per 250 ms poll)
```

**Total: 5 427 backend LOC, 6 171 frontend LOC.**

## 2. Current data flow

`PLC → PlcService._read_all() → _decode_into_cache() → change list → Core._on_poll() → composed snapshot → SSE → zustand store → selector-scoped React render`

The composition runs **on the PLC worker thread**. HTTP threads only ever read a
finished snapshot object. No request path touches the PLC.

## 3. Current machine control flow

`React → REST POST → CommandGate.evaluate() → PlcService.submit_write() → queue → executed on the poll thread → db_write → next independent poll reads back → CONFIRMED / MISMATCH`

`CommandGate` runs eight checks in fixed order: tag exists, link usable,
emergency, access class vs mode, automatic ownership, physical interlocks, value
validity, confirmation. Access classes are `read_only` / `safe_manual` /
`engineering` / `protected`.

## 4. Current PLC communication

- **One** Snap7 client, imported lazily inside `PlcService._connect`.
- `_io_lock` serialises all Snap7 calls; `_state_lock` guards the cache.
- Writes are issued **on the worker thread** immediately after a fresh read, so
  a Bool read-modify-write cannot interleave with another thread's read.
- Reconnect uses exponential backoff 1 s → 10 s.
- Connection states: `DISCONNECTED / CONNECTING / CONNECTED / DEGRADED / RECONNECTING / SIMULATED`.

## 5. Frontend / backend responsibilities

| Frontend | Backend |
|---|---|
| Render, interact, chart | Every safety and authorisation decision |
| Display backend-authoritative state | Mode ownership, lifecycle derivation |
| Disable controls as a *courtesy* | Refuse commands as the *control* |

Already correct: `/api/cycle/start` enforces the quantity rule server-side, so a
curl bypass fails identically to the disabled button.

## 6. Current digital-twin architecture

**Important finding: the existing twin is 2-D SVG, not 3-D.**

- `components/digitalTwin/FactorySchematic.tsx` — hand-authored SVG, 1000×460
  user units, topological rather than dimensioned.
- `components/digitalTwin/layout.ts` — placements with an explicit
  `confidence` field (`sequenced` / `schematic` / `unassigned`).
- `services/twin.py` — replays `data/twin_reference.json` exported from MATLAB
  by `tools/export_twin_reference.m`, aligned to the live cycle clock.

There is **no 3-D renderer, no camera, no orbit controls** in the project today.
Part 13's "preserve existing 3-D navigation" therefore has nothing to preserve —
it has to be built.

## 7. Current state/lifecycle architecture

`MachineModel._derive()` runs every poll and returns one of:
`DISCONNECTED · EMERGENCY_STOPPED · FAULT · RECOVERY_REQUIRED · RESETTING ·
IDLE · READY · STARTING · AUTO_RUNNING · COMPLETED · MANUAL_MODE · MAINTENANCE`.

Separately, **mode** (`AUTO` / `MANUAL` / `MAINTENANCE`) is backend-owned and
governs *who may command what*. The PLC has no mode tag; inventing one would be
a fabrication, so ownership is enforced in the backend.

**This is the existing lifecycle. Part 5 must extend it, not replace it.**

## 8. Current storage architecture

**There is none.** Everything is in-memory and dies with the process:

| Store | Location | Capacity | Survives restart |
|---|---|---|---|
| Events | `EventLog._events` | 4 000 ring | no |
| Faults | `EventLog._faults` | unbounded dict | no |
| Tag history | `TagHistory._by_tag` | 120/tag | no |
| Global changes | `TagHistory._global` | 5 000 ring | no |
| Commands | `PlcService._recent_commands` | 400 | no |

This is the single largest gap, and what Part 3 addresses.

## 9. Files likely to be modified

| File | Change |
|---|---|
| `backend/core.py` | own the source manager, data service, chat service |
| `backend/api/rest.py` | new endpoints (extend, not duplicate) |
| `backend/state/machine.py` | add source-aware lifecycle states |
| `backend/plc/service.py` | expose an adapter-shaped surface; **no behavioural change** |
| `frontend/src/types/index.ts` | extend the snapshot contract |
| `frontend/src/App.tsx` | new routes |
| `frontend/src/components/layout/TopBar.tsx` | source/mode banner |
| `config/config.json` | database, sources, chat sections |

## 10. New modules to add

```
backend/sources/    base.py · plc_source.py · matlab_source.py · manager.py
backend/db/         schema.py · store.py · ingest.py · queries.py
backend/services/   recording.py · chat.py
backend/chat/       context.py · providers.py
frontend/src/components/twin3d/   Scene + per-station components
frontend/src/components/chat/     ChatPanel
frontend/src/components/data/     RecordingControls
frontend/src/pages/               History, Machine3D
```

## 11. Integration plan

1. Wrap the **existing** `PlcService` in a `DataSourceAdapter` — no rewrite.
2. Add `SourceManager` enforcing exactly one active control source.
3. Add the MATLAB adapter behind the same interface (mock + file + TCP).
4. Add SQLite with a **dedicated writer thread** fed by a bounded queue.
5. Add recording sessions and snapshots on top of that queue.
6. Add the chatbot with a **read-only** context view and no command path.
7. Extend the API; keep every existing route working.
8. Extend the frontend; keep every existing page working.
9. Build the 3-D twin **alongside** the 2-D schematic, sharing state.

## 12. Major risks and how each is handled

| Risk | Mitigation |
|---|---|
| **Second Snap7 client** | `PlcService` stays the sole owner. The adapter wraps it; it does not open connections. |
| **Simulation commands reaching the real PLC** | `SourceManager` routes every write to the *active* adapter only. The PLC adapter refuses writes when it is not active. |
| **Two sources controlling one machine** | One active control source, enforced in the manager, not by convention. |
| **Stale data shown as live** | Every normalised sample carries `source`, `timestamp`, `quality`, `sequence`. Quality degrades to `STALE` past budget. |
| **DB blocking PLC comms** | The poll thread only does `queue.put_nowait()`. A separate writer thread owns the SQLite connection. Queue full ⇒ **drop and count**, never block. |
| **Millions of rows** | Nothing is written per poll by default. Events, transitions and cycle summaries only; tag samples only inside an explicit recording session, and then sampled/deadbanded. |
| **Breaking React↔backend** | Snapshot fields are **added**, never renamed or removed. Existing types stay valid. |
| **Breaking the working twin** | The 2-D schematic stays and keeps working. 3-D is a new sibling view over the same store. |

## 13. Decision recorded: SQLite, not a server database

SQLite via the Python stdlib `sqlite3`:

- keeps the dependency list at `flask` + `python-snap7` + nothing new;
- installs on an offline lab PC with no service to administer;
- handles the intended volume comfortably, because the ingestion policy
  deliberately keeps writes in the tens per minute, not thousands per second;
- WAL mode lets the reader (HTTP) and the single writer proceed concurrently.

`db.url` in config accepts a Postgres/MySQL DSN for later; the store is written
against a narrow DB-API surface so swapping the driver is contained.
