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
%   REFERENCE FIGURES (dt = 5e-4, 8 Sep 2026, second re-baseline of the day)
%   RE-BASELINED TO THE MEASURED CELL. Ten real cycles came back from the
%   machine's own history database, and three things in this model were set
%   from them for the first time: the SUPPLY PRESSURE (4.3 bar gauge, not the
%   assumed 6.0), and two of the machine's own SEQUENCER DWELLS, plus a third
%   on weaker evidence. FACTORYPARAMS section 13L is the account.
%       cycle time            70.370 s      (was 63.160)
%       machine time          57.870 s      (was 50.660)
%       final workpiece       (1.509274, 0.200000) m
%       position error        0.73 mm       (was 0.82)
%       peak chamber A        5.31 bar abs  (was 7.01 - the regulator dropped)
%       peak chamber B        5.46 bar abs  (was 7.24)
%       air per cycle         6.41 normal litres  (was 8.44 - less pressure,
%                             less mass for the same swept volume)
%       state transitions     39, watchdog timeouts 0
%
%   WHAT MOVED AND WHY. Two independent causes, and they push opposite ways on
%   the air and the same way on the clock.
%
%   THE PRESSURE. The cell runs 4.03-4.38 bar gauge across 37 samples, and all
%   four regulator faces read 4.3. The model assumed 5.5 bar absolute at the
%   receiver and regulated to 6.0 bar gauge. Lower supply means lower force,
%   slower rods and less air per stroke - which is why peak chamber pressures
%   fell by 1.7 bar and air fell 24 %. It also broke a hidden coupling on the
%   first attempt: P.P_br_rdy was a free-standing 5.5e5 Pa ABSOLUTE, above the
%   new 5.32e5 set point, so BR_RDY could never become true and the cycle
%   stalled against the horizon having moved 0.756 NL. It is now a FRACTION of
%   the regulated supply, which is what it always meant.
%
%   THE DWELLS, and this is the larger half. The machine's PLC has NO CYLINDER
%   POSITION FEEDBACK anywhere in its 158 tags, so when it holds cylinder A's
%   extend coil for 8.059 s it is not waiting for the rod - it cannot see the
%   rod. It is running a timer. The model advanced the instant its own modelled
%   reed switch closed, at 2.72 s, and lost the difference every cycle. Three
%   measured dwells are now in the sequencer: cylinder A's hold (n=7, stdev
%   0.078 s), the T#5S outfeed pulse (n=10, stdev 0.077 s), the FC6 N4
%   transfer wait (n=1) and FC7 N2's dispense TON (n=1).
%
%   THE TEMPTATION THAT WAS REFUSED, because it would have produced the right
%   cycle time for the wrong reason: closing the meter-out needle until the
%   modelled rod itself took 8 s. That models a slow rod where the machine has
%   a fast rod and a wait, and it would have silently mis-set a commissioning
%   value that is still unmeasured.
%
%   AGAINST THE MACHINE. Measured machine time is 64.03 s over six full real
%   cycles (61.25-73.99 s). This model is now 57.870 s - a gap of 1.11x, from
%   1.26x, 1.69x and 3.4x three days ago. FIVE measured dwells are now in the
%   sequencer and the engraver-to-belt-3 move is on the barrel that actually
%   makes it; 13M accounts for the remaining 6 s.
%   [NOT LIKE FOR LIKE - corrected 2026-09-12, plan H1. The recorder stops
%   its clock when the last outfeed push STARTS (S37); 57.870 s runs on
%   through that push and its retract. To S37 the model's machine time is
%   52.200 s, so the gap is 1.23x and about 12 s, not 6. The 'cycle to S37'
%   row below pins it.]
%   [H2, 2026-09-12: the T#10S start delay. Cycle 70.370 -> 78.020 s, to
%   S37 64.700 -> 72.350 s, machine time to S37 52.200 -> 59.850 s against
%   the measured 64.03 s: 1.07x. Nothing else moved.]
%   [H3, 2026-09-12: belt 3 from the tape. Cycle 78.020 -> 76.550 s, to S37
%   72.350 -> 70.880 s, machine time to S37 58.380 s: 1.10x. Final x
%   1.509274 -> 1.289840 m, error 0.16 mm, air 6.303 NL.]
%   [H4, 2026-09-12: belt speeds 0.210 / 0.310 / 0.150 m/s. Cycle 76.550 ->
%   75.070 s, to S37 69.400 s, machine time to S37 56.900 s: 1.13x.]
%   [H5, 2026-09-12: belt 2 starts with the transfer push, belt 3 as
%   cylinder B releases. Cycle 75.070 -> 73.620 s, to S37 67.950 s, machine
%   time to S37 55.450 s: 1.15x. Final x 1.289700 m, error 0.30 mm.]
%   [H6, 2026-09-13: the 1.463 s wait before cylinder A. Cycle 73.620 ->
%   74.930 s, to S37 69.260 s, machine time to S37 56.760 s: 1.13x. Air
%   6.466 NL.]
%   [H7, 2026-09-13: nameplate bores and strokes on every barrel; the bin up
%   36.5 mm for SV12/SV13's 160 mm stroke. Cycle 74.930 -> 75.720 s, to S37
%   69.910 s, machine to S37 57.410 s: 1.12x. Air 9.573 NL, final (1.289833,
%   0.236501) m.]
%   [H8, 2026-09-13: room air 25 C, P.T_air 293.15 -> 298.15 K. Cycle 75.720
%   -> 75.650 s, to S37 69.850 s, machine to S37 57.350 s: 1.12x. Air 9.431 NL.]
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
R(end+1,:) = {'FRL set pressure',  (P.P_set-P.P_atm)/1e5, 4.3,   1e-6,  'bar g'};
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
% CHANGED 2026-09-08. CYL_B now reads 250 / 208.5 from ITS OWN geometry, and
% MOVE_TO_CV3 reads the same figures because it now BORROWS CYL_B's. The two
% rows swapped: the machine's transition log shows solenoid 11 never firing
% and cylinder B making the engraver-to-belt-3 move. The numbers are identical
% either way - it is the same 203.5 mm move - so this table changes only in
% WHICH row derives them and which borrows.
% CHANGED 2026-09-11. MOVE_TO_CV3 stops borrowing: it is the SV11 BYPASS and
% derives its own stroke from c2_byp -> c3_load, a 252.5 mm x-move, so it reads
% 300 / 257.5 - the figures cylinder B had for this same path in its
% 2026-09-02 bypass placement. The nameplate on SV11's barrel says A51, 160 mm,
% which cannot cover 252.5 mm: the schematic layout is too wide here, and that
% waits on the belt datums (FACTORY_ACTUATORS). CYL_B is unchanged.
% 2026-09-12 (plan H3): MOVE_TO_CV3 lands at belt 3's start (c3_byp), so its
% travel is 117.5 mm and 300 / 257.5 became 125 / 122.5. Outfeeds A and B
% moved along belt 3 but push the same distance into the bin.
%          mag1  mag2  mag3  mag4  mag5  xfer1 cylA  cylB  mvCV3 outA  outB
% 2026-09-13 (plan H7): the NAMEPLATE strokes - A51/A52 160 mm, A12/A28
% 300 - replace the derived ones; the switches stay at the layout's travel.
% The outfeeds' switch moved 191.5 -> 155.0 with the bin (INITIALIZE_FACTORY).
std_mm  = [160   160   160   160   160   160   300   300   160   160   160];
trip_mm = [87.5  87.5  87.5  87.5  87.5  112.5 257.5 208.5 122.5 155.0 155.0];
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
% 70.370 / 64.700 until 2026-09-12 (plan H2): the T#10S start delay adds
% 7.65 s at the front of the cycle and moves nothing else.
% 78.020 / 72.350 after H2; H3 (belt 3 from the tape) took 1.47 s off the
% belt-3 run and moved the bin, so the final x moved with it.
% 76.550 / 70.880 after H3; H4 (belt speeds) took 1.48 s off belts 1 and 2.
% 75.070 / 69.400 after H4; H5 (push and belt together) took 1.45 s off.
% 73.620 / 67.950 after H5; H6 (the wait before cylinder A) added 1.31 s.
% 74.930 / 69.260 after H6; H7 (nameplate bores and strokes) added 0.79 s.
% 75.720 / 69.910 after H7; H8 (room air 25 C) took 0.07 s off.
S(end+1,:) = {'cycle time',        LOG.cycle_time,        75.650,   0.05,  's'};
% To S37, where the recorder stops its clock (plan H1, 2026-09-12). The row
% above runs 5.67 s further, through the outfeed push and retract.
S(end+1,:) = {'cycle to S37',      LOG.cycle_time_rec,    69.850,   0.05,  's'};
S(end+1,:) = {'final workpiece x', LOG.blk_final(1),       1.289933, 2e-3, 'm'};
S(end+1,:) = {'final workpiece y', LOG.blk_final(2),       0.236502, 2e-3, 'm'};
S(end+1,:) = {'position error',    LOG.pos_error*1e3,      0.067,    2.0,  'mm'};
S(end+1,:) = {'peak chamber A',    max(LOG.PA(:))/1e5,     5.316,    0.15, 'bar'};
S(end+1,:) = {'peak chamber B',    max(LOG.PB(:))/1e5,     5.515,    0.15, 'bar'};
% Air was 6.413 until 2026-09-11. SV11 then took its own 300 mm stroke in place
% of CYL_B's borrowed 250 mm, and its idle rod-side chamber - charged every
% cycle from branch 3 - holds more air. Nothing else moved.
S(end+1,:) = {'air per cycle',     LOG.air_NL,             9.431,    0.30, 'NL'};
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
