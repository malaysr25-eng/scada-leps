function M = factory_io_map(action)
%FACTORY_IO_MAP  Relate the real PLC's tags to the model's signals.
%
%   M = FACTORY_IO_MAP()          the mapping table
%   FACTORY_IO_MAP('report')      print what is confirmed and what is not
%
%   WHY THIS FILE EXISTS, AND WHAT IT DELIBERATELY DOES NOT DO
%
%   PLCTAGLIST records what the machine's PLC exposes over the network: 10
%   proximity sensors, 13 solenoid valves, 3 conveyors, 5 magazine
%   compartments. Those are facts.
%
%   Until 2026-08-30 nothing supplied said which solenoid drove which
%   cylinder or where any sensor sat, and 23 rows here read UNMAPPED rather
%   than carry an invented answer. Decoding the TIA Portal program listing
%   (plc/abc.pdf) closed most of that: the program text names every coil's
%   physical address, the internal command that writes it, and the network
%   that fires it. See the block comment above the sensor rows below.
%
%   What the listing does NOT say is where a sensor is bolted or which
%   physical barrel is "cylinder A". Those rows are PROVISIONAL, and walking
%   the cell is still what closes them.
%
%   ALL TEN proximity sensors are now MODELLED, in the machine's own
%   numbering (2026-09-02). The four the sequence gates on kept their exact
%   physical trip points, which is why the pinned cycle time did not move;
%   only the numbers changed, onto the machine's. See P.PROX in
%   INITIALIZE_FACTORY and P.PROX_GUARD for which four those are.
%   Since 2026-09-11 a fifth, P.PROX_BYPASS (prox 8), gates the SV11 bypass
%   route, and the belt-2 guard of the engraved route is prox 7.
%
%   ALL THIRTEEN SOLENOID COILS ARE NOW MODELLED TOO (2026-09-02, later the
%   same day). The plant carries the machine's eleven pneumatic actuators,
%   with CYL_A and CYL_B double-solenoid, so each coil row below names a real
%   element of the command vector rather than a cylinder the model did not
%   have. See FACTORY_ACTUATORS and FACTORY_CMD_BUS.
%
%   AND FIVE ROWS STOPPED POINTING AT NOTHING. Air_Pressure_ok,
%   ENGV_Plate_Home, All_Cylinders_Home, Emergency and Startup_Healthy were
%   all marked CONFIRMED against `ilk.*` model signals THAT WERE NEVER BUILT.
%   A row mapping a real tag onto a name nobody implemented is worse than an
%   UNMAPPED row, because it reads as done. They now name the channel or the
%   derived status that actually exists.
%
%   Every row carries a Status:
%
%     CONFIRMED   the mapping is fixed beyond doubt, either by the tag name
%                 itself (Conveyor1 is conveyor 1; Comp3 is magazine 3) or
%                 by the PLC program text, which is stronger
%     PROVISIONAL a mapping is proposed and is a working assumption
%     UNMAPPED    the real signal exists and the model has no counterpart,
%                 or the counterpart cannot be identified from what we have
%
%   An UNMAPPED row is not an omission. It is the honest state of knowledge,
%   and it is what someone with access to the machine has to fill in.
%   Filling it in is an edit to THIS FILE ONLY.
%
%   See also PLCTAGLIST, PLC_SNAPSHOT, INPUTS_REQUIRED.md.

if nargin < 1; action = 'table'; end

%  PlcShort                ModelSignal          Status         Note
raw = { ...
% ---- conveyors: names fix these outright -------------------------------
 'Conveyor1',              'conv(1)',           'CONFIRMED',   'run command, conveyor 1'
 'Conveyor2',              'conv(2)',           'CONFIRMED',   'run command, conveyor 2'
 'Conveyor3',              'conv(3)',           'CONFIRMED',   'run command, conveyor 3'
% ---- magazine inventory: Comp N is magazine N --------------------------
 'Comp1.Ok',               'mag(1).ok',         'CONFIRMED',   'magazine 1 has stock'
 'Comp1.Low',              'mag(1).low',        'CONFIRMED',   ''
 'Comp1.Empty',            'mag(1).empty',      'CONFIRMED',   ''
 'Comp2.Ok',               'mag(2).ok',         'CONFIRMED',   ''
 'Comp2.Low',              'mag(2).low',        'CONFIRMED',   ''
 'Comp2.Empty',            'mag(2).empty',      'CONFIRMED',   ''
 'Comp3.Ok',               'mag(3).ok',         'CONFIRMED',   ''
 'Comp3.Low',              'mag(3).low',        'CONFIRMED',   ''
 'Comp3.Empty',            'mag(3).empty',      'CONFIRMED',   ''
 'Comp4.Ok',               'mag(4).ok',         'CONFIRMED',   ''
 'Comp4.Low',              'mag(4).low',        'CONFIRMED',   ''
 'Comp4.Empty',            'mag(4).empty',      'CONFIRMED',   ''
 'Comp5.Ok',               'mag(5).ok',         'CONFIRMED',   ''
 'Comp5.Low',              'mag(5).low',        'CONFIRMED',   ''
 'Comp5.Empty',            'mag(5).empty',      'CONFIRMED',   ''
% ---- interlocks and safety: unambiguous by name ------------------------
% Each of these is DERIVED in FACTORY_PLC from a channel the sensor bus
% already carries, rather than given a duplicate channel of its own.
 'Air_Pressure_ok',        'plc.ilk.air_ok',    'CONFIRMED'  , 'derived from y.P_READY. The machine s own switch SETTING is not known - FC8 N1 says the transmitter reads 0-10 bar gauge, not where the ok threshold sits'
 'ENGV_Plate_Home',        'plc.ilk.plate_home','CONFIRMED',   'derived from y.HS_BOT - the same physical condition, platform at its lower limit'
 'All_Cylinders_Home',     'plc.ilk.cyl_home',  'CONFIRMED',   'all(y.RET) over all 11 actuators'
 'Emergency Healthy',      'plc.ilk.estop_ok',  'CONFIRMED',   'derived from y.ESTOP_OK'
 'Startup_Healthy',        'plc.ilk.startup_ok','CONFIRMED',   'air_ok AND plate_home AND cyl_home AND estop_ok'
 'Emergency',              'y.ESTOP_OK',        'CONFIRMED',   'local E-Stop input. MODELLED 2026-09-02, driven by P.fault.estop - the model had no E-Stop at all before that'
% ---- engraving plate limits --------------------------------------------
 'PGM_Up_Limit',           'sens.plate_up',     'CONFIRMED',   'replaces the modelled HS_TOP'
 'PGM_Low_Limit',          'sens.plate_down',   'CONFIRMED',   'replaces the modelled HS_BOT'
% ---- cycle control ------------------------------------------------------
 'CMD_START',              'cmd.start',         'CONFIRMED',   'HMI start'
 'Cycle_Completed',        'cmd.cycle_done',    'CONFIRMED',   ''
 'Cycle_Reset',            'cmd.cycle_reset',   'CONFIRMED',   ''
 'MODE_HIGH_SPEED',        'cmd.high_speed',    'CONFIRMED',   'selects the fast motion profile'
 'Engraving_Completed',    'sens.engrave_done', 'CONFIRMED',   'REPLACES the t_engrave timer placeholder'
 'Productqty_25mm',        'cmd.qty_25',        'CONFIRMED',   'batch count, 25 mm product'
 'Productqty_50mm',        'cmd.qty_50',        'CONFIRMED',   'batch count, 50 mm product'
 'Total products',         'cmd.qty_total',     'CONFIRMED',   ''
% ---- analog pressure ----------------------------------------------------
 'Pressure.Value',         'sens.P_supply',     'CONFIRMED',   'engineering value; snapshot read 4.315'
 'Pressure.Normx',         'sens.P_norm',       'CONFIRMED',   '0..1 normalised'
 'Pressure.Low Value',     'cfg.P_scale_lo',    'CONFIRMED',   'scaling range low'
 'Pressure.High Value',    'cfg.P_scale_hi',    'CONFIRMED',   'scaling range high'
 'Pressure.Low Alarm',     'sens.P_alarm_lo',   'CONFIRMED',   ''
 'Pressure.High Alarm',    'sens.P_alarm_hi',   'CONFIRMED',   ''
% ---- WHAT THE PLC PROGRAM SETTLED, 2026-08-30 ---------------------------
% Everything below was UNMAPPED until the TIA Portal listing (plc/abc.pdf)
% was decoded. It is no longer a guess: the program text names, for every
% coil and every input, the physical address and the network that drives or
% reads it. Two independent networks give the same addresses - FC3
% solenoid_manual, which writes the coils, and FC8 Fc_IO, which mirrors them
% to the HMI - so the decode is cross-checked, not taken on trust.
%
% Blocks referenced below:
%   FC3  solenoid_manual        the ONLY place an output coil is written
%   FC6  void_main              the automatic cycle, networks 1-17
%   FC7  void_main_sub_funcs    magazine selection and the transport flags
%   FC8  Fc_IO                  raw I/O <-> HMI status mirror
%
% WHAT IS STILL NOT KNOWN, and why some rows below are PROVISIONAL: the
% program fixes each signal's ROLE IN THE SEQUENCE. It does not say where a
% sensor is bolted, nor which physical barrel is "cylinder A". Walking the
% cell is still what closes those, and INPUTS_REQUIRED.md 3 and 4 now ask
% the narrower question rather than the open one.
% ---- proximity sensors --------------------------------------------------
 'Proximity_sensor1',      'y.PX(1)',               'CONFIRMED',   '%I0.3  FC7 N2: prox 1 AND workpiece_choice=1 -> 2 s TON -> wp_in_cv1. MODELLED'
 'Proximity_sensor2',      'y.PX(2)',               'CONFIRMED',   '%I0.7  same network, workpiece_choice=2. MODELLED'
 'Proximity_sensor3',      'y.PX(3)',               'CONFIRMED',   '%I0.0  same network, workpiece_choice=3. MODELLED'
 'Proximity_sensor4',      'y.PX(4)',               'CONFIRMED',   '%I0.1  same network, workpiece_choice=4. MODELLED'
 'Proximity_sensor5',      'y.PX(5)',               'CONFIRMED',   '%I1.1  same network, workpiece_choice=5. MODELLED'
 'Proximity_sensor6',      'y.PX(6)',               'PROVISIONAL', '%I1.5  FC6 N3 and FC7 N4: clears mag push, gates conveyor 1. Role known, position along the belt is not'
 'Proximity_sensor7',      'y.PX(7)',               'CONFIRMED',   '%I0.4  FC7 N5 WP IN CV2 MID feeds FC6 N7 CYLA EXT: the ENGRAVED-route stop at the cylinder A line. MODELLED at c2_end, the S16 guard when engraving is selected (at the belt midpoint until 2026-09-11)'
 'Proximity_sensor8',      'y.PX(8)',               'PROVISIONAL', '%I0.6  FC6 N5: 400 ms TP -> Wp_move_cv3 -> solenoid 11. The BYPASS pickup (operator, 2026-09-10); an engraved block never reaches it (recorded). MODELLED at c2_byp, the S16 guard when engraving is skipped. Position is the schematic waypoint, not the tape'
 'Proximity_sensor9',      'y.PX(9)',               'PROVISIONAL', '%I0.2  FC6 N14 sets STOP_CONV3, N16 runs a 5 s TP -> solenoid 12'
 'Proximity_sensor10',     'y.PX(10)',              'PROVISIONAL', '%I0.5  FC6 N16: 5 s TP -> solenoid 13. Second outfeed station, MODELLED at SV13''s line, 55 cm along conveyor 3 and downstream of outfeed A (tape 2026-09-10, applied 2026-09-12)'
% The register's PGM_Low_Limit and PGM_Up_Limit are wired as Proximity_
% sensor_11 (%I1.2) and _12 (%I1.0). 12 wired inputs = 10 proximity sensors
% + 2 platform limits, which reconciles exactly with the register's 10.
% There was never a discrepancy. Those two are mapped above, under the
% engraving plate limits.
% ---- solenoid valves ----------------------------------------------------
% 1-5 are five magazine pushers, one per compartment, selected by
% workpiece_choice. Comp1..Comp5 are already CONFIRMED above, so this is the
% same numbering, and FC7 N3 states it outright.
 'Solenoid_valve1',        'u.sol(1)  MAG1_PUSH',  'CONFIRMED',   '%Q3.1  FC7 N3: mag_push_on AND workpiece_choice=1 -> compartment 1 pusher. MODELLED'
 'Solenoid_valve2',        'u.sol(2)  MAG2_PUSH',  'CONFIRMED',   '%Q3.0  same network, workpiece_choice=2. MODELLED'
 'Solenoid_valve3',        'u.sol(3)  MAG3_PUSH',  'CONFIRMED',   '%Q2.7  same network, workpiece_choice=3. MODELLED'
 'Solenoid_valve4',        'u.sol(4)  MAG4_PUSH',  'CONFIRMED',   '%Q2.6  same network, workpiece_choice=4. MODELLED'
 'Solenoid_valve5',        'u.sol(5)  MAG5_PUSH',  'CONFIRMED',   '%Q2.2  same network, workpiece_choice=5. MODELLED'
 'Solenoid_valve6',        'u.sol(6)  XFER_CV1_CV2','PROVISIONAL','%Q0.2  FC6 N4 SOLENOID VALVE 6 ON, 2 s TON after wp_in_cv1_end, with prox 7 and 8. Reads as the conveyor 1 -> conveyor 2 transfer. MODELLED at that station'
% 7-10 are FOUR COILS ON TWO CYLINDERS, and this is the finding that changed
% the shape of the model: cylinders A and B are DOUBLE-SOLENOID, one coil each
% way, so they hold position with both coils de-energised. As of 2026-09-02
% the plant expresses that - FACTORY_DERIVATIVES latches the spool and holds
% it when neither coil is energised, which a spring-return valve cannot do.
%
% THESE FOUR ROWS STAY CONFIRMED, and the distinction matters. What the
% listing fixes beyond doubt is WHICH COIL DRIVES WHICH DIRECTION OF WHICH
% NAMED CYLINDER - %Q3.6 is written only by pgm_cylA_Ext, and so on. That is
% the mapping this column grades, and it is settled.
%
% What is NOT settled is WHICH PHYSICAL BARREL cylinder "A" is. That is a
% different question, it lives in the Note column and in question 3b, and it
% is ONE ROW of FACTORY_ACTUATORS to change. Downgrading the Status for it
% would confuse an unknown about the machine's layout with an unknown about
% the mapping, and the mapping is what this table is.
 'Solenoid_valve7',        'u.sol(7)  CYL_A ext',  'CONFIRMED'  , '%Q3.6  written ONLY by pgm_cylA_Ext (FC3). Cylinder A extend coil. MODELLED as the c2_end -> engrave transfer; WHICH BARREL IS A is question 3b'
 'Solenoid_valve8',        'u.sol(8)  CYL_A ret',  'CONFIRMED'  , '%Q2.0  written ONLY by pgm_cylA_Ret. Cylinder A retract coil. MODELLED'
 'Solenoid_valve9',        'u.sol(9)  CYL_B ext',  'CONFIRMED'  , '%Q2.5  written ONLY by pgm_cylB_Ext. Cylinder B extend coil. ROLE: the ENGRAVED route, engraver -> belt 3 - recorded 2026-09-08, seen at the panel 2026-09-10, and the maintainer 2026-09-11: CYLINDER b FIRES WHEN ENGRAVING IS DONE AND IT PUSHES BLOCK TO BELT 3. (The owner reading of 2026-09-02, cylinder B as the no-engrave bypass, is superseded; the bypass is solenoid 11.) MODELLED as eng_out'
 'Solenoid_valve10',       'u.sol(10) CYL_B ret',  'CONFIRMED'  , '%Q2.4  written ONLY by pgm_cylB_Ret. Cylinder B retract coil. MODELLED and placed'
 'Solenoid_valve11',       'u.sol(11) MOVE_TO_CV3','CONFIRMED'  , '%Q2.3  FC6 N15, 2 s TP on Wp_move_cv3 with conveyor 3 on and conveyor 2 off. THE BYPASS: fires when engraving is SKIPPED (maintainer, 2026-09-11) and pushes the block from belt 2 straight onto belt 3. MODELLED on the c2_byp -> c3_byp stroke (belt 3''s start, 2026-09-12), commanded in states S40-S43 when P.engrave_selected is false'
 'Solenoid_valve12',       'u.sol(12) OUTFEED_A',  'PROVISIONAL', '%Q0.1  FC6 N16, 5 s TP after prox 9. What it physically moves is not stated. MODELLED as the eject-to-bin actuator'
 'Solenoid_valve13',       'u.sol(13) OUTFEED_B',  'PROVISIONAL', '%Q2.1  FC6 N16, 5 s TP after prox 10. Second outfeed lane. MODELLED pneumatically; POSITION NOT KNOWN, borrows its stroke from solenoid 12'
};

M = cell2table(raw, 'VariableNames', {'PlcShort','ModelSignal','Status','Note'});

% Every Pot_Control tag belongs to one of the three stepper axes. THE MODEL
% HAS NO STEPPER AXIS AT ALL - the engraving base is an electric axis driven to
% a position, and pot_1/2/3 are unrepresented (FactoryParams section 13C item
% 1, and HANDOFF "If you have no machine access"). This comment used to point
% at FACTORY_STEPPER_AXIS, which has never existed.
% Manual-command duplicates of the outputs are intentionally not listed: they
% are the same physical coil, commanded from the HMI instead of the sequencer.

if strcmpi(action, 'report')
    n = @(s) sum(strcmp(M.Status, s));
    fprintf('\n  PLC I/O MAPPING\n  %s\n', repmat('-', 1, 64));
    fprintf('  CONFIRMED   %3d   name fixes the mapping\n', n('CONFIRMED'));
    fprintf('  PROVISIONAL %3d   working assumption\n',     n('PROVISIONAL'));
    fprintf('  UNMAPPED    %3d   NOT KNOWN - needs someone at the machine\n', n('UNMAPPED'));
    fprintf('  %s\n  total %d rows\n\n', repmat('-', 1, 64), height(M));
    u = M(strcmp(M.Status,'UNMAPPED'), :);
    if ~isempty(u)
        fprintf('  Unmapped, grouped:\n');
        fprintf('    %d proximity sensors - walk the cell, note what each watches\n', ...
                sum(startsWith(u.PlcShort, 'Proximity')));
        fprintf('    %d solenoid valves   - jog each from the manual page, note what moves\n', ...
                sum(startsWith(u.PlcShort, 'Solenoid')));
        fprintf('\n  Both are an afternoon''s work and close the whole table.\n');
        fprintf('  See INPUTS_REQUIRED.md section 8.\n\n');
    end
    prov = M(strcmp(M.Status,'PROVISIONAL'), :);
    if ~isempty(prov)
        fprintf('  Provisional, and what each still needs:\n');
        for i = 1:height(prov)
            fprintf('    %-20s -> %s\n', prov.PlcShort{i}, prov.ModelSignal{i});
        end
        fprintf(['\n  The PLC program listing fixed the ROLE of every one of\n' ...
                 '  these. What is left is physical: where the sensor is bolted,\n' ...
                 '  and which barrel is which. See INPUTS_REQUIRED.md 3 and 4.\n\n']);
    end
end

if nargout == 0 && ~strcmpi(action,'table'); clear M; end
end
