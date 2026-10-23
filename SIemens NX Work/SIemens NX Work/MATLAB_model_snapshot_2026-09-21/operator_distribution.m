function R = operator_distribution(varargin)
%OPERATOR_DISTRIBUTION  Predict a cycle-time DISTRIBUTION, not a single number.
%
%   R = OPERATOR_DISTRIBUTION() runs the Monte Carlo and prints the comparison.
%   R = OPERATOR_DISTRIBUTION('N', 10000) sets the sample count.
%   R = OPERATOR_DISTRIBUTION('Validate', true) also runs FULL simulations at
%       the extremes to re-check the additivity this relies on (slow, ~3 min).
%
%   WHY THIS EXISTS
%
%   The model predicted the same cycle time every run. The real cell does not:
%   its operator dwell ranges 5.95 to 28.65 s with a standard deviation of
%   7.83 s, so cycle time is not a scalar and quoting one was always a category
%   error. This turns the model's single answer into a distribution that can be
%   compared with the machine's.
%
%   WHY IT DOES NOT NEED N FULL SIMULATIONS
%
%   Because the operator time is ADDITIVE, and that was measured rather than
%   assumed. Three full runs at operator totals of 5.950, 13.979 and 28.649 s
%   gave machine times of 57.860, 57.861 and 57.861 s - constant to one
%   millisecond across the whole sampled range, with 39 transitions and an
%   unchanged final position every time. The plant genuinely just waits.
%
%   So cycle_time = machine_time + operator_total, and ten thousand samples are
%   arithmetic rather than ten thousand simulations. Pass 'Validate' to re-run
%   the three full simulations and confirm the constant still holds; if the
%   sequencer ever gains a state that does real work during the dwell, that
%   check is what will catch it.
%
%   THE END POINT, corrected 2026-09-12 (plan H1). Until then the constant was
%   machine time to S39, 57.861 s. The observed cycles it is added against
%   end earlier: the recorder's cycle_completed rises when the last outfeed
%   push STARTS, which is S37. So the 5.67 s outfeed push and retract were
%   credited to the model and to nothing on the real side. Like for like the
%   constant is 52.191 s (52.190 / 52.191 at the two extreme operator totals,
%   additive exactly as before), and the comparison it produces is worse and
%   true. The method was sound; the end point was not. See
%   Project_Notes/to_matlab/round2_2026-09-10/SEGMENT_BUDGET_2026-09-10.md.
%
%   AND THE START, the same day (plan H2). The T#10S start delay added
%   7.65 s of machine time at the front of the cycle: 52.191 -> 59.841 s
%   (59.840 / 59.841 at the extremes). Additivity holds exactly as before.
%   AND BELT 3 (plan H3): 59.841 -> 58.371 s (58.370 / 58.371), with the
%   outfeed at the measured 43 cm instead of 65.
%   AND THE BELT SPEEDS (plan H4): 58.371 -> 56.891 s (56.890 / 56.891).
%   AND THE OVERLAP (plan H5): 56.891 -> 55.441 s (55.440 / 55.441).
%   AND THE WAIT BEFORE CYLINDER A (plan H6): 55.441 -> 56.751 s.
%   AND THE NAMEPLATES (plan H7): 56.751 -> 57.401 s (57.400 / 57.401).
%   AND THE ROOM AIR (plan H8): 57.401 -> 57.341 s (57.340 / 57.341).
%
%   See also FACTORY_OPERATOR_DRAW, FACTORYPARAMS section 10.

o = struct('N', 10000, 'Validate', false, 'Seed', 42, 'Verbose', true);
o = parse_options(o, varargin, mfilename);

P = FactoryParams();

% ---- the machine-time constant, and where it comes from -----------------
% Measured over the full sampled range, held to 1 ms, and TO S37 - where the
% recorder stops its clock. It was 57.861 s to S39, then 52.191 s to S37
% before the T#10S start delay went in (plan H2), both 2026-09-12; then
% 59.841 s, 58.371 s after H3's shorter belt 3, and 56.891 s after H4's
% measured belt speeds, 55.441 s after H5's push/belt overlap, and 56.751 s
% after H6's wait before cylinder A, 57.401 s after H7's nameplate bores
% and strokes, and 57.341 s after H8's room air. See the header.
R.t_machine = 57.341;                                     % s
R.end_point = 'S37 entry: the last outfeed push starts (the recorder''s cycle_completed)';
R.machine_time_source = 'measured to S37 over op_total 5.950 / 28.649 s';

if o.Validate
    fprintf('Re-checking additivity with three FULL simulations...\n');
    tot = [min(P.OP.samples) mean(P.OP.samples) max(P.OP.samples)];
    mt  = zeros(1,3);
    for k = 1:3
        Q = P; Q.t_op_confirm = P.OP.confirm;
        rest = tot(k) - P.OP.confirm;
        Q.t_op_notice = rest*P.OP.notice_frac;
        Q.t_engrave   = rest*(1-P.OP.notice_frac);
        L = run_factory_simulation('Params', Q, 'Plot', false, 'Verbose', false);
        mt(k) = L.cycle_time_rec - tot(k);
        fprintf('  op_total %7.3f -> cycle to S37 %7.3f -> machine %8.4f\n', ...
                tot(k), L.cycle_time_rec, mt(k));
    end
    R.validated_machine_time = mt;
    R.validation_spread_s    = max(mt) - min(mt);
    if R.validation_spread_s > 0.05
        warning('operator_distribution:additivity', ...
            ['Machine time varied by %.3f s across the operator range. The ' ...
             'additivity this function relies on NO LONGER HOLDS - the ' ...
             'sequencer must now do real work during the dwell. Use full ' ...
             'simulations, not this shortcut.'], R.validation_spread_s);
    end
    R.t_machine = mean(mt);
end

% ---- the Monte Carlo ----------------------------------------------------
rs   = RandStream('twister', 'Seed', o.Seed);
draw = P.OP.samples(randi(rs, numel(P.OP.samples), 1, o.N));
cyc  = R.t_machine + draw;

R.N          = o.N;
R.samples    = P.OP.samples;
R.predicted  = struct('mean', mean(cyc), 'median', median(cyc), ...
                      'sd', std(cyc), 'min', min(cyc), 'max', max(cyc), ...
                      'p05', prctile(cyc,5), 'p95', prctile(cyc,95));

% ---- what the machine actually did --------------------------------------
% Six FULL real cycles. The seventh recorded cycle ran 194.3 s and is excluded
% upstream as not a full cycle; it is not dropped here to flatter the model.
R.observed_cycles = [70.220 70.517 75.425 79.710 89.968 90.241];
oc = R.observed_cycles;
R.observed = struct('mean', mean(oc), 'median', median(oc), ...
                    'sd', std(oc), 'min', min(oc), 'max', max(oc), 'n', numel(oc));

R.mean_gap_s = R.observed.mean - R.predicted.mean;
% Overlap of the two ranges, as a fraction of the observed range.
lo = max(R.predicted.min, R.observed.min);
hi = min(R.predicted.max, R.observed.max);
R.range_overlap_frac = max(0, hi-lo) / (R.observed.max - R.observed.min);

if o.Verbose
    fprintf('\n  OPERATOR-DRIVEN CYCLE TIME  (%d samples)\n  %s\n', o.N, repmat('=',1,60));
    fprintf('  machine time (constant)      %8.3f s   %s\n', R.t_machine, R.machine_time_source);
    fprintf('  end point, both sides        %s\n', R.end_point);
    fprintf('  operator dwell, n=%d          %s\n', numel(P.OP.samples), mat2str(P.OP.samples,5));
    fprintf('  %s\n', repmat('-',1,62));
    fprintf('  %-12s %9s %9s %9s %9s %9s\n','','mean','median','sd','min','max');
    fprintf('  %-12s %9.2f %9.2f %9.2f %9.2f %9.2f\n','PREDICTED', ...
            R.predicted.mean, R.predicted.median, R.predicted.sd, R.predicted.min, R.predicted.max);
    fprintf('  %-12s %9.2f %9.2f %9.2f %9.2f %9.2f\n','OBSERVED', ...
            R.observed.mean, R.observed.median, R.observed.sd, R.observed.min, R.observed.max);
    fprintf('  %s\n', repmat('-',1,62));
    fprintf('  mean gap        %+8.2f s   (the model is still this much too fast)\n', R.mean_gap_s);
    fprintf('  range overlap   %8.0f %% of the observed range\n', 100*R.range_overlap_frac);
    fprintf('  predicted 5-95%%  %8.2f .. %.2f s\n', R.predicted.p05, R.predicted.p95);
    fprintf('  %s\n\n', repmat('=',1,60));
    fprintf(['  READ THIS BEFORE QUOTING THE SPREAD. The predicted sd is not a\n' ...
             '  prediction - it is the measured operator spread arriving intact\n' ...
             '  at the far end, because the model adds a CONSTANT to a sampled\n' ...
             '  dwell. It shows the model no longer claims zero variance. It\n' ...
             '  does NOT show the model can predict variability it was not\n' ...
             '  given: machine-time variance is still modelled as exactly zero,\n' ...
             '  and the real cell varied 61.25-63.24 s there.\n\n']);
end
end
