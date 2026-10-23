function factory_plant_sfun(block)
%FACTORY_PLANT_SFUN  Level-2 MATLAB S-function wrapping the physical plant.
%
%   Continuous states : the full plant state vector s (see P.IX)
%   Input  port 1     : command vector from the PLC, FACTORY_CMD_BUS wide
%                       [pump; dv(1:4); sol(1:13); conv(1:3); base]
%   Output port 1     : full state vector s          (for logging / scopes)
%   Output port 2     : sensor vector, FACTORY_SENSOR_BUS wide (to the PLC)
%
%   WHY A LEVEL-2 S-FUNCTION AND NOT A MATLAB FUNCTION BLOCK
%   FACTORY_DERIVATIVES uses cell arrays, struct arrays with character
%   fields and STRCMP, none of which are supported by MATLAB Function block
%   code generation. A Level-2 S-function executes the interpreted MATLAB
%   directly, so the physics that was validated stays byte-identical instead
%   of being rewritten into a codegen-safe dialect and re-validated.
%   Trade-off: no code generation from this block. See Known Issues.
%
%   ITERATION 03 FIX. Every method used to call
%       P = initialize_factory(FactoryParams());
%   which rebuilt the entire parameter set, cylinder table, region table and
%   index map on every one of ~720,000 evaluations. The model was not wrong,
%   it was too slow to finish. Parameters now come from
%   FACTORY_PARAMS_CACHED. After editing FactoryParams.m or JanaticsData.m
%   run RESET_FACTORY (or "clear factory_params_cached") or the model will
%   keep using the old values.
%
%   Sensor vector packing: FACTORY_SENSOR_BUS is the definition. Do not
%   restate the indices here - a header that lists them is a second copy that
%   drifts, and this one did: it described a 28-wide bus with PX(1:4) for the
%   whole of the day after the sensors were widened to the machine's ten.
%     B = factory_sensor_bus(P);  B.PX, B.EXT, ... B.width
%
%   Command vector packing: FACTORY_CMD_BUS, on the same terms.
%     B = factory_cmd_bus(P);     B.pump, B.dv, B.sol, B.conv, B.base

setup(block);
end

%% ------------------------------------------------------------------------
function setup(block)
P = factory_params_cached();

block.NumInputPorts  = 1;
block.NumOutputPorts = 2;
block.SetPreCompInpPortInfoToDynamic;
block.SetPreCompOutPortInfoToDynamic;

block.InputPort(1).Dimensions        = factory_cmd_bus(P).width;
block.InputPort(1).DatatypeID        = 0;
block.InputPort(1).Complexity        = 'Real';
block.InputPort(1).DirectFeedthrough = false;

block.OutputPort(1).Dimensions = P.NS;
block.OutputPort(2).Dimensions = factory_sensor_bus(P).width;
for k = 1:2
    block.OutputPort(k).DatatypeID   = 0;
    block.OutputPort(k).Complexity   = 'Real';
    block.OutputPort(k).SamplingMode = 'Sample';
end

block.NumDialogPrms = 0;
% [0 0] = continuous. This is the ONLY declaration Simulink accepts for this
% block, and three alternatives were measured and rejected:
%
%   [0 1] "fixed in minor step"   -> "Single rate S-function ... must specify
%                                     a continuous sample time"
%   [0 0; P.t_scan 0] multi-rate  -> "Only one sample time can be specified"
%   port-based sample times       -> Simulink:blocks:MSFcnMissingSetPortSampleTime
%
% A block with continuous states cannot be multi-rate through block-based
% sample times, so Outputs is called at EVERY ode4 minor step: 16,001 times
% for a 2 s run, of which only the ~200 landing on a PLC scan are ever read.
% Profiling attributes 2.8 s of an 8.4 s profiled run to this one method.
%
% Recovering that ~25% needs port-based sample times plus registered
% SetInputPortSampleTime / SetOutputPortSampleTime methods. NOT DONE, and
% deliberately so: making the INPUT port discrete changes when the command
% reaches the plant, which is precisely the mechanism of the actuation-latency
% defect that made the Simulink path disagree with the MATLAB path for the
% project's whole history (see P.plc_io_delay). The risk is not worth 25% on
% a cross-check path. See Project_Notes/NEXT_STEPS.md.
%
% Do NOT assign block.OutputPort(k).SampleTime: it switches the block to
% port-based sample times, after which this line raises
% Simulink:Engine:ChangePortToBlockSampleTimes and the model will not build.
block.SampleTimes   = [0 0];             % continuous
block.NumContStates = P.NS;
block.SimStateCompliance = 'DefaultSimState';

block.RegBlockMethod('InitializeConditions', @InitConditions);
block.RegBlockMethod('Outputs',              @Outputs);
block.RegBlockMethod('Derivatives',          @Derivatives);
end

%% ------------------------------------------------------------------------
function InitConditions(block)
[~, s0] = factory_params_cached();
block.ContStates.Data = s0;
end

%% ------------------------------------------------------------------------
function Outputs(block)
P = factory_params_cached();
s = block.ContStates.Data;
block.OutputPort(1).Data = s;
y = factory_sensors(s, P);
% Order is FACTORY_SENSOR_BUS's, and the assertion below is what keeps it
% that way: a channel added to one and not the other fails here rather than
% silently shifting every index downstream.
v = double([ y.CAM; y.PX(:); y.EXT(:); y.RET(:); ...
             y.HS_TOP; y.HS_BOT; y.P_res; y.P_READY; ...
             y.BR_RDY(:); y.CHG(:); y.ESTOP_OK ]);
B = factory_sensor_bus(P);
if numel(v) ~= B.width
    error('factory_plant_sfun:busWidth', ...
        'Packed %d sensor channels, FACTORY_SENSOR_BUS declares %d.', ...
        numel(v), B.width);
end
block.OutputPort(2).Data = v;
end

%% ------------------------------------------------------------------------
function Derivatives(block)
P  = factory_params_cached();
s  = block.ContStates.Data;
uv = block.InputPort(1).Data;
B  = factory_cmd_bus(P);
u.pump_on = uv(B.pump) > 0.5;
u.dv      = uv(B.dv)';
u.sol     = uv(B.sol)';
u.conv    = uv(B.conv)';
u.base    = uv(B.base);
block.Derivatives.Data = factory_derivatives(s, u, P);
end
