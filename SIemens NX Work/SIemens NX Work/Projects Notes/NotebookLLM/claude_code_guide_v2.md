# Claude Code Master Integration Guide — BITS Pilani MCD Digital Twin

> **Corrections, 2026-09-19.** The file names below now match the files that exist, and the OPC UA step points at the working server, `SIemens NX Work/Tests & Claude Files/mcd_replay_server.py`. The mock server in this folder never starts its OPC UA server.

This guide provides structured prompts, test procedures, and code generation templates for using **Claude Code** alongside the BITS Pilani MCD cell dataset.

---

## 1. Quick Start Execution for Claude Code

When working with Claude Code in your local CLI or IDE:
1. Provide `mcd_cell_config_v3.json` as the structural data context.
2. Provide `mcd_master_reference_v3.md` as the domain knowledge context.
3. `mcd_cycle_simulator_v3.py` only prints the timeline. For real checks run `python -m unittest test_mcd_replay -v` in `Tests & Claude Files/`.
4. Run `SIemens NX Work/Tests & Claude Files/mcd_replay_server.py` to stream the cycle over OPC UA.

---

## 2. Recommended Claude Code Prompts

### Prompt 1: Generate S7-1200 PLC SCL Code for Latching Valves
```text
Context: I am working on the BITS Pilani MCD cell project.
Task: Write a Siemens TIA Portal SCL (Structured Control Language) Function Block (FB) for controlling double-solenoid latching valves CYL_A (SV7 extend / SV8 retract) and CYL_B (SV9 extend / SV10 retract).
Requirements:
- Enforce mutual exclusion (SV7 and SV8 cannot be active simultaneously).
- Include safety interlocks with Proximity_sensor7 and Proximity_sensor9.
- Use exact tag names from mcd_cell_config.json.
```

### Prompt 2: Extend OPC UA Server with AsyncUA
```text
Context: Use mcd_opc_ua_mock_server.py and mcd_cell_config.json.
Task: Add an OPC UA write handler that allows NX MCD to publish sensor states (e.g. Proximity_sensor6 = TRUE) back to the Python server, triggering automatic state progression in real time.
```

### Prompt 3: Unit Testing State Machine Transitions
```text
Context: Refer to mcd_cycle_simulator.py.
Task: Write pytest unit tests that verify:
1. Belt 1 stops within 0.1s of Proximity_sensor6 tripping.
2. Platform cannot lower until Engraving_Completed signal is HIGH.
3. Total Engraved route duration is strictly 75.64s +/- 0.5s.
```
