classdef ProcessViewTest < matlab.unittest.TestCase
    %PROCESSVIEWTEST  The per-process 2-D view, VISUALIZE_PROCESSES.
    %
    %   The load-bearing assertion here is coverage: the process table must
    %   partition every state of the ENGRAVED route, S00-S39, with no gap and
    %   no overlap. (The SV11 bypass, S40-S43, has a table of its own and is
    %   covered by BYPASSROUTETEST; this class runs the default route.) A gap means a
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
            ST    = factory_states();
            nS    = find(strcmp(ST(:,1), 'S39_CYCLE_COMPLETE'));   % engraved route
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
            ST = factory_states();
            tc.verifyEqual(last, find(strcmp(ST(:,1), 'S39_CYCLE_COMPLETE')), ...
                'the last process does not end at S39_CYCLE_COMPLETE');
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
            %
            % P.v_belt is PER CONVEYOR (1x3), because the machine carries one
            % pot_control.convN.set_velocity per axis. Each belt process is
            % therefore checked against ITS OWN setpoint, read out of the
            % process name, rather than against a single number. All three
            % were 0.150 when this was written. Since H4 (2026-09-12) they are
            % 0.210 / 0.310 / 0.150, which is the case this was written for.
            %
            % The belt window starts where the rod lets go of the part, not
            % where the belt is switched on. See PROCESS_TABLE in
            % VISUALIZE_PROCESSES. With the old 16-18 window this failed on
            % 2026-09-13 (H7): belt 2 had already delivered the part.
            isBelt = contains(tc.T.Mechanism, 'belt friction');
            tc.verifyNotEmpty(find(isBelt, 1), 'no belt-driven process found');
            names = tc.T.Process(isBelt);
            expect = zeros(numel(names), 1);
            for k = 1:numel(names)
                d = regexp(names{k}, 'Belt\s*(\d)', 'tokens', 'once');
                tc.assertNotEmpty(d, sprintf( ...
                    'belt process "%s" does not name its conveyor', names{k}));
                i = str2double(d{1});
                tc.assertTrue(i >= 1 && i <= numel(tc.LOG.P.v_belt), ...
                    sprintf('belt index %d is outside P.v_belt', i));
                expect(k) = tc.LOG.P.v_belt(i);
            end
            tc.verifyEqual(tc.T.PeakSpeed_ms(isBelt), expect, ...
                'RelTol', 0.01, ...
                'a belt-driven process did not reach its own belt setpoint');
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
            % THE CEILING IS THE RELIEF VALVE, not a catalogue figure.
            %
            % This bound was J.CYL.F_ext_6bar - a BORE-20 cylinder at 6 bar,
            % 169.6 N. It stopped describing this plant twice over: CYL_A
            % became bore 32 on 2026-09-07, and the supply became a measured
            % 4.3 bar on 2026-09-08. It then failed on a push of 367 N, which
            % is not a defect - CYL_A's steady output at 4.3 bar is 346 N and
            % the excess is the Hunt-Crossley contact transient as the rod
            % drives the block into its locating stop, which it now does for
            % 8 s instead of releasing immediately.
            %
            % Bound it by what the AIR SYSTEM can physically deliver instead:
            % the strongest actuator in the plant, at the relief valve's set
            % pressure. Supply cannot exceed the relief setting, so no
            % cylinder can ever beat this, and the check still catches a push
            % that is nonsense by an order of magnitude. It also follows the
            % plant: add a bigger bore and the ceiling moves with it.
            Amax  = max([tc.LOG.P.CYL.A_A]);
            Fceil = (tc.LOG.P.P_relief - tc.LOG.P.P_atm) * Amax;
            tc.verifyLessThan(tc.T.PeakForce_N(isPush), Fceil, ...
                'a push exceeded what the air system can deliver at relief pressure');
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
