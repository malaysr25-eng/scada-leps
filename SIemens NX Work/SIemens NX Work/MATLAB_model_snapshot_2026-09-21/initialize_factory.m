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
    'c3_end',  [12.900,  3.865], ...  % [MEAS] SV12 push line, 43 cm along belt 3
    'bin',     [12.900,  2.365], ...  % [ADD] collection bin, Sequence.xlsx 42
    'c3_out_b',[14.100,  3.865], ...  % [MEAS] SV13 push line, 55 cm along belt 3
    'bin_b',   [14.100,  2.365], ...  % [ASM] outfeed B's drop, same bin
    'c2_byp',  [ 7.925,  3.865], ...  % [SRC] block on conveyor 2, at belt 3
    'c3_byp',  [ 9.100,  3.865]);     % [ASM] SV11's drop, at belt 3's start
% BELT 3 FROM THE TAPE, 2026-09-12 (plan H3). The maintainer measured belt 3
% from its own start, x = 8.60 here (the drawn belt edge): SV11's drop 0 cm,
% cylinder B's drop 17 cm, SV12's push line 43 cm, SV13's 55 cm, px9 47 cm,
% px10 60 cm, length 75 cm (PROX_POSITIONS_MEASURED_2026-09-10.md). The datum
% checks out against the one point the drawing and the tape share: cylinder B's
% drop, c3_load, is 18.5 cm along in the drawing against 17 on the tape, so
% c3_load stays where it is. What moved:
%   c3_end    15.100 -> 12.900   outfeed A (SV12) and PX09 at 43 cm, not 65.
%                                The recorder had said so since 2026-09-07
%                                (FactoryParams 13J).
%   c3_out_b  13.240 -> 14.100   outfeed B (SV13) and PX10 at 55 cm, DOWNSTREAM
%                                of outfeed A, not upstream. A block stopped at
%                                outfeed A never reaches it - which is why prox
%                                10 has never tripped in a real cycle (F4).
%   c3_byp    new, 9.100         SV11's drop. "0 cm" is read as the block at
%                                the very start of the belt, its centre half a
%                                block (50 mm) in: [ASM].
%   bin, bin_b follow their outfeeds.
% Belt 2, measured from its own start (y = 8.50), already agrees with the tape
% and did not move: px7 26.0 cm drawn against 25 measured, px8 46.4 against 47.
% The belt-1 datum and the px6 "-20 cm" were not applied: see INPUTS_REQUIRED 4b.
%
% 'bin' is an [ADD]: Sequence.xlsx step 42 requires a collection bin and the
% reference script has none.
% [2026-09-13, plan H7: the bin's y moved 2.000 -> 2.365. SV12 and SV13 are
% stamped 160 mm, and a 186.5 mm push cannot reach a switch at 191.5 mm;
% 150 mm of travel (switch at 155) can, and the block still leaves belt 3
% with 32.5 mm to spare. The bin is invented and the stamp is not.]
%
% 'c2_byp' is where the workpiece sits on conveyor 2 when it is NOT going to
% be engraved: it runs past c2_end and on down the belt to the height of
% conveyor 3, and CYL_B pushes it +x from there onto belt 3. The owner marked
% the cylinder's position on a drawing of the cell; the x is conveyor 2's own
% centreline and the y is belt 3's, so neither number is invented.
% [CORRECTED 2026-09-11: the barrel that pushes from here is SOLENOID 11,
% MOVE_TO_CV3. The maintainer: "SV11 FIRES WHEN ENGRAVING IS SKIPPED". The
% position the owner marked stands; the barrel named with it did not.]
%
% It lands at c3_load - the SAME point the engraved part joins belt 3 from the
% engraver. Both routes converge there, which is what makes this a bypass
% rather than a second lane.
% [SUPERSEDED 2026-09-12, plan H3: SV11 drops the block at belt 3's start,
% c3_byp, 135 mm upstream of c3_load. The routes still converge on belt 3,
% but not at one point.]
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
% [SUPERSEDED 2026-09-12, plan H3: MEASURED. SV13's line is 55 cm along belt
% 3, downstream of outfeed A. See the belt-3 note above.]
%
% [SUPERSEDED 2026-09-11: coil 11 is MOVE_TO_CV3, the bypass, placed at
% c2_byp -> c3_load. See FACTORY_ACTUATORS. The paragraph is kept as written.]
% The OTHER unplaced actuator, XFER_CV2_CV3 on coil 11, is deliberately still
% unplaced. FC6 N15 fires it on Wp_move_cv3 with conveyor 3 on and conveyor 2
% off, and pairs it with no sensor at all - so there is no equivalent
% inference available and putting it somewhere would be invention. Question
% 17b asks for it.
% P.layout_variant is absent for every normal run, exactly as act_variant and
% base_variant are. PLCIOLATENCYTEST sets it to 'drawing' to restore the belt-3
% layout its historical figures were measured on, before plan H3 (2026-09-12):
% outfeed A at the drawing's c3_end, outfeed B upstream of it, and SV11
% landing where cylinder B does. A measurement cannot be reproduced on a
% layout it was not taken on. Stops and the bin follow in sections 3 and 4.
drawingLayout = isfield(P, 'layout_variant') && strcmp(P.layout_variant, 'drawing');
if drawingLayout
    WPu.c3_end   = [15.100, 3.865];  WPu.bin   = [15.100, 2.000];
    WPu.c3_out_b = [13.240, 3.865];  WPu.bin_b = [13.240, 2.000];
    WPu.c3_byp   = WPu.c3_load;
end
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

% The ROUTE, from FACTORYPARAMS section 15, is read here because three things
% below depend on it: which actuators the sequence drives, which belt-2
% locating stop exists, and which sensor ends the belt-2 run.
if ~(isscalar(P.engrave_selected) && ...
     (islogical(P.engrave_selected) || isnumeric(P.engrave_selected)))
    error('initialize_factory:route', ...
        'P.engrave_selected must be true (engrave) or false (the SV11 bypass).');
end
P.engrave_selected = logical(P.engrave_selected);

% P.act_variant is absent for every normal run. PLCIOLATENCYTEST sets it to
% 'historical5' to rebuild the five-cylinder plant its reference figures were
% measured on; see FACTORY_ACTUATORS.
if isfield(P, 'act_variant'); actVariant = P.act_variant; else; actVariant = 'machine'; end

% P.base_variant is absent for every normal run, exactly as act_variant is.
% The engraving axis became a velocity JOG on 2026-09-08 (FACTORYPARAMS
% section 8); PLCIOLATENCYTEST sets this to 'historical_pid' to restore the
% stiff position loop its reference figures were measured on. Resolved once
% here rather than tested inside FACTORY_DERIVATIVES, which runs per step.
if isfield(P, 'base_variant')
    P.base_jog = ~strcmp(P.base_variant, 'historical_pid');
else
    P.base_jog = true;
end
% P.seq_variant is absent for every normal run, as the variants above are.
% PLCIOLATENCYTEST sets it to 'serial' to restore the pre-H5 sequencing its
% historical figures were measured on: each belt started only once the
% previous push had come home. FACTORY_PLC reads the resolved flag. The
% Stateflow chart and the Python port always overlap - nothing reproduces
% history through them.
P.push_belt_overlap = ~(isfield(P, 'seq_variant') && strcmp(P.seq_variant, 'serial'));
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
    % PER-ACTUATOR AREAS. P.A_A / P.A_B remain as the nominal bore-20 pair,
    % because verify_model pins them and the catalogue cross-check reads them,
    % but the PHYSICS now reads these. All eleven are identical today; see the
    % note on bores in FACTORY_ACTUATORS for why they exist anyway.
    P.CYL(c).bore     = a.bore_mm*1e-3;
    P.CYL(c).rod      = a.rod_mm*1e-3;
    P.CYL(c).A_A      = pi*P.CYL(c).bore^2/4;
    P.CYL(c).A_B      = pi*(P.CYL(c).bore^2 - P.CYL(c).rod^2)/4;
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
        if isfield(a, 'stroke_mm') && ~isnan(a.stroke_mm)
            % THE NAMEPLATE STROKE, plan H7 2026-09-13. The reed switch stays
            % at the layout's x_trip; the barrel is as long as its label says.
            P.CYL(c).stroke = a.stroke_mm*1e-3;
            if P.CYL(c).stroke < P.CYL(c).x_trip - 1e-9
                error('initialize_factory:nameplateTooShort', ...
                    ['%s is stamped %.0f mm but its switch sits at %.1f mm. ' ...
                     'Either the layout or the barrel assignment is wrong.'], ...
                    a.name, a.stroke_mm, P.CYL(c).x_trip*1e3);
            end
        else
            P.CYL(c).stroke = std_stroke(P.CYL(c).x_trip, P.strokes);
        end
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
% Which five depends on the route. P.ACT.bypass has been looked up since
% 2026-09-02 and found nothing until 2026-09-11, when solenoid 11 took the role.
if P.engrave_selected
    P.ACT.driven = [P.ACT.feed P.ACT.xfer1 P.ACT.eng_in P.ACT.eng_out P.ACT.eject];
else
    % The bypass: SV11 stands in for cylinders A and B together, and the
    % engraving platform never moves. FACTORY_PLC states S40-S43.
    if isempty(P.ACT.bypass)
        error('initialize_factory:noBypass', ...
            ['P.engrave_selected is false but no actuator carries the ' ...
             '''bypass'' role (actuator variant "%s").'], actVariant);
    end
    P.ACT.driven = [P.ACT.feed P.ACT.xfer1 P.ACT.bypass P.ACT.eject];
end

%% ---- 3. Support-surface regions (priority ordered) --------------------
% [REF] rectangles from the reference script, in drawing units.
rdef = { 'conv3', 8.60,16.20, 3.19, 4.54,  1, 0; ...
         'engrave',8.60,12.30, 4.30, 6.95, 0, 0; ...
         'conv2', 7.25, 8.60, 0.90, 8.50,  0,-1; ...
         'conv1', 1.00, 8.60, 8.50, 9.85,  1, 0; ...
         'bin'  ,12.40,15.90, 1.00, 3.19,  0, 0};   % widened - see below
if drawingLayout; rdef{strcmp(rdef(:,1), 'bin'), 2} = 12.70; end   % pre-H3 bin edge
for i = 1:size(rdef,1)
    P.REG(i).name = rdef{i,1};
    P.REG(i).box  = [rdef{i,2} rdef{i,3} rdef{i,4} rdef{i,5}]*S;
    P.REG(i).uv   = [rdef{i,6} rdef{i,7}];   % belt direction unit vector
end
% THE BIN SPANS BOTH OUTFEED STATIONS. It was drawn under outfeed A alone,
% x = 14.30..15.90, because outfeed A was the only ejector the model had. The
% machine has two - solenoid 12 at prox 9 and solenoid 13 at prox 10, out of
% the same FC6 N16 network - and they drop into the SAME bin, so its left edge
% moves out to 12.70 to reach under outfeed B at x = 13.240. That 12.70 is not
% a measurement: it is outfeed B's own x less half a workpiece, i.e. the least
% the bin can be and still catch what B pushes. BIN_floor's gate widens with
% it, or a block ejected by B would fall through a floor that stops a metre to
% its right.
%
% Nothing in the modelled cycle crosses the new area: belt 3 runs at y = 3.865
% and the bin's top edge is 3.19, so the support-region priority list is
% untouched.
% [2026-09-12, plan H3: outfeed A moved to x = 12.900, upstream of outfeed B,
% so the left edge is now outfeed A's x less half a workpiece: 12.40.]

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
         'C3_side_rail','y',-1,  3.865,'x', 8.60,12.10; ...
         'C3_end_stop' ,'x',+1, 12.900,'y', 3.19, 4.54; ...
         'BIN_floor'   ,'y',-1,  2.365,'x',12.40,15.90; ...
         'C2_byp_stop' ,'y',-1,  3.865,'x', 7.25, 8.60};
% BELT 3, 2026-09-12 (plan H3): C3_end_stop and BIN_floor follow outfeed A to
% x = 12.900, and C3_side_rail's gate ends at 12.10 - 0.80 short of outfeed
% A, the margin it always had - so the rail cannot block the eject push.
%
% ONE ROUTE'S STOP IS THE OTHER ROUTE'S WALL (2026-09-11). C2_end_stop holds an
% engraved block on the cylinder A line. On the real cell nothing hard-stops it
% there - the belt stops on prox 7 - and a block that is NOT to be engraved
% runs straight past that point to prox 8. So that stand-in exists on the
% engraved route only, and the bypass gets its own at c2_byp, where SV11 picks
% the block up. Both are [ADD], for the reason the whole table is: without a
% stop the block coasts past its target and the rod meets it off-centre. On the
% engraved route P.STOP is exactly the seven stops it always was, in order.
if drawingLayout   % the pre-H3 belt-3 stops; see section 1
    sdef{strcmp(sdef(:,1), 'C3_side_rail'), 7} = 14.30;
    sdef{strcmp(sdef(:,1), 'C3_end_stop'),  4} = 15.100;
    sdef{strcmp(sdef(:,1), 'BIN_floor'),    6} = 12.70;
    sdef{strcmp(sdef(:,1), 'BIN_floor'),    4} = 2.000;   % pre-H7 bin floor
end
if P.engrave_selected
    sdef(strcmp(sdef(:,1), 'C2_byp_stop'), :) = [];
else
    sdef(strcmp(sdef(:,1), 'C2_end_stop'), :) = [];
end
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
% 2026-09-11: THE BELT-2 TRIP POINT PASSED FROM PX8 TO PX7, AND PX8 MOVED ON.
% The PLC listing gives the two routes two sensors. FC7 N5 ("WP IN CV2 MID",
% prox 7) feeds FC6 N7 (CYLA EXT) on the engraved route; FC6 N5 turns prox 8
% into Wp_move_cv3, which FC6 N15 turns into solenoid 11 on the bypass. The
% operator names prox 8 the SV11 pickup, and the one fully-watched engraved
% cycle never tripped it. So PX7 now sits at c2_end, where the engraved block
% stops - the same trip point, so the engraved cycle does not move - and PX8
% sits at c2_byp, where the bypass block stops. The tape readings (px7 25 cm,
% px8 47 cm along belt 2, 2026-09-10) are not applied here: they wait on the
% belt datums with everything else on that belt.
%
% ROLES are from the PLC program (plc/abc.pdf, FC6/FC7 - see FactoryParams
% section 13C). POSITIONS are a different matter and are marked below.
%
%   1-5   magazine compartments 1-5, dispense confirm.  FC7 N2 gates each on
%         workpiece_choice = N, so only the SELECTED compartment's sensor can
%         fire. The model feeds from compartment P.mag_choice, so exactly one
%         of these five ever trips. That is faithful, not a defect.
%   6     conveyor 1.       FC6 N3 / FC7 N4, clears the magazine push.
%   7     conveyor 2, engraved stop.  FC7 N5 "WP IN CV2 MID" -> FC6 N7 CYLA EXT.
%   8     conveyor 2, bypass pickup.  FC6 N5, 400 ms pulse -> Wp_move_cv3 -> SV11.
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

% PX7 sat at the conveyor 2 midpoint, (c2_load + c2_end)/2, until 2026-09-11,
% on nothing more than its network's title. See the note above.

% Outfeed station B sits upstream of station A on conveyor 3. The model ejects
% only at c3_end, so PX(10) trips as the block PASSES, which is what the real
% sensor would do. Placed at 60 % of the belt run: assumed, not measured.
% [SUPERSEDED 2026-09-12, plan H3: outfeed B is DOWNSTREAM of outfeed A, at
% 55 cm measured. A block stopped at outfeed A never reaches PX(10), and none
% ever has on the real cell.]
%
% ONE definition, not two: the waypoint c3_out_b in section 1 is that point,
% and the outfeed B actuator stands there. The sensor reads the waypoint
% rather than recomputing the 0.60, so the station and its sensor cannot drift
% apart - which is exactly the failure the magazine row had before mag_pitch
% was defined once.
c3_b = P.WP.c3_out_b;

P.PROX = [ magRow          % 1-5   magazine compartments      [ASM] except 1
           P.WP.c1_end     % 6     conveyor 1                 [SRC] step 11
           P.WP.c2_end     % 7     conveyor 2, engraved stop  [PLC] FC7 N5, step 18
           P.WP.c2_byp     % 8     conveyor 2, bypass pickup  [PLC] FC6 N5
           P.WP.c3_end     % 9     conveyor 3, outfeed A      [MEAS] SV12 line, 43 cm
           c3_b ];         % 10    conveyor 3, outfeed B      [MEAS] SV13 line, 55 cm
P.PROX_NAME = {'PX01_mag1_dispense','PX02_mag2_dispense', ...
               'PX03_mag3_dispense','PX04_mag4_dispense', ...
               'PX05_mag5_dispense','PX06_conv1', ...
               'PX07_conv2_engrave','PX08_conv2_bypass', ...
               'PX09_conv3_outfeed_a','PX10_conv3_outfeed_b'};
% Which of the ten the sequencer actually gates on. The other six are
% MODELLED AND LOGGED but guard nothing, because the model's sequence is
% Sequence.xlsx's and the machine's is FC6's, and those are not the same
% sequence. Reconciling them is the plant re-model, not this change.
P.PROX_GUARD = [P.mag_choice 6 7 9];   % [PLC] states 8, 11, 17, 35
% The bypass route's own sensor. State 17 (S16) watches PX(PROX_GUARD(3)) when
% engraving is selected and PX(PROX_BYPASS) when it is skipped.
P.PROX_BYPASS = 8;                     % [PLC] FC6 N5 -> Wp_move_cv3
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
