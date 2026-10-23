/**
 * SUPERSEDED 2026-09-03 — DO NOT USE. Nothing imports this component.
 *
 * Replaced by `components/cell/CellPlan.tsx`, which draws the same live signals
 * on the cell's real metric geometry rather than on the topological layout in
 * `./layout.ts` -- see the note at the top of that file for what was wrong with
 * it. The honest behaviours below were carried over intact: belts flow only on
 * coil AND encoder, the workpiece is a dashed ghost where nothing confirms it,
 * and unknown is a dashed outline rather than OFF.
 *
 * ---------------------------------------------------------------------------
 *
 * The live factory schematic -- the visual centrepiece.
 *
 * WHAT IT SHOWS AND HOW HONESTLY
 * ------------------------------
 * * Sensors illuminate the moment their PLC bit rises. Their positions are
 *   drawn only where the Sequencing sheet supports them (see layout.ts);
 *   unplaceable sensors go in a labelled tray instead of being guessed onto
 *   the belt.
 *
 * * The workpiece is drawn **solid** at a station a physical sensor confirmed,
 *   and as a **dashed ghost** anywhere its position is only inferred. There is
 *   no interpolation between sensors: the cell has presence detectors, not
 *   encoders on the part, so a smoothly gliding block would be an animation of
 *   something nobody measured.
 *
 * * Belt hatching animates only while the run coil is energised AND the encoder
 *   reports motion. A belt commanded on but not turning is drawn stopped and
 *   flagged -- which is exactly the conveyor-2 symptom in the Errors sheet.
 */

import { useMemo } from 'react'
import { AlertTriangle } from 'lucide-react'
import {
  selectActuators, selectConveyors, selectInventory, selectSensors,
  selectStale, useMachine,
} from '../../stores/machineStore'
import type { SensorView, Tri } from '../../types'
import { classNames } from '../../utils/format'
import {
  BELTS, CANVAS, PRODUCT_PATH, SENSORS, STATIONS, UNASSIGNED_SENSORS,
} from './layout'

const C = {
  edge: '#283348',
  edgeSoft: '#1d2534',
  surface: '#10151f',
  surfaceHi: '#151b27',
  text: '#a9b6c9',
  textDim: '#5a6980',
  run: '#22c55e',
  warn: '#f59e0b',
  fault: '#ef4444',
  info: '#38bdf8',
  twin: '#a78bfa',
}

export function FactorySchematic({
  onSensorClick,
}: {
  onSensorClick?: (sensor: SensorView) => void
}) {
  const sensors = useMachine(selectSensors)
  const conveyors = useMachine(selectConveyors)
  const actuators = useMachine(selectActuators)
  const inventory = useMachine(selectInventory)
  const stale = useMachine(selectStale)

  const byRole = useMemo(() => {
    const map = new Map<string, SensorView>()
    sensors?.forEach((s) => map.set(s.role, s))
    return map
  }, [sensors])

  const token = inventory?.activeToken ?? null
  const tokenPoint = token
    ? PRODUCT_PATH.find((p) => p.station === token.station) ?? PRODUCT_PATH[0]
    : null
  const confirmed = token?.positioning === 'CONFIRMED'

  return (
    <div className="relative">
      <svg
        viewBox={`0 0 ${CANVAS.w} ${CANVAS.h}`}
        className={classNames(
          'w-full rounded-lg border border-panel-700 bg-panel-950',
          stale && 'opacity-60 saturate-50',
        )}
        role="img"
        aria-label="Live factory schematic"
      >
        <defs>
          <pattern id="beltHatch" width="12" height="12" patternTransform="rotate(45)"
                   patternUnits="userSpaceOnUse">
            <line x1="0" y1="0" x2="0" y2="12" stroke={C.edge} strokeWidth="5" />
          </pattern>
          <filter id="lampGlow" x="-140%" y="-140%" width="380%" height="380%">
            <feGaussianBlur stdDeviation="3.4" result="b" />
            <feMerge>
              <feMergeNode in="b" />
              <feMergeNode in="SourceGraphic" />
            </feMerge>
          </filter>
        </defs>

        {/* ---- transfer links (drawn under everything) ---- */}
        <g stroke={C.edgeSoft} strokeWidth="2" strokeDasharray="3 4" fill="none">
          <path d="M216 74 L216 96" />
          <path d="M400 130 L400 216" />
          <path d="M418 233 L470 233" />
          <path d="M620 250 L620 336 L590 336" />
          <path d="M840 353 L872 353" />
          <path d="M142 165 L168 165 L168 113" />
        </g>

        {/* ---- stations ---- */}
        {STATIONS.map((s) => (
          <Station key={s.id} box={s} sensors={byRole} />
        ))}

        {/* ---- belts ---- */}
        {BELTS.map((belt) => {
          const live = conveyors?.find((c) => c.index === belt.index)
          const commandedOn = live?.running === true
          const moving =
            commandedOn &&
            live?.feedbackVelocity != null &&
            Math.abs(live.feedbackVelocity) > 1e-6
          const mismatch = commandedOn && !moving

          return (
            <g key={belt.index}>
              <rect
                x={belt.x} y={belt.y} width={belt.w} height={belt.h} rx="6"
                fill={C.surfaceHi}
                stroke={mismatch ? C.fault : commandedOn ? C.run : C.edge}
                strokeWidth={commandedOn ? 1.8 : 1.2}
              />
              <rect
                x={belt.x + 3} y={belt.y + 3}
                width={belt.w - 6} height={belt.h - 6} rx="4"
                fill="url(#beltHatch)"
                opacity={moving ? 0.9 : 0.32}
                className={moving ? 'animate-beltFlow' : undefined}
                style={{ strokeDasharray: 12 }}
              />
              <text
                x={belt.x + 8} y={belt.y - 7}
                fontSize="10.5" fill={C.text}
                fontFamily="Inter, system-ui" letterSpacing="0.7"
              >
                {belt.label.toUpperCase()}
              </text>
              <text
                x={belt.x + belt.w} y={belt.y - 7}
                fontSize="10" textAnchor="end"
                fill={mismatch ? C.fault : moving ? C.run : C.textDim}
                fontFamily="JetBrains Mono, monospace"
              >
                {live?.feedbackVelocity != null
                  ? `${live.feedbackVelocity.toFixed(2)} fb`
                  : 'no fb'}
                {live?.commandedVelocity != null
                  ? ` / ${live.commandedVelocity.toFixed(2)} cmd`
                  : ''}
              </text>
              {mismatch && (
                <g transform={`translate(${belt.x + belt.w / 2 - 8}, ${belt.y + 8})`}>
                  <title>
                    Run coil energised but encoder feedback is zero. See Diagnostics.
                  </title>
                  <circle cx="8" cy="9" r="10" fill={C.fault} opacity="0.18" />
                  <text x="8" y="13" fontSize="13" textAnchor="middle" fill={C.fault}>
                    !
                  </text>
                </g>
              )}
            </g>
          )
        })}

        {/* ---- sensors ---- */}
        {SENSORS.map((placement) => {
          const live = byRole.get(placement.role)
          const on = live?.value === true
          const unknown = live?.value == null
          return (
            <g
              key={placement.role}
              transform={`translate(${placement.x}, ${placement.y})`}
              className={onSensorClick ? 'cursor-pointer' : undefined}
              onClick={() => live && onSensorClick?.(live)}
            >
              <title>
                {`${placement.label} — ${live?.address ?? 'no tag'}\n` +
                  `${on ? 'ACTIVE' : unknown ? 'UNKNOWN' : 'clear'}\n` +
                  `Placement: ${placement.source}`}
              </title>
              {on && (
                <circle r="13" fill={C.run} opacity="0.2" />
              )}
              <circle
                r="7"
                fill={on ? C.run : C.surface}
                stroke={on ? C.run : unknown ? C.textDim : C.edge}
                strokeWidth="1.6"
                strokeDasharray={unknown ? '2 2' : undefined}
              />
              <text
                y="-13" fontSize="9.5" textAnchor="middle"
                fill={on ? C.run : C.textDim}
                fontFamily="JetBrains Mono, monospace" fontWeight="600"
              >
                {placement.label}
              </text>
            </g>
          )
        })}

        {/* ---- the workpiece ---- */}
        {tokenPoint && (
          <g transform={`translate(${tokenPoint.x}, ${tokenPoint.y})`}>
            <title>
              {`${token?.tokenId} — ${token?.stationLabel}\n` +
                `${confirmed ? 'Position CONFIRMED by a sensor' : 'Position ESTIMATED — no sensor confirmation'}\n` +
                `${token?.lastEvent ?? ''}`}
            </title>
            <rect
              x="-13" y="-10" width="26" height="20" rx="3"
              fill={confirmed ? 'rgba(56,189,248,0.22)' : 'transparent'}
              stroke={confirmed ? C.info : C.twin}
              strokeWidth="2"
              strokeDasharray={confirmed ? undefined : '4 3'}
            />
            <text
              y="-16" fontSize="9.5" textAnchor="middle"
              fill={confirmed ? C.info : C.twin}
              fontFamily="JetBrains Mono, monospace" fontWeight="700"
            >
              {token?.tokenId}
            </text>
            <text
              y="23" fontSize="8" textAnchor="middle"
              fill={confirmed ? C.info : C.twin}
              fontFamily="Inter, system-ui" letterSpacing="0.6"
            >
              {confirmed ? 'CONFIRMED' : 'ESTIMATED'}
            </text>
          </g>
        )}

        {/* ---- valve tray ---- */}
        <g transform="translate(24, 300)">
          <text fontSize="10" fill={C.textDim} fontFamily="Inter, system-ui"
                letterSpacing="0.8">
            SOLENOID VALVES — station mapping not recorded in any source
          </text>
          {(actuators ?? []).map((a, i) => {
            const on = a.state === true
            const unknown = a.state == null
            const col = i % 7
            const row = Math.floor(i / 7)
            return (
              <g key={a.index} transform={`translate(${col * 44}, ${14 + row * 30})`}>
                <title>
                  {`${a.label} — ${a.stateAddress}\n` +
                    `Output coil: ${on ? 'ON' : unknown ? 'UNKNOWN' : 'OFF'}\n` +
                    `Manual command bit: ${a.manualCommand === true ? 'ON' : a.manualCommand === false ? 'OFF' : 'UNKNOWN'}\n` +
                    a.feedbackNote}
                </title>
                <rect
                  width="38" height="22" rx="4"
                  fill={on ? 'rgba(34,197,94,0.18)' : C.surface}
                  stroke={on ? C.run : unknown ? C.textDim : C.edge}
                  strokeWidth="1.3"
                  strokeDasharray={unknown ? '2 2' : undefined}
                />
                <text
                  x="19" y="15" fontSize="10" textAnchor="middle"
                  fill={on ? C.run : C.textDim}
                  fontFamily="JetBrains Mono, monospace" fontWeight="600"
                >
                  {a.index}
                </text>
                {a.manualCommand === true && (
                  <circle cx="34" cy="4" r="2.6" fill={C.info}>
                    <title>Manual command bit is set for this valve</title>
                  </circle>
                )}
              </g>
            )
          })}
        </g>

        {/* ---- unassigned sensors tray ---- */}
        <g transform="translate(360, 300)">
          <text fontSize="10" fill={C.textDim} fontFamily="Inter, system-ui"
                letterSpacing="0.8">
            UNPLACED SENSORS — no station recorded
          </text>
          {UNASSIGNED_SENSORS.map((u, i) => {
            const live = byRole.get(u.role)
            const on = live?.value === true
            return (
              <g key={u.role} transform={`translate(${i * 38}, 14)`}>
                <title>{`${u.label} — ${live?.address ?? 'no tag'}\n${u.source}`}</title>
                <rect
                  width="32" height="22" rx="4"
                  fill={on ? 'rgba(34,197,94,0.18)' : C.surface}
                  stroke={on ? C.run : C.edge}
                  strokeWidth="1.3" strokeDasharray="3 2"
                />
                <text
                  x="16" y="15" fontSize="9" textAnchor="middle"
                  fill={on ? C.run : C.textDim}
                  fontFamily="JetBrains Mono, monospace"
                >
                  {u.label}
                </text>
              </g>
            )
          })}
        </g>
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
    </div>
  )
}

// ---------------------------------------------------------------------------

function Station({
  box,
  sensors,
}: {
  box: (typeof STATIONS)[number]
  sensors: Map<string, SensorView>
}) {
  const inventory = useMachine(selectInventory)

  // The engraving box reflects the plate limit switches, which ARE documented.
  let accent = C.edge
  let status: string | null = null
  if (box.kind === 'engraving') {
    const up = sensors.get('sensor.pgm_up_limit')?.value as Tri
    const low = sensors.get('sensor.pgm_low_limit')?.value as Tri
    if (up === true) {
      accent = C.warn
      status = 'PLATE UP'
    } else if (low === true) {
      accent = C.run
      status = 'PLATE DOWN'
    } else {
      accent = C.textDim
      status = 'PLATE IN TRANSIT'
    }
  }

  return (
    <g>
      <rect
        x={box.x} y={box.y} width={box.w} height={box.h} rx="8"
        fill={C.surface} stroke={accent} strokeWidth="1.4"
      />
      <text
        x={box.x + 8} y={box.y + 16} fontSize="10" fill={C.text}
        fontFamily="Inter, system-ui" letterSpacing="0.6"
      >
        {box.label.toUpperCase()}
      </text>
      {status && (
        <text
          x={box.x + 8} y={box.y + 32} fontSize="10.5" fill={accent}
          fontFamily="JetBrains Mono, monospace" fontWeight="700"
        >
          {status}
        </text>
      )}
      {box.kind === 'magazine' &&
        (inventory?.magazines ?? []).map((m, i) => {
          const known = m.cameraCount != null
          return (
            <g key={m.index} transform={`translate(${box.x + 10}, ${box.y + 28 + i * 34})`}>
              <title>
                {`${m.label}\nCamera count: ${known ? m.cameraCount : 'camera offline'}\n` +
                  `PLC: ${m.plcEmpty === true ? 'EMPTY' : m.plcLow === true ? 'LOW' : m.plcOk === true ? 'OK' : 'unknown'}` +
                  (m.mismatch ? `\nMISMATCH: ${m.mismatch}` : '')}
              </title>
              <rect
                width="98" height="26" rx="4"
                fill={C.surfaceHi}
                stroke={m.mismatch ? C.warn : m.plcEmpty === true ? C.fault : C.edge}
                strokeWidth="1.2"
              />
              <text x="7" y="17" fontSize="9.5" fill={C.textDim}
                    fontFamily="Inter, system-ui">
                M{m.index}
              </text>
              <text
                x="91" y="17" fontSize="11" textAnchor="end"
                fill={known ? C.text : C.textDim}
                fontFamily="JetBrains Mono, monospace" fontWeight="600"
              >
                {known ? m.cameraCount : '--'}
              </text>
              {m.mismatch && (
                <circle cx="52" cy="6" r="2.6" fill={C.warn} />
              )}
            </g>
          )
        })}
    </g>
  )
}
