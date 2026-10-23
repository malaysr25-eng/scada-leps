function T = audit_provenance(varargin)
%AUDIT_PROVENANCE  Count and list every provenance-tagged parameter.
%
%   audit_provenance                 print the tag summary
%   audit_provenance('List', true)   also list every tagged parameter
%   T = audit_provenance(...)        return a table
%
%   Every parameter in FACTORYPARAMS and JANATICSDATA carries a provenance tag
%   in its trailing comment. This counts them, so the figures quoted in
%   INPUTS_REQUIRED.md are derived rather than hand-maintained.
%
%     [PLH] placeholder, must be replaced         needs real data
%     [ASM] engineering assumption, in no source  needs real data
%     [EST] engineering estimate                  needs real data
%     [JAN] Janatics catalogue figure             PROVISIONAL, needs confirming
%     [COMM] commissioning setting                read it off the machine
%     [CAL] calculated from the above             recomputes itself
%     [REF] from the reference layout script      inherits SCALE
%     [PLC] OBSERVED on the real machine's PLC     no - this IS the real data
%     [MEAS] MEASURED by hand on the machine      no - this IS the real data
%     [CAD] read from the vendor solid model     no - this IS the real data
%
%   ONLY ASSIGNMENT LINES ARE COUNTED. A plain text search also matches the
%   ten-line tag legend in each file header and overcounts every tag.
%
%   Example
%     audit_provenance('List', true)
%
%   See also FACTORYPARAMS, JANATICSDATA.

o = struct('List', false);
o = parse_options(o, varargin, mfilename);

tags  = {'PLH','ASM','EST','JAN','COMM','CAL','REF','PLC','MEAS','CAD'};
needs = {'yes','yes','yes','provisional','read off machine','no','inherits SCALE','NO - observed fact','NO - measured on the machine', ...
         'NO - read from the vendor CAD'};
here  = fileparts(mfilename('fullpath'));
files = {'FactoryParams.m','JanaticsData.m'};

name = {}; tag = {}; src = {}; lineno = []; desc = {};
for f = 1:numel(files)
    txt = strsplit(fileread(fullfile(here, files{f})), newline);
    for k = 1:numel(txt)
        L = txt{k};
        % an assignment, then a comment carrying the tag
        m = regexp(L, '^[^%]*=[^%]*%\s*\[(PLH|ASM|EST|JAN|COMM|CAL|REF|PLC|MEAS|CAD)\]\s*(.*)$', 'tokens', 'once');
        if isempty(m); continue; end
        lhs = strtrim(extractBefore(L, '='));
        name{end+1}   = lhs;                       %#ok<AGROW>
        tag{end+1}    = m{1};                      %#ok<AGROW>
        desc{end+1}   = strtrim(m{2});             %#ok<AGROW>
        src{end+1}    = files{f};                  %#ok<AGROW>
        lineno(end+1) = k;                         %#ok<AGROW>
    end
end

T = table(name(:), tag(:), src(:), lineno(:), desc(:), ...
          'VariableNames', {'Parameter','Tag','File','Line','Description'});

fprintf('\n  PROVENANCE AUDIT  (assignment lines only)\n');
fprintf('  %s\n', repmat('-', 1, 62));
fprintf('  %-6s %6s   %s\n', 'tag', 'count', 'needs real data?');
n_unmeasured = 0;
for i = 1:numel(tags)
    c = sum(strcmp(T.Tag, tags{i}));
    fprintf('  %-6s %6d   %s\n', ['[' tags{i} ']'], c, needs{i});
    if any(strcmp(tags{i}, {'PLH','ASM','EST'})); n_unmeasured = n_unmeasured + c; end
end
fprintf('  %s\n', repmat('-', 1, 62));
fprintf('  %-6s %6d\n', 'TOTAL', height(T));
fprintf('  %-6s %6d   PLH + ASM + EST\n', 'UNMEAS', n_unmeasured);
fprintf('  %6s %6d   provisional Janatics figures\n', '', sum(strcmp(T.Tag,'JAN')));
fprintf('\n  See INPUTS_REQUIRED.md for what to supply for each.\n\n');

if o.List
    for i = 1:numel(tags)
        sel = T(strcmp(T.Tag, tags{i}), :);
        if isempty(sel); continue; end
        fprintf('  [%s]  %d entries\n', tags{i}, height(sel));
        for k = 1:height(sel)
            fprintf('    %-24s %-16s:%-4d %s\n', sel.Parameter{k}, ...
                    erase(sel.File{k}, '.m'), sel.Line(k), sel.Description{k});
        end
        fprintf('\n');
    end
end

if nargout == 0; clear T; end
end
