function visualize_factory(LOG, speed, varargin)
%VISUALIZE_FACTORY  Replay the simulated cycle on the original factory layout.
%
%   VISUALIZE_FACTORY(LOG)         replay at 1x
%   VISUALIZE_FACTORY(LOG, speed)  replay at 'speed' x real time
%   VISUALIZE_FACTORY(LOG, speed, 'Units', 'drawing')
%                                  draw on the reference script's own axes
%
%   Options
%     'Units'  'metres'  (default) axes in metres, i.e. the scale the physics
%                        actually runs at: a 1.7 x 1.3 m cell for SCALE = 0.10
%              'drawing' axes in the reference script's drawing units, giving
%                        the familiar 0-18 x 0-12 frame. DISPLAY ONLY -- it
%                        rescales nothing and simulates nothing differently.
%
%   Use 'drawing' to compare against the original reference figure. Do not
%   read it as a claim that the cell is 18 m wide: those are drawing units,
%   which P.SCALE = 0.10 converts to metres. That scale was confirmed on
%   2026-08-25 - conveyor 1 measures 760 mm over 7.6 drawing units.
%
%   A MANUAL-INPUT RUN (run_factory_simulation('Operator','console')) replays
%   with its operator line: what was chosen, the laser running with a violet
%   mark on the block, the wait for ENG DONE, and when it was pressed. To
%   watch a cycle WHILE it runs, use run_factory_simulation('Live', true).
%   Both draw through FACTORY_VIEW, so they cannot drift apart.
%
%   The layout is reproduced from the reference script
%   function multi_station_simulation().txt so the cell stays recognisable.
%
%   CRITICAL: this function is a DISPLAY ONLY. Every position it draws is
%   read from LOG, which was produced by the physics. It computes no motion,
%   interpolates no coordinates and contains no pause()-driven sequencing.
%   Deleting this file would not change the simulation result in any way.
%
%   Compare with the reference script, where move_linear() and
%   animate_block_move() used linspace() to GENERATE the motion. That
%   relationship is now inverted.
%
%   See also FACTORY_VIEW, RUN_FACTORY_SIMULATION, DRAW_CELL_LAYOUT.

% LOG is optional. visualize_factory(4) means "replay at 4x using the cached
% result"; a numeric first argument cannot be a LOG, so it is the speed.
if nargin < 1
    LOG = factory_log();
elseif isnumeric(LOG)
    if nargin >= 2; varargin = [{speed}, varargin]; end
    speed = LOG;
    LOG   = factory_log();
elseif ischar(LOG) || isstring(LOG)
    varargin = [{LOG}, varargin];
    if nargin >= 2; varargin = [varargin, {speed}]; end
    LOG   = factory_log();
    speed = 1;
end
if nargin < 2 || isempty(speed) || ~isnumeric(speed); speed = 1; end
o = struct('Units', 'metres');
o = parse_options(o, varargin, mfilename);

V  = factory_view('open', LOG.P, 'Units', o.Units);
op = factory_view('opfromlog', LOG);          % [] for an automatic run

% ---- replay ------------------------------------------------------------
tic; i = 1; nl = numel(LOG.t);
while i <= nl
    % pick the log sample matching wall-clock time scaled by 'speed'
    i = find(LOG.t >= toc*speed, 1, 'first');
    if isempty(i); i = nl; end
    if ~factory_view('alive', V); return; end     % the window was closed

    factory_view('frame', V, LOG, i);
    if ~isempty(op)
        [s, las] = factory_view('opnote', op, LOG.state(i), LOG.t(i));
        factory_view('note', V, s);
        factory_view('laser', V, las);
    end

    drawnow limitrate;
    if i >= nl; break; end
end
factory_view('done', V, 'Status: Cycle Complete - Part Ejected into Bin');
end
