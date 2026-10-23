function [plc, u] = factory_plc(plc, y, t, P)
%FACTORY_PLC  Deterministic scan-based sequencer implementing Sequence.xlsx.
%
%   [plc, u] = FACTORY_PLC(plc, y, t, P) executes one PLC scan.
%     plc  controller state struct (use FACTORY_PLC_INIT to create)
%     y    sensor struct from FACTORY_SENSORS
%     t    current simulation time [s]
%     u    command struct consumed by FACTORY_DERIVATIVES
%
%   DESIGN RULE. A state advances only when a PHYSICAL sensor confirms the
%   commanded action has happened. The only exceptions are the three manual
%   operator states (Excel rows 27-29), for which Sequence.xlsx supplies no
%   completion signal at all - there is nothing to wait for but the operator.
%   Those three are the model's only timed transitions and are marked as
%   placeholders.
%
%   This structure maps one-to-one onto Stateflow: each CASE below becomes a
%   state, each guard becomes a transition condition. See BUILD_FACTORY_MODEL.
%
%   THE SEQUENCER WRITES COILS, NOT CYLINDERS. Until 2026-09-02 it wrote a
%   spool target per cylinder, plc.sv(1:5). It now writes the machine's
%   thirteen solenoid coils, plc.sol(1:13), through ACT_CMD, because eleven
%   actuators carry thirteen coils - CYL_A and CYL_B are double-solenoid and
%   take two each. Which coil belongs to which actuator is FACTORY_ACTUATORS'
%   business, and P.ACT names the actuator by role so that no bare index
%   appears below.
%
%   THE SENSOR GUARDS MOVED WITH THE COMMANDS. y.EXT, y.RET and y.CHG are
%   indexed by ACTUATOR, and the actuator numbering is now the machine's, so
%   y.EXT(2) is the second magazine pusher and not - as it was until
%   2026-09-02 - the conveyor 1 to 2 transfer. Every guard below therefore
%   names its actuator through P.ACT as well. Leaving the bare indices was
%   caught by the cycle stalling at S13 with a watchdog timeout, which is the
%   loud failure the physics-gated design is supposed to produce; it is worth
%   knowing that it did.
%
%   COILS ARE HELD, NOT PULSED. The real machine pulses the double-solenoid
%   coils for T#2S (FC6 networks 4, 7, 15) and relies on the valve latching.
%   This sequencer energises them for the whole stroke instead. For a latching
%   valve the two produce the SAME spool trajectory, which is why widening the
%   valve model did not move the pinned baseline; modelling the pulse would
%   add a timer that changes nothing. Recorded so that nobody reads the held
%   coil as a claim about how the machine drives it.
%
%   TWO ROUTES (2026-09-11). The maintainer: "CYLINDER b FIRES WHEN ENGRAVING
%   IS DONE AND IT PUSHES BLOCK TO BELT 3, SV11 FIRES WHEN ENGRAVING IS
%   SKIPPED". P.engrave_selected picks the route at S16. Engraved - the default,
%   and every recorded cycle so far - is the Sequence.xlsx cycle, unchanged.
%   Skipped is S40-S43: the block runs on to prox 8, conveyor 2 stops and
%   conveyor 3 starts, SV11 pushes the block across onto belt 3 on its T#2S
%   pulse (FC6 N5 -> Wp_move_cv3 -> FC6 N15), and the cycle rejoins the
%   engraved route at S33. Cylinders A and B and the platform never move.

ST = factory_states();

%% ---- derived interlock status -------------------------------------------
% The machine publishes Air_Pressure_ok, ENGV_Plate_Home, All_Cylinders_Home,
% Emergency Healthy and Startup_Healthy as tags. Every one of them is a
% condition the model can already compute, so they are DERIVED here rather
% than duplicated as extra channels on the sensor bus - two channels computing
% one condition is how this project has drifted before.
%
% These are STATUS, not guards. Nothing below reads them, so they cannot
% change the sequence; they exist so FACTORY_IO_MAP can point those rows at a
% signal that is real instead of at an `ilk.*` name that was never built.
plc.ilk.air_ok     = y.P_READY;
plc.ilk.plate_home = y.HS_BOT;
plc.ilk.cyl_home   = all(y.RET);
plc.ilk.estop_ok   = y.ESTOP_OK;
plc.ilk.startup_ok = plc.ilk.air_ok && plc.ilk.plate_home && ...
                     plc.ilk.cyl_home && plc.ilk.estop_ok;

%% ---- E-Stop -------------------------------------------------------------
% A hard-wired safety loop on the real machine - PLCTAGLIST carries Emergency
% and Emergency Healthy - and the model had no counterpart to it until
% 2026-09-02. Dropping the loop de-energises every coil, stops the compressor
% and HOLDS the sequencer where it stands. It does not reset: Cycle_Reset is a
% separate tag on the machine and resetting here would invent a behaviour.
%
% t_in is frozen with everything else, so the per-state watchdog cannot expire
% while the cell is stopped and report a timeout that is really an E-Stop.
%
% Note what de-energising does NOT do. A double-solenoid valve HOLDS its spool
% with both coils off, so CYL_A and CYL_B keep the position they had. That is
% the real behaviour of this hardware, and it is why an E-Stop on this cell
% does not drop the workpiece mid-transfer.
%
% plc.base is left alone. Whether the electric engraving axis holds or falls
% when its drive is disabled is not known, and inventing either is worse than
% leaving the command where the sequence put it. INPUTS_REQUIRED.md asks.
if ~y.ESTOP_OK
    plc.estop = true;
    plc.sol   = zeros(1, P.NSOL);
    plc.conv  = [0 0 0];
    plc.pump  = false;
    u.pump_on = plc.pump;  u.dv   = plc.dv;    u.sol = plc.sol;
    u.conv    = plc.conv;  u.base = plc.base;
    return
end
plc.estop = false;

plc.t_in = plc.t_in + P.t_scan;
st  = plc.state;
nxt = 0;
el  = plc.t_in;

%% ---- compressor pressure switch (hysteresis) ---------------------------
% A physical pressure switch on the receiver, scanned every cycle. This is
% not part of the Excel sequence but without it the compressor never stops
% and the receiver integrates to unbounded pressure.
if y.P_res >= P.P_cut_out
    plc.pump = false;
elseif y.P_res <= P.P_cut_in
    plc.pump = plc.pump_enable;
else
    plc.pump = plc.pump && plc.pump_enable;
end

%% ---- sequencer ---------------------------------------------------------
switch st
    case 1   % S00_INIT
        plc.pump_enable = false; plc.dv = [0 0 0 0];
        plc.sol = zeros(1,P.NSOL); plc.conv = [0 0 0]; plc.base = 0;
        nxt = 2;

    case 2   % S01_CAMERA_DETECT              [SRC 1]  Camera -> PLC
        if y.CAM; nxt = 3; end

    case 3   % S02_PUMP_CMD                   [SRC 2]  PLC -> Pump
        plc.pump_enable = true;
        plc.pump = y.P_res < P.P_cut_out;
        nxt = 4;

    case 4   % S03_PRESSURE_PREP              [SRC 3]  Pump -> Dist. Valve
        % THE T#10S START DELAY, plan H2 2026-09-12. The machine waits 10 s
        % from CMD_START before the first dispense (n=5, 9.99-10.20 s to SV1)
        % and checks no pressure. P_READY is the model's own interlock: it is
        % met at ~2.4 s, so it binds only if the supply fails. The cylinder-
        % home pulse the machine fires in this window (SV10, SV8) is not
        % modelled: coils are held here, not pulsed, and both rods start home.
        if y.P_READY && el >= P.PLC.t_start_delay; nxt = 5; end

    case 5   % S04_DV_READY                   [SRC 4]  Dist. Valve -> PLC
        nxt = 6;

    case 6   % S05_DV_SEL_FEEDER              [SRC 5,6]
        plc.dv = [1 0 0 0];
        if y.BR_RDY(1) && y.CHG(P.ACT.feed);    nxt = 7;  end

    case 7   % S06_A1_EXTEND                  [SRC 7,8]
        plc = act_cmd(plc, P, P.ACT.feed,    1);
        if y.EXT(P.ACT.feed);    nxt = 8;  end

    case 8   % S07_PROX1_CHECK                [SRC 9]
        % FC7 N2 gates on "prox N AND workpiece_choice = N", then runs a 2 s
        % TON before the conveyor starts. Read straight off the one fully
        % watched real cycle: SV1 fires at 9.987 s, prox 1 confirms at 10.734,
        % and conveyor 1 does not start until 12.755 - 2.021 s later. The
        % model advanced on the sensor alone and lost the whole TON.
        if y.PX(P.PROX_GUARD(1)) && el >= P.PLC.t_dispense_ton; nxt = 9; end

    case 9   % S08_A1_RETRACT                 [IMPLICIT]
        plc = act_cmd(plc, P, P.ACT.feed,    0);
        if y.RET(P.ACT.feed);    nxt = 10; end

    case 10  % S09_CONV1_START                [SRC 10]
        plc.conv(1) = 1; nxt = 11;

    case 11  % S10_PROX2_CHECK                [SRC 11]
        if y.PX(P.PROX_GUARD(2)); nxt = 12; end

    case 12  % S11_CONV1_STOP                 [SRC 12]
        plc.conv(1) = 0; nxt = 13;

    case 13  % S12_DV_SEL_FEEDER2             [SRC 13,14]
        % FC6 N4 waits 2 s after prox 6 before firing the conveyor 1 -> 2
        % transfer, and the wait sits HERE, before the transfer is commanded,
        % which is where the machine puts it. Measured 2.124 s but n=1 - it
        % rests on the single fully-watched cycle, and it agrees with a T#2S
        % literal in the program text (13K). Two sources, one cycle.
        plc.dv = [1 0 0 0];
        if y.BR_RDY(1) && y.CHG(P.ACT.xfer1) && el >= P.PLC.t_xfer1_dwell
            nxt = 14;
        end

    case 14  % S13_A6_EXTEND                  [SRC 15,16]
        % PUSH AND BELT TOGETHER, plan H5 2026-09-12. In every recorded cycle
        % conveyor 2 starts in the SAME SAMPLE as the transfer push (SV6), not
        % after the rod has come home: 19.651 s for both in C0003-180221. So
        % belt 2 is switched on here, and S15 finds it already running. The
        % model used to push, retract, and only then start the belt.
        plc = act_cmd(plc, P, P.ACT.xfer1,   1);
        % Absent flag = overlap: a P that skipped INITIALIZE_FACTORY gets the
        % machine's behaviour, not the historical one.
        if ~isfield(P, 'push_belt_overlap') || P.push_belt_overlap; plc.conv(2) = 1; end
        if y.EXT(P.ACT.xfer1);   nxt = 15; end

    case 15  % S14_A6_RETRACT                 [IMPLICIT]
        plc = act_cmd(plc, P, P.ACT.xfer1,   0);
        if y.RET(P.ACT.xfer1);   nxt = 16; end

    case 16  % S15_CONV2_START                [SRC 17]
        % Already running since S13 (plan H5). Kept, so the state table stays
        % one-to-one with Sequence.xlsx row 17.
        plc.conv(2) = 1; nxt = 17;

    case 17  % S16_PROX3_CHECK                [SRC 18]  | bypass: FC6 N5
        % THE ROUTE SPLITS HERE. Engraving selected: conveyor 2 stops on prox
        % 7 at the cylinder A line (FC7 N5, "WP IN CV2 MID") and the
        % Sequence.xlsx cycle carries on. Engraving skipped: the block runs on
        % to prox 8, which FC6 N5 turns into Wp_move_cv3, and the SV11 branch
        % at the bottom of this switch takes it straight to belt 3.
        if P.engrave_selected
            if y.PX(P.PROX_GUARD(3)); nxt = 18; end
        else
            if y.PX(P.PROX_BYPASS);   nxt = 41; end
        end

    case 18  % S17_CONV2_STOP                 [SRC 19]
        plc.conv(2) = 0; nxt = 19;

    case 19  % S18_DV_SEL_SECOND              [SRC 20,21]
        % THE WAIT BEFORE CYLINDER A, plan H6 2026-09-13. The machine fires SV7
        % 1.31-1.58 s after conveyor 2 stops (n=7), in the sample its
        % conveyor-2 axis finishes a position move. The model has no such
        % axis, so the wait enters as its measured mean. See FactoryParams.
        plc.dv = [0 1 0 0];
        if y.BR_RDY(2) && y.CHG(P.ACT.eng_in) && el >= P.PLC.t_cylA_wait;  nxt = 20; end

    case 20  % S19_S2A1_EXTEND                [SRC 22,23]
        % The machine holds this coil 8.059 s (n=7) and CANNOT SEE THE ROD -
        % it has no cylinder position feedback anywhere in its 158 tags, so it
        % is timing, not waiting. Rod arrival is still required: the dwell
        % delays the step, it does not excuse an actuator that never arrives.
        plc = act_cmd(plc, P, P.ACT.eng_in,  1);
        if y.EXT(P.ACT.eng_in) && el >= P.PLC.t_cylA_hold;  nxt = 21; end

    case 21  % S20_S2A1_FEEDBACK              [SRC 24]  Actuator -> PLC
        nxt = 22;

    case 22  % S21_S2A1_RETRACT               [IMPLICIT]
        plc = act_cmd(plc, P, P.ACT.eng_in,  0);
        if y.RET(P.ACT.eng_in);  nxt = 23; end

    case 23  % S22_BASE_UP                    [SRC 25]  PLC -> Engraving Base
        plc.base = 1; nxt = 24;

    case 24  % S23_HEIGHT_TOP                 [SRC 26]  Height sensor -> PLC
        if y.HS_TOP; nxt = 25; end

    case 25  % S24_OPERATOR_NOTIFY            [SRC 27]  PLC -> Interface
        plc.op_notified = true;
        if el >= P.t_op_notice; nxt = 26; end        % PLACEHOLDER timing

    case 26  % S25_ENGRAVE_MANUAL             [SRC 28]  Manual input
        plc.engraving = true;
        if el >= P.t_engrave; nxt = 27; end          % PLACEHOLDER timing

    case 27  % S26_ENGRAVE_CONFIRM            [SRC 29]  Manual input
        plc.engraving = false; plc.engraved = true;
        if el >= P.t_op_confirm; nxt = 28; end       % PLACEHOLDER timing

    case 28  % S27_BASE_DOWN                  [IMPLICIT]
        % Excel row 30 verifies the bottom position but no row ever commands
        % the base down. The command is implied by row 30 and added here.
        plc.base = 0; nxt = 29;

    case 29  % S28_HEIGHT_BOTTOM              [SRC 30]  Height sensor -> PLC
        if y.HS_BOT; nxt = 30; end

    case 30  % S29_DV_SEL_THIRD               [SRC 31,32]
        plc.dv = [0 0 1 0];
        if y.BR_RDY(3) && y.CHG(P.ACT.eng_out); nxt = 31; end

    case 31  % S30_S3A1_EXTEND                [SRC 33,34]
        % The machine holds cylinder B's extend coil 8.199 s for this move -
        % SV9 at 80.751 s, SV10 at 88.950 s in the fully-watched cycle - and,
        % like cylinder A, it cannot see the rod. Same argument, same shape of
        % guard: arrived AND the dwell elapsed.
        plc = act_cmd(plc, P, P.ACT.eng_out, 1);
        if y.EXT(P.ACT.eng_out) && el >= P.PLC.t_cylB_hold; nxt = 32; end

    case 32  % S31_S3A1_FEEDBACK              [SRC 35]  Actuator -> PLC
        nxt = 33;

    case 33  % S32_S3A1_RETRACT               [IMPLICIT]
        % BELT 3 STARTS AS CYLINDER B RELEASES, plan H5 2026-09-12: conveyor 3
        % and SV10 (cylinder B's retract) rise in the same sample, 88.950 s in
        % C0003-180221. So belt 3 starts here, with the retract, not after it.
        plc = act_cmd(plc, P, P.ACT.eng_out, 0);
        if ~isfield(P, 'push_belt_overlap') || P.push_belt_overlap; plc.conv(3) = 1; end
        if y.RET(P.ACT.eng_out); nxt = 34; end

    case 34  % S33_CONV3_START                [SRC 36 - ANOMALY, see below]
        % [2026-09-12, plan H5: belt 3 is already running by here - since S32
        % on the engraved route, since S40 on the bypass. Kept one-to-one with
        % Sequence.xlsx row 36.]
        % Excel row 36 reads "Conveyor Stop". Implemented as START because
        % the workpiece has just been placed on a stationary belt and row 37
        % requires a downstream position check that a stopped belt can never
        % reach. Rows 10-12 and 17-19 establish Start/check/Stop as the
        % pattern. Recorded as an anomaly, not silently corrected.
        plc.conv(3) = 1; nxt = 35;

    case 35  % S34_PROX4_FINAL                [SRC 37]  Final position check
        if y.PX(P.PROX_GUARD(4)); nxt = 36; end

    case 36  % S35_CONV3_STOP                 [SRC 38]
        plc.conv(3) = 0; nxt = 37;

    case 37  % S36_DV_SEL_FOURTH              [SRC 39,40]
        plc.dv = [0 0 0 1];
        if y.BR_RDY(4) && y.CHG(P.ACT.eject);   nxt = 38; end

    case 38  % S37_S3A2_EXTEND                [SRC 41,42]  -> Bin
        % FC6 N16 fires this coil as a T#5S PULSE. Measured 5.010 s over ten
        % real cycles, stdev 0.077 s - the tightest figure in the data set,
        % and the model implemented none of it.
        plc = act_cmd(plc, P, P.ACT.eject,   1);
        if y.EXT(P.ACT.eject) && el >= P.PLC.t_outfeed_pulse;   nxt = 39; end

    case 39  % S38_S3A2_RETRACT               [IMPLICIT]
        plc = act_cmd(plc, P, P.ACT.eject,   0);
        if y.RET(P.ACT.eject);   nxt = 40; end

    case 40  % S39_CYCLE_COMPLETE
        plc.complete = true;

    % ---- the bypass route, P.engrave_selected = false ------------------
    case 41  % S40_BYP_CONV2_STOP             [PLC FC6 N5, N15]
        % FC6 N15 fires solenoid 11 only with conveyor 3 ON and conveyor 2
        % OFF, so both change here, before the push.
        plc.conv(2) = 0; plc.conv(3) = 1; nxt = 42;

    case 42  % S41_BYP_DV_SEL                 [branch 3, as FACTORY_ACTUATORS]
        plc.dv = [0 0 1 0];
        if y.BR_RDY(3) && y.CHG(P.ACT.bypass); nxt = 43; end

    case 43  % S42_BYP_SV11_EXTEND            [PLC FC6 N15, T#2S TP]
        % A spring-return valve on a 2 s pulse: the coil drops when the TP
        % expires and the spring brings the rod home. The guard has the
        % outfeed's shape - the rod must arrive AND the pulse must have run -
        % so the timer cannot excuse a rod that never gets there.
        plc = act_cmd(plc, P, P.ACT.bypass, 1);
        if y.EXT(P.ACT.bypass) && el >= P.PLC.t_valve_pulse; nxt = 44; end

    case 44  % S43_BYP_SV11_RETRACT           [IMPLICIT]
        % Rejoin the engraved route at S33: belt 3 carries the block to prox
        % 9 and the outfeed exactly as it carries an engraved one.
        plc = act_cmd(plc, P, P.ACT.bypass, 0);
        if y.RET(P.ACT.bypass); nxt = 34; end
end

%% ---- watchdog ----------------------------------------------------------
if nxt == 0 && plc.t_in > P.t_timeout && st ~= 40
    plc.timeouts(end+1,:) = {t, ST{st,1}};
    plc.fault = true;
    plc.t_in  = 0;
end

if nxt ~= 0 && nxt ~= st
    plc.state = nxt;
    plc.t_in  = 0;
    plc.log(end+1,:) = {t, ST{nxt,1}, ST{nxt,2}};
end

%% ---- outputs -----------------------------------------------------------
u.pump_on = plc.pump;
u.dv      = plc.dv;
u.sol     = plc.sol;
u.conv    = plc.conv;
u.base    = plc.base;
end

% =========================================================================
function plc = act_cmd(plc, P, a, want)
%ACT_CMD  Command actuator a to extend (want = 1) or retract (want = 0).
%
%   The sequencer says what it wants the ROD to do; this turns that into coil
%   states according to the valve the actuator actually carries.
%
%     spring-return    one coil. Energised extends, released lets the spring
%                      retract, so the coil IS the command.
%     double-solenoid  two coils. Energise the one for the direction wanted
%                      and drop the other; never both, which on real hardware
%                      is a wiring fault rather than a command.
C = P.CYL(a);
plc.sol(C.coil_ext) = want;
if C.dbl
    plc.sol(C.coil_ret) = 1 - want;
end
end
