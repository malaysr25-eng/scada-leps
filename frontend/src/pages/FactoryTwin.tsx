/**
 * Cell view: the plan at the Overview's size, with the status line the
 * MATLAB replay prints beneath it and the actuator roll-up beside it. This is
 * the screen to leave up on a wall monitor during a run.
 *
 * The plan is drawn to the simulation's own metric geometry, so this and the
 * MATLAB figure are the same picture of the same cell -- which is what makes it
 * possible to point at a barrel here and find it on the bench.
 */

import { useState } from 'react'
import { CellPlan, CellStatusLine, groupCoils } from '../components/cell/CellPlan'
import { ACTUATORS, actuatorLabel } from '../components/cell/actuatorModel'
import { CELL_PALETTE } from '../components/cell/cellGeometry'
import { Badge, Note, Panel } from '../components/common/Primitives'
import {
  SensorBoard, SensorDetail, SensorEventStream,
} from '../components/sensors/SensorPanel'
import { selectActuators, useMachine } from '../stores/machineStore'
import type { SensorView, Tri } from '../types'
import { ago, classNames } from '../utils/format'

export function FactoryTwinPage() {
  const [selected, setSelected] = useState<SensorView | null>(null)

  return (
    <div className="space-y-4">
      <Panel
        title="Cell plan"
      >
        {/* Same width as the Overview's middle column (its side columns are
            340px at xl, 360px each at 2xl), so the plan fits on one screen. */}
        <div className="mx-auto xl:max-w-[calc(100%-340px-1rem)] 2xl:max-w-[calc(100%-720px-2rem)]">
          <CellPlan onSensorClick={setSelected} />
        </div>
      </Panel>

      <CellStatusLine />

      <div className="grid gap-4 xl:grid-cols-[1fr_360px]">
        <div className="space-y-4">
          <ActuatorRollup />
          <Panel title="All sensors">
            <SensorBoard onSelect={setSelected} />
          </Panel>
          <Panel title="Sensor event stream">
            <SensorEventStream limit={24} />
          </Panel>
        </div>
        <div>
          {selected ? (
            <SensorDetail sensor={selected} onClose={() => setSelected(null)} />
          ) : (
            <Panel title="Sensor detail">
              <p className="py-8 text-center text-xs text-ink-500">
                Click a sensor on the plan or in the board.
              </p>
            </Panel>
          )}
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------

/**
 * Thirteen coils presented as the eleven actuators they actually drive.
 *
 * Read-only: this page watches, `/manual` commands. The pairing itself is the
 * information -- coils 7 and 8 are the two ends of CYL_A's spool, and reading
 * them as independent valves is how "actuator 8 did not retract" gets
 * misdiagnosed.
 */
function ActuatorRollup() {
  const actuators = useMachine(selectActuators)
  const { grouped, unmapped } = groupCoils(actuators)

  return (
    <Panel
      title="Actuators"
      actions={
        <Badge tone="idle">
          {ACTUATORS.filter((a) => a.kind === 'double').length} double-solenoid
        </Badge>
      }
    >
      <div className="overflow-x-auto">
        <table className="w-full min-w-[640px] text-left text-xs">
          <thead>
            <tr className="border-b border-panel-700 text-xs uppercase tracking-wider text-ink-500">
              <th className="py-1.5 pr-3 font-medium">Actuator</th>
              <th className="py-1.5 pr-3 font-medium">Valve</th>
              <th className="py-1.5 pr-3 font-medium">Extend</th>
              <th className="py-1.5 pr-3 font-medium">Retract</th>
              <th className="py-1.5 pr-3 font-medium">Stroke</th>
              <th className="py-1.5 font-medium">Last change</th>
            </tr>
          </thead>
          <tbody>
            {grouped.map(({ actuator, extend, retract }) => {
              const live = extend?.state === true || retract?.state === true
              return (
                <tr
                  key={actuator.name}
                  className={classNames(
                    'border-b border-panel-800/70',
                    live && 'bg-state-run/6',
                  )}
                  title={actuator.note}
                >
                  <td className="py-1.5 pr-3">
                    <div className="flex items-center gap-2">
                      <span
                        className="inline-block h-2.5 w-4 shrink-0 rounded-sm border-2"
                        style={{
                          borderColor:
                            actuator.kind === 'double'
                              ? CELL_PALETTE.actuatorDouble
                              : CELL_PALETTE.actuator,
                          borderStyle: actuator.contact ? 'solid' : 'dotted',
                        }}
                      />
                      <span className="font-mono text-ink-200">
                        {actuatorLabel(actuator)}
                      </span>
                      {actuator.alias && (
                        <span className="text-xs text-ink-500">
                          {actuator.alias}
                        </span>
                      )}
                    </div>
                  </td>
                  <td className="py-1.5 pr-3 text-ink-400">
                    {actuator.kind === 'double' ? 'Double, latching' : 'Spring-return'}
                    <span className="ml-1.5 text-xs text-ink-600">
                      br {actuator.branch}
                    </span>
                  </td>
                  <td className="py-1.5 pr-3">
                    <CoilCell
                      value={extend?.state ?? null}
                      address={extend?.stateAddress}
                      coil={actuator.coilExtend}
                    />
                  </td>
                  <td className="py-1.5 pr-3">
                    {actuator.coilRetract > 0 ? (
                      <CoilCell
                        value={retract?.state ?? null}
                        address={retract?.stateAddress}
                        coil={actuator.coilRetract}
                      />
                    ) : (
                      <span className="text-xs text-ink-600">spring</span>
                    )}
                  </td>
                  <td className="py-1.5 pr-3 font-mono text-ink-400">
                    {actuator.geometry.travel != null
                      ? `${(actuator.geometry.travel * 1000).toFixed(1)} mm`
                      : 'not claimed'}
                  </td>
                  <td className="py-1.5 text-ink-500">
                    {ago(extend?.lastChangeAt ?? retract?.lastChangeAt ?? null)}
                  </td>
                </tr>
              )
            })}
          </tbody>
        </table>
      </div>

      {unmapped.length > 0 && (
        <Note tone="warn">
          {unmapped.length} coil{unmapped.length === 1 ? '' : 's'} not in the
          actuator model ({unmapped.map((u) => `SV${u.index}`).join(', ')}).
        </Note>
      )}
    </Panel>
  )
}

function CoilCell({
  value,
  address,
  coil,
}: {
  value: Tri
  address?: string
  coil: number
}) {
  const on = value === true
  const unknown = value == null
  return (
    <span
      className="inline-flex items-center gap-1.5"
      title={`Coil ${coil} — ${address ?? 'no tag'}`}
    >
      <span
        className={classNames(
          'inline-block h-2.5 w-2.5 shrink-0 rounded-full',
          on
            ? 'bg-state-run'
            : unknown
              ? 'border border-dashed border-ink-500'
              : 'border border-panel-500',
        )}
      />
      <span
        className={classNames(
          'font-mono text-xs',
          on ? 'text-state-run' : 'text-ink-500',
        )}
      >
        {on ? 'ON' : unknown ? 'N/A' : 'OFF'}
      </span>
      <span className="font-mono text-xs text-ink-600">{coil}</span>
    </span>
  )
}
