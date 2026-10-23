"""
test_bypass_route.py
====================
The SV11 bypass route in the Python reference port, P['engrave_selected'] False.

The maintainer, 2026-09-11, verbatim:
    "CYLINDER b FIRES WHEN ENGRAVING IS DONE AND IT PUSHES BLOCK TO BELT 3,
     SV11 FIRES WHEN ENGRAVING IS SKIPPED"

The MATLAB twin of this file is tests/BypassRouteTest.m.  Like it, this pins
no numbers - no bypass cycle has been recorded on the real cell - and asserts
behaviour: the route, and that the block still reaches the bin.

The route is module state in janatics_physics (P and STOPS), so the class
restores the engraved route when it finishes, whatever happens, and the last
test checks that it did.  test_model_equivalence runs after this file and
needs the engraved route.
"""
import math
import unittest

import janatics_physics as jp


class BypassRoute(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        jp.set_route(False)
        try:
            (cls.t, cls.s, cls.plc, cls.trans,
             cls.log, cls.mj) = jp.run(tmax=90.0, dt=5e-4, verbose=False)
        finally:
            jp.set_route(True)

    def test_cycle_completes(self):
        self.assertEqual(self.plc.st, jp.SN['S39_CYCLE_COMPLETE'])

    def test_no_watchdog_timeout(self):
        self.assertEqual(self.plc.timeouts, [])

    def test_route_is_the_bypass_in_order(self):
        """S01..S16, then S40..S43, then back into S33..S39."""
        names = [n for _t, n, _x in self.trans]
        expected = ([n for n, _ in jp.STATES[1:jp.SN['S16_PROX3_CHECK'] + 1]]
                    + ['S40_BYP_CONV2_STOP', 'S41_BYP_DV_SEL',
                       'S42_BYP_SV11_EXTEND', 'S43_BYP_SV11_RETRACT']
                    + [n for n, _ in jp.STATES[jp.SN['S33_CONV3_START']:
                                               jp.SN['S39_CYCLE_COMPLETE'] + 1]])
        self.assertEqual(names, expected)

    def test_workpiece_reaches_the_bin(self):
        bx, by = self.s[jp.IDX['bx']], self.s[jp.IDX['by']]
        tx, ty = jp.WP['bin'][0] * jp.S, jp.WP['bin'][1] * jp.S
        self.assertLess(math.hypot(bx - tx, by - ty), 5e-3)

    def test_engraved_route_is_restored(self):
        self.assertTrue(jp.P['engrave_selected'])
        names = [st_[0] for st_ in jp.STOPS]
        self.assertIn('C2_end_stop', names)
        self.assertNotIn('C2_byp_stop', names)


if __name__ == '__main__':
    unittest.main()
