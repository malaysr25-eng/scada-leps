classdef BypassRouteTest < matlab.unittest.TestCase
    %BYPASSROUTETEST  The SV11 bypass route, P.engrave_selected = false.
    %
    %   The maintainer, 2026-09-11, verbatim:
    %       "CYLINDER b FIRES WHEN ENGRAVING IS DONE AND IT PUSHES BLOCK TO
    %        BELT 3, SV11 FIRES WHEN ENGRAVING IS SKIPPED"
    %   The engraved route is CYCLEREGRESSIONTEST's. This class is the other.
    %
    %   It asserts BEHAVIOUR and pins no numbers. No bypass cycle has ever been
    %   recorded on the real cell, so a pinned bypass cycle time would pin the
    %   model to itself. What must hold regardless:
    %     - the route is the one FACTORY_STATES describes, in that order
    %     - SV11 extends; cylinders A and B stay home; the platform stays down
    %     - the block still reaches the bin, through the same outfeed
    %   plus the static facts that make it a route: where the two belt-2
    %   sensors sit, which belt-2 locating stop exists on each route, and
    %   which barrel is the bypass.
    %
    %   One shared simulation run, about 15 s.
    %
    %   See also FACTORY_PLC, FACTORY_STATES, CYCLEREGRESSIONTEST.

    properties
        LOG     % the bypass run
        P       % its parameters
        Pe      % the engraved-route parameters, for the static comparisons
        ST
    end

    methods (TestClassSetup)
        function runBypass(tc)
            Q = FactoryParams();
            Q.engrave_selected = false;
            tc.LOG = run_factory_simulation('Params', Q, 'Plot', false, ...
                                            'Verbose', false);
            tc.P   = tc.LOG.P;
            tc.Pe  = initialize_factory(FactoryParams());
            tc.ST  = factory_states();
        end
    end

    methods (Access = private)
        function k = idx(tc, name)
            k = find(strcmp(tc.ST(:,1), name));
        end
        function got = entered(tc)
            % The PLC's own transition log: every state entered, S01 onward.
            % LOG.state is sampled AFTER the first scan, so it never shows S00
            % and would make an expected list off by one at its start.
            got = tc.LOG.plc.log(:,2);
            got = got(:);
        end
    end

    methods (Test)

        % ---- the run ---------------------------------------------------------

        function cycleCompletes(tc)
            tc.verifyTrue(logical(tc.LOG.complete), ...
                'the bypass cycle did not reach S39_CYCLE_COMPLETE');
        end

        function noWatchdogTimeoutOccurs(tc)
            tc.verifyEmpty(tc.LOG.plc.timeouts, ...
                'a bypass state was left by its watchdog, not its guard');
        end

        function theRouteIsTheBypassInOrder(tc)
            % S01..S16, then S40..S43, then back into S33..S39.
            n    = tc.ST(:,1);
            want = [n(tc.idx('S01_CAMERA_DETECT'):tc.idx('S16_PROX3_CHECK')); ...
                    n(tc.idx('S40_BYP_CONV2_STOP'):tc.idx('S43_BYP_SV11_RETRACT')); ...
                    n(tc.idx('S33_CONV3_START'):tc.idx('S39_CYCLE_COMPLETE'))];
            tc.verifyEqual(tc.entered(), want, ...
                'the bypass run did not walk S01-S16, S40-S43, S33-S39');
        end

        function noEngravingStateIsEntered(tc)
            skipped = tc.ST(tc.idx('S17_CONV2_STOP'):tc.idx('S32_S3A1_RETRACT'), 1);
            hit = intersect(tc.entered(), skipped);
            tc.verifyEmpty(hit, sprintf( ...
                'the bypass entered engraved-route states: %s', ...
                strjoin(hit(:)', ', ')));
        end

        function theBypassHasNoOperatorTime(tc)
            % No engraving, so no operator: machine time is the whole cycle.
            tc.verifyEqual(tc.LOG.time_operator, 0, ...
                'the bypass run charged operator time it never spends');
            tc.verifyEqual(tc.LOG.time_engrave, 0);
        end

        function theProcessViewCoversTheBypassRoute(tc)
            % VISUALIZE_PROCESSES picks the bypass table for a bypass LOG. Its
            % processes must all be reached and must add up to the cycle, the
            % same checks PROCESSVIEWTEST makes of the engraved route.
            T = visualize_processes(tc.LOG);
            close all force
            tc.verifyTrue(any(strcmp(T.Process, 'SV11 bypass to belt 3')), ...
                'the process view has no SV11 bypass process');
            tc.verifyGreaterThan(T.Duration_s, 0, ...
                'a process of the bypass view was never entered');
            tc.verifyEqual(sum(T.Duration_s), tc.LOG.cycle_time, ...
                'AbsTol', 0.05 * height(T));
        end

        function sv11ExtendsAndCylindersAandBStayHome(tc)
            P = tc.P;
            b = P.ACT.bypass;
            tc.verifyGreaterThanOrEqual(max(tc.LOG.rod(:, b)), ...
                P.CYL(b).x_trip - 2e-3, 'SV11 never reached its reed switch');
            tc.verifyLessThan(max(tc.LOG.rod(:, P.ACT.eng_in)), 1e-3, ...
                'cylinder A moved on the bypass route');
            tc.verifyLessThan(max(tc.LOG.rod(:, P.ACT.eng_out)), 1e-3, ...
                'cylinder B moved on the bypass route');
        end

        function thePlatformNeverMoves(tc)
            tc.verifyLessThan(max(abs(tc.LOG.base_z)), tc.P.z_tol, ...
                'the engraving platform moved on the bypass route');
        end

        function workpieceReachesTheBin(tc)
            d = norm(tc.LOG.blk_final - tc.LOG.blk_target);
            tc.verifyLessThan(d, 5e-3, ...
                'the bypassed workpiece did not reach the bin within 5 mm');
        end

        function theBypassIsShorterThanTheEngravedCycle(tc)
            % It skips cylinder A's hold, the platform both ways, the operator
            % and cylinder B's hold. If it is not shorter, it is not a bypass.
            tc.verifyLessThan(tc.LOG.cycle_time, ...
                CycleRegressionTest.REF_CYCLE_TIME, ...
                'the bypass cycle is not shorter than the engraved one');
        end

        % ---- the static facts that make it a route ----------------------------

        function theBeltTwoSensorsSitWhereEachRouteStops(tc)
            Pe = tc.Pe;
            tc.verifyEqual(Pe.PROX_GUARD(3), 7, ...
                'the engraved route must stop belt 2 on prox 7 (FC7 N5)');
            tc.verifyEqual(Pe.PROX_BYPASS, 8, ...
                'the bypass must stop belt 2 on prox 8 (FC6 N5)');
            tc.verifyEqual(Pe.PROX(7,:), Pe.WP.c2_end, 'AbsTol', 1e-12, ...
                'prox 7 is not at the cylinder A line');
            tc.verifyEqual(Pe.PROX(8,:), Pe.WP.c2_byp, 'AbsTol', 1e-12, ...
                'prox 8 is not at the SV11 pickup');
            % An engraved block, held at c2_end, must be out of prox 8's
            % range, or the recording's "an engraved block never trips px8"
            % would not hold in the model.
            tc.verifyGreaterThan(norm(Pe.WP.c2_byp - Pe.WP.c2_end), ...
                Pe.prox_rng + Pe.blk_W, ...
                'prox 8 is close enough to c2_end to see an engraved block');
        end

        function eachRouteHasItsOwnBeltTwoStop(tc)
            ne = {tc.Pe.STOP.name};
            nb = {tc.P.STOP.name};
            tc.verifyTrue(any(strcmp(ne, 'C2_end_stop')) && ...
                          ~any(strcmp(ne, 'C2_byp_stop')), ...
                'the engraved route must have C2_end_stop and not C2_byp_stop');
            tc.verifyTrue(any(strcmp(nb, 'C2_byp_stop')) && ...
                          ~any(strcmp(nb, 'C2_end_stop')), ...
                'the bypass must have C2_byp_stop and not C2_end_stop');
            tc.verifyNumElements(ne, 7, ...
                'the engraved route must keep exactly its seven stops');
        end

        function theBypassBarrelIsSolenoid11AndBIsTheEngravedExit(tc)
            Pe = tc.Pe;
            c = Pe.CYL(Pe.ACT.bypass);
            tc.verifyEqual(c.name, 'MOVE_TO_CV3');
            tc.verifyEqual(c.coil_ext, 11, 'the bypass is not solenoid 11');
            tc.verifyFalse(logical(c.dbl), 'SV11 is a spring-return valve');
            tc.verifyTrue(logical(c.placed), 'SV11 has no position');
            tc.verifyEqual({c.axis, c.dir}, {'x', 1}, 'SV11 must push +x');
            b = Pe.CYL(Pe.ACT.eng_out);
            tc.verifyEqual({b.name, b.coil_ext, b.coil_ret}, {'CYL_B', 9, 10}, ...
                'cylinder B must stay the engraver -> belt 3 actuator');
        end

    end
end
