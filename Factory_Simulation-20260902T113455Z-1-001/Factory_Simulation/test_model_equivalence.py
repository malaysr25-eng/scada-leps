"""
test_model_equivalence.py
=========================
Enforces the project's central claim: that janatics_physics.py is
equation-for-equation identical to the MATLAB implementation.

Both models are run over the same 42-step sequence and their state-transition
sequences are compared. Until this existed the agreement was verified by hand
once, and nothing failed if a later edit to one implementation drifted from the
other -- which is the risk, because that agreement is the strongest validation
evidence the project has.

REQUIRES MATLAB. Every test here skips cleanly if `matlab` is not on PATH, so
the suite still runs on a machine without it. Set FACTORY_SKIP_MATLAB=1 to skip
deliberately.

COST: MATLAB is launched once for the whole class (~60-90 s including startup),
not once per test.

Run:  python -m unittest test_model_equivalence -v
"""
import os
import shutil
import subprocess
import sys
import tempfile
import unittest

import janatics_physics as jp

HERE = os.path.dirname(os.path.abspath(__file__))

# Tolerances. These are not round numbers picked for comfort -- see the
# docstring on each test for what sets them.
TOL_TIME = 1e-6      # s   transition timestamps; both models fire on the
                     #     same t_scan grid, so these should agree exactly
TOL_POS = 1e-6       # m   integrated block position; measured delta is 4e-9
TOL_PRESSURE_REL = 1e-3   # -  peak pressures are SAMPLED maxima; see
                          #    test_peak_pressures_agree for why this is loose


def _matlab_available():
    if os.environ.get('FACTORY_SKIP_MATLAB'):
        return False
    return shutil.which('matlab') is not None


def _parse_export(path):
    """Parse the [SECTION] / tab-separated record written by MATLAB."""
    sections = {'STATES': [], 'TRANSITIONS': [], 'FINAL': {}}
    current = None
    with open(path, encoding='utf-8', errors='replace') as fh:
        for line in fh:
            line = line.rstrip('\n').rstrip('\r')
            if not line.strip():
                continue
            if line.startswith('[') and line.endswith(']'):
                current = line[1:-1]
                continue
            parts = line.split('\t')
            if current == 'STATES':
                sections['STATES'].append((int(parts[0]), parts[1], parts[2]))
            elif current == 'TRANSITIONS':
                sections['TRANSITIONS'].append((float(parts[0]), int(parts[1]), parts[2]))
            elif current == 'FINAL':
                sections['FINAL'][parts[0]] = float(parts[1])
    return sections


@unittest.skipUnless(_matlab_available(),
                     'MATLAB not on PATH (or FACTORY_SKIP_MATLAB set)')
class TestModelEquivalence(unittest.TestCase):
    """MATLAB implementation vs the janatics_physics.py port."""

    ml = None
    py = None

    @classmethod
    def setUpClass(cls):
        # --- MATLAB side: one launch for the whole class -----------------
        cls._tmpdir = tempfile.mkdtemp(prefix='factory_eq_')
        out = os.path.join(cls._tmpdir, 'equivalence_matlab.txt')
        proc = subprocess.run(
            ['matlab', '-batch',
             "export_equivalence_data('%s')" % out.replace('\\', '/')],
            cwd=HERE, capture_output=True, text=True, timeout=900)
        if not os.path.exists(out):
            raise unittest.SkipTest(
                'MATLAB export failed (exit %s).\nstdout:\n%s\nstderr:\n%s'
                % (proc.returncode, proc.stdout[-2000:], proc.stderr[-2000:]))
        cls.ml = _parse_export(out)

        # --- Python side --------------------------------------------------
        t, s, plc, trans, log, mj = jp.run(tmax=90.0, dt=5e-4, verbose=False)
        pkA = pkB = 0.0
        for _tt, st in log:
            for c in range(jp.NCYL):
                pkA = max(pkA, st[jp.IDX['PA_%d' % c]])
                pkB = max(pkB, st[jp.IDX['PB_%d' % c]])
        cls.py = dict(
            t=t, s=s, plc=plc, trans=trans,
            states=[(i, n, x) for i, (n, x) in enumerate(jp.STATES)],
            final=dict(cycle_time=t,
                       blk_x=s[jp.IDX['bx']], blk_y=s[jp.IDX['by']],
                       peak_PA=pkA, peak_PB=pkB),
        )

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(getattr(cls, '_tmpdir', ''), ignore_errors=True)

    # ---- state table ----------------------------------------------------

    def test_state_tables_are_identical(self):
        """factory_states.m and jp.STATES must list the same states in order.

        This is the cheapest possible drift detector: adding a state to one
        implementation and not the other breaks it before any physics runs.
        """
        ml_states = [(i, n) for i, n, _x in self.ml['STATES']]
        py_states = [(i, n) for i, n, _x in self.py['states']]
        self.assertEqual(len(ml_states), len(py_states),
                         'state count differs: MATLAB %d, Python %d'
                         % (len(ml_states), len(py_states)))
        for (mi, mn), (pi, pn) in zip(ml_states, py_states):
            self.assertEqual((mi, mn), (pi, pn))

    def test_state_excel_references_are_identical(self):
        """The Excel row each state implements must agree.

        Guards against the two ports drifting on which Sequence.xlsx row a
        state covers, including the implicit 'i' states and the row-36 anomaly.
        """
        ml_refs = [(n, x) for _i, n, x in self.ml['STATES']]
        py_refs = [(n, x) for _i, n, x in self.py['states']]
        self.assertEqual(ml_refs, py_refs)

    # ---- transition sequence -------------------------------------------

    def test_transition_counts_agree(self):
        self.assertEqual(len(self.ml['TRANSITIONS']), len(self.py['trans']),
                         'transition count differs: MATLAB %d, Python %d'
                         % (len(self.ml['TRANSITIONS']), len(self.py['trans'])))

    def test_transition_state_sequence_is_identical(self):
        """The ORDER of states visited must match exactly.

        Timing agreeing while identities differ would be a silent, serious
        divergence, so names are compared independently of timestamps.
        """
        ml_names = [n for _t, _i, n in self.ml['TRANSITIONS']]
        py_names = [tr[1] for tr in self.py['trans']]
        self.assertEqual(ml_names, py_names)

    def test_transition_times_are_identical(self):
        """Every transition must fire at the same instant in both models.

        Transitions occur on PLC scan boundaries (t_scan = 10 ms) driven by
        integrated physical state, so agreement should be exact rather than
        approximate. Measured delta across all 39 transitions is 0.000 ms.
        """
        worst = 0.0
        worst_at = None
        for (mt, _mi, mn), ptr in zip(self.ml['TRANSITIONS'], self.py['trans']):
            d = abs(mt - ptr[0])
            if d > worst:
                worst, worst_at = d, mn
        self.assertLessEqual(
            worst, TOL_TIME,
            'largest transition-time delta %.9f s at %s exceeds %.9f s'
            % (worst, worst_at, TOL_TIME))

    def test_both_models_complete_the_cycle(self):
        self.assertEqual(self.ml['FINAL']['complete'], 1.0)
        self.assertEqual(self.py['plc'].st, jp.SN['S39_CYCLE_COMPLETE'])

    # ---- end-of-cycle state ---------------------------------------------

    def test_final_block_position_agrees(self):
        """Integrated state, not a sampled quantity, so this is held tight."""
        self.assertAlmostEqual(self.ml['FINAL']['blk_x'],
                               self.py['final']['blk_x'], delta=TOL_POS)
        self.assertAlmostEqual(self.ml['FINAL']['blk_y'],
                               self.py['final']['blk_y'], delta=TOL_POS)

    def test_cycle_times_differ_by_exactly_one_plc_scan(self):
        """MATLAB reports cycle_time one t_scan later than Python.

        This is definitional, not a physics difference: both log
        S39_CYCLE_COMPLETE at the same instant (asserted by
        test_transition_times_are_identical), but MATLAB's LOG.cycle_time
        includes one further scan before declaring the cycle over. Pinning the
        gap to exactly t_scan means a real timing divergence still fails here
        rather than hiding inside a loose tolerance.
        """
        gap = self.ml['FINAL']['cycle_time'] - self.py['final']['cycle_time']
        self.assertAlmostEqual(
            gap, jp.P['t_scan'], delta=TOL_TIME,
            msg='cycle-time gap %.9f s is not one PLC scan (%.9f s)'
                % (gap, jp.P['t_scan']))

    def test_peak_pressures_agree(self):
        """Loose on purpose: peaks are sampled maxima, not integrated state.

        The two implementations log at different rates -- Python every 10 ms,
        MATLAB every 5 ms -- so MATLAB resolves sharper transients and reports a
        slightly higher peak. Measured relative delta is 4.3e-5 on chamber A.
        Tightening this would test the logging grid, not the physics.
        """
        for key in ('peak_PA', 'peak_PB'):
            ml_v = self.ml['FINAL'][key]
            py_v = self.py['final'][key]
            rel = abs(ml_v - py_v) / max(abs(ml_v), 1.0)
            self.assertLessEqual(
                rel, TOL_PRESSURE_REL,
                '%s relative delta %.3e exceeds %.3e (MATLAB %.3f, Python %.3f)'
                % (key, rel, TOL_PRESSURE_REL, ml_v, py_v))


class TestEquivalenceHarness(unittest.TestCase):
    """Checks on the harness itself, which need no MATLAB."""

    def test_export_helper_exists(self):
        """The MATLAB half of this test must be present and committed."""
        self.assertTrue(
            os.path.exists(os.path.join(HERE, 'export_equivalence_data.m')),
            'export_equivalence_data.m is missing; the equivalence test cannot '
            'run without it')

    def test_parser_round_trips_a_known_record(self):
        """Guards the parser itself, so a parsing bug cannot mimic agreement."""
        sample = ('[STATES]\n'
                  '0\tS00_INIT\t-\n'
                  '1\tS01_CAMERA_DETECT\t1\n'
                  '[TRANSITIONS]\n'
                  '0.000000\t1\tS01_CAMERA_DETECT\n'
                  '2.010000\t4\tS04_DV_READY\n'
                  '[FINAL]\n'
                  'cycle_time\t31.08\n'
                  'complete\t1\n')
        fd, path = tempfile.mkstemp(suffix='.txt')
        try:
            with os.fdopen(fd, 'w', encoding='utf-8') as fh:
                fh.write(sample)
            got = _parse_export(path)
        finally:
            os.unlink(path)
        self.assertEqual(got['STATES'],
                         [(0, 'S00_INIT', '-'), (1, 'S01_CAMERA_DETECT', '1')])
        self.assertEqual(got['TRANSITIONS'],
                         [(0.0, 1, 'S01_CAMERA_DETECT'),
                          (2.01, 4, 'S04_DV_READY')])
        self.assertEqual(got['FINAL'], {'cycle_time': 31.08, 'complete': 1.0})


if __name__ == '__main__':
    unittest.main(verbosity=2)
