function mdl = build_factory_model(varargin)
%BUILD_FACTORY_MODEL  Construct Factory_Physics_Model.slx programmatically.
%
%   build_factory_model()                       build the default model
%   build_factory_model('Name', value, ...)     options below
%   mdl = build_factory_model(...)              returns the model name
%
%   Options
%     'Model'   model name                        (default 'Factory_Physics_Model')
%     'PLC'     'sfunction' | 'stateflow'         (default 'sfunction')
%     'Scopes'  true/false, add viewer scopes     (default true)
%     'Save'    true/false, save the .slx to disk (default true)
%     'Open'    true/false, open the model window (default true)
%
%   The .slx is BUILT BY THIS SCRIPT rather than shipped as a binary, so the
%   model is diffable, reviewable and reproducible in version control, and
%   regenerating it after a parameter change is one command.
%
%   ARCHITECTURE
%
%     Factory_Physics_Model
%       PLC              controller, 10 ms discrete, 40 states
%       Plant            Level-2 S-function, the validated physics
%       Stop             halts the run when the cycle completes
%       Goto/From tags   PLANT_STATE, SENSORS, CMD, PLC_STATE
%       14 viewer subsystems, one per architecture block, each tapping the
%          relevant bus through a From block and displaying it on a Scope
%       To Workspace     plant_state, sensors, commands, plc_state
%
%   The physics is monolithic inside the plant S-function so that the
%   Simulink model and RUN_FACTORY_SIMULATION execute IDENTICAL equations.
%   Splitting it into Simscape networks is future work.
%
%   ITERATION 03 - WHAT WAS WRONG WITH THE ITERATION 01 BUILDER
%   The previous version of this file had never been executed and could not
%   have worked. Five defects were found by inspection and fixed here:
%     1. It used 'built-in/S-Function', which is the C-MEX block, to host a
%        Level-2 MATLAB S-function. Simulink would have gone looking for a
%        compiled MEX file named factory_plant_sfun.
%     2. It created 14 subsystems each containing an unconnected Inport.
%        An unconnected input port is a hard compile error.
%     3. It used the undocumented 'built-in/Note' block for annotations.
%     4. It built each Stateflow state label with two "en:" blocks, which
%        Stateflow rejects.
%     5. Nothing stopped the run when the cycle finished, so every
%        simulation ran the full stop time regardless.
%
%   See also RUN_SIMULINK_MODEL, FACTORY_PLANT_SFUN, FACTORY_PLC_SFUN.

o = struct('Model','Factory_Physics_Model','PLC','sfunction', ...
           'Scopes',true,'Save',true,'Open',true);
o = parse_options(o, varargin, mfilename);
mdl = o.Model;

P  = factory_params_cached();
ST = factory_states();

%% ---- 1. create the model ----------------------------------------------
if bdIsLoaded(mdl); close_system(mdl, 0); end
% NEW_SYSTEM warns "The model name ... is shadowing another name in the MATLAB
% workspace or path" whenever Factory_Physics_Model.slx already exists on the
% path, which it does because the .slx is committed. The in-memory model
% legitimately shadows the file it is about to overwrite. Verified benign:
% which -all returns exactly one entry and no base-workspace variable shares
% the name. Do not chase this warning.
new_system(mdl);
if o.Open; open_system(mdl); end

set_param(mdl, ...
    'SolverType',        'Fixed-step', ...
    'Solver',            'ode4', ...
    'FixedStep',         num2str(P.dt, '%.10g'), ...
    'StartTime',         '0', ...
    'StopTime',          num2str(P.t_max, '%.10g'), ...
    'SaveOutput',        'on', ...
    'SaveFormat',        'Dataset', ...
    'ReturnWorkspaceOutputs', 'on', ...
    ... % SIMULINK TEST NEEDS THIS. Simulink Test builds its harness by
    ... % referencing this model, and the default 'Multiple' forbids data
    ... % logging in a model that may be instanced more than once. With the 4 To
    ... % Workspace blocks and 14 viewer Scopes present, harness creation failed
    ... % with Simulink:modelReference:MultiInstanceToWksAndScope. 'Single' is
    ... % correct here regardless: this model is a whole cell, never a reusable
    ... % component, so there is no case for instancing it twice.
    'ModelReferenceNumInstancesAllowed', 'Single');

Simulink.Annotation([mdl '/annotation'], ...
    'Text', sprintf(['PHYSICS-BASED FACTORY MODEL  (built by build_factory_model)\n' ...
    'Sequence : Sequence.xlsx, 42 steps, authoritative\n' ...
    'Layout   : function multi_station_simulation().txt\n' ...
    'Hardware : Janatics, PROVISIONAL - see JanaticsData.m\n' ...
    'Solver   : ode4 fixed step %.1e s.  DO NOT RAISE IT - the model\n' ...
    '           diverges to NaN at 1.0e-3 s (verified).\n' ...
    'PLC scan : %.0f ms, output latency %d scan(s)  [P.plc_io_delay]\n' ...
    'Agreement: MATLAB and Simulink agree exactly at plc_io_delay = 0.\n' ...
    '           Verify with COMPARE_EXECUTION_PATHS.\n' ...
    'Parameters: edit FactoryParams.m / JanaticsData.m, then RESET_FACTORY.'], ...
    P.dt, P.t_scan*1000, P.plc_io_delay), 'Position', [30 20 620 150]);

%% ---- 2. plant ----------------------------------------------------------
% 'simulink/User-Defined Functions/Level-2 MATLAB S-Function' is the correct
% block for a .m S-function. 'built-in/S-Function' hosts compiled MEX only.
add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function', ...
    [mdl '/Plant'], 'FunctionName','factory_plant_sfun', ...
    'Position', [430 200 590 300]);

%% ---- 3. controller -----------------------------------------------------
switch lower(o.PLC)
    case 'sfunction'
        add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function', ...
            [mdl '/PLC'], 'FunctionName','factory_plc_sfun', ...
            'Position', [150 200 310 300]);
        plcOutCmd = 'PLC/1'; plcOutState = 'PLC/2'; plcOutDone = 'PLC/3';
    case 'stateflow'
        build_stateflow_plc(mdl, ST, P);
        plcOutCmd = 'PLC/1'; plcOutState = 'PLC/2'; plcOutDone = 'PLC/3';
    otherwise
        error('build_factory_model:PLC', ...
              'PLC must be ''sfunction'' or ''stateflow'', got ''%s''.', o.PLC);
end

%% ---- 4. closed loop, with an external test interface -------------------
% The model is a CLOSED AUTONOMOUS LOOP: the PLC drives the plant and the plant
% feeds the PLC, so until now it had no root Inports at all. That is why
% model_test refused it - a component with no inputs cannot be driven - and why
% Simulink Test harnesses, coverage and Model Advisor had nothing to work with.
%
% The fix is a switchable command source rather than breaking the loop:
%
%   FACTORY_EXT_CMD = 0  (default)  the PLC drives the plant. Identical
%                                   behaviour to before, bit for bit.
%   FACTORY_EXT_CMD = 1             the root Inport drives the plant, so a
%                                   harness can command it directly.
%
% The selector lives in the MODEL WORKSPACE, so the model stays self-contained
% and a plain sim(mdl) still runs the real closed-loop cycle.
mws = get_param(mdl, 'ModelWorkspace');
assignin(mws, 'FACTORY_EXT_CMD', 0);

add_block('built-in/Inport', [mdl '/cmd_ext'], ...
    'PortDimensions', sprintf('%d', factory_cmd_bus(P).width), ...
    'Position',[150 380 180 400]);
add_block('built-in/Constant', [mdl '/ext_select'], ...
    'Value','FACTORY_EXT_CMD', 'Position',[150 430 180 450]);
add_block('built-in/Switch', [mdl '/cmd_source'], ...
    'Criteria','u2 >= Threshold', 'Threshold','0.5', ...
    'Position',[260 370 290 440]);

add_line(mdl, 'cmd_ext/1',    'cmd_source/1', 'autorouting','on');
add_line(mdl, 'ext_select/1', 'cmd_source/2', 'autorouting','on');
add_line(mdl, plcOutCmd,      'cmd_source/3', 'autorouting','on');
add_line(mdl, 'cmd_source/1', 'Plant/1',      'autorouting','on');
add_line(mdl, 'Plant/2', 'PLC/1', 'autorouting','on');     % sensors -> PLC

%% ---- 5. stop on cycle completion --------------------------------------
% Without this the run always lasts the full stop time. The plant carries no
% "finished" concept; the controller does, so the controller stops the run.
add_block('built-in/Stop', [mdl '/Stop'], 'Position',[700 470 730 500]);
add_line(mdl, plcOutDone, 'Stop/1', 'autorouting','on');

%% ---- 6. signal distribution -------------------------------------------
% CMD taps the SWITCH OUTPUT, not the PLC output. It has to be what actually
% reaches the plant: SIMOUT_TO_LOG re-evaluates FACTORY_DERIVATIVES from this
% signal to reconstruct the forces, so logging the PLC's request instead would
% silently produce wrong forces whenever the external source is selected.
tags = { 'PLANT_STATE', 'Plant/1',      [650 200 690 220]
         'SENSORS',     'Plant/2',      [650 260 690 280]
         'CMD',         'cmd_source/1', [340 200 380 220]
         'PLC_STATE',   plcOutState,    [340 260 380 280] };
for i = 1:size(tags,1)
    gp = [mdl '/Goto_' tags{i,1}];
    add_block('built-in/Goto', gp, 'GotoTag', tags{i,1}, ...
              'TagVisibility','global', 'Position', tags{i,3});
    add_line(mdl, tags{i,2}, ['Goto_' tags{i,1} '/1'], 'autorouting','on');
end

%% ---- 7. logging --------------------------------------------------------
logs = { 'plant_state','PLANT_STATE',[880 180 950 210]
         'sensors',    'SENSORS',    [880 240 950 270]
         'commands',   'CMD',        [880 300 950 330]
         'plc_state',  'PLC_STATE',  [880 360 950 390] };
for i = 1:size(logs,1)
    fp = [mdl '/From_log_' logs{i,1}];
    tp = [mdl '/log_' logs{i,1}];
    add_block('built-in/From', fp, 'GotoTag', logs{i,2}, ...
              'Position', [790 logs{i,3}(2) 850 logs{i,3}(4)]);
    add_block('built-in/ToWorkspace', tp, ...
              'VariableName', logs{i,1}, 'SaveFormat','StructureWithTime', ...
              'MaxDataPoints','inf', 'Decimation','20', ...
              'Position', logs{i,3});
    add_line(mdl, ['From_log_' logs{i,1} '/1'], ['log_' logs{i,1} '/1'], ...
             'autorouting','on');
end

%% ---- 7b. root outputs, so a test harness can observe -------------------
% Without these the model publishes nothing a harness can assert on. To
% Workspace blocks are fine for a person reading results afterwards; a harness
% needs real Outports.
outs = { 'plant_state_out', 'Plant/1',      [880 430 910 450]
         'sensors_out',     'Plant/2',      [880 470 910 490]
         'plc_state_out',   plcOutState,    [880 510 910 530]
         'cmd_out',         'cmd_source/1', [880 550 910 570] };
for i = 1:size(outs,1)
    add_block('built-in/Outport', [mdl '/' outs{i,1}], 'Position', outs{i,3});
    add_line(mdl, outs{i,2}, [outs{i,1} '/1'], 'autorouting','on');
end

%% ---- 8. architecture viewer subsystems --------------------------------
% One subsystem per architecture block named in the project. Each taps the
% relevant bus with a From block. With 'Scopes',true the tap ends in a Scope
% you can open during the run; with false it ends in a Terminator, which
% costs nothing. Either way every port inside is connected, which is what
% the Iteration 01 builder got wrong.
views = { 'Camera_Detection',    'SENSORS',     'CAM = index 1'
          'Sensor_System',       'SENSORS',     busNote(P, {'PX','EXT','RET','HS_TOP','HS_BOT'})
          'Pneumatic_System',    'PLANT_STATE', ixNote(P, {'P_res','P_br'})
          'Distribution_Valve',  'PLANT_STATE', ixNote(P, {'dv'})
          'Feeder_Valve_System', 'PLANT_STATE', ixNote(P, {'sp'})
          'Actuator_Systems',    'PLANT_STATE', ixNote(P, {'PA','PB','x','v'})
          'Conveyor_Systems',    'PLANT_STATE', ixNote(P, {'om','ei','vref'})
          'Workpiece_Dynamics',  'PLANT_STATE', ixNote(P, {'bx','by','bvx','bvy'})
          'Engraving_Base',      'PLANT_STATE', ixNote(P, {'bz','bvz','bei'})
          'Laser_Engraving',     'PLC_STATE',   'states 25..29 are the engraving process'
          'Operator_Interface',  'PLC_STATE',   'states 25,26,27 - PLACEHOLDER timings'
          'Interlocks',          'SENSORS',     busNote(P, {'P_READY','BR_RDY','CHG'})
          'Fault_System',        'PLANT_STATE', 'switches live in P.fault, not in the diagram'
          'Visualization',       'PLANT_STATE', 'use visualize_factory(LOG) from MATLAB' };
for i = 1:size(views,1)
    nm = views{i,1};
    sp = [mdl '/' nm];
    y0 = 60 + (i-1)*60;
    add_block('built-in/Subsystem', sp, 'Position',[1050 y0 1210 y0+40]);
    delete_line_if_any(sp);
    add_block('built-in/From', [sp '/tap'], 'GotoTag', views{i,2}, ...
              'Position',[40 40 100 60]);
    if o.Scopes
        add_block('built-in/Scope', [sp '/view'], 'Position',[200 30 240 70]);
    else
        add_block('built-in/Terminator', [sp '/view'], 'Position',[200 40 220 60]);
    end
    add_line(sp, 'tap/1', 'view/1');
    Simulink.Annotation([sp '/note'], 'Text', views{i,3}, ...
                        'Position',[40 100 400 130]);
end

%% ---- 9. arrange, save --------------------------------------------------
try
    Simulink.BlockDiagram.arrangeSystem(mdl);
catch ME
    warning('build_factory_model:arrange', ...
        'arrangeSystem failed (%s). Layout will be untidy but the model is valid.', ...
        ME.identifier);
end
if o.Save
    save_system(mdl);
    fprintf('Built %s.slx  (PLC = %s, %d states, %d plant states)\n', ...
            mdl, o.PLC, size(ST,1), P.NS);
    fprintf('Run it with:  run_simulink_model\n');
end
end

%% ========================================================================
function delete_line_if_any(sp)
%DELETE_LINE_IF_ANY  Empty a freshly added Subsystem.
%   add_block('built-in/Subsystem', ...) creates In1 -> Out1 already wired.
%   Those ports would be unconnected at the parent level, which is the exact
%   error the Iteration 01 builder produced, so they are removed.
try
    lines = find_system(sp, 'SearchDepth',1, 'FindAll','on', 'Type','line');
    for i = 1:numel(lines); delete_line(lines(i)); end
catch
    % nothing to delete
end
for b = {'In1','Out1'}
    p = [sp '/' b{1}];
    if getSimulinkBlockHandle(p) > 0; delete_block(p); end
end
end

%% ========================================================================
function build_stateflow_plc(mdl, ST, P)
%BUILD_STATEFLOW_PLC  Stateflow variant of the controller.
%
%   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
%   %  BUILDS AND RUNS.  CORRECTNESS NOT VERIFIED.                        %
%   %                                                                     %
%   %  Executed for the first time on 2026-08-24, once Stateflow was       %
%   %  installed: it builds a chart, compiles, and simulates.             %
%   %                                                                     %
%   %  That is RUNNING, not CORRECT. Nothing yet checks that the chart     %
%   %  walks the same 40 states as FACTORY_PLC, so do not describe it as   %
%   %  validated. The default 'sfunction' PLC remains the validated path;  %
%   %  it executes FACTORY_PLC itself, byte for byte.                     %
%   %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
if isempty(ver('stateflow'))
    error('build_factory_model:noStateflow', ...
        ['Stateflow is not installed. Use the default PLC:\n' ...
         '    build_factory_model(''PLC'',''sfunction'')']);
end
nS = size(ST,1);
chartPath = [mdl '/PLC'];
add_block('sflib/Chart', chartPath, 'Position', [150 200 310 340]);

rt    = sfroot;
chart = rt.find('-isa','Stateflow.Chart','Path',chartPath);
chart.ActionLanguage          = 'MATLAB';
chart.ChartUpdate             = 'DISCRETE';
chart.SampleTime              = num2str(P.t_scan, '%.10g');
chart.ExecuteAtInitialization = true;

addData(chart, 'sens', 'Input',  sprintf('%d', factory_sensor_bus(P).width));
addData(chart, 'cmd',  'Output', sprintf('%d', factory_cmd_bus(P).width));
addData(chart, 'step', 'Output', '1');
addData(chart, 'done', 'Output', '1');
for pn = {'t_op_notice','t_engrave','t_op_confirm'}
    addData(chart, pn{1}, 'Parameter', '1');
end

sfS = cell(nS,1);
for i = 1:nS
    st = Stateflow.State(chart);
    st.Name        = ST{i,1};
    st.Position    = [40, 40 + (i-1)*70, 260, 50];
    % ONE entry-action block per state. The Iteration 01 builder emitted two
    % "en:" blocks per label, which Stateflow rejects.
    ea = entryActionFor(i, P);
    if isempty(ea)
        st.LabelString = ST{i,1};
    else
        st.LabelString = sprintf('%s\nen:%s', ST{i,1}, ea);
    end
    st.Description = sprintf('Sequence.xlsx step %s', ST{i,2});
    sfS{i} = st;
end

dt0 = Stateflow.Transition(chart);
dt0.Destination       = sfS{1};
dt0.DestinationOClock = 0;
dt0.SourceEndPoint    = [160, 10];

for i = 1:nS-1
    tr = Stateflow.Transition(chart);
    tr.Source            = sfS{i};
    tr.Destination       = sfS{i+1};
    tr.SourceOClock      = 6;
    tr.DestinationOClock = 0;
    tr.LabelString       = guardFor(i, P);
end

for fn = {'t_op_notice','t_engrave','t_op_confirm'}
    assignin('base', fn{1}, P.(fn{1}));
end
end

%% ========================================================================
function d = addData(chart, name, scope, sz)
d = Stateflow.Data(chart);
d.Name  = name;
d.Scope = scope;
if ~strcmp(sz,'1'); d.Props.Array.Size = sz; end
end

%% ========================================================================
function a = entryActionFor(i, P)
%ENTRYACTIONFOR  Entry action mirroring FACTORY_PLC case i.
%   cmd = [pump; dv(1:4); sol(1:NSOL); conv(1:NCONV); base]
%
%   Every index is generated from FACTORY_CMD_BUS and FACTORY_ACTUATORS, for
%   exactly the reason GUARDFOR generates its sensor indices: these are
%   literals inside GENERATED STRINGS. On 2026-09-02 the command vector went
%   from 14 wide to 22 and the station valves stopped being one coil per
%   actuator. A stale literal here still compiles and still simulates - it
%   just energises the wrong coil.
%
%   The actuator is named by ROLE, never by number, so that re-ordering
%   FACTORY_ACTUATORS cannot silently drive a different barrel.
if nargin < 2 || isempty(P); P = factory_params_cached(); end
B = factory_cmd_bus(P);
    function s = act(role, want)
        % Extend (want = 1) or retract (want = 0), honouring the valve type:
        % a double-solenoid gets one coil energised and the other dropped.
        C = P.CYL(P.ACT.(role));
        if C.dbl
            s = sprintf(' cmd(%d) = %d; cmd(%d) = %d;', ...
                        B.sol(C.coil_ext), want, B.sol(C.coil_ret), 1 - want);
        else
            s = sprintf(' cmd(%d) = %d;', B.sol(C.coil_ext), want);
        end
    end
    function s = dvsel(k)
        v = zeros(1,4); v(k) = 1;
        s = sprintf(' cmd(%d:%d) = [%d;%d;%d;%d];', B.dv(1), B.dv(end), v);
    end
    function s = cvcmd(k, on)
        s = sprintf(' cmd(%d) = %d;', B.conv(k), on);
    end
switch i
    case 1,  a = sprintf(' cmd = zeros(%d,1); step = 0; done = 0;', B.width);
    case 3,  a = sprintf(' cmd(%d) = 1; step = 2;', B.pump);
    case 6,  a = [dvsel(1)          ' step = 5;'];
    case 7,  a = [act('feed',    1) ' step = 7;'];
    case 9,  a =  act('feed',    0);
    case 10, a = [cvcmd(1, 1)       ' step = 10;'];
    case 12, a = [cvcmd(1, 0)       ' step = 12;'];
    case 13, a = [dvsel(1)          ' step = 13;'];
    case 14, a = [act('xfer1',   1) ' step = 15;'];
    case 15, a =  act('xfer1',   0);
    case 16, a = [cvcmd(2, 1)       ' step = 17;'];
    case 18, a = [cvcmd(2, 0)       ' step = 19;'];
    case 19, a = [dvsel(2)          ' step = 20;'];
    case 20, a = [act('eng_in',  1) ' step = 22;'];
    case 22, a =  act('eng_in',  0);
    case 23, a = sprintf(' cmd(%d) = 1; step = 25;', B.base);
    case 28, a = sprintf(' cmd(%d) = 0;', B.base);
    case 30, a = [dvsel(3)          ' step = 31;'];
    case 31, a = [act('eng_out', 1) ' step = 33;'];
    case 33, a =  act('eng_out', 0);
    case 34, a = [cvcmd(3, 1)       ' step = 36;'];
    case 36, a = [cvcmd(3, 0)       ' step = 38;'];
    case 37, a = [dvsel(4)          ' step = 39;'];
    case 38, a = [act('eject',   1) ' step = 41;'];
    case 39, a =  act('eject',   0);
    case 40, a = ' done = 1;';
    otherwise, a = '';
end
end

%% ========================================================================
function g = guardFor(i, P)
%GUARDFOR  Transition guard from state i to state i+1.
%
%   Indices come from FACTORY_SENSOR_BUS, never from literals. They used to be
%   written out by hand here - 27 of them, inside generated strings, correct
%   only while no channel width ever changed. When the proximity sensors went
%   from the model's 4 to the machine's 10 on 2026-09-02, every channel after
%   them shifted by six. A wrong index inside a generated string still
%   compiles; it just guards on the wrong sensor in one branch.
if nargin < 2 || isempty(P); P = factory_params_cached(); end
B = factory_sensor_bus(P);
    function s = ch(field, k)          % one channel, as a guard fragment
        idx = B.(field);
        s = sprintf('sens(%d) > 0.5', idx(k));
    end
    function s = both(f1, k1, f2, k2)  % two channels, ANDed
        s = sprintf('%s && %s', ch(f1, k1), ch(f2, k2));
    end
G = P.PROX_GUARD;                      % which PX each check watches
% EXT, RET and CHG are indexed by ACTUATOR, and that numbering is now the
% machine's eleven rather than the model's old five - so actuator 2 is the
% second magazine pusher, not the conveyor 1 to 2 transfer it used to be.
% Name the actuator by role, never by number.
A = P.ACT;
switch i
    case 2,  g = ['[' ch('CAM',1)                    ']'];
    case 4,  g = ['[' ch('P_READY',1)                ']'];
    case 6,  g = ['[' both('BR_RDY',1,'CHG',A.feed)    ']'];
    case 7,  g = ['[' ch('EXT',A.feed)                 ']'];
    case 8,  g = ['[' ch('PX',G(1))                  ']'];
    case 9,  g = ['[' ch('RET',A.feed)                 ']'];
    case 11, g = ['[' ch('PX',G(2))                  ']'];
    case 13, g = ['[' both('BR_RDY',1,'CHG',A.xfer1)   ']'];
    case 14, g = ['[' ch('EXT',A.xfer1)                ']'];
    case 15, g = ['[' ch('RET',A.xfer1)                ']'];
    case 17, g = ['[' ch('PX',G(3))                  ']'];
    case 19, g = ['[' both('BR_RDY',2,'CHG',A.eng_in)  ']'];
    case 20, g = ['[' ch('EXT',A.eng_in)               ']'];
    case 22, g = ['[' ch('RET',A.eng_in)               ']'];
    case 24, g = ['[' ch('HS_TOP',1)                 ']'];
    case 25, g = '[after(t_op_notice,  sec)]';            % PLACEHOLDER
    case 26, g = '[after(t_engrave,    sec)]';            % PLACEHOLDER
    case 27, g = '[after(t_op_confirm, sec)]';            % PLACEHOLDER
    case 29, g = ['[' ch('HS_BOT',1)                 ']'];
    case 30, g = ['[' both('BR_RDY',3,'CHG',A.eng_out) ']'];
    case 31, g = ['[' ch('EXT',A.eng_out)              ']'];
    case 33, g = ['[' ch('RET',A.eng_out)              ']'];
    case 35, g = ['[' ch('PX',G(4))                  ']'];
    case 37, g = ['[' both('BR_RDY',4,'CHG',A.eject)   ']'];
    case 38, g = ['[' ch('EXT',A.eject)                ']'];
    case 39, g = ['[' ch('RET',A.eject)                ']'];
    otherwise, g = '';                                    % immediate
end
end

%% ========================================================================
function s = ixNote(P, fields)
%IXNOTE  Render part of the state-vector index map for a diagram annotation.
%   Same argument as BUSNOTE. These annotations used to state their ranges as
%   text - 'PA 10:14, PB 15:19' - and went silently wrong the moment P.NS
%   changed, which it did on 2026-09-02 when the plant went from 51 states to
%   81. A wrong annotation is worse than none: it is read as documentation.
parts = cell(1, numel(fields));
for i = 1:numel(fields)
    r = P.IX.(fields{i});
    if isscalar(r)
        parts{i} = sprintf('%s %d', fields{i}, r);
    else
        parts{i} = sprintf('%s %d:%d', fields{i}, r(1), r(end));
    end
end
s = strjoin(parts, ', ');
end

%% ========================================================================
function s = busNote(P, fields)
%BUSNOTE  Render part of the sensor bus layout for a diagram annotation.
%   The annotations used to state the ranges as text and drifted from the
%   code the moment a width changed. Now they are generated.
B = factory_sensor_bus(P);
parts = cell(1, numel(fields));
for i = 1:numel(fields)
    r = B.(fields{i});
    if isscalar(r)
        parts{i} = sprintf('%s %d', fields{i}, r);
    else
        parts{i} = sprintf('%s %d:%d', fields{i}, r(1), r(end));
    end
end
s = strjoin(parts, ', ');
end
