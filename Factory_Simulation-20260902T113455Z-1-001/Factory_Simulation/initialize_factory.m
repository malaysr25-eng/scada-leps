function [P, s0] = initialize_factory(P)
%INITIALIZE_FACTORY  Build derived geometry, state index map and initial state.
%
%   [P, s0] = INITIALIZE_FACTORY(P) takes the parameter struct from
%   FactoryParams and adds:
%     P.WP     workpiece waypoints          (metres)
%     P.CYL    actuator table               (struct array, 11 entries)
%     P.ACT    role -> actuator index map
%     P.REG    support-surface regions      (struct array)
%     P.STOP   mechanical locating stops    (struct array)
%     P.PROX   proximity sensor positions   (metres)
%     P.IX     state vector index map
%   and returns the initial state vector s0.
%
%   All layout coordinates are taken from the reference script
%   function multi_station_simulation().txt, in DRAWING UNITS, and converted
%   to metres with P.SCALE. The spatial arrangement of the original is
%   preserved exactly; only the unit interpretation changes.

if nargin < 1 || isempty(P); P = FactoryParams(); end
S = P.SCALE;

%% ---- 1. Workpiece waypoints (drawing units -> m) -----------------------
% Block CENTRE coordinates. Derived from the reference script's rectangles;
% where the script was internally inconsistent the geometric centreline of
% the relevant conveyor/fixture was used instead (see equation audit).
WPu = struct( ...
    'feed',    [ 1.600, 10.000], ...  % [REF] feeder, above conveyor 1
    'c1_load', [ 1.600,  9.175], ...  % [CAL] conveyor 1 centreline
    'c1_end',  [ 7.925,  9.175], ...  % [CAL] aligned to conveyor 2 centre
    'c2_load', [ 7.925,  8.100], ...  % [CAL] entry onto conveyor 2
    'c2_end',  [ 7.925,  5.900], ...  % [REF] aligned to St.2 Actuator 1 axis
    'engrave', [10.450,  5.900], ...  % [CAL] laser engraver centre
    'c3_load', [10.450,  3.865], ...  % [CAL] station 3 belt centreline
    'c3_end',  [15.100,  3.865], ...  % [REF] aligned to eject actuator axis
    'bin',     [15.100,  2.000], ...  % [ADD] collection bin, Sequence.xlsx 42
    'c3_out_b',[13.240,  3.865], ...  % [ASM] second outfeed station, 60 % run
    'bin_b',   [13.240,  2.000], ...  % [ASM] where outfeed B pushes to
    'c3_byp',  [ 7.925,  3.865]);     % [ASM] where CYL_B's bypass lands
% 'bin' is an [ADD]: Sequence.xlsx step 42 requires a collection bin and the
% reference script has none.
%
% 'c3_byp' IS THE HONEST APPROXIMATION IN THIS FILE, and it is worth stating
% plainly rather than leaving someone to find it. The owner says cylinder B
% diverts the workpiece from the end of conveyor 2 straight onto conveyor 3,
% past the engraver. c2_end sits at x = 7.925 and the reference layout draws
% conveyor 3 starting at x = 8.60, so a straight push down from c2_end lands
% on the conveyor 3 CENTRELINE but 0.675 drawing units SHORT of the drawn
% belt. The alternatives were worse: a diagonal stroke, which this model's
% single-axis cylinders cannot express, or an invented landing x.
%
% So the stroke is real - same 203.5 mm travel as the engraver-to-belt-3 move,
% same 250 mm standard cylinder - and the landing point is a layout artefact,
% not a claim about the machine. Nothing commands CYL_B, so nothing depends on
% it. Question 3c asks where the bypass really lands.
%
% THE SECOND OUTFEED STATION, and why it is placed rather than left unplaced.
%
% FC6 N16 is one network and it is symmetric: proximity sensor 9 runs a 5 s TP
% to solenoid 12, and proximity sensor 10 runs a 5 s TP to solenoid 13. Two
% sensors, two coils, the same network, the same timer. Outfeed A is at its
% sensor - PX09 sits at c3_end and solenoid 12 ejects from there - so outfeed
% B is at ITS sensor, PX10.
%
% That is an inference from the program's own structure, not from the layout,
% which is why it is [ASM] and not [SRC]. What it is NOT is a free choice: the
% 60 % figure comes from where PX10 was already assumed to sit (section 5, and
% question 4b), so the station and its sensor move together by construction
% rather than being placed twice.
%
% The OTHER unplaced actuator, XFER_CV2_CV3 on coil 11, is deliberately still
% unplaced. FC6 N15 fires it on Wp_move_cv3 with conveyor 3 on and conveyor 2
% off, and pairs it with no sensor at all - so there is no equivalent
% inference available and putting it somewhere would be invention. Question
% 17b asks for it.
f = fieldnames(WPu);
for i = 1:numel(f); P.WP.(f{i}) = WPu.(f{i}) * S; end
P.WPu = WPu;

%% ---- 2. Actuator table -------------------------------------------------
% ALL ELEVEN of the machine's pneumatic actuators, in the machine's own
% numbering, resolved from FACTORY_ACTUATORS. Until 2026-09-02 this was a
% five-row `cdef` literal sitting here; see that file for why it moved out and
% for what every column means.
%
% The five actuators the sequence actually drives keep EXACTLY the geometry
% they had - same waypoints, same approach gap, same standard-stroke rounding -
% so their strokes and switch positions are unchanged to the last micrometre.
% What is new is the other six, the machine's coil numbering, and the
% double-solenoid valve type on CYL_A and CYL_B.
%
% P.mag_choice and P.mag_pitch are set HERE, before the table is resolved,
% because a magazine pusher's lateral position depends on both. They used to
% live in section 5 with the proximity sensors, which read the same two values
% for the same reason.
P.mag_choice = 1;          % [ASM] compartment the model feeds from      -
P.mag_pitch  = 0.110;      % [CAD] magazine slot pitch, Magazine.STEP    m

% P.act_variant is absent for every normal run. PLCIOLATENCYTEST sets it to
% 'historical5' to rebuild the five-cylinder plant its reference figures were
% measured on; see FACTORY_ACTUATORS.
if isfield(P, 'act_variant'); actVariant = P.act_variant; else; actVariant = 'machine'; end
ACT    = factory_actuators(actVariant);
P.NCYL = numel(ACT);
P.NSOL = sum([ACT.coil_ext] > 0) + sum([ACT.coil_ret] > 0);   % 13 coils

for c = 1:P.NCYL
    a = ACT(c);
    P.CYL(c).name     = a.name;
    P.CYL(c).alias    = a.alias;
    P.CYL(c).role     = a.role;
    P.CYL(c).dbl      = a.dbl;
    P.CYL(c).coil_ext = a.coil_ext;
    P.CYL(c).coil_ret = a.coil_ret;
    P.CYL(c).branch   = a.branch;
    P.CYL(c).mag      = a.mag;
    P.CYL(c).excel    = a.excel;
    P.CYL(c).short    = a.short;
    P.CYL(c).axis     = a.axis;
    P.CYL(c).dir      = a.dir;
    % PLACED and CONTACT are different questions and the drawing needs the
    % first one. CYL_B is placed - it has real geometry and a real chamber -
    % and is still barred from touching the workpiece, because the bypass path
    % is not representable in this layout. Keying the diagram off `contact`
    % printed it as "position unknown", which is precisely wrong.
    P.CYL(c).placed   = a.placed;
    P.CYL(c).contact  = a.contact;
    if a.hasGeom
        k  = 1 + strcmp(a.axis,'y');          % 1 for x-axis, 2 for y-axis
        p0 = P.WP.(a.from)(k);
        p1 = P.WP.(a.to)(k);
        P.CYL(c).travel = abs(p1 - p0);
        % The rod must travel the approach gap plus the transport distance.
        % That distance is fixed by the layout, and it is where the END-OF-
        % STROKE REED SWITCH is clamped on the barrel.
        P.CYL(c).x_trip = P.gap_app + P.CYL(c).travel;
        % [JAN] The CYLINDER, however, cannot be bought to that length.
        % Iteration 01 used the required travel AS the stroke, i.e. it assumed
        % a cylinder of any length is purchasable. Janatics A53/A54 are
        % supplied on a standard stroke ladder (JanaticsData.CYL.strokes), so
        % the stroke is rounded UP to the next standard size and the switch is
        % clamped short of the mechanical end. Consequences: extra dead length
        % in chamber B, and EXT feedback that fires at x_trip rather than at
        % the end stop (see FACTORY_SENSORS).
        P.CYL(c).stroke = std_stroke(P.CYL(c).x_trip, P.strokes);
        % p0 is the waypoint ALONG the cylinder axis, so the half-extent must
        % be the one on that axis: L for an x-axis cylinder (k = 1), W for a
        % y (k = 2).
        blk_ax          = P.blk_L*(k == 1) + P.blk_W*(k == 2);
        face0           = p0 - a.dir*blk_ax/2;      % workpiece face toward rod
        P.CYL(c).tip0   = face0 - a.dir*P.gap_app;  % rod tip when retracted
        % A magazine pusher stands at its own compartment, one P.mag_pitch
        % (110 mm) from its neighbour, against a 100 mm workpiece. So the
        % lateral gate in FACTORY_DERIVATIVES excludes every pusher but the
        % selected one BY GEOMETRY, with 10 mm to spare. No flag, no special
        % case, and the margin is a real number someone can check.
        P.CYL(c).lat    = P.WP.(a.from)(3-k) + magOffset(a, P);
    elseif a.placed
        % POSITION KNOWN, PATH NOT. CYL_B belongs to the engraving machine and
        % the owner has not said what it moves or how far, so it stands at its
        % waypoint, borrows a stroke from the other half of its double-solenoid
        % pair, and is drawn - but claims no travel and touches nothing.
        d = find(strcmp({ACT.name}, a.stroke_of), 1);
        if isempty(d) || d >= c
            error('initialize_factory:strokeDonorOrder', ...
                ['%s borrows the stroke of %s, which must appear EARLIER ' ...
                 'in FACTORY_ACTUATORS so it is already resolved.'], ...
                a.name, a.stroke_of);
        end
        k  = 1 + strcmp(a.axis,'y');
        p0 = P.WP.(a.from)(k);
        P.CYL(c).travel = P.CYL(d).travel;
        P.CYL(c).x_trip = P.CYL(d).x_trip;
        P.CYL(c).stroke = P.CYL(d).stroke;
        blk_ax          = P.blk_L*(k == 1) + P.blk_W*(k == 2);
        face0           = p0 - a.dir*blk_ax/2;
        P.CYL(c).tip0   = face0 - a.dir*P.gap_app;
        P.CYL(c).lat    = P.WP.(a.from)(3-k);
    else
        % PLACEMENT NOT KNOWN - see the block comment in FACTORY_ACTUATORS.
        % Full pneumatics, no contact geometry. The stroke is BORROWED from
        % the actuator of the same class at the same station, [ASM], because
        % chamber B needs a volume and that is the traceable place to get one.
        % tip0 and lat are NaN so that anything reaching for a rod position
        % fails loudly instead of inventing one.
        d = find(strcmp({ACT.name}, a.stroke_of), 1);
        if isempty(d) || d >= c
            error('initialize_factory:strokeDonorOrder', ...
                ['%s borrows the stroke of %s, which must appear EARLIER ' ...
                 'in FACTORY_ACTUATORS so it is already resolved.'], ...
                a.name, a.stroke_of);
        end
        P.CYL(c).travel = P.CYL(d).travel;
        P.CYL(c).x_trip = P.CYL(d).x_trip;
        P.CYL(c).stroke = P.CYL(d).stroke;
        P.CYL(c).tip0   = NaN;
        P.CYL(c).lat    = NaN;
    end
end

% Role -> actuator index, so the sequencer never carries a bare number and a
% re-ordering of the table cannot silently drive the wrong barrel.
% Sequence.xlsx's "A1" is whichever compartment the model feeds from, so that
% alias is attached here rather than in the table.
P.ACT.mag     = find(strcmp({ACT.role}, 'mag_push'));
P.ACT.feed    = P.ACT.mag(P.mag_choice);
P.ACT.xfer1   = find(strcmp({ACT.role}, 'xfer1'),   1);
P.ACT.eng_in  = find(strcmp({ACT.role}, 'eng_in'),  1);
P.ACT.eng_out = find(strcmp({ACT.role}, 'eng_out'), 1);
P.ACT.bypass  = find(strcmp({ACT.role}, 'bypass'),  1);
P.ACT.eject   = find(strcmp({ACT.role}, 'eject'),   1);
P.CYL(P.ACT.feed).alias = 'A1';
% The five the model's sequence commands. The other six are MODELLED - they
% breathe, they draw air, they sit on the bus - but Sequence.xlsx never asks
% them to move, exactly as only one magazine pusher fires per cycle on the
% real machine.
P.ACT.driven  = [P.ACT.feed P.ACT.xfer1 P.ACT.eng_in P.ACT.eng_out P.ACT.eject];

%% ---- 3. Support-surface regions (priority ordered) --------------------
% [REF] rectangles from the reference script, in drawing units.
rdef = { 'conv3', 8.60,16.20, 3.19, 4.54,  1, 0; ...
         'engrave',8.60,12.30, 4.30, 6.95, 0, 0; ...
         'conv2', 7.25, 8.60, 0.90, 8.50,  0,-1; ...
         'conv1', 1.00, 8.60, 8.50, 9.85,  1, 0; ...
         'bin'  ,14.30,15.90, 1.00, 3.19,  0, 0};
for i = 1:size(rdef,1)
    P.REG(i).name = rdef{i,1};
    P.REG(i).box  = [rdef{i,2} rdef{i,3} rdef{i,4} rdef{i,5}]*S;
    P.REG(i).uv   = [rdef{i,6} rdef{i,7}];   % belt direction unit vector
end
% Which region each conveyor drives: C1, C2, C3
P.CONV_REG = [4 3 1];      % indices into P.REG
P.NCONV    = 3;

%% ---- 4. Mechanical locating stops and belt side rails -----------------
% [ADD] Not present in the reference script, but physically required. Without
% them the workpiece separates from the rod at end-of-stroke and coasts past
% the target by 20-100 mm, so the proximity sensors never see it. Every real
% transfer station has locating stops. With them, final position error is
% 0.0 mm and is set by GEOMETRY rather than by actuator dynamics.
% Columns: name, axis, direction resisted, position, gate axis, gate min/max.
sdef = { 'C1_side_rail','y',-1,  9.175,'x', 1.00, 7.40; ...
         'C1_end_stop' ,'x',+1,  7.925,'y', 8.50, 9.85; ...
         'C2_end_stop' ,'y',-1,  5.900,'x', 7.25, 8.60; ...
         'ENG_fixture' ,'x',+1, 10.450,'y', 4.30, 6.95; ...
         'C3_side_rail','y',-1,  3.865,'x', 8.60,14.30; ...
         'C3_end_stop' ,'x',+1, 15.100,'y', 3.19, 4.54; ...
         'BIN_floor'   ,'y',-1,  2.000,'x',14.30,15.90};
for i = 1:size(sdef,1)
    P.STOP(i).name = sdef{i,1};
    P.STOP(i).ax   = 1 + strcmp(sdef{i,2},'y');
    P.STOP(i).dir  = sdef{i,3};
    P.STOP(i).pos  = sdef{i,4}*S;
    P.STOP(i).gax  = 1 + strcmp(sdef{i,5},'y');
    P.STOP(i).g0   = sdef{i,6}*S;
    P.STOP(i).g1   = sdef{i,7}*S;
end

%% ---- 5. Sensor locations ----------------------------------------------
% TEN proximity sensors, in the MACHINE'S OWN NUMBERING. Until 2026-09-02 the
% model carried four, numbered 1-4 by the order Sequence.xlsx happened to
% mention them. The machine has ten and numbers them differently, so every
% conversation about "sensor 3" meant two different things depending on who
% was speaking.
%
% The four physical TRIP POINTS are unchanged - PX1, PX6, PX8 and PX9 below
% sit exactly where the old PX1..PX4 sat. Only the numbering moved, onto the
% machine's. That is why the pinned cycle time and final position did not
% change when this was done.
%
% ROLES are from the PLC program (plc/abc.pdf, FC6/FC7 - see FactoryParams
% section 13C). POSITIONS are a different matter and are marked below.
%
%   1-5   magazine compartments 1-5, dispense confirm.  FC7 N2 gates each on
%         workpiece_choice = N, so only the SELECTED compartment's sensor can
%         fire. The model feeds from compartment P.mag_choice, so exactly one
%         of these five ever trips. That is faithful, not a defect.
%   6     conveyor 1.       FC6 N3 / FC7 N4, clears the magazine push.
%   7     conveyor 2 mid.   FC7 N5, the network is titled "WP IN CV2 MID".
%   8     conveyor 2 end.   FC6 N5, 400 ms pulse -> Wp_move_cv3.
%   9     conveyor 3, outfeed station A.  FC6 N14 sets STOP_CONV3.
%  10     conveyor 3, outfeed station B.  FC6 N16, gates solenoid 13.
%
% PHOTOGRAPHS, 2026-09-02, corroborate the count and the layout: five acrylic
% magazine compartments in a row with five Janatics cylinders behind them, and
% a row of five M18 barrels on brackets along the conveyor below. That is an
% independent confirmation of FC7 N3, which was read out of the program text.
%
% WHAT IS STILL ASSUMED: where sensors 2-5, 7 and 10 sit ALONG the belt.
% Their roles are known; their positions are not, and a ladder diagram cannot
% say. INPUTS_REQUIRED.md question 4b asks for exactly this. The placements
% below are the working assumption, chosen so that each sensor sits where its
% role puts it, and are tagged [ASM] accordingly.
% P.mag_choice and P.mag_pitch are set in section 2, because the magazine
% PUSHERS need them to place themselves and the pushers resolve first. These
% sensors and those actuators must agree about where compartment N is, which
% is exactly why the two values are now defined once instead of twice.

% Compartment 1 is the model's feed point, so PX(1) keeps the old PX1 trip.
magRow = zeros(5, 2);
for i = 1:5
    magRow(i,:) = P.WP.c1_load + [(i - P.mag_choice)*P.mag_pitch, 0];
end

% Conveyor 2 runs from c2_load to c2_end; "mid" is taken as its midpoint.
c2_mid = (P.WP.c2_load + P.WP.c2_end) / 2;

% Outfeed station B sits upstream of station A on conveyor 3. The model ejects
% only at c3_end, so PX(10) trips as the block PASSES, which is what the real
% sensor would do. Placed at 60 % of the belt run: assumed, not measured.
%
% ONE definition, not two: the waypoint c3_out_b in section 1 is that point,
% and the outfeed B actuator stands there. The sensor reads the waypoint
% rather than recomputing the 0.60, so the station and its sensor cannot drift
% apart - which is exactly the failure the magazine row had before mag_pitch
% was defined once.
c3_b = P.WP.c3_out_b;

P.PROX = [ magRow          % 1-5   magazine compartments      [ASM] except 1
           P.WP.c1_end     % 6     conveyor 1                 [SRC] step 11
           c2_mid          % 7     conveyor 2 mid             [ASM]
           P.WP.c2_end     % 8     conveyor 2 end             [SRC] step 18
           P.WP.c3_end     % 9     conveyor 3, outfeed A      [SRC] step 37
           c3_b ];         % 10    conveyor 3, outfeed B      [ASM]
P.PROX_NAME = {'PX01_mag1_dispense','PX02_mag2_dispense', ...
               'PX03_mag3_dispense','PX04_mag4_dispense', ...
               'PX05_mag5_dispense','PX06_conv1', ...
               'PX07_conv2_mid','PX08_conv2_end', ...
               'PX09_conv3_outfeed_a','PX10_conv3_outfeed_b'};
% Which of the ten the sequencer actually gates on. The other six are
% MODELLED AND LOGGED but guard nothing, because the model's sequence is
% Sequence.xlsx's and the machine's is FC6's, and those are not the same
% sequence. Reconciling them is the plant re-model, not this change.
P.PROX_GUARD = [P.mag_choice 6 8 9];   % [PLC] states 8, 11, 17, 35
P.CAM  = P.WP.feed;    % [SRC] step 1, camera field of view

%% ---- 6. State vector index map ----------------------------------------
n = P.NCYL; m = P.NCONV;
P.IX.P_res = 1;
P.IX.P_br  = 2:5;                 % 4 distribution branches
P.IX.dv    = 6:9;                 % distribution valve spool positions
P.IX.PA    = 9  + (1:n);          % cap-side chamber pressures
P.IX.PB    = 9  + n + (1:n);      % rod-side chamber pressures
P.IX.x     = 9  + 2*n + (1:n);    % rod positions
P.IX.v     = 9  + 3*n + (1:n);    % rod velocities
P.IX.sp    = 9  + 4*n + (1:n);    % station valve spool positions
b = 9 + 5*n;
P.IX.om    = b + (1:m);           % conveyor pulley speeds
P.IX.ei    = b + m + (1:m);       % speed-loop integrators
P.IX.vref  = b + 2*m + (1:m);     % ramped belt speed references
b = b + 3*m;
P.IX.bz  = b+1; P.IX.bvz = b+2; P.IX.bei = b+3;   % engraving base
P.IX.bx  = b+4; P.IX.by  = b+5;                    % workpiece position
P.IX.bvx = b+6; P.IX.bvy = b+7;                    % workpiece velocity
P.IX.mair= b+8;                                    % cumulative air mass drawn
P.NS = b+8;

%% ---- 7. Initial state --------------------------------------------------
s0 = zeros(P.NS,1);
s0(P.IX.P_res) = P.P_res_0;
s0(P.IX.P_br)  = P.P_atm;
s0(P.IX.PA)    = P.P_atm;
s0(P.IX.PB)    = P.P_atm;
s0(P.IX.bx)    = P.WP.feed(1);
s0(P.IX.by)    = P.WP.feed(2);
s0(P.IX.mair)  = 0;
end

% =========================================================================
function off = magOffset(a, P)
%MAGOFFSET  Lateral offset of a magazine pusher from the selected compartment.
%   Zero for anything that is not a pusher. Compartment P.mag_choice is the
%   model's feed point and therefore sits at offset 0, which is what keeps
%   PX(P.mag_choice) and the pusher that serves it at the same coordinate.
if a.mag == 0
    off = 0;
else
    off = (a.mag - P.mag_choice) * P.mag_pitch;
end
end

% =========================================================================
function L = std_stroke(need, ladder)
%STD_STROKE  Smallest Janatics standard stroke that still reaches the target.
%   A pusher that cannot reach its target is not a design option, so the
%   rounding is always UP. If the requirement exceeds the longest standard
%   stroke the function errors rather than silently returning a cylinder that
%   cannot do the job.
k = find(ladder >= need - 1e-9, 1, 'first');
if isempty(k)
    error('initialize_factory:strokeTooLong', ...
        ['Required travel %.1f mm exceeds the longest standard Janatics ' ...
         'stroke (%.1f mm). Either the layout scale (P.SCALE) is wrong or ' ...
         'this station needs a different actuator family.'], ...
        need*1e3, max(ladder)*1e3);
end
L = ladder(k);
end
