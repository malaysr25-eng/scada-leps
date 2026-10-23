"""
Generate config/tag_overlay.json.

The overlay carries the engineering metadata the vendor tag list does not:
subsystem grouping, write-access class, a stable semantic role the application
code binds to, and the schematic placement used by the factory view.

Every access class below is justified from the tag's own description in
`Tag_list (1).xlsx`. Nothing here invents an address. Re-run this script after
the tag list changes:

    python tools/build_tag_overlay.py
"""

import json
import os

RO = "read_only"
SAFE = "safe_manual"
ENG = "engineering"
PROT = "protected"

G_SAFETY = "Safety & Interlocks"
G_CYCLE = "Cycle Control"
G_MAG = "Magazines"
G_SENSOR = "Sensors"
G_OUT = "Actuator Outputs"
G_CONV = "Conveyor Outputs"
G_MOTION = "Conveyor Motion"
G_MANUAL = "Manual Commands"
G_PRESS = "Pneumatics / Pressure"
G_RAW = "Diagnostics / Raw"

tags = {}


def t(tag_id, group, access, role=None, short=None, unit="", notes=""):
    entry = {"group": group, "access": access}
    if role:
        entry["role"] = role
    if short:
        entry["short"] = short
    if unit:
        entry["unit"] = unit
    if notes:
        entry["notes"] = notes
    tags[tag_id] = entry


# ---------------------------------------------------------------------------
# Safety and start interlocks -- feedback only. Never writable from a browser.
# ---------------------------------------------------------------------------
t("system.start_interlocks.air_pressure_ok", G_SAFETY, RO,
  "safety.air_pressure_ok", "Air Pressure OK")
t("system.start_interlocks.engv_plate_home", G_SAFETY, RO,
  "safety.engraving_plate_home", "Engraving Plate Home")
t("system.start_interlocks.all_cylinders_home", G_SAFETY, RO,
  "safety.all_cylinders_home", "All Cylinders Home")
t("system.start_interlocks.emergency_healthy", G_SAFETY, RO,
  "safety.emergency_healthy", "E-Stop Circuit Healthy",
  notes="Hardware safety-relay loop feedback. This is a STATUS bit from a "
        "certified circuit, not a software stop. It is never written.")
t("system.startup_healthy", G_SAFETY, RO, "safety.startup_healthy", "Startup Healthy")
t("io_status.digital_inputs.emergency", G_SAFETY, RO,
  "safety.emergency_input", "Emergency Input",
  notes="Local E-Stop circuit feedback on the digital input card.")

# ---------------------------------------------------------------------------
# Cycle control. PROTECTED: reachable only through /api/cycle/* endpoints that
# apply the quantity and interlock rules. Never through the generic tag write.
# ---------------------------------------------------------------------------
t("system.productqty_25mm", G_CYCLE, PROT, "order.qty_25mm", "Qty 25 mm", "pcs")
t("system.productqty_50mm", G_CYCLE, PROT, "order.qty_50mm", "Qty 50 mm", "pcs")
t("system.mode_high_speed", G_CYCLE, PROT, "cmd.mode_high_speed", "High Speed Mode")
t("system.cmd_start", G_CYCLE, PROT, "cmd.start", "Cycle Start",
  notes="Guarded by /api/cycle/start: qty_25 + qty_50 must be > 0 and the "
        "start interlocks must be healthy.")
t("system.engraving_completed", G_CYCLE, SAFE, "cmd.engraving_completed",
  "Engraving Complete",
  notes="Operator acknowledgement for sequence step 29. The manual step the "
        "PLC waits on -- deliberately operator-writable.")
t("system.cycle_reset", G_CYCLE, PROT, "cmd.cycle_reset", "Cycle Reset",
  notes="Recovery command. Exposed via /api/cycle/reset behind the restart "
        "checklist.")
t("system.total_products", G_CYCLE, RO, "status.total_products", "Total Products", "pcs")
t("system.cycle_completed", G_CYCLE, RO, "status.cycle_completed", "Cycle Completed")

# ---------------------------------------------------------------------------
# Magazine / compartment status.
# The legacy app.py forced all five .Ok bits TRUE on every START press, which
# defeats the empty-magazine interlock. Kept ENGINEERING (maintenance mode,
# confirmed) rather than something the START path silently sets.
# ---------------------------------------------------------------------------
for i in range(1, 6):
    t("comp_status.comp%d.ok" % i, G_MAG, ENG, "magazine.%d.ok" % i,
      "Mag %d OK" % i,
      notes="Legacy app.py wrote this TRUE on every START, bypassing the "
            "empty-magazine interlock. See DEBUGGING_REPORT.md E-05.")
    t("comp_status.comp%d.low" % i, G_MAG, RO, "magazine.%d.low" % i, "Mag %d Low" % i)
    t("comp_status.comp%d.empty" % i, G_MAG, RO, "magazine.%d.empty" % i,
      "Mag %d Empty" % i)

# ---------------------------------------------------------------------------
# Digital inputs -- proximity sensors and limit switches.
# ---------------------------------------------------------------------------
for i in range(1, 11):
    t("io_status.digital_inputs.proximity_sensor%d" % i, G_SENSOR, RO,
      "sensor.proximity.%d" % i, "PX %d" % i)

t("io_status.digital_inputs.pgm_low_limit", G_SENSOR, RO,
  "sensor.pgm_low_limit", "Plate Low Limit")
t("io_status.digital_inputs.pgm_up_limit", G_SENSOR, RO,
  "sensor.pgm_up_limit", "Plate Up Limit")

# ---------------------------------------------------------------------------
# Digital outputs -- these are the PLC's OUTPUT STATUS mirror. They are what
# the coil is actually doing. READ_ONLY: the intended write path is the
# manual_commands struct, and writing an output-image address would be
# overwritten by the PLC on its next scan anyway.
# ---------------------------------------------------------------------------
for i in range(1, 14):
    t("io_status.digital_outputs.solenoid_valve%d" % i, G_OUT, RO,
      "valve.%d.state" % i, "SV %d" % i,
      notes="Output coil state. Command it via manual_commands.Solenoid_Valve%d." % i)

for i in range(1, 4):
    t("io_status.digital_outputs.conveyor%d" % i, G_CONV, RO,
      "conveyor.%d.running" % i, "Conveyor %d Run" % i)

# ---------------------------------------------------------------------------
# Pressure.
# ---------------------------------------------------------------------------
t("io_status.analog_inputs.pressure.value", G_PRESS, RO, "pressure.value",
  "Pressure", "bar")
t("io_status.analog_inputs.pressure.normx", G_PRESS, RO, "pressure.normx",
  "Pressure Norm", "0-1")
t("io_status.analog_inputs.pressure.low_value", G_PRESS, RO, "pressure.low_limit",
  "Scale Low", "bar")
t("io_status.analog_inputs.pressure.high_value", G_PRESS, RO, "pressure.high_limit",
  "Scale High", "bar")
t("io_status.analog_inputs.pressure.low_alarm", G_PRESS, RO, "pressure.low_alarm",
  "Pressure Low Alarm")
t("io_status.analog_inputs.pressure.high_alarm", G_PRESS, RO, "pressure.high_alarm",
  "Pressure High Alarm")

# ---------------------------------------------------------------------------
# Conveyor motion (Pot_Control). Setpoints are ENGINEERING; feedback READ_ONLY.
# This is the block behind "conveyor 2 speed randomly stops responding":
# Set_Velocity is a setpoint, Current_Velocity_Fb is the encoder truth, and the
# old dashboards showed neither next to the other.
# ---------------------------------------------------------------------------
for i in range(1, 4):
    c = "pot_control.conv%d" % i
    t(c + ".set_highspeed", G_MOTION, ENG, "conveyor.%d.set_highspeed" % i,
      "C%d High Speed Sel" % i)
    t(c + ".highspeed_position", G_MOTION, ENG, "conveyor.%d.highspeed_position" % i,
      "C%d HS Position" % i)
    t(c + ".highspeed_velocity", G_MOTION, ENG, "conveyor.%d.highspeed_velocity" % i,
      "C%d HS Velocity" % i)
    t(c + ".lowspeed_position", G_MOTION, ENG, "conveyor.%d.lowspeed_position" % i,
      "C%d LS Position" % i)
    t(c + ".lowspeed_velocity", G_MOTION, ENG, "conveyor.%d.lowspeed_velocity" % i,
      "C%d LS Velocity" % i)
    t(c + ".set_position", G_MOTION, ENG, "conveyor.%d.set_position" % i,
      "C%d Set Position" % i)
    t(c + ".set_velocity", G_MOTION, ENG, "conveyor.%d.set_velocity" % i,
      "C%d Set Velocity" % i,
      notes="Commanded speed. Compare against conveyor.%d.velocity_fb." % i)
    t(c + ".goto_position", G_MOTION, ENG, "conveyor.%d.goto" % i, "C%d Go To" % i)
    t(c + ".set_home", G_MOTION, ENG, "conveyor.%d.set_home" % i, "C%d Home" % i)
    t(c + ".reset", G_MOTION, ENG, "conveyor.%d.reset" % i, "C%d Fault Reset" % i)
    t(c + ".error_fb", G_MOTION, RO, "conveyor.%d.error_fb" % i, "C%d Error" % i)
    t(c + ".axis_homed_fb", G_MOTION, RO, "conveyor.%d.homed_fb" % i, "C%d Homed" % i)
    t(c + ".current_position_fb", G_MOTION, RO, "conveyor.%d.position_fb" % i,
      "C%d Position" % i, "deg")
    t(c + ".current_velocity_fb", G_MOTION, RO, "conveyor.%d.velocity_fb" % i,
      "C%d Velocity FB" % i,
      notes="Encoder feedback. This is the ONLY trustworthy 'is it moving' "
            "signal for conveyor %d." % i)

# ---------------------------------------------------------------------------
# Manual command struct -- the sanctioned manual write path.
# ---------------------------------------------------------------------------
for i in range(1, 14):
    t("manual_commands.solenoid_valve%d" % i, G_MANUAL, SAFE,
      "manual.valve.%d" % i, "Manual SV %d" % i)
for i in range(1, 4):
    t("manual_commands.conveyor%d" % i, G_MANUAL, SAFE,
      "manual.conveyor.%d" % i, "Manual Conveyor %d" % i)


overlay = {
    "_comment": [
        "Generated by tools/build_tag_overlay.py -- edit that script, not this file.",
        "access: read_only | safe_manual | engineering | protected",
        "No address is ever declared here; addresses come only from the tag list."
    ],
    "sheet_defaults": {
        "io and process tags": {"group": "IO & Process", "access": RO},
        "pot control": {"group": G_MOTION, "access": RO},
        "manual commands": {"group": G_MANUAL, "access": SAFE},
    },
    "tags": tags,
    "raw_blocks": [
        {
            "db": 59,
            "start_byte": 266,
            "end_byte": 269,
            "dtype": "Bool",
            "group": G_RAW,
            "description": "UNDOCUMENTED bit -- not present in Tag_list (1).xlsx.",
            "notes": (
                "The legacy SCADA Hub's data_on.json mapped these 4 bytes to "
                "proximity_sensor1-10 and solenoid_valve1-13, but the tag list "
                "ends at DB59.DBX265.7 and documents those signals at 128-131. "
                "The legacy map also packs the bits contiguously, ignoring S7 "
                "struct byte alignment, so it drifts 3 bits: its "
                "'solenoid_valve8' is DBX268.4. Registered here as raw and "
                "read-only so the region can be observed against live hardware "
                "without any HMI indicator depending on it. "
                "See DEBUGGING_REPORT.md E-18."
            ),
        },
        {
            "db": 59,
            "start_byte": 270,
            "end_byte": 278,
            "dtype": "Int",
            "group": G_RAW,
            "description": "UNDOCUMENTED word -- not present in Tag_list (1).xlsx.",
            "notes": (
                "Read by the legacy json_write_for_web_tag.py as product1-5 "
                "counters. Unconfirmed against the tag list."
            ),
        },
    ],
}

here = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
out = os.path.join(here, "config", "tag_overlay.json")
os.makedirs(os.path.dirname(out), exist_ok=True)
with open(out, "w", encoding="utf-8") as fh:
    json.dump(overlay, fh, indent=2)
    fh.write("\n")

print("wrote %s (%d annotated tags, %d raw blocks)"
      % (out, len(tags), len(overlay["raw_blocks"])))
