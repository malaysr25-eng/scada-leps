function B = factory_sensor_bus(P)
%FACTORY_SENSOR_BUS  The one definition of the plant -> PLC sensor vector.
%
%   B = FACTORY_SENSOR_BUS(P) returns a struct of index ranges into the
%   sensor bus, plus B.width, derived from the parameter set.
%
%   WHY THIS FILE EXISTS
%
%   The bus layout was written out by hand in THREE places that had to agree:
%   the packing in FACTORY_PLANT_SFUN, the unpacking in FACTORY_PLC_SFUN, and
%   twenty-seven literal indices inside the Stateflow guard strings that
%   BUILD_FACTORY_MODEL generates. Nothing checked that they agreed.
%
%   They agreed only because the widths had never changed. On 2026-09-02 the
%   proximity sensors went from the model's 4 to the machine's 10, which
%   shifts every channel after them by six. Doing that by hand across three
%   files, one of which encodes the indices inside generated strings, is the
%   kind of edit that passes review and fails silently in one branch of a
%   state machine nobody exercises that week.
%
%   So the layout is defined once, here, and the three consumers ask.
%
%   LAYOUT (widths come from P, so this table is a description, not a promise)
%
%     CAM       1               camera at the feeder
%     PX        n_prox          proximity sensors, the MACHINE's numbering
%     EXT       NCYL            cylinder fully extended
%     RET       NCYL            cylinder fully retracted
%     HS_TOP    1               engraving platform upper limit  (PGM_Up_Limit)
%     HS_BOT    1               engraving platform lower limit  (PGM_Low_Limit)
%     P_res     1               receiver pressure, ANALOGUE, not thresholded
%     P_READY   1               receiver at working pressure
%     BR_RDY    NBR             distribution branch pressurised
%     CHG       NCYL            retract chamber charged
%     ESTOP_OK  1               E-Stop loop closed (the machine's Emergency)
%
%   WHAT IS DELIBERATELY *NOT* A CHANNEL HERE. Air_Pressure_ok,
%   ENGV_Plate_Home, All_Cylinders_Home and Startup_Healthy are all real tags
%   on the machine, and every one of them is the same physical condition as a
%   channel already on this bus: P_READY, HS_BOT, all(RET), and a conjunction
%   of those three. They are mapped onto those channels in FACTORY_IO_MAP
%   rather than duplicated here. Two channels computing one condition is how
%   this project has drifted before.
%
%   HS_TOP and HS_BOT are the machine's Proximity_sensor_11 and _12. They are
%   kept in their own channels rather than folded into PX because the model
%   computes them from the platform's height, not from the workpiece position,
%   and merging them would hide that difference. See FACTORY_IO_MAP.
%
%   Example
%     B = factory_sensor_bus(FactoryParams());
%     v(B.PX(6))        % conveyor 1 sensor, machine numbering
%
%   See also FACTORY_SENSORS, FACTORY_PLANT_SFUN, FACTORY_PLC_SFUN,
%   BUILD_FACTORY_MODEL.

if nargin < 1 || isempty(P)
    P = factory_params_cached();
end

nProx = size(P.PROX, 1);
nCyl  = P.NCYL;
nBr   = numel(P.IX.P_br);

k = 0;
    function r = take(w)
        r = k + (1:w);
        k = k + w;
    end

B.CAM     = take(1);
B.PX      = take(nProx);
B.EXT     = take(nCyl);
B.RET     = take(nCyl);
B.HS_TOP  = take(1);
B.HS_BOT  = take(1);
B.P_res   = take(1);
B.P_READY = take(1);
B.BR_RDY  = take(nBr);
B.CHG     = take(nCyl);
% Appended rather than filed next to the other interlock-ish channels on
% purpose: appending shifts nothing that already exists, and this bus is read
% by three consumers plus a set of generated Stateflow guard strings.
B.ESTOP_OK = take(1);

B.width   = k;

% Channels that are logical on the wire and must be thresholded at 0.5 when
% unpacked. P_res is the sole analogue channel and is deliberately absent.
B.logical = {'CAM','PX','EXT','RET','HS_TOP','HS_BOT','P_READY','BR_RDY', ...
             'CHG','ESTOP_OK'};
end
