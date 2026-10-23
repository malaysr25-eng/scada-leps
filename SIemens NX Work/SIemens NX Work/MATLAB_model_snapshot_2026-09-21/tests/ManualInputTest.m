classdef ManualInputTest < matlab.unittest.TestCase
    %MANUALINPUTTEST  run_factory_simulation('Operator','console'): a cycle
    %   driven by a person at the console instead of the operator timers.
    %
    %   The answers are SCRIPTED through 'OperatorInput', so nothing here waits
    %   on a keyboard or on a real-time laser pause. What must hold:
    %     - the default run never asks the operator anything
    %     - "skip" takes the SV11 bypass, and nothing else is asked
    %     - "engrave" asks for the laser wait, then ENG DONE, in that order,
    %       with the laser time from FACTORYPARAMS
    %     - the dwell the PLC sees is laser + reaction + the measured confirm
    %     - machine time does not depend on the operator
    %     - bad settings and bad answers are refused by name
    %
    %   Three shared simulation runs, about 45 s.
    %
    %   See also RUN_FACTORY_SIMULATION, FACTORY_OPERATOR_CONSOLE.

    properties
        Lauto     % default run, with an OperatorInput that must never be called
        Leng      % console run, engrave, ENG DONE after 2.0 s
        Lbyp      % console run, skip
        callsEng
        callsByp
    end

    properties (Constant)
        REACTION = 2.0;     % s, the scripted ENG DONE reaction
    end

    methods (TestClassSetup)
        function runThree(tc)
            reset_factory('Quiet', true);
            tc.Lauto = run_factory_simulation('Plot', false, 'Verbose', false, ...
                'OperatorInput', @(varargin) error('ManualInputTest:asked', ...
                'the default run asked the operator something'));
            [fn, tc.callsEng] = scripted(true, tc.REACTION);
            tc.Leng = run_factory_simulation('Plot', false, 'Verbose', false, ...
                'Operator', 'console', 'OperatorInput', fn);
            [fn, tc.callsByp] = scripted(false, tc.REACTION);
            tc.Lbyp = run_factory_simulation('Plot', false, 'Verbose', false, ...
                'Operator', 'console', 'OperatorInput', fn);
        end
    end

    methods (Test)

        function theDefaultRunNeverAsksTheOperator(tc)
            tc.verifyTrue(logical(tc.Lauto.complete));
            tc.verifyEqual(tc.Lauto.P.op_mode, 'nominal');
            tc.verifyFalse(isfield(tc.Lauto, 'operator'), ...
                'an automatic run should carry no operator record');
        end

        function skippingEngravingTakesTheBypass(tc)
            L = tc.Lbyp;
            tc.verifyTrue(logical(L.complete), 'the skipped cycle did not complete');
            tc.verifyFalse(L.P.engrave_selected);
            tc.verifyEqual(L.time_operator, 0);
            tc.verifyEqual(kinds(tc.callsByp), {'engrave?'}, ...
                'a skipped cycle must ask only whether to engrave');
        end

        function engDoneIsAskedAfterTheLaserInOrder(tc)
            tc.verifyEqual(kinds(tc.callsEng), {'engrave?', 'laser', 'eng_done'});
            c = tc.callsEng(2);
            tc.verifyEqual(c{2}, tc.Leng.P.OP.t_laser_50, ...
                'the laser wait must use P.OP.t_laser_50');
        end

        function theDwellIsLaserPlusReactionPlusConfirm(tc)
            L = tc.Leng; P = L.P;
            tc.verifyTrue(logical(L.complete));
            want = P.OP.t_laser_50 + tc.REACTION + P.OP.confirm;
            tc.verifyEqual(L.time_operator, want, 'AbsTol', 1e-9);
            tc.verifyEqual(L.operator.reaction_s, tc.REACTION);
            % and the PLC actually dwelt that long, to within THREE scans. The
            % PLC only changes state on a scan, and the dwell spans three timed
            % states (S24, S25, S26), each of which rounds up to its next scan:
            % S24's 0 s still takes one scan, S25's 6.65 s and S26's 1.297 s
            % each round up by less than one. Seen: 7.970 against 7.947 s.
            te = @(nm) L.plc.log{strcmp(L.plc.log(:,2), nm), 1};
            dwell = te('S27_BASE_DOWN') - te('S24_OPERATOR_NOTIFY');
            tc.verifyEqual(dwell, want, 'AbsTol', 3*P.t_scan + 1e-9);
        end

        function machineTimeDoesNotDependOnTheOperator(tc)
            tc.verifyEqual(tc.Leng.machine_time_rec, tc.Lauto.machine_time_rec, ...
                'AbsTol', 0.02, 'a person at the console changed machine time');
        end

        function anUnknownOperatorModeIsRejected(tc)
            tc.verifyError(@() run_factory_simulation('Operator', 'keyboard', ...
                'Plot', false, 'Verbose', false), 'run_factory_simulation:operator');
        end

        function aNonFunctionOperatorInputIsRejected(tc)
            tc.verifyError(@() run_factory_simulation('Operator', 'console', ...
                'OperatorInput', 42, 'Plot', false, 'Verbose', false), ...
                'run_factory_simulation:operatorInput');
        end

        function aNegativeReactionIsRejected(tc)
            [fn, ~] = scripted(true, -1);
            tc.verifyError(@() run_factory_simulation('Operator', 'console', ...
                'OperatorInput', fn, 'Plot', false, 'Verbose', false), ...
                'run_factory_simulation:reaction');
        end

        function theConsoleRejectsAnUnknownRequest(tc)
            tc.verifyError(@() factory_operator_console('bogus'), ...
                'factory_operator_console:kind');
        end

        function theConsoleLaserWaitIsRealTime(tc)
            t0 = tic;
            evalc('factory_operator_console(''laser'', 0.3);');
            tc.verifyGreaterThanOrEqual(toc(t0), 0.29, ...
                'the laser wait returned before its time');
        end
    end
end

%% ------------------------------------------------------------------------
function [fn, calls] = scripted(engrave, reaction)
%SCRIPTED  An OperatorInput that answers from a script and records each call.
calls = containers.Map('KeyType', 'double', 'ValueType', 'any');
fn = @(kind, info) answer(calls, kind, info, engrave, reaction);
end

function out = answer(calls, kind, info, engrave, reaction)
calls(calls.Count + 1) = {kind, info};
switch kind
    case 'engrave?', out = engrave;
    case 'laser',    out = [];
    case 'eng_done', out = reaction;
    otherwise, error('ManualInputTest:kind', 'unexpected request %s', kind);
end
end

function k = kinds(calls)
k = cell(1, calls.Count);
for i = 1:calls.Count
    c = calls(i); k{i} = c{1};
end
end
