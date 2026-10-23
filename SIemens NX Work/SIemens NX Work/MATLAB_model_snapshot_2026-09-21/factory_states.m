function ST = factory_states()
%FACTORY_STATES  The PLC / Stateflow state table.
%
%   ST = FACTORY_STATES() returns an N x 3 cell array:
%       {name, excel_ref, transition guard}
%
%   excel_ref is the row number in Sequence.xlsx that the state implements.
%     '5,6'  the state implements two consecutive Excel rows
%     '8i'   IMPLICIT - not an Excel row. Sequence.xlsx never commands any
%            actuator to retract, but a rod left extended physically blocks
%            the next transport. These six states are engineering additions
%            and are flagged as such wherever they appear.
%     '36*'  Excel ANOMALY. Row 36 reads "Conveyor Stop" immediately after
%            the workpiece is placed on the station 3 belt, and row 38 reads
%            "Conveyor Stop" again after the row 37 position check. The
%            established pattern in rows 10-12 and 17-19 is
%            Start -> proximity check -> Stop. Row 36 is implemented as
%            Conveyor START. The Excel text is NOT silently overwritten -
%            the anomaly is recorded here, in the development log, and in
%            the sequence mapping table.
%
%   The guard column names the sensor that must go TRUE for the state to
%   advance. Actuator guards are written by ROLE - feed, xfer1, eng_in,
%   eng_out, eject - because the actuator numbering became the machine's
%   eleven on 2026-09-02 and 'EXT(2)' now means the second magazine pusher.
%   The roles resolve through P.ACT; see FACTORY_ACTUATORS.
% Guards marked 'timer' are the ONLY time-based transitions in
%   the model, and every one of them corresponds to a manual operator action
%   for which Sequence.xlsx supplies no duration.
%
%   TWO ROUTES, 2026-09-11. S00-S39 are the ENGRAVED route, the one
%   Sequence.xlsx describes. S40-S43 are the BYPASS, which Sequence.xlsx never
%   mentions - the maintainer: "SV11 FIRES WHEN ENGRAVING IS SKIPPED". It
%   leaves the engraved route at S16, when prox 8 sees the block and
%   P.engrave_selected is false, and rejoins it at S33 once SV11 has put the
%   block on belt 3. The four are APPENDED, not inserted, so every engraved-
%   route index - which the logs, COMPARE_TO_RECORDING and the Python port all
%   compare - is unchanged. Their excel_ref names the FC6 NETWORK ('N5',
%   'N15') because there is no Excel row to name.

ST = { ...
 'S00_INIT',            '-',      'immediate'
 'S01_CAMERA_DETECT',   '1',      'CAM'
 'S02_PUMP_CMD',        '2',      'immediate'
 'S03_PRESSURE_PREP',   '3',      'P_READY & T#10S'
 'S04_DV_READY',        '4',      'immediate'
 'S05_DV_SEL_FEEDER',   '5,6',    'BR_RDY(1) & CHG(feed)'
 'S06_A1_EXTEND',       '7,8',    'EXT(feed)'
 'S07_PROX1_CHECK',     '9',      'PX(1) mag 1'
 'S08_A1_RETRACT',      '8i',     'RET(feed)'
 'S09_CONV1_START',     '10',     'immediate'
 'S10_PROX2_CHECK',     '11',     'PX(6) conv 1'
 'S11_CONV1_STOP',      '12',     'immediate'
 'S12_DV_SEL_FEEDER2',  '13,14',  'BR_RDY(1) & CHG(xfer1)'
 'S13_A6_EXTEND',       '15,16',  'EXT(xfer1)'
 'S14_A6_RETRACT',      '16i',    'RET(xfer1)'
 'S15_CONV2_START',     '17',     'immediate'
 'S16_PROX3_CHECK',     '18',     'PX(7) conv 2 | bypass: PX(8)'
 'S17_CONV2_STOP',      '19',     'immediate'
 'S18_DV_SEL_SECOND',   '20,21',  'BR_RDY(2) & CHG(eng_in) & wait'
 'S19_S2A1_EXTEND',     '22,23',  'EXT(eng_in)'
 'S20_S2A1_FEEDBACK',   '24',     'immediate'
 'S21_S2A1_RETRACT',    '24i',    'RET(eng_in)'
 'S22_BASE_UP',         '25',     'immediate'
 'S23_HEIGHT_TOP',      '26',     'HS_TOP'
 'S24_OPERATOR_NOTIFY', '27',     'timer (t_op_notice)'
 'S25_ENGRAVE_MANUAL',  '28',     'timer (t_engrave)'
 'S26_ENGRAVE_CONFIRM', '29',     'timer (t_op_confirm)'
 'S27_BASE_DOWN',       '30i',    'immediate'
 'S28_HEIGHT_BOTTOM',   '30',     'HS_BOT'
 'S29_DV_SEL_THIRD',    '31,32',  'BR_RDY(3) & CHG(eng_out)'
 'S30_S3A1_EXTEND',     '33,34',  'EXT(eng_out)'
 'S31_S3A1_FEEDBACK',   '35',     'immediate'
 'S32_S3A1_RETRACT',    '35i',    'RET(eng_out)'
 'S33_CONV3_START',     '36*',    'immediate'
 'S34_PROX4_FINAL',     '37',     'PX(9) conv 3'
 'S35_CONV3_STOP',      '38',     'immediate'
 'S36_DV_SEL_FOURTH',   '39,40',  'BR_RDY(4) & CHG(eject)'
 'S37_S3A2_EXTEND',     '41,42',  'EXT(eject)'
 'S38_S3A2_RETRACT',    '42i',    'RET(eject)'
 'S39_CYCLE_COMPLETE',  '-',      'terminal'
 'S40_BYP_CONV2_STOP',  'N5',     'immediate'
 'S41_BYP_DV_SEL',      'N15',    'BR_RDY(3) & CHG(bypass)'
 'S42_BYP_SV11_EXTEND', 'N15',    'EXT(bypass)'
 'S43_BYP_SV11_RETRACT','N15i',   'RET(bypass) -> S33'
};
end
