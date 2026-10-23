
#!/usr/bin/env python
"""
Entry point for the unified SCADA / digital-twin platform.

    python run.py                     # normal, uses config/config.json
    python run.py --simulate          # no PLC hardware required
    python run.py --config other.json
    python run.py --port 8080

The reloader is deliberately never enabled: it forks a second process, and a
second process means a second Snap7 client competing for the same PLC.
"""

from __future__ import annotations

import argparse
import logging
import os
import signal
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from backend.app import create_app             # noqa: E402
from backend.core import Core, load_config     # noqa: E402
from backend.plc.simulator import PlcSimulator  # noqa: E402

DEFAULT_CONFIG = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "config", "config.json"
)


def start_assistant(cfg: dict) -> None:
    """
    Start the Assistant page's chat server (cellchat, port 5052) through
    `cellctl start assistant`, which does nothing when it already runs.

    It runs detached and in the background: cellctl waits up to 20 s for the
    server to answer, and the dashboard must not wait for it. The chat server
    keeps running after the dashboard stops; `cellctl stop assistant` ends it.
    Skipped with --simulate, because the assistant talks to the real cell.
    """
    if not cfg.get("autostart", True):
        return
    cellctl = cfg.get("cellctl", "")
    if not os.path.isfile(cellctl):
        print("  ! assistant: cellctl not found at %r, not started" % cellctl)
        return
    flags = 0
    if os.name == "nt":
        flags = subprocess.CREATE_NO_WINDOW | subprocess.CREATE_NEW_PROCESS_GROUP
    try:
        subprocess.Popen(
            ["cmd", "/c", cellctl, "start", "assistant"] if os.name == "nt" else [cellctl, "start", "assistant"],
            cwd=os.path.dirname(cellctl),
            stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            creationflags=flags,
        )
        print("  assistant: starting cellchat through cellctl (port 5052)")
    except OSError as e:
        print("  ! assistant: could not run cellctl: %s" % e)


def main() -> int:
    parser = argparse.ArgumentParser(description="Unified SCADA platform")
    parser.add_argument("--config", default=DEFAULT_CONFIG)
    parser.add_argument("--host", default=None)
    parser.add_argument("--port", type=int, default=None)
    parser.add_argument("--plc-ip", default=None)
    parser.add_argument("--plc-port", type=int, default=None,
                        help="S7 port (default 102). Another value only for a local fake PLC.")
    parser.add_argument(
        "--simulate", action="store_true",
        help="Run with no PLC hardware. Writes round-trip through an in-memory "
             "image so the whole UI, including write confirmation, is exercisable.",
    )
    parser.add_argument(
        "--sim-fault", action="append", default=[],
        help="With --simulate, inject a scripted fault so the diagnostics "
             "screens can be exercised: emergency, air_pressure, "
             "conveyor2_stall, valve8_chatter, plate_stuck_top. Repeatable.",
    )
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level.upper(), logging.INFO),
        format="%(asctime)s  %(levelname)-7s %(name)-10s %(message)s",
        datefmt="%H:%M:%S",
    )
    # Werkzeug logs one line per SSE connection; useful, but not per heartbeat.
    logging.getLogger("werkzeug").setLevel(logging.WARNING)

    if not os.path.exists(args.config):
        print("Config not found: %s" % args.config, file=sys.stderr)
        return 2

    config = load_config(args.config)

    if args.simulate:
        config.setdefault("plc", {})["simulate"] = True
    if args.plc_ip:
        config.setdefault("plc", {})["plc_ip"] = args.plc_ip
    if args.plc_port:
        config.setdefault("plc", {})["port"] = args.plc_port

    server = config.get("server", {})
    host = args.host or server.get("host", "0.0.0.0")
    port = args.port or int(server.get("port", 5000))

    core = Core(config)
    app = create_app(core)

    simulator = None
    if config.get("plc", {}).get("simulate"):
        simulator = PlcSimulator(core.plc, core.registry)

    def shutdown(_signum, _frame):
        print("\nStopping...")
        core.stop()
        sys.exit(0)

    signal.signal(signal.SIGINT, shutdown)
    try:
        signal.signal(signal.SIGTERM, shutdown)
    except (AttributeError, ValueError):
        pass
    if hasattr(signal, "SIGBREAK"):     # Windows Ctrl+Break: how a launcher (the cell MCP server) stops it cleanly
        signal.signal(signal.SIGBREAK, shutdown)

    core.start()

    if not config.get("plc", {}).get("simulate"):
        start_assistant(config.get("assistant", {}))

    if simulator:
        simulator.start()
        for fault in args.sim_fault:
            simulator.inject(fault, True)

    plc_cfg = config.get("plc", {})
    banner = [
        "",
        "  Unified SCADA / Digital Twin Platform",
        "  " + "-" * 46,
        "  PLC            : %s:%s  rack %s slot %s%s"
        % (plc_cfg.get("plc_ip"), plc_cfg.get("port", 102), plc_cfg.get("rack", 0), plc_cfg.get("slot", 1),
           "   [SIMULATED]" if plc_cfg.get("simulate") else ""),
        "  Poll interval  : %.0f ms" % (float(plc_cfg.get("poll_interval", 0.25)) * 1000),
        "  Tags           : %d (%d documented, %d undocumented/raw)"
        % (
            len(core.registry.tags),
            sum(1 for t in core.registry.tags if t.provenance == "documented"),
            sum(1 for t in core.registry.tags if t.provenance == "undocumented"),
        ),
        "  DB read plan   : %s" % (core.plc._read_plan,),
        "  HMI            : http://127.0.0.1:%d" % port,
        "  API health     : http://127.0.0.1:%d/api/health" % port,
        "  " + "-" * 46,
        "",
    ]
    print("\n".join(banner))

    for warning in core.registry.warnings:
        print("  ! registry: %s" % warning)
    if core.registry.warnings:
        print("")

    try:
        # threaded=True so SSE streams and command POSTs run concurrently.
        # use_reloader=False so exactly one PLC client exists. Non-negotiable.
        app.run(host=host, port=port, debug=False, threaded=True, use_reloader=False)
    finally:
        if simulator:
            simulator.stop()
        core.stop()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
