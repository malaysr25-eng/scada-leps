function o = parse_options(o, args, fname)
%PARSE_OPTIONS  Apply Name/Value arguments to a defaults struct, with real errors.
%
%   o = PARSE_OPTIONS(defaults, varargin, mfilename)
%
%   Every entry point in this project takes its options as Name/Value pairs.
%   They all used to do it with
%
%       for i = 1:2:numel(varargin); o.(varargin{i}) = varargin{i+1}; end
%
%   which has two failure modes, both of which reached a user:
%
%     1. An ODD number of arguments indexes past the end and reports
%           Index exceeds the number of array elements. Index must not exceed 3.
%        which names neither the function nor the offending argument.
%
%        This is what happens if you paste a whole line out of FACTORY_HELP,
%        description column and all. MATLAB command syntax turns
%            build_factory_model regenerate the .slx
%        into build_factory_model('regenerate','the','.slx') - three char
%        arguments. FACTORY_HELP now comments its descriptions out so that
%        pasting a whole line is harmless, and this function explains the
%        error if it happens anyway.
%
%     2. An unknown or misspelled option is SILENTLY ACCEPTED, because
%        assigning to a new field just creates it. 'Verbos' instead of
%        'Verbose' had no effect and gave no warning.
%
%   PARSE_OPTIONS rejects both, names the function, and lists what is valid.
%
%   See also FACTORY_HELP.

if nargin < 3 || isempty(fname); fname = 'this function'; end
valid = fieldnames(o);

if mod(numel(args), 2) ~= 0
    txt = cellfun(@describe, args, 'UniformOutput', false);
    error('parse_options:oddPairs', ...
        ['%s takes Name/Value pairs, but received %d arguments:\n    %s\n\n' ...
         'A Name/Value list must have an even number of arguments.\n\n' ...
         'If you pasted a line out of FACTORY_HELP, paste only the command - ' ...
         'the description after it was read as arguments. In MATLAB command ' ...
         'syntax, "%s a b c" means %s(''a'',''b'',''c'').\n\n' ...
         'Valid options: %s'], ...
        upper(fname), numel(args), strjoin(txt, ', '), ...
        fname, fname, strjoin(valid', ', '));
end

for i = 1:2:numel(args)
    name = args{i};
    if ~(ischar(name) || isstring(name)) || ~isvector(name)
        error('parse_options:badName', ...
            ['%s expected an option NAME in position %d, but got a %s.\n' ...
             'Valid options: %s'], ...
            upper(fname), i, class(name), strjoin(valid', ', '));
    end
    name = char(name);
    hit = valid(strcmpi(valid, name));
    if isempty(hit)
        error('parse_options:unknownOption', ...
            '''%s'' is not an option of %s.\nValid options: %s', ...
            name, upper(fname), strjoin(valid', ', '));
    end
    o.(hit{1}) = args{i+1};       % canonical case, so 'verbose' sets 'Verbose'
end
end

%% ------------------------------------------------------------------------
function s = describe(v)
%DESCRIBE  Short readable form of one argument, for the error message.
if ischar(v)
    s = ['''' v ''''];
elseif isstring(v) && isscalar(v)
    s = ['"' char(v) '"'];
elseif isnumeric(v) && isscalar(v)
    s = num2str(v);
elseif islogical(v) && isscalar(v)
    s = mat2str(v);
else
    s = ['<' class(v) ' ' mat2str(size(v)) '>'];
end
end
