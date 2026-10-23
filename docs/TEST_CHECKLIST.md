# TEST CHECKLIST

Reproducible tests for the platform. Automated first, then the manual procedures
that need a person or the real machine.

---

## A. Automated suite

```bash
.\.venv\Scripts\python.exe run.py --simulate --port 5055     # terminal 1
.\.venv\Scripts\python.exe tools\selftest.py --port 5055     # terminal 2
```

Expected: **47 passed, 0 failed**. Exit code 0.

Every check exercises a **backend** rule. A frontend can be bypassed with curl,
so UI-only validation would prove nothing.

| § | Group | Checks | Covers |
|---|-------|--------|--------|
| 1 | Connectivity & registry | 6 | Tag load, snapshot shape, device counts |
| 2 | Zero-quantity rule | 4 | E-16 |
| 3 | Protected & read-only tags | 6 | Access enforcement |
| 4 | Auto/manual ownership | 9 | E-13, write confirmation |
| 5 | Value validation | 3 | Type/range coercion |
| 6 | Full automatic cycle | 13 | Start ordering, sequence inference, operator hold |
| 7 | Reset & recovery | 2 | E-20 |
| 8 | Real-time stream | 2 | E-11 |
| 9 | JSON safety | 2 | NaN regression |

### What §6 asserts that is easy to get wrong

- **Start ordering:** quantities and mode are written *before* `CMD_START`, so
  the PLC never sees a start with stale quantities.
- **No teleporting:** `lastConfirmedStep < 28` shortly after start. An earlier
  build satisfied step 28 on the first poll because the plate low-limit switch
  is closed at rest — the timeline claimed the machine was nearly finished
  before it had moved.
- **The operator hold is real:** the cycle waits at `cmd.engraving_completed`
  and only proceeds when acknowledged.

---

## B. PLC communication

Requires the real PLC.

| # | Test | Procedure | Expected |
|---|------|-----------|----------|
| B1 | Connect | `python run.py` | Banner shows the IP; top bar `PLC CONNECTED`; `staleSeconds` small and stable |
| B2 | Single client | Start the platform, then `netstat -ano \| findstr :102` | Exactly one established connection from this host |
| B3 | No reloader fork | `tasklist \| findstr python` | One process. Two means the reloader is on — a second Snap7 client |
| B4 | Poll health | `/api/health`, watch the top bar | `latencyAvgMs` stable; `errorCount` not climbing |
| B5 | Tag decode | Tag Explorer vs TIA Portal | Spot-check pressure, a hand-triggered proximity sensor, conveyor position feedbacks |
| B6 | Disconnect | Unplug the network cable | Within ~1 s: `DISCONNECTED`; **values retained and marked stale**; schematic desaturates; write controls disable. UI stays responsive |
| B7 | Reconnect | Plug back in | Reconnects with backoff; live updates resume with **no browser refresh** |
| B8 | Backoff | Leave it disconnected 60 s | Retry interval grows 1 s → 10 s. No connect storm |
| B9 | Concurrent browsers | Open 3 tabs | All update; poll rate unchanged; `subscribers: 3` on `/api/health` |
| B10 | Slow client | Open a tab, suspend it, wait 2 min | Poll latency unaffected. Bounded queue drops frames rather than blocking |
| B11 | Bool write | MANUAL → energise a valve | `PENDING` → `WRITTEN` → `CONFIRMED`. Latency shown |
| B12 | Int write | Start a cycle with 2 × 25 mm | `DBW108 = 2` confirmed; verify in TIA Portal |
| B13 | Real write | MAINTENANCE → conveyor Set_Velocity 0.20 | Confirmed within tolerance (Real compares with 1e-3, not `==`) |
| B14 | Contested write | Write a bit the PLC program drives | Settles `MISMATCH` with the explanation, **not** a false green |

---

## C. Automatic operation

| # | Test | Procedure | Expected |
|---|------|-----------|----------|
| C1 | Zero quantity — UI | Set both to 0 | Start disabled; reason shown: *"Select at least one product…"* |
| C2 | Zero quantity — backend | `curl -X POST .../api/cycle/start -d '{"qty25":0,"qty50":0}'` | `422 invalid_order`. **This is the real control** |
| C3 | Negative | `{"qty25":-1,"qty50":1}` | `422` |
| C4 | Out of range | `{"qty25":40000,"qty50":0}` | `422`, S7 Int range |
| C5 | Bypass attempt | `POST /api/tags/system.cmd_start/write {"value":true}` | `403 not_writable` — `protected` |
| C6 | Valid 25 mm | 1 × 25 mm, Start | Quantities then `CMD_START`; `AUTO_RUNNING`; cycle ID assigned |
| C7 | Valid 50 mm | 0 / 1 | Same |
| C8 | Mixed | 1 / 1 | Both quantities written |
| C9 | Already running | Start twice | `409 already_running` |
| C10 | Wrong mode | MANUAL, then Start | `409 wrong_mode` |
| C11 | Completion | Run to the end | `COMPLETED`; `Total products` matches; token in completed list |
| C12 | Interlock block | Force an interlock low, then Start | `409 interlocks_blocked`, blockers listed |

---

## D. Manual operation

| # | Test | Procedure | Expected |
|---|------|-----------|----------|
| D1 | Locked in AUTO | AUTO, try a valve | Refused `wrong_mode`; the panel explains that AUTO owns the machine |
| D2 | Enter MANUAL | Top bar → Manual | Mode changes; valve tiles arm |
| D3 | Command a valve | Energise SV1 | Command bit and output coil shown separately; command reaches `CONFIRMED` |
| D4 | Physical confirmation | Observe the cylinder | Moves. **The HMI cannot confirm this** — no reed-switch tag. Panel says so |
| D5 | Auto/manual conflict | Start a cycle, then try a valve | `409 auto_owns`. **This is E-13** |
| D6 | Mode refused mid-cycle | Cycle running, switch to MANUAL | Refused with a reason |
| D7 | Engineering locked | MANUAL, try Set_Velocity | `403 wrong_mode` |
| D8 | Engineering confirm | MAINTENANCE, Set_Velocity without confirm | `409 confirmation_required` |
| D9 | Engineering write | Same, with confirm | Accepted, confirmed, logged |
| D10 | High-risk confirm | MAINTENANCE, `Goto_Position` | Requires confirmation; blocked if the matching limit is active |
| D11 | Bad value | `{"value":"banana"}` on a Bool | `400 invalid_value` |
| D12 | Attribution | Command a valve, open Diagnostics | Change shows source `operator` with the command ID |

---

## E. Emergency and fault

| # | Test | Procedure | Expected |
|---|------|-----------|----------|
| E1 | Emergency display | Press the hardware E-Stop | Red ribbon within one poll; `EMERGENCY_STOPPED`; HW E-Stop reads `TRIPPED` |
| E2 | UI responsive | Navigate during emergency | Every page works. **It does not freeze** |
| E3 | Commands blocked | Try any write | `403 emergency_active` |
| E4 | Frozen context | Open the restart checklist | Sequence step, active sensors, energised valves, safety bits **as they were at the stop** |
| E5 | Context survives | Wait 5 minutes | Still displayed |
| E6 | Checklist | Read it | All six documented interlocks with live values; unsatisfied ones named |
| E7 | Reset blocked | Reset while an interlock is low | `409 interlocks_blocked` with the list |
| E8 | Recovery | Clear the E-Stop | `RECOVERY_REQUIRED` → checklist passes → `READY` |
| E9 | Reset | Press Reset | `Cycle_Reset` written and confirmed; sequence tracker cleared |
| E10 | Restart | Start a new cycle | Runs normally |
| E11 | Override | Force reset past a blocker | Requires explicit confirmation; event log records the bypassed blockers |
| E12 | Software stop honesty | Read the red control | Reads **SOFTWARE STOP**; tooltip and toast state it is not a functional-safety stop |

Simulated equivalents:

```bash
python run.py --simulate --sim-fault emergency
python run.py --simulate --sim-fault plate_stuck_top     # E-14
```

---

## F. Sensors and sequence

| # | Test | Procedure | Expected |
|---|------|-----------|----------|
| F1 | Live illumination | Pass metal over PX1 | Schematic lamp lights within one poll; board tile turns green |
| F2 | Event stream | Same | Two entries with millisecond timestamps: `OFF → ON`, `ON → OFF` |
| F3 | Transition count | Trigger 5 times | Count increments to 5 |
| F4 | Sensor detail | Click a sensor | Tag ID, address, last transition, count, description |
| F5 | Unknown ≠ off | Stop the backend, reload | Sensors show `N/A` with a dashed lamp, **not** OFF |
| F6 | Sequence advance | Run a cycle | Steps confirm in order as sensors fire |
| F7 | No teleporting | Watch from the start | Does not jump to step 28+ because the plate limit is closed at rest |
| F8 | Stall | Block the belt so PX3 never fires | Stall banner: signal name, elapsed, budget, **actual state** |
| F9 | Stall clears | Unblock it | Fault clears; sequence resumes |
| F10 | Operator hold | Reach the engraving step | *"Awaiting operator"* in amber — **not** a fault |
| F11 | Acknowledge | Press Engraving Complete | Sequence advances |
| F12 | Unobservable honesty | Read a cylinder step | Greyed, *"Cylinder extended (no reed-switch tag)"*. Never ticks |

---

## G. Diagnostics

| # | Test | Procedure | Expected |
|---|------|-----------|----------|
| G1 | Chatter (E-18) | `--sim-fault valve8_chatter` | Finding within 30 s: *"SV 8 is toggling rapidly — N transitions in 30 s. Attribution: plc."* Tagged E-18 |
| G2 | Attribution | Compare an operator write against PLC-driven chatter | `operator` vs `plc` badges differ |
| G3 | Conveyor stall (E-07) | `--sim-fault conveyor2_stall` | FAULT: run coil on, feedback zero, with the setpoint. Tagged E-07 |
| G4 | Fault clears | Stop the belt | Cleared, and the clearing is logged |
| G5 | Pressure (E-02) | `--sim-fault air_pressure` | Low-pressure finding; interlock fails on the checklist |
| G6 | Staleness | Stop the PLC | Stale finding; values marked, not blanked |
| G7 | Watch list | Open Diagnostics | Pre-pinned with the tags the Errors sheet names: SV7, SV8, SV11, SV12, conveyor 2 speed pair, emergency, plate home |
| G8 | Pin/unpin | Pin a tag from Tag Explorer | Appears in the watch list, persists |
| G9 | Change history | Filter by tag | Every transition with previous, new, time, source |
| G10 | Command history | After several commands | Requested, PLC read-back, outcome, latency |
| G11 | Event filter | Filter by FAULT | Only faults |
| G12 | Fault survives | Raise a fault, navigate away and back | Still listed with its raise time |

---

## H. Tag Explorer

| # | Test | Expected |
|---|------|----------|
| H1 | Load | 158 tags: 121 documented + 37 raw |
| H2 | Search | Name, address, description and role all match |
| H3 | Filter by group | 10 subsystems |
| H4 | Filter by type | Bool / Int / Real |
| H5 | Filter by access | Four classes |
| H6 | **Filter provenance = Undocumented** | Exactly the 266–269 and 270–278 raw tags, flagged `UNDOC` |
| H7 | Changed recently | Only tags that transitioned |
| H8 | Detail | Symbolic name, role, address, access with its rationale, source sheet, history |
| H9 | Access honesty | An output mirror shows `Read only`, not a Toggle |
| H10 | **E-18 comparison** | Compare `raw.db59.x268_4` against `io_status.digital_outputs.solenoid_valve5` during a cycle. If they track, the legacy mapping error is confirmed |

---

## I. Camera

| # | Test | Procedure | Expected |
|---|------|-----------|----------|
| I1 | Offline | Backend without the bridge | `OFFLINE`; instructions shown; **counts withheld** |
| I2 | Online | Start the bridge | `ONLINE` within ~2 s; counts appear |
| I3 | Stale | Kill the bridge | `STALE` after `stale_after`; counts withheld, not frozen at the last value |
| I4 | Atomic writes | Poll the counts file in a tight loop while the bridge runs | Never a partial read. **This was the legacy blanking bug** |
| I5 | Mismatch | Force a magazine `Empty` bit true while the camera sees blocks | Mismatch flagged on that magazine; both values still shown |
| I6 | Independence | Kill the bridge mid-cycle | PLC poll latency unaffected; cycle continues |

---

## J. Digital twin

| # | Test | Procedure | Expected |
|---|------|-----------|----------|
| J1 | No reference | Fresh install | *"No reference"*; export instructions; **no invented prediction** |
| J2 | Export | Run `export_twin_reference.m` | JSON written; transition and sample counts reported |
| J3 | Load | Reload in the HMI | `LOADED`; transitions listed |
| J4 | Comparison | Run a cycle | Real elapsed vs nominal; predicted state; agreement |
| J5 | Conveyor comparison | During a run | Commanded / feedback / predicted side by side with provenance chips |
| J6 | Divergence | Delay the cycle artificially | Timing mismatch with predicted and actual times |
| J7 | Caveats | Open the page | Model caveats in amber, including SCALE and the placeholder time |
| J8 | Provenance | Inspect any twin figure | Carries `LIVE` / `ASM` / `PLH` etc. |
| J9 | Synthetic honesty | Use the sample generator | First caveat states in full that the timings are fabricated |
| J10 | Stale reference | Corrupt the JSON | `ERROR` with the reason; the rest of the HMI is unaffected |

---

## K. Frontend robustness

| # | Test | Procedure | Expected |
|---|------|-----------|----------|
| K1 | Backend down at load | Open the HMI with no backend | *"Backend unreachable — retrying"*. No crash |
| K2 | Backend restart | Restart mid-session | Reconnects automatically. **No manual refresh** (E-11) |
| K3 | Fallback polling | Block SSE only | Updates continue at 2 s, marked degraded |
| K4 | Deep link | Open `#/diagnostics` directly | Loads that page |
| K5 | Refresh | F5 on any page | Same page, state restored |
| K6 | Laptop width | 1366 × 768 | Usable; no horizontal scroll |
| K7 | Wide monitor | 2560 × 1440 | Uses the width |
| K8 | Console | Run for 10 minutes | No errors |
| K9 | Re-render scope | React DevTools profiler | A sensor change re-renders the sensor components, not the whole tree |
| K10 | Reduced motion | Enable the OS setting | Animations stop; state still readable via colour and label |

---

## L. Regression guards

Run before any release.

```bash
cd frontend && npm run typecheck        # must be clean
cd frontend && npm run build            # must succeed
python tools/selftest.py --port 5055    # 47/47
```

| # | Guard | Why it exists |
|---|-------|---------------|
| L1 | No bare `NaN` in `/api/state` | An uninitialised PLC Real produced invalid JSON, silently killing the browser stream |
| L2 | Start writes quantities before `CMD_START` | Otherwise the PLC can start on stale quantities |
| L3 | `lastConfirmedStep < 28` early in a cycle | Guards the level-vs-edge sequence bug |
| L4 | Cache never optimistically patched | Guards the false-confirmation bug (E-10) |
| L5 | `use_reloader=False` | A fork means a second Snap7 client |
| L6 | Registry parses 121 documented tags | Guards the stdlib xlsx reader against pandas parity |
