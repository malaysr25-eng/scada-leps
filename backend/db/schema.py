"""
SQL schema.

DESIGNED AROUND THIS PROJECT'S DATA MODEL, NOT A GENERIC ONE
------------------------------------------------------------
The tables below mirror what the application already produces: events and
latching faults from `state/events.py`, attributed tag transitions from
`state/history.py`, commands with their read-back outcome from
`plc/service.py`, lifecycle transitions from `state/machine.py`, and cycles from
the machine model. Nothing is invented to fill a template.

THE ROW-COUNT PROBLEM, AND THE ANSWER
-------------------------------------
At a 250 ms poll with 158 tags, writing every value every poll would be
**54 million rows/day**. So by default nothing is written per poll.

What is written, and roughly how often on a working machine:

| table | trigger | rows/day (typical) |
|---|---|---|
| `system_events` | an event is emitted | hundreds |
| `alarms` | a fault latches or clears | tens |
| `state_history` | lifecycle/mode/source transition | tens |
| `cycle_history` | one row per completed cycle | tens–hundreds |
| `command_history` | one row per write | tens |
| `data_snapshots` | operator presses Save | a handful |
| `recording_sessions` | operator starts a recording | a handful |
| `tag_samples` | **only inside a recording**, sampled and deadbanded | bounded by the session |
| `cycle_metrics` | aggregate per cycle | one per cycle |

`tag_samples` is the only table that could grow quickly, and it can only grow
while an operator has deliberately started a recording session. Even then the
ingest policy applies an interval and a deadband, so a steady signal writes
nothing.

INDEXING
--------
Every table is queried by time, so every table is indexed by time. Additional
indexes follow the actual query shapes in `queries.py` — session+tag for
recordings, key for alarms, severity for event filtering — rather than being
sprinkled hopefully.
"""

from __future__ import annotations

SCHEMA_VERSION = 1

# ---------------------------------------------------------------------------
# SQLite pragmas.
#
# WAL is the important one: it lets the HTTP threads read while the single
# writer thread writes, without either blocking the other. Without it a query
# from the History page could stall the writer, which would back-pressure into
# the queue, which is the one thing this design must never do.
#
# synchronous=NORMAL trades a small durability window for not fsyncing on every
# commit. Losing the last few seconds of *diagnostic history* after a power cut
# is acceptable; stalling the PLC poll loop is not.
# ---------------------------------------------------------------------------
PRAGMAS = [
    "PRAGMA journal_mode=WAL",
    "PRAGMA synchronous=NORMAL",
    "PRAGMA foreign_keys=ON",
    "PRAGMA busy_timeout=5000",
    "PRAGMA temp_store=MEMORY",
]

STATEMENTS = [
    # -- meta ------------------------------------------------------------
    """
    CREATE TABLE IF NOT EXISTS schema_meta (
        key   TEXT PRIMARY KEY,
        value TEXT NOT NULL
    )
    """,

    # -- events ----------------------------------------------------------
    """
    CREATE TABLE IF NOT EXISTS system_events (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        ts         REAL    NOT NULL,
        severity   TEXT    NOT NULL,
        category   TEXT    NOT NULL,
        message    TEXT    NOT NULL,
        source     TEXT,
        source_id  TEXT,
        cycle_id   TEXT,
        detail     TEXT
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_events_ts ON system_events(ts DESC)",
    "CREATE INDEX IF NOT EXISTS ix_events_sev_ts ON system_events(severity, ts DESC)",
    "CREATE INDEX IF NOT EXISTS ix_events_cat_ts ON system_events(category, ts DESC)",

    # -- alarms ----------------------------------------------------------
    """
    CREATE TABLE IF NOT EXISTS alarms (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        alarm_key    TEXT    NOT NULL,
        severity     TEXT    NOT NULL,
        message      TEXT    NOT NULL,
        raised_at    REAL    NOT NULL,
        cleared_at   REAL,
        acknowledged INTEGER NOT NULL DEFAULT 0,
        occurrences  INTEGER NOT NULL DEFAULT 1,
        issue_ref    TEXT,
        cycle_id     TEXT,
        detail       TEXT
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_alarms_raised ON alarms(raised_at DESC)",
    "CREATE INDEX IF NOT EXISTS ix_alarms_key ON alarms(alarm_key, raised_at DESC)",
    "CREATE INDEX IF NOT EXISTS ix_alarms_active ON alarms(cleared_at) WHERE cleared_at IS NULL",

    # -- lifecycle / mode / source transitions ---------------------------
    """
    CREATE TABLE IF NOT EXISTS state_history (
        id            INTEGER PRIMARY KEY AUTOINCREMENT,
        ts            REAL NOT NULL,
        kind          TEXT NOT NULL,      -- lifecycle | mode | source | connection
        previous      TEXT,
        current       TEXT NOT NULL,
        cycle_id      TEXT,
        operator      TEXT,
        source_id     TEXT,
        detail        TEXT
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_state_ts ON state_history(ts DESC)",
    "CREATE INDEX IF NOT EXISTS ix_state_kind_ts ON state_history(kind, ts DESC)",

    # -- cycles ----------------------------------------------------------
    """
    CREATE TABLE IF NOT EXISTS cycle_history (
        id                INTEGER PRIMARY KEY AUTOINCREMENT,
        cycle_id          TEXT    NOT NULL UNIQUE,
        started_at        REAL    NOT NULL,
        ended_at          REAL,
        duration_s        REAL,
        outcome           TEXT,             -- COMPLETED | ABORTED | EMERGENCY | FAULT
        qty_25mm          INTEGER,
        qty_50mm          INTEGER,
        products_done     INTEGER,
        high_speed        INTEGER,
        mode              TEXT,
        source_id         TEXT,
        max_step_reached  INTEGER,
        fault_count       INTEGER DEFAULT 0,
        stall_count       INTEGER DEFAULT 0,
        detail            TEXT
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_cycle_started ON cycle_history(started_at DESC)",

    # -- per-cycle aggregates -------------------------------------------
    """
    CREATE TABLE IF NOT EXISTS cycle_metrics (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        cycle_id    TEXT NOT NULL,
        metric      TEXT NOT NULL,
        min_value   REAL,
        max_value   REAL,
        avg_value   REAL,
        last_value  REAL,
        sample_count INTEGER DEFAULT 0,
        unit        TEXT,
        FOREIGN KEY (cycle_id) REFERENCES cycle_history(cycle_id) ON DELETE CASCADE
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_metrics_cycle ON cycle_metrics(cycle_id, metric)",

    # -- commands --------------------------------------------------------
    """
    CREATE TABLE IF NOT EXISTS command_history (
        id           INTEGER PRIMARY KEY AUTOINCREMENT,
        ts           REAL NOT NULL,
        command_id   TEXT,
        tag_id       TEXT NOT NULL,
        address      TEXT,
        requested    TEXT,
        observed     TEXT,
        dtype        TEXT,
        outcome      TEXT NOT NULL,       -- CONFIRMED | MISMATCH | REJECTED | ...
        latency_ms   REAL,
        operator     TEXT,
        origin       TEXT,                -- manual | auto | recovery | system
        source_id    TEXT,
        cycle_id     TEXT,
        error        TEXT
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_cmd_ts ON command_history(ts DESC)",
    "CREATE INDEX IF NOT EXISTS ix_cmd_tag_ts ON command_history(tag_id, ts DESC)",
    "CREATE INDEX IF NOT EXISTS ix_cmd_outcome ON command_history(outcome, ts DESC)",

    # -- operator snapshots ---------------------------------------------
    """
    CREATE TABLE IF NOT EXISTS data_snapshots (
        id         INTEGER PRIMARY KEY AUTOINCREMENT,
        ts         REAL NOT NULL,
        label      TEXT,
        note       TEXT,
        operator   TEXT,
        trigger    TEXT NOT NULL,        -- manual | cycle_end | fault | api
        mode       TEXT,
        lifecycle  TEXT,
        source_id  TEXT,
        cycle_id   TEXT,
        quality    TEXT,
        payload    TEXT NOT NULL         -- full JSON snapshot
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_snap_ts ON data_snapshots(ts DESC)",
    "CREATE INDEX IF NOT EXISTS ix_snap_trigger ON data_snapshots(trigger, ts DESC)",

    # -- recording sessions ----------------------------------------------
    """
    CREATE TABLE IF NOT EXISTS recording_sessions (
        id             INTEGER PRIMARY KEY AUTOINCREMENT,
        session_uid    TEXT NOT NULL UNIQUE,
        label          TEXT,
        note           TEXT,
        operator       TEXT,
        started_at     REAL NOT NULL,
        ended_at       REAL,
        mode           TEXT,
        source_id      TEXT,
        sample_interval_s REAL,
        deadband       REAL,
        tag_filter     TEXT,
        sample_count   INTEGER DEFAULT 0,
        dropped_count  INTEGER DEFAULT 0,
        status         TEXT NOT NULL DEFAULT 'ACTIVE'   -- ACTIVE | COMPLETED | ABORTED
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_sessions_started ON recording_sessions(started_at DESC)",
    "CREATE INDEX IF NOT EXISTS ix_sessions_status ON recording_sessions(status)",

    # -- recorded tag samples --------------------------------------------
    # The only high-volume table, and it can only grow while a recording
    # session is active.
    """
    CREATE TABLE IF NOT EXISTS tag_samples (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        session_uid TEXT NOT NULL,
        ts          REAL NOT NULL,
        tag_id      TEXT NOT NULL,
        num_value   REAL,
        bool_value  INTEGER,
        text_value  TEXT,
        quality     TEXT,
        source_id   TEXT,
        FOREIGN KEY (session_uid) REFERENCES recording_sessions(session_uid) ON DELETE CASCADE
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_samples_session_ts ON tag_samples(session_uid, ts DESC)",
    "CREATE INDEX IF NOT EXISTS ix_samples_session_tag_ts ON tag_samples(session_uid, tag_id, ts)",

    # -- long-term tag history (event-driven, not periodic) --------------
    # Transitions of *watched* tags only, so the diagnostic question "when did
    # SV8 actually change?" survives a restart. Bounded by the watch list.
    """
    CREATE TABLE IF NOT EXISTS historical_tag_data (
        id          INTEGER PRIMARY KEY AUTOINCREMENT,
        ts          REAL NOT NULL,
        tag_id      TEXT NOT NULL,
        previous    TEXT,
        value       TEXT,
        attribution TEXT,               -- operator | plc | contested
        command_id  TEXT,
        source_id   TEXT,
        cycle_id    TEXT
    )
    """,
    "CREATE INDEX IF NOT EXISTS ix_hist_ts ON historical_tag_data(ts DESC)",
    "CREATE INDEX IF NOT EXISTS ix_hist_tag_ts ON historical_tag_data(tag_id, ts DESC)",
]

# Retention. Applied by a low-priority sweep in the writer thread, oldest first.
DEFAULT_RETENTION = {
    "system_events": 90,
    "alarms": 365,
    "state_history": 365,
    "cycle_history": 365,
    "cycle_metrics": 365,
    "command_history": 180,
    "historical_tag_data": 30,
    "tag_samples": 30,
    # data_snapshots and recording_sessions are deliberately absent: an
    # operator explicitly asked for those, so they are never swept
    # automatically. Deleting a manual capture behind someone's back would be
    # a nasty surprise.
}

RETENTION_TIME_COLUMN = {
    "system_events": "ts",
    "alarms": "raised_at",
    "state_history": "ts",
    "cycle_history": "started_at",
    "command_history": "ts",
    "historical_tag_data": "ts",
    "tag_samples": "ts",
}
