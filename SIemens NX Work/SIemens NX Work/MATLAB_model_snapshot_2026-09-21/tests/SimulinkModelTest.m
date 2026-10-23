classdef SimulinkModelTest < matlab.unittest.TestCase
    %SIMULINKMODELTEST  Build and run Factory_Physics_Model.
    %
    %   Tagged 'Slow' and 'Simulink'. The build alone takes tens of seconds
    %   and a full run is several minutes at a 0.5 ms fixed step with an
    %   interpreted S-function, so these are excluded from the default suite.
    %
    %   Run them explicitly:
    %       runtests('SimulinkModelTest')
    %       run_all_tests('IncludeSlow', true)
    %
    %   These exist because the Simulink path was unbuildable until the
    %   port-based / block-based sample-time conflict in factory_plant_sfun.m
    %   was fixed. Nothing detected that, because nothing ever built it.
    %
    %   See also BUILD_FACTORY_MODEL, RUN_SIMULINK_MODEL.

    properties (Constant)
        MODEL = 'Factory_Physics_Model';
    end

    methods (Access = private)
        function closeQuietly(~, mdl)
            try %#ok<TRYNC>
                set_param(mdl, 'SimulationCommand', 'term');
            end
            try %#ok<TRYNC>
                close_system(mdl, 0);
            end
        end
    end

    methods (TestMethodTeardown)
        function shut(tc) %#ok<MANU>
            % Force-discard every open model.
            %
            % bdclose('all') REFUSES to close a model with unsaved changes and
            % warns instead. The tests here build with 'Save', false, so every
            % model is dirty, and a swallowed failure leaves that dirty model
            % in memory for the next test to pick up -- which made
            % modelRunsAndCompletesTheCycle fail in the suite while passing in
            % isolation. close_system(name, 0) discards explicitly.
            for m = find_system('type', 'block_diagram')'
                try %#ok<TRYNC>
                    close_system(m{1}, 0);
                end
            end

            % Clear the persistent state these tests leave behind.
            %
            % factory_params_cached holds the parameter struct and
            % factory_plc_sfun holds the CONTROLLER state in persistent
            % variables, so an aborted or completed Simulink run leaves the
            % sequencer mid-cycle for the next test to inherit. reset_factory
            % exists for exactly this; see its header. The MATLAB-only driver
            % is unaffected because it rebuilds its parameters every call.
            try %#ok<TRYNC>
                reset_factory('Quiet', true);
            end
        end
    end

    methods (Test, TestTags = {'Slow','Simulink'})

        function simulinkIsAvailable(tc)
            tc.assumeTrue(logical(license('test','Simulink')), ...
                'Simulink licence not available');
            tc.verifyNotEmpty(ver('simulink'), 'Simulink is not installed');
        end

        function modelBuilds(tc)
            % Regression guard for the sample-time defect: any reintroduction
            % of a port-based sample time in the plant S-function fails here.
            mdl = build_factory_model('Save', false, 'Open', false);
            tc.verifyEqual(mdl, tc.MODEL);
            tc.verifyNotEmpty(find_system(mdl, 'Type', 'Block'));
        end

        function modelHasThePlantAndPlcBlocks(tc)
            build_factory_model('Save', false, 'Open', false);
            blocks = find_system(tc.MODEL, 'Type', 'Block');
            names  = cellfun(@(b) get_param(b,'Name'), blocks, ...
                             'UniformOutput', false);
            tc.verifyTrue(any(strcmp(names, 'Plant')), 'no Plant block');
            tc.verifyTrue(any(strcmp(names, 'PLC')),   'no PLC block');
        end

        function solverIsFixedStepRk4AtTheParameterStep(tc)
            % The Simulink path must integrate the same way as
            % run_factory_simulation, which uses explicit RK4 at P.dt. ode4
            % IS classic RK4; a change to either breaks comparability.
            P = factory_params_cached();
            build_factory_model('Save', false, 'Open', false);
            tc.verifyEqual(get_param(tc.MODEL,'SolverType'), 'Fixed-step');
            tc.verifyEqual(get_param(tc.MODEL,'Solver'),     'ode4');
            tc.verifyEqual(str2double(get_param(tc.MODEL,'FixedStep')), P.dt, ...
                'RelTol', 1e-12);
        end

        function modelRunsAndCompletesTheCycle(tc)
            o = run_simulink_model('Plot', false, 'Open', false);

            % run_simulink_model returns the Simulink.SimulationOutput OBJECT
            % with LOG attached, not a plain struct. isfield() is false for an
            % object even when the property exists and reads correctly, so it
            % must not be used here -- doing so reported a completed run as a
            % failure while the model was working perfectly.
            tc.verifyTrue(isprop(o, 'LOG') || isfield(o, 'LOG'), ...
                'run_simulink_model returned no LOG');

            L = o.LOG;
            tc.verifyTrue(logical(L.complete), ...
                'the Simulink run did not complete the cycle');
            tc.verifyGreaterThanOrEqual(L.state(end), 40, ...
                'the run ended before S39_CYCLE_COMPLETE');
        end

        function theSimulinkLogIsCompleteEnoughForTheProcessView(tc)
            % Until 2026-08-24 the Simulink path set LOG.blk_a to zeros with the
            % note "not logged on this path" and carried no force breakdown, so
            % the two execution paths produced DIFFERENT LOG contents and
            % visualize_processes rejected a Simulink LOG outright.
            %
            % simout_to_log now reconstructs both by re-evaluating
            % factory_derivatives at each logged sample. That is exact rather
            % than approximate: the .slx logs the full plant state and the
            % command vector, and the derivative is a pure function of those.
            o = run_simulink_model('Plot', false, 'Open', false);
            L = o.LOG;
            for f = {'blk_a','F_rod','F_stop','F_fric','F_net','belt_v','reg'}
                tc.verifyTrue(isfield(L, f{1}), ...
                    sprintf('the Simulink LOG is missing %s', f{1}));
            end
            tc.verifyFalse(all(L.blk_a(:) == 0), ...
                'blk_a is all zeros - the reconstruction did not run');
            tc.verifyEqual(L.F_rod + L.F_stop + L.F_fric, L.F_net, 'AbsTol', 0, ...
                'the reconstructed breakdown does not sum to the net force');
            tc.verifyEqual(L.P.blk_m*L.blk_a, L.F_net, 'AbsTol', 1e-9, ...
                'reconstructed net force is not mass times acceleration');
            tc.verifyWarningFree(@() visualize_processes(L), ...
                'visualize_processes no longer accepts a Simulink LOG');
            close all force
        end

        function simulinkAgreesWithTheMatlabOnlyPath(tc)
            % The two paths execute the same equations (FACTORY_DERIVATIVES),
            % the same integrator (ode4 / RK4 at P.dt) and the same sequencer
            % (FACTORY_PLC), so they must agree to floating-point noise.
            %
            % They did not, for the whole history of the project: 0.300 s and
            % 0.486 mm by S39_CYCLE_COMPLETE. The cause was NOT integration.
            % FACTORY_PLC_SFUN ran its scan in Update but emitted from
            % Outputs, delaying every command by one scan. It is now
            % P.plc_io_delay and both paths honour it.
            %
            % The tolerances below are therefore TIGHT ON PURPOSE. Measured
            % residual after the fix:
            %     worst state entry delta  2.7e-11 s   (time accumulation)
            %     cycle time delta         2.7e-11 s
            %     final position delta     0 m exactly
            %     air consumption delta    0 NL exactly
            % Loosening any of these hides a real scheduling regression.
            % PLCIOLATENCYTEST pins the mechanism itself without Simulink.
            R = compare_execution_paths('Verbose', false);

            tc.verifyEqual(R.plc_io_delay, 0, ...
                'this test is only meaningful at the default zero latency');

            tc.verifyEqual(R.n_trans_sl, R.n_trans_ml, ...
                ['the paths entered different numbers of states. Simulink ' ...
                 'used to report 40 to MATLAB''s 39 because it logged ' ...
                 'S00_INIT before the first scan had run.']);

            tc.verifyLessThan(R.max_state_delta, 1e-6, ...
                ['a PLC state entry time diverged by more than 1 us. Compare ' ...
                 'against P.t_scan = 10 ms: a divergence near a multiple of ' ...
                 'the scan period means the write-delay bug is back.']);

            tc.verifyEqual(R.cycle_sl, R.cycle_ml, 'AbsTol', 1e-6, ...
                'Simulink / MATLAB cycle-time divergence returned');

            tc.verifyEqual(R.pos_sl, R.pos_ml, 'AbsTol', 1e-9, ...
                'Simulink / MATLAB final-position divergence returned');

            tc.verifyEqual(R.air_delta, 0, 'AbsTol', 1e-9, ...
                'Simulink / MATLAB air-consumption divergence returned');
        end

        function plcSampleTimesAreCorrectAtTheBoundary(tc)
            % The plant must be continuous and the PLC discrete at the scan
            % period. If the plant ever acquires a discrete rate, or the PLC
            % inherits, the closed loop silently changes character. This is
            % the check the MATLAB Agentic Toolkit's model_query_params
            % performs; done here so the suite does not depend on the MCP
            % server being connected.
            P = factory_params_cached();
            mdl = tc.MODEL;
            build_factory_model('Model', mdl, 'Save', false, 'Open', false);

            cleanup = onCleanup(@() tc.closeQuietly(mdl));
            set_param(mdl, 'SimulationCommand', 'update');   % compile

            stPlant = get_param([mdl '/Plant'], 'CompiledSampleTime');
            stPlc   = get_param([mdl '/PLC'],   'CompiledSampleTime');

            tc.verifyEqual(stPlant(1), 0, ...
                'the Plant block is no longer continuous');
            tc.verifyEqual(stPlc(1), P.t_scan, 'AbsTol', 1e-12, ...
                'the PLC block is no longer discrete at P.t_scan');
        end

    end
end
