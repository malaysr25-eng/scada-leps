#!/usr/bin/env python3
"""
extract_cell_timings.py - pull everything the digital twin still needs out of
the SCADA platform's history database.

RUN THIS ON THE PC WITH THE SCADA DASHBOARD. It only READS the database and
writes one JSON file. It never writes a PLC tag and never touches the portal.

    python extract_cell_timings.py --db path/to/scada_history.db -o cell_timings.json
    python extract_cell_timings.py --db <path> --date 2026-09-21 -o cell_timings_2026-09-21.json

It copies the database (db + -wal) to a temporary folder and reads only the
copy, like capture_window.py. The live file is never opened.

Then send cell_timings.json back to the model side. That one file is enough;
the database itself does not need to travel.

WHY THIS EXISTS
---------------
The model's remaining error is a large block of machine time per cycle and the
largest identified cause is a set of dwell timers in the machine's own FC6 that
the model does not implement. Every one of them is measurable from the
transition log this database already holds. So is the belt speed, the cylinder
stroke time, the platform travel, and the spread across cycles that tells us how
much of the difference is real.

THE ONE TRAP, AND IT HAS ALREADY COST THIS PROJECT THREE SESSIONS
-----------------------------------------------------------------
The portal has a BUILT-IN PLC SIMULATOR. Cycles recorded against it look
completely normal - `source_id` reads "plc", the lifecycle reads COMPLETED -
and they are not the machine. They are seeded with this model's own parameter
values, so a model validated against them agrees with itself.

The reliable marker is `state_history` with kind='connection'. This script
reads it, builds the intervals when the backend was SIMULATED, and EXCLUDES
every cycle overlapping them.

Two further POSITIVE markers, either of which excludes on its own:
  - supply pressure pinned at exactly 6.2 bar (the real cell reads 4.0-4.4)
  - a conveyor Set_Velocity of exactly 0.150 or 0.200 - the model's own numbers.
    The real PLC technology objects read 180.0.

WHAT CHANGED, AND WHY IT MATTERS (2026-09-08)
---------------------------------------------
1. ABSENCE OF A TAG IS NOT EVIDENCE. An earlier version excluded any cycle with
   "no proximity sensor and no magazine pusher transition". But the recordings
   this project holds watched 13 of the machine's 158 tags: no proximity sensor
   appears in `historical_tag_data` AT ALL, so that test fired on every cycle
   ever recorded and reported 0 real out of 12 - including five genuine cycles
   of the real cell. It was not a discriminator, it was a constant.

   That test now runs ONLY over tags this cycle actually watched. If the
   proximity sensors were not being sampled, their silence proves nothing and is
   reported as `coverage_limited`, not as an exclusion.

2. THE RECORDER'S OWN TABLE WAS NEVER READ. Edges came from
   `historical_tag_data` only. The full-coverage capture - all 158 tags - lives
   in `tag_samples`, and that is where the only fully-watched real cycle is. Both
   tables are now merged, deduplicated, and reduced to level changes.

3. A TAG'S FIRST OBSERVATION IS ITS INITIAL LEVEL, NOT A TRANSITION. The
   recorder's first sweep writes every tag at once; counting those as edges put
   ~120 fake simultaneous "transitions" at the head of the timeline.

4. THE OUTFEED HAPPENS AFTER `ended_at`. Cycle end is stamped when
   `cycle_completed` rises, but prox 9, SV12 and the T#5S outfeed pulse land in
   the seconds after it. A tail window (--tail, default 15 s) catches them;
   anything past cycle end is flagged `after_cycle_end` in the timeline.

WHAT CHANGED FOR ROUND 4 (2026-09-15), schema 3
-----------------------------------------------
5. MANUAL BUTTON PRESSES ARE CUT OFF. A cycle record can run on into the
   maintainer's manual tests. On 2026-09-10, C0004-165150 (outcome
   MANUAL_SAVE) ran 403 s. The schema-2 script measured cylinder A's and B's
   "holds" from two button presses (4.605 s and 8.187 s). Intervals are now
   measured only up to the first manual_commands.* change inside the cycle.
   The timeline still keeps every event; those at or after the cut carry
   "after_manual_cut". --keep-manual turns the cut off. This is the rule
   Project_Notes/tools/cut_manual_tail.py applied by hand on 2026-09-13.
6. --date YYYY-MM-DD keeps only the cycles that started on that day (local).
7. Three more belt-2 intervals: prox 7 -> prox 8 (it becomes belt 2's speed
   once that distance is taped), conveyor 2 -> prox 8, and prox 8 -> SV11 (the
   bypass push).
8. Each cycle carries a "route": "engraved" if the platform moved (either
   limit switch changed), "bypass" if SV11 fired and the platform did not move,
   and "neither" otherwise. The 2026-09-10 cycles were all "neither": the block
   stopped at prox 8 and neither SV7 nor SV11 fired. Whole-cycle times are also
   given per route, every shape included.
9. It reads a copy of the database, never the live file (see the top).

Python 3.6+. Standard library only - no venv needed.
"""

import argparse
import datetime
import json
import os
import shutil
import sqlite3
import statistics
import sys
import tempfile
from collections import defaultdict

# --------------------------------------------------------------------------
# The tag namespace, as used by the portal. Verified against a real
# scada_history.db on 2026-09-08.
# --------------------------------------------------------------------------
DI = "io_status.digital_inputs."
DO = "io_status.digital_outputs."
AI = "io_status.analog_inputs."
POT = "pot_control."

PROX = [DI + "proximity_sensor%d" % i for i in range(1, 11)]
SOL = [DO + "solenoid_valve%d" % i for i in range(1, 14)]
CONV = [DO + "conveyor%d" % i for i in range(1, 4)]
UP_LIMIT = DI + "pgm_up_limit"
LOW_LIMIT = DI + "pgm_low_limit"
PRESSURE = AI + "pressure.value"
EMERGENCY = DI + "emergency"
ENGRAVE_DONE = "system.engraving_completed"
SET_VELOCITY = [POT + "conv%d.set_velocity" % i for i in range(1, 4)]
MANUAL = "manual_commands."      # HMI manual buttons; see header item 5

# What the model wants, and why. Each entry is:
#   (label, from_tag, from_edge, to_tag, to_edge, what it settles)
# Edges: 'rise' = false->true, 'fall' = true->false.
INTERVALS = [
    ("cycle_conveyor1_run", CONV[0], "rise", PROX[5], "rise",
     "belt 1 speed x distance to prox 6"),
    ("sv6_delay_after_prox6", PROX[5], "rise", SOL[5], "rise",
     "FC6 N4 dwell - modelled as 0, PLC listing says 2 s TON"),
    ("cycle_conveyor2_run", CONV[1], "rise", CONV[1], "fall",
     "belt 2 run length"),
    ("prox7_into_conveyor2", CONV[1], "rise", PROX[6], "rise",
     "where prox 7 sits along belt 2"),
    ("cylA_extend_duration", SOL[6], "rise", SOL[7], "rise",
     "cylinder A stroke time; model has 2.69 s at bore 32"),
    ("cylB_extend_duration", SOL[8], "rise", SOL[9], "rise",
     "cylinder B stroke time, the same question for the second barrel"),
    ("platform_rise", LOW_LIMIT, "rise", UP_LIMIT, "rise",
     "t_base_travel upward - the two limit edges, whatever the switch polarity"),
    ("platform_dwell_at_top", UP_LIMIT, "rise", UP_LIMIT, "fall",
     "operator notice + engrave + confirm, the 12.5 s [PLH] block"),
    ("operator_notice_and_engrave", UP_LIMIT, "rise", ENGRAVE_DONE, "rise",
     "platform at top -> operator's button press"),
    ("operator_confirm", ENGRAVE_DONE, "rise", UP_LIMIT, "fall",
     "button press -> platform starts moving again"),
    ("platform_fall", UP_LIMIT, "fall", LOW_LIMIT, "fall",
     "t_base_travel downward, currently 8.0 s [PLC]"),
    ("cycle_conveyor3_run", CONV[2], "rise", PROX[8], "rise",
     "belt 3 speed x distance to prox 9"),
    ("sv12_delay_after_prox9", PROX[8], "rise", SOL[11], "rise",
     "FC6 N16 gate"),
    ("sv12_pulse_width", SOL[11], "rise", SOL[11], "fall",
     "FC6 N16 T#5S pulse - model does not implement it"),
    # Round 4 (header item 7).
    ("prox7_to_prox8", PROX[6], "rise", PROX[7], "rise",
     "belt 2 speed, once the prox 7 -> prox 8 distance is taped"),
    ("conveyor2_to_prox8", CONV[1], "rise", PROX[7], "rise",
     "where prox 8 sits along belt 2"),
    ("prox8_to_sv11", PROX[7], "rise", SOL[10], "rise",
     "bypass: block at prox 8 -> SV11 push"),
]

# Coils whose ON-duration is itself a programmed pulse worth measuring.
PULSE_TAGS = [SOL[5], SOL[10], SOL[11], SOL[12], SOL[6], SOL[8], SOL[7], SOL[9]]

# Tags whose silence is only meaningful if they were actually being watched.
COVERAGE_GROUPS = {
    "proximity_sensors": PROX,
    "magazine_pushers": SOL[:5],
    "conveyors": CONV,
}

# `max_step_reached` for a cycle that ran the sequence all the way to the bin.
# Below it the cycle stopped early and its DURATION means nothing, even though
# the sub-intervals it did reach are perfectly good. Above it the sequencer
# re-entered - a second product on the same cycle record - so the duration
# covers more than one part. Either way, averaging them into one cycle time
# produces a number that describes no cycle that ever ran.
FULL_CYCLE_STEP = 34


def as_bool(v):
    """Tag values arrive as text or as an int; normalise to a bool."""
    if v is None:
        return None
    if isinstance(v, bool):
        return v
    s = str(v).strip().lower()
    if s in ("true", "1", "1.0", "on", "yes"):
        return True
    if s in ("false", "0", "0.0", "off", "no"):
        return False
    return None


def simulated_windows(cur):
    """[(start_ts, end_ts_or_None)] during which the backend was SIMULATED."""
    rows = list(cur.execute(
        "select ts, current from state_history where kind='connection' "
        "order by ts"))
    windows, open_at = [], None
    for ts, cur_state in rows:
        st = (cur_state or "").upper()
        if st == "SIMULATED" and open_at is None:
            open_at = ts
        elif st != "SIMULATED" and open_at is not None:
            windows.append((open_at, ts))
            open_at = None
    if open_at is not None:
        windows.append((open_at, None))
    return windows


def overlaps_simulated(start, end, windows):
    for w0, w1 in windows:
        if w1 is None:
            if end is None or end >= w0:
                return True
        elif start is not None and end is not None:
            if start < w1 and end > w0:
                return True
        elif start is not None and w0 <= start < w1:
            return True
    return False


def prior_level(cur, tag, t0):
    """The tag's last known level strictly before t0, or None if never seen.

    Both tables are change-logged, not periodic: a row is written when a value
    moves. So a tag's level at the start of a cycle is whatever it was last
    written as, however long ago - and without that, the first row inside the
    window is ambiguous. It is either the recorder opening its eyes on a level
    that was already there, or a genuine edge, and only the previous value tells
    you which. Getting this wrong costs the first transition of every cycle
    (conveyor 1 starting, which is the whole of `cycle_conveyor1_run`) or
    invents a hundred simultaneous ones.
    """
    best = None
    for row in cur.execute(
            "select ts, value from historical_tag_data where tag_id=? and ts < ? "
            "order by ts desc limit 1", (tag, t0)):
        b = as_bool(row[1])
        if b is not None:
            best = (row[0], b)
    for row in cur.execute(
            "select ts, bool_value, text_value from tag_samples where tag_id=? "
            "and ts < ? order by ts desc limit 1", (tag, t0)):
        b = as_bool(row[1] if row[1] is not None else row[2])
        if b is not None and (best is None or row[0] > best[0]):
            best = (row[0], b)
    return None if best is None else best[1]


def edges_for(cur, t0, t1):
    """{tag: [(ts, bool), ...]} over [t0, t1], from BOTH tables.

    `historical_tag_data` is the change log the portal writes for the tags on
    its watch list; `tag_samples` is what the recorder captures, which is where
    a full 158-tag capture lives. Neither alone is the whole picture.

    Returns level CHANGES only, measured against the level the tag already held
    when the cycle began - see prior_level(). A tag never seen before this
    window has no prior, so its first observation sets the baseline and is not
    counted as a transition.
    """
    raw = defaultdict(list)

    for ts, tag, val in cur.execute(
            "select ts, tag_id, value from historical_tag_data "
            "where ts >= ? and ts <= ?", (t0, t1)):
        b = as_bool(val)
        if b is not None:
            raw[tag].append((ts, b))

    for ts, tag, bval, tval in cur.execute(
            "select ts, tag_id, bool_value, text_value from tag_samples "
            "where ts >= ? and ts <= ?", (t0, t1)):
        b = as_bool(bval if bval is not None else tval)
        if b is not None:
            raw[tag].append((ts, b))

    out, initial = {}, {}
    for tag, series in raw.items():
        series.sort(key=lambda e: e[0])
        start = prior_level(cur, tag, t0)
        if start is None:
            start = series[0][1]
            series = series[1:]
        initial[tag] = start
        changes, last = [], start
        for ts, v in series:
            if v != last:
                changes.append((ts, v))
                last = v
        out[tag] = changes
    return out, initial


def first_edge(series, kind, after=None):
    want = True if kind == "rise" else False
    for ts, v in series:
        if after is not None and ts < after:
            continue
        if v is want:
            return ts
    return None


def measure(edges):
    """Every interval this script knows how to measure, for one cycle."""
    got = {}
    for label, ftag, fedge, ttag, tedge, _why in INTERVALS:
        a = first_edge(edges.get(ftag, []), fedge)
        if a is None:
            continue
        b = first_edge(edges.get(ttag, []), tedge, after=a + 1e-9)
        if b is None:
            continue
        got[label] = round(b - a, 3)
    for tag in PULSE_TAGS:
        a = first_edge(edges.get(tag, []), "rise")
        if a is None:
            continue
        b = first_edge(edges.get(tag, []), "fall", after=a + 1e-9)
        if b is not None:
            got["pulse_" + tag.rsplit(".", 1)[-1]] = round(b - a, 3)
    return got


def coverage_for(edges, initial):
    """Which tag groups were actually being watched over this cycle.

    'watched' means the tag was observed at all - it had a level. 'moved' means
    it changed. A group that was never watched cannot testify either way, and
    this is the whole reason the earlier version reported every real cycle as
    simulated.
    """
    cov = {}
    for name, tags in COVERAGE_GROUPS.items():
        watched = [t for t in tags if t in initial]
        moved = [t for t in tags if edges.get(t)]
        cov[name] = {
            "watched": len(watched),
            "of": len(tags),
            "moved": len(moved),
            "names_moved": sorted(t.rsplit(".", 1)[-1] for t in moved),
        }
    return cov


def summarise(values):
    vals = [v for v in values if v is not None]
    if not vals:
        return None
    s = {"n": len(vals), "min": min(vals), "max": max(vals),
         "mean": round(statistics.mean(vals), 3)}
    s["spread"] = round(s["max"] - s["min"], 3)
    if len(vals) > 1:
        s["stdev"] = round(statistics.stdev(vals), 3)
    return s


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--db", default="data/scada_history.db",
                    help="path to scada_history.db (default: data/scada_history.db)")
    ap.add_argument("-o", "--out", default="cell_timings.json")
    ap.add_argument("--tail", type=float, default=15.0,
                    help="seconds past ended_at to keep reading, so the outfeed "
                         "that fires on cycle completion is captured (default 15)")
    ap.add_argument("--include-simulated", action="store_true",
                    help="also compute stats over simulated cycles. Do not use "
                         "for calibration; it exists only to compare them.")
    ap.add_argument("--keep-manual", action="store_true",
                    help="do NOT cut a cycle at its first manual_commands change "
                         "(header item 5). Only for comparing with schema 2.")
    ap.add_argument("--date", help="only cycles that started on YYYY-MM-DD (local)")
    a = ap.parse_args()

    if not os.path.exists(a.db):
        sys.exit("No database at %s\nPass --db with the right path." % a.db)

    # A COPY, never the live file (header item 9). The -wal holds the newest
    # rows, so it is copied too; the copy is opened normally, which folds the
    # WAL in. The -shm is an index SQLite rebuilds, and the backend can hold a
    # lock on it, so it is not needed.
    tmp = tempfile.mkdtemp(prefix="cell_timings_")
    copy = os.path.join(tmp, "scada_history.db")
    shutil.copy2(a.db, copy)
    if os.path.exists(a.db + "-wal"):
        try:
            shutil.copy2(a.db + "-wal", copy + "-wal")
        except OSError:
            print("WARNING: could not copy %s-wal - the newest rows may be missing" % a.db)
    con = sqlite3.connect(copy)
    cur = con.cursor()

    sim_windows = simulated_windows(cur)

    cycles, real, simulated, unknown = [], [], [], []
    q = ("select cycle_id, started_at, ended_at, duration_s, outcome, "
         "source_id, mode, qty_25mm, qty_50mm, max_step_reached "
         "from cycle_history order by started_at")
    # FETCHALL, and a SEPARATE cursor for the per-cycle queries below.
    # Iterating `cur` directly while the loop body also calls cur.execute()
    # resets the outer result set: the loop then stops after ONE cycle and
    # reports the rest as if they did not exist. No error, no warning, just a
    # short answer - which on a database of ten real cycles would look like a
    # database of one. Caught on 2026-09-08 by a row count that disagreed with
    # a direct query.
    rows = list(con.execute(q))
    if a.date:
        rows = [r for r in rows if r[1] is not None and
                datetime.datetime.fromtimestamp(r[1]).strftime("%Y-%m-%d") == a.date]
    inner = con.cursor()
    n_cut = 0
    for (cid, t0, t1, dur, outcome, src, mode, q25, q50, step) in rows:
        rec = {"cycle_id": cid, "started_at": t0, "ended_at": t1,
               "duration_s": dur, "outcome": outcome, "source_id": src,
               "mode": mode, "qty_25mm": q25, "qty_50mm": q50,
               "max_step_reached": step}

        if t0 is None or t1 is None:
            rec["verdict"] = "UNKNOWN - no start/end timestamp"
            unknown.append(rec)
            cycles.append(rec)
            continue

        # Read past cycle end: the outfeed fires as `cycle_completed` rises.
        t_end = t1 + a.tail
        edges, initial = edges_for(inner, t0, t_end)
        rec["transition_count"] = sum(len(v) for v in edges.values())
        rec["tags_watched"] = len(initial)
        rec["tags_that_moved"] = sorted(t for t in edges if edges[t])

        # THE MANUAL CUT (header item 5). Everything the PLC did by itself is
        # measured; nothing a person commanded from the HMI is.
        t_cut = None
        man = sorted((ts, tag) for tag, series in edges.items()
                     if tag.startswith(MANUAL) for ts, _v in series)
        if man and not a.keep_manual:
            t_cut = man[0][0]
            n_cut += 1
            rec["manual_cut"] = {
                "at_t": round(t_cut - t0, 3),
                "first_manual_tag": man[0][1],
                "manual_changes_dropped": len(man),
                "rule": "intervals use only events before the first "
                        "manual_commands change; the timeline keeps them all",
            }
        auto = edges if t_cut is None else {
            tag: [e for e in series if e[0] < t_cut] for tag, series in edges.items()}
        rec["watch_coverage"] = coverage_for(auto, initial)
        rec["intervals"] = measure(auto)

        # Which way the block went (header item 8).
        platform = bool(auto.get(UP_LIMIT) or auto.get(LOW_LIMIT))
        sv11 = first_edge(auto.get(SOL[10], []), "rise") is not None
        rec["route"] = ("engraved" if platform else
                        "bypass" if sv11 else "neither")

        # THE RAW TIMELINE, seconds from cycle start, for every tag that moved.
        # Carried in full because no list of intervals written in advance can
        # anticipate what the model will need next: the FC6 dwell timers were
        # only identified after somebody read the transition order, not from a
        # metric anyone had thought to compute. Small - a cycle is a few
        # hundred edges - and it makes the export self-contained.
        tl = []
        for tag, series in edges.items():
            short = tag.rsplit(".", 1)[-1]
            for ts, v in series:
                e = {"t": round(ts - t0, 3), "tag": short,
                     "value": bool(v), "full_tag": tag}
                if ts > t1:
                    e["after_cycle_end"] = True
                if t_cut is not None and ts >= t_cut:
                    e["after_manual_cut"] = True
                tl.append(e)
        rec["timeline"] = sorted(tl, key=lambda e: (e["t"], e["tag"]))

        # pressure behaviour during the cycle
        pv = [r[0] for r in inner.execute(
            "select num_value from tag_samples where tag_id=? and ts between ? and ? "
            "and num_value is not null", (PRESSURE, t0, t_end))]
        if pv:
            rec["pressure_bar"] = {"min": min(pv), "max": max(pv), "n": len(pv)}

        # conveyor Set_Velocity seen during the cycle, from either table
        vel = set()
        for tag in SET_VELOCITY:
            for r in inner.execute(
                    "select num_value from tag_samples where tag_id=? "
                    "and ts between ? and ? and num_value is not null",
                    (tag, t0, t_end)):
                vel.add(round(r[0], 4))
            for r in inner.execute(
                    "select value from historical_tag_data where tag_id=? "
                    "and ts between ? and ?", (tag, t0, t_end)):
                try:
                    vel.add(round(float(r[0]), 4))
                except (TypeError, ValueError):
                    pass
        if vel:
            rec["set_velocity_seen"] = sorted(vel)

        # --- the source check ---
        # Only POSITIVE evidence excludes. Each of these is something the
        # simulator does that the machine does not.
        reasons = []
        if overlaps_simulated(t0, t1, sim_windows):
            reasons.append("state_history says connection=SIMULATED over this cycle")
        if pv and min(pv) == max(pv) == 6.2:
            reasons.append("supply pressure pinned at exactly 6.2 bar")
        model_vels = sorted(v for v in vel if v in (0.15, 0.2))
        if model_vels:
            reasons.append("conveyor Set_Velocity reads %s - the model's own "
                           "numbers; the real axes read 180.0"
                           % ", ".join(str(v) for v in model_vels))

        # The silence of the proximity sensors and magazine pushers is only
        # evidence if they were being watched. See the header, item 1.
        cov = rec["watch_coverage"]
        prox_watched = cov["proximity_sensors"]["watched"]
        push_watched = cov["magazine_pushers"]["watched"]
        prox_moved = cov["proximity_sensors"]["moved"]
        push_moved = cov["magazine_pushers"]["moved"]
        notes = []
        if prox_watched and push_watched:
            if not prox_moved and not push_moved:
                reasons.append("no proximity sensor and no magazine pusher "
                               "transition, and both groups WERE being watched")
        else:
            notes.append(
                "coverage_limited: %d/10 proximity sensors and %d/5 magazine "
                "pushers were watched in this cycle, so their silence is not "
                "evidence either way" % (prox_watched, push_watched))
        if notes:
            rec["notes"] = notes

        # How much of the sequence this cycle actually ran. Independent of
        # whether it was real - a real cycle can still be a partial one.
        if step is None:
            rec["cycle_shape"] = "unknown - no max_step_reached"
        elif step < FULL_CYCLE_STEP:
            rec["cycle_shape"] = ("partial - stopped at step %d of %d, so "
                                  "duration_s is not a cycle time"
                                  % (step, FULL_CYCLE_STEP))
        elif step > FULL_CYCLE_STEP:
            rec["cycle_shape"] = ("extended - reached step %d, past the normal "
                                  "end of %d; the sequencer re-entered, so "
                                  "duration_s covers more than one part"
                                  % (step, FULL_CYCLE_STEP))
        else:
            rec["cycle_shape"] = "full"

        if reasons:
            rec["verdict"] = "SIMULATED - EXCLUDED"
            rec["why_excluded"] = reasons
            simulated.append(rec)
        else:
            rec["verdict"] = "REAL"
            real.append(rec)
        cycles.append(rec)

    pool = real if not a.include_simulated else real + simulated
    stats = {}
    for label, _f, _fe, _t, _te, why in INTERVALS:
        vals = [c["intervals"].get(label) for c in pool if "intervals" in c]
        s = summarise(vals)
        if s:
            s["settles"] = why
            stats[label] = s
    for tag in PULSE_TAGS:
        key = "pulse_" + tag.rsplit(".", 1)[-1]
        s = summarise([c.get("intervals", {}).get(key) for c in pool])
        if s:
            stats[key] = s
    # Whole-cycle time over FULL cycles only. A partial cycle's duration is not
    # a cycle time and an extended one covers more than one part; mixing them
    # in gives a mean that describes nothing.
    full = [c for c in pool if c.get("cycle_shape") == "full" and c.get("duration_s")]
    s = summarise([c["duration_s"] for c in full])
    if s:
        s["settles"] = "whole cycle, start to bin, full cycles only"
        s["cycle_ids"] = [c["cycle_id"] for c in full]
        stats["whole_cycle"] = s
    other = [c for c in pool if c.get("cycle_shape") != "full" and c.get("duration_s")]
    if other:
        stats["whole_cycle_excluded_shapes"] = {
            "n": len(other),
            "note": "not counted in whole_cycle - partial or extended cycles",
            "cycles": [{"cycle_id": c["cycle_id"], "duration_s": c["duration_s"],
                        "shape": c["cycle_shape"]} for c in other],
        }

    # Whole-cycle time per route, every shape included: a bypass cycle's
    # max_step_reached has never been seen, so the full-cycle rule above may
    # not fit it. Read each with its shapes.
    by_route = {}
    for route in ("engraved", "bypass", "neither"):
        cs = [c for c in pool if c.get("route") == route and c.get("duration_s")]
        s = summarise([c["duration_s"] for c in cs])
        if s:
            s["cycle_ids"] = [c["cycle_id"] for c in cs]
            s["shapes"] = sorted(set(str(c.get("cycle_shape")) for c in cs))
            by_route[route] = s
    if by_route:
        stats["whole_cycle_by_route"] = by_route

    out = {
        "schemaVersion": 3,
        "generatedBy": "extract_cell_timings.py (round 4)",
        "database": os.path.abspath(a.db),
        "tail_seconds": a.tail,
        "manual_cut": not a.keep_manual,
        "date": a.date,
        "simulated_windows": [{"from": w0, "to": w1} for w0, w1 in sim_windows],
        "counts": {"total": len(cycles), "real": len(real),
                   "simulated_excluded": len(simulated), "unknown": len(unknown)},
        "statistics_over": "real cycles only" if not a.include_simulated
                           else "real AND simulated - NOT for calibration",
        "statistics": stats,
        "cycles": cycles,
    }
    with open(a.out, "w") as f:
        json.dump(out, f, indent=2, sort_keys=False)

    print("Read   %s" % os.path.abspath(a.db))
    print("Cycles %d total: %d REAL, %d simulated (excluded), %d unknown"
          % (len(cycles), len(real), len(simulated), len(unknown)))
    if sim_windows:
        print("       %d SIMULATED window(s) found in state_history" % len(sim_windows))
    if a.date:
        print("       only cycles started on %s" % a.date)
    if n_cut:
        print("       %d cycle(s) cut at their first manual button press "
              "(see manual_cut in the JSON)" % n_cut)
    routes = defaultdict(int)
    for c in cycles:
        routes[c.get("route", "no timeline")] += 1
    print("       routes: %s" % ", ".join("%s %d" % kv for kv in sorted(routes.items())))

    limited = [c for c in cycles if c.get("notes")]
    if limited:
        print()
        print("  %d cycle(s) ran with a narrowed watch list. Their proximity"
              % len(limited))
        print("  sensors and magazine pushers were not sampled, so nothing can be")
        print("  concluded from their silence - and the intervals that depend on")
        print("  those tags are simply absent. Widen the watch list and re-run.")

    if not real:
        print()
        print("  *** NO REAL CYCLES IN THIS DATABASE. ***")
        print("  Nothing here can calibrate the model. Every cycle is excluded;")
        print("  see 'why_excluded' per cycle in the JSON. Run the cell with the")
        print("  backend connected to the real PLC and re-run this script.")
    else:
        print()
        print("  %-32s %6s %8s %8s %8s" % ("interval", "n", "mean", "min", "max"))
        for k, v in stats.items():
            if "mean" not in v:
                continue
            print("  %-32s %6d %8.3f %8.3f %8.3f"
                  % (k, v["n"], v["mean"], v["min"], v["max"]))
        skipped = stats.get("whole_cycle_excluded_shapes")
        if skipped:
            print()
            print("  %d cycle(s) left out of whole_cycle as partial or extended:"
                  % skipped["n"])
            for c in skipped["cycles"]:
                print("     %-24s %8.2f s  %s"
                      % (c["cycle_id"], c["duration_s"], c["shape"]))
    print()
    print("Wrote  %s" % os.path.abspath(a.out))
    print("Send that one file back to the model side.")


if __name__ == "__main__":
    main()
