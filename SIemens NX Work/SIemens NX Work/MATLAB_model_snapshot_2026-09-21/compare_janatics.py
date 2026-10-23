"""
compare_janatics.py
===================
Iteration 02 acceptance + before/after harness.

Runs the Iteration-01 reference (validate_physics) and the Janatics-integrated
model (janatics_physics) through the SAME 42-step Excel sequence and reports
the differences demanded by the iteration brief section 12.

Nothing here tunes either model.  Both are run as written.
"""
import math, os, sys, importlib

# Both models live beside this script; resolve relative to it so the harness
# runs from any working directory and on any platform.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

BASE = importlib.import_module('validate_physics')
JAN = importlib.import_module('janatics_physics')


def metrics(M, dt=5e-4, label=''):
    """Run a model and pull out every quantity the comparison table needs."""
    t, s, plc, trans, log, mj = M.run(dt=dt, verbose=False)
    IDX, P = M.IDX, M.P

    # --- peaks over the logged trajectory -------------------------------
    pkA = pkB = 0.0
    pk_v = [0.0] * M.NCYL
    pk_blk = 0.0
    pk_res = 0.0
    for tt, st in log:
        pk_res = max(pk_res, st[IDX['P_res']])
        for c in range(M.NCYL):
            pkA = max(pkA, st[IDX['PA_%d' % c]])
            pkB = max(pkB, st[IDX['PB_%d' % c]])
            pk_v[c] = max(pk_v[c], abs(st[IDX['v_%d' % c]]))
        pk_blk = max(pk_blk, math.hypot(st[IDX['bvx']], st[IDX['bvy']]))

    # --- per-state durations --------------------------------------------
    dur = {}
    for i, (tt, nm, xr) in enumerate(trans):
        end = trans[i + 1][0] if i + 1 < len(trans) else t
        dur[nm] = end - tt

    bx, by = s[IDX['bx']], s[IDX['by']]
    tgt = (M.WP['bin'][0] * M.S, M.WP['bin'][1] * M.S)

    air = s[IDX['m_air']] if 'm_air' in IDX else None

    return dict(label=label, t=t, state=M.STATES[plc.st][0],
                timeouts=plc.timeouts, ntrans=len(trans),
                pos=(bx, by), err=math.hypot(bx - tgt[0], by - tgt[1]),
                pkA=pkA, pkB=pkB, pk_res=pk_res, pk_v=pk_v, pk_blk=pk_blk,
                maxjump=mj, dur=dur, air=air, cylp=M.CYLP, P=P)


def bar(p):
    return p / 1e5


def pct(new, old):
    if old == 0:
        return float('nan')
    return (new - old) / old * 100.0


EXT_STATES = ['S06_A1_EXTEND', 'S13_A6_EXTEND', 'S19_S2A1_EXTEND',
              'S30_S3A1_EXTEND', 'S37_S3A2_EXTEND']
RET_STATES = ['S08_A1_RETRACT', 'S14_A6_RETRACT', 'S21_S2A1_RETRACT',
              'S32_S3A1_RETRACT', 'S38_S3A2_RETRACT']


def report(b, j):
    W = 78
    print('=' * W)
    print('ITERATION 02 - JANATICS INTEGRATION : BEFORE / AFTER')
    print('=' * W)

    print('\n[A] SEQUENCE INTEGRITY (must be identical - sequence was NOT edited)')
    print('  states executed        base %3d   janatics %3d   %s'
          % (b['ntrans'], j['ntrans'], 'OK' if b['ntrans'] == j['ntrans'] else 'FAIL'))
    print('  final state            base %s   janatics %s   %s'
          % (b['state'], j['state'],
             'OK' if b['state'] == j['state'] else 'FAIL'))
    print('  watchdog timeouts      base %s   janatics %s   %s'
          % (b['timeouts'] or 'none', j['timeouts'] or 'none',
             'OK' if not (b['timeouts'] or j['timeouts']) else 'FAIL'))

    print('\n[B] CYLINDER GEOMETRY')
    print('  %-6s  %-28s  %-28s' % ('cyl', 'Iteration 01', 'Janatics'))
    for c in range(len(b['cylp'])):
        cb, cj = b['cylp'][c], j['cylp'][c]
        print('  %-6s  stroke %6.1f mm (custom)   stroke %6.1f mm (std), trip %6.1f mm'
              % (cb['name'], cb['stroke'] * 1e3, cj['stroke'] * 1e3,
                 cj['x_trip'] * 1e3))

    print('\n[C] PNEUMATIC PARAMETERS')
    rows = [
        ('bore                 mm', b['P']['D_bore'] * 1e3, j['P']['D_bore'] * 1e3),
        ('rod                  mm', b['P']['d_rod'] * 1e3, j['P']['d_rod'] * 1e3),
        ('A_A                 mm2', b['P']['A_A'] * 1e6, j['P']['A_A'] * 1e6),
        ('A_B                 mm2', b['P']['A_B'] * 1e6, j['P']['A_B'] * 1e6),
        ('dead volume         cm3', b['P']['V_dead'] * 1e6, j['P']['V_dead'] * 1e6),
        ('supply conductance  e-9', b['P']['C_in'] * 1e9, j['P']['C_sup'] * 1e9),
        ('exhaust cond (ext)  e-9', b['P']['C_ex'] * 1e9, j['P']['C_ctrl_B'] * 1e9),
        ('exhaust cond (ret)  e-9', b['P']['C_ex'] * 1e9, j['P']['C_ctrl_A'] * 1e9),
        ('supply-line cond    e-9', b['P']['C_dv'] * 1e9, j['P']['C_dv'] * 1e9),
    ]
    for nm, ov, nv in rows:
        print('  %-24s %12.4f -> %12.4f   %+8.1f %%'
              % (nm, ov, nv, pct(nv, ov)))

    print('\n[D] OPERATING PRESSURE')
    print('  regulator set point       none (receiver direct) -> %.2f bar g'
          % (bar(j['P']['P_set'] - j['P']['P_atm'])))
    print('  peak receiver             %.2f -> %.2f bar abs'
          % (bar(b['pk_res']), bar(j['pk_res'])))
    print('  peak chamber A            %.2f -> %.2f bar abs   %+.1f %%'
          % (bar(b['pkA']), bar(j['pkA']), pct(j['pkA'], b['pkA'])))
    print('  peak chamber B            %.2f -> %.2f bar abs   %+.1f %%'
          % (bar(b['pkB']), bar(j['pkB']), pct(j['pkB'], b['pkB'])))

    print('\n[E] ACTUATOR FORCE at rated 6 bar g (theoretical, one side vented)')
    for lbl, M in (('Iteration 01', b), ('Janatics    ', j)):
        Pg = 6e5
        Fe = Pg * M['P']['A_A']
        Fr = Pg * M['P']['A_B']
        print('  %s  extend %6.1f N   retract %6.1f N' % (lbl, Fe, Fr))
    print('  Janatics catalogue A53/A54 Ø20/Ø8 @ 6 bar : 142 N (annulus side)')
    print('  model annulus x 0.90 (Janatics allowance)  : %.1f N'
          % (0.90 * 6e5 * j['P']['A_B']))

    print('\n[F] STROKE TIME (extend states, sensor-to-sensor, s)')
    tot_b = tot_j = 0.0
    for nm in EXT_STATES:
        ob, nj = b['dur'].get(nm, 0), j['dur'].get(nm, 0)
        tot_b += ob
        tot_j += nj
        print('  %-20s %7.3f -> %7.3f   %+8.1f %%' % (nm, ob, nj, pct(nj, ob)))
    print('  %-20s %7.3f -> %7.3f   %+8.1f %%'
          % ('TOTAL EXTEND', tot_b, tot_j, pct(tot_j, tot_b)))

    print('\n[G] RETRACT TIME (s)')
    rb = rj = 0.0
    for nm in RET_STATES:
        ob, nj = b['dur'].get(nm, 0), j['dur'].get(nm, 0)
        rb += ob
        rj += nj
        print('  %-20s %7.3f -> %7.3f   %+8.1f %%' % (nm, ob, nj, pct(nj, ob)))
    print('  %-20s %7.3f -> %7.3f   %+8.1f %%'
          % ('TOTAL RETRACT', rb, rj, pct(rj, rb)))

    print('\n[H] ACTUATOR SPEED (peak rod speed, m/s)')
    for c in range(len(b['cylp'])):
        print('  %-6s %7.3f -> %7.3f   %+8.1f %%'
              % (b['cylp'][c]['name'], b['pk_v'][c], j['pk_v'][c],
                 pct(j['pk_v'][c], b['pk_v'][c])))

    print('\n[I] AIR CONSUMPTION per cycle')
    if j['air'] is not None:
        rho0 = j['P']['rho0']
        NL = j['air'] / rho0 * 1000.0
        print('  Janatics model  %.5f kg  = %.2f normal litres' % (j['air'], NL))
        # geometric check
        geo = 0.0
        for c in j['cylp']:
            geo += (j['P']['A_A'] * c['x_trip'] + j['P']['A_B'] * c['stroke'])
        geoNL = geo * (j['P']['P_set'] / 101325.0) * 1000.0
        print('  swept-volume check (free air) %.2f NL  (model/geometry %.2f)'
              % (geoNL, NL / geoNL))
        print('  Iteration 01 did not instrument air consumption.')

    print('\n[J] VALVE FLOW HEADROOM')
    Cs = j['P']['C_sup']
    peak_mdot = Cs * j['P']['rho0'] * j['P']['P_set']
    lpm = peak_mdot / j['P']['rho0'] * 60000.0
    print('  peak supply demand through DS2+GR  %.0f l/min (free air, choked)' % lpm)
    print('  Janatics DS2 G1/8 rating            450 l/min')
    print('  Janatics FRCLM13 rating             500 l/min')

    print('\n[K] CYCLE TIME')
    print('  cycle                     %7.3f -> %7.3f s   %+.2f %%'
          % (b['t'], j['t'], pct(j['t'], b['t'])))
    op = b['P']['t_op_notice'] + b['P']['t_engrave'] + b['P']['t_op_confirm']
    print('  of which operator PLACEHOLDER %.1f s (unchanged, both models)' % op)
    print('  physics-derived portion   %7.3f -> %7.3f s   %+.2f %%'
          % (b['t'] - op, j['t'] - op, pct(j['t'] - op, b['t'] - op)))

    print('\n[L] WORKPIECE PLACEMENT')
    print('  final position   base (%.4f, %.4f)  janatics (%.4f, %.4f)'
          % (b['pos'][0], b['pos'][1], j['pos'][0], j['pos'][1]))
    print('  error vs bin target       %.2f mm -> %.2f mm'
          % (b['err'] * 1e3, j['err'] * 1e3))
    print('  max displacement / step   %.3e -> %.3e m' % (b['maxjump'], j['maxjump']))
    print('=' * W)


if __name__ == '__main__':
    print('running Iteration-01 baseline ...')
    b = metrics(BASE, label='base')
    print('running Janatics model ...')
    j = metrics(JAN, label='janatics')
    report(b, j)
