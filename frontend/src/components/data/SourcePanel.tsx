/**
 * Data-source detail panel.
 *
 * Shows every registered source side by side with its health, quality and
 * control eligibility. The point of the layout is that "who is in control" and
 * "whose data am I looking at" are answered separately, because they are
 * separate questions and conflating them is how simulated values get read as
 * plant data.
 */

import { useState } from 'react'
import {
  Activity, AlertTriangle, Ban, Cpu, FlaskConical, Loader2, Play, Square,
} from 'lucide-react'
import { api } from '../../services/api'
import { useMachine } from '../../stores/machineStore'
import type { Quality, SourceInfo } from '../../types'
import { ago, classNames, num } from '../../utils/format'
import { Badge, Button, EmptyState, Panel } from '../common/Primitives'

const QUALITY_TONE: Record<Quality, 'run' | 'warn' | 'fault' | 'idle'> = {
  GOOD: 'run',
  STALE: 'warn',
  UNCERTAIN: 'warn',
  BAD: 'fault',
}

export function SourcePanel() {
  const sources = useMachine((s) => s.snapshot?.dataSources)
  const pushToast = useMachine((s) => s.pushToast)
  const [busy, setBusy] = useState<string | null>(null)

  if (!sources) {
    return (
      <Panel title="Data sources">
        <EmptyState>Waiting for the first snapshot.</EmptyState>
      </Panel>
    )
  }

  async function act(
    id: string,
    fn: () => Promise<{ ok: boolean; error?: { message: string } }>,
    okTitle: string,
  ) {
    setBusy(id)
    const res = await fn()
    setBusy(null)
    pushToast(
      res.ok
        ? { kind: 'ok', title: okTitle }
        : { kind: 'warn', title: 'Refused', detail: res.error?.message },
    )
  }

  return (
    <Panel
      title="Data sources"
      actions={<Badge tone="info">{sources.mode}</Badge>}
    >
      <div className="space-y-3">
        {sources.sources.map((src) => (
          <SourceCard
            key={src.sourceId}
            source={src}
            isTelemetry={src.sourceId === sources.telemetrySourceId}
            transition={sources.transitions.find((t) => t.sourceId === src.sourceId)}
            busy={busy === src.sourceId}
            onTakeControl={() =>
              act(
                src.sourceId,
                () => api.setControlSource(src.sourceId),
                'Control source changed',
              )
            }
            onDisplay={() =>
              act(
                src.sourceId,
                () => api.setTelemetrySource(src.sourceId),
                'Telemetry source changed',
              )
            }
            onStart={() =>
              act(src.sourceId, () => api.startSource(src.sourceId), 'Source started')
            }
            onStop={() =>
              act(src.sourceId, () => api.stopSource(src.sourceId), 'Source stopped')
            }
          />
        ))}
      </div>
    </Panel>
  )
}

function SourceCard({
  source,
  isTelemetry,
  transition,
  busy,
  onTakeControl,
  onDisplay,
  onStart,
  onStop,
}: {
  source: SourceInfo
  isTelemetry: boolean
  transition?: { allowed: boolean; reason: string }
  busy: boolean
  onTakeControl: () => void
  onDisplay: () => void
  onStart: () => void
  onStop: () => void
}) {
  const Icon = source.kind === 'PLC' ? Cpu : FlaskConical
  const healthy = source.state === 'CONNECTED' || source.state === 'DEGRADED'
  const synthetic = Boolean(
    (source.detail as Record<string, unknown> | undefined)?.synthetic,
  )

  return (
    <div
      className={classNames(
        'rounded-lg border p-3',
        source.controlActive
          ? 'border-state-run/50 bg-state-run/8'
          : healthy
            ? 'border-panel-700 bg-panel-800'
            : 'border-panel-700 bg-panel-800/60',
      )}
    >
      <div className="mb-2 flex flex-wrap items-center gap-2">
        <Icon
          size={16}
          className={source.kind === 'PLC' ? 'text-state-info' : 'text-state-twin'}
        />
        <span className="text-sm font-semibold text-ink-100">{source.name}</span>

        {source.controlActive && <Badge tone="run">IN CONTROL</Badge>}
        {isTelemetry && <Badge tone="info">DISPLAYED</Badge>}
        {!source.supportsControl && (
          <Badge tone="idle" icon={<Ban size={10} />}>
            telemetry only
          </Badge>
        )}
        {synthetic && (
          <Badge tone="warn" icon={<AlertTriangle size={10} />}>
            synthetic
          </Badge>
        )}
      </div>

      <div className="mb-2.5 grid grid-cols-2 gap-2 sm:grid-cols-4">
        <Field label="State" value={source.state} />
        <Field
          label="Quality"
          value={source.quality}
          tone={QUALITY_TONE[source.quality]}
        />
        <Field
          label="Last data"
          value={source.lastDataAt ? ago(source.lastDataAt) : 'never'}
          tone={source.stale ? 'warn' : undefined}
        />
        <Field label="Latency" value={`${num(source.latencyMs, 1)} ms`} />
      </div>

      {source.lastError && (
        <p className="mb-2 flex items-start gap-1.5 text-xs leading-snug text-state-warn">
          <AlertTriangle size={11} className="mt-0.5 shrink-0" />
          {source.lastError}
        </p>
      )}

      {source.errorCount > 0 && (
        <p className="mb-2 text-xs text-ink-500">
          {source.errorCount} error{source.errorCount === 1 ? '' : 's'}
          {source.reconnectCount > 0 && ` · ${source.reconnectCount} reconnects`}
        </p>
      )}

      <div className="flex flex-wrap gap-2">
        <Button
          variant={source.controlActive ? 'success' : 'primary'}
          size="sm"
          disabled={busy || !transition?.allowed || source.controlActive}
          onClick={onTakeControl}
          title={transition?.reason || 'Give this source machine control'}
        >
          {busy ? <Loader2 size={12} className="animate-spin" /> : <Activity size={12} />}
          {source.controlActive ? 'In control' : 'Take control'}
        </Button>

        <Button
          variant="ghost"
          size="sm"
          disabled={busy || isTelemetry}
          onClick={onDisplay}
          title="Show this source's data on the dashboards. Grants no control."
        >
          {isTelemetry ? 'Displaying' : 'Display'}
        </Button>

        {source.running ? (
          <Button
            variant="ghost"
            size="sm"
            disabled={busy || source.controlActive}
            onClick={onStop}
            title={
              source.controlActive
                ? 'Move control elsewhere before stopping this source'
                : 'Stop this source'
            }
          >
            <Square size={12} />
            Stop
          </Button>
        ) : (
          <Button variant="ghost" size="sm" disabled={busy} onClick={onStart}>
            <Play size={12} />
            Start
          </Button>
        )}
      </div>

      {transition && !transition.allowed && (
        <p className="mt-2 text-xs leading-snug text-ink-500">
          {transition.reason}
        </p>
      )}

      {source.detail && Object.keys(source.detail).length > 0 && (
        <details className="mt-2">
          <summary className="cursor-pointer text-xs uppercase tracking-wider text-ink-600 hover:text-ink-400">
            Adapter detail
          </summary>
          <pre className="mt-1.5 overflow-x-auto rounded bg-panel-950 p-2 font-mono text-xs leading-relaxed text-ink-400">
            {JSON.stringify(source.detail, null, 2)}
          </pre>
        </details>
      )}
    </div>
  )
}

function Field({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone?: 'run' | 'warn' | 'fault' | 'idle'
}) {
  const colour = {
    run: 'text-state-run',
    warn: 'text-state-warn',
    fault: 'text-state-fault',
    idle: 'text-ink-300',
  }[tone ?? 'idle']

  return (
    <div>
      <div className="text-xs uppercase tracking-wider text-ink-500">{label}</div>
      <div className={classNames('font-mono text-xs', colour)}>{value}</div>
    </div>
  )
}
