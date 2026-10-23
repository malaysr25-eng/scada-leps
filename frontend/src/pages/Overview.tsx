/**
 * Overview -- the primary SCADA screen.
 *
 * Cycle control, the cell plan and order progress share the first row, so
 * the operating loop is on screen without scrolling; sensors, the event
 * stream and the camera follow. Diagnostics, the tag explorer and the twin comparison live on
 * their own pages so this one stays readable.
 */

import { useState } from 'react'
import { Boxes, Package } from 'lucide-react'
import { CellPlan } from '../components/cell/CellPlan'
import { CameraPanel } from '../components/common/CameraPanel'
import { Badge, EmptyState, Note, Panel } from '../components/common/Primitives'
import { CycleControl } from '../components/controls/CycleControl'
import { RestartChecklist } from '../components/machine/RestartChecklist'
import { SequenceTimeline } from '../components/machine/SequenceTimeline'
import {
  SensorBoard, SensorDetail, SensorEventStream,
} from '../components/sensors/SensorPanel'
import { useSequenceCatalogue } from '../hooks/useSequenceCatalogue'
import { selectInventory, selectMachine, useMachine } from '../stores/machineStore'
import type { SensorView } from '../types'
import { classNames } from '../utils/format'

export function OverviewPage() {
  const catalogue = useSequenceCatalogue()
  const machine = useMachine(selectMachine)
  const [selectedSensor, setSelectedSensor] = useState<SensorView | null>(null)

  const inFault =
    machine?.lifecycle === 'EMERGENCY_STOPPED' ||
    machine?.lifecycle === 'FAULT' ||
    machine?.lifecycle === 'RECOVERY_REQUIRED'

  return (
    <div className="space-y-4">
      <div className="grid gap-4 xl:grid-cols-[340px_1fr] 2xl:grid-cols-[360px_1fr_360px]">
        <div className="space-y-4">
          <CycleControl />
          {inFault && <RestartChecklist />}
        </div>

        <Panel title="Live cell">
          <CellPlan onSensorClick={setSelectedSensor} compact />
        </Panel>

        <div className="grid gap-4 xl:col-span-2 xl:grid-cols-2 2xl:col-span-1 2xl:grid-cols-1 2xl:content-start">
          {selectedSensor && (
            <SensorDetail
              sensor={selectedSensor}
              onClose={() => setSelectedSensor(null)}
            />
          )}
          <InventoryPanel />
        </div>
      </div>

      <div className="grid gap-4 xl:grid-cols-2 2xl:grid-cols-[1fr_1fr_360px]">
        <Panel
          title="Sensors"
          subtitle="Click a sensor for its address, history and last transition"
        >
          <SensorBoard onSelect={setSelectedSensor} />
        </Panel>

        <Panel title="Sensor event stream" subtitle="Every edge, to the millisecond">
          <SensorEventStream limit={12} />
        </Panel>

        <CameraPanel compact />
      </div>

      {!inFault && (
        <div className="grid gap-4 xl:grid-cols-2">
          <SequenceTimeline catalogue={catalogue} compact />
          <RestartChecklist />
        </div>
      )}

      {inFault && <SequenceTimeline catalogue={catalogue} compact />}
    </div>
  )
}

// ---------------------------------------------------------------------------

function InventoryPanel() {
  const inventory = useMachine(selectInventory)

  if (!inventory) {
    return (
      <Panel title="Product tracking">
        <EmptyState>Waiting for the first PLC read.</EmptyState>
      </Panel>
    )
  }

  const { order, progress, activeToken, magazines } = inventory
  const mismatches = magazines.filter((m) => m.mismatch)

  return (
    <Panel
      title="Product tracking"
      actions={
        <Badge tone={order.total > 0 ? 'info' : 'idle'}>
          {order.total} ordered
        </Badge>
      }
    >
      <div className="space-y-3">
        <div className="grid grid-cols-3 gap-2">
          <Cell label="25 mm" value={String(order.qty25)} />
          <Cell label="50 mm" value={String(order.qty50)} />
          <Cell
            label="Completed"
            value={
              progress.plcTotalProducts != null
                ? String(progress.plcTotalProducts)
                : '--'
            }
            tone="run"
          />
        </div>

        {order.total > 0 && progress.plcTotalProducts != null && (
          <div>
            <div className="mb-1 flex justify-between text-xs uppercase tracking-wider text-ink-500">
              <span>Progress</span>
              <span>
                {progress.plcTotalProducts} / {order.total}
              </span>
            </div>
            <div className="h-1.5 overflow-hidden rounded-full bg-panel-700">
              <div
                className="h-full rounded-full bg-state-run transition-all"
                style={{
                  width: `${Math.min(
                    100,
                    (progress.plcTotalProducts / Math.max(1, order.total)) * 100,
                  )}%`,
                }}
              />
            </div>
            <p className="mt-1 text-xs text-ink-600">
              Source: {progress.source}
            </p>
          </div>
        )}

        {activeToken && (
          <div className="rounded-lg border border-state-info/40 bg-state-info/8 p-2.5">
            <div className="mb-1 flex items-center gap-2">
              <Package size={13} className="text-state-info" />
              <span className="font-mono text-sm font-bold text-state-info">
                {activeToken.tokenId}
              </span>
              <Badge
                tone={activeToken.positioning === 'CONFIRMED' ? 'run' : 'twin'}
                className="ml-auto !py-0 !text-xs"
              >
                {activeToken.positioning}
              </Badge>
            </div>
            <dl className="space-y-0.5 text-xs">
              <TokenRow label="At">{activeToken.stationLabel}</TokenRow>
              <TokenRow label="Last event">{activeToken.lastEvent || '--'}</TokenRow>
              <TokenRow label="Expected next">
                {activeToken.expectedNext || '--'}
              </TokenRow>
            </dl>
          </div>
        )}

        <div>
          <h3 className="mb-1.5 flex items-center gap-1.5 text-xs uppercase tracking-wider text-ink-500">
            <Boxes size={11} /> Magazines
          </h3>
          <div className="grid grid-cols-5 gap-1.5">
            {magazines.map((m) => (
              <div
                key={m.index}
                title={
                  m.mismatch ??
                  `Camera: ${m.cameraCount ?? 'offline'} · PLC: ${
                    m.plcEmpty === true
                      ? 'EMPTY'
                      : m.plcLow === true
                        ? 'LOW'
                        : m.plcOk === true
                          ? 'OK'
                          : 'unknown'
                  }`
                }
                className={classNames(
                  'rounded border px-1.5 py-1.5 text-center',
                  m.mismatch
                    ? 'border-state-warn/50 bg-state-warn/10'
                    : m.plcEmpty === true
                      ? 'border-state-fault/50 bg-state-fault/10'
                      : 'border-panel-700 bg-panel-800',
                )}
              >
                <div className="text-xs text-ink-500">M{m.index}</div>
                <div className="font-mono text-sm text-ink-200">
                  {m.cameraCount ?? '--'}
                </div>
              </div>
            ))}
          </div>
        </div>

        {mismatches.length > 0 && (
          <Note tone="warn">
            {mismatches.length} magazine
            {mismatches.length === 1 ? '' : 's'}: camera and PLC disagree.
          </Note>
        )}
      </div>
    </Panel>
  )
}

function Cell({
  label,
  value,
  tone = 'idle',
}: {
  label: string
  value: string
  tone?: 'idle' | 'run'
}) {
  return (
    <div className="rounded-lg border border-panel-700 bg-panel-800 px-2 py-1.5">
      <div className="text-xs uppercase tracking-wider text-ink-500">{label}</div>
      <div
        className={classNames(
          'mt-0.5 font-mono text-lg tabular-nums',
          tone === 'run' ? 'text-state-run' : 'text-ink-100',
        )}
      >
        {value}
      </div>
    </div>
  )
}

function TokenRow({
  label,
  children,
}: {
  label: string
  children: React.ReactNode
}) {
  return (
    <div className="flex gap-2">
      <dt className="w-24 shrink-0 text-ink-500">{label}</dt>
      <dd className="min-w-0 flex-1 text-ink-300">{children}</dd>
    </div>
  )
}
