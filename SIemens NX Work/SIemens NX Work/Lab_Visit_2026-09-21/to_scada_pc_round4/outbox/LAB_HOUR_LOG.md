# Lab log — Monday 2026-09-21

Write the **clock time** at the start and end of each test. The SCADA-PC
session uses those times to pull out exactly what the PLC saw. No time, no
extraction, so the times matter more than the notes.

Recording session started at: __15:02:42__  Restart due at: ~~16:02~~ done 15:59 / __16:59__ / __17:59__

Sessions today (all tags, 0.100 s, deadband 0.001):
| # | uid | start | end | samples |
|---|---|---|---|---|
| 1 | `17b99f885bc848ca` | 15:02:42.917 | 15:58:55.454 COMPLETED | 21,528 |
| 2 | `bf36673c8d2f4c2e` | 15:59:00.839 | ACTIVE — expires 16:59:00 | running |

Gap between sessions: 5.4 s (15:58:55.5 – 15:59:00.8). Cell was in FAULT, nothing lost.
Database in use: `C:\Users\DELL\Desktop\new_scada\scada_platform\data\scada_history.db`
(NOTE: the scripts' auto-pick chooses the WRONG database today — it picks the stale
2026-09-10 file in `new_scada\data\`. Always pass `--db` with the path above.)

| # | Test | Start | End | What the PLC saw | Capture file |
|---|---|---|---|---|---|
| 1 | Recorder check | 15:02:42 | — | PASS. Real PLC, 4.26–4.38 bar, all tags 0.1 s | `recorder_check_1505` |
| 2 | 50 mm cycle | 15:54:19 | 15:55:06 | Station 1 clean (PX1 2.517 s). **Stalled step 23** — plate never rose, SV 7 never fired | `cycle_E_step23stall_1554` |
| 3 | 50 mm cycle | 15:59:43 | 16:01:12 | **BEST OF DAY.** Full engraved route incl. SV 7, plate up/down, SV 11, SV 12, PX 9. Faulted to RECOVERY_REQUIRED by the false conveyor-2 motion fault, so no `cycle_history` row | `cycle_A_engraved_1559` |
| 4 | 50 mm cycle | 16:02:07 | 16:02:54 | Station 1 clean (PX1 2.297 s). **Stalled step 23** | `cycle_B_step23stall_1602` |
| 5 | 50 mm cycle | 16:11:01 | 16:11:48 | Station 1 clean (PX1 2.289 s). **Stalled step 23** | `cycle_C_step23stall_1611` |
| 6 | — | | | not run — time | |
| 7 | — | | | not run — time | |
| 8 | Bypass cycle. **Which HMI setting?** | | | **NOT RUN.** No bypass cycle today — STEP 4 has no data. Question unanswered | — |
| 9 | Compartment-4 dispense | | | **NOT RUN** | — |
| 10 | Belt 3 timing | | | **NOT RUN** | — |
| 11 | Run by hand | 15:20:51 | 16:04:05 | Manual SV 2 (15:20:51, 15:26:14), manual conveyors 1/2/3 (14:41–14:43), manual SV 7 (16:03:42, 16:03:48), manual SV 9/SV 10/SV 13 | various |
| 12 | **25 mm / MAG_2 cycle** | 15:15:21 | 15:15:52 | MAG_2 pushes, block goes straight to PX 2, **PX 1 never fires, stalled step 7**. Same on 2026-09-10 | `cycle_D_25mm_mag2_1515` |
| 13 | **CONTROL: cycle with NO block** | 16:15:11 | 16:15:42 | **No PX 1 and no PX 2/3/4/5/6 at all.** Proves the prox chain only fires on a real block | `control_EMPTY_no_block_1615` |
| 14 | PX 1 static test (block placed by hand) | 15:24:16 | 15:25:51 | PX 1 True for 95.088 s. Sensor, wiring and PLC read all confirmed good | `px1_static_test` |
| 15 | 50 mm cycle — last of the day | 16:30:18 | 16:30:38 | Station 1 clean (PX1 2.332 s). **Belt-1 index 2.006 s** — block left belt 1 again. Killed by the conveyor-2 motion fault at 16:30:37.882 | `cycle_F_final_1630` |

## Answers still owed to the model side

- **Bypass cycle HMI setting — NOT ANSWERED.** No bypass cycle was run.
- **Which valve drives which cylinder (Job 5a)** — still unrecorded. SV 1 = MAG_1,
  SV 2 = MAG_2 is the only mapping established today, and only by correlation.
- **Where prox 7's LED lights (Job 1)** — not recorded.

## Findings

Full write-up in `outbox/FINDINGS_2026-09-21.md`. The three that matter:

1. **Belt 1 runs ~41% faster than on 2026-09-10** — index 1.81 s vs 3.09 s, with
   identical PLC setpoints (180.0 both days). Drive-side or mechanical. This is
   why the block overruns the end of belt 1.
2. **A false "conveyor: run output ON, no encoder motion" fault kills every
   cycle** before it can be written to `cycle_history`, which is why the
   extractor found nothing usable.
3. **PX 8 is faulty** — chattered 100+ times with the line completely empty.

## Rules at the machine

- **SV7/SV8 and SV9/SV10 are latching valves.** Every extend needs its retract
  before moving on, or the next cycle starts with a rod out.
- **Do not touch any flow-control needle valve.** They set the rod speeds.
- **Do not change the PLC program or `engraving_power`.** Only the person
  responsible for the cell switches things on.
- **Manual button tests go after the automatic cycles, not in between.** A
  cycle record can run on into them (2026-09-10). The extractor now cuts them
  off, but a clean record needs no cut.
- **Video:** normal mode, not slow motion, with a stopwatch or clock in frame.
