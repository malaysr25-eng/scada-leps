function factory_plc_sfun(block)
%FACTORY_PLC_SFUN  Level-2 MATLAB S-function wrapping the validated PLC.
%
%   Discrete block, sample time P.t_scan (10 ms), zero-order hold on its
%   outputs - exactly how a real PLC behaves and exactly what
%   RUN_FACTORY_SIMULATION does.
%
%   Input  port 1 : sensor vector from the plant, FACTORY_SENSOR_BUS wide
%   Output port 1 : command vector, FACTORY_CMD_BUS wide
%                   [pump; dv(1:4); sol(1:13); conv(1:3); base]
%   Output port 2 : 1x1  active PLC state number (1..40)
%   Output port 3 : 1x1  cycle-complete flag, drives the Stop block
%
%   WHY THIS EXISTS RATHER THAN A STATEFLOW CHART
%   Iteration 01 shipped BUILD_FACTORY_MODEL, which constructs the same
%   40-state sequence as a Stateflow chart through the Stateflow API. That
%   path now builds and runs (2026-08-24), but nothing yet checks it walks the
%   same 40 states, and programmatic chart construction is fragile. This block
%   runs FACTORY_PLC directly - the same file the
%   validated MATLAB driver calls, byte for byte - so the Simulink model and
%   the MATLAB driver cannot diverge, and the model needs only Simulink, no
%   Stateflow licence.
%
%   The Stateflow variant is still available:
%       build_factory_model('PLC','stateflow')
%   It builds and simulates, but its SEQUENCE is unverified against
%   FACTORY_PLC. See README.md section 11 (Known limitations).
%
%   LIMITATION - SINGLE INSTANCE
%   The controller state is held in a PERSISTENT variable, so exactly one
%   instance of this block may appear in one MATLAB session. That is true of
%   this model. If you ever need two cells in one model, move the state into
%   DWork vectors first.
%
%   After an aborted simulation the persistent state can be left mid-cycle.
%   RESET_FACTORY clears it. Simulink also calls InitializeConditions at the
%   start of every run, which clears it too, so this is belt and braces.
%
%   Sensor vector packing: FACTORY_SENSOR_BUS is the definition. Do not
%   restate the indices here - a header that lists them is a second copy that
%   drifts, and this one did: it described a 28-wide bus with PX(1:4) for the
%   whole of the day after the sensors were widened to the machine's ten.
%     B = factory_sensor_bus(P);  B.PX, B.EXT, ... B.width
%
%   Command vector packing: FACTORY_CMD_BUS, on the same terms.
%     B = factory_cmd_bus(P);     B.pump, B.dv, B.sol, B.conv, B.base
%
%   See also FACTORY_PLC, FACTORY_PLANT_SFUN, BUILD_FACTORY_MODEL.

setup(block);
end

%% ------------------------------------------------------------------------
function setup(block)
P = factory_params_cached();

block.NumInputPorts  = 1;
block.NumOutputPorts = 3;
block.SetPreCompInpPortInfoToDynamic;
block.SetPreCompOutPortInfoToDynamic;

block.InputPort(1).Dimensions        = factory_sensor_bus(P).width;
block.InputPort(1).DatatypeID        = 0;      % double
block.InputPort(1).Complexity        = 'Real';
% DIRECT FEEDTHROUGH is chosen by P.plc_io_delay. It is not cosmetic.
%
%   delay 0 -> TRUE.  Outputs reads the sensor bus and runs the scan, so the
%              command leaves in the SAME scan the sensors were read in.
%              Identical to RUN_FACTORY_SIMULATION.
%   delay 1 -> FALSE. Outputs emits the command latched by the PREVIOUS scan
%              and the scan runs in Update.
%
% TRUE does NOT create an algebraic loop. FACTORY_PLANT_SFUN declares its own
% input port non-direct-feedthrough because its Outputs method reads only
% block.ContStates, so the plant already breaks the loop. The old comment
% here claimed FALSE was doing that job; it was not, and the unnecessary
% FALSE is what made the Simulink path lag the MATLAB path by one scan on
% every command (open issue 3).
block.InputPort(1).DirectFeedthrough = (P.plc_io_delay == 0);

block.OutputPort(1).Dimensions = factory_cmd_bus(P).width;
block.OutputPort(2).Dimensions = 1;
block.OutputPort(3).Dimensions = 1;
for k = 1:3
    block.OutputPort(k).DatatypeID = 0;
    block.OutputPort(k).Complexity = 'Real';
    block.OutputPort(k).SamplingMode = 'Sample';
end

block.NumDialogPrms = 0;
block.SampleTimes   = [P.t_scan 0];            % discrete, 10 ms
block.NumContStates = 0;
block.SimStateCompliance = 'HasNoSimState';

block.RegBlockMethod('InitializeConditions', @InitConditions);
block.RegBlockMethod('Outputs',              @Outputs);
block.RegBlockMethod('Update',               @Update);
block.RegBlockMethod('Terminate',            @Terminate);
end

%% ------------------------------------------------------------------------
function InitConditions(block) %#ok<INUSD>
P = factory_params_cached();
plc_state('reset', P);
end

%% ------------------------------------------------------------------------
function Outputs(block)
% With P.plc_io_delay == 0 the scan happens HERE, so the command reflects the
% sensors of this very scan. With 1 the scan happened in Update one scan ago
% and this only re-emits what was latched then.
P = factory_params_cached();
if P.plc_io_delay == 0
    plc_state('scan', P, unpack_sensors(block.InputPort(1).Data, P), ...
              block.CurrentTime);
end
[~, u, st, done] = plc_state('get');
block.OutputPort(1).Data = [u.pump_on; u.dv(:); u.sol(:); u.conv(:); u.base];
block.OutputPort(2).Data = st;
block.OutputPort(3).Data = done;
end

%% ------------------------------------------------------------------------
function Update(block)
% One PLC scan: read the sensor bus, run the sequencer, latch the outputs.
% Skipped entirely when P.plc_io_delay == 0, because Outputs already scanned
% at this time value and plc_state would refuse the duplicate anyway.
P = factory_params_cached();
if P.plc_io_delay == 0; return; end
plc_state('scan', P, unpack_sensors(block.InputPort(1).Data, P), ...
          block.CurrentTime);
end

%% ------------------------------------------------------------------------
function Terminate(block) %#ok<INUSD>
% Leave the final controller state in place so the caller can inspect it
% with FACTORY_PLC_SFUN's companion, plc_state('get'), after the run.
end

%% ========================================================================
function [plc, u, st, done] = plc_state(action, P, y, t)
%PLC_STATE  Persistent holder for the controller state and latched outputs.
%   TSCAN holds the time of the last scan actually executed. Simulink may
%   call Outputs more than once at the same time value (initialisation,
%   solver resets); without the guard the sequencer would advance twice in
%   one scan and the run would silently skip states.
persistent PLC U TSCAN
switch action
    case 'reset'
        PLC   = factory_plc_init(P);
        U     = struct('pump_on',false,'dv',[0 0 0 0], ...
                       'sol',zeros(1,P.NSOL),'conv',[0 0 0],'base',0);
        TSCAN = NaN;
    case 'scan'
        if isempty(PLC); PLC = factory_plc_init(P); end
        if isempty(TSCAN) || isnan(TSCAN) || t > TSCAN
            [PLC, U] = factory_plc(PLC, y, t, P);
            TSCAN    = t;
        end
    case 'get'
        % nothing to do
end
if isempty(PLC)
    % plc_state('get') is called with ONE argument, so P is not in scope here.
    % The old literal zeros(1,5) survived that; P.NSOL would not, and would
    % have thrown only on the path where the block is polled before its first
    % reset. Fetch the cache rather than re-typing the width.
    if nargin < 2 || isempty(P); P = factory_params_cached(); end
    plc = []; u = struct('pump_on',false,'dv',[0 0 0 0], ...
                         'sol',zeros(1,P.NSOL),'conv',[0 0 0],'base',0);
    st = 1; done = 0;
else
    plc = PLC; u = U; st = PLC.state; done = double(PLC.complete);
end
end

%% ========================================================================
function y = unpack_sensors(v, P)
%UNPACK_SENSORS  Inverse of the packing in FACTORY_PLANT_SFUN.
%   Logical channels are thresholded at 0.5 so the bus can travel as double.
n = P.NCYL;
B = factory_sensor_bus(P);
if numel(v) ~= B.width
    error('factory_plc_sfun:busWidth', ...
        'Sensor bus is %d wide, FACTORY_SENSOR_BUS declares %d.', ...
        numel(v), B.width);
end
y.CAM     = v(B.CAM)     > 0.5;
y.PX      = (v(B.PX)     > 0.5)';
y.EXT     = (v(B.EXT)    > 0.5)';
y.RET     = (v(B.RET)    > 0.5)';
y.HS_TOP  = v(B.HS_TOP)  > 0.5;
y.HS_BOT  = v(B.HS_BOT)  > 0.5;
y.P_res   = v(B.P_res);          % the one analogue channel
y.P_READY = v(B.P_READY) > 0.5;
y.BR_RDY  = (v(B.BR_RDY) > 0.5)';
y.CHG     = (v(B.CHG)    > 0.5)';
y.ESTOP_OK = v(B.ESTOP_OK) > 0.5;
if numel(y.EXT) ~= n
    error('factory_plc_sfun:width', ...
        'Sensor bus is packed for %d cylinders, model has %d.', ...
        numel(y.EXT), n);
end
end
