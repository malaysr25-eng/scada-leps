classdef PhysicsTest < matlab.unittest.TestCase
    %PHYSICSTEST  factory_derivatives, factory_sensors and support_region.
    %
    %   Covers the continuous-time right-hand side and the sensor models --
    %   the layer that makes this a physics model rather than a script.
    %
    %   Assertions are structural and physical (shape, finiteness, purity,
    %   conservation direction, locality) rather than recorded numbers, so
    %   re-sizing the parameter set does not turn them into false failures.
    %   Pinned reference values live in CycleRegressionTest.
    %
    %   See also FACTORY_DERIVATIVES, FACTORY_SENSORS, SUPPORT_REGION.

    properties
        P
        s0
        u0
    end

    methods (TestClassSetup)
        function build(tc)
            [tc.P, tc.s0] = initialize_factory(FactoryParams());
            plc = factory_plc_init(tc.P);
            [~, tc.u0] = factory_plc(plc, factory_sensors(tc.s0, tc.P), 0, tc.P);
        end
    end

    methods (Access = private)
        function u = quiet(tc)
            % An all-off command: nothing energised anywhere.
            u = tc.u0;
            u.pump_on = false;
            u.dv      = zeros(1,4);
            u.sol     = zeros(1,tc.P.NSOL);
            u.conv    = zeros(1,tc.P.NCONV);
            u.base    = 0;
        end
    end

    methods (Test)

        % ---- shape and hygiene -------------------------------------------

        function derivativeHasOneEntryPerState(tc)
            ds = factory_derivatives(tc.s0, tc.quiet(), tc.P);
            tc.verifyNumElements(ds, tc.P.NS);
        end

        function derivativeIsColumnShaped(tc)
            % RK4 in run_factory_simulation adds ds to s directly; a row here
            % would broadcast into an NS x NS matrix instead of erroring.
            ds = factory_derivatives(tc.s0, tc.quiet(), tc.P);
            tc.verifySize(ds, [tc.P.NS 1]);
        end

        function derivativeIsFiniteAtInitialCondition(tc)
            ds = factory_derivatives(tc.s0, tc.quiet(), tc.P);
            tc.verifyTrue(all(isfinite(ds)));
        end

        function derivativeIsDeterministic(tc)
            % RK4 evaluates the field four times per step. A hidden dependence
            % on call order would corrupt the integration silently.
            u = tc.quiet();
            tc.verifyEqual(factory_derivatives(tc.s0, u, tc.P), ...
                           factory_derivatives(tc.s0, u, tc.P));
        end

        function derivativeDoesNotMutateItsInputs(tc)
            s = tc.s0; u = tc.quiet();
            factory_derivatives(s, u, tc.P);
            tc.verifyEqual(s, tc.s0, 'factory_derivatives mutated the state');
        end

        function derivativeStaysFiniteAtDegenerateState(tc)
            % Zero absolute pressure is unphysical, but an overshooting solver
            % step can approach it. The field must stay finite rather than
            % emit NaN and poison the whole state vector.
            s = tc.s0; IX = tc.P.IX;
            s(IX.PA) = 0; s(IX.PB) = 0; s(IX.P_res) = 0;
            ds = factory_derivatives(s, tc.quiet(), tc.P);
            tc.verifyTrue(all(isfinite(ds)), ...
                'derivatives produced non-finite values at zero pressure');
        end

        % ---- quiescence ---------------------------------------------------

        function workpieceIsAtRestWhenNothingIsCommanded(tc)
            % No spurious drift. Catches sign errors in gravity or the support
            % reaction that would otherwise show only as slow creep.
            ds = factory_derivatives(tc.s0, tc.quiet(), tc.P);
            IX = tc.P.IX;
            for f = {'bx','by','bvx','bvy'}
                tc.verifyEqual(ds(IX.(f{1})), 0, 'AbsTol', 1e-9, ...
                    sprintf('workpiece %s drifts with no command', f{1}));
            end
        end

        function noChamberActivityWithEveryValveClosed(tc)
            ds = factory_derivatives(tc.s0, tc.quiet(), tc.P);
            IX = tc.P.IX;
            tc.verifyEqual(ds(IX.PA), zeros(numel(IX.PA),1), 'AbsTol', 1e-6);
            tc.verifyEqual(ds(IX.PB), zeros(numel(IX.PB),1), 'AbsTol', 1e-6);
        end

        % ---- receiver ------------------------------------------------------

        function receiverIsStaticWithPumpOff(tc)
            ds = factory_derivatives(tc.s0, tc.quiet(), tc.P);
            tc.verifyEqual(ds(tc.P.IX.P_res), 0, 'AbsTol', 1e-9);
        end

        function receiverChargesWithPumpOn(tc)
            u = tc.quiet(); u.pump_on = true;
            ds = factory_derivatives(tc.s0, u, tc.P);
            tc.verifyGreaterThan(ds(tc.P.IX.P_res), 0);
        end

        function reliefValveBleedsAnOverpressuredReceiver(tc)
            % The relief is a physical device independent of the PLC. Without
            % it the receiver integrates without bound.
            s = tc.s0;
            s(tc.P.IX.P_res) = tc.P.P_relief * 1.05;
            ds = factory_derivatives(s, tc.quiet(), tc.P);
            tc.verifyLessThan(ds(tc.P.IX.P_res), 0);
        end

        % ---- sensors -------------------------------------------------------

        function sensorsAreDeterministic(tc)
            tc.verifyEqual(factory_sensors(tc.s0, tc.P), ...
                           factory_sensors(tc.s0, tc.P));
        end

        function sensorsDoNotMutateTheState(tc)
            s = tc.s0;
            factory_sensors(s, tc.P);
            tc.verifyEqual(s, tc.s0, 'factory_sensors mutated the state');
        end

        function receiverReadingTracksTheStateVector(tc)
            % The pressure switch must read live state, not a stored setpoint.
            s = tc.s0; s(tc.P.IX.P_res) = 7.3e5;
            y = factory_sensors(s, tc.P);
            tc.verifyEqual(y.P_res, 7.3e5, 'RelTol', 1e-12);
        end

        function cameraSeesTheBlockAtTheFeedPosition(tc)
            % Excel step 1 is a camera detect; if this is false the cycle
            % cannot start at all.
            y = factory_sensors(tc.s0, tc.P);
            tc.verifyTrue(logical(y.CAM));
        end

        function cameraClearsOnceTheBlockLeaves(tc)
            s = tc.s0;
            s(tc.P.IX.bx) = s(tc.P.IX.bx) + 10*tc.P.prox_rng;
            y = factory_sensors(s, tc.P);
            tc.verifyFalse(logical(y.CAM));
        end

        function proximitySensorsAreLocal(tc)
            % A sensor that latches globally would let the sequence advance
            % without the workpiece arriving -- the exact failure the physical
            % guards exist to prevent.
            s = tc.s0;
            s(tc.P.IX.bx) = 1e3;
            s(tc.P.IX.by) = 1e3;
            y = factory_sensors(s, tc.P);
            tc.verifyFalse(any(logical(y.PX)), ...
                'a proximity sensor fired with the block 1 km away');
        end

        function sensorFailureForcesProximityLow(tc)
            % Fault hook must actually take effect, or fault studies are void.
            Pf = tc.P; Pf.fault.sensor_fail = true;
            y  = factory_sensors(tc.s0, Pf);
            tc.verifyFalse(any(logical(y.PX)));
        end

        function sensorFailureLeavesTheCameraAlone(tc)
            % Pins the SCOPE of the fault hook. P.fault.sensor_fail suppresses
            % the proximity sensors only; the camera is a separate device and
            % is deliberately unaffected. Asserting this stops the hook
            % quietly growing to cover the camera, which would change what a
            % "sensor failure" study actually means.
            Pf = tc.P; Pf.fault.sensor_fail = true;
            y  = factory_sensors(tc.s0, Pf);
            tc.verifyTrue(logical(y.CAM), ...
                ['sensor_fail suppressed the camera. If that is intended, ' ...
                 'update FactoryParams (which documents it as "force all ' ...
                 'proximity sensors low") and this test together.']);
        end

        function heightSensorBiasIsApplied(tc)
            % The height sensor is exposed as the two window comparators
            % HS_TOP / HS_BOT, not as a raw reading, so the bias is observed
            % through the comparator flipping rather than a numeric offset.
            % The base starts at z = 0, so HS_BOT is true; a bias of twice
            % z_tol must push it outside the window.
            tc.verifyTrue(logical(factory_sensors(tc.s0, tc.P).HS_BOT), ...
                'precondition: HS_BOT should be true at the home position');
            Pf = tc.P; Pf.fault.height_sens_bias = 2*tc.P.z_tol;
            tc.verifyFalse(logical(factory_sensors(tc.s0, Pf).HS_BOT), ...
                'height_sens_bias had no effect on the height comparator');
        end

        % ---- support region -------------------------------------------------

        function blockFarOutsideFallsBackToPlate(tc)
            [~, name] = support_region(-99, -99, tc.P);
            tc.verifyEqual(name, 'plate');
        end

        function supportRegionAlwaysReturnsAName(tc)
            for x = -0.5:0.25:2.0
                for y = -0.5:0.25:1.5
                    [~, name] = support_region(x, y, tc.P);
                    tc.verifyNotEmpty(name);
                end
            end
        end

        % ---- optional force-breakdown output --------------------------------
        %
        % factory_derivatives returns the 2-D workpiece force breakdown as an
        % optional second output, which VISUALIZE_PROCESSES draws. The whole
        % point is that the arrows cannot disagree with the motion, so the
        % contract is asserted here rather than in the visualiser.

        function diagnosticsDoNotChangeTheDerivative(tc)
            % Requesting dbg must not perturb ds by even one bit. The
            % accumulators are deliberately PARALLEL to Fblk rather than
            % replacing it, precisely so this holds.
            C = tc.cases();
            for k = 1:numel(C)
                c = C{k};
                ds1        = factory_derivatives(c.s, c.u, tc.P);
                [ds2, ~]   = factory_derivatives(c.s, c.u, tc.P);
                tc.verifyTrue(isequal(ds1, ds2), ...
                    sprintf('ds changed when dbg was requested, case %d', k));
            end
        end

        function forceBreakdownSumsToTheNetForce(tc)
            C = tc.cases();
            for k = 1:numel(C)
                c = C{k};
                [~, d] = factory_derivatives(c.s, c.u, tc.P);
                tc.verifyEqual(d.F_rod + d.F_stop + d.F_fric, d.F_net, ...
                    'AbsTol', 0, ...
                    sprintf('breakdown does not sum to F_net, case %d', k));
            end
        end

        function netForceEqualsMassTimesLoggedAcceleration(tc)
            % F_net is what actually drives bvx/bvy, so m*a must reproduce it.
            C = tc.cases();
            for k = 1:numel(C)
                c = C{k};
                [ds, d] = factory_derivatives(c.s, c.u, tc.P);
                a = [ds(tc.P.IX.bvx) ds(tc.P.IX.bvy)];
                tc.verifyEqual(tc.P.blk_m*a, d.F_net, 'RelTol', 1e-12, ...
                    'AbsTol', 1e-12, ...
                    sprintf('F_net ~= m*a, case %d', k));
            end
        end

        function perCylinderForcesSumToTheRodForce(tc)
            C = tc.cases();
            for k = 1:numel(C)
                c = C{k};
                [~, d] = factory_derivatives(c.s, c.u, tc.P);
                tc.verifyEqual(sum(d.F_cyl, 1), d.F_rod, 'AbsTol', 1e-12, ...
                    sprintf('per-cylinder forces do not sum to F_rod, case %d', k));
            end
        end

    end

    methods (Access = private)
        function c = cases(tc)
            % A few states that exercise rod contact, stops and belt friction,
            % not just the quiescent initial condition where every force is 0.
            c = {};
            c{1} = struct('s', tc.s0, 'u', tc.quiet());

            s = tc.s0; u = tc.u0;
            % Energise the FEED actuator's extend coil. This read
            % u.sv = [1 0 0 0 0] until 2026-09-02; after the command vector
            % became the machine's 13 coils that set a field nothing reads, so
            % the case silently degraded into a second quiescent test instead
            % of one that exercises rod contact. It still PASSED, which is the
            % point worth remembering.
            u.pump_on = true; u.dv = [1 0 0 0];
            u.sol(tc.P.CYL(tc.P.ACT.feed).coil_ext) = 1;
            s(tc.P.IX.PA) = 6e5; s(tc.P.IX.PB) = 2e5; s(tc.P.IX.x) = 0.02;
            c{2} = struct('s', s, 'u', u);

            s = tc.s0; u = tc.u0;
            u.conv = [1 0 0];
            s(tc.P.IX.om) = 5; s(tc.P.IX.bvx) = 0.05;
            c{3} = struct('s', s, 'u', u);
        end
    end
end
