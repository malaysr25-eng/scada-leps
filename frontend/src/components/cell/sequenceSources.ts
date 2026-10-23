/**
 * What each sequence step's guard is according to the MATLAB model, and where
 * that disagrees with what the backend is watching.
 *
 * TWO SOURCES DESCRIBE THE SAME FORTY STEPS
 *
 *   `Factory_Simulation/factory_states.m`  the simulation's state table. Its
 *       third column names the sensor that must go true, in the MACHINE'S OWN
 *       sensor numbering, which changed to ten sensors on 2026-09-02.
 *
 *   `backend/state/sequence.py`            the live tracker. It is what
 *       actually infers the step position from PLC edges, and it is the only
 *       thing on this screen that moves.
 *
 * They agree on thirty-seven of the forty steps. On three -- S10, S16 and S34 --
 * they name different sensors, and this file records that rather than picking a
 * winner:
 *
 *   step  factory_states.m   backend/state/sequence.py   corroboration
 *   S10   PX(6) conv 1       sensor.proximity.2          FC6 N3 gates conveyor
 *                                                        1 on %I1.5 = PX6
 *   S16   PX(8) conv 2       sensor.proximity.3          FC6 N5 pulses on
 *                                                        %I0.6 = PX8
 *   S34   PX(9) conv 3       sensor.proximity.4          FC6 N14 sets
 *                                                        STOP_CONV3 on
 *                                                        %I0.2 = PX9
 *
 * `initialize_factory.m` states the reason directly: sensors 1-5 are the five
 * magazine compartments' dispense confirms, and FC7 N2 gates each on
 * `workpiece_choice = N`, so in a single-compartment cycle exactly one of them
 * can ever fire. Watching proximity 2, 3 and 4 for conveyor position therefore
 * watches three sensors that stay low all cycle.
 *
 * WHY THE FRONTEND DOES NOT SIMPLY USE THE MATLAB BINDING
 *
 * Because the backend is out of implementation scope and it is the only thing
 * that actually advances the step index. Silently relabelling its guard would
 * put a sensor name on screen that is not the one being watched -- a worse lie
 * than the disagreement itself. So both are shown, side by side, marked.
 *
 * If the backend binding is later corrected, the `matlabRole` values here will
 * match `guardRole` from the snapshot and the conflict markers disappear on
 * their own.
 */

/** The guard column of `factory_states.m`, verbatim, keyed by state name. */
export const MATLAB_GUARD: Record<string, string> = {
  S00_INIT: 'immediate',
  S01_CAMERA_DETECT: 'CAM',
  S02_PUMP_CMD: 'immediate',
  S03_PRESSURE_PREP: 'P_READY',
  S04_DV_READY: 'immediate',
  S05_DV_SEL_FEEDER: 'BR_RDY(1) & CHG(feed)',
  S06_A1_EXTEND: 'EXT(feed)',
  S07_PROX1_CHECK: 'PX(1) mag 1',
  S08_A1_RETRACT: 'RET(feed)',
  S09_CONV1_START: 'immediate',
  S10_PROX2_CHECK: 'PX(6) conv 1',
  S11_CONV1_STOP: 'immediate',
  S12_DV_SEL_FEEDER2: 'BR_RDY(1) & CHG(xfer1)',
  S13_A6_EXTEND: 'EXT(xfer1)',
  S14_A6_RETRACT: 'RET(xfer1)',
  S15_CONV2_START: 'immediate',
  S16_PROX3_CHECK: 'PX(8) conv 2',
  S17_CONV2_STOP: 'immediate',
  S18_DV_SEL_SECOND: 'BR_RDY(2) & CHG(eng_in)',
  S19_S2A1_EXTEND: 'EXT(eng_in)',
  S20_S2A1_FEEDBACK: 'immediate',
  S21_S2A1_RETRACT: 'RET(eng_in)',
  S22_BASE_UP: 'immediate',
  S23_HEIGHT_TOP: 'HS_TOP',
  S24_OPERATOR_NOTIFY: 'timer (t_op_notice)',
  S25_ENGRAVE_MANUAL: 'timer (t_engrave)',
  S26_ENGRAVE_CONFIRM: 'timer (t_op_confirm)',
  S27_BASE_DOWN: 'immediate',
  S28_HEIGHT_BOTTOM: 'HS_BOT',
  S29_DV_SEL_THIRD: 'BR_RDY(3) & CHG(eng_out)',
  S30_S3A1_EXTEND: 'EXT(eng_out)',
  S31_S3A1_FEEDBACK: 'immediate',
  S32_S3A1_RETRACT: 'RET(eng_out)',
  S33_CONV3_START: 'immediate',
  S34_PROX4_FINAL: 'PX(9) conv 3',
  S35_CONV3_STOP: 'immediate',
  S36_DV_SEL_FOURTH: 'BR_RDY(4) & CHG(eject)',
  S37_S3A2_EXTEND: 'EXT(eject)',
  S38_S3A2_RETRACT: 'RET(eject)',
  S39_CYCLE_COMPLETE: 'terminal',
}

export interface GuardConflict {
  /** The sensor the MATLAB state table names. */
  matlabSensor: string
  /** Its backend role, so the live value can still be read for comparison. */
  matlabRole: string
  /** The PLC network that corroborates the MATLAB reading. */
  corroboration: string
  /** Why the backend's choice cannot fire in a normal cycle. */
  consequence: string
}

/**
 * The three steps where the two sources name different sensors. Keyed by state
 * name so a step whose backend binding is later corrected simply stops
 * matching -- see `hasConflict`.
 */
export const GUARD_CONFLICTS: Record<string, GuardConflict> = {
  S10_PROX2_CHECK: {
    matlabSensor: 'PX06',
    matlabRole: 'sensor.proximity.6',
    corroboration:
      'FC6 N3 / FC7 N4 gate the conveyor 1 clear on %I1.5, which factory_io_map.m ' +
      'maps to proximity sensor 6.',
    consequence:
      'Proximity 2 is magazine compartment 2\'s dispense confirm. FC7 N2 gates it ' +
      'on workpiece_choice = 2, so it cannot fire while the cell feeds from ' +
      'compartment 1.',
  },
  S16_PROX3_CHECK: {
    matlabSensor: 'PX08',
    matlabRole: 'sensor.proximity.8',
    corroboration:
      'FC6 N5 pulses Wp_move_cv3 for 400 ms on %I0.6, the end of conveyor 2, ' +
      'which factory_io_map.m maps to proximity sensor 8.',
    consequence:
      'Proximity 3 is magazine compartment 3\'s dispense confirm and cannot fire ' +
      'while the cell feeds from compartment 1.',
  },
  S34_PROX4_FINAL: {
    matlabSensor: 'PX09',
    matlabRole: 'sensor.proximity.9',
    corroboration:
      'FC6 N14 sets STOP_CONV3 on %I0.2, outfeed station A, which ' +
      'factory_io_map.m maps to proximity sensor 9.',
    consequence:
      'Proximity 4 is magazine compartment 4\'s dispense confirm and cannot fire ' +
      'while the cell feeds from compartment 1.',
  },
}

/**
 * True when the backend is still watching a different sensor from the one the
 * MATLAB state table names. Compares against the live catalogue's `guardRole`
 * so the marker clears itself if the backend binding is ever corrected.
 */
export function hasConflict(stepKey: string, guardRole: string | null): boolean {
  const c = GUARD_CONFLICTS[stepKey]
  return !!c && guardRole !== c.matlabRole
}

// ---------------------------------------------------------------------------
// step -> the thing on the plan view it acts on
// ---------------------------------------------------------------------------

export type PlanFocus =
  | { kind: 'sensor'; id: string }
  | { kind: 'actuator'; name: string }
  | { kind: 'conveyor'; index: 1 | 2 | 3 }
  | { kind: 'engraver' }
  | { kind: 'camera' }

/**
 * Which element of the plan view each step drives or reads. Derived from the
 * guard column above plus `factory_actuators.m`'s role map -- e.g. the four
 * `BR_RDY(n) & CHG(role)` guards each name an actuator role, and that role
 * resolves to one barrel.
 *
 * Steps with no element -- S00 and S39 -- are simply absent.
 */
export const STEP_FOCUS: Record<string, PlanFocus> = {
  S01_CAMERA_DETECT: { kind: 'camera' },
  S05_DV_SEL_FEEDER: { kind: 'actuator', name: 'MAG1_PUSH' },
  S06_A1_EXTEND: { kind: 'actuator', name: 'MAG1_PUSH' },
  S07_PROX1_CHECK: { kind: 'sensor', id: 'PX01' },
  S08_A1_RETRACT: { kind: 'actuator', name: 'MAG1_PUSH' },
  S09_CONV1_START: { kind: 'conveyor', index: 1 },
  S10_PROX2_CHECK: { kind: 'sensor', id: 'PX06' },
  S11_CONV1_STOP: { kind: 'conveyor', index: 1 },
  S12_DV_SEL_FEEDER2: { kind: 'actuator', name: 'XFER_CV1_CV2' },
  S13_A6_EXTEND: { kind: 'actuator', name: 'XFER_CV1_CV2' },
  S14_A6_RETRACT: { kind: 'actuator', name: 'XFER_CV1_CV2' },
  S15_CONV2_START: { kind: 'conveyor', index: 2 },
  S16_PROX3_CHECK: { kind: 'sensor', id: 'PX08' },
  S17_CONV2_STOP: { kind: 'conveyor', index: 2 },
  S18_DV_SEL_SECOND: { kind: 'actuator', name: 'CYL_A' },
  S19_S2A1_EXTEND: { kind: 'actuator', name: 'CYL_A' },
  S20_S2A1_FEEDBACK: { kind: 'actuator', name: 'CYL_A' },
  S21_S2A1_RETRACT: { kind: 'actuator', name: 'CYL_A' },
  S22_BASE_UP: { kind: 'engraver' },
  S23_HEIGHT_TOP: { kind: 'engraver' },
  S24_OPERATOR_NOTIFY: { kind: 'engraver' },
  S25_ENGRAVE_MANUAL: { kind: 'engraver' },
  S26_ENGRAVE_CONFIRM: { kind: 'engraver' },
  S27_BASE_DOWN: { kind: 'engraver' },
  S28_HEIGHT_BOTTOM: { kind: 'engraver' },
  S29_DV_SEL_THIRD: { kind: 'actuator', name: 'MOVE_TO_CV3' },
  S30_S3A1_EXTEND: { kind: 'actuator', name: 'MOVE_TO_CV3' },
  S31_S3A1_FEEDBACK: { kind: 'actuator', name: 'MOVE_TO_CV3' },
  S32_S3A1_RETRACT: { kind: 'actuator', name: 'MOVE_TO_CV3' },
  S33_CONV3_START: { kind: 'conveyor', index: 3 },
  S34_PROX4_FINAL: { kind: 'sensor', id: 'PX09' },
  S35_CONV3_STOP: { kind: 'conveyor', index: 3 },
  S36_DV_SEL_FOURTH: { kind: 'actuator', name: 'OUTFEED_A' },
  S37_S3A2_EXTEND: { kind: 'actuator', name: 'OUTFEED_A' },
  S38_S3A2_RETRACT: { kind: 'actuator', name: 'OUTFEED_A' },
}

/** A short human label for what a focus points at, for tooltips and captions. */
export function focusLabel(focus: PlanFocus | undefined): string | null {
  if (!focus) return null
  switch (focus.kind) {
    case 'sensor':
      return focus.id
    case 'actuator':
      return focus.name.replace(/_/g, ' ')
    case 'conveyor':
      return `Conveyor ${focus.index}`
    case 'engraver':
      return 'Engraver'
    case 'camera':
      return 'Camera'
  }
}

/**
 * The four distribution branches, and what they are not.
 *
 * `factory_actuators.m` is explicit: the branches are a SEQUENCE.XLSX construct.
 * The machine has one FRL and a manifold, and the PLC listing shows no
 * distribution-valve coil at all. So a branch number says which of the model's
 * four supply groups feeds an actuator -- it is not a thing the HMI can read.
 */
export const BRANCH_NOTE =
  'The four distribution branches are a Sequence.xlsx construct. The machine ' +
  'has one FRL and a manifold, and the PLC listing contains no ' +
  'distribution-valve coil, so no branch pressure can be read. The nine ' +
  '"branch ready + charged" guards below are unobservable for that reason.'
