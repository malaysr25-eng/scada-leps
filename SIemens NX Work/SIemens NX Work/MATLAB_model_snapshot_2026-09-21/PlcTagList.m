function T = PlcTagList()
%PLCTAGLIST  The real cell's PLC tag register - CONFIRMED HARDWARE DATA.
%
%   T = PLCTAGLIST() returns a table of every tag the machine's Siemens S7
%   PLC publishes, transcribed MECHANICALLY from plc/PLC_Tag_List.xlsx.
%
%   THIS FILE IS UNLIKE EVERYTHING ELSE IN THIS PROJECT. Every other
%   parameter here is an assumption, an estimate, or a provisional
%   catalogue figure. These are OBSERVED FACTS about the installed machine:
%   the tag names, data types and data-block addresses it actually exposes.
%   Do not edit them to suit the model. If the model disagrees, the model
%   is what is wrong.
%
%   Columns
%     Sheet    sheet of the supplied register
%     Section  heading it sat under
%     Group    interlock | system | magazine | din | dout | analog | axis | manual
%     Name     full symbolic tag name
%     Short    name with the container path stripped, e.g. Comp1.Ok
%     Type     Bool | Int | Real
%     DB       data block number (59 throughout)
%     Kind     X bit, W word, D double word
%     Byte     byte offset in the DB
%     Bit      bit offset, 0 for W and D
%     Desc     the register's own description
%
%   Short is NOT unique on its own: a solenoid or conveyor appears once as
%   a Digital_Outputs coil and again as a manual_commands mirror. They are
%   the same physical coil driven from two places. Use Group to separate
%   them - (Group, Short) together are unique.
%
%   Source: PLC_Dashboard/, supplied 2026-08-24. Siemens S7 at rack 0
%   slot 1, read over SNAP7, every tag in DB59.
%
%   Corrected 2026-09-03: this said "snap7 / OPC UA". It is snap7 only.
%   Neither Final/app.py nor the new_scada backend contains any OPC UA client,
%   and a search of both for "opcua" or port 4840 returns nothing. The
%   distinction matters - see FACTORYPARAMS section 13F, because it is the
%   most likely reason the OPC UA server cannot be found on the network.
%
%   See also FACTORY_IO_MAP, PLCIOTEST, JANATICSDATA.

persistent Tc
if ~isempty(Tc); T = Tc; return; end

raw = { ...
  'io and process tags', 'STRATUP TAGS', 'interlock', 'DB_Global.System.Start_interlocks.Air_Pressure_ok', 'Air_Pressure_ok', 'Bool', 59, 'X', 0, 0, 'Pneumatic air pressure feedback within target operating limits.'
  'io and process tags', 'STRATUP TAGS', 'interlock', 'DB_Global.System.Start_interlocks.ENGV_Plate_Home', 'ENGV_Plate_Home', 'Bool', 59, 'X', 0, 1, 'Engraving plate physical home position sensor feedback.'
  'io and process tags', 'STRATUP TAGS', 'interlock', 'DB_Global.System.Start_interlocks.All_Cylinders_Home', 'All_Cylinders_Home', 'Bool', 59, 'X', 0, 2, 'Retracted home-position confirmation for all pneumatic cylinders.'
  'io and process tags', 'STRATUP TAGS', 'interlock', 'DB_Global.System.Start_interlocks.Emergency Healthy', 'Emergency Healthy', 'Bool', 59, 'X', 0, 3, 'Safety relay loop closed / E-Stop circuit healthy signal.'
  'io and process tags', 'STRATUP TAGS', 'system', 'DB_Global.System.Startup_Healthy', 'Startup_Healthy', 'Bool', 59, 'X', 2, 0, 'Initial power-up sequence and diagnostics completed cleanly.'
  'io and process tags', 'PRODUCT SELECTION AND STATUS', 'system', 'DB_Global.System.Productqty_25mm', 'Productqty_25mm', 'Int', 59, 'W', 108, 0, 'Target selection or piece counter setpoint for 25mm dimension specifications required per processing batch run.'
  'io and process tags', 'PRODUCT SELECTION AND STATUS', 'system', 'DB_Global.System.Productqty_50mm', 'Productqty_50mm', 'Int', 59, 'W', 110, 0, 'Target selection or piece counter setpoint for 50mm dimension specifications required per processing batch run'
  'io and process tags', 'PRODUCT SELECTION AND STATUS', 'system', 'DB_Global.System.MODE_HIGH_SPEED', 'MODE_HIGH_SPEED', 'Bool', 59, 'X', 112, 0, 'Operating mode toggled to high-speed run profile selection.'
  'io and process tags', 'PRODUCT SELECTION AND STATUS', 'system', 'DB_Global.System.CMD_START', 'CMD_START', 'Bool', 59, 'X', 112, 2, 'Command bit triggered by the HMI to initialize the sequence loop.'
  'io and process tags', 'PRODUCT SELECTION AND STATUS', 'system', 'DB_Global.System.Engraving_Completed', 'Engraving_Completed', 'Bool', 59, 'X', 112, 3, 'Execution bit signaling the engraving process step finished.'
  'io and process tags', 'PRODUCT SELECTION AND STATUS', 'system', 'DB_Global.System.Total products', 'Total products', 'Int', 59, 'W', 114, 0, 'Total quantity tracking storage variable across all specs.'
  'io and process tags', 'PRODUCT SELECTION AND STATUS', 'system', 'DB_Global.System.Cycle_Completed', 'Cycle_Completed', 'Bool', 59, 'X', 116, 0, 'Completed process cycle status confirmation logic bit.'
  'io and process tags', 'PRODUCT SELECTION AND STATUS', 'system', 'DB_Global.System.Cycle_Reset', 'Cycle_Reset', 'Bool', 59, 'X', 116, 1, 'Reset command input to clear the active process sequence parameters.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp1.Ok', 'Comp1.Ok', 'Bool', 59, 'X', 118, 0, 'Comp1 - Compartment status healthy with sufficient inventory or magazines ready.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp1.Low', 'Comp1.Low', 'Bool', 59, 'X', 118, 1, 'Comp1 - Compartment inventory dropping below threshold level alert.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp1.Empty', 'Comp1.Empty', 'Bool', 59, 'X', 118, 2, 'Comp1 - Compartment completely depleted of magazines warning indicator.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp2.Ok', 'Comp2.Ok', 'Bool', 59, 'X', 120, 0, 'Comp2 - Compartment status healthy with sufficient inventory or magazines ready.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp2.Low', 'Comp2.Low', 'Bool', 59, 'X', 120, 1, 'Comp2 - Compartment inventory dropping below threshold level alert.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp2.Empty', 'Comp2.Empty', 'Bool', 59, 'X', 120, 2, 'Comp2 - Compartment completely depleted of magazines warning indicator.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp3.Ok', 'Comp3.Ok', 'Bool', 59, 'X', 122, 0, 'Comp3 - Compartment status healthy with sufficient inventory or magazines ready.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp3.Low', 'Comp3.Low', 'Bool', 59, 'X', 122, 1, 'Comp3 - Compartment inventory dropping below threshold level alert.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp3.Empty', 'Comp3.Empty', 'Bool', 59, 'X', 122, 2, 'Comp3 - Compartment completely depleted of magazines warning indicator.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp4.Ok', 'Comp4.Ok', 'Bool', 59, 'X', 124, 0, 'Comp4 - Compartment status healthy with sufficient inventory or magazines ready.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp4.Low', 'Comp4.Low', 'Bool', 59, 'X', 124, 1, 'Comp4 - Compartment inventory dropping below threshold level alert.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp4.Empty', 'Comp4.Empty', 'Bool', 59, 'X', 124, 2, 'Comp4 - Compartment completely depleted of magazines warning indicator.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp5.Ok', 'Comp5.Ok', 'Bool', 59, 'X', 126, 0, 'Comp5 - Compartment status healthy with sufficient inventory or magazines ready.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp5.Low', 'Comp5.Low', 'Bool', 59, 'X', 126, 1, 'Comp5 - Compartment inventory dropping below threshold level alert.'
  'io and process tags', 'Product level status to plc', 'magazine', 'DB_Global.Comp_Status.Comp5.Empty', 'Comp5.Empty', 'Bool', 59, 'X', 126, 2, 'Comp5 - Compartment completely depleted of magazines warning indicator.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor1', 'Proximity_sensor1', 'Bool', 59, 'X', 128, 0, 'Proximity sensor 1 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor2', 'Proximity_sensor2', 'Bool', 59, 'X', 128, 1, 'Proximity sensor 2 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor3', 'Proximity_sensor3', 'Bool', 59, 'X', 128, 2, 'Proximity sensor 3 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor4', 'Proximity_sensor4', 'Bool', 59, 'X', 128, 3, 'Proximity sensor 4 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor5', 'Proximity_sensor5', 'Bool', 59, 'X', 128, 4, 'Proximity sensor 5 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor6', 'Proximity_sensor6', 'Bool', 59, 'X', 128, 5, 'Proximity sensor 6 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor7', 'Proximity_sensor7', 'Bool', 59, 'X', 128, 6, 'Proximity sensor 7 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor8', 'Proximity_sensor8', 'Bool', 59, 'X', 128, 7, 'Proximity sensor 8 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor9', 'Proximity_sensor9', 'Bool', 59, 'X', 129, 0, 'Proximity sensor 9 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Proximity_sensor10', 'Proximity_sensor10', 'Bool', 59, 'X', 129, 1, 'Proximity sensor 10 feedback status.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.PGM_Low_Limit', 'PGM_Low_Limit', 'Bool', 59, 'X', 129, 2, 'Program low limit physical overtravel switch input.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.PGM_Up_Limit', 'PGM_Up_Limit', 'Bool', 59, 'X', 129, 3, 'Program high/up limit physical overtravel switch input.'
  'io and process tags', 'Digital input status', 'din', 'DB_Global.IO Status.Digital_Inputs.Emergency', 'Emergency', 'Bool', 59, 'X', 129, 4, 'Local emergency stop circuit feedback monitoring bit.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve1', 'Solenoid_valve1', 'Bool', 59, 'X', 130, 0, 'Physical output command coil for Solenoid Valve 1.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve2', 'Solenoid_valve2', 'Bool', 59, 'X', 130, 1, 'Physical output command coil for Solenoid Valve 2.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve3', 'Solenoid_valve3', 'Bool', 59, 'X', 130, 2, 'Physical output command coil for Solenoid Valve 3.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve4', 'Solenoid_valve4', 'Bool', 59, 'X', 130, 3, 'Physical output command coil for Solenoid Valve 4.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve5', 'Solenoid_valve5', 'Bool', 59, 'X', 130, 4, 'Physical output command coil for Solenoid Valve 5.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve6', 'Solenoid_valve6', 'Bool', 59, 'X', 130, 5, 'Physical output command coil for Solenoid Valve 6.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve7', 'Solenoid_valve7', 'Bool', 59, 'X', 130, 6, 'Physical output command coil for Solenoid Valve 7.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve8', 'Solenoid_valve8', 'Bool', 59, 'X', 130, 7, 'Physical output command coil for Solenoid Valve 8.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve9', 'Solenoid_valve9', 'Bool', 59, 'X', 131, 0, 'Physical output command coil for Solenoid Valve 9.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve10', 'Solenoid_valve10', 'Bool', 59, 'X', 131, 1, 'Physical output command coil for Solenoid Valve 10.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve11', 'Solenoid_valve11', 'Bool', 59, 'X', 131, 2, 'Physical output command coil for Solenoid Valve 11.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve12', 'Solenoid_valve12', 'Bool', 59, 'X', 131, 3, 'Physical output command coil for Solenoid Valve 12.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Solenoid_valve13', 'Solenoid_valve13', 'Bool', 59, 'X', 131, 4, 'Physical output command coil for Solenoid Valve 13.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Conveyor1', 'Conveyor1', 'Bool', 59, 'X', 131, 5, 'Physical run command coil for Conveyor System 1.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Conveyor2', 'Conveyor2', 'Bool', 59, 'X', 131, 6, 'Physical run command coil for Conveyor System 2.'
  'io and process tags', 'Digital output status', 'dout', 'DB_Global.IO Status.Digital_Outputs.Conveyor3', 'Conveyor3', 'Bool', 59, 'X', 131, 7, 'Physical run command coil for Conveyor System 3.'
  'io and process tags', 'analog input status', 'analog', 'DB_Global.IO Status.Analog_inputs.Pressure.Value', 'Pressure.Value', 'Real', 59, 'D', 132, 0, 'Raw scaled or calculated engineering value of the process pressure.'
  'io and process tags', 'analog input status', 'analog', 'DB_Global.IO Status.Analog_inputs.Pressure.Normx', 'Pressure.Normx', 'Real', 59, 'D', 136, 0, 'Normalized percentage value representation (0.0 to 1.0 scale).'
  'io and process tags', 'analog input status', 'analog', 'DB_Global.IO Status.Analog_inputs.Pressure.Low Value', 'Pressure.Low Value', 'Real', 59, 'D', 140, 0, 'Minimum engineering scaling range setpoint boundary limit.'
  'io and process tags', 'analog input status', 'analog', 'DB_Global.IO Status.Analog_inputs.Pressure.High Value', 'Pressure.High Value', 'Real', 59, 'D', 144, 0, 'Maximum engineering scaling range setpoint boundary limit.'
  'io and process tags', 'analog input status', 'analog', 'DB_Global.IO Status.Analog_inputs.Pressure.Low Alarm', 'Pressure.Low Alarm', 'Bool', 59, 'X', 148, 0, 'Active flag identifying if value falls beneath the low threshold limit.'
  'io and process tags', 'analog input status', 'analog', 'DB_Global.IO Status.Analog_inputs.Pressure.High Alarm', 'Pressure.High Alarm', 'Bool', 59, 'X', 148, 1, 'Active flag identifying if value exceeds the high threshold limit.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Set_HighSpeed', 'Conv1.Set_HighSpeed', 'Bool', 59, 'X', 150, 0, 'Conv1 - Flag to toggle high speed operational mode via Stepper Technology Object.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.HighSpeed_Position', 'Conv1.HighSpeed_Position', 'Real', 59, 'D', 152, 0, 'Conv1 - Target position coordinate for high speed operations.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.HighSpeed_Velocity', 'Conv1.HighSpeed_Velocity', 'Real', 59, 'D', 156, 0, 'Conv1 - Velocity profile target value for high speed motions.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.LowSpeed_Position', 'Conv1.LowSpeed_Position', 'Real', 59, 'D', 160, 0, 'Conv1 - Target position coordinate for low speed operations.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.LowSpeed_Velocity', 'Conv1.LowSpeed_Velocity', 'Real', 59, 'D', 164, 0, 'Conv1 - Velocity profile target value for low speed motions.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Set_Position', 'Conv1.Set_Position', 'Real', 59, 'D', 168, 0, 'Conv1 - Custom manual or automated setpoint position index.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Set_Velocity', 'Conv1.Set_Velocity', 'Real', 59, 'D', 172, 0, 'Conv1 - Custom manual or automated setpoint velocity index.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Goto_Position', 'Conv1.Goto_Position', 'Bool', 59, 'X', 176, 0, 'Conv1 - Command bit to initiate positioning cycle execution.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Set_Home', 'Conv1.Set_Home', 'Bool', 59, 'X', 176, 1, 'Conv1 - Command flag to execute a homing routine on the active axis.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Error_Fb', 'Conv1.Error_Fb', 'Bool', 59, 'X', 176, 2, 'Conv1 - Active fault or error state feedback loop identifier from driver.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Axis_Homed_Fb', 'Conv1.Axis_Homed_Fb', 'Bool', 59, 'X', 176, 3, 'Conv1 - Axis calibration feedback confirming home position is locked.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Current_Position_Fb', 'Conv1.Current_Position_Fb', 'Real', 59, 'D', 178, 0, 'Conv1 - Live position feedback reading from encoder loop.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Current_Velocity_Fb', 'Conv1.Current_Velocity_Fb', 'Real', 59, 'D', 182, 0, 'Conv1 - Live velocity feedback reading from encoder loop.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv1.Reset', 'Conv1.Reset', 'Bool', 59, 'X', 186, 0, 'Conv1 - Fault acknowledgement and tracking reset command.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Set_HighSpeed', 'Conv2.Set_HighSpeed', 'Bool', 59, 'X', 188, 0, 'Conv2 - Flag to toggle high speed operational mode via Stepper Technology Object.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.HighSpeed_Position', 'Conv2.HighSpeed_Position', 'Real', 59, 'D', 190, 0, 'Conv2 - Target position coordinate for high speed operations.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.HighSpeed_Velocity', 'Conv2.HighSpeed_Velocity', 'Real', 59, 'D', 194, 0, 'Conv2 - Velocity profile target value for high speed motions.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.LowSpeed_Position', 'Conv2.LowSpeed_Position', 'Real', 59, 'D', 198, 0, 'Conv2 - Target position coordinate for low speed operations.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.LowSpeed_Velocity', 'Conv2.LowSpeed_Velocity', 'Real', 59, 'D', 202, 0, 'Conv2 - Velocity profile target value for low speed motions.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Set_Position', 'Conv2.Set_Position', 'Real', 59, 'D', 206, 0, 'Conv2 - Custom manual or automated setpoint position index.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Set_Velocity', 'Conv2.Set_Velocity', 'Real', 59, 'D', 210, 0, 'Conv2 - Custom manual or automated setpoint velocity index.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Goto_Position', 'Conv2.Goto_Position', 'Bool', 59, 'X', 214, 0, 'Conv2 - Command bit to initiate positioning cycle execution.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Set_Home', 'Conv2.Set_Home', 'Bool', 59, 'X', 214, 1, 'Conv2 - Command flag to execute a homing routine on the active axis.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Error_Fb', 'Conv2.Error_Fb', 'Bool', 59, 'X', 214, 2, 'Conv2 - Active fault or error state feedback loop identifier from driver.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Axis_Homed_Fb', 'Conv2.Axis_Homed_Fb', 'Bool', 59, 'X', 214, 3, 'Conv2 - Axis calibration feedback confirming home position is locked.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Current_Position_Fb', 'Conv2.Current_Position_Fb', 'Real', 59, 'D', 216, 0, 'Conv2 - Live position feedback reading from encoder loop.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Current_Velocity_Fb', 'Conv2.Current_Velocity_Fb', 'Real', 59, 'D', 220, 0, 'Conv2 - Live velocity feedback reading from encoder loop.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv2.Reset', 'Conv2.Reset', 'Bool', 59, 'X', 224, 0, 'Conv2 - Fault acknowledgement and tracking reset command.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Set_HighSpeed', 'Conv3.Set_HighSpeed', 'Bool', 59, 'X', 226, 0, 'Conv3 - Flag to toggle high speed operational mode via Stepper Technology Object.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.HighSpeed_Position', 'Conv3.HighSpeed_Position', 'Real', 59, 'D', 228, 0, 'Conv3 - Target position coordinate for high speed operations.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.HighSpeed_Velocity', 'Conv3.HighSpeed_Velocity', 'Real', 59, 'D', 232, 0, 'Conv3 - Velocity profile target value for high speed motions.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.LowSpeed_Position', 'Conv3.LowSpeed_Position', 'Real', 59, 'D', 236, 0, 'Conv3 - Target position coordinate for low speed operations.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.LowSpeed_Velocity', 'Conv3.LowSpeed_Velocity', 'Real', 59, 'D', 240, 0, 'Conv3 - Velocity profile target value for low speed motions.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Set_Position', 'Conv3.Set_Position', 'Real', 59, 'D', 244, 0, 'Conv3 - Custom manual or automated setpoint position index.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Set_Velocity', 'Conv3.Set_Velocity', 'Real', 59, 'D', 248, 0, 'Conv3 - Custom manual or automated setpoint velocity index.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Goto_Position', 'Conv3.Goto_Position', 'Bool', 59, 'X', 252, 0, 'Conv3 - Command bit to initiate positioning cycle execution.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Set_Home', 'Conv3.Set_Home', 'Bool', 59, 'X', 252, 1, 'Conv3 - Command flag to execute a homing routine on the active axis.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Error_Fb', 'Conv3.Error_Fb', 'Bool', 59, 'X', 252, 2, 'Conv3 - Active fault or error state feedback loop identifier from driver.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Axis_Homed_Fb', 'Conv3.Axis_Homed_Fb', 'Bool', 59, 'X', 252, 3, 'Conv3 - Axis calibration feedback confirming home position is locked.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Current_Position_Fb', 'Conv3.Current_Position_Fb', 'Real', 59, 'D', 254, 0, 'Conv3 - Live position feedback reading from encoder loop.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Current_Velocity_Fb', 'Conv3.Current_Velocity_Fb', 'Real', 59, 'D', 258, 0, 'Conv3 - Live velocity feedback reading from encoder loop.'
  'pot control', '', 'axis', 'DB_Global.Pot_Control.Conv3.Reset', 'Conv3.Reset', 'Bool', 59, 'X', 262, 0, 'Conv3 - Fault acknowledgement and tracking reset command.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve1', 'Solenoid_Valve1', 'Bool', 59, 'X', 264, 0, 'Manual activation toggle for Solenoid Valve 1.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve2', 'Solenoid_Valve2', 'Bool', 59, 'X', 264, 1, 'Manual activation toggle for Solenoid Valve 2.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve3', 'Solenoid_Valve3', 'Bool', 59, 'X', 264, 2, 'Manual activation toggle for Solenoid Valve 3.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve4', 'Solenoid_Valve4', 'Bool', 59, 'X', 264, 3, 'Manual activation toggle for Solenoid Valve 4.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve5', 'Solenoid_Valve5', 'Bool', 59, 'X', 264, 4, 'Manual activation toggle for Solenoid Valve 5.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve6', 'Solenoid_Valve6', 'Bool', 59, 'X', 264, 5, 'Manual activation toggle for Solenoid Valve 6.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve7', 'Solenoid_Valve7', 'Bool', 59, 'X', 264, 6, 'Manual activation toggle for Solenoid Valve 7.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve8', 'Solenoid_Valve8', 'Bool', 59, 'X', 264, 7, 'Manual activation toggle for Solenoid Valve 8.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve9', 'Solenoid_Valve9', 'Bool', 59, 'X', 265, 0, 'Manual activation toggle for Solenoid Valve 9.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve10', 'Solenoid_Valve10', 'Bool', 59, 'X', 265, 1, 'Manual activation toggle for Solenoid Valve 10.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve11', 'Solenoid_Valve11', 'Bool', 59, 'X', 265, 2, 'Manual activation toggle for Solenoid Valve 11.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve12', 'Solenoid_Valve12', 'Bool', 59, 'X', 265, 3, 'Manual activation toggle for Solenoid Valve 12.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Solenoid_Valve13', 'Solenoid_Valve13', 'Bool', 59, 'X', 265, 4, 'Manual activation toggle for Solenoid Valve 13.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Conveyor1', 'Conveyor1', 'Bool', 59, 'X', 265, 5, 'Manual override activation command for Conveyor line 1.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Conveyor2', 'Conveyor2', 'Bool', 59, 'X', 265, 6, 'Manual override activation command for Conveyor line 2.'
  'manual commands', '', 'manual', 'DB_Global.manual_commands.Conveyor3', 'Conveyor3', 'Bool', 59, 'X', 265, 7, 'Manual override activation command for Conveyor line 3.'
};

T = cell2table(raw, 'VariableNames', ...
    {'Sheet','Section','Group','Name','Short','Type','DB','Kind','Byte','Bit','Desc'});
Tc = T;
end
