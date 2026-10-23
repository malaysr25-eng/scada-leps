function matlab_live_bridge(varargin)
%MATLAB_LIVE_BRIDGE  Publish live simulation values to the SCADA platform.
%
%   Companion to backend/sources/matlab_source.py. Two transports, matching
%   the two the adapter implements:
%
%     matlab_live_bridge('transport','file', 'path','.../data/matlab_live.json')
%     matlab_live_bridge('transport','tcp',  'host','127.0.0.1','port',5560)
%
%   Options:
%     'values'     function handle returning a struct of the current values.
%                  Default: a demo generator, clearly flagged synthetic.
%     'rate'       publish rate in Hz (default 2)
%     'duration'   seconds to run, Inf to run until Ctrl-C (default Inf)
%
%   USE WITH A RUNNING SIMULINK MODEL
%   ---------------------------------
%   Supply a 'values' handle that reads whatever your model exposes, e.g.
%
%       vals = @() struct( ...
%           'sim_belt1_speed',      get_param('MyModel/Belt1','RuntimeObject').OutputPort(1).Data, ...
%           'sim_receiver_pressure', evalin('base','P_res_now'));
%       matlab_live_bridge('values', vals, 'rate', 5);
%
%   WHY THE FILE TRANSPORT WRITES TO A TEMP FILE FIRST
%   --------------------------------------------------
%   MOVEFILE is atomic. Writing straight to the target means a reader can land
%   between FOPEN (which truncates) and FCLOSE and get a half-written file.
%   That exact defect is what made the legacy SCADA blank every tag for a
%   frame, so it is not optional here.
%
%   STATUS
%   ------
%   This script has NOT been executed against a real MATLAB installation --
%   no licence was available in the environment where the platform was built.
%   The wire format is deliberately trivial (one JSON object, or one per line
%   for TCP) and is documented in docs/DATA_SOURCES.md. Verify it on first use.
%
%   See also EXPORT_TWIN_REFERENCE.

p = inputParser;
addParameter(p, 'transport', 'file', @(s) ismember(s, {'file','tcp'}));
addParameter(p, 'path', fullfile(fileparts(mfilename('fullpath')), '..', ...
                                 'data', 'matlab_live.json'), @ischar);
addParameter(p, 'host', '127.0.0.1', @ischar);
addParameter(p, 'port', 5560, @isnumeric);
addParameter(p, 'values', @demo_values, @(f) isa(f, 'function_handle'));
addParameter(p, 'rate', 2, @isnumeric);
addParameter(p, 'duration', Inf, @isnumeric);
parse(p, varargin{:});
opt = p.Results;

period = 1 / max(opt.rate, 0.1);
t0 = tic;

switch opt.transport
    case 'file'
        outdir = fileparts(opt.path);
        if ~isempty(outdir) && ~exist(outdir, 'dir')
            mkdir(outdir);
        end
        fprintf('Publishing to %s at %.1f Hz. Ctrl-C to stop.\n', opt.path, opt.rate);

        while toc(t0) < opt.duration
            publish_file(opt.path, build_payload(opt.values));
            pause(period);
        end

    case 'tcp'
        fprintf('Connecting to %s:%d ...\n', opt.host, opt.port);
        client = tcpclient(opt.host, opt.port, 'Timeout', 5);
        cleanup = onCleanup(@() clear('client'));  %#ok<NASGU>
        fprintf('Connected. Streaming at %.1f Hz. Ctrl-C to stop.\n', opt.rate);

        while toc(t0) < opt.duration
            line = [jsonencode(build_payload(opt.values)) newline];
            write(client, unicode2native(line, 'UTF-8'));
            pause(period);
        end
end

end

% -------------------------------------------------------------------------

function payload = build_payload(valuesFn)
%BUILD_PAYLOAD  Wrap the current values with a timestamp the adapter trusts.
%
%   The adapter uses this timestamp to decide whether the feed has gone stale,
%   so it must be the time the values were sampled -- not the time they were
%   read at the other end.
payload = struct( ...
    'timestamp', posixtime(datetime('now', 'TimeZone', 'UTC')), ...
    'modelName', 'Factory_Physics_Model', ...
    'values',    valuesFn());
end

% -------------------------------------------------------------------------

function publish_file(target, payload)
%PUBLISH_FILE  Atomic write: temp file in the same directory, then rename.
tmp = [target '.tmp'];

fid = fopen(tmp, 'w');
if fid < 0
    warning('matlab_live_bridge:cannotWrite', 'could not open %s', tmp);
    return
end
fwrite(fid, jsonencode(payload), 'char');
fclose(fid);

% Same filesystem, so this is atomic. A reader sees the old file or the new
% one, never a partial one.
movefile(tmp, target, 'f');
end

% -------------------------------------------------------------------------

function v = demo_values()
%DEMO_VALUES  Synthetic values, for checking the transport end to end.
%
%   Clearly not model output. Replace with a handle that reads your running
%   model -- see the header comment.
t = mod(posixtime(datetime('now', 'TimeZone', 'UTC')), 31.08);
phase = t / 31.08;

v = struct( ...
    'sim_belt1_speed',       0.15 * pulse(phase, 0.10, 0.22), ...
    'sim_belt2_speed',       0.15 * pulse(phase, 0.34, 0.46), ...
    'sim_belt3_speed',       0.15 * pulse(phase, 0.78, 0.90), ...
    'sim_receiver_pressure', 5.5 - 0.9 * phase, ...
    'sim_base_z',            0.12 * pulse(phase, 0.50, 0.72), ...
    'sim_cycle_phase',       phase, ...
    'synthetic',             true);
end

function y = pulse(phase, a, b)
if phase < a || phase > b
    y = 0;
else
    y = sin(pi * (phase - a) / max(b - a, eps));
end
end
