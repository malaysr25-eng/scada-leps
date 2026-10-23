/**
 * The cell's real geometry, in metres.
 *
 * WHERE EVERY NUMBER COMES FROM
 * -----------------------------
 * This file is a transcription, not a design. Every coordinate below is read
 * out of the MATLAB model that drives the simulation:
 *
 *   Factory_Simulation/initialize_factory.m   waypoints, sensor placement
 *   Factory_Simulation/draw_cell_layout.m     conveyor/engraver/bin rectangles
 *   Factory_Simulation/FactoryParams.m        P.SCALE = 0.10 m per drawing unit
 *
 * The MATLAB sources hold the layout in DRAWING UNITS and convert with
 * `P.SCALE`. That conversion is done once, here, so the frontend carries
 * metres and nothing downstream has to remember the factor. `initialize_factory`
 * records the scale as confirmed on 2026-08-25: conveyor 1 measures 760 mm over
 * 7.6 drawing units.
 *
 * WHY THIS REPLACED THE OLD `digitalTwin/layout.ts`
 *
 * That file drew three parallel left-to-right belts on an undimensioned
 * 1000x460 canvas and put PX05-PX10 plus all thirteen valves in an "unassigned"
 * tray, on the stated grounds that "no source ties this sensor to a station".
 * That was true of `Tag_list (1).xlsx` read on its own. It is not true of this
 * project: `initialize_factory.m` places all ten proximity sensors and all
 * eleven actuators, in metres, each with its own provenance. The cell is
 * T-shaped, not three parallel belts, and it is 1.72 x 1.20 m.
 *
 * So the schematic is now TO SCALE and the tray is gone.
 *
 * PROVENANCE CODES, as the MATLAB sources use them:
 *   SRC  stated by a source document (Sequence.xlsx row, PLC listing)
 *   REF  from the original reference layout script
 *   CAL  calculated from other sourced geometry
 *   CAD  a measured mechanical dimension
 *   ADD  required by the process, absent from the reference script
 *   ASM  assumed; the role is known, the position is not
 *
 * Nothing here is invented. Where a position is unknown it is either derived
 * and marked ASM exactly as the model marks it, or it is absent -- see
 * PLATE_LIMITS, which have no x-y position at all because the plan view has no
 * vertical axis.
 */

/** Drawing units to metres. FactoryParams.m: `P.SCALE = 0.10`. */
export const SCALE = 0.1

// ---------------------------------------------------------------------------
// world -> SVG
// ---------------------------------------------------------------------------

/**
 * The drawn frame, in metres, with a small margin around the station bounds.
 * Station 1's boundary is the leftmost and topmost thing on the plan; station
 * 3's is the rightmost; conveyor 2's foot is the lowest.
 */
const FRAME = { xMin: -0.14, xMax: 1.7, yMin: 0.03, yMax: 1.26 }

/** 1000 SVG units per metre, i.e. one unit is a millimetre. */
const UNITS_PER_M = 1000

export const VIEW = {
  w: Math.round((FRAME.xMax - FRAME.xMin) * UNITS_PER_M),
  h: Math.round((FRAME.yMax - FRAME.yMin) * UNITS_PER_M),
}

/** Metres (model X) to SVG X. */
export const mx = (x: number) => (x - FRAME.xMin) * UNITS_PER_M

/** Metres (model Y) to SVG Y. SVG Y grows downward; the model's grows up. */
export const my = (y: number) => (FRAME.yMax - y) * UNITS_PER_M

/** A length in metres to SVG units. */
export const mlen = (d: number) => d * UNITS_PER_M

// ---------------------------------------------------------------------------
// waypoints -- initialize_factory.m section 1
// ---------------------------------------------------------------------------

export type WaypointId =
  | 'feed' | 'c1_load' | 'c1_end' | 'c2_load' | 'c2_end' | 'engrave'
  | 'c3_load' | 'c3_end' | 'bin' | 'c3_out_b' | 'bin_b' | 'c3_byp'

export type Provenance = 'SRC' | 'REF' | 'CAL' | 'CAD' | 'ADD' | 'ASM'

/**
 * Workpiece waypoints -- block CENTRE coordinates, metres.
 * Drawing-unit values and their provenance tags are `initialize_factory.m`'s
 * own, converted here by SCALE.
 */
export const WAYPOINT: Record<WaypointId, readonly [number, number]> = {
  feed:     [0.16,   1.0    ], // [REF] feeder, above conveyor 1
  c1_load:  [0.16,   0.9175 ], // [CAL] conveyor 1 centreline
  c1_end:   [0.7925, 0.9175 ], // [CAL] aligned to conveyor 2 centre
  c2_load:  [0.7925, 0.81   ], // [CAL] entry onto conveyor 2
  c2_end:   [0.7925, 0.59   ], // [REF] aligned to St.2 Actuator 1 axis
  engrave:  [1.045,  0.59   ], // [CAL] laser engraver centre
  c3_load:  [1.045,  0.3865 ], // [CAL] station 3 belt centreline
  c3_end:   [1.51,   0.3865 ], // [REF] aligned to eject actuator axis
  bin:      [1.51,   0.2    ], // [ADD] collection bin, Sequence.xlsx row 42
  c3_out_b: [1.324,  0.3865 ], // [ASM] second outfeed station, 60 % of the run
  bin_b:    [1.324,  0.2    ], // [ASM] where outfeed B pushes to
  c3_byp:   [0.7925, 0.3865 ], // [ASM] where CYL_B's bypass would land
}

// ---------------------------------------------------------------------------
// surfaces -- draw_cell_layout.m
// ---------------------------------------------------------------------------

export interface CellRect {
  id: string
  label: string
  /** Left edge, metres. */
  x: number
  /** BOTTOM edge in model coordinates, metres. */
  y: number
  w: number
  h: number
  provenance: Provenance
  source: string
}

export interface BeltSurface extends CellRect {
  /** Conveyor number as the PLC and the backend number them. */
  index: 1 | 2 | 3
  /** Travel direction of the belt surface, model coordinates. */
  flow: readonly [number, number]
  caption: string
}

/**
 * The three conveyors. `flow` is `P.REG(i).uv` from initialize_factory section
 * 3; `P.CONV_REG = [4 3 1]` is what maps conveyor 1/2/3 onto those regions.
 * Conveyor 2 runs DOWNWARD -- the cell is a T, not a row of parallel belts.
 */
export const BELTS: BeltSurface[] = [
  {
    index: 1, id: 'conv1', label: 'Conveyor 1',
    x: 0.1, y: 0.85, w: 0.76, h: 0.135,
    flow: [1, 0], caption: '> > >  CONVEYOR 1  > > >',
    provenance: 'REF',
    source: 'draw_cell_layout.m: rectangle [1 8.5 7.6 1.35] drawing units.',
  },
  {
    index: 2, id: 'conv2', label: 'Conveyor 2',
    x: 0.725, y: 0.09, w: 0.135, h: 0.76,
    flow: [0, -1], caption: 'v  CONVEYOR 2  v',
    provenance: 'REF',
    source: 'draw_cell_layout.m: rectangle [7.25 0.9 1.35 7.6] drawing units.',
  },
  {
    index: 3, id: 'conv3', label: 'Station 3 belt',
    x: 0.86, y: 0.319, w: 0.76, h: 0.135,
    flow: [1, 0], caption: '> > >  STATION 3 BELT  > > >',
    provenance: 'REF',
    source: 'draw_cell_layout.m: rectangle [8.6 3.19 7.6 1.35] drawing units.',
  },
]

export const ENGRAVER: CellRect = {
  id: 'engraver', label: 'Laser engraver',
  x: 0.86, y: 0.43, w: 0.37, h: 0.265,
  provenance: 'REF',
  source: 'draw_cell_layout.m: rectangle [8.6 4.3 3.7 2.65] drawing units.',
}

export const BIN: CellRect = {
  id: 'bin', label: 'Bin',
  x: 1.43, y: 0.1, w: 0.16, h: 0.219,
  provenance: 'ADD',
  source:
    'draw_cell_layout.m: [14.3 1.0 1.6 2.19]. Required by Sequence.xlsx step ' +
    '42 and absent from the reference script, hence [ADD].',
}

export const STATION_BOUNDS: CellRect[] = [
  {
    id: 'st1', label: 'Station 1',
    x: -0.08, y: 0.82, w: 1.0, h: 0.38,
    provenance: 'REF',
    source: 'draw_cell_layout.m: [-0.8 8.2 10 3.8] drawing units.',
  },
  {
    id: 'st2', label: 'Station 2',
    x: 0.5, y: 0.15, w: 0.4, h: 0.65,
    provenance: 'REF',
    source: 'draw_cell_layout.m: [5 1.5 4 6.5] drawing units.',
  },
  {
    id: 'st3', label: 'Station 3',
    x: 0.92, y: 0.15, w: 0.72, h: 0.85,
    provenance: 'REF',
    source: 'draw_cell_layout.m: [9.2 1.5 7.2 8.5] drawing units.',
  },
]

// ---------------------------------------------------------------------------
// sensors -- initialize_factory.m section 5
// ---------------------------------------------------------------------------

export interface SensorPlacement {
  /** 'PX01' .. 'PX10', the label draw_cell_layout puts on the figure. */
  id: string
  /** The machine's own sensor number. */
  n: number
  /** Backend snapshot role -- how the live value is looked up. */
  role: string
  /** Full name from `P.PROX_NAME`. */
  name: string
  x: number
  y: number
  /**
   * True when the sequencer gates on this sensor: `P.PROX_GUARD = [1 6 8 9]`.
   * draw_cell_layout fills these four and leaves the other six hollow, so the
   * plan distinguishes "stops the cycle" from "modelled and logged only".
   */
  guarded: boolean
  /** What the sensor does, from the PLC program (FC6/FC7). */
  duty: string
  /** Provenance of the POSITION, which is a separate question from the duty. */
  provenance: Provenance
  positionNote: string
}

const MAG_PITCH = 0.11 // [CAD] Magazine.STEP, initialize_factory P.mag_pitch
const MAG_CHOICE = 1 // [ASM] the compartment the model feeds from

const magRow = (i: number): readonly [number, number] => [
  WAYPOINT.c1_load[0] + (i - MAG_CHOICE) * MAG_PITCH,
  WAYPOINT.c1_load[1],
]

const c2Mid: readonly [number, number] = [
  (WAYPOINT.c2_load[0] + WAYPOINT.c2_end[0]) / 2,
  (WAYPOINT.c2_load[1] + WAYPOINT.c2_end[1]) / 2,
]

const MAG_DUTY =
  'Magazine compartment %d dispense confirm. FC7 N2 gates each of the five on ' +
  'workpiece_choice = N, so only the selected compartment can fire.'

export const SENSORS: SensorPlacement[] = [
  ...[1, 2, 3, 4, 5].map((n): SensorPlacement => {
    const [x, y] = magRow(n)
    return {
      id: `PX0${n}`,
      n,
      role: `sensor.proximity.${n}`,
      name: `PX0${n}_mag${n}_dispense`,
      x,
      y,
      guarded: n === MAG_CHOICE,
      duty: MAG_DUTY.replace('%d', String(n)),
      provenance: n === MAG_CHOICE ? 'CAL' : 'ASM',
      positionNote:
        n === MAG_CHOICE
          ? 'Compartment 1 is the model feed point, so PX01 sits on the ' +
            'c1_load waypoint. initialize_factory.m section 5.'
          : `Compartment ${n} is one magazine pitch (110 mm) from its ` +
            'neighbour. The role is known from FC7 N2; the position along the ' +
            'belt is the model working assumption, [ASM].',
    }
  }),
  {
    id: 'PX06', n: 6, role: 'sensor.proximity.6', name: 'PX06_conv1',
    x: WAYPOINT.c1_end[0], y: WAYPOINT.c1_end[1], guarded: true,
    duty: 'Conveyor 1. FC6 N3 / FC7 N4, clears the magazine push.',
    provenance: 'SRC',
    positionNote: 'End of conveyor 1 (c1_end). Sequence.xlsx step 11.',
  },
  {
    id: 'PX07', n: 7, role: 'sensor.proximity.7', name: 'PX07_conv2_mid',
    x: c2Mid[0], y: c2Mid[1], guarded: false,
    duty: 'Conveyor 2 mid. FC7 N5, the network is titled "WP IN CV2 MID".',
    provenance: 'ASM',
    positionNote:
      'Taken as the midpoint of conveyor 2. The role is known; the position ' +
      'along the belt is not recorded anywhere, [ASM].',
  },
  {
    id: 'PX08', n: 8, role: 'sensor.proximity.8', name: 'PX08_conv2_end',
    x: WAYPOINT.c2_end[0], y: WAYPOINT.c2_end[1], guarded: true,
    duty: 'Conveyor 2 end. FC6 N5, a 400 ms pulse to Wp_move_cv3.',
    provenance: 'SRC',
    positionNote: 'End of conveyor 2 (c2_end). Sequence.xlsx step 18.',
  },
  {
    id: 'PX09', n: 9, role: 'sensor.proximity.9', name: 'PX09_conv3_outfeed_a',
    x: WAYPOINT.c3_end[0], y: WAYPOINT.c3_end[1], guarded: true,
    duty: 'Conveyor 3, outfeed station A. FC6 N14 sets STOP_CONV3.',
    provenance: 'SRC',
    positionNote: 'End of the station 3 belt (c3_end). Sequence.xlsx step 37.',
  },
  {
    id: 'PX10', n: 10, role: 'sensor.proximity.10', name: 'PX10_conv3_outfeed_b',
    x: WAYPOINT.c3_out_b[0], y: WAYPOINT.c3_out_b[1], guarded: false,
    duty: 'Conveyor 3, outfeed station B. FC6 N16 gates solenoid 13.',
    provenance: 'ASM',
    positionNote:
      'Placed at 60 % of the belt run, with outfeed B standing at it. FC6 N16 ' +
      'is symmetric -- prox 9 pulses solenoid 12, prox 10 pulses solenoid 13 -- ' +
      'and outfeed A stands at its own sensor. Inferred from the program, [ASM].',
  },
]

/** Camera field of view. `P.CAM = P.WP.feed`, Sequence.xlsx step 1. */
export const CAMERA = {
  x: WAYPOINT.feed[0],
  y: WAYPOINT.feed[1],
  label: 'CAM',
  note:
    'Camera field of view, at the feed point. P.CAM = P.WP.feed, ' +
    'initialize_factory.m section 5. Served by the YOLO service, not the PLC.',
}

/**
 * The two platform limit switches, DELIBERATELY WITHOUT COORDINATES.
 *
 * They are the machine's Proximity_sensor_11 and _12 (PGM_Up_Limit /
 * PGM_Low_Limit) and they watch the engraving platform's HEIGHT. A plan view
 * has no vertical axis, so draw_cell_layout.m names them beside the engraver
 * rather than giving them a fictitious x-y. This does the same: the caption is
 * anchored to the engraver rectangle and no position is claimed.
 */
export const PLATE_LIMITS = [
  { id: 'PX11', role: 'sensor.pgm_up_limit', label: 'UP', name: 'PGM_Up_Limit' },
  { id: 'PX12', role: 'sensor.pgm_low_limit', label: 'LOW', name: 'PGM_Low_Limit' },
] as const

export const PLATE_LIMIT_NOTE =
  'PX11/12 watch the engraving platform height. This is a plan view and has ' +
  'no vertical axis, so they are named at the engraver rather than given an ' +
  'invented position. There is no height transducer -- only these two limits, ' +
  'so the plate is either at a limit or "in transit", never at a stated height.'

// ---------------------------------------------------------------------------
// workpiece anchors
// ---------------------------------------------------------------------------

/**
 * Where the tracked token is drawn for each station the backend can report.
 * Station keys are `backend/state/products.py::STATIONS`; each anchor is the
 * waypoint of the sensor that confirms that station, so a CONFIRMED token is
 * drawn at the place its sensor actually sits.
 *
 * `magazine` and `feeder` have no confirming sensor and the backend never marks
 * them CONFIRMED; they anchor to the magazine body and the feed waypoint.
 */
export const TOKEN_ANCHOR: Record<string, { x: number; y: number }> = {
  magazine: { x: WAYPOINT.feed[0], y: 1.115 },
  feeder: { x: WAYPOINT.feed[0], y: WAYPOINT.feed[1] },
  conveyor1: { x: WAYPOINT.c1_load[0], y: WAYPOINT.c1_load[1] },
  conveyor1_end: { x: WAYPOINT.c1_end[0], y: WAYPOINT.c1_end[1] },
  conveyor2: { x: WAYPOINT.c2_end[0], y: WAYPOINT.c2_end[1] },
  engraving: { x: WAYPOINT.engrave[0], y: WAYPOINT.engrave[1] },
  conveyor3: { x: WAYPOINT.c3_end[0], y: WAYPOINT.c3_end[1] },
  bin: { x: WAYPOINT.bin[0], y: WAYPOINT.bin[1] },
}

/** Workpiece footprint. FactoryParams.m: `P.blk_L = P.blk_W = 0.100` m. */
export const BLOCK = { l: 0.1, w: 0.1 }

// ---------------------------------------------------------------------------
// the reference figure's palette
// ---------------------------------------------------------------------------

/**
 * The colours `draw_cell_layout.m` and `visualize_factory.m` actually use,
 * converted from MATLAB triples. Keeping them means the HMI plan and the
 * MATLAB figure read as the same machine, which is the point of drawing it to
 * scale in the first place.
 *
 * These carry OBJECT identity only. Live state is painted in the product's own
 * state tokens on top, so "dim structural colour" and "bright state colour"
 * stay separable at a glance.
 */
export const CELL_PALETTE = {
  belt: '#3366b3', // [0.2 0.4 0.7]
  engraver: '#b33333', // [0.7 0.2 0.2]
  actuator: '#666699', // [0.4 0.4 0.6]
  actuatorDouble: '#ffcc4d', // [1 0.8 0.3]  double-solenoid edge
  sensor: '#ffd933', // [1 0.85 0.2]
  camera: '#66e6ff', // [0.4 0.9 1]
  bin: '#404047', // [0.25 0.25 0.28]
  bound: '#999999', // [0.6 0.6 0.6]
  rod: '#22d3ee', // 'c'
  block: '#e68019', // [0.9 0.5 0.1]
  blockDone: '#33cc33', // [0.2 0.8 0.2]
} as const
