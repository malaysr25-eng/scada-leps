/**
 * The 3-D cell — assembled from `parts.tsx`, bound to the same store the rest
 * of the HMI uses.
 *
 * NO NEW STATE PATH
 * -----------------
 * This reads `useMachine` and the same semantic roles as the 2-D schematic. It
 * introduces no tag mapping of its own, so it cannot drift from the rest of the
 * application or show something the diagnostics disagree with.
 *
 * WHAT IS ANIMATED, AND FROM WHAT
 * -------------------------------
 * | part | driven by | confirmed? |
 * |---|---|---|
 * | belt scroll | `conveyor.N.velocity_fb` (encoder) | yes |
 * | belt run lamp | `conveyor.N.running` (output coil) | yes |
 * | valve indicators | `valve.N.state` (output image) | yes |
 * | proximity lamps | `sensor.proximity.N` | yes |
 * | engraving lift | both plate limit switches | yes |
 * | magazine contents | camera counts + `Comp_Status` | yes |
 * | PLC status LED | link state | yes |
 * | E-stop | `safety.emergencyActive` | yes |
 * | pressure gauge | `pressure.value` | yes |
 * | **cylinder rods** | **nothing — no actuator-to-valve map exists** | no |
 *
 * The last row is the important one. Rather than guessing that actuator N is
 * solenoid N, cylinders render idle and are marked unmapped. See
 * docs/TWIN_COMPONENT_MAPPING.md §5.
 */

import { Suspense, useMemo } from 'react'
import { Canvas } from '@react-three/fiber'
import {
  ContactShadows, Environment, Grid, Html, OrbitControls, PerspectiveCamera,
} from '@react-three/drei'
import { useMachine } from '../../stores/machineStore'
import {
  AirReceiver, BasePanels, Conveyor, Desk, ElectricalCabinet, EngravingStation,
  EStop, Frame, Magazine, OutputBin, PneumaticCylinder, PneumaticTube,
  ProximitySensor, ValveManifold, Workpiece,
} from './parts'
import {
  CABINET, CELL, CONVEYORS, CYLINDERS, SENSORS, TABLE_HEIGHT, TUBE_RUNS,
} from './machineLayout'

export interface Selection {
  id: string
  label: string
  kind: string
  confidence: string
  note?: string
  binding?: string
  value?: string
}

/**
 * Where the workpiece token is drawn, per station.
 *
 * Sensor-confirmed stations map to a real position. Between them the token is
 * drawn at the last confirmed place with a ghost halo — there is no encoder on
 * the part, so interpolating a smooth glide would be animating something nobody
 * measures.
 */
const TOKEN_POSITIONS: Record<string, [number, number, number]> = {
  magazine: [0.46, TABLE_HEIGHT + 0.12, 0.12],
  feeder: [0.30, TABLE_HEIGHT + 0.05, 0.16],
  conveyor1: [0.32, TABLE_HEIGHT + 0.05, 0.30],
  conveyor1_end: [1.02, TABLE_HEIGHT + 0.05, 0.30],
  conveyor2: [1.06, TABLE_HEIGHT + 0.05, 0.90],
  engraving: [1.37, TABLE_HEIGHT + 0.09, 1.17],
  conveyor3: [2.05, TABLE_HEIGHT + 0.05, 1.14],
  bin: [2.52, TABLE_HEIGHT + 0.06, 1.30],
}

export function MachineScene({
  onSelect,
  showTubing = true,
  showSurroundings = true,
}: {
  onSelect: (s: Selection | null) => void
  showTubing?: boolean
  showSurroundings?: boolean
}) {
  const snapshot = useMachine((s) => s.snapshot)
  const stale = useMachine((s) => s.snapshot?.connection.stale ?? true)

  const roles = useMemo(() => {
    const conveyors = snapshot?.conveyors ?? []
    const actuators = snapshot?.actuators ?? []
    const sensors = snapshot?.sensors ?? []
    return {
      conveyor: (i: number) => conveyors.find((c) => c.index === i),
      valve: (i: number) => actuators.find((a) => a.index === i),
      sensor: (role: string) => sensors.find((s) => s.role === role),
    }
  }, [snapshot])

  const inventory = snapshot?.inventory
  const token = inventory?.activeToken ?? null
  const safety = snapshot?.safety

  return (
    <Canvas
      shadows
      dpr={[1, 2]}
      gl={{ antialias: true, powerPreference: 'high-performance' }}
      style={{ background: '#070a0f' }}
    >
      <PerspectiveCamera makeDefault position={[3.1, 2.3, 3.0]} fov={38} />
      <OrbitControls
        makeDefault
        target={[1.05, TABLE_HEIGHT * 0.75, 0.75]}
        minDistance={0.9}
        maxDistance={9}
        maxPolarAngle={Math.PI / 2.05}
        enableDamping
        dampingFactor={0.08}
      />

      {/* Lab-ish lighting: one key from above-front, cool fill, warm rim, so
          the extrusion reads as metal and the tinted acrylics read as tinted. */}
      <ambientLight intensity={0.55} />
      <directionalLight
        position={[2.6, 3.4, 2.4]}
        intensity={1.5}
        castShadow
        shadow-mapSize={[2048, 2048]}
        shadow-camera-left={-3}
        shadow-camera-right={3}
        shadow-camera-top={3}
        shadow-camera-bottom={-3}
      />
      <directionalLight position={[-2.2, 1.8, -1.6]} intensity={0.4} color="#9fc4e8" />
      <pointLight position={[1.2, 1.5, 2.4]} intensity={0.35} color="#ffd9a0" />
      <Suspense fallback={null}>
        <Environment preset="warehouse" />
      </Suspense>

      {/* floor */}
      <mesh
        position={[CELL.width / 2, -0.001, CELL.depth / 2]}
        rotation={[-Math.PI / 2, 0, 0]}
        receiveShadow
      >
        <planeGeometry args={[14, 14]} />
        <meshStandardMaterial color="#9aa3ab" roughness={0.94} />
      </mesh>
      <Grid
        position={[CELL.width / 2, 0.002, CELL.depth / 2]}
        args={[14, 14]}
        cellSize={0.25}
        cellColor="#6d757d"
        sectionSize={1}
        sectionColor="#525a62"
        fadeDistance={11}
        infiniteGrid={false}
      />
      <ContactShadows
        position={[CELL.width / 2, 0.004, CELL.depth / 2]}
        opacity={0.45}
        scale={7}
        blur={2.2}
        far={2.4}
      />

      {/* Everything dims when the data is stale, so an out-of-date model is
          visibly out of date rather than quietly wrong. */}
      <group>
        <Frame />
        <BasePanels />

        {CONVEYORS.map((placement) => {
          const live = roles.conveyor(placement.index)
          const running = live?.running ?? null
          const velocity = live?.feedbackVelocity ?? null
          const mismatch =
            running === true &&
            (velocity === null || Math.abs(velocity) < 1e-6)

          return (
            <Conveyor
              key={placement.id}
              placement={placement}
              running={running}
              velocity={velocity}
              mismatch={mismatch}
              onSelect={() =>
                onSelect({
                  id: placement.id,
                  label: placement.label,
                  kind: 'Conveyor',
                  confidence: placement.confidence,
                  note: placement.note,
                  binding: `conveyor.${placement.index}.running + .velocity_fb`,
                  value: `run coil ${running === true ? 'ON' : running === false ? 'OFF' : 'N/A'}, ` +
                    `feedback ${velocity !== null ? velocity.toFixed(3) : 'N/A'}` +
                    (mismatch ? '  — MISMATCH: commanded on, encoder zero' : ''),
                })
              }
            />
          )
        })}

        <Magazine
          counts={(inventory?.magazines ?? []).map((m) => m.cameraCount)}
          empties={(inventory?.magazines ?? []).map((m) => m.plcEmpty)}
          onSelect={() =>
            onSelect({
              id: 'magazine',
              label: 'Feed magazine',
              kind: 'Storage',
              confidence: 'PHOTO',
              note:
                'Transparent acrylic, five compartments, plywood top. Block '
                + 'counts come from the camera; the red edge is the PLC\'s own '
                + 'Comp_Status Empty bit. Both are shown because they can '
                + 'disagree.',
              binding: 'inventory.magazines[].cameraCount / .plcEmpty',
              value: (inventory?.magazines ?? [])
                .map((m) => `M${m.index}=${m.cameraCount ?? '?'}`)
                .join('  '),
            })
          }
        />

        {CYLINDERS.map((placement) => {
          const valveIndex = placement.valveRole
            ? Number(placement.valveRole.split('.')[1])
            : null
          const live = valveIndex ? roles.valve(valveIndex) : undefined
          return (
            <PneumaticCylinder
              key={placement.id}
              placement={placement}
              extended={live?.state ?? null}
              onSelect={() =>
                onSelect({
                  id: placement.id,
                  label: placement.label,
                  kind: 'Pneumatic cylinder',
                  confidence: placement.confidence,
                  note: placement.note,
                  binding: placement.valveRole ?? 'NONE — unmapped',
                  value: placement.valveRole
                    ? `coil ${live?.state === true ? 'ON' : 'OFF'}`
                    : 'No actuator-to-valve mapping exists in any supplied '
                      + 'source, so this cylinder is not animated. Energising '
                      + 'one valve at a time in Manual mode would establish it.',
                })
              }
            />
          )
        })}

        <EngravingStation
          plateUp={roles.sensor('sensor.pgm_up_limit')?.value ?? null}
          plateLow={roles.sensor('sensor.pgm_low_limit')?.value ?? null}
          engraving={snapshot?.sequence.awaitingOperator ?? false}
          onSelect={() => {
            const up = roles.sensor('sensor.pgm_up_limit')?.value
            const low = roles.sensor('sensor.pgm_low_limit')?.value
            onSelect({
              id: 'engraver',
              label: 'Laser engraving station',
              kind: 'Station',
              confidence: 'PHOTO',
              note:
                'Red/orange tinted enclosure on a raised platform. The lift '
                + 'shows three states: UP, DOWN, and IN TRANSIT when neither '
                + 'limit is made — the third is the stuck-plate condition from '
                + 'the Errors sheet.',
              binding: 'sensor.pgm_up_limit / sensor.pgm_low_limit',
              value:
                up === true ? 'PLATE UP'
                  : low === true ? 'PLATE DOWN'
                    : 'IN TRANSIT (neither limit made)',
            })
          }}
        />

        <ValveManifold
          valves={Array.from({ length: 13 }, (_, i) => roles.valve(i + 1)?.state ?? null)}
          onSelect={() =>
            onSelect({
              id: 'valve_manifold',
              label: 'Solenoid valve manifold',
              kind: 'Pneumatics',
              confidence: 'APPROX',
              note:
                'A bank of solenoid bodies is visible in the side view, but no '
                + 'photograph lets the individual valves be numbered. Indicators '
                + 'follow the real output-image bits in tag order.',
              binding: 'valve.1..13.state',
              value: `${
                Array.from({ length: 13 }, (_, i) => roles.valve(i + 1)?.state)
                  .filter((v) => v === true).length
              } of 13 energised`,
            })
          }
        />

        {SENSORS.map((s) => {
          const live = roles.sensor(s.role)
          return (
            <ProximitySensor
              key={s.id}
              position={s.position}
              active={live?.value ?? null}
              onSelect={() =>
                onSelect({
                  id: s.id,
                  label: s.label,
                  kind: 'Proximity sensor',
                  confidence: s.confidence,
                  note: s.note,
                  binding: s.role,
                  value: `${
                    live?.value === true ? 'ACTIVE'
                      : live?.value === false ? 'clear' : 'unknown'
                  } · ${live?.address ?? 'no tag'} · ${live?.transitions ?? 0} transitions`,
                })
              }
            />
          )
        })}

        <OutputBin contents={inventory?.completedTokens.length ?? 0} />
        <EStop active={safety?.emergencyActive === true} />

        {token && TOKEN_POSITIONS[token.station] && (
          <Workpiece
            position={TOKEN_POSITIONS[token.station]}
            confirmed={token.positioning === 'CONFIRMED'}
          />
        )}

        {showTubing &&
          TUBE_RUNS.map((run) => (
            <PneumaticTube key={run.id} points={run.points} />
          ))}

        {showSurroundings && (
          <>
            <ElectricalCabinet
              plcConnected={
                snapshot?.connection.plc === 'CONNECTED' ||
                snapshot?.connection.plc === 'SIMULATED'
              }
            />
            <AirReceiver pressure={safety?.pressureBar ?? null} />
            <Desk />
          </>
        )}

        {/* Station labels, billboarded so they stay legible from any angle. */}
        <StationLabel position={[0.46, TABLE_HEIGHT + 0.40, 0.12]} text="MAGAZINE" />
        <StationLabel position={[1.37, TABLE_HEIGHT + 0.46, 1.17]} text="LASER ENGRAVER" />
        <StationLabel
          position={[CABINET.position[0], CABINET.baseHeight + 0.72, CABINET.position[2]]}
          text="CONTROL CABINET"
        />
        <StationLabel position={[2.52, TABLE_HEIGHT + 0.26, 1.30]} text="OUTPUT BIN" />
      </group>

      {stale && (
        <Html center position={[CELL.width / 2, TABLE_HEIGHT + 0.9, CELL.depth / 2]}>
          <div className="whitespace-nowrap rounded-lg border border-state-warn/60 bg-panel-950/90 px-3 py-1.5 text-[11px] font-bold uppercase tracking-wider text-state-warn">
            Stale — last known values
          </div>
        </Html>
      )}
    </Canvas>
  )
}

function StationLabel({
  position,
  text,
}: {
  position: [number, number, number]
  text: string
}) {
  return (
    <Html center position={position} distanceFactor={5} occlude>
      <div className="pointer-events-none select-none whitespace-nowrap rounded border border-panel-600/70 bg-panel-950/75 px-1.5 py-0.5 text-[9px] font-semibold uppercase tracking-[0.14em] text-ink-300">
        {text}
      </div>
    </Html>
  )
}
