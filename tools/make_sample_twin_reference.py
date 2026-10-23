#!/usr/bin/env python
"""
Generate a SYNTHETIC twin reference, for testing the integration only.

WHAT THIS IS FOR
----------------
The real reference comes from `tools/export_twin_reference.m`, run in MATLAB
against the validated physics model. That is the only file anyone should draw
engineering conclusions from.

This script exists so the Digital Twin page, the mismatch detectors and the
provenance rendering can be exercised on a machine with no MATLAB licence --
during development, in the test checklist, and when demonstrating the HMI away
from the lab.

HOW IT AVOIDS BEING MISTAKEN FOR THE REAL THING
-----------------------------------------------
The payload it writes is deliberately, loudly marked:

  * ``meta.source`` reads "SYNTHETIC SAMPLE -- NOT FROM MATLAB".
  * ``meta.synthetic`` is true.
  * The first caveat, which the HMI renders at the top of the twin page in
    amber, states in full that the numbers are fabricated for testing.

The state list itself is real -- it is transcribed from `factory_states.m` --
but every *timing* below is invented. Timings are the whole point of the
comparison, so a synthetic reference can validate the plumbing and nothing
else.

    python tools/make_sample_twin_reference.py
"""

from __future__ import annotations

import json
import math
import os
import time

HERE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(HERE, "data", "twin_reference.json")

# The real 40-state table from factory_states.m: (key, excel_ref, guard).
# Transcribed, not invented -- only the timings below are synthetic.
STATES = [
    ("S00_INIT", "-", "immediate"),
    ("S01_CAMERA_DETECT", "1", "CAM"),
    ("S02_PUMP_CMD", "2", "immediate"),
    ("S03_PRESSURE_PREP", "3", "P_READY"),
    ("S04_DV_READY", "4", "immediate"),
    ("S05_DV_SEL_FEEDER", "5,6", "BR_RDY(1) & CHG(1)"),
    ("S06_A1_EXTEND", "7,8", "EXT(1)"),
    ("S07_PROX1_CHECK", "9", "PX(1)"),
    ("S08_A1_RETRACT", "8i", "RET(1)"),
    ("S09_CONV1_START", "10", "immediate"),
    ("S10_PROX2_CHECK", "11", "PX(2)"),
    ("S11_CONV1_STOP", "12", "immediate"),
    ("S12_DV_SEL_FEEDER2", "13,14", "BR_RDY(1) & CHG(2)"),
    ("S13_A6_EXTEND", "15,16", "EXT(2)"),
    ("S14_A6_RETRACT", "16i", "RET(2)"),
    ("S15_CONV2_START", "17", "immediate"),
    ("S16_PROX3_CHECK", "18", "PX(3)"),
    ("S17_CONV2_STOP", "19", "immediate"),
    ("S18_DV_SEL_SECOND", "20,21", "BR_RDY(2) & CHG(3)"),
    ("S19_S2A1_EXTEND", "22,23", "EXT(3)"),
    ("S20_S2A1_FEEDBACK", "24", "immediate"),
    ("S21_S2A1_RETRACT", "24i", "RET(3)"),
    ("S22_BASE_UP", "25", "immediate"),
    ("S23_HEIGHT_TOP", "26", "HS_TOP"),
    ("S24_OPERATOR_NOTIFY", "27", "timer (t_op_notice)"),
    ("S25_ENGRAVE_MANUAL", "28", "timer (t_engrave)"),
    ("S26_ENGRAVE_CONFIRM", "29", "timer (t_op_confirm)"),
    ("S27_BASE_DOWN", "30i", "immediate"),
    ("S28_HEIGHT_BOTTOM", "30", "HS_BOT"),
    ("S29_DV_SEL_THIRD", "31,32", "BR_RDY(3) & CHG(4)"),
    ("S30_S3A1_EXTEND", "33,34", "EXT(4)"),
    ("S31_S3A1_FEEDBACK", "35", "immediate"),
    ("S32_S3A1_RETRACT", "35i", "RET(4)"),
    ("S33_CONV3_START", "36*", "immediate"),
    ("S34_PROX4_FINAL", "37", "PX(4)"),
    ("S35_CONV3_STOP", "38", "immediate"),
    ("S36_DV_SEL_FOURTH", "39,40", "BR_RDY(4) & CHG(5)"),
    ("S37_S3A2_EXTEND", "41,42", "EXT(5)"),
    ("S38_S3A2_RETRACT", "42i", "RET(5)"),
    ("S39_CYCLE_COMPLETE", "-", "terminal"),
]

# Synthetic dwell per state, summing to roughly the model's documented 31.08 s
# nominal cycle. INVENTED. The real durations come from the MATLAB run.
DWELL = {
    "S24_OPERATOR_NOTIFY": 3.0,
    "S25_ENGRAVE_MANUAL": 8.0,
    "S26_ENGRAVE_CONFIRM": 1.5,
    "S07_PROX1_CHECK": 1.1,
    "S10_PROX2_CHECK": 1.6,
    "S16_PROX3_CHECK": 1.8,
    "S23_HEIGHT_TOP": 1.2,
    "S28_HEIGHT_BOTTOM": 1.2,
    "S34_PROX4_FINAL": 1.7,
}
DEFAULT_DWELL = 0.28


def build() -> dict:
    transitions = []
    t = 0.0
    for index, (key, excel_ref, guard) in enumerate(STATES):
        transitions.append({
            "t": round(t, 6),
            "index": index,
            "state": key,
            "excelRef": excel_ref,
            "guard": guard,
        })
        t += DWELL.get(key, DEFAULT_DWELL)

    cycle_time = round(t, 6)

    # 20 Hz series, matching the MATLAB exporter's rate.
    rate = 20
    n = int(cycle_time * rate) + 1
    times = [round(i / rate, 4) for i in range(n)]

    def belt_window(start_key: str, stop_key: str, speed: float):
        start = next(x["t"] for x in transitions if x["state"] == start_key)
        stop = next(x["t"] for x in transitions if x["state"] == stop_key)
        # A first-order ramp, so the trace is not a square wave.
        return [
            round(speed * (1 - math.exp(-(ts - start) / 0.35)), 5)
            if start <= ts < stop else 0.0
            for ts in times
        ]

    series = {
        "t": times,
        "v_belt1": belt_window("S09_CONV1_START", "S11_CONV1_STOP", 0.15),
        "v_belt2": belt_window("S15_CONV2_START", "S17_CONV2_STOP", 0.15),
        "v_belt3": belt_window("S33_CONV3_START", "S35_CONV3_STOP", 0.15),
        # A slow bleed-down from the model's nominal 5.5 bar start pressure.
        "P_res": [round(5.5 - 0.9 * (ts / max(cycle_time, 1e-6)), 4) for ts in times],
    }

    base_up = next(x["t"] for x in transitions if x["state"] == "S22_BASE_UP")
    base_down = next(x["t"] for x in transitions if x["state"] == "S27_BASE_DOWN")
    series["base_z"] = [
        round(0.12 if base_up <= ts < base_down else 0.0, 5) for ts in times
    ]

    return {
        "schemaVersion": 1,
        "exportedAt": time.time(),
        "exportedAtLocal": time.strftime("%Y-%m-%d %H:%M:%S"),
        "cycleTime": cycle_time,
        "complete": True,
        "transitions": transitions,
        "series": series,
        "parameters": [
            {"name": "SCALE", "tag": "ASM"},
            {"name": "D_bore", "tag": "ASM"},
            {"name": "d_rod", "tag": "ASM"},
            {"name": "t_engrave", "tag": "PLH"},
            {"name": "t_op_notice", "tag": "PLH"},
            {"name": "t_op_confirm", "tag": "PLH"},
            {"name": "v_belt_sp", "tag": "ASM"},
            {"name": "mu_k", "tag": "EST"},
            {"name": "mu_s", "tag": "EST"},
            {"name": "P_set", "tag": "JAN"},
        ],
        "caveats": [
            "SYNTHETIC SAMPLE. Every timing in this reference is fabricated to "
            "exercise the integration. It is NOT output from the MATLAB model "
            "and no engineering conclusion may be drawn from it. Generate the "
            "real reference with tools/export_twin_reference.m.",
            "SCALE is recorded as CONFIRMED INCORRECT in the lab data sheet. "
            "All predicted positions inherit that error.",
            "69 of 97 tagged parameters in the real model are unmeasured "
            "(PLH + ASM + EST). See INPUTS_REQUIRED.md.",
            "Every Janatics component is a technically compatible candidate, "
            "not a part confirmed to be installed.",
            "12.5 s of the 31.08 s nominal cycle is operator/engraving "
            "placeholder time with no measured duration.",
            "The model is deterministic and predicts zero cycle-time variation, "
            "so any real variation will read as divergence.",
            "The model has 5 cylinders and 4 proximity sensors; the real cell "
            "has 13 solenoid valves and 10 proximity sensors. The mapping "
            "between them is not recorded in any supplied source.",
        ],
        "meta": {
            "source": "SYNTHETIC SAMPLE -- NOT FROM MATLAB",
            "synthetic": True,
            "generator": "tools/make_sample_twin_reference.py",
            "stateCount": len(STATES),
            "sampleCount": n,
            "sampleRateHz": rate,
            "note": "State names and Excel references are transcribed from "
                    "factory_states.m and are accurate. All timings are invented.",
        },
    }


def main() -> int:
    payload = build()
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    tmp = OUT + ".tmp"
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(payload, fh, allow_nan=False)
    os.replace(tmp, OUT)

    print("Wrote %s" % OUT)
    print("  %d transitions, synthetic cycle %.2f s"
          % (len(payload["transitions"]), payload["cycleTime"]))
    print("\n  THIS IS A TEST FIXTURE, NOT MODEL OUTPUT.")
    print("  Replace it by running tools/export_twin_reference.m in MATLAB.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
