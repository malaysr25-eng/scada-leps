/**
 * The physical components of the cell, as individual 3-D parts.
 *
 * COMPONENT-BASED, NOT ONE MESH
 * -----------------------------
 * Each station is its own component reading its own slice of state. That is
 * what lets a valve animate without re-rendering the frame, and what lets a
 * part be replaced later without touching the rest.
 *
 * BINDINGS ARE NEVER INVENTED
 * ---------------------------
 * A component animates only from a role that exists in the tag registry. Where
 * no mapping is recorded — every cylinder, because no supplied source maps
 * actuator numbers to valve numbers — the part renders in its idle state and
 * the inspector says why. It does not guess and animate.
 */

import { useMemo, useRef } from 'react'
import { useFrame } from '@react-three/fiber'
import * as THREE from 'three'
import {
  BELT_THICKNESS, BELT_WIDTH, CABINET, CELL, ENGRAVER, EXTRUSION, MAGAZINE,
  MATERIALS as M, OUTPUT_BIN, TABLE_HEIGHT, VALVE_MANIFOLD,
  type ConveyorPlacement, type CylinderPlacement,
} from './machineLayout'

type Tri = boolean | null

// ===========================================================================
// frame
// ===========================================================================

/** One length of aluminium extrusion. */
function Beam({
  from, to, size = EXTRUSION,
}: {
  from: [number, number, number]
  to: [number, number, number]
  size?: number
}) {
  const { position, rotation, length } = useMemo(() => {
    const a = new THREE.Vector3(...from)
    const b = new THREE.Vector3(...to)
    const dir = b.clone().sub(a)
    const len = dir.length()
    const mid = a.clone().add(dir.clone().multiplyScalar(0.5))
    const quat = new THREE.Quaternion().setFromUnitVectors(
      new THREE.Vector3(0, 1, 0), dir.clone().normalize(),
    )
    const euler = new THREE.Euler().setFromQuaternion(quat)
    return {
      position: [mid.x, mid.y, mid.z] as [number, number, number],
      rotation: [euler.x, euler.y, euler.z] as [number, number, number],
      length: len,
    }
  }, [from, to])

  return (
    <mesh position={position} rotation={rotation} castShadow receiveShadow>
      <boxGeometry args={[size, length, size]} />
      <meshStandardMaterial color={M.extrusion} metalness={0.6} roughness={0.42} />
    </mesh>
  )
}

export function Frame() {
  const { width: W, depth: D } = CELL
  const H = TABLE_HEIGHT
  const corners: [number, number][] = [
    [0.05, 0.05], [W - 0.05, 0.05], [W - 0.05, D - 0.05], [0.05, D - 0.05],
  ]

  return (
    <group>
      {/* legs */}
      {corners.map(([x, z], i) => (
        <Beam key={`leg${i}`} from={[x, 0, z]} to={[x, H, z]} size={EXTRUSION * 1.3} />
      ))}
      {/* top rails */}
      {corners.map(([x, z], i) => {
        const [nx, nz] = corners[(i + 1) % corners.length]
        return <Beam key={`top${i}`} from={[x, H, z]} to={[nx, H, nz]} />
      })}
      {/* lower rails, for stiffness — visible in the photographs */}
      {corners.map(([x, z], i) => {
        const [nx, nz] = corners[(i + 1) % corners.length]
        return <Beam key={`bot${i}`} from={[x, 0.14, z]} to={[nx, 0.14, nz]} />
      })}
      {/* mid cross-member under the belt junction */}
      <Beam from={[0.05, H, D / 2]} to={[W - 0.05, H, D / 2]} />
    </group>
  )
}

export function BasePanels() {
  const { width: W, depth: D } = CELL
  return (
    <mesh
      position={[W / 2, TABLE_HEIGHT - 0.012, D / 2]}
      rotation={[-Math.PI / 2, 0, 0]}
      receiveShadow
    >
      <planeGeometry args={[W - 0.12, D - 0.12]} />
      <meshStandardMaterial color={M.basePanel} roughness={0.85} metalness={0.05} />
    </mesh>
  )
}

// ===========================================================================
// conveyor
// ===========================================================================

export function Conveyor({
  placement,
  running,
  velocity,
  mismatch,
  onSelect,
}: {
  placement: ConveyorPlacement
  running: Tri
  velocity: number | null
  mismatch: boolean
  onSelect: () => void
}) {
  const beltRef = useRef<THREE.Mesh>(null)
  const along = placement.axis === 'x'
  const L = placement.length

  // The belt texture scrolls only when the ENCODER says it is moving, not when
  // the run coil is merely energised. A belt commanded on but not turning is
  // drawn stopped — that is the conveyor-2 symptom from the Errors sheet, and
  // animating it anyway would hide exactly the fault we want visible.
  const moving = running === true && velocity !== null && Math.abs(velocity) > 1e-6

  useFrame((_, delta) => {
    if (!beltRef.current || !moving) return
    const mat = beltRef.current.material as THREE.MeshStandardMaterial
    if (mat.map) {
      const speed = Math.min(Math.abs(velocity ?? 0) * 4, 2)
      if (along) mat.map.offset.x -= delta * speed
      else mat.map.offset.y -= delta * speed
    }
  })

  const texture = useMemo(() => {
    // Chevron stripes, drawn once to a canvas. Cheaper and sharper than a
    // procedural shader for this.
    const c = document.createElement('canvas')
    c.width = 64
    c.height = 64
    const ctx = c.getContext('2d')!
    ctx.fillStyle = M.beltBlue
    ctx.fillRect(0, 0, 64, 64)
    ctx.strokeStyle = M.beltBlueDark
    ctx.lineWidth = 5
    for (let i = -64; i < 128; i += 22) {
      ctx.beginPath()
      ctx.moveTo(i, 0)
      ctx.lineTo(i + 32, 64)
      ctx.stroke()
    }
    const t = new THREE.CanvasTexture(c)
    t.wrapS = t.wrapT = THREE.RepeatWrapping
    t.repeat.set(along ? L * 8 : 2, along ? 2 : L * 8)
    return t
  }, [along, L])

  return (
    <group position={placement.position} onClick={onSelect}>
      {/* belt surface */}
      <mesh
        ref={beltRef}
        position={[along ? L / 2 : 0, BELT_THICKNESS, along ? 0 : L / 2]}
        castShadow
        receiveShadow
      >
        <boxGeometry
          args={along
            ? [L, BELT_THICKNESS, BELT_WIDTH]
            : [BELT_WIDTH, BELT_THICKNESS, L]}
        />
        <meshStandardMaterial map={texture} roughness={0.72} metalness={0.05} />
      </mesh>

      {/* side rails */}
      {[-1, 1].map((side) => (
        <mesh
          key={side}
          position={
            along
              ? [L / 2, BELT_THICKNESS, side * (BELT_WIDTH / 2 + 0.012)]
              : [side * (BELT_WIDTH / 2 + 0.012), BELT_THICKNESS, L / 2]
          }
          castShadow
        >
          <boxGeometry
            args={along ? [L, 0.035, 0.014] : [0.014, 0.035, L]}
          />
          <meshStandardMaterial color={M.extrusion} metalness={0.62} roughness={0.4} />
        </mesh>
      ))}

      {/* end rollers */}
      {[0, L].map((d) => (
        <mesh
          key={d}
          position={along ? [d, BELT_THICKNESS, 0] : [0, BELT_THICKNESS, d]}
          rotation={along ? [Math.PI / 2, 0, 0] : [0, 0, Math.PI / 2]}
          castShadow
        >
          <cylinderGeometry args={[0.022, 0.022, BELT_WIDTH, 16]} />
          <meshStandardMaterial color={M.steel} metalness={0.8} roughness={0.28} />
        </mesh>
      ))}

      {/* motor / gearbox housing with its pushbuttons */}
      <group
        position={
          along
            ? [L + 0.09, -0.02, 0]
            : [0, -0.02, L + 0.09]
        }
      >
        <mesh castShadow receiveShadow>
          <boxGeometry args={[0.16, 0.12, 0.13]} />
          <meshStandardMaterial color={M.creamBox} roughness={0.66} />
        </mesh>
        {/* green run lamp — this one DOES have a live binding */}
        <mesh position={[0.055, 0.03, 0.066]}>
          <cylinderGeometry args={[0.011, 0.011, 0.008, 12]} />
          <meshStandardMaterial
            color={running === true ? '#31d158' : '#1d4a28'}
            emissive={running === true ? '#31d158' : '#000000'}
            emissiveIntensity={running === true ? 1.6 : 0}
          />
        </mesh>
        <mesh position={[0.02, 0.03, 0.066]}>
          <cylinderGeometry args={[0.011, 0.011, 0.008, 12]} />
          <meshStandardMaterial color="#c96a1e" />
        </mesh>
      </group>

      {/* mismatch marker: run coil on, encoder zero */}
      {mismatch && (
        <mesh position={along ? [L / 2, 0.13, 0] : [0, 0.13, L / 2]}>
          <sphereGeometry args={[0.028, 16, 16]} />
          <meshStandardMaterial
            color="#ef4444"
            emissive="#ef4444"
            emissiveIntensity={1.4}
            transparent
            opacity={0.8}
          />
        </mesh>
      )}
    </group>
  )
}

// ===========================================================================
// magazine
// ===========================================================================

export function Magazine({
  counts,
  empties,
  onSelect,
}: {
  counts: (number | null)[]
  empties: Tri[]
  onSelect: () => void
}) {
  const { width: W, height: H, depth: D, compartments } = MAGAZINE
  const cw = W / compartments

  return (
    <group
      position={MAGAZINE.position}
      rotation={[MAGAZINE.rotationX, 0, 0]}
      onClick={onSelect}
    >
      {/* tinted acrylic shell */}
      <mesh castShadow>
        <boxGeometry args={[W, H, D]} />
        <meshPhysicalMaterial
          color={M.acrylicClear}
          transparent
          opacity={0.20}
          roughness={0.06}
          metalness={0}
          transmission={0.85}
          thickness={0.01}
        />
      </mesh>

      {/* plywood top cover */}
      <mesh position={[0, H / 2 + 0.008, 0]} castShadow>
        <boxGeometry args={[W + 0.03, 0.014, D + 0.03]} />
        <meshStandardMaterial color={M.plywood} roughness={0.86} />
      </mesh>

      {/* vertical dividers */}
      {Array.from({ length: compartments - 1 }, (_, i) => (
        <mesh key={i} position={[-W / 2 + cw * (i + 1), 0, 0]}>
          <boxGeometry args={[0.004, H * 0.92, D * 0.92]} />
          <meshPhysicalMaterial
            color={M.acrylicClear}
            transparent
            opacity={0.34}
            transmission={0.7}
          />
        </mesh>
      ))}

      {/* stored blocks — count comes from the camera, or nothing if it is stale */}
      {counts.map((count, i) => {
        const n = Math.min(count ?? 0, 4)
        return Array.from({ length: n }, (_, k) => (
          <mesh
            key={`${i}-${k}`}
            position={[
              -W / 2 + cw * (i + 0.5),
              -H / 2 + 0.022 + k * 0.038,
              0,
            ]}
            castShadow
          >
            <boxGeometry args={[cw * 0.62, 0.032, D * 0.6]} />
            <meshStandardMaterial color={M.wood} roughness={0.9} />
          </mesh>
        ))
      })}

      {/* empty compartments get a red edge, from the PLC's own status bit */}
      {empties.map((empty, i) =>
        empty === true ? (
          <mesh key={`e${i}`} position={[-W / 2 + cw * (i + 0.5), -H / 2 - 0.006, 0]}>
            <boxGeometry args={[cw * 0.9, 0.004, D * 0.9]} />
            <meshStandardMaterial
              color="#ef4444"
              emissive="#ef4444"
              emissiveIntensity={1.2}
            />
          </mesh>
        ) : null,
      )}
    </group>
  )
}

// ===========================================================================
// pneumatic cylinder
// ===========================================================================

export function PneumaticCylinder({
  placement,
  extended,
  onSelect,
}: {
  placement: CylinderPlacement
  /** null when no valve mapping is known — the rod then stays retracted. */
  extended: Tri
  onSelect: () => void
}) {
  const rodRef = useRef<THREE.Group>(null)
  const target = extended === true ? placement.stroke : 0

  useFrame((_, delta) => {
    if (!rodRef.current) return
    const axis = placement.axis
    const cur = axis === 'x'
      ? rodRef.current.position.x
      : axis === 'z' ? rodRef.current.position.z : rodRef.current.position.y
    // Smoothed rather than instant: a pneumatic rod takes a moment. The
    // duration is not modelled from anything measured, so it is not claimed as
    // a real stroke time anywhere in the UI.
    const next = cur + (target * placement.direction - cur) * Math.min(delta * 7, 1)
    if (axis === 'x') rodRef.current.position.x = next
    else if (axis === 'z') rodRef.current.position.z = next
    else rodRef.current.position.y = next
  })

  const rot: [number, number, number] =
    placement.axis === 'x' ? [0, 0, Math.PI / 2]
      : placement.axis === 'z' ? [Math.PI / 2, 0, 0]
        : [0, 0, 0]

  const unmapped = placement.valveRole === null

  return (
    <group position={placement.position} onClick={onSelect}>
      {/* barrel */}
      <mesh rotation={rot} castShadow>
        <cylinderGeometry args={[0.017, 0.017, 0.13, 18]} />
        <meshStandardMaterial
          color={M.steel}
          metalness={0.86}
          roughness={0.22}
        />
      </mesh>

      {/* end caps */}
      {[-1, 1].map((s) => (
        <mesh
          key={s}
          rotation={rot}
          position={
            placement.axis === 'x' ? [s * 0.068, 0, 0]
              : placement.axis === 'z' ? [0, 0, s * 0.068]
                : [0, s * 0.068, 0]
          }
          castShadow
        >
          <cylinderGeometry args={[0.021, 0.021, 0.014, 18]} />
          <meshStandardMaterial color={M.extrusionDark} metalness={0.7} roughness={0.35} />
        </mesh>
      ))}

      {/* rod + pusher face */}
      <group ref={rodRef}>
        <mesh
          rotation={rot}
          position={
            placement.axis === 'x' ? [placement.direction * 0.105, 0, 0]
              : placement.axis === 'z' ? [0, 0, placement.direction * 0.105]
                : [0, placement.direction * 0.105, 0]
          }
          castShadow
        >
          <cylinderGeometry args={[0.0065, 0.0065, 0.085, 12]} />
          <meshStandardMaterial color="#e8ecef" metalness={0.94} roughness={0.1} />
        </mesh>
        <mesh
          position={
            placement.axis === 'x' ? [placement.direction * 0.152, 0, 0]
              : placement.axis === 'z' ? [0, 0, placement.direction * 0.152]
                : [0, placement.direction * 0.152, 0]
          }
          castShadow
        >
          <boxGeometry args={[0.026, 0.03, 0.026]} />
          <meshStandardMaterial color={M.creamBoxDark} roughness={0.6} />
        </mesh>
      </group>

      {/* An unmapped cylinder is marked, so nobody reads its stillness as
          "the actuator is idle" when it actually means "we don't know". */}
      {unmapped && (
        <mesh position={[0, 0.045, 0]}>
          <sphereGeometry args={[0.008, 10, 10]} />
          <meshStandardMaterial color="#64748b" transparent opacity={0.55} />
        </mesh>
      )}
    </group>
  )
}

// ===========================================================================
// engraving station
// ===========================================================================

export function EngravingStation({
  plateUp,
  plateLow,
  engraving,
  onSelect,
}: {
  plateUp: Tri
  plateLow: Tri
  engraving: boolean
  onSelect: () => void
}) {
  const liftRef = useRef<THREE.Group>(null)
  const { enclosure: E, platformTravel } = ENGRAVER

  // Three states, not two. Neither limit made means IN TRANSIT — or stuck,
  // which is exactly the E-14 fault. The model shows it mid-travel rather than
  // snapping to a position it cannot confirm.
  const targetY =
    plateUp === true ? platformTravel
      : plateLow === true ? 0
        : platformTravel * 0.5

  useFrame((_, delta) => {
    if (!liftRef.current) return
    liftRef.current.position.y +=
      (targetY - liftRef.current.position.y) * Math.min(delta * 3.2, 1)
  })

  return (
    <group position={ENGRAVER.position} onClick={onSelect}>
      {/* raised platform the whole station sits on */}
      <mesh position={[E.width / 2, -0.03, E.depth / 2]} castShadow receiveShadow>
        <boxGeometry args={[E.width + 0.10, 0.05, E.depth + 0.10]} />
        <meshStandardMaterial color={M.extrusionDark} metalness={0.55} roughness={0.5} />
      </mesh>

      {/* the lift, driven by the two limit switches */}
      <group ref={liftRef} position={[E.width / 2, 0, E.depth / 2]}>
        <mesh castShadow receiveShadow>
          <boxGeometry args={[0.16, 0.014, 0.16]} />
          <meshStandardMaterial color={M.creamBox} roughness={0.6} />
        </mesh>
        <mesh position={[0, 0.014, 0]}>
          <boxGeometry args={[0.10, 0.014, 0.10]} />
          <meshStandardMaterial color={M.wood} roughness={0.9} />
        </mesh>
      </group>

      {/* laser gantry inside the enclosure */}
      <group position={[E.width / 2, 0.20, E.depth / 2]}>
        <mesh castShadow>
          <boxGeometry args={[E.width * 0.8, 0.022, 0.028]} />
          <meshStandardMaterial color={M.extrusion} metalness={0.7} roughness={0.3} />
        </mesh>
        <mesh position={[0, -0.024, 0]} castShadow>
          <boxGeometry args={[0.05, 0.04, 0.045]} />
          <meshStandardMaterial color="#2a2e35" roughness={0.45} />
        </mesh>
        {engraving && (
          <mesh position={[0, -0.10, 0]}>
            <cylinderGeometry args={[0.0018, 0.0018, 0.14, 8]} />
            <meshStandardMaterial
              color="#ff3b30"
              emissive="#ff3b30"
              emissiveIntensity={3}
            />
          </mesh>
        )}
      </group>

      {/* tinted enclosure — the machine's most recognisable feature */}
      <mesh position={[E.width / 2, E.height / 2, E.depth / 2]}>
        <boxGeometry args={[E.width, E.height, E.depth]} />
        <meshPhysicalMaterial
          color={M.laserRed}
          transparent
          opacity={0.34}
          roughness={0.12}
          metalness={0}
          transmission={0.6}
          thickness={0.02}
          side={THREE.DoubleSide}
        />
      </mesh>

      {/* enclosure frame edges */}
      <lineSegments position={[E.width / 2, E.height / 2, E.depth / 2]}>
        <edgesGeometry args={[new THREE.BoxGeometry(E.width, E.height, E.depth)]} />
        <lineBasicMaterial color="#7a1f10" />
      </lineSegments>
    </group>
  )
}

// ===========================================================================
// misc parts
// ===========================================================================

export function OutputBin({ contents }: { contents: number }) {
  const { size } = OUTPUT_BIN
  return (
    <group position={OUTPUT_BIN.position}>
      <mesh position={[0, size.height / 2, 0]} castShadow receiveShadow>
        <boxGeometry args={[size.width, size.height, size.depth]} />
        <meshStandardMaterial color={M.binBlue} roughness={0.72} />
      </mesh>
      {/* hollow it out */}
      <mesh position={[0, size.height / 2 + 0.012, 0]}>
        <boxGeometry args={[size.width - 0.03, size.height, size.depth - 0.03]} />
        <meshStandardMaterial color="#0e2f66" roughness={0.8} side={THREE.BackSide} />
      </mesh>
      {Array.from({ length: Math.min(contents, 5) }, (_, i) => (
        <mesh
          key={i}
          position={[
            (i % 2 ? 0.05 : -0.05),
            0.03 + Math.floor(i / 2) * 0.036,
            (i % 3 ? 0.03 : -0.03),
          ]}
          rotation={[0, i * 0.4, 0]}
          castShadow
        >
          <boxGeometry args={[0.09, 0.032, 0.07]} />
          <meshStandardMaterial color={M.wood} roughness={0.9} />
        </mesh>
      ))}
    </group>
  )
}

export function ElectricalCabinet({ plcConnected }: { plcConnected: boolean }) {
  const { size, baseHeight } = CABINET
  return (
    <group position={CABINET.position} rotation={[0, CABINET.rotationY, 0]}>
      {/* black rolling base */}
      <mesh position={[0, baseHeight / 2, 0]} castShadow receiveShadow>
        <boxGeometry args={[size.width, baseHeight, size.depth]} />
        <meshStandardMaterial color={M.blackBase} roughness={0.78} />
      </mesh>

      {/* cabinet body */}
      <mesh position={[0, baseHeight + size.height / 2, 0]} castShadow receiveShadow>
        <boxGeometry args={[size.width, size.height, size.depth]} />
        <meshStandardMaterial color={M.cabinetCream} roughness={0.62} />
      </mesh>

      {/* glazed window */}
      <mesh position={[0, baseHeight + size.height / 2, size.depth / 2 + 0.002]}>
        <planeGeometry args={[size.width * 0.76, size.height * 0.66]} />
        <meshPhysicalMaterial
          color="#93b6c9"
          transparent
          opacity={0.32}
          roughness={0.04}
          transmission={0.8}
        />
      </mesh>

      {/* what is visible through it: PLC, PSU, three terminal rows */}
      <group position={[0, baseHeight + size.height / 2, size.depth / 2 - 0.03]}>
        {/* S7-1200 */}
        <mesh position={[-size.width * 0.22, size.height * 0.22, 0]}>
          <boxGeometry args={[0.13, 0.075, 0.05]} />
          <meshStandardMaterial color="#3f4a52" roughness={0.5} />
        </mesh>
        {/* PLC RUN led — a real binding */}
        <mesh position={[-size.width * 0.27, size.height * 0.24, 0.027]}>
          <sphereGeometry args={[0.006, 8, 8]} />
          <meshStandardMaterial
            color={plcConnected ? '#31d158' : '#ef4444'}
            emissive={plcConnected ? '#31d158' : '#ef4444'}
            emissiveIntensity={2}
          />
        </mesh>
        {/* PSU */}
        <mesh position={[size.width * 0.10, size.height * 0.22, 0]}>
          <boxGeometry args={[0.07, 0.085, 0.05]} />
          <meshStandardMaterial color="#d8d2c4" roughness={0.55} />
        </mesh>
        {/* terminal rows */}
        {[0.02, -0.10, -0.20].map((y, r) => (
          <mesh key={r} position={[0, y, 0]}>
            <boxGeometry args={[size.width * 0.7, 0.028, 0.035]} />
            <meshStandardMaterial color="#b8b2a4" roughness={0.7} />
          </mesh>
        ))}
      </group>
    </group>
  )
}

export function AirReceiver({ pressure }: { pressure: number | null }) {
  return (
    <group position={[3.05, 0.16, 0.92]}>
      <mesh rotation={[0, 0, Math.PI / 2]} castShadow receiveShadow>
        <cylinderGeometry args={[0.10, 0.10, 0.40, 24]} />
        <meshStandardMaterial color={M.steel} metalness={0.72} roughness={0.35} />
      </mesh>
      {/* compressor head */}
      <mesh position={[0.08, 0.11, 0]} castShadow>
        <boxGeometry args={[0.10, 0.11, 0.09]} />
        <meshStandardMaterial color="#4a4f56" roughness={0.55} />
      </mesh>
      {/* gauge face, needle driven by live pressure */}
      <group position={[-0.14, 0.09, 0.04]}>
        <mesh rotation={[Math.PI / 2, 0, 0]}>
          <cylinderGeometry args={[0.026, 0.026, 0.01, 20]} />
          <meshStandardMaterial color="#e9ecef" roughness={0.4} />
        </mesh>
        <mesh
          position={[0, 0.008, 0]}
          rotation={[0, 0, -((pressure ?? 0) / 10) * Math.PI * 1.4 + Math.PI * 0.7]}
        >
          <boxGeometry args={[0.021, 0.0025, 0.0025]} />
          <meshStandardMaterial color="#c0392b" />
        </mesh>
      </group>
    </group>
  )
}

export function ValveManifold({
  valves,
  onSelect,
}: {
  valves: Tri[]
  onSelect: () => void
}) {
  const n = VALVE_MANIFOLD.valveCount
  return (
    <group position={VALVE_MANIFOLD.position} onClick={onSelect}>
      {/* manifold rail */}
      <mesh position={[n * 0.021, 0, 0]} castShadow>
        <boxGeometry args={[n * 0.044, 0.035, 0.06]} />
        <meshStandardMaterial color={M.extrusionDark} metalness={0.6} roughness={0.4} />
      </mesh>
      {valves.map((on, i) => (
        <group key={i} position={[i * 0.044 + 0.022, 0.045, 0]}>
          <mesh castShadow>
            <boxGeometry args={[0.034, 0.055, 0.045]} />
            <meshStandardMaterial color="#2f3237" roughness={0.5} />
          </mesh>
          {/* coil indicator — bound to the real output-image bit */}
          <mesh position={[0, 0.033, 0.016]}>
            <sphereGeometry args={[0.006, 8, 8]} />
            <meshStandardMaterial
              color={on === true ? '#ffb020' : '#3a3d42'}
              emissive={on === true ? '#ffb020' : '#000000'}
              emissiveIntensity={on === true ? 2.2 : 0}
            />
          </mesh>
        </group>
      ))}
    </group>
  )
}

export function ProximitySensor({
  position,
  active,
  onSelect,
}: {
  position: [number, number, number]
  active: Tri
  onSelect: () => void
}) {
  return (
    <group position={position} onClick={onSelect}>
      <mesh castShadow>
        <cylinderGeometry args={[0.009, 0.009, 0.05, 14]} />
        <meshStandardMaterial color="#b0b6bd" metalness={0.75} roughness={0.3} />
      </mesh>
      <mesh position={[0, 0.03, 0]}>
        <sphereGeometry args={[0.008, 12, 12]} />
        <meshStandardMaterial
          color={active === true ? '#31d158' : active === null ? '#4a5058' : '#1f3a26'}
          emissive={active === true ? '#31d158' : '#000000'}
          emissiveIntensity={active === true ? 2.4 : 0}
        />
      </mesh>
      {active === true && (
        <pointLight color="#31d158" intensity={0.35} distance={0.28} />
      )}
    </group>
  )
}

export function EStop({ active }: { active: boolean }) {
  return (
    <group position={[2.18, TABLE_HEIGHT + 0.10, 0.52]}>
      <mesh position={[0, -0.035, 0]} castShadow>
        <boxGeometry args={[0.07, 0.07, 0.03]} />
        <meshStandardMaterial color={M.estopPlate} roughness={0.6} />
      </mesh>
      <mesh position={[0, active ? -0.006 : 0, 0]} castShadow>
        <cylinderGeometry args={[0.022, 0.026, active ? 0.014 : 0.024, 20]} />
        <meshStandardMaterial
          color={M.estopRed}
          roughness={0.45}
          emissive={active ? '#ff2020' : '#000000'}
          emissiveIntensity={active ? 0.9 : 0}
        />
      </mesh>
    </group>
  )
}

export function PneumaticTube({ points }: { points: [number, number, number][] }) {
  const geometry = useMemo(() => {
    const curve = new THREE.CatmullRomCurve3(
      points.map((p) => new THREE.Vector3(...p)),
    )
    return new THREE.TubeGeometry(curve, 40, 0.0035, 7, false)
  }, [points])

  return (
    <mesh geometry={geometry}>
      <meshStandardMaterial color={M.tubeBlue} roughness={0.42} metalness={0.05} />
    </mesh>
  )
}

export function Desk() {
  return (
    <group position={[-0.55, 0, 0.75]}>
      <mesh position={[0, 0.72, 0]} castShadow receiveShadow>
        <boxGeometry args={[0.55, 0.03, 1.0]} />
        <meshStandardMaterial color="#3a3f45" roughness={0.7} />
      </mesh>
      {[-0.42, 0.42].map((z) => (
        <mesh key={z} position={[0, 0.36, z]} castShadow>
          <boxGeometry args={[0.5, 0.72, 0.03]} />
          <meshStandardMaterial color="#2b2f34" roughness={0.75} />
        </mesh>
      ))}
      {/* monitor */}
      <mesh position={[0, 0.94, 0.1]} rotation={[0, 0.4, 0]} castShadow>
        <boxGeometry args={[0.02, 0.30, 0.48]} />
        <meshStandardMaterial color="#101317" roughness={0.4} />
      </mesh>
      {/* keyboard */}
      <mesh position={[0.04, 0.745, -0.1]} rotation={[0, 0.4, 0]}>
        <boxGeometry args={[0.14, 0.012, 0.36]} />
        <meshStandardMaterial color="#1b1f24" roughness={0.7} />
      </mesh>
    </group>
  )
}

/** The workpiece token, when the backend has a position for it. */
export function Workpiece({
  position,
  confirmed,
}: {
  position: [number, number, number]
  confirmed: boolean
}) {
  return (
    <group position={position}>
      <mesh castShadow>
        <boxGeometry args={[0.10, 0.04, 0.10]} />
        <meshStandardMaterial color={M.wood} roughness={0.88} />
      </mesh>
      {/* A halo whose colour states whether a sensor actually confirmed this
          position, or whether it is only inferred. */}
      <mesh position={[0, 0.05, 0]}>
        <sphereGeometry args={[0.016, 12, 12]} />
        <meshStandardMaterial
          color={confirmed ? '#38bdf8' : '#a78bfa'}
          emissive={confirmed ? '#38bdf8' : '#a78bfa'}
          emissiveIntensity={1.4}
          transparent
          opacity={confirmed ? 0.9 : 0.45}
        />
      </mesh>
    </group>
  )
}
