#!/usr/bin/env python3
"""
MCD OPC UA Mock Server & Telemetry Replay Server (v2)
Provides OPC UA communication interface for NX MCD Virtual Commissioning.
Plays back the exact validated MATLAB cycle telemetry (75.64s Engraved route / 29.74s Bypass route)
to drive 3D kinematics in NX MCD without a physical Siemens S7 PLC.
"""

import asyncio
import json
import logging
import os
import sys
import time

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")

PLC_TAGS = {
    # Conveyor Controls
    "Conveyor1": False,
    "Conveyor2": False,
    "Conveyor3": False,
    # Actuator Solenoids
    "Solenoid_valve1": False,
    "Solenoid_valve2": False,
    "Solenoid_valve3": False,
    "Solenoid_valve4": False,
    "Solenoid_valve5": False,
    "Solenoid_valve6": False,
    "Solenoid_valve7": False,  # Cyl A Extend (Latching)
    "Solenoid_valve8": False,  # Cyl A Retract (Latching)
    "Solenoid_valve9": False,  # Cyl B Extend (Latching)
    "Solenoid_valve10": False, # Cyl B Retract (Latching)
    "Solenoid_valve11": False,
    "Solenoid_valve12": False,
    "Solenoid_valve13": False,
    # Proximity Sensors
    "Proximity_sensor1": False,
    "Proximity_sensor2": False,
    "Proximity_sensor3": False,
    "Proximity_sensor4": False,
    "Proximity_sensor5": False,
    "Proximity_sensor6": False,
    "Proximity_sensor7": False,
    "Proximity_sensor8": False,
    "Proximity_sensor9": False,
    "Proximity_sensor10": False,
    # System Status & Feedback
    "Engraving_Completed": False,
    "Current_Position_Fb": 0.0,
    "MODE_HIGH_SPEED": True
}

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

class MCDMockServer:
    def __init__(self, config_file=None):
        if config_file is None:
            config_file = find_config_file()
        with open(config_file, "r") as f:
            self.config = json.load(f)
        self.tags = PLC_TAGS.copy()
        
    def reset_tags(self):
        for k in self.tags:
            if isinstance(self.tags[k], bool):
                self.tags[k] = False
            elif isinstance(self.tags[k], float):
                self.tags[k] = 0.0

    async def run_engraved_cycle_replay(self, speed_factor=1.0):
        logging.info("=== STARTING ENGRAVED ROUTE REPLAY (75.64s total) ===")
        events = self.config.get("engraved_cycle_timeline") or self.config["cycles"]["engraved_route"]["timeline"]
        self.reset_tags()
        start_wall = time.time()
        
        for i, ev in enumerate(events):
            target_t = ev["time_s"] / speed_factor
            current_elapsed = time.time() - start_wall
            if target_t > current_elapsed:
                await asyncio.sleep(target_t - current_elapsed)
            
            # Active signals update
            active_signals = ev["signals"]
            # Apply to tag dictionary
            for sig in active_signals:
                if sig in self.tags:
                    self.tags[sig] = True
            
            sim_time = time.time() - start_wall
            active_str = [k for k, v in self.tags.items() if v is True]
            logging.info(f"[{sim_time*speed_factor:06.2f}s] {ev['event']:<50} | Active PLC Tags: {active_str}")
        
        logging.info("=== ENGRAVED ROUTE REPLAY COMPLETE ===")

    async def run_opc_ua_protocol_server(self, host="0.0.0.0", port=4840):
        try:
            from asyncua import Server
            server = Server()
            await server.init()
            server.set_endpoint(f"opc.tcp://{host}:{port}/freeopcua/server/")
            idx = await server.register_namespace("BITS_PILANI_MCD")
            
            mcd_obj = await server.nodes.objects.add_object(idx, "MCD_Cell_PLC")
            node_map = {}
            for tag, default_val in self.tags.items():
                node = await mcd_obj.add_variable(idx, tag, default_val)
                await node.set_writable()
                node_map[tag] = node
                
            logging.info(f"AsyncUA OPC Server listening at opc.tcp://{host}:{port}/freeopcua/server/")
            async with server:
                while True:
                    await asyncio.sleep(1)
        except ImportError:
            logging.warning("asyncua library not installed. Running internal standalone TCP telemetry server instead...")
            server = await asyncio.start_server(self._handle_tcp_client, host, port)
            logging.info(f"Standalone MCD TCP Server listening on {host}:{port}")
            async with server:
                await server.serve_forever()

    async def _handle_tcp_client(self, reader, writer):
        addr = writer.get_extra_info('peername')
        logging.info(f"Connected by MCD client: {addr}")
        while True:
            data = await reader.read(100)
            if not data:
                break
            # Send current tag state as JSON
            response = json.dumps(self.tags).encode('utf-8') + b"\n"
            writer.write(response)
            await writer.drain()
        logging.info(f"Client disconnected: {addr}")

if __name__ == "__main__":
    server = MCDMockServer()
    if "--replay" in sys.argv:
        asyncio.run(server.run_engraved_cycle_replay(speed_factor=2.0))
    else:
        asyncio.run(server.run_engraved_cycle_replay(speed_factor=1.0))
