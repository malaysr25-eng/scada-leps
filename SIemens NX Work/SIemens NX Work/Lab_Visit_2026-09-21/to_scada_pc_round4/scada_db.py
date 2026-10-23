"""Shared helpers: find the SCADA history database, and read a COPY of it.

READ-ONLY BY CONSTRUCTION. Nothing here ever opens the live database file.
The database, its -wal journal and its -shm index are copied to a temporary
folder first and only the copy is opened. A copy includes rows still sitting in
the WAL, which a read-only or immutable open of the live file can miss.

Why the search: on 2026-09-10 the backend was started from one directory above
scada_platform/, so it wrote to new_scada/data/ instead of
scada_platform/data/, and the obvious path read the OLD file. So every
candidate is checked and the one with the newest sample wins. The choice is
printed so a human can see it.

Python 3.6+, standard library only.
"""
import os
import shutil
import sqlite3
import tempfile
import time
import datetime

CANDIDATES = [
    'data/scada_history.db',
    '../data/scada_history.db',
    '../../data/scada_history.db',
    r'C:/Users/DELL/Desktop/new_scada/data/scada_history.db',
    r'C:/Users/DELL/Desktop/new_scada/scada_platform/data/scada_history.db',
]


def snapshot(path):
    """Copy db + -wal + -shm to a temp folder and open the copy."""
    tmp = tempfile.mkdtemp(prefix='scada_snap_')
    dst = os.path.join(tmp, 'scada_history.db')
    shutil.copy2(path, dst)
    # -wal holds the newest rows, so it is retried and a failure is reported.
    # -shm is only an index SQLite rebuilds from the -wal; while the backend
    # has the database open, Windows can hold an exclusive lock on it, so a
    # failed -shm copy is expected and skipped. (Fixed 2026-09-10: the first
    # version copied -shm unconditionally and crashed with PermissionError.)
    for ext in ('-wal', '-shm'):
        if not os.path.exists(path + ext):
            continue
        for attempt in range(3):
            try:
                shutil.copy2(path + ext, dst + ext)
                break
            except (PermissionError, OSError):
                if ext == '-shm':
                    break
                time.sleep(0.3)
        else:
            print('WARNING  : could not copy %s - the newest rows may be missing' % (path + ext))
    con = sqlite3.connect(dst)
    con.row_factory = None
    return con, dst


def newest_sample(con):
    try:
        r = con.execute('select max(ts) from tag_samples').fetchone()
        return r[0] or 0.0
    except sqlite3.Error:
        return 0.0


def find_db(explicit=None, verbose=True):
    """Return (connection to a copy, original path)."""
    if explicit:
        if not os.path.exists(explicit):
            raise SystemExit('database not found: %s' % explicit)
        con, _ = snapshot(explicit)
        if verbose:
            print('database : %s  (newest sample %s)' % (explicit, fmt(newest_sample(con))))
        return con, explicit
    best = None
    seen = []
    for c in CANDIDATES:
        p = os.path.abspath(c)
        if not os.path.exists(p) or p in seen:
            continue
        seen.append(p)
        con, _ = snapshot(p)
        t = newest_sample(con)
        if verbose:
            print('candidate: %s  newest sample %s' % (p, fmt(t) if t else '-'))
        if best is None or t > best[1]:
            best = (con, t, p)
    if best is None:
        raise SystemExit('no scada_history.db found; pass --db <path>')
    if verbose:
        print('USING    : %s' % best[2])
        age = time.time() - best[1]
        if age > 120:
            print('WARNING  : newest sample is %.0f s old - is the recorder running?' % age)
    return best[0], best[2]


def fmt(ts):
    """Time of day; the DATE is added whenever it is not today. (Fixed
    2026-09-10: without it a 2026-09-01 sample read as newer than today's.)"""
    if not ts:
        return '-'
    d = datetime.datetime.fromtimestamp(ts)
    if d.date() == datetime.date.today():
        return d.strftime('%H:%M:%S.%f')[:-3]
    return d.strftime('%Y-%m-%d %H:%M:%S.%f')[:-3]


def parse_when(s, now=None, date=None):
    """'HH:MM', 'HH:MM:SS' (on --date, default today, local) or an epoch."""
    now = now or time.time()
    if date:
        now = time.mktime(datetime.datetime.strptime(date, '%Y-%m-%d').timetuple()) + 43200
    try:
        v = float(s)
        if v > 1e9:
            return v
    except ValueError:
        pass
    parts = [int(x) for x in s.split(':')]
    while len(parts) < 3:
        parts.append(0)
    d = datetime.datetime.fromtimestamp(now)
    return time.mktime(d.replace(hour=parts[0], minute=parts[1], second=parts[2],
                                 microsecond=0).timetuple())


def columns(con, table):
    return [r[1] for r in con.execute('pragma table_info(%s)' % table)]
