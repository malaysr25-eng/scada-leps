"""
Per-tag change history and the watch list.

This exists specifically to answer the class of question the Errors sheet is
full of: "solenoid_valve_8 randomly turns on and off" -- when, how often, and
was there a command from us at that moment, or did the PLC do it on its own?

Every recorded transition carries an attribution:

    "operator"  a command this backend issued was in flight for that tag
    "plc"       nothing of ours was in flight -- the PLC program changed it
    "unknown"   attribution window could not be established

That single distinction turns an unreproducible complaint into a decidable
question.
"""

from __future__ import annotations

import threading
import time
from collections import deque
from typing import Any, Deque, Dict, List, Optional

# How long after issuing a write we still credit a change to the operator.
ATTRIBUTION_WINDOW_S = 2.5


class TagHistory:
    def __init__(self, per_tag: int = 120, global_capacity: int = 5000) -> None:
        self._lock = threading.RLock()
        self._per_tag = per_tag
        self._by_tag: Dict[str, Deque[dict]] = {}
        self._global: Deque[dict] = deque(maxlen=global_capacity)
        self._watch: List[str] = []
        # tag_id -> (expires_at, command_id, requested)
        self._pending_attribution: Dict[str, tuple] = {}
        self._transition_counts: Dict[str, int] = {}

    # -- attribution ----------------------------------------------------

    def note_command(self, tag_id: str, command_id: str, requested: Any) -> None:
        """Called when a write is issued, so the next change can be attributed."""
        with self._lock:
            self._pending_attribution[tag_id] = (
                time.time() + ATTRIBUTION_WINDOW_S,
                command_id,
                requested,
            )

    def _attribute(self, tag_id: str, value: Any) -> tuple:
        entry = self._pending_attribution.get(tag_id)
        if not entry:
            return "plc", None
        expires, command_id, requested = entry
        if time.time() > expires:
            self._pending_attribution.pop(tag_id, None)
            return "plc", None
        if value == requested:
            self._pending_attribution.pop(tag_id, None)
            return "operator", command_id
        # A change to something other than what we asked for, inside our
        # window: the PLC is fighting the command. Worth flagging as its own
        # thing rather than blaming the operator.
        return "contested", command_id

    # -- recording ------------------------------------------------------

    def record(self, changes: List[dict]) -> List[dict]:
        """Record a poll's worth of changes; returns them enriched with source."""
        if not changes:
            return []

        enriched = []
        with self._lock:
            for ch in changes:
                tag_id = ch["tagId"]
                source, command_id = self._attribute(tag_id, ch["value"])
                entry = {
                    "tagId": tag_id,
                    "previous": ch["previous"],
                    "value": ch["value"],
                    "at": ch["at"],
                    "source": source,
                    "commandId": command_id,
                }
                bucket = self._by_tag.get(tag_id)
                if bucket is None:
                    bucket = deque(maxlen=self._per_tag)
                    self._by_tag[tag_id] = bucket
                bucket.append(entry)
                self._global.append(entry)
                self._transition_counts[tag_id] = self._transition_counts.get(tag_id, 0) + 1
                enriched.append(entry)

        return enriched

    # -- queries --------------------------------------------------------

    def for_tag(self, tag_id: str, limit: int = 60) -> List[dict]:
        with self._lock:
            bucket = self._by_tag.get(tag_id)
            if not bucket:
                return []
            return list(bucket)[-limit:][::-1]

    def last_change(self, tag_id: str) -> Optional[dict]:
        with self._lock:
            bucket = self._by_tag.get(tag_id)
            return bucket[-1] if bucket else None

    def recent(self, limit: int = 200, tag_ids: Optional[List[str]] = None) -> List[dict]:
        with self._lock:
            items = list(self._global)
        if tag_ids:
            wanted = set(tag_ids)
            items = [i for i in items if i["tagId"] in wanted]
        return items[-limit:][::-1]

    def transition_count(self, tag_id: str) -> int:
        with self._lock:
            return self._transition_counts.get(tag_id, 0)

    def chatter_report(self, window_s: float = 30.0, threshold: int = 8) -> List[dict]:
        """
        Tags that changed suspiciously often in the recent window.

        A solenoid that toggles 20 times in 30 s is not being commanded, it is
        either oscillating in the PLC program or being read from the wrong
        address. Either way the operator should be told which.
        """
        cutoff = time.time() - window_s
        counts: Dict[str, dict] = {}
        with self._lock:
            for entry in reversed(self._global):
                if entry["at"] < cutoff:
                    break
                slot = counts.setdefault(
                    entry["tagId"],
                    {"tagId": entry["tagId"], "count": 0, "sources": set(),
                     "lastAt": entry["at"]},
                )
                slot["count"] += 1
                slot["sources"].add(entry["source"])

        out = []
        for slot in counts.values():
            if slot["count"] >= threshold:
                out.append({
                    "tagId": slot["tagId"],
                    "count": slot["count"],
                    "windowSeconds": window_s,
                    "sources": sorted(slot["sources"]),
                    "lastAt": slot["lastAt"],
                })
        out.sort(key=lambda x: -x["count"])
        return out

    # -- watch list -----------------------------------------------------

    def watch(self) -> List[str]:
        with self._lock:
            return list(self._watch)

    def set_watch(self, tag_ids: List[str]) -> List[str]:
        with self._lock:
            self._watch = list(dict.fromkeys(tag_ids))
            return list(self._watch)

    def add_watch(self, tag_id: str) -> List[str]:
        with self._lock:
            if tag_id not in self._watch:
                self._watch.append(tag_id)
            return list(self._watch)

    def remove_watch(self, tag_id: str) -> List[str]:
        with self._lock:
            self._watch = [t for t in self._watch if t != tag_id]
            return list(self._watch)
