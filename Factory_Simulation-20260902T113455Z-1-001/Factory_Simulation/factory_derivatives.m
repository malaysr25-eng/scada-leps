function [ds, dbg] = factory_derivatives(s, u, P)
%FACTORY_DERIVATIVES  Continuous-time physics of the factory cell.
%
%   ds = FACTORY_DERIVATIVES(s, u, P) returns the state derivative.
%   [ds, dbg] = FACTORY_DERIVATIVES(...) also returns the 2-D force breakdown
%       acting on the workpiece, for VISUALIZE_PROCESSES:
%         dbg.F_rod   1x2  net rod-tip contact force            [N]
%         dbg.F_stop  1x2  net locating-stop reaction           [N]
%         dbg.F_fric  1x2  belt / plate friction                [N]
%         dbg.F_net   1x2  total, identical to what drives bvx/bvy
%         dbg.F_cyl   nx2  per-cylinder contact contribution    [N]
%         dbg.belt_v  1x2  belt surface velocity under the part [m/s]
%         dbg.v_rel   1x2  workpiece velocity relative to it    [m/s]
%         dbg.reg     idx into P.REG, 0 = static plate
%         dbg.reg_name
%
%   dbg IS ONLY ASSEMBLED WHEN A SECOND OUTPUT IS REQUESTED. The RK4 hot path
%   calls this ~7 million times per run with one output and takes the cheap
%   branch. The accumulators below are PARALLEL to Fblk rather than replacing
%   it, so the arithmetic that produces ds is untouched and bit-identical -
%   asserted by PhysicsTest/diagnosticsDoNotChangeTheDerivative.
%
%   s   state vector, indexed by P.IX (see INITIALIZE_FACTORY)
%   u   command struct from FACTORY_PLC:
%         u.pump_on  logical      compressor contactor
%         u.dv       1x4 0/1      distribution valve branch select
%         u.sol      1x13 0/1     THE MACHINE'S SOLENOID COILS. Not one per
%                                 actuator: eleven actuators carry thirteen
%                                 coils, because CYL_A and CYL_B are
%                                 double-solenoid and take two each. The map
%                                 from coil to actuator is FACTORY_ACTUATORS.
%         u.conv     1x3 0/1      conveyor run commands
%         u.base     0/1          engraving base up/down command
%
%   GOVERNING EQUATIONS (all SI, all dimensionally verified - see the
%   equation audit table in
%   Project_Notes/History/Factory_Simulation_Development_Log.md):
%
%   Receiver / manifold (isothermal, fixed volume):
%       dP/dt = (R*T/V) * (mdot_in - mdot_out)                    [Pa/s]
%
%   Cylinder chamber (polytropic, moving boundary):
%       dP/dt = (n*R*T/V)*mdot - (n*P/V)*dV/dt                    [Pa/s]
%       V_A = V_dead + A_A*x ,  V_B = V_dead + A_B*(L - x)
%
%   Restriction mass flow (ISO 6358, choked and subsonic branches):
%       mdot = C*rho0*Pu                       , Pd/Pu <= b
%       mdot = C*rho0*Pu*sqrt(1-((r-b)/(1-b))^2), otherwise
%
%   Regulator (Janatics FRL, ideal reducing valve):
%       P_supply = min(P_receiver, P_set)                          [Pa]
%
%   Valve circuit (Janatics DS2 5/2 + GR speed controller, METER-OUT):
%       supply  through C_sup     = series(C_DS2, C_GR_check)
%       exhaust through C_ctrl_A / C_ctrl_B  = GR needle setting
%
%   Valve spool, the two types the machine actually runs:
%       spring-return   d(sp)/dt = (coil            - sp)/tau_sv
%       double-solenoid d(sp)/dt = (1               - sp)/tau_sv , extend coil
%                                = (0               - sp)/tau_sv , retract coil
%                                = 0                             , both off
%
%   Piston:
%       m*xddot = P_A*A_A - P_B*A_B - P_atm*(A_A-A_B)
%                 - F_friction + F_endstop - F_contact             [N]
%       F_friction = c_visc*v + (F_coul0 + f_loss*F_drive)*tanh(v/v_eps)
%       F_drive    = max(gauge force available on either face)
%       f_loss     = 1 - 0.90, the Janatics catalogue force allowance
%
%   Conveyor drivetrain (referred to the pulley shaft):
%       J_eq*omegadot = N*eta*T_motor - r*F_belt - T_friction     [N*m]
%       v_belt = r*omega                                          [m/s]
%       J_eq = J_pulley + N^2*J_motor
%
%   Contact (Hunt-Crossley, all interfaces):
%       F = k*delta + lambda*delta*deltadot ,  F >= 0              [N]
%
%   Workpiece:
%       m*xddot = sum(F_contact) + F_friction_from_support         [N]

ds = zeros(P.NS,1);
IX = P.IX; n = P.NCYL; m = P.NCONV;
RT = P.R_air * P.T_air;

% PERFORMANCE. Everything below is read inside the per-cylinder, per-branch or
% per-conveyor loops, which run about 250,000 times per cycle at dt = 0.5 ms. MATLAB
% resolves a struct field on every access, and a NESTED one (P.fault.x) twice,
% so these lookups alone accounted for tens of millions of resolutions per run.
% Hoisting them changes no arithmetic: results are bit-identical.
Patm    = P.P_atm;      b_crit  = P.b_crit;     rho0    = P.rho0;
A_A     = P.A_A;        A_B     = P.A_B;        V_dead  = P.V_dead;
n_poly  = P.n_poly;     C_sup   = P.C_sup;      C_dv    = P.C_dv;
C_ctrlA = P.C_ctrl_A;   C_ctrlB = P.C_ctrl_B;   tau_sv  = P.tau_sv;
F_coul0 = P.F_coul0;    f_loss  = P.f_loss;     c_visc  = P.c_visc;
v_eps   = P.v_eps;      k_end   = P.k_end;      lam_end = P.lam_end;
k_ct    = P.k_ct;       lam_ct  = P.lam_ct;     m_pist  = P.m_pist;
blk_L   = P.blk_L;      blk_W   = P.blk_W;      CYL     = P.CYL;
fr_scale = P.fault.friction_scale;
fr_stick = P.fault.actuator_stick;
fr_stuck = P.fault.valve_stuck;

Pr  = s(IX.P_res);
bx  = s(IX.bx);  by  = s(IX.by);
bvx = s(IX.bvx); bvy = s(IX.bvy);
Fblk = [0 0];

want_dbg = nargout > 1;
if want_dbg
    dF_rod = [0 0]; dF_stop = [0 0]; dF_cyl = zeros(P.NCYL, 2);
end

%% ---- 1. Receiver -------------------------------------------------------
mdot_in = 0;
if u.pump_on
    mdot_in = P.mdot_pump * P.fault.P_supply_scale;
end
% Safety relief valve: a physical device, independent of the PLC. Without it
% (and without the compressor pressure switch) the receiver integrates without
% bound and drags every downstream chamber with it.
mdot_out = 0;
if Pr > P.P_relief
    mdot_out = pneu_mdot(P.C_relief, Pr, Patm, b_crit, rho0);
end
% [JAN] Janatics FRL regulator. Everything downstream of it sees the SET
% pressure, not the receiver pressure. Iteration 01 had no regulator, so
% actuator force cycled with the compressor pressure switch (6.0 - 8.0 bar).
% Modelled as an ideal reducing valve: it can drop pressure, never raise it.
Preg = min(Pr, P.P_set);
for k = 1:4
    mdot_out = mdot_out + pneu_mdot(C_dv*s(IX.dv(k)), Preg, s(IX.P_br(k)), b_crit, rho0);
end
ds(IX.P_res) = (RT/P.V_res) * (mdot_in - mdot_out);

%% ---- 2. Distribution valve spools --------------------------------------
for k = 1:4
    ds(IX.dv(k)) = (u.dv(k) - s(IX.dv(k))) / P.tau_dv;
end

%% ---- 3. Cylinders ------------------------------------------------------
branch_draw = zeros(1,4);
air_draw    = 0;
for c = 1:n
    C  = CYL(c);
    PA = s(IX.PA(c)); PB = s(IX.PB(c));
    x  = s(IX.x(c));  v  = s(IX.v(c));
    sp = s(IX.sp(c)); br = C.branch;
    Pm = s(IX.P_br(br));

    % [JAN] Janatics DS2 5/2 valve + GR speed controller at the cylinder port.
    %   sp = 1 -> A fed through DS2+GR check, B exhausts through the GR needle
    %   sp = 0 -> B fed, A exhausts
    % Supply is nearly unrestricted (C_sup); the SPEED is set on the EXHAUST
    % side by the needle (C_ctrl_*). This is meter-out, which is what a GR
    % mounted on the cylinder port actually does, and it is the reason the
    % rod does not run away when the load leaves it.
    % pneu_mdot returns exactly 0 when its conductance is <= 0, and every
    % conductance here is a positive constant times sp or (1-sp). For most of
    % the cycle the spool sits hard at 0 or 1, so half of these calls did no
    % work but still paid MATLAB's call overhead -- 7.1 million calls per run.
    % Guarding on the spool position is exactly equivalent and skips them.
    if sp > 0
        qAin  = pneu_mdot(C_sup*sp,      Pm, PA,   b_crit, rho0);
        qBout = pneu_mdot(C_ctrlB*sp,    PB, Patm, b_crit, rho0);
    else
        qAin = 0; qBout = 0;
    end
    if sp < 1
        qBin  = pneu_mdot(C_sup*(1-sp),  Pm, PB,   b_crit, rho0);
        qAout = pneu_mdot(C_ctrlA*(1-sp),PA, Patm, b_crit, rho0);
    else
        qBin = 0; qAout = 0;
    end
    mA = qAin - qAout;
    mB = qBin - qBout;
    branch_draw(br) = branch_draw(br) + qAin + qBin;
    air_draw        = air_draw + qAin + qBin;

    VA = V_dead + A_A*x;
    VB = V_dead + A_B*(C.stroke - x);
    nn = n_poly;
    ds(IX.PA(c)) = (nn*RT/VA)*mA - (nn*PA/VA)*( A_A*v);
    ds(IX.PB(c)) = (nn*RT/VB)*mB - (nn*PB/VB)*(-A_B*v);

    % --- spool target, from the MACHINE'S solenoid coils ------------------
    % A SPRING-RETURN valve follows its single coil: energised the spool goes
    % to 1, released the spring returns it to 0.
    %
    % A DOUBLE-SOLENOID valve is a LATCH. The extend coil drives the spool to
    % 1, the retract coil to 0, and with BOTH COILS OFF THE SPOOL HOLDS - which
    % is what tgt = sp, and so ds = 0, says. That hold is why the machine can
    % PULSE these coils (FC6 networks 4, 7 and 15, T#2S, P.PLC.t_valve_pulse)
    % rather than energise them for the whole stroke, and it is precisely the
    % behaviour a spring-return valve cannot express. It is the reason this
    % was a re-model and not a wider array.
    %
    % Both coils energised at once is a WIRING FAULT on a real double-solenoid
    % valve, not a command. Extend is taken to win, which is what a spool
    % driven from both ends by equal pilots does not do - it stalls - but the
    % sequencer never issues it and inventing a stall would be inventing
    % physics nobody has observed.
    if C.dbl
        if u.sol(C.coil_ext) > 0.5
            tgt = 1;
        elseif u.sol(C.coil_ret) > 0.5
            tgt = 0;
        else
            tgt = sp;                     % both coils off - HOLD POSITION
        end
    else
        tgt = u.sol(C.coil_ext);
    end
    if fr_stuck(c)
        ds(IX.sp(c)) = 0;
    else
        ds(IX.sp(c)) = (tgt - sp) / tau_sv;
    end

    % --- piston force balance ---
    Fp   = PA*A_A - PB*A_B - Patm*(A_A - A_B);
    % [JAN] Janatics tabulates output force as 0.90*P*A, so the loss scales
    % WITH the driving load. A fixed Coulomb force (Iteration 01) cannot
    % reproduce the catalogue at both low and high pressure. Modelled as
    % small breakaway + load-proportional loss.
    F_drive = max([(PA - Patm)*A_A, (PB - Patm)*A_B, 0]);
    Fc   = (F_coul0 + f_loss*F_drive + fr_stick(c)) * fr_scale;
    Ffr  = c_visc*fr_scale*v + Fc*tanh(v/v_eps);

    Fend = 0;
    if x < 0
        Fend =  contact_hc(-x, -v, k_end, lam_end);
    elseif x > C.stroke
        Fend = -contact_hc(x - C.stroke, v, k_end, lam_end);
    end

    % --- rod tip / workpiece contact, 1-D along the cylinder axis ---
    if C.axis == 'x'
        bpos = bx; bvel = bvx; lat = by;
        ax_ext = blk_L;                  % extent ALONG the rod axis
        lat_ext = blk_W;                 % extent ACROSS it
    else
        bpos = by; bvel = bvy; lat = bx;
        ax_ext = blk_W;
        lat_ext = blk_L;
    end
    Fct = 0;
    % Alignment uses the FULL lateral extent, as it always has. Half would be
    % the geometrically correct test against a point rod tip; that is a
    % separate question from the cuboid, so it is left alone here.
    %
    % C.contact is false for the two actuators whose PLACEMENT IS NOT KNOWN
    % (XFER_CV2_CV3 and OUTFEED_B - see FACTORY_ACTUATORS). They are fully
    % modelled pneumatically and have no rod-tip geometry at all; their tip0
    % and lat are NaN, so this guard is what stops a NaN reaching the force
    % balance. Skipping them here is not an approximation, it is the refusal
    % to invent a position.
    %
    % The four UNSELECTED magazine pushers need no such guard. They are
    % placed, one P.mag_pitch = 110 mm apart, and the workpiece is P.blk_L =
    % 100 mm wide, so the lateral test below excludes them with 10 mm to
    % spare. Geometry does that work, not a flag.
    if C.contact && abs(lat - C.lat) < lat_ext   % workpiece in front of the rod
        tip  = C.tip0 + C.dir*x;
        face = bpos - C.dir*ax_ext/2;
        pen  = C.dir*(tip - face);         % > 0 means interference
        if pen > 0
            rate = C.dir*(C.dir*v - bvel); % closing speed
            Fct  = contact_hc(pen, rate, k_ct, lam_ct);
        end
    end

    ds(IX.x(c)) = v;
    ds(IX.v(c)) = (Fp - Ffr + Fend - Fct) / m_pist;

    if C.axis == 'x'
        Fblk(1) = Fblk(1) + C.dir*Fct;     % Newton's third law
        if want_dbg
            dF_rod(1) = dF_rod(1) + C.dir*Fct; dF_cyl(c,1) = C.dir*Fct;
        end
    else
        Fblk(2) = Fblk(2) + C.dir*Fct;
        if want_dbg
            dF_rod(2) = dF_rod(2) + C.dir*Fct; dF_cyl(c,2) = C.dir*Fct;
        end
    end
end

%% ---- 4. Branch manifolds -----------------------------------------------
for k = 1:4
    % Fed from the REGULATED pressure, identically to the receiver draw above.
    qin = pneu_mdot(C_dv*s(IX.dv(k)), Preg, s(IX.P_br(k)), b_crit, rho0);
    ds(IX.P_br(k)) = (RT/P.V_branch) * (qin - branch_draw(k));
end

%% ---- 5. Mechanical locating stops --------------------------------------
for i = 1:numel(P.STOP)
    T = P.STOP(i);
    if T.gax == 1; gp = bx; else; gp = by; end
    if gp < T.g0 || gp > T.g1; continue; end
    if T.ax == 1; bp = bx; bv = bvx; else; bp = by; bv = bvy; end
    pen = T.dir*(bp - T.pos);
    if pen > 0
        Fs = contact_hc(pen, T.dir*bv, P.k_stop, P.lam_stop);
        Fblk(T.ax) = Fblk(T.ax) - T.dir*Fs;
        if want_dbg; dF_stop(T.ax) = dF_stop(T.ax) - T.dir*Fs; end
    end
end

%% ---- 6. Conveyors and belt/workpiece friction --------------------------
[reg, ~] = support_region(bx, by, P);
belt_v = [0 0]; belt_i = 0;
for i = 1:m
    if reg == P.CONV_REG(i)
        vb = P.r_pul * s(IX.om(i));
        belt_v = P.REG(reg).uv * vb;
        belt_i = i;
    end
end

% Regularised Coulomb friction between workpiece and whatever supports it.
% F = -mu_k*N*tanh(|vrel|/v_creep) * vrel_hat
N_norm = P.blk_m * P.g;
vrel   = [bvx bvy] - belt_v;
spd    = hypot(vrel(1), vrel(2));
Ff     = [0 0];
if spd > 1e-12
    mag = P.mu_k * P.fault.conveyor_slip * N_norm * tanh(spd/P.v_creep);
    Ff  = -mag * vrel / spd;
end
Fblk = Fblk + Ff;

Jeq = P.J_pul + P.N_gear^2 * P.J_mot;
for i = 1:m
    om = s(IX.om(i)); ei = s(IX.ei(i)); vref = s(IX.vref(i));
    % Drive speed reference with acceleration ramp (as a real VFD does).
    if u.conv(i); vtgt = P.v_belt; else; vtgt = 0; end
    ds(IX.vref(i)) = max(-P.a_belt, min(P.a_belt, (vtgt - vref)/0.01));

    err = vref/P.r_pul - om;
    Tm  = P.Kp_cv*err + P.Ki_cv*ei;
    Tm  = max(-P.T_max, min(P.T_max, Tm));
    if P.fault.conveyor_fail(i); Tm = 0; end
    if abs(Tm) < P.T_max                       % integrator anti-windup
        ds(IX.ei(i)) = err;
    else
        ds(IX.ei(i)) = 0;
    end

    Treact = 0;
    if i == belt_i
        % Reaction of the belt friction acting back on the pulley shaft.
        Treact = -P.r_pul * dot(Ff, P.REG(reg).uv);
    end
    Tfr = P.b_visc*om + P.T_coul*tanh(om/P.om_eps);
    ds(IX.om(i)) = (P.N_gear*P.eta_gb*Tm - Treact - Tfr) / Jeq;
end

%% ---- 7. Engraving base (electric vertical axis) ------------------------
bz = s(IX.bz); bvz = s(IX.bvz); bei = s(IX.bei);
on_base = (reg > 0) && strcmp(P.REG(reg).name,'engrave');
m_ax = P.m_base + P.blk_m*on_base;
if u.base; ztgt = P.z_top; else; ztgt = 0; end
ez  = ztgt - bz;
Fax = P.Kp_bz*ez + P.Ki_bz*bei - P.Kd_bz*bvz + m_ax*P.g;   % gravity feed-fwd
Fax = max(-P.F_ax_max, min(P.F_ax_max, Fax));
if abs(Fax) < P.F_ax_max; ds(IX.bei) = ez; else; ds(IX.bei) = 0; end
ds(IX.bz)  = bvz;
ds(IX.bvz) = (Fax - m_ax*P.g) / m_ax;

%% ---- 8. Workpiece planar dynamics --------------------------------------
ds(IX.bx)  = bvx;
ds(IX.by)  = bvy;
ds(IX.bvx) = Fblk(1) / P.blk_m;
ds(IX.bvy) = Fblk(2) / P.blk_m;

if want_dbg
    [~, rname]   = support_region(bx, by, P);
    dbg.F_rod    = dF_rod;
    dbg.F_stop   = dF_stop;
    dbg.F_fric   = Ff;
    dbg.F_net    = Fblk;
    dbg.F_cyl    = dF_cyl;
    dbg.belt_v   = belt_v;
    dbg.v_rel    = vrel;
    dbg.reg      = reg;
    dbg.reg_name = rname;
end

%% ---- 9. Air consumption accounting -------------------------------------
% Cumulative mass of air drawn from the manifolds into the cylinders. A pure
% accumulator: it is an output of the model and feeds back into nothing.
ds(IX.mair) = air_draw;
end

% =========================================================================
function q = pneu_mdot(C, Pu, Pd, b, rho0)
%PNEU_MDOT  ISO 6358 compressible mass flow through a restriction [kg/s].
%   Positive from Pu to Pd. Reverse flow handled by swapping and negating.
%
%   Takes b_crit and rho0 as SCALARS rather than the whole parameter struct.
%   This is called ~7 million times per cycle, and resolving two struct fields
%   on every call was pure overhead. The arithmetic is unchanged.
if C <= 0; q = 0; return; end
sgn = 1;
if Pd > Pu; tmp = Pu; Pu = Pd; Pd = tmp; sgn = -1; end
if Pu <= 1; q = 0; return; end
r = Pd/Pu;
if r <= b
    f = 1;                                   % choked
else
    z = (r - b)/(1 - b);
    f = sqrt(max(0, 1 - z*z));               % subsonic
end
q = sgn * C * rho0 * Pu * f;
end

% =========================================================================
function F = contact_hc(pen, rate, k, lam)
%CONTACT_HC  Hunt-Crossley normal contact force [N].
%   F = k*pen + lam*pen*rate, clamped to F >= 0.
%   Damping scales with penetration, so it vanishes continuously at
%   separation and dissipates on BOTH approach and rebound, and the clamp
%   forbids adhesive tension. A one-sided Kelvin-Voigt damper was used
%   first; it is undamped on rebound and was rejected (see equation audit).
if pen <= 0; F = 0; return; end
F = k*pen + lam*pen*rate;
if F < 0; F = 0; end
end
