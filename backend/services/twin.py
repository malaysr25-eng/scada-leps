"""
Digital twin adapter: MATLAB/Simulink reference trajectory vs the live machine.

WHY A REFERENCE TRAJECTORY, NOT CO-SIMULATION
---------------------------------------------
The supplied model is a batch simulator, not a real-time service.
``run_factory_simulation`` integrates a whole 31.08 s cycle with RK4 and hands
back a LOG struct logged at 200 Hz. There is no stepping API, no server, and
the README is explicit that runtime is not a design goal ("A change that makes
the model faster but less faithful is a regression here").

Wiring a browser to a MATLAB Engine session in that shape would mean either
rewriting the validated solver into a stepped one -- forbidden by the brief and
by good sense -- or blocking the HMI for 30 s per cycle.

So the integration is:

    MATLAB  ->  tools/export_twin_reference.m  ->  twin_reference.json
                                                          |
                          this adapter aligns it to the live cycle clock
                                                          |
                                     predicted vs actual, per signal

The exporter reads ``LOG`` and writes plain JSON. It does not modify a single
file of the physics model. Re-export whenever parameters change.

WHAT THE COMPARISON IS AND IS NOT
---------------------------------
It is a *nominal* trajectory: one deterministic run under the model's current
parameters. The model documents itself as having 69 unmeasured parameters, a
``SCALE`` that is "CONFIRMED INCORRECT", 12.5 s of placeholder operator time in
a 31.08 s cycle, and zero modelled variability. Divergence between real and
predicted therefore means "these two disagree", never "the machine is wrong".

Every twin figure carries a provenance tag from the model's own scheme
(MEA/CAL/JAN/COMM/EST/ASM/PLH) so nothing on screen can be mistaken for a
measurement.
"""

from __future__ import annotations

import json
import os
import threading
import time
from typing import Any, Dict, List, Optional

# Provenance vocabulary, taken from FactoryParams.m / INPUTS_REQUIRED.md.
PROVENANCE = {
    "MEA": ("Measured", "Measured on the real cell."),
    "CAL": ("Calculated", "Derived from other parameters; recomputes itself."),
    "JAN": ("Catalogue", "Janatics catalogue figure -- a compatible candidate "
                         "part, NOT a component confirmed to be installed."),
    "COMM": ("Commissioning", "A setting read off the machine, not a part spec."),
    "EST": ("Estimated", "Engineering estimate from typical data."),
    "ASM": ("Assumed", "Engineering assumption -- appears in no source."),
    "PLH": ("Placeholder", "Known to be wrong; must be replaced with a "
                           "measurement before the number means anything."),
    "REF": ("Reference layout", "From the reference layout script; inherits SCALE."),
    "LIVE": ("Live PLC", "Read from the PLC this poll."),
}

UNAVAILABLE = "UNAVAILABLE"
LOADED = "LOADED"
ERROR = "ERROR"


class TwinAdapter:
    def __init__(self, config: dict, event_log) -> None:
        self.events = event_log
        self.reference_path = config.get("reference_path", "")
        self.enabled = bool(config.get("enabled", True))
        self.mismatch_tolerance_s = float(config.get("mismatch_tolerance_s", 2.0))
        self.speed_tolerance = float(config.get("speed_tolerance", 0.05))
        # Same meaning and default as diagnostics.position_tolerance: how far
        # an axis may sit from Set_Position and still count as parked.
        self.position_tolerance = float(config.get("position_tolerance", 0.5))
        # And diagnostics.motion_grace_s: let the drive ramp up before its
        # speed is compared, or every index logs a mismatch on its first poll.
        self.motion_grace_s = float(config.get("motion_grace_s", 2.0))
        self._moving_since: Dict[int, float] = {}

        self._lock = threading.RLock()
        self._reference: Optional[dict] = None
        self._status = UNAVAILABLE
        self._error = ""
        self._loaded_at: Optional[float] = None
        self._mismatches: List[dict] = []
        self._announced: set = set()

    # ------------------------------------------------------------------

    def load(self) -> bool:
        if not self.enabled:
            self._status = UNAVAILABLE
            self._error = "Digital twin integration is disabled in config."
            return False

        if not self.reference_path or not os.path.exists(self.reference_path):
            self._status = UNAVAILABLE
            self._error = (
                "No exported twin reference at %s. Run "
                "tools/export_twin_reference.m in MATLAB to generate it."
                % (self.reference_path or "<unset>")
            )
            return False

        try:
            with open(self.reference_path, "r", encoding="utf-8") as fh:
                data = json.load(fh)
        except (json.JSONDecodeError, OSError) as exc:
            self._status = ERROR
            self._error = "Could not read twin reference: %s" % exc
            self.events.warning("twin", self._error)
            return False

        with self._lock:
            self._reference = data
            self._status = LOADED
            self._error = ""
            self._loaded_at = time.time()

        self.events.info(
            "twin",
            "Digital twin reference loaded: %d transitions, nominal cycle %.2f s"
            % (len(data.get("transitions", [])), data.get("cycleTime", 0.0)),
        )
        return True

    # ------------------------------------------------------------------

    @property
    def available(self) -> bool:
        return self._status == LOADED and self._reference is not None

    def connection_state(self) -> str:
        return {
            LOADED: "CONNECTED",
            ERROR: "DEGRADED",
            UNAVAILABLE: "DISCONNECTED",
        }[self._status]

    # ------------------------------------------------------------------

    def predicted_at(self, elapsed: float) -> Dict[str, Any]:
        """Sample the reference trajectory at a cycle-relative time."""
        if not self.available:
            return {}

        ref = self._reference or {}
        series = ref.get("series", {})
        times = series.get("t") or []
        if not times:
            return {}

        # Nearest sample. The reference is logged at 200 Hz, so no
        # interpolation is warranted for a screen refreshed at 4 Hz.
        idx = self._nearest_index(times, elapsed)
        out: Dict[str, Any] = {"sampleIndex": idx, "sampleTime": times[idx]}

        for name, values in series.items():
            if name == "t":
                continue
            if isinstance(values, list) and idx < len(values):
                out[name] = values[idx]
        return out

    @staticmethod
    def _nearest_index(times: List[float], target: float) -> int:
        if target <= times[0]:
            return 0
        if target >= times[-1]:
            return len(times) - 1
        lo, hi = 0, len(times) - 1
        while lo < hi - 1:
            mid = (lo + hi) // 2
            if times[mid] < target:
                lo = mid
            else:
                hi = mid
        return lo if abs(times[lo] - target) <= abs(times[hi] - target) else hi

    def expected_state_at(self, elapsed: float) -> Optional[dict]:
        if not self.available:
            return None
        for entry in reversed(self._reference.get("transitions", [])):
            if entry.get("t", 0.0) <= elapsed:
                return entry
        return None

    def expected_transition(self, state_name: str) -> Optional[dict]:
        if not self.available:
            return None
        for entry in self._reference.get("transitions", []):
            if entry.get("state") == state_name:
                return entry
        return None

    # ------------------------------------------------------------------

    def compare(
        self,
        roles: Dict[str, Any],
        elapsed: Optional[float],
        sequence_state,
        running: bool,
    ) -> dict:
        """Build the real-vs-predicted comparison shown in the twin view."""
        base = {
            "status": self._status,
            "connection": self.connection_state(),
            "error": self._error,
            "loadedAt": self._loaded_at,
            "referencePath": self.reference_path,
            "available": self.available,
            "provenanceLegend": {
                k: {"label": v[0], "meaning": v[1]} for k, v in PROVENANCE.items()
            },
            "modelCaveats": [],
            "conveyors": [],
            "signals": [],
            "mismatches": [],
            "cycle": {},
        }

        if not self.available:
            base["modelCaveats"] = [
                "No exported reference is loaded, so no prediction is shown. "
                "Everything on this page would otherwise be a guess."
            ]
            base["conveyors"] = self._conveyors_live_only(roles)
            return base

        ref = self._reference or {}
        base["modelCaveats"] = ref.get("caveats", [])
        base["modelMeta"] = ref.get("meta", {})

        predicted = self.predicted_at(elapsed) if elapsed is not None else {}
        expected_state = self.expected_state_at(elapsed) if elapsed is not None else None

        base["cycle"] = {
            "realElapsed": round(elapsed, 2) if elapsed is not None else None,
            "nominalCycleTime": ref.get("cycleTime"),
            "predictedState": (expected_state or {}).get("state"),
            "predictedStateIndex": (expected_state or {}).get("index"),
            "inferredStepKey": self._inferred_key(sequence_state),
            "agreement": self._state_agreement(sequence_state, expected_state),
            "provenance": "PLH",
            "provenanceNote": (
                "12.5 s of the model's 31.08 s nominal cycle is unmeasured "
                "operator/engraving placeholder time."
            ),
        }

        # -- conveyors --------------------------------------------------
        mismatches: List[dict] = []
        for i in (1, 2, 3):
            commanded = roles.get("conveyor.%d.set_velocity" % i)
            feedback = roles.get("conveyor.%d.velocity_fb" % i)
            run_output = roles.get("conveyor.%d.running" % i)
            predicted_speed = predicted.get("v_belt%d" % i)
            target = roles.get("conveyor.%d.set_position" % i)
            actual = roles.get("conveyor.%d.position_fb" % i)

            # The run output is a station enable, not a motor-running signal:
            # on 2026-09-21 conveyor 2's stayed ON for 63.8 s while the axis sat
            # correctly at its target with zero velocity. Only compare speeds
            # while the axis is away from Set_Position, the same gate as
            # Diagnostics._run_without_motion (E-07). With no position feedback
            # there is no way to tell moving from parked, so nothing is flagged.
            moving = (
                run_output is True
                and isinstance(target, (int, float))
                and isinstance(actual, (int, float))
                and abs(target - actual) > self.position_tolerance
            )
            if moving:
                started = self._moving_since.setdefault(i, time.time())
                moving = time.time() - started >= self.motion_grace_s
            else:
                self._moving_since.pop(i, None)

            status = "OK"
            detail = ""

            if moving and isinstance(feedback, (int, float)) and abs(feedback) < 1e-6:
                status = "MISMATCH"
                detail = "Axis is away from Set_Position but encoder feedback reads zero."
            elif (
                isinstance(commanded, (int, float))
                and isinstance(feedback, (int, float))
                and moving
                and abs(commanded) > 1e-6
                and abs(commanded - feedback) / max(abs(commanded), 1e-6) > self.speed_tolerance
            ):
                status = "DIVERGENT"
                detail = "Commanded %.3f vs feedback %.3f." % (commanded, feedback)

            if status != "OK":
                mismatches.append({
                    "key": "conveyor.%d.speed" % i,
                    "subject": "Conveyor %d" % i,
                    "status": status,
                    "detail": detail,
                })

            base["conveyors"].append({
                "index": i,
                "runOutput": run_output,
                "commanded": commanded,
                "commandedProvenance": "LIVE",
                "feedback": feedback,
                "feedbackProvenance": "LIVE",
                "predicted": predicted_speed,
                "predictedProvenance": "ASM",
                "status": status,
                "detail": detail,
                "note": (
                    "Errors sheet 2026-08-19: conveyor 2 speed intermittently "
                    "stops responding to dashboard changes. Commanded vs "
                    "feedback is the pair that settles it."
                    if i == 2 else ""
                ),
            })

        # -- pneumatics -------------------------------------------------
        live_pressure = roles.get("pressure.value")
        base["signals"].append({
            "key": "pressure.receiver",
            "label": "Receiver pressure",
            "live": live_pressure,
            "liveProvenance": "LIVE",
            "predicted": predicted.get("P_res"),
            "predictedProvenance": "ASM",
            "unit": "bar",
            "note": "Model start pressure is an assumption (5.5 bar nominal, "
                    "4.3 bar entered in the lab data sheet).",
        })

        # -- timing divergence -----------------------------------------
        if running and elapsed is not None and sequence_state.waiting_for:
            timing = self._timing_divergence(sequence_state, elapsed)
            if timing:
                mismatches.append(timing)

        base["mismatches"] = mismatches
        self._record(mismatches)
        return base

    def _conveyors_live_only(self, roles: Dict[str, Any]) -> List[dict]:
        out = []
        for i in (1, 2, 3):
            out.append({
                "index": i,
                "runOutput": roles.get("conveyor.%d.running" % i),
                "commanded": roles.get("conveyor.%d.set_velocity" % i),
                "commandedProvenance": "LIVE",
                "feedback": roles.get("conveyor.%d.velocity_fb" % i),
                "feedbackProvenance": "LIVE",
                "predicted": None,
                "predictedProvenance": None,
                "status": "NO_REFERENCE",
                "detail": "No twin reference loaded.",
            })
        return out

    @staticmethod
    def _inferred_key(sequence_state) -> Optional[str]:
        from backend.state.sequence import STEPS

        idx = sequence_state.step_index
        return STEPS[idx].twin_state if 0 <= idx < len(STEPS) else None

    def _state_agreement(self, sequence_state, expected_state) -> str:
        if not expected_state:
            return "UNKNOWN"
        inferred = self._inferred_key(sequence_state)
        if inferred is None:
            return "UNKNOWN"
        return "AGREE" if inferred == expected_state.get("state") else "DIVERGENT"

    def _timing_divergence(self, sequence_state, elapsed: float) -> Optional[dict]:
        from backend.state.sequence import STEPS

        idx = sequence_state.step_index
        if not (0 <= idx < len(STEPS)):
            return None
        step = STEPS[idx]
        if not step.twin_state:
            return None

        expected = self.expected_transition(step.twin_state)
        if not expected:
            return None

        predicted_t = expected.get("t")
        if predicted_t is None:
            return None

        delta = elapsed - predicted_t
        if delta <= self.mismatch_tolerance_s:
            return None

        return {
            "key": "timing.%s" % step.key,
            "subject": "Step %d %s" % (step.index, step.name),
            "status": "LATE",
            "detail": (
                "Twin predicts this state at t=%.2f s; the real cycle is at "
                "t=%.2f s (+%.2f s). Waiting for: %s."
                % (predicted_t, elapsed, delta, sequence_state.waiting_for)
            ),
        }

    def _record(self, mismatches: List[dict]) -> None:
        for m in mismatches:
            key = m["key"]
            if key in self._announced:
                continue
            self._announced.add(key)
            self.events.warning(
                "twin",
                "DIGITAL TWIN MISMATCH -- %s: %s" % (m["subject"], m["detail"]),
                subject=m["subject"], status=m["status"],
            )
        # Allow a mismatch to be announced again once it has gone away.
        current = {m["key"] for m in mismatches}
        self._announced &= current

    def reference_meta(self) -> dict:
        if not self.available:
            return {"available": False, "error": self._error}
        ref = self._reference or {}
        return {
            "available": True,
            "meta": ref.get("meta", {}),
            "cycleTime": ref.get("cycleTime"),
            "transitions": ref.get("transitions", []),
            "caveats": ref.get("caveats", []),
            "parameters": ref.get("parameters", []),
            "exportedAt": ref.get("exportedAt"),
            "seriesNames": sorted(
                k for k in (ref.get("series") or {}).keys() if k != "t"
            ),
        }
