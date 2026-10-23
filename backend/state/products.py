"""
Product and magazine tracking.

WHAT CAN AND CANNOT BE TRACKED, AND WHY
---------------------------------------
The brief asks for per-product identity ("Product #001, type 25 mm, currently
on conveyor 1"). The available hardware does not support it, and inventing it
would produce a convincing screen that lies:

* The camera counts blocks per magazine column. ``camera_yolo.py`` derives the
  column from the bounding-box centroid each frame and overwrites
  ``products.json`` -- there is no tracker, no object ID, no frame-to-frame
  association. A block is not the same object between two frames.
* The proximity sensors are presence detectors on a belt. They report "some-
  thing is here", not "block #17 is here".
* No tag in ``Tag_list (1).xlsx`` carries a part ID, serial or index.

So this module tracks what is real:

  * **Magazine level** per compartment -- from the camera counts and the PLC's
    own Comp_Status OK/Low/Empty bits, with the two shown side by side so a
    disagreement is visible rather than averaged away.
  * **Order progress** -- requested vs the PLC's own Total_products counter.
  * **A cycle-level token** -- one in-flight workpiece per cycle, moved between
    stations by *confirmed sensor transitions only*. Its position is labelled
    CONFIRMED at a sensor and ESTIMATED between sensors.

If per-part identity is needed later, the honest route is a part marker the
camera can read, or an RFID/barcode station. Noted in docs/ARCHITECTURE.md.
"""

from __future__ import annotations

import time
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional

# Where a token can be, in process order. Each is anchored to a real signal.
STATIONS = [
    ("magazine", "Magazine", None),
    ("feeder", "Feeder station", None),
    ("conveyor1", "Conveyor 1", "sensor.proximity.1"),
    ("conveyor1_end", "Conveyor 1 end", "sensor.proximity.2"),
    ("conveyor2", "Conveyor 2", "sensor.proximity.3"),
    ("engraving", "Engraving station", "sensor.pgm_up_limit"),
    ("conveyor3", "Conveyor 3", "sensor.proximity.4"),
    ("bin", "Output bin", None),
]

STATION_LABEL = {k: label for k, label, _ in STATIONS}
STATION_ORDER = [k for k, _, _ in STATIONS]

CONFIRMED = "CONFIRMED"      # a physical sensor says so
ESTIMATED = "ESTIMATED"      # inferred from the sequence, not sensed
UNKNOWN = "UNKNOWN"


@dataclass
class CycleToken:
    """One workpiece in flight. Cycle-scoped, not a persistent part identity."""

    token_id: str
    cycle_id: Optional[str]
    created_at: float
    station: str = "magazine"
    positioning: str = ESTIMATED
    last_confirmed_station: Optional[str] = None
    last_confirmed_at: Optional[float] = None
    last_event: str = ""
    expected_next: str = ""
    completed_at: Optional[float] = None
    product_type: str = "unknown"

    def to_dict(self) -> dict:
        return {
            "tokenId": self.token_id,
            "cycleId": self.cycle_id,
            "createdAt": self.created_at,
            "station": self.station,
            "stationLabel": STATION_LABEL.get(self.station, self.station),
            "positioning": self.positioning,
            "lastConfirmedStation": self.last_confirmed_station,
            "lastConfirmedAt": self.last_confirmed_at,
            "lastEvent": self.last_event,
            "expectedNext": self.expected_next,
            "completedAt": self.completed_at,
            "productType": self.product_type,
            "identityNote": (
                "Cycle-level token. The hardware provides no per-part identity; "
                "see docs/ARCHITECTURE.md."
            ),
        }


class ProductTracker:
    def __init__(self, event_log) -> None:
        self.events = event_log
        self.active: Optional[CycleToken] = None
        self.completed: List[CycleToken] = []
        self._token_seq = 0
        self._order = {"qty25": 0, "qty50": 0, "requestedAt": None}
        self._prev_total: Optional[int] = None

    # -- order ----------------------------------------------------------

    def set_order(self, qty25: int, qty50: int) -> None:
        self._order = {
            "qty25": int(qty25),
            "qty50": int(qty50),
            "requestedAt": time.time(),
        }

    # -- token lifecycle -------------------------------------------------

    def begin_cycle(self, cycle_id: Optional[str]) -> CycleToken:
        self._token_seq += 1
        token = CycleToken(
            token_id="P%03d" % self._token_seq,
            cycle_id=cycle_id,
            created_at=time.time(),
            expected_next="Feeder actuator extends",
        )
        self.active = token
        self.events.info(
            "product", "Workpiece %s entered the cycle" % token.token_id,
            tokenId=token.token_id, cycleId=cycle_id,
        )
        return token

    def end_cycle(self) -> None:
        if self.active:
            self.active.completed_at = time.time()
            self.active.station = "bin"
            self.completed.append(self.active)
            if len(self.completed) > 200:
                del self.completed[:-100]
            self.events.info(
                "product", "Workpiece %s completed" % self.active.token_id,
                tokenId=self.active.token_id,
            )
            self.active = None

    def update(self, roles: Dict[str, Any], sensor_changes: List[dict],
               running: bool) -> None:
        """Advance the token on confirmed sensor rises only."""
        if not running or not self.active:
            return

        for change in sensor_changes:
            if change.get("value") is not True:
                continue
            role = change.get("role")
            for key, label, anchor in STATIONS:
                if anchor and anchor == role:
                    self._move(key, label, role)
                    break

    def _move(self, station: str, label: str, role: str) -> None:
        token = self.active
        if token is None or token.station == station:
            return

        token.station = station
        token.positioning = CONFIRMED
        token.last_confirmed_station = station
        token.last_confirmed_at = time.time()
        token.last_event = "Confirmed at %s (%s)" % (label, role)

        idx = STATION_ORDER.index(station) if station in STATION_ORDER else -1
        token.expected_next = (
            STATION_LABEL.get(STATION_ORDER[idx + 1], "")
            if 0 <= idx < len(STATION_ORDER) - 1 else "Output bin"
        )

        self.events.plc(
            "product",
            "Workpiece %s detected at %s" % (token.token_id, label),
            tokenId=token.token_id, station=station, role=role,
        )

    def mark_estimated(self, station: str, reason: str) -> None:
        if self.active and self.active.station != station:
            self.active.station = station
            self.active.positioning = ESTIMATED
            self.active.last_event = reason

    # -- inventory -------------------------------------------------------

    def inventory(self, roles: Dict[str, Any], camera_counts: Dict[str, Any],
                  camera_online: bool) -> dict:
        """
        Magazine view. Camera counts and PLC status bits are reported side by
        side; a disagreement becomes a visible mismatch instead of being
        silently reconciled.
        """
        magazines = []
        for i in range(1, 6):
            cam = camera_counts.get("c%d" % i)
            plc_ok = roles.get("magazine.%d.ok" % i)
            plc_low = roles.get("magazine.%d.low" % i)
            plc_empty = roles.get("magazine.%d.empty" % i)

            mismatch = None
            if camera_online and cam is not None and plc_empty is not None:
                if plc_empty is True and cam > 0:
                    mismatch = "PLC reports EMPTY but the camera sees %d block(s)." % cam
                elif plc_empty is False and cam == 0:
                    mismatch = "Camera sees no blocks but the PLC does not report EMPTY."

            magazines.append({
                "index": i,
                "label": "Magazine %d" % i,
                "cameraCount": cam if camera_online else None,
                "cameraOnline": camera_online,
                "plcOk": plc_ok,
                "plcLow": plc_low,
                "plcEmpty": plc_empty,
                "mismatch": mismatch,
            })

        total_products = roles.get("status.total_products")
        requested = self._order["qty25"] + self._order["qty50"]

        return {
            "magazines": magazines,
            "order": {
                "qty25": self._order["qty25"],
                "qty50": self._order["qty50"],
                "total": requested,
                "requestedAt": self._order["requestedAt"],
            },
            "progress": {
                "plcTotalProducts": total_products,
                "requested": requested,
                "remaining": (
                    max(0, requested - total_products)
                    if isinstance(total_products, int) and requested else None
                ),
                "source": "PLC System.Total_products (DB59.DBW114)",
            },
            "activeToken": self.active.to_dict() if self.active else None,
            "completedTokens": [t.to_dict() for t in self.completed[-20:]][::-1],
            "identityLimitation": (
                "Per-part identity is not available from the current hardware. "
                "The camera re-counts every frame with no object tracking, and "
                "no PLC tag carries a part ID. Tokens below are cycle-scoped."
            ),
        }
