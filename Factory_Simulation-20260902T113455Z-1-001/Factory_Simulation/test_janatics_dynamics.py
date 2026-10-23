"""
test_janatics_dynamics.py
=========================
Unit tests for the parts of janatics_physics.py that carry the simulation:
derivatives(), sensors(), the PLC state machine, and the sequencing they
produce together.

test_janatics_physics.py covers the closed-form primitives -- roughly 30 lines
of an 811-line module. These are the layers above: the state vector, the
constitutive coupling between them, and the feedback loop that makes the model
a digital twin rather than a scripted animation.

Assertions are structural and physical (state-vector shape, finiteness,
determinism, conservation direction, hysteresis, sequence monotonicity) rather
than recorded values, so re-sizing the Janatics parameter set does not turn
them into false failures.

The sequencing tests run the full cycle once and share it across the class,
which takes a few seconds. Numerical agreement with the MATLAB implementation
is a separate concern, covered by test_model_equivalence.py.

Run:  python -m unittest test_janatics_dynamics -v
"""
import math
import unittest

import janatics_physics as jp

P = jp.P


def _quiescent():
    """Initial state and the command a freshly constructed PLC emits."""
    return jp.init_state(), jp.PLC().out()


class TestStateVector(unittest.TestCase):
    """The state vector and its index map must stay mutually consistent."""

    def test_init_state_has_declared_length(self):
        self.assertEqual(len(jp.init_state()), jp.NS)

    def test_index_map_covers_the_state_vector(self):
        """Every index in IDX must be addressable, and none may collide."""
        idx = sorted(jp.IDX.values())
        self.assertEqual(len(idx), len(set(idx)), 'duplicate index in IDX')
        self.assertEqual(idx[0], 0)
        self.assertLess(idx[-1], jp.NS)

    def test_init_state_is_entirely_finite(self):
        self.assertTrue(all(math.isfinite(v) for v in jp.init_state()))

    def test_chambers_and_branches_start_at_atmosphere(self):
        s = jp.init_state()
        for k in range(4):
            self.assertAlmostEqual(s[jp.IDX['P_br%d' % k]], P['P_atm'])
        for c in range(jp.NCYL):
            self.assertAlmostEqual(s[jp.IDX['PA_%d' % c]], P['P_atm'])
            self.assertAlmostEqual(s[jp.IDX['PB_%d' % c]], P['P_atm'])

    def test_receiver_starts_precharged(self):
        """The receiver must start charged or the cycle cannot begin."""
        s = jp.init_state()
        self.assertAlmostEqual(s[jp.IDX['P_res']], P['P_res_0'])
        self.assertGreater(s[jp.IDX['P_res']], P['P_atm'])

    def test_workpiece_starts_in_the_camera_field_of_view(self):
        """Step 1 is a camera detect; if the block starts elsewhere it stalls."""
        self.assertTrue(jp.sensors(jp.init_state())['CAM'])


class TestDerivatives(unittest.TestCase):
    """The right-hand side of the ODE system."""

    def test_returns_one_derivative_per_state(self):
        s, u = _quiescent()
        self.assertEqual(len(jp.derivatives(s, u)), jp.NS)

    def test_all_derivatives_finite_at_initial_condition(self):
        s, u = _quiescent()
        self.assertTrue(all(math.isfinite(v) for v in jp.derivatives(s, u)))

    def test_is_deterministic(self):
        """Same state and command must give the same derivative.

        RK4 evaluates the field four times per step; a hidden dependence on
        call order would corrupt the integration silently.
        """
        s, u = _quiescent()
        self.assertEqual(jp.derivatives(s, u), jp.derivatives(s, u))

    def test_does_not_mutate_its_arguments(self):
        """derivatives() must be pure; the integrator reuses these buffers."""
        s, u = _quiescent()
        before = list(s)
        jp.derivatives(s, u)
        self.assertEqual(s, before)

    def test_workpiece_is_at_rest_when_nothing_is_commanded(self):
        """No spurious drift: a supported block with no actuation must not move.

        Catches sign errors in gravity or the support reaction, which would
        otherwise show up only as a slow positional drift over a full cycle.
        """
        s, u = _quiescent()
        d = jp.derivatives(s, u)
        for key in ('bx', 'by', 'bvx', 'bvy'):
            self.assertAlmostEqual(d[jp.IDX[key]], 0.0, places=9)

    def test_receiver_is_static_with_the_pump_off(self):
        s, u = _quiescent()
        u = dict(u, pump_on=False)
        self.assertAlmostEqual(jp.derivatives(s, u)[jp.IDX['P_res']], 0.0,
                               places=9)

    def test_receiver_charges_with_the_pump_on(self):
        s, u = _quiescent()
        u = dict(u, pump_on=True)
        self.assertGreater(jp.derivatives(s, u)[jp.IDX['P_res']], 0.0)

    def test_receiver_does_not_charge_past_the_relief_setting(self):
        """The safety relief must bleed a receiver driven above its set point."""
        s, u = _quiescent()
        s[jp.IDX['P_res']] = P['P_relief'] * 1.05
        u = dict(u, pump_on=False)
        self.assertLess(jp.derivatives(s, u)[jp.IDX['P_res']], 0.0)

    def test_no_chamber_activity_without_a_valve_command(self):
        """With every valve closed, no cylinder chamber may charge."""
        s, u = _quiescent()
        d = jp.derivatives(s, u)
        for c in range(jp.NCYL):
            self.assertAlmostEqual(d[jp.IDX['PA_%d' % c]], 0.0, places=6)
            self.assertAlmostEqual(d[jp.IDX['PB_%d' % c]], 0.0, places=6)

    def test_survives_a_degenerate_state_without_producing_nan(self):
        """Robustness at the boundary the solver can transiently reach.

        Zero absolute pressure is unphysical but an overshooting step can
        approach it; the field must stay finite rather than emit NaN and
        poison the whole state vector.
        """
        s, u = _quiescent()
        for c in range(jp.NCYL):
            s[jp.IDX['PA_%d' % c]] = 0.0
            s[jp.IDX['PB_%d' % c]] = 0.0
        s[jp.IDX['P_res']] = 0.0
        self.assertTrue(all(math.isfinite(v) for v in jp.derivatives(s, u)))


class TestSensors(unittest.TestCase):
    """sensors() must be a pure function of physical state."""

    EXPECTED_KEYS = {'CAM', 'P_res', 'P_READY', 'HS_TOP', 'HS_BOT',
                     'PX1', 'PX2', 'PX3', 'PX4'}

    def test_exposes_the_expected_signals(self):
        sn = jp.sensors(jp.init_state())
        self.assertTrue(self.EXPECTED_KEYS.issubset(set(sn)))
        for c in range(jp.NCYL):
            self.assertIn('EXT_%d' % c, sn)
            self.assertIn('RET_%d' % c, sn)

    def test_is_deterministic(self):
        s = jp.init_state()
        self.assertEqual(jp.sensors(s), jp.sensors(s))

    def test_does_not_mutate_the_state(self):
        s = jp.init_state()
        before = list(s)
        jp.sensors(s)
        self.assertEqual(s, before)

    def test_receiver_reading_tracks_the_state_vector(self):
        """The pressure switch must read actual state, not a stored setpoint."""
        s = jp.init_state()
        s[jp.IDX['P_res']] = 7.3e5
        self.assertAlmostEqual(jp.sensors(s)['P_res'], 7.3e5)

    def test_camera_clears_once_the_block_leaves_its_field(self):
        s = jp.init_state()
        s[jp.IDX['bx']] += 10.0 * P['prox_rng']
        self.assertFalse(jp.sensors(s)['CAM'])

    def test_proximity_sensors_are_local(self):
        """Each PX must respond to its own waypoint and not to a distant block.

        A sensor that latches globally would let the sequence advance without
        the workpiece actually arriving -- the exact failure the physical
        guards exist to prevent.
        """
        s = jp.init_state()
        s[jp.IDX['bx']] = 1e3
        s[jp.IDX['by']] = 1e3
        sn = jp.sensors(s)
        for k in ('PX1', 'PX2', 'PX3', 'PX4'):
            self.assertFalse(sn[k], '%s true with the block 1 km away' % k)

    def test_each_proximity_sensor_fires_at_its_own_waypoint(self):
        for name, (px, py) in jp.PROX.items():
            s = jp.init_state()
            s[jp.IDX['bx']] = px * jp.S
            s[jp.IDX['by']] = py * jp.S
            self.assertTrue(jp.sensors(s)[name],
                            '%s did not fire at its own waypoint' % name)


class TestPLC(unittest.TestCase):
    """The state machine, exercised directly rather than through a full run."""

    def test_starts_in_the_initial_state(self):
        self.assertEqual(jp.PLC().st, jp.SN['S00_INIT'])

    def test_output_carries_every_actuator_channel(self):
        u = jp.PLC().out()
        for key in ('pump_on', 'dv_sel', 'sol', 'conv_on', 'base_cmd'):
            self.assertIn(key, u)
        # The command carries the machine's COILS, not one entry per
        # actuator: 11 actuators, 13 coils, because CYL_A and CYL_B are
        # double-solenoid. NCYL would pass here for the wrong reason.
        self.assertEqual(len(u['sol']), jp.NSOL)
        self.assertEqual(len(u['conv_on']), jp.NCONV)

    def test_no_watchdog_timeouts_before_stepping(self):
        self.assertEqual(jp.PLC().timeouts, [])

    def _stepped(self, pump_enable, pump, p_res):
        plc = jp.PLC()
        plc.pump_enable = pump_enable
        plc.pump = pump
        sn = dict(jp.sensors(jp.init_state()), P_res=p_res)
        plc.step(0.0, sn, P['t_scan'])
        return plc.pump

    def test_compressor_stops_at_cut_out(self):
        self.assertFalse(self._stepped(True, True, P['P_cut_out'] + 1.0))

    def test_compressor_starts_at_cut_in_when_enabled(self):
        self.assertTrue(self._stepped(True, False, P['P_cut_in'] - 1.0))

    def test_compressor_stays_off_when_not_enabled(self):
        """Sequence control must override the pressure switch, not race it."""
        self.assertFalse(self._stepped(False, False, P['P_cut_in'] - 1.0))

    def test_compressor_holds_state_inside_the_hysteresis_band(self):
        """Between cut-in and cut-out the pump must latch, not chatter."""
        mid = 0.5 * (P['P_cut_in'] + P['P_cut_out'])
        self.assertTrue(self._stepped(True, True, mid))
        self.assertFalse(self._stepped(True, False, mid))

    def test_cut_in_is_below_cut_out(self):
        """An inverted band would make the hysteresis meaningless."""
        self.assertLess(P['P_cut_in'], P['P_cut_out'])
        self.assertLess(P['P_cut_out'], P['P_relief'])

    def test_relief_sits_just_above_cut_out(self):
        """The safety relief must be a modest margin above cut-out.

        This is asserted independently because the run-time pressure bound in
        TestSequencing scales with P_relief and therefore cannot catch a
        relief set far too high -- such a relief would simply never lift, and
        the bound would move with it. Pinning the ratio here keeps that bound
        meaningful.
        """
        self.assertGreater(P['P_relief'], P['P_cut_out'])
        self.assertLess(P['P_relief'], 1.5 * P['P_cut_out'],
                        'relief %.0f Pa is more than 1.5x cut-out %.0f Pa; the '
                        'pressure bound in TestSequencing becomes vacuous'
                        % (P['P_relief'], P['P_cut_out']))


class TestStateTable(unittest.TestCase):
    """Static properties of the state table, no simulation required."""

    def test_state_names_are_unique(self):
        names = [n for n, _x in jp.STATES]
        self.assertEqual(len(names), len(set(names)))

    def test_name_index_map_agrees_with_the_table(self):
        for i, (n, _x) in enumerate(jp.STATES):
            self.assertEqual(jp.SN[n], i)

    def test_every_excel_step_is_implemented(self):
        """All 42 rows of Sequence.xlsx must be covered by some state."""
        refs = set()
        for _n, x in jp.STATES:
            for tok in str(x).replace('i', '').replace('*', '').split(','):
                tok = tok.strip()
                if tok.isdigit():
                    refs.add(int(tok))
        self.assertEqual(set(range(1, 43)) - refs, set(),
                         'Excel steps not implemented by any state')


class TestSequencing(unittest.TestCase):
    """One full cycle, shared across the class."""

    @classmethod
    def setUpClass(cls):
        cls.t, cls.s, cls.plc, cls.trans, cls.log, cls.mj = jp.run(
            tmax=90.0, dt=5e-4, verbose=False)

    def test_cycle_completes(self):
        self.assertEqual(self.plc.st, jp.SN['S39_CYCLE_COMPLETE'])

    def test_no_watchdog_timeout_occurs(self):
        """Every state must be left via its guard, not its timeout."""
        self.assertEqual(self.plc.timeouts, [])

    def test_state_index_never_decreases(self):
        """The sequence is strictly forward; no state may be revisited.

        A backward step would mean a guard chattered and the machine re-entered
        a state it had already completed.
        """
        idx = [jp.SN[tr[1]] for tr in self.trans]
        for prev, nxt in zip(idx, idx[1:]):
            self.assertLess(prev, nxt,
                            'state index went %d -> %d' % (prev, nxt))

    def test_transition_times_are_non_decreasing(self):
        ts = [tr[0] for tr in self.trans]
        for a, b in zip(ts, ts[1:]):
            self.assertLessEqual(a, b)

    def test_workpiece_reaches_the_bin(self):
        bx = self.s[jp.IDX['bx']]
        by = self.s[jp.IDX['by']]
        tx, ty = jp.WP['bin'][0] * jp.S, jp.WP['bin'][1] * jp.S
        self.assertLess(math.hypot(bx - tx, by - ty), 5e-3,
                        'workpiece did not reach the bin within 5 mm')

    def test_workpiece_never_teleports(self):
        """Continuity: displacement per logged sample must stay bounded."""
        worst = 0.0
        prev = None
        for _tt, st in self.log:
            cur = (st[jp.IDX['bx']], st[jp.IDX['by']])
            if prev is not None:
                worst = max(worst, math.hypot(cur[0] - prev[0],
                                              cur[1] - prev[1]))
            prev = cur
        self.assertLess(worst, 0.05,
                        'max displacement per sample %.4f m is discontinuous'
                        % worst)

    def test_pressures_stay_physical_throughout(self):
        """No chamber may go sub-atmospheric-negative or exceed the relief."""
        ceiling = P['P_relief'] * 1.05
        for _tt, st in self.log:
            self.assertGreaterEqual(st[jp.IDX['P_res']], 0.0)
            self.assertLessEqual(st[jp.IDX['P_res']], ceiling)
            for c in range(jp.NCYL):
                for tag in ('PA_%d', 'PB_%d'):
                    v = st[jp.IDX[tag % c]]
                    self.assertGreaterEqual(v, 0.0)
                    self.assertLessEqual(v, ceiling)

    def test_every_state_is_entered_exactly_once(self):
        names = [tr[1] for tr in self.trans]
        self.assertEqual(len(names), len(set(names)))

    def test_all_logged_states_stay_finite(self):
        for _tt, st in self.log:
            self.assertTrue(all(math.isfinite(v) for v in st))


if __name__ == '__main__':
    unittest.main(verbosity=2)
