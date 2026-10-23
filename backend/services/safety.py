"""
Command authorisation: the gate every write passes through.

The order of checks matters and is fixed:

  1. Does the tag exist?
  2. Is the PLC link usable?
  3. Is an emergency active?
  4. Does the current mode permit this access class?
  5. Does automatic operation currently own this tag?
  6. Do the physical interlocks permit it?
  7. Is the value valid for the type and range?
  8. Does it need explicit operator confirmation?

Only after all eight does the command reach PlcService.submit_write().

The old dashboards had none of this: `/api/write/<index>` accepted any value
for any of 121 tags at any time, including while an automatic cycle was
running. That is precisely the "no communication between the manual website and
the automatic website" entry in the Errors sheet (17-08-2026), expressed as
code.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, List, Optional

from backend.plc.registry import (
    ACCESS_ENGINEERING,
    ACCESS_PROTECTED,
    ACCESS_READ_ONLY,
    ACCESS_SAFE_MANUAL,
    Tag,
)
from backend.state.machine import (
    MODE_AUTO,
    MODE_MAINTENANCE,
    MODE_MANUAL,
    ST_EMERGENCY,
    ST_DISCONNECTED,
)


@dataclass
class Decision:
    allowed: bool
    reason: str = ""
    code: str = ""
    requires_confirmation: bool = False
    risk: str = "low"          # low | medium | high
    warnings: List[str] = None

    def to_dict(self) -> dict:
        return {
            "allowed": self.allowed,
            "reason": self.reason,
            "code": self.code,
            "requiresConfirmation": self.requires_confirmation,
            "risk": self.risk,
            "warnings": self.warnings or [],
        }


def _deny(code: str, reason: str, risk: str = "low") -> Decision:
    return Decision(False, reason, code, risk=risk)


# Access classes each mode may write.
_MODE_PERMITS = {
    MODE_AUTO: set(),                                   # nothing manual in AUTO
    MODE_MANUAL: {ACCESS_SAFE_MANUAL},
    MODE_MAINTENANCE: {ACCESS_SAFE_MANUAL, ACCESS_ENGINEERING},
}

# Engineering roles an operator may also write in MANUAL: the conveyor speed
# profile only. Homing, goto and position setpoints stay MAINTENANCE-only.
_MANUAL_SPEED_ROLES = {
    "conveyor.%d.%s" % (i, suffix)
    for i in (1, 2, 3)
    for suffix in ("set_velocity", "highspeed_velocity",
                   "lowspeed_velocity", "set_highspeed")
}

# Roles the automatic sequencer owns while a cycle is live. Manual writes to
# these are refused even in MANUAL mode, because two writers on one coil is
# the failure we are removing.
_AUTO_OWNED_PREFIXES = ("manual.valve.", "manual.conveyor.")

# Commands that move something heavy, or that can drive a part into a fixture.
# Risk-based, so ordinary engineering testing is not buried under dialogs.
_HIGH_RISK_ROLES = {
    "conveyor.1.set_home", "conveyor.2.set_home", "conveyor.3.set_home",
    "conveyor.1.goto", "conveyor.2.goto", "conveyor.3.goto",
}


class CommandGate:
    def __init__(self, machine, plc, event_log, config: Optional[dict] = None) -> None:
        self.machine = machine
        self.plc = plc
        self.events = event_log
        self.config = config or {}

    # ------------------------------------------------------------------

    def evaluate(
        self,
        tag: Optional[Tag],
        value: Any,
        roles: Dict[str, Any],
        confirmed: bool = False,
        intent: str = "manual",
    ) -> Decision:
        # 1. tag exists ------------------------------------------------
        if tag is None:
            return _deny("unknown_tag", "No such tag in the registry.")

        # 2. link usable -----------------------------------------------
        if not self.plc.is_live:
            return _deny(
                "plc_offline",
                "PLC link is %s. Writes are blocked until it recovers."
                % self.plc.connection,
            )

        lifecycle = self.machine.state.lifecycle
        mode = self.machine.state.mode

        # 3. emergency --------------------------------------------------
        if lifecycle == ST_EMERGENCY:
            return _deny(
                "emergency_active",
                "Emergency stop is active. All process commands are blocked "
                "until the hardware safety circuit is healthy again.",
                risk="high",
            )
        if lifecycle == ST_DISCONNECTED:
            return _deny("plc_offline", "PLC link lost.")

        # 4. access class vs mode ---------------------------------------
        if tag.access == ACCESS_READ_ONLY:
            return _deny(
                "read_only",
                "%s is read-only. It reports state; it does not accept commands."
                % tag.short,
            )

        if tag.access == ACCESS_PROTECTED and intent != "internal":
            return _deny(
                "protected",
                "%s is safety/process-critical and cannot be written from the "
                "tag interface. Use the dedicated cycle control." % tag.short,
                risk="high",
            )

        permitted = _MODE_PERMITS.get(mode, set())
        manual_speed = mode == MODE_MANUAL and tag.role in _MANUAL_SPEED_ROLES
        if tag.access not in permitted and not manual_speed and intent != "internal":
            if mode == MODE_AUTO:
                return _deny(
                    "wrong_mode",
                    "The automatic sequencer owns the machine in AUTO mode. "
                    "Switch to MANUAL to command %s." % tag.short,
                )
            return _deny(
                "wrong_mode",
                "%s requires MAINTENANCE mode (it is classed '%s'); current "
                "mode is %s." % (tag.short, tag.access, mode),
            )

        # 5. automatic ownership ----------------------------------------
        if intent != "internal" and self._auto_owns(tag, roles):
            return _deny(
                "auto_owns",
                "An automatic cycle is in progress and owns %s. Reset the cycle "
                "before commanding it manually." % tag.short,
                risk="high",
            )

        # 6. physical interlocks ----------------------------------------
        interlock = self._interlocks(tag, value, roles)
        if interlock:
            return interlock

        # 7. value range -------------------------------------------------
        # codec.coerce() enforces the *type* at write time; it has no opinion
        # about magnitude. A velocity setpoint is the case that matters: the
        # stepper TO will accept whatever number reaches it, so a mistyped
        # "150" instead of "1.50" is a real command, not a rejected one.
        range_denial = self._range_check(tag, value)
        if range_denial:
            return range_denial

        # 8. confirmation -----------------------------------------------
        warnings: List[str] = []
        risk = "low"
        needs_confirm = False

        if tag.role in _HIGH_RISK_ROLES:
            risk = "high"
            needs_confirm = True
            warnings.append("This initiates axis motion.")

        if tag.access == ACCESS_ENGINEERING:
            risk = "medium" if risk == "low" else risk
            needs_confirm = True
            warnings.append(
                "Engineering command: it changes a setpoint the PLC program "
                "also writes."
            )

        if roles.get("safety.air_pressure_ok") is not True and self._is_pneumatic(tag):
            warnings.append(
                "Air pressure is not confirmed healthy -- the cylinder may not "
                "complete its stroke."
            )

        if needs_confirm and not confirmed:
            return Decision(
                False,
                "This command requires explicit confirmation.",
                "confirmation_required",
                requires_confirmation=True,
                risk=risk,
                warnings=warnings,
            )

        return Decision(True, "", "", False, risk, warnings)

    # ------------------------------------------------------------------

    def _auto_owns(self, tag: Tag, roles: Dict[str, Any]) -> bool:
        if not tag.role:
            return False
        if not any(tag.role.startswith(p) for p in _AUTO_OWNED_PREFIXES):
            return False
        return (
            roles.get("cmd.start") is True
            and roles.get("status.cycle_completed") is not True
        )

    @staticmethod
    def _is_pneumatic(tag: Tag) -> bool:
        return bool(tag.role and tag.role.startswith("manual.valve."))

    @staticmethod
    def _range_check(tag: Tag, value: Any) -> Optional[Decision]:
        """
        Reject a numeric write outside the tag's commissioned range.

        Two deliberate non-behaviours:

        * A tag with no ``min``/``max`` in the overlay is not range-checked.
          Inventing a bound for a drive nobody has commissioned would refuse
          legitimate commands, which is its own hazard.
        * Bools and non-numerics fall straight through. This gate is about
          magnitude; type correctness is codec.coerce()'s job.
        """
        if tag.minimum is None and tag.maximum is None:
            return None
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return None

        number = float(value)
        if number != number:  # NaN
            return _deny(
                "out_of_range",
                "%s was sent a value that is not a number." % tag.short,
                risk="medium",
            )

        unit = (" " + tag.unit) if tag.unit else ""
        if tag.minimum is not None and number < tag.minimum:
            return _deny(
                "out_of_range",
                "%s = %g%s is below the commissioned minimum of %g%s."
                % (tag.short, number, unit, tag.minimum, unit),
                risk="medium",
            )
        if tag.maximum is not None and number > tag.maximum:
            return _deny(
                "out_of_range",
                "%s = %g%s exceeds the commissioned maximum of %g%s."
                % (tag.short, number, unit, tag.maximum, unit),
                risk="medium",
            )
        return None

    def _interlocks(self, tag: Tag, value: Any, roles: Dict[str, Any]) -> Optional[Decision]:
        """
        Physical interlocks that can be justified from documented tags only.

        Note what is NOT here: there is no per-cylinder extend/retract
        interlock, because the tag list contains no reed-switch feedback for
        any cylinder. Adding one would mean inventing an address.
        """
        role = tag.role or ""

        # Never jog an axis further into an active limit switch. This mirrors
        # the guard already present in app_platform_control (1).py.
        if role.endswith(".goto") or role.endswith(".set_home"):
            if roles.get("sensor.pgm_up_limit") is True and value is True:
                return _deny(
                    "limit_active",
                    "Upper limit switch is active. Clear the limit before "
                    "commanding motion.",
                    risk="high",
                )

        # Engraving acknowledgement only means something once the plate is up.
        if role == "cmd.engraving_completed" and value is True:
            if roles.get("sensor.pgm_up_limit") is not True:
                return Decision(
                    True, "", "",
                    requires_confirmation=False,
                    risk="medium",
                    warnings=[
                        "The plate upper-limit switch is not active, so the "
                        "engraving station may not be in position. Acknowledging "
                        "now will advance the sequence anyway."
                    ],
                )

        return None

    # ------------------------------------------------------------------

    def describe_mode(self) -> dict:
        mode = self.machine.state.mode
        return {
            "mode": mode,
            "permits": sorted(_MODE_PERMITS.get(mode, set())),
            "description": {
                MODE_AUTO: "The automatic sequencer owns the machine. Manual "
                           "component commands are refused.",
                MODE_MANUAL: "Operator may command the manual_commands struct "
                             "(valves and conveyors) and conveyor speed. Other "
                             "engineering setpoints stay locked.",
                MODE_MAINTENANCE: "Engineering commands unlocked, including "
                                  "conveyor motion setpoints. Confirmations required.",
            }.get(mode, ""),
        }
