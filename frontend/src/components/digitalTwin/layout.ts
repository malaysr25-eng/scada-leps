/**
 * SUPERSEDED 2026-09-03 — DO NOT USE. Nothing imports this file.
 *
 * Use `components/cell/cellGeometry.ts` instead. The premise below -- that no
 * source places the sensors or the actuators -- was true of
 * `Tag_list (1).xlsx` read alone and false of this project:
 * `Factory_Simulation/initialize_factory.m` places all ten proximity sensors
 * and all eleven actuators in metres, each carrying its own provenance tag.
 *
 * The concrete consequences of that premise, all now fixed:
 *   * the cell was drawn as three parallel left-to-right belts. It is a T --
 *     conveyor 2 runs north to south down the middle.
 *   * PX05-PX10 and all thirteen valves were swept into "unassigned" trays.
 *     Every one of them has a position.
 *   * the canvas was undimensioned. The cell is 1.72 x 1.20 m and the plan is
 *     now drawn 1:1 with the simulation geometry.
 *
 * Kept only so the reasoning above is not lost. Delete once that has been read.
 *
 * ---------------------------------------------------------------------------
 *
 * Physical layout of the cell, for the schematic view.
 *
 * PROVENANCE OF EVERY PLACEMENT
 * -----------------------------
 * `Tag_list (1).xlsx` documents what each signal *is*. It documents nothing
 * about where anything sits on the bench. So each placement below carries an
 * explicit confidence, and the schematic renders the three tiers differently:
 *
 *   'sequenced'  The Sequencing sheet ties this signal to a specific station.
 *                PX1 is checked immediately after the feeder pushes onto belt
 *                1 (row 9); PX2 gates the belt-1 stop (row 11); PX3 gates the
 *                belt-2 stop (row 18); PX4 is the final position check on belt
 *                3 (row 37). Drawn solid.
 *
 *   'schematic'  Ordering is implied by the process but the exact bench
 *                position is not recorded anywhere. Conveyor and station
 *                geometry is of this kind. Drawn solid but not dimensioned --
 *                the schematic is topological, not to scale.
 *
 *   'unassigned' No source ties this signal to a station. PX5-PX10 and most of
 *                the 13 solenoid valves are in this class: the Sequencing
 *                sheet says "Actuator" without a number, and the Errors sheet
 *                names actuators 7, 8, 11 and 12 without ever mapping them to
 *                a valve address. Rendered in a labelled tray rather than
 *                guessed onto the belt.
 *
 * Assigning the unassigned ones is a five-minute job at the machine with the
 * Manual Control page: energise one valve, watch which cylinder moves. Until
 * someone does that and records it here, the schematic says "unassigned"
 * instead of inventing a position.
 */

export type Confidence = 'sequenced' | 'schematic' | 'unassigned'

export interface SensorPlacement {
  role: string
  label: string
  x: number
  y: number
  confidence: Confidence
  source: string
}

export interface StationBox {
  id: string
  label: string
  x: number
  y: number
  w: number
  h: number
  kind: 'magazine' | 'station' | 'engraving' | 'bin'
}

export interface BeltGeometry {
  index: number
  label: string
  x: number
  y: number
  w: number
  h: number
  direction: 'right' | 'down' | 'left'
}

// Canvas is 1000 x 460 user units; the schematic is topological, not to scale.
export const CANVAS = { w: 1000, h: 460 }

export const BELTS: BeltGeometry[] = [
  { index: 1, label: 'Conveyor 1', x: 168, y: 96, w: 250, h: 34, direction: 'right' },
  { index: 2, label: 'Conveyor 2', x: 168, y: 216, w: 250, h: 34, direction: 'right' },
  { index: 3, label: 'Conveyor 3', x: 590, y: 336, w: 250, h: 34, direction: 'right' },
]

export const STATIONS: StationBox[] = [
  { id: 'magazines', label: 'Magazines (camera)', x: 24, y: 60, w: 118, h: 210, kind: 'magazine' },
  { id: 'feeder', label: 'Feeder', x: 168, y: 30, w: 96, h: 44, kind: 'station' },
  { id: 'transfer', label: 'Transfer', x: 300, y: 152, w: 96, h: 44, kind: 'station' },
  { id: 'engraving', label: 'Engraving station', x: 470, y: 176, w: 150, h: 116, kind: 'engraving' },
  { id: 'bin', label: 'Output bin', x: 872, y: 318, w: 100, h: 70, kind: 'bin' },
]

/**
 * Sensor placements. Only PX1-PX4 and the two plate limit switches have a
 * defensible station; the rest are explicitly unassigned.
 */
export const SENSORS: SensorPlacement[] = [
  {
    role: 'sensor.proximity.1', label: 'PX1', x: 196, y: 84,
    confidence: 'sequenced',
    source: 'Sequencing row 9: position detection right after the feeder pushes onto belt 1.',
  },
  {
    role: 'sensor.proximity.2', label: 'PX2', x: 392, y: 84,
    confidence: 'sequenced',
    source: 'Sequencing row 11: position detection that gates the belt-1 stop (row 12).',
  },
  {
    role: 'sensor.proximity.3', label: 'PX3', x: 392, y: 204,
    confidence: 'sequenced',
    source: 'Sequencing row 18: position detection that gates the belt-2 stop (row 19).',
  },
  {
    role: 'sensor.proximity.4', label: 'PX4', x: 800, y: 324,
    confidence: 'sequenced',
    source: 'Sequencing row 37: final position check on belt 3.',
  },
  {
    role: 'sensor.pgm_up_limit', label: 'UP', x: 636, y: 190,
    confidence: 'sequenced',
    source: 'Sequencing row 26: vertical verification once the engraving base is raised.',
  },
  {
    role: 'sensor.pgm_low_limit', label: 'LOW', x: 636, y: 278,
    confidence: 'sequenced',
    source: 'Sequencing row 30: bottom verification once the base is lowered.',
  },
]

/** Proximity sensors with no documented station. */
export const UNASSIGNED_SENSORS = [5, 6, 7, 8, 9, 10].map((n) => ({
  role: `sensor.proximity.${n}`,
  label: `PX${n}`,
  confidence: 'unassigned' as Confidence,
  source:
    'No source ties this sensor to a station. The Sequencing sheet references ' +
    'only four position checks; the tag list records no physical location.',
}))

/**
 * Valves that the Sequencing sheet lets us place by *station role*, not by
 * valve number -- because it never gives a valve number. Every one of the 13
 * valves is therefore drawn in the tray, and the station boxes show which
 * *stage* is active rather than claiming a specific coil drives it.
 */
export const VALVE_COUNT = 13

export const PRODUCT_PATH: { station: string; x: number; y: number }[] = [
  { station: 'magazine', x: 84, y: 165 },
  { station: 'feeder', x: 216, y: 60 },
  { station: 'conveyor1', x: 216, y: 113 },
  { station: 'conveyor1_end', x: 400, y: 113 },
  { station: 'conveyor2', x: 400, y: 233 },
  { station: 'engraving', x: 545, y: 233 },
  { station: 'conveyor3', x: 700, y: 353 },
  { station: 'bin', x: 922, y: 353 },
]
