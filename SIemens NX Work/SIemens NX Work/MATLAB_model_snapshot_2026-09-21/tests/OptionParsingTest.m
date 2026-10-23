classdef OptionParsingTest < matlab.unittest.TestCase
    %OPTIONPARSINGTEST  Name/Value option handling across every entry point.
    %
    %   These exist because a user pasted a whole line out of FACTORY_HELP,
    %   description column and all:
    %
    %       build_factory_model                    regenerate the .slx
    %
    %   MATLAB command syntax turned that into
    %   build_factory_model('regenerate','the','.slx'), and the old parser
    %
    %       for i = 1:2:numel(varargin); o.(varargin{i}) = varargin{i+1}; end
    %
    %   indexed past the end and reported only
    %
    %       Index exceeds the number of array elements. Index must not exceed 3.
    %
    %   naming neither the function nor the cause. The same parser also
    %   SILENTLY ACCEPTED misspelled options, because assigning to a new struct
    %   field just creates it.
    %
    %   Fast: nothing here runs a simulation.
    %
    %   See also PARSE_OPTIONS, FACTORY_HELP.

    methods (Test)

        % ---- parse_options itself ------------------------------------------

        function oddArgumentCountIsRejected(tc)
            tc.verifyError(@() parse_options(struct('A',1), {'A'}, 'thing'), ...
                'parse_options:oddPairs');
        end

        function theOddCountErrorNamesTheFunctionAndTheArguments(tc)
            % The whole point is that the message is actionable, so assert on
            % its content, not just that it threw.
            try
                parse_options(struct('Save',true), {'regenerate','the','.slx'}, ...
                              'build_factory_model');
                tc.verifyFail('expected an error');
            catch ME
                tc.verifySubstring(ME.message, 'BUILD_FACTORY_MODEL');
                tc.verifySubstring(ME.message, '''regenerate''');
                tc.verifySubstring(ME.message, 'FACTORY_HELP');
                tc.verifySubstring(ME.message, 'Save');   % lists valid options
            end
        end

        function unknownOptionIsRejected(tc)
            % Previously this silently created a field and did nothing.
            tc.verifyError(@() parse_options(struct('Verbose',true), ...
                {'Verbos', false}, 'run_all_tests'), ...
                'parse_options:unknownOption');
        end

        function unknownOptionErrorListsTheValidOnes(tc)
            try
                parse_options(struct('Verbose',true,'IncludeSlow',false), ...
                              {'Verbos', false}, 'run_all_tests');
                tc.verifyFail('expected an error');
            catch ME
                tc.verifySubstring(ME.message, 'Verbose');
                tc.verifySubstring(ME.message, 'IncludeSlow');
            end
        end

        function aNonStringOptionNameIsRejected(tc)
            tc.verifyError(@() parse_options(struct('A',1), {42, 'x'}, 'thing'), ...
                'parse_options:badName');
        end

        function validPairsAreApplied(tc)
            o = parse_options(struct('Plot',true,'Verbose',true), ...
                              {'Plot', false}, 'thing');
            tc.verifyFalse(o.Plot);
            tc.verifyTrue(o.Verbose, 'untouched defaults must survive');
        end

        function optionNamesAreCaseInsensitiveButStoredCanonically(tc)
            o = parse_options(struct('Verbose',true), {'verbose', false}, 'thing');
            tc.verifyFalse(o.Verbose, 'lower-case name should set the field');
            tc.verifyEqual(fieldnames(o), {'Verbose'}, ...
                'must not create a second, differently-cased field');
        end

        function emptyArgumentsLeaveTheDefaults(tc)
            d = struct('A',1,'B','two');
            tc.verifyEqual(parse_options(d, {}, 'thing'), d);
        end

        % ---- the entry points actually use it -------------------------------

        function everyEntryPointUsesParseOptions(tc)
            % Structural guard: if someone reintroduces the raw loop anywhere,
            % this fails. That loop is the defect, not a style preference.
            here  = fileparts(fileparts(mfilename('fullpath')));
            files = dir(fullfile(here, '*.m'));
            offenders = {};
            for i = 1:numel(files)
                if strcmp(files(i).name, 'parse_options.m'); continue; end
                txt = fileread(fullfile(here, files(i).name));
                if contains(txt, 'varargin{i}) = varargin{i+1}')
                    offenders{end+1} = files(i).name; %#ok<AGROW>
                end
            end
            tc.verifyEmpty(offenders, sprintf(...
                ['these still use the unguarded option loop: %s\n' ...
                 'Replace it with:  o = parse_options(o, varargin, mfilename);'], ...
                strjoin(offenders, ', ')));
        end

        function entryPointsRejectABadOptionEndToEnd(tc)
            % Cheap ones only - none of these starts a simulation before the
            % option parse, so the error arrives immediately.
            tc.verifyError(@() run_all_tests('NoSuchOption', 1), ...
                'parse_options:unknownOption');
            tc.verifyError(@() reset_factory('NoSuchOption', 1), ...
                'parse_options:unknownOption');
            tc.verifyError(@() audit_provenance('NoSuchOption', 1), ...
                'parse_options:unknownOption');
        end

        function entryPointsRejectAnOddArgumentCountEndToEnd(tc)
            tc.verifyError(@() reset_factory('Quiet'), 'parse_options:oddPairs');
            tc.verifyError(@() audit_provenance('List'), 'parse_options:oddPairs');
        end

        % ---- the toolbox audit ----------------------------------------------

        function checkEnvironmentAcceptsTheToolboxesOption(tc)
            env = check_environment('Toolboxes', true, 'Quiet', true);
            tc.verifyTrue(isfield(env, 'toolboxes'));
            tc.verifyNotEmpty(env.toolboxes, 'the audit reported nothing');
            for f = {'name','installed','licensed','unblocks'}
                tc.verifyTrue(isfield(env.toolboxes, f{1}), ...
                    sprintf('toolbox audit is missing field %s', f{1}));
            end
        end

        function theToolboxAuditDoesNotAffectWhetherTheEnvironmentIsOk(tc)
            % None of the audited toolboxes is needed to run the model, so a
            % missing one is an opportunity, not a failure. If this ever flips,
            % check_environment would start reporting a broken setup on a
            % machine that runs the model perfectly well.
            a = check_environment('Quiet', true);
            b = check_environment('Quiet', true, 'Toolboxes', true);
            tc.verifyEqual(b.ok, a.ok, ...
                'the toolbox audit changed env.ok');
        end

        % ---- factory_help output is safe to paste ---------------------------

        function factoryHelpCommentsOutItsDescriptions(tc)
            % Copying a whole line out of factory_help must be harmless.
            %
            % The property under test: if a line has a COLUMN GAP -- two or more
            % spaces separating the command from trailing prose -- then the
            % prose must begin with %, or MATLAB command syntax parses it as
            % arguments. That is exactly what produced
            %     build_factory_model('regenerate','the','.slx')
            %
            % Lines with no column gap (a complete statement, or the clearly
            % labelled terminal commands) are left alone.
            %
            % An earlier version of this test SKIPPED lines with no %, which is
            % the failure case, so it passed against a deliberately broken
            % factory_help. Mutation testing caught that; do not reintroduce it.
            txt   = evalc('factory_help');
            lines = strsplit(txt, newline);
            bad   = {};
            for i = 1:numel(lines)
                s = strtrim(lines{i});
                if isempty(s) || all(ismember(s, '-=')); continue; end
                % A line that STARTS with % is wholly a comment - that is how
                % factory_help prints its inert variants. Nothing after the %
                % can execute, so the column-gap rule does not apply.
                if startsWith(s, '%'); continue; end
                tok = regexp(s, '^(\S.*?)\s{2,}(\S.*)$', 'tokens', 'once');
                if isempty(tok); continue; end      % no column gap, nothing to split
                if ~startsWith(tok{2}, '%')
                    bad{end+1} = s; %#ok<AGROW>
                end
            end
            tc.verifyEmpty(bad, sprintf(...
                ['these factory_help lines have trailing prose that is NOT ' ...
                 'commented, so pasting the whole line passes it as ' ...
                 'arguments:\n  %s'], strjoin(bad, sprintf('\n  '))));
            tc.verifySubstring(txt, 'exactly one command runs');
        end

    end
end
