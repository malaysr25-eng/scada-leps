function plc = factory_plc_init(P)
%FACTORY_PLC_INIT  Create the PLC controller state struct.
plc.state       = 1;              % S00_INIT
plc.t_in        = 0;              % time in current state [s]
plc.pump_enable = false;          % sequencer's pump request
plc.pump        = false;          % pump contactor after pressure switch
plc.dv          = [0 0 0 0];      % distribution valve branch select
plc.sol         = zeros(1,P.NSOL);% the machine's 13 solenoid coils
plc.estop       = false;          % true while the E-Stop loop is open
% Derived interlock status, recomputed every scan by FACTORY_PLC. Initialised
% false so the struct has its full shape before the first scan.
plc.ilk         = struct('air_ok',false,'plate_home',false, ...
                         'cyl_home',false,'estop_ok',false,'startup_ok',false);
plc.conv        = [0 0 0];        % conveyor run commands
plc.base        = 0;              % engraving base up/down
plc.op_notified = false;
plc.engraving   = false;
plc.engraved    = false;
plc.complete    = false;
plc.fault       = false;
plc.log         = cell(0,3);      % {time, state name, excel ref}
plc.timeouts    = cell(0,2);      % {time, state name}
end
