function draw_cell_layout(ax, P, K, varargin)
%DRAW_CELL_LAYOUT  Draw the static factory cell into an axes.
%
%   DRAW_CELL_LAYOUT(ax, P, K)
%   DRAW_CELL_LAYOUT(ax, P, K, 'Name', value, ...)
%
%   ax   target axes
%   P    parameter struct
%   K    metre -> display multiplier. 1 draws in metres; 1/P.SCALE draws in
%        the reference script's drawing units.
%
%   Options
%     'Labels'  true/false   station and conveyor text        (default true)
%     'Sensors' true/false   proximity markers and the camera (default true)
%     'Alpha'   0..1         face transparency                (default 1)
%
%   The geometry is reproduced from the reference script
%   function multi_station_simulation().txt so the cell stays recognisable
%   against the original figure.
%
%   WHY THIS IS A SEPARATE FILE
%   VISUALIZE_FACTORY and VISUALIZE_PROCESSES both draw the same cell. Holding
%   the coordinates in one place means the animated replay and the per-process
%   panels cannot drift apart, which they would the first time a rectangle was
%   nudged in one file and not the other.
%
%   This draws the STATIC cell only. Nothing here reads LOG, and nothing here
%   computes motion.
%
%   See also VISUALIZE_FACTORY, VISUALIZE_PROCESSES.

o = struct('Labels', true, 'Sensors', true, 'Alpha', 1);
o = parse_options(o, varargin, mfilename);

S = P.SCALE;
blue = [0.2 0.4 0.7]; grey = [0.4 0.4 0.6]; dash = [0.6 0.6 0.6];
R = @(v) rectangle(ax, 'Position', [v(1) v(2) v(3) v(4)]*S*K);

% ---- conveyors, actuators, engraver, bin -------------------------------
set(R([1 8.5 7.6 1.35]),   'FaceColor',[blue o.Alpha],'EdgeColor','w');  % Conveyor 1
set(R([7.25 0.9 1.35 7.6]),'FaceColor',[blue o.Alpha],'EdgeColor','w');  % Conveyor 2
set(R([8.6 3.19 7.6 1.35]),'FaceColor',[blue o.Alpha],'EdgeColor','w');  % St.3 belt
set(R([8.6 4.3 3.7 2.65]), 'FaceColor',[[0.7 0.2 0.2] o.Alpha],'EdgeColor','w');
% ACTUATOR BODIES ARE GENERATED, NOT DRAWN BY HAND. This used to be six
% literal rectangles copied from the reference figure, against a plant that
% carried five cylinders and now carries eleven. The picture was wrong in two
% ways at once: it showed six bodies for eleven actuators, and it labelled
% three different barrels "Actuator 1", because the reference figure names
% each actuator by its position within a station rather than globally.
%
% Each body is now placed at its own retracted rod tip, on its own axis,
% behind the direction it pushes. Nothing here chooses a coordinate; every one
% comes from P.CYL, which comes from FACTORY_ACTUATORS.
bl = 0.12;   % body length along the stroke axis, m
bw = 0.08;   % body width across it, m
for c = 1:P.NCYL
    C = P.CYL(c);
    if ~C.placed; continue; end           % no geometry - see the note below
    if C.axis == 'x'
        x0 = min(C.tip0, C.tip0 - C.dir*bl);
        pos = [x0, C.lat - bw/2, bl, bw];
    else
        y0 = min(C.tip0, C.tip0 - C.dir*bl);
        pos = [C.lat - bw/2, y0, bw, bl];
    end
    % A DOUBLE-SOLENOID actuator is drawn with a brighter edge, so that the
    % two valve types the cell actually runs are distinguishable at a glance.
    if C.dbl; ec = [1 0.8 0.3]; lw = 1.6; else; ec = [1 1 1]; lw = 0.5; end
    % An actuator that is placed but may NOT contact the workpiece is drawn
    % DASHED. Today that is CYL_B alone: a real bypass cylinder whose path this
    % 2-D single-axis layout cannot express, so it is shown where it stands and
    % marked as outside the modelled material flow.
    if C.placed && ~C.contact; ls = ':'; else; ls = '-'; end
    rectangle(ax, 'Position', pos*K, 'FaceColor',[grey o.Alpha], ...
              'EdgeColor', ec, 'LineWidth', lw, 'LineStyle', ls);
end
set(R([-0.8 8.2 10 3.8]),  'EdgeColor',dash,'LineStyle','--');           % St.1 bound
set(R([5 1.5 4 6.5]),      'EdgeColor',dash,'LineStyle','--');           % St.2 bound
set(R([9.2 1.5 7.2 8.5]),  'EdgeColor',dash,'LineStyle','--');           % St.3 bound
% [ADD] collection bin - required by Sequence.xlsx step 42, absent from the
% reference script.
set(R([14.3 1.0 1.6 2.19]),'FaceColor',[[0.25 0.25 0.28] o.Alpha],'EdgeColor','w');

% ---- sensors (absent from the reference script) ------------------------
% All TEN proximity sensors, in the MACHINE's numbering, each labelled. They
% were drawn as unlabelled circles, which made ten identical markers out of
% ten sensors that do different jobs. The four the sequence actually gates on
% (P.PROX_GUARD) are filled, so the six that are modelled and logged but guard
% nothing are visibly different from the four that stop the cycle.
if o.Sensors
    for i = 1:size(P.PROX,1)
        gated = any(P.PROX_GUARD == i);
        if gated; mfc = [1 0.85 0.2]; else; mfc = 'none'; end
        plot(ax, P.PROX(i,1)*K, P.PROX(i,2)*K, 'o', 'MarkerSize',7, ...
             'MarkerEdgeColor',[1 0.85 0.2], 'MarkerFaceColor',mfc, ...
             'LineWidth',1.2);
        if o.Labels
            % 'PX07_conv2_mid' -> 'PX07'. The full name is in P.PROX_NAME.
            tag = regexprep(P.PROX_NAME{i}, '_.*$', '');
            % Above the marker, not beside it: PX09 and PX10 sit on the
            % conveyor 3 belt and a right-hand label lands on the belt's own
            % caption.
            text(ax, P.PROX(i,1)*K, (P.PROX(i,2) + 0.018)*K, tag, ...
                 'Color',[1 0.85 0.2],'FontSize',7, ...
                 'HorizontalAlignment','center');
        end
    end
    plot(ax, P.CAM(1)*K, P.CAM(2)*K, 's', 'MarkerSize',9, ...
         'MarkerEdgeColor',[0.4 0.9 1], 'LineWidth',1.4);
    if o.Labels
        text(ax, P.CAM(1)*K, P.CAM(2)*K, '  CAM', ...
             'Color',[0.4 0.9 1],'FontSize',7);
    end
    % The two platform limit switches are the machine's Proximity_sensor_11
    % and _12 (PGM_Up_Limit / PGM_Low_Limit). They watch the engraving
    % platform's HEIGHT, which this plan view has no axis for, so they are
    % named at the engraver rather than given a fictitious x-y position.
    if o.Labels
        % Clear of the engraver rectangle - a yellow caption inside the red
        % box is unreadable, which is what the first attempt produced.
        text(ax, 9.3*S*K, 7.15*S*K, 'PX11/12 (platform z)', ...
             'Color',[1 0.85 0.2],'FontSize',7);
    end
end

% ---- labels ------------------------------------------------------------
if o.Labels
    txt = @(x,y,str,varargin) text(ax, x*S*K, y*S*K, str, ...
                                   'Color','w','FontSize',8, varargin{:});
    % Wording follows the reference figure so the two read side by side. Each
    % actuator is named as its station names it, not by a global index.
    txt(2.0, 8.8,'> > > Conveyor 1 (Extended) > > >','FontWeight','bold');
    txt(7.8, 3.0,'v Conveyor 2 (Top -> Bottom) v','FontWeight','bold','Rotation',90);
    txt(10.2,3.75,'> > > Station 3 Belt (L -> R) > > >','FontWeight','bold');
    txt(9.6, 5.9,'Laser Engraver','FontWeight','bold');
    txt(14.4,1.4,'BIN');
    % Actuator labels are generated with the bodies, from P.CYL, and carry the
    % machine's coil numbers so a double-solenoid is readable as one.
    bl2 = 0.12; bw2 = 0.08;
    for c = 1:P.NCYL
        C = P.CYL(c);
        if ~C.placed; continue; end
        if C.dbl
            lab = sprintf('%s [%d/%d]', C.short, C.coil_ext, C.coil_ret);
        else
            lab = sprintf('%s [%d]', C.short, C.coil_ext);
        end
        if C.axis == 'x'
            lx = min(C.tip0, C.tip0 - C.dir*bl2);
            ly = C.lat + bw2/2;
        else
            lx = C.lat - bw2/2;
            ly = max(C.tip0, C.tip0 - C.dir*bl2);
        end
        text(ax, lx*K, ly*K, lab, 'Color',[0.85 0.85 1],'FontSize',7, ...
             'VerticalAlignment','bottom');
    end
    % The actuators the model carries but CANNOT DRAW, named rather than
    % omitted. Their role is known from the PLC listing and their position is
    % not, so putting them anywhere on this plan would be inventing a
    % coordinate. Saying so on the figure is the honest alternative to a
    % rectangle that looks like a measurement.
    un = P.CYL(~[P.CYL.placed]);
    if ~isempty(un)
        names = arrayfun(@(C) sprintf('%s [%d]', C.short, C.coil_ext), ...
                         un, 'UniformOutput', false);
        text(ax, 10.4*S*K, 0.9*S*K, ...
             sprintf('Not shown - position unknown: %s', strjoin(names, ', ')), ...
             'Color',[0.75 0.6 0.6],'FontSize',7);
    end
    % Placed, drawn, and deliberately outside the modelled material flow.
    nc = P.CYL([P.CYL.placed] & ~[P.CYL.contact]);
    if ~isempty(nc)
        names = arrayfun(@(C) C.short, nc, 'UniformOutput', false);
        text(ax, 10.4*S*K, 0.4*S*K, ...
             sprintf(['Dotted = real cylinder, path not representable in ' ...
                      'this layout: %s'], strjoin(names, ', ')), ...
             'Color',[0.75 0.6 0.6],'FontSize',7);
    end
    % STATION 3 sits at the LEFT of its boundary: the collection bin occupies
    % the bottom-right corner, where the reference script put this label.
    text(ax,-0.6*S*K,11.9*S*K,'STATION 1','Color',dash,'FontWeight','bold');
    text(ax, 5.2*S*K, 1.8*S*K,'STATION 2','Color',dash,'FontWeight','bold');
    text(ax, 9.6*S*K, 1.8*S*K,'STATION 3','Color',dash,'FontWeight','bold');
end
end
