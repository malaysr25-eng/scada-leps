classdef SequencerTest < matlab.unittest.TestCase
    %SEQUENCERTEST  factory_plc, factory_plc_init and factory_states.
    %
    %   Exercises the PLC directly rather than through a full run, so a
    %   sequencing defect is reported against the guard that caused it
    %   instead of as a cycle-time change.
    %
    %   See also FACTORY_PLC, FACTORY_PLC_INIT, FACTORY_STATES.

    properties
        P
        s0
        ST
    end

    methods (TestClassSetup)
        function build(tc)
            [tc.P, tc.s0] = initialize_factory(FactoryParams());
            tc.ST = factory_states();
        end
    end

    methods (Access = private)
        function pump = steppedPump(tc, enable, pump, p_res)
            plc = factory_plc_init(tc.P);
            plc.pump_enable = enable;
            plc.pump        = pump;
            y = factory_sensors(tc.s0, tc.P);
            y.P_res = p_res;
            plc = factory_plc(plc, y, 0, tc.P);
            pump = plc.pump;
        end
    end

    methods (Test)

        % ---- state table ---------------------------------------------------

        function stateTableHasThreeColumns(tc)
            % {name, excel_ref, guard}
            tc.verifySize(tc.ST, [size(tc.ST,1) 3]);
        end

        function stateNamesAreUnique(tc)
            names = tc.ST(:,1);
            tc.verifyEqual(numel(names), numel(unique(names)));
        end

        function stateNamesAreOrderedByIndex(tc)
            % S00, S01, ... must appear in numerical order, because the
            % sequencer and every log compare state INDICES.
            for i = 1:size(tc.ST,1)
                expected = sprintf('S%02d_', i-1);
                tc.verifySubstring(tc.ST{i,1}, expected);
            end
        end

        function everyExcelStepIsImplemented(tc)
            % All 42 rows of Sequence.xlsx must be covered by some state.
            refs = [];
            for i = 1:size(tc.ST,1)
                tok = strsplit(strrep(strrep(tc.ST{i,2},'i',''),'*',''), ',');
                for k = 1:numel(tok)
                    v = str2double(strtrim(tok{k}));
                    if ~isnan(v); refs(end+1) = v; end %#ok<AGROW>
                end
            end
            missing = setdiff(1:42, refs);
            tc.verifyEmpty(missing, ...
                sprintf('Excel steps not implemented: %s', mat2str(missing)));
        end

        function everyStateDeclaresAGuard(tc)
            for i = 1:size(tc.ST,1)
                tc.verifyNotEmpty(tc.ST{i,3}, ...
                    sprintf('state %s has no guard', tc.ST{i,1}));
            end
        end

        function onlyOperatorStatesUseTimers(tc)
            % The design rule: a state advances only when a PHYSICAL sensor
            % confirms it, EXCEPT the three manual operator states for which
            % Sequence.xlsx supplies no completion signal. If a fourth timer
            % appears, the model has silently become time-driven somewhere.
            timed = find(strcmpi(tc.ST(:,3), 'timer'));
            tc.verifyLessThanOrEqual(numel(timed), 3, ...
                sprintf(['%d timed transitions found; only the three manual ' ...
                         'operator states may be timed'], numel(timed)));
        end

        % ---- controller initial state ---------------------------------------

        function controllerStartsInStateOne(tc)
            plc = factory_plc_init(tc.P);
            tc.verifyEqual(plc.state, 1);
        end

        function controllerStartsWithNothingEnergised(tc)
            plc = factory_plc_init(tc.P);
            tc.verifyFalse(logical(plc.pump));
            tc.verifyTrue(all(plc.dv   == 0));
            tc.verifyTrue(all(plc.sol  == 0));
            tc.verifyTrue(all(plc.conv == 0));
        end

        function controllerStartsWithNoTimeouts(tc)
            plc = factory_plc_init(tc.P);
            tc.verifyEmpty(plc.timeouts);
        end

        % ---- compressor pressure switch --------------------------------------

        function compressorStopsAtCutOut(tc)
            tc.verifyFalse(tc.steppedPump(true, true, tc.P.P_cut_out + 1));
        end

        function compressorStartsAtCutInWhenEnabled(tc)
            tc.verifyTrue(tc.steppedPump(true, false, tc.P.P_cut_in - 1));
        end

        function compressorStaysOffWhenNotEnabled(tc)
            % Sequence control must override the pressure switch, not race it.
            tc.verifyFalse(tc.steppedPump(false, false, tc.P.P_cut_in - 1));
        end

        function compressorLatchesInsideTheHysteresisBand(tc)
            % Between cut-in and cut-out the pump holds state, it does not
            % chatter. Both directions are checked.
            mid = 0.5*(tc.P.P_cut_in + tc.P.P_cut_out);
            tc.verifyTrue( tc.steppedPump(true, true,  mid));
            tc.verifyFalse(tc.steppedPump(true, false, mid));
        end

        % ---- one scan --------------------------------------------------------

        function dwellTimerResetsOnTransition(tc)
            % t_in measures time IN the current state, so it must restart when
            % the state changes. S00_INIT has an 'immediate' guard, so one
            % scan both transitions and resets.
            plc = factory_plc_init(tc.P);
            plc = factory_plc(plc, factory_sensors(tc.s0, tc.P), 0, tc.P);
            tc.verifyGreaterThan(plc.state, 1, 'precondition: expected a transition');
            tc.verifyEqual(plc.t_in, 0, 'AbsTol', 1e-12, ...
                'dwell timer did not reset when the state changed');
        end

        function dwellTimerAccumulatesWhileWaiting(tc)
            % In a state whose guard is false the timer must accumulate one
            % t_scan per scan; the watchdog depends on it.
            s = tc.s0;
            s(tc.P.IX.bx) = 1e3;      % block far away, so CAM stays false
            s(tc.P.IX.by) = 1e3;
            y = factory_sensors(s, tc.P);

            plc = factory_plc_init(tc.P);
            plc = factory_plc(plc, y, 0, tc.P);   % leave INIT
            held = plc.state;

            n = 5;
            for k = 1:n
                plc = factory_plc(plc, y, k*tc.P.t_scan, tc.P);
            end
            tc.verifyEqual(plc.state, held, ...
                'precondition: the sequencer should have waited here');
            tc.verifyEqual(plc.t_in, n*tc.P.t_scan, 'RelTol', 1e-12, ...
                'dwell timer did not accumulate one t_scan per scan');
        end

        function commandStructCarriesEveryActuatorChannel(tc)
            plc = factory_plc_init(tc.P);
            [~, u] = factory_plc(plc, factory_sensors(tc.s0, tc.P), 0, tc.P);
            for f = {'pump_on','dv','sol','conv','base'}
                tc.verifyTrue(isfield(u, f{1}), ...
                    sprintf('command struct is missing %s', f{1}));
            end
            % The command carries the machine's COILS, not one entry per
            % actuator: 11 actuators, 13 coils, because CYL_A and CYL_B are
            % double-solenoid. NCYL would pass here for the wrong reason.
            tc.verifyNumElements(u.sol,  tc.P.NSOL);
            tc.verifyNumElements(u.conv, tc.P.NCONV);
            tc.verifyNumElements(u.dv,   4);
        end

        function initStateAdvancesImmediately(tc)
            % S00_INIT is an 'immediate' guard; it must not stall the cycle.
            plc = factory_plc_init(tc.P);
            plc = factory_plc(plc, factory_sensors(tc.s0, tc.P), 0, tc.P);
            tc.verifyGreaterThan(plc.state, 1);
        end

    end
end
