/**
 * The cell plan view -- the visual centrepiece, drawn to scale.
 *
 * WHAT CHANGED AND WHY IT MATTERS
 * -------------------------------
 * The previous schematic declared itself "topological, not to scale" and drew
 * three parallel left-to-right belts. The machine is a T: conveyor 1 runs east
 * along the top, conveyor 2 runs SOUTH down the middle, and the station 3 belt
 * runs east again along the bottom, with the engraver between them. Anyone
 * navigating the real cell from that old picture would have walked the wrong
 * way. Every rectangle, sensor and actuator body here is at its metric position
 * from `cellGeometry.ts`, which is a transcription of the MATLAB model.
 *
 * WHAT IS DRAWN, AND HOW HONESTLY
 *
 * * **Sensors** illuminate on their PLC bit. A sensor that GATES the sequence
 *   (`P.PROX_GUARD = [1 6 8 9]`) carries a second, outer ring, so the four that
 *   can stop the cycle are distinguishable from the six that are wired and
 *   logged but guard nothing. Unknown is a dashed outline, never OFF.
 *
 * * **Actuators** are eleven bodies at their own retracted rod tips, each
 *   labelled with the machine's coil numbers -- `CYL A [7/8]` is one
 *   double-solenoid cylinder, not two valves. The stroke TRACK is drawn,
 *   because the geometry is sourced. The rod's position within it is NOT drawn,
 *   because no reed switch exists on any of the eleven and inventing a moving
 *   rod is exactly the lie this interface is built to avoid.
 *
 * * **Belts** flow only while the run coil is energised AND the encoder reports
 *   motion. A belt commanded on but not turning is drawn stopped and flagged --
 *   which is the conveyor-2 symptom in the Errors sheet.
 *
 * * **The workpiece** is solid where a sensor confirms it and a dashed ghost
 *   where its position is only inferred. There is no interpolation between
 *   sensors: the cell has presence detectors, not encoders on the part.
 *
 * * **The engraving platform** has two limit switches and no height
 *   transducer, so it reads UP, DOWN or IN TRANSIT and never a millimetre
 *   figure.
 *
 * COLOUR HAS TWO JOBS HERE AND THEY ARE KEPT SEPARATE. Dim structural colour is
 * the machine, borrowed from the MATLAB figure's own palette so the two
 * drawings read as the same cell. Bright state colour is live signal, in the
 * product's `state-*` tokens. Nothing dim is a reading; nothing bright is
 * decoration.
 */

import { useMemo, type ReactNode } from 'react'
import { AlertTriangle } from 'lucide-react'
import {
  selectActuators, selectConveyors, selectInventory, selectSafety,
  selectSensors, selectSequence, selectStale, useMachine,
} from '../../stores/machineStore'
import type { ActuatorView, ConveyorView, SensorView, Tri } from '../../types'
import { classNames, num } from '../../utils/format'
import {
  ACTUATORS, actuatorLabel, COIL_MAP, NO_ROD_FEEDBACK, type Actuator,
} from './actuatorModel'
import {
  BELTS, BIN, BLOCK, CAMERA, CELL_PALETTE, ENGRAVER, mlen, mx, my,
  PLATE_LIMIT_NOTE, PLATE_LIMITS, SENSORS, STATION_BOUNDS, TOKEN_ANCHOR, VIEW,
} from './cellGeometry'
import type { PlanFocus } from './sequenceSources'

const C = {
  edge: '#283348',
  surface: '#10151f',
  text: '#a9b6c9',
  textDim: '#5a6980',
  run: '#22c55e',
  warn: '#f59e0b',
  fault: '#ef4444',
  info: '#38bdf8',
  twin: '#a78bfa',
}

const MONO = 'JetBrains Mono, Consolas, monospace'
const SANS = 'Inter, Segoe UI, system-ui, sans-serif'

/**
 * Actuators whose label is drawn to the LEFT of the body rather than the right.
 *
 * Purely a rendering concern -- unlike `drawOffset`, which records a fact about
 * the model (two actuators resolving to the same rectangle) and therefore lives
 * with the model. MOVE_TO_CV3's label would otherwise run underneath CYL_B's
 * displaced body.
 */
const LABEL_LEFT = new Set(['MOVE_TO_CV3'])

export interface CellPlanProps {
  onSensorClick?: (sensor: SensorView) => void
  onActuatorClick?: (actuator: Actuator, coils: ActuatorView[]) => void
  /** Highlight the element a sequence step acts on. */
  focus?: PlanFocus
  /** Hide the legend; the Overview uses this to save vertical space. The
   *  plan itself is capped at 62vh everywhere. */
  compact?: boolean
}

export function CellPlan({
  onSensorClick,
  onActuatorClick,
  focus,
  compact,
}: CellPlanProps) {
  const sensors = useMachine(selectSensors)
  const conveyors = useMachine(selectConveyors)
  const actuators = useMachine(selectActuators)
  const inventory = useMachine(selectInventory)
  const sequence = useMachine(selectSequence)
  const stale = useMachine(selectStale)

  const sensorByRole = useMemo(() => {
    const map = new Map<string, SensorView>()
    sensors?.forEach((s) => map.set(s.role, s))
    return map
  }, [sensors])

  const coilByIndex = useMemo(() => {
    const map = new Map<number, ActuatorView>()
    actuators?.forEach((a) => map.set(a.index, a))
    return map
  }, [actuators])

  const token = inventory?.activeToken ?? null
  const anchor = token ? TOKEN_ANCHOR[token.station] : undefined
  // visualize_factory.m turns the block green at `LOG.state(i) >= 26`, the step
  // at which the operator confirms the engraving. The same threshold here.
  const engraved = (sequence?.stepIndex ?? 0) >= 26

  const plateUp = sensorByRole.get('sensor.pgm_up_limit')?.value ?? null
  const plateLow = sensorByRole.get('sensor.pgm_low_limit')?.value ?? null

  return (
    <div className="relative">
      <svg
        viewBox={`0 0 ${VIEW.w} ${VIEW.h}`}
        className={classNames(
          'max-h-[62vh] w-full rounded-lg border border-panel-700 bg-panel-950',
          stale && 'opacity-60 saturate-50',
        )}
        role="img"
        aria-label="Cell plan view, drawn to scale from the simulation geometry"
      >
        <defs>
          <filter id="cellGlow" x="-140%" y="-140%" width="380%" height="380%">
            <feGaussianBlur stdDeviation="9" result="b" />
            <feMerge>
              <feMergeNode in="b" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        <ScaleBar />
        {STATION_BOUNDS.map((b) => (
          <StationBound key={b.id} bound={b} />
        ))}

        {/* ---- fixed surfaces ---- */}
        <Surface
          rect={BIN}
          fill={CELL_PALETTE.bin}
          stroke="#ffffff"
          fillOpacity={0.55}
        />
        <EngraverBlock up={plateUp} low={plateLow} focused={focus?.kind === 'engraver'} />

        {/* ---- belts ---- */}
        {BELTS.map((belt) => (
          <Belt
            key={belt.index}
            belt={belt}
            live={conveyors?.find((c) => c.index === belt.index)}
            focused={focus?.kind === 'conveyor' && focus.index === belt.index}
          />
        ))}

        {/* ---- actuators ---- */}
        {ACTUATORS.map((a) => (
          <ActuatorBody
            key={a.name}
            actuator={a}
            coils={a.coils.map((n) => coilByIndex.get(n)).filter(Boolean) as ActuatorView[]}
            focused={focus?.kind === 'actuator' && focus.name === a.name}
            onClick={onActuatorClick}
          />
        ))}

        {/* ---- workpiece, under the sensors so a lamp is never hidden ---- */}
        {anchor && token && (
          <Workpiece
            x={anchor.x}
            y={anchor.y}
            label={token.tokenId}
            confirmed={token.positioning === 'CONFIRMED'}
            engraved={engraved}
            title={
              `${token.tokenId} — ${token.stationLabel}\n` +
              (token.positioning === 'CONFIRMED'
                ? 'Position CONFIRMED by a physical sensor.'
                : 'Position ESTIMATED from the sequence — no sensor confirms it.') +
              `\nLast event: ${token.lastEvent || '—'}` +
              `\nExpected next: ${token.expectedNext || '—'}`
            }
          />
        )}

        {/* ---- sensors ---- */}
        {SENSORS.map((p) => (
          <Sensor
            key={p.id}
            placement={p}
            live={sensorByRole.get(p.role)}
            focused={focus?.kind === 'sensor' && focus.id === p.id}
            onClick={onSensorClick}
          />
        ))}
        <Camera focused={focus?.kind === 'camera'} />
        <PlateLimits up={plateUp} low={plateLow} sensorByRole={sensorByRole} />

        {/* ---- captions, last so they sit above every fill ---- */}
        <Captions />
      </svg>

      {stale && (
        <div className="pointer-events-none absolute inset-0 grid place-items-center">
          <div className="flex items-center gap-2 rounded-lg border border-state-warn/50 bg-panel-950/90 px-4 py-2">
            <AlertTriangle size={16} className="text-state-warn" />
            <span className="text-xs font-semibold uppercase tracking-wider text-state-warn">
              Stale &mdash; last known values
            </span>
          </div>
        </div>
      )}

      {!compact && <Legend />}
    </div>
  )
}

// ---------------------------------------------------------------------------
// static furniture
// ---------------------------------------------------------------------------

/** A 100 mm scale bar. The whole point of the redraw is that this is real. */
function ScaleBar() {
  const x = mx(1.06)
  const y = my(0.075)
  const len = mlen(0.1)
  return (
    <g stroke={C.textDim} fill={C.textDim}>
      <title>The plan is drawn to scale: P.SCALE = 0.10 m per drawing unit.</title>
      <line x1={x} y1={y} x2={x + len} y2={y} strokeWidth="3" />
      <line x1={x} y1={y - 8} x2={x} y2={y + 8} strokeWidth="3" />
      <line x1={x + len} y1={y - 8} x2={x + len} y2={y + 8} strokeWidth="3" />
      <text
        x={x + len / 2} y={y - 16} fontSize="20" textAnchor="middle"
        fontFamily={MONO} stroke="none"
      >
        100 mm
      </text>
    </g>
  )
}

function StationBound({ bound }: { bound: (typeof STATION_BOUNDS)[number] }) {
  return (
    <g>
      <rect
        x={mx(bound.x)}
        y={my(bound.y + bound.h)}
        width={mlen(bound.w)}
        height={mlen(bound.h)}
        fill="none"
        stroke={CELL_PALETTE.bound}
        strokeOpacity="0.32"
        strokeWidth="2.5"
        strokeDasharray="14 10"
      />
      <text
        x={mx(bound.x) + 12}
        y={my(bound.y + bound.h) + 26}
        fontSize="21"
        fontFamily={SANS}
        fontWeight="700"
        letterSpacing="1.6"
        fill={CELL_PALETTE.bound}
        fillOpacity="0.6"
      >
        {bound.label.toUpperCase()}
      </text>
    </g>
  )
}

function Surface({
  rect,
  fill,
  stroke,
  fillOpacity = 0.3,
}: {
  rect: { x: number; y: number; w: number; h: number; source: string }
  fill: string
  stroke: string
  fillOpacity?: number
}) {
  return (
    <rect
      x={mx(rect.x)}
      y={my(rect.y + rect.h)}
      width={mlen(rect.w)}
      height={mlen(rect.h)}
      fill={fill}
      fillOpacity={fillOpacity}
      stroke={stroke}
      strokeOpacity="0.35"
      strokeWidth="2"
    >
      <title>{rect.source}</title>
    </rect>
  )
}

/**
 * Belt and fixture names.
 *
 * Every caption sits in clear space rather than across a belt, because the
 * sensors and actuator bodies now occupy the positions the MATLAB figure could
 * afford to write over -- ten sensors and eleven barrels where that figure had
 * four and six. Each belt is named at the end it STARTS from, with the arrow
 * showing travel, so the material path reads without a legend.
 */
function Captions() {
  const cap = (
    x: number,
    y: number,
    text: string,
    anchor: 'start' | 'end' = 'start',
  ) => (
    <text
      key={text}
      x={mx(x)}
      y={my(y)}
      fontSize="21"
      fontFamily={SANS}
      fontWeight="600"
      letterSpacing="1.4"
      textAnchor={anchor}
      fill={C.text}
    >
      {text}
    </text>
  )
  return (
    <g>
      {/* Conveyor 1 starts at its west end; label sits outside, to the left. */}
      {cap(0.09, 0.905, 'CONVEYOR 1 →', 'end')}
      {/* Conveyor 2 runs north to south; label sits west of it, clear of the
          two barrels and PX07/PX08 that stand on its centreline. */}
      {cap(0.715, 0.3, 'CONVEYOR 2 ↓', 'end')}
      {/* Station 3 belt starts at its west end; label sits below it. */}
      {cap(0.865, 0.29, 'STATION 3 BELT →')}
      {/* The engraver's top-left corner carries the MOVE>CV3 and CYL_B
          barrels and its centre carries the workpiece, so the name goes at
          the foot of the box. */}
      {cap(0.874, 0.46, 'LASER ENGRAVER')}
      {cap(1.437, 0.125, 'BIN')}
    </g>
  )
}

// ---------------------------------------------------------------------------
// belts
// ---------------------------------------------------------------------------

function Belt({
  belt,
  live,
  focused,
}: {
  belt: (typeof BELTS)[number]
  live: ConveyorView | undefined
  focused: boolean
}) {
  const commandedOn = live?.running === true
  const moving =
    commandedOn &&
    live?.feedbackVelocity != null &&
    Math.abs(live.feedbackVelocity) > 1e-6
  const mismatch = commandedOn && !moving
  const unknown = live?.running == null

  const x = mx(belt.x)
  const y = my(belt.y + belt.h)
  const w = mlen(belt.w)
  const h = mlen(belt.h)
  const horizontal = belt.flow[0] !== 0

  // Three flow lines across the belt width, drawn in the travel direction so
  // the dash march runs the way the belt actually runs.
  const lanes = [0.28, 0.5, 0.72].map((t) => {
    if (horizontal) {
      const ly = y + h * t
      const forward = belt.flow[0] > 0
      return { x1: forward ? x : x + w, y1: ly, x2: forward ? x + w : x, y2: ly }
    }
    const lx = x + w * t
    // flow [0,-1] is downward in model space, which is +y in SVG space.
    const forward = belt.flow[1] < 0
    return { x1: lx, y1: forward ? y : y + h, x2: lx, y2: forward ? y + h : y }
  })

  return (
    <g>
      <title>
        {`${belt.label} — ${live?.runAddress ?? 'no run tag'}\n` +
          `Run coil: ${commandedOn ? 'ON' : live?.running === false ? 'OFF' : 'UNKNOWN'}\n` +
          `Encoder feedback: ${live?.feedbackVelocity != null ? live.feedbackVelocity.toFixed(3) : 'no feedback tag'}\n` +
          belt.source}
      </title>
      <rect
        x={x} y={y} width={w} height={h} rx="8"
        fill={CELL_PALETTE.belt}
        fillOpacity={moving ? 0.42 : 0.24}
        stroke={mismatch ? C.fault : commandedOn ? C.run : focused ? C.info : '#ffffff'}
        strokeOpacity={commandedOn || mismatch || focused ? 0.9 : 0.32}
        strokeWidth={commandedOn || mismatch || focused ? 5 : 2}
        strokeDasharray={unknown ? '10 8' : undefined}
      />
      <g
        stroke={moving ? C.run : C.text}
        strokeOpacity={moving ? 0.85 : 0.22}
        strokeWidth="9"
        strokeLinecap="round"
        strokeDasharray="16 8"
      >
        {lanes.map((l, i) => (
          <line
            key={i}
            {...l}
            className={moving ? 'animate-beltFlow' : undefined}
          />
        ))}
      </g>
      {mismatch && (
        <g transform={`translate(${x + w / 2}, ${y + h / 2})`}>
          <title>
            Run coil energised but the encoder reports no motion. See Diagnostics.
          </title>
          <circle r="26" fill={C.fault} fillOpacity="0.2" />
          <text
            y="10" fontSize="32" textAnchor="middle" fill={C.fault}
            fontFamily={MONO} fontWeight="700"
          >
            !
          </text>
        </g>
      )}
    </g>
  )
}

// ---------------------------------------------------------------------------
// engraver + plate limits
// ---------------------------------------------------------------------------

function EngraverBlock({
  up,
  low,
  focused,
}: {
  up: Tri
  low: Tri
  focused: boolean
}) {
  const accent =
    up === true ? C.warn : low === true ? C.run : up == null && low == null ? C.textDim : C.info

  return (
    <g>
      <rect
        x={mx(ENGRAVER.x)}
        y={my(ENGRAVER.y + ENGRAVER.h)}
        width={mlen(ENGRAVER.w)}
        height={mlen(ENGRAVER.h)}
        rx="8"
        fill={CELL_PALETTE.engraver}
        fillOpacity="0.26"
        stroke={focused ? C.info : accent}
        strokeOpacity={focused ? 0.95 : 0.75}
        strokeWidth={focused ? 5 : 3}
      >
        <title>{ENGRAVER.source}</title>
      </rect>
    </g>
  )
}

function PlateLimits({
  up,
  low,
  sensorByRole,
}: {
  up: Tri
  low: Tri
  sensorByRole: Map<string, SensorView>
}) {
  const status =
    up === true
      ? { text: 'PLATE UP', tone: C.warn }
      : low === true
        ? { text: 'PLATE DOWN', tone: C.run }
        : up == null || low == null
          ? { text: 'PLATE UNKNOWN', tone: C.textDim }
          : { text: 'PLATE IN TRANSIT', tone: C.info }

  // Placed OUTSIDE the engraver rectangle, to its right. Inside it there is no
  // room: the two barrels stand on the top-left corner, the workpiece sits in
  // the middle when it is on the base, and the box is only 370 x 265 mm.
  const x = mx(ENGRAVER.x + ENGRAVER.w) + 20
  const y = my(ENGRAVER.y + ENGRAVER.h) + 35

  return (
    <g>
      <title>{PLATE_LIMIT_NOTE}</title>
      <text
        x={x} y={y} fontSize="22" fontFamily={MONO} fontWeight="700"
        fill={status.tone}
      >
        {status.text}
      </text>
      {PLATE_LIMITS.map((limit, i) => {
        const live = sensorByRole.get(limit.role)
        const on = live?.value === true
        const unknown = live?.value == null
        return (
          <g key={limit.id} transform={`translate(${x + i * 104}, ${y + 8})`}>
            <title>
              {`${limit.name} (${limit.id}) — ${live?.address ?? 'no tag'}\n` +
                `${on ? 'MADE' : unknown ? 'UNKNOWN' : 'clear'}\n${PLATE_LIMIT_NOTE}`}
            </title>
            <circle
              cx="10" cy="10" r="10"
              fill={on ? CELL_PALETTE.sensor : 'none'}
              stroke={on ? CELL_PALETTE.sensor : unknown ? C.textDim : C.edge}
              strokeWidth="3"
              strokeDasharray={unknown ? '4 4' : undefined}
            />
            <text
              x="26" y="17" fontSize="19" fontFamily={MONO}
              fill={on ? CELL_PALETTE.sensor : C.textDim}
            >
              {limit.label}
            </text>
          </g>
        )
      })}
      <text
        x={x} y={y + 62} fontSize="17" fontFamily={SANS} fill={C.textDim}
      >
        PX11/12 — platform height, no plan position
      </text>
    </g>
  )
}

// ---------------------------------------------------------------------------
// actuators
// ---------------------------------------------------------------------------

function ActuatorBody({
  actuator,
  coils,
  focused,
  onClick,
}: {
  actuator: Actuator
  coils: ActuatorView[]
  focused: boolean
  onClick?: (a: Actuator, coils: ActuatorView[]) => void
}) {
  const { body, tip0, lat, travel } = actuator.geometry
  const extendCoil = coils.find((c) => c.index === actuator.coilExtend)
  const retractCoil = coils.find((c) => c.index === actuator.coilRetract)

  const extendOn = extendCoil?.state === true
  const retractOn = retractCoil?.state === true
  const anyOn = extendOn || retractOn
  const unknown = coils.length === 0 || coils.every((c) => c.state == null)

  const edge = actuator.kind === 'double' ? CELL_PALETTE.actuatorDouble : '#ffffff'
  const accent = extendOn ? C.run : retractOn ? C.info : focused ? C.info : edge

  // The stroke TRACK is real geometry. The rod's position on it is not
  // measured, so the track is drawn and the rod tip never is.
  const track =
    travel != null
      ? actuator.axis === 'x'
        ? {
            x1: mx(tip0), y1: my(lat),
            x2: mx(tip0 + actuator.dir * travel), y2: my(lat),
          }
        : {
            x1: mx(lat), y1: my(tip0),
            x2: mx(lat), y2: my(tip0 + actuator.dir * travel),
          }
      : null

  // The offset moves the BODY only. `geometry` is never touched, the track is
  // drawn at the true position, and a leader ties the two together.
  const [ox, oy] = actuator.drawOffset
  const offset = ox !== 0 || oy !== 0
  const bodyX = mx(body.x + ox)
  const bodyY = my(body.y + body.h + oy)
  const labelLeft = LABEL_LEFT.has(actuator.name)
  const labelX = labelLeft ? bodyX + mlen(body.w) - 8 : bodyX
  const labelY = bodyY - 10

  return (
    <g
      className={onClick ? 'cursor-pointer' : undefined}
      onClick={() => onClick?.(actuator, coils)}
    >
      <title>
        {`${actuator.name}${actuator.alias ? ` (${actuator.alias})` : ''} — ${actuatorLabel(actuator)}\n` +
          `${actuator.kind === 'double' ? 'Double-solenoid, latching' : 'Spring-return'} · branch ${actuator.branch} · Sequence.xlsx ${actuator.excel}\n` +
          coils
            .map(
              (c) =>
                `coil ${c.index} ${c.index === actuator.coilExtend ? 'extend' : 'retract'} ` +
                `${c.stateAddress}: ${c.state === true ? 'ON' : c.state === false ? 'OFF' : 'UNKNOWN'}`,
            )
            .join('\n') +
          `\n${travel != null ? `Stroke travel ${(travel * 1000).toFixed(1)} mm` : 'No stroke claimed — position known, path not'}` +
          (offset
            ? '\nDRAWN DISPLACED for legibility. In the model this actuator stands ' +
              'on the engrave waypoint, in the same rectangle as MOVE_TO_CV3; ' +
              'the leader line points at its real position.'
            : '') +
          `\n${NO_ROD_FEEDBACK}\n${actuator.note}`}
      </title>

      {offset && (
        <line
          x1={bodyX + mlen(body.w) / 2}
          y1={bodyY + mlen(body.h) / 2}
          x2={actuator.axis === 'x' ? mx(tip0) : mx(lat)}
          y2={actuator.axis === 'x' ? my(lat) : my(tip0)}
          stroke={C.textDim}
          strokeOpacity="0.5"
          strokeWidth="2"
          strokeDasharray="5 6"
        />
      )}

      {track && (
        <line
          {...track}
          stroke={extendOn ? CELL_PALETTE.rod : C.textDim}
          strokeOpacity={extendOn ? 0.75 : 0.3}
          strokeWidth={extendOn ? 8 : 4}
          strokeDasharray="10 10"
          strokeLinecap="round"
        />
      )}

      <rect
        x={bodyX}
        y={bodyY}
        width={mlen(body.w)}
        height={mlen(body.h)}
        rx="5"
        fill={CELL_PALETTE.actuator}
        fillOpacity={anyOn ? 0.85 : 0.45}
        stroke={accent}
        strokeOpacity={anyOn || focused ? 1 : 0.65}
        strokeWidth={anyOn || focused ? 5 : actuator.kind === 'double' ? 3.5 : 2}
        strokeDasharray={
          !actuator.contact ? '7 6' : unknown ? '4 5' : undefined
        }
      />

      <text
        x={labelX}
        y={labelY}
        textAnchor={labelLeft ? 'end' : 'start'}
        fontSize="19"
        fontFamily={MONO}
        fontWeight="600"
        fill={anyOn ? accent : '#d8d8f0'}
        fillOpacity={anyOn ? 1 : 0.8}
      >
        {actuatorLabel(actuator)}
      </text>
    </g>
  )
}

// ---------------------------------------------------------------------------
// sensors
// ---------------------------------------------------------------------------

function Sensor({
  placement,
  live,
  focused,
  onClick,
}: {
  placement: (typeof SENSORS)[number]
  live?: SensorView
  focused: boolean
  onClick?: (s: SensorView) => void
}) {
  const on = live?.value === true
  const unknown = live == null || live.value == null

  return (
    <g
      transform={`translate(${mx(placement.x)}, ${my(placement.y)})`}
      className={onClick && live ? 'cursor-pointer' : undefined}
      onClick={() => live && onClick?.(live)}
    >
      <title>
        {`${placement.id} — ${live?.address ?? 'no tag'}\n` +
          `${on ? 'ACTIVE' : unknown ? 'UNKNOWN — no value' : 'clear'}\n` +
          `${placement.duty}\n` +
          `${placement.guarded ? 'GATES the sequence (P.PROX_GUARD).' : 'Wired and logged; guards no transition.'}\n` +
          `Position [${placement.provenance}]: ${placement.positionNote}`}
      </title>

      {on && (
        <circle r="30" fill={C.run} opacity="0.22" />
      )}

      {/* Outer ring = this sensor can stop the cycle. A shape, not a colour. */}
      {placement.guarded && (
        <circle
          r="24"
          fill="none"
          stroke={on ? C.run : CELL_PALETTE.sensor}
          strokeOpacity={on ? 0.85 : 0.5}
          strokeWidth="2.5"
        />
      )}

      <circle
        r="15"
        fill={on ? C.run : 'none'}
        stroke={on ? C.run : focused ? C.info : unknown ? C.textDim : CELL_PALETTE.sensor}
        strokeWidth={focused ? 5 : 3.5}
        strokeDasharray={unknown ? '5 5' : undefined}
      />

      {unknown && (
        <text
          y="7" fontSize="20" textAnchor="middle" fill={C.textDim}
          fontFamily={MONO} fontWeight="700"
        >
          ?
        </text>
      )}

      <text
        y="-30" fontSize="20" textAnchor="middle"
        fill={on ? C.run : CELL_PALETTE.sensor}
        fillOpacity={on ? 1 : 0.85}
        fontFamily={MONO} fontWeight="700"
      >
        {placement.id}
      </text>
    </g>
  )
}

function Camera({ focused }: { focused: boolean }) {
  return (
    <g transform={`translate(${mx(CAMERA.x)}, ${my(CAMERA.y)})`}>
      <title>{CAMERA.note}</title>
      <rect
        x="-17" y="-17" width="34" height="34" rx="4"
        fill="none"
        stroke={focused ? C.info : CELL_PALETTE.camera}
        strokeWidth={focused ? 5 : 3.5}
      />
      <text
        x="26" y="8" fontSize="20" fontFamily={MONO} fontWeight="700"
        fill={CELL_PALETTE.camera}
      >
        CAM
      </text>
    </g>
  )
}

// ---------------------------------------------------------------------------
// workpiece
// ---------------------------------------------------------------------------

function Workpiece({
  x,
  y,
  label,
  confirmed,
  engraved,
  title,
}: {
  x: number
  y: number
  label: string
  confirmed: boolean
  engraved: boolean
  title: string
}) {
  const colour = engraved ? CELL_PALETTE.blockDone : CELL_PALETTE.block
  const w = mlen(BLOCK.l)
  const h = mlen(BLOCK.w)
  return (
    <g transform={`translate(${mx(x)}, ${my(y)})`}>
      <title>{title}</title>
      <rect
        x={-w / 2} y={-h / 2} width={w} height={h} rx="4"
        fill={colour}
        fillOpacity={confirmed ? 0.7 : 0.12}
        stroke={colour}
        strokeWidth="4"
        strokeDasharray={confirmed ? undefined : '12 9'}
      />
      {/* The token is 100 mm square at this scale, so its id fits inside it.
          Keeping the annotation within the block's own footprint matters: the
          workpiece sits ON a sensor at most of its stations, and a label hung
          above or below it lands on that sensor's label. */}
      <text
        y="6" fontSize="17" textAnchor="middle"
        fill={confirmed ? '#070a0f' : colour}
        fontFamily={MONO} fontWeight="700"
      >
        {label}
      </text>
      <text
        y="68" fontSize="15" textAnchor="middle" fill={colour}
        fontFamily={SANS} letterSpacing="1.2"
      >
        {confirmed ? 'CONFIRMED' : 'ESTIMATED'}
      </text>
    </g>
  )
}

// ---------------------------------------------------------------------------
// legend
// ---------------------------------------------------------------------------

function Legend() {
  return (
    <div className="mt-2 grid gap-x-5 gap-y-1.5 text-xs leading-snug text-ink-500 sm:grid-cols-2 xl:grid-cols-4">
      <LegendRow swatch={<SensorSwatch guarded />}>
        Double ring &mdash; this sensor gates a sequence transition
        (<code className="font-mono">P.PROX_GUARD</code>).
      </LegendRow>
      <LegendRow swatch={<SensorSwatch />}>
        Single ring &mdash; wired and logged, but guards nothing. Dashed = no
        value; never drawn as OFF.
      </LegendRow>
      <LegendRow
        swatch={
          <span
            className="inline-block h-3 w-5 rounded-sm border-2"
            style={{ borderColor: CELL_PALETTE.actuatorDouble }}
          />
        }
      >
        Gold edge &mdash; double-solenoid, latching. Both coils off means the
        spool <em>holds</em>, not retracts.
      </LegendRow>
      <LegendRow
        swatch={
          <span
            className="inline-block h-3 w-5 rounded-sm border-2 border-dotted"
            style={{ borderColor: CELL_PALETTE.actuator }}
          />
        }
      >
        Dotted body &mdash; real cylinder whose path this plan cannot express
        (CYL&nbsp;B).
      </LegendRow>
      <LegendRow
        swatch={
          <span className="inline-block h-0.5 w-5 rounded bg-ink-500 opacity-60" />
        }
      >
        Dashed track &mdash; sourced stroke geometry. No rod is drawn on it:
        there is no reed switch on any actuator.
      </LegendRow>
      <LegendRow
        swatch={<span className="inline-block h-2 w-5 rounded-sm bg-state-run/70" />}
      >
        Belt flows only when the run coil is on <em>and</em> the encoder reports
        motion.
      </LegendRow>
      <LegendRow
        swatch={
          <span
            className="inline-block h-3 w-3 rounded-sm border-2"
            style={{ borderColor: CELL_PALETTE.block }}
          />
        }
      >
        Solid workpiece = a sensor confirms it. Dashed = inferred from the
        sequence only.
      </LegendRow>
      <LegendRow swatch={<span className="inline-block h-0.5 w-5 bg-ink-500" />}>
        Drawn to scale, 1&nbsp;:&nbsp;1 with the simulation geometry
        (<code className="font-mono">P.SCALE&nbsp;=&nbsp;0.10</code>).
      </LegendRow>
    </div>
  )
}

function SensorSwatch({ guarded }: { guarded?: boolean }) {
  return (
    <span className="relative inline-flex h-4 w-4 items-center justify-center">
      {guarded && (
        <span
          className="absolute inset-0 rounded-full border"
          style={{ borderColor: CELL_PALETTE.sensor, opacity: 0.55 }}
        />
      )}
      <span
        className="h-2 w-2 rounded-full border-2"
        style={{ borderColor: CELL_PALETTE.sensor }}
      />
    </span>
  )
}

function LegendRow({
  swatch,
  children,
}: {
  swatch: ReactNode
  children: ReactNode
}) {
  return (
    <div className="flex items-start gap-2">
      <span className="mt-0.5 shrink-0">{swatch}</span>
      <span className="min-w-0">{children}</span>
    </div>
  )
}

// ---------------------------------------------------------------------------
// the status line and footer
// ---------------------------------------------------------------------------

/**
 * `visualize_factory.m` prints a status line and a footer under the figure:
 *
 *     Status: %s   (Excel step %s)
 *     t = %6.2f s   block = (%.3f, %.3f) m   |v| = %.3f m/s
 *     receiver = %.2f bar   base z = %.1f mm
 *
 * The composition is kept because it is the one an operator familiar with the
 * simulation already reads. What is NOT kept is the pretence that all six
 * figures exist on the real machine. Of them, exactly one -- receiver pressure
 * -- has a PLC tag. Block position, block velocity and base height are computed
 * inside the physics model and have no address anywhere in `Tag_list (1).xlsx`,
 * so they read "no tag" rather than a number.
 *
 * Cycle elapsed replaces the simulation's `t`: it is a real backend
 * measurement, and it is labelled as cycle elapsed rather than borrowing the
 * simulation's clock.
 */
export function CellStatusLine() {
  const sequence = useMachine(selectSequence)
  const safety = useMachine(selectSafety)
  const machine = useMachine((s) => s.snapshot?.machine)
  const conveyors = useMachine(selectConveyors)

  const step = sequence?.step
  const status = step ? step.name : 'No step inferred yet'
  const excel = step?.excelRef && step.excelRef !== '-' ? step.excelRef : null

  const beltFb = (conveyors ?? [])
    .map((c) => c.feedbackVelocity)
    .filter((v): v is number => v != null && Math.abs(v) > 1e-6)
  const beltSpeed = beltFb.length ? Math.max(...beltFb.map(Math.abs)) : null

  return (
    <div className="space-y-2">
      <div className="flex flex-wrap items-baseline gap-x-3 gap-y-1 rounded-lg border border-panel-700 bg-panel-900 px-3 py-2">
        <span className="text-xs font-semibold uppercase tracking-[0.16em] text-ink-500">
          Status
        </span>
        <span className="font-mono text-sm font-bold text-state-warn">
          {status}
        </span>
        {excel && (
          <span className="font-mono text-xs text-ink-500">
            (Sequencing row {excel})
          </span>
        )}
        {sequence?.confidence !== 'inferred' && (
          <span className="ml-auto rounded border border-panel-600 px-1.5 py-px text-xs uppercase tracking-wider text-ink-500">
            not yet confirmed by a sensor
          </span>
        )}
      </div>

      <dl className="grid grid-cols-2 gap-x-4 gap-y-2 rounded-lg border border-panel-700 bg-panel-900 px-3 py-2 sm:grid-cols-3 xl:grid-cols-5">
        <FooterStat
          label="Cycle elapsed"
          value={machine?.cycleElapsed != null ? `${machine.cycleElapsed.toFixed(2)} s` : null}
          hint="Measured by the backend from cycle start. The simulation's own t is not a machine signal."
        />
        <FooterStat
          label="Block position"
          value={null}
          hint="No tag. The workpiece coordinate exists only inside the physics model; the cell has presence detectors, not encoders on the part."
        />
        <FooterStat
          label="Belt speed"
          value={beltSpeed != null ? `${num(beltSpeed, 3)}` : null}
          hint="Highest non-zero conveyor encoder feedback. This is the belt, not the block: block velocity has no tag."
        />
        <FooterStat
          label="Receiver"
          value={safety?.pressureBar != null ? `${safety.pressureBar.toFixed(2)} bar` : null}
          hint="The one footer figure from the MATLAB view that has a real PLC address."
        />
        <FooterStat
          label="Base z"
          value={null}
          hint="No height transducer. The engraving platform has two limit switches only, shown on the plan as UP / DOWN / IN TRANSIT."
        />
      </dl>
    </div>
  )
}

function FooterStat({
  label,
  value,
  hint,
}: {
  label: string
  value: string | null
  hint: string
}) {
  return (
    <div className="min-w-0" title={hint}>
      <dt className="truncate text-xs uppercase tracking-[0.14em] text-ink-500">
        {label}
      </dt>
      <dd
        className={classNames(
          'mt-0.5 truncate font-mono text-sm tabular-nums',
          value ? 'text-ink-200' : 'text-ink-500',
        )}
      >
        {value ?? 'no tag'}
      </dd>
    </div>
  )
}

// ---------------------------------------------------------------------------
// coil roll-up, used by the manual page and the twin page
// ---------------------------------------------------------------------------

/** Group the snapshot's thirteen flat coils under the eleven actuators. */
export function groupCoils(actuators: ActuatorView[] | undefined) {
  const byIndex = new Map<number, ActuatorView>()
  actuators?.forEach((a) => byIndex.set(a.index, a))
  const grouped = ACTUATORS.map((a) => ({
    actuator: a,
    extend: byIndex.get(a.coilExtend),
    retract: a.coilRetract > 0 ? byIndex.get(a.coilRetract) : undefined,
  }))
  // A coil the snapshot publishes that this model does not claim would be a
  // real discrepancy, not a rendering detail, so it is surfaced rather than
  // dropped.
  const unmapped = (actuators ?? []).filter((a) => !COIL_MAP[a.index])
  return { grouped, unmapped }
}
