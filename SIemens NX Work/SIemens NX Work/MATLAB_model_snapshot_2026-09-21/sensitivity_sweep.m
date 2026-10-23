function T = sensitivity_sweep(varargin)
%SENSITIVITY_SWEEP  Which UNMEASURED parameters actually change the answer?
%
%   T = SENSITIVITY_SWEEP()                  sweep every PLH/ASM/EST parameter
%   T = SENSITIVITY_SWEEP('Step', 0.10)      perturbation size (default 0.10)
%   T = SENSITIVITY_SWEEP('Tags', {'ASM'})   restrict to some provenance tags
%   T = SENSITIVITY_SWEEP('Out', 'file.csv') also write the ranked table
%
%   WHY THIS EXISTS
%
%   AUDIT_PROVENANCE says 78 parameters are unmeasured, and that number is
%   [2026-09-13: 78 -> 77 when P.T_air was measured (plan H8), and back to
%   78 the same day with the manual-input mode's laser placeholder]
%   alarming on its own terms. It is also close to meaningless: it counts the
%   placeholder for the operator's reaction time the same as a placeholder for
%   a bracket's mass. COMPLETION_PLAN criterion C5 is not "measure all 78", it
%   is "no parameter that moves the answer by more than 1% is still a guess".
%
%   This separates the two. It perturbs each unmeasured parameter one at a
%   time, re-runs the full cycle, and reports how far MACHINE TIME moved. What
%   comes out is a ranked list: the handful worth a trip to the machine, and
%   the long tail that can stay as assumptions with a clear conscience.
%
%   HOW TO READ THE RESULT
%
%   Sensitivity is percent change in machine time per +10% change in the
%   parameter, so the numbers are comparable across units. A parameter at 0.0
%   is not "unimportant in principle" - it means the model's answer does not
%   currently depend on it, which is exactly what is worth knowing before
%   spending lab time on it.
%
%   WHAT THIS CANNOT TELL YOU, AND IT MATTERS
%
%   1. ONE AT A TIME. Interactions are invisible. Two parameters that each do
%      nothing alone can matter together, and this will not see it.
%   2. LOCAL. A 10% step around the current value. A parameter can be flat here
%      and steep elsewhere, particularly anything that gates a threshold.
%   3. MACHINE TIME ONLY. A parameter that leaves the timing alone but ruins
%      the final position scores 0.0 here. Final position is reported alongside
%      so the ranking can be sanity-checked rather than trusted blindly.
%   5. CALCULATED DEPENDENTS ARE RECOMPUTED - fixed 2026-09-10. FACTORYPARAMS
%      derives a few values from others ([CAL] lines, e.g. the platform jog
%      speed v_base_jog = z_top / t_base_travel). The first version of this
%      sweep perturbed z_top and left the jog speed alone, so the platform
%      rose 10% slower and z_top scored +2.75% - the largest in the run. That
%      was an artefact: with the dependent recomputed, a different travel
%      simply changes the speed, the travel TIME stays the measured one, and
%      z_top moves machine time by essentially nothing (45 mm applied
%      consistently: -0.03 s). Every [CAL] assignment in FACTORYPARAMS is now
%      re-evaluated, in file order, after each perturbation.
%   4. DERIVED PARAMETERS ARE OVERWRITTEN. Anything INITIALIZE_FACTORY
%      recomputes is restored before the run, and reports as 'overwritten'
%      rather than as insensitive. Those are not the same thing and the Status
%      column says which happened.
%   6. THE END POINT, 2026-09-12 (plan H1). Machine and cycle time are taken
%      at S37, where the recorder stops its clock, not at S39. Rankings made
%      before then ran to S39 and carried the 5.67 s outfeed tail in the
%      denominator, so the same shift in seconds now scores about 11% higher,
%      and a parameter that only moves the outfeed pulse or its retract now
%      scores nothing - correctly, since the real clock never sees it.
%
%   See also AUDIT_PROVENANCE, FACTORYPARAMS, OPERATOR_DISTRIBUTION.

o = struct('Step', 0.10, 'Tags', {{'PLH','ASM','EST'}}, 'Out', '', ...
           'Verbose', true);
o = parse_options(o, varargin, mfilename);

A = audit_provenance();
A = A(ismember(A.Tag, o.Tags), :);

P0 = FactoryParams();
calLines = readCalLines();
if o.Verbose
    fprintf('\n  SENSITIVITY SWEEP\n');
    fprintf('  %s\n', repmat('=', 1, 74));
    fprintf('  %d candidate parameters, +%.0f%% each, one at a time.\n', ...
            height(A), 100*o.Step);
    fprintf('  Baseline run first...\n');
end

B = runOnce(P0);
if ~B.ok
    error('sensitivity_sweep:baseline', ...
          'The BASELINE run did not complete. Fix that before sweeping.');
end
if o.Verbose
    fprintf('  baseline (to S37): machine %.3f s, cycle %.3f s, pos error %.4f m\n\n', ...
            B.machine, B.cycle, B.pos);
end

n = height(A);
name = A.Parameter;  tag = A.Tag;
d_machine = nan(n,1); d_cycle = nan(n,1); d_pos = nan(n,1);
base_val  = nan(n,1);
status = repmat({''}, n, 1);

for i = 1:n
    fld = name{i};
    [v, okget] = tryGet(P0, fld);
    if ~okget
        status{i} = 'not a field'; continue
    end
    if ~isnumeric(v) || ~isscalar(v) || ~isfinite(v) || v == 0
        if isnumeric(v) && ~isscalar(v)
            status{i} = 'not scalar';
        elseif isnumeric(v) && isscalar(v) && v == 0
            status{i} = 'zero, cannot scale';
        else
            status{i} = 'not numeric';
        end
        continue
    end
    base_val(i) = v;

    want = v * (1 + o.Step);
    Q = trySet(P0, fld, want);
    Q = recomputeCal(Q, calLines);
    R = runOnce(Q);

    % Did the perturbation survive the derived-quantity rebuild?
    [vAfter, okAfter] = tryGet(R.P, fld);
    if okAfter && isnumeric(vAfter) && isscalar(vAfter) && ...
            abs(vAfter - want) > 1e-9 * max(1, abs(want))
        status{i} = 'overwritten'; continue
    end

    if ~R.ok
        status{i} = 'DID NOT COMPLETE'; continue
    end
    d_machine(i) = 100 * (R.machine - B.machine) / B.machine;
    d_cycle(i)   = 100 * (R.cycle   - B.cycle)   / B.cycle;
    d_pos(i)     = 1000 * (R.pos    - B.pos);  % mm change in pos ERROR
    status{i}    = 'ok';

    if o.Verbose
        fprintf('  %3d/%d  %-34s %+7.3f %%\n', i, n, fld, d_machine(i));
    end
end

T = table(name, tag, base_val, d_machine, d_cycle, d_pos, status, ...
    'VariableNames', {'Parameter','Tag','Value','dMachinePct', ...
                      'dCyclePct','dPos_mm','Status'});

[~, ix] = sort(abs(T.dMachinePct), 'descend', 'MissingPlacement', 'first');
T = T(ix, :);

if o.Verbose; report(T, o.Step); end
if ~isempty(o.Out)
    writetable(T, o.Out);
    fprintf('  written to %s\n', o.Out);
end
end

% ------------------------------------------------------------------------
function R = runOnce(P)
R = struct('ok', false, 'machine', NaN, 'cycle', NaN, 'pos', NaN, 'P', P);
try
    L = run_factory_simulation('Params', P, 'Plot', false, 'Verbose', false);
    R.P       = L.P;
    R.cycle   = L.cycle_time_rec;             % to S37, the recorder's end point
    R.machine = L.machine_time_rec;
    R.pos     = L.pos_error;                  % m, distance from the bin target
    % L.complete is the sequencer's own verdict. Trust it rather than deriving
    % one from the stop time - re-deriving is how the Simulink StopTime
    % staleness hid a truncated cycle for a day.
    R.ok = L.complete && isfinite(R.cycle) && R.cycle > 0;
catch ME
    R.ok  = false;
    R.err = ME.message;
end
end

function L = readCalLines()
% Every [CAL] assignment in FACTORYPARAMS, in file order, as executable code.
% Comment lines are skipped; P.dt is a constant and is left alone.
here = fileparts(mfilename('fullpath'));
txt  = strsplit(fileread(fullfile(here, 'FactoryParams.m')), newline);
L = {};
for k = 1:numel(txt)
    s = txt{k};
    if isempty(regexp(s, '^\s*P\.', 'once')); continue; end
    tok = regexp(s, '^\s*(P\.[\w\.]+\s*=[^%]*?);?\s*%\s*\[CAL\]', 'tokens', 'once');
    if isempty(tok) || startsWith(strtrim(tok{1}), 'P.dt'); continue; end
    L{end+1} = strtrim(tok{1}); %#ok<AGROW>
end
end

function P = recomputeCal(P, L)
% Re-derive the calculated parameters from the (perturbed) inputs. The
% struct must be called P here because the source lines name it P.
for k = 1:numel(L)
    eval([L{k} ';']);
end
end

function [v, ok] = tryGet(P, path)
v = []; ok = false;
parts = strsplit(path, '.');
if ~strcmp(parts{1}, 'P'); return; end
c = P;
for k = 2:numel(parts)
    nm = regexprep(parts{k}, '\(.*\)$', '');
    if ~isstruct(c) || ~isfield(c, nm); return; end
    c = c.(nm);
end
v = c; ok = true;
end

function P = trySet(P, path, val)
parts = strsplit(path, '.');
parts = parts(2:end);
for k = 1:numel(parts)
    parts{k} = regexprep(parts{k}, '\(.*\)$', '');
end
P = setNested(P, parts, val);
end

function s = setNested(s, parts, val)
if numel(parts) == 1
    s.(parts{1}) = val;
else
    s.(parts{1}) = setNested(s.(parts{1}), parts(2:end), val);
end
end

function report(T, step)
fprintf('\n  %s\n', repmat('=', 1, 74));
fprintf('  RANKED BY EFFECT ON MACHINE TIME  (+%.0f%% perturbation)\n', 100*step);
fprintf('  %s\n', repmat('-', 1, 74));

bad = strcmp(T.Status, 'DID NOT COMPLETE');
if any(bad)
    fprintf('\n  BROKE THE CYCLE - these matter most, effect unmeasurable:\n');
    for i = find(bad)'
        fprintf('      %-34s %s\n', T.Parameter{i}, T.Tag{i});
    end
end

ok  = strcmp(T.Status, 'ok');
big = ok & abs(T.dMachinePct) >= 1.0;
fprintf('\n  ABOVE 1%% - criterion C5 says these must not stay guesses (%d):\n', nnz(big));
if ~any(big)
    fprintf('      none\n');
else
    for i = find(big)'
        fprintf('      %-34s %-5s %+7.2f %%   (value %g)\n', ...
            T.Parameter{i}, T.Tag{i}, T.dMachinePct(i), T.Value(i));
    end
end

sml = ok & abs(T.dMachinePct) < 1.0 & abs(T.dMachinePct) > 1e-9;
fprintf('\n  BELOW 1%% - real but small (%d):\n', nnz(sml));
for i = find(sml)'
    fprintf('      %-34s %-5s %+7.3f %%\n', T.Parameter{i}, T.Tag{i}, T.dMachinePct(i));
end

zro = ok & abs(T.dMachinePct) <= 1e-9;
fprintf('\n  NO EFFECT ON TIMING (%d).', nnz(zro));
fprintf(' Check dPos_mm before calling one irrelevant.\n');
moved = zro & abs(T.dPos_mm) > 0.01;
if any(moved)
    fprintf('      of those, these DID move the final position:\n');
    for i = find(moved)'
        fprintf('      %-34s %+8.3f mm\n', T.Parameter{i}, T.dPos_mm(i));
    end
end

skip = ~ok & ~bad;
fprintf('\n  NOT SWEPT (%d): ', nnz(skip));
u = unique(T.Status(skip));
for k = 1:numel(u)
    fprintf('%s x%d  ', u{k}, nnz(strcmp(T.Status(skip), u{k})));
end
fprintf('\n  %s\n\n', repmat('=', 1, 74));
end
