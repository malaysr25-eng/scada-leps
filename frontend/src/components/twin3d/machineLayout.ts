/**
 * Physical layout of the real cell, in metres, read from the reference
 * photographs.
 *
 * SCALE ANCHOR
 * ------------
 * The only measured dimension available is the conveyor length, 76 cm, from the
 * lab data sheet (`Industry 4.0_5.0 Lab data.xlsx`, sheet `Data`, rows 20–22).
 * Everything else is proportioned against that by eye from the photographs.
 *
 * That makes the model **proportionally faithful and dimensionally
 * approximate**. One tape measurement of the table would upgrade it; until then
 * every dimension except the conveyor length carries `APPROX` in the component
 * table and the UI says so.
 *
 * COORDINATE SYSTEM
 * -----------------
 *   +X  along conveyor 1, left → right as seen in the wide overview photo
 *   +Y  up
 *   +Z  toward the viewer (conveyor 2 runs along Z)
 *   origin at the floor, front-left corner of the table frame
 *
 * LAYOUT, FROM THE PHOTOGRAPHS
 * ----------------------------
 * The cell is T-shaped, not a straight line. Reading the two top-down frames
 * together with the wide overviews:
 *
 *     magazine + 5 pushers  ──►  CONVEYOR 1 (along X)
 *                                     │
 *                                     ▼  transfer pusher
 *                                CONVEYOR 2 (along Z)
 *                                     │
 *                                     ▼  station pusher
 *                          [ LASER ENCLOSURE, raised ]
 *                                     │
 *                                     ▼
 *                                CONVEYOR 3 (along X)  ──►  bin
 *
 * The existing 2-D schematic draws conveyors 1 and 2 parallel. The photographs
 * show them perpendicular; that is the single biggest layout correction here.
 */

// ---------------------------------------------------------------------------
// scale
// ---------------------------------------------------------------------------

/** Measured: lab data sheet rows 20–22. The one real dimension. */
export const CONVEYOR_LENGTH = 0.76

/** Table height, proportioned against the conveyors in the overview photos. */
export const TABLE_HEIGHT = 0.78
export const BELT_WIDTH = 0.13
export const BELT_THICKNESS = 0.018
export const EXTRUSION = 0.03

export const CELL = {
  // Widened from 2.2 m: conveyor 3 starts at x=1.62 and is 0.76 long, so it
  // needs 2.38 m of table before the bin. Caught by tools/check_twin_layout.py.
  width: 2.75,  // X
  depth: 1.65,  // Z
  height: TABLE_HEIGHT,
}

export type Confidence = 'PHOTO' | 'PROP' | 'APPROX' | 'DOC'

export interface Placement {
  id: string
  label: string
  position: [number, number, number]
  rotationY?: number
  confidence: Confidence
  note?: string
  /** Semantic role this component reads, if any. Never invented. */
  role?: string
}

// ---------------------------------------------------------------------------
// conveyors
// ---------------------------------------------------------------------------

export interface ConveyorPlacement extends Placement {
  index: 1 | 2 | 3
  length: number
  /** 'x' runs along X, 'z' runs along Z. Direction of travel is +axis. */
  axis: 'x' | 'z'
}

export const CONVEYORS: ConveyorPlacement[] = [
  {
    id: 'conveyor1', label: 'Conveyor 1', index: 1,
    position: [0.62, TABLE_HEIGHT, 0.30],
    length: CONVEYOR_LENGTH, axis: 'x',
    confidence: 'PHOTO', role: 'conveyor.1.running',
    note: 'Runs left-to-right beneath the magazine, as seen in both top-down views.',
  },
  {
    id: 'conveyor2', label: 'Conveyor 2', index: 2,
    position: [1.06, TABLE_HEIGHT, 0.76],
    length: CONVEYOR_LENGTH, axis: 'z',
    confidence: 'PHOTO', role: 'conveyor.2.running',
    note: 'PERPENDICULAR to conveyor 1 — this is what makes the cell T-shaped. '
        + 'The 2-D schematic drew it parallel, which was wrong.',
  },
  {
    id: 'conveyor3', label: 'Conveyor 3', index: 3,
    position: [1.62, TABLE_HEIGHT, 1.14],
    length: CONVEYOR_LENGTH, axis: 'x',
    confidence: 'PHOTO', role: 'conveyor.3.running',
    note: 'Offset and downstream of the engraver, feeding the output bin.',
  },
]

// ---------------------------------------------------------------------------
// magazine
// ---------------------------------------------------------------------------

export const MAGAZINE = {
  id: 'magazine',
  label: 'Feed magazine',
  /** Elevated above belt height and tilted forward, per the close photographs. */
  position: [0.46, TABLE_HEIGHT + 0.20, 0.12] as [number, number, number],
  rotationX: -0.16,
  width: 0.72,
  height: 0.20,
  depth: 0.16,
  compartments: 5,
  confidence: 'PHOTO' as Confidence,
  note: 'Transparent acrylic with vertical dividers and a tan plywood top '
      + 'cover. Wooden blocks visible inside. Compartment count read as 5, '
      + 'consistent with the five Comp_Status tag groups.',
}

// ---------------------------------------------------------------------------
// pneumatic cylinders
// ---------------------------------------------------------------------------

export interface CylinderPlacement extends Placement {
  /** Rod travel in metres. Proportioned; real stroke is unknown. */
  stroke: number
  /** Which way the rod extends. */
  axis: 'x' | 'z' | 'y'
  direction: 1 | -1
  /**
   * Valve role this cylinder is driven by, if known.
   *
   * `null` for most of them, deliberately. No supplied source maps actuator
   * numbers to valve numbers — the Errors sheet says "actuator 7", the
   * Sequencing sheet says "Actuator" with no number. A cylinder with a null
   * binding renders idle and the inspector says why.
   */
  valveRole: string | null
}

export const CYLINDERS: CylinderPlacement[] = [
  // Feed pushers: a dense row of five along the magazine, clearly visible.
  ...[0, 1, 2, 3, 4].map((i) => ({
    id: `feed_pusher_${i + 1}`,
    label: `Feed pusher ${i + 1}`,
    position: [0.20 + i * 0.145, TABLE_HEIGHT + 0.075, 0.06] as [number, number, number],
    stroke: 0.09,
    axis: 'z' as const,
    direction: 1 as const,
    valveRole: null,
    confidence: 'PHOTO' as Confidence,
    note: 'One of five pushers photographed in a row facing the magazine. '
        + 'Which solenoid drives it is not recorded in any supplied source.',
  })),
  {
    id: 'transfer_pusher',
    label: 'Transfer pusher (belt 1 → belt 2)',
    position: [1.06, TABLE_HEIGHT + 0.075, 0.30],
    stroke: 0.11, axis: 'z', direction: 1, valveRole: null,
    confidence: 'APPROX',
    note: 'Position inferred from the belt junction. Exact body not clearly '
        + 'visible in any view.',
  },
  {
    id: 'engraver_infeed_pusher',
    label: 'Engraver infeed pusher',
    position: [1.06, TABLE_HEIGHT + 0.075, 1.02],
    stroke: 0.10, axis: 'x', direction: 1, valveRole: null,
    confidence: 'APPROX',
    note: 'Pushes from belt 2 onto the engraving platform.',
  },
  {
    id: 'engraver_outfeed_pusher',
    label: 'Engraver outfeed pusher',
    position: [1.34, TABLE_HEIGHT + 0.075, 1.02],
    stroke: 0.10, axis: 'x', direction: 1, valveRole: null,
    confidence: 'APPROX',
    note: 'Moves the engraved block onto belt 3.',
  },
  {
    id: 'ejector',
    label: 'Bin ejector',
    position: [2.40, TABLE_HEIGHT + 0.075, 1.14],
    stroke: 0.09, axis: 'z', direction: 1, valveRole: null,
    confidence: 'APPROX',
    note: 'Ejects into the output crate at the end of belt 3.',
  },
]

// ---------------------------------------------------------------------------
// engraving station
// ---------------------------------------------------------------------------

export const ENGRAVER = {
  id: 'engraver',
  label: 'Laser engraving station',
  /** Raised on its own platform above belt height — clear in every overview. */
  position: [1.20, TABLE_HEIGHT + 0.06, 1.02] as [number, number, number],
  enclosure: { width: 0.34, height: 0.30, depth: 0.30 },
  /** Travel of the lift between the two limit switches. */
  platformTravel: 0.11,
  confidence: 'PHOTO' as Confidence,
  note: 'Red/orange tinted acrylic enclosure (DAJA) on a raised platform, with '
      + 'the gantry visible through the tint.',
}

// ---------------------------------------------------------------------------
// output
// ---------------------------------------------------------------------------

export const OUTPUT_BIN = {
  id: 'output_bin',
  label: 'Output bin',
  position: [2.52, TABLE_HEIGHT, 1.30] as [number, number, number],
  size: { width: 0.30, height: 0.16, depth: 0.22 },
  confidence: 'PHOTO' as Confidence,
  note: 'Blue plastic crate, photographed containing a wooden block.',
}

// ---------------------------------------------------------------------------
// electrical cabinet + air
// ---------------------------------------------------------------------------

export const CABINET = {
  id: 'cabinet',
  label: 'Electrical cabinet',
  /** Separate from the cell, on its own black rolling base. */
  position: [3.05, 0, 0.42] as [number, number, number],
  rotationY: -Math.PI / 2,
  size: { width: 0.62, height: 0.58, depth: 0.26 },
  baseHeight: 0.52,
  confidence: 'PHOTO' as Confidence,
  note: 'Cream steel enclosure with a large glazed window. Siemens S7-1200, '
      + 'power supply and three rows of terminal blocks visible through it.',
}

export const AIR_RECEIVER = {
  id: 'air_receiver',
  label: 'Air receiver',
  position: [3.05, 0.16, 0.92] as [number, number, number],
  radius: 0.10,
  length: 0.40,
  confidence: 'PHOTO' as Confidence,
  note: 'Horizontal cylindrical tank with a compressor head, at floor level '
      + 'beside the cabinet.',
}

export const VALVE_MANIFOLD = {
  id: 'valve_manifold',
  label: 'Solenoid valve manifold',
  position: [0.14, TABLE_HEIGHT - 0.18, 0.62] as [number, number, number],
  valveCount: 13,
  confidence: 'APPROX' as Confidence,
  note: 'A bank of solenoid bodies is clearly visible in the side view, but '
      + 'individual valves cannot be numbered from any photograph.',
}

export const ESTOP = {
  id: 'estop',
  label: 'Emergency stop',
  position: [2.18, TABLE_HEIGHT + 0.10, 0.52] as [number, number, number],
  confidence: 'PHOTO' as Confidence,
  note: 'Red mushroom button on a yellow plate, visible on the right-hand side.',
}

export const DESK = {
  id: 'desk',
  label: 'Operator desk',
  position: [-0.55, 0, 0.75] as [number, number, number],
  confidence: 'PHOTO' as Confidence,
  note: 'Monitor and keyboard on an adjacent bench.',
}

// ---------------------------------------------------------------------------
// sensors
// ---------------------------------------------------------------------------

export interface SensorPlacement extends Placement {
  role: string
}

/**
 * Only the four proximity sensors the Sequencing sheet ties to a station, plus
 * the two plate limit switches.
 *
 * PX5–PX10 are NOT placed. The Sequencing sheet describes four position
 * checks; no source says where the other six are. They appear in the inspector
 * as unplaced rather than being scattered onto the model.
 */
export const SENSORS: SensorPlacement[] = [
  {
    id: 'px1', label: 'PX1', role: 'sensor.proximity.1',
    position: [0.30, TABLE_HEIGHT + 0.05, 0.30],
    confidence: 'DOC',
    note: 'Sequencing row 9: position detection after the feeder pushes onto belt 1.',
  },
  {
    id: 'px2', label: 'PX2', role: 'sensor.proximity.2',
    position: [0.94, TABLE_HEIGHT + 0.05, 0.30],
    confidence: 'DOC',
    note: 'Sequencing row 11: gates the belt-1 stop.',
  },
  {
    id: 'px3', label: 'PX3', role: 'sensor.proximity.3',
    position: [1.06, TABLE_HEIGHT + 0.05, 1.02],
    confidence: 'DOC',
    note: 'Sequencing row 18: gates the belt-2 stop.',
  },
  {
    id: 'px4', label: 'PX4', role: 'sensor.proximity.4',
    position: [2.28, TABLE_HEIGHT + 0.05, 1.14],
    confidence: 'DOC',
    note: 'Sequencing row 37: final position check on belt 3.',
  },
  {
    id: 'pgm_up', label: 'Plate up limit', role: 'sensor.pgm_up_limit',
    position: [1.40, TABLE_HEIGHT + 0.22, 1.02],
    confidence: 'DOC',
    note: 'Sequencing row 26: vertical verification with the base raised.',
  },
  {
    id: 'pgm_low', label: 'Plate low limit', role: 'sensor.pgm_low_limit',
    position: [1.40, TABLE_HEIGHT + 0.04, 1.02],
    confidence: 'DOC',
    note: 'Sequencing row 30: bottom verification.',
  },
]

export const UNPLACED_SENSORS = [5, 6, 7, 8, 9, 10].map((n) => ({
  id: `px${n}`,
  label: `PX${n}`,
  role: `sensor.proximity.${n}`,
  reason:
    'No supplied source ties this sensor to a station. The Sequencing sheet '
    + 'describes only four position checks, and the tag list records no '
    + 'physical location.',
}))

// ---------------------------------------------------------------------------
// pneumatic tubing (visible runs only)
// ---------------------------------------------------------------------------

export const TUBE_RUNS: { id: string; points: [number, number, number][] }[] = [
  {
    id: 'tube_manifold_to_feed',
    points: [
      [0.16, TABLE_HEIGHT - 0.14, 0.62],
      [0.16, TABLE_HEIGHT + 0.02, 0.40],
      [0.24, TABLE_HEIGHT + 0.09, 0.10],
    ],
  },
  {
    id: 'tube_manifold_to_transfer',
    points: [
      [0.20, TABLE_HEIGHT - 0.14, 0.60],
      [0.70, TABLE_HEIGHT - 0.10, 0.46],
      [1.04, TABLE_HEIGHT + 0.09, 0.34],
    ],
  },
  {
    id: 'tube_manifold_to_engraver',
    points: [
      [0.24, TABLE_HEIGHT - 0.14, 0.64],
      [0.80, TABLE_HEIGHT - 0.12, 0.90],
      [1.04, TABLE_HEIGHT + 0.09, 1.00],
    ],
  },
  {
    id: 'tube_manifold_to_ejector',
    points: [
      [0.28, TABLE_HEIGHT - 0.14, 0.66],
      [1.30, TABLE_HEIGHT - 0.14, 1.30],
      [2.38, TABLE_HEIGHT + 0.08, 1.20],
    ],
  },
  {
    id: 'tube_receiver_to_manifold',
    points: [
      [2.93, 0.22, 0.92],
      [1.20, 0.30, 0.40],
      [0.20, TABLE_HEIGHT - 0.20, 0.60],
    ],
  },
]

// ---------------------------------------------------------------------------
// palette, sampled from the photographs
// ---------------------------------------------------------------------------

export const MATERIALS = {
  extrusion: '#b8bfc7',
  extrusionDark: '#8b939c',
  beltBlue: '#1f5fbf',
  beltBlueDark: '#164a99',
  basePanel: '#1c2b4a',
  creamBox: '#ddd6c4',
  creamBoxDark: '#c2baa6',
  cabinetCream: '#e0dac9',
  laserRed: '#e2452a',
  acrylicClear: '#cfe3f0',
  plywood: '#c9a06a',
  wood: '#9a6b3f',
  binBlue: '#1a4fa0',
  tubeBlue: '#2f7fd4',
  steel: '#c9ced4',
  blackBase: '#15171b',
  estopRed: '#d61f26',
  estopPlate: '#e8c341',
} as const
