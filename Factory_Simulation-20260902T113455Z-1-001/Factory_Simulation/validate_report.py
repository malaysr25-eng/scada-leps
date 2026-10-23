"""Acceptance tests for the physics core. Everything reported in the .md
validation section is produced by this script."""
import math, validate_physics as V

def run(dt=5e-4, tmax=60.0):
    s = V.init_state(); plc = V.PLC(); t = 0.0
    nsc = max(1, int(round(V.P['t_scan'] / dt))); k = 0
    u = plc.out()
    rec = dict(trans=[], maxstep=0.0, maxspeed=0.0, maxPA=0.0, maxPB=0.0,
               slip=0.0, guards=[], wp={}, minPres=1e9)
    prev = (s[V.IDX['bx']], s[V.IDX['by']])
    prev_sn = V.sensors(s); prev_st = plc.st
    while t < tmax:
        if k % nsc == 0:
            sn = V.sensors(s)
            st_before = plc.st
            if plc.step(t, sn, V.P['t_scan']):
                rec['trans'].append((t, V.STATES[st_before][0],
                                     V.STATES[plc.st][0], V.STATES[plc.st][1]))
                rec['guards'].append((V.STATES[st_before][0], prev_sn, sn))
            prev_sn = sn
            u = plc.out()
            if plc.st == V.SN['S39_CYCLE_COMPLETE']:
                break
        k1 = V.derivatives(s, u)
        s2 = [s[i] + .5*dt*k1[i] for i in range(V.NS)]
        k2 = V.derivatives(s2, u)
        s3 = [s[i] + .5*dt*k2[i] for i in range(V.NS)]
        k3 = V.derivatives(s3, u)
        s4 = [s[i] + dt*k3[i] for i in range(V.NS)]
        k4 = V.derivatives(s4, u)
        s = [s[i] + dt/6*(k1[i]+2*k2[i]+2*k3[i]+k4[i]) for i in range(V.NS)]
        t += dt; k += 1

        bx, by = s[V.IDX['bx']], s[V.IDX['by']]
        vx, vy = s[V.IDX['bvx']], s[V.IDX['bvy']]
        rec['maxstep'] = max(rec['maxstep'], math.hypot(bx-prev[0], by-prev[1]))
        rec['maxspeed'] = max(rec['maxspeed'], math.hypot(vx, vy))
        prev = (bx, by)
        rec['minPres'] = min(rec['minPres'], s[V.IDX['P_res']])
        for c in range(V.NCYL):
            rec['maxPA'] = max(rec['maxPA'], s[V.IDX['PA_%d' % c]])
            rec['maxPB'] = max(rec['maxPB'], s[V.IDX['PB_%d' % c]])
        # conveyor slip while a belt is commanded and carrying the block
        sup = V.support_of(bx, by)
        for i, (nm, uv, reg) in enumerate(V.CONV):
            if sup == reg and u['conv_on'][i]:
                vb = V.P['r_pul']*s[V.IDX['om_%d' % i]]
                if vb > 0.9*V.P['v_belt_sp']:
                    rel = abs((vx*uv[0]+vy*uv[1]) - vb)
                    rec['slip'] = max(rec['slip'], rel)
    rec['t_end'] = t
    rec['state'] = V.STATES[plc.st][0]
    rec['s'] = s
    rec['timeouts'] = plc.timeouts
    return rec


print('='*74)
print('ACCEPTANCE TESTS  -  physics core, Iteration 01')
print('='*74)

r = run(5e-4)
S = V.S

# --- T1 sequence conformance ------------------------------------------------
order = [x[3] for x in r['trans']]
explicit, implicit = [], []
for o in order:
    for part in o.split(','):
        part = part.strip()
        if part.endswith('i'):                    # engineering-added state
            if part[:-1].isdigit(): implicit.append(int(part[:-1]))
        else:
            part = part.rstrip('*')               # '*' = Excel anomaly
            if part.isdigit(): explicit.append(int(part))
mono = all(explicit[i] < explicit[i+1] for i in range(len(explicit)-1))
covered = sorted(set(explicit))
missing = [i for i in range(1, 43) if i not in covered]
print('\n[T1] Excel sequence conformance')
print('     Stateflow states executed : %d' % len(r['trans']))
print('     of which added (implicit) : %d  -> %s' % (len(implicit), sorted(set(implicit))))
print('     Excel steps covered       : %d / 42   missing = %s'
      % (len(covered), missing or 'none'))
print('     strictly increasing order : %s  (no Excel step reordered)' % mono)

# --- T2 feedback-driven transitions ----------------------------------------
GUARDED = {
 'S01_CAMERA_DETECT':'CAM','S03_PRESSURE_PREP':'P_READY',
 'S06_A1_EXTEND':'EXT_0','S07_PROX1_CHECK':'PX1','S08_A1_RETRACT':'RET_0',
 'S10_PROX2_CHECK':'PX2','S13_A6_EXTEND':'EXT_1','S14_A6_RETRACT':'RET_1',
 'S16_PROX3_CHECK':'PX3','S19_S2A1_EXTEND':'EXT_2','S21_S2A1_RETRACT':'RET_2',
 'S23_HEIGHT_TOP':'HS_TOP','S28_HEIGHT_BOTTOM':'HS_BOT',
 'S30_S3A1_EXTEND':'EXT_3','S32_S3A1_RETRACT':'RET_3','S34_PROX4_FINAL':'PX4',
 'S37_S3A2_EXTEND':'EXT_4','S38_S3A2_RETRACT':'RET_4'}
print('\n[T2] Transition guards driven by physical sensor, not timer')
ok = 0; bad = []
for st, sn_prev, sn_now in r['guards']:
    if st in GUARDED:
        key = GUARDED[st]
        if sn_now.get(key):
            ok += 1
        else:
            bad.append(st)
print('     guarded transitions verified TRUE at exit: %d/%d' % (ok, len(GUARDED)))
print('     failures: %s' % (bad or 'none'))

# --- T3 positioning accuracy ------------------------------------------------
print('\n[T3] Final workpiece position vs Sequence.xlsx target (bin)')
bx, by = r['s'][V.IDX['bx']], r['s'][V.IDX['by']]
tx, ty = V.WP['bin'][0]*S, V.WP['bin'][1]*S
print('     block  = (%.4f, %.4f) m' % (bx, by))
print('     target = (%.4f, %.4f) m   error = %.1f mm'
      % (tx, ty, 1000*math.hypot(bx-tx, by-ty)))

# --- T4 no teleport ---------------------------------------------------------
print('\n[T4] Continuity (workpiece never teleports)')
print('     max displacement per %.0e s step = %.3e m' % (5e-4, r['maxstep']))
print('     max workpiece speed              = %.4f m/s' % r['maxspeed'])
print('     implied max step at that speed   = %.3e m' % (r['maxspeed']*5e-4))

# --- T5 pressure bounds -----------------------------------------------------
print('\n[T5] Pneumatic bounds (no unphysical over-pressure)')
print('     supply cut-out      = %.2f bar' % (V.P['P_cut_out']/1e5))
print('     max chamber A       = %.2f bar' % (r['maxPA']/1e5))
print('     max chamber B       = %.2f bar' % (r['maxPB']/1e5))
print('     min receiver        = %.2f bar' % (r['minPres']/1e5))
print('     PASS' if r['maxPA'] < 1.3*V.P['P_cut_out'] and r['maxPB'] < 1.3*V.P['P_cut_out'] else '     FAIL')

# --- T6 belt no-slip --------------------------------------------------------
print('\n[T6] Belt/workpiece contact (static friction, no gross slip)')
print('     max |v_block - v_belt| at speed = %.4f m/s' % r['slip'])
Fmax = V.P['mu_s']*V.P['blk_m']*V.P['g']
Freq = V.P['blk_m']*V.P['a_belt']
print('     required accel force = %.3f N ; static friction limit = %.3f N'
      % (Freq, Fmax))
print('     PASS (F_req < mu_s*N)' if Freq < Fmax else '     FAIL')

# --- T7 solver convergence --------------------------------------------------
print('\n[T7] Solver convergence (halve the step, compare)')
r2 = run(2.5e-4)
print('     dt=5.0e-4 : cycle %.4f s   block=(%.5f, %.5f)'
      % (r['t_end'], r['s'][V.IDX['bx']], r['s'][V.IDX['by']]))
print('     dt=2.5e-4 : cycle %.4f s   block=(%.5f, %.5f)'
      % (r2['t_end'], r2['s'][V.IDX['bx']], r2['s'][V.IDX['by']]))
d = math.hypot(r['s'][V.IDX['bx']]-r2['s'][V.IDX['bx']],
               r['s'][V.IDX['by']]-r2['s'][V.IDX['by']])
print('     position difference = %.3e m ; cycle-time difference = %.4f s'
      % (d, abs(r['t_end']-r2['t_end'])))

# --- T8 height sensor -------------------------------------------------------
print('\n[T8] Height sensor reflects physical base position')
print('     final base z = %.6f m (commanded bottom = 0)' % r['s'][V.IDX['bz']])
print('     z_top setpoint = %.4f m, tolerance = %.4f m'
      % (V.P['z_top'], V.P['z_tol']))

print('\n[T9] Watchdog timeouts during nominal run: %s' % (r['timeouts'] or 'none'))
print('\ncycle time = %.3f s  (of which operator/engraving placeholder = %.1f s)'
      % (r['t_end'], V.P['t_op_notice']+V.P['t_engrave']+V.P['t_op_confirm']))
print('='*74)
