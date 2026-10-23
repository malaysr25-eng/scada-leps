classdef CycleRegressionTest < matlab.unittest.TestCase
    %CYCLEREGRESSIONTEST  Full-cycle behaviour and pinned reference values.
    %
    %   Runs run_factory_simulation once and shares the result across the
    %   class. Two kinds of assertion live here:
    %
    %     BEHAVIOURAL  physical invariants that must hold for any valid
    %                  parameter set (completion, monotonic sequencing,
    %                  continuity, bounded pressure).
    %
    %     REFERENCE    values pinned to the validated Iteration-03 result.
    %                  These are EXPECTED to change when a parameter changes.
    %                  A failure here is a prompt to confirm the change was
    %                  intended and to re-baseline, not automatically a bug.
    %
    %   The reference values are the same ones verify_model.m checks, kept
    %   here so the figures survive as data in the test suite rather than
    %   only inside a report.
    %
    %   Runtime is roughly 20-40 s for the single shared run.
    %
    %   See also RUN_FACTORY_SIMULATION, VERIFY_MODEL.

    properties (Constant)
        % RE-BASELINED 2026-09-02 to the machine's ELEVEN pneumatic actuators.
        % The plant carried 5 spring-return cylinders; it now carries all 11
        % actuators on 13 coils, two of them double-solenoid.
        %
        % What moved, and why - because a re-baseline nobody can explain is
        % indistinguishable from a regression:
        %
        %   air per cycle  4.94 -> 5.90 NL, +19 %. THE HEADLINE. Six more
        %       rod-side chambers hang off the manifold and every one of them
        %       charges. This is the change; the rest follows from it.
        %   cycle time     31.030 -> 31.080 s, +0.05 s. Branch 1 now feeds six
        %       chambers instead of two, so it charges more slowly and the
        %       CHG / BR_RDY waits in S05 and S12 gate later.
        %   final x        1.509300 -> 1.509243 m, 57 um. Same locating stops,
        %       marginally different approach velocity into them.
        %   peak pressures essentially unmoved, as they must be: the same
        %       regulator feeds the same cylinders through the same orifices.
        %
        % The DOUBLE-SOLENOID valve model contributed none of this. A latching
        % valve driven by maintained coils produces the same spool trajectory
        % as a spring-return one, which was the argument for doing it this way.
        % The previous baseline is in git history and in ITERATION_LOG.md.
        %
        % MOVED AGAIN, later the same day, when the machine's owner said what
        % cylinder B is FOR: it fires when engraving is SKIPPED, so it is a
        % BYPASS and not the engraver-to-belt-3 transfer the model had assumed.
        % Solenoid 11 does that move. Reassigning it grew solenoid 11's stroke
        % from a borrowed 125 mm to its real 250 mm, and a bigger rod-side
        % chamber draws more air: 5.898 -> 6.041 NL, cycle 31.080 -> 31.090 s.
        % Same mechanism as the first shift, one actuator instead of six.
        %
        % AND ONCE MORE, when the owner added that cylinder B belongs to the
        % ENGRAVING MACHINE. It moved off the conveyor 2 end to the engraver
        % and stopped claiming a travel of its own, borrowing CYL_A's 300 mm.
        % 6.041 -> 6.094 NL, and the cycle came back to 31.080 s. Three
        % baselines in one day, every one of them a chamber volume changing.
        % RE-BASELINED AGAIN 2026-09-07, AND THIS TIME FROM A NAMEPLATE.
        % Every re-baseline above this line came from a structural decision
        % the project made about the plant. This one came from reading a label
        % on the machine: a barrel photographed at the cell reads A120323000 -
        % Janatics A12, bore 32, stroke 300 - so CYL_A carries 32 / 12 instead
        % of the [JAN] 20 / 8 it has had since Iteration 01.
        %
        %   air per cycle  6.094 -> 8.202 NL, +35 %. THE HEADLINE, and it is
        %       the same mechanism as every shift above: a chamber got bigger.
        %       CYL_A's cap-side area went 314.2 -> 804.2 mm^2, its annulus
        %       263.9 -> 691.2 mm^2, and the stroke did not change, so the
        %       barrel holds 2.6x the air it did.
        %   cycle time     31.080 -> 33.840 s, +2.76 s. Branch 2 charges a
        %       chamber 2.6x larger, so the CHG / BR_RDY waits gate later.
        %       Air is the change; the cycle time follows from it.
        %   final x        1.509224 -> 1.509179 m, 45 um. The locating stops
        %       are mechanical - a stronger cylinder arrives at the same stop.
        %   peak pressures UNMOVED to 3 mbar, as they must be: the same
        %       regulator through the same orifices. A bigger chamber changes
        %       how long it takes to fill, not what it fills to.
        %
        % The direction is worth noting, and worth discounting. The model was
        % 3.35x too fast against the real cell's ~62 s of machine time; it is
        % now 2.91x. About half of that came from the METER-OUT NEEDLE, not
        % the bore: P.C_ctrl_B is a [COMM] setting chosen for a bore-20
        % cylinder and it now vents a 2.6x larger annulus, so the extend
        % crawls at 0.098 m/s where the setting was picked for 0.20. See
        % FactoryParams 13J section 1B. The bore rests on its stroke agreeing
        % three ways, not on this. And it says nothing about the remaining
        % 2.91x - see FactoryParams 13I.
        % RE-BASELINED 2026-09-08 - the engraving axis (NEXT_STEPS F2).
        %   cycle time     33.840 -> 49.290 s, +15.45 s. The axis was a stiff
        %   position PID finishing its travel in 0.225 s; the machine JOGS it
        %   until a limit switch trips and takes 7.7-8.3 s EACH WAY in every
        %   recorded real cycle. Two travels per cycle, so about 15.5 s. The
        %   size of this was predicted before the change, not discovered after.
        %   air per cycle  8.202 -> 8.436 NL, +2.9 %. The platform carries the
        %   block for longer, so the axis holds against gravity for longer.
        %   Peak pressures did not move at all - the pneumatics are untouched.
        %   final x        1.509179 -> 1.509175 m, 4 um. Mechanical stops.
        %   P.t_max also went 45 -> 90 s: at 45 the cycle no longer fitted in
        %   the horizon and stalled in S34, which is the horizon stopping it
        %   rather than the plant.
        % RE-BASELINED AGAIN 2026-09-08, TO THE MEASURED CELL. Ten real
        % cycles came back from the machine's history database. Two changes,
        % both from measurement, neither tuned:
        %
        %   SUPPLY PRESSURE 6.0 -> 4.3 bar gauge. 37 samples read 4.03-4.38
        %       and all four regulator faces read 4.3. Peak chamber pressures
        %       fall 1.7 bar and air falls 24 % - less pressure is less mass
        %       for the same swept volume. This is the first time the
        %       pneumatic supply has been set from measurement.
        %   THREE SEQUENCER DWELLS, which the model had none of. The machine
        %       holds cylinder A's extend coil 8.059 s (n=7) and CANNOT SEE
        %       THE ROD - no cylinder position feedback exists in its 158
        %       tags - so it is timing, not waiting. Also the T#5S outfeed
        %       pulse (5.010 s, n=10) and the FC6 N4 transfer wait (2.124 s,
        %       n=1), and FC7 N2's dispense TON (2.021 s, n=1). Together
        %       they are most of the +13.87 s.
        %
        %   cycle time     49.290 -> 63.160 s
        %   machine time   36.790 -> 50.660 s, against a MEASURED 64.03 s
        %   air per cycle   8.436 ->  6.397 NL, DOWN - the pressure, not the
        %       dwells; a dwell costs time, not air
        %   position error  0.821 ->  0.726 mm, slightly better: a slower rod
        %       arrives at the same mechanical stop with less overshoot
        %
        % The gap to the real cell is now 1.26x, from 1.69x and 3.4x. What was
        % NOT done is worth recording: the obvious way to make cylinder A take
        % 8 s is to close the meter-out needle until the modelled rod is that
        % slow. That would be the right cycle time for the wrong reason - a
        % slow rod where the machine has a fast rod and a wait.
        % RE-BASELINED 2026-09-08, third time today - NEXT_STEPS F3, the
        % engraver-to-belt-3 move. The machine's transition log shows
        % solenoid 11 NEVER FIRING in a real cycle - it does not appear once -
        % while cylinder B's coils rise at 80.751 s and 88.950 s, held 8.199 s,
        % exactly in that slot. So the role and the geometry moved to CYL_B and
        % a fifth measured dwell went in with them.
        %
        %   cycle time     63.160 -> 70.370 s
        %   machine time   50.660 -> 57.870 s, against a MEASURED 64.03 s
        %   gap            1.26x -> 1.11x
        %                  [NOT LIKE FOR LIKE - corrected 2026-09-12: 1.23x
        %                  at the recorder's end point. See REF_CYCLE_TIME_REC.]
        %   air per cycle   6.397 ->  6.413 NL
        %
        % The role swap ALONE moved the cycle 0.01 s, which is the useful part:
        % the geometry was already right and only the actuator was wrong, so
        % the 7.21 s is the DWELL, not the reassignment. Doing the swap first
        % is what let the dwell attach to the barrel that really makes the move.
        % RE-BASELINED 2026-09-12 - plan H2, the T#10S start delay. The model
        % spent the start charging the receiver to P_ready (2.38 s), a
        % threshold the real supply never reaches. The machine waits 10 s
        % from CMD_START and checks no pressure (cmd_start -> SV1 9.99-10.20 s,
        % n=5). S03 now holds for P.PLC.t_start_delay; SV1 fires at 10.17 s.
        %
        %   cycle time        70.370 -> 78.020 s   (+7.65 s, all at the front)
        %   cycle to S37      64.700 -> 72.350 s
        %   machine to S37    52.200 -> 59.850 s, against a MEASURED 64.03 s
        %   gap               1.23x  -> 1.07x
        %   air, pressures, final position, transitions: UNMOVED. The wait is
        %   dead time: the receiver sits at cut-out and nothing moves.
        % RE-BASELINED AGAIN 2026-09-12 - plan H3, belt 3 from the tape. The
        % outfeed (SV12, PX09, the end stop, the bin) moved from 65 cm to the
        % measured 43 cm along belt 3, SV13 went downstream of it, and SV11 now
        % lands at the belt's start, so its stroke fell 300 -> 125 mm.
        %
        %   cycle time        78.020 -> 76.550 s   (belt-3 run 3.10 -> 1.64 s)
        %   cycle to S37      72.350 -> 70.880 s
        %   machine to S37    59.850 -> 58.380 s, against a MEASURED 64.03 s
        %   gap               1.07x  -> 1.10x: FURTHER from the machine, and
        %                     correctly. Belt 3 was too long, so fixing it
        %                     makes the model faster. The rest is H4-H6.
        %   final x           1.509274 -> 1.289840 m: the bin is under the
        %                     tape's outfeed A
        %   position error    0.726 -> 0.160 mm
        %   air per cycle     6.452 -> 6.303 NL: SV11's idle rod side shrank
        %   pressures, transitions: unmoved
        % RE-BASELINED AGAIN 2026-09-12 - plan H4, belt speeds. Belt 1 runs at
        % 0.210 m/s (recorded sensor pitches, 4 cycles) and belt 2 at 0.310
        % (tape); belt 3 stays at the assumed 0.150.
        %
        %   cycle time        76.550 -> 75.070 s
        %   belt-1 run         4.22  ->  3.15 s   (recorded 3.08 s, n=4: WITHIN C3)
        %   belt-2 run         1.39  ->  0.98 s   (recorded 2.70 s: further out.
        %                     The model's block rides 220 mm of belt 2; the real
        %                     one rides px6 -> px7, 45 cm. That is the transfer
        %                     geometry, H5, not the speed.)
        %   machine to S37    58.380 -> 56.900 s, against a MEASURED 64.03 s: 1.13x
        %   position, pressures, transitions: unmoved; air 6.303 -> 6.301
        % RE-BASELINED AGAIN 2026-09-12 - plan H5, push and belt together. In
        % every recorded cycle conveyor 2 starts in the same sample as the
        % transfer push (SV6), and conveyor 3 in the same sample as cylinder
        % B's retract (SV10). The model finished each push first.
        %
        %   cycle time        75.070 -> 73.620 s
        %   px6 -> belt 2 on   3.14  ->  2.140 s   (recorded 2.123)
        %   B -> belt 3 on     8.90  ->  8.210 s   (recorded 8.199)
        %   machine to S37    56.900 -> 55.450 s, against a MEASURED 64.03 s: 1.15x
        %   final x 1.289840 -> 1.289700 m, error 0.160 -> 0.300 mm: the block
        %   now lands on a moving belt 3; air 6.301 -> 6.293 NL
        % RE-BASELINED 2026-09-13 - plan H6, the wait before cylinder A. The
        % machine fires SV7 1.312-1.584 s after conveyor 2 stops (n=7), when
        % its conveyor-2 axis finishes a position move. The model spent 0.17 s
        % there; S18 now waits the measured mean, 1.463 s.
        %
        %   cycle time        73.620 -> 74.930 s   (conv 2 off -> SV7 1.480 s)
        %   machine to S37    55.450 -> 56.760 s, against a MEASURED 64.03 s: 1.13x
        %   air per cycle     6.293 -> 6.466 NL: the wait holds branch 2
        %                     selected 1.46 s longer (observed, not traced)
        %   position, transitions: unmoved; peak B 5.461 -> 5.448 bar
        % RE-BASELINED 2026-09-13 - plan H7, nameplate bores and strokes. Every
        % barrel now carries its label: A51/A52 25 / 160, A28 (cylinder B) and
        % A12 (cylinder A) 32 / 300. Strokes are the STAMPED ones (a new
        % stroke_mm column), and the bin moved up 36.5 mm so SV12/SV13's 160 mm
        % stroke reaches its switch.
        %
        %   cycle time        74.930 -> 75.720 s
        %   machine to S37    56.760 -> 57.410 s, against a MEASURED 64.03 s: 1.12x
        %   air per cycle     6.466 -> 9.573 NL, +48 %: every chamber is larger
        %   final position    (1.289700, 0.200000) -> (1.289833, 0.236501) m:
        %                     the bin moved; error 0.300 -> 0.167 mm
        %   peak B            5.461 -> 5.516 bar; transitions unmoved
        % RE-BASELINED 2026-09-13 - plan H8, room air 25 C measured at the cell
        % (P.T_air 293.15 -> 298.15 K, [ASM] -> [MEAS]).
        %
        %   cycle time        75.720 -> 75.650 s
        %   machine to S37    57.410 -> 57.350 s: still 1.12x
        %   air per cycle     9.573 -> 9.431 NL: warmer air, less mass per fill
        %   error             0.167 -> 0.067 mm; peak B 5.516 -> 5.515 bar
        REF_CYCLE_TIME = 75.65;     % s
        % THE RECORDER'S END POINT, added 2026-09-12 (plan H1). The machine's
        % clock stops when the last outfeed push STARTS (S37). REF_CYCLE_TIME
        % runs on 5.67 s through that push and its retract, which the real
        % clock never counts. Compare THIS with a recording, never
        % REF_CYCLE_TIME. Machine time to here is 52.20 s against a measured
        % 64.03 s: 1.23x, not the 1.11x above. No physics moved.
        % [H2, the same day: 64.70 -> 72.35 s, machine 59.85 s, 1.07x.]
        % [H3, the same day: 72.35 -> 70.88 s, machine 58.38 s, 1.10x.]
        % [H4, the same day: 70.88 -> 69.40 s, machine 56.90 s, 1.13x.]
        % [H5, the same day: 69.40 -> 67.95 s, machine 55.45 s, 1.15x.]
        % [H6, 2026-09-13: 67.95 -> 69.26 s, machine 56.76 s, 1.13x.]
        % [H7, the same day: 69.26 -> 69.91 s, machine 57.41 s, 1.12x.]
        % [H8, the same day: 69.91 -> 69.85 s, machine 57.35 s, 1.12x.]
        REF_CYCLE_TIME_REC = 69.85; % s, S37 entry
        REF_BLK_X      = 1.289933;  % m
        REF_BLK_Y      = 0.236502;  % m  (0.200000 until H7 moved the bin)
        REF_POS_ERR_MM = 0.067;     % mm
        REF_PEAK_PA    = 5.316;     % bar
        REF_PEAK_PB    = 5.515;     % bar
        % 6.413 until 2026-09-11, when SV11 (the bypass) took its own 300 mm
        % stroke instead of CYL_B's borrowed 250: a bigger idle chamber on
        % branch 3. Cycle time, position and pressures did not move.
        % 6.452 -> 6.303 on 2026-09-12 (plan H3): that stroke fell to 125 mm.
        % 6.303 -> 6.301 with H4's belt speeds, the same day: noise.
        % 6.301 -> 6.293 with H5's overlap, the same day.
        % 6.293 -> 6.466 with H6's wait, 2026-09-13.
        % 6.466 -> 9.573 with H7's nameplate bores and strokes, the same day.
        % 9.573 -> 9.431 with H8's room air, the same day.
        REF_AIR_NL     = 9.431;     % normal litres
        REF_TRANSITIONS = 39;
    end

    properties
        LOG
        P
    end

    methods (TestClassSetup)
        function runCycle(tc)
            tc.LOG = run_factory_simulation();
            tc.P   = tc.LOG.P;
        end
    end

    methods (Test)

        % ---- behavioural ----------------------------------------------------

        function cycleCompletes(tc)
            tc.verifyTrue(logical(tc.LOG.complete), ...
                'the cycle did not reach S39_CYCLE_COMPLETE');
        end

        function noWatchdogTimeoutOccurs(tc)
            % Every state must be left via its guard, not its timeout. A
            % timeout means a physical condition never became true.
            tc.verifyEmpty(tc.LOG.plc.timeouts);
        end

        function stateIndexNeverDecreases(tc)
            % The sequence is strictly forward. A backward step means a guard
            % chattered and the machine re-entered a completed state.
            st = tc.LOG.state(:);
            tc.verifyTrue(all(diff(st) >= 0), ...
                'the PLC state index decreased during the run');
        end

        function everyStateIsEnteredAtMostOnce(tc)
            st = tc.LOG.state(:);
            ch = st([true; diff(st) ~= 0]);
            tc.verifyEqual(numel(ch), numel(unique(ch)), ...
                'a state was entered more than once');
        end

        function workpieceReachesTheBin(tc)
            d = norm(tc.LOG.blk_final - tc.LOG.blk_target);
            tc.verifyLessThan(d, 5e-3, ...
                'workpiece did not reach the bin within 5 mm');
        end

        function workpieceNeverTeleports(tc)
            % Continuity: displacement per logged sample must stay bounded.
            d = hypot(diff(tc.LOG.blk(:,1)), diff(tc.LOG.blk(:,2)));
            tc.verifyLessThan(max(d), 0.05, ...
                sprintf('max displacement per sample %.4f m is discontinuous', ...
                        max(d)));
        end

        function everyLoggedStateIsFinite(tc)
            tc.verifyTrue(all(isfinite(tc.LOG.blk(:))));
            tc.verifyTrue(all(isfinite(tc.LOG.PA(:))));
            tc.verifyTrue(all(isfinite(tc.LOG.PB(:))));
            tc.verifyTrue(all(isfinite(tc.LOG.P_res(:))));
        end

        function pressuresStayPositive(tc)
            tc.verifyGreaterThanOrEqual(min(tc.LOG.PA(:)),    0);
            tc.verifyGreaterThanOrEqual(min(tc.LOG.PB(:)),    0);
            tc.verifyGreaterThanOrEqual(min(tc.LOG.P_res(:)), 0);
        end

        function nothingExceedsTheCylinderRating(tc)
            % One-sided bound. Deliberately NOT expressed as a tolerance
            % around the rating: more margin must never count as a failure.
            % See the note in verify_model.m.
            peak  = max([tc.LOG.PA(:); tc.LOG.PB(:); tc.LOG.P_res(:)]);
            limit = tc.P.p_max + tc.P.P_atm;
            tc.verifyLessThan(peak, limit, ...
                sprintf('peak %.3f bar exceeds rating %.3f bar', ...
                        peak/1e5, limit/1e5));
        end

        function airConsumptionIsPositiveAndBounded(tc)
            tc.verifyGreaterThan(tc.LOG.air_NL, 0);
            tc.verifyLessThan(tc.LOG.air_NL, 100, ...
                'air consumption is implausibly large');
        end

        % ---- pinned reference values -----------------------------------------

        function cycleTimeMatchesReference(tc)
            tc.verifyEqual(tc.LOG.cycle_time, tc.REF_CYCLE_TIME, ...
                'AbsTol', 0.05, tc.rebaselineHint('cycle time'));
        end

        function recorderEndPointMatchesReference(tc)
            % The figure every comparison with the real cell must use.
            tc.verifyEqual(tc.LOG.cycle_time_rec, tc.REF_CYCLE_TIME_REC, ...
                'AbsTol', 0.05, tc.rebaselineHint('cycle time to S37'));
            % What it drops is the outfeed pulse and retract, and nothing else.
            tc.verifyEqual(tc.LOG.cycle_time - tc.LOG.cycle_time_rec, ...
                tc.REF_CYCLE_TIME - tc.REF_CYCLE_TIME_REC, 'AbsTol', 0.05, ...
                'the S37 -> S39 outfeed tail changed length');
        end

        function finalPositionMatchesReference(tc)
            tc.verifyEqual(tc.LOG.blk_final(1), tc.REF_BLK_X, ...
                'AbsTol', 1e-4, tc.rebaselineHint('final x'));
            tc.verifyEqual(tc.LOG.blk_final(2), tc.REF_BLK_Y, ...
                'AbsTol', 1e-4, tc.rebaselineHint('final y'));
        end

        function positionErrorMatchesReference(tc)
            tc.verifyEqual(1000*tc.LOG.pos_error, tc.REF_POS_ERR_MM, ...
                'AbsTol', 0.05, tc.rebaselineHint('position error'));
        end

        function peakPressuresMatchReference(tc)
            tc.verifyEqual(max(tc.LOG.PA(:))/1e5, tc.REF_PEAK_PA, ...
                'AbsTol', 0.05, tc.rebaselineHint('peak chamber A'));
            tc.verifyEqual(max(tc.LOG.PB(:))/1e5, tc.REF_PEAK_PB, ...
                'AbsTol', 0.05, tc.rebaselineHint('peak chamber B'));
        end

        function airPerCycleMatchesReference(tc)
            tc.verifyEqual(tc.LOG.air_NL, tc.REF_AIR_NL, ...
                'AbsTol', 0.30, tc.rebaselineHint('air per cycle'));
        end

        function transitionCountMatchesReference(tc)
            st = tc.LOG.state(:);
            n  = numel(st([true; diff(st) ~= 0]));
            tc.verifyEqual(n, tc.REF_TRANSITIONS, ...
                tc.rebaselineHint('transition count'));
        end

        % ---- agreement with the standalone verifier ---------------------------

        function verifyModelAgrees(tc)
            % verify_model.m is the project's own acceptance check. Running it
            % here means the two cannot drift apart: if verify_model is
            % re-baselined and this suite is not, one of them fails.
            tc.verifyTrue(logical(verify_model('Verbose', false)), ...
                'verify_model reported a failure');
        end

    end

    methods (Access = private)
        function msg = rebaselineHint(~, what)
            msg = sprintf(['%s differs from the pinned Iteration-03 ' ...
                'baseline. If a parameter was changed deliberately, confirm ' ...
                'the new value is correct and update the REF_ constants in ' ...
                'CycleRegressionTest AND the reference table in ' ...
                'verify_model.m together.'], what);
        end
    end
end
