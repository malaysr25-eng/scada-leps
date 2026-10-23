classdef ParametersTest < matlab.unittest.TestCase
    %PARAMETERSTEST  Parameter set, provenance chain and derived quantities.
    %
    %   Covers FactoryParams, JanaticsData and initialize_factory. These run
    %   in well under a second and catch the largest class of defect: a
    %   parameter change that silently breaks a derived quantity or an
    %   invariant the physics relies on.
    %
    %   Assertions are structural and dimensional rather than pinned values,
    %   except where a value is a catalogue figure that must not drift. Those
    %   are marked CATALOGUE and are deliberately exact.
    %
    %   See also FACTORYPARAMS, JANATICSDATA, INITIALIZE_FACTORY.

    properties
        P
        s0
    end

    methods (TestClassSetup)
        function build(tc)
            [tc.P, tc.s0] = initialize_factory(FactoryParams());
        end
    end

    methods (Test)

        % ---- provenance chain -------------------------------------------

        function janaticsRegisterTravelsWithParameters(tc)
            % Manufacturer data must reach the physics only via FactoryParams.
            tc.verifyTrue(isfield(tc.P, 'JAN'), ...
                'FactoryParams must carry the Janatics register as P.JAN');
        end

        function everyCylinderHasATagAndStatus(tc)
            J = JanaticsData();
            tc.verifyNumElements(J.CYL.tag, 5);
            tc.verifyNumElements(J.CYL.factory_id, 5);
            tc.verifyNotEmpty(J.CYL.status);
        end

        function hardwareIsStillMarkedProvisional(tc)
            % Guards the honesty of the register. No BOM has ever been
            % supplied, so nothing may quietly become 'CONFIRMED' without a
            % real source. If this test fails, check a document was attached.
            J = JanaticsData();
            tc.verifyEqual(J.CYL.status, 'PROVISIONAL', ...
                ['Cylinder status changed from PROVISIONAL. That is only ' ...
                 'valid if a nameplate, BOM or purchase record was supplied ' ...
                 'and recorded in Janatics_Component_Register.csv.']);
        end

        % ---- geometry ----------------------------------------------------

        function pistonAreasFollowFromBoreAndRod(tc)
            tc.verifyEqual(tc.P.A_A, pi*tc.P.D_bore^2/4, 'RelTol', 1e-12);
            tc.verifyEqual(tc.P.A_B, pi*(tc.P.D_bore^2 - tc.P.d_rod^2)/4, ...
                'RelTol', 1e-12);
        end

        function annulusIsSmallerThanCapSide(tc)
            % A rod-side area >= cap-side would invert every actuator force.
            tc.verifyLessThan(tc.P.A_B, tc.P.A_A);
        end

        function rodFitsInsideTheBore(tc)
            tc.verifyLessThan(tc.P.d_rod, tc.P.D_bore);
        end

        function catalogueAnnulusForceMatches(tc)
            % CATALOGUE: Janatics tabulates 142 N annulus force at 6 bar for a
            % bore-20 / rod-8 cylinder. Reproducing it from first principles
            % confirms bore, rod, the gauge-pressure convention AND the
            % catalogue force efficiency are all mutually consistent.
            %
            % The efficiency is taken from the register rather than written as
            % a literal 0.90, so that a change to J.CYL.f_eff fails here
            % instead of silently disagreeing with the stored figure.
            eff = 1 - tc.P.f_loss;
            F   = eff * 6e5 * tc.P.A_B;
            tc.verifyEqual(F, 142.0, 'AbsTol', 1.0, ...
                sprintf(['annulus force %.2f N disagrees with the catalogue ' ...
                         '142 N (efficiency %.3f, A_B %.3f mm^2)'], ...
                         F, eff, tc.P.A_B*1e6));
        end

        function catalogueEfficiencyComesFromTheRegister(tc)
            % verify_model.m writes this factor as a literal 0.90. Pin the two
            % together so they cannot drift apart unnoticed.
            J = JanaticsData();
            tc.verifyEqual(1 - tc.P.f_loss, J.CYL.f_eff, 'RelTol', 1e-12);
        end

        function workpieceMassFollowsFromDensityAndEdge(tc)
            tc.verifyEqual(tc.P.blk_m, ...
                tc.P.blk_rho*tc.P.blk_L*tc.P.blk_W*tc.P.blk_H, ...
                'RelTol', 1e-12);
        end

        % ---- pneumatics --------------------------------------------------

        function compressorBandIsOrdered(tc)
            % cut-in < cut-out < relief, or the pressure switch is meaningless
            % and the relief either never lifts or fights the compressor.
            tc.verifyLessThan(tc.P.P_cut_in,  tc.P.P_cut_out);
            tc.verifyLessThan(tc.P.P_cut_out, tc.P.P_relief);
        end

        function reliefSitsJustAboveCutOut(tc)
            % A relief set far above cut-out would never lift. Pinned
            % independently so a pressure bound expressed as a multiple of
            % P_relief cannot silently become vacuous.
            tc.verifyLessThan(tc.P.P_relief, 1.5*tc.P.P_cut_out);
        end

        function regulatorSetPointIsBelowCutOut(tc)
            % The FRL cannot deliver more than the receiver holds.
            tc.verifyLessThanOrEqual(tc.P.P_set, tc.P.P_cut_out + tc.P.P_atm);
        end

        function criticalPressureRatioIsPhysical(tc)
            % ISO 6358 b is a ratio strictly inside (0,1).
            tc.verifyGreaterThan(tc.P.b_crit, 0);
            tc.verifyLessThan(tc.P.b_crit, 1);
        end

        function conductancesArePositive(tc)
            for f = {'C_sup','C_dv'}
                tc.verifyGreaterThan(tc.P.(f{1}), 0, ...
                    sprintf('%s must be positive', f{1}));
            end
        end

        % ---- friction ----------------------------------------------------

        function staticFrictionExceedsKinetic(tc)
            % mu_k > mu_s would make a body harder to keep moving than to
            % start, which is unphysical for dry contact.
            tc.verifyGreaterThan(tc.P.mu_s, tc.P.mu_k);
        end

        function frictionCoefficientsArePlausible(tc)
            for f = {'mu_s','mu_k'}
                tc.verifyGreaterThan(tc.P.(f{1}), 0);
                tc.verifyLessThan(tc.P.(f{1}), 1.5);
            end
        end

        function regularisationVelocityIsSmallButFinite(tc)
            tc.verifyGreaterThan(tc.P.v_creep, 0);
            tc.verifyLessThan(tc.P.v_creep, 0.05);
        end

        % ---- state vector -------------------------------------------------

        function initialStateMatchesDeclaredLength(tc)
            tc.verifyNumElements(tc.s0, tc.P.NS);
        end

        function initialStateIsFinite(tc)
            tc.verifyTrue(all(isfinite(tc.s0)));
        end

        function indexMapIsCollisionFree(tc)
            % Every P.IX entry must address a distinct, in-range slot.
            IX = tc.P.IX;
            idx = [];
            for f = fieldnames(IX)'
                idx = [idx, IX.(f{1})(:)']; %#ok<AGROW>
            end
            tc.verifyEqual(numel(idx), numel(unique(idx)), ...
                'P.IX contains a duplicated state index');
            tc.verifyGreaterThanOrEqual(min(idx), 1);
            tc.verifyLessThanOrEqual(max(idx), tc.P.NS);
        end

        function chambersStartAtAtmosphere(tc)
            IX = tc.P.IX;
            tc.verifyEqual(tc.s0(IX.PA), repmat(tc.P.P_atm, numel(IX.PA), 1), ...
                'RelTol', 1e-12);
            tc.verifyEqual(tc.s0(IX.PB), repmat(tc.P.P_atm, numel(IX.PB), 1), ...
                'RelTol', 1e-12);
        end

        function receiverStartsPrecharged(tc)
            % A receiver at atmosphere could never start the cycle.
            tc.verifyGreaterThan(tc.s0(tc.P.IX.P_res), tc.P.P_atm);
        end

        function solverStepResolvesThePlcScan(tc)
            % The PLC must be sampled on an integer number of solver steps.
            r = tc.P.t_scan / tc.P.dt;
            tc.verifyEqual(r, round(r), 'AbsTol', 1e-9, ...
                't_scan must be an integer multiple of dt');
            tc.verifyGreaterThanOrEqual(r, 2);
        end

        % ---- fault hooks --------------------------------------------------

        function faultHooksDefaultToInactive(tc)
            % Every baseline result in the repo assumes faults off. If a
            % default changes, every reference value silently moves.
            F = tc.P.fault;
            tc.verifyFalse(F.low_pressure);
            tc.verifyFalse(F.sensor_fail);
            tc.verifyEqual(F.P_supply_scale, 1.00);
            tc.verifyEqual(F.conveyor_slip,  1.00);
            tc.verifyEqual(F.friction_scale, 1.00);
            tc.verifyEqual(F.sensor_delay,   0.0);
            tc.verifyEqual(F.height_sens_bias, 0.0);
            tc.verifyTrue(all(F.valve_stuck   == 0));
            tc.verifyTrue(all(F.actuator_stick == 0));
            tc.verifyTrue(all(F.conveyor_fail == 0));
        end

    end
end
