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

P = LOG.P; S = P.SCALE; ST = factory_states();

% K converts a METRE quantity into whatever the axes are displaying. Every
% coordinate below is metres (LOG, P.CYL, P.PROX, P.CAM, P.blk_L/W), so a single
% multiplier keeps the layout, the workpiece and the rods in one frame.
switch lower(o.Units)
    case 'metres',  K = 1;           ulab = 'm';
    case 'drawing', K = 1/S;         ulab = 'drawing units';
    otherwise
        error('visualize_factory:units', ...
              "Units must be 'metres' or 'drawing', got '%s'", o.Units);
end

fig = figure('Name','Factory Layout Simulation (physics-driven)', ...
             'Color',[0.12 0.12 0.12]);
ax  = axes('Parent',fig,'Color',[0.08 0.08 0.08]);
hold(ax,'on'); grid(ax,'on'); axis(ax,'equal');
ax.XColor = [0.8 0.8 0.8]; ax.YColor = [0.8 0.8 0.8];
xlim(ax,[-1 18]*S*K); ylim(ax,[-1 13]*S*K);
xlabel(ax,sprintf('X Position (%s)',ulab));
ylabel(ax,sprintf('Y Position (%s)',ulab));
title(ax,'Automated Assembly Line - Physics-Based Simulation', ...
      'Color','w','FontSize',13);

% ---- static cell -------------------------------------------------------
% The geometry lives in DRAW_CELL_LAYOUT so this replay and the per-process
% panels in VISUALIZE_PROCESSES cannot drift apart. Nudging a rectangle in one
% file and not the other is exactly the failure it prevents.
draw_cell_layout(ax, P, K);

% ---- moving objects ----------------------------------------------------
wL = P.blk_L*K;  wW = P.blk_W*K;   % x and y extents, drawn to scale
blk = rectangle(ax,'Position',[LOG.blk(1,1)*K-wL/2, LOG.blk(1,2)*K-wW/2, wL, wW], ...
                'FaceColor',[0.9 0.5 0.1],'EdgeColor','k','LineWidth',1.5);
% One rod per PLACED actuator. Any whose position is not known have
% tip0 = lat = NaN and are deliberately not drawn; DRAW_CELL_LAYOUT names them
% on the figure instead. Drawing a NaN line would leave them silently absent,
% which is the failure mode this project keeps trying to avoid.
%
% PLACED, not CONTACT. CYL_B is a real cylinder with real geometry that is
% barred from touching the workpiece, and it should still be animated.
rods = gobjects(1,P.NCYL);
for c = 1:P.NCYL
    if ~P.CYL(c).placed; continue; end
    rods(c) = line(ax,[0 0],[0 0],'LineWidth',5,'Color','c');
end
sta = text(ax,0,12.3*S*K,'','Color','y','FontSize',11,'FontWeight','bold');
inf = text(ax,0,-0.6*S*K,'','Color',[0.7 0.9 0.7],'FontSize',9);

% ---- replay ------------------------------------------------------------
tic; i = 1; nl = numel(LOG.t);
while i <= nl
    % pick the log sample matching wall-clock time scaled by 'speed'
    i = find(LOG.t >= toc*speed, 1, 'first');
    if isempty(i); i = nl; end

    set(blk,'Position',[LOG.blk(i,1)*K-wL/2, LOG.blk(i,2)*K-wW/2, wL, wW]);
    if LOG.state(i) >= 26; set(blk,'FaceColor',[0.2 0.8 0.2]); end

    for c = 1:P.NCYL
        C = P.CYL(c);
        if ~C.placed; continue; end
        tip = (C.tip0 + C.dir*LOG.rod(i,c))*K;
        if C.axis == 'x'
            set(rods(c),'XData',[C.tip0*K tip],'YData',[C.lat*K C.lat*K]);
        else
            set(rods(c),'XData',[C.lat*K C.lat*K],'YData',[C.tip0*K tip]);
        end
    end

    set(sta,'String',sprintf('Status: %s   (Excel step %s)', ...
        strrep(ST{LOG.state(i),1},'_',' '), ST{LOG.state(i),2}));
    set(inf,'String',sprintf(['t = %6.2f s    block = (%.3f, %.3f) m    ' ...
        '|v| = %.3f m/s    receiver = %.2f bar    base z = %.1f mm'], ...
        LOG.t(i), LOG.blk(i,1), LOG.blk(i,2), ...
        hypot(LOG.blk_v(i,1),LOG.blk_v(i,2)), ...
        LOG.P_res(i)/1e5, 1000*LOG.base_z(i)));

    drawnow limitrate;
    if i >= nl; break; end
end
set(sta,'String','Status: Cycle Complete - Part Ejected into Bin');
end
