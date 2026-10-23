function out = run_simulink_model(varargin)
%RUN_SIMULINK_MODEL  Build if necessary, configure, run and report the model.
%
%   out = RUN_SIMULINK_MODEL()
%   out = RUN_SIMULINK_MODEL('Name', value, ...)
%
%   Options
%     'Model'    model name              (default 'Factory_Physics_Model')
%     'Rebuild'  force a rebuild         (default false)
%     'StopTime' override stop time [s]  (default P.t_max)
%     'Plot'     draw results            (default true)
%     'Open'     open the model window   (default true)
%     'Animate'  afterwards, replay the run on the cell picture at 1x
%                (VISUALIZE_FACTORY; default false). A replay, not a live
%                view: this path runs about 6x slower than real time.
%
%   WHAT IT DOES, IN ORDER
%     1. checks the environment (CHECK_ENVIRONMENT) and stops if anything
%        required is missing - it does not attempt to run a broken setup
%     2. clears the parameter cache so edits to FactoryParams.m take effect
%     3. builds Factory_Physics_Model.slx if it is not on the path
%     4. verifies the solver settings are the ones the physics needs
%     5. runs the simulation
%     6. converts the logged signals into the same LOG struct that
%        RUN_FACTORY_SIMULATION produces, so the same plotting and
%        visualisation code works on both
%
%   WHAT IT DOES NOT DO
%   It does not silently change model parameters to make a run succeed. If
%   the solver settings in the .slx disagree with FactoryParams.m it says so
%   and asks you to rebuild, rather than quietly overwriting your model.
%
%   Example
%     out = run_simulink_model;
%     LOG = out.LOG;
%     visualize_factory(LOG);
%
%   See also BUILD_FACTORY_MODEL, RUN_FACTORY_SIMULATION, CHECK_ENVIRONMENT.

o = struct('Model','Factory_Physics_Model','Rebuild',false, ...
           'StopTime',[], 'Plot',true, 'Open',true, 'Animate',false);
o = parse_options(o, varargin, mfilename);
mdl = o.Model;

%% ---- 1. environment ----------------------------------------------------
env = check_environment('Quiet', true, 'Simulink', true);
if ~env.ok
    check_environment('Simulink', true);   % print the full table
    error('run_simulink_model:environment', ...
        ['The environment is not ready. See the table above. ' ...
         'README.md section 12 (Troubleshooting) lists the fixes.']);
end

%% ---- 2. fresh parameters ----------------------------------------------
% Anything cached from a previous run is discarded here, so an edit to
% FactoryParams.m or JanaticsData.m always takes effect.
reset_factory('Quiet', true);
P = factory_params_cached();

%% ---- 3. build if needed ------------------------------------------------
if o.Rebuild || isempty(which([mdl '.slx']))
    fprintf('Building %s ...\n', mdl);
    build_factory_model('Model', mdl, 'Open', o.Open);
elseif ~bdIsLoaded(mdl)
    load_system(mdl);
end
if o.Open && ~strcmp(get_param(mdl,'Open'),'on'); open_system(mdl); end

%% ---- 4. verify the solver settings -------------------------------------
% These are not cosmetic. The model diverges to NaN at a 1.0e-3 s step.
% STOPTIME IS CHECKED HERE TOO, added 2026-09-08, and it is not cosmetic
% either. BUILD_FACTORY_MODEL bakes StopTime into the .slx from P.t_max at
% BUILD time, and this function LOADS the saved model - so raising P.t_max
% leaves every saved .slx behind with the old horizon. That happened the day
% the engraving axis became a jog: the cycle grew 33.84 -> 49.29 s past a
% StopTime of 45 still saved in the file, and SIMULINKMODELTEST reported it as
% "the Simulink run did not complete the cycle", which points at the plant
% rather than at the horizon that actually stopped it.
%
% A truncated run is not a failed run and must not be diagnosed as one. The
% solver settings have been guarded this way since the ode4 defect; the
% horizon was the same class of stale-saved-state bug and was not.
want = struct('SolverType','Fixed-step', 'Solver','ode4', ...
              'FixedStep', num2str(P.dt,'%.10g'), ...
              'StopTime',  num2str(P.t_max,'%.10g'));
bad = {};
f = fieldnames(want);
for i = 1:numel(f)
    got = get_param(mdl, f{i});
    if ~strcmp(strtrim(got), strtrim(want.(f{i})))
        bad{end+1} = sprintf('%s is "%s", expected "%s"', f{i}, got, want.(f{i})); %#ok<AGROW>
    end
end
if ~isempty(bad)
    error('run_simulink_model:solver', ...
        ['The saved model does not match FactoryParams.m:\n  %s\n' ...
         'Rebuild it:  run_simulink_model(''Rebuild'', true)\n' ...
         'These are baked into the .slx at BUILD time, so a parameter edit ' ...
         'does not reach a saved model on its own.\n' ...
         'Do not simply raise the step size - the physics diverges above ' ...
         '8.3e-4 s. And do not lower StopTime to make a run "finish": a ' ...
         'truncated cycle reports as an incomplete one.'], ...
        strjoin(bad, '\n  '));
end
if ~isempty(o.StopTime)
    set_param(mdl, 'StopTime', num2str(o.StopTime,'%.10g'));
end

%% ---- 5. run ------------------------------------------------------------
fprintf('Simulating %s  (stop time %s s, step %g s)\n', ...
        mdl, get_param(mdl,'StopTime'), P.dt);
fprintf(['This is an interpreted S-function at a 0.5 ms fixed step. ' ...
         'Expect several minutes.\n']);
tic;
out = sim(mdl);
wall = toc;

%% ---- 6. repackage into the standard LOG struct ------------------------
LOG = simout_to_log(out, P);
LOG.wall_time = wall;
out.LOG = LOG;

fprintf('\n  ------------------------------------------------\n');
if LOG.complete
    fprintf('  CYCLE COMPLETE       %8.3f s (simulated)\n', LOG.cycle_time);
else
    fprintf('  CYCLE DID NOT COMPLETE - ended in state %d\n', LOG.state(end));
end
fprintf('  wall-clock           %8.1f s\n', wall);
fprintf('  final workpiece      (%.4f, %.4f) m\n', LOG.blk_final);
fprintf('  position error       %8.2f mm\n', 1000*LOG.pos_error);
fprintf('  peak chamber A       %8.2f bar\n', max(LOG.PA(:))/1e5);
fprintf('  peak chamber B       %8.2f bar\n', max(LOG.PB(:))/1e5);
fprintf('  air consumed         %8.2f normal litres\n', LOG.air_NL);
fprintf('  ------------------------------------------------\n');

if o.Plot; plot_factory_results(LOG); end
if o.Animate; visualize_factory(LOG); end
end

%% ========================================================================
function LOG = simout_to_log(out, P)
%SIMOUT_TO_LOG  Convert Simulink logs into the RUN_FACTORY_SIMULATION format.
%   Keeping one LOG format means PLOT_FACTORY_RESULTS and VISUALIZE_FACTORY
%   work unchanged on either execution path, and the two paths can be
%   compared field by field.
S  = get_signal(out, 'plant_state');
PS = get_signal(out, 'plc_state');
CM = get_signal(out, 'commands');
IX = P.IX;

LOG.t      = S.time(:);
X          = S.signals.values;
LOG.blk    = [X(:,IX.bx)  X(:,IX.by)];
LOG.blk_v  = [X(:,IX.bvx) X(:,IX.bvy)];
% Acceleration and the 2-D force breakdown are RECONSTRUCTED, not logged.
% They used to be zeros with the note "not logged on this path", which meant
% the two execution paths produced different LOG contents and
% VISUALIZE_PROCESSES rejected a Simulink LOG outright.
%
% No model change is needed: the .slx already logs the full plant state and the
% command vector, and FACTORY_DERIVATIVES is a pure function of those. So the
% same values the MATLAB path records directly can be recovered exactly here,
% by re-evaluating the physics at each logged sample. One evaluation per sample
% costs well under a second against an 87 s run.
LOG.blk_a  = zeros(size(LOG.blk));
LOG.F_rod  = zeros(size(LOG.blk));  LOG.F_stop = zeros(size(LOG.blk));
LOG.F_fric = zeros(size(LOG.blk));  LOG.F_net  = zeros(size(LOG.blk));
LOG.belt_v = zeros(size(LOG.blk));  LOG.reg    = zeros(size(LOG.t));
CMv = CM.signals.values;
for k = 1:numel(LOG.t)
    uk = unpack_command(CMv(k,:), P);
    [dsk, dbgk] = factory_derivatives(X(k,:)', uk, P);
    LOG.blk_a(k,:) = [dsk(IX.bvx) dsk(IX.bvy)];
    LOG.F_rod(k,:) = dbgk.F_rod;   LOG.F_stop(k,:) = dbgk.F_stop;
    LOG.F_fric(k,:)= dbgk.F_fric;  LOG.F_net(k,:)  = dbgk.F_net;
    LOG.belt_v(k,:)= dbgk.belt_v;  LOG.reg(k)      = dbgk.reg;
end
LOG.rod    = X(:,IX.x);
LOG.rod_v  = X(:,IX.v);
LOG.PA     = X(:,IX.PA);
LOG.PB     = X(:,IX.PB);
% Per-actuator areas, as FACTORY_DERIVATIVES uses. This read the scalars
% P.A_A / P.A_B until 2026-09-02, when the bores became per-actuator against
% the day a real one arrived. That day was 2026-09-07: CYL_A is bore 32 from a
% nameplate and the other ten are still the [JAN] 20, so the scalars would now
% be wrong here for CYL_A.
aA = reshape([P.CYL.A_A], 1, []);
aB = reshape([P.CYL.A_B], 1, []);
LOG.rod_F  = LOG.PA.*aA - LOG.PB.*aB - P.P_atm*(aA-aB);
LOG.spool  = X(:,IX.sp);
LOG.P_res  = X(:,IX.P_res);
LOG.P_br   = X(:,IX.P_br);
LOG.v_blt  = P.r_pul*X(:,IX.om);
LOG.base_z = X(:,IX.bz);
LOG.m_air  = X(:,IX.mair);
LOG.state  = interp1(PS.time(:), PS.signals.values(:), LOG.t, 'previous', 1);

LOG.P          = P;
LOG.cycle_time = LOG.t(end);
LOG.complete   = LOG.state(end) >= 40;
LOG.blk_final  = LOG.blk(end,:);
LOG.blk_target = P.WP.bin;
LOG.pos_error  = norm(LOG.blk_final - LOG.blk_target);
LOG.air_kg     = LOG.m_air(end);
LOG.air_NL     = 1000*LOG.air_kg/P.rho0;
% The SV11 bypass has no operator (no engraving), as in RUN_FACTORY_SIMULATION.
LOG.time_operator = (P.t_op_notice + P.t_engrave + P.t_op_confirm) * P.engrave_selected;
% The recorder's end point, S37 entry (row 38), as in RUN_FACTORY_SIMULATION.
% An exact match, not >= 38: on the bypass, rows 41-44 come BEFORE row 34.
k37 = find(LOG.state == 38, 1);
if isempty(k37); LOG.cycle_time_rec = NaN; else; LOG.cycle_time_rec = LOG.t(k37); end
LOG.machine_time_rec = LOG.cycle_time_rec - LOG.time_operator;
end

%% ========================================================================
function u = unpack_command(v, P)
%UNPACK_COMMAND  Inverse of the packing in FACTORY_PLC_SFUN's Outputs.
%   [pump; dv(1:4); sol(1:NSOL); conv(1:NCONV); base]
%   Indices come from FACTORY_CMD_BUS rather than being recomputed, which is
%   the whole point of that file: this function used to derive them from
%   P.NCYL, and P.NCYL is no longer the coil count.
B = factory_cmd_bus(P);
u.pump_on = v(B.pump) > 0.5;
u.dv      = v(B.dv);
u.sol     = v(B.sol);
u.conv    = v(B.conv);
u.base    = v(B.base);
end

%% ========================================================================
function s = get_signal(out, name)
%GET_SIGNAL  Pull a To Workspace variable out of the SimulationOutput.
if isprop(out, name) || isfield(out, name)
    s = out.(name);
elseif evalin('base', sprintf('exist(''%s'',''var'')', name)) == 1
    s = evalin('base', name);
else
    error('run_simulink_model:missingLog', ...
        ['The model did not return the logged signal "%s". The To ' ...
         'Workspace block may have been deleted. Rebuild with ' ...
         'run_simulink_model(''Rebuild'', true).'], name);
end
end
