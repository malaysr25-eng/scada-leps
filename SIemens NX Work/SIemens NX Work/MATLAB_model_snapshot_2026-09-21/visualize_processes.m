function T = visualize_processes(LOG, varargin)
%VISUALIZE_PROCESSES  The 2-D physics of every process, end to end.
%
%   visualize_processes(LOG)
%   visualize_processes(LOG, 'Name', value, ...)
%   T = visualize_processes(...)   also returns a per-process summary table
%
%   Options
%     'Units'    'metres' (default) or 'drawing'   display scale only
%     'Process'  []  all processes in one figure (default)
%                k  draw only process k, full size
%     'Forces'   true/false  draw the force vectors            (default true)
%     'Save'     true/false  write process_view.png beside the code (default false)
%
%   WHAT EACH PANEL SHOWS
%   One panel per process, plus an end-to-end overview. Within a panel:
%
%     grey line      the path the workpiece actually took, from LOG
%     hollow square  where it started; filled square where it ended
%     cyan arrow     rod-tip contact force on the workpiece      F_rod
%     orange arrow   belt / plate friction                       F_fric
%     red arrow      locating-stop reaction                      F_stop
%     green arrow    workpiece velocity
%     cyan bars      the rods, at the instant drawn
%
%   The vectors are drawn at the instant of PEAK NET FORCE inside that
%   process, which is the moment the mechanism is doing the most work. Arrow
%   lengths are scaled per panel, because a 0.1 N friction force and a 100 N
%   contact force cannot share one scale; every magnitude is printed.
%
%   WHERE THE FORCES COME FROM
%   They are NOT recomputed here. FACTORY_DERIVATIVES returns the breakdown as
%   its optional second output, RUN_FACTORY_SIMULATION logs it from the very
%   same call that produces the logged acceleration, and this function only
%   draws what is in LOG. So the arrows cannot disagree with the motion, and
%   deleting this file changes no simulation result.
%
%   The breakdown satisfies F_rod + F_stop + F_fric = F_net exactly, and
%   F_net = blk_m * blk_a. PhysicsTest asserts both.
%
%   WORKS ON EITHER EXECUTION PATH. RUN_FACTORY_SIMULATION logs the breakdown
%   directly; RUN_SIMULINK_MODEL reconstructs it in SIMOUT_TO_LOG by
%   re-evaluating FACTORY_DERIVATIVES at each logged sample, which is exact
%   because the .slx logs both the full plant state and the command vector.
%   Until 2026-08-24 a Simulink LOG was rejected outright.
%
%   Example
%     LOG = run_factory_simulation('Plot', false);
%     T   = visualize_processes(LOG)
%
%   See also RUN_FACTORY_SIMULATION, VISUALIZE_FACTORY, DRAW_CELL_LAYOUT.

% LOG is optional. Called with no arguments, or with an option name first,
% the result comes from FACTORY_LOG - which produces one if none is cached.
% That removes this project's commonest error, an undefined LOG.
if nargin < 1
    LOG = factory_log();
elseif ischar(LOG) || isstring(LOG)
    varargin = [{LOG}, varargin];      % first arg was an option name
    LOG = factory_log();
end

o = struct('Units','metres', 'Process',[], 'Forces',true, 'Save',false);
o = parse_options(o, varargin, mfilename);

if ~isfield(LOG,'F_net')
    error('visualize_processes:noForces', ...
        ['This LOG carries no force breakdown, so there is nothing to draw.\n' ...
         'Both execution paths supply one, so this LOG was probably built ' ...
         'by hand or came from an older version.\nProduce a fresh one:\n' ...
         '    LOG = run_factory_simulation(''Plot'', false);\n' ...
         '    out = run_simulink_model(''Plot'', false); LOG = out.LOG;']);
end

P = LOG.P; S = P.SCALE;
switch lower(o.Units)
    case 'metres',  K = 1;     ulab = 'm';
    case 'drawing', K = 1/S;   ulab = 'drawing units';
    otherwise
        error('visualize_processes:units', ...
              "Units must be 'metres' or 'drawing', got '%s'", o.Units);
end

P_DEF = process_table(P);
np    = size(P_DEF,1);

if isempty(o.Process)
    sel = 1:np; nr = 3; nc = 4; withOverview = true;
else
    validateattributes(o.Process, {'numeric'}, ...
        {'scalar','integer','>=',1,'<=',np}, mfilename, 'Process');
    sel = o.Process; nr = 1; nc = 1; withOverview = false;
end

fig = figure('Name','Per-process 2-D physics (physics-driven)', ...
             'Color',[0.12 0.12 0.12], 'Position',[60 60 1500 900]);

% ---- summary table, built as the panels are drawn ----------------------
nameC = {}; stateC = {}; durC = []; distC = []; vpkC = []; fpkC = []; mechC = {};

k = 0;
if withOverview
    k = k + 1;
    ax = subplot(nr, nc, k, 'Parent', fig);
    draw_overview(ax, LOG, P, K, ulab, P_DEF);
end

for i = sel
    k = k + 1;
    ax = subplot(nr, nc, k, 'Parent', fig);
    r  = draw_process(ax, LOG, P, K, P_DEF(i,:), o.Forces);
    nameC{end+1} = P_DEF{i,1};       stateC{end+1} = sprintf('%d-%d', P_DEF{i,2}, P_DEF{i,3}); %#ok<AGROW>
    durC(end+1)  = r.dur;            distC(end+1)  = r.dist;   %#ok<AGROW>
    vpkC(end+1)  = r.vpk;            fpkC(end+1)   = r.fpk;    %#ok<AGROW>
    mechC{end+1} = P_DEF{i,4};       %#ok<AGROW>
end

sgtitle(fig, sprintf(['Factory cell - 2-D physics of each process, end to end' ...
    '   (cycle %.2f s, axes in %s)'], LOG.cycle_time, ulab), ...
    'Color','w','FontSize',13,'FontWeight','bold');

if o.Save
    f = fullfile(fileparts(mfilename('fullpath')), 'process_view.png');
    % exportgraphics is R2020a+. print works everywhere, and the project
    % documents an R2018b floor, so fall back rather than raise it.
    if exist('exportgraphics','file') == 2
        exportgraphics(fig, f, 'BackgroundColor',[0.12 0.12 0.12], 'Resolution',150);
    else
        set(fig,'InvertHardcopy','off','PaperPositionMode','auto');
        print(fig, f, '-dpng', '-r150');
    end
    fprintf('Wrote %s\n', f);
end

T = table(nameC(:), stateC(:), durC(:), 1000*distC(:), vpkC(:), fpkC(:), mechC(:), ...
    'VariableNames', {'Process','States','Duration_s','Distance_mm', ...
                      'PeakSpeed_ms','PeakForce_N','Mechanism'});
if nargout == 0
    disp(T); clear T
end
end

%% ========================================================================
function D = process_table(P)
%PROCESS_TABLE  The end-to-end chain, grouped into physical processes.
%   {name, first PLC state, last PLC state, mechanism}
%   State numbers index FACTORY_STATES. The chain depends on the ROUTE. The
%   engraved route walks S00-S39 in order. The SV11 bypass (P.engrave_selected
%   false) leaves at S16 for S40-S43 and rejoins at S33, so its table skips
%   the engraving station and lists the bypass push in its place.
%
%   THE PUSH/BELT BOUNDARY, 2026-09-13 (plan H7). Belt 2 was 'Belt 2
%   transports' 16-18 (S15-S17), and the push 13-15, until this date. Since
%   H5 belt 2 starts WITH the transfer push, in S13, not in S15 after it.
%   A state may sit in only one process, so the boundary is drawn where the
%   rod lets go of the part. In S14, the retract, the belt carries it alone:
%   180 mm at 0.310 m/s with 0 N of rod force. So S14 now belongs to the
%   belt. Before H7 the part was still moving when S15 began, so the old
%   window caught the belt speed anyway. With the nameplate barrels it
%   reaches the belt-2 stop during S14, and the old window saw 0.049 m/s.
%   S32, cylinder B's retract, stays with the push. The rod still touches
%   the part as S32 begins (366 N), and the part is coasting off the push at
%   0.25 m/s, faster than belt 3's 0.150.
if nargin >= 1 && isfield(P, 'engrave_selected') && ~P.engrave_selected
    D = { ...
     'Feed and detect',        1,  2, 'workpiece at rest, camera sees it'
     'Pressurise and select',  3,  6, 'receiver charges, distribution valve selects'
     'A1 pushes to belt 1',    7,  9, 'pneumatic contact force, x axis'
     'Belt 1 transports',     10, 12, 'belt friction drives the part'
     'A6 pushes to belt 2',   13, 14, 'pneumatic contact force, y axis'
     'Belt 2 transports',     15, 17, 'belt friction drives the part'
     'SV11 bypass to belt 3', 41, 44, 'pneumatic contact force, x axis'
     'Belt 3 transports',     34, 36, 'belt friction drives the part'
     'S3A2 ejects to bin',    37, 40, 'pneumatic contact force, x axis'
    };
    return
end
D = { ...
 'Feed and detect',        1,  2, 'workpiece at rest, camera sees it'
 'Pressurise and select',  3,  6, 'receiver charges, distribution valve selects'
 'A1 pushes to belt 1',    7,  9, 'pneumatic contact force, x axis'
 'Belt 1 transports',     10, 12, 'belt friction drives the part'
 'A6 pushes to belt 2',   13, 14, 'pneumatic contact force, y axis'
 'Belt 2 transports',     15, 18, 'belt friction drives the part'
 'S2A1 to engraving base',19, 22, 'pneumatic contact force, x axis'
 'Engrave (base up/down)',23, 29, 'vertical axis, part rides the base'
 'S3A1 pushes to belt 3', 30, 33, 'pneumatic contact force, y axis'
 'Belt 3 transports',     34, 36, 'belt friction drives the part'
 'S3A2 ejects to bin',    37, 40, 'pneumatic contact force, x axis'
};
end

%% ========================================================================
function draw_overview(ax, LOG, P, K, ulab, D)
%DRAW_OVERVIEW  The whole path, coloured by process.
hold(ax,'on'); axis(ax,'equal'); grid(ax,'on');
set(ax,'Color',[0.08 0.08 0.08],'XColor',[0.8 0.8 0.8],'YColor',[0.8 0.8 0.8]);
draw_cell_layout(ax, P, K, 'Labels', false, 'Alpha', 0.35);

cmap = lines(size(D,1));
for i = 1:size(D,1)
    m = LOG.state >= D{i,2} & LOG.state <= D{i,3};
    if ~any(m); continue; end
    plot(ax, LOG.blk(m,1)*K, LOG.blk(m,2)*K, '-', ...
         'Color', cmap(i,:), 'LineWidth', 2.2);
end
plot(ax, LOG.blk(1,1)*K,   LOG.blk(1,2)*K,   'ws','MarkerSize',9,'LineWidth',1.6);
plot(ax, LOG.blk(end,1)*K, LOG.blk(end,2)*K, 'ws','MarkerSize',9, ...
     'LineWidth',1.6,'MarkerFaceColor','w');

xlim(ax,[-1 18]*P.SCALE*K); ylim(ax,[-1 13]*P.SCALE*K);

% ---- arrow legend, so the other panels read without the docs -----------
leg = { 'rod contact', [0 0.85 1]
        'friction',    [1 0.6 0.15]
        'stop',        [1 0.3 0.3]
        'velocity',    [0.4 1 0.4] };
xl = xlim(ax); yl = ylim(ax);
for i = 1:size(leg,1)
    text(ax, xl(1)+0.03*diff(xl), yl(2)-(0.05+0.055*i)*diff(yl), ...
         ['-> ' leg{i,1}], 'Color', leg{i,2}, ...
         'FontSize', 7.5, 'FontWeight','bold');
end

title(ax, sprintf('End to end  (%d processes)', size(D,1)), ...
      'Color','w','FontSize',10,'FontWeight','bold');
xlabel(ax, sprintf('x (%s)', ulab), 'Color',[0.8 0.8 0.8], 'FontSize',8);
ylabel(ax, sprintf('y (%s)', ulab), 'Color',[0.8 0.8 0.8], 'FontSize',8);
end

%% ========================================================================
function r = draw_process(ax, LOG, P, K, d, showF)
%DRAW_PROCESS  One process: path, forces at peak load, and its numbers.
name = d{1}; s0 = d{2}; s1 = d{3};
hold(ax,'on'); axis(ax,'equal'); grid(ax,'on');
set(ax,'Color',[0.08 0.08 0.08],'XColor',[0.8 0.8 0.8],'YColor',[0.8 0.8 0.8]);
draw_cell_layout(ax, P, K, 'Labels', false, 'Alpha', 0.35);

m  = LOG.state >= s0 & LOG.state <= s1;
r  = struct('dur',0,'dist',0,'vpk',0,'fpk',0);

if ~any(m)
    title(ax, sprintf('%s  -- not reached', name), 'Color',[1 0.5 0.5], 'FontSize',9);
    xlim(ax,[-1 18]*P.SCALE*K); ylim(ax,[-1 13]*P.SCALE*K);
    return
end

idx  = find(m);
path = LOG.blk(idx,:);
vmag = hypot(LOG.blk_v(idx,1), LOG.blk_v(idx,2));
fmag = hypot(LOG.F_net(idx,1), LOG.F_net(idx,2));

r.dur  = LOG.t(idx(end)) - LOG.t(idx(1));
r.dist = norm(path(end,:) - path(1,:));
r.vpk  = max(vmag);
r.fpk  = max(fmag);

% ---- path and endpoints ------------------------------------------------
plot(ax, path(:,1)*K, path(:,2)*K, '-', 'Color',[0.75 0.75 0.8], 'LineWidth',2);
wL = P.blk_L*K;  wW = P.blk_W*K;   % x and y extents, drawn to scale
rectangle(ax,'Position',[path(1,1)*K-wL/2, path(1,2)*K-wW/2, wL, wW], ...
          'EdgeColor',[0.9 0.9 0.9],'LineWidth',1.2);
rectangle(ax,'Position',[path(end,1)*K-wL/2, path(end,2)*K-wW/2, wL, wW], ...
          'FaceColor',[0.9 0.5 0.1],'EdgeColor','k','LineWidth',1.2);

% ---- frame the action, BEFORE drawing arrows -------------------------
% The arrow scale is derived from the panel span, so the limits have to be
% settled first. Scaling by block size instead made the vectors unreadable.
pad = 4*max(P.blk_L, P.blk_W)*K;
xr  = [min(path(:,1)) max(path(:,1))]*K + [-pad pad];
yr  = [min(path(:,2)) max(path(:,2))]*K + [-pad pad];
if diff(xr) < 6*pad; c0 = mean(xr); xr = c0 + [-3 3]*pad; end
if diff(yr) < 6*pad; c0 = mean(yr); yr = c0 + [-3 3]*pad; end
xlim(ax, xr); ylim(ax, yr);

% ---- the instant of peak net force ------------------------------------
[~, j] = max(fmag); i0 = idx(j);
px = LOG.blk(i0,1)*K; py = LOG.blk(i0,2)*K;

% rods, drawn where they were at that instant
for c = 1:P.NCYL
    C = P.CYL(c); tip = (C.tip0 + C.dir*LOG.rod(i0,c))*K;
    if C.axis == 'x'
        line(ax, [C.tip0*K tip], [C.lat*K C.lat*K], 'LineWidth',3,'Color',[0 0.8 0.9]);
    else
        line(ax, [C.lat*K C.lat*K], [C.tip0*K tip], 'LineWidth',3,'Color',[0 0.8 0.9]);
    end
end

if showF
    % One length scale per panel: forces here span orders of magnitude, so a
    % shared absolute scale would render most arrows invisible. 22% of the
    % smaller panel span reads clearly without covering the layout.
    L  = 0.22 * min(diff(xr), diff(yr));
    F  = [LOG.F_rod(i0,:); LOG.F_fric(i0,:); LOG.F_stop(i0,:)];
    fs = max(hypot(F(:,1), F(:,2)));
    if fs > 1e-9
        col = {[0 0.85 1], [1 0.6 0.15], [1 0.3 0.3]};
        for q = 1:3
            if hypot(F(q,1), F(q,2)) < 1e-9; continue; end
            quiver(ax, px, py, F(q,1)/fs*L, F(q,2)/fs*L, 0, ...
                   'Color',col{q}, 'LineWidth',2.4, 'MaxHeadSize',1.2);
        end
    end
    vv = LOG.blk_v(i0,:); vs = max(vmag);
    if vs > 1e-9
        quiver(ax, px, py, vv(1)/vs*L*0.7, vv(2)/vs*L*0.7, 0, ...
               'Color',[0.4 1 0.4], 'LineWidth',1.8, 'MaxHeadSize',1.2, ...
               'LineStyle','--');
    end
end

title(ax, sprintf('%s   [S%02d-S%02d]', name, s0-1, s1-1), ...
      'Color','w','FontSize',9,'FontWeight','bold');
dz = 1000*(max(LOG.base_z(idx)) - min(LOG.base_z(idx)));
if dz > 0.1; extra = sprintf('   base dz %.0f mm', dz); else; extra = ''; end
xlabel(ax, sprintf(['%.2f s   %.0f mm%s   v_{pk} %.3f m/s   F_{pk} %.1f N' ...
                    '\n%s'], r.dur, 1000*r.dist, extra, r.vpk, r.fpk, d{4}), ...
       'Color',[0.7 0.9 0.7], 'FontSize',7.5);
end
