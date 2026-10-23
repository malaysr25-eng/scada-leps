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
        REF_CYCLE_TIME = 31.08;     % s
        REF_BLK_X      = 1.509224;  % m
        REF_BLK_Y      = 0.200004;  % m
        REF_POS_ERR_MM = 0.776;     % mm
        REF_PEAK_PA    = 7.013;     % bar
        REF_PEAK_PB    = 7.239;     % bar
        REF_AIR_NL     = 6.094;     % normal litres
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
