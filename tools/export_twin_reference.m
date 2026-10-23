function export_twin_reference(outfile)
%EXPORT_TWIN_REFERENCE  Export the digital twin's nominal cycle for the HMI.
%
%   EXPORT_TWIN_REFERENCE() runs the validated MATLAB model once and writes
%   scada_platform/data/twin_reference.json, which the SCADA backend replays
%   against the live cycle clock to produce the real-vs-predicted comparison.
%
%   EXPORT_TWIN_REFERENCE(OUTFILE) writes somewhere else.
%
%   USAGE
%     >> cd Factory_Simulation
%     >> addpath('<repo>/scada_platform/tools')
%     >> export_twin_reference
%
%   Or non-interactively:
%     matlab -batch "cd('Factory_Simulation'); addpath('../Final/scada_platform/tools'); export_twin_reference"
%
%   WHY AN EXPORT AND NOT A LIVE CO-SIMULATION
%   ------------------------------------------
%   run_factory_simulation is a batch integrator: it solves a whole 31.08 s
%   cycle with RK4 and returns a LOG struct logged at 200 Hz. There is no
%   stepping API and no server, and README.md is explicit that runtime is not
%   a design goal ("A change that makes the model faster but less faithful is
%   a regression here"). Driving a browser from a MATLAB Engine session would
%   therefore mean either rewriting the validated solver into a stepped one --
%   which the brief forbids and which would invalidate the regression tests --
%   or blocking the HMI for 30 s per cycle.
%
%   Exporting the nominal trajectory once gives the operator a genuine
%   reference to diverge from, costs nothing at runtime, and leaves every file
%   of the physics model untouched. This script only READS the model's output.
%
%   WHAT IS EXPORTED
%   ----------------
%     meta         model version, host, export time, provenance counts
%     cycleTime    LOG.cycle_time
%     transitions  every PLC state change: {t, index, state}
%     series       downsampled trajectories the HMI compares against
%     parameters   the tagged parameter list with its provenance codes
%     caveats      the model's own stated limitations, carried through so the
%                  HMI cannot present the twin as better calibrated than it is
%
%   See also RUN_FACTORY_SIMULATION, FACTORY_STATES, EXPORT_EQUIVALENCE_DATA.

if nargin < 1 || isempty(outfile)
    here    = fileparts(mfilename('fullpath'));
    outfile = fullfile(here, '..', 'data', 'twin_reference.json');
end

outdir = fileparts(outfile);
if ~isempty(outdir) && ~exist(outdir, 'dir')
    mkdir(outdir);
end

fprintf('Running the factory simulation (this takes a moment)...\n');
LOG = run_factory_simulation();
ST  = factory_states();

fprintf('Cycle time: %.3f s, complete: %d\n', LOG.cycle_time, LOG.complete);

% ---- state transitions -------------------------------------------------
% LOG.state holds 1-based row indices into ST. The HMI is 0-based, matching
% the convention already used by export_equivalence_data.m, so the two records
% stay directly comparable.
st = LOG.state(:);
tt = LOG.t(:);
changeIdx = [1; find(diff(st) ~= 0) + 1];

transitions = cell(numel(changeIdx), 1);
for i = 1:numel(changeIdx)
    k = st(changeIdx(i));
    transitions{i} = struct( ...
        't',     round(tt(changeIdx(i)), 6), ...
        'index', k - 1, ...
        'state', ST{k, 1}, ...
        'excelRef', ST{k, 2}, ...
        'guard', ST{k, 3});
end

% ---- series ------------------------------------------------------------
% Downsample to ~20 Hz. The HMI refreshes at 4 Hz against a 250 ms PLC poll,
% so shipping the full 200 Hz log would inflate the file roughly tenfold to
% carry detail nothing downstream can use.
targetHz = 20;
n        = numel(tt);
if n > 1
    dt     = median(diff(tt));
    stride = max(1, round((1 / targetHz) / max(dt, eps)));
else
    stride = 1;
end
idx = 1:stride:n;

series = struct();
series.t = roundvec(tt(idx), 4);

% Belt speeds. LOG.v_blt is [nSamples x 3] for the three conveyors.
if isfield(LOG, 'v_blt') && ~isempty(LOG.v_blt)
    v = LOG.v_blt;
    for c = 1:min(3, size(v, 2))
        series.(sprintf('v_belt%d', c)) = roundvec(v(idx, c), 5);
    end
end

% Receiver pressure, converted to bar gauge for display alongside the PLC's
% own pressure reading, which is scaled in bar.
if isfield(LOG, 'P_res') && ~isempty(LOG.P_res)
    series.P_res = roundvec(LOG.P_res(idx) / 1e5, 4);
end

% Engraving base height.
if isfield(LOG, 'base_z') && ~isempty(LOG.base_z)
    series.base_z = roundvec(LOG.base_z(idx), 5);
end

% Workpiece position: x and y if 2-D.
if isfield(LOG, 'blk') && ~isempty(LOG.blk)
    blk = LOG.blk;
    series.blk_x = roundvec(blk(idx, 1), 5);
    if size(blk, 2) > 1
        series.blk_y = roundvec(blk(idx, 2), 5);
    end
end

% Per-cylinder rod positions.
if isfield(LOG, 'rod') && ~isempty(LOG.rod)
    rod = LOG.rod;
    for c = 1:size(rod, 2)
        series.(sprintf('rod%d', c)) = roundvec(rod(idx, c), 5);
    end
end

% ---- provenance --------------------------------------------------------
% Read straight from the parameter set so the HMI cannot drift from the model
% about what has actually been measured.
parameters = {};
caveats    = {};
try
    P = LOG.P;
    if isfield(P, 'prov') && isstruct(P.prov)
        names = fieldnames(P.prov);
        parameters = cell(numel(names), 1);
        for i = 1:numel(names)
            parameters{i} = struct( ...
                'name', names{i}, ...
                'tag',  string(P.prov.(names{i})));
        end
    end
catch
    % A missing provenance struct is not fatal; the HMI degrades to showing
    % the caveats alone.
end

caveats = { ...
  'SCALE (cell dimension scale) is recorded as CONFIRMED INCORRECT in the lab data sheet. All predicted positions inherit that error.'
  '69 of 97 tagged parameters are unmeasured (PLH + ASM + EST). See INPUTS_REQUIRED.md.'
  'Every Janatics component is a technically compatible candidate, not a part confirmed to be installed. No nameplate, BOM or photograph has been supplied.'
  '12.5 s of the 31.08 s nominal cycle is operator/engraving placeholder time with no measured duration.'
  'The model is deterministic: no sensor noise, no actuation jitter, no part-to-part spread. It predicts zero cycle-time variation, so any real variation will read as divergence.'
  'PLC scan time is modelled in form but has never been measured on the real controller.'
  'The model has 5 cylinders and 4 proximity sensors; the real cell has 13 solenoid valves and 10 proximity sensors. The mapping between them is not recorded in any supplied source.'
};

% ---- assemble ----------------------------------------------------------
payload = struct();
payload.schemaVersion = 1;
payload.exportedAt    = posixtime(datetime('now', 'TimeZone', 'UTC'));
payload.exportedAtLocal = datestr(now, 'yyyy-mm-dd HH:MM:SS'); %#ok<TNOW1,DATST>
payload.cycleTime     = round(LOG.cycle_time, 6);
payload.complete      = logical(LOG.complete);
payload.transitions   = transitions;
payload.series        = series;
payload.parameters    = parameters;
payload.caveats       = caveats;

meta = struct();
meta.source          = 'run_factory_simulation';
meta.matlabVersion   = version();
meta.stateCount      = size(ST, 1);
meta.sampleCount     = numel(idx);
meta.sampleRateHz    = targetHz;
meta.originalSamples = n;
if isfield(LOG, 'pos_error'); meta.positionErrorM = round(LOG.pos_error, 6); end
if isfield(LOG, 'air_NL');    meta.airPerCycleNL  = round(LOG.air_NL, 4);    end
payload.meta = meta;

% ---- write -------------------------------------------------------------
json = jsonencode(payload);
fid  = fopen(outfile, 'w');
if fid < 0
    error('export_twin_reference:cannotWrite', 'Could not open %s', outfile);
end
cleanup = onCleanup(@() fclose(fid));
fwrite(fid, json, 'char');

fprintf('\nWrote %s\n', outfile);
fprintf('  %d state transitions\n', numel(transitions));
fprintf('  %d samples at %d Hz (from %d at full rate)\n', numel(idx), targetHz, n);
fprintf('  %d series: %s\n', numel(fieldnames(series)) - 1, ...
        strjoin(setdiff(fieldnames(series), {'t'})', ', '));
fprintf('\nReload it in the HMI: Digital Twin page -> Reload.\n');

end

% -------------------------------------------------------------------------

function v = roundvec(x, digits)
%ROUNDVEC  Round and force a row vector, so jsonencode emits a flat array.
%   A column vector would encode as an array of single-element arrays, which
%   the JavaScript side would then have to unwrap.
v = round(x(:)', digits);
end
