function plot_factory_results(LOG)
if nargin < 1 || isempty(LOG); LOG = factory_log(); end
%PLOT_FACTORY_RESULTS  Dashboard of the logged physical and control signals.
%
%   PLOT_FACTORY_RESULTS(LOG) draws the mechanical, pneumatic and control
%   traces produced by RUN_FACTORY_SIMULATION.

P = LOG.P; t = LOG.t;
figure('Name','Factory Simulation Results','Color','w','Position',[80 60 1180 800]);

subplot(3,3,1);
plot(t, LOG.blk(:,1), t, LOG.blk(:,2), 'LineWidth',1.2); grid on;
xlabel('t (s)'); ylabel('m'); title('Workpiece position');
legend('x','y','Location','best');

subplot(3,3,2);
plot(t, hypot(LOG.blk_v(:,1), LOG.blk_v(:,2)), 'LineWidth',1.2); grid on;
xlabel('t (s)'); ylabel('m/s'); title('Workpiece speed');

subplot(3,3,3);
plot(t, hypot(LOG.blk_a(:,1), LOG.blk_a(:,2)), 'LineWidth',1.2); grid on;
xlabel('t (s)'); ylabel('m/s^2'); title('Workpiece acceleration');

subplot(3,3,4);
plot(t, LOG.rod*1000, 'LineWidth',1.1); grid on;
xlabel('t (s)'); ylabel('mm'); title('Actuator rod positions');
legend({P.CYL.name},'Location','best','FontSize',7);

subplot(3,3,5);
plot(t, LOG.rod_F, 'LineWidth',1.1); grid on;
xlabel('t (s)'); ylabel('N'); title('Net actuator force  P_AA_A-P_BA_B');

subplot(3,3,6);
plot(t, LOG.v_blt, 'LineWidth',1.2); grid on;
xlabel('t (s)'); ylabel('m/s'); title('Belt speeds  v = r\omega');
legend('C1','C2','C3','Location','best','FontSize',7);

subplot(3,3,7);
yyaxis left;
plot(t, LOG.P_res/1e5, 'k', 'LineWidth',1.4); hold on;
plot(t, LOG.P_br/1e5, 'LineWidth',0.9); grid on;
yline(P.P_cut_out/1e5,'r--'); yline(P.P_cut_in/1e5,'g--');
yline(P.P_set/1e5,'b:');                      % Janatics FRL set point
xlabel('t (s)'); ylabel('bar');
yyaxis right;
plot(t, 1000*LOG.m_air/P.rho0, 'LineWidth',1.2);
ylabel('air (NL)');
title('Pressures (L) and cumulative air (R)');
legend('receiver','br1','br2','br3','br4','cut-out','cut-in','FRL set', ...
       'air NL','Location','best','FontSize',6);

subplot(3,3,8);
plot(t, LOG.PA/1e5, '-', 'LineWidth',1.0); hold on;
plot(t, LOG.PB/1e5, '--','LineWidth',1.0); grid on;
xlabel('t (s)'); ylabel('bar'); title('Cylinder chambers (solid A, dashed B)');

subplot(3,3,9);
stairs(t, LOG.state, 'LineWidth',1.3); grid on; hold on;
plot(t, LOG.base_z*1000, 'LineWidth',1.1);
xlabel('t (s)'); ylabel('state / mm'); title('PLC state and base height');
legend('PLC state','base z (mm)','Location','best','FontSize',7);

sgtitle(sprintf(['Physics-based factory cycle   |   cycle %.2f s   |   ' ...
    'position error %.2f mm   |   peak chamber %.2f bar'], ...
    LOG.cycle_time, 1000*LOG.pos_error, max([LOG.PA(:);LOG.PB(:)])/1e5));
end
