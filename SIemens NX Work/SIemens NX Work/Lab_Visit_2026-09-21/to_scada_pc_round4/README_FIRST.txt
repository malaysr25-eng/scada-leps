COPY THIS WHOLE FOLDER TO THE SCADA PC            round 4, for Monday 2026-09-21
==========================================================================

  PROMPT.txt               Paste the block inside it into Claude on the SCADA
                           PC, from this folder. It does the software half.
  LAB_HOUR_LOG.md          For YOU at the machine: write the clock time at the
                           start and end of each test.
  capture_window.py        Everything the PLC saw in a time window.
  scada_db.py              Helper used by capture_window.py. Keep it beside it.
  extract_cell_timings.py  Round 4 (schema 3). Every cycle's intervals, as one
                           JSON file. Copies the database first.

Both scripts are read-only: they copy the database and read only the copy.
capture_window.py and scada_db.py are unchanged from round 3.

QUICK USE (from this folder, on the SCADA PC):

  python capture_window.py --last-min 2 --label recorder_check
  python capture_window.py --from 10:40:00 --to 10:43:30 --label bypass_1
  python extract_cell_timings.py --db <path> --date 2026-09-21 -o outbox/cell_timings_2026-09-21.json

WHAT IS NEW IN THE EXTRACTOR (2026-09-15)
  - It stops measuring a cycle at the first manual button press. On
    2026-09-10 a cycle record ran into the manual tests, and two button
    presses were counted as cylinder holds. That was fixed by hand; now it is
    automatic. --keep-manual turns it off.
  - --date keeps one day's cycles.
  - Each cycle says which route it took: engraved, bypass, or neither.
  - Three belt-2 intervals: prox 7 -> prox 8, conveyor 2 -> prox 8, and
    prox 8 -> SV11.
  TESTED before sending, on the 2026-09-10 database: with the cut it gives the
  same intervals as the hand-cut round-3 file; with --keep-manual it gives the
  original round-3 file. All five cycles matched.

RECORDING SESSIONS STOP AFTER ONE HOUR (max_session_seconds = 3600 in
config.json). Restart the recording every hour. Set a phone alarm.

BRING BACK: the outbox folder the SCADA session makes (database copy
included), your videos and photos copied to disk, and the filled
LAB_HOUR_LOG.md.
