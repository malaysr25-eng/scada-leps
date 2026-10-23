"""
Historical queries.

Every query here is bounded by a LIMIT and shaped to hit an index defined in
schema.py. An unbounded `SELECT *` against `tag_samples` from an HTTP thread
would hold a read transaction long enough to matter, so no such query exists.
"""

from __future__ import annotations

import json
import time
from typing import Any, Dict, List, Optional

MAX_LIMIT = 5000


def _limit(value: Optional[int], default: int = 200) -> int:
    try:
        n = int(value) if value is not None else default
    except (TypeError, ValueError):
        n = default
    return max(1, min(n, MAX_LIMIT))


def _window(since: Optional[float], until: Optional[float]) -> tuple:
    return (
        float(since) if since else 0.0,
        float(until) if until else time.time() + 86400.0,
    )


class HistoryQueries:
    def __init__(self, store) -> None:
        self.store = store

    # ------------------------------------------------------------------

    def events(
        self,
        since: Optional[float] = None,
        until: Optional[float] = None,
        severity: Optional[str] = None,
        category: Optional[str] = None,
        limit: Optional[int] = None,
    ) -> List[dict]:
        lo, hi = _window(since, until)
        sql = "SELECT * FROM system_events WHERE ts BETWEEN ? AND ?"
        params: List[Any] = [lo, hi]
        if severity:
            sql += " AND severity = ?"
            params.append(severity)
        if category:
            sql += " AND category = ?"
            params.append(category)
        sql += " ORDER BY ts DESC LIMIT ?"
        params.append(_limit(limit))
        return [_decode_detail(r) for r in self.store.query(sql, tuple(params))]

    def alarms(
        self,
        since: Optional[float] = None,
        active_only: bool = False,
        limit: Optional[int] = None,
    ) -> List[dict]:
        sql = "SELECT * FROM alarms WHERE raised_at >= ?"
        params: List[Any] = [float(since) if since else 0.0]
        if active_only:
            sql += " AND cleared_at IS NULL"
        sql += " ORDER BY raised_at DESC LIMIT ?"
        params.append(_limit(limit))
        return [_decode_detail(r) for r in self.store.query(sql, tuple(params))]

    def state_history(
        self,
        kind: Optional[str] = None,
        since: Optional[float] = None,
        limit: Optional[int] = None,
    ) -> List[dict]:
        sql = "SELECT * FROM state_history WHERE ts >= ?"
        params: List[Any] = [float(since) if since else 0.0]
        if kind:
            sql += " AND kind = ?"
            params.append(kind)
        sql += " ORDER BY ts DESC LIMIT ?"
        params.append(_limit(limit))
        return [_decode_detail(r) for r in self.store.query(sql, tuple(params))]

    def cycles(
        self,
        since: Optional[float] = None,
        limit: Optional[int] = None,
    ) -> List[dict]:
        rows = self.store.query(
            "SELECT * FROM cycle_history WHERE started_at >= ? "
            "ORDER BY started_at DESC LIMIT ?",
            (float(since) if since else 0.0, _limit(limit, 100)),
        )
        return [_decode_detail(r) for r in rows]

    def cycle_detail(self, cycle_id: str) -> Optional[dict]:
        cycle = self.store.query_one(
            "SELECT * FROM cycle_history WHERE cycle_id = ?", (cycle_id,)
        )
        if not cycle:
            return None
        cycle = _decode_detail(cycle)
        cycle["metrics"] = self.store.query(
            "SELECT metric, min_value, max_value, avg_value, last_value, "
            "sample_count FROM cycle_metrics WHERE cycle_id = ? ORDER BY metric",
            (cycle_id,),
        )
        cycle["events"] = self.store.query(
            "SELECT ts, severity, category, message FROM system_events "
            "WHERE cycle_id = ? ORDER BY ts LIMIT 500",
            (cycle_id,),
        )
        return cycle

    def commands(
        self,
        since: Optional[float] = None,
        tag_id: Optional[str] = None,
        outcome: Optional[str] = None,
        limit: Optional[int] = None,
    ) -> List[dict]:
        sql = "SELECT * FROM command_history WHERE ts >= ?"
        params: List[Any] = [float(since) if since else 0.0]
        if tag_id:
            sql += " AND tag_id = ?"
            params.append(tag_id)
        if outcome:
            sql += " AND outcome = ?"
            params.append(outcome)
        sql += " ORDER BY ts DESC LIMIT ?"
        params.append(_limit(limit))
        return self.store.query(sql, tuple(params))

    def snapshots(self, limit: Optional[int] = None) -> List[dict]:
        """Metadata only. The payload can be megabytes; fetch it per-id."""
        return self.store.query(
            "SELECT id, ts, label, note, operator, trigger, mode, lifecycle, "
            "source_id, cycle_id, quality, LENGTH(payload) AS payload_bytes "
            "FROM data_snapshots ORDER BY ts DESC LIMIT ?",
            (_limit(limit, 100),),
        )

    def snapshot(self, snapshot_id: int) -> Optional[dict]:
        row = self.store.query_one(
            "SELECT * FROM data_snapshots WHERE id = ?", (snapshot_id,)
        )
        if not row:
            return None
        try:
            row["payload"] = json.loads(row["payload"])
        except (TypeError, ValueError):
            pass
        return row

    def sessions(self, limit: Optional[int] = None) -> List[dict]:
        rows = self.store.query(
            "SELECT * FROM recording_sessions ORDER BY started_at DESC LIMIT ?",
            (_limit(limit, 100),),
        )
        for row in rows:
            if row.get("tag_filter"):
                try:
                    row["tag_filter"] = json.loads(row["tag_filter"])
                except (TypeError, ValueError):
                    pass
        return rows

    def session_samples(
        self,
        session_uid: str,
        tag_id: Optional[str] = None,
        limit: Optional[int] = None,
    ) -> List[dict]:
        sql = "SELECT ts, tag_id, num_value, bool_value, text_value, quality " \
              "FROM tag_samples WHERE session_uid = ?"
        params: List[Any] = [session_uid]
        if tag_id:
            sql += " AND tag_id = ?"
            params.append(tag_id)
        sql += " ORDER BY ts LIMIT ?"
        params.append(_limit(limit, 2000))
        return self.store.query(sql, tuple(params))

    def session_tags(self, session_uid: str) -> List[dict]:
        return self.store.query(
            "SELECT tag_id, COUNT(*) AS samples, MIN(ts) AS first_ts, "
            "MAX(ts) AS last_ts FROM tag_samples WHERE session_uid = ? "
            "GROUP BY tag_id ORDER BY samples DESC LIMIT ?",
            (session_uid, MAX_LIMIT),
        )

    def tag_history(
        self,
        tag_id: str,
        since: Optional[float] = None,
        limit: Optional[int] = None,
    ) -> List[dict]:
        return self.store.query(
            "SELECT * FROM historical_tag_data WHERE tag_id = ? AND ts >= ? "
            "ORDER BY ts DESC LIMIT ?",
            (tag_id, float(since) if since else 0.0, _limit(limit, 500)),
        )

    # ------------------------------------------------------------------

    def summary(self) -> dict:
        """Row counts and coverage, for the History page header."""
        tables = [
            "system_events", "alarms", "state_history", "cycle_history",
            "cycle_metrics", "command_history", "data_snapshots",
            "recording_sessions", "tag_samples", "historical_tag_data",
        ]
        counts = {}
        for table in tables:
            row = self.store.query_one("SELECT COUNT(*) AS n FROM %s" % table)
            counts[table] = (row or {}).get("n", 0)

        oldest = self.store.query_one(
            "SELECT MIN(ts) AS t FROM system_events"
        ) or {}
        newest = self.store.query_one(
            "SELECT MAX(ts) AS t FROM system_events"
        ) or {}

        return {
            "counts": counts,
            "totalRows": sum(counts.values()),
            "oldestEventAt": oldest.get("t"),
            "newestEventAt": newest.get("t"),
            "sizeBytes": self.store.size_bytes(),
        }

    def export_session_csv(self, session_uid: str, tag_id: Optional[str] = None) -> str:
        """CSV text for a recording. Bounded by the same LIMIT as the query."""
        rows = self.session_samples(session_uid, tag_id, limit=MAX_LIMIT)
        lines = ["timestamp,iso_time,tag_id,value,quality"]
        for row in rows:
            value = row["num_value"]
            if value is None:
                value = row["bool_value"]
            if value is None:
                value = row["text_value"]
            lines.append(
                "%.6f,%s,%s,%s,%s" % (
                    row["ts"],
                    time.strftime("%Y-%m-%dT%H:%M:%S", time.localtime(row["ts"])),
                    row["tag_id"],
                    "" if value is None else value,
                    row.get("quality") or "",
                )
            )
        return "\n".join(lines)


def _decode_detail(row: dict) -> dict:
    if row.get("detail"):
        try:
            row["detail"] = json.loads(row["detail"])
        except (TypeError, ValueError):
            pass
    return row
