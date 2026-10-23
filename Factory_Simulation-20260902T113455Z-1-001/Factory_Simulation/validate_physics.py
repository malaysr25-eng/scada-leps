"""
validate_physics.py
===================
Reference port (Python) of the physics core + PLC state machine that is
implemented in MATLAB as FactoryParams.m / factory_derivatives.m / factory_plc.m.

PURPOSE: this file exists ONLY to numerically validate the governing equations,
parameter sizing, contact model and feedback-driven sequencing independently of
MATLAB.  Equation-for-equation identical to the MATLAB implementation.

This is the Iteration-01 reference, kept as the [ASM]-sized baseline that
janatics_physics.py is compared against.  Where MATLAB is installed, prefer
running it directly over inferring its behaviour from this port.

Units: strict SI (m, kg, s, N, Pa, rad, K).
"""
import math

# ----------------------------------------------------------------------------
# 0. TAGS:  [SRC]=from Sequence.xlsx  [REF]=from reference MATLAB layout script
#           [ASM]=engineering assumption  [CAL]=calculated  [EST]=estimate
#           [PLH]=placeholder
# ----------------------------------------------------------------------------

P = {}

# --- 0.1 Environment -------------------------------------------------------
P['g']       = 9.80665      # [ASM] gravity                          m/s^2
P['T_air']   = 293.15       # [ASM] isothermal air temperature       K
P['R_air']   = 287.05       # [ASM] specific gas constant, dry air   J/(kg K)
P['n_poly']  = 1.30         # [ASM] polytropic index, chamber        -
P['P_atm']   = 101325.0     # [ASM] ambient pressure                 Pa
P['rho0']    = 1.185        # [ASM] ISO 6358 reference density       kg/m^3
P['b_crit']  = 0.40         # [ASM] ISO 6358 critical pressure ratio -

# --- 0.2 Geometry scale ----------------------------------------------------
# The reference script labels axes "m" but draws a 17 x 13 cell with a 0.6
# "m" block.  Treated as a schematic: 1 drawing unit = SCALE metres.
P['SCALE']   = 0.10         # [ASM] drawing unit -> metre            m/unit
S = P['SCALE']

# --- 0.3 Workpiece ---------------------------------------------------------
P['blk_a']   = 0.6 * S      # [REF] cube edge                        m
P['blk_rho'] = 2700.0       # [ASM] Al 6061                          kg/m^3
P['blk_m']   = P['blk_rho'] * P['blk_a']**3     # [CAL]              kg
P['mu_s']    = 0.40         # [ASM] static friction, block/surface   -
P['mu_k']    = 0.35         # [ASM] kinetic friction                 -
P['v_creep'] = 2.0e-3       # [ASM] friction regularisation velocity m/s

# --- 0.4 Pneumatic supply --------------------------------------------------
P['V_res']    = 5.0e-3      # [ASM] receiver volume                  m^3
P['P_cut_in'] = 6.0e5       # [ASM] compressor cut-in  (abs)         Pa
P['P_cut_out']= 8.0e5       # [ASM] compressor cut-out (abs)         Pa
P['mdot_pump']= 3.0e-3      # [ASM] compressor delivery              kg/s
P['P_ready']  = 6.5e5       # [ASM] receiver ready threshold         Pa
P['P_br_rdy'] = 5.5e5       # [ASM] branch/chamber charged threshold Pa
P['P_res_0']  = 5.5e5       # [ASM] receiver initial charge          Pa
P['P_relief'] = 9.0e5       # [ASM] receiver safety relief set point Pa
P['C_relief'] = 5.0e-8      # [ASM] relief valve conductance         m^3/(s Pa)
P['C_dv']     = 6.0e-9      # [ASM] distribution valve conductance   m^3/(s Pa)
P['tau_dv']   = 0.030       # [ASM] distribution valve response      s
P['V_branch'] = 1.0e-4      # [ASM] branch manifold + tubing volume  m^3

# --- 0.5 Cylinders ---------------------------------------------------------
# Bore / rod common to all five; strokes come from the reference layout.
P['D_bore']  = 0.020        # [ASM] bore                             m
P['d_rod']   = 0.008        # [ASM] rod diameter                     m
P['A_A']     = math.pi * P['D_bore']**2 / 4.0                    # [CAL] m^2
P['A_B']     = math.pi * (P['D_bore']**2 - P['d_rod']**2) / 4.0  # [CAL] m^2
P['m_pist']  = 0.120        # [ASM] piston + rod mass                kg
P['V_dead']  = 1.0e-5       # [ASM] dead vol (port+tube+cushion)     m^3
P['C_in']    = 2.5e-10      # [CAL] inlet conductance, METER-IN, sized
                            #       from mdot=(P_A/RT)A_A*v for
                            #       v_ext ~ 0.2 m/s                  m^3/(s Pa)
P['C_ex']    = 1.5e-8       # [CAL] exhaust conductance, sized for
                            #       ~50 ms chamber blow-down:
                            #       C = V_B/(t_bd*R*T)               m^3/(s Pa)
P['tau_sv']  = 0.020        # [ASM] station valve spool response     s
P['F_coul']  = 5.0          # [ASM] cylinder Coulomb friction        N
P['c_visc']  = 15.0         # [ASM] cylinder viscous friction        N s/m
P['k_end']   = 2.0e5        # [ASM] end-stop stiffness               N/m
P['lam_end'] = 1.0e6        # [ASM] end-stop Hunt-Crossley damping   N s/m^2
P['k_ct']    = 1.0e5        # [ASM] rod/block contact stiffness      N/m
P['lam_ct']  = 5.0e5        # [ASM] rod/block H-C damping            N s/m^2
P['gap_app'] = 0.005        # [ASM] rod-tip approach gap             m

# --- 0.6 Conveyors ---------------------------------------------------------
P['r_pul']   = 0.020        # [ASM] pulley radius                    m
P['N_gear']  = 20.0         # [ASM] gearbox ratio                    -
P['eta_gb']  = 0.90         # [ASM] gearbox efficiency               -
P['J_mot']   = 1.0e-6       # [ASM] motor rotor inertia              kg m^2
P['J_pul']   = 2.0e-5       # [ASM] pulley + belt inertia @ pulley   kg m^2
P['T_max']   = 0.050        # [ASM] motor torque limit               N m
P['b_visc']  = 2.0e-4       # [ASM] drivetrain viscous               N m s/rad
P['T_coul']  = 3.0e-3       # [ASM] drivetrain Coulomb               N m
P['Kp_cv']   = 0.030        # [ASM] speed-loop P gain                N m s/rad
P['Ki_cv']   = 0.200        # [ASM] speed-loop I gain                N m/rad
P['v_belt_sp']= 0.150       # [ASM] belt setpoint speed              m/s
P['a_belt']  = 0.400        # [ASM] belt accel/decel ramp limit      m/s^2

# --- 0.7 Engraving base (electric linear axis) -----------------------------
# [SRC] step 25 is "PLC -> Engraving Base": no valve in the chain, hence NOT
# pneumatic.  Modelled as a motor-driven vertical axis.
P['m_base']  = 2.00         # [ASM] moving base mass                 kg
P['z_top']   = 0.050        # [ASM] engraving height                 m
P['Kp_bz']   = 4.0e3        # [ASM] axis position P gain             N/m
P['Kd_bz']   = 2.0e2        # [ASM] axis velocity D gain             N s/m
P['Ki_bz']   = 2.0e3        # [ASM] axis integral gain               N/(m s)
P['F_ax_max']= 200.0        # [ASM] axis force limit                 N
P['v_base']  = 0.050        # [ASM] axis speed limit                 m/s
P['z_tol']   = 1.0e-3       # [ASM] height sensor tolerance          m

# --- 0.8 Sensors -----------------------------------------------------------
P['prox_rng']= 0.030        # [ASM] proximity detection radius       m
P['t_scan']  = 0.010        # [ASM] PLC scan period                  s
P['t_sens']  = 0.005        # [ASM] sensor transport delay           s

# --- 0.9 Process (no timing given in Sequence.xlsx) ------------------------
P['t_op_notice'] = 3.0      # [PLH] operator reaction to notification s
P['t_engrave']   = 8.0      # [PLH] manual engraving duration         s
P['t_op_confirm']= 1.5      # [PLH] operator confirm-finish delay     s
P['t_timeout']   = 30.0     # [ASM] PLC per-state watchdog timeout    s

# ----------------------------------------------------------------------------
# 1. LAYOUT  (drawing units from reference script -> metres via SCALE)
# ----------------------------------------------------------------------------
def u(v):
    return v * S

# Surface regions [x0,x1,y0,y1] in drawing units, priority-ordered
REGIONS = [
    ('conv3',   8.60, 16.20, 3.19, 4.54),
    ('engrave', 8.60, 12.30, 4.30, 6.95),
    ('conv2',   7.25,  8.60, 0.90, 8.50),
    ('conv1',   1.00,  8.60, 8.50, 9.85),
    ('bin',    14.30, 15.90, 1.00, 3.19),
]

# Block waypoint centres (drawing units) - preserve reference layout
WP = {
    'feed':     (1.600, 10.000),
    'c1_load':  (1.600,  9.175),
    'c1_end':   (7.925,  9.175),
    'c2_load':  (7.925,  8.100),
    'c2_end':   (7.925,  5.900),
    'engrave':  (10.450, 5.900),
    'c3_load':  (10.450, 3.865),
    'c3_end':   (15.100, 3.865),
    'bin':      (15.100, 2.000),
}

# Cylinder definitions: axis, sign, block start->end waypoints
# DELIBERATELY STILL FIVE SPRING-RETURN CYLINDERS, and still commanded by
# u_cmd['sv'].  This file is the ITERATION-01 REFERENCE: compare_janatics.py
# exists to diff it against the Janatics-integrated model, so it has to stay
# the thing it was.  On 2026-09-02 the live plant (janatics_physics.py and the
# MATLAB path) was widened to the machine's eleven actuators on thirteen
# coils; this was NOT, on purpose.  Widening it would delete the baseline the
# comparison is against.  Do not "fix" the mismatch here.
CYL = [
    # name        axis  dir   from        to
    ('A1',        'y',  -1,  'feed',     'c1_load'),   # [SRC] 7-8
    ('A6',        'y',  -1,  'c1_end',   'c2_load'),   # [SRC] 15-16
    ('S2A1',      'x',  +1,  'c2_end',   'engrave'),   # [SRC] 22-23
    ('S3A1',      'y',  -1,  'engrave',  'c3_load'),   # [SRC] 33-34
    ('S3A2',      'y',  -1,  'c3_end',   'bin'),       # [SRC] 41-42
]
NCYL = len(CYL)
# distribution-valve branch feeding each cylinder [SRC] 6,14,21,32,40
CYL_BRANCH = [0, 0, 1, 2, 3]

CYLP = []
for name, axis, d, wfrom, wto in CYL:
    p0 = WP[wfrom][0 if axis == 'x' else 1]
    p1 = WP[wto][0 if axis == 'x' else 1]
    travel = abs(p1 - p0) * S
    stroke = P['gap_app'] + travel
    # rod tip retracted position, in the axis coordinate (metres)
    face0 = (p0 - d * 0.3) * S     # block face the rod contacts, at start
    tip0 = face0 - d * P['gap_app']
    CYLP.append(dict(name=name, axis=axis, dir=d, travel=travel,
                     stroke=stroke, tip0=tip0,
                     other=WP[wfrom][1 if axis == 'x' else 0] * S))

# --- Mechanical locating stops / belt side rails -------------------------
# [ADD] Not drawn in the reference script, but physically required: without
# them the block separates from the rod at end-of-stroke and coasts past the
# target.  Every real transfer station has these.  A stop at 'pos' on 'axis'
# resists motion in direction 'd'; active only while the block lies inside the
# gate window on the other axis.  Values are block-CENTRE coordinates.
STOPS = [
    # name              axis  d      pos    gate-axis window (drawing units)
    ('C1_side_rail',    'y',  -1,   9.175,  'x',  1.00,  7.40),
    ('C1_end_stop',     'x',  +1,   7.925,  'y',  8.50,  9.85),
    ('C2_end_stop',     'y',  -1,   5.900,  'x',  7.25,  8.60),
    ('ENG_fixture',     'x',  +1,  10.450,  'y',  4.30,  6.95),
    ('C3_side_rail',    'y',  -1,   3.865,  'x',  8.60, 14.30),
    ('C3_end_stop',     'x',  +1,  15.100,  'y',  3.19,  4.54),
    ('BIN_floor',       'y',  -1,   2.000,  'x', 14.30, 15.90),
]
P['k_stop'] = 5.0e4         # [ASM] locating-stop stiffness           N/m
P['lam_stop'] = 5.0e5       # [ASM] locating-stop H-C damping         N s/m^2

# conveyor: (name, belt unit vector, region key)
CONV = [('C1', (1.0, 0.0), 'conv1'),
        ('C2', (0.0, -1.0), 'conv2'),
        ('C3', (1.0, 0.0), 'conv3')]
NCONV = 3

# proximity sensors: (name, x, y) drawing units [SRC] 9,11,18,37
PROX = {
    'PX1': WP['c1_load'],   # block landed on conveyor 1      [SRC] 9
    'PX2': WP['c1_end'],    # block at end of conveyor 1      [SRC] 11
    'PX3': WP['c2_end'],    # block at end of conveyor 2      [SRC] 18
    'PX4': WP['c3_end'],    # final position check            [SRC] 37
}
CAM = WP['feed']            # camera field of view            [SRC] 1

# ----------------------------------------------------------------------------
# 2. STATE VECTOR
# ----------------------------------------------------------------------------
IDX = {}
_i = 0
def _add(n):
    global _i
    IDX[n] = _i
    _i += 1

_add('P_res')
for k in range(4):
    _add('P_br%d' % k)
    _add('dv%d' % k)
for c in range(NCYL):
    for f in ('PA', 'PB', 'x', 'v', 'sp'):
        _add('%s_%d' % (f, c))
for c in range(NCONV):
    _add('om_%d' % c); _add('ei_%d' % c); _add('vref_%d' % c)
_add('bz'); _add('bvz'); _add('bei')
_add('bx'); _add('by'); _add('bvx'); _add('bvy')
NS = _i


def init_state():
    s = [0.0] * NS
    s[IDX['P_res']] = P['P_res_0']
    for k in range(4):
        s[IDX['P_br%d' % k]] = P['P_atm']
    for c in range(NCYL):
        s[IDX['PA_%d' % c]] = P['P_atm']
        s[IDX['PB_%d' % c]] = P['P_atm']
    s[IDX['bx']] = WP['feed'][0] * S
    s[IDX['by']] = WP['feed'][1] * S
    return s


# ----------------------------------------------------------------------------
# 3. CONSTITUTIVE RELATIONS
# ----------------------------------------------------------------------------
def mdot_orifice(C, Pu, Pd):
    """ISO 6358 compressible mass flow through a restriction.
    Returns kg/s, positive from Pu to Pd. Handles reverse flow."""
    if C <= 0.0:
        return 0.0
    sgn = 1.0
    if Pd > Pu:
        Pu, Pd = Pd, Pu
        sgn = -1.0
    if Pu <= 1.0:
        return 0.0
    r = Pd / Pu
    b = P['b_crit']
    if r <= b:                                   # choked
        f = 1.0
    else:                                        # subsonic
        q = (r - b) / (1.0 - b)
        f = math.sqrt(max(0.0, 1.0 - q * q))
    return sgn * C * P['rho0'] * Pu * f


def support_of(bx, by):
    """Which surface carries the block, and that surface's velocity."""
    xu, yu = bx / S, by / S
    for name, x0, x1, y0, y1 in REGIONS:
        if x0 <= xu <= x1 and y0 <= yu <= y1:
            return name
    return 'plate'


def contact_hc(pen, pen_rate, k, lam):
    """Hunt-Crossley normal contact force.
        F = k*delta + lam*delta*delta_dot ,  F >= 0 (no adhesion)
    Damping is proportional to penetration, so it vanishes continuously at
    separation and dissipates on BOTH approach and rebound.  Replaces the
    one-sided Kelvin-Voigt damper, which was undamped on rebound and produced
    a limit cycle at the end stops."""
    if pen <= 0.0:
        return 0.0
    F = k * pen + lam * pen * pen_rate
    return F if F > 0.0 else 0.0


def friction_2d(vrel, N, mu_k):
    """Regularised Coulomb friction vector opposing relative sliding.
    F = -mu_k*N*tanh(|vrel|/v_creep) * vrel_hat  (Simscape-style regularisation)"""
    sp = math.hypot(vrel[0], vrel[1])
    if sp < 1e-12:
        return (0.0, 0.0)
    mag = mu_k * N * math.tanh(sp / P['v_creep'])
    return (-mag * vrel[0] / sp, -mag * vrel[1] / sp)


# ----------------------------------------------------------------------------
# 4. DERIVATIVES
# ----------------------------------------------------------------------------
def derivatives(s, u_cmd):
    """u_cmd: dict with pump_on, dv_sel(list of 4 0/1), sv(list of NCYL 0/1),
    conv_on(list of 3 0/1), base_cmd (0/1)."""
    ds = [0.0] * NS
    g = P['g']

    # ---- 4.1 receiver ------------------------------------------------------
    Pr = s[IDX['P_res']]
    mdot_in = P['mdot_pump'] if u_cmd['pump_on'] else 0.0
    # receiver safety relief valve (physical backstop, independent of the PLC)
    mdot_out = mdot_orifice(P['C_relief'], Pr, P['P_atm']) if Pr > P['P_relief'] else 0.0
    for k in range(4):
        Cb = P['C_dv'] * s[IDX['dv%d' % k]]
        mdot_out += mdot_orifice(Cb, Pr, s[IDX['P_br%d' % k]])
    # dP/dt = (n R T / V)(mdot_in - mdot_out)          [isothermal receiver]
    ds[IDX['P_res']] = (P['R_air'] * P['T_air'] / P['V_res']) * (mdot_in - mdot_out)

    # ---- 4.2 distribution valve spools -------------------------------------
    for k in range(4):
        ds[IDX['dv%d' % k]] = (u_cmd['dv_sel'][k] - s[IDX['dv%d' % k]]) / P['tau_dv']

    # ---- 4.3 cylinders + branch manifolds ----------------------------------
    branch_draw = [0.0] * 4
    bx, by = s[IDX['bx']], s[IDX['by']]
    bvx, bvy = s[IDX['bvx']], s[IDX['bvy']]
    Fblk = [0.0, 0.0]

    for c in range(NCYL):
        cp = CYLP[c]
        PA, PB = s[IDX['PA_%d' % c]], s[IDX['PB_%d' % c]]
        x, v = s[IDX['x_%d' % c]], s[IDX['v_%d' % c]]
        sp = s[IDX['sp_%d' % c]]
        br = CYL_BRANCH[c]
        Pm = s[IDX['P_br%d' % br]]

        # 5/2 valve: sp=1 -> A fed / B exhaust ; sp=0 -> A exhaust / B fed
        mA = mdot_orifice(P['C_in'] * sp, Pm, PA) \
             - mdot_orifice(P['C_ex'] * (1.0 - sp), PA, P['P_atm'])
        mB = mdot_orifice(P['C_in'] * (1.0 - sp), Pm, PB) \
             - mdot_orifice(P['C_ex'] * sp, PB, P['P_atm'])
        branch_draw[br] += (mdot_orifice(P['C_in'] * sp, Pm, PA)
                            + mdot_orifice(P['C_in'] * (1.0 - sp), Pm, PB))

        VA = P['V_dead'] + P['A_A'] * x
        VB = P['V_dead'] + P['A_B'] * (cp['stroke'] - x)
        n = P['n_poly']
        # dP/dt = (n R T/V) mdot - (n P/V) dV/dt
        ds[IDX['PA_%d' % c]] = (n * P['R_air'] * P['T_air'] / VA) * mA \
                               - (n * PA / VA) * (P['A_A'] * v)
        ds[IDX['PB_%d' % c]] = (n * P['R_air'] * P['T_air'] / VB) * mB \
                               - (n * PB / VB) * (-P['A_B'] * v)
        ds[IDX['sp_%d' % c]] = (u_cmd['sv'][c] - sp) / P['tau_sv']

        # piston force balance
        Fp = PA * P['A_A'] - PB * P['A_B'] - P['P_atm'] * (P['A_A'] - P['A_B'])
        Ffr = P['c_visc'] * v + P['F_coul'] * math.tanh(v / 1e-3)
        Fend = 0.0
        if x < 0.0:
            Fend = contact_hc(-x, -v, P['k_end'], P['lam_end'])
        elif x > cp['stroke']:
            Fend = -contact_hc(x - cp['stroke'], v, P['k_end'], P['lam_end'])

        # rod-tip / block contact (1-D along the cylinder axis)
        d = cp['dir']
        if cp['axis'] == 'x':
            bpos, bvel, opos = bx, bvx, by
        else:
            bpos, bvel, opos = by, bvy, bx
        Fct = 0.0
        # lateral alignment gate: block must be in front of this rod
        if abs(opos - cp['other']) < P['blk_a']:
            tip = cp['tip0'] + d * x
            face = bpos - d * 0.3 * S                 # block face toward rod
            pen = d * (tip - face)                    # >0 => interference
            if pen > 0.0:
                rate = d * (d * v - bvel)
                Fct = contact_hc(pen, rate, P['k_ct'], P['lam_ct'])
        Fload = -d * Fct * d          # reaction magnitude along rod axis
        ds[IDX['x_%d' % c]] = v
        ds[IDX['v_%d' % c]] = (Fp - Ffr + Fend - Fct) / P['m_pist']

        if cp['axis'] == 'x':
            Fblk[0] += d * Fct
        else:
            Fblk[1] += d * Fct

    # ---- 4.4 branch manifolds ----------------------------------------------
    for k in range(4):
        Cb = P['C_dv'] * s[IDX['dv%d' % k]]
        min_ = mdot_orifice(Cb, Pr, s[IDX['P_br%d' % k]])
        ds[IDX['P_br%d' % k]] = (P['R_air'] * P['T_air'] / P['V_branch']) \
                                * (min_ - branch_draw[k])

    # ---- 4.4b mechanical locating stops ------------------------------------
    for nm, ax, d, pos, gax, g0, g1 in STOPS:
        gpos = (bx if gax == 'x' else by) / S
        if not (g0 <= gpos <= g1):
            continue
        bpos = bx if ax == 'x' else by
        bvel = bvx if ax == 'x' else bvy
        pen = d * (bpos - pos * S)
        if pen > 0.0:
            rate = d * bvel
            Fs = contact_hc(pen, rate, P['k_stop'], P['lam_stop'])
            if ax == 'x':
                Fblk[0] -= d * Fs
            else:
                Fblk[1] -= d * Fs

    # ---- 4.5 conveyors ------------------------------------------------------
    sup = support_of(bx, by)
    belt_v = (0.0, 0.0)
    belt_idx = -1
    for i, (nm, uv, reg) in enumerate(CONV):
        om = s[IDX['om_%d' % i]]
        vb = P['r_pul'] * om
        if sup == reg:
            belt_v = (uv[0] * vb, uv[1] * vb)
            belt_idx = i

    # block support friction
    Nn = P['blk_m'] * g
    vrel = (bvx - belt_v[0], bvy - belt_v[1])
    Ff = friction_2d(vrel, Nn, P['mu_k'])
    Fblk[0] += Ff[0]
    Fblk[1] += Ff[1]

    for i, (nm, uv, reg) in enumerate(CONV):
        om = s[IDX['om_%d' % i]]
        ei = s[IDX['ei_%d' % i]]
        vref = s[IDX['vref_%d' % i]]
        # commanded speed ramp (drive accel limit)
        vtgt = P['v_belt_sp'] if u_cmd['conv_on'][i] else 0.0
        dv = vtgt - vref
        ds[IDX['vref_%d' % i]] = max(-P['a_belt'], min(P['a_belt'], dv / 0.01))
        om_ref = vref / P['r_pul']
        err = om_ref - om
        Tm = P['Kp_cv'] * err + P['Ki_cv'] * ei
        Tm = max(-P['T_max'], min(P['T_max'], Tm))
        ds[IDX['ei_%d' % i]] = err if abs(Tm) < P['T_max'] else 0.0   # anti-windup
        # reaction torque from block friction on this belt
        Treact = 0.0
        if i == belt_idx:
            # force belt applies to block = -Ff ; reaction on belt = +Ff
            Fbelt_on_blk = (Ff[0] * uv[0] + Ff[1] * uv[1])
            Treact = -P['r_pul'] * Fbelt_on_blk
        Jeq = P['J_pul'] + P['N_gear']**2 * P['J_mot']
        Tfr = P['b_visc'] * om + P['T_coul'] * math.tanh(om / 0.05)
        ds[IDX['om_%d' % i]] = (P['N_gear'] * P['eta_gb'] * Tm - Treact - Tfr) / Jeq

    # ---- 4.6 engraving base (vertical electric axis) -----------------------
    bz, bvz, bei = s[IDX['bz']], s[IDX['bvz']], s[IDX['bei']]
    on_base = (sup == 'engrave')
    m_ax = P['m_base'] + (P['blk_m'] if on_base else 0.0)
    ztgt = P['z_top'] if u_cmd['base_cmd'] else 0.0
    ez = ztgt - bz
    Fax = P['Kp_bz'] * ez + P['Ki_bz'] * bei - P['Kd_bz'] * bvz + m_ax * g
    Fax = max(-P['F_ax_max'], min(P['F_ax_max'], Fax))
    ds[IDX['bei']] = ez if abs(Fax) < P['F_ax_max'] else 0.0
    ds[IDX['bz']] = bvz
    ds[IDX['bvz']] = (Fax - m_ax * g) / m_ax

    # ---- 4.7 workpiece planar dynamics -------------------------------------
    ds[IDX['bx']] = bvx
    ds[IDX['by']] = bvy
    ds[IDX['bvx']] = Fblk[0] / P['blk_m']
    ds[IDX['bvy']] = Fblk[1] / P['blk_m']
    return ds


# ----------------------------------------------------------------------------
# 5. SENSORS  (physical conditions only - never timers)
# ----------------------------------------------------------------------------
def sensors(s):
    bx, by = s[IDX['bx']], s[IDX['by']]
    o = {}
    o['CAM'] = (math.hypot(bx - CAM[0] * S, by - CAM[1] * S) < P['prox_rng'])
    for k, (px, py) in PROX.items():
        o[k] = (math.hypot(bx - px * S, by - py * S) < P['prox_rng'])
    for c in range(NCYL):
        st = CYLP[c]['stroke']
        o['EXT_%d' % c] = s[IDX['x_%d' % c]] >= st - 2e-3
        o['RET_%d' % c] = s[IDX['x_%d' % c]] <= 2e-3
    o['HS_TOP'] = abs(s[IDX['bz']] - P['z_top']) < P['z_tol']
    o['HS_BOT'] = abs(s[IDX['bz']]) < P['z_tol']
    o['P_res'] = s[IDX['P_res']]
    o['P_READY'] = s[IDX['P_res']] >= P['P_ready']
    for k in range(4):
        o['BR_RDY_%d' % k] = s[IDX['P_br%d' % k]] >= P['P_br_rdy']
    for c in range(NCYL):
        # retract-side chamber charged => 5/2 valve has actually pre-loaded the
        # cylinder, so extension starts against a real back-pressure
        o['CHG_%d' % c] = s[IDX['PB_%d' % c]] >= P['P_br_rdy'] * 0.85
    return o


# ----------------------------------------------------------------------------
# 6. PLC  -  one state per Sequence.xlsx step group, feedback driven
# ----------------------------------------------------------------------------
# (state name, excel ref, transition-guard key)
STATES = [
    ('S00_INIT',              '-'),
    ('S01_CAMERA_DETECT',     '1'),
    ('S02_PUMP_CMD',          '2'),
    ('S03_PRESSURE_PREP',     '3'),
    ('S04_DV_READY',          '4'),
    ('S05_DV_SEL_FEEDER',     '5,6'),
    ('S06_A1_EXTEND',         '7,8'),
    ('S07_PROX1_CHECK',       '9'),
    ('S08_A1_RETRACT',        '8i'),
    ('S09_CONV1_START',       '10'),
    ('S10_PROX2_CHECK',       '11'),
    ('S11_CONV1_STOP',        '12'),
    ('S12_DV_SEL_FEEDER2',    '13,14'),
    ('S13_A6_EXTEND',         '15,16'),
    ('S14_A6_RETRACT',        '16i'),
    ('S15_CONV2_START',       '17'),
    ('S16_PROX3_CHECK',       '18'),
    ('S17_CONV2_STOP',        '19'),
    ('S18_DV_SEL_SECOND',     '20,21'),
    ('S19_S2A1_EXTEND',       '22,23'),
    ('S20_S2A1_FEEDBACK',     '24'),
    ('S21_S2A1_RETRACT',      '24i'),
    ('S22_BASE_UP',           '25'),
    ('S23_HEIGHT_TOP',        '26'),
    ('S24_OPERATOR_NOTIFY',   '27'),
    ('S25_ENGRAVE_MANUAL',    '28'),
    ('S26_ENGRAVE_CONFIRM',   '29'),
    ('S27_BASE_DOWN',         '30i'),
    ('S28_HEIGHT_BOTTOM',     '30'),
    ('S29_DV_SEL_THIRD',      '31,32'),
    ('S30_S3A1_EXTEND',       '33,34'),
    ('S31_S3A1_FEEDBACK',     '35'),
    ('S32_S3A1_RETRACT',      '35i'),
    ('S33_CONV3_START',       '36*'),
    ('S34_PROX4_FINAL',       '37'),
    ('S35_CONV3_STOP',        '38'),
    ('S36_DV_SEL_FOURTH',     '39,40'),
    ('S37_S3A2_EXTEND',       '41,42'),
    ('S38_S3A2_RETRACT',      '42i'),
    ('S39_CYCLE_COMPLETE',    '-'),
]
SN = {n: i for i, (n, _) in enumerate(STATES)}


class PLC:
    def __init__(self):
        self.st = 0
        self.t_in = 0.0
        self.pump_enable = False
        self.pump = False
        self.dv = [0, 0, 0, 0]
        self.sv = [0] * NCYL
        self.cv = [0, 0, 0]
        self.base = 0
        self.op_notified = False
        self.timeouts = []

    def out(self):
        return dict(pump_on=self.pump, dv_sel=self.dv, sv=self.sv,
                    conv_on=self.cv, base_cmd=self.base)

    def step(self, t, sn, dt):
        self.t_in += dt
        # --- compressor pressure switch (hysteresis, sampled every scan) ----
        if sn['P_res'] >= P['P_cut_out']:
            self.pump = False
        elif sn['P_res'] <= P['P_cut_in']:
            self.pump = self.pump_enable
        else:
            self.pump = self.pump and self.pump_enable
        st = self.st
        nxt = None
        el = self.t_in

        if st == SN['S00_INIT']:
            self.pump_enable = False; self.dv = [0, 0, 0, 0]
            self.sv = [0] * NCYL; self.cv = [0, 0, 0]; self.base = 0
            nxt = SN['S01_CAMERA_DETECT']
        elif st == SN['S01_CAMERA_DETECT']:
            if sn['CAM']: nxt = SN['S02_PUMP_CMD']
        elif st == SN['S02_PUMP_CMD']:
            self.pump_enable = True
            self.pump = sn['P_res'] < P['P_cut_out']
            nxt = SN['S03_PRESSURE_PREP']
        elif st == SN['S03_PRESSURE_PREP']:
            if sn['P_READY']: nxt = SN['S04_DV_READY']
        elif st == SN['S04_DV_READY']:
            nxt = SN['S05_DV_SEL_FEEDER']
        elif st == SN['S05_DV_SEL_FEEDER']:
            self.dv = [1, 0, 0, 0]
            if sn['BR_RDY_0'] and sn['CHG_0']: nxt = SN['S06_A1_EXTEND']
        elif st == SN['S06_A1_EXTEND']:
            self.sv[0] = 1
            if sn['EXT_0']: nxt = SN['S07_PROX1_CHECK']
        elif st == SN['S07_PROX1_CHECK']:
            if sn['PX1']: nxt = SN['S08_A1_RETRACT']
        elif st == SN['S08_A1_RETRACT']:
            self.sv[0] = 0
            if sn['RET_0']: nxt = SN['S09_CONV1_START']
        elif st == SN['S09_CONV1_START']:
            self.cv[0] = 1; nxt = SN['S10_PROX2_CHECK']
        elif st == SN['S10_PROX2_CHECK']:
            if sn['PX2']: nxt = SN['S11_CONV1_STOP']
        elif st == SN['S11_CONV1_STOP']:
            self.cv[0] = 0; nxt = SN['S12_DV_SEL_FEEDER2']
        elif st == SN['S12_DV_SEL_FEEDER2']:
            self.dv = [1, 0, 0, 0]
            if sn['BR_RDY_0'] and sn['CHG_1']: nxt = SN['S13_A6_EXTEND']
        elif st == SN['S13_A6_EXTEND']:
            self.sv[1] = 1
            if sn['EXT_1']: nxt = SN['S14_A6_RETRACT']
        elif st == SN['S14_A6_RETRACT']:
            self.sv[1] = 0
            if sn['RET_1']: nxt = SN['S15_CONV2_START']
        elif st == SN['S15_CONV2_START']:
            self.cv[1] = 1; nxt = SN['S16_PROX3_CHECK']
        elif st == SN['S16_PROX3_CHECK']:
            if sn['PX3']: nxt = SN['S17_CONV2_STOP']
        elif st == SN['S17_CONV2_STOP']:
            self.cv[1] = 0; nxt = SN['S18_DV_SEL_SECOND']
        elif st == SN['S18_DV_SEL_SECOND']:
            self.dv = [0, 1, 0, 0]
            if sn['BR_RDY_1'] and sn['CHG_2']: nxt = SN['S19_S2A1_EXTEND']
        elif st == SN['S19_S2A1_EXTEND']:
            self.sv[2] = 1
            if sn['EXT_2']: nxt = SN['S20_S2A1_FEEDBACK']
        elif st == SN['S20_S2A1_FEEDBACK']:
            nxt = SN['S21_S2A1_RETRACT']
        elif st == SN['S21_S2A1_RETRACT']:
            self.sv[2] = 0
            if sn['RET_2']: nxt = SN['S22_BASE_UP']
        elif st == SN['S22_BASE_UP']:
            self.base = 1; nxt = SN['S23_HEIGHT_TOP']
        elif st == SN['S23_HEIGHT_TOP']:
            if sn['HS_TOP']: nxt = SN['S24_OPERATOR_NOTIFY']
        elif st == SN['S24_OPERATOR_NOTIFY']:
            self.op_notified = True
            if el >= P['t_op_notice']: nxt = SN['S25_ENGRAVE_MANUAL']
        elif st == SN['S25_ENGRAVE_MANUAL']:
            if el >= P['t_engrave']: nxt = SN['S26_ENGRAVE_CONFIRM']
        elif st == SN['S26_ENGRAVE_CONFIRM']:
            if el >= P['t_op_confirm']: nxt = SN['S27_BASE_DOWN']
        elif st == SN['S27_BASE_DOWN']:
            self.base = 0; nxt = SN['S28_HEIGHT_BOTTOM']
        elif st == SN['S28_HEIGHT_BOTTOM']:
            if sn['HS_BOT']: nxt = SN['S29_DV_SEL_THIRD']
        elif st == SN['S29_DV_SEL_THIRD']:
            self.dv = [0, 0, 1, 0]
            if sn['BR_RDY_2'] and sn['CHG_3']: nxt = SN['S30_S3A1_EXTEND']
        elif st == SN['S30_S3A1_EXTEND']:
            self.sv[3] = 1
            if sn['EXT_3']: nxt = SN['S31_S3A1_FEEDBACK']
        elif st == SN['S31_S3A1_FEEDBACK']:
            nxt = SN['S32_S3A1_RETRACT']
        elif st == SN['S32_S3A1_RETRACT']:
            self.sv[3] = 0
            if sn['RET_3']: nxt = SN['S33_CONV3_START']
        elif st == SN['S33_CONV3_START']:
            self.cv[2] = 1; nxt = SN['S34_PROX4_FINAL']
        elif st == SN['S34_PROX4_FINAL']:
            if sn['PX4']: nxt = SN['S35_CONV3_STOP']
        elif st == SN['S35_CONV3_STOP']:
            self.cv[2] = 0; nxt = SN['S36_DV_SEL_FOURTH']
        elif st == SN['S36_DV_SEL_FOURTH']:
            self.dv = [0, 0, 0, 1]
            if sn['BR_RDY_3'] and sn['CHG_4']: nxt = SN['S37_S3A2_EXTEND']
        elif st == SN['S37_S3A2_EXTEND']:
            self.sv[4] = 1
            if sn['EXT_4']: nxt = SN['S38_S3A2_RETRACT']
        elif st == SN['S38_S3A2_RETRACT']:
            self.sv[4] = 0
            if sn['RET_4']: nxt = SN['S39_CYCLE_COMPLETE']

        # watchdog
        if nxt is None and self.t_in > P['t_timeout'] and st != SN['S39_CYCLE_COMPLETE']:
            self.timeouts.append((t, STATES[st][0]))
            self.t_in = 0.0
        if nxt is not None and nxt != st:
            self.st = nxt
            self.t_in = 0.0
            return True
        return False


# ----------------------------------------------------------------------------
# 7. RK4 fixed-step driver
# ----------------------------------------------------------------------------
def run(tmax=90.0, dt=5e-4, verbose=True):
    s = init_state()
    plc = PLC()
    t = 0.0
    scan_acc = 0.0
    log = []
    trans = []
    nsc = int(round(P['t_scan'] / dt))
    k = 0
    u_cmd = plc.out()
    max_pen = 0.0
    max_jump = 0.0
    prev = (s[IDX['bx']], s[IDX['by']])

    while t < tmax:
        if k % nsc == 0:
            sn = sensors(s)
            if plc.step(t, sn, P['t_scan']):
                trans.append((t, STATES[plc.st][0], STATES[plc.st][1]))
            u_cmd = plc.out()
            if plc.st == SN['S39_CYCLE_COMPLETE']:
                log.append((t, list(s)))
                break

        # RK4
        k1 = derivatives(s, u_cmd)
        s2 = [s[i] + 0.5 * dt * k1[i] for i in range(NS)]
        k2 = derivatives(s2, u_cmd)
        s3 = [s[i] + 0.5 * dt * k2[i] for i in range(NS)]
        k3 = derivatives(s3, u_cmd)
        s4 = [s[i] + dt * k3[i] for i in range(NS)]
        k4 = derivatives(s4, u_cmd)
        s = [s[i] + dt / 6.0 * (k1[i] + 2 * k2[i] + 2 * k3[i] + k4[i])
             for i in range(NS)]
        t += dt
        k += 1

        j = math.hypot(s[IDX['bx']] - prev[0], s[IDX['by']] - prev[1])
        max_jump = max(max_jump, j)
        prev = (s[IDX['bx']], s[IDX['by']])
        if k % 20 == 0:
            log.append((t, list(s)))

    return t, s, plc, trans, log, max_jump


if __name__ == '__main__':
    print('states:', NS, ' block mass %.4f kg' % P['blk_m'],
          ' A_A=%.3e A_B=%.3e m^2' % (P['A_A'], P['A_B']))
    for c in CYLP:
        print('  %-6s axis=%s dir=%+d travel=%.4f stroke=%.4f tip0=%.4f'
              % (c['name'], c['axis'], c['dir'], c['travel'], c['stroke'], c['tip0']))
    t, s, plc, trans, log, mj = run()
    print('\n--- transitions ---')
    for tt, nm, xr in trans:
        print('  t=%7.3f  %-24s  excel:%s' % (tt, nm, xr))
    print('\nfinal state: %s  t=%.3f' % (STATES[plc.st][0], t))
    print('block xy = (%.4f, %.4f) m  target bin=(%.4f, %.4f)'
          % (s[IDX['bx']], s[IDX['by']], WP['bin'][0] * S, WP['bin'][1] * S))
    print('max per-step block displacement = %.3e m (teleport check)' % mj)
    print('timeouts:', plc.timeouts)
