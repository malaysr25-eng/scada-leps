/**
 * The cell's eleven pneumatic actuators and thirteen solenoid coils.
 *
 * Transcribed from `Factory_Simulation/factory_actuators.m`, which is the one
 * definition the MATLAB plant, sequencer, sensor bus and Simulink builder all
 * read. Coil numbers, valve types and roles come from the machine's own TIA
 * Portal listing (`plc/abc.pdf`, FC3 `solenoid_manual` writes every coil, FC8
 * `Fc_IO` mirrors them); `factory_io_map.m` carries the address-by-address map.
 *
 * WHY THE FRONTEND NEEDS THIS AT ALL
 *
 * The backend snapshot presents thirteen flat entries -- "Solenoid Valve 1" to
 * "Solenoid Valve 13" -- because thirteen coil tags is exactly what
 * `Tag_list (1).xlsx` contains. That is the correct thing for the backend to
 * publish and the wrong thing for an operator to read. Thirteen coils are
 * eleven actuators: coils 7/8 are one double-solenoid cylinder and so are
 * coils 9/10. Showing SV7 and SV8 as unrelated tiles hides the fact that they
 * are the two ends of one spool.
 *
 * So this file groups the coils, and nothing more. Every live value still comes
 * from the snapshot; nothing here holds state.
 *
 * THE TWO VALVE TYPES, AND WHY THE DIFFERENCE MATTERS ON SCREEN
 *
 * A SPRING-RETURN valve follows its single coil: energised the spool goes to 1,
 * de-energised the spring returns it. A DOUBLE-SOLENOID valve is a LATCH -- the
 * extend coil drives the spool to 1, the retract coil drives it to 0, and with
 * BOTH COILS OFF THE SPOOL HOLDS WHERE IT IS. That is why FC6 networks 4, 7 and
 * 15 can PULSE those coils for T#2S and release. It is also why "both coils
 * off" must never be drawn as "retracted" for CYL_A or CYL_B: the spool is
 * wherever it was last driven, and no tag reports which.
 *
 * WHAT THIS FILE CANNOT TELL YOU
 *
 * Rod position. There is no reed-switch or end-of-stroke address for any of the
 * eleven actuators anywhere in the tag list -- the backend says so on every
 * actuator it publishes (`feedbackNote`). The stroke geometry below is real and
 * sourced; the rod's position within it is not measured and is never drawn as
 * if it were.
 */

import { CELL_PALETTE, WAYPOINT, type Provenance, type WaypointId } from './cellGeometry'

// ---------------------------------------------------------------------------
// dimensions -- FactoryParams.m and draw_cell_layout.m
// ---------------------------------------------------------------------------

const BLK_L = 0.1 // P.blk_L, workpiece length, m
const BLK_W = 0.1 // P.blk_W, workpiece width, m
const GAP_APP = 0.005 // P.gap_app, approach gap between rod tip and face, m
const BODY_LEN = 0.12 // draw_cell_layout `bl`, body length along the axis, m
const BODY_WID = 0.08 // draw_cell_layout `bw`, body width across it, m
const MAG_PITCH = 0.11 // P.mag_pitch, magazine slot pitch, m
const MAG_CHOICE = 1 // P.mag_choice, the compartment the model feeds from

// ---------------------------------------------------------------------------
// the table
// ---------------------------------------------------------------------------

export type ValveKind = 'spring' | 'double'

interface ActuatorDef {
  name: string
  /** The name Sequence.xlsx uses; empty when the sequence never mentions it. */
  alias: string
  /** What the sequencer asks for. Resolved through `P.ACT` in MATLAB. */
  role: string
  kind: ValveKind
  /** Coil driving the spool to 1. */
  coilExtend: number
  /** Coil driving it back to 0; 0 for a spring-return valve. */
  coilRetract: number
  /** Distribution-valve branch 1-4 that feeds it. */
  branch: 1 | 2 | 3 | 4
  axis: 'x' | 'y'
  dir: 1 | -1
  from: WaypointId
  /** Absent when the actuator has a position but no known path. */
  to: WaypointId | null
  /** Magazine compartment number, 0 if not a pusher. */
  mag: number
  /** Sequence.xlsx step reference, '-' when it has none. */
  excel: string
  /** Compact label. Lives in factory_actuators.m so drawings cannot invent one. */
  short: string
  /**
   * False when the rod is barred from touching the workpiece. Today that is
   * CYL_B alone: a real cylinder belonging to the engraving machine whose path
   * this single-axis plan cannot express.
   */
  contact: boolean
  /**
   * A DRAWING separation, in metres, applied to the body and its label only.
   *
   * CYL_B and MOVE_TO_CV3 both stand at the `engrave` waypoint, on the same
   * axis, pushing the same way -- so `initialize_factory.m` resolves them to
   * the *identical* rectangle and the MATLAB figure prints their two labels on
   * top of each other. Drawing them coincident here would hide one actuator
   * behind another.
   *
   * So one of them is nudged, and the nudge is declared rather than baked into
   * a coordinate: the offset never touches `geometry`, a leader line is drawn
   * back to the real position, and the tooltip says so. CYL_B is the one moved
   * because it claims no stroke, so nothing geometric depends on where it sits.
   */
  drawOffset: readonly [number, number]
  note: string
}

const DEFS: ActuatorDef[] = [
  ...[1, 2, 3, 4, 5].map((n): ActuatorDef => ({
    name: `MAG${n}_PUSH`,
    alias: n === MAG_CHOICE ? 'A1' : '',
    role: 'mag_push',
    kind: 'spring',
    coilExtend: n,
    coilRetract: 0,
    branch: 1,
    axis: 'y',
    dir: -1,
    from: 'feed',
    to: 'c1_load',
    mag: n,
    excel: n === MAG_CHOICE ? '7-8' : '-',
    short: `MAG${n}`,
    contact: true,
    drawOffset: [0, 0],
    note:
      n === MAG_CHOICE
        ? 'The compartment the model feeds from, so Sequence.xlsx\'s "A1" is ' +
          'this pusher. One pusher fires per cycle on the real machine too.'
        : 'Modelled and on the air bus, but Sequence.xlsx never commands it: ' +
          'exactly one magazine pusher fires per cycle.',
  })),
  {
    name: 'XFER_CV1_CV2', alias: 'A6', role: 'xfer1', kind: 'spring',
    coilExtend: 6, coilRetract: 0, branch: 1,
    axis: 'y', dir: -1, from: 'c1_end', to: 'c2_load', mag: 0,
    excel: '15-16', short: 'XFER 1>2', contact: true, drawOffset: [0, 0],
    note: 'Transfers the block from the end of conveyor 1 onto conveyor 2.',
  },
  {
    name: 'CYL_A', alias: 'S2A1', role: 'eng_in', kind: 'double',
    coilExtend: 7, coilRetract: 8, branch: 2,
    axis: 'x', dir: 1, from: 'c2_end', to: 'engrave', mag: 0,
    excel: '22-23', short: 'CYL A', contact: true, drawOffset: [0, 0],
    note:
      'Double-solenoid: coil 7 extends, coil 8 retracts, and with both off the ' +
      'spool holds. Pushes the block from the foot of conveyor 2 onto the ' +
      'engraving base.',
  },
  {
    name: 'CYL_B', alias: '', role: 'bypass', kind: 'double',
    coilExtend: 9, coilRetract: 10, branch: 3,
    axis: 'y', dir: -1, from: 'engrave', to: null, mag: 0,
    excel: '-', short: 'CYL B', contact: false, drawOffset: [0.115, 0.075],
    note:
      'Belongs to the ENGRAVING MACHINE, corrected by the machine owner on ' +
      '2026-09-02: "cylinder B is energised when engraving is NOT to be done ' +
      '(50 mm is selected on the interface)", coil 9 out and coil 10 back. ' +
      'What it moves and how far is not stated, so it claims no stroke and its ' +
      'rod may not touch the workpiece. Nothing in the model commands it.',
  },
  {
    name: 'MOVE_TO_CV3', alias: 'S3A1', role: 'eng_out', kind: 'spring',
    coilExtend: 11, coilRetract: 0, branch: 3,
    axis: 'y', dir: -1, from: 'engrave', to: 'c3_load', mag: 0,
    excel: '33-34', short: 'MOVE>CV3', contact: true, drawOffset: [0, 0],
    note:
      'FC6 N15 fires it on `Wp_move_cv3` with conveyor 3 on and conveyor 2 ' +
      'off. It stands at the same waypoint as CYL_B, which is why their labels ' +
      'collide on the MATLAB figure.',
  },
  {
    name: 'OUTFEED_A', alias: 'S3A2', role: 'eject', kind: 'spring',
    coilExtend: 12, coilRetract: 0, branch: 4,
    axis: 'y', dir: -1, from: 'c3_end', to: 'bin', mag: 0,
    excel: '41-42', short: 'OUT A', contact: true, drawOffset: [0, 0],
    note: 'FC6 N16: proximity 9 runs a 5 s TP onto this coil.',
  },
  {
    name: 'OUTFEED_B', alias: '', role: 'outfeed_b', kind: 'spring',
    coilExtend: 13, coilRetract: 0, branch: 4,
    axis: 'y', dir: -1, from: 'c3_out_b', to: 'bin_b', mag: 0,
    excel: '-', short: 'OUT B', contact: true, drawOffset: [0, 0],
    note:
      'The other half of the symmetric FC6 N16: proximity 10 runs a 5 s TP ' +
      'onto coil 13. Sequence.xlsx never commands it. Placed at its own sensor ' +
      'by that symmetry, [ASM].',
  },
]

// ---------------------------------------------------------------------------
// resolved geometry
// ---------------------------------------------------------------------------

export interface ActuatorGeometry {
  /** Body rectangle: left edge, BOTTOM edge (model coords), width, height. */
  body: { x: number; y: number; w: number; h: number }
  /** Rod tip when fully retracted, along the stroke axis. */
  tip0: number
  /** Lateral coordinate of the rod centreline, across the stroke axis. */
  lat: number
  /**
   * Transport distance along the axis, metres. Null when the actuator has a
   * position but no known path -- CYL_B, whose stroke is BORROWED from CYL_A in
   * the model purely so its chamber has a volume.
   */
  travel: number | null
}

export interface Actuator extends ActuatorDef {
  geometry: ActuatorGeometry
  /** Every coil this actuator owns, in extend-then-retract order. */
  coils: number[]
  strokeProvenance: Provenance
}

function resolve(def: ActuatorDef): ActuatorGeometry {
  // MATLAB's k: 1 for an x-axis cylinder, 2 for a y-axis one. Here as an index.
  const axisIdx = def.axis === 'x' ? 0 : 1
  const latIdx = 1 - axisIdx
  const p0 = WAYPOINT[def.from][axisIdx]

  const magOffset = def.mag === 0 ? 0 : (def.mag - MAG_CHOICE) * MAG_PITCH
  const lat = WAYPOINT[def.from][latIdx] + magOffset

  // initialize_factory.m: the rod tip sits one approach gap off the workpiece
  // face, and the face is half a block from the waypoint centre.
  const blkAx = def.axis === 'x' ? BLK_L : BLK_W
  const face0 = p0 - def.dir * (blkAx / 2)
  const tip0 = face0 - def.dir * GAP_APP

  const travel =
    def.to === null ? null : Math.abs(WAYPOINT[def.to][axisIdx] - p0)

  // draw_cell_layout.m: the body sits BEHIND the retracted tip, on the axis.
  const back = Math.min(tip0, tip0 - def.dir * BODY_LEN)
  const body =
    def.axis === 'x'
      ? { x: back, y: lat - BODY_WID / 2, w: BODY_LEN, h: BODY_WID }
      : { x: lat - BODY_WID / 2, y: back, w: BODY_WID, h: BODY_LEN }

  return { body, tip0, lat, travel }
}

export const ACTUATORS: Actuator[] = DEFS.map((def) => ({
  ...def,
  geometry: resolve(def),
  coils: def.coilRetract > 0 ? [def.coilExtend, def.coilRetract] : [def.coilExtend],
  // A row derives its own stroke exactly when it gives both waypoints;
  // anything else borrows one, which factory_actuators.m marks [ASM].
  strokeProvenance: def.to === null ? 'ASM' : 'CAL',
}))

/** Coil number (1-13) to the actuator it drives and which way it drives it. */
export const COIL_MAP: Record<
  number,
  { actuator: Actuator; direction: 'extend' | 'retract' }
> = (() => {
  const map: Record<number, { actuator: Actuator; direction: 'extend' | 'retract' }> = {}
  for (const a of ACTUATORS) {
    map[a.coilExtend] = { actuator: a, direction: 'extend' }
    if (a.coilRetract > 0) map[a.coilRetract] = { actuator: a, direction: 'retract' }
  }
  return map
})()

export const ACTUATOR_BY_NAME: Record<string, Actuator> = Object.fromEntries(
  ACTUATORS.map((a) => [a.name, a]),
)

/** Edge colour for an actuator body, matching the MATLAB figure's convention. */
export function actuatorEdge(a: Actuator): string {
  return a.kind === 'double' ? CELL_PALETTE.actuatorDouble : '#ffffff'
}

/**
 * The valve label the MATLAB figure prints: `SHORT [ext]` or `SHORT [ext/ret]`.
 * Generated from the table for the same reason MATLAB generates it -- so a
 * drawing cannot invent a naming scheme of its own.
 */
export function actuatorLabel(a: Actuator): string {
  return a.coilRetract > 0
    ? `${a.short} [${a.coilExtend}/${a.coilRetract}]`
    : `${a.short} [${a.coilExtend}]`
}

/** The sentence the UI shows wherever rod position would otherwise be implied. */
export const NO_ROD_FEEDBACK =
  'No reed-switch or end-of-stroke tag exists for any of the eleven actuators, ' +
  'so rod position is never known. The coil state is the furthest the ' +
  'available tags reach.'
