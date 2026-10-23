"""
Application core: the single object that owns every service and composes the
one machine-state snapshot the whole UI renders from.

There is exactly one of these per process. Everything that needs PLC data goes
through it, which is what makes "one source of truth" structural rather than a
convention someone has to remember.

The composition runs on the PLC worker thread once per poll, so HTTP requests
and SSE subscribers only ever read a finished snapshot.
"""

from __future__ import annotations

import json
import logging
import os
import threading
import time
from typing import Any, Dict, List, Optional

from backend.chat.service import ChatService
from backend.db.ingest import IngestPolicy
from backend.db.queries import HistoryQueries
from backend.db.store import DataStore
from backend.plc.registry import load_registry
from backend.plc.service import PlcService
from backend.services.recording import RecordingService
from backend.sources.manager import SourceManager
from backend.sources.matlab_source import MatlabSourceAdapter
from backend.sources.plc_source import PlcSourceAdapter
from backend.services.camera import CameraService
from backend.services.diagnostics import Diagnostics
from backend.services.safety import CommandGate
from backend.services.twin import TwinAdapter
from backend.state.events import EventLog
from backend.state.history import TagHistory
from backend.state.machine import (
    MachineModel,
    ST_COMPLETED,
    ST_DISCONNECTED,
)
from backend.state.products import ProductTracker
from backend.state.sequence import SequenceTracker, sequence_catalogue

log = logging.getLogger("core")

SCHEMA_VERSION = 1


def load_config(path: str) -> dict:
    with open(path, "r", encoding="utf-8") as fh:
        cfg = json.load(fh)

    root = os.path.dirname(os.path.dirname(os.path.abspath(path)))

    def resolve(value: str) -> str:
        if not value:
            return value
        return value if os.path.isabs(value) else os.path.normpath(os.path.join(root, value))

    cfg["_root"] = root
    cfg["tag_list_path"] = resolve(cfg.get("tag_list_path", ""))
    cfg["tag_overlay_path"] = resolve(cfg.get("tag_overlay_path", ""))
    for section, keys in (
        ("camera", ("detections_path", "counts_path", "frame_path")),
        ("digital_twin", ("reference_path",)),
    ):
        block = cfg.get(section) or {}
        for key in keys:
            if block.get(key):
                block[key] = resolve(block[key])
        cfg[section] = block
    return cfg


class Core:
    def __init__(self, config: dict) -> None:
        self.config = config
        self.started_at = time.time()

        self.events = EventLog(capacity=int(config.get("event_capacity", 4000)))
        self.history = TagHistory()

        self.registry = load_registry(
            config.get("tag_list_path", ""), config.get("tag_overlay_path", "")
        )
        for warning in self.registry.warnings:
            log.warning("registry: %s", warning)
            self.events.warning("registry", warning)

        self.plc = PlcService(self.registry, config.get("plc", {}))
        self.sequence = SequenceTracker(
            self.events, float(config.get("sequence", {}).get("step_timeout_s", 30.0))
        )
        self.machine = MachineModel(self.events, self.plc, self.sequence)
        self.products = ProductTracker(self.events)
        self.camera = CameraService(config.get("camera", {}), self.events)
        self.twin = TwinAdapter(config.get("digital_twin", {}), self.events)
        self.gate = CommandGate(self.machine, self.plc, self.events, config)
        self.diagnostics = Diagnostics(
            self.plc, self.history, self.events, self.machine,
            config.get("diagnostics", {}),
        )

        # ---- data sources -------------------------------------------
        # PlcService stays the sole Snap7 owner; the adapter only wraps it.
        self.sources = SourceManager(self.events)
        self.plc_source = PlcSourceAdapter(
            self.plc,
            stale_after=float(
                config.get("diagnostics", {}).get("stale_budget_s", 3.0)
            ),
        )
        self.sources.register(self.plc_source)

        matlab_cfg = (config.get("sources") or {}).get("matlab") or {}
        self.matlab_source = MatlabSourceAdapter(matlab_cfg, self.registry)
        self.sources.register(self.matlab_source)

        # ---- persistence ---------------------------------------------
        self.store = DataStore(config.get("db") or {}, self.events)
        self.ingest = IngestPolicy(self.store, config.get("ingest") or {}, self.events)
        self.queries = HistoryQueries(self.store)
        self.recording = RecordingService(
            self.store, self.ingest, self.events, config.get("recording") or {}
        )

        # ---- help assistant ------------------------------------------
        # Constructed with `self`, but ChatService only ever calls
        # `core.snapshot()` through ChatContext. See backend/chat/context.py.
        self.chat = ChatService(self, config.get("chat") or {})

        # Persistence bookkeeping, so nothing is written twice.
        self._persisted_event_id = 0
        self._persisted_commands: set = set()
        self._known_faults: Dict[str, bool] = {}
        self._last_persisted_lifecycle: Optional[str] = None
        self._last_persisted_mode: Optional[str] = None
        self._last_persisted_conn: Optional[str] = None
        self._last_persisted_source_mode: Optional[str] = None
        self._saved_cycles: set = set()

        self.max_total_qty = config.get("max_total_quantity")

        self._snapshot_lock = threading.RLock()
        self._snapshot: Dict[str, Any] = {}
        self._subscribers: List[Any] = []
        self._subscriber_lock = threading.RLock()

        self.plc.add_change_listener(self._on_poll)

    # ------------------------------------------------------------------
    # lifecycle
    # ------------------------------------------------------------------

    def start(self) -> None:
        self.events.info(
            "system",
            "Unified SCADA platform starting: %d tags (%d documented, %d raw)"
            % (
                len(self.registry.tags),
                sum(1 for t in self.registry.tags if t.provenance == "documented"),
                sum(1 for t in self.registry.tags if t.provenance == "undocumented"),
            ),
        )
        self.history.set_watch(self.diagnostics.default_watch_list())
        self.twin.load()

        # Database first: it must be accepting writes before the poll loop
        # starts producing events, or the first minute of history is lost.
        self.store.start()

        self.camera.start()
        self.plc.start()

        # The PLC takes control by default when it is the only control-capable
        # source. Doing this after plc.start() means the health check in
        # set_control_source sees a real connection state.
        threading.Timer(1.0, self._auto_select_control).start()

        if self.matlab_source.enabled:
            self.matlab_source.start()

    def _auto_select_control(self) -> None:
        """Give control to the PLC once it is up, unless something already has it."""
        if self.sources.control_source is not None:
            return
        ok, reason = self.sources.set_control_source("plc", operator="startup")
        if not ok:
            log.info("PLC did not take control at startup: %s", reason)

    def stop(self) -> None:
        self.plc.stop()
        self.camera.stop()
        self.sources.stop_all()
        # Last, so queued writes from the shutdown path still land.
        self.store.stop()

    # ------------------------------------------------------------------
    # the per-poll pipeline
    # ------------------------------------------------------------------

    def _on_poll(self, changes: List[dict], plc_snapshot: dict) -> None:
        try:
            enriched = self.history.record(changes)
            roles = self.machine.roles()

            role_changes = self._annotate_roles(enriched)
            self._log_signal_changes(role_changes)

            machine_state = self.machine.update(roles)

            # "Running" is a fact about the PLC, not about our lifecycle enum.
            # Deriving it from the lifecycle meant a single FAULT froze the
            # sequence and product trackers -- exactly when an operator most
            # needs to see what the machine was doing. The cycle is running if
            # the PLC says it is.
            running = (
                roles.get("cmd.start") is True
                and roles.get("status.cycle_completed") is not True
            )

            # Rising edges are counted from the poller's change list before the
            # cursor is advanced, so an edge that occurs while an earlier guard
            # is still being confirmed is never lost.
            self.sequence.observe(role_changes)
            sequence_state = self.sequence.update(roles, running)

            if (
                running
                and self.products.active is None
                and machine_state.lifecycle not in (ST_DISCONNECTED,)
            ):
                self.products.begin_cycle(machine_state.cycle_id)
            if machine_state.lifecycle == ST_COMPLETED and self.products.active:
                self.products.end_cycle()

            self.products.update(
                roles,
                [c for c in role_changes if (c.get("role") or "").startswith("sensor.")],
                running,
            )

            findings = self.diagnostics.evaluate(roles, running)
            self._sync_faults(findings)

            elapsed = None
            if machine_state.cycle_started_at and not machine_state.cycle_ended_at:
                elapsed = time.time() - machine_state.cycle_started_at

            twin_view = self.twin.compare(roles, elapsed, sequence_state, running)

            snapshot = self._compose(
                plc_snapshot, roles, machine_state, sequence_state,
                twin_view, findings, role_changes,
            )

            with self._snapshot_lock:
                self._snapshot = snapshot

            # Persistence runs AFTER the snapshot is published-ready and does
            # nothing but enqueue. It cannot block the poll loop: every call
            # below is a bounded put_nowait.
            self._persist(snapshot, role_changes, roles, machine_state)

            self._publish(snapshot)

        except Exception:
            log.exception("poll pipeline failed")

    # ------------------------------------------------------------------
    # persistence -- enqueue only, never block
    # ------------------------------------------------------------------

    def _persist(
        self,
        snapshot: dict,
        role_changes: List[dict],
        roles: Dict[str, Any],
        machine_state,
    ) -> None:
        """
        Push newly-happened things into the database queue.

        Everything here is O(new items) and non-blocking. The store drops
        rather than blocks when its queue is full, so a slow disk degrades
        history, never the control loop.
        """
        if not self.store.enabled or not self.store.ready:
            return

        try:
            sources = snapshot.get("dataSources") or {}
            context = {
                "cycleId": machine_state.cycle_id,
                "sourceId": sources.get("controlSourceId"),
            }

            # -- events: only ones we have not already stored --------------
            for event in reversed(snapshot.get("events") or []):
                if event["id"] > self._persisted_event_id:
                    self.ingest.on_event(event, context)
                    self._persisted_event_id = max(
                        self._persisted_event_id, event["id"]
                    )

            # -- alarms: raise on first sight, clear on disappearance -------
            for fault in self.events.faults(include_cleared=True):
                key = fault["key"]
                was_active = self._known_faults.get(key)
                if fault["active"] and was_active is not True:
                    self.ingest.on_alarm_raised(fault, context)
                elif not fault["active"] and was_active is True:
                    self.ingest.on_alarm_cleared(fault)
                self._known_faults[key] = fault["active"]

            # -- transitions ------------------------------------------------
            lifecycle = machine_state.lifecycle
            if lifecycle != self._last_persisted_lifecycle:
                self.ingest.on_state_transition(
                    "lifecycle", self._last_persisted_lifecycle, lifecycle, context
                )
                self._last_persisted_lifecycle = lifecycle

            mode = machine_state.mode
            if mode != self._last_persisted_mode:
                self.ingest.on_state_transition(
                    "mode", self._last_persisted_mode, mode, context
                )
                self._last_persisted_mode = mode

            conn = (snapshot.get("connection") or {}).get("plc")
            if conn != self._last_persisted_conn:
                self.ingest.on_state_transition(
                    "connection", self._last_persisted_conn, conn, context
                )
                self._last_persisted_conn = conn

            source_mode = sources.get("mode")
            if source_mode != self._last_persisted_source_mode:
                self.ingest.on_state_transition(
                    "source", self._last_persisted_source_mode, source_mode, context
                )
                self._last_persisted_source_mode = source_mode

            # -- settled commands -------------------------------------------
            for command in snapshot.get("commands") or []:
                if command["state"] in ("PENDING", "WRITTEN"):
                    continue
                if command["id"] in self._persisted_commands:
                    continue
                self.ingest.on_command(command, context)
                self._persisted_commands.add(command["id"])
            if len(self._persisted_commands) > 2000:
                self._persisted_commands.clear()

            # -- watched-tag transitions ------------------------------------
            self.ingest.on_tag_changes(role_changes, self.history.watch(), context)

            # -- in-memory aggregates (no I/O) ------------------------------
            self.ingest.accumulate(roles, machine_state.cycle_id)

            # -- a completed cycle, once ------------------------------------
            if (
                machine_state.lifecycle == ST_COMPLETED
                and machine_state.cycle_id
                and machine_state.cycle_id not in self._saved_cycles
            ):
                self._saved_cycles.add(machine_state.cycle_id)
                self.recording.save_cycle(
                    snapshot, outcome="COMPLETED", operator="system",
                    note="Automatic summary at cycle completion.",
                )

            # -- active recording session -----------------------------------
            self.recording.tick(
                self.sources.read_latest(), sources.get("telemetrySourceId") or "plc"
            )

        except Exception:
            # Persistence must never take the control loop down with it.
            log.exception("persistence pass failed")

    def _recent_changes(self, limit: int) -> List[dict]:
        """A rolling, role-annotated window of recent tag transitions."""
        return self._annotate_roles(self.history.recent(limit=limit))[::-1]

    def _annotate_roles(self, changes: List[dict]) -> List[dict]:
        out = []
        for ch in changes:
            tag = self.registry.get(ch["tagId"])
            entry = dict(ch)
            entry["role"] = tag.role if tag else None
            entry["short"] = tag.short if tag else ch["tagId"]
            entry["address"] = tag.address if tag else None
            entry["group"] = tag.group if tag else None
            out.append(entry)
        return out

    def _log_signal_changes(self, changes: List[dict]) -> None:
        """Sensor and output transitions become first-class events."""
        for ch in changes:
            role = ch.get("role") or ""
            if role.startswith("sensor.") or role.startswith("valve.") or role.startswith("conveyor."):
                if not role.endswith((".state", ".running")) and not role.startswith("sensor."):
                    continue
                self.events.plc(
                    "signal",
                    "%s  %s -> %s"
                    % (ch["short"], _fmt(ch["previous"]), _fmt(ch["value"])),
                    source=ch.get("source", "plc"),
                    tagId=ch["tagId"], role=role, address=ch.get("address"),
                )

    def _sync_faults(self, findings: List[dict]) -> None:
        """Latch FAULT-severity findings; clear the ones that went away."""
        current = set()
        for f in findings:
            if f["severity"] != "FAULT":
                continue
            current.add(f["key"])
            self.events.raise_fault(
                f["key"], "%s -- %s" % (f["title"], f["detail"]),
                issueRef=f.get("issueRef"),
            )
        for fault in self.events.active_faults():
            key = fault["key"]
            if key.startswith("sequence.stalled."):
                continue
            if key == "safety.emergency":
                continue
            if key not in current:
                self.events.clear_fault(key)

    # ------------------------------------------------------------------

    def _compose(self, plc_snapshot, roles, machine_state, sequence_state,
                 twin_view, findings, role_changes) -> dict:
        camera_state = self.camera.state()
        running = (
            roles.get("cmd.start") is True
            and roles.get("status.cycle_completed") is not True
        )
        stale = self.plc.stale_seconds()
        stale_budget = float(self.config.get("diagnostics", {}).get("stale_budget_s", 3.0))

        return {
            "schemaVersion": SCHEMA_VERSION,
            "timestamp": time.time(),
            "uptimeSeconds": round(time.time() - self.started_at, 1),

            "connection": {
                "plc": plc_snapshot["connection"],
                "plcSimulated": plc_snapshot["simulated"],
                "plcHealth": plc_snapshot["health"],
                "staleSeconds": None if stale == float("inf") else round(stale, 2),
                "staleBudgetSeconds": stale_budget,
                "stale": stale > stale_budget,
                "camera": camera_state["status"],
                "digitalTwin": twin_view["connection"],
            },

            "machine": machine_state.to_dict(),
            "mode": self.gate.describe_mode(),
            "safety": self.machine.safety(roles),
            "restartChecklist": [
                i.to_dict() for i in self.machine.restart_checklist(roles)
            ],
            "canStart": self._can_start(roles),

            "sequence": sequence_state.to_dict(running),
            "sensors": self._sensors(roles),
            "actuators": self._actuators(roles),
            "conveyors": self._conveyors(roles),
            "inventory": self.products.inventory(
                roles, self.camera.counts(), self.camera.online
            ),

            "camera": camera_state,
            "digitalTwin": twin_view,

            "diagnostics": {
                "findings": findings,
                "activeFaults": self.events.active_faults(),
                "watch": self._watch_view(),
                # A rolling window from the history buffer, NOT just this
                # poll's deltas. Sending only the current poll's changes made
                # the sensor event stream permanently empty: at 250 ms polling
                # a given poll usually has zero transitions, so the UI had
                # nothing to accumulate.
                "recentChanges": self._recent_changes(60),
            },

            "commands": plc_snapshot["commands"],
            "inflightCommands": plc_snapshot["inflight"],

            # ---- added by the data-source / persistence extension --------
            # Purely additive: existing consumers are unaffected.
            "dataSources": self.sources.describe(),
            "recording": self.recording.status(),
            "database": self._database_summary(),

            "events": self.events.recent(limit=60),
        }

    def _database_summary(self) -> dict:
        """Small enough to ride in every snapshot; the full stats are on /api/db."""
        stats = self.store.stats()
        return {
            "enabled": stats["enabled"],
            "ready": stats["ready"],
            "queueDepth": stats["queueDepth"],
            "queueCapacity": stats["queueCapacity"],
            "written": stats["written"],
            "dropped": stats["dropped"],
            "errors": stats["errors"],
            "healthy": stats["healthy"],
            "lastWriteAt": stats["lastWriteAt"],
            "writeMsAvg": stats["writeMsAvg"],
        }

    def _can_start(self, roles: Dict[str, Any]) -> dict:
        qty25 = roles.get("order.qty_25mm") or 0
        qty50 = roles.get("order.qty_50mm") or 0
        ok_order, order_reason = self.machine.validate_order(
            qty25, qty50, self.max_total_qty
        )
        ok_restart, blockers = self.machine.can_restart(roles)
        running = roles.get("cmd.start") is True and roles.get("status.cycle_completed") is not True

        reasons = []
        if not ok_order:
            reasons.append(order_reason)
        if not ok_restart:
            reasons.extend("%s is not satisfied." % b.label for b in blockers)
        if running:
            reasons.append("A cycle is already running.")
        if self.machine.state.mode != "AUTO":
            reasons.append("Switch to AUTO mode to start a cycle.")

        return {
            "allowed": not reasons,
            "reasons": reasons,
            "orderValid": ok_order,
            "orderReason": order_reason,
            "interlocksSatisfied": ok_restart,
            "plcQty25": qty25,
            "plcQty50": qty50,
        }

    def _sensors(self, roles: Dict[str, Any]) -> List[dict]:
        out = []
        specs = [("sensor.proximity.%d" % i, "PX %d" % i, "proximity") for i in range(1, 11)]
        specs += [
            ("sensor.pgm_low_limit", "Plate Low Limit", "limit"),
            ("sensor.pgm_up_limit", "Plate Up Limit", "limit"),
        ]
        for role, label, kind in specs:
            tag = self.registry.role(role)
            if not tag:
                continue
            last = self.history.last_change(tag.id)
            out.append({
                "role": role,
                "tagId": tag.id,
                "label": label,
                "kind": kind,
                "address": tag.address,
                "description": tag.description,
                "value": roles.get(role),
                "lastChangeAt": last["at"] if last else None,
                "lastChangeFrom": last["previous"] if last else None,
                "transitions": self.history.transition_count(tag.id),
            })
        return out

    def _actuators(self, roles: Dict[str, Any]) -> List[dict]:
        out = []
        for i in range(1, 14):
            state_tag = self.registry.role("valve.%d.state" % i)
            manual_tag = self.registry.role("manual.valve.%d" % i)
            if not state_tag:
                continue
            last = self.history.last_change(state_tag.id)
            out.append({
                "index": i,
                "label": "Solenoid Valve %d" % i,
                "stateRole": "valve.%d.state" % i,
                "stateTagId": state_tag.id,
                "stateAddress": state_tag.address,
                "state": roles.get("valve.%d.state" % i),
                "manualRole": "manual.valve.%d" % i,
                "manualTagId": manual_tag.id if manual_tag else None,
                "manualAddress": manual_tag.address if manual_tag else None,
                "manualCommand": roles.get("manual.valve.%d" % i),
                "lastChangeAt": last["at"] if last else None,
                "transitions": self.history.transition_count(state_tag.id),
                "feedback": None,
                "feedbackNote": (
                    "No reed-switch or end-of-stroke tag exists for this "
                    "cylinder in Tag_list (1).xlsx, so extend/retract cannot "
                    "be physically confirmed."
                ),
            })
        return out

    # Speed-profile roles the HMI may write, by the key the UI uses. The tag
    # *ids* are resolved from the registry rather than spelled out in the
    # frontend: the overlay is the single authority on which address a role
    # lives at, and a UI that hardcodes "pot_control.convN.set_velocity"
    # silently stops working the day that address moves.
    _SPEED_ROLES = {
        "setVelocity": "set_velocity",
        "highSpeedVelocity": "highspeed_velocity",
        "lowSpeedVelocity": "lowspeed_velocity",
        "highSpeedSelect": "set_highspeed",
    }

    def _conveyor_speed_tags(self, index: int) -> Dict[str, Any]:
        """
        Per-conveyor descriptor for each writable speed tag: its id, address,
        commissioned range and unit. ``None`` for a role the registry does not
        carry, so the UI can disable that control instead of POSTing to a tag
        that does not exist.
        """
        out: Dict[str, Any] = {}
        for key, suffix in self._SPEED_ROLES.items():
            tag = self.registry.role("conveyor.%d.%s" % (index, suffix))
            out[key] = None if tag is None else {
                "tagId": tag.id,
                "address": tag.address,
                "unit": tag.unit,
                "min": tag.minimum,
                "max": tag.maximum,
                "access": tag.access,
            }
        return out

    def _conveyors(self, roles: Dict[str, Any]) -> List[dict]:
        out = []
        for i in (1, 2, 3):
            run_tag = self.registry.role("conveyor.%d.running" % i)
            out.append({
                "index": i,
                "label": "Conveyor %d" % i,
                "running": roles.get("conveyor.%d.running" % i),
                "runAddress": run_tag.address if run_tag else None,
                "manualCommand": roles.get("manual.conveyor.%d" % i),
                "commandedVelocity": roles.get("conveyor.%d.set_velocity" % i),
                "feedbackVelocity": roles.get("conveyor.%d.velocity_fb" % i),
                "position": roles.get("conveyor.%d.position_fb" % i),
                "setPosition": roles.get("conveyor.%d.set_position" % i),
                "highSpeedSelected": roles.get("conveyor.%d.set_highspeed" % i),
                # The two stored profiles the PLC's stepper TO selects between.
                # Published alongside the live setpoint so an operator can see
                # *why* the commanded speed is what it is before changing it.
                "highSpeedVelocity": roles.get("conveyor.%d.highspeed_velocity" % i),
                "lowSpeedVelocity": roles.get("conveyor.%d.lowspeed_velocity" % i),
                "highSpeedPosition": roles.get("conveyor.%d.highspeed_position" % i),
                "lowSpeedPosition": roles.get("conveyor.%d.lowspeed_position" % i),
                "speedTags": self._conveyor_speed_tags(i),
                "error": roles.get("conveyor.%d.error_fb" % i),
                "homed": roles.get("conveyor.%d.homed_fb" % i),
            })
        return out

    def _watch_view(self) -> List[dict]:
        values = self.plc.values()
        out = []
        for tag_id in self.history.watch():
            tag = self.registry.get(tag_id)
            if not tag:
                continue
            last = self.history.last_change(tag_id)
            out.append({
                "tagId": tag_id,
                "label": tag.short,
                "address": tag.address,
                "group": tag.group,
                "dtype": tag.dtype,
                "value": values.get(tag_id),
                "previous": last["previous"] if last else None,
                "lastChangeAt": last["at"] if last else None,
                "lastChangeSource": last["source"] if last else None,
                "transitions": self.history.transition_count(tag_id),
                "provenance": tag.provenance,
            })
        return out

    # ------------------------------------------------------------------
    # snapshot access + fan-out
    # ------------------------------------------------------------------

    def snapshot(self) -> dict:
        with self._snapshot_lock:
            if self._snapshot:
                return self._snapshot
        # Before the first poll completes, still return a usable shape so the
        # UI renders a "connecting" state instead of crashing on undefined.
        return self._bootstrap_snapshot()

    def _bootstrap_snapshot(self) -> dict:
        roles = {r: None for r in self.registry.by_role}
        return {
            "schemaVersion": SCHEMA_VERSION,
            "timestamp": time.time(),
            "uptimeSeconds": round(time.time() - self.started_at, 1),
            "connection": {
                "plc": self.plc.connection,
                "plcSimulated": self.plc.simulate,
                "plcHealth": self.plc._health.to_dict(),
                "staleSeconds": None,
                "staleBudgetSeconds": 3.0,
                "stale": True,
                "camera": self.camera.state()["status"],
                "digitalTwin": self.twin.connection_state(),
            },
            "machine": self.machine.state.to_dict(),
            "mode": self.gate.describe_mode(),
            "safety": self.machine.safety(roles),
            "restartChecklist": [i.to_dict() for i in self.machine.restart_checklist(roles)],
            "canStart": {"allowed": False, "reasons": ["Waiting for the first PLC read."]},
            "sequence": self.sequence.state.to_dict(False),
            "sensors": self._sensors(roles),
            "actuators": self._actuators(roles),
            "conveyors": self._conveyors(roles),
            "inventory": self.products.inventory(roles, {}, False),
            "camera": self.camera.state(),
            "digitalTwin": self.twin.compare(roles, None, self.sequence.state, False),
            "diagnostics": {
                "findings": [], "activeFaults": [], "watch": [], "recentChanges": [],
            },
            "commands": [],
            "inflightCommands": 0,
            "dataSources": self.sources.describe(),
            "recording": self.recording.status(),
            "database": self._database_summary(),
            "events": self.events.recent(limit=60),
        }

    def subscribe(self, queue) -> None:
        with self._subscriber_lock:
            self._subscribers.append(queue)

    def unsubscribe(self, queue) -> None:
        with self._subscriber_lock:
            if queue in self._subscribers:
                self._subscribers.remove(queue)

    def _publish(self, snapshot: dict) -> None:
        with self._subscriber_lock:
            targets = list(self._subscribers)
        for q in targets:
            try:
                # Drop the oldest frame rather than block the PLC thread on a
                # slow browser. A stalled tab must never slow the poll loop.
                if q.full():
                    try:
                        q.get_nowait()
                    except Exception:
                        pass
                q.put_nowait(snapshot)
            except Exception:
                pass

    def subscriber_count(self) -> int:
        with self._subscriber_lock:
            return len(self._subscribers)

    # ------------------------------------------------------------------

    def sequence_catalogue(self) -> List[dict]:
        return sequence_catalogue()


def _fmt(value: Any) -> str:
    if value is True:
        return "ON"
    if value is False:
        return "OFF"
    return str(value)
