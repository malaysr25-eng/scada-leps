function LOG = run_factory_simulation(varargin)
%RUN_FACTORY_SIMULATION  Execute one full production cycle.
%
%   LOG = RUN_FACTORY_SIMULATION()
%   LOG = RUN_FACTORY_SIMULATION('Name', Value, ...)
%
%   Options
%     'Params'    parameter struct (default FactoryParams())
%     'Plot'      true/false, draw the results dashboard   (default true)
%     'Animate'   true/false, replay the physical motion   (default false)
%     'Verbose'   true/false, print the state trace        (default true)
%     'Operator'  'auto' (default) runs the operator timers of FACTORYPARAMS.
%                 'console' asks a PERSON: engrave (the 50 mm job) or skip,
%                 before the cycle; then at S25 waits P.OP.t_laser_50 of real
%                 time while the laser runs and asks for ENG DONE. Your
%                 reaction time becomes the operator part of the dwell. MATLAB
%                 path only; see FACTORY_OPERATOR_CONSOLE.
%     'OperatorInput'  function handle answering those questions, called as
%                 out = f(kind, info) with kind 'engrave?', 'laser' or
%                 'eng_done' (default @factory_operator_console). Tests pass a
%                 scripted one, so nothing waits on a keyboard.
%     'Live'      true/false: draw the cell WHILE the cycle runs (default
%                 false), through FACTORY_VIEW - the same frames
%                 VISUALIZE_FACTORY replays. With 'Operator','console' the
%                 figure shows the laser, then waits for ENG DONE: any key on
%                 the figure. A display only: the LOG is identical.
%     'LiveSpeed' 1 (default) plays the live view in real time, 4 is 4x, Inf
%                 draws as fast as the cycle is computed.
%
%   The physical plant is integrated with fixed-step RK4 at P.dt. The PLC
%   runs on its own scan clock at P.t_scan and its outputs are held constant
%   between scans, exactly as a real PLC behaves.
%
%   NOTHING in this function moves the workpiece. The workpiece moves only
%   because FACTORY_DERIVATIVES computes forces on it. There is no
%   interpolation, no pause(), no scripted coordinate path.
%
%   Example
%     LOG = run_factory_simulation('Animate', true);
%     LOG = run_factory_simulation('Operator', 'console');   % you are the operator
%     LOG = run_factory_simulation('Operator', 'console', 'Live', true);  % and watch

opt = struct('Params',[], 'Plot',true, 'Animate',false, 'Verbose',true, ...
             'Operator','auto', 'OperatorInput',[], 'Live',false, 'LiveSpeed',1);
opt = parse_options(opt, varargin, mfilename);

% --- manual input: a person at the console (2026-09-13) ------------------
if ~((ischar(opt.Operator) || isstring(opt.Operator)) && ...
        any(strcmpi(opt.Operator, {'auto', 'console'})))
    error('run_factory_simulation:operator', ...
        'Operator must be ''auto'' or ''console'', got %s.', describeArg(opt.Operator));
end
interactive = strcmpi(opt.Operator, 'console');
if ~(isscalar(opt.Live) && (islogical(opt.Live) || isnumeric(opt.Live)))
    error('run_factory_simulation:live', ...
        'Live must be true or false, got %s.', describeArg(opt.Live));
end
live = logical(opt.Live);
if ~(isnumeric(opt.LiveSpeed) && isscalar(opt.LiveSpeed) && opt.LiveSpeed > 0)
    error('run_factory_simulation:liveSpeed', ...
        ['LiveSpeed must be a positive number: 1 is real time, Inf is as ' ...
         'fast as computed. Got %s.'], describeArg(opt.LiveSpeed));
end
defaultAsk = isempty(opt.OperatorInput);
ask = opt.OperatorInput;
if isempty(ask); ask = @factory_operator_console; end
if ~isa(ask, 'function_handle')
    error('run_factory_simulation:operatorInput', ...
        'OperatorInput must be a function handle, got %s.', describeArg(ask));
end
if interactive
    Pin = opt.Params;
    if isempty(Pin); Pin = FactoryParams(); end
    % The HMI's product choice, before the cycle: engrave the 50 mm job, or
    % skip engraving and send the part through the SV11 bypass.
    Pin.engrave_selected = logical(ask('engrave?', []));
    % The PLC's notification is taken as the laser starting, so there is no
    % separate notice time. The confirm is the measured button-to-platform delay.
    Pin.op_mode      = 'interactive';
    Pin.t_op_notice  = 0;
    Pin.t_op_confirm = Pin.OP.confirm;
    opt.Params = Pin;
end

[P, s] = initialize_factory(opt.Params);
plc    = factory_plc_init(P);
ST     = factory_states();
S_ENG      = find(strcmp(ST(:,1), 'S25_ENGRAVE_MANUAL'));
t_timeout0 = P.t_timeout;
if interactive
    oprec = struct('mode', 'console', 'engrave', P.engrave_selected, ...
                   'laser_s', NaN, 'reaction_s', NaN);
end

% --- live view (2026-09-14) ----------------------------------------------
% DISPLAY ONLY. It reads the state and pauses for real time, and writes
% nothing back, so a live run computes the same LOG as any other run.
% LiveViewTest holds that.
V = []; op = []; fstep = 1; tlive = [];
if live
    V  = factory_view('open', P, 'Title', 'Automated Assembly Line - LIVE');
    op = factory_view('opnew', P, interactive);
    tlive = tic;
end

dt   = P.dt;
nsc  = max(1, round(P.t_scan/dt));
nmax = ceil(P.t_max/dt);
dec  = max(1, round(0.005/dt));            % log at 200 Hz
if live; fstep = max(1, round(0.04/(dec*dt))); end   % live view: a frame every ~0.04 s, ~25 fps

% --- preallocate log ----------------------------------------------------
nl = ceil(nmax/dec)+1; k = 0; li = 0;
LOG.t     = zeros(nl,1);
LOG.blk   = zeros(nl,2);   LOG.blk_v = zeros(nl,2);
LOG.blk_a = zeros(nl,2);
LOG.rod   = zeros(nl,P.NCYL);  LOG.rod_v = zeros(nl,P.NCYL);
LOG.rod_F = zeros(nl,P.NCYL);
LOG.PA    = zeros(nl,P.NCYL);  LOG.PB    = zeros(nl,P.NCYL);
LOG.spool = zeros(nl,P.NCYL);
LOG.P_res = zeros(nl,1);       LOG.P_br  = zeros(nl,4);
LOG.v_blt = zeros(nl,P.NCONV); LOG.T_mot = zeros(nl,P.NCONV);
LOG.base_z= zeros(nl,1);
LOG.m_air = zeros(nl,1);
LOG.state = zeros(nl,1);
% CAM + every proximity sensor + EXT per actuator + the two platform limit
% switches + the E-Stop loop. Width follows P.PROX and P.NCYL, both of which
% have moved onto the machine's counts - the sensors from 4 to 10 on
% 2026-09-02, the actuators from 5 to 11 the same day - so it is computed
% rather than written.
LOG.sens  = false(nl, 1 + size(P.PROX,1) + P.NCYL + 3);
LOG.sens_name = [{'CAM'}, P.PROX_NAME, ...
                 arrayfun(@(c) sprintf('EXT_%s', P.CYL(c).name), ...
                          1:P.NCYL, 'UniformOutput', false), ...
                 {'HS_TOP_PGM_Up', 'HS_BOT_PGM_Low', 'ESTOP_OK'}];
LOG.cmd_conv = zeros(nl,P.NCONV);
LOG.cmd_pump = zeros(nl,1);
% The 13 solenoid coils as commanded, one column per coil (Solenoid_valve1..13).
% Logged since 2026-09-19 so a replay can publish real coil edges to NX MCD
% (the replay server lives in Digital Twin/SIemens NX Work). Logging only.
LOG.cmd_sol  = false(nl,P.NSOL);
% 2-D force breakdown on the workpiece, for VISUALIZE_PROCESSES. These come
% from the SAME factory_derivatives call that already produces blk_a below, so
% they cost no extra physics evaluations and cannot disagree with the motion.
LOG.F_rod  = zeros(nl,2);  LOG.F_stop = zeros(nl,2);
LOG.F_fric = zeros(nl,2);  LOG.F_net  = zeros(nl,2);
LOG.belt_v = zeros(nl,2);  LOG.reg    = zeros(nl,1);

aA = [P.CYL.A_A]; aB = [P.CYL.A_B];   % per-actuator piston areas
t = 0; u = struct('pump_on',false,'dv',[0 0 0 0], ...
                  'sol',zeros(1,P.NSOL),'conv',[0 0 0],'base',0);
% u_pending implements P.plc_io_delay. At 0 the command computed by a scan is
% applied by that same scan. At 1 it is held back and applied by the NEXT
% scan, which is what the Simulink path used to do implicitly and is the
% T_exec -> t_scan limit of a real read/execute/write PLC cycle.
u_pending = u;

% --- production timing ---------------------------------------------------
t_state_entry = zeros(numel(ST),1);
prev_state    = plc.state;

while t < P.t_max
    % ---- PLC scan (zero-order hold on the plant) ----
    if mod(k, nsc) == 0
        y = factory_sensors(s, P);
        [plc, u_new] = factory_plc(plc, y, t, P);
        if P.plc_io_delay == 0
            u = u_new;                      % same-scan write
        else
            u = u_pending; u_pending = u_new;   % one-scan write delay
        end
        if plc.state ~= prev_state
            t_state_entry(plc.state) = t;
            prev_state = plc.state;
            if opt.Verbose
                fprintf('  t=%7.3f s   %-22s  Excel %s\n', ...
                        t, ST{plc.state,1}, ST{plc.state,2});
            end
            if interactive
                P.t_timeout = t_timeout0;            % S25's lift ends with S25
                if plc.state == S_ENG
                    if isstruct(op); op.t25 = t; end
                    [P, oprec, op] = operatorAtEngraver(P, ask, oprec, live, V, op, ...
                                                        defaultAsk);
                end
            end
        end
        if plc.complete; break; end
    end

    % ---- log ----
    if mod(k, dec) == 0
        li = li + 1;
        [ds, dbg] = factory_derivatives(s, u, P);
        LOG.t(li)       = t;
        LOG.blk(li,:)   = [s(P.IX.bx)  s(P.IX.by)];
        LOG.blk_v(li,:) = [s(P.IX.bvx) s(P.IX.bvy)];
        LOG.blk_a(li,:) = [ds(P.IX.bvx) ds(P.IX.bvy)];
        LOG.rod(li,:)   = s(P.IX.x)';
        LOG.rod_v(li,:) = s(P.IX.v)';
        % Per-actuator areas, as FACTORY_DERIVATIVES uses. This read the
        % scalars P.A_A / P.A_B until 2026-09-02, when the bores became
        % per-actuator against the day a real one arrived. That day was
        % 2026-09-07: CYL_A is bore 32 from a nameplate and the other ten are
        % still the [JAN] 20, so aA and aB are no longer one number repeated
        % and the scalars would now be wrong here for CYL_A.
        LOG.rod_F(li,:) = (s(P.IX.PA).*aA(:) - s(P.IX.PB).*aB(:) ...
                           - P.P_atm*(aA(:)-aB(:)))';
        LOG.PA(li,:)    = s(P.IX.PA)';
        LOG.PB(li,:)    = s(P.IX.PB)';
        LOG.spool(li,:) = s(P.IX.sp)';
        LOG.P_res(li)   = s(P.IX.P_res);
        LOG.P_br(li,:)  = s(P.IX.P_br)';
        LOG.v_blt(li,:) = (P.r_pul*s(P.IX.om))';
        LOG.base_z(li)  = s(P.IX.bz);
        LOG.m_air(li)   = s(P.IX.mair);
        LOG.state(li)   = plc.state;
        LOG.cmd_conv(li,:) = u.conv;
        LOG.cmd_pump(li)   = u.pump_on;
        LOG.cmd_sol(li,:)  = u.sol ~= 0;
        LOG.F_rod(li,:)  = dbg.F_rod;   LOG.F_stop(li,:) = dbg.F_stop;
        LOG.F_fric(li,:) = dbg.F_fric;  LOG.F_net(li,:)  = dbg.F_net;
        LOG.belt_v(li,:) = dbg.belt_v;  LOG.reg(li)      = dbg.reg;
        yy = factory_sensors(s, P);
        LOG.sens(li,:) = [yy.CAM yy.PX yy.EXT yy.HS_TOP yy.HS_BOT yy.ESTOP_OK];
        if live && mod(li - 1, fstep) == 0
            [live, op] = liveFrame(V, LOG, li, op, t, tlive, opt.LiveSpeed, ...
                                   S_ENG, t_state_entry);
        end
    end

    % ---- RK4 ----
    k1 = factory_derivatives(s,            u, P);
    k2 = factory_derivatives(s + dt/2*k1,  u, P);
    k3 = factory_derivatives(s + dt/2*k2,  u, P);
    k4 = factory_derivatives(s + dt  *k3,  u, P);
    s  = s + dt/6*(k1 + 2*k2 + 2*k3 + k4);

    t = t + dt; k = k + 1;
end

% --- trim ---------------------------------------------------------------
f = fieldnames(LOG);
for i = 1:numel(f)
    if size(LOG.(f{i}),1) >= li; LOG.(f{i}) = LOG.(f{i})(1:li,:); end
end

% --- production metrics -------------------------------------------------
LOG.P          = P;
if interactive
    LOG.operator = oprec;          % who pressed ENG DONE, and how fast
end
LOG.plc        = plc;
LOG.cycle_time = t;
LOG.complete   = plc.complete;
LOG.blk_final  = [s(P.IX.bx) s(P.IX.by)];
LOG.blk_target = P.WP.bin;
LOG.pos_error  = norm(LOG.blk_final - LOG.blk_target);
te = t_state_entry;
LOG.time_station1 = te(13) - te(6);      % S05 -> S12 entry
if P.engrave_selected
    LOG.time_station2 = te(23) - te(19);     % S18 -> S22 entry
    LOG.time_engrave  = te(28) - te(23);     % base up -> base down
    LOG.time_station3 = t      - te(30);     % S29 -> end
    LOG.time_operator = P.t_op_notice + P.t_engrave + P.t_op_confirm;
else
    % The SV11 bypass never reaches the engraving station: no station 2, no
    % engraving, and no operator - so machine time is the whole cycle.
    % Station 3 starts when SV11's branch is selected (S41, row 42).
    LOG.time_station2 = 0;
    LOG.time_engrave  = 0;
    LOG.time_station3 = t      - te(42);     % S41 -> end
    LOG.time_operator = 0;
end
% THE RECORDER'S END POINT, added 2026-09-12 (plan H1). The machine's
% cycle_completed rises in the same sample as SV12, i.e. when the last outfeed
% push STARTS: S37 here, row 38 on both routes. cycle_time runs on to S39,
% through the T#5S outfeed pulse and its retract (5.67 s), which the real
% clock never counts. Compare THESE with a recording, not cycle_time. The
% mismatch is how "1.11x" was quoted for what is 1.23x like for like
% (Project_Notes/to_matlab/round2_2026-09-10/SEGMENT_BUDGET_2026-09-10.md s2).
if te(38) > 0
    LOG.cycle_time_rec = te(38);             % S37 entry
else
    LOG.cycle_time_rec = NaN;                % never reached the outfeed
end
LOG.machine_time_rec = LOG.cycle_time_rec - LOG.time_operator;
% Air consumption. Normal litres = mass / ISO 6358 reference density.
LOG.air_kg = s(P.IX.mair);
LOG.air_NL = 1000*LOG.air_kg/P.rho0;

if opt.Verbose
    fprintf('\n  ------------------------------------------------\n');
    if plc.complete
        fprintf('  CYCLE COMPLETE       %8.3f s\n', LOG.cycle_time);
    else
        fprintf('  CYCLE DID NOT COMPLETE - stopped in %s\n', ST{plc.state,1});
    end
    if P.engrave_selected && interactive
        fprintf(['  of which operator    %8.3f s  (laser %.2f s [PLH] + your ' ...
                 'ENG DONE %.2f s + confirm %.3f s)' newline], LOG.time_operator, ...
                oprec.laser_s, oprec.reaction_s, P.t_op_confirm);
    elseif P.engrave_selected
        fprintf('  of which operator    %8.3f s  (PLACEHOLDER timing)\n', ...
                LOG.time_operator);
    else
        fprintf('  of which operator    %8.3f s  (SV11 bypass - no engraving)\n', ...
                LOG.time_operator);
    end
    fprintf('  machine time         %8.3f s\n', ...
            LOG.cycle_time - LOG.time_operator);
    fprintf('  to outfeed start     %8.3f s  (machine %.3f s) - the recorder''s end point\n', ...
            LOG.cycle_time_rec, LOG.machine_time_rec);
    fprintf('  final workpiece      (%.4f, %.4f) m\n', LOG.blk_final);
    fprintf('  bin target           (%.4f, %.4f) m\n', LOG.blk_target);
    fprintf('  position error       %8.2f mm\n', 1000*LOG.pos_error);
    fprintf('  peak workpiece speed %8.4f m/s\n', max(hypot(LOG.blk_v(:,1),LOG.blk_v(:,2))));
    fprintf('  peak chamber A       %8.2f bar\n', max(LOG.PA(:))/1e5);
    fprintf('  peak chamber B       %8.2f bar\n', max(LOG.PB(:))/1e5);
    fprintf('  air consumed         %8.2f normal litres\n', LOG.air_NL);
    if ~isempty(plc.timeouts)
        fprintf('  WATCHDOG TIMEOUTS    %d\n', size(plc.timeouts,1));
    end
    fprintf('  ------------------------------------------------\n');
end

if live && factory_view('alive', V)
    if plc.complete
        factory_view('done', V, 'Status: Cycle Complete - Part Ejected into Bin');
    else
        factory_view('done', V, sprintf('Status: stopped in %s', ...
                     strrep(ST{plc.state,1}, '_', ' ')));
    end
end
if opt.Plot;    plot_factory_results(LOG); end
if opt.Animate; visualize_factory(LOG);    end
end

%% ========================================================================
function [P, rec, op] = operatorAtEngraver(P, ask, rec, live, V, op, defaultAsk)
%OPERATORATENGRAVER  S25 with a person: the laser runs, then ENG DONE.
%   With the live view, the figure shows the laser and the wait. Only the
%   DEFAULT console is handed the figure (for the countdown and the key
%   press); a scripted OperatorInput keeps the plain arguments its tests use.
L = P.OP.t_laser_50;
live = live && factory_view('alive', V);
laserInfo = L; doneInfo = [];
if live
    % The last frame drawn predates S25, and the run now stops for the
    % laser and ENG DONE. Say S25 on the figure before it does.
    factory_view('status', V, V.iEng);
    factory_view('laser', V, true);
    factory_view('note', V, sprintf('LASER ON  0.0 / %.2f s  (placeholder time)', L));
    drawnow;
    if defaultAsk
        laserInfo = struct('t', L, 'tick', @(el) liveTick(V, el, L));
        doneInfo  = struct('fig', V.fig);
    end
end
ask('laser', laserInfo);
live = live && factory_view('alive', V);
if live
    factory_view('laser', V, false);
    if defaultAsk
        factory_view('note', V, 'Engraving finished - press any key on this figure for ENG DONE');
    else
        factory_view('note', V, 'Engraving finished - waiting for ENG DONE');
    end
    drawnow;
end
r = ask('eng_done', doneInfo);
if ~(isnumeric(r) && isscalar(r) && isreal(r) && isfinite(r) && r >= 0)
    error('run_factory_simulation:reaction', ...
        'The ENG DONE reaction must be a finite number of seconds >= 0, got %s.', ...
        describeArg(r));
end
P.t_engrave = L + r;
% The real PLC has no watchdog on the operator, so a slow ENG DONE must not
% trip this model's. The limit is lifted for S25 only (restored on the next
% state change) and the run's time limit grows by the reaction.
P.t_timeout = max(P.t_timeout, P.t_engrave + 1);
P.t_max     = P.t_max + r;
rec.laser_s    = L;
rec.reaction_s = r;
if isstruct(op)
    op.reaction_s = r;
    op.pressed    = true;   % the S25 frames still to come are the dwell catching up
end
if live && factory_view('alive', V)
    factory_view('note', V, sprintf('ENG DONE pressed after %.2f s - platform moves in %.3f s', ...
                 r, P.t_op_confirm));
    drawnow;
end
end

function s = describeArg(v)
%DESCRIBEARG  Short readable form of a bad argument, for the error message.
if ischar(v) || (isstring(v) && isscalar(v))
    s = ['''' char(v) ''''];
elseif (isnumeric(v) || islogical(v)) && numel(v) <= 4
    s = mat2str(v);
else
    s = ['a ' class(v)];
end
end

function [live, op] = liveFrame(V, LOG, li, op, t, tlive, speed, S_ENG, te)
%LIVEFRAME  One live frame: wait until real time catches up, then draw it.
%   The simulation computes faster than real time, so at LiveSpeed 1 it waits
%   here. After the ENG DONE wait it is BEHIND the wall clock, so it does not
%   wait until it has caught up. The platform is still through that stretch,
%   so nothing visible jumps.
if ~factory_view('alive', V); live = false; return; end   % closed: carry on unseen
live = true;
if isfinite(speed)
    ahead = t/speed - toc(tlive);
    if ahead > 0; pause(ahead); end
end
if isnan(op.t25) && te(S_ENG) > 0; op.t25 = te(S_ENG); end
factory_view('frame', V, LOG, li);
[s, las] = factory_view('opnote', op, LOG.state(li), t);
factory_view('note', V, s);
factory_view('laser', V, las);
drawnow limitrate;
end

function liveTick(V, el, L)
%LIVETICK  The live figure's laser countdown, called by the console.
if factory_view('alive', V)
    factory_view('note', V, sprintf('LASER ON  %.1f / %.2f s  (placeholder time)', min(el, L), L));
    drawnow limitrate;
end
end
