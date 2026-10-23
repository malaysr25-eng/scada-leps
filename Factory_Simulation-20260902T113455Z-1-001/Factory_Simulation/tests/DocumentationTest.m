classdef DocumentationTest < matlab.unittest.TestCase
    %DOCUMENTATIONTEST  Guards the documentation against silent drift.
    %
    %   Documentation rot is invisible to every other test in this suite. The
    %   README claimed 98 tests while the suite was 114, and had no description
    %   for five files that had already been added, committed and used. Nothing
    %   failed, because nothing was looking.
    %
    %   These tests look. They assert only facts that are mechanically checkable
    %   and that go stale on their own:
    %
    %     - the test count the README quotes is the count the suite has
    %     - every test class is listed in README and in run_all_tests
    %     - every function in the project root is mentioned in the README
    %     - every function named in a README matlab block actually resolves
    %
    %   Deliberately NOT asserted: timings ("about 98 s"), which are
    %   machine-dependent, and prose accuracy, which no test can judge.
    %
    %   Fast: parses files, runs no simulation.
    %
    %   See also RUN_ALL_TESTS.

    properties (Constant)
        % Files that legitimately need no README entry, each with its reason.
        README_EXEMPT = { ...
            'factory_params_cached.m'   % internal cache, documented in situ
            'factory_plc_init.m'        % constructor for factory_plc
            'export_equivalence_data.m' % developer utility for the Python port
            };
    end

    methods (Access = private)
        function r = root(~)
            r = fileparts(fileparts(mfilename('fullpath')));
        end
        function t = readme(tc)
            t = fileread(fullfile(tc.root(), 'README.md'));
        end
        function s = fastSuite(tc)
            s = matlab.unittest.TestSuite.fromFolder(fullfile(tc.root(),'tests'));
            s = s.selectIf(~matlab.unittest.selectors.HasTag('Slow'));
        end
    end

    methods (Test)

        function readmeTestCountMatchesTheSuite(tc)
            % The requested guard. Enumerating a suite does not RUN it, so this
            % is cheap and cannot recurse.
            txt = tc.readme();
            n   = regexp(txt, '(\d+)\s+tests, about', 'tokens');
            tc.assertNotEmpty(n, ...
                ['README no longer states a test count in the form ' ...
                 '"<N> tests, about <T> s." Restore it or update this test.']);
            tc.assertNumElements(n, 1, ...
                'README states a test count more than once; they can disagree.');

            stated = str2double(n{1}{1});
            actual = numel(tc.fastSuite());
            tc.verifyEqual(stated, actual, sprintf( ...
                ['README says %d tests, the suite has %d.\n' ...
                 'Update the count in README.md section 9 (Testing).'], ...
                stated, actual));
        end

        function everyTestClassIsListedInTheReadme(tc)
            txt = tc.readme();
            d   = dir(fullfile(tc.root(), 'tests', '*.m'));
            missing = {};
            for i = 1:numel(d)
                cls = erase(d(i).name, '.m');
                if ~contains(txt, ['`' cls '`'])
                    missing{end+1} = cls; %#ok<AGROW>
                end
            end
            tc.verifyEmpty(missing, sprintf( ...
                'these test classes are not listed in README section 9: %s', ...
                strjoin(missing, ', ')));
        end

        function everyTestClassIsListedInRunAllTests(tc)
            % run_all_tests documents the suite in its own header. It drifts too.
            hdr = fileread(fullfile(tc.root(), 'run_all_tests.m'));
            d   = dir(fullfile(tc.root(), 'tests', '*.m'));
            missing = {};
            for i = 1:numel(d)
                cls = erase(d(i).name, '.m');
                if ~contains(hdr, cls)
                    missing{end+1} = cls; %#ok<AGROW>
                end
            end
            tc.verifyEmpty(missing, sprintf( ...
                ['these test classes are missing from the run_all_tests ' ...
                 'header: %s'], strjoin(missing, ', ')));
        end

        function everyProjectFunctionIsMentionedInTheReadme(tc)
            % This is the check that would have caught visualize_processes,
            % draw_cell_layout, parse_options, factory_help and
            % audit_provenance all being added without a README entry.
            txt = tc.readme();
            d   = dir(fullfile(tc.root(), '*.m'));
            missing = {};
            for i = 1:numel(d)
                if any(strcmp(d(i).name, tc.README_EXEMPT)); continue; end
                if ~contains(txt, d(i).name)
                    missing{end+1} = d(i).name; %#ok<AGROW>
                end
            end
            tc.verifyEmpty(missing, sprintf( ...
                ['these project files are never mentioned in README.md: %s\n' ...
                 'Add them to section 4 and section 7, or list them in ' ...
                 'DocumentationTest.README_EXEMPT with a reason.'], ...
                strjoin(missing, ', ')));
        end

        function handoffQuotesTheRealFastSuiteCount(tc)
            % HANDOFF section 2 quotes the same counts and drifts the same way;
            % it said 93/93 while the suite was 114. It writes them as "N / N",
            % so require that pair to appear for the real fast-suite size.
            %
            % HANDOFF.md sits in Project_Notes/, a sibling of this folder, so
            % that this folder can be shared on its own. Somebody holding only
            % the simulation folder has no HANDOFF.md, and this test has
            % nothing to say to them - hence assume rather than verify.
            f = fullfile(tc.root(), '..', 'Project_Notes', 'HANDOFF.md');
            tc.assumeTrue(isfile(f), ...
                'Project_Notes/HANDOFF.md is absent; nothing for this to check.');
            hnd = fileread(f);
            n   = numel(tc.fastSuite());
            tc.verifyTrue(contains(hnd, sprintf('%d / %d', n, n)), sprintf( ...
                ['Project_Notes/HANDOFF.md does not quote the real fast-suite ' ...
                 'count of %d.\nUpdate the run_all_tests line in HANDOFF ' ...
                 'section 2.'], n));
        end

        function factoryHelpQuotesTheRealTestCount(tc)
            % factory_help prints "fast MATLAB suite, N tests" and drifts just
            % like the README did - it sat at 86 while the suite was 134,
            % because nothing was checking it. Now something is.
            txt = evalc('factory_help');
            n   = regexp(txt, 'fast MATLAB suite,\s*(\d+)\s*tests', 'tokens', 'once');
            tc.assertNotEmpty(n, ...
                ['factory_help no longer prints "fast MATLAB suite, N tests". ' ...
                 'Restore that wording or update this test.']);
            tc.verifyEqual(str2double(n{1}), numel(tc.fastSuite()), sprintf( ...
                ['factory_help says %s tests, the suite has %d.\n' ...
                 'Update the run_all_tests line in factory_help.m.'], ...
                n{1}, numel(tc.fastSuite())));
        end

        function factoryHelpSectionsHaveOneRunnableLine(tc)
            % THE guard for factory_help's design. Each section must offer
            % exactly one runnable line, with its variants printed as inert
            % comments, so that pasting a whole section runs one command.
            %
            % Two earlier designs listed alternatives as if they were a
            % sequence. Pasting "Run the simulation" ran the simulation twice
            % and then Simulink - about 124 s - and "Verify it is still
            % correct" took roughly nine minutes. Both were paste-safe in the
            % narrow sense of not erroring, which is why only a structural
            % check catches this.
            txt   = evalc('factory_help');
            lines = strsplit(txt, newline);
            sec   = '(preamble)';
            runnable = containers.Map('KeyType','char','ValueType','any');
            order = {};
            for k = 1:numel(lines)
                L = lines{k};
                if startsWith(L, '  ') && ~startsWith(L, '   ') && ~isempty(strtrim(L))
                    t = strtrim(L);
                    if ~all(ismember(t, '-=')) && ~contains(t, '%')
                        sec = t;
                        if ~isKey(runnable, sec)
                            runnable(sec) = {}; order{end+1} = sec; %#ok<AGROW>
                        end
                    end
                    continue
                end
                if ~startsWith(L, '    '); continue; end
                t = strtrim(L);
                if isempty(t) || startsWith(t, '%'); continue; end
                if ~isKey(runnable, sec); runnable(sec) = {}; order{end+1} = sec; end %#ok<AGROW>
                runnable(sec) = [runnable(sec), {t}];
            end
            bad = {};
            for i = 1:numel(order)
                cmds = runnable(order{i});
                if numel(cmds) > 1
                    bad{end+1} = sprintf('"%s" has %d runnable lines: %s', ...
                        order{i}, numel(cmds), strjoin(cmds, ' | ')); %#ok<AGROW>
                end
            end
            tc.verifyEmpty(bad, sprintf(['factory_help sections must offer ONE ' ...
                'runnable line, variants commented:\n  %s'], ...
                strjoin(bad, sprintf('\n  '))));
        end

        function everyCommandInTheReadmeResolves(tc)
            % Names invoked inside ```matlab blocks must exist. A renamed or
            % deleted function otherwise leaves the README quietly telling the
            % reader to run something that errors.
            txt   = tc.readme();
            blks  = regexp(txt, '```matlab\s*\n(.*?)```', 'tokens');
            local = {};        % variables assigned earlier in the same block
            bad   = {};
            for b = 1:numel(blks)
                lines = strsplit(blks{b}{1}, newline);
                for k = 1:numel(lines)
                    L = strtrim(lines{k});
                    if isempty(L) || startsWith(L, '%'); continue; end
                    % record assignment targets so they are not treated as calls
                    lhs = regexp(L, '^([A-Za-z]\w*)\s*=', 'tokens', 'once');
                    if ~isempty(lhs); local{end+1} = lhs{1}; end %#ok<AGROW>
                    % every identifier used as a call or a bare statement
                    for st = strsplit(L, ';')
                        s = strtrim(st{1});
                        if isempty(s); continue; end
                        s = regexprep(s, '^[A-Za-z]\w*\s*=\s*', '');
                        nm = regexp(strtrim(s), '^([a-z_]\w*)', 'tokens', 'once');
                        if isempty(nm); continue; end
                        nm = nm{1};
                        if any(strcmp(nm, local)); continue; end
                        if exist(nm, 'file') || exist(nm, 'builtin') ...
                                || ~isempty(which(nm))
                            continue
                        end
                        bad{end+1} = nm; %#ok<AGROW>
                    end
                end
            end
            tc.verifyEmpty(unique(bad), sprintf( ...
                'README matlab blocks invoke names that do not resolve: %s', ...
                strjoin(unique(bad), ', ')));
        end

    end
end
