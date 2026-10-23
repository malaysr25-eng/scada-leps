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
        if y.P_READY; nxt = 5; end

    case 5   % S04_DV_READY                   [SRC 4]  Dist. Valve -> PLC
        nxt = 6;

    case 6   % S05_DV_SEL_FEEDER              [SRC 5,6]
        plc.dv = [1 0 0 0];
        if y.BR_RDY(1) && y.CHG(P.ACT.feed);    nxt = 7;  end

    case 7   % S06_A1_EXTEND                  [SRC 7,8]
        plc = act_cmd(plc, P, P.ACT.feed,    1);
        if y.EXT(P.ACT.feed);    nxt = 8;  end

    case 8   % S07_PROX1_CHECK                [SRC 9]
        if y.PX(P.PROX_GUARD(1)); nxt = 9; end

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
        plc.dv = [1 0 0 0];
        if y.BR_RDY(1) && y.CHG(P.ACT.xfer1);   nxt = 14; end

    case 14  % S13_A6_EXTEND                  [SRC 15,16]
        plc = act_cmd(plc, P, P.ACT.xfer1,   1);
        if y.EXT(P.ACT.xfer1);   nxt = 15; end

    case 15  % S14_A6_RETRACT                 [IMPLICIT]
        plc = act_cmd(plc, P, P.ACT.xfer1,   0);
        if y.RET(P.ACT.xfer1);   nxt = 16; end

    case 16  % S15_CONV2_START                [SRC 17]
        plc.conv(2) = 1; nxt = 17;

    case 17  % S16_PROX3_CHECK                [SRC 18]
        if y.PX(P.PROX_GUARD(3)); nxt = 18; end

    case 18  % S17_CONV2_STOP                 [SRC 19]
        plc.conv(2) = 0; nxt = 19;

    case 19  % S18_DV_SEL_SECOND              [SRC 20,21]
        plc.dv = [0 1 0 0];
        if y.BR_RDY(2) && y.CHG(P.ACT.eng_in);  nxt = 20; end

    case 20  % S19_S2A1_EXTEND                [SRC 22,23]
        plc = act_cmd(plc, P, P.ACT.eng_in,  1);
        if y.EXT(P.ACT.eng_in);  nxt = 21; end

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
        plc = act_cmd(plc, P, P.ACT.eng_out, 1);
        if y.EXT(P.ACT.eng_out); nxt = 32; end

    case 32  % S31_S3A1_FEEDBACK              [SRC 35]  Actuator -> PLC
        nxt = 33;

    case 33  % S32_S3A1_RETRACT               [IMPLICIT]
        plc = act_cmd(plc, P, P.ACT.eng_out, 0);
        if y.RET(P.ACT.eng_out); nxt = 34; end

    case 34  % S33_CONV3_START                [SRC 36 - ANOMALY, see below]
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
        plc = act_cmd(plc, P, P.ACT.eject,   1);
        if y.EXT(P.ACT.eject);   nxt = 39; end

    case 39  % S38_S3A2_RETRACT               [IMPLICIT]
        plc = act_cmd(plc, P, P.ACT.eject,   0);
        if y.RET(P.ACT.eject);   nxt = 40; end

    case 40  % S39_CYCLE_COMPLETE
        plc.complete = true;
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
