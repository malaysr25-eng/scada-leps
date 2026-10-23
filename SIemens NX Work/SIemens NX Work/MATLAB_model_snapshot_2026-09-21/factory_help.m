function factory_help()
%FACTORY_HELP  Every command in this project, safe to paste at the MATLAB prompt.
%
%   factory_help
%
%   HOW THIS IS LAID OUT, AND WHY
%
%   Each section shows exactly ONE runnable line - the thing you almost always
%   want. Its variants are printed underneath as MATLAB comments, so they are
%   visible but inert. Paste a whole section and precisely one command runs.
%
%   That is deliberate, and it is the third design of this file. The first two
%   both failed in the same way: they printed a MENU of alternatives, and a
%   menu gets used as a SCRIPT.
%
%     Design 1 laid the description out as a second column. Copying a whole
%     line ran, in MATLAB command syntax,
%         build_factory_model('regenerate', 'the', '.slx')
%     Fixed by commenting the descriptions.
%
%     Design 2 listed viewer commands that needed a LOG without showing how to
%     get one. Copying gave "Unrecognized function or variable 'LOG'",
%     whereupon MATLAB helpfully suggested the built-in log().
%
%     Both were symptoms, not the cause. Pasting any multi-line section fired
%     several commands at once: "Run the simulation" ran the simulation twice
%     and then Simulink, about 124 s to reach a result nobody asked for, and
%     "Verify it is still correct" took roughly nine minutes. Alternatives
%     were being read as a sequence.
%
%   So: one runnable line per section, variants inert. Guarded by
%   DocumentationTest/factoryHelpSectionsHaveOneRunnableLine.
%
%   The LOG problem is gone at the root too - the viewers take no argument and
%   obtain a result through FACTORY_LOG, which produces one if none is cached.
%   Pass a LOG explicitly whenever you prefer.
%
%   The commands under TERMINAL at the end are not MATLAB, and are printed
%   commented for that reason.
%
%   See also FACTORY_LOG, CHECK_ENVIRONMENT, RUN_ALL_TESTS, RESET_FACTORY,
%   OPERATOR_DISTRIBUTION, FACTORY_OPERATOR_DRAW, FACTORY_OPERATOR_CONSOLE,
%   FACTORY_VIEW.

b   = @(s) fprintf('\n  %s\n  %s\n', s, repmat('-', 1, numel(s)));
run = @(cmd, what) fprintf('    %-44s %% %s\n', cmd, what);
alt = @(cmd, what) fprintf('      %% %-40s %s\n', cmd, what);

fprintf('\n  FACTORY SIMULATION\n');
fprintf('  %s\n', repmat('=', 1, 74));
fprintf('  One runnable line per section; the variants below it are comments.\n');
fprintf('  Paste a whole section and exactly one command runs.\n');

b('Check the setup');
run('check_environment',                        'MATLAB, Simulink, paths, physics');
alt('check_environment(''Simulink'', true)',      'include the Simulink path');
alt('check_environment(''Toolboxes'', true)',     'audit LICENSED toolboxes');

b('Run the simulation');
run('LOG = run_factory_simulation;',            'the MATLAB path, ~17 s');
alt('run_factory_simulation(''Plot'', false)',    'no results dashboard');
alt('out = run_simulink_model',                 'the Simulink path, ~87 s');
alt('run_simulink_model(''Animate'', true)',      'Simulink run, then replay on the cell');
alt('LOG = out.LOG',                            'same LOG struct, Simulink path');
alt('P = FactoryParams; P.engrave_selected = false;', 'the SV11 bypass - then:');
alt('run_factory_simulation(''Params'', P)',      'engraving skipped, ~8 s');

b('You as the operator (manual input)');
run('LOG = run_factory_simulation(''Operator'',''console'',''Live'',true);', 'watch live; ENG DONE = any key on figure');
alt('run_factory_simulation(''Operator'',''console'')', 'no figure: Enter in the Command Window');
alt('P = FactoryParams; P.OP.t_laser_50',       'the laser wait, 4.65 s placeholder');
alt('P = FactoryParams; P.OP.t_laser_50 = 10;', 'a different laser time - then:');
alt('run_factory_simulation(''Params'',P,''Operator'',''console'')', 'console run with it');
alt('LOG.operator',                            'what you chose, how fast you pressed');

b('See the physical motion');
run('visualize_factory',                        'animated replay, uses factory_log');
alt('visualize_factory(4)',                     'replay at 4x speed');
alt('visualize_factory(4, ''Units'',''drawing'')',  '4x, in drawing units');
alt('run_factory_simulation(''Live'', true)',     'watch the cycle AS IT RUNS, 1x');
alt('plot_factory_results',                     'static results dashboard');

b('2-D physics of each process, end to end');
run('T = visualize_processes;',                 '11 processes + overview');
alt('visualize_processes(''Process'', 3)',        'just one, full size');
alt('visualize_processes(''Save'', true)',        'also write process_view.png');
alt('visualize_processes(''Forces'', false)',     'paths only, no force arrows');

b('Predicted cycle time as a DISTRIBUTION, not one number');
run('R = operator_distribution;',               '10,000 draws from 7 real dwells');
alt('operator_distribution(''Validate'', true)',  're-run 3 sims, recheck additivity');
alt('operator_distribution(''N'', 1000)',         'fewer samples');
alt('P = factory_operator_draw(FactoryParams)',  'ONE random dwell, seed 0');
alt('factory_operator_draw(FactoryParams, 7)',   'the same draw every time, seed 7');

b('Verify it is still correct');
run('run_all_tests',                            'fast MATLAB suite, 201 tests');
alt('run_all_tests(''IncludeSlow'', true)',       'add the Simulink tests, ~5 min');
alt('verify_model',                             'acceptance checks, ~20 s');
alt('R = compare_execution_paths',              'MATLAB vs Simulink, ~105 s');
alt('runtests(''PlcIoTest'')',                    'one test class only');

b('The real machine (PLC data, 2026-08-24)');
run('factory_io_map(''report'')',                 'what is mapped, what is not');
alt('T = PlcTagList',                           'all 121 real PLC tags');
alt('M = factory_io_map',                       'the mapping table itself');
alt('P = FactoryParams; P.REAL',                'observed counts and readings');

b('Inspect the parameters');
run('audit_provenance',                         'count every tagged parameter');
alt('audit_provenance(''List'', true)',           'list them all');
alt('P = FactoryParams',                        'the full parameter struct');

b('Rebuild the Simulink model');
run('build_factory_model',                      'regenerate the .slx');
alt('run_simulink_model(''Rebuild'', true)',      'rebuild, then run');

b('After editing FactoryParams.m or JanaticsData.m');
run('reset_factory',                            'MANDATORY - clears both caches');
alt('reset_factory(''Model'', true)',             'also close the .slx');

fprintf('\n  %s\n', repmat('=', 1, 74));
fprintf('  Physical-fidelity knob, see INPUTS_REQUIRED.md section 3:\n');
fprintf('      %% P = FactoryParams; P.plc_io_delay = 1;\n');
fprintf('      %% LOG = run_factory_simulation(''Params'', P);\n');
fprintf('\n  TERMINAL commands. NOT MATLAB - printed commented so that pasting\n');
fprintf('  them is harmless. Run these from a shell, not from this prompt:\n');
fprintf('      %% matlab -batch "run_all_tests"\n');
fprintf('      %% python -m unittest discover -p "test_*.py"\n\n');
end
