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

opt = struct('Params',[], 'Plot',true, 'Animate',false, 'Verbose',true);
opt = parse_options(opt, varargin, mfilename);

[P, s] = initialize_factory(opt.Params);
plc    = factory_plc_init(P);
ST     = factory_states();

dt   = P.dt;
nsc  = max(1, round(P.t_scan/dt));
nmax = ceil(P.t_max/dt);
dec  = max(1, round(0.005/dt));            % log at 200 Hz

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
% 2-D force breakdown on the workpiece, for VISUALIZE_PROCESSES. These come
% from the SAME factory_derivatives call that already produces blk_a below, so
% they cost no extra physics evaluations and cannot disagree with the motion.
LOG.F_rod  = zeros(nl,2);  LOG.F_stop = zeros(nl,2);
LOG.F_fric = zeros(nl,2);  LOG.F_net  = zeros(nl,2);
LOG.belt_v = zeros(nl,2);  LOG.reg    = zeros(nl,1);

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
        LOG.rod_F(li,:) = (s(P.IX.PA).*P.A_A - s(P.IX.PB).*P.A_B ...
                           - P.P_atm*(P.A_A-P.A_B))';
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
        LOG.F_rod(li,:)  = dbg.F_rod;   LOG.F_stop(li,:) = dbg.F_stop;
        LOG.F_fric(li,:) = dbg.F_fric;  LOG.F_net(li,:)  = dbg.F_net;
        LOG.belt_v(li,:) = dbg.belt_v;  LOG.reg(li)      = dbg.reg;
        yy = factory_sensors(s, P);
        LOG.sens(li,:) = [yy.CAM yy.PX yy.EXT yy.HS_TOP yy.HS_BOT yy.ESTOP_OK];
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
LOG.plc        = plc;
LOG.cycle_time = t;
LOG.complete   = plc.complete;
LOG.blk_final  = [s(P.IX.bx) s(P.IX.by)];
LOG.blk_target = P.WP.bin;
LOG.pos_error  = norm(LOG.blk_final - LOG.blk_target);
te = t_state_entry;
LOG.time_station1 = te(13) - te(6);      % S05 -> S12 entry
LOG.time_station2 = te(23) - te(19);     % S18 -> S22 entry
LOG.time_engrave  = te(28) - te(23);     % base up -> base down
LOG.time_station3 = t      - te(30);     % S29 -> end
LOG.time_operator = P.t_op_notice + P.t_engrave + P.t_op_confirm;
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
    fprintf('  of which operator    %8.3f s  (PLACEHOLDER timing)\n', ...
            LOG.time_operator);
    fprintf('  machine time         %8.3f s\n', ...
            LOG.cycle_time - LOG.time_operator);
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

if opt.Plot;    plot_factory_results(LOG); end
if opt.Animate; visualize_factory(LOG);    end
end
