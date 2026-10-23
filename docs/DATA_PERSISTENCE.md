# SQL PERSISTENCE, INGESTION AND RECORDING

How history is stored without blocking the control loop or filling the disk.

---

## 1. The two problems, and the two answers

**Problem 1: a database write must never delay a PLC poll.**
A 250 ms control loop that occasionally blocks for a 40 ms fsync is a loop with
40 ms of jitter, and the trustworthiness of the poll cadence is the foundation
everything else rests on.

*Answer:* the poll thread's entire interaction with the database is
`queue.put_nowait(record)`. A separate writer thread owns the SQLite
connection. When the queue fills the store **drops the record and counts it** —
it never blocks and never grows without bound.

**Problem 2: 158 tags at 250 ms is 54 million rows a day.**

*Answer:* nothing is written per poll. Events, alarms, transitions, commands
and cycle summaries only. Per-tag samples require an operator to start a
recording, and even then are interval-limited and deadbanded.

---

## 2. Architecture

```
PLC poll thread                    writer thread              HTTP threads
──────────────                     ─────────────              ────────────
Core._persist()
  IngestPolicy.on_*()
    store.write(table, **cols)
      queue.put_nowait()  ──────►  drain up to batch_size
      (O(1), never blocks)         executemany + ONE commit
                                   retention sweep            short-lived
                                          │                   read-only
                                          ▼                   connections
                                   scada_history.db (WAL)  ◄──────┘
```

WAL mode is what lets the History page read while the writer writes, without
either blocking the other.

`synchronous=NORMAL` trades a small durability window for not fsyncing on every
commit. Losing the last few seconds of *diagnostic history* after a power cut is
acceptable; stalling the control loop is not.

---

## 3. Schema

| table | holds | typical rows/day |
|---|---|---|
| `system_events` | every emitted event | hundreds |
| `alarms` | latched faults, raised and cleared | tens |
| `state_history` | lifecycle / mode / source / connection transitions | tens |
| `cycle_history` | one row per cycle | tens–hundreds |
| `cycle_metrics` | min/max/avg per cycle, per signal | ~10 per cycle |
| `command_history` | every write with its read-back outcome | tens |
| `data_snapshots` | operator captures (full JSON state) | a handful |
| `recording_sessions` | explicit recordings | a handful |
| `tag_samples` | **only inside a recording**, sampled + deadbanded | bounded by the session |
| `historical_tag_data` | watched-tag transitions | bounded by the watch list |

Every table is indexed by time, plus the specific shapes `queries.py` actually
uses (session+tag, alarm key, severity) rather than hopeful extra indexes.

---

## 4. Ingestion policy

Four paths, in increasing volume:

### 1. Event-driven — always on, cheap
Something a human would want to read later: a fault latched, the lifecycle
changed, a command was written, a cycle finished. Volume follows the machine's
behaviour, not the poll rate.

### 2. Watched-tag transitions — always on, bounded
Only tags on the watch list, only when they change, **rate-limited per tag**.

The rate limit is protection, not optimisation. A tag toggling at 3 Hz — the
reported SV8 behaviour from the Errors sheet — would write a quarter of a
million rows a day on its own. After the burst limit the tag is suppressed and
the *suppressed count* is recorded, so the fact of the chatter survives even
though individual edges do not.

### 3. Cycle summaries and aggregates — one row per cycle
Min/max/avg accumulated **in memory** during the cycle, written once at the
end. Trendable history at a thousandth of the row cost of storing samples.

### 4. Recording sessions — operator-initiated
Per-tag samples, with an interval and a deadband.

### Deadband

A `Real` jittering in its last decimal place is not news. Numeric samples are
stored only when they move by more than the deadband, or when `max_interval`
has elapsed — so a flat trace still gets periodic anchors and a gap means "not
recorded" rather than being indistinguishable from "unchanged".

Bools store on every change, because for a Bool every change *is* the news.

### Measured effect

A 22-second cycle with recording active:

| | rows |
|---|---|
| Naive (every tag, every poll) | ~13 900 |
| This policy | 202 samples + ~120 event/state/command rows |

**~98 % reduction**, and the 202 are only there because a recording was
running. Idle, a six-second window adds **zero** tag rows — asserted by
`selftest_extended.py` §15.

---

## 5. Backpressure: drop, don't block

The queue is bounded (default 20 000). When it fills, the store increments
`dropped` and returns False. It does not block, and it does not grow until the
process dies.

That is the right trade here: the database holds diagnostic history, and losing
some is annoying. Stalling the control loop, or exhausting memory, is dangerous.
The dropped count is surfaced in the UI so the loss is visible, not silent.

Measured on a live simulated cycle: **324 rows written, 0 dropped, 0.47 ms
average batch write, PLC poll latency unaffected.**

---

## 6. Retention

A low-priority sweep runs hourly in the writer thread, oldest first, `LIMIT
20000` per pass so one sweep cannot hold the write lock for long.

| table | default |
|---|---|
| `system_events` | 90 days |
| `alarms`, `state_history`, `cycle_history`, `cycle_metrics` | 365 days |
| `command_history` | 180 days |
| `historical_tag_data`, `tag_samples` | 30 days |
| `data_snapshots`, `recording_sessions` | **never swept** |

Snapshots and recordings are exempt deliberately: an operator explicitly asked
for those, and deleting a manual capture behind someone's back would be a nasty
surprise.

Override per table in `config.json → db.retention_days`.

---

## 7. Manual capture

| action | endpoint | what it stores |
|---|---|---|
| Save Snapshot | `POST /api/data/snapshot` | the complete composed state as one row |
| Start Recording | `POST /api/data/recording/start` | opens a session |
| Stop Recording | `POST /api/data/recording/stop` | closes it, writes final counts |
| Save Cycle | `POST /api/data/cycle/save` | cycle summary + aggregates + a pinned snapshot |

All on the **Data** page. Sessions are bounded by `max_session_seconds` (1 h)
and `max_session_samples` (500 000) so a forgotten recording cannot fill the
disk.

---

## 8. Querying

The **History** page has tabs for cycles, events, alarms, snapshots and
recordings. Every query is bounded by a `LIMIT` and shaped to hit an index — an
unbounded scan of `tag_samples` from an HTTP thread would hold a read
transaction long enough to matter.

Recordings export as CSV: `GET /api/history/sessions/<uid>/export`.

---

## 9. Why SQLite

- Keeps the dependency list at `flask` + `python-snap7` and nothing else, so it
  installs on an offline lab PC.
- No service to administer on a machine whose job is running an HMI.
- Comfortable for the intended volume, because the ingestion policy keeps
  writes in the tens per minute rather than thousands per second.
- WAL gives concurrent reads alongside the single writer.

`db.path` accepts any path. The store is written against a narrow DB-API
surface, so swapping to Postgres later is contained to `store.py` — but there
is no reason to until the volume justifies it, and this policy is designed so
it does not.
