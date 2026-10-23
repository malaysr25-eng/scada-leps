/**
 * The operating-mode banner.
 *
 * WHY THIS IS LARGE AND LOUD
 * --------------------------
 * The single most dangerous confusion in a system that can run against either a
 * real PLC or a simulation is not knowing which one you are looking at. An
 * operator who believes simulated numbers are plant data will draw wrong
 * conclusions about a real machine.
 *
 * So the mode is stated in full width, in words, with a colour and an icon, at
 * the top of every page:
 *
 *     [ PLC / REAL MODE ]  PLC: CONNECTED  SOURCE: Siemens S7-1200  LAST DATA: …
 *     [ SIMULATION MODE ]  SIM: RUNNING    SOURCE: MATLAB/Simulink  LAST DATA: …
 *     [ DISCONNECTED ]     NO ACTIVE DATA SOURCE
 *
 * Simulation mode also gets a diagonal hazard stripe, so it is distinguishable
 * from PLC mode at a glance across a room and without relying on colour alone.
 *
 * The backend is authoritative: this renders `snapshot.dataSources`, it never
 * decides anything. Selecting a source POSTs and waits for the backend to
 * agree.
 */

import { useState } from 'react'
import {
  AlertTriangle, Ban, Cable, CheckCircle2, Cpu, Database, FlaskConical,
  Loader2, Radio, Unplug,
} from 'lucide-react'
import { api } from '../../services/api'
import { selectConnection, useMachine } from '../../stores/machineStore'
import type { Quality, SystemMode } from '../../types'
import { ago, classNames, clockMs } from '../../utils/format'
import { Badge, Button } from '../common/Primitives'

const MODE_META: Record<
  SystemMode,
  { label: string; tone: string; bg: string; border: string; icon: typeof Cpu; hazard: boolean }
> = {
  PLC_CONNECTED: {
    label: 'PLC / REAL MODE',
    tone: 'text-state-run', bg: 'bg-state-run/12', border: 'border-state-run/50',
    icon: Cpu, hazard: false,
  },
  PLC_CONNECTING: {
    label: 'PLC CONNECTING',
    tone: 'text-state-warn', bg: 'bg-state-warn/12', border: 'border-state-warn/50',
    icon: Loader2, hazard: false,
  },
  SIMULATION_RUNNING: {
    label: 'SIMULATION MODE',
    tone: 'text-state-twin', bg: 'bg-state-twin/12', border: 'border-state-twin/55',
    icon: FlaskConical, hazard: true,
  },
  SIMULATION_STOPPED: {
    label: 'SIMULATION STOPPED',
    tone: 'text-ink-400', bg: 'bg-panel-800', border: 'border-panel-600',
    icon: FlaskConical, hazard: true,
  },
  DISCONNECTED: {
    label: 'DISCONNECTED',
    tone: 'text-state-fault', bg: 'bg-state-fault/12', border: 'border-state-fault/55',
    icon: Unplug, hazard: false,
  },
  ERROR: {
    label: 'SOURCE ERROR',
    tone: 'text-state-fault', bg: 'bg-state-fault/12', border: 'border-state-fault/55',
    icon: AlertTriangle, hazard: false,
  },
}

// `--simulate` runs the stand-in PLC behind the real PLC adapter, so the
// source manager reports PLC_CONNECTED. The PLC link itself says SIMULATED;
// the banner must never call that real.
const SIMULATED_PLC_META = {
  label: 'SIMULATED PLC',
  tone: 'text-state-twin', bg: 'bg-state-twin/12', border: 'border-state-twin/55',
  icon: FlaskConical, hazard: true,
}

const QUALITY_TONE: Record<Quality, string> = {
  GOOD: 'text-state-run',
  STALE: 'text-state-warn',
  UNCERTAIN: 'text-state-warn',
  BAD: 'text-state-fault',
}

export function ModeBanner() {
  const sources = useMachine((s) => s.snapshot?.dataSources)
  const database = useMachine((s) => s.snapshot?.database)
  const recording = useMachine((s) => s.snapshot?.recording)
  const plcLink = useMachine(selectConnection)?.plc
  const pushToast = useMachine((s) => s.pushToast)
  const [busy, setBusy] = useState(false)
  const [open, setOpen] = useState(false)

  if (!sources) return null

  const simulatedPlc = sources.mode === 'PLC_CONNECTED' && plcLink === 'SIMULATED'
  const meta = simulatedPlc
    ? SIMULATED_PLC_META
    : MODE_META[sources.mode] ?? MODE_META.DISCONNECTED
  const Icon = meta.icon

  async function takeControl(sourceId: string) {
    setBusy(true)
    const res = await api.setControlSource(sourceId)
    setBusy(false)
    if (!res.ok) {
      pushToast({
        kind: 'warn',
        title: 'Control change refused',
        detail: res.error.message,
      })
    } else {
      pushToast({ kind: 'ok', title: 'Control source changed' })
      setOpen(false)
    }
  }

  async function useTelemetry(sourceId: string) {
    setBusy(true)
    const res = await api.setTelemetrySource(sourceId)
    setBusy(false)
    pushToast(
      res.ok
        ? {
            kind: 'ok',
            title: 'Telemetry source changed',
            detail: 'Display only — machine control is unaffected.',
          }
        : { kind: 'warn', title: 'Refused', detail: res.error.message },
    )
  }

  return (
    <div
      className={classNames(
        'relative overflow-hidden border-b px-4 py-2',
        meta.bg, meta.border,
      )}
    >
      {/* Hazard stripes for simulation: readable without colour. */}
      {meta.hazard && (
        <div
          className="pointer-events-none absolute inset-0 opacity-[0.10]"
          style={{
            backgroundImage:
              'repeating-linear-gradient(45deg,currentColor 0 10px,transparent 10px 20px)',
          }}
        />
      )}

      <div className="relative flex flex-wrap items-center gap-x-6 gap-y-2">
        <div className="flex items-center gap-2.5">
          <Icon
            size={20}
            className={classNames(
              meta.tone,
              sources.mode === 'PLC_CONNECTING' && 'animate-spin',
            )}
          />
          <span
            className={classNames(
              'text-base font-bold uppercase tracking-[0.16em]',
              meta.tone,
            )}
          >
            [ {meta.label} ]
          </span>
        </div>

        <Field
          icon={Cable}
          label={sources.mode.startsWith('SIM') ? 'Simulation' : 'PLC'}
          value={
            simulatedPlc
              ? 'SIMULATED'
              : sources.sources.find((s) => s.sourceId === sources.controlSourceId)
                  ?.state ?? 'NO CONTROL SOURCE'
          }
          tone={meta.tone}
        />

        <Field
          icon={Radio}
          label="Source"
          value={
            simulatedPlc
              ? 'Stand-in PLC (no hardware)'
              : sources.telemetrySourceName ?? 'none'
          }
        />

        <Field
          icon={CheckCircle2}
          label="Last data"
          value={
            sources.lastDataAt
              ? `${clockMs(sources.lastDataAt)}  (${ago(sources.lastDataAt)})`
              : 'never'
          }
          tone={sources.stale ? 'text-state-warn' : undefined}
        />

        <div className="leading-tight">
          <div className="text-xs uppercase tracking-[0.16em] text-ink-500">
            Quality
          </div>
          <div
            className={classNames(
              'text-sm font-bold',
              QUALITY_TONE[sources.quality] ?? 'text-ink-400',
            )}
          >
            {sources.quality}
            {sources.stale && <span className="ml-1.5">· STALE</span>}
          </div>
        </div>

        <div className="ml-auto flex items-center gap-2">
          {recording?.recording && (
            <Badge tone="fault">
              <span className="mr-1 inline-block h-2 w-2 rounded-full bg-state-fault" />
              REC {recording.session?.sampleCount ?? 0}
            </Badge>
          )}

          <Badge
            tone={
              !database?.enabled ? 'idle'
                : database.healthy ? 'run' : 'warn'
            }
            icon={<Database size={11} />}
            title={
              database?.enabled
                ? `${database.written} rows written, ${database.dropped} dropped, queue ${database.queueDepth}/${database.queueCapacity}`
                : 'Database disabled in config'
            }
          >
            {!database?.enabled ? 'DB off' : database.ready ? 'DB ok' : 'DB starting'}
          </Badge>

          <Button variant="ghost" size="sm" onClick={() => setOpen((v) => !v)}>
            Sources…
          </Button>
        </div>
      </div>

      {open && (
        <div className="relative mt-3 rounded-lg border border-panel-600 bg-panel-900 p-3">
          <p className="mb-2 text-xs leading-relaxed text-ink-400">
            {sources.note}
          </p>
          <div className="space-y-2">
            {sources.sources.map((src) => {
              const transition = sources.transitions.find(
                (t) => t.sourceId === src.sourceId,
              )
              return (
                <div
                  key={src.sourceId}
                  className={classNames(
                    'flex flex-wrap items-center gap-3 rounded-lg border p-2.5',
                    src.controlActive
                      ? 'border-state-run/50 bg-state-run/8'
                      : 'border-panel-700 bg-panel-800',
                  )}
                >
                  <div className="min-w-[200px]">
                    <div className="flex items-center gap-2">
                      <span className="text-sm font-semibold text-ink-200">
                        {src.name}
                      </span>
                      {src.controlActive && <Badge tone="run">CONTROL</Badge>}
                      {!src.supportsControl && (
                        <Badge tone="idle" icon={<Ban size={10} />}>
                          telemetry only
                        </Badge>
                      )}
                    </div>
                    <div className="mt-0.5 font-mono text-xs text-ink-500">
                      {src.kind} · {src.state} · quality {src.quality}
                      {src.ageSeconds !== null && ` · ${src.ageSeconds.toFixed(1)}s old`}
                    </div>
                    {src.lastError && (
                      <div className="mt-0.5 text-xs text-state-warn">
                        {src.lastError}
                      </div>
                    )}
                  </div>

                  <div className="ml-auto flex items-center gap-2">
                    <Button
                      variant="ghost"
                      size="sm"
                      disabled={busy || src.sourceId === sources.telemetrySourceId}
                      onClick={() => useTelemetry(src.sourceId)}
                      title="Show this source's data on the dashboards. Grants no control."
                    >
                      {src.sourceId === sources.telemetrySourceId
                        ? 'Displaying'
                        : 'Display'}
                    </Button>
                    <Button
                      variant={src.controlActive ? 'success' : 'primary'}
                      size="sm"
                      disabled={busy || !transition?.allowed || src.controlActive}
                      onClick={() => takeControl(src.sourceId)}
                      title={transition?.reason || 'Give this source machine control'}
                    >
                      {src.controlActive ? 'In control' : 'Take control'}
                    </Button>
                  </div>

                  {transition && !transition.allowed && (
                    <p className="w-full text-xs leading-snug text-ink-500">
                      {transition.reason}
                    </p>
                  )}
                </div>
              )
            })}
          </div>
        </div>
      )}
    </div>
  )
}

function Field({
  icon: Icon,
  label,
  value,
  tone,
}: {
  icon: typeof Cpu
  label: string
  value: string
  tone?: string
}) {
  return (
    <div className="flex items-center gap-1.5 leading-tight">
      <Icon size={13} className="text-ink-500" />
      <div>
        <div className="text-xs uppercase tracking-[0.16em] text-ink-500">
          {label}
        </div>
        <div className={classNames('text-sm font-semibold', tone ?? 'text-ink-200')}>
          {value}
        </div>
      </div>
    </div>
  )
}
