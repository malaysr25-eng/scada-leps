"""Everything the PLC saw in a time window, as a timeline. READ-ONLY.

Use it right after each physical test: note the clock time before and after,
then

    python capture_window.py --from 16:40 --to 16:43 --label tape_belt2
    python capture_window.py --last-min 5 --label sv9_video
    python capture_window.py --from 09:00 --match conveyor3,conv3 --label conv3_diag
    python capture_window.py --date 2026-09-10 --from 16:57:10 --to 16:58:00 --label past_day

Writes <label>_timeline.txt (readable) and <label>.json (everything) into
--out-dir (default: ./outbox). Prints a short summary.

What it reports:
  - every change of every tag in the window, with the value each tag held
    just BEFORE the window (the database stores changes, so without that the
    first change of each tag would be silently lost - a bug caught 2026-09-10)
  - pulse widths (on -> off) of every boolean
  - every manual command (requested / observed / latency)
  - system events and alarms in the window
  - which recording session was active and its sample interval

NOTE ON MANUAL COMMANDS: the time a coil is held is how long a HUMAN held the
button, not how long the rod took to move. There are no reed switches on these
cylinders. Rod travel times come only from video.
"""
import argparse
import json
import os
import time

import scada_db as S

NOISY = ('.normx',)          # skipped in the readable timeline, kept in JSON


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--db')
    ap.add_argument('--from', dest='t_from')
    ap.add_argument('--to', dest='t_to')
    ap.add_argument('--last-min', type=float)
    ap.add_argument('--date', help='YYYY-MM-DD for --from/--to (default today)')
    ap.add_argument('--label', default='window')
    ap.add_argument('--out-dir', default='outbox')
    ap.add_argument('--match', default='',
                    help='comma list; keep only tags/events containing one of these')
    a = ap.parse_args()

    con, path = S.find_db(a.db)
    now = time.time()
    if a.last_min:
        t0, t1 = now - 60 * a.last_min, now
    else:
        if not a.t_from:
            raise SystemExit('give --from HH:MM (and optionally --to) or --last-min N')
        t0 = S.parse_when(a.t_from, now, a.date)
        t1 = S.parse_when(a.t_to, now, a.date) if a.t_to else now
    if t1 <= t0:
        raise SystemExit('window is empty: %s -> %s' % (S.fmt(t0), S.fmt(t1)))
    match = [m.strip().lower() for m in a.match.split(',') if m.strip()]
    keep = (lambda s: True) if not match else (lambda s: any(m in (s or '').lower() for m in match))
    print('window   : %s -> %s  (%.1f s)' % (S.fmt(t0), S.fmt(t1), t1 - t0))

    # ---- tag changes, with the state before the window --------------------
    tags = [r[0] for r in con.execute(
        'select distinct tag_id from tag_samples where ts between ? and ?', (t0, t1))]
    events, pulses, before = [], [], {}
    for tg in sorted(tags):
        if not keep(tg):
            continue
        prev = con.execute(
            'select bool_value,num_value,text_value from tag_samples '
            'where tag_id=? and ts<? order by ts desc limit 1', (tg, t0)).fetchone()
        last = None if prev is None else next((v for v in prev if v is not None), None)
        before[tg] = last
        rise = None
        if last in (1, True):
            rise = t0
        for ts, b, n, x in con.execute(
                'select ts,bool_value,num_value,text_value from tag_samples '
                'where tag_id=? and ts between ? and ? order by ts', (tg, t0, t1)):
            v = b if b is not None else (n if n is not None else x)
            if last is None or v != last:
                events.append({'t': ts, 'tag': tg, 'from': last, 'to': v})
                if b is not None:
                    if v and not last:
                        rise = ts
                    elif (not v) and last and rise is not None:
                        pulses.append({'tag': tg, 'on': rise, 'off': ts, 'width_s': ts - rise})
                        rise = None
            last = v
    events.sort(key=lambda e: e['t'])

    # ---- commands, events, alarms, session ---------------------------------
    def rows(sql, args):
        cur = con.execute(sql, args)
        cols = [d[0] for d in cur.description]
        return [dict(zip(cols, r)) for r in cur]

    cmds = [c for c in rows('select * from command_history where ts between ? and ? order by ts', (t0, t1))
            if keep(c.get('tag_id'))]
    sysev = [e for e in rows('select * from system_events where ts between ? and ? order by ts', (t0, t1))
             if keep(e.get('message')) or keep(e.get('detail'))]
    alarms = [x for x in rows('select * from alarms where (raised_at between ? and ?) or '
                              '(cleared_at between ? and ?) order by raised_at', (t0, t1, t0, t1))
              if keep(x.get('alarm_key')) or keep(x.get('message'))]
    sess = rows('select session_uid,label,started_at,ended_at,sample_interval_s,deadband,status '
                'from recording_sessions where started_at<=? and (ended_at is null or ended_at>=?)',
                (t1, t0))

    # ---- write --------------------------------------------------------------
    os.makedirs(a.out_dir, exist_ok=True)
    base = os.path.join(a.out_dir, a.label)
    out = {'database': path, 'window': [t0, t1], 'window_local': [S.fmt(t0), S.fmt(t1)],
           'match': match, 'sessions': sess, 'state_before': before, 'changes': events,
           'pulses': pulses, 'commands': cmds, 'system_events': sysev, 'alarms': alarms}
    with open(base + '.json', 'w') as f:
        json.dump(out, f, indent=1, default=str)

    with open(base + '_timeline.txt', 'w') as f:
        w = lambda s='': (f.write(s + '\n'), print(s))
        w('WINDOW %s -> %s   db %s' % (S.fmt(t0), S.fmt(t1), path))
        # The sample count is the real test of whether the recorder was
        # capturing. (Fixed 2026-09-10: a session row left with ended_at NULL
        # matched every window, so the old warning could never fire.)
        nsamp = con.execute('select count(*) from tag_samples where ts between ? and ?',
                            (t0, t1)).fetchone()[0]
        w('tag_samples in window: %d' % nsamp)
        if nsamp == 0:
            w('WARNING: NO tag_samples in this window - the recorder was not capturing')
        for s in sess:
            orphan = ' (ended_at NULL - may be an orphaned row, not a live session)'                 if s['ended_at'] is None and s['started_at'] < t0 - 3700 else ''
            w('session %s "%s" sample %.3f s%s' % (s['session_uid'], s['label'],
                                                 s['sample_interval_s'] or 0, orphan))
        w('\n-- changes (t = seconds from window start) --')
        for e in events:
            if any(e['tag'].endswith(n) for n in NOISY):
                continue
            w('%9.3f  %s  %-52s %s -> %s' % (e['t'] - t0, S.fmt(e['t']), e['tag'], e['from'], e['to']))
        w('\n-- boolean pulse widths --')
        for p in pulses:
            w('  %-52s %s -> %s  %.3f s' % (p['tag'], S.fmt(p['on']), S.fmt(p['off']), p['width_s']))
        w('\n-- manual commands --')
        for c in cmds:
            w('  %s  %-40s req=%-5s obs=%-5s %-10s %s ms' % (S.fmt(c['ts']), c['tag_id'], c['requested'],
                                                            c['observed'], c['outcome'], c['latency_ms']))
        w('\n-- alarms --')
        for x in alarms:
            w('  %s  %-36s %s' % (S.fmt(x['raised_at']), x['alarm_key'], (x['message'] or '')[:110]))
        w('\n-- system events (%d) --' % len(sysev))
        for e in sysev[:400]:
            w('  %s  %-8s %-10s %s' % (S.fmt(e['ts']), e['severity'], e['category'], (e['message'] or '')[:100]))
    print('\nwrote %s.json and %s_timeline.txt' % (base, base))
    print('%d changes, %d pulses, %d commands, %d alarms, %d events' %
          (len(events), len(pulses), len(cmds), len(alarms), len(sysev)))


if __name__ == '__main__':
    main()
