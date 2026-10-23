classdef PlcIoLatencyTest < matlab.unittest.TestCase
    %PLCIOLATENCYTEST  Pin the mechanism behind the old Simulink divergence.
    %
    %   For the whole history of this project the Simulink path disagreed
    %   with the MATLAB path: 0.300 s and 0.486 mm by S39_CYCLE_COMPLETE.
    %   It was recorded as "scheduling latency at the discrete-PLC /
    %   continuous-plant boundary" and asserted only loosely.
    %
    %   THE ACTUAL CAUSE. FACTORY_PLC_SFUN ran its scan in Update but emitted
    %   the result from Outputs, so the plant received every command one
    %   scan late. RUN_FACTORY_SIMULATION applied it in the same scan. The
    %   lag accumulated once per physics-gated transition.
    %
    %   The giveaway was that every increment of the divergence was an exact
    %   multiple of P.t_scan. Integration error cannot be quantised to the
    %   PLC clock; only a scheduling error can.
    %
    %   It is now P.plc_io_delay and BOTH paths honour it, so the two agree
    %   at either setting. These tests run on the MATLAB path ONLY - no
    %   Simulink licence and no 90 s model run - yet they reproduce the
    %   historical Simulink numbers exactly, which is what proves the
    %   diagnosis rather than merely asserting it.
    %
    %   REF_DELAY1_* below were the pre-fix SIMULINK results. They are
    %   reproduced here by the MATLAB path at plc_io_delay = 1.
    %
    %   See also COMPARE_EXECUTION_PATHS, FACTORY_PLC_SFUN, SIMULINKMODELTEST.

    properties (Constant)
        % HISTORICAL figures, taken before 2026-08-25 with the drawing's
        % 60 mm 0.583 kg cube AND the model's five spring-return cylinders.
        % Reproduced by historicalParams below, NOT by the current parameter
        % set - see that method for why.
        %
        % The plant became part of "the conditions these were taken under" on
        % 2026-09-02, when it was widened to the machine's eleven actuators on
        % thirteen coils. historicalParams restores both.
        %
        % delay 0 - the historical default
        REF_D0_CYCLE = 31.0800;     % s
        REF_D0_X     = 1.509379;    % m

        % delay 1 - reproduces the pre-fix Simulink run
        REF_D1_CYCLE = 31.3700;     % s
        REF_D1_X     = 1.509865;    % m

        % the historical Simulink-vs-MATLAB final-position divergence
        REF_DIVERGENCE_MM = 0.485877;   % mm
    end

    properties
        L0      % plc_io_delay = 0, CURRENT parameters
        L1      % plc_io_delay = 1, CURRENT parameters
        H0      % plc_io_delay = 0, HISTORICAL parameters
        H1      % plc_io_delay = 1, HISTORICAL parameters
        P
    end

    methods (Access = private)
        function P = historicalParams(~)
            %HISTORICALPARAMS  The conditions the REF_* figures were taken under.
            %
            %   REF_D1_X and friends are measurements of a real Simulink run
            %   made before 2026-08-25, when the model used the drawing's
            %   60 mm 0.583 kg cube. They are historical facts, and a
            %   measurement of the OLD workpiece cannot be reproduced by the
            %   NEW one - the physics moved. Re-pinning them to the current
            %   workpiece would turn a proof into a self-referential
            %   regression pin and quietly destroy the evidence.
            %
            %   So reproduce them under the conditions they were taken under.
            %   Verified 2026-08-25: this restores all five figures exactly.
            P = FactoryParams();
            P.blk_L = 0.6*P.SCALE;  P.blk_W = P.blk_L;  P.blk_H = P.blk_L;
            P.blk_rho = 2700;
            % ...and the five-cylinder plant. Widening to the machine's eleven
            % actuators put six more rod-side chambers on the manifold, which
            % moved the air and with it the branch-charge waits. These figures
            % predate that, so reproducing them means reproducing that plant.
            P.act_variant = 'historical5';
            P.blk_m = P.blk_rho*P.blk_L*P.blk_W*P.blk_H;
            P.blk_J = P.blk_m*(P.blk_L^2 + P.blk_W^2)/12;
            P.k_ct  = 1.0e5;  P.lam_ct  = 5.0e5;
            P.k_stop = 5.0e4; P.lam_stop = 5.0e5;
            P.dt = 5.0e-4;
            P = initialize_factory(P);
        end
    end

    methods (TestClassSetup)
        function runBothLatencies(tc)
            tc.P = FactoryParams();
            P1 = tc.P; P1.plc_io_delay = 1;
            tc.L0 = run_factory_simulation('Params', tc.P, ...
                        'Plot', false, 'Verbose', false);
            tc.L1 = run_factory_simulation('Params', P1, ...
                        'Plot', false, 'Verbose', false);
            Ph0 = tc.historicalParams();
            Ph1 = Ph0; Ph1.plc_io_delay = 1;
            tc.H0 = run_factory_simulation('Params', Ph0, ...
                        'Plot', false, 'Verbose', false);
            tc.H1 = run_factory_simulation('Params', Ph1, ...
                        'Plot', false, 'Verbose', false);
        end
    end

    methods (Test)

        function defaultLatencyIsZero(tc)
            % The default must stay 0: every pinned reference value in
            % verify_model.m and CycleRegressionTest was baselined on it.
            tc.verifyEqual(tc.P.plc_io_delay, 0, ...
                'P.plc_io_delay must default to 0 or every pinned value shifts');
        end

        function bothPathsCompleteAtEitherLatency(tc)
            tc.verifyTrue(logical(tc.L0.complete), 'delay 0 did not complete');
            tc.verifyTrue(logical(tc.L1.complete), 'delay 1 did not complete');
        end

        function oneScanOfLatencyDelaysTheCycle(tc)
            % The pinned figures belong to the historical workpiece; the
            % ordering claim holds for any workpiece, so assert it on both.
            tc.verifyEqual(tc.H0.cycle_time, tc.REF_D0_CYCLE, 'AbsTol', 0.005);
            tc.verifyEqual(tc.H1.cycle_time, tc.REF_D1_CYCLE, 'AbsTol', 0.005);
            tc.verifyGreaterThan(tc.H1.cycle_time, tc.H0.cycle_time, ...
                'a write delay can only ever make the cycle longer');
            tc.verifyGreaterThan(tc.L1.cycle_time, tc.L0.cycle_time, ...
                'a write delay can only ever make the cycle longer');
        end

        function delayOneReproducesTheHistoricalSimulinkPosition(tc)
            % THE PROOF. 1.509865 m was measured on the SIMULINK path before
            % the fix. Reproducing it on the MATLAB path purely by setting
            % plc_io_delay = 1 identifies the write delay as the whole cause.
            tc.verifyEqual(tc.H1.blk_final(1), tc.REF_D1_X, 'AbsTol', 1e-6, ...
                'plc_io_delay=1 no longer reproduces the pre-fix Simulink result');
            tc.verifyEqual(tc.H0.blk_final(1), tc.REF_D0_X, 'AbsTol', 1e-6);

            d_mm = 1000*norm(tc.H1.blk_final - tc.H0.blk_final);
            tc.verifyEqual(d_mm, tc.REF_DIVERGENCE_MM, 'AbsTol', 1e-3, ...
                ['the reproduced divergence no longer matches the 0.485877 mm ' ...
                 'measured between the two paths before the fix']);
        end

        function theDivergenceIsQuantisedToTheScanClock(tc)
            % The signature that ruled integration error out. Every state
            % entry time must shift by a whole number of scan periods.
            ST = factory_states();
            t0 = tc.entryTimes(tc.L0, ST);
            t1 = tc.entryTimes(tc.L1, ST);
            ok = ~isnan(t0) & ~isnan(t1);
            shift_scans = (t1(ok) - t0(ok)) / tc.P.t_scan;

            tc.verifyEqual(shift_scans, round(shift_scans), 'AbsTol', 1e-6, ...
                ['a state entry shifted by a NON-integer number of scans, so ' ...
                 'the divergence is no longer purely a scheduling effect']);
            tc.verifyGreaterThanOrEqual(min(shift_scans), 0, ...
                'a write delay cannot make any state happen earlier');
        end

        function latencyAccumulatesRatherThanOffsetting(tc)
            % A constant offset would show one step and then flatten. The
            % real behaviour grows once per physics-gated transition, which
            % is why it reached 0.30 s rather than staying at 0.01 s.
            ST = factory_states();
            t0 = tc.entryTimes(tc.L0, ST);
            t1 = tc.entryTimes(tc.L1, ST);
            ok = ~isnan(t0) & ~isnan(t1);
            d  = t1(ok) - t0(ok);

            tc.verifyGreaterThan(d(end), 20*tc.P.t_scan, ...
                'the accumulated lag collapsed - it should exceed 20 scans');
            tc.verifyLessThanOrEqual(d(1), 2*tc.P.t_scan, ...
                'the lag should start near zero and grow, not start large');
        end

    end

    methods (Access = private)
        function t = entryTimes(~, L, ST)
            %ENTRYTIMES  First entry time of every PLC state, NaN if never.
            t = nan(size(ST,1),1); t(1) = 0;
            for i = 1:size(L.plc.log,1)
                k = find(strcmp(ST(:,1), L.plc.log{i,2}), 1);
                if ~isempty(k) && isnan(t(k)); t(k) = L.plc.log{i,1}; end
            end
        end
    end
end
