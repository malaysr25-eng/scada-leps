function T = compare_to_recording(varargin)
%COMPARE_TO_RECORDING  Model interval vs measured interval, state by state.
%
%   T = COMPARE_TO_RECORDING()             use the newest cell_timings.json
%   T = COMPARE_TO_RECORDING('File', f)    use a specific extraction
%   T = COMPARE_TO_RECORDING('Log', LOG)   compare an existing run
%   T = COMPARE_TO_RECORDING('Tol', 0.10)  divergence threshold (default 0.10)
%   T = COMPARE_TO_RECORDING('Route', 'bypass')  the SV11 route; runs the bypass
%
%   ROUTES (2026-09-15). The route splits at S16: engraved (cylinder A, the
%   platform, cylinder B) or bypass (on to prox 8, SV11 across to belt 3). A
%   round-4 (schema 3) extraction labels each cycle's route: engraved, bypass,
%   or neither when the block stopped before either. The intervals before the
%   split (belt 1, the SV6 delay) are compared with every real cycle. The
%   rest are compared only with cycles that took the route being compared, so
%   a bypass cycle's belt-3 run never reaches the engraved comparison. An
%   older file has no routes: the engraved comparison then uses every cycle,
%   as it always did, and says so. 'Route' defaults to the LOG's own route
%   (P.engrave_selected), or 'engraved'. CompareToRecordingTest re-times every
%   mapped pair, on both routes, from the LOG's own conveyor and sensor edges.
%
%   THIS IS COMPLETION CRITERION C3. The whole-cycle number has been compared
%   for weeks and it hides everything: a model can be 6 s slow overall because
%   one state is 6 s slow, or because twelve states are 0.5 s slow, and those
%   are completely different problems with completely different fixes. This
%   compares each interval the recorder actually measures against the same
%   interval in the model, and says which states carry the error.
%
%   HOW THE MAPPING WAS ESTABLISHED, because a wrong one would be invisible
%
%   The recorder names its intervals after tags; the model names its states
%   after steps. The correspondence is NOT guessed. Each entry below was
%   confirmed two ways: against the dwell wiring in FACTORY_PLC (which line
%   advances which state on which timer) and against the printed state trace
%   of a real run, where the modelled duration reproduces the timer to within
%   a scan. Where that confirmation could not be made, the entry is
%   **UNMAPPED** and stays out of the comparison.
%
%   That follows the project rule for I/O maps and applies for the same
%   reason: an interval compared against the wrong state produces a number
%   that looks like a finding and is not one.
%
%   WHAT IT REPORTS
%
%   For each mapped interval: the model's duration, the recording's mean and
%   spread across however many cycles observed it, the gap, and whether that
%   gap is inside criterion C3 (within 10% or within 0.5 s, whichever is
%   kinder). Intervals seen in only one cycle are flagged, because a spread of
%   zero from n=1 is not agreement.
%
%   See also SENSITIVITY_SWEEP, OPERATOR_DISTRIBUTION, FACTORY_STATES.

o = struct('File', '', 'Log', [], 'Route', '', 'Tol', 0.10, 'AbsTol', 0.5, ...
           'Verbose', true);
o = parse_options(o, varargin, mfilename);

% ---- which route ---------------------------------------------------------
route = lower(char(string(o.Route)));
if ~isempty(route) && ~any(strcmp(route, {'engraved', 'bypass'}))
    error('compare_to_recording:route', ...
        'Route must be ''engraved'' or ''bypass'', got ''%s''.', route);
end
if ~isempty(o.Log)
    logRoute = 'engraved';
    if isfield(o.Log, 'P') && isfield(o.Log.P, 'engrave_selected') && ...
            ~o.Log.P.engrave_selected
        logRoute = 'bypass';
    end
    if ~isempty(route) && ~strcmp(route, logRoute)
        error('compare_to_recording:routeLog', ...
            ['''Route'' is ''%s'' but the LOG passed in ran the %s route ' ...
             '(P.engrave_selected). Pass a LOG of the route to compare.'], ...
            route, logRoute);
    end
    route = logRoute;
end
if isempty(route); route = 'engraved'; end

% ---- the mapping ---------------------------------------------------------
% {recorded interval, from state, to state, how it was confirmed}
% States are the 0-based indices printed by the state trace.
%
% Before the route splits at S16 both routes run the same states, so these
% are compared with every real cycle.
SHARED = {
 'cycle_conveyor1_run'         ,  9, 11, 'CONV1_START -> CONV1_STOP'
 'sv6_delay_after_prox6'       , 12, 13, 'factory_plc line 167, t_xfer1_dwell'
};
PULSE = 'a coil pulse width, not a state interval';
switch route
    case 'engraved'
        R = {
 'cycle_conveyor2_run'         , 13, 17, 'conveyor 2 on (S13 since H5) -> CONV2_STOP'
 'cycle_conveyor3_run'         , 32, 35, 'conveyor 3 on (S32 since H5) -> CONV3_STOP'
 'cylA_extend_duration'        , 19, 20, 'factory_plc line 198, t_cylA_hold'
 'cylB_extend_duration'        , 30, 31, 'factory_plc line 243, t_cylB_hold'
 'platform_rise'               , 23, 24, 'S23 guard is HS_TOP'
 'platform_fall'               , 28, 29, 'S28 guard is HS_BOT'
 'platform_dwell_at_top'       , 24, 27, 'the whole operator dwell'
 'operator_notice_and_engrave' , 24, 26, 'notice + engrave, confirm excluded'
 'operator_confirm'            , 26, 27, 'confirm only'
        };
        % Deliberately UNMAPPED. Listed so the gap is visible rather than silent.
        U = {
 'prox7_into_conveyor2'  , 'no model state pair reproduces it; 2.622 s matches nothing'
 'pulse_solenoid_valve6' , PULSE
 'pulse_solenoid_valve7' , PULSE
 'pulse_solenoid_valve8' , PULSE
 'pulse_solenoid_valve9' , PULSE
 'pulse_solenoid_valve10', PULSE
 'pulse_solenoid_valve12', PULSE
 'sv12_pulse_width'      , PULSE
 'pulse_solenoid_valve11', 'the bypass coil: compare it with ''Route'', ''bypass'''
 'conveyor2_to_prox8'    , 'bypass only: this route stops the block at prox 7'
 'prox7_to_prox8'        , 'this route stops the block at prox 7; it never reaches prox 8'
 'prox8_to_sv11'         , 'bypass only'
        };
    case 'bypass'
        % Each confirmed against FACTORY_PLC's cases (named) and the trace of
        % a bypass run on 2026-09-15: S13 18.580, S40 20.560, S42 20.700,
        % S43 22.700, S35 23.810 s, against conveyor 2 on 18.59 / off 20.57,
        % prox 8 20.555, conveyor 3 on 20.57, prox 9 23.81 s.
        R = {
 'cycle_conveyor2_run'         , 13, 40, 'conveyor 2 on at S13, off at S40 (case 41)'
 'conveyor2_to_prox8'          , 13, 40, 'S16 leaves for S40 on prox 8 (case 17)'
 'prox8_to_sv11'               , 40, 42, 'S40 is entered on prox 8; S42 energises SV11 (case 43)'
 'pulse_solenoid_valve11'      , 42, 43, 'S42 holds SV11 for T#2S, S43 drops it (cases 43, 44)'
 'cycle_conveyor3_run'         , 40, 35, 'conveyor 3 on at S40 (case 41); S35 is entered on prox 9'
        };
        U = {
 'prox7_into_conveyor2'  , 'no model state pair reproduces it'
 'prox7_to_prox8'        , 'prox 7 is not a guard on the bypass; no state marks it'
 'pulse_solenoid_valve6' , PULSE
 'pulse_solenoid_valve12', PULSE
 'sv12_pulse_width'      , PULSE
 'cylinders A and B'     , 'do not move on the bypass (and SV7-SV10 do not fire)'
 'platform, operator'    , 'the platform stays down on the bypass'
        };
end
M = [SHARED; R];
shared = [true(size(SHARED, 1), 1); false(size(R, 1), 1)];

% ---- the recording -------------------------------------------------------
f = o.File;
if isempty(f); f = newestExtraction(); end
if isempty(f) || ~isfile(f)
    error('compare_to_recording:noFile', ...
        ['No cell_timings.json found. Pass one with ''File''.\n' ...
         'Looked under Project_Notes for the newest extraction.']);
end
R = jsondecode(fileread(f));
if o.Verbose
    fprintf('\n  COMPARE TO RECORDING\n');
    fprintf('  %s\n', repmat('=', 1, 74));
    fprintf('  recording : %s\n', f);
end

% Real cycles only. A simulator cycle agrees with the model by construction
% and would make this report say the model is perfect.
cyc = R.cycles;
if ~iscell(cyc); cyc = num2cell(cyc); end
real_ix = false(1, numel(cyc));
for k = 1:numel(cyc)
    c = cyc{k};
    real_ix(k) = ~(isfield(c,'source_id') && contains(lower(string(c.source_id)), 'sim')) ...
              && ~(isfield(c,'mode')      && contains(lower(string(c.mode)),      'sim'));
end
cyc = cyc(real_ix);
if o.Verbose
    fprintf('  cycles    : %d real of %d\n', numel(cyc), numel(real_ix));
end
if isempty(cyc)
    error('compare_to_recording:noRealCycles', ...
        ['Every cycle in this extraction is flagged simulated. Comparing ' ...
         'against the simulator tells you nothing - it is seeded from the ' ...
         'model''s own parameters.']);
end

% ---- which cycles each interval may use ----------------------------------
% See ROUTES in the header. A cycle without a route label (an older file,
% or a mixed one) is never counted for a route-specific interval of a
% labelled file.
labelled = cellfun(@(c) isfield(c, 'route'), cyc);
routes = repmat({''}, 1, numel(cyc));
routes(labelled) = cellfun(@(c) char(string(c.route)), cyc(labelled), ...
                           'UniformOutput', false);
if any(labelled)
    onRoute = strcmp(routes, route);
    routeNote = sprintf(['%s. Shared intervals use all %d real cycles; the ' ...
        'route''s own use %d (by route: %s)'], route, numel(cyc), ...
        nnz(onRoute), tally(routes));
else
    onRoute = repmat(strcmp(route, 'engraved'), 1, numel(cyc));
    routeNote = sprintf('%s. Routes are not labelled in this file (extractor schema < 3): %s', ...
        route, ternary(strcmp(route, 'engraved'), ...
        'every real cycle is used for every interval, as before', ...
        'only the intervals before the split are compared'));
end
if o.Verbose
    fprintf('  route     : %s\n', routeNote);
end

% ---- the model -----------------------------------------------------------
L = o.Log;
if isempty(L)
    if strcmp(route, 'engraved')
        L = factory_log();
    else
        Q = FactoryParams(); Q.engrave_selected = false;
        L = run_factory_simulation('Params', Q, 'Plot', false, 'Verbose', false);
    end
end
tin = stateEntryTimes(L);
if o.Verbose
    fprintf('  model     : cycle %.3f s', L.cycle_time);
    if isfield(L, 'cycle_time_rec')   % a LOG cached before 2026-09-12 lacks it
        fprintf(', to S37 %.3f s (the recorder''s end point)', L.cycle_time_rec);
    end
    fprintf('\n\n');
end

% ---- compare -------------------------------------------------------------
n = size(M, 1);
Interval = M(:,1);
FromTo   = arrayfun(@(i) sprintf('S%02d->S%02d', M{i,2}, M{i,3}), (1:n)', ...
                    'UniformOutput', false);
Model = nan(n,1); Meas = nan(n,1); Lo = nan(n,1); Hi = nan(n,1);
N = zeros(n,1); Gap = nan(n,1); GapPct = nan(n,1);
Verdict = repmat({''}, n, 1);

for i = 1:n
    a = M{i,2} + 1; b = M{i,3} + 1;        % trace index -> raw state value
    if a <= numel(tin) && b <= numel(tin) && isfinite(tin(a)) && isfinite(tin(b))
        Model(i) = tin(b) - tin(a);
    end
    if shared(i); pool = cyc; else; pool = cyc(onRoute); end
    v = collect(pool, M{i,1});
    N(i) = numel(v);
    if N(i) > 0
        Meas(i) = mean(v); Lo(i) = min(v); Hi(i) = max(v);
    end
    if isfinite(Model(i)) && isfinite(Meas(i))
        Gap(i)    = Model(i) - Meas(i);
        GapPct(i) = 100 * Gap(i) / Meas(i);
        within = abs(Gap(i)) <= o.AbsTol || abs(GapPct(i)) <= 100*o.Tol;
        if N(i) == 1
            Verdict{i} = ternary(within, 'within (n=1)', 'OUTSIDE (n=1)');
        else
            Verdict{i} = ternary(within, 'within', 'OUTSIDE');
        end
    elseif ~isfinite(Meas(i))
        Verdict{i} = 'not recorded';
    else
        Verdict{i} = 'state not reached';
    end
end

Scope = repmat({'route'}, n, 1);
Scope(shared) = {'shared'};
T = table(Interval, FromTo, Model, Meas, Lo, Hi, N, Gap, GapPct, Verdict, Scope);
[~, ix] = sort(abs(T.Gap), 'descend', 'MissingPlacement', 'last');
T = T(ix, :);

if o.Verbose; report(T, U, o); end
end

% ------------------------------------------------------------------------
function v = collect(cyc, name)
v = [];
for k = 1:numel(cyc)
    c = cyc{k};
    if isfield(c, 'intervals') && isstruct(c.intervals) && ...
            isfield(c.intervals, name)
        x = c.intervals.(name);
        if isnumeric(x) && isscalar(x) && isfinite(x); v(end+1) = x; end %#ok<AGROW>
    end
end
end

function tin = stateEntryTimes(L)
% First time the sequencer entered each state. States that never happened
% stay NaN rather than 0, so a missing state cannot masquerade as an instant
% one - which is exactly how a truncated Simulink run once read as complete.
% CALIBRATION, and it is worth stating because an off-by-one here is
% invisible: L.state stores the trace's display index PLUS ONE. Verified
% empirically - state value 2 is the first entered, at t = 0.000, and the
% printed trace calls that same moment S01_CAMERA_DETECT. So tin is indexed
% by the raw state value, and callers convert with display + 1.
s = L.state(:); t = L.t(:);
s = s(s >= 1);  tt = t(L.state(:) >= 1);
tin = nan(1, max(s));
d = [true; diff(s) ~= 0];
for k = find(d)'
    if isnan(tin(s(k))); tin(s(k)) = tt(k); end
end
end

function out = ternary(c, a, b)
if c; out = a; else; out = b; end
end

function f = newestExtraction()
f = '';
here = fileparts(mfilename('fullpath'));
root = fileparts(here);
d = dir(fullfile(root, 'Project_Notes', '**', 'cell_timings*.json'));
if isempty(d); return; end
[~, i] = max([d.datenum]);
f = fullfile(d(i).folder, d(i).name);
end

function report(T, U, o)
fprintf('  %s\n', repmat('-', 1, 74));
fprintf('  %-28s %8s %8s %6s %8s  %s\n', ...
        'interval', 'model', 'measured', 'n', 'gap', 'verdict');
fprintf('  %s\n', repmat('-', 1, 74));
for i = 1:height(T)
    if isfinite(T.Gap(i))
        fprintf('  %-28s %8.3f %8.3f %6d %+8.3f  %s\n', ...
            T.Interval{i}, T.Model(i), T.Meas(i), T.N(i), T.Gap(i), T.Verdict{i});
    else
        fprintf('  %-28s %8s %8s %6d %8s  %s\n', ...
            T.Interval{i}, fmt(T.Model(i)), fmt(T.Meas(i)), T.N(i), '-', ...
            T.Verdict{i});
    end
end

bad = contains(T.Verdict, 'OUTSIDE');
fprintf('\n  %s\n', repmat('-', 1, 74));
fprintf('  CRITERION C3: within %.0f%% or %.1f s, whichever is kinder.\n', ...
        100*o.Tol, o.AbsTol);
fprintf('  %d of %d mapped intervals PASS, %d fail.\n', ...
        nnz(contains(T.Verdict, 'within')), height(T), nnz(bad));
if any(bad)
    fprintf('\n  WHERE THE ERROR ACTUALLY IS:\n');
    for i = find(bad)'
        fprintf('      %-28s %+7.3f s  (%+.1f%%)\n', ...
                T.Interval{i}, T.Gap(i), T.GapPct(i));
    end
    fprintf('\n  Sum of the failing gaps: %+.3f s. Compare that with the\n', ...
            sum(T.Gap(bad)));
    fprintf('  whole-cycle gap before assuming they are the same thing.\n');
end

one = T.N == 1;
if any(one)
    fprintf('\n  SEEN IN ONLY ONE CYCLE (%d) - agreement here is not evidence:\n', nnz(one));
    for i = find(one)'
        fprintf('      %s\n', T.Interval{i});
    end
end

fprintf('\n  DELIBERATELY UNMAPPED (%d), so the gap is visible not silent:\n', size(U,1));
for i = 1:size(U,1)
    fprintf('      %-24s %s\n', U{i,1}, U{i,2});
end
fprintf('  %s\n\n', repmat('=', 1, 74));
end

function s = fmt(x)
if isfinite(x); s = sprintf('%8.3f', x); else; s = '       -'; end
end

function s = tally(routes)
% 'engraved 1, bypass 1, neither 1', in first-seen order; unlabelled as '(none)'.
routes(cellfun(@isempty, routes)) = {'(none)'};
[u, ~, k] = unique(routes, 'stable');
s = strjoin(arrayfun(@(i) sprintf('%s %d', u{i}, nnz(k == i)), 1:numel(u), ...
                     'UniformOutput', false), ', ');
end
