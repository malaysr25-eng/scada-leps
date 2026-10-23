function results = run_all_tests(varargin)
%RUN_ALL_TESTS  Run the project's MATLAB test suite.
%
%   run_all_tests()                        fast suite (default)
%   run_all_tests('IncludeSlow', true)     also build and run Simulink
%   results = run_all_tests(...)           return the TestResult array
%
%   Options
%     'IncludeSlow'  include tests tagged 'Slow' (default false). The
%                    Simulink tests build the model and run a full cycle at a
%                    0.5 ms fixed step with an interpreted S-function, which
%                    takes several minutes.
%     'Verbose'      print the per-test table (default true)
%
%   Figures stay hidden during the run: DefaultFigureVisible is 'off' until
%   the run ends, and is put back even after an error or Ctrl+C. Several
%   tests draw figures. On screen they take focus, and closing one by hand
%   during a run removes a figure a later check may count. That is a
%   possible cause of LiveViewTest's missing live figure on 2026-09-14, but
%   it was never confirmed. Added 2026-09-15.
%
%   WHAT IS COVERED
%     ParametersTest        parameter set, provenance chain, derived
%                           quantities, state-vector layout, fault defaults
%     PhysicsTest           factory_derivatives, factory_sensors,
%                           support_region
%     SequencerTest         factory_plc, factory_states, pressure switch
%     CycleRegressionTest   full cycle, physical invariants and the pinned
%                           Iteration-03 reference values, including the
%                           cycle to S37 where the recorder stops its clock
%     BypassRouteTest       the SV11 bypass route (P.engrave_selected = false):
%                           the states it walks, what moves and what does not,
%                           and that the block still reaches the bin
%     PlcIoTest             the real PLC tag register, the model's mapping to
%                           it, and that P.REAL cannot drift from the register
%     DocumentationTest     that README and this header still describe the
%                           suite and the project files that actually exist
%     DocumentationFactsTest  that numbers written in PROSE match the model
%     ProcessViewTest       visualize_processes: that the process table
%                           partitions every engraved-route state with no gap
%                           or overlap, and that the logged forces are consistent
%     CompareToRecordingTest  compare_to_recording: every mapped state pair
%                           re-timed from the LOG's own conveyor and sensor
%                           edges on both routes, and that a route-labelled
%                           extraction feeds each route only its own cycles
%     OptionParsingTest     Name/Value option handling on every entry point,
%                           and that FACTORY_HELP output is safe to paste
%     OperatorDistributionTest  that FACTORY_PARAMS stays deterministic, that
%                           FACTORY_OPERATOR_DRAW only ever returns one of the
%                           seven observed dwells, and that machine time is
%                           still independent of the dwell - which is the
%                           assumption OPERATOR_DISTRIBUTION is built on - and
%                           taken at the same end point as the observed cycles
%     LiveViewTest          run_factory_simulation('Live', true) and FACTORY_VIEW:
%                           a live run computes the same LOG as a normal one,
%                           closing the figure does not stop it, ENG DONE by a
%                           key on the figure, and the engraved-colour rule
%     ManualInputTest       run_factory_simulation('Operator','console'): the
%                           engrave/skip question, the laser wait then ENG
%                           DONE, and that the operator changes the dwell but
%                           not machine time. Answers are scripted, no keyboard
%     PlcIoLatencyTest      P.plc_io_delay: that delay 1 reproduces the
%                           historical Simulink numbers, that the shift is a
%                           whole number of scans, and that it accumulates
%     StateflowSequenceTest the Stateflow chart against FACTORY_PLC. It is
%                           NOT equivalent - a characterisation test pins the
%                           38-scan divergence so it cannot drift silently
%     SimulinkModelTest     build, run, sample times, and exact agreement with
%                           the MATLAB path                      [Slow]
%
%   The Python suite is separate and covers the reference ports plus the
%   MATLAB/Python equivalence check:
%       python -m unittest discover -p "test_*.py"
%
%   EVERY ITERATION SHOULD RUN THIS BEFORE BEING CONSIDERED DONE. Record the
%   result in Project_Notes/ITERATION_LOG.md.
%
%   See also VERIFY_MODEL, CHECK_ENVIRONMENT.

o = struct('IncludeSlow', false, 'Verbose', true);
o = parse_options(o, varargin, mfilename);

here = fileparts(mfilename('fullpath'));
addpath(here);
addpath(fullfile(here, 'tests'));

suite = matlab.unittest.TestSuite.fromFolder(fullfile(here, 'tests'));

if ~o.IncludeSlow
    suite = suite.selectIf(~matlab.unittest.selectors.HasTag('Slow'));
end

runner = matlab.unittest.TestRunner.withTextOutput;
% Hidden figures for the run; see the header. onCleanup puts the setting
% back however the run ends.
vis0 = get(groot, 'DefaultFigureVisible');
set(groot, 'DefaultFigureVisible', 'off');
restoreVis = onCleanup(@() set(groot, 'DefaultFigureVisible', vis0));
results = runner.run(suite);
clear restoreVis

np = nnz([results.Passed]);
ni = nnz([results.Incomplete]);
nt = numel(results);
nf = nt - np - ni;
fprintf('\n  %s\n', repmat('=', 1, 72));
fprintf('  MATLAB TEST SUITE: %d / %d passed, %.1f s\n', ...
        np, nt, sum([results.Duration]));
if ~o.IncludeSlow
    fprintf('  (Simulink tests skipped. Use run_all_tests(''IncludeSlow'', true).)\n');
end
% Incomplete is not Failed. A test filtered by an assumption is one that had
% nothing to check here - DocumentationTest's HANDOFF check does exactly that
% when Project_Notes/ is absent, which is the normal state of a shared copy of
% this folder. Reporting it as a failure would tell somebody their copy is
% broken when it is not.
if ni > 0
    fprintf('  SKIPPED (assumption not met, not a failure):\n');
    skipped = results([results.Incomplete]);
    for i = 1:numel(skipped)
        fprintf('    %s\n', skipped(i).Name);
    end
end
if nf > 0
    fprintf('  FAILURES:\n');
    bad = results(~[results.Passed] & ~[results.Incomplete]);
    for i = 1:numel(bad)
        fprintf('    %s\n', bad(i).Name);
    end
end
fprintf('  %s\n\n', repmat('=', 1, 72));

if nargout == 0
    clear results
end
end
