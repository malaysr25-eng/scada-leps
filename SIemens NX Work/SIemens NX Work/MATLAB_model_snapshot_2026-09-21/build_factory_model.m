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
%   ARCHITECTURE  (as drawn since 2026-09-14)
%
%   The top level is a TOP VIEW OF THE CELL, drawn with DRAW_CELL_LAYOUT's
%   geometry: belts 1-3, the engraver, the bin, the camera and every placed
%   actuator, each where it stands, inside the three station areas. Those
%   blocks are DISPLAY ONLY - each taps a global tag into a Terminator and
%   computes nothing. Beside the cell, the ENGINE panel computes all of it:
%
%       PLC              controller, 10 ms discrete, 44 states (40 engraved + 4 bypass)
%       Plant            Level-2 S-function, the validated physics
%       cmd_source       the PLC or the root Inport drives the plant (FACTORY_EXT_CMD)
%       Stop             halts the run when the cycle completes
%       Goto tags        PLANT_STATE, SENSORS, CMD, PLC_STATE (global)
%       4 Outports       for a test harness to observe
%       Logging          subsystem: From -> To Workspace for plant_state,
%                        sensors, commands and plc_state
%       Views            subsystem: 14 viewers, one per architecture block,
%                        each tapping its bus through a From block into a Scope
%
%   The physics stays in ONE block so that this model and
%   RUN_FACTORY_SIMULATION execute identical equations; the cell drawing
%   around it changes nothing the model computes. Until 2026-09-14 the top
%   level was ~40 blocks that arrangeSystem stacked into one column.
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
    P.dt, P.t_scan*1000, P.plc_io_delay), 'Position', [1120 690 1880 830]);

%% ---- 2. the cell, seen from above --------------------------------------
% The same geometry as DRAW_CELL_LAYOUT and VISUALIZE_FACTORY, so the diagram
% looks like the machine: blue belts, the orange engraver, the grey bin, every
% placed actuator at its own rod tip. One metre of cell is 600 canvas pixels;
% the cell's y axis points up and the canvas's points down. Everything drawn
% here is DISPLAY ONLY (see STATIONBLOCK).
S  = P.SCALE;
cm = @(x, y, w, h) round([60 + 600*x, 60 + 600*(1.3 - y - h), ...
                          60 + 600*(x + w), 60 + 600*(1.3 - y)]);   % m -> [l t r b]
du = @(v) cm(v(1)*S, v(2)*S, v(3)*S, v(4)*S);                     % drawing units -> [l t r b]

areaBlock(mdl, 'STATION 1 - feed',      du([-0.8 8.2 10 3.8]));
areaBlock(mdl, 'STATION 2 - engraving', du([5 1.5 4 6.5]));
areaBlock(mdl, 'STATION 3 - outfeed',   du([9.2 1.5 7.2 8.5]));

belt = '[0.20 0.40 0.70]';
stationBlock(mdl, 'Belt_1', du([1 8.5 7.6 1.35]), belt, 'BELT 1   > > >', 'PLANT_STATE', ...
    'Conveyor 1. Its drive states (om, ei, vref) are in PLANT_STATE; open Views for scopes.');
stationBlock(mdl, 'Belt_2', du([7.25 0.9 1.35 7.6]), belt, 'BELT 2\nv\nv\nv', 'PLANT_STATE', ...
    'Conveyor 2, into the engraver. Drive states in PLANT_STATE.');
stationBlock(mdl, 'Belt_3', du([8.6 3.19 7.6 1.35]), belt, 'BELT 3   > > >', 'PLANT_STATE', ...
    'Conveyor 3, to the outfeed. Drive states in PLANT_STATE.');
stationBlock(mdl, 'Laser_Engraver', du([8.6 4.6 3.7 1.8]), '[0.95 0.45 0.10]', ...
    'DAJA LASER ENGRAVER\nplatform up / down', 'PLC_STATE', ...
    'Platform up (S23), laser and ENG DONE (S24-S26), platform down (S27-S28).');
stationBlock(mdl, 'Bin', du([12.7 1.0 3.2 2.19]), '[0.30 0.30 0.33]', 'BIN', 'SENSORS', ...
    'Collection bin, fed by both outfeed pushers.');
stationBlock(mdl, 'Camera', cm(P.CAM(1) - 0.025, P.CAM(2) - 0.025, 0.05, 0.05), ...
    '[0.40 0.90 1.00]', 'CAM', 'SENSORS', 'The camera that detects the part (CAM, sensor index 1).');

% Every PLACED actuator, generated from P.CYL exactly as DRAW_CELL_LAYOUT draws
% it: the body behind its retracted rod tip, on its own axis. A non-contact one
% (CYL_B) is offset one body width, as there, so bodies do not coincide.
bl = 0.12; bw = 0.08;
for c = 1:P.NCYL
    C = P.CYL(c);
    if ~C.placed; continue; end
    dg = (C.placed && ~C.contact) * 1.4 * bw;
    if C.axis == 'x'
        pos = cm(min(C.tip0, C.tip0 - C.dir*bl), C.lat - bw/2 + dg, bl, bw);
    else
        pos = cm(C.lat - bw/2 + dg, min(C.tip0, C.tip0 - C.dir*bl), bw, bl);
    end
    if C.dbl
        lab = sprintf('%s\\n[%d/%d]', C.short, C.coil_ext, C.coil_ret);
    else
        lab = sprintf('%s\\n[%d]', C.short, C.coil_ext);
    end
    stationBlock(mdl, ['Act_' C.name], pos, '[0.60 0.60 0.75]', lab, 'PLANT_STATE', ...
        sprintf('%s: bore %g mm, stroke %g mm. Rod and chambers (x, v, PA, PB) are in PLANT_STATE.', ...
                C.name, 1000*C.bore, 1000*C.stroke));
end

%% ---- 3. the engine: plant and controller -----------------------------
% 'simulink/User-Defined Functions/Level-2 MATLAB S-Function' is the correct
% block for a .m S-function. 'built-in/S-Function' hosts compiled MEX only.
ex = 1120;                                   % the engine panel's left edge
areaBlock(mdl, 'ENGINE - the PLC and the physics compute the whole cell', [ex 90 ex+780 670]);
add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function', ...
    [mdl '/Plant'], 'FunctionName','factory_plant_sfun', ...
    'Position', [ex+440 300 ex+640 460], 'BackgroundColor', 'orange');
labelBlock([mdl '/Plant'], 'PLANT', 'factory_plant_sfun - physics, RK4', ...
    {'cmd'}, {'plant state', 'sensors'});
set_param([mdl '/Plant'], 'ShowName', 'off');

switch lower(o.PLC)
    case 'sfunction'
        add_block('simulink/User-Defined Functions/Level-2 MATLAB S-Function', ...
            [mdl '/PLC'], 'FunctionName','factory_plc_sfun', ...
            'Position', [ex+30 300 ex+230 460], 'BackgroundColor', 'lightBlue');
        labelBlock([mdl '/PLC'], 'PLC', 'factory_plc_sfun - 10 ms scan', ...
            {'sensors'}, {'cmd', 'state', 'done'});
        set_param([mdl '/PLC'], 'ShowName', 'off');
        plcOutCmd = 'PLC/1'; plcOutState = 'PLC/2'; plcOutDone = 'PLC/3';
    case 'stateflow'
        build_stateflow_plc(mdl, ST, P);
        set_param([mdl '/PLC'], 'Position', [ex+30 300 ex+230 460], ...
                  'BackgroundColor', 'lightBlue');
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
    'Position',[ex+270 180 ex+300 200]);
add_block('built-in/Constant', [mdl '/ext_select'], ...
    'Value','FACTORY_EXT_CMD', 'Position',[ex+270 220 ex+300 240]);
add_block('built-in/Switch', [mdl '/cmd_source'], ...
    'Criteria','u2 >= Threshold', 'Threshold','0.5', ...
    'Position',[ex+350 180 ex+380 330]);

add_line(mdl, 'cmd_ext/1',    'cmd_source/1', 'autorouting','on');
add_line(mdl, 'ext_select/1', 'cmd_source/2', 'autorouting','on');
nameLine(add_line(mdl, plcOutCmd,      'cmd_source/3', 'autorouting','on'), 'plc cmd');
nameLine(add_line(mdl, 'cmd_source/1', 'Plant/1',      'autorouting','on'), 'cmd');
% The feedback wire runs UNDER both blocks. Autorouting took the shortest
% path, straight through the PLC.
nameLine(loopLine(mdl, 'Plant', 2, 'PLC', 1, 478), 'sensors');  % sensors -> PLC

%% ---- 5. stop on cycle completion --------------------------------------
% Without this the run always lasts the full stop time. The plant carries no
% "finished" concept; the controller does, so the controller stops the run.
add_block('built-in/Stop', [mdl '/Stop'], 'Position',[ex+280 590 ex+310 620]);
add_line(mdl, plcOutDone, 'Stop/1', 'autorouting','on');

%% ---- 6. signal distribution -------------------------------------------
% CMD taps the SWITCH OUTPUT, not the PLC output. It has to be what actually
% reaches the plant: SIMOUT_TO_LOG re-evaluates FACTORY_DERIVATIVES from this
% signal to reconstruct the forces, so logging the PLC's request instead would
% silently produce wrong forces whenever the external source is selected.
tags = { 'PLANT_STATE', 'Plant/1',      [ex+680 310 ex+750 330]
         'SENSORS',     'Plant/2',      [ex+680 430 ex+750 450]
         'CMD',         'cmd_source/1', [ex+420 120 ex+490 140]
         'PLC_STATE',   plcOutState,    [ex+270 490 ex+340 510] };
for i = 1:size(tags,1)
    gp = [mdl '/Goto_' tags{i,1}];
    add_block('built-in/Goto', gp, 'GotoTag', tags{i,1}, ...
              'TagVisibility','global', 'Position', tags{i,3});
    add_line(mdl, tags{i,2}, ['Goto_' tags{i,1} '/1'], 'autorouting','on');
end

%% ---- 7. logging --------------------------------------------------------
% In a subsystem of its own. The tags are global, so the From blocks reach them
% from here, and a To Workspace block logs from any level: RUN_SIMULINK_MODEL
% reads the same plant_state, sensors, commands and plc_state as before.
lg = [mdl '/Logging'];
add_block('built-in/Subsystem', lg, 'Position', [ex+440 570 ex+580 630], ...
          'BackgroundColor', 'gray');
delete_line_if_any(lg);
logs = { 'plant_state','PLANT_STATE'
         'sensors',    'SENSORS'
         'commands',   'CMD'
         'plc_state',  'PLC_STATE' };
for i = 1:size(logs,1)
    y  = 40 + (i-1)*60;
    fp = [lg '/From_log_' logs{i,1}];
    tp = [lg '/log_' logs{i,1}];
    add_block('built-in/From', fp, 'GotoTag', logs{i,2}, ...
              'Position', [40 y 130 y+30]);
    add_block('built-in/ToWorkspace', tp, ...
              'VariableName', logs{i,1}, 'SaveFormat','StructureWithTime', ...
              'MaxDataPoints','inf', 'Decimation','20', ...
              'Position', [200 y 300 y+30]);
    add_line(lg, ['From_log_' logs{i,1} '/1'], ['log_' logs{i,1} '/1'], ...
             'autorouting','on');
end

%% ---- 7b. root outputs, so a test harness can observe -------------------
% Without these the model publishes nothing a harness can assert on. To
% Workspace blocks are fine for a person reading results afterwards; a harness
% needs real Outports. Each sits beside its own source; the order - and so the
% port numbers 1-4 a harness sees - is unchanged.
outs = { 'plant_state_out', 'Plant/1',      [ex+680 355 ex+710 375]
         'sensors_out',     'Plant/2',      [ex+680 395 ex+710 415]
         'plc_state_out',   plcOutState,    [ex+270 540 ex+300 560]
         'cmd_out',         'cmd_source/1', [ex+420 160 ex+450 180] };
for i = 1:size(outs,1)
    add_block('built-in/Outport', [mdl '/' outs{i,1}], 'Position', outs{i,3});
    add_line(mdl, outs{i,2}, [outs{i,1} '/1'], 'autorouting','on');
end

%% ---- 8. architecture viewer subsystems --------------------------------
% One subsystem per architecture block named in the project, all inside Views.
% Each taps the relevant bus with a From block. With 'Scopes',true the tap ends
% in a Scope you can open during the run; with false it ends in a Terminator,
% which costs nothing. Either way every port inside is connected, which is
% what the Iteration 01 builder got wrong.
vw = [mdl '/Views'];
add_block('built-in/Subsystem', vw, 'Position', [ex+620 570 ex+760 630], ...
          'BackgroundColor', 'gray');
delete_line_if_any(vw);
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
    nm  = views{i,1};
    sp  = [vw '/' nm];
    col = floor((i-1)/7); row = mod(i-1, 7);
    xv  = 40 + col*260;   yv = 40 + row*70;
    add_block('built-in/Subsystem', sp, 'Position',[xv yv xv+180 yv+40]);
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

%% ---- 9. fit, save ------------------------------------------------------
set_param(mdl, 'ZoomFactor', 'FitSystem');   % open showing the whole cell
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
%   %  BUILDS, RUNS, AND IS *NOT* EQUIVALENT TO FACTORY_PLC.              %
%   %                                                                     %
%   %  Checked for the first time on 2026-09-02. It was previously         %
%   %  described as "correctness not verified"; it is now verified, and    %
%   %  the answer is no.                                                   %
%   %                                                                     %
%   %      S-function path, as measured   63.160 s                         %
%   %      this chart                    62.900 s                          %
%   %      difference                     0.260 s = EXACTLY 26 x t_scan    %
%   %                                                                     %
%   %  Re-measured 2026-09-07 with CYL_A's real bore. It read 31.080 /     %
%   %  30.700 / 38 scans before. The lead stayed a WHOLE number of scans   %
%   %  and changed SIZE, which is new: it depends on the plant, so it is   %
%   %  not a fixed start-up cost, and 49 > the 39 transitions in a cycle,  %
%   %  so it is not one scan per state either. STATEFLOWSEQUENCETEST.      %
%   %                                                                     %
%   %  Quantised to the PLC clock, which integration error cannot be, so   %
%   %  the cause is scheduling or chart semantics. Two hypotheses are      %
%   %  already ruled out by measurement - see STATEFLOWSEQUENCETEST, which %
%   %  pins the divergence so it cannot drift silently.                    %
%   %                                                                     %
%   %  The default 'sfunction' PLC remains THE validated path; it executes %
%   %  FACTORY_PLC itself, byte for byte. Do not use this chart for        %
%   %  results.                                                            %
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
% The three operator placeholders, plus the four MEASURED sequencer dwells
% added 2026-09-08. The chart must carry them or it silently runs a different
% sequence from FACTORY_PLC - which is exactly what happened when they were
% added to the sequencer alone: the chart came out 13.98 s short, and the
% divergence this file's own characterisation test records stopped being the
% scan-quantised scheduling effect and became a missing-logic bug.
for pn = {'t_op_notice','t_engrave','t_op_confirm', ...
          't_cylA_hold','t_cylB_hold','t_outfeed_pulse','t_xfer1_dwell', ...
          't_dispense_ton','t_valve_pulse','t_start_delay','t_cylA_wait','engrave_selected'}
    addData(chart, pn{1}, 'Parameter', '1');
end

% The engraved route is one column, S00 to S39. The bypass states S40-S43 stand
% in a second column beside S16, where they branch off.
iEnd  = find(strcmp(ST(:,1), 'S39_CYCLE_COMPLETE'));
iFork = find(strcmp(ST(:,1), 'S16_PROX3_CHECK'));
sfS = cell(nS,1);
for i = 1:nS
    st = Stateflow.State(chart);
    st.Name        = ST{i,1};
    if i <= iEnd
        st.Position = [40, 40 + (i-1)*70, 260, 50];
    else
        st.Position = [360, 40 + (iFork + i - iEnd - 1)*70, 260, 50];
    end
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

for i = 1:iEnd-1
    tr = Stateflow.Transition(chart);
    tr.Source            = sfS{i};
    tr.Destination       = sfS{i+1};
    tr.SourceOClock      = 6;
    tr.DestinationOClock = 0;
    tr.LabelString       = guardFor(i, P);
end

% The bypass branch. Its guards are generated by BYPASSEDGES for the reason
% GUARDFOR's are: an index inside a generated string must itself be generated.
E = bypassEdges(P, ST);
for k = 1:size(E,1)
    tr = Stateflow.Transition(chart);
    tr.Source            = sfS{E{k,1}};
    tr.Destination       = sfS{E{k,2}};
    tr.SourceOClock      = E{k,4};
    tr.DestinationOClock = E{k,5};
    tr.LabelString       = E{k,3};
end

for fn = {'t_op_notice','t_engrave','t_op_confirm'}
    assignin('base', fn{1}, P.(fn{1}));
end
for fn = {'t_cylA_hold','t_cylB_hold','t_outfeed_pulse','t_xfer1_dwell', ...
          't_dispense_ton','t_valve_pulse','t_start_delay','t_cylA_wait'}
    assignin('base', fn{1}, P.PLC.(fn{1}));
end
assignin('base', 'engrave_selected', double(P.engrave_selected));
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
    case 14, a = [act('xfer1',   1) cvcmd(2, 1) ' step = 15;'];   % H5: belt 2 with the push
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
    case 33, a = [act('eng_out', 0) cvcmd(3, 1)];   % H5: belt 3 as B releases
    case 34, a = [cvcmd(3, 1)       ' step = 36;'];
    case 36, a = [cvcmd(3, 0)       ' step = 38;'];
    case 37, a = [dvsel(4)          ' step = 39;'];
    case 38, a = [act('eject',   1) ' step = 41;'];
    case 39, a =  act('eject',   0);
    case 40, a = ' done = 1;';
    % the bypass route, S40-S43 - FACTORY_PLC cases 41-44. The historical
    % five-actuator plant has no bypass barrel, and never takes this route.
    case 41, a = [cvcmd(2, 0) cvcmd(3, 1)];
    case 42, a =  dvsel(3);
    case 43, if isempty(P.ACT.bypass); a = ''; else; a = act('bypass', 1); end
    case 44, if isempty(P.ACT.bypass); a = ''; else; a = act('bypass', 0); end
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
    case 4,  g = ['[' ch('P_READY',1) ' && after(t_start_delay, sec)' ']'];
    case 6,  g = ['[' both('BR_RDY',1,'CHG',A.feed)    ']'];
    case 7,  g = ['[' ch('EXT',A.feed)                 ']'];
    case 8,  g = ['[' ch('PX',G(1)) ' && after(t_dispense_ton, sec)' ']'];
    case 9,  g = ['[' ch('RET',A.feed)                 ']'];
    case 11, g = ['[' ch('PX',G(2))                  ']'];
    case 13, g = ['[' both('BR_RDY',1,'CHG',A.xfer1) ' && after(t_xfer1_dwell, sec)' ']'];
    case 14, g = ['[' ch('EXT',A.xfer1)                ']'];
    case 15, g = ['[' ch('RET',A.xfer1)                ']'];
    case 17, g = ['[' ch('PX',G(3)) ' && engrave_selected > 0.5' ']'];
    case 19, g = ['[' both('BR_RDY',2,'CHG',A.eng_in) ' && after(t_cylA_wait, sec)' ']'];
    case 20, g = ['[' ch('EXT',A.eng_in) ' && after(t_cylA_hold, sec)' ']'];
    case 22, g = ['[' ch('RET',A.eng_in)               ']'];
    case 24, g = ['[' ch('HS_TOP',1)                 ']'];
    case 25, g = '[after(t_op_notice,  sec)]';            % PLACEHOLDER
    case 26, g = '[after(t_engrave,    sec)]';            % PLACEHOLDER
    case 27, g = '[after(t_op_confirm, sec)]';            % PLACEHOLDER
    case 29, g = ['[' ch('HS_BOT',1)                 ']'];
    case 30, g = ['[' both('BR_RDY',3,'CHG',A.eng_out) ']'];
    case 31, g = ['[' ch('EXT',A.eng_out) ' && after(t_cylB_hold, sec)' ']'];
    case 33, g = ['[' ch('RET',A.eng_out)              ']'];
    case 35, g = ['[' ch('PX',G(4))                  ']'];
    case 37, g = ['[' both('BR_RDY',4,'CHG',A.eject)   ']'];
    case 38, g = ['[' ch('EXT',A.eject) ' && after(t_outfeed_pulse, sec)' ']'];
    case 39, g = ['[' ch('RET',A.eject)                ']'];
    otherwise, g = '';                                    % immediate
end
end

%% ========================================================================
function E = bypassEdges(P, ST)
%BYPASSEDGES  The SV11 bypass branch: {from, to, guard, srcOClock, dstOClock}.
%   Mirrors FACTORY_PLC case 17's bypass exit and cases 41-44. Sensor indices
%   come from FACTORY_SENSOR_BUS and the actuator by ROLE, as in GUARDFOR.
if isempty(P.ACT.bypass)
    E = cell(0, 5);                      % the historical plant has no bypass
    return
end
B  = factory_sensor_bus(P);
ch = @(field, k) sprintf('sens(%d) > 0.5', B.(field)(k));
ix = @(name) find(strcmp(ST(:,1), name));
A  = P.ACT;
E = { ...
 ix('S16_PROX3_CHECK'),      ix('S40_BYP_CONV2_STOP'),   ['[' ch('PX',P.PROX_BYPASS) ' && engrave_selected < 0.5]'],     3, 9
 ix('S40_BYP_CONV2_STOP'),   ix('S41_BYP_DV_SEL'),       '',                                                              6, 0
 ix('S41_BYP_DV_SEL'),       ix('S42_BYP_SV11_EXTEND'),  ['[' ch('BR_RDY',3) ' && ' ch('CHG',A.bypass) ']'],              6, 0
 ix('S42_BYP_SV11_EXTEND'),  ix('S43_BYP_SV11_RETRACT'), ['[' ch('EXT',A.bypass) ' && after(t_valve_pulse, sec)' ']'],    6, 0
 ix('S43_BYP_SV11_RETRACT'), ix('S33_CONV3_START'),      ['[' ch('RET',A.bypass) ']'],                                    9, 3};
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

%% ========================================================================
function stationBlock(mdl, name, pos, colour, label, tag, note)
%STATIONBLOCK  One piece of the cell, drawn where it stands. DISPLAY ONLY.
%   A subsystem holding a From tap into a Terminator: it compiles, it names
%   the signal to look at, and it computes nothing. Its icon is a label on
%   the part's own colour.
sp = [mdl '/' name];
add_block('built-in/Subsystem', sp, 'Position', pos, 'BackgroundColor', colour, ...
          'ShowName', 'off');
delete_line_if_any(sp);
add_block('built-in/From', [sp '/tap'], 'GotoTag', tag, 'Position', [40 40 100 60]);
add_block('built-in/Terminator', [sp '/end'], 'Position', [200 40 220 60]);
add_line(sp, 'tap/1', 'end/1');
Simulink.Annotation([sp '/note'], 'Text', note, 'Position', [40 100 460 160]);
labelBlock(sp, label, '', {}, {});
end

%% ========================================================================
function areaBlock(mdl, label, pos)
%AREABLOCK  A shaded, labelled area. DISPLAY ONLY.
%   An area is a BLOCK, built-in/Area, whose name is its label. A
%   Simulink.Annotation cannot become one: AnnotationType is read-only, even
%   in the constructor (SetParamReadOnly, seen 2026-09-14).
ap = [mdl '/' label];
try
    add_block('built-in/Area', ap, 'Position', pos);
catch ME
    if getSimulinkBlockHandle(ap) > 0; delete_block(ap); end   % no stray label
    warning('build_factory_model:area', ...
        'Could not draw the area "%s" (%s). The model is unaffected.', label, ME.identifier);
end
end

%% ========================================================================
function labelBlock(blk, title, sub, ins, outs)
%LABELBLOCK  A mask icon with a title and named ports. DISPLAY ONLY.
%   TITLE and SUB may contain \n (the two characters), which the icon's
%   disp() reads as a line break. A block the release cannot mask keeps its
%   default icon, which is why a failure here only warns.
try
    m = Simulink.Mask.create(blk);
    txt = strrep(title, '''', '''''');
    if ~isempty(sub); txt = [txt '\n' strrep(sub, '''', '''''')]; end
    cmds = ['disp(''' txt ''');'];
    for k = 1:numel(ins)
        cmds = [cmds newline sprintf('port_label(''input'', %d, ''%s'');', k, ins{k})]; %#ok<AGROW>
    end
    for k = 1:numel(outs)
        cmds = [cmds newline sprintf('port_label(''output'', %d, ''%s'');', k, outs{k})]; %#ok<AGROW>
    end
    m.Display = cmds;
catch ME
    warning('build_factory_model:mask', ...
        'Could not label %s (%s). The model is unaffected.', blk, ME.identifier);
end
end

%% ========================================================================
function h = loopLine(mdl, src, sp, dst, dp, yBelow)
%LOOPLINE  Wire SRC output SP to DST input DP along a path under the blocks.
%   A line whose end points sit on the two ports connects them, so this is a
%   real connection with a chosen route, not a drawing.
ph = get_param([mdl '/' src], 'PortHandles');  a = get_param(ph.Outport(sp), 'Position');
ph = get_param([mdl '/' dst], 'PortHandles');  b = get_param(ph.Inport(dp),  'Position');
pts = [a; a(1)+25 a(2); a(1)+25 yBelow; b(1)-25 yBelow; b(1)-25 b(2); b];
h = add_line(mdl, pts);
end

%% ========================================================================
function nameLine(h, name)
%NAMELINE  Name a signal line on the diagram. DISPLAY ONLY.
try
    set_param(h, 'Name', name);
catch ME
    warning('build_factory_model:lineName', ...
        'Could not name the line "%s" (%s).', name, ME.identifier);
end
end
