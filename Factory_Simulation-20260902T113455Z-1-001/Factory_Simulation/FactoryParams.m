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
P.T_air    = 293.15;    % [ASM] air temperature (isothermal)        K
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
P.P_res_0   = 5.5e5;    % [ASM] receiver pressure at t = 0 (abs)    Pa
P.P_cut_in  = 6.0e5;    % [ASM] compressor pressure switch, cut-in  Pa
P.P_cut_out = 8.0e5;    % [ASM] compressor pressure switch, cut-out Pa
P.mdot_pump = 3.0e-3;   % [EST] compressor mass delivery            kg/s
P.P_ready   = 6.5e5;    % [ASM] receiver "ready" threshold          Pa
P.P_br_rdy  = 5.5e5;    % [ASM] branch/chamber charged threshold    Pa
P.P_relief  = 9.0e5;    % [ASM] receiver relief valve set point     Pa
P.C_relief  = 5.0e-8;   % [EST] relief valve sonic conductance      m^3/(s*Pa)

% --- Janatics FRL (air preparation) -------------------------------------
% Iteration 01 had NO regulator: every actuator saw the raw receiver
% pressure cycling between the 6.0 and 8.0 bar switch settings, so rod force
% cycled with it. A real cell always regulates.
P.P_set     = J.FRL.p_set + P.P_atm;  % [COMM] regulator set point (abs) Pa
P.C_dv      = J.C.frl;  % [JAN] FRL + supply line conductance       m^3/(s*Pa)
P.tau_dv    = 0.030;    % [EST] distribution valve response time    s
P.V_branch  = 1.0e-4;   % [EST] branch manifold + tubing volume     m^3

%% ---- 5. Cylinders (Janatics A53/A54, bore 20) --------------------------
% WHICH cylinders, how many, which coil drives each and which valve type each
% carries is NOT here - it is in FACTORY_ACTUATORS, which holds the machine's
% eleven pneumatic actuators on thirteen coils. What is here is the per-
% cylinder physics they all share. A53/A54 bore 20 is still a [JAN] assumption
% for every one of them; section 13B records that the CAD says the cell
% actually runs bore 8 and bore 32, and that finding is still not applied.
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
P.v_belt   = 0.150;     % [ASM] belt speed set point                m/s
P.a_belt   = 0.400;     % [ASM] drive accel/decel ramp limit        m/s^2
P.om_eps   = 0.05;      % [ASM] drivetrain friction regularisation  rad/s

%% ---- 8. Engraving base (ELECTRIC vertical axis) ------------------------
% Sequence.xlsx step 25 is "PLC -> Engraving Base" with NO valve in the
% chain, unlike every actuator. The base is therefore NOT pneumatic and no
% Janatics component applies to it.
P.m_base   = 2.00;      % [EST] moving base mass                    kg
P.z_top    = 0.050;     % [ASM] engraving working height            m
P.Kp_bz    = 4.0e3;     % [ASM] axis position gain                  N/m
P.Ki_bz    = 2.0e3;     % [ASM] axis integral gain                  N/(m*s)
P.Kd_bz    = 2.0e2;     % [ASM] axis velocity gain                  N*s/m
P.F_ax_max = 200;       % [EST] axis force limit                    N

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
P.t_max   = 45.0;       % [ASM] simulation time limit               s
                        %       nominal cycle is 31.07 s

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
% 31.08 s cycle, 12.5 s is operator-paced. The honest predicted quantity is
% MACHINE time, about 18.58 s, with an operator distribution on top.
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
%
% WHAT (2) SETTLED. Read alone, (1) suggested cylinder B might be a diverter
% carrying the part past the engraver, and the model was briefly built that
% way. (2) says it belongs to the ENGRAVING MACHINE. So cylinder B is at the
% engraver, coil 9 drives it out and coil 10 back - the polarity the table
% already had - and it actuates the machine rather than the workpiece. That is
% why it carries no travel and touches nothing: see FACTORY_ACTUATORS.
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
end
