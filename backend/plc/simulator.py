"""
Offline PLC simulator.

PURPOSE, AND ITS LIMITS
-----------------------
This is **not** a model of the machine. The physics model is the MATLAB
project; this is a stand-in PLC so the HMI can be developed, demonstrated and
regression-tested when the real S7-1200 is not on the bench.

It drives the simulated DB image through the documented sequence using the
real tag addresses from the registry, so every screen exercises the same code
path it will use against live hardware. The connection indicator reads
SIMULATED throughout and the UI labels it -- nothing here can be mistaken for
live plant data.

What it reproduces on purpose:
  * The start interlocks coming up healthy.
  * Sensors rising and falling as a workpiece advances.
  * Conveyor run coils and encoder feedback tracking their setpoint.
  * Set_HighSpeed selecting between the stored high/low velocity profiles,
    under the assumption documented on _apply_speed_profiles().
  * CMD_START / Cycle_Completed / Total_products behaving as the HMI expects.
  * The engraving step *waiting for the operator acknowledgement*, so the
    manual step in the sequence is genuinely exercised.

What it does not reproduce: real timing, real pneumatics, or any fault
behaviour it is not explicitly asked to inject.
"""

from __future__ import annotations

import logging
import threading
import time
from typing import Dict, Optional

log = logging.getLogger("sim")

# Conveyor axis travel, in the position units the cell reports. The 2026-09-21
# capture shows every axis working between 30.0 (home) and 2.0 (transfer).
_AXIS_HOME = 30.0
_AXIS_AWAY = 2.0
_AXIS_EPSILON = 0.05
# Position units covered per second, per unit of velocity setpoint. Chosen so
# the seeded 0.15 setpoint crosses the 28-unit span in ~0.75 s, as recorded.
_AXIS_UNITS_PER_UNIT_SPEED = 250.0


def _is_num(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool)


class PlcSimulator:
    """Drives PlcService's simulated buffers on its own thread."""

    def __init__(self, plc, registry, tick: float = 0.1) -> None:
        self.plc = plc
        self.registry = registry
        self.tick = tick
        self._stop = threading.Event()
        self._thread: Optional[threading.Thread] = None
        self._phase = "idle"
        self._phase_started = 0.0
        self._step = 0
        self._products_done = 0
        self._faults: Dict[str, bool] = {}
        # Last observed Set_HighSpeed per conveyor, so profile selection can be
        # edge-triggered. See _apply_speed_profiles().
        self._high_speed: Dict[int, Optional[bool]] = {1: None, 2: None, 3: None}

    # ------------------------------------------------------------------

    def _write(self, role: str, value) -> None:
        tag = self.registry.role(role)
        if tag is None:
            return
        self.plc._simulate_write(tag, value)

    def _read(self, role: str):
        tag = self.registry.role(role)
        return None if tag is None else self.plc.value(tag.id)

    # ------------------------------------------------------------------

    def seed_healthy(self) -> None:
        """Bring the simulated cell up in a clean, ready-to-start state."""
        for role in (
            "safety.air_pressure_ok",
            "safety.engv_plate_home" if self.registry.role("safety.engv_plate_home")
            else "safety.engraving_plate_home",
            "safety.all_cylinders_home",
            "safety.emergency_healthy",
            "safety.startup_healthy",
        ):
            self._write(role, True)

        for i in range(1, 6):
            self._write("magazine.%d.ok" % i, True)
            self._write("magazine.%d.low" % i, False)
            self._write("magazine.%d.empty" % i, False)

        self._write("pressure.value", 6.2)
        self._write("pressure.normx", 0.72)
        self._write("pressure.low_limit", 0.0)
        self._write("pressure.high_limit", 10.0)
        self._write("sensor.pgm_low_limit", True)

        for i in (1, 2, 3):
            self._write("conveyor.%d.homed_fb" % i, True)
            self._write("conveyor.%d.set_velocity" % i, 0.15)
            self._write("conveyor.%d.position_fb" % i, _AXIS_HOME)
            self._write("conveyor.%d.set_position" % i, _AXIS_HOME)
            # Two stored profiles either side of the 0.15 the sequence runs at,
            # so switching profiles produces a visible change. These are
            # demo values, not commissioned machine data.
            self._write("conveyor.%d.lowspeed_velocity" % i, 0.15)
            self._write("conveyor.%d.highspeed_velocity" % i, 0.40)
            self._write("conveyor.%d.set_highspeed" % i, False)
            self._high_speed[i] = False

        log.info("simulator seeded: interlocks healthy, magazines loaded")

    def inject(self, fault: str, active: bool = True) -> None:
        """
        Inject a scripted fault so the diagnostics screens can be tested.

        Supported: 'emergency', 'air_pressure', 'conveyor2_stall',
                   'valve8_chatter', 'plate_stuck_top'.
        """
        self._faults[fault] = active
        log.info("simulator fault %s -> %s", fault, active)

        if fault == "emergency":
            self._write("safety.emergency_healthy", not active)
            self._write("safety.emergency_input", active)
        elif fault == "air_pressure":
            self._write("safety.air_pressure_ok", not active)
            self._write("pressure.value", 2.1 if active else 6.2)
            self._write("pressure.low_alarm", active)

    # ------------------------------------------------------------------

    def start(self) -> None:
        if self._thread and self._thread.is_alive():
            return
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, name="plc-sim", daemon=True)
        self._thread.start()

    def stop(self) -> None:
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=2.0)

    def _run(self) -> None:
        # Let the poller establish its buffers before seeding them.
        self._stop.wait(0.6)
        self.seed_healthy()

        while not self._stop.is_set():
            try:
                self._advance()
            except Exception:
                log.exception("simulator tick failed")
            self._stop.wait(self.tick)

    # ------------------------------------------------------------------

    def _enter(self, phase: str) -> None:
        self._phase = phase
        self._phase_started = time.monotonic()

    def _held(self) -> float:
        return time.monotonic() - self._phase_started

    def _advance(self) -> None:
        # Runs before the "is a cycle started" gate below: an engineer changes
        # conveyor speed with the line stopped, which is exactly when the rest
        # of this method returns early.
        self._apply_speed_profiles()
        self._advance_axes()

        if self._faults.get("valve8_chatter"):
            # Toggle SV8's *output mirror* only -- the thing the Errors sheet
            # describes -- at a rate no operator command could produce.
            self._write(
                "valve.8.state", int(time.monotonic() * 3) % 2 == 0
            )

        if self._faults.get("plate_stuck_top"):
            self._write("sensor.pgm_up_limit", True)
            self._write("sensor.pgm_low_limit", False)
            self._write("safety.engraving_plate_home", False)

        started = self._read("cmd.start") is True
        completed = self._read("status.cycle_completed") is True

        if not started:
            if self._phase != "idle":
                self._reset_io()
                self._enter("idle")
            return

        if completed:
            return

        if self._phase == "idle":
            self._products_done = 0
            self._write("status.total_products", 0)
            self._enter("feed")
            self._step = 0

        handler = getattr(self, "_phase_" + self._phase, None)
        if handler:
            handler()

    def _reset_io(self) -> None:
        for i in range(1, 11):
            self._write("sensor.proximity.%d" % i, False)
        for i in range(1, 14):
            self._write("valve.%d.state" % i, False)
        for i in (1, 2, 3):
            self._write("conveyor.%d.running" % i, False)
            self._write("conveyor.%d.velocity_fb" % i, 0.0)
            # Park each axis at home, target matching, so a reset cell shows no
            # position error and therefore no motion fault.
            self._write("conveyor.%d.set_position" % i, _AXIS_HOME)
            self._write("conveyor.%d.position_fb" % i, _AXIS_HOME)
        self._write("status.cycle_completed", False)
        if not self._faults.get("plate_stuck_top"):
            self._write("sensor.pgm_up_limit", False)
            self._write("sensor.pgm_low_limit", True)

    def _apply_speed_profiles(self) -> None:
        """
        Model Set_HighSpeed as a *profile selector*, edge-triggered.

        ASSUMPTION, STATED PLAINLY: the tag list documents Set_HighSpeed as a
        "flag to toggle high speed operational mode via Stepper Technology
        Object", and Set_Velocity as a "custom manual or automated setpoint".
        The real PLC program, not this file, is the authority on how it wires
        the two together. The reading modelled here is that flipping the flag
        loads the matching stored profile into Set_Velocity, and that between
        flips Set_Velocity is a free custom override.

        Edge-triggering is what makes that override survive: reapplying the
        profile every tick would stamp on a velocity the operator just typed
        and make the setpoint box look broken.
        """
        for i in (1, 2, 3):
            selected = self._read("conveyor.%d.set_highspeed" % i)
            if not isinstance(selected, bool):
                continue
            if selected == self._high_speed[i]:
                continue

            self._high_speed[i] = selected
            role = "highspeed_velocity" if selected else "lowspeed_velocity"
            profile = self._read("conveyor.%d.%s" % (i, role))
            if isinstance(profile, (int, float)) and not isinstance(profile, bool):
                self._write("conveyor.%d.set_velocity" % i, float(profile))

    def _advance_axes(self) -> None:
        """
        Move each conveyor axis toward Set_Position, as the stepper TO does.

        Added because the run coil alone is not a motion signal -- see
        Diagnostics._run_without_motion. The detector now compares Set_Position
        against Current_Position_Fb, so a simulator that never moves an axis
        would make E-07 unreachable and the ``--inject conveyor2_stall``
        demonstration silently do nothing.

        The travel rate scales with the velocity setpoint, so changing a speed
        profile visibly changes how long an index takes, as on the real cell.
        """
        for i in (1, 2, 3):
            target = self._read("conveyor.%d.set_position" % i)
            actual = self._read("conveyor.%d.position_fb" % i)
            if not _is_num(target) or not _is_num(actual):
                continue

            error = float(target) - float(actual)
            vel_role = "conveyor.%d.velocity_fb" % i

            if abs(error) <= _AXIS_EPSILON:
                if float(actual) != float(target):
                    self._write("conveyor.%d.position_fb" % i, float(target))
                self._write(vel_role, 0.0)
                continue

            # Commanded to move. A stalled drive holds position and reports
            # zero velocity -- exactly the signature E-07 looks for.
            if i == 2 and self._faults.get("conveyor2_stall"):
                self._write(vel_role, 0.0)
                continue

            setpoint = self._read("conveyor.%d.set_velocity" % i)
            if not _is_num(setpoint) or float(setpoint) == 0.0:
                setpoint = 0.15
            speed = abs(float(setpoint))
            step = min(abs(error), speed * _AXIS_UNITS_PER_UNIT_SPEED * self.tick)
            direction = 1.0 if error > 0 else -1.0

            self._write("conveyor.%d.position_fb" % i, float(actual) + direction * step)
            self._write(vel_role, direction * speed)

    def _belt(self, index: int, on: bool) -> None:
        """
        Enable a station and send its axis to the far end, or back home.

        Matching the 2026-09-21 capture: the run coil rises, Set_Position goes
        30.0 -> 2.0, the axis sweeps across and then *sits at 2.0 with zero
        velocity* while the coil stays on. The motion is the position command,
        not the coil.
        """
        self._write("conveyor.%d.running" % index, on)
        self._write(
            "conveyor.%d.set_position" % index,
            _AXIS_AWAY if on else _AXIS_HOME,
        )

    # -- phases ---------------------------------------------------------

    def _phase_feed(self):
        self._write("valve.1.state", True)
        self._write("safety.all_cylinders_home", False)
        if self._held() > 1.2:
            self._write("sensor.proximity.1", True)
            self._write("valve.1.state", False)
            self._enter("belt1")

    def _phase_belt1(self):
        self._belt(1, True)
        if self._held() > 0.4:
            self._write("sensor.proximity.1", False)
        if self._held() > 2.4:
            self._write("sensor.proximity.6", True)
            self._belt(1, False)
            self._enter("transfer")

    def _phase_transfer(self):
        self._write("valve.6.state", True)
        if self._held() > 1.0:
            self._write("valve.6.state", False)
            self._write("sensor.proximity.6", False)
            self._enter("belt2")

    def _phase_belt2(self):
        self._belt(2, True)
        if self._held() > 2.6:
            self._write("sensor.proximity.7", True)
            self._belt(2, False)
            self._enter("to_engraver")

    def _phase_to_engraver(self):
        self._write("valve.7.state", True)
        if self._held() > 1.2:
            self._write("valve.7.state", False)
            self._write("sensor.proximity.7", False)
            self._enter("plate_up")

    def _phase_plate_up(self):
        self._write("sensor.pgm_low_limit", False)
        self._write("safety.engraving_plate_home", False)
        if self._held() > 1.6:
            self._write("sensor.pgm_up_limit", True)
            self._enter("await_operator")

    def _phase_await_operator(self):
        # Hold here until the operator acknowledges via /api/engraving/complete.
        # This is the real manual step, so the HMI's operator prompt is exercised.
        if self._read("cmd.engraving_completed") is True:
            self._write("cmd.engraving_completed", False)
            self._enter("plate_down")

    def _phase_plate_down(self):
        if self._faults.get("plate_stuck_top"):
            return  # deliberately never reaches the bottom limit
        self._write("sensor.pgm_up_limit", False)
        if self._held() > 1.6:
            self._write("sensor.pgm_low_limit", True)
            self._write("safety.engraving_plate_home", True)
            self._enter("to_belt3")

    def _phase_to_belt3(self):
        self._write("valve.9.state", True)
        if self._held() > 1.2:
            self._write("valve.9.state", False)
            self._enter("belt3")

    def _phase_belt3(self):
        self._belt(3, True)
        if self._held() > 2.4:
            self._write("sensor.proximity.9", True)
            self._belt(3, False)
            self._enter("eject")

    def _phase_eject(self):
        self._write("valve.12.state", True)
        if self._held() > 1.2:
            self._write("valve.12.state", False)
            self._write("sensor.proximity.9", False)
            self._write("safety.all_cylinders_home", True)
            self._products_done += 1
            self._write("status.total_products", self._products_done)

            requested = (self._read("order.qty_25mm") or 0) + (self._read("order.qty_50mm") or 0)
            if self._products_done >= max(1, requested):
                self._write("status.cycle_completed", True)
                self._enter("done")
            else:
                self._enter("feed")

    def _phase_done(self):
        pass
