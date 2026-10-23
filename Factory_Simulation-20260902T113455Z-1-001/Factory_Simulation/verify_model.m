function pass = verify_model(varargin)
%VERIFY_MODEL  Acceptance self-test against the validated reference numbers.
%
%   pass = VERIFY_MODEL()              parameters + full simulation
%   pass = VERIFY_MODEL('Quick', true) parameters only, no simulation
%
%   RUN THIS FIRST, BEFORE YOU TRUST ANY RESULT.
%
%   The physics in this project was validated by porting it to Python and
%   executing it there (validate_physics.py, janatics_physics.py), because
%   the environment it was written in had no MATLAB. The MATLAB files are
%   line-by-line transcriptions of that validated code. This function checks
%   the transcription: it runs the MATLAB model and compares it against the
%   numbers the Python reference produced.
%
%   If a check FAILS, the MATLAB is wrong, not the reference. Report the
%   failing line against Project_Notes/History/Iteration_03.md.
%
%   REFERENCE FIGURES (dt = 5e-4, 2 Sep 2026)
%   Re-baselined to the machine's ELEVEN pneumatic actuators on 13 coils, two
%   of them double-solenoid, replacing the model's 5 spring-return cylinders.
%   The workpiece re-baseline of 26 Aug (a 100 x 100 x 40 mm wooden block of
%   0.300 kg) still stands underneath it. Previous figures are in git history,
%   in Project_Notes/ITERATION_LOG.md and in History/Iteration_03.md.
%       cycle time            31.080 s      (was 31.030)
%       final workpiece       (1.509224, 0.200004) m
%       position error        0.78 mm       (was 0.70)
%       peak chamber A        7.01 bar abs
%       peak chamber B        7.24 bar abs
%       air per cycle         6.09 normal litres  (was 4.94 - SIX more
%                             rod-side chambers now charge off the manifold,
%                             and solenoid 11 grew from a borrowed 125 mm
%                             stroke to its real 250 mm once the owner said
%                             cylinder B is a bypass. Air is the change; the
%                             rest follows from it)
%       state transitions     39, watchdog timeouts 0
%
%   See also CHECK_ENVIRONMENT, RUN_FACTORY_SIMULATION.

o = struct('Quick', false, 'Verbose', true);
o = parse_options(o, varargin, mfilename);

R = {};   % {name, value, expected, tol, unit}

%% ---- A. parameters and derived geometry -------------------------------
P = initialize_factory(FactoryParams());

R(end+1,:) = {'bore',              P.D_bore*1e3,      20.0,      1e-6,  'mm'};
R(end+1,:) = {'rod diameter',      P.d_rod*1e3,        8.0,      1e-6,  'mm'};
R(end+1,:) = {'cap-side area A_A', P.A_A*1e6,        314.159265, 1e-4,  'mm^2'};
R(end+1,:) = {'rod-side area A_B', P.A_B*1e6,        263.893782, 1e-4,  'mm^2'};
R(end+1,:) = {'FRL set pressure',  (P.P_set-P.P_atm)/1e5, 6.0,   1e-6,  'bar g'};
R(end+1,:) = {'C supply',          P.C_sup*1e9,        9.1662,   1e-3,  'e-9'};
R(end+1,:) = {'C FRL/line',        P.C_dv*1e9,        17.0341,   1e-3,  'e-9'};
R(end+1,:) = {'C exhaust extend',  P.C_ctrl_B*1e9,     0.52929,  1e-5,  'e-9'};
R(end+1,:) = {'C exhaust retract', P.C_ctrl_A*1e9,     1.26020,  1e-5,  'e-9'};
R(end+1,:) = {'load-prop. loss',   P.f_loss,           0.10,     1e-9,  '-'};

% One row per actuator, in FACTORY_ACTUATORS order. The five the sequence
% drives - the selected magazine pusher, the transfer, CYL_A, CYL_B and the
% outfeed - hold EXACTLY the strokes and switch positions they had before the
% plant was widened, which is the check that the widening moved geometry
% nowhere. The four idle pushers repeat the selected one because they are the
% same cylinder at the same station; XFER_CV2_CV3 and OUTFEED_B repeat the
% actuator whose stroke they BORROW, which is what makes that [ASM] visible
% here rather than buried in the table.
% CYL_B and MOVE_TO_CV3 both read 250 / 208.5 because they make the SAME
% 203.5 mm y-move: cylinder B diverts conveyor 2 -> conveyor 3 past the
% engraver, solenoid 11 moves engraver -> conveyor 3. Corrected 2026-09-02 when
% the owner said what cylinder B is for; solenoid 11 previously borrowed the
% other transfer's 125 / 112.5 because nothing had placed it.
% CYL_B reads 300 / 257.5 because it BORROWS CYL_A's - it belongs to the
% engraving machine and the owner has not said what it moves or how far, so
% the model claims no travel for it. MOVE_TO_CV3 reads 250 / 208.5 from its
% own geometry, the engraver-to-belt-3 move that used to be attributed to
% cylinder B.
%          mag1  mag2  mag3  mag4  mag5  xfer1 cylA  cylB  mvCV3 outA  outB
std_mm  = [100   100   100   100   100   125   300   300   250   200   200];
trip_mm = [87.5  87.5  87.5  87.5  87.5  112.5 257.5 257.5 208.5 191.5 191.5];
if numel(std_mm) ~= P.NCYL
    error('verify_model:actuatorCount', ...
        ['The pinned stroke table has %d rows and the model has %d ' ...
         'actuators. Extend the table; do not shorten the loop.'], ...
        numel(std_mm), P.NCYL);
end
for c = 1:P.NCYL
    R(end+1,:) = {sprintf('%s standard stroke', P.CYL(c).name), ...
                  P.CYL(c).stroke*1e3, std_mm(c), 1e-6, 'mm'};   %#ok<AGROW>
    R(end+1,:) = {sprintf('%s switch position', P.CYL(c).name), ...
                  P.CYL(c).x_trip*1e3, trip_mm(c), 1e-6, 'mm'};  %#ok<AGROW>
end

% Catalogue cross-check: Janatics tabulates 142 N on the annulus side at
% 6 bar for a bore 20 / rod 8 cylinder. The model must reproduce that from
% first principles, not by storing it.
R(end+1,:) = {'annulus force at 6 bar (cat. 142 N)', ...
              0.90*6e5*P.A_B, 142.0, 1.0, 'N'};

R(end+1,:) = {'state vector length', P.NS, 81, 0, '-'};
R(end+1,:) = {'pneumatic actuators', P.NCYL, 11, 0, '-'};
R(end+1,:) = {'solenoid coils',      P.NSOL, 13, 0, '-'};
R(end+1,:) = {'solver step',         P.dt*1e3, 0.5, 1e-9, 'ms'};

if o.Quick
    pass = report(R, {}, o);
    return
end

%% ---- B. full simulation ------------------------------------------------
fprintf('Running the reference cycle (this takes a few minutes) ...\n');
LOG = run_factory_simulation('Plot', false, 'Verbose', false);

S = {};   % simulation results, wider tolerances
S(end+1,:) = {'cycle time',        LOG.cycle_time,        31.080,   0.05,  's'};
S(end+1,:) = {'final workpiece x', LOG.blk_final(1),       1.509224, 2e-3, 'm'};
S(end+1,:) = {'final workpiece y', LOG.blk_final(2),       0.200004, 2e-3, 'm'};
S(end+1,:) = {'position error',    LOG.pos_error*1e3,      0.776,    2.0,  'mm'};
S(end+1,:) = {'peak chamber A',    max(LOG.PA(:))/1e5,     7.013,    0.15, 'bar'};
S(end+1,:) = {'peak chamber B',    max(LOG.PB(:))/1e5,     7.239,    0.15, 'bar'};
S(end+1,:) = {'air per cycle',     LOG.air_NL,             6.094,    0.30, 'NL'};
S(end+1,:) = {'final PLC state',   LOG.plc.state,         40,        0,    '-'};
S(end+1,:) = {'watchdog timeouts', size(LOG.plc.timeouts,1), 0,      0,    '-'};
S(end+1,:) = {'state transitions', size(LOG.plc.log,1),   39,        0,    '-'};

% Nothing may exceed the cylinder's rated pressure.
%
% This is a ONE-SIDED bound, not a tolerance comparison, and it must be
% checked separately. R and S are compared with abs(val-exp) <= tol, which
% is symmetric: under that rule a peak pressure FURTHER below the rating --
% i.e. a larger safety margin -- counts as a larger deviation and fails.
% The check previously lived in S with tol = 3.0 bar and failed at
% |8.004 - 11.013| = 3.009, reporting a healthy 3 bar margin as a defect and
% printing "the MATLAB transcription is wrong". The physics was never at
% fault; the comparison was.
B = {};   % {name, value, limit, unit} -- passes when value < limit
B(end+1,:) = {'peak pressure vs rating', ...
              max([LOG.PA(:); LOG.PB(:); LOG.P_res(:)])/1e5, ...
              (P.p_max+P.P_atm)/1e5, 'bar'};

pass = report(R, S, B, o);
end

%% ========================================================================
function pass = report(R, S, B, o)
allr = [R; S];
pass = true;
if o.Verbose
    fprintf('\n  MODEL VERIFICATION\n  %s\n', repmat('=',1,72));
end
for i = 1:size(allr,1)
    if i == size(R,1)+1 && o.Verbose
        fprintf('  %s\n', repmat('-',1,72));
    end
    val = allr{i,2}; exp_ = allr{i,3}; tol = allr{i,4};
    ok  = abs(val - exp_) <= tol;
    pass = pass && ok;
    if o.Verbose
        fprintf('  %s %-38s %12.5f   ref %10.5f  %s\n', ...
                mark(ok), allr{i,1}, val, exp_, allr{i,5});
    end
end

% ---- one-sided bounds: pass when value is strictly below the limit ------
if ~isempty(B)
    if o.Verbose
        fprintf('  %s\n', repmat('-',1,72));
    end
    for i = 1:size(B,1)
        val = B{i,2}; lim = B{i,3};
        ok  = val < lim;
        pass = pass && ok;
        if o.Verbose
            fprintf('  %s %-38s %12.5f   lim %10.5f  %s (margin %.3f)\n', ...
                    mark(ok), B{i,1}, val, lim, B{i,4}, lim - val);
        end
    end
end
if o.Verbose
    fprintf('  %s\n', repmat('=',1,72));
    if pass
        fprintf(['  ALL CHECKS PASS. The MATLAB model reproduces the ' ...
                 'validated reference.\n\n']);
    else
        fprintf(['  ONE OR MORE CHECKS FAILED. The MATLAB transcription is ' ...
                 'wrong, not\n  the reference. Do not use the results. ' ...
                 'See Project_Notes/History/Iteration_03.md.\n\n']);
    end
end
end

function m = mark(ok)
if ok; m = '[ok]'; else; m = '[XX]'; end
end
