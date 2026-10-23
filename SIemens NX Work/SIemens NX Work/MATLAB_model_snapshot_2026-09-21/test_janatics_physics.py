"""
test_janatics_physics.py
========================
Unit tests for the pure functions in janatics_physics.py.

These cover the closed-form primitives only -- ISO 6358 orifice flow,
Hunt-Crossley contact, regularised Coulomb friction and support lookup.
They assert physical invariants (choking, sign reversal, no adhesion,
no force at rest) rather than regression values, so they stay valid if
the Janatics parameter set is re-sized.

Run:  python -m unittest test_janatics_physics -v
"""
import math
import unittest

import janatics_physics as jp

P = jp.P


class TestMdotOrifice(unittest.TestCase):
    """ISO 6358 compressible flow through a restriction."""

    def test_non_positive_conductance_gives_no_flow(self):
        self.assertEqual(jp.mdot_orifice(0.0, 7e5, 1e5), 0.0)
        self.assertEqual(jp.mdot_orifice(-1e-8, 7e5, 1e5), 0.0)

    def test_equal_pressures_give_no_flow(self):
        self.assertEqual(jp.mdot_orifice(1e-8, 7e5, 7e5), 0.0)

    def test_choked_flow_is_independent_of_downstream_pressure(self):
        """Below the critical ratio b, mdot depends on Pu only."""
        Pu = 1e6
        b = P['b_crit']
        deep = jp.mdot_orifice(1e-8, Pu, 0.1 * b * Pu)
        at_b = jp.mdot_orifice(1e-8, Pu, b * Pu)
        self.assertAlmostEqual(deep, at_b, places=12)

    def test_choked_flow_matches_closed_form(self):
        """f == 1 when choked, so mdot == C * rho0 * Pu."""
        C, Pu = 1e-8, 1e6
        expected = C * P['rho0'] * Pu
        self.assertAlmostEqual(
            jp.mdot_orifice(C, Pu, P['b_crit'] * Pu), expected, places=12)

    def test_choked_flow_is_linear_in_upstream_pressure(self):
        a = jp.mdot_orifice(1e-8, 7e5, 1e5)
        b = jp.mdot_orifice(1e-8, 3.5e5, 1e5)
        self.assertAlmostEqual(a, 2.0 * b, places=12)

    def test_reverse_flow_is_antisymmetric(self):
        fwd = jp.mdot_orifice(1e-8, 7e5, 1e5)
        rev = jp.mdot_orifice(1e-8, 1e5, 7e5)
        self.assertGreater(fwd, 0.0)
        self.assertAlmostEqual(rev, -fwd, places=12)

    def test_subsonic_flow_decreases_towards_zero_pressure_drop(self):
        """In the subsonic branch, mdot falls monotonically as r -> 1."""
        Pu = 1e6
        b = P['b_crit']
        ratios = [b + (1.0 - b) * k / 8.0 for k in range(1, 8)]
        flows = [jp.mdot_orifice(1e-8, Pu, r * Pu) for r in ratios]
        for lo, hi in zip(flows[1:], flows[:-1]):
            self.assertLess(lo, hi)
        self.assertGreater(flows[0], 0.0)

    def test_negligible_upstream_pressure_gives_no_flow(self):
        self.assertEqual(jp.mdot_orifice(1e-8, 0.5, 0.1), 0.0)


class TestContactHC(unittest.TestCase):
    """Hunt-Crossley normal contact: F = k*d + lam*d*d_dot, clamped at 0."""

    def test_no_force_without_penetration(self):
        self.assertEqual(jp.contact_hc(0.0, 1.0, 1e5, 1e3), 0.0)
        self.assertEqual(jp.contact_hc(-1e-3, 1.0, 1e5, 1e3), 0.0)

    def test_static_penetration_is_pure_spring(self):
        self.assertAlmostEqual(
            jp.contact_hc(1e-4, 0.0, 1e5, 1e3), 1e5 * 1e-4, places=12)

    def test_damping_is_proportional_to_penetration(self):
        """The Hunt-Crossley damping term is lam*pen*pen_rate, not lam*pen_rate.

        Isolating damping as F(pen, rate) - F(pen, 0) must scale linearly with
        penetration; a plain Kelvin-Voigt damper would make it constant.
        """
        k, lam, rate = 1e5, 1e3, 1.0
        for pen in (1e-6, 1e-5, 1e-4):
            damping = (jp.contact_hc(pen, rate, k, lam)
                       - jp.contact_hc(pen, 0.0, k, lam))
            self.assertAlmostEqual(damping, lam * pen * rate, places=12)

    def test_damping_vanishes_continuously_at_separation(self):
        """As penetration -> 0+, total force -> 0 even at high closing rate.

        Kelvin-Voigt would leave a lam*pen_rate force discontinuity here.
        """
        lam, rate = 1e3, 1.0
        self.assertLess(jp.contact_hc(1e-12, rate, 1e5, lam), 1e-6 * lam * rate)

    def test_no_adhesion_on_fast_rebound(self):
        """A large negative penetration rate must not pull the bodies together."""
        self.assertEqual(jp.contact_hc(1e-4, -1e6, 1e5, 1e3), 0.0)

    def test_force_is_never_negative(self):
        for rate in (-1e6, -1.0, 0.0, 1.0, 1e6):
            self.assertGreaterEqual(jp.contact_hc(1e-4, rate, 1e5, 1e3), 0.0)


class TestFriction2D(unittest.TestCase):
    """Regularised Coulomb friction, tanh-smoothed near zero velocity."""

    def test_no_force_at_rest(self):
        self.assertEqual(jp.friction_2d((0.0, 0.0), 10.0, 0.35), (0.0, 0.0))

    def test_opposes_sliding_direction(self):
        fx, fy = jp.friction_2d((1.0, 0.0), 10.0, 0.35)
        self.assertLess(fx, 0.0)
        self.assertAlmostEqual(fy, 0.0, places=12)

    def test_magnitude_saturates_at_coulomb_limit(self):
        """tanh -> 1 well above v_creep, so |F| -> mu_k * N."""
        N, mu = 10.0, 0.35
        fx, fy = jp.friction_2d((1.0, 0.0), N, mu)
        self.assertAlmostEqual(math.hypot(fx, fy), mu * N, places=6)

    def test_magnitude_never_exceeds_coulomb_limit(self):
        N, mu = 10.0, 0.35
        for v in (1e-6, 1e-3, P['v_creep'], 0.1, 5.0):
            fx, fy = jp.friction_2d((v, 0.0), N, mu)
            self.assertLessEqual(math.hypot(fx, fy), mu * N + 1e-12)

    def test_is_antiparallel_to_velocity(self):
        v = (0.6, -0.8)
        fx, fy = jp.friction_2d(v, 10.0, 0.35)
        mag = math.hypot(fx, fy)
        self.assertAlmostEqual(fx / mag, -v[0], places=9)
        self.assertAlmostEqual(fy / mag, -v[1], places=9)

    def test_zero_normal_load_gives_no_force(self):
        self.assertEqual(jp.friction_2d((1.0, 0.0), 0.0, 0.35), (0.0, 0.0))


class TestSupportOf(unittest.TestCase):
    """Support-surface lookup over the drawing-unit regions."""

    def test_far_outside_falls_back_to_plate(self):
        self.assertEqual(jp.support_of(-99.0, -99.0), 'plate')

    def test_every_region_resolves_to_its_own_name(self):
        S = P['SCALE']
        for name, x0, x1, y0, y1 in jp.REGIONS:
            cx = 0.5 * (x0 + x1) * S
            cy = 0.5 * (y0 + y1) * S
            self.assertEqual(jp.support_of(cx, cy), name)

    def test_result_is_always_a_known_region_or_plate(self):
        valid = {r[0] for r in jp.REGIONS} | {'plate'}
        for i in range(-5, 25):
            for k in range(-5, 20):
                self.assertIn(jp.support_of(i * 0.1, k * 0.1), valid)


if __name__ == '__main__':
    unittest.main(verbosity=2)
