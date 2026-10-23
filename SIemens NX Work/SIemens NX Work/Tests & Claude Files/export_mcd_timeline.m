function files = export_mcd_timeline(outdir)
%EXPORT_MCD_TIMELINE  Write the validated MATLAB cycle as a replay timeline for NX MCD.
%
%   files = EXPORT_MCD_TIMELINE()          write next to this file
%   files = EXPORT_MCD_TIMELINE(outdir)    write into OUTDIR
%
%   Runs the model twice - the engraved route and the SV11 bypass - and writes
%   one JSON file per route:
%
%     mcd_timeline_engraved.json
%     mcd_timeline_bypass.json
%
%   Each holds, on the model's own clock:
%     outputs           every on/off EDGE of the signals a PLC drives, named as
%                       the real PLC tags: Conveyor1..3, Solenoid_valve1..13,
%                       Engraving_Completed. These are what MCD should READ.
%     expected_sensors  the model's edges for Proximity_sensor1..10. MCD makes
%                       its own sensor signals; these are for CHECKING them.
%     positions         rods 1-11 and the engraving platform in mm, 20 Hz, for
%                       driving joints by position instead of by coil.
%     states            every sequencer state entered, with its time.
%
%   MCD_REPLAY_SERVER.PY plays these files over OPC UA.
%
%   Nothing here is hand-typed: every time comes from LOG.cmd_sol, LOG.cmd_conv,
%   LOG.sens and LOG.plc.log of a real run. LOG.cmd_sol was added to
%   RUN_FACTORY_SIMULATION on 2026-09-19 for exactly this.
%
%   Engraving_Completed has no falling edge in the model (it has no reset
%   step), so it rises when the operator confirms (S26) and stays high to the
%   end of the cycle. That is stated in the file too.

here = fileparts(mfilename('fullpath'));
if nargin < 1 || isempty(outdir); outdir = here; end
repo = fullfile(here, '..', '..', 'Factory_Simulation', 'Factory_Simulation');
addpath(repo);

reset_factory('Quiet', true);
P = FactoryParams();
Leng = run_factory_simulation('Params', P, 'Plot', false, 'Verbose', false);
Q = P; Q.engrave_selected = false;
Lbyp = run_factory_simulation('Params', Q, 'Plot', false, 'Verbose', false);
assert(isfield(Leng, 'cmd_sol'), ...
    'This LOG has no cmd_sol. Pull the Factory_Simulation change of 2026-09-19.');

[~, commit] = system(sprintf('git -C "%s" rev-parse --short HEAD', repo));
[~, dirty]  = system(sprintf('git -C "%s" status --porcelain', repo));
src = struct('model', 'Factory_Simulation / run_factory_simulation', ...
             'commit', strtrim(commit), 'uncommitted_changes', ~isempty(strtrim(dirty)), ...
             'generated', char(datetime('now', 'Format', 'yyyy-MM-dd HH:mm:ss')));

files = { writeRoute(Leng, 'engraved', src, outdir), ...
          writeRoute(Lbyp, 'bypass',   src, outdir) };
fprintf('Wrote\n  %s\n  %s\n', files{:});
end

% ------------------------------------------------------------------------
function f = writeRoute(L, route, src, outdir)
P = L.P;
t = L.t(:);

out = struct();
for k = 1:size(L.cmd_conv, 2)
    out.(sprintf('Conveyor%d', k)) = edges(t, L.cmd_conv(:, k) ~= 0);
end
for k = 1:size(L.cmd_sol, 2)
    out.(sprintf('Solenoid_valve%d', k)) = edges(t, L.cmd_sol(:, k));
end
t26 = stateTime(L, 'S26_ENGRAVE_CONFIRM');
if isnan(t26)
    out.Engraving_Completed = {{0, false}};
else
    out.Engraving_Completed = {{0, false}, {round(t26, 3), true}};
end

sens = struct();
for k = 1:numel(P.PROX_NAME)
    col = strcmp(L.sens_name, P.PROX_NAME{k});
    sens.(sprintf('Proximity_sensor%d', k)) = edges(t, L.sens(:, col));
end

tp  = (0:0.05:t(end))';
idx = arrayfun(@(x) find(t >= x, 1, 'first'), tp);
pos = struct('t', round(tp, 3), ...
             'Platform_z_mm', round(1000 * L.base_z(idx), 2));
names = cell(1, P.NCYL);
for c = 1:P.NCYL
    pos.(sprintf('Rod%d_mm', c)) = round(1000 * L.rod(idx, c), 2);
    names{c} = P.CYL(c).name;
end
pos.rod_names = names;

st = L.plc.log;
states = cellfun(@(tt, nm) {round(tt, 3), nm}, st(:, 1), st(:, 2), 'UniformOutput', false);

doc = struct( ...
    'schema', 'bits-mcd-replay/1', ...
    'route', route, ...
    'source', src, ...
    'cycle_time_s', round(L.cycle_time, 3), ...
    'to_S37_s', round(L.cycle_time_rec, 3), ...
    'notes', {{ ...
        'outputs: what a PLC drives - MCD reads these', ...
        'expected_sensors: the model''s own sensor edges - for checking MCD, not for driving it', ...
        'Engraving_Completed: rises at S26 (operator confirm) and has no falling edge in the model', ...
        'times in seconds from camera detect; positions in mm'}}, ...
    'outputs', out, ...
    'expected_sensors', sens, ...
    'positions', pos, ...
    'states', {states});

f = fullfile(outdir, sprintf('mcd_timeline_%s.json', route));
fid = fopen(f, 'w');
fprintf(fid, '%s', jsonencode(doc, 'PrettyPrint', true));
fclose(fid);
end

function e = edges(t, x)
% {{t0, value}, {t, value}, ...}: the starting level, then every change.
x = logical(x(:));
e = {{0, x(1)}};
k = find(diff(x) ~= 0) + 1;
for i = k'
    e{end+1} = {round(t(i), 3), x(i)}; %#ok<AGROW>
end
end

function tt = stateTime(L, name)
hit = find(strcmp(L.plc.log(:, 2), name), 1);
if isempty(hit); tt = NaN; else; tt = L.plc.log{hit, 1}; end
end
