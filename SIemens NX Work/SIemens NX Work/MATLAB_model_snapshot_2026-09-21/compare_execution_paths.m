function R = compare_execution_paths(varargin)
%COMPARE_EXECUTION_PATHS  Measure MATLAB vs Simulink agreement, per transition.
%
%   R = COMPARE_EXECUTION_PATHS()
%   R = COMPARE_EXECUTION_PATHS('Name', value, ...)
%
%   Options
%     'Verbose'  print the per-state table          (default true)
%     'MLLog'    reuse an existing MATLAB LOG       (default [], run one)
%
%   Returns a struct R with
%     R.state_ml, R.state_sl   40x1 entry time of each PLC state [s], NaN if
%                              the state was never entered
%     R.state_delta            R.state_sl - R.state_ml
%     R.max_state_delta        worst per-state disagreement [s]
%     R.cycle_ml/.cycle_sl     cycle time on each path [s]
%     R.cycle_delta            difference [s]
%     R.pos_ml/.pos_sl         final workpiece position [m]
%     R.pos_delta              Euclidean final-position difference [m]
%     R.air_delta              air consumption difference [normal litres]
%     R.n_trans_ml/.n_trans_sl number of states actually entered
%
%   WHY THIS EXISTS
%   The two paths execute the same equations (FACTORY_DERIVATIVES) with the
%   same integrator (RK4 / ode4 at P.dt) and the same sequencer
%   (FACTORY_PLC), so they should agree to floating-point noise. For the
%   whole history of the project they did not: the Simulink path lagged by
%   0.300 s and 0.486 mm by S39_CYCLE_COMPLETE.
%
%   The cause was NOT integration. FACTORY_PLC_SFUN ran its scan in Update
%   but emitted the result from Outputs, so every command reached the plant
%   one scan late, and the lag accumulated once per physics-gated transition.
%   The tell was that every increment of the divergence was an exact multiple
%   of P.t_scan - integration error cannot be quantised to the PLC clock.
%   It is now P.plc_io_delay, defaulting to 0, and honoured by both paths.
%
%   This function is the instrument that found it and the regression guard
%   that keeps it closed. Run it after ANY change to the scheduling of either
%   path.
%
%   Example
%     R = compare_execution_paths;
%     assert(R.max_state_delta < 1e-9)
%
%   See also RUN_FACTORY_SIMULATION, RUN_SIMULINK_MODEL, SIMULINKMODELTEST.

o = struct('Verbose', true, 'MLLog', []);
o = parse_options(o, varargin, mfilename);

ST = factory_states();
nS = size(ST,1);

%% ---- MATLAB path -------------------------------------------------------
if isempty(o.MLLog)
    reset_factory('Quiet', true);
    ML = run_factory_simulation('Plot', false, 'Verbose', false);
else
    ML = o.MLLog;
end

% plc.log records {time, name, excelref} for every transition. S00_INIT is
% the initial state and is never logged as a transition, so it is time 0.
R.state_ml    = nan(nS,1);
R.state_ml(1) = 0;
for i = 1:size(ML.plc.log,1)
    k = find(strcmp(ST(:,1), ML.plc.log{i,2}), 1);
    if ~isempty(k) && isnan(R.state_ml(k)); R.state_ml(k) = ML.plc.log{i,1}; end
end

%% ---- Simulink path -----------------------------------------------------
reset_factory('Quiet', true);
out = run_simulink_model('Plot', false, 'Open', false);
SL  = out.LOG;

R.state_sl = nan(nS,1);
for i = 1:numel(SL.state)
    s = SL.state(i);
    if s >= 1 && s <= nS && isnan(R.state_sl(s)); R.state_sl(s) = SL.t(i); end
end
% The Simulink log starts at t = 0 AFTER the first scan has already run, so
% S00_INIT never appears as a sample. It is entered at t = 0 by definition.
if isnan(R.state_sl(1)); R.state_sl(1) = 0; end

%% ---- compare -----------------------------------------------------------
R.state_delta     = R.state_sl - R.state_ml;
both              = ~isnan(R.state_delta);
R.max_state_delta = max(abs(R.state_delta(both)));
R.n_trans_ml      = sum(~isnan(R.state_ml));
R.n_trans_sl      = sum(~isnan(R.state_sl));

R.cycle_ml    = ML.cycle_time;      R.cycle_sl = SL.cycle_time;
R.cycle_delta = R.cycle_sl - R.cycle_ml;
R.pos_ml      = ML.blk_final;       R.pos_sl   = SL.blk_final;
R.pos_delta   = norm(R.pos_sl - R.pos_ml);
R.air_delta   = SL.air_NL - ML.air_NL;
R.plc_io_delay = ML.P.plc_io_delay;

%% ---- report ------------------------------------------------------------
if o.Verbose
    fprintf('\n  MATLAB vs Simulink, P.plc_io_delay = %d\n', R.plc_io_delay);
    fprintf('  %-4s %-22s %10s %10s %12s\n','idx','state','MATLAB','Simulink','delta [s]');
    for i = 1:nS
        fprintf('  %-4d %-22s %10.4f %10.4f %12.6f\n', ...
                i, ST{i,1}, R.state_ml(i), R.state_sl(i), R.state_delta(i));
    end
    fprintf('\n  states entered      %d (MATLAB)  %d (Simulink)\n', ...
            R.n_trans_ml, R.n_trans_sl);
    fprintf('  worst state delta   %.6e s\n', R.max_state_delta);
    fprintf('  cycle time          %.4f / %.4f  delta %.6e s\n', ...
            R.cycle_ml, R.cycle_sl, R.cycle_delta);
    fprintf('  final position      delta %.6e m  (%.4f mm)\n', ...
            R.pos_delta, 1000*R.pos_delta);
    fprintf('  air consumption     delta %.6e NL\n', R.air_delta);
end
end
