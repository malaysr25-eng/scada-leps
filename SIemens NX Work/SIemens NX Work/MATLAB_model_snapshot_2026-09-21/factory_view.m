function varargout = factory_view(action, varargin)
%FACTORY_VIEW  The animated cell view, shared by the replay and the live run.
%
%   V = FACTORY_VIEW('open', P)                  open a figure and draw the cell
%   V = FACTORY_VIEW('open', P, 'Units', u, 'Title', str)
%   FACTORY_VIEW('frame', V, LOG, i)             draw log sample i
%   FACTORY_VIEW('note',  V, str)                the operator line ('' clears it)
%   FACTORY_VIEW('laser', V, on)                 the violet laser mark on the block
%   FACTORY_VIEW('done',  V, str)                the final status line
%   FACTORY_VIEW('status', V, state)             the status line for a PLC state,
%                                                without a new frame (the live run
%                                                uses it when it stops for ENG DONE)
%   tf = FACTORY_VIEW('alive', V)                false once the figure is closed
%   op = FACTORY_VIEW('opnew', P, console)       operator record for a live run
%   op = FACTORY_VIEW('opfromlog', LOG)          the same for a replay ([] if the
%                                                run had no operator at the console)
%   [str, laserOn] = FACTORY_VIEW('opnote', op, state, t)
%                                                the operator line for one moment
%
%   WHY ONE FILE. VISUALIZE_FACTORY replays a finished LOG, and
%   RUN_FACTORY_SIMULATION('Live', true) draws the same frames while the
%   cycle is being computed. Both call this, so the replay and the live view
%   cannot drift apart. DRAW_CELL_LAYOUT exists for the same reason.
%
%   DISPLAY ONLY. It reads LOG and P and writes nothing back. A live run
%   computes the same LOG as any other run, and LIVEVIEWTEST holds that.
%
%   THE BLOCK TURNS GREEN once engraving starts (S25), and only on the
%   engraved route. Until 2026-09-14 the rule was "state index >= 26". The
%   SV11 bypass states (41-44) satisfy that too, so a part that skipped
%   engraving was drawn as engraved.
%
%   See also VISUALIZE_FACTORY, RUN_FACTORY_SIMULATION, DRAW_CELL_LAYOUT.

switch action
    case 'open',      varargout{1} = openView(varargin{:});
    case 'frame',     drawFrame(varargin{:});
    case 'note'
        V = varargin{1};
        if isAlive(V); set(V.opl, 'String', varargin{2}); end
    case 'laser',     laserMark(varargin{:});
    case 'done'
        V = varargin{1};
        if isAlive(V)
            set(V.sta, 'String', varargin{2});
            set(V.opl, 'String', '');
            laserMark(V, false);
        end
    case 'status'
        V = varargin{1};
        if isAlive(V)
            set(V.sta, 'String', statusText(V, varargin{2}));
            set(V.blk, 'FaceColor', blockColour(V, varargin{2}));
        end
    case 'alive',     varargout{1} = isAlive(varargin{1});
    case 'opnew',     varargout{1} = opNew(varargin{:});
    case 'opfromlog', varargout{1} = opFromLog(varargin{1});
    case 'opnote',    [varargout{1}, varargout{2}] = opNote(varargin{:});
    otherwise
        error('factory_view:action', ['Unknown action ''%s''. Valid: open, frame, ' ...
              'note, laser, done, status, alive, opnew, opfromlog, opnote.'], char(action));
end
end

%% ========================================================================
function V = openView(P, varargin)
o = struct('Units', 'metres', 'Title', 'Automated Assembly Line - Physics-Based Simulation');
o = parse_options(o, varargin, 'factory_view');
S = P.SCALE;
% K converts a METRE quantity into whatever the axes are displaying. Every
% coordinate is metres (LOG, P.CYL, P.PROX, P.CAM, P.blk_L/W), so a single
% multiplier keeps the layout, the workpiece and the rods in one frame.
switch lower(o.Units)
    case 'metres',  K = 1;   ulab = 'm';
    case 'drawing', K = 1/S; ulab = 'drawing units';
    otherwise
        error('visualize_factory:units', ...
              "Units must be 'metres' or 'drawing', got '%s'", o.Units);
end

fig = figure('Name', 'Factory Layout Simulation (physics-driven)', ...
             'Color', [0.12 0.12 0.12], 'Tag', 'factory_view');
ax  = axes('Parent', fig, 'Color', [0.08 0.08 0.08]);
hold(ax, 'on'); grid(ax, 'on'); axis(ax, 'equal');
ax.XColor = [0.8 0.8 0.8]; ax.YColor = [0.8 0.8 0.8];
% Headroom above the cell (to 14.5, was 13) for the status and operator
% lines. At 12.3 the status line sat on the magazine labels.
xlim(ax, [-1 18]*S*K); ylim(ax, [-1 14.5]*S*K);
xlabel(ax, sprintf('X Position (%s)', ulab));
ylabel(ax, sprintf('Y Position (%s)', ulab));
title(ax, o.Title, 'Color', 'w', 'FontSize', 13);

draw_cell_layout(ax, P, K);

wL = P.blk_L*K;  wW = P.blk_W*K;   % x and y extents, drawn to scale
blk = rectangle(ax, 'Position', [0 0 wL wW], 'FaceColor', orange(), ...
                'EdgeColor', 'k', 'LineWidth', 1.5, 'Visible', 'off');
% One rod per PLACED actuator. Any whose position is not known have
% tip0 = lat = NaN and are deliberately not drawn; DRAW_CELL_LAYOUT names them
% on the figure instead. PLACED, not CONTACT: CYL_B is barred from touching
% the workpiece but is a real cylinder, and is animated.
rods = gobjects(1, P.NCYL);
for c = 1:P.NCYL
    if ~P.CYL(c).placed; continue; end
    rods(c) = line(ax, [0 0], [0 0], 'LineWidth', 5, 'Color', 'c');
end
sta = text(ax, -0.8*S*K, 14.0*S*K, '', 'Color', 'y', 'FontSize', 11, 'FontWeight', 'bold');
opl = text(ax, -0.8*S*K, 13.3*S*K, '', 'Color', [0.85 0.65 1], 'FontSize', 11, 'FontWeight', 'bold');
txt = text(ax, -0.8*S*K, -0.6*S*K, '', 'Color', [0.7 0.9 0.7], 'FontSize', 9);
las = line(ax, NaN, NaN, 'LineStyle', 'none', 'Marker', 'p', 'MarkerSize', 18, ...
           'MarkerFaceColor', [0.75 0.35 1], 'MarkerEdgeColor', 'w', 'Visible', 'off');

ST = factory_states();
V = struct('fig', fig, 'ax', ax, 'P', P, 'K', K, 'ST', {ST}, 'blk', blk, ...
           'wL', wL, 'wW', wW, 'rods', rods, 'sta', sta, 'opl', opl, ...
           'txt', txt, 'las', las, ...
           'iEng', find(strcmp(ST(:,1), 'S25_ENGRAVE_MANUAL')));
end

%% ========================================================================
function drawFrame(V, LOG, i)
if ~isAlive(V); return; end
P = V.P; K = V.K;
set(V.blk, 'Position', [LOG.blk(i,1)*K - V.wL/2, LOG.blk(i,2)*K - V.wW/2, V.wL, V.wW], ...
    'Visible', 'on');
set(V.blk, 'FaceColor', blockColour(V, LOG.state(i)));
for c = 1:P.NCYL
    C = P.CYL(c);
    if ~C.placed; continue; end
    tip = (C.tip0 + C.dir*LOG.rod(i,c))*K;
    if C.axis == 'x'
        set(V.rods(c), 'XData', [C.tip0*K tip], 'YData', [C.lat*K C.lat*K]);
    else
        set(V.rods(c), 'XData', [C.lat*K C.lat*K], 'YData', [C.tip0*K tip]);
    end
end
set(V.sta, 'String', statusText(V, LOG.state(i)));
set(V.txt, 'String', sprintf(['t %6.2f s   block (%.3f, %.3f) m   ' ...
    '|v| %.3f m/s   receiver %.2f bar   base z %.1f mm'], ...
    LOG.t(i), LOG.blk(i,1), LOG.blk(i,2), ...
    hypot(LOG.blk_v(i,1), LOG.blk_v(i,2)), ...
    LOG.P_res(i)/1e5, round(1000*LOG.base_z(i), 1) + 0));   % + 0: no '-0.0'
if strcmp(get(V.las, 'Visible'), 'on'); laserMark(V, true); end   % follow the block
end

function laserMark(V, on)
if ~isAlive(V); return; end
if on
    p = get(V.blk, 'Position');
    set(V.las, 'XData', p(1) + p(3)/2, 'YData', p(2) + p(4)/2, 'Visible', 'on');
else
    set(V.las, 'Visible', 'off');
end
end

function c = blockColour(V, state)
% Green once engraving starts (S25), and only on the engraved route.
if V.P.engrave_selected && state >= V.iEng
    c = green();
else
    c = orange();
end
end

function s = statusText(V, state)
s = sprintf('Status: %s   (Excel step %s)', strrep(V.ST{state,1}, '_', ' '), V.ST{state,2});
end

function tf = isAlive(V)
tf = isstruct(V) && isfield(V, 'fig') && isgraphics(V.fig);
end

function c = orange(); c = [0.9 0.5 0.1]; end
function c = green();  c = [0.2 0.8 0.2]; end

%% ---- the operator line --------------------------------------------------
function op = opNew(P, console)
ST  = factory_states();
idx = @(nm) find(strcmp(ST(:,1), nm));
op = struct('console', logical(console), 'engrave', logical(P.engrave_selected), ...
            'laser_s', NaN, 'reaction_s', NaN, 'confirm_s', P.t_op_confirm, ...
            't25', NaN, 'pressed', false, 'iS24', idx('S24_OPERATOR_NOTIFY'), ...
            'iS25', idx('S25_ENGRAVE_MANUAL'), 'iS26', idx('S26_ENGRAVE_CONFIRM'));
if op.console && isfield(P, 'OP') && isfield(P.OP, 't_laser_50')
    op.laser_s = P.OP.t_laser_50;
end
end

function op = opFromLog(LOG)
op = [];
if ~isfield(LOG, 'operator'); return; end
op = opNew(LOG.P, true);
op.engrave    = logical(LOG.operator.engrave);
op.laser_s    = LOG.operator.laser_s;
op.reaction_s = LOG.operator.reaction_s;
if isfield(LOG, 'plc') && isfield(LOG.plc, 'log') && ~isempty(LOG.plc.log)
    k = find(strcmp(LOG.plc.log(:,2), 'S25_ENGRAVE_MANUAL'), 1);
    if ~isempty(k); op.t25 = LOG.plc.log{k,1}; end
end
end

function [s, las] = opNote(op, state, t)
%OPNOTE  What the operator line says at one moment, and whether the laser shows.
s = ''; las = false;
if isempty(op) || ~op.console; return; end
if ~op.engrave
    s = 'Operator: SKIP engraving - the part takes the SV11 bypass';
    return
end
if state < op.iS24
    s = 'Operator: ENGRAVE the 50 mm job';
elseif state == op.iS24
    s = 'Platform up - the laser starts';
elseif state == op.iS25
    if op.pressed                       % live, after the press: the dwell is catching up
        s = sprintf('ENG DONE pressed after %.2f s', op.reaction_s);
        return
    end
    el = t - op.t25;
    if isnan(el); el = 0; end
    if el < op.laser_s
        s = sprintf('LASER ON  %.1f / %.2f s  (placeholder time)', el, op.laser_s);
        las = true;
    elseif isnan(op.reaction_s)
        s = sprintf('Waiting for ENG DONE  %.1f s', el - op.laser_s);
    else
        s = sprintf('Waiting for ENG DONE  %.1f / %.2f s', el - op.laser_s, op.reaction_s);
    end
elseif state == op.iS26
    s = sprintf('ENG DONE pressed after %.2f s - platform moves in %.3f s', ...
                op.reaction_s, op.confirm_s);
else
    s = 'Engraved: the 50 mm job';
end
end
