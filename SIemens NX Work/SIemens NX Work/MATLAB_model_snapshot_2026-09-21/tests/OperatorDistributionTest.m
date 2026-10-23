classdef OperatorDistributionTest < matlab.unittest.TestCase
    %OPERATORDISTRIBUTIONTEST  The operator is a distribution, and the model
    %   must stay deterministic anyway.
    %
    %   Two things have to be true at once and they pull against each other:
    %
    %     1. The model must PREDICT A SPREAD, because the real operator varies
    %        5.95 to 28.65 s and a single number was always a category error.
    %     2. The model must stay BIT-DETERMINISTIC by default, because every
    %        pinned reference value in this project depends on it and a
    %        stochastic model cannot be regression-tested.
    %
    %   The resolution is that FACTORYPARAMS never samples. The draw lives in
    %   FACTORY_OPERATOR_DRAW and has to be asked for. These tests hold that
    %   line - if someone later makes FactoryParams sample by default, the
    %   first test here fails and says why.
    %
    %   See also FACTORY_OPERATOR_DRAW, OPERATOR_DISTRIBUTION.

    methods (Test)

        function factoryParamsIsDeterministic(tc)
            % THE LINE THAT MUST NOT MOVE. Ten calls, one answer.
            a = FactoryParams();
            for k = 1:10
                b = FactoryParams();
                tc.verifyEqual([b.t_op_notice b.t_engrave b.t_op_confirm], ...
                               [a.t_op_notice a.t_engrave a.t_op_confirm], ...
                    ['FactoryParams returned different operator times on ' ...
                     'successive calls. It must never sample: half the ' ...
                     'project calls it expecting the same struct, and every ' ...
                     'pinned baseline assumes it. Sampling belongs in ' ...
                     'FACTORY_OPERATOR_DRAW.']);
            end
            tc.verifyEqual(a.op_mode, 'nominal');
        end

        function nominalTotalIsUnchanged(tc)
            % The nominal is a REGRESSION ANCHOR, not a forecast. If it moves,
            % every pinned cycle time moves with it, so it moves deliberately
            % or not at all.
            P = FactoryParams();
            tc.verifyEqual(P.t_op_notice + P.t_engrave + P.t_op_confirm, ...
                12.5, 'AbsTol', 1e-9, ...
                ['The nominal operator block moved off 12.5 s. That is a ' ...
                 're-baseline of every pinned cycle time - confirm it was ' ...
                 'intended and update verify_model and CycleRegressionTest.']);
        end

        function drawIsReproducibleAndFromTheObservedSet(tc)
            P = FactoryParams();
            for seed = 1:20
                A = factory_operator_draw(P, seed);
                B = factory_operator_draw(P, seed);
                tc.verifyEqual(A.op_total, B.op_total, ...
                    'the same seed gave two different draws');
                tc.verifyTrue(any(abs(P.OP.samples - A.op_total) < 1e-9), ...
                    ['a draw produced a value that is not one of the seven ' ...
                     'observed dwells. This is a bootstrap, not a fitted ' ...
                     'distribution - it may only ever return what was seen.']);
            end
        end

        function drawPreservesTheTotalItDrew(tc)
            % The three parts must add back up to the dwell that was drawn,
            % or the model is simulating an operator nobody observed.
            P = FactoryParams();
            for seed = 1:10
                Q = factory_operator_draw(P, seed);
                tc.verifyEqual(Q.t_op_notice + Q.t_engrave + Q.t_op_confirm, ...
                    Q.op_total, 'AbsTol', 1e-9, ...
                    'the split does not sum to the drawn dwell');
                tc.verifyEqual(Q.t_op_confirm, P.OP.confirm, 'AbsTol', 1e-9, ...
                    'confirm is measured and must not be scaled with the rest');
            end
        end

        function theDrawSpansTheObservedRange(tc)
            % A sampler that only ever returns the middle would hide the very
            % thing this exists to show.
            P = FactoryParams();
            got = arrayfun(@(s) getfield(factory_operator_draw(P,s),'op_total'), 1:400); %#ok<GFLD>
            tc.verifyEqual(min(got), min(P.OP.samples), 'AbsTol', 1e-9);
            tc.verifyEqual(max(got), max(P.OP.samples), 'AbsTol', 1e-9);
        end

        function predictedDistributionOverlapsTheObserved(tc)
            % The headline claim, held to a number. Overlap is generous on
            % purpose: the model is still ~6.7 s too fast on MACHINE time
            % (57.35 s to S37 against 64.03 s measured, after H8), which is a known and
            % separately-tracked gap, so demanding a tight match here would
            % be testing the wrong thing.
            %
            % 2026-09-12: the overlap was 81% while machine time ran to S39,
            % past the recorder's end point. Like for like it is 53% - just
            % over this floor. The floor was NOT lowered to make room; the
            % plan's H2 (the T#10S start delay, +7.5 s) is expected to raise
            % it. If this fails before H2 lands, that is the true gap talking.
            % H2 landed the same day and raised it well clear of the floor.
            R = operator_distribution('N', 5000, 'Verbose', false);
            tc.verifyGreaterThan(R.range_overlap_frac, 0.5, ...
                sprintf(['the predicted and observed cycle-time ranges now ' ...
                         'overlap only %.0f%%. Either the operator samples ' ...
                         'or the machine time have moved a long way.'], ...
                        100*R.range_overlap_frac));
            tc.verifyGreaterThan(R.predicted.sd, 5, ...
                'the model has stopped predicting a spread');
        end

        function machineTimeIsTakenAtTheRecordersEndPoint(tc)
            % Plan H1, 2026-09-12. The observed cycles end when the last
            % outfeed push STARTS (S37), so the constant added to the operator
            % draw must end there too. Until 2026-09-12 it ran to S39 and
            % credited the model with the 5.67 s outfeed tail. Chained to the
            % live run through CycleRegressionTest's pin, so neither the
            % constant nor the model can drift on its own.
            R = operator_distribution('N', 10, 'Verbose', false);
            P = FactoryParams();
            want = CycleRegressionTest.REF_CYCLE_TIME_REC - ...
                   (P.t_op_notice + P.t_engrave + P.t_op_confirm);
            tc.verifyEqual(R.t_machine, want, 'AbsTol', 0.05, ...
                ['OPERATOR_DISTRIBUTION''s machine-time constant is not machine ' ...
                 'time to S37. The observed cycles end there; a constant that ' ...
                 'runs on to S39 flatters the model by the outfeed tail.']);
        end

        function additivityStillHolds(tc)
            % OPERATOR_DISTRIBUTION does arithmetic instead of N simulations,
            % and that shortcut is only valid while the plant does nothing
            % during the dwell. This is the guard on that assumption.
            %
            % Tagged Slow: three full cycles, about three minutes.
            P  = FactoryParams();
            mt = zeros(1,2);
            tot = [min(P.OP.samples) max(P.OP.samples)];
            for k = 1:2
                Q = P; Q.t_op_confirm = P.OP.confirm;
                rest = tot(k) - P.OP.confirm;
                Q.t_op_notice = rest*P.OP.notice_frac;
                Q.t_engrave   = rest*(1-P.OP.notice_frac);
                L = run_factory_simulation('Params', Q, 'Plot', false, 'Verbose', false);
                mt(k) = L.cycle_time_rec - tot(k);   % to S37, as the recorder
            end
            tc.verifyEqual(mt(1), mt(2), 'AbsTol', 0.05, ...
                sprintf(['machine time changed by %.3f s across the operator ' ...
                         'range, so operator time is no longer additive and ' ...
                         'OPERATOR_DISTRIBUTION''s arithmetic shortcut is ' ...
                         'invalid. Something now does real work during the ' ...
                         'dwell.'], abs(mt(1)-mt(2))));
        end

    end
end
