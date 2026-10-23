"""
Central machine state: lifecycle, control ownership, restart prerequisites.

TWO ORTHOGONAL CONCEPTS, DELIBERATELY KEPT APART
------------------------------------------------
*Lifecycle* is **derived** from PLC tags on every poll. It is what the machine
is doing. The HMI cannot set it.

*Mode* (AUTO / MANUAL / MAINTENANCE) is **owned by this backend**. It is who is
allowed to command what. The PLC has no mode tag, so inventing one would be a
fabrication; instead the backend enforces ownership itself and every command is
stamped with the mode that authorised it.

Conflating the two is what let the old system have an "automatic" website and a
"manual" website issuing contradictory commands to the same coils with neither
aware of the other (Errors sheet, 17-08-2026).

LIFECYCLE STATES
----------------
DISCONNECTED       no usable PLC link; values on screen are stale
EMERGENCY_STOPPED  E-Stop circuit reports unhealthy
FAULT              a latched fault is active
RECOVERY_REQUIRED  emergency cleared but start interlocks not yet satisfied
RESETTING          a reset command is in flight
IDLE               link healthy, startup not confirmed
READY              all start interlocks healthy, no cycle running
STARTING           start issued, not yet observed running
AUTO_RUNNING       cycle in progress
COMPLETED          cycle_completed latched true
MANUAL_MODE        operator has taken manual ownership
MAINTENANCE        engineering ownership, extra commands unlocked

The frontend never freezes: even in DISCONNECTED the last known values are
retained and flagged stale, which is the specific failure recorded in the
Errors sheet for 19-08-2026 ("the scada hub ... just stops working").
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

MODE_AUTO = "AUTO"
MODE_MANUAL = "MANUAL"
MODE_MAINTENANCE = "MAINTENANCE"
VALID_MODES = (MODE_AUTO, MODE_MANUAL, MODE_MAINTENANCE)

ST_DISCONNECTED = "DISCONNECTED"
ST_EMERGENCY = "EMERGENCY_STOPPED"
ST_FAULT = "FAULT"
ST_RECOVERY = "RECOVERY_REQUIRED"
ST_RESETTING = "RESETTING"
ST_IDLE = "IDLE"
ST_READY = "READY"
ST_STARTING = "STARTING"
ST_RUNNING = "AUTO_RUNNING"
ST_COMPLETED = "COMPLETED"
ST_MANUAL = "MANUAL_MODE"
ST_MAINTENANCE = "MAINTENANCE"

# States in which normal process commands must be blocked.
BLOCKING_STATES = (ST_DISCONNECTED, ST_EMERGENCY)


@dataclass
class ChecklistItem:
    key: str
    label: str
    role: Optional[str]
    satisfied: Optional[bool]
    required: bool
    detail: str = ""

    def to_dict(self) -> dict:
        return {
            "key": self.key,
            "label": self.label,
            "role": self.role,
            "satisfied": self.satisfied,
            "required": self.required,
            "detail": self.detail,
        }


@dataclass
class MachineState:
    mode: str = MODE_AUTO
    lifecycle: str = ST_DISCONNECTED
    previous_lifecycle: str = ST_DISCONNECTED
    lifecycle_since: float = field(default_factory=time.time)

    cycle_id: Optional[str] = None
    cycle_started_at: Optional[float] = None
    cycle_ended_at: Optional[float] = None
    cycle_count: int = 0

    # Snapshot preserved at the instant an emergency or fault was detected.
    frozen_context: Optional[dict] = None

    reset_pending_until: float = 0.0

    def to_dict(self) -> dict:
        return {
            "mode": self.mode,
            "lifecycle": self.lifecycle,
            "previousLifecycle": self.previous_lifecycle,
            "lifecycleSince": self.lifecycle_since,
            "lifecycleElapsed": round(time.time() - self.lifecycle_since, 2),
            "cycleId": self.cycle_id,
            "cycleStartedAt": self.cycle_started_at,
            "cycleEndedAt": self.cycle_ended_at,
            "cycleCount": self.cycle_count,
            "cycleElapsed": (
                round(time.time() - self.cycle_started_at, 2)
                if self.cycle_started_at and not self.cycle_ended_at
                else None
            ),
            "frozenContext": self.frozen_context,
        }


class MachineModel:
    """Derives lifecycle from live roles and owns mode transitions."""

    def __init__(self, event_log, plc, sequence_tracker) -> None:
        self.events = event_log
        self.plc = plc
        self.sequence = sequence_tracker
        self.state = MachineState()
        self._last_roles: Dict[str, Any] = {}

    # ------------------------------------------------------------------
    # role access
    # ------------------------------------------------------------------

    def roles(self) -> Dict[str, Any]:
        """Resolve every semantic role to its current cached value."""
        out: Dict[str, Any] = {}
        values = self.plc.values()
        for role, tag in self.plc.registry.by_role.items():
            out[role] = values.get(tag.id)
        self._last_roles = out
        return out

    # ------------------------------------------------------------------
    # safety view
    # ------------------------------------------------------------------

    def safety(self, roles: Dict[str, Any]) -> dict:
        """
        Safety signals, kept strictly separate by origin.

        `hardwareEmergencyHealthy` comes from the safety-relay loop
        (Start_interlocks.Emergency Healthy). It reports a certified circuit.
        Nothing in this application can drive it, and no button here is a
        substitute for it.
        """
        emergency_healthy = roles.get("safety.emergency_healthy")
        emergency_input = roles.get("safety.emergency_input")

        return {
            "hardwareEmergencyHealthy": emergency_healthy,
            "emergencyInputActive": emergency_input,
            "emergencyActive": emergency_healthy is False,
            "startupHealthy": roles.get("safety.startup_healthy"),
            "airPressureHealthy": roles.get("safety.air_pressure_ok"),
            "allCylindersHome": roles.get("safety.all_cylinders_home"),
            "engravingPlateHome": roles.get("safety.engraving_plate_home"),
            "pressureLowAlarm": roles.get("pressure.low_alarm"),
            "pressureHighAlarm": roles.get("pressure.high_alarm"),
            "pressureBar": roles.get("pressure.value"),
            "note": (
                "Emergency status is READ from the PLC safety circuit. This "
                "web application provides no functional-safety stop and is not "
                "a substitute for the hardware E-Stop."
            ),
        }

    # ------------------------------------------------------------------
    # restart checklist
    # ------------------------------------------------------------------

    def restart_checklist(self, roles: Dict[str, Any]) -> List[ChecklistItem]:
        connected = self.plc.is_live
        items = [
            ChecklistItem(
                "plc", "PLC connected", None, connected, True,
                "" if connected else "Link state: %s" % self.plc.connection,
            ),
            ChecklistItem(
                "emergency", "Emergency circuit healthy", "safety.emergency_healthy",
                roles.get("safety.emergency_healthy") is True, True,
                "Reset the physical E-Stop, then acknowledge here."
                if roles.get("safety.emergency_healthy") is not True else "",
            ),
            ChecklistItem(
                "air", "Air pressure healthy", "safety.air_pressure_ok",
                roles.get("safety.air_pressure_ok") is True, True,
            ),
            ChecklistItem(
                "cylinders", "All cylinders at home position",
                "safety.all_cylinders_home",
                roles.get("safety.all_cylinders_home") is True, True,
            ),
            ChecklistItem(
                "plate", "Engraving plate at home position",
                "safety.engraving_plate_home",
                roles.get("safety.engraving_plate_home") is True, True,
                "Errors sheet records this sticking at the top on 2026-08-19. "
                "If it will not confirm, jog the plate down in Maintenance mode.",
            ),
            ChecklistItem(
                "startup", "Startup diagnostics healthy", "safety.startup_healthy",
                roles.get("safety.startup_healthy") is True, True,
            ),
            ChecklistItem(
                "faults", "No active faults", None,
                len(self.events.active_faults()) == 0, False,
                "Acknowledge or clear active faults before restarting.",
            ),
        ]
        return items

    def can_restart(self, roles: Dict[str, Any]) -> tuple:
        items = self.restart_checklist(roles)
        blockers = [i for i in items if i.required and i.satisfied is not True]
        return (not blockers), blockers

    # ------------------------------------------------------------------
    # order validation -- the rule from the Errors sheet, 19-08-2026
    # ------------------------------------------------------------------

    @staticmethod
    def validate_order(qty_25: int, qty_50: int, max_total: Optional[int] = None) -> tuple:
        """
        Returns (ok, reason). Enforced here so the frontend cannot bypass it by
        POSTing directly -- the Errors sheet records the machine starting with
        both quantities at zero and then failing to terminate.
        """
        try:
            q25 = int(qty_25)
            q50 = int(qty_50)
        except (TypeError, ValueError):
            return False, "Quantities must be whole numbers."

        if q25 < 0 or q50 < 0:
            return False, "Quantities cannot be negative."

        total = q25 + q50
        if total <= 0:
            return False, "Select at least one product before starting the cycle."

        if max_total is not None and total > max_total:
            return False, "Total quantity %d exceeds the configured maximum of %d." % (
                total, max_total,
            )

        if q25 > 32767 or q50 > 32767:
            return False, "Quantity exceeds the S7 Int range (max 32767)."

        return True, ""

    # ------------------------------------------------------------------
    # mode
    # ------------------------------------------------------------------

    def set_mode(self, mode: str, operator: str = "local") -> tuple:
        mode = (mode or "").upper()
        if mode not in VALID_MODES:
            return False, "Unknown mode %r" % mode

        roles = self._last_roles or self.roles()

        # Refuse to hand manual control to an operator while an automatic
        # cycle is live: that is exactly the two-websites-fighting failure.
        if mode in (MODE_MANUAL, MODE_MAINTENANCE) and self._cycle_running(roles):
            return False, (
                "An automatic cycle is running. Let it finish, or reset the "
                "cycle, before taking manual control."
            )

        if self.state.mode == mode:
            return True, ""

        previous = self.state.mode
        self.state.mode = mode
        self.events.command(
            "mode", "Control mode changed %s -> %s" % (previous, mode),
            source=operator, previous=previous, mode=mode,
        )
        return True, ""

    # ------------------------------------------------------------------
    # lifecycle derivation -- runs on every poll
    # ------------------------------------------------------------------

    @staticmethod
    def _cycle_running(roles: Dict[str, Any]) -> bool:
        return roles.get("cmd.start") is True and roles.get("status.cycle_completed") is not True

    def update(self, roles: Dict[str, Any]) -> MachineState:
        now = time.time()
        new_state = self._derive(roles, now)

        if new_state != self.state.lifecycle:
            self._transition(new_state, roles, now)

        return self.state

    def _derive(self, roles: Dict[str, Any], now: float) -> str:
        if not self.plc.is_live:
            return ST_DISCONNECTED

        if roles.get("safety.emergency_healthy") is False:
            return ST_EMERGENCY

        if self.events.active_faults():
            return ST_FAULT

        if now < self.state.reset_pending_until:
            return ST_RESETTING

        # Recovering from an emergency/fault: interlocks must come back first.
        if self.state.lifecycle in (ST_EMERGENCY, ST_FAULT, ST_RECOVERY):
            ok, _ = self.can_restart(roles)
            if not ok:
                return ST_RECOVERY

        if self.state.mode == MODE_MAINTENANCE:
            return ST_MAINTENANCE
        if self.state.mode == MODE_MANUAL:
            return ST_MANUAL

        if roles.get("status.cycle_completed") is True:
            return ST_COMPLETED

        if roles.get("cmd.start") is True:
            # STARTING until something observable actually moves.
            if self.state.lifecycle == ST_STARTING:
                moving = any(
                    roles.get("conveyor.%d.running" % i) is True for i in (1, 2, 3)
                ) or any(
                    roles.get("valve.%d.state" % i) is True for i in range(1, 14)
                )
                if not moving and (now - self.state.lifecycle_since) < 5.0:
                    return ST_STARTING
            return ST_RUNNING

        if roles.get("safety.startup_healthy") is not True:
            return ST_IDLE

        ok, _ = self.can_restart(roles)
        return ST_READY if ok else ST_IDLE

    def _transition(self, new_state: str, roles: Dict[str, Any], now: float) -> None:
        previous = self.state.lifecycle
        self.state.previous_lifecycle = previous
        self.state.lifecycle = new_state
        self.state.lifecycle_since = now

        severity_note = ""

        if new_state == ST_EMERGENCY:
            # Preserve everything about the moment it stopped. The old SCADA
            # lost this entirely.
            self.state.frozen_context = self._freeze(roles, "emergency")
            self.events.emit(
                "EMERGENCY", "safety",
                "EMERGENCY: safety circuit reports unhealthy. Cycle terminated.",
                source="plc",
                frozenAt=now,
            )
            self.events.raise_fault(
                "safety.emergency",
                "Emergency stop active -- hardware safety circuit is unhealthy.",
                severity="EMERGENCY",
            )
        elif previous == ST_EMERGENCY:
            self.events.info(
                "safety",
                "Emergency circuit healthy again. Recovery checklist required "
                "before a cycle can start.",
            )
            self.events.clear_fault("safety.emergency")

        if new_state == ST_FAULT and previous not in (ST_FAULT, ST_EMERGENCY):
            self.state.frozen_context = self._freeze(roles, "fault")

        if new_state == ST_RUNNING and previous in (ST_READY, ST_STARTING, ST_IDLE):
            self.state.cycle_count += 1
            self.state.cycle_id = "C%04d-%s" % (
                self.state.cycle_count, time.strftime("%H%M%S", time.localtime(now)),
            )
            self.state.cycle_started_at = now
            self.state.cycle_ended_at = None
            self.sequence.reset("new cycle %s" % self.state.cycle_id)
            self.events.info(
                "cycle", "Cycle %s started" % self.state.cycle_id,
                cycleId=self.state.cycle_id,
            )

        if new_state == ST_COMPLETED and self.state.cycle_started_at:
            self.state.cycle_ended_at = now
            self.events.info(
                "cycle",
                "Cycle %s completed in %.1f s"
                % (self.state.cycle_id, now - self.state.cycle_started_at),
                cycleId=self.state.cycle_id,
                durationSeconds=round(now - self.state.cycle_started_at, 2),
            )

        if new_state == ST_DISCONNECTED:
            self.events.warning(
                "connection",
                "PLC link lost. Displayed values are the last known good values "
                "and are now marked stale.",
                source="plc",
            )
        elif previous == ST_DISCONNECTED:
            self.events.info("connection", "PLC link restored; live updates resumed.")

        self.events.info(
            "lifecycle", "State %s -> %s%s" % (previous, new_state, severity_note),
            previous=previous, state=new_state,
        )

    def _freeze(self, roles: Dict[str, Any], reason: str) -> dict:
        """Capture the machine picture at the instant things went wrong."""
        from backend.state.sequence import STEPS

        seq = self.sequence.state
        step = STEPS[seq.step_index] if 0 <= seq.step_index < len(STEPS) else None
        return {
            "reason": reason,
            "at": time.time(),
            "lifecycle": self.state.lifecycle,
            "mode": self.state.mode,
            "cycleId": self.state.cycle_id,
            "sequenceStepIndex": seq.step_index,
            "sequenceStepName": step.name if step else None,
            "waitingFor": seq.waiting_for,
            "sensors": {
                k: v for k, v in roles.items() if k.startswith("sensor.")
            },
            "valves": {
                k: v for k, v in roles.items() if k.startswith("valve.")
            },
            "conveyors": {
                k: v for k, v in roles.items() if k.startswith("conveyor.")
            },
            "safety": {
                k: v for k, v in roles.items() if k.startswith("safety.")
            },
        }

    def mark_reset_pending(self, seconds: float = 2.0) -> None:
        self.state.reset_pending_until = time.time() + seconds
