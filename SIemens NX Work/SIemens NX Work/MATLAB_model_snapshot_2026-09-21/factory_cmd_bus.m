function B = factory_cmd_bus(P)
%FACTORY_CMD_BUS  The one definition of the PLC -> plant command vector.
%
%   B = FACTORY_CMD_BUS(P) returns a struct of index ranges into the command
%   vector, plus B.width, derived from the parameter set.
%
%   WHY THIS FILE EXISTS
%
%   The same argument that produced FACTORY_SENSOR_BUS, one bus later. The
%   command layout was written out by hand in FOUR places that had to agree:
%   the packing in FACTORY_PLC_SFUN, the unpacking in FACTORY_PLANT_SFUN, the
%   root Inport width and the Stateflow action strings in
%   BUILD_FACTORY_MODEL, and the reconstruction in RUN_SIMULINK_MODEL.
%
%   They agreed only because the width had never changed. On 2026-09-02 the
%   plant went from 5 spring-return cylinders to the machine's 11 actuators on
%   13 coils, so the vector went from 14 wide to 22 and every station-valve
%   index after the branch selects moved. Doing that by hand across four
%   files, one of which encodes the indices inside GENERATED strings, is the
%   edit that passes review and then drives the wrong coil in one branch of a
%   state machine nobody exercises that week.
%
%   So the layout is defined once, here, and the four consumers ask.
%
%   LAYOUT (widths come from P, so this table is a description, not a promise)
%
%     pump    1        compressor contactor
%     dv      4        distribution valve branch select
%     sol     NSOL     THE MACHINE'S SOLENOID COILS, 13 of them
%     conv    NCONV    conveyor run commands
%     base    1        engraving base up/down
%
%   sol is indexed by COIL, not by actuator. Eleven actuators carry thirteen
%   coils because CYL_A and CYL_B are double-solenoid and take an extend and a
%   retract coil each. FACTORY_ACTUATORS maps coil to actuator; nothing else
%   should.
%
%   Example
%     B = factory_cmd_bus(FactoryParams());
%     v(B.sol(7))        % cylinder A extend coil, machine numbering
%
%   See also FACTORY_SENSOR_BUS, FACTORY_ACTUATORS, FACTORY_PLC_SFUN,
%   FACTORY_PLANT_SFUN, BUILD_FACTORY_MODEL.

if nargin < 1 || isempty(P)
    P = factory_params_cached();
end

k = 0;
    function r = take(w)
        r = k + (1:w);
        k = k + w;
    end

B.pump = take(1);
B.dv   = take(4);
B.sol  = take(P.NSOL);
B.conv = take(P.NCONV);
B.base = take(1);

B.width = k;
end
