#!/usr/bin/env python
"""
PLC address helper for the launcher scripts.

    python tools/plc_config.py show              # print the configured PLC
    python tools/plc_config.py get-ip            # print just the IP
    python tools/plc_config.py set-ip 172.21.30.157 [--rack 0] [--slot 1]
    python tools/plc_config.py test [IP]         # port-102 reachability + Snap7 connect
    python tools/plc_config.py get-port          # dashboard port (for the launchers)
    python tools/plc_config.py lan-urls          # URLs other PCs can open

`set-ip` edits config/config.json in place with a targeted replace, so the
file's comments, key order and formatting are left alone.

`test` opens a Snap7 connection, reads the CPU state and disconnects. Do not
run it while run.py is up: it is a second Snap7 client, briefly.
"""

from __future__ import annotations

import argparse
import ipaddress
import json
import os
import re
import socket
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CONFIG = os.path.join(ROOT, "config", "config.json")


def load() -> dict:
    with open(CONFIG, "r", encoding="utf-8", newline="") as fh:
        return json.load(fh)


def plc_block() -> dict:
    return load().get("plc", {})


def replace_key(text: str, key: str, value: str) -> str:
    """Replace the first `"key": <scalar>` inside the "plc" block."""
    start = text.index('"plc"')
    end = text.index("}", start)
    block = text[start:end]
    pattern = r'("%s"\s*:\s*)("[^"]*"|-?\d+(?:\.\d+)?)' % re.escape(key)
    if not re.search(pattern, block):
        raise KeyError(key)
    block = re.sub(pattern, lambda m: m.group(1) + value, block, count=1)
    return text[:start] + block + text[end:]


def cmd_show(_args) -> int:
    plc = plc_block()
    print("  Config   : %s" % CONFIG)
    print("  PLC IP   : %s" % plc.get("plc_ip"))
    print("  Rack/Slot: %s / %s" % (plc.get("rack", 0), plc.get("slot", 1)))
    print("  Simulate : %s" % plc.get("simulate", False))
    return 0


def cmd_get_ip(_args) -> int:
    print(plc_block().get("plc_ip", ""))
    return 0


def cmd_get_port(_args) -> int:
    print(int(load().get("server", {}).get("port", 5000)))
    return 0


def cmd_lan_urls(_args) -> int:
    port = int(load().get("server", {}).get("port", 5000))
    for ip in local_ipv4s():
        print("  From another PC on LAN : http://%s:%d" % (ip, port))
    return 0


def cmd_set_ip(args) -> int:
    try:
        ipaddress.IPv4Address(args.ip)
    except ValueError:
        print("  Not a valid IPv4 address: %r" % args.ip, file=sys.stderr)
        return 2

    with open(CONFIG, "r", encoding="utf-8", newline="") as fh:
        text = fh.read()
    text = replace_key(text, "plc_ip", json.dumps(args.ip))
    if args.rack is not None:
        text = replace_key(text, "rack", str(args.rack))
    if args.slot is not None:
        text = replace_key(text, "slot", str(args.slot))
    json.loads(text)  # never write a file run.py cannot parse
    with open(CONFIG, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)

    print("  Saved PLC IP %s to config/config.json" % args.ip)
    return 0


def local_ipv4s() -> list:
    ips = set()
    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            ips.add(info[4][0])
    except OSError:
        pass
    return sorted(ip for ip in ips if not ip.startswith("127."))


def cmd_test(args) -> int:
    plc = plc_block()
    ip = args.ip or plc.get("plc_ip")
    rack, slot = int(plc.get("rack", 0)), int(plc.get("slot", 1))

    print("  Testing PLC %s (rack %d, slot %d)" % (ip, rack, slot))
    mine = local_ipv4s()
    print("  This PC  : %s" % (", ".join(mine) or "no IPv4 address found"))

    try:
        target = ipaddress.IPv4Address(ip)
        same = [m for m in mine
                if ipaddress.IPv4Network(m + "/24", strict=False) == ipaddress.IPv4Network(str(target) + "/24", strict=False)]
        if not same:
            print("  ! No adapter on this PC is in %s.x -- set a static IP on the"
                  " PLC network adapter first." % ".".join(ip.split(".")[:3]))
    except ValueError:
        print("  ! %r is not a valid IPv4 address" % ip)
        return 2

    # 1. ISO-on-TCP port. Fast, and tells "wrong network" apart from "PUT/GET off".
    try:
        with socket.create_connection((ip, 102), timeout=3):
            pass
        print("  [OK]   TCP port 102 reachable")
    except OSError as exc:
        print("  [FAIL] TCP port 102 not reachable: %s" % exc)
        print("         Check the cable, the PC's IP/subnet, and that the PLC is powered.")
        return 1

    # 2. Real Snap7 session.
    try:
        import snap7
    except ImportError:
        print("  [FAIL] python-snap7 is not installed -- run setup.bat")
        return 1

    client = snap7.client.Client()
    try:
        client.connect(ip, rack, slot)
        if not client.get_connected():
            raise RuntimeError("connect() returned but the session is not up")
        try:
            state = client.get_cpu_state()
        except Exception:
            state = "unknown"
        print("  [OK]   Snap7 connected, CPU state: %s" % state)
        return 0
    except Exception as exc:
        print("  [FAIL] Snap7 connect failed: %s" % exc)
        print("         Port 102 is open, so check rack/slot and, in TIA Portal,")
        print("         'Permit access with PUT/GET communication' + optimized-access OFF on DB59.")
        return 1
    finally:
        try:
            client.disconnect()
        except Exception:
            pass


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[1])
    sub = parser.add_subparsers(dest="cmd", required=True)
    sub.add_parser("show").set_defaults(fn=cmd_show)
    sub.add_parser("get-ip").set_defaults(fn=cmd_get_ip)
    sub.add_parser("get-port").set_defaults(fn=cmd_get_port)
    sub.add_parser("lan-urls").set_defaults(fn=cmd_lan_urls)
    p = sub.add_parser("set-ip")
    p.add_argument("ip")
    p.add_argument("--rack", type=int)
    p.add_argument("--slot", type=int)
    p.set_defaults(fn=cmd_set_ip)
    p = sub.add_parser("test")
    p.add_argument("ip", nargs="?")
    p.set_defaults(fn=cmd_test)
    args = parser.parse_args()
    return args.fn(args)


if __name__ == "__main__":
    raise SystemExit(main())
