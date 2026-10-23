#!/usr/bin/env python3
"""
MCD Cell Cycle Simulator & State Assertion Engine (v3)

CORRECTED 2026-09-19: this script PRINTS the timeline in mcd_cell_config_v3.json
and checks only that it ends at the right time. It does not simulate or verify
physics or latching. For real checks against the model, run
    python -m unittest test_mcd_replay -v      (in SIemens NX Work/Tests & Claude Files)
Validates state machine transitions, latching valve logic, sensor triggers, and conveyor timings.
"""

import json
import os
import sys

def find_config_file():
    candidates = [
        "mcd_cell_config_v3.json",
        "mcd_cell_config_v2.json",
        "mcd_cell_config.json",
        os.path.join(os.path.dirname(__file__), "mcd_cell_config_v3.json"),
        os.path.join(os.path.dirname(__file__), "mcd_cell_config_v2.json"),
        os.path.join(os.path.dirname(__file__), "mcd_cell_config.json"),
        "/workspace/artifacts/mcd_cell_config_v3.json",
        "/workspace/artifacts/mcd_cell_config_v2.json",
        "/workspace/artifacts/mcd_cell_config.json"
    ]
    for path in candidates:
        if path and os.path.exists(path):
            return path
    raise FileNotFoundError("Could not locate any MCD JSON config file.")

class MCDCellSimulator:
    def __init__(self, config_path=None):
        if config_path is None:
            config_path = find_config_file()
        with open(config_path, "r") as f:
            self.config = json.load(f)
        self.reset()

    def reset(self):
        self.time = 0.0
        self.block_pos = list(self.config["waypoints"]["load"])
        self.active_signals = set()
        self.cyl_a_extended = False
        self.cyl_b_extended = False

    def simulate_engraved_route(self):
        print("=== Simulating Engraved Cycle (75.64s) ===")
        timeline = self.config.get("engraved_cycle_timeline") or self.config["cycles"]["engraved_route"]["timeline"]
        for event in timeline:
            t = event["time_s"]
            desc = event["event"]
            signals = event["signals"]
            
            # Latching logic check
            if "Solenoid_valve7" in signals:
                self.cyl_a_extended = True
            if "Solenoid_valve8" in signals:
                self.cyl_a_extended = False
            if "Solenoid_valve9" in signals:
                self.cyl_b_extended = True
            if "Solenoid_valve10" in signals:
                self.cyl_b_extended = False
                
            print(f"[{t:06.2f}s] {desc:<55} | Cyl A: {'EXT' if self.cyl_a_extended else 'RET'} | Cyl B: {'EXT' if self.cyl_b_extended else 'RET'}")
            
        print("\nSimulation assertions:")
        assert abs(timeline[-1]["time_s"] - 75.64) < 0.01, "Total engraved cycle time mismatch!"
        print("[PASS] The engraved timeline ends at 75.64 s (the model's cycle is 75.65 s)")
        print("[INFO] Cylinder states are printed above; latching is not verified here")

    def simulate_bypass_route(self):
        print("\n=== Simulating Bypass Cycle (29.74s) ===")
        timeline = self.config.get("bypass_cycle_timeline") or self.config["cycles"]["bypass_route"]["timeline"]
        for event in timeline:
            t = event["time_s"]
            desc = event["event"]
            print(f"[{t:06.2f}s] {desc}")
        assert abs(timeline[-1]["time_s"] - 29.74) < 0.01, "Bypass cycle time mismatch!"
        print("[PASS] The bypass timeline ends at 29.74 s")

if __name__ == "__main__":
    sim = MCDCellSimulator()
    sim.simulate_engraved_route()
    sim.simulate_bypass_route()
