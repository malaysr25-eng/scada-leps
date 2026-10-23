classdef DocumentationFactsTest < matlab.unittest.TestCase
    %DOCUMENTATIONFACTSTEST  Check what the documents CLAIM against what is TRUE.
    %
    %   DOCUMENTATIONTEST already checks that the documents are internally
    %   consistent: counts line up, every test class is listed, every function
    %   is mentioned. What it cannot catch is a document that is perfectly
    %   consistent and simply WRONG. That happened repeatedly, and every time
    %   it happened the suite was green:
    %
    %     - README section 10 carried a provenance table summing to 100 when
    %       the real total was 122, and listed a [SRC] tag that no longer
    %       existed anywhere in the project.
    %     - README section 11 was headed "the scale assumption - unresolved,
    %       highest priority" and stated "this has been confirmed as not
    %       correct", while the same file's own summary table four hundred
    %       lines above said SCALE was confirmed CORRECT.
    %     - The README described the workpiece as "roughly 5x lighter" when the
    %       figure was 1943x. Then 1.55x. Then 1.94x.
    %     - P.dt carried a comment quoting measured stability limits that had
    %       been measured against a completely different workpiece.
    %
    %   None of that is a coding error, so nothing tested it. A number written
    %   in prose is an assertion about the model, and this class holds it to
    %   the same standard as a number written in code.
    %
    %   HOW TO ADD A CLAIM
    %   Add a row to the table CLAIMS builds below:
    %       {file, pattern, expected, tolerance, description}
    %   The pattern is a regular expression with one capture group per number.
    %
    %   TWO RULES THAT MAKE THIS WORTH HAVING:
    %     1. EVERY occurrence must be correct, not just the first. A figure
    %        stated in two places that disagree is exactly the README section
    %        11 failure above.
    %     2. A pattern that matches NOTHING is a FAILURE, not a skip. Without
    %        that, rewording a sentence silently switches its check off, and
    %        the check quietly rots instead of failing loudly.
    %
    %   Patterns are deliberately ASCII-only and tolerant about separators,
    %   because the documents use en-dashes, multiplication signs and
    %   superscripts that do not survive FILEREAD uniformly across platforms.
    %
    %   See also DOCUMENTATIONTEST, AUDIT_PROVENANCE, FACTORYPARAMS.

    properties (Access = private)
        P       % the live parameter set
    end

    methods (Access = private)
        function r = root(~)
            r = fileparts(fileparts(mfilename('fullpath')));
        end

        function t = doc(tc, name)
            t = fileread(fullfile(tc.root(), name));
        end

        function at = assertedNotQuoted(~, txt, phrase)
            %ASSERTEDNOTQUOTED  Occurrences that ASSERT the phrase, not cite it.
            %
            %   A blocklist of overturned claims must not fire on a document
            %   that correctly RECORDS the claim as overturned. This project
            %   does exactly that - INPUTS_REQUIRED says
            %
            %       Six sessions of "SCALE is confirmed wrong" were wrong
            %       about *what* was wrong
            %
            %   which is history, not an assertion. A phrase wrapped in double
            %   quotes is being cited; anywhere else it is being claimed. The
            %   distinction matters: a project that records its own corrections
            %   must be able to quote what it got wrong.
            at = strfind(txt, phrase);
            keep = true(size(at));
            for i = 1:numel(at)
                b = at(i) - 1;  a = at(i) + numel(phrase);
                if b >= 1 && a <= numel(txt) && txt(b) == '"' && txt(a) == '"'
                    keep(i) = false;      % quoted, therefore cited
                end
            end
            at = at(keep);
        end

        function c = claims(tc)
            %CLAIMS  Every numeric assertion the documents make, and its truth.
            %
            %   Built by appending rather than as one cell literal: a blank
            %   line inside a { } literal is read by MATLAB as a ROW separator,
            %   which silently turns this list into a matrix and breaks the
            %   iteration. checkcode caught that; it would not have been
            %   obvious from a passing test.
            Q   = tc.P;
            REG = CycleRegressionTest.REF_CYCLE_TIME;
            c   = {};

            function add(file, pattern, expected, tol, why)
                c{end+1} = {file, pattern, expected, tol, why};
            end

            % the geometry scale, stated in more than one place
            add('README.md', '`SCALE = ([\d.]+)`', Q.SCALE, 1e-9, ...
                'the drawing-unit-to-metre scale');

            % the workpiece, quoted in millimetres
            add('README.md', '(\d+) . (\d+) .\s*(\d+) mm wooden block', ...
                [Q.blk_L Q.blk_W Q.blk_H]*1000, 1e-9, ...
                'workpiece L x W x H');

            add('README.md', 'wooden block . ([\d.]+) kg', Q.blk_m, 1e-9, ...
                'workpiece mass');

            % the solver step
            add('README.md', '`dt = ([\d.]+) ms`', Q.dt*1000, 1e-9, ...
                'the fixed integration step');

            % Cycle time, which must agree with the regression pin.
            %
            % This used to sample the WORKPIECE re-baseline sentence,
            % '31.070 s to 31.030 s'. That sentence is a historical fact about
            % a change made on 2026-08-26 and it stays true and stays put -
            % this project marks findings superseded rather than rewriting
            % them. What it stopped being, on 2026-09-02, is a statement of
            % the CURRENT baseline, because the plant re-model moved the cycle
            % to 31.080 s.
            %
            % So the pin now samples the PLANT re-baseline sentence instead:
            % the live number belongs to the live claim.
            add('README.md', ...
                'Cycle time moved \*\*([\d.]+) s to ([\d.]+) s\*\*', ...
                [31.030 REG], 5e-3, ...
                'cycle time before and after the plant re-model');
        end
    end

    methods (TestClassSetup)
        function buildParameters(tc)
            tc.P = FactoryParams();
        end
    end

    methods (Test)

        function everyQuotedNumberMatchesTheModel(tc)
            % The core check. Each claim's pattern is applied to its document,
            % and EVERY occurrence must agree with the live value.
            cl = tc.claims();
            for k = 1:numel(cl)
                [f, pat, want, tol, why] = cl{k}{:};
                txt = tc.doc(f);
                hits = regexp(txt, pat, 'tokens');

                tc.verifyNotEmpty(hits, sprintf( ...
                    ['%s no longer states %s.\n' ...
                     'Pattern /%s/ matched nothing.\n\n' ...
                     'This is a FAILURE and not a skip on purpose: if a ' ...
                     'reworded sentence quietly disabled its own check, the ' ...
                     'claim would rot unnoticed. Either restore the wording, ' ...
                     'or update the pattern in DocumentationFactsTest.claims ' ...
                     'deliberately.'], f, why, pat));

                for h = 1:numel(hits)
                    got = str2double(hits{h});
                    tc.verifyEqual(got(:).', want(:).', 'AbsTol', tol, sprintf( ...
                        ['%s states the wrong value for %s.\n' ...
                         '  document says : %s\n' ...
                         '  model says    : %s\n' ...
                         '(occurrence %d of %d)\n\n' ...
                         'The document is wrong, not the model - the model is ' ...
                         'what runs. Update %s.'], ...
                        f, why, mat2str(got(:).', 8), mat2str(want(:).', 8), ...
                        h, numel(hits), f));
                end
            end
        end

        function theProvenanceTableMatchesTheLiveAudit(tc)
            % README section 10 quotes a count per provenance tag and a total.
            % It has drifted twice: once summing to 100 against a real 122,
            % once to 138 against a real 143. AUDIT_PROVENANCE is the truth.
            % evalc both runs the audit and suppresses its printed table.
            % It assigns into this workspace, so calling it a second time
            % outside the evalc would run the whole audit twice for nothing.
            evalc('A = audit_provenance();');
            txt = tc.doc('README.md');

            quoted = regexp(txt, '\|\s*`\[(\w+)\]`\s*\|[^|]*\|\s*(\d+)\s*\|', 'tokens');
            tc.assertNotEmpty(quoted, ...
                'README section 10 no longer contains a provenance table.');

            for k = 1:numel(quoted)
                tag = quoted{k}{1};
                said = str2double(quoted{k}{2});
                actual = nnz(strcmp(A.Tag, tag));
                tc.verifyEqual(said, actual, sprintf( ...
                    ['README section 10 says [%s] = %d, audit_provenance ' ...
                     'counts %d.\nRegenerate the table from a live ' ...
                     '`audit_provenance` run.'], tag, said, actual));
            end

            % every tag that really exists must appear in the table
            for realTag = unique(A.Tag).'
                tc.verifyTrue(any(strcmp(cellfun(@(q) q{1}, quoted, ...
                    'UniformOutput', false), realTag{1})), sprintf( ...
                    ['tag [%s] has %d parameters but is missing from the ' ...
                     'README section 10 table.'], realTag{1}, nnz(strcmp(A.Tag, realTag{1}))));
            end

            total = regexp(txt, '\|\s*\|\s*\*\*total\*\*\s*\|\s*\*\*(\d+)\*\*\s*\|', 'tokens', 'once');
            tc.assertNotEmpty(total, 'README section 10 has no total row.');
            tc.verifyEqual(str2double(total{1}), height(A), sprintf( ...
                'README section 10 totals %s, audit_provenance counts %d.', ...
                total{1}, height(A)));
        end

        function noDocumentStillCallsTheScaleUnresolved(tc)
            % SCALE was called "confirmed wrong" for six sessions and is now
            % confirmed correct four ways. The phrasing outlived the belief in
            % three files. A blunt check, but it is the failure that actually
            % happened.
            banned = { ...
                'SCALE is confirmed wrong', ...
                'confirmed as not correct', ...
                'CONFIRMED INCORRECT', ...
                'scale assumption - unresolved', ...
                'The correct scale is not yet known'};
            for f = {'README.md', 'INPUTS_REQUIRED.md'}
                txt = tc.doc(f{1});
                for b = banned
                    live = tc.assertedNotQuoted(txt, b{1});
                    tc.verifyEmpty(live, sprintf( ...
                        ['%s asserts "%s" outside quotation marks.' ...
                         'SCALE = 0.10 is confirmed four ways: tape 760 mm, ' ...
                         'conveyor.stp 775, Conveyor1.STEP 780, ' ...
                         'Conveyor2.STEP 750.'], f{1}, b{1}));
                end
            end
        end

        function noDocumentStillCallsTheWorkpieceUnapplied(tc)
            % The workpiece measurement was RECORDED-NOT-APPLIED for a day and
            % several documents said so. It is applied now.
            banned = {'not yet applied', 'deliberately **not yet applied**', ...
                      'RECORDED, NOT APPLIED - see the'};
            for f = {'README.md', 'INPUTS_REQUIRED.md'}
                txt = tc.doc(f{1});
                for b = banned
                    tc.verifyEmpty(strfind(txt, b{1}), sprintf( ...
                        '%s still describes the workpiece as unapplied.', f{1}));
                end
            end
        end

    end
end
