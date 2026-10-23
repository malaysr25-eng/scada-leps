"""
Diagnostics: turn the Errors sheet's unreproducible complaints into detectors.

Each detector below exists because of a specific line in
``Industry 4.0_5.0 Lab data.xlsx`` sheet ``Errors``. None of them fixes a
mechanical fault -- they make the fault visible, timestamped and attributable,
which is the difference between "actuator 11 sometimes doesn't move" and
"actuator 11's coil was commanded at 14:02:16.782, the PLC confirmed the bit,
and proximity sensor 5 never rose within 8 s".

DETECTORS
---------
chatter              a tag toggling far faster than any command rate     -> E-18
command_not_reflected a manual write the PLC overwrote                   -> E-10
run_without_motion   conveyor away from Set_Position, encoder reads zero -> E-07
pressure_starved     air pressure unhealthy while the cycle is running   -> E-02/E-14
stale_data           values on screen older than the staleness budget    -> E-11
sequence_stall       raised by the sequence tracker, surfaced here       -> E-19/E-20
"""

from __future__ import annotations

import time
from typing import Any, Dict, List, Optional

from backend.plc.service import CMD_MISMATCH, CMD_TIMEOUT


def _is_number(value: Any) -> bool:
    """True for a real numeric reading. Bools are PLC bits, not measurements."""
    return isinstance(value, (int, float)) and not isinstance(value, bool)


class Diagnostics:
    def __init__(self, plc, history, event_log, machine, config: Optional[dict] = None) -> None:
        self.plc = plc
        self.history = history
        self.events = event_log
        self.machine = machine
        cfg = config or {}
        self.chatter_window = float(cfg.get("chatter_window_s", 30.0))
        self.chatter_threshold = int(cfg.get("chatter_threshold", 8))
        self.stale_budget = float(cfg.get("stale_budget_s", 3.0))
        self.motion_grace = float(cfg.get("motion_grace_s", 2.0))
        # How far Current_Position_Fb may sit from Set_Position before the axis
        # counts as "commanded to move". The 2026-09-21 capture shows the axes
        # settling within ~0.25 of target (2.25 -> 2.0, 30.15 -> 30.0), so this
        # sits just above the observed overshoot.
        self.position_tolerance = float(cfg.get("position_tolerance", 0.5))

        self._run_since: Dict[int, float] = {}
        self._findings: List[dict] = []

    # ------------------------------------------------------------------

    def evaluate(self, roles: Dict[str, Any], running: bool) -> List[dict]:
        findings: List[dict] = []
        findings.extend(self._chatter())
        findings.extend(self._command_not_reflected())
        findings.extend(self._run_without_motion(roles))
        findings.extend(self._pressure(roles, running))
        findings.extend(self._staleness())
        self._findings = findings
        return findings

    def findings(self) -> List[dict]:
        return list(self._findings)

    # -- detectors ------------------------------------------------------

    def _chatter(self) -> List[dict]:
        out = []
        for entry in self.history.chatter_report(self.chatter_window, self.chatter_threshold):
            tag = self.plc.registry.get(entry["tagId"])
            label = tag.short if tag else entry["tagId"]
            plc_driven = entry["sources"] == ["plc"]

            out.append({
                "key": "chatter.%s" % entry["tagId"],
                "severity": "WARNING",
                "title": "%s is toggling rapidly" % label,
                "detail": (
                    "%d transitions in %.0f s. Attribution: %s."
                    % (entry["count"], entry["windowSeconds"], ", ".join(entry["sources"]))
                    + (
                        " No command from this application was in flight, so the "
                        "PLC program or the field wiring is driving it."
                        if plc_driven else ""
                    )
                ),
                "tagId": entry["tagId"],
                "address": tag.address if tag else None,
                "count": entry["count"],
                "issueRef": "E-18",
                "at": entry["lastAt"],
            })
        return out

    def _command_not_reflected(self) -> List[dict]:
        out = []
        for cmd in self.plc.recent_commands(limit=30):
            if cmd["state"] not in (CMD_MISMATCH, CMD_TIMEOUT):
                continue
            if time.time() - (cmd.get("settledAt") or 0) > 120:
                continue
            tag = self.plc.registry.get(cmd["tagId"])
            out.append({
                "key": "command.%s" % cmd["id"],
                "severity": "WARNING",
                "title": "Command to %s was not held by the PLC"
                         % (tag.short if tag else cmd["tagId"]),
                "detail": cmd.get("error")
                          or "Wrote %r; PLC reads %r." % (cmd["requested"], cmd["observed"]),
                "tagId": cmd["tagId"],
                "address": cmd["address"],
                "commandId": cmd["id"],
                "issueRef": "E-10",
                "at": cmd.get("settledAt"),
            })
        return out

    def _run_without_motion(self, roles: Dict[str, Any]) -> List[dict]:
        """
        A conveyor axis was told to go somewhere and the encoder says it did not.

        Errors sheet 2026-08-19: "the speed of conveyer 2 randomly start/stop
        responding to changes to the speed on the dashboard". The workaround in
        use is turning the physical knob -- which is itself evidence that the
        commanded value and the actual motion are decoupled somewhere.

        WHY THIS IS NOT GATED ON THE RUN COIL
        -------------------------------------
        It was, and it faulted every good cycle on the machine.

        ``Conveyor1..3`` are *station enables*, not motor-running signals. In
        the 2026-09-21 lab capture (cycle ``C0004-155943``) conveyor 2's coil
        was ON for 66.1 s -- 16:00:00.649 to 16:01:06.728 -- spanning the plate
        rise, the engraving and the plate fall, and for 63.8 s of that the axis
        was correctly parked at position 2.0 with zero velocity. The old check
        fired after 2 s of that, raised a FAULT, and drove
        AUTO_RUNNING -> FAULT -> RECOVERY_REQUIRED. The cycle then never closed
        as COMPLETED, no ``cycle_history`` row was written, and the timings
        extractor could not see a single one of the day's good cycles.
        See FINDINGS_2026-09-21.md sections 4 and 10.

        The honest "motion was commanded" signal in the tag list is the
        *position error*: ``Set_Position`` is where the PLC has told the axis to
        be, ``Current_Position_Fb`` is where it is. The same capture shows the
        pattern plainly -- ``set_position 30.0 -> 2.0`` and the axis sweeps away
        at -47 counts/s, then sits at 2.0 until ``set_position 2.0 -> 30.0``
        sends it back. Zero velocity while it is already at its target is
        correct behaviour and is no longer reported.

        ``Goto_Position`` would be the obvious gate and is deliberately not used:
        it does not appear anywhere in the 2026-09-21 captures, so nothing
        establishes how it behaves on this machine.
        """
        out = []
        now = time.time()
        for i in (1, 2, 3):
            running = roles.get("conveyor.%d.running" % i) is True
            feedback = roles.get("conveyor.%d.velocity_fb" % i)
            target = roles.get("conveyor.%d.set_position" % i)
            actual = roles.get("conveyor.%d.position_fb" % i)
            commanded = roles.get("conveyor.%d.set_velocity" % i)

            error = (
                abs(target - actual)
                if _is_number(target) and _is_number(actual)
                else None
            )

            # All four must hold before zero feedback means anything: the
            # station is enabled, the axis is away from its commanded position,
            # and a non-zero speed was asked for.
            #
            # A conveyor with no position feedback in the registry yields
            # error=None and is never faulted here. That is deliberate: without
            # a target to compare against there is no way to tell a stalled
            # axis from a parked one, and guessing produced the failure above.
            commanded_to_move = (
                running
                and error is not None
                and error > self.position_tolerance
                and _is_number(commanded)
                and abs(commanded) > 1e-6
            )

            if not commanded_to_move:
                self._run_since.pop(i, None)
                continue

            # The clock starts when the axis was asked to move, not when the
            # station was enabled.
            started = self._run_since.setdefault(i, now)
            if now - started < self.motion_grace:
                continue  # let the drive ramp up before judging it

            if _is_number(feedback) and abs(feedback) < 1e-6:
                out.append({
                    "key": "conveyor.%d.no_motion" % i,
                    "severity": "FAULT",
                    "title": "Conveyor %d: commanded to move, no encoder motion" % i,
                    "detail": (
                        "Set_Position is %s and Current_Position_Fb is %s, a "
                        "position error of %.2f held for %.1f s, and "
                        "Current_Velocity_Fb still reads 0. Commanded speed is "
                        "%s. Check the drive enable, the stepper driver and the "
                        "Set_Velocity path."
                        % (target, actual, error, now - started, commanded)
                    ),
                    "issueRef": "E-07",
                    "at": now,
                })
        return out

    def _pressure(self, roles: Dict[str, Any], running: bool) -> List[dict]:
        out = []
        if roles.get("pressure.low_alarm") is True:
            out.append({
                "key": "pressure.low_alarm",
                "severity": "FAULT",
                "title": "Pneumatic pressure low alarm",
                "detail": "Reading %s bar. Cylinders may stall mid-stroke."
                          % roles.get("pressure.value"),
                "issueRef": "E-02",
                "at": time.time(),
            })
        elif running and roles.get("safety.air_pressure_ok") is False:
            out.append({
                "key": "pressure.unhealthy_while_running",
                "severity": "WARNING",
                "title": "Air pressure not confirmed healthy during a cycle",
                "detail": "Air_Pressure_ok is FALSE while the cycle is running. "
                          "Cylinder strokes may be incomplete.",
                "issueRef": "E-02",
                "at": time.time(),
            })
        return out

    def _staleness(self) -> List[dict]:
        stale = self.plc.stale_seconds()
        if stale == float("inf"):
            return [{
                "key": "plc.never_connected",
                "severity": "FAULT",
                "title": "No successful PLC read yet",
                "detail": "Link state: %s. %s"
                          % (self.plc.connection, self.plc._health.last_error or ""),
                "issueRef": "E-11",
                "at": time.time(),
            }]
        if stale > self.stale_budget:
            return [{
                "key": "plc.stale",
                "severity": "WARNING",
                "title": "PLC values are stale",
                "detail": "Last successful read was %.1f s ago (budget %.1f s). "
                          "Everything on screen is the last known good value."
                          % (stale, self.stale_budget),
                "issueRef": "E-11",
                "at": time.time(),
            }]
        return []

    # ------------------------------------------------------------------

    def default_watch_list(self) -> List[str]:
        """
        The tags the Errors sheet actually names, pre-pinned so an engineer
        opening Diagnostics is already looking at the right signals.
        """
        wanted_roles = [
            "valve.8.state", "manual.valve.8",          # E-18 random toggling
            "valve.7.state", "manual.valve.7",          # E-06/E-09 alignment
            "valve.11.state", "manual.valve.11",        # E-04 no movement
            "valve.12.state", "manual.valve.12",        # E-08 partial stroke
            "conveyor.2.set_velocity", "conveyor.2.velocity_fb",
            "conveyor.2.running",                       # E-07
            "safety.emergency_healthy", "safety.engraving_plate_home",
            "sensor.pgm_up_limit", "sensor.pgm_low_limit",  # E-02/E-14
            "cmd.start", "status.cycle_completed",
        ]
        out = []
        for role in wanted_roles:
            tag = self.plc.registry.role(role)
            if tag:
                out.append(tag.id)
        return out
