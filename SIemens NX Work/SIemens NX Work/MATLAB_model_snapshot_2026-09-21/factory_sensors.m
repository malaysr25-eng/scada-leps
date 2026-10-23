function y = factory_sensors(s, P)
%FACTORY_SENSORS  Sensor models. Every output is a function of the PHYSICAL
%   state only. No sensor is ever driven by elapsed time.
%
%   y = FACTORY_SENSORS(s, P) returns a struct of sensor readings:
%     y.CAM         logical   camera sees a workpiece at the feeder  [SRC 1]
%     y.PX(1:10)    logical   proximity sensors, MACHINE numbering
%     y.EXT(1:11)   logical   actuator fully extended      [SRC 24,35]
%     y.RET(1:11)   logical   actuator fully retracted     (implicit)
%     y.HS_TOP      logical   height sensor, top verified        [SRC 26]
%     y.HS_BOT      logical   height sensor, bottom verified     [SRC 30]
%     y.P_res       double    receiver pressure, analogue          [Pa]
%     y.P_READY     logical   receiver at working pressure       [SRC 4]
%     y.BR_RDY(1:4) logical   distribution branch pressurised    [SRC 4]
%     y.CHG(1:11)   logical   actuator retract chamber charged
%     y.ESTOP_OK    logical   E-Stop loop closed                 [PLC]
%
%   y.ESTOP_OK is the machine's "Emergency" input, and until 2026-09-02 the
%   model had no counterpart to it at all - the one genuine gap left in the
%   sensor set once all ten proximity sensors were modelled. It is driven by
%   P.fault.estop rather than by geometry, because an E-Stop is pressed by a
%   person and there is nothing in the plant state to compute it from.
%
%   y.CHG deserves comment. It reports that the 5/2 valve has actually
%   pre-loaded the rod-side chamber to supply pressure. The PLC waits for it
%   before commanding extension. Without that wait the piston free-runs
%   across the approach gap against an empty chamber and strikes the
%   workpiece at over 1.3 m/s instead of pushing it at 0.2 m/s. This is the
%   physical readiness signal that Sequence.xlsx step 4 calls for.

IX = P.IX;
bx = s(IX.bx); by = s(IX.by);

% --- camera -------------------------------------------------------------
y.CAM = hypot(bx - P.CAM(1), by - P.CAM(2)) < P.prox_rng;

% --- proximity sensors --------------------------------------------------
np = size(P.PROX,1);
y.PX = false(1,np);
for i = 1:np
    y.PX(i) = hypot(bx - P.PROX(i,1), by - P.PROX(i,2)) < P.prox_rng;
end
if P.fault.sensor_fail
    y.PX(:) = false;
end

% --- cylinder end-of-stroke feedback ------------------------------------
n = P.NCYL;
y.EXT = false(1,n); y.RET = false(1,n);
% [JAN] The A54 magnetic-piston cylinder is sensed by a barrel-clamped reed
% switch (AM4 series). The switch reports the position the machine builder
% CLAMPED IT AT, which is the transport target (P.CYL.x_trip), not the
% mechanical end of stroke (P.CYL.stroke). Since Iteration 02 rounds strokes
% up to the Janatics standard ladder these are no longer the same point, and
% waiting for the mechanical end would deadlock the sequence: the rod stops
% against the workpiece locating stop and never reaches it.
for c = 1:n
    x = s(IX.x(c));
    y.EXT(c) = x >= P.CYL(c).x_trip - P.ext_tol;
    y.RET(c) = x <= P.ext_tol;
end

% --- height sensor on the engraving base --------------------------------
z = s(IX.bz) + P.fault.height_sens_bias;
y.HS_TOP = abs(z - P.z_top) < P.z_tol;
y.HS_BOT = abs(z)           < P.z_tol;

% --- E-Stop loop --------------------------------------------------------
% A hard-wired safety loop, not a computed condition. FACTORY_PLC drops every
% coil and holds the sequencer while this is false.
y.ESTOP_OK = ~P.fault.estop;

% --- pneumatic pressures ------------------------------------------------
y.P_res   = s(IX.P_res);
y.P_READY = s(IX.P_res) >= P.P_ready;
y.BR_RDY  = false(1,4);
for k = 1:4
    y.BR_RDY(k) = s(IX.P_br(k)) >= P.P_br_rdy;
end
y.CHG = false(1,n);
for c = 1:n
    y.CHG(c) = s(IX.PB(c)) >= 0.85*P.P_br_rdy;
end
end
