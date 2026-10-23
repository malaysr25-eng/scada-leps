classdef LiveViewTest < matlab.unittest.TestCase
    %LIVEVIEWTEST  run_factory_simulation('Live', true) and FACTORY_VIEW.
    %
    %   The load-bearing check: a live run computes the SAME LOG as a normal
    %   run. The view reads the state and waits for real time, and must never
    %   write to it. The live runs here use LiveSpeed Inf, so nothing waits on
    %   the wall clock, and scripted answers, so nothing waits on a keyboard.
    %
    %   Also: closing the figure does not stop the run; ENG DONE by a key on
    %   the figure (a modifier key alone does not count); the fallback when the
    %   figure is closed during the wait; the engraved-colour rule; and the
    %   operator line a replay shows.
    %
    %   Four shared runs, about 90 s.
    %
    %   See also FACTORY_VIEW, RUN_FACTORY_SIMULATION, FACTORY_OPERATOR_CONSOLE.

    properties
        Lref        % automatic run
        Llive       % automatic run, live
        Lman        % console run, scripted: engrave, ENG DONE after 2.0 s
        Lmanlive    % the same, live
        newFigLive      % live figures the automatic live run added
        newFigManLive   % ... and the manual live run
    end

    methods (TestClassSetup)
        function runFour(tc)
            % Each live run's figure is found by what it ADDED, not by a total
            % count at the end. The total read 1 instead of 2 in the full suite
            % on 2026-09-14 (it read 2 when this class ran first), so a count
            % depends on what the rest of the suite leaves open.
            reset_factory('Quiet', true);
            tc.Lref  = run_factory_simulation('Plot', false, 'Verbose', false);
            f0 = liveFigs();
            tc.Llive = run_factory_simulation('Plot', false, 'Verbose', false, ...
                'Live', true, 'LiveSpeed', Inf);
            f1 = liveFigs();
            tc.newFigLive = f1(~ismember(f1, f0));
            tc.Lman = run_factory_simulation('Plot', false, 'Verbose', false, ...
                'Operator', 'console', 'OperatorInput', @scriptedAnswer);
            f2 = liveFigs();
            tc.Lmanlive = run_factory_simulation('Plot', false, 'Verbose', false, ...
                'Operator', 'console', 'OperatorInput', @scriptedAnswer, ...
                'Live', true, 'LiveSpeed', Inf);
            f3 = liveFigs();
            tc.newFigManLive = f3(~ismember(f3, f2));
            fprintf(['LiveViewTest setup: live figures %d before, %d after the ' ...
                     'live run, %d before and %d after the manual live run\n'], ...
                    numel(f0), numel(f1), numel(f2), numel(f3));
        end
    end

    methods (TestClassTeardown)
        function shut(~)
            close all force
        end
    end

    methods (Test)

        function aLiveRunComputesTheSameLog(tc)
            sameLog(tc, tc.Llive, tc.Lref);
        end

        function aLiveManualRunComputesTheSameLog(tc)
            sameLog(tc, tc.Lmanlive, tc.Lman);
            tc.verifyEqual(tc.Lmanlive.operator, tc.Lman.operator);
        end

        function theLiveRunsDrewTheCell(tc)
            tc.verifyNumElements(tc.newFigLive, 1, ...
                'the automatic live run should have drawn exactly one figure');
            tc.verifyNumElements(tc.newFigManLive, 1, ...
                'the manual live run should have drawn exactly one figure');
        end

        function closingTheFigureDoesNotStopTheRun(tc)
            L = run_factory_simulation('Plot', false, 'Verbose', false, ...
                'Operator', 'console', 'OperatorInput', @closeThenAnswer, ...
                'Live', true, 'LiveSpeed', Inf);
            tc.verifyTrue(logical(L.complete), 'closing the live figure stopped the cycle');
            tc.verifyEqual(L.machine_time_rec, tc.Lman.machine_time_rec, 'AbsTol', 1e-12);
        end

        function aBadLiveSettingIsRejected(tc)
            tc.verifyError(@() run_factory_simulation('Live', 'yes', ...
                'Plot', false, 'Verbose', false), 'run_factory_simulation:live');
            tc.verifyError(@() run_factory_simulation('Live', true, 'LiveSpeed', 0, ...
                'Plot', false, 'Verbose', false), 'run_factory_simulation:liveSpeed');
        end

        function anEngravedPartTurnsGreen(tc)
            V = factory_view('open', tc.Lref.P);
            c = onCleanup(@() delete(V.fig(isgraphics(V.fig)))); %#ok<NASGU>
            factory_view('frame', V, tc.Lref, numel(tc.Lref.t));
            tc.verifyEqual(get(V.blk, 'FaceColor'), [0.2 0.8 0.2], 'AbsTol', 1e-12);
        end

        function aSkippedPartIsNeverShownEngraved(tc)
            Q = FactoryParams(); Q.engrave_selected = false;
            L = run_factory_simulation('Params', Q, 'Plot', false, 'Verbose', false);
            V = factory_view('open', L.P);
            c = onCleanup(@() delete(V.fig(isgraphics(V.fig)))); %#ok<NASGU>
            factory_view('frame', V, L, numel(L.t));
            tc.verifyEqual(get(V.blk, 'FaceColor'), [0.9 0.5 0.1], 'AbsTol', 1e-12, ...
                'a part that skipped engraving was drawn as engraved');
        end

        function theReplayLineFollowsTheOperator(tc)
            op = factory_view('opfromlog', tc.Lman);
            tc.verifyNotEmpty(op);
            t25 = op.t25;
            [s1, las1] = factory_view('opnote', op, op.iS25, t25 + 1.0);
            tc.verifySubstring(s1, 'LASER ON');
            tc.verifyTrue(las1, 'the laser mark should show while the laser runs');
            [s2, las2] = factory_view('opnote', op, op.iS25, t25 + op.laser_s + 0.5);
            tc.verifySubstring(s2, 'Waiting for ENG DONE');
            tc.verifyFalse(las2);
            s3 = factory_view('opnote', op, op.iS26, t25 + 10);
            tc.verifySubstring(s3, 'ENG DONE pressed after 2.00 s');
            tc.verifyEmpty(factory_view('opfromlog', tc.Lref), ...
                'an automatic run has no operator to show');
        end

        function engDoneAcceptsAKeyOnTheFigure(tc)
            f  = figure('Visible', 'off');
            cf = onCleanup(@() delete(f(isgraphics(f)))); %#ok<NASGU>
            tm = timer('StartDelay', 0.3, 'TimerFcn', @(~, ~) pressKey(f, 'space'));
            ct = onCleanup(@() delete(tm)); %#ok<NASGU>
            start(tm);
            r = callQuietly(struct('fig', f, 'fallback', @() error('LiveViewTest:fallback', ...
                'the fallback ran although the figure was open')));
            tc.verifyGreaterThan(r, 0.2);
            tc.verifyLessThan(r, 5);
        end

        function aModifierKeyAloneIsNotEngDone(tc)
            f  = figure('Visible', 'off');
            cf = onCleanup(@() delete(f(isgraphics(f)))); %#ok<NASGU>
            t1 = timer('StartDelay', 0.2, 'TimerFcn', @(~, ~) pressKey(f, 'shift'));
            t2 = timer('StartDelay', 0.7, 'TimerFcn', @(~, ~) pressKey(f, 'return'));
            ct = onCleanup(@() delete([t1 t2])); %#ok<NASGU>
            start(t1); start(t2);
            r = callQuietly(struct('fig', f));
            tc.verifyGreaterThan(r, 0.6, 'Shift alone was taken as ENG DONE');
        end

        function aClosedFigureFallsBackToTheCommandWindow(tc)
            f  = figure('Visible', 'off');
            tm = timer('StartDelay', 0.3, 'TimerFcn', @(~, ~) delete(f));
            ct = onCleanup(@() delete(tm)); %#ok<NASGU>
            start(tm);
            hit = containers.Map('KeyType', 'char', 'ValueType', 'logical');
            callQuietly(struct('fig', f, 'fallback', @() markFallback(hit)));
            tc.verifyTrue(isKey(hit, 'ran'), ...
                'closing the figure during the wait did not reach the Command Window fallback');
        end
    end
end

%% ------------------------------------------------------------------------
function sameLog(tc, A, B)
for f = {'t', 'blk', 'blk_v', 'rod', 'PA', 'PB', 'state', 'base_z', 'P_res', 'm_air'}
    tc.verifyEqual(A.(f{1}), B.(f{1}), sprintf('the live run changed LOG.%s', f{1}));
end
for f = {'cycle_time', 'cycle_time_rec', 'machine_time_rec', 'air_NL', 'pos_error'}
    tc.verifyEqual(A.(f{1}), B.(f{1}), sprintf('the live run changed LOG.%s', f{1}));
end
end

function out = scriptedAnswer(kind, ~)
switch kind
    case 'engrave?', out = true;
    case 'laser',    out = [];
    case 'eng_done', out = 2.0;
end
end

function out = closeThenAnswer(kind, info)
% Close the live figure when the laser starts, then answer as scripted.
if strcmp(kind, 'laser')
    delete(findall(groot, 'Type', 'figure', 'Tag', 'factory_view'));
end
out = scriptedAnswer(kind, info);
end

function pressKey(f, key)
if isgraphics(f)
    cb = get(f, 'KeyPressFcn');
    if ~isempty(cb); cb(f, struct('Key', key)); end
end
end

function r = callQuietly(info)
r = [];
evalc('r = factory_operator_console(''eng_done'', info);');
end

function markFallback(hit)
hit('ran') = true;
end

function f = liveFigs()
%LIVEFIGS  Every open figure FACTORY_VIEW has drawn.
f = findall(groot, 'Type', 'figure', 'Tag', 'factory_view');
end
