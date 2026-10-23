function P = FactoryParams()
%FACTORYPARAMS  Central parameter definition for the multi-station factory model.
%
%   All engineering parameters live here. Nothing physical may be hard-coded
%   anywhere else in the model, and no manufacturer figure may be written
%   here - manufacturer figures live in JANATICSDATA and are read from it.
%
%       JanaticsData.m -> FactoryParams.m -> initialize_factory.m
%                                         -> factory_derivatives.m
%
%   PROVENANCE TAGS - every value carries one. Never remove them.
%     [JAN] Janatics manufacturer figure, read from JANATICSDATA
%     [COMM] commissioning setting (a knob on the machine, not a component)
%     [REF] taken from the reference layout script
%            (function multi_station_simulation().txt)
%     [ASM] engineering assumption - NOT in any source
%     [CAL] calculated from other parameters
%     [EST] engineering estimate from typical component data
%     [PLH] placeholder - must be replaced with real data
%     [PLC] OBSERVED on the real machine's PLC. Read from PLCTAGLIST or from
%           the live snapshot in plc/plc_snapshot.json.
%     [MEAS] MEASURED on the real machine by hand - tape measure, scales,
%           gauge. Supplied 2026-08-25 in Physics_Framework.xlsx.
%
%   [PLC] and [MEAS] are the only values in this file that are FACTS about the
%   installed cell. Everything else is assumed, estimated or provisional.
%
%   IMPORTANT 1. Sequence.xlsx contains a "Governing Physics Equation" column
%   which is COMPLETELY EMPTY, and contains no numerical data of any kind.
%   Sequence.xlsx is authoritative for SEQUENCE and TOPOLOGY only.
%
%   IMPORTANT 2. Every [JAN] value is PROVISIONAL. No nameplate, BOM or
%   purchase record for the installed equipment has ever been supplied. See
%   the confirmation-status block at the top of JANATICSDATA.
%
%   Units are strict SI: m, kg, s, N, Pa, rad, K.
%
%   See also JANATICSDATA, INITIALIZE_FACTORY, RUN_FACTORY_SIMULATION.

J = JanaticsData();
P.JAN = J;              % the whole register travels with the parameter set

%% ---- 1. Environment -----------------------------------------------------
P.g        = 9.80665;   % [ASM] gravitational acceleration          m/s^2
% ROOM AIR, plan H8 2026-09-13: 25 C measured at the cell on 2026-09-10.
% It was 293.15 K (20 C), an assumption. One reading at one time of day,
% so it is a fact about that afternoon, not a controlled temperature.
P.T_air    = 298.15;    % [MEAS] air temperature (isothermal)       K
P.R_air    = 287.05;    % [ASM] specific gas constant, dry air      J/(kg*K)
P.n_poly   = 1.30;      % [ASM] polytropic index, cylinder chamber  -
P.P_atm    = 101325;    % [ASM] ambient pressure                    Pa
P.rho0     = 1.185;     % [ASM] ISO 6358 reference density          kg/m^3
P.b_crit   = 0.40;      % [ASM] ISO 6358 critical pressure ratio    -

%% ---- 2. Geometry scale --------------------------------------------------
% The reference script labels its axes "m" but draws a 17 x 13 cell holding a
% 0.6 "m" cube. At face value that is a 583 kg workpiece pushed by pneumatic
% cylinders - not credible. The drawing is treated as a SCHEMATIC and scaled.
% SCALE = 0.10 yields a 60 mm workpiece in a 1.7 x 1.3 m cell.
% Set SCALE = 1.0 to interpret the drawing literally (see Known Issues).
P.SCALE    = 0.10;      % [ASM] drawing unit -> metre               m/unit

%% ---- 3. Workpiece -------------------------------------------------------
% Three separate extents, not one edge, because the part is a CUBOID.
%
% 100 x 100 x 40 mm of wood.
%
% L and W are READ FROM THE CAD: Box_50MM.STEP measures 100.00 x 100.00 mm in
% plan. Its bounding box looks larger because the part sits in assembly
% coordinates - the block spans X -398.16..-298.16, Y 307.83..407.83.
%
% H = 40 mm is MEASURED IN THE LAB and takes precedence over the CAD's 50 mm
% block. The cell runs several thicknesses; 40 is the one on the machine.
%
% Confirmed three further ways, which is why this is not a lone reading:
%   - Magazine.STEP has four 5 mm dividers making FIVE slots of 105-110 mm,
%     115 mm deep, 305 mm tall. A 100 mm block fits with normal clearance.
%   - The PLC's magazine_inventory.json reports five columns of six - the same
%     five slots, from the live machine rather than the CAD.
%   - The annotated layout labels the blocks 100 x 100 x (25,35,45,55,65).
%     Neither 40 nor 50 is in that list, so the list is not exhaustive.
%
% What this replaces: the drawing's 0.6-unit block, which at SCALE = 0.10 gave
% a 60 mm aluminium cube of 0.583 kg. The drawing does not draw the part to
% scale. The real block is 0.300 kg - 1.94x lighter, and a cuboid.
%
% Axis convention: L is the x extent, W the y extent, H the z extent. The plant
% is 2-D in x and y, so H reaches the physics only through the mass.
P.blk_L    = 0.100;                % [CAD] Box_50MM.STEP, X extent   m
P.blk_W    = 0.100;                % [CAD] Box_50MM.STEP, Y extent   m
P.blk_H    = 0.040;                % [MEAS] measured in the lab      m
% CONFIRMED 2026-08-26 BY WEIGHING. A block came in at 0.300 kg, and
% 0.300 / (0.100 x 0.100 x 0.040) = 750 kg/m^3 exactly. Density had been the
% last unconfirmed part of the workpiece - it scales the mass, and so every
% friction and inertia term - and one reading closed it.
P.blk_rho  = 750;                  % [MEAS] wood, weighed            kg/m^3
P.blk_m    = P.blk_rho*P.blk_L*P.blk_W*P.blk_H;   % [CAL] mass      kg
% About the vertical axis through the centroid. Cuboid form; for a cube it
% reduces to m*a^2/6, which is what this line read before the measurement.
% Still computed and still used nowhere - no orientation state exists.
P.blk_J    = P.blk_m*(P.blk_L^2 + P.blk_W^2)/12;  % [CAL] inertia   kg*m^2
P.mu_s     = 0.40;      % [EST] static friction, block/steel        -
P.mu_k     = 0.35;      % [EST] kinetic friction, block/steel       -
P.v_creep  = 2.0e-3;    % [ASM] friction regularisation velocity    m/s

%% ---- 4. Pneumatic supply ------------------------------------------------
% Compressor and receiver are NOT Janatics equipment and are not identified.
P.V_res     = 5.0e-3;   % [EST] receiver volume                     m^3
% MEASURED, APPLIED 2026-09-08. The cell's supply sits at 4.03-4.38 bar gauge
% across 37 samples spanning ten real cycles, and all four regulator faces read
% 4.3 by eye. The model ran 5.5e5 Pa absolute - 4.487 bar gauge - which is
% close, and 6.0 bar gauge at the regulator, which is not. NEXT_STEPS F6.
%
% Both numbers below now start the model where the machine starts. This is the
% first time the pneumatic SUPPLY has been set from measurement rather than
% assumption; every actuator force in the model scales with it.
%
% The COMPRESSOR SWITCH IS NOT TOUCHED. P_cut_in / P_cut_out stay [ASM] at
% 6.0 / 8.0 bar because nobody has read the dial, and the recorded 4.38 bar
% ceiling is the transmitter's view of the common supply, which sits
% downstream of the regulator - it does not tell us what the receiver does.
% Setting the switch from a downstream reading would be inventing a number to
% match a symptom. INPUTS_REQUIRED still asks for the dial.
P.P_res_0   = 4.3e5 + 101325;  % [PLC] receiver at t = 0, 4.3 bar g   Pa
P.P_cut_in  = 6.0e5;    % [ASM] compressor pressure switch, cut-in  Pa
P.P_cut_out = 8.0e5;    % [ASM] compressor pressure switch, cut-out Pa
P.mdot_pump = 3.0e-3;   % [EST] compressor mass delivery            kg/s
P.P_ready   = 6.5e5;    % [ASM] receiver "ready" threshold          Pa
P.P_relief  = 9.0e5;    % [ASM] receiver relief valve set point     Pa
P.C_relief  = 5.0e-8;   % [EST] relief valve sonic conductance      m^3/(s*Pa)

% --- Janatics FRL (air preparation) -------------------------------------
% Iteration 01 had NO regulator: every actuator saw the raw receiver
% pressure cycling between the 6.0 and 8.0 bar switch settings, so rod force
% cycled with it. A real cell always regulates.
% REGULATOR SET POINT, measured 2026-09-08. J.FRL.p_set is the Janatics
% catalogue's assumed 6.0 bar commissioning value and is left alone in the
% register; what the cell is actually SET to is 4.3 bar gauge, read off all
% four regulator faces and corroborated by 37 samples of the PLC's own supply
% transmitter. A set point is a knob, not a component property, so measuring
% it overrides the catalogue without contradicting it.
P.P_set     = 4.3e5 + P.P_atm;  % [PLC] regulator set point (abs)  Pa

% BRANCH-CHARGED THRESHOLD, made relative 2026-09-08. This was a free-standing
% 5.5e5 Pa ABSOLUTE, sized when the regulator was assumed to be 6.0 bar gauge.
% Dropping the regulator to its measured 4.3 bar put the set point at 5.32e5
% absolute - BELOW this threshold - so BR_RDY could never become true, and the
% cycle stalled against the simulation horizon having moved 0.756 NL of air.
% Nothing was wrong with the pressure measurement; the guard was expressed in
% units that could not follow it.
%
% It is now a FRACTION OF THE REGULATED SUPPLY, which is what it always meant:
% "this branch has charged close enough to the supply to actuate". A regulator
% change can no longer leave it behind.
%
% The fraction reproduces the old absolute value at the old set point - 0.75 x
% 6.0 bar + atm = 5.513e5 against the old 5.5e5, 0.24% apart - so the guard's
% STRICTNESS is unchanged and only the pressure moved. One change at a time.
P.P_br_frac = 0.75;     % [ASM] branch-charged fraction of set pressure  -
P.P_br_rdy  = P.P_atm + P.P_br_frac*(P.P_set - P.P_atm);  % [CAL]        Pa
P.C_dv      = J.C.frl;  % [JAN] FRL + supply line conductance       m^3/(s*Pa)
P.tau_dv    = 0.030;    % [EST] distribution valve response time    s
P.V_branch  = 1.0e-4;   % [EST] branch manifold + tubing volume     m^3

%% ---- 5. Cylinders (nominal bore 20 - see the note, it is NOT the cell) --
% WHICH cylinders, how many, which coil drives each and which valve type each
% carries is NOT here - it is in FACTORY_ACTUATORS, which holds the machine's
% eleven pneumatic actuators on thirteen coils. What is here is the per-
% cylinder physics they all share.
%
% THE BORE 20 BELOW IS NOT THE CELL'S BORE AND NO LONGER DRIVES THE PHYSICS.
% Section 13B records that the CAD measures bore 8 and bore 32; section 13J
% records two nameplates read at the machine, bore 32 and bore 25. Bore 20
% appears in none of them. Since 2026-09-02 the physics has read a PER-ACTUATOR
% bore from FACTORY_ACTUATORS (P.CYL(c).A_A / A_B), and since 2026-09-07 CYL_A
% carries its real 32 / 12 from a nameplate. The remaining ten rows still carry
% the [JAN] 20 / 8 below, because their barrels have not been read.
% [SUPERSEDED 2026-09-13, plan H7: every row now carries its nameplate bore -
% A51/A52 25 / 10, A12/A28 32 / 12 - and its stamped stroke. The 20 / 8 below
% is the nominal pair only.]
%
% P.D_bore, P.d_rod, P.A_A and P.A_B therefore survive as the NOMINAL pair and
% nothing else: VERIFY_MODEL pins them, PARAMETERSTEST checks their algebra,
% and the Janatics catalogue cross-check (142 N on the annulus at 6 bar) reads
% them. They are a fixed reference point, not a description of the machine.
% Do not reach for them to get a cylinder's area - reach for P.CYL(c).
P.D_bore  = J.CYL.bore;   % [JAN] bore diameter                     m
P.d_rod   = J.CYL.rod;    % [JAN] rod diameter                      m
P.A_A     = pi*P.D_bore^2/4;                % [CAL] cap-side area   m^2
P.A_B     = pi*(P.D_bore^2 - P.d_rod^2)/4;  % [CAL] rod-side area   m^2
P.m_pist  = J.CYL.m_moving;  % [EST] piston + rod moving mass       kg
P.V_dead  = J.CYL.V_dead;    % [EST] dead volume (port + cushion)   m^3
P.strokes = J.CYL.strokes;   % [JAN] standard stroke ladder         m
P.p_max   = J.CYL.p_max;     % [JAN] max working pressure (gauge)   Pa

% --- Janatics pneumatic circuit, per cylinder port ----------------------
% Circuit:  FRL -> manifold -> DS2 5/2 valve -> GR flow control -> cylinder
% Supply passes the GR free-flow check; exhaust passes the GR needle.
% METER-OUT. Iteration 01 metered IN, which is why it needed C_in = 2.5e-10,
% 66x below the real DS2 valve: the restriction it was modelling was never
% the valve, it was the speed controller.
P.C_sup   = J.C.supply;       % [JAN] DS2 + GR check, in series     m^3/(s*Pa)
P.C_ctrl_B= J.C.exh_extend;   % [COMM] vent B -> sets EXTEND speed  m^3/(s*Pa)
P.C_ctrl_A= J.C.exh_retract;  % [COMM] vent A -> sets RETRACT speed m^3/(s*Pa)
P.tau_sv  = J.VAL.tau;        % [EST] 5/2 spool response (not published) s

% --- friction ------------------------------------------------------------
% Janatics rates output force at 0.90*P*A, i.e. the loss scales WITH the
% driving load, so a fixed Coulomb force cannot reproduce the catalogue.
P.f_loss  = 1 - J.CYL.f_eff;  % [JAN] load-proportional loss        -
P.F_coul0 = 2.0;        % [EST] unpressurised breakaway friction    N
P.c_visc  = 15.0;       % [EST] cylinder viscous friction           N*s/m
P.v_eps   = 1.0e-3;     % [ASM] friction regularisation velocity    m/s
P.gap_app = 0.005;      % [ASM] rod-tip to workpiece approach gap   m

%% ---- 6. Contact models (Hunt-Crossley) ---------------------------------
% F = k*delta + lambda*delta*delta_dot , clamped to F >= 0.
P.k_end    = 2.0e5;     % [ASM] cylinder end-stop stiffness         N/m
P.lam_end  = 1.0e6;     % [ASM] cylinder end-stop H-C damping       N*s/m^2
% The end stop above acts on the PISTON. The four below act on the WORKPIECE.
%
% These are the ORIGINAL values and they are correct for the agreed 0.375 kg
% block: the contact period is 12.2 ms, giving 24.3 solver steps per period at
% dt = 5e-4, against 30.3 for the old 0.583 kg cube. Comfortable.
%
% Worth recording because it cost a day. A workpiece figure of 0.300 g was
% briefly taken as real, and at that mass these stiffnesses are wildly out of
% proportion to anything the part can feel - its whole friction load would be
% 0.0012 N - which makes the unilateral contact chatter against a piston 400x
% its mass. The cycle then diverges at every dt from 5e-4 down to 2e-5. That
% whole failure mode was an artefact of the wrong mass, not a defect here.
P.k_ct     = 1.0e5;     % [ASM] rod/workpiece contact stiffness     N/m
P.lam_ct   = 5.0e5;     % [ASM] rod/workpiece H-C damping           N*s/m^2
P.k_stop   = 5.0e4;     % [ASM] locating-stop stiffness             N/m
P.lam_stop = 5.0e5;     % [ASM] locating-stop H-C damping           N*s/m^2

%% ---- 7. Conveyors (NOT Janatics equipment - generic) -------------------
% THE DRIVES ARE STEPPERS. Three sources now agree: the PLC carries three
% Stepper Technology Objects and the outputs pul+ / dir+ / pot_1_pulse+ (13C),
% the owner says the belts are driven by electric motors (13E), and a motor
% nameplate photographed at the cell reads JK42HS34-1334, a NEMA 17 hybrid
% stepper (13J). Anywhere this project still describes the drives as "generic
% 3-phase", that description is wrong.
%
% The seven numbers below did NOT move on the strength of that nameplate, and
% 13J section 5 gives the reason at length: they are a self-consistent set of
% assumptions - a 20:1 ratio sized against a 0.050 N*m motor - and dropping one
% real figure into it would make the set less coherent rather than more. The
% photograph also does not say which of the cell's four stepper axes it was
% taken on. This subsystem is measured together or not at all.
P.r_pul    = 0.020;     % [ASM] drive pulley radius                 m
P.N_gear   = 20.0;      % [ASM] gearbox reduction ratio             -
P.eta_gb   = 0.90;      % [EST] gearbox efficiency                  -
P.J_mot    = 1.0e-6;    % [EST] motor rotor inertia                 kg*m^2
P.J_pul    = 2.0e-5;    % [EST] pulley + belt inertia at pulley     kg*m^2
P.T_max    = 0.050;     % [EST] motor torque limit                  N*m
P.b_visc   = 2.0e-4;    % [EST] drivetrain viscous friction         N*m*s/rad
P.T_coul   = 3.0e-3;    % [EST] drivetrain Coulomb friction         N*m
P.Kp_cv    = 0.030;     % [ASM] speed loop proportional gain        N*m*s/rad
P.Ki_cv    = 0.200;     % [ASM] speed loop integral gain            N*m/rad
% Belt speed is PER CONVEYOR, because the machine's is: it carries three
% Pot_Control axes, each with its own Set_Velocity. Index it as P.v_belt(i);
% do not assume it is scalar.
%
% THE STRUCTURE IS OBSERVED. THE NUMBER IS NOT. This was briefly tagged [PLC]
% on 2026-09-06, on the grounds that the 2026-09-01 recording showed all three
% axes at 0.150. That recording is the SCADA application's built-in SIMULATOR,
% which seeds exactly this value - simulator.py line 92,
% `self._write("conveyor.%d.set_velocity" % i, 0.15)`. The 0.150 in the trace
% is this model's own assumption handed back to it. See 13I.
%
% The real controller reads Set_Velocity = 180.0 on all three axes, in a unit
% the technology object does not state. 180.0 is NOT 0.150 m/s in any obvious
% reading, and converting it without knowing the unit is exactly the kind of
% guess this project does not make. It stays [ASM] until a belt is timed over a
% measured distance - INPUTS_REQUIRED section 4.4, lab item A10.
P.v_belt   = [0.150 0.150 0.150];   % [ASM] per-conveyor speed set point  m/s
% [2026-09-12, plan H4: TWO OF THE THREE ARE NOW TIMED.] The [ASM] line above
% is the default and now stands for BELT 3 alone, which no usable recording
% has timed (one cycle, sampled once a second). Belts 1 and 2 are overwritten
% below. Neither is converted from Set_Velocity = 180: both are timed over
% measured distances, as the paragraph above asked.
%   Belt 1: leading edges over the 110 mm magazine pitch, four automatic
%   cycles on 2026-09-10 - three or four pitches per cycle at ~0.21 m/s, the
%   odd slow one a one-sample logging artefact (round-3 review section 3).
%   Belt 2: the maintainer's tape, 75 cm in ~2.4 s, forward only, n=1. The
%   automatic cycles bound it from below: px6 -> px8, 67 cm, in 2.09-2.34 s
%   INCLUDING the transfer push, so at least 0.27 m/s on the belt.
% Tagged separately because their sources differ: the recorder for belt 1,
% the tape for belt 2.
P.v_belt(1) = 0.210;   % [PLC] belt 1, recorded sensor pitch, 4 cycles    m/s
P.v_belt(2) = 0.310;   % [MEAS] belt 2, tape 75 cm in ~2.4 s, n=1         m/s
P.a_belt   = 0.400;     % [ASM] drive accel/decel ramp limit        m/s^2
P.om_eps   = 0.05;      % [ASM] drivetrain friction regularisation  rad/s

%% ---- 8. Engraving base (ELECTRIC vertical axis) ------------------------
% Sequence.xlsx step 25 is "PLC -> Engraving Base" with NO valve in the
% chain, unlike every actuator. The base is therefore NOT pneumatic and no
% Janatics component applies to it.
% THE AXIS IS JOGGED, NOT DRIVEN TO A POSITION. The PLC listing is explicit:
% Axis_1 runs at a commanded VELOCITY (72.0, unit unstated) until a limit
% switch trips - %I1.0 upper, %I1.2 lower. There is no position setpoint
% anywhere in the program, and the controller has no way to know where the
% platform is between the two switches.
%
% This was modelled as a stiff position PID to P.z_top until 2026-09-08, which
% put the whole travel at 0.225 s against a MEASURED 7.7-8.3 s per direction
% in every recorded real cycle - about 35x too fast, and roughly 15 s of the
% cell's ~41 s cycle-time gap. NEXT_STEPS F2.
%
% WHAT IS OBSERVED IS THE TIME, NOT THE DISTANCE. Nobody has measured the
% platform stroke, so P.z_top stays [ASM]; the travel time is [REC] and the
% jog speed is derived from the two. If the stroke is ever measured, correct
% z_top and the travel time stays right, which is the way round that matches
% the evidence.
P.m_base   = 2.00;      % [EST] moving base mass                    kg
P.z_top    = 0.050;     % [ASM] engraving working height            m
% UP AND DOWN ARE NOT THE SAME, measured 2026-09-08 over seven real cycles:
% 7.785 s rising and 8.166 s falling, with standard deviations of 0.079 and
% 0.107 s. The 8.0 s applied on 2026-09-08 was the right number and the wrong
% shape - it was a single figure standing for a range nobody had split yet.
%
% A screw axis being slower DOWN than UP is the interesting part, because
% gravity assists the descent. That points at the drive holding the platform
% back on the way down rather than letting it run, which is what a stepper
% jogged at a fixed velocity does in both directions. It is consistent with
% the axis being velocity-commanded rather than falling under its own weight,
% and it is a second, independent sign that the jog model is the right shape.
%
% Index it as P.t_base_travel(1) rising, (2) falling. Do not assume scalar.
P.t_base_travel = [7.785 8.166];  % [PLC] limit-to-limit, up / down  s
P.v_base_jog = P.z_top ./ P.t_base_travel;  % [CAL] jog speed, up/down m/s
P.Kd_bz    = 2.0e2;     % [ASM] axis velocity-loop gain             N*s/m
P.Ki_bz    = 2.0e3;     % [ASM] axis velocity-loop integral gain    N/s
P.Kp_bz    = 4.0e3;     % [ASM] HISTORICAL position gain            N/m
P.F_ax_max = 200;       % [EST] axis force limit                    N
% Kd_bz and Ki_bz now close a VELOCITY loop on the jog setpoint; the limit
% switches in FACTORY_SENSORS stop the motion, exactly as %I1.0 / %I1.2 do.
% Kp_bz belongs to the superseded position loop and is kept for one reason:
% PLCIOLATENCYTEST rebuilds the pre-2026-09-08 axis to reproduce reference
% figures measured on it, the same way it rebuilds the old workpiece and the
% five-cylinder plant. See P.base_variant in INITIALIZE_FACTORY.
%
% t_base_travel is [PLC] and not [REC]: it is read from the machine's own
% %I1.0 / %I1.2 limit inputs in recorded cycles, which is what [PLC] means.
% [REC] is used in the intake sheet but is NOT a provenance tag in this
% project - AUDIT_PROVENANCE would not have counted it.

%% ---- 9. Sensors --------------------------------------------------------
P.prox_rng = 0.030;     % [EST] proximity sensor detection radius   m
P.z_tol    = 1.0e-3;    % [EST] height sensor tolerance             m
P.ext_tol  = J.REED.repeat; % [EST] reed-switch trip window         m
P.t_scan   = 0.010;     % [ASM] PLC scan period                     s

% PLC OUTPUT LATENCY - how long after reading its inputs the PLC writes its
% outputs to the physical actuators, expressed in whole scans.
%
% A real PLC scan is read-inputs -> execute -> write-outputs, all inside one
% scan period, so the true latency is T_exec/t_scan and lies in [0, 1]. The
% two limiting cases are the only ones a scan-quantised model can express:
%
%   0  outputs land in the SAME scan the inputs were read (T_exec -> 0).
%      This is what RUN_FACTORY_SIMULATION has always done.
%   1  outputs land at the START OF THE NEXT scan (T_exec -> t_scan).
%      This is what the Simulink path did implicitly, because
%      FACTORY_PLC_SFUN ran its scan in Update but emitted from Outputs.
%
% That undeclared mismatch WAS open issue 3: it delayed every command by one
% scan on the Simulink path only, accumulating once per physics-gated
% transition to 0.300 s (exactly 30 scans) and 0.486 mm by S39_CYCLE_COMPLETE.
% Both paths now read this parameter, so they agree at either setting.
%
% MEASUREMENT REQUIRED: the real cell's scan execution time. Until it is
% measured, 0 is the documented default because it is what every pinned
% reference value in VERIFY_MODEL and CYCLEREGRESSIONTEST was baselined on.
% See Project_Notes/NEXT_STEPS.md.
P.plc_io_delay = 0;     % [ASM] PLC output latency, whole scans     -

%% ---- 10. Process timing ------------------------------------------------
% Sequence.xlsx steps 27-29 are MANUAL operator actions and give NO duration.
% These are placeholders. Replace with measured operator data.
P.t_op_notice  = 3.0;   % [PLH] operator reaction to notification   s
P.t_engrave    = 8.0;   % [PLH] manual engraving duration           s
P.t_op_confirm = 1.5;   % [PLH] operator confirm-finish delay       s

% ---- THE OPERATOR IS A DISTRIBUTION, NOT A CONSTANT ---------------------
%
% The three placeholders above are one number each. The real operator is not.
% Seven real cycles put the platform's dwell at the top - which is notice plus
% engrave plus confirm, the whole human contribution - at:
%
%     5.950  7.281  8.968  13.217  16.252  17.533  28.649   seconds
%
%     mean 13.979   median 13.217   sd 7.832   min 5.950   max 28.649
%
% The spread is the finding. A standard deviation of 7.8 s on a mean of 14 is
% not measurement noise, it is the process: somebody notices a lamp, engraves a
% block by hand, and presses a button. The slowest cycle took nearly FIVE TIMES
% the fastest.
%
% WHY THIS IS SAMPLED EMPIRICALLY AND NOT FITTED. With n = 7 you cannot honestly
% fit a lognormal and quote its parameters - the shape would be an artefact of
% seven points. So the model DRAWS FROM THE SEVEN OBSERVED VALUES. That is a
% weaker claim and a true one: the model does what the machine was seen to do.
% If a wider recording arrives, extend P.OP.samples and nothing else changes.
P.OP.samples = ...       % [PLC] platform dwell at top, seven real cycles   s
    [5.950 7.281 8.968 13.217 16.252 17.533 28.649];
P.OP.confirm = 1.297;    % [PLC] button press -> platform moves, n=1        s
%
% THE SPLIT IS STILL A PLACEHOLDER, and this must not be blurred. What is
% MEASURED is the TOTAL dwell (n=7) and the confirm delay (n=1). How the
% remainder divides between "noticing" and "engraving" was observed ONCE, and
% one observation cannot support a ratio. So the model keeps its original 3:8
% split of whatever is left after the confirm. Only a stopwatch splits it -
% LAB_DAY_RUNBOOK block A3 asks for exactly that.
P.OP.notice_frac = 3/11; % [PLH] share of the non-confirm dwell            -
%
% [2026-09-13, the user: the seven dwells above were recorded while the
% engraver was NOT working, so they are not engraving processes. They stay
% the operator distribution for now, but read them as "the platform held at
% the top with the laser idle", not as engraving times.]
%
% THE LASER TIME, for the manual-input mode only (RUN_FACTORY_SIMULATION
% 'Operator','console'). The console waits this long in real time while the
% laser runs, then asks for ENG DONE. It is a PLACEHOLDER, chosen 2026-09-13
% and to be replaced once the laser is timed at the cell (laser on to off,
% per job). What bounds it:
%   - Wood Carving.mp4, the only footage with the laser visibly on: at least
%     6.1 s of footage, about 3.0 s of machine time at the promo's measured
%     ~2x slow-down (VIDEO_REFERENCE section 2).
%   - The fastest recorded dwell, 5.95 s less the 1.297 s confirm, gave this
%     4.65 s as a ceiling. Given the note above, that ceiling rests on cycles
%     in which the laser did not run, so it bounds nothing. 4.65 s is kept
%     because the user chose it, not because the data forces it.
% Only the 50 mm job: no 25 mm engraving has ever been recorded. The
% automatic run does not read this value, so no pinned figure depends on it.
% [2026-09-15, the user: the laser takes a different time for each job, so
% for now this can only be an assumption. One stopwatch reading will not
% settle it. Time several engravings of each job and keep the spread
% (Project_Notes/LAB_VISIT_2026-09-16.md).]
P.OP.t_laser_50 = 4.65;  % [PLH] laser time, 50 mm job, manual mode only   s

% MODE. 'nominal' is DETERMINISTIC and is the default, because every pinned
% reference value in this project was measured on it and a stochastic model
% cannot be regression-tested. 'sample' draws one dwell per run from
% P.OP.samples and is what produces a cycle-time DISTRIBUTION.
%
% The nominal 12.5 s is 1.48 s below the measured mean of 13.979. It is left
% alone on purpose: moving it would re-baseline the whole project for a fifth
% time in two days, and the honest prediction is the distribution rather than
% any single number. OPERATOR_DISTRIBUTION reports the distribution; the
% nominal is a REGRESSION ANCHOR, not a forecast. Do not quote it as one.
% MODE, declared here so that anything reading P can tell which it has. The
% default is DETERMINISTIC and must stay that way: every pinned reference value
% in this project was measured on it, and a stochastic model cannot be
% regression-tested. FACTORY_OPERATOR_DRAW sets these to 'sample' on the copy
% it returns.
%
% The nominal 12.5 s is 1.48 s BELOW the measured mean of 13.979. It is left
% alone on purpose - moving it re-baselines every pinned cycle time - and the
% honest prediction is the DISTRIBUTION, which OPERATOR_DISTRIBUTION reports.
% The nominal is a regression anchor, not a forecast. Do not quote it as one.
P.op_mode = 'nominal';   % [ASM] 'nominal' | 'sample' | 'interactive'      -
P.op_seed = 0;           % [ASM] seed used when a draw is taken            -

% FACTORYPARAMS ITSELF NEVER SAMPLES, and that is deliberate. It takes no
% arguments and half the project calls it expecting the same struct every time;
% a parameter file that returned a different answer per call would be a trap.
% The draw lives in FACTORY_OPERATOR_DRAW, which takes P and a seed and hands
% back P with the three operator times replaced. See OPERATOR_DISTRIBUTION for
% the Monte Carlo that uses it.
P.t_timeout    = 30.0;  % [ASM] PLC per-state watchdog timeout      s

%% ---- 11. Solver --------------------------------------------------------
% VERIFIED STABILITY LIMIT, RE-VERIFIED 2026-08-26 against the agreed
% 100 x 100 x 50 mm workpiece.
%
% RK4 on this system diverged to NaN at dt = 1.0e-3 and was stable through
% 8.3e-4 with the old 0.583 kg cube, so 5.0e-4 carried ~1.7x margin. At the
% real 0.375 kg block the step is CONVERGED, measured three ways - final
% workpiece x, in metres:
%     dt = 5.0e-4    1.509291      cycle 31.0350 s
%     dt = 2.5e-4    1.509293      cycle 31.0350 s
%     dt = 1.0e-4    1.509292      cycle 31.0350 s
% Halving or quartering it moves the result by 2e-6 m. DO NOT RAISE IT, and
% there is nothing to gain by lowering it.
P.dt      = 5.0e-4;     % [CAL] fixed integration step (RK4)        s
P.t_max   = 120.0;      % [ASM] simulation time limit               s
                        %       Raised 90 -> 120 on 2026-09-12: the T#10S
                        %       start delay (plan H2) put a full cycle with
                        %       the slowest observed operator (28.65 s) at
                        %       ~94.2 s, past 90. The saved .slx was rebuilt
                        %       with it, since StopTime is baked in at build.
                        %       Was 45.0, which the jogged engraving axis
                        %       overran on 2026-09-08 - the cycle stalled in
                        %       S34 with the horizon, not the plant, stopping
                        %       it. Raised with the real cell's 69-90 s cycles
                        %       in view, so a faithful model has room to
                        %       finish. This is a HORIZON, not a timeout: the
                        %       per-state watchdogs are unchanged.

%% ---- 12. OBSERVED FROM THE REAL MACHINE ---------------------------------
% Everything above this line is assumed, estimated or provisional. Everything
% in P.REAL was read off the installed cell's PLC on 2026-08-24 and is fact.
%
% IT IS RECORDED, NOT APPLIED. The model above still runs on its original
% assumptions, deliberately: adopting these figures changes every pinned
% reference value, and several of them cannot be applied correctly until the
% PLC-to-actuator mapping is known (see FACTORY_IO_MAP - 23 of its rows are
% UNMAPPED). Applying half a re-model would be worse than none.
%
% Where P.REAL contradicts the model, the model is what is wrong.

% --- I/O counts. The model is built for far fewer channels than exist. ---
P.REAL.n_prox     = 10;     % [PLC] proximity sensors  (model has 10)
P.REAL.n_solenoid = 13;     % [PLC] solenoid coils     (model has 13)
P.REAL.n_conveyor = 3;      % [PLC] conveyor drives    (model has 3 - agrees)
P.REAL.n_magazine = 5;      % [PLC] feed compartments  (model has 5 pushers,
%                           %       no stock model - see INPUTS_REQUIRED)

% --- Two ENGRAVING JOBS are run, not two workpiece sizes -----------------
% CORRECTED 2026-08-25. First recorded here as two product dimensions and
% described as "the FIRST real length anywhere in this project". That was
% wrong. The user confirms 25 and 50 mm are HOW MUCH ENGRAVING IS DONE - the
% engraving length. They say nothing about the workpiece and do not help
% settle P.SCALE, which stays fully blocked.
%
% What they do expose is a real defect: P.t_engrave below is ONE invented
% duration, yet the machine runs two engraving jobs of different length, and a
% 50 mm engrave cannot take as long as a 25 mm one. The fix is not two timers -
% the PLC publishes Engraving_Completed, so the state should be sensor-driven
% like every other state in this sequence.
P.REAL.engrave_mm = [25 50];  % [PLC] Productqty_25mm / Productqty_50mm

% --- Magazine capacity ---------------------------------------------------
% 30 in total across the 5 columns, so 6 per column. Consistent with the live
% snapshot in plc/magazine_inventory.json, whose largest column reads 6.
P.REAL.magazine_total  = 30;  % [PLC] blocks held across all columns
P.REAL.magazine_perCol = 6;   % [PLC] confirmed 2026-08-25, 6 per column

% --- Engraving completion is a PERSON, not a sensor -----------------------
% Confirmed 2026-08-25: the operator presses a button, and that sets
% System.Engraving_Completed. So the engraving duration is not a machine
% property at all - it is human work time, and human work time has SPREAD.
%
% This is why P.t_engrave below cannot be fixed by measuring it once. It needs
% a mean and a spread, for EACH of the two engraving lengths in
% P.REAL.engrave_mm, because a 50 mm engrave takes longer than a 25 mm one.
%
% And it is why the model must stop implying it can predict CYCLE time. Of the
% 33.84 s cycle, 12.5 s is operator-paced. The honest predicted quantity is
% MACHINE time, about 21.34 s, with an operator distribution on top.
P.REAL.engrave_is_manual = true;   % [PLC] Engraving_Completed is operator-driven

% --- Supply pressure, live snapshot ---------------------------------------
% Single reading from plc/plc_snapshot.json, operating point unknown. The
% model assumes P_res_0 = 5.5 bar and regulates to 6.0 bar, both [ASM].
P.REAL.P_supply_bar = 4.315;  % [PLC] Analog_inputs.Pressure.Value

% --- Conveyor axes are POSITION controlled, not velocity controlled -------
% Pot_Control exposes Goto_Position, Set_Home, Axis_Homed_Fb and encoder
% position and velocity feedback, with separate high and low speed profiles.
% The model drives them as free-running belts with a PI velocity loop. That
% is a structural difference, not a parameter one.
P.REAL.axis_position_controlled = true;   % [PLC] Pot_Control.*
P.REAL.axis_position_snapshot   = [30 30 30];  % [PLC] Current_Position_Fb, units unknown

% --- Engraving completion is a SIGNAL, not a timer ------------------------
% P.t_engrave below is [PLH] - 8 s of invented time, the largest single piece
% of guesswork in the cycle. The machine publishes Engraving_Completed.
P.REAL.engrave_has_done_signal = true;    % [PLC] System.Engraving_Completed

% --- Safety and start interlocks the model has none of --------------------
P.REAL.interlocks = {'Air_Pressure_ok','ENGV_Plate_Home', ...
                     'All_Cylinders_Home','Emergency Healthy'};  % [PLC]

%% ---- 13. MEASURED ON THE REAL MACHINE, 2026-08-25 -----------------------
% Supplied by hand in Physics_Framework.xlsx. RECORDED, NOT
% APPLIED - see the note at the end of this block.

P.MEAS.conveyor_mm   = [760 760 760];  % [MEAS] belt length, each conveyor
P.MEAS.blk_L_mm      = 10;             % [MEAS] workpiece length
P.MEAS.blk_W_mm      = 10;             % [MEAS] workpiece width
P.MEAS.blk_H_mm      = 4;              % [MEAS] workpiece height
P.MEAS.blk_rho       = 750;            % [MEAS] wood density          kg/m^3
P.MEAS.P_res_0_bar   = 4.3;            % [MEAS] receiver at cycle start
P.MEAS.prox_rated_mm = 125;            % [MEAS] proximity sensor RATED MAXIMUM

% --- SCALE IS CONFIRMED CORRECT. The project was wrong about what was wrong.
% Conveyor 1 is drawn 7.6 units wide in the reference layout and measures
% 760 mm, so SCALE = 0.760/7.6 = 0.1000 m/unit EXACTLY - the value P.SCALE has
% held all along. The cell really is 1.70 x 1.30 m.
%
% Open issue 1 has said since session 1 that "SCALE is confirmed wrong" and
% treated it as blocking every dimensional result. It was not the scale. The
% reasoning that produced SCALE = 0.10 - that a 0.6-unit block at 1:1 would be
% a 583 kg workpiece, which is absurd - was sound, and the answer was right.
%
% --- THE WORKPIECE FIGURE ON THIS BLOCK IS SUPERSEDED. READ THIS.
% blk_L_mm / blk_W_mm / blk_H_mm above record 10 x 10 x 4 mm as supplied on
% 2026-08-25. They are LEFT IN PLACE because they were genuinely reported and
% deleting a supplied reading hides that it happened - but they are NOT what
% the model uses and NOT believed to describe the production block.
%
% The agreed workpiece is 100 x 100 x 50 mm, 0.375 kg (section 3, 2026-08-26).
%
% What overturned the 10 x 10 x 4: MAGAZINE GEOMETRY, which cannot be
% mislabelled the way a written number can. Magazine.STEP carries four 5 mm
% dividers making FIVE slots of 105-110 mm, 115 mm deep and 305 mm tall. A
% 100 mm block sits in that with normal clearance; a 10 mm chip would have
% 100 mm of slop and could not feed. The PLC's own magazine_inventory.json
% independently reports five columns of six - the same five. The annotated
% layout in Inputs/Image1.jpg labels the blocks 100 x 100 x (25,35,45,55,65).
%
% A COMPLETE re-baseline was built on the 0.300 g figure and validated green at
% 143/143 before the magazine caught it. See Project_Notes/NEXT_STEPS.md 0B.
% The rule that came out of it: a measurement that forces a SOLVER change is
% suspicious. At 0.300 g this model diverges at every dt from 5e-4 down to
% 2e-5, and none of that was a defect in the physics.
%
% What the 10 x 10 x 4 mm actually measured is not yet established.
%
% --- prox_rated_mm IS NOT P.prox_rng
% 125 mm is the sensor's RATED MAXIMUM - what the component can do. P.prox_rng
% is the distance at which a real 100 x 100 x 50 mm WOODEN block actually trips
% it, which is a different number and still unknown. The type is confirmed
% CAPACITIVE (2026-08-26), which is consistent with a wooden target. But 125 mm
% does not sit comfortably with the M18 barrel in the CAD: a capacitive M18
% typically ranges a few mm to about 20. Worth resolving at the machine.


%% ---- 13B. READ FROM THE VENDOR CAD, 2026-08-25 -------------------------
% RECORDED, NOT APPLIED. Nothing below feeds the physics; these are facts held
% beside the model so that the assumptions they contradict are visible.
%
% Sources, all parsed as text: the STEP files supplied in BITS_MCD_project, the
% eight further STEP exports made 2026-08-25 from the Siemens NX and Parasolid
% originals, and the dimensioned plan view in Inputs/total_assembly_v2_1.pdf.
% The STEP reader was validated against big_cylinder.stp, whose bore was known
% independently, before any of the new figures were trusted.

% --- the cell
P.CAD.cell_x_mm       = 1614;   % [CAD] assembly drawing, dimensioned      mm
P.CAD.cell_y_mm       = 1449.9; % [CAD] assembly drawing, dimensioned      mm
P.CAD.cell_y_stp_mm   = 1570;   % [CAD] base_40.stp bbox - see note below  mm

% --- conveyors
P.CAD.conv1_len_mm    = 780;    % [CAD] Conveyor1.STEP, overall X          mm
P.CAD.conv2_len_mm    = 750;    % [CAD] Conveyor2.STEP, overall X          mm
P.CAD.conveyor_len_mm = 775;    % [CAD] conveyor.stp, overall X            mm
P.CAD.conv1_wide_mm   = 370.4;  % [CAD] Conveyor1.STEP, Y                  mm
P.CAD.conv2_wide_mm   = 120;    % [CAD] Conveyor2.STEP, Y                  mm

% --- the LARGE cylinder. Folder Janatics-A27,A28; barrel 1202510000; the
%     STEP's own PRODUCT names read JANATICS-DEFAULT_A12_*.
P.CAD.cyl_big_bore_mm = 32;     % [CAD] r=16.000 faces AND the part names   mm
% The bore 32 is corroborated TEXTUALLY, independently of the geometry parse:
% that folder's Parasolid parts are named "FEC Sub Assembly_Ø32 FEC" and
% "REC Sub Assembly_Ø32 REC" - the vendor's own front and rear end covers,
% labelled Ø32 by the vendor. Two unrelated readings of the same file set.
P.CAD.cyl_big_rod_mm  = 12;     % [CAD] rod surface, big_cylinder.stp      mm
P.CAD.cyl_big_len_mm  = 618;    % [CAD] big_cylinder.stp, overall          mm
P.CAD.cyl_body_w_mm   = 47.8;   % [CAD] big_cylinder.stp cross-section     mm

% --- the SMALL cylinder. Folder Janatics-A51,A52; barrel 1501160000.
%     Five separate parts agree: barrel ID 8.0 and OD 9.0; piston head 8.0 on
%     a 4.0 shaft; both end covers 16.9 across, sealing at 8.2 and 4.2; the
%     nut ring cum wiper at 8.3 and 3.5.
P.CAD.cyl_sml_bore_mm = 8;      % [CAD] barrel ID and piston OD agree      mm
P.CAD.cyl_sml_rod_mm  = 4;      % [CAD] rod shaft, sealed at 4.2 both ends mm
P.CAD.cyl_sml_body_mm = 16.9;   % [CAD] end-cover cross-section            mm

% --- the proximity sensor
P.CAD.prox_thread_mm  = 18;     % [CAD] M18: crest 17.88, root 16.74       mm
P.CAD.prox_body_mm    = 76.6;   % [CAD] Sensor.step_sldprt.STEP, overall   mm

% --- the magazine
P.CAD.mag_x_mm        = 555;    % [CAD] Magazine.STEP                      mm
P.CAD.mag_y_mm        = 115;    % [CAD] Magazine.STEP, stray body removed  mm
P.CAD.mag_z_mm        = 305;    % [CAD] Magazine.STEP                      mm

% --- the workpiece, read directly rather than inferred
P.CAD.blk_L_mm        = 100;    % [CAD] Box_50MM.STEP, X                   mm
P.CAD.blk_W_mm        = 100;    % [CAD] Box_50MM.STEP, Y                   mm
P.CAD.blk_H_mm        = 50;     % [CAD] Box_50MM.STEP, Z                   mm

% --- magazine slot pitch, which is what overturned the 10 x 10 x 4 reading
P.CAD.mag_slots       = 5;      % [CAD] four 5 mm dividers -> five slots    -
P.CAD.mag_slot_mm     = 110;    % [CAD] 105-110 across the five            mm

P.CAD.source = 'BITS_MCD_project + Inputs/total_assembly_v2_1.pdf';

% --- SCALE IS CONFIRMED FOUR WAYS, INDEPENDENTLY. CLOSED.
%     tape on conveyor 1   760 mm      0.760/7.6 = 0.1000
%     conveyor.stp         775 mm      0.775/7.6 = 0.1020
%     Conveyor1.STEP       780 mm      0.780/7.6 = 0.1026
%     Conveyor2.STEP       750 mm      0.750/7.6 = 0.0987
% A 2.6 % spread across four sources, which is what you expect when some
% numbers span the end frames and one is a tape laid along the belt. Nothing
% here moves P.SCALE.
%
% The assembly drawing also carries dimensions of 604.33 and 644.33 near the
% conveyors. Those are INTERNAL dimensions, not overall length; read as
% conveyor length they would have overturned the scale, and they do not.
% The drawing's title block reads "SCALE 0.100", which is a PLOT scale - how
% the sheet is printed - and shares a value with P.SCALE by coincidence. It is
% not a fifth confirmation and must not be quoted as one.
%
% --- WHY cell_y HAS TWO VALUES
% The drawing dimensions the cell at 1449.9 mm in Y. The bounding box of
% base_40.stp gives 1570 mm. Both are recorded because the difference is not
% resolved: a bounding box catches anything that protrudes, so the drawing is
% the more likely of the two, but nothing here proves it.
%
% --- QUESTION 14 IS ANSWERED IN PART, AND THE ANSWER WAS BIGGER THAN ASKED
% The question was "which cylinders are bore 32 and which are bore 20". The
% CAD says the choice was wrong: this cell contains bore 32 AND bore 8, and
% JANATICSDATA's bore 20 / rod 8 matches NEITHER of them. At 6 bar:
%     bore  8   ->   30 N        6.2x LESS than the model assumes
%     bore 20   ->  188 N        what JANATICSDATA currently claims
%     bore 32   ->  482 N        2.6x MORE than the model assumes
% That is coherent with everything else measured: a 1.6 m cell moving a
% 0.375 kg block needs modest pushers and one large cylinder where the press
% actually has to press. Bore 20 everywhere was sized against the phantom
% 0.583 kg workpiece.
%
% STILL OPEN, and the reason this is not applied: WHICH of the six cylinders
% is which. Assigning 8 or 32 to A1, A6, S2A1, S3A1, S3A2 and the press
% without reading the barrels would be inventing an answer - the mistake the
% UNMAPPED rows of FACTORY_IO_MAP exist to refuse. Question 14 now asks that.
%
% --- THE SENSORS ARE CAPACITIVE. RESOLVED 2026-08-26, AND THE MODEL IS FINE.
% Sensor.step_sldprt.STEP is a 76.6 mm M18 barrel, and a sibling file in the
% drop is named "Inductive Proximity Sensor Assembly". That filename is wrong:
% confirmed on 2026-08-26 the sensors are CAPACITIVE.
%
% This matters because it decides whether FACTORY_SENSORS is right in FORM. It
% computes every y.PX from the WORKPIECE position. An inductive sensor cannot
% detect wood at all, so had they been inductive they would have to be watching
% metal - a rod, a carrier, a fixture - and the sensor model would have needed
% rewriting rather than re-tuning. Capacitive sensors DO detect wood. The model
% is structurally correct as written.
%
% STILL OPEN, and now the only sensor question: P.MEAS.prox_rated_mm = 125 does
% not sit comfortably with an M18 capacitive barrel, which typically ranges a
% few mm to about 20. Either the 125 belongs to something else or the sensor is
% not the M18 in the CAD. P.prox_rng = 0.030 remains [ASM] either way - the
% trip distance against a real 100 x 100 mm wooden block is still unmeasured.


% --- A DEFECT IN THE SUPPLIED CAD, worth reporting upstream
% Magazine.STEP places 15 of its 396 points at Y = 55052.5 mm, a stray body
% 55 metres from the part. mag_y_mm above is the real 115 mm span of the
% other 381.

%% ---- 13C. READ FROM THE PLC PROGRAM LISTING, 2026-08-30 ----------------
% RECORDED, NOT APPLIED, on the same terms as 13B. Nothing below feeds the
% physics. These are facts about the program the machine actually runs, held
% beside the model so that the assumptions they contradict stay visible.
%
% Source: Factory_Simulation/plc/abc.pdf, the 113-page TIA Portal "Program
% blocks" export, decoded with Project_Notes/tools/read_pdf_text.py. The file
% has no usable text layer and uses subset CID fonts, so the decode resolves
% glyph codes through each font's ToUnicode map. Two independent networks
% carry the I/O addresses - FC3 solenoid_manual, which writes the coils, and
% FC8 Fc_IO, which mirrors them to the HMI - and they agree exactly. That
% cross-check is why the addresses are trusted; a single reading would not
% have been. See the caution in read_pdf_text.py before adding to this list.
%
% Blocks: FC1 motor_function, FC2 move_to_db1, FC3 solenoid_manual,
%         FC4 pot_1_lad, FC5 manual_off, FC6 void_main (the automatic cycle),
%         FC7 void_main_sub_funcs, FC8 Fc_IO, FC9 Fc_System, OB1 Main.

% --- what is actually wired
P.PLC.n_din       = 13;    % [PLC] 10 prox + 2 platform limits + E-stop   -
P.PLC.n_dout      = 22;    % [PLC] 13 solenoids, 3 conveyors, engrave, 5 axis -
P.PLC.n_solenoid  = 13;    % [PLC] FC3, every coil written in one network -
P.PLC.n_prox      = 10;    % [PLC] %I0.0-%I1.5, agrees with PlcTagList    -
P.PLC.n_axis      = 3;     % [PLC] pot_1, pot_2, pot_3 + Axis_1 platform  -

% --- the pneumatic actuator inventory, which the model does NOT match
% Solenoids 1-5 are five magazine pushers, one per compartment. 6 and 11 are
% transfers. 7/8 and 9/10 are extend and retract coils on TWO cylinders, so
% cylinders A and B are DOUBLE-SOLENOID and hold position with both coils
% off. 12 and 13 are two outfeed stations. See FACTORY_IO_MAP for the
% address-by-address map.
P.PLC.n_pneu_act  = 11;    % [PLC] 5 pushers + 2 xfer + 2 cyl + 2 outfeed -
P.PLC.n_dbl_sol   = 2;     % [PLC] cylinder A and cylinder B              -

% --- timer presets, against the model's invented placeholders in section 10
P.PLC.t_cycle_watchdog  = 10.0;   % [PLC] FC6 N1, T#10S                    s
% [CORRECTED 2026-09-12, plan H2.] Read on 2026-08-30 as a cycle WATCHDOG.
% The recordings say it is a START DELAY: cmd_start -> magazine push (SV1) is
% 9.987 / 10.013 / 10.026 / 10.167 / 10.196 s over five cycles, with dead time
% on every tag in between except a cylinder-home pulse (SV10 ~2.0 s, SV8
% ~5 s). It is APPLIED as P.PLC.t_start_delay below. This field is kept for
% the reading it records.

% ---- SEQUENCER DWELLS, MEASURED 2026-09-08 AND APPLIED -------------------
% These are the machine's own programmed waits, measured off the transition
% log of real cycles. Until now the model had NONE of them: it advanced the
% instant a modelled sensor confirmed, and the machine does not do that.
%
% WHY THEY ARE DWELLS AND NOT SLOW ACTUATORS - this is the whole point, and
% getting it backwards would have produced the right cycle time for the wrong
% reason. The cylinder-A interval measures 8.059 s from the extend coil to the
% retract coil, against 2.72 s in the model, and the obvious move is to close
% the meter-out needle until the modelled rod takes 8 s too. That would be
% WRONG. The machine has NO CYLINDER POSITION FEEDBACK - 13D established that
% the whole 158-tag register carries none, and that the PLC latches
% pgm_cylA_Ext rather than reading a switch. A controller that cannot see the
% rod cannot be waiting for it. It is running a timer, and the real rod almost
% certainly arrives early and then sits there.
%
% So the rod keeps its own speed and the SEQUENCER waits, which is what the
% machine does. The guards below read "arrived AND the dwell has elapsed", so
% the physics still has to deliver the rod - the dwell cannot paper over an
% actuator that never gets there.
P.PLC.t_cylA_hold      = 8.059;  % [PLC] SV7 rising -> SV8 rising, n=7,
                                 %       stdev 0.078 s                      s
P.PLC.t_outfeed_pulse  = 5.010;  % [PLC] SV12 ON duration, FC6 N16 T#5S,
                                 %       n=10, stdev 0.077 s                s
P.PLC.t_xfer1_dwell    = 2.124;  % [PLC] prox 6 rising -> SV6 rising, the
                                 %       FC6 N4 2 s TON. n=1 - it rests on
                                 %       the ONE fully-watched cycle         s
P.PLC.t_cylB_hold      = 8.199;  % [PLC] SV9 rising -> SV10 rising, the
                                 %       engraver-to-belt-3 move. n=1, and
                                 %       within 0.14 s of cylinder A's 8.059 -
                                 %       which is itself evidence: two barrels
                                 %       on one shared needle and one shared
                                 %       timer should behave alike            s
P.PLC.t_dispense_ton   = 2.021;  % [PLC] prox N confirm -> conveyor 1 start.
                                 %       FC7 N2's 2 s TON, read straight off
                                 %       the fully-watched cycle: SV1 at
                                 %       9.987 s, prox 1 at 10.734, conveyor 1
                                 %       at 12.755. n=1, and it matches a T#2S
                                 %       literal in the program (13K)         s
P.PLC.t_start_delay    = 10.0;   % [PLC] FC6 N1 T#10S beside CMD_START: the
                                 %       wait before the first dispense. S03
                                 %       holds for it (plan H2, 2026-09-12).
                                 %       n=5 cmd_start -> SV1 9.99-10.20 s    s
P.PLC.t_cylA_wait      = 1.463;  % [PLC] conveyor 2 stops -> SV7 rises, n=7,
                                 %       1.312-1.584 s, sd 0.126: the PLC
                                 %       waits for the conveyor-2 axis move
                                 %       to end (plan H6, 2026-09-13)        s
%
% THE WAIT BEFORE CYLINDER A, added 2026-09-13 (plan H6). In seven recorded
% cycles cylinder A's extend coil rises 1.312-1.584 s after conveyor 2 stops
% (the 10-cycle baseline; an eighth, C0001-113035, reads 0.254 s at t = 7.5 s,
% before the start delay could have ended, so it is not a normal cycle and is
% excluded). The round-2 handoff (section 4.2) judged this NOT a timer, since
% it scatters by ~0.3 s, and advised against a fixed dwell. That judgement
% stands. What is known since is the cause: the PLC fires SV7 in the same
% sample the conveyor-2 axis completes its position move to 30
% (SEGMENT_BUDGET_2026-09-10 section 3), so it waits on a MOTION whose length
% depends on where the block stopped. This model has no Pot_Control axis, so
% the wait enters as its measured MEAN, in S18, where the model otherwise
% spends 0.17 s. Zero was the one value known to be wrong.
%
% THE START DELAY, added 2026-09-12 (plan H2). The model used to spend that
% window charging the receiver to P_ready (2.38 s), a threshold the real
% supply never reaches. The machine checks no pressure: it waits 10 s. The
% cylinder-home pulse it fires meanwhile (SV10 ~2 s, SV8 ~5 s) is NOT
% modelled. This model holds coils rather than pulsing them (FACTORY_PLC
% header), and both rods already start home, so the pulse would move nothing.
%
% CONFIDENCE IS NOT EQUAL ACROSS THESE THREE. The first two come from seven
% and ten cycles with standard deviations under 0.08 s, which is as solid as
% anything in this model. The third rests on a single cycle, because the other
% nine real recordings never watched a proximity sensor. It is applied because
% it also matches a T#2S literal in the program text (13K), so two independent
% sources agree - but one cycle is one cycle, and it is the first thing to
% re-measure when a wider recording arrives.

P.PLC.t_cyl_watchdog    = 12.0;   % [PLC] FC6 N8/N13, T#12S                s
P.PLC.t_valve_pulse     = 2.0;    % [PLC] FC6 N4/N7/N15, T#2S              s
P.PLC.t_outfeed         = 5.0;    % [PLC] FC6 N16, T#5S after prox 9 / 10  s
P.PLC.t_move_relative   = 1.0;    % [PLC] FC6 N9, T#1S                     s
P.PLC.t_cv2_end_pulse   = 0.400;  % [PLC] FC6 N5, t#400ms on prox 8        s
P.PLC.t_mag_push_pulse  = 0.100;  % [PLC] FC6 N2, T#0.1S                   s
P.PLC.t_mag_dispense    = 2.0;    % [PLC] FC7 N2, T#2S to confirm dispense s

% --- the analogue pressure transmitter, FC8 N1
% NORM_X over the raw range then SCALE_X to 0..10, so the HMI's
% Pressure.Value is in BAR GAUGE and the transmitter is a 0-10 bar unit.
% P.P_set and the receiver settings in section 4 are still [ASM]; this says
% what instrument would confirm them and in what units it reads.
P.PLC.p_raw_lo    = 2765;   % [PLC] %IW64 ktf_a10_raw at 0 bar          counts
P.PLC.p_raw_hi    = 13520;  % [PLC] %IW64 ktf_a10_raw at full scale     counts
P.PLC.p_span_bar  = 10.0;   % [PLC] SCALE_X upper limit                    bar

% --- product recipe. NOT the block on the bench.
% The workpiece-selection network (FC9 N4) moves a PRODUCT_HEIGHT of 50 or
% 25 per compartment, and the tag register carries Productqty_25mm and
% Productqty_50mm as separate counters. The block MEASURED in the lab is
% 40 mm high (section 3), so the cell is configured for two products that
% are neither. Which compartment holds which is not readable from the
% flattened export. This is a question, not a correction - see
% INPUTS_REQUIRED.md.
P.PLC.h_product_a_mm = 50;  % [PLC] FC9 N4, PRODUCT_HEIGHT constant       mm
P.PLC.h_product_b_mm = 25;  % [PLC] FC9 N4, PRODUCT_HEIGHT constant       mm

% --- motion constants. UNITS ARE NOT STATED in the listing and the axes are
% not homed to anything the model knows, so these are recorded as raw
% numbers, deliberately without a unit.
P.PLC.jog_velocity   = 72.0;    % [PLC] FC6 N10, MC_MoveJog Velocity      -
P.PLC.moverel_value  = 515.0;   % [PLC] FC6 N10, +/- about the limits     -
P.PLC.pot_rel_dist   = 30.0;    % [PLC] FC4, Pot1_Relative distance       -
P.PLC.pot_rel_vel    = 20.0;    % [PLC] FC4, Pot1_Relative velocity       -
P.PLC.pot_jog_vel    = 200.0;   % [PLC] FC4, Pot1_Jog velocity            -

P.PLC.source = 'plc/abc.pdf, TIA Portal Program blocks export';

% --- THREE THINGS THE MODEL DOES NOT REPRESENT, now evidenced rather than
%     suspected. None is applied, because applying half a re-model is worse
%     than none - the same reason 13B's bore finding is still not applied.
%
% 1. THE ENGRAVING PLATFORM IS ELECTRIC AND JOGGED, NOT DRIVEN TO A POSITION.
%    FC6 N10 runs MC_MoveJog on "Axis_1" forward and backward at velocity
%    72.0 until pgm_upper_limit_switch or pgm_lower_limit_switch trips.
%    Section 8 already models the base as an ELECTRIC vertical axis, which is
%    right in kind; what it does not model is that the stroke is terminated
%    by a switch rather than commanded.
%
% 2. THE CONVEYOR RUN COMMANDS ARE PLAIN ON/OFF COILS. conveyor_1/2/3 are
%    %Q3.2, %Q3.3 and %Q3.4 and the PLC never writes a speed to them. The
%    model runs a PI speed loop with ramp limiting and rotor inertia, which
%    models the DRIVE's internals, not anything the PLC does. Separately,
%    Pot_Control.Conv1/2/3 are three POSITION axes commanded with
%    MC_MoveAbsolute and their own high- and low-speed setpoints. Whether
%    those axes drive the belts or something else at each station cannot be
%    read from the listing.
%
% 3. FIVE MAGAZINE PUSHERS, NOT ONE. The model collapses them into cylinder
%    A1. Only one fires per cycle, chosen by workpiece_choice, so the cycle
%    time is unaffected - but the air consumed and the inventory logic are.

%% ---- 13D. PHOTOGRAPHS AND THE COMPONENT DATA DROP, 2026-09-02 ----------
% RECORDED, NOT APPLIED, on the same terms as 13B and 13C.
%
% Four photographs of the running cell, plus the "Component Data" folder
% (vendor PDFs and four Word documents). Between them they CONFIRM things the
% PLC listing had only implied, and they introduce one trap.

% --- THE TRAP, AND IT IS A BAD ONE ---------------------------------------
% "Component Data/Components and Sensors.docx" and "Control Flow.docx"
% describe a FIVE-STATION TRAINING KIT: feeder, inspection, buffer, drilling,
% sorting - with a suction gripper, a rotary actuator, an RFID reader, metal
% and plastic detectors and an SP-1523D drilling machine. Its sensors are
% named B1, 1B1, 2B2 and its cylinders 1A, 2A, 3A.
%
% THAT IS NOT THIS CELL. None of it appears anywhere in this machine's PLC
% program: no RFID, no suction, no metal detector, no drill. Our cell's
% program has 13 solenoids, 10 proximity sensors and a laser engraver.
%
% The folder itself says so. "Laser Engraving Work/abc.pdf" is BYTE-IDENTICAL
% to plc/abc.pdf (md5 31512bc6b9a1b84584a21105839693f4), so the laser cell is
% ONE SUBFOLDER of a wider lab, and the rest of Component Data documents the
% training rig beside it.
%
% Both are Janatics, both are Siemens, both are in the same room, and the
% temptation to read the training kit's component list as a bill of materials
% for this cell is exactly the kind of inference this project has already lost
% six sessions to. Anything below marked CANDIDATE comes from that folder and
% is NOT confirmed to be installed here.
P.PHOTO.source = 'four cell photographs, 2026-09-02';
P.CD.source    = 'Component Data/ - LASER ENGRAVING WORK ONLY is this cell';

% --- WHAT THE PHOTOGRAPHS CONFIRM ----------------------------------------
% Independent of the program text, and agreeing with it.
P.PHOTO.n_mag_compartments = 5;  % [MEAS] acrylic magazine, counted        -
P.PHOTO.n_mag_pushers      = 5;  % [MEAS] Janatics cylinders behind it     -
P.PHOTO.n_belt_sensors     = 5;  % [MEAS] M18 barrels on brackets, one row -
%
% That is FC7 N3 - "mag_push_on AND workpiece_choice = N -> solenoid N" - read
% off the machine instead of out of the program. Two unrelated sources, five
% compartments, five pushers, five sensors. This is why P.PROX now carries the
% five magazine sensors as real modelled signals rather than as a note.
%
% The blocks in the compartments are DARK BROWN HARDWOOD, not the pale timber
% the 750 kg/m^3 density suggests. Density was confirmed by weighing on
% 2026-08-26 and is not in doubt; the species is still unrecorded and is worth
% a line on the intake sheet, because a hardwood at 750 is plausible and a
% hardwood at 900 is not the same workpiece.

% --- THE CYLINDER LABELS, PARTLY LEGIBLE ---------------------------------
% Two Janatics barrels sit over the conveyor at the engraving station. Their
% labels read, clearly:
%     "JANATICS  AIR CYLINDER"      brand confirmed ON THE MACHINE, not
%                                   just in the CAD folder
%     "MAX PR. 10 bar"              pressure rating
%     "MAGNETIC"                    magnetic piston
%
% The model number begins "A6..." and does NOT resolve further at this
% resolution. It is NOT transcribed here. Question 14 still needs the label
% read by eye.
P.PHOTO.cyl_max_bar   = 10;      % [MEAS] barrel label, legible            bar
P.PHOTO.cyl_magnetic  = true;    % [MEAS] barrel label reads MAGNETIC      -
%
% "MAGNETIC" matters more than it looks. A magnetic piston is what a reed or
% Hall switch senses, so these cylinders are BUILT to take position feedback -
% and the PLC still has none, latching pgm_cylA_Ext instead (13C, FC7 N6/N7).
% So the missing feedback is a WIRING AND PROGRAM choice, not a hardware
% limit. Fitting two switches would make cylA observable. That is a finding
% about the machine, not about the model, and it is worth telling whoever
% owns the cell.
%
% Against P.P_relief = 9.0e5 Pa absolute (about 8 bar gauge): a 10 bar barrel
% has margin, and VERIFY_MODEL's peak of 8.00 bar sits inside it. Consistent,
% and now consistent with a number read off the machine rather than a
% catalogue.

% --- CANDIDATES FROM THE TRAINING-KIT DOCUMENT ---------------------------
% Recorded so the next session does not have to re-read the folder to find
% out whether they were considered. Every one is a CANDIDATE: named in a
% document about the OTHER machine, plausible here, confirmed nowhere.
P.CD.motor_candidate  = 'Vexta AXHM450K-GFH';  % [EST] brushless, 50 W    -
P.CD.motor_rpm_min    = 100;     % [EST] AXH Series manual, speed range   rpm
P.CD.motor_rpm_max    = 3000;    % [EST] AXH Series manual, speed range   rpm
P.CD.frl_candidate    = 'Janatics FRC136134';  % [EST] filter regulator   -
P.CD.gauge_candidate  = 'Janatics PS0102504';  % [EST] pressure meter     -
P.CD.dcv_candidate    = 'Janatics DC36W';      % [EST] flow + check valve -
P.CD.sys_pressure_bar = 6;       % [EST] "maintains the total required 6 bar"
%
% The 6 bar agrees with P.P_set, which is already [COMM]. That is mild
% corroboration and nothing more - the same regulator setting is unremarkable
% across a whole lab.
%
% P.J_mot, P.T_max and P.N_gear in section 7 stay [ASM]. A 50 W brushless
% motor's inertia is a real number and it is in that manual, but applying it
% would mean asserting this cell runs that motor, and no photograph shows a
% legible motor nameplate. INPUTS_REQUIRED question 19 asks for one.

%% ---- 13E. TOLD BY THE MACHINE'S OWNER, 2026-09-02 ----------------------
% RECORDED, NOT APPLIED, on the same terms as 13B, 13C and 13D.
%
% Source: the maintainer, from operating the cell. That is a weaker source than
% the PLC listing for ADDRESSES and a much stronger one for BEHAVIOUR, because
% the listing says what fires and never says why.
%
% THE STATEMENTS, in the owner's words and in the order they were given.
% Kept verbatim because the READING of the first one changed within the hour
% and the words did not - which is exactly why this project quotes rather than
% paraphrases.
%
%   1. "cylinder B is energised when engraving is NOT to be done (50 mm is
%       selected on the interface)"
%   2. "solenoid 9 is for extending the cylinder and solenoid 10 is for
%       retracting it FOR ENGRAVING MACHINE"
%   3. "every cylinder is moved by solenoid (pneumatic) and conveyor is moved
%       by electric motor"
%   4. "cylinder B ... basically pushes the block when cylinder A doesn't push
%       it (when there is no engraving)" - with the position marked on a
%       drawing of the cell, beside conveyor 2 at the height of belt 3
%
% WHAT (4) SETTLED, and it took all four to get there. (1) alone suggested a
% diverter and the model was briefly built as one, at the end of conveyor 2,
% which diverged the cycle to NaN. (2) moved it to the engraving machine with
% no path at all. (4) gives the position and the logic together:
%
%   engraving selected     the block stops at c2_end and CYLINDER A pushes it
%                          +x into the engraver
%   50 mm, no engraving    the block runs FURTHER DOWN conveyor 2 to belt 3's
%                          height, and CYLINDER B pushes it +x onto belt 3
%
% So A and B are alternatives to each other - same axis, same station, one
% above the other - and coil 9 out / coil 10 back is the polarity the table
% already had. The geometry corroborates the reading: both travels come out at
% 252.5 mm and both round to the same 300 mm standard cylinder, which is what
% the cell's two big double-solenoid barrels should look like.
%
% WHAT (3) CONFIRMS, rather than changes. Two modelling choices that were
% assumptions are now corroborated:
%   - all eleven pneumatic actuators are solenoid-driven cylinders, so the
%     valve model in FACTORY_DERIVATIVES applies to every one of them
%   - the conveyors are ELECTRIC MOTORS, so section 7's motor-and-gearbox
%     drivetrain is right in kind. It does NOT retract 13C item 2: the PLC
%     still writes plain on/off coils (%Q3.2/3.3/3.4) and the PI speed loop in
%     the model is the DRIVE's internals, not anything the PLC does.
% It also leaves section 8 standing: the engraving platform is not a cylinder,
% it is Axis_1, jogged by MC_MoveJog between limit switches, so modelling it as
% an electric vertical axis remains correct.
%
% WHY IT MATTERS. It is the first thing anyone has said about what cylinder B
% is FOR, and it contradicts an assumption this model is currently running on.
% FACTORY_ACTUATORS assigns CYL_B (coils 9/10) the role 'eng_out', the
% engraver-to-belt-3 transfer, on the reasoning that the sequence needs that
% motion and the two double-solenoid cylinders were the plausible pair. If
% cylinder B fires when engraving is SKIPPED, it is not the actuator that moves
% an engraved part off the platform - it is a BYPASS.
%
% WHAT IT LINES UP WITH, and this is why it reads as true rather than as a
% surprise. Section 13C already records two products, PRODUCT_HEIGHT 50 and 25
% (FC9 N4), with separate counters Productqty_25mm and Productqty_50mm, and
% notes that the model has one product against the machine's two. A 50 mm part
% that is not engraved and a 25 mm part that is explains what those two
% counters are counting, and gives the product selection an actual consequence
% rather than being a number the model ignores.
%
% WHAT IS STILL NOT KNOWN, and therefore what is NOT changed here:
%   - where cylinder B is bolted and what it pushes, from where to where
%   - which actuator performs the engrave -> conveyor 3 move on the ENGRAVING
%     path, if it is not cylinder B. Solenoid 11 fires on Wp_move_cv3 (FC6
%     N15) and is the obvious candidate, but that is an inference and the rule
%     here is that inferences do not become mappings
%   - whether the 50 mm path skips the platform raise as well as the engrave
%
% The model has NO product selection and NO bypass branch, so the behaviour
% described above is absent from it entirely. Adding it is a sequencer change,
% not a parameter, and it needs the geometry above first. INPUTS_REQUIRED.md
% question 3c asks for exactly that.
%
% ANSWERED AND BUILT 2026-09-11. The route above is real and the barrel was
% not: SOLENOID 11 serves it, not cylinder B (panel test 2026-09-10; the
% maintainer 2026-09-11). It is modelled - section 15, P.engrave_selected, and
% FACTORY_PLC states S40-S43. The skip never reaches the engraving station,
% which answers the platform question; what the HMI selects it WITH is open.

%% ---- 13E2. THE COMPONENT DATA FOLDER, ITEM BY ITEM, 2026-09-03 ---------
% 13D warned that this folder is a trap and named two documents. It did not
% classify the rest, which left the trap half-set. Every item is now listed
% with what it is, so nobody has to re-derive it:
%
%   TIA Portal.docx            GENERIC TRAINING MATERIAL for the Bangalore lab
%                              - how to configure an S7-1500, address I/O, use
%                              data blocks, stand up an OPC UA server. It
%                              describes NO cell, so it cannot be misread as a
%                              BOM. Useful as METHOD reference: see 13F.
%   Diagnostic Kit.docx        Two lines, about troubleshooting "the
%                              mechatronics kit". THE TRAINING RIG, not this
%                              cell.
%   Control Flow.docx          THE TRAINING RIG - see 13D.
%   Components/Components and Sensors.docx
%                              THE TRAINING RIG - see 13D.
%   Laser Engraving Work/abc.pdf
%                              BYTE-IDENTICAL to plc/abc.pdf. THIS cell.
%   Components/AXH Series.pdf          UNCLASSIFIED
%   Components/Limit Switches.pdf      UNCLASSIFIED
%   Components/Photosensor - SICK.pdf  UNCLASSIFIED
%   Components/SP-1523D_Leaflet.pdf    UNCLASSIFIED
%
% THE FOUR UNCLASSIFIED PDFs ARE VENDOR DATASHEETS AND MUST NOT BE MINED AS A
% BILL OF MATERIALS until someone says which rig they belong to. They sit
% beside "Components and Sensors.docx", which 13D establishes describes the
% training rig, so the default assumption has to be that they do too.
%
% Two of them would matter a great deal if they turned out to be THIS cell,
% which is exactly why the temptation must be resisted:
%   - AXH Series is an Oriental Motor brushless DC range. Every conveyor
%     drivetrain figure in section 7 is [EST] or [ASM], and the owner has
%     confirmed the conveyors are electric motors, so a real motor datasheet
%     would replace eight assumptions at once.
%   - "Photosensor - SICK" is a PHOTOELECTRIC sensor. The cell's proximity
%     sensors were confirmed CAPACITIVE on 2026-08-26, and that confirmation
%     is load-bearing: FACTORY_SENSORS computes every y.PX from the workpiece
%     position, which is only correct for a sensor that can see wood. If this
%     datasheet were this cell's, that finding would need revisiting.
%
% Neither is applied. INPUTS_REQUIRED asks which rig they belong to.

%% ---- 13E3. EVERY SUPPLIED FOLDER, SURVEYED 2026-09-03 ------------------
% RECORDED so that nobody surveys them a fourth time. Seven folders sit beside
% this model; here is what each holds and whether anything in it is still
% unmined.
%
%   BITS_MCD_project/     THE VENDOR CAD. FULLY MINED - section 13B. Its part
%                         FILENAMES are a partial bill of materials and they
%                         are already recorded: barrel 1501160000 (small) and
%                         1202510000 (large), folders Janatics-A27,A28 and
%                         Janatics-A51,A52, tie rod 2102510000, piston 410034,
%                         front end covers 410198 / 430093, needle 310000,
%                         wiper 770040, circlip 840001, lock nuts 830016 /
%                         832001, end cover bolt 010169. Nothing new here.
%                         Note it contains A12, A27/A28 and A51/A52 and NOTHING
%                         named A53 or A54, which is what JANATICSDATA assumes.
%                         Also 'Inputs/' - the photographs, mined in 13D.
%   Component Data/       Classified item by item in 13E2. Four vendor PDFs
%                         remain deliberately UNCLASSIFIED; question 18.
%   new_scada/            MINED 2026-09-03 - section 13G. Its history database
%                         held two live machine cycles, now extracted to
%                         plc/simulator_trace_2026-09-01.json. Its
%                         config/Tag_list (1).xlsx is BYTE-IDENTICAL to
%                         plc/PLC_Tag_List.xlsx, so nothing was missing there.
%                         Its twin_reference.json is this model's OWN export.
%   PLC_Dashboard/        Four Python files and the same tag list. app.py and
%                         app_fixed.py are the snap7 clients 13F cites.
%                         "app_platform_control (1).py" is a MANUAL JOG panel
%                         for Axis_1, captioned "Momentary jog control. Hold a
%                         button to move; release to stop." That CORROBORATES
%                         13C item 1 - the engraving platform is jogged, not
%                         driven to a position - from a second source. It
%                         carries no automatic sequence and no timings.
%   Final/                The YOLO camera dataset: 1002 labelled images,
%                         weights, capture and inference scripts. The model's
%                         camera is one range check (y.CAM), so none of it is
%                         needed. It is also the provenance for the credential
%                         warning in HANDOFF section 4.
%   resources/            MATLAB project metadata. Nothing.
%   Project_Notes/        This project's own working record.
%
% NOTHING IN ANY OF THEM IS STILL UNMINED except the four PDFs in
% Component Data/Components/, which are held back on purpose rather than
% overlooked. Everything else that was going to change the model already has.

%% ---- 13F. THE TIA PORTAL REFERENCE DOC, 2026-09-03 ---------------------
% RECORDED, NOT APPLIED. Nothing below feeds the physics.
%
% Source: "Component Data/TIA Portal.docx". WHAT IT IS MATTERS, because 13D
% warns that two documents in that folder describe a DIFFERENT five-station
% training rig. This one is neither: it is GENERIC TIA PORTAL TRAINING
% MATERIAL for the Bangalore lab - how to configure an S7-1500, address I/O,
% use data blocks, and stand up an OPC UA server. It describes no cell at all,
% so it cannot be mistaken for a bill of materials. It is a METHOD reference.
%
% WHY IT EARNS A SECTION. It bears directly on the one item that separates
% this project from an actual digital twin: a live link to the machine.
%
%   - The OPC UA server on an S7-1500 is NOT on by default. It is activated in
%     the CPU's Properties > OPC UA > Server page, and it only starts after a
%     hardware compile and DOWNLOAD.
%   - Firmware >= 2.6 is required on an S7-1500 (>= 4.2 on a 1200).
%   - A runtime LICENCE is needed, and its class depends on the CPU: 1511/1512
%     take the small licence, 1515/1516 a different one.
%   - UA Expert is the open-source client for testing an endpoint before
%     pointing MATLAB at it.
%   - An S7-1200 can only be a server; an S7-1500 can be server or client.
%
% AND THE FINDING THAT CHANGES THE PICTURE. Every piece of software that has
% ever talked to this machine uses SNAP7, not OPC UA:
%
%   Final/app.py                             snap7.client.Client(),
%                                            192.168.0.102, rack 0, slot 1
%   new_scada/.../backend/plc/service.py     snap7.client.Client()
%
% A search of both backends for "opcua", "opc_ua" or port 4840 returns
% NOTHING. So HANDOFF open issue 15 - "opcuaserverinfo('192.168.0.102') finds
% nothing" - most likely has a simpler cause than the three that were
% suspected (wrong subnet, no discovery service, bad discovery URL): the OPC
% UA server has probably never been switched on, because nothing ever needed
% it. Section B of the PLC Access sheet is the fix, and B7 is the step people
% miss.
%
% PLCTAGLIST's header said the tags were read "over snap7 / OPC UA". That was
% loose and is corrected: snap7 only.
%
% THE PRACTICAL CONSEQUENCE, and it is a good one. The machine is reachable
% TODAY over snap7 - the dashboard reads DB59 live. A connected twin does not
% have to wait for OPC UA. See NEXT_STEPS.md A14.

%% ---- 13G. A REAL MACHINE TRACE, 2026-09-01 -----------------------------
% RECORDED, NOT APPLIED, on the same terms as 13B-13F. But read this one: it
% is the FIRST TIME this project has compared itself against the machine.
%
% >>> WHOLLY SUPERSEDED 2026-09-07. THIS IS NOT A MACHINE TRACE. It is the
% >>> SCADA application's built-in PLC SIMULATOR, and the title of this
% >>> section is wrong in its most important word. Every number below is a
% >>> simulator constant or a simulator behaviour. READ 13I FIRST; nothing in
% >>> this section or in 13H may be cited without it.
% >>>
% >>> The interim correction of 2026-09-06 (13H) found a real defect - the
% >>> recorder watched 13 of 158 tags - but it audited the INSTRUMENT and
% >>> never asked about the SOURCE, and so it left the false premise standing
% >>> and built a new conclusion on top of it.
% >>>
% >>> Both sections are kept exactly as written. Two successive readings of
% >>> the same file each found the previous one's error and missed a larger
% >>> one underneath it, and that sequence is worth more to a future session
% >>> than a tidy summary would be.
%
% Source: new_scada/scada_platform/data/scada_history.db, extracted to
% plc/simulator_trace_2026-09-01.json. The SCADA application recorded it live on
% 2026-09-01 with source_id "plc" and config plc.simulate = false, over snap7
% to 192.168.0.102 rack 0 slot 1. Two AUTO cycles, both COMPLETED, zero faults,
% zero stalls, qty_25mm = 1 each - so both ran the 25 mm ENGRAVED product.
%
%   cycle 1  C0001-112601   18.146 s
%   cycle 2  C0001-113035   17.732 s
%
% CYCLE 1, RELATIVE TO cmd_start:
%
%   t+ 0.000  system.cmd_start                        false -> true
%   t+ 5.104  conveyor 2 ON, velocity feedback 0.2
%   t+ 7.668  conveyor 2 OFF; SOLENOID 7 ON      (CYL_A extend)
%   t+ 8.946  solenoid 7 OFF; pgm_low_limit drops (platform leaves bottom)
%   t+10.479  pgm_up_limit TRUE                   (platform at top)
%   t+11.504  pgm_up_limit FALSE                  (platform leaves top)
%   t+13.041  pgm_low_limit TRUE                  (platform back at bottom)
%   t+13.296  SOLENOID 11 ON                      (MOVE_TO_CV3)
%   t+14.316  solenoid 11 OFF
%   t+16.865  SOLENOID 12 ON                      (OUTFEED_A)
%   t+18.145  solenoid 12 OFF; system.cycle_completed TRUE
%
% WHAT IT CONFIRMS, and this is worth a great deal:
%
%   1. THE ACTUATOR ORDER IS CYL_A (7) -> MOVE_TO_CV3 (11) -> OUTFEED_A (12).
%      That is exactly what FACTORY_ACTUATORS now says, and it was arrived at
%      from the owner's words. The machine's own trace agrees INDEPENDENTLY.
%      The model's earlier assumption - that coils 9/10 made the
%      engraver-to-belt-3 move - would have put solenoid 9 in this trace. It is
%      not there.
%   2. CYL_B (coils 9/10) NEVER FIRES in either cycle, and both cycles ran the
%      ENGRAVED product. That is the owner's statement, observed: cylinder B
%      belongs to the no-engrave path.
%
% WHAT IT CONTRADICTS. None of this is applied; each needs a decision.
%
%   3. THE ENGRAVING PHASE IS ~4.1 s, NOT 12.5 s, AND IT IS NOT MANUAL.
%      Platform leaves bottom at t+8.946 and is back at t+13.041: 4.095 s, of
%      which the DWELL AT TOP - the engraving itself - is 11.504 - 10.479 =
%      1.025 s. Rise 1.533 s, fall 1.537 s.
%
%      Section 10 models this as THREE MANUAL OPERATOR STEPS totalling 12.5 s
%      (t_op_notice 3.0 + t_engrave 8.0 + t_op_confirm 1.5), all [PLH], on the
%      reading that Sequence.xlsx rows 27-29 are operator actions with no
%      completion signal. The trace shows an automatic sequence with no
%      operator gap anywhere in it. THIS IS A STRUCTURAL DISAGREEMENT, not a
%      parameter that is merely too big, and it is the largest single
%      contributor to the model's cycle time.
%   4. CONVEYOR 2 RUNS AT 0.2 m/s, conveyors 1 and 3 at 0.15. The model has one
%      P.v_belt = 0.150 for all three.
%   5. THE PRESSURE TRANSMITTER READ 6.2 bar throughout both cycles, against
%      P.MEAS.P_res_0_bar = 4.3 and the 4.315 in the older PLC snapshot. FC8 N1
%      says that tag is BAR GAUGE. Different day, possibly a different
%      regulator setting; recorded, not reconciled.
%   6. conveyor.N.position_fb IS 30.0 AND NEVER MOVES, on all three conveyors,
%      across 142 samples. That closes the "30.0 with no unit" puzzle in the
%      direction of "it is not a position feedback at all".
%
% WHAT IT DOES *NOT* SAY, and this matters more than anything above:
%
%   THIS IS NOT A WHOLE CYCLE BY THE MODEL'S DEFINITION. No magazine pusher
%   (solenoids 1-5) fires anywhere in the trace, and conveyor 1 never runs. The
%   recorded cycle starts with conveyor 2 already carrying a part. The model's
%   sequence starts at the feeder: camera, pressurise, magazine push, belt 1,
%   transfer, belt 2, and only then reaches the point this trace begins at.
%
%   SO 18.146 s AND 31.080 s ARE NOT COMPARABLE, and anyone who subtracts them
%   is measuring the difference in scope, not in fidelity. The model's own
%   process breakdown (VISUALIZE_PROCESSES) puts 8.1 s before belt 2 starts.
%
%   Two cycles is also a sample of two. Section 4.4 of NEXT_STEPS asks for ten
%   or more precisely because the model predicts zero spread and these two
%   differ by 0.414 s.
%
% See NEXT_STEPS.md - items A8, A10, A13 and A16 all move because of this.

%% ---- 13H. WHAT THE TRACE COULD NOT RECORD, 2026-09-06 ------------------
%
% >>> SUPERSEDED 2026-09-07 BY 13I. The instrument analysis below is correct
% >>> and still useful - the recorder really did watch 13 of 158 tags. What
% >>> is wrong is everything it concluded, because the file it audited is the
% >>> SCADA SIMULATOR, not the machine. In particular the headline result,
% >>> "model machine time 18.580 s against a recorded 18.146 s, within 5%",
% >>> is the model being compared with a stand-in seeded from the model's own
% >>> parameters. WITHDRAWN. The real figure is about 62 s. See 13I.
%
% A re-audit of 13G against the recorder's own source. Nothing here is a new
% measurement; it is the same file read with its instrument understood. Three
% of 13G's conclusions do not survive it, and one of them was the headline.
%
% THE RECORDER CAPTURED 13 TAGS OUT OF 158.
%
% new_scada/backend/db/ingest.py persists transitions of WATCHED tags only.
% The watch list is set once at start-up from
% backend/services/diagnostics.py::default_watch_list, whose own docstring
% says it holds "the tags the Errors sheet actually names" - it is a fixed
% diagnostic set built to illustrate a fault list, not a survey of the plant.
% Seventeen roles go in. Thirteen tags ever came out, and this is not inferred
% from the code but counted from the file itself:
%
%   SELECT DISTINCT tag_id FROM historical_tag_data  ->  13 rows
%
%   pgm_low_limit, pgm_up_limit, conveyor2 output, solenoid 7, 11 and 12
%   outputs, manual solenoid 8, conv2 set_velocity and velocity_fb,
%   cmd_start, cycle_completed, emergency_healthy, engv_plate_home.
%
% NEVER WATCHED, therefore INVISIBLE to the transition list whatever they did:
% solenoids 1-6, 9, 10 and 13; conveyor 1 and conveyor 3; ALL TEN PROXIMITY
% SENSORS. The snapshot in plc/simulator_trace_2026-09-01.json shows the machine
% publishes 158 tags, so 145 of them could not appear.
%
%   >>> AN ABSENCE FROM THE TRANSITION LIST IS NOT AN OBSERVATION OF ABSENCE.
%
% WHAT THAT COSTS 13G:
%
%   13G CLAIM 2 - "CYL_B (coils 9/10) NEVER FIRES" - WITHDRAWN. Coils 9 and 10
%   are not in the watch list. The trace cannot show them firing and cannot
%   show them idle. The owner's statement that cylinder B belongs to the
%   no-engrave path still stands on its own; it simply is NOT corroborated
%   here, and 13G said it was. Still open: question 3c, and lab item A3.
%
%   13G "WHAT IT DOES *NOT* SAY" - WITHDRAWN, AND REVERSED IN PART. It argued
%   the recording covers only the back half of the cycle because "no magazine
%   pusher fires and conveyor 1 never runs". Solenoids 1-5 and conveyor 1 are
%   unwatched, so the first half of that is unsupported either way. The second
%   half is CONTRADICTED by evidence already in the same file:
%
%     cycle_metrics is accumulated on EVERY poll for ten aggregate roles,
%     independent of the watch list (ingest.py::TagAccumulator, an unweighted
%     mean). Conveyors 1 and 3 are among them. For BOTH cycles:
%
%       conveyor.1.velocity_fb   avg 0.018750  max 0.15   n 72   ->  9 samples
%       conveyor.2.velocity_fb   avg 0.027778  max 0.20   n 72   -> 10 samples
%       conveyor.3.velocity_fb   avg 0.018750  max 0.15   n 72   ->  9 samples
%
%     avg*n/max is exactly 9, 10 and 9 in all six cases - a clean on/off with
%     no ramp captured, at a 0.25 s poll. So ALL THREE CONVEYORS RAN in both
%     recorded cycles: conveyor 1 for about 2.25 s, conveyor 2 for 2.5 s,
%     conveyor 3 for 2.25 s.
%
%   CONSEQUENCE: 18.146 s vs 31.080 s IS RE-OPENED. 13G closed that comparison
%   as a scope mismatch and told the reader not to make it. Conveyor 1 ran, so
%   the recording is not obviously the back half of anything. Whether a
%   magazine pusher fired remains genuinely unknown - unwatched, and the model
%   spends 8.1 s before belt 2 starts. This is now the single most valuable
%   open question in the project, and lab item A16 - a trace that starts at the
%   magazine - is what settles it. DO NOT subtract the two numbers yet either;
%   the point is that the reason for not doing so has changed from "different
%   scope, proven" to "scope unknown, and it may well be the same".
%
%   13G CLAIM 4 - "CONVEYOR 2 RUNS AT 0.2 m/s" - TRUE BUT MISREAD. conv2's
%   set_velocity is a POT, and the trace records a hand turning it:
%
%     t+0.000    conv2.set_velocity  0.0  -> 0.15   (power-up / reset)
%     t+9.238    conv2.set_velocity  0.15 -> 0.20   (immediately before cycle 1)
%     t+282.650  conv2.set_velocity  0.15 -> 0.20   (immediately before cycle 2)
%     t+955.562  conv2.set_velocity  0.0  -> 0.15   (reset; NOT raised again)
%
%   and the third, partial cycle that follows that last reset runs conveyor 2
%   at 0.15, not 0.20. So 0.20 is ONE OPERATOR'S DIAL POSITION during two
%   cycles, not a machine constant. THE MACHINE'S DEFAULT IS 0.15 ON ALL
%   THREE - which is the value P.v_belt has always held.
%
%   Writing 0.20 into conveyor 2 as a fact about the cell would have been the
%   [JAN] mistake again: a provisional figure repeated until it looked like a
%   nameplate. Section 7 now carries THREE setpoints, all at the observed
%   default of 0.150, so the structure the machine really has - three
%   independent pots - is expressible without inventing what they are set to.
%
% WHAT THE RE-AUDIT ADDS, rather than takes away:
%
%   A. A 158-TAG SNAPSHOT OF THE MACHINE AT REST now sits in
%      plc/simulator_trace_2026-09-01.json under "snapshot_at_rest", taken from
%      the two recording sessions that ran immediately after each cycle. It is
%      the widest single observation of the real cell this project has. All
%      158 tags were already transcribed in PLCTAGLIST; what is new is their
%      OBSERVED VALUES.
%
%   B. MODE_HIGH_SPEED SELECTS NOTHING. Every one of
%      pot_control.conv{1,2,3}.{highspeed,lowspeed}_{velocity,position} reads
%      0.0, and system.mode_high_speed is false. The high/low-speed profiles
%      exist in the tag list and are UNCONFIGURED on this machine. That closes
%      the open half of A10 - the model is right to have no concept of them.
%
%   C. THE FIVE MAGAZINE COMPARTMENTS ALL REPORT OK. comp_status.comp1..5.ok
%      are all true, .low and .empty all false, after both cycles. It does not
%      say how many blocks each holds - only that none is low or empty.
%
%   D. system.engraving_completed IS FALSE after both cycles, and both ran the
%      engraved product. The engrave-done signal exists as a tag and did not
%      assert. Either it is set and cleared inside the cycle - it is unwatched,
%      so a pulse would not appear - or nothing drives it. Question for A8.
%
%   E. THE ENGRAVING DWELL IS NOT CONSTANT. 13G quotes 1.025 s from cycle 1.
%      Cycle 2 is 0.768 s, a 25% spread, while rise and fall repeat to within
%      7 ms (1.533/1.538 and 1.537/1.544). Whatever sets the dwell is not the
%      same mechanism that sets the platform travel. Recorded for D3.
%
% AND ONE NUMBER THAT FALLS OUT OF RE-OPENING THE COMPARISON. Offered as an
% observation, not as a validation - but it is the closest this project has
% come to one, and it should be checked rather than left unsaid.
%
%   RUN_FACTORY_SIMULATION already reports the cycle split two ways, because
%   the three operator steps are [PLH] and it refuses to let them hide:
%
%     CYCLE COMPLETE     31.080 s
%     of which operator  12.500 s   (PLACEHOLDER timing)
%     machine time       18.580 s
%
%   The machine recorded 18.146 s and 17.732 s.
%
%     model machine time  18.580 s
%     machine, cycle 1    18.146 s   ->  model is +2.4%
%     machine, cycle 2    17.732 s   ->  model is +4.8%
%
%   WHY THIS IS NOT NOTHING. If the recording really were "the back half" as
%   13G concluded, the right comparison would be the model's back half, which
%   VISUALIZE_PROCESSES puts at 22.890 s from belt 2 onward, or 10.390 s of
%   machine time once the 12.5 s of operator steps come out - against a
%   recorded 18.146 s. It would not be close in either direction. It is the
%   WHOLE machine time that lands within 5% of the machine's whole recorded
%   cycle, which is what one would expect if both are counting the same work.
%
%   WHY IT IS NOT A VALIDATION EITHER, and these are not small:
%
%     - Whether a magazine pusher fired is still unknown (solenoids 1-5 are
%       unwatched). If none did, the agreement is a coincidence between two
%       different quantities and must be dropped.
%     - The BELT TIMES DO NOT LINE UP INSIDE THE TOTAL. At a 0.25 s poll the
%       machine shows 9 / 10 / 9 samples on conveyors 1 / 2 / 3, so roughly
%       2.25 / 2.5 / 2.25 s. The model spends 4.225 / 1.365 / 3.105 s. Same
%       order of magnitude, same total to within 1.7 s, DIFFERENT DISTRIBUTION.
%       So even if the totals agree, the internal geometry does not, and the
%       waypoints are the likely reason.
%     - Two cycles is a sample of two, differing by 0.414 s where the model
%       predicts zero spread.
%
%   WHAT IT WOULD MEAN IF IT HOLDS. That the model's machine physics is already
%   within a few percent of the real cell, and that essentially the WHOLE of
%   the 31.080 vs 18.1 discrepancy is the 12.5 s of invented operator time that
%   13G's claim 3 and NEXT_STEPS D3 already identify as the wrong shape.
%   Settling it needs one trace that provably starts at the magazine - lab item
%   A16, now the highest-value item on that list.
%
% The extraction is now reproducible: Project_Notes/tools/read_scada_history.py
% regenerates the JSON from the SCADA database, read-only, and writes the
% instrument's own limits into the file so this cannot be forgotten twice.

%% ---- 13I. THE 2026-09-01 "TRACE" IS THE SIMULATOR, 2026-09-07 ----------
% The single most important correction in this file. It invalidates 13G
% entirely, invalidates 13H's conclusions, and moves the model's known error
% against the real cell from "within 5%" to "a factor of three and a half".
%
% Raised by the machine's owner on the pre-filled intake sheet
% (Project_Notes/Engraving_Cell_Intake_Sheet_PREFILLED.docx, 2026-09-07) and
% then VERIFIED HERE against the SCADA application's own source. The
% verification, not the claim, is what follows.
%
% THE PROOF. new_scada/backend/plc/simulator.py, in its seed routine:
%
%     line  84   self._write("pressure.value", 6.2)
%     line  85   self._write("pressure.normx", 0.72)
%     line  86-87 pressure low_limit 0.0 / high_limit 10.0
%     line  88   self._write("sensor.pgm_low_limit", True)
%     line  79-82 magazine.1..5  ok True, low False, empty False
%     line  91-93 conveyor.1..3  homed_fb True, set_velocity 0.15,
%                                position_fb 30.0
%
% Now compare that with every figure 13G and 13H drew out of the recording:
%
%   pressure 6.2 bar, constant across 142 samples ......... simulator line 84
%   normx 0.72, which is NOT 6.2/10 and puzzled 13H ....... simulator line 85
%   all five magazine compartments ok, none low/empty ..... simulator line 79
%   all three axes homed ................................. simulator line 91
%   set_velocity 0.150 on all three ...................... simulator line 92
%   position_fb 30.0 "and never moves" ................... simulator line 93
%
% Six for six. The "158-tag snapshot of the machine at rest" is a snapshot of
% a Python object. The "30.0 with no unit" puzzle that survived three sessions
% is a seed constant. And the 0.150 m/s that 13H promoted to [PLC] as an
% observed machine value is THIS MODEL'S OWN P.v_belt, handed back to it
% through a stand-in - which is why it matched so beautifully.
%
% WHY IT LOOKED REAL, and this is the part worth remembering. The recording
% carries source_id "plc", the config says plc.simulate = false, and the
% lifecycle shows source DISCONNECTED -> PLC_CONNECTED. All three were cited
% in 13G as proof. None of them is. state_history holds a fourth field that
% nothing looked at:
%
%     11:25:51   connection   None -> SIMULATED
%     11:25:52   source       DISCONNECTED -> PLC_CONNECTED
%
% and no connection transition afterwards, so SIMULATED stood through both
% cycles. backend/sources/plc_source.py:58 maps it deliberately:
%
%     "SIMULATED": SRC_CONNECTED
%
% with the comment "from the core's point of view the offline PLC stand-in
% behaves like a healthy controller". The application is not lying; it is
% documented behaviour. The reader assumed source_id named a machine when it
% names an ADAPTER.
%
%   >>> A DATA SOURCE THAT REPORTS ITSELF HEALTHY IS NOT REPORTING THAT IT IS
%   >>> REAL. Check what produced the numbers before auditing what they mean.
%
% WHAT THE REAL CELL DOES. From the owner's sheet - five real cycles across
% three days, recorded and read live off the controller at 13:50 on
% 2026-09-07. These are NOT verified here; they are the owner's figures and
% they are tagged as such wherever used.
%
%   whole cycle, start to bin        90.0, 68.9, 72.1, 70.5, 79.7 s
%   less the operator dwell          61.3, 63.0, 63.4, 63.2, 62.2 s
%   THIS MODEL                       33.840 s total, 21.340 s machine time
%
%   >>> THE MODEL IS ABOUT 2.9x TOO FAST, not 5% too slow. A two-second
%   >>> spread across five cycles on three different days is not operator
%   >>> variance; it is a machine that takes a minute to do what the model
%   >>> does in twenty-one seconds.
%
%   >>> UPDATED 2026-09-07. This read 31.080 / 18.580 s and "about 3.4x too
%   >>> fast" until CYL_A's real bore was applied from a nameplate (13J),
%   >>> which cost 2.76 s. The gap closed from 3.35x to 2.91x. It is worth
%   >>> being precise about what that does and does not mean: one corrected
%   >>> parameter moved the model 9 % toward the machine and left 191 % of
%   >>> the gap in place. Nine barrels are still unread and every one of
%   >>> them is a chamber whose size is a guess, so this direction is worth
%   >>> pursuing - but a 2.9x gap is not going to close on bores alone.
%
% And the engraving platform, which 13G said rose in 1.533 s, really takes
% 7.7-8.3 s in each direction - the two limit inputs are that far apart in
% every real cycle. Axis_1 is JOGGED at velocity 72.0 until a limit trips; it
% is not driven to a position. Section 8's model of that axis needs rebuilding
% against those numbers, and NEXT_STEPS D3 is now a much larger job than the
% "replace three [PLH] steps" it was written as.
%
% FOUR MORE CORRECTIONS FROM THE SHEET, none applied, each needing a decision:
%
%   1. SOLENOID 11 NEVER FIRES IN A REAL CYCLE. The engrave-to-conveyor-3 move
%      is made by CYLINDER B, coils 9/10. FACTORY_ACTUATORS has #8 CYL_B on
%      the engrave->c3_load leg and #9 XFER_CV2_CV3 on coil 11, and 13G cited
%      the simulator's solenoid-11 firing as independent confirmation of that
%      arrangement. It confirmed nothing. Note the shape of this: the owner
%      said cylinder B does this job, the simulator disagreed, and the
%      simulator was believed. Lab item A1/A3.
%   2. SOLENOID 13 NEVER FIRES AND PROXIMITY 10 NEVER TRIPS in any real cycle.
%      Actuator #11 OUTFEED_B and the c3_out_b waypoint rest on symmetry with
%      solenoid 12 / prox 9, and nothing has ever observed them.
%   3. PROXIMITY 9 IS NEAR THE START OF CONVEYOR 3, not the far end - it trips
%      1.02 s after that belt starts and gates the outfeed immediately.
%      Proximity 7 is nearer the END of conveyor 2 than its middle, despite
%      the PLC's own "WP IN CV2 MID" network title.
%   4. THE FOUR REGULATORS READ 4.3 bar, and supply never rose above 4.380 bar
%      in any real recording, dipping to 4.03 on actuation. P.P_set = 5.5 is
%      too high and there is no 6/8 bar sawtooth anywhere. This agrees with
%      P.MEAS.P_res_0_bar = 4.3, measured by hand on 2026-08-25 - the one
%      figure in this area that was right all along.
%
% THE BELT SETPOINT IS NOT 0.150 AND NOT KNOWN. The real axes read
% Set_Velocity = 180.0, with HighSpeed_Velocity and LowSpeed_Velocity also
% 180.0, in a unit the technology object does not state. So 13H's other
% conclusion - that MODE_HIGH_SPEED "selects nothing" because the profiles are
% 0.0 - is also simulator noise; on the real machine all three profiles are
% populated and equal. P.v_belt is back to [ASM]; see section 7.
%
% THE CONVEYOR POSITION FEEDBACK DOES MOVE. Conv1 swept 2.0 -> 25.0 during a
% real cycle, Conv2 1.8 -> 30.0, Conv3 2.0 -> 30.15. The "it is not a position
% feedback at all" reading in 13G item 6 was the simulator's frozen 30.0. The
% unit is still unknown and the P1/P2/tape test is still the way to settle it.
%
% THE VIDEO, Project_Notes/Wood Carving.mp4, 105.5 s at 25 fps. What it
% settles and what it cannot:
%
%   - The engraver is a commercial DAJA enclosed DIODE LASER - the beam is
%     plainly violet. The workpiece is presented into its bed by a vertical
%     axis; the block is visible on a platform below the unit between two
%     upright rails. That is consistent with section 8 modelling a driven
%     vertical axis rather than a pneumatic cylinder.
%   - IT CANNOT TIME ANYTHING. It is an EDITED COMPILATION: 16 shots, cut
%     boundaries at 3.75, 7.5, 9.0, 10.5, 14.25, 15.75, 27.0, 29.0, 41.5,
%     49.25, 55.5, 62.75, 66.25, 89.75 and 96.75 s, each with a step change in
%     mean frame brightness. Its 105.5 s is a duration of FOOTAGE. Reading a
%     cycle time off it would repeat, in a third instrument, exactly the
%     mistake 13G made in the first.
%
% Method note: the cut list and the laser-on windows were measured, not
% eyeballed - per-frame violet-pixel fraction and inter-frame difference at
% 0.25 s, MATLAB VideoReader.
%
% ADDENDUM 2026-09-10 - extends the above, supersedes none of it. Full note:
% Project_Notes/VIDEO_REFERENCE.md.
%   - The cut list is REPRODUCED: an independent detector found 15 of 15
%     boundaries within 0.3 s, none missing, none extra.
%   - Nor can the promo time a motion WITHIN one shot. The same S2A1 push
%     takes >= 6.5 s in shot 15.75-27.0 and 3.4 +/- 0.5 s in the phone take
%     below - about 2x. Slowed footage or different flow settings; either
%     way not a clock.
%   - BITS_MCD_project/.../Engraving process_Video.mp4 is a CONTINUOUS phone
%     take of one whole cycle (67.5 s, no cut, no duplicated frame). Not
%     clock-calibrated and of unknown date, so +/- 1 s and "a machine like
%     this one". It shows the S2A1 rod done in about 3 s: the model reaches
%     95% stroke in 2.63 s. So of the 8.059 s cylinder-A hold, about 5 s is
%     timer with the rod home - the 2026-09-08 refusal to close the meter-out
%     needle to match 8.059 s was right.
%   - It also shows the block riding belt 3 for roughly 5 s, against a single
%     recorded 1.024 s. That is a caution on the n=1 figure, not a value to
%     apply. Nothing in this addendum changes a parameter.

%% ---- 13J. NAMEPLATES AND THE FILLED INTAKE SHEET, 2026-09-07 -----------
% Sources, both new on 2026-09-07:
%   (a) six photographs taken at the cell, 14:10-14:23. FOUR carry a legible
%       MODEL line, between them THREE distinct nameplates; the other two show
%       the engraving platform's drive. They are filed under
%       Project_Notes/figures/cell-photos-2026-09-07/, named by capture time -
%       IMG20260907141019 is the vertical A51, 142309 the A12, 141423 the
%       motor. That folder belongs to the maintainer's working record and is
%       NOT published, so on a clone it will not be present; the readings
%       below are the part that travels.
%   (b) Project_Notes/Engraving_Cell_Intake_Sheet_PREFILLED.docx with the
%       hand-entered columns filled in.
%
% THE A51 APPEARS TWICE, on two differently mounted barrels - one vertical
% (14:10:19) and one horizontal with a rod-end clevis (14:23:13). Same model
% code on both, so the cell holds AT LEAST TWO of them. That is worth having
% because it is the kind of thing a single photograph cannot say, and because
% neither of the two is identified with an actuator.
%
% ONE THING FROM THIS IS APPLIED and everything else is RECORDED, on the same
% terms as 13B, 13C and 13D. The applied item is CYL_A's bore; it is in
% FACTORY_ACTUATORS, not here, because that is where per-actuator bores live.
%
% ==== 1. THE BARREL NAMEPLATES. QUESTION 14 IS ANSWERED, IN PART. =========
%
% Question 14 has blocked structural work since 2026-08-25: the CAD says the
% cell runs bore 8 and bore 32, JANATICSDATA assumed 20 for all six barrels,
% and nothing said WHICH cylinder was which. Two labels have now been read.
%
%     A120323000   Janatics A12, bore 32, stroke 300, MAX.PR 10 bar
%     A510251600   Janatics A51, bore 25, stroke 160, MAX.PR 10 bar
%
% The code's structure and the four independent corroborations of how it is
% read are in JANATICSDATA section 1B. The values are J.NP.big and J.NP.mini.
P.NP.big_model   = 'A120323000';   % [MEAS] nameplate, photographed
P.NP.mini_model  = 'A510251600';   % [MEAS] nameplate, photographed
P.NP.big_bore_mm  = 32;   % [MEAS] nameplate "032"                       mm
P.NP.big_stroke_mm = 300; % [MEAS] nameplate "300"                       mm
P.NP.mini_bore_mm = 25;   % [MEAS] nameplate "025"                       mm
P.NP.mini_stroke_mm = 160;% [MEAS] nameplate "160"                       mm
%
% SUPERSEDES 13D. That section records "The model number begins A6... and does
% NOT resolve further at this resolution. It is NOT transcribed here." The
% series is A5, not A6, and the whole code resolves at full resolution. 13D
% was right to refuse to transcribe a label it could not read - the note is
% kept exactly as written, because declining to guess is what made this
% correction a correction rather than a contradiction.
%
% THE BORE 20 ASSUMPTION IS NOW POSITIVELY REFUTED, not merely doubted. Three
% sources - CAD geometry, CAD part names, and two nameplates - and bore 20
% appears in none of them. At 6 bar, cap side, as raw P*A - the same
% convention 13B's table uses, so the two are directly comparable:
%     bore  8  ->   30 N      [CAD] candidate, unread barrel
%     bore 20  ->  188 N      what JANATICSDATA assumed for all six
%     bore 25  ->  295 N      [MEAS] A51 nameplate
%     bore 32  ->  482 N      [MEAS] A12 nameplate
% CYL_A therefore gained 2.56x its cap-side force and 2.62x its annulus.
%
% WHICH BARREL IS WHICH is still only answered for ONE actuator, and only by
% inference from stroke. The section A panel test - energise %Q3.6, then
% %Q2.5, and watch which rod extends - was NOT done and is still the thing
% that would confirm it. See FACTORY_ACTUATORS for the CYL_A reasoning.
%
% ==== 1B. WHAT THE BORE CHANGE COST, AND WHY HALF OF IT IS AN ARTEFACT ===
%
% Applying CYL_A's bore moved the cycle 31.080 -> 33.840 s and the air per
% cycle 6.094 -> 8.202 NL. It is tempting to read all of that as "a bigger
% cylinder takes longer", and to read the direction - the model is now 2.91x
% too fast instead of 3.35x - as support for the bore. Only part of that is
% honest, and the dishonest part must be said plainly because it points the
% same way as the honest part, which is the worst case.
%
% THE PART THAT IS REAL. CYL_A's chambers grew 2.6x at an unchanged 300 mm
% stroke, so branch 2 has 2.6x as much volume to charge. That is unavoidable
% physics and it is where the air goes.
%
% THE PART THAT IS AN ARTEFACT. The rod speed is not set by the bore. It is
% set by the METER-OUT NEEDLE, P.C_ctrl_B, and that is a [COMM] value - a
% fitter's screwdriver setting, not a component property. JANATICSDATA chose
% it, in Iteration 02, to produce 0.20 m/s extend ON A BORE-20 CYLINDER:
%
%     J.C.exh_extend  = 5.2929e-10;   % [COMM] vents chamber B -> 0.20 m/s
%
% Venting a 2.6x larger annulus through the same orifice gives a mean extend
% speed of 0.098 m/s, roughly half. So CYL_A's extend takes 2.69 s where it
% took about one second, and a good part of the 2.76 s is that.
%
% ON THE REAL MACHINE THAT NEEDLE WOULD HAVE BEEN SET FOR THE CYLINDER THAT
% IS ACTUALLY FITTED. Nobody buys a bore-32 cylinder and leaves the speed
% controller where it was for a bore-20 one; the rod would crawl and the
% fitter would open the needle until it did not. The model now carries a real
% bore behind a commissioning setting that was never measured for it.
%
% WHY THIS IS NOT FIXED HERE. Opening the needle to restore 0.20 m/s would be
% inventing a second number to make the first one comfortable, and the whole
% point of applying a nameplate is to stop doing that. P.C_ctrl_B has always
% been [COMM] and has always been unmeasured; what changed today is that its
% wrongness became visible, which is an improvement. The measurement that
% closes it is on the intake sheet already - time a rod over its stroke, or
% read the needle's turns-open - and it is now worth more than it was.
%
% CONSEQUENCE FOR THE HEADLINE. "The gap closed from 3.35x to 2.91x" is true
% and it is weaker evidence than it looks, because a mismatched speed
% controller closes that gap for a reason that has nothing to do with the
% cell. Do not quote the direction as corroboration of the bore without
% quoting this paragraph with it. The bore is corroborated by the STROKE
% agreeing three ways; that argument stands on its own and does not need the
% cycle time.
%
% ==== 2. THE UNIT TRAP, CAUGHT BY THE MAGAZINE ===========================
%
% The intake sheet's own instruction is "Write millimetres, not centimetres",
% printed there because the 2026-08-25 readings were taken in cm and entered
% into mm columns. It happened again. The sensor column reads
%     0mm, 12cm, 23cm, 34cm, 46cm, 56cm, 86cm, 110cm, 162cm, 172cm
% - the writer switched to cm at the second row and stayed there.
%
% THE CHECK THAT SETTLES IT is the one CLAUDE.md asks for: test a hand-entered
% measurement against known geometry before believing it. Sensors 1-5 are the
% five magazine dispense confirms, one per compartment, so the gaps between
% them ARE the magazine slot pitch:
%     12->0, 23->12, 34->23, 46->34   =   120, 110, 110, 120 mm, mean 115
% The CAD measures the magazine's five slots at 105-110 mm across
% (P.CAD.mag_slot_mm), and a 100 mm block has to fit in one. Read as cm the
% column agrees with the CAD to 5-10 mm. Read as mm it makes the pitch 11.5 mm
% - a magazine narrower than the block it holds. The unit is CENTIMETRES and
% it is not a judgement call.
%
% P.mag_pitch IS NOT CHANGED, and the arithmetic is worth stating exactly
% rather than rounding in the model's favour. The measured mean is 115 mm and
% the CAD range is 105-110, so 115 sits 5 mm ABOVE the top of it - agreeing
% with the CAD, not falling inside it. That 5 mm is inside the measurement's
% own resolution: the column was written to whole centimetres, so each entry
% carries +-10 mm and a pitch differenced from two of them carries more. A
% reading that cannot resolve better than the value it is being compared to
% cannot improve that value, so this is corroboration and nothing else.
% Confirming a value and improving one are different acts, and the [CAD]
% 110 mm stays.
%
% ==== 3. THE TEN SENSOR POSITIONS, AND WHAT THEY OVERTURN ================
%
% Read as centimetres, and with the sheet's own note - "measured from when the
% block arrives at starting position" - these are distances along the block's
% route from the compartment-1 load point. Against the model's cumulative path
% (initialize_factory section 1, waypoints x P.SCALE):
%
%   sensor   measured   model    delta   what the model has it as
%   PX01        0        0.0        0    compartment 1  [datum]
%   PX02      120      110.0      +10    compartment 2
%   PX03      230      220.0      +10    compartment 3
%   PX04      340      330.0      +10    compartment 4
%   PX05      460      440.0      +20    compartment 5
%   PX06      560      632.5    -72.5    c1_end
%   PX07      860      850.0      +10    c2_mid
%   PX08     1100      960.0     +140    c2_end
%   PX09     1620     1881.0     -261    c3_end
%   PX10     1720     1695.0      +25    c3_out_b, the assumed 60 % point
%
% Six of the ten land within 25 mm of a layout derived from a schematic
% drawing scaled by 0.1. That is a better result than this project had any
% right to expect and it is a real check on P.SCALE and on the waypoints.
%
% THREE DISAGREEMENTS, and two of them are corroborated by the recorder:
%
%   PX09 IS NEAR THE START OF CONVEYOR 3, NOT AT ITS END. Measured 1620 mm is
%   204 mm into a 465 mm belt run, 44 % along. The recorder says PX09 trips
%   1.02 s after conveyor 3 starts. At a belt speed of 0.15-0.20 m/s, 1.02 s
%   is 153-204 mm. TWO INSTRUMENTS, TAKEN ON DIFFERENT DAYS BY DIFFERENT
%   MEANS, AGREE. The model puts PX09 at c3_end, 465 mm along, and that is
%   wrong. It matters because PX09 gates STOP_CONV3 and the 5 s outfeed pulse
%   that ENDS every recorded cycle: the block stops much earlier on belt 3
%   than the model has it stopping.
%
%   PX08 IS PAST c2_end, ON THE BYPASS RUN. Measured 1100 mm is 140 mm beyond
%   c2_end, i.e. 69 % of the 203.5 mm run down to c2_byp, where a NON-ENGRAVED
%   block goes.
%   The recorder says PX08 never tripped in the fully-watched cycle, and the
%   sheet asks whether it is "in the path at all". If it sits past c2_end then
%   an engraved block stops before reaching it and NEVER TRIPS IT - which is
%   exactly what was recorded. The measurement explains the recording.
%
%   PX10 IS 100 mm PAST PX09, NOT UPSTREAM OF IT. The model puts outfeed B
%   BEFORE outfeed A on belt 3, at an assumed 60 % of the run; the measurement
%   puts PX10 at 65 % - the assumed fraction was nearly right - but PX09 at
%   44 %, so the ORDER is reversed. Station B is downstream of station A.
%
% NOT APPLIED, and this is a decision rather than an omission. Moving PX09
% moves the outfeed station with it - the ejector must stand where its sensor
% is - which moves the c3_end waypoint, OUTFEED_A's geometry, the bin, and the
% support region under both. That is a layout change, not a parameter change,
% and it deserves its own iteration with its own before-and-after. What is
% needed first is the belt-by-belt datum: these ten readings are cumulative
% path distance and the model's waypoints are cell coordinates, so mapping one
% onto the other needs to know where each belt starts. INPUTS_REQUIRED
% question 4b is now answerable and is upgraded from "unknown" to "measured,
% needs a datum".
% [APPLIED FOR BELT 3, 2026-09-12, plan H3. The belt-by-belt datums came in
% on 2026-09-10 (Project_Notes/to_matlab/round2_2026-09-10/
% PROX_POSITIONS_MEASURED_2026-09-10.md). PX09 and outfeed A now stand at
% 43 cm along belt 3 (c3_end 15.100 -> 12.900), PX10 and outfeed B at 55 cm,
% downstream. Belt 2, measured from its own start, already agreed with the
% tape and did not move. See INITIALIZE_FACTORY section 1.]
% Path distance from the compartment-1 load point, sensors 1-10 in the
% machine's own numbering. Written as a continuation so the tag sits on the
% ASSIGNMENT line - AUDIT_PROVENANCE reads assignment lines only, and a tag
% parked on the line below is a tag that does not exist as far as the audit
% and README section 10 are concerned.
P.MEAS.prox_path_mm = ...   % [MEAS] intake sheet, cm read as mm         mm
    [0 120 230 340 460 560 860 1100 1620 1720];
%
% ==== 4. THE CYLINDER STROKES, AND ONE CONFLICT ==========================
%
% Same sheet, same hand, same sitting, and by section 2 above the same
% centimetres. Section C reads: cylinder A 29, cylinder B 17, magazine pusher
% 20 - so 290, 170 and 200 mm.
%
%   CYLINDER A   290 mm measured, 300 mm stamped on the A12 nameplate, 300 mm
%                DERIVED by this model from the layout before either was
%                known. Three sources, one answer. This is what made CYL_A's
%                bore safe to apply.
%   PUSHER       200 mm, which matches neither nameplate. The magazine pushers
%                are a THIRD barrel and nobody has read its label. The CAD's
%                bore 8 stays a candidate and stays unapplied.
%   CYLINDER B   170 mm measured, against 160 mm stamped on the A51 nameplate
%                - and against 252.5 mm of travel that THIS MODEL GIVES IT.
%
% THAT LAST ROW IS A CONFLICT AND IT IS THE MOST USEFUL THING ON THE SHEET.
% A 160 mm cylinder cannot make a 252.5 mm push. Either the measurement is of
% something else, or CYL_B is placed wrongly. CYL_B's placement came from the
% owner's own drawing and has already been wrong twice (FACTORY_ACTUATORS
% keeps both), so it is not a placement to defend on habit. Nothing is changed
% on one hand-written figure whose unit had to be inferred; what is recorded is
% that the next reading of that barrel decides between two live possibilities.
P.MEAS.cylA_stroke_mm = 290;  % [MEAS] intake sheet, cm read as mm        mm
P.MEAS.cylB_stroke_mm = 170;  % [MEAS] intake sheet - CONFLICTS, see above mm
P.MEAS.push_stroke_mm = 200;  % [MEAS] intake sheet, cm read as mm        mm
%
% ==== 5. THE MOTOR NAMEPLATE. THE FIRST ONE THIS PROJECT HAS EVER HAD. ====
%
% JK42HS34-1334, on a motor bolted under the engraving platform's board with
% its shaft coupled upward. A NEMA 17 hybrid stepper: 42 mm frame, 34 mm body.
P.NP.motor_model = 'JK42HS34-1334';  % [MEAS] motor nameplate, photographed
%
% WHAT IT CONFIRMS. Section 7 calls the conveyor drives "generic 3-phase" and
% 13E records the owner saying they are electric; the PLC carries three
% Stepper Technology Objects and the outputs pul+ / dir+ / pot_1_pulse+. A
% stepper nameplate on the cell agrees with all of that. The drives are
% steppers and the "generic 3-phase" description in section 7 is wrong.
%
% WHAT IT DOES NOT SETTLE, AND WHY NOTHING IN SECTION 7 MOVED. The photograph
% does not say WHICH axis this motor drives - the cell has four stepper axes
% (three conveyors and the engraving platform) and this label was read off
% one of them. Worse, section 7's drivetrain is a matched set of assumptions:
% P.N_gear = 20 with P.T_max = 0.050 N*m. A NEMA 17 of this size holds roughly
% 0.26-0.28 N*m with a rotor inertia near 3.4e-6 kg*m^2 - so applying the
% motor alone would put 5.6 N*m at a pulley carrying a 0.3 kg block through an
% invented 20:1 gearbox. Replacing ONE number of a self-consistent invented
% set with a real one makes the set less coherent, not more. The whole
% subsystem - ratio, pulley radius, inertia, torque - has to be read together.
% INPUTS_REQUIRED question 19 stays open and gets more specific.
%
% ==== 6. THE ENGRAVING PLATFORM'S DRIVE, SEEN =============================
%
% Two photographs show the vertical axis: a threaded rod running in a bronze
% flange nut between black guide rails, with a Janatics profile cylinder
% mounted horizontally above it. Section 8 models the base as a driven
% vertical axis on the strength of Sequence.xlsx step 25 having no valve in
% its chain. That inference is now confirmed by looking at it.
%
% The thread is a V-form metric coarse thread, NOT a Tr8x2 trapezoidal lead
% screw. Measured off the photograph rather than eyeballed: the pitch-to-outer-
% diameter ratio is 0.161 and 0.175 in two independent bands of the rod, by
% autocorrelation of the intensity profile along the rod axis against the rod
% width in the same band. Metric coarse runs 0.156 (M8x1.25) to 0.15 (M10x1.5);
% Tr8x2 would be 0.25. The distinction matters because it sets travel per
% revolution, and the two differ by 1.6x.
%
% NOT APPLIED. A ratio off a photograph identifies a thread FORM; it does not
% give a lead, and section 8 is a force-limited PID axis that has no lead in it
% to give. What the section-8 axis actually needs is its TRAVEL TIME, and the
% intake sheet has that from the recorder: 7.7-8.3 s between the two limit
% switches, in both directions, in every recorded cycle. P.z_top = 0.050 m is
% still [ASM] and the axis has no explicit travel time; reconciling the two is
% a section-8 task and is listed in NEXT_STEPS rather than done here.
P.MEAS.base_travel_s = [7.7 8.3];  % [MEAS] limit-switch to limit-switch,
                                   % both directions, five recorded cycles  s
%
% ==== 7. WHAT THE SHEET STILL DOES NOT ANSWER =============================
%
% Named here so the next session does not re-read the document to find out.
% Every one of these was on the sheet and came back blank:
%   - the section A panel test. Which rod extends on %Q3.6 and on %Q2.5, and
%     whether the two valve bodies really are double-solenoid. Five minutes.
%   - what solenoids 6, 11, 12 and 13 physically move.
%   - the sensor TRIP DISTANCE against a real block. The column that asked for
%     it was filled with positions instead, so the 125 mm rated-range oddity
%     is exactly as open as it was and P.prox_rng = 0.030 is still [EST].
%   - the stopwatch columns 6-8, the regulator faces, the compressor dial,
%     belt speed measured, the conveyor position unit, PLC scan time.
%   - the bore stamps on the magazine pushers and the four unread barrels.
%
% AND THE ONE THAT MATTERS MOST IS UNCHANGED. The real cell takes 69-90 s per
% cycle, about 62 s of it machine time, against this model's 21.34 s of
% machine time (18.58 s before this section's own bore change). Nothing on this sheet touches that. Section 13I is still the
% project's honest position and NEXT_STEPS section F is still what to do
% about it.

% ---- 13J ADDENDUM, 2026-09-10: SIX MORE BARRELS, LABELLED AT THE CELL ----
% RECORDED, NOT APPLIED. Full note: Project_Notes/CYLINDER_PHOTOS_2026-09-10.md
% Six photographs 11:57-11:59, labelled by hand afterwards by the maintainer:
%
%     hand label    nameplate      reads as
%     Cylinder A    A120323000     A12, bore 32, stroke 300
%     Cylinder B    A280323000     A28, bore 32, stroke 300   NEW CODE
%     xfer.1        A510251600     A51, bore 25, stroke 160
%     SV-2          A510251600     A51, bore 25, stroke 160
%     (none)        A510251600     A51, bore 25, stroke 160
%     (none)        A520251600     A52, bore 25, stroke 160   NEW CODE, MAGNETIC
%
% The two new codes were anticipated: the vendor CAD folders are named
% "Janatics-A27,A28" and "Janatics-A51,A52" (JANATICSDATA 1B). Same
% ten-character scheme.
%
% WHAT IT SETTLES:
%   - CYL_A IS the A12. The 2026-09-07 assignment was inferred from stroke; it
%     is now identified at the machine. Already applied; nothing changes.
%   - XFER_CV1_CV2 (xfer1) is an A51 - bore 25, not the bore 20 it carries.
%   - MAG2_PUSH is an A51, via "SV-2" and the CONFIRMED io-map row for
%     Solenoid_valve2. That SUPERSEDES the reading that the magazine pushers
%     are a third barrel type (INPUTS_REQUIRED 14): the stamp says 160 and the
%     hand-measured 200 mm does not survive it. Only MAG2 has been read.
%   - The barrel labelled Cylinder B has stroke 300. The model gives CYL_B a
%     208.5 mm travel, rounded up to a 250 mm standard stroke; 300 covers it
%     and a 160-170 mm barrel could not, so the intake sheet's 170 mm is not
%     that barrel's stroke. (First drafted as "252.5 mm" - CYL_B's travel in
%     its superseded 2026-09-02 placement, quoted rather than computed.)
% WHAT IT DOES NOT SETTLE: whether "cylinder 3" is that barrel - see the
% 2026-09-10 note at the end of 13M.
% No bore is applied here. Each is a re-baseline under rule 1: bore 20 -> 25
% is 1.56x force, 20 -> 32 is 2.56x.
% [APPLIED 2026-09-13, plan H7: all of them - MAG1/3/4/5 as A51 on the
% maintainer's word, SV11/SV12 A51 and SV13 A52 from the 2026-09-10 evening
% photographs - with their stamped strokes. See FACTORY_ACTUATORS.]

%% ---- 13K. THE PROGRAM'S OWN TIMER PRESETS, 2026-09-08 ------------------
% RECORDED, NOT APPLIED, on the same terms as 13B, 13C, 13D and 13J.
%
% Source: Project_Notes/plc_listing_extracted.txt, the decoded TIA Portal
% export, re-read on 2026-09-08 for T#<n> literals specifically. 46 presets
% found. This is the first time the TIMER VALUES have been pulled out as a set
% rather than encountered one at a time while reading networks.
%
% WHY IT MATTERS. The model's remaining error is ~25 s of machine time, and
% 13J item 3 named the machine's FC6 dwell timers as the largest identified
% cause. Those timers are not an inference any more - they are literals in the
% program text, and they corroborate the 2026-08-30 network decode exactly.
%
% THE PRESETS, and what sits next to each in the text:
%
%   T#0.1S  x21   every solenoid coil and every conveyor, in one block.
%                 This is FC3 solenoid_manual's per-coil debounce on the
%                 MANUAL command page. NOT sequence timing - do not add it.
%   T#0.5S  x2    solenoid_valve_7 and _9, the two cylinder EXTEND coils
%   T#1S    x1    next to pgm_cylA and Axis_1
%   T#2S    x5    one of them unambiguously next to conveyor_1 AND
%                 solenoid_valve_6 - this is FC6 N4's "2 s TON after
%                 wp_in_cv1_end", read independently of the network decode
%   T#5S    x2    both next to solenoid_valve_12 and _13 - FC6 N16's outfeed
%                 pulse, again confirming the decode
%   T#8S    x2    in the timer-instance block near solenoid_valve_8/9/10
%   T#10S   x3    one next to CMD_START - the cycle watchdog 13C recorded
%   T#12S   x2    next to pgm_cylA and pgm_cylB
%
% TWO INDEPENDENT CONFIRMATIONS OF 13C, which was decoded from the networks
% and is now confirmed from the literals: solenoid 6 carries a 2 s timer and
% sits beside conveyor 1, and solenoids 12/13 carry 5 s timers. Two different
% readings of the same export, agreeing.
P.PGM.t_sv6_ton   = 2.0;   % [PLC] T#2S beside conveyor_1 / solenoid_valve_6  s
P.PGM.t_sv12_tp   = 5.0;   % [PLC] T#5S beside solenoid_valve_12 / _13        s
P.PGM.t_watchdog  = 10.0;  % [PLC] T#10S beside CMD_START                     s
P.PGM.t_manual_db = 0.1;   % [PLC] T#0.1S, FC3 manual-page debounce           s
%
% THE T#8S IS NOT CLAIMED AS THE PLATFORM, and the temptation is worth naming.
% Section 8 sets P.t_base_travel = 8.0 s from recorded limit-switch intervals,
% and the program contains two T#8S presets - which looks like a beautiful
% independent confirmation. IT IS NOT ONE. Both T#8S literals sit in the
% timer-instance block beside solenoid_valve_8, _9 and _10, not beside Axis_1
% or either limit switch. Reading them as the platform would be exactly the
% mistake 13C already records: taking proximity in a glyph-level PDF decode
% for a connection in the ladder. The 8.0 s stands on the recorded limit
% inputs alone, which is enough.
%
% WHAT THIS DOES NOT SETTLE, and it is the useful question:
%
%   The T#12S beside pgm_cylA. The owner's sheet records "cylinder A retract
%   coil energised 11.99 s", which is suspiciously close to that preset - but
%   11.99 s is a TIME FROM CYCLE START in that table, not a duration, and the
%   same table puts the extend coil at 8.13 s. So the machine holds cylinder A
%   extended for about 3.9 s, against this model's 2.7 s. Whether T#12S is
%   measured from cycle start, from the extend, or from something else is NOT
%   resolvable from the text dump, and the difference between those readings
%   is several seconds of cycle time. It needs the ladder read in TIA Portal,
%   or the transition log timed - both of which live on the SCADA machine.
%
% NOTHING HERE IS APPLIED. The model's sequencer walks Sequence.xlsx's 40
% states and the machine's walks FC6's 17 networks, and those are not the same
% sequence; dropping FC6's timers into a different state machine would produce
% a cycle time that matches for the wrong reason. Reconciling the two is a
% plant re-model, and it is now the largest identified piece of work left.
% See Project_Notes/SCADA_PC_BRIEF.md, which asks for exactly what would
% settle it.

%% ---- 13L. TEN REAL CYCLES, AND WHAT THEY CHANGED, 2026-09-08 -----------
% APPLIED, not merely recorded - the first section here that is. Source:
% Project_Notes/to_matlab/, extracted from the machine's own history database
% on the SCADA PC and sent back as model_parameters.json + cell_timings.json.
%
% TWELVE cycles in the database, TWO excluded as the portal's simulator, TEN
% genuine. Of those, SIX are complete cycles and exactly ONE - C0003-180221,
% 09-01 18:02 - was recorded with all 158 tags watched. That single cycle is
% why several figures below carry n=1 while others carry n=7 or n=10.
%
% ==== WHAT WAS APPLIED ====================================================
%
% 1. THE SUPPLY PRESSURE, section 4. 4.3 bar gauge, from 37 samples reading
%    4.03-4.38 and all four regulator faces. The model assumed 5.5e5 Pa abs at
%    the receiver and 6.0 bar gauge at the regulator. NEXT_STEPS F6, closed.
%
% 2. THREE SEQUENCER DWELLS, section 12 (P.PLC.t_*), wired into FACTORY_PLC.
%    The model had none. See the note there for why they are dwells and not
%    slow actuators - it is the whole point and it decides the physics.
%
% 3. THE PLATFORM'S UP/DOWN ASYMMETRY, section 8. 7.785 s rising and 8.166 s
%    falling over seven cycles, where the model used 8.0 s both ways.
%
% ==== A COUPLING THAT BROKE, AND IS NOW STRUCTURALLY FIXED ================
%
% Dropping the regulator to 4.3 bar stalled the cycle outright: it ran to the
% 90 s horizon having moved 0.756 NL of air. P.P_br_rdy - the branch-charged
% guard - was a free-standing 5.5e5 Pa ABSOLUTE, sized when the regulator was
% assumed to be 6.0 bar. The new set point is 5.32e5 absolute, BELOW it, so
% BR_RDY could never become true.
%
% Nothing was wrong with the measurement; the guard was expressed in units
% that could not follow it. It is now a FRACTION of the regulated supply,
% which is what "this branch has charged enough to actuate" always meant. A
% regulator change cannot leave it behind again. The fraction was chosen to
% reproduce the old absolute value at the old set point, so only the pressure
% moved and not the guard's strictness.
%
% ==== THE TEMPTATION THAT WAS REFUSED =====================================
%
% Cylinder A's extend-to-retract interval measures 8.059 s against the model's
% 2.72 s. The obvious move is to close the meter-out needle - P.C_ctrl_B, a
% [COMM] value nobody has measured - until the modelled rod takes 8 s too.
%
% THAT WOULD HAVE BEEN WRONG, and it would have produced exactly the right
% cycle time. The machine has NO CYLINDER POSITION FEEDBACK: 13D established
% that the 158-tag register carries none and that the PLC latches
% pgm_cylA_Ext rather than reading a switch. A controller that cannot see the
% rod is not waiting for it - it is running a timer, and the real rod almost
% certainly arrives early and then sits. Modelling that as a slow rod would
% have mis-set a commissioning value AND hidden a dwell, while the clock
% agreed. The rod keeps its speed; the sequencer waits.
%
% ==== WHERE THE MODEL NOW STANDS ==========================================
P.REAL.t_machine_meas   = 64.03;  % [PLC] measured machine time, n=6      s
P.REAL.t_machine_spread = [61.25 73.99];  % [PLC] min/max of the six      s
P.REAL.t_cycle_meas     = 79.35;  % [PLC] whole cycle, mean of six        s
%
%   model machine time   48.640 s   (was 36.790 this morning, 18.580 on 09-06)
%   measured             64.030 s
%   gap                  1.32x      (was 1.69x, and 3.4x two days ago)
%
% ABOUT 15 s IS STILL MISSING, and the returned analysis names where it is
% thought to be: the magazine dispense, the retract strokes, and the waits
% between sequencer steps that nobody has instrumented. The raw transition
% timeline for every real cycle travels inside cell_timings.json, so that can
% be chased without another trip to the machine.
%
% ==== WHAT THE DATA CORRECTS, BEYOND THE NUMBERS APPLIED ==================
%
% THE OPERATOR BLOCK IS NOT A CONSTANT AND SHOULD NOT BE ONE. The model's
% invented 12.5 s lands near the measured mean of 13.98 s, which flatters it.
% The RANGE is 5.95 to 28.65 s with a standard deviation of 7.83 s over seven
% cycles. A single number cannot represent that, and the model currently
% predicts zero cycle-time variance against a machine whose operator supplies
% most of its spread. This is a STRUCTURAL gap, not a parameter error, and it
% is left open deliberately - see the three [PLH] values in section 10.
P.REAL.t_operator_mean   = 13.979; % [PLC] platform dwell at top, n=7      s
P.REAL.t_operator_sd     = 7.832;  % [PLC] and this is the real finding    s
P.REAL.t_operator_range  = [5.95 28.649];  % [PLC] min/max over seven      s
%
% CONVEYOR 3 IS THE ONE PLACE THE MODEL IS TOO SLOW. Measured 1.024 s against
% a modelled 3.11 s. Every other interval runs the other way. That is
% consistent with prox 9 sitting near the START of belt 3 rather than its end,
% which 13J item 3 already established from two independent instruments - so
% the belt is not slow, the block simply stops sooner. Not applied here
% because moving prox 9 moves the outfeed station, the bin and the support
% region with it; it is a layout change and it needs the belt-by-belt datum.

%% ---- 13M. SOLENOID 11 NEVER FIRES, 2026-09-08 --------------------------
% APPLIED. NEXT_STEPS F3, and it is the fourth reading this row has had.
%
% THE EVIDENCE, from the one real cycle recorded with all 158 tags watched
% (C0003-180221, in Project_Notes/to_matlab/cell_timings.json):
%
%   solenoid_valve11   DOES NOT APPEAR IN THE TIMELINE AT ALL. Not once, in a
%                      cycle where every one of the 13 coils was watched.
%   solenoid_valve9    rises at 80.751 s
%   solenoid_valve10   rises at 88.950 s
%
% That is cylinder B, held 8.199 s, in exactly the slot between the platform
% reaching bottom (78.741 s) and conveyor 3 starting (88.950 s) - the
% engraver-to-belt-3 move. The model gave that move to solenoid 11 and did it
% in 1.835 s.
%
% So the role and the geometry moved to CYL_B in FACTORY_ACTUATORS, and a
% fifth measured dwell went in with them.
P.PLC.t_cylB_hold_meas = 8.199;  % [PLC] SV9 -> SV10, n=1                   s
%
% WHAT THE SWAP ITSELF WAS WORTH: 0.01 s. The geometry was already right - the
% move is the same 203.5 mm either way - and only the actuator was wrong. All
% 7.21 s of the change is the DWELL. That is worth stating because it would
% have been easy to credit the reassignment and move on: doing the swap first
% is what let the dwell attach to the barrel that really makes the move, but
% the swap is not what moved the clock.
%
% THIS CONTRADICTS THE OWNER AND THE CONTRADICTION IS LEFT STANDING.
%
% Section 13E records the owner saying, four times and consistently, that
% cylinder B fires when engraving is SKIPPED - the 50 mm no-engrave path. The
% recording shows cylinder B firing on the ENGRAVED path. Both cannot describe
% the same cylinder.
%
% The model now follows the RECORDING for the engraving path, on the grounds
% that a transition log is an observation and a description is a memory. The
% owner's words are not edited and not withdrawn: they may still be right
% about the bypass, and if they are, the cell has cylinder B doing double duty
% and the model has only ever seen one of its two jobs.
%
% WHAT THIS DOES NOT CLAIM: that solenoid 11 does nothing. Only that nothing
% has ever seen it move. It fires in SIMULATOR runs - which is how it acquired
% the role in the first place, and is a small reminder of 13I.
%
% THE BYPASS QUESTION IS REOPENED and is now unanswered rather than answered
% wrongly. INPUTS_REQUIRED 3b - the five-minute panel test - settles it, and
% is why that test leads the lab list.
% [ANSWERED 2026-09-10 and 2026-09-11 - the round-2 note below, and section 15.]
%
% 2026-09-10 - THE MAINTAINER, AT THE CELL, adds a statement and a label, kept
% verbatim on the same terms as 13E:
%     "cylinder 3 pushes block from engraving machine to conveyor 3"
% and a barrel photographed and hand-labelled "Cylinder B" (A280323000,
% stroke 300). This SHARPENS the reopened question and does not close it:
%   R1  "cylinder 3" is the barrel labelled Cylinder B. The 2026-09-08
%       assignment of the engraver -> belt 3 move to coils 9/10 stands, and
%       the owner's bypass statement remains unexplained.
%   R2  "cylinder 3" is a THIRD barrel. Then coils 9/10 drive cylinder 3, the
%       barrel labelled Cylinder B is the owner's no-engrave bypass, and the
%       standing contradiction dissolves - owner and recording were each right
%       about a different barrel. The model row named CYL_B would be cylinder 3
%       wearing B's name.
% R2 reconciles everyone, which makes it attractive and is not evidence for
% it. Nothing is remapped. The panel test gains one column: for %Q2.5 (SV9)
% and %Q2.3 (SV11), WHICH LABELLED BARREL moves, as well as where it pushes.
%
% ROUND 2, SAME AFTERNOON - RECORDED, NOT APPLIED. Full notes in
% Project_Notes/to_matlab/round2_2026-09-10/ (README_FOR_MATLAB_CLAUDE.md,
% SEGMENT_BUDGET, PROX_POSITIONS_MEASURED) and CYLINDER_PHOTOS_2026-09-10.md.
%   - R1 IS OBSERVED. At the panel, cylinder A pushed belt 2 -> engraver and
%     cylinder B pushed engraver -> belt 3. The 2026-09-08 assignment stands,
%     now on positive observation rather than on solenoid 11's silence.
%   - THE BYPASS IS SV11 (%Q2.3), belt 2 -> belt 3 directly, per the operator.
%     SV13 (%Q2.1) is a second outfeed piston into the same bin. The owner's
%     "cylinder B is the bypass" named the wrong actuator; the route is real.
%     Neither route exists in this model yet.
%     [BUILT 2026-09-11: the SV11 bypass is section 15 and FACTORY_PLC
%     S40-S43. The SV13 lane is still not modelled as a route.]
%   - Nameplates: SV11 = A51, SV12 = A51, SV13 = A52 (magnetic), all bore 25,
%     stroke 160.
%   - THE ~10 s BEFORE THE MAGAZINE PUSH is 10.0 s in 4 of 4 cycles, and 13K
%     already records a T#10S beside CMD_START that 13C read as a cycle
%     watchdog. It behaves as a START DELAY. The model spends 2.52 s there,
%     charging to the ready threshold instead.
%   - THE TWO CLOCKS END AT DIFFERENT MOMENTS. The recorder's cycle ends as
%     the last outfeed push starts; this model's total includes that push and
%     its retract, 5.66 s. Like for like, machine time is about 52.2 s here
%     against 64.03 s measured: roughly 1.23x, not the 1.11x quoted above.
%   - MEASURED at the cell: room air 25 C (model 20 C, -0.10 s if applied) and
%     platform stroke ~45 mm (model 50 mm, -0.03 s: the travel time is
%     measured, so the stroke only rescales the jog speed).
%     [Room air APPLIED 2026-09-13, plan H8: section 1, P.T_air = 298.15 K.
%     At the H7 baseline it moved machine time to S37 by -0.06 s, not the
%     -0.10 s predicted at the 2026-09-10 baseline.]
%   - The conveyor axis readings pot_control.convN.current_position_fb do NOT
%     track the belt surface: belt 1's swings 25 -> 2 -> 25 -> 2 -> 25 during
%     one forward transport. Nothing may be read off them as belt travel until
%     the tape-mark test says what they are.
%
% ==== WHERE THE MODEL NOW STANDS ==========================================
%
%   model machine time   57.870 s   (was 50.660 before this, 18.580 on 09-06)
%   measured             64.030 s
%   gap                  1.11x      (was 1.26x, 1.69x, and 3.4x on 09-06)
%   [NOT LIKE FOR LIKE - corrected 2026-09-12, plan H1. The recorder's clock
%   stops when the last outfeed push starts (S37); the 57.870 s runs on
%   5.67 s past it. To S37 machine time is 52.200 s: a 1.23x gap, and about
%   12 s remains, not the 6 s below. LOG.machine_time_rec carries it. The
%   round-2 note in 13M said so on 2026-09-10; this is where it is applied.]
%   [H2, 2026-09-12: the T#10S start delay (P.PLC.t_start_delay). Machine
%   time to S37 52.200 -> 59.850 s against 64.03 s: 1.07x. What remains is
%   H3-H6 in PLAN_TO_WEDNESDAY: belt datums and speeds, the push/belt
%   overlap, and the belt-2 wait.]
%   [H3, 2026-09-12: belt 3 from the tape. Machine time to S37 59.850 ->
%   58.380 s: 1.10x - faster, because belt 3 was too long. H4-H6 remain.]
%   [H4, 2026-09-12: belt speeds. Machine time to S37 58.380 -> 56.900 s:
%   1.13x. Belt 1 now agrees with the recorder; belt 2 does not, and that is
%   the transfer geometry (H5).]
%   [H5, 2026-09-12: belt 2 starts with the transfer push and belt 3 as
%   cylinder B releases, as recorded. Machine time to S37 56.900 -> 55.450 s:
%   1.15x. The transfer GEOMETRY (px6 -20 cm) is not applied: it needs a
%   240 mm push from a barrel stamped 160, so the reading is suspect.]
%   [H6, 2026-09-13: the 1.463 s wait before cylinder A (P.PLC.t_cylA_wait).
%   Machine time to S37 55.450 -> 56.760 s: 1.13x, the first correction since
%   H2 to move the model toward the machine.]
%   [H7, 2026-09-13: nameplate bores and strokes on every barrel. Machine
%   time to S37 56.760 -> 57.410 s: 1.12x. Air per cycle 6.47 -> 9.57 NL.]
%   [H8, 2026-09-13: room air 25 C applied, P.T_air 298.15 K. Machine time
%   to S37 57.410 -> 57.350 s: 1.12x. Air per cycle 9.57 -> 9.43 NL.]
%
% ABOUT 6 s REMAINS. From the segment budget in 13L, the named remainder is
% three unnamed sequencer gaps totalling 5.09 s - before cylinder A, before
% the platform rises, and before cylinder B - plus 1.77 s on conveyor 2 and
% 0.55 s on conveyor 1, less 2.09 s where the model is too SLOW on conveyor 3
% because prox 9 is modelled at the wrong end of that belt. Every one of those
% is in the timeline already held; none needs another trip to the machine.
% [2026-09-13: the first of the three, before cylinder A, is now modelled as
% P.PLC.t_cylA_wait - plan H6.]

%% ---- 14. Fault injection switches --------------------------------------
% All nominally inactive. Architecture hooks for future fault studies.
P.fault.low_pressure     = false; P.fault.P_supply_scale = 1.00;
% Sized from FACTORY_ACTUATORS rather than written as 5, so that adding an
% actuator cannot leave a fault vector one short and silently index past its
% end. This is the same reason FACTORY_SENSOR_BUS derives its widths from P.
n_act = numel(factory_actuators());
P.fault.valve_stuck      = zeros(1,n_act); % per actuator, 1 = spool frozen
P.fault.actuator_stick   = zeros(1,n_act); % per actuator, extra Coulomb N
P.fault.conveyor_fail    = zeros(1,3);  % per conveyor, 1 = no torque
P.fault.conveyor_slip    = 1.00;        % scales mu between belt and block
P.fault.sensor_fail      = false;       % force all proximity sensors low
P.fault.sensor_delay     = 0.0;         % [s] additional sensor lag
P.fault.height_sens_bias = 0.0;         % [m] height sensor offset
P.fault.friction_scale   = 1.00;        % scales all cylinder friction
% The E-Stop. Not a fault of the model's invention: the machine has a real
% "Emergency" input and an "Emergency Healthy" loop (PLCTAGLIST), and until
% 2026-09-02 the model had no counterpart to either. Setting this true drops
% the loop, which FACTORY_PLC treats as a hard stop - every coil de-energised,
% the compressor off, the sequencer held. Default false = loop closed.
P.fault.estop            = false;       % true = E-Stop pressed

%% ---- 15. Which route the block takes -----------------------------------
% A SELECTOR, not a physical quantity, so - like the fault switches above - it
% carries no provenance tag and AUDIT_PROVENANCE does not count it.
%
% The cell runs two routes. The maintainer, 2026-09-11, verbatim:
%     "CYLINDER b FIRES WHEN ENGRAVING IS DONE AND IT PUSHES BLOCK TO BELT 3,
%      SV11 FIRES WHEN ENGRAVING IS SKIPPED"
%
%   true   ENGRAVE. Belt 2 stops on prox 7, cylinder A pushes the block into
%          the engraver, the platform rises and falls, cylinder B pushes it
%          onto belt 3. The Sequence.xlsx cycle, states S00-S39.
%   false  SKIP. The block runs on down belt 2 to prox 8 and solenoid 11,
%          MOVE_TO_CV3, pushes it straight across onto belt 3 on a T#2S pulse
%          (FC6 N5 -> Wp_move_cv3 -> FC6 N15). States S40-S43, then the
%          engraved route's own belt 3 and outfeed from S33.
%
% Default true: every real cycle recorded so far was engraved, so every pinned
% figure in this project is an engraved-route figure, and no bypass cycle has
% been recorded to pin the other route against. What the HMI selects the skip
% WITH is not established. The owner's 2026-09-02 words tie it to "50 mm is
% selected on the interface", while section 3 records 25 and 50 as engraving
% LENGTHS; settle that before a product is wired to this switch.
P.engrave_selected = true;
end
