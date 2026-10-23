classdef ProcessViewTest < matlab.unittest.TestCase
    %PROCESSVIEWTEST  The per-process 2-D view, VISUALIZE_PROCESSES.
    %
    %   The load-bearing assertion here is coverage: the process table must
    %   partition ALL 40 PLC states with no gap and no overlap. A gap means a
    %   process silently missing from the "end to end" claim; an overlap means
    %   the same motion counted twice. Neither is visible by looking at the
    %   figure, which is exactly why it is tested.
    %
    %   One shared simulation run, about 17 s.
    %
    %   See also VISUALIZE_PROCESSES, RUN_FACTORY_SIMULATION.

    properties
        LOG
        T
    end

    methods (TestClassSetup)
        function runOnce(tc)
            reset_factory('Quiet', true);
            % Deliberately through FACTORY_LOG rather than calling the driver
            % directly: it is the path real use takes, and it warms the cache
            % the lifecycle tests below then reuse for free.
            tc.LOG = factory_log();
            tc.T   = visualize_processes(tc.LOG);
        end
    end

    methods (TestClassTeardown)
        function shut(~)
            close all force
        end
    end

    methods (Test)

        % ---- the LOG carries what the view needs ----------------------------

        function theLogCarriesTheForceBreakdown(tc)
            for f = {'F_rod','F_stop','F_fric','F_net','belt_v','reg'}
                tc.verifyTrue(isfield(tc.LOG, f{1}), ...
                    sprintf('LOG is missing %s', f{1}));
            end
            n = numel(tc.LOG.t);
            tc.verifySize(tc.LOG.F_net, [n 2]);
        end

        function loggedForcesSumAndMatchTheLoggedAcceleration(tc)
            L = tc.LOG;
            tc.verifyEqual(L.F_rod + L.F_stop + L.F_fric, L.F_net, 'AbsTol', 0, ...
                'logged breakdown does not sum to the logged net force');
            tc.verifyEqual(L.P.blk_m*L.blk_a, L.F_net, 'AbsTol', 1e-9, ...
                'logged net force is not mass times logged acceleration');
        end

        % ---- process table coverage -----------------------------------------

        function everyPlcStateBelongsToExactlyOneProcess(tc)
            nS    = size(factory_states(), 1);
            count = zeros(1, nS);
            for i = 1:height(tc.T)
                r = sscanf(tc.T.States{i}, '%d-%d');
                count(r(1):r(2)) = count(r(1):r(2)) + 1;
            end
            gaps = find(count == 0);
            dups = find(count > 1);
            tc.verifyEmpty(gaps, sprintf(...
                'states covered by NO process: %s', mat2str(gaps)));
            tc.verifyEmpty(dups, sprintf(...
                'states covered by MORE THAN ONE process: %s', mat2str(dups)));
        end

        function theProcessesRunInOrderAndAreContiguous(tc)
            last = 0;
            for i = 1:height(tc.T)
                r = sscanf(tc.T.States{i}, '%d-%d');
                tc.verifyEqual(r(1), last+1, sprintf(...
                    'process %d starts at %d, expected %d', i, r(1), last+1));
                tc.verifyGreaterThanOrEqual(r(2), r(1));
                last = r(2);
            end
            tc.verifyEqual(last, size(factory_states(),1), ...
                'the last process does not end at the last PLC state');
        end

        % ---- the numbers it reports -----------------------------------------

        function everyProcessWasReached(tc)
            % A zero duration would mean the cycle never entered that process.
            tc.verifyGreaterThan(tc.T.Duration_s, 0, ...
                'some process was never entered');
        end

        function durationsAccountForTheWholeCycle(tc)
            % The processes partition the states, so their durations should
            % add up to the cycle, bar one logging interval per boundary.
            tol = 0.05 * height(tc.T);
            tc.verifyEqual(sum(tc.T.Duration_s), tc.LOG.cycle_time, ...
                'AbsTol', tol);
        end

        function transportProcessesReachTheBeltSetpoint(tc)
            % A belt-driven process must peak at the commanded belt speed. If
            % it does not, the part is slipping and the friction model or the
            % drive has changed.
            isBelt = contains(tc.T.Mechanism, 'belt friction');
            tc.verifyNotEmpty(find(isBelt, 1), 'no belt-driven process found');
            tc.verifyEqual(tc.T.PeakSpeed_ms(isBelt), ...
                repmat(tc.LOG.P.v_belt, nnz(isBelt), 1), 'RelTol', 0.01, ...
                'a belt-driven process did not reach the belt setpoint');
        end

        function pneumaticProcessesDevelopRealContactForce(tc)
            isPush = contains(tc.T.Mechanism, 'pneumatic');
            tc.verifyNotEmpty(find(isPush, 1), 'no pneumatic process found');
            % The floor used to be a hard-coded 1 N, sized against the
            % drawing's 0.583 kg cube. The measured workpiece is 0.300 g and
            % pushes peak at ~0.02 N, so that constant failed the moment the
            % real part arrived - it was measuring the old workpiece, not the
            % physics. Tie it to the part instead: a push that cannot beat
            % static friction could not move anything, whatever the part
            % weighs.
            Ffric = tc.LOG.P.mu_s * tc.LOG.P.blk_m * tc.LOG.P.g;
            tc.verifyGreaterThan(tc.T.PeakForce_N(isPush), Ffric, ...
                'a pneumatic push developed less force than static friction');
            tc.verifyLessThan(tc.T.PeakForce_N(isPush), ...
                tc.LOG.P.JAN.CYL.F_ext_6bar, ...
                'a push exceeded the cylinder theoretical output at 6 bar');
        end

        % ---- the cached LOG -------------------------------------------------
        %
        % factory_log removed this project's commonest error, an undefined LOG,
        % by letting the viewers fetch or produce a result themselves.

        function factoryLogCachesSoTheSecondCallIsFree(tc)
            % The cache is already warm from setup, so this must be instant.
            t = tic; L = factory_log(); dt = toc(t);
            tc.verifyLessThan(dt, 1, 'a cached factory_log call took over a second');
            tc.verifyEqual(L, tc.LOG, 'the cached LOG changed between calls');
        end

        function factoryLogReportsWhetherAResultIsCached(tc)
            tc.verifyTrue(factory_log('has'), 'setup warmed the cache');
        end

        function factoryLogRejectsAnUnknownAction(tc)
            tc.verifyError(@() factory_log('wibble'), 'factory_log:action');
        end

        function theViewersNeedNoArgument(tc)
            % The whole point of factory_log. These must not error on a bare
            % call, which is what a reader pasting from factory_help does.
            T2 = visualize_processes;
            tc.verifyEqual(height(T2), height(tc.T));
            tc.verifyWarningFree(@() plot_factory_results);
            close all force
        end

        function theCacheLifecycleEndsWithResetFactoryClearingIt(tc)
            % Declared LAST on purpose: it leaves the cache cold, and the one
            % repopulation it forces costs a simulation. Nothing after it needs
            % a warm cache.
            factory_log('clear');
            tc.verifyFalse(factory_log('has'), '''clear'' did not clear');
            L = factory_log();                       % repopulates, ~17 s
            tc.verifyTrue(factory_log('has'), 'a call did not populate the cache');
            tc.verifyEqual(L.cycle_time, tc.LOG.cycle_time, 'RelTol', 1e-12, ...
                'a rebuilt LOG differs from the original');
            reset_factory('Quiet', true);
            tc.verifyFalse(factory_log('has'), ...
                'reset_factory must clear the cached LOG - a parameter edit does not');
        end

        % ---- interface ------------------------------------------------------

        function itRejectsALogWithoutForces(tc)
            bare = rmfield(tc.LOG, 'F_net');
            tc.verifyError(@() visualize_processes(bare), ...
                'visualize_processes:noForces');
        end

        function aSingleProcessCanBeDrawnAlone(tc)
            tc.verifyWarningFree(@() visualize_processes(tc.LOG, 'Process', 3));
        end

        function anOutOfRangeProcessIsRejected(tc)
            % validateattributes throws MATLAB:<fname>:notLessEqual, not the
            % arguments-block 'MATLAB:validators:...' form.
            tc.verifyError(@() visualize_processes(tc.LOG, 'Process', 99), ...
                'MATLAB:visualize_processes:notLessEqual');
        end

        function drawingUnitsAreAccepted(tc)
            tc.verifyWarningFree(@() visualize_processes(tc.LOG, ...
                'Units', 'drawing', 'Forces', false));
        end

    end
end
