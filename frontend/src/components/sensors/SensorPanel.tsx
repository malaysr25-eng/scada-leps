/**
 * Sensor board and the live transition stream.
 *
 * The old SCADA rendered sensors as a wall of identical text boxes with no
 * timestamps and no history, so "did PX3 ever fire?" was unanswerable after
 * the fact. Here every sensor keeps its last transition time and a running
 * transition count, and the stream below records every edge with milliseconds.
 */

import { useMemo } from 'react'
import { Radio, X } from 'lucide-react'
import {
  selectDiagnostics, selectSensors, useMachine,
} from '../../stores/machineStore'
import type { SensorView } from '../../types'
import { ago, classNames, clockMs, pretty } from '../../utils/format'
import { Badge, EmptyState, Lamp, Panel } from '../common/Primitives'

export function SensorBoard({
  onSelect,
}: {
  onSelect?: (s: SensorView) => void
}) {
  const sensors = useMachine(selectSensors)

  if (!sensors?.length) {
    return <EmptyState>No sensors in the tag registry.</EmptyState>
  }

  return (
    <div className="grid grid-cols-2 gap-2 sm:grid-cols-3 xl:grid-cols-4">
      {sensors.map((s) => {
        const on = s.value === true
        const unknown = s.value == null
        return (
          <button
            key={s.role}
            onClick={() => onSelect?.(s)}
            className={classNames(
              'group flex items-center gap-2.5 rounded-lg border px-3 py-2 text-left transition-colors',
              on
                ? 'border-state-run/50 bg-state-run/10'
                : unknown
                  ? 'border-dashed border-panel-600 bg-panel-800/50'
                  : 'border-panel-700 bg-panel-800 hover:border-panel-500',
            )}
          >
            <Lamp value={s.value} size="lg" />
            <div className="min-w-0 flex-1">
              <div className="flex items-baseline justify-between gap-2">
                <span
                  className={classNames(
                    'truncate font-mono text-xs font-semibold',
                    on ? 'text-state-run' : unknown ? 'text-ink-500' : 'text-ink-200',
                  )}
                >
                  {s.label}
                </span>
                <span
                  className={classNames(
                    'shrink-0 text-[10px] font-bold uppercase tracking-wider',
                    on ? 'text-state-run' : unknown ? 'text-ink-500' : 'text-ink-500',
                  )}
                >
                  {on ? 'Active' : unknown ? 'N/A' : 'Clear'}
                </span>
              </div>
              <div className="mt-0.5 flex items-baseline justify-between gap-2 text-[10px] text-ink-500">
                <span className="truncate font-mono">{s.address}</span>
                <span className="shrink-0">{s.transitions}×</span>
              </div>
            </div>
          </button>
        )
      })}
    </div>
  )
}

// ---------------------------------------------------------------------------

export function SensorEventStream({ limit = 14 }: { limit?: number }) {
  const diagnostics = useMachine(selectDiagnostics)

  const stream = useMemo(
    () =>
      (diagnostics?.recentChanges ?? [])
        .filter((c) => (c.role ?? '').startsWith('sensor.'))
        .slice(-limit)
        .reverse(),
    [diagnostics?.recentChanges, limit],
  )

  return (
    <div className="space-y-1">
      {stream.length === 0 && (
        <p className="py-6 text-center text-xs text-ink-500">
          No sensor transitions yet this session.
        </p>
      )}
      {stream.map((c, i) => (
        <div
          key={`${c.tagId}-${c.at}-${i}`}
          className="flex items-center gap-3 rounded border border-panel-800 bg-panel-900 px-2.5 py-1.5 font-mono text-[11px]"
        >
          <span className="shrink-0 text-ink-500">{clockMs(c.at)}</span>
          <span className="w-24 shrink-0 truncate font-semibold text-ink-200">
            {c.short}
          </span>
          <span className="text-ink-500">{pretty(c.previous)}</span>
          <span className="text-ink-500">→</span>
          <span
            className={classNames(
              'font-bold',
              c.value === true ? 'text-state-run' : 'text-ink-400',
            )}
          >
            {pretty(c.value)}
          </span>
          {c.source === 'operator' && (
            <Badge tone="info" className="!py-0 !text-[9px]">
              operator
            </Badge>
          )}
        </div>
      ))}
    </div>
  )
}

// ---------------------------------------------------------------------------

export function SensorDetail({
  sensor,
  onClose,
}: {
  sensor: SensorView
  onClose: () => void
}) {
  return (
    <Panel
      title={
        <span className="flex items-center gap-2">
          <Radio size={14} /> {sensor.label}
        </span>
      }
      actions={
        <button
          onClick={onClose}
          className="rounded p-1 text-ink-400 hover:bg-panel-700 hover:text-ink-100"
          aria-label="Close sensor detail"
        >
          <X size={15} />
        </button>
      }
    >
      <dl className="space-y-2 text-xs">
        <Row label="State">
          <span className="flex items-center gap-2">
            <Lamp value={sensor.value} />
            <span
              className={
                sensor.value === true
                  ? 'font-bold text-state-run'
                  : sensor.value == null
                    ? 'text-ink-500'
                    : 'text-ink-300'
              }
            >
              {sensor.value === true ? 'ACTIVE' : sensor.value == null ? 'UNKNOWN' : 'CLEAR'}
            </span>
          </span>
        </Row>
        <Row label="Tag">
          <span className="break-all font-mono text-ink-300">{sensor.tagId}</span>
        </Row>
        <Row label="PLC address">
          <span className="font-mono text-ink-300">{sensor.address}</span>
        </Row>
        <Row label="Last transition">
          <span className="text-ink-300">
            {sensor.lastChangeAt
              ? `${clockMs(sensor.lastChangeAt)}  (${ago(sensor.lastChangeAt)})`
              : 'none this session'}
          </span>
        </Row>
        <Row label="Transitions">
          <span className="font-mono text-ink-300">{sensor.transitions}</span>
        </Row>
        <Row label="Description">
          <span className="text-ink-400">{sensor.description || '--'}</span>
        </Row>
      </dl>
    </Panel>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-start gap-3 border-b border-panel-800 pb-1.5 last:border-0">
      <dt className="w-28 shrink-0 text-[10px] uppercase tracking-wider text-ink-500">
        {label}
      </dt>
      <dd className="min-w-0 flex-1">{children}</dd>
    </div>
  )
}
