function J = JanaticsData()
%JANATICSDATA  Janatics manufacturer data register (single source of truth).
%
%   J = JANATICSDATA() returns the manufacturer-derived component data used
%   by the model. NOTHING manufacturer-specific may be written anywhere else
%   in the project. FactoryParams reads this file; the physics reads
%   FactoryParams. The chain is:
%
%       JanaticsData.m  ->  FactoryParams.m  ->  initialize_factory.m
%                                            ->  factory_derivatives.m
%
%   CONFIRMATION STATUS (read this before quoting any number downstream)
%   -------------------------------------------------------------------
%   No nameplate, purchase order, machine BOM or photograph of the installed
%   equipment has ever been supplied to this project. Sequence.xlsx names
%   component TYPES ("Actuator", "Feeder Station Valve", "Pump") and no
%   models, no part numbers and no dimensions.
%
%   Every component below is therefore PROVISIONAL: it is a technically
%   compatible Janatics component selected to suit the duty implied by the
%   layout, NOT a component known to be installed. J.<comp>.status records
%   this. Do not let a candidate become an "actual" by repetition.
%
%   J.<comp>.src records where each number came from:
%       'JAN-CAT'  Janatics catalogue figure carried from Iteration 02
%       'CAL'      calculated in this file from a JAN-CAT figure
%       'EST'      engineering estimate, no manufacturer figure available
%       'COMM'     commissioning value (a setting, not a component property)
%
%   PROVENANCE WARNING. The catalogue figures below were gathered in
%   Iteration 02 and are reproduced here verbatim. The catalogue document
%   names are recorded, but the retrieval URLs and page numbers were NOT
%   captured at the time and this environment has no network access, so they
%   could not be re-attached. Treat the catalogue figures as UNVERIFIED
%   SECOND-HAND until someone re-opens the Janatics documents and completes
%   the source columns in Janatics_Component_Register.csv.
%
%   See also FACTORYPARAMS, README.md section 10 (Parameters and provenance).

%% ---- 0. constants used by the conversions ------------------------------
rho0 = 1.185;      % ISO 6358 reference density              kg/m^3
b    = 0.40;       % ISO 6358 critical pressure ratio        -
Patm = 101325;     % ambient                                 Pa

%% ---- 1. Pneumatic cylinders  (ACT-01 .. ACT-05) ------------------------
% Sequence.xlsx rows 7,15,22,33,41 each drive an "Actuator". The layout
% requires five linear pushers, strokes 87.5 - 257.5 mm (see
% initialize_factory), pushing a ~0.58 kg block horizontally.
J.CYL.factory_id = {'ACT-01','ACT-02','ACT-03','ACT-04','ACT-05'};
J.CYL.tag        = {'A1','A6','S2A1','S3A1','S3A2'};
J.CYL.series     = 'A53/A54 (double acting, non-magnetic / magnetic piston)';
J.CYL.model      = 'A53/A54 bore 20, standard stroke';
J.CYL.partno     = 'NOT ESTABLISHED - requires factory BOM';
J.CYL.status     = 'PROVISIONAL';
J.CYL.doc        = 'Janatics cylinder catalogue A53A54 (sheet ref A53A54-01-01-B)';

J.CYL.bore    = 0.020;   % [JAN-CAT] bore diameter                     m
J.CYL.rod     = 0.008;   % [JAN-CAT] rod diameter for bore 20          m
J.CYL.p_max   = 10.0e5;  % [JAN-CAT] max working pressure (gauge)      Pa
J.CYL.p_min   = 0.5e5;   % [JAN-CAT] min working pressure (gauge)      Pa
J.CYL.port    = 'G1/8';  % [JAN-CAT] port thread, bore 20              -
% [JAN-CAT] standard stroke ladder. A cylinder cannot be bought to an
% arbitrary length; a pusher must be rounded UP to the next standard stroke.
J.CYL.strokes = [10 25 40 50 80 100 125 160 200 250 300]*1e-3;   %       m
% [JAN-CAT] Janatics tabulates output force as 0.90 x P*A. Checked against
% the catalogue tables for bores 12/16/20/25/40: ratio 0.896-0.907. The 10 %
% is the manufacturer's own loss allowance and is PROPORTIONAL TO LOAD, not
% a fixed breakaway force - that distinction changes the friction model.
J.CYL.f_eff   = 0.90;    % [JAN-CAT] catalogue force efficiency        -
J.CYL.F_ext_6bar = 0.90*6e5*pi*J.CYL.bore^2/4;              % [CAL]     N
J.CYL.F_ret_6bar = 0.90*6e5*pi*(J.CYL.bore^2-J.CYL.rod^2)/4;% [CAL]     N
J.CYL.m_moving   = 0.120;% [EST] piston + rod moving mass, not published kg
J.CYL.V_dead     = 2.5e-6;% [EST] port + cushion dead volume, G1/8      m^3
J.CYL.cushion    = 'adjustable both ends (catalogue option, not modelled)';

%% ---- 2. Directional control valves  (VAL-01 .. VAL-05) ----------------
% Sequence.xlsx rows 6,14,21,32,40: "Station Valve -> Actuator". A double
% acting cylinder driven forward and back needs 5/2.
J.VAL.factory_id = {'VAL-01','VAL-02','VAL-03','VAL-04','VAL-05'};
J.VAL.series  = 'DS2 (5/2 solenoid operated, spring / pilot return)';
J.VAL.model   = 'DS2 series, G1/8 ported';
J.VAL.partno  = 'NOT ESTABLISHED - requires factory BOM';
J.VAL.status  = 'PROVISIONAL';
J.VAL.doc     = 'Janatics directional control valve catalogue, DS2 series';
J.VAL.func    = '5/2';    % [JAN-CAT] port/position configuration
J.VAL.port    = 'G1/8';   % [JAN-CAT]
J.VAL.Q_lpm   = 450;      % [JAN-CAT] nominal flow, 6 bar inlet, dp 1 bar l/min
J.VAL.p_range = [2.0e5 8.0e5];  % [JAN-CAT] operating pressure range (g) Pa
J.VAL.coil    = 'solenoid, voltage NOT ESTABLISHED (24 VDC assumed for the PLC I/O only)';
J.VAL.manual_override = 'standard on DS2 (not modelled)';
J.VAL.tau     = 0.020;    % [EST] spool travel time - NOT published by
                          %       Janatics. Carried from Iteration 01.   s

%% ---- 3. Speed controllers  (FCV-01 .. FCV-05) -------------------------
% Not named in Sequence.xlsx. Physically required: without an adjustable
% restriction the rod speed is whatever the valve happens to give. Iteration
% 01 hid this element inside a fictitious "valve inlet conductance" 66x
% smaller than the real DS2 - i.e. it was modelling the speed controller and
% calling it the valve. Janatics sells the element separately, so it is now
% a separate component with its own catalogue data.
J.FCV.factory_id = {'FCV-01','FCV-02','FCV-03','FCV-04','FCV-05'};
J.FCV.series  = 'GR (flow control valve, banjo/elbow, cylinder-port mounting)';
J.FCV.model   = 'GR series, G1/8';
J.FCV.partno  = 'NOT ESTABLISHED - requires factory BOM';
J.FCV.status  = 'PROVISIONAL';
J.FCV.doc     = 'Janatics flow control valve catalogue, GR series';
J.FCV.port    = 'G1/8';   % [JAN-CAT]
J.FCV.Q_free  = 300;      % [JAN-CAT] free-flow (check) direction, min   l/min
J.FCV.Q_ctrl  = 400;      % [JAN-CAT] controlled direction, needle open  l/min
J.FCV.mode    = 'meter-out (exhaust control) - GR mounted at the cylinder port';

%% ---- 4. Air preparation  (FRL-01) -------------------------------------
% Sequence.xlsx row 2/3 "PLC -> Pump -> Distribution Valve" has no air
% preparation in it. A cell without an FRL has no set pressure at all, which
% is why Iteration 01's actuators saw the raw receiver swinging 6.0-8.0 bar.
J.FRL.factory_id = 'FRL-01';
J.FRL.series  = 'FRCLM13 (filter + regulator + lubricator, modular)';
J.FRL.model   = 'FRCLM13, G1/4';
J.FRL.partno  = 'NOT ESTABLISHED - requires factory BOM';
J.FRL.status  = 'PROVISIONAL';
J.FRL.doc     = 'Janatics air preparation catalogue, FRCLM series';
J.FRL.port    = 'G1/4';    % [JAN-CAT]
J.FRL.Q_lpm   = 500;       % [JAN-CAT] flow at 7 bar inlet, 6 bar set,
                           %           dp 1 bar                          l/min
J.FRL.p_reg   = [0.5e5 10.0e5]; % [JAN-CAT] regulation range (gauge)     Pa
J.FRL.filter  = 40e-6;     % [JAN-CAT] standard filter element           m
J.FRL.p_set   = 6.0e5;     % [COMM] SET PRESSURE - this is a knob on the
                           %        regulator, not a component property.
                           %        6 bar g is the assumed cell setting.  Pa

%% ---- 5. Position sensing  (PS-01 .. PS-05) ----------------------------
% Sequence.xlsx rows 24 and 35 require "Actuator -> PLC status feedback".
J.REED.factory_id = {'PS-01','PS-02','PS-03','PS-04','PS-05'};
J.REED.series = 'AM4 (reed switch, barrel clamp) - requires A54 magnetic piston';
J.REED.status = 'PROVISIONAL';
J.REED.doc    = 'Janatics cylinder sensor catalogue, AM series';
J.REED.note   = ['A barrel-clamped switch senses the position the machine ' ...
                 'builder clamps it at, NOT the mechanical end of stroke. ' ...
                 'With a rounded-up standard stroke these are different ' ...
                 'points, and sensing at the mechanical end would deadlock ' ...
                 'the sequence.'];
J.REED.repeat = 2.0e-3;   % [EST] switching repeatability window          m

%% ---- 6. Derived ISO 6358 sonic conductances ---------------------------
% Janatics publishes flow as l/min of free air at a stated inlet pressure and
% pressure drop. The physics needs ISO 6358 sonic conductance C. Conversion,
% applied identically to every catalogue figure above:
%
%     mdot   = Q[l/min]/60000 * rho0                                  [kg/s]
%     r      = Pd/Pu ,  Pd = Pu - dp     (both ABSOLUTE)
%     f      = 1                       if r <= b        (choked)
%            = sqrt(1-((r-b)/(1-b))^2) otherwise        (subsonic)
%     C      = mdot / (rho0 * Pu * f)                         [m^3/(s*Pa)]
%
% Verified: this reproduces every conductance carried from Iteration 02 to
% better than 0.005 %.
q2C = @(Q, Pin_g, dp) (Q/60000*rho0) / ...
      (rho0*(Pin_g+Patm)*iso_f((Pin_g+Patm-dp)/(Pin_g+Patm), b));

J.C.valve    = q2C(J.VAL.Q_lpm, 6e5, 1e5);   % [CAL] DS2 5/2       1.6525e-8
J.C.fcv_free = q2C(J.FCV.Q_free, 6e5, 1e5);  % [CAL] GR check      1.1016e-8
J.C.fcv_max  = q2C(J.FCV.Q_ctrl, 6e5, 1e5);  % [CAL] GR needle max 1.4689e-8
J.C.frl      = q2C(J.FRL.Q_lpm,  7e5, 1e5);  % [CAL] FRL + line    1.7034e-8

% Supply path = DS2 in series with the GR check (the GR is mounted AT the
% cylinder port, so supply air passes its free-flow direction).
% Restrictions in series:  1/C^2 = 1/C1^2 + 1/C2^2
J.C.supply   = 1/sqrt(1/J.C.valve^2 + 1/J.C.fcv_free^2);   % [CAL] 9.1662e-9

% Exhaust path = GR needle, i.e. METER-OUT. These two are the commissioning
% settings of the needle (a fitter's screwdriver), expressed below as a
% fraction of the GR's catalogue controlled range. They are the only numbers
% here that a person can change on the machine without buying anything.
J.C.exh_extend  = 5.2929e-10;   % [COMM] vents chamber B -> 0.20 m/s extend
J.C.exh_retract = 1.2602e-9;    % [COMM] vents chamber A -> 0.40 m/s retract
J.C.needle_extend  = J.C.exh_extend /J.C.fcv_max;  % [CAL] 3.60 % of range
J.C.needle_retract = J.C.exh_retract/J.C.fcv_max;  % [CAL] 8.58 % of range

%% ---- 7. NOT identified -------------------------------------------------
% Recorded so that no future reader mistakes silence for confirmation.
J.unidentified = { ...
 'Compressor / receiver', 'Sequence.xlsx row 2 "Pump". No Janatics data. Sized generically.'
 'Distribution valve',    'Rows 4,13,20,31,39. Modelled as 4 branch manifolds. Model unknown.'
 'Conveyor drives',       'Rows 10,17,36. Not pneumatic. Motor/gearbox generic.'
 'Engraving base axis',   'Row 25. Electric axis (no valve in its chain). Generic.'
 'Proximity sensors',     'Rows 9,11,18,37. Detection radius is an estimate.'
 'Camera',                'Row 1. Modelled as a position-triggered logical.'
 'Tubing / fittings',     'Sizes unknown. Lumped into the branch volume.'
 'Quick exhaust / check valves', 'Not evidenced anywhere. Not modelled.'
 'Pressure switch',       'Physically required (row 2 never stops the pump). Setting assumed.'};
end

% =========================================================================
function f = iso_f(r, b)
%ISO_F  ISO 6358 flow function.
if r <= b
    f = 1;
else
    z = (r-b)/(1-b);
    f = sqrt(max(0, 1 - z*z));
end
end
