function export_equivalence_data(outfile)
%EXPORT_EQUIVALENCE_DATA  Dump the MATLAB model's behaviour for cross-checking.
%
%   EXPORT_EQUIVALENCE_DATA(OUTFILE) runs the MATLAB implementation and writes
%   a plain-text record of everything test_model_equivalence.py compares
%   against the Python port: the state table, the state-transition sequence,
%   and the end-of-cycle scalars.
%
%   The format is deliberately dumb - "key value" lines under [SECTION]
%   headers - so the Python side needs no MATLAB file readers and the output
%   can be diffed by eye when a comparison fails.
%
%   This exists to make the MATLAB<->Python equivalence an enforced, repeatable
%   check rather than a manual one. It is test scaffolding: nothing in the
%   simulation depends on it.
%
%   See also RUN_FACTORY_SIMULATION, CHECK_ENVIRONMENT.

if nargin < 1 || isempty(outfile)
    outfile = 'equivalence_matlab.txt';
end

LOG = run_factory_simulation();
ST  = factory_states();

fid = fopen(outfile, 'w');
if fid < 0
    error('export_equivalence_data:cannotWrite', ...
          'could not open %s for writing', outfile);
end
c = onCleanup(@() fclose(fid));

% ---- state table -------------------------------------------------------
% Emitted 0-based so the indices line up with the Python list directly.
fprintf(fid, '[STATES]\n');
for i = 1:size(ST, 1)
    fprintf(fid, '%d\t%s\t%s\n', i - 1, ST{i, 1}, ST{i, 2});
end

% ---- transition sequence ----------------------------------------------
% A transition is any change in the logged state index. The first sample is
% included so the sequence starts at the initial state, matching the Python
% record which logs its own entry state.
%
% NOTE: LOG.state holds MATLAB 1-based row indices into ST, so ST{st,1} is the
% name and st-1 is the 0-based index the Python port uses. Emitting the 0-based
% form keeps the two records directly comparable.
st = LOG.state(:);
tt = LOG.t(:);
ch = [1; find(diff(st) ~= 0) + 1];
fprintf(fid, '[TRANSITIONS]\n');
for i = 1:numel(ch)
    k = st(ch(i));
    fprintf(fid, '%.6f\t%d\t%s\n', tt(ch(i)), k - 1, ST{k, 1});
end

% ---- end-of-cycle scalars ---------------------------------------------
fprintf(fid, '[FINAL]\n');
fprintf(fid, 'cycle_time\t%.9f\n', LOG.cycle_time);
fprintf(fid, 'complete\t%d\n',     LOG.complete);
fprintf(fid, 'blk_x\t%.12f\n',     LOG.blk_final(1));
fprintf(fid, 'blk_y\t%.12f\n',     LOG.blk_final(2));
fprintf(fid, 'pos_error\t%.12f\n', LOG.pos_error);
fprintf(fid, 'air_NL\t%.9f\n',     LOG.air_NL);
fprintf(fid, 'peak_PA\t%.6f\n',    max(LOG.PA(:)));
fprintf(fid, 'peak_PB\t%.6f\n',    max(LOG.PB(:)));
fprintf(fid, 'n_states\t%d\n',     size(ST, 1));

fprintf('export_equivalence_data: wrote %s\n', outfile);
end
