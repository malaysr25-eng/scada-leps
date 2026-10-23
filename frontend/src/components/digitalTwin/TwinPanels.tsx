/**
 * Digital twin comparison panels.
 *
 * WHAT IS BEING COMPARED
 * ----------------------
 * The MATLAB model is a batch simulator: `run_factory_simulation` integrates a
 * whole 31.08 s cycle and returns a LOG struct. It is exported once to JSON by
 * `tools/export_twin_reference.m` and replayed against the live cycle clock
 * here. So the "predicted" column is a **nominal reference trajectory**, not a
 * live co-simulation.
 *
 * WHY EVERY NUMBER CARRIES A PROVENANCE TAG
 * -----------------------------------------
 * The model's own documentation is unusually candid, and this UI honours it
 * rather than papering over it:
 *
 *   - 69 of 97 tagged parameters are unmeasured (PLH + ASM + EST).
 *   - `SCALE` is recorded as "CONFIRMED INCORRECT".
 *   - 12.5 s of the 31.08 s nominal cycle is placeholder operator time.
 *   - Every Janatics component is a *compatible candidate*, not a part known
 *     to be installed.
 *   - The model is deterministic: it predicts zero cycle-time variation.
 *
 * A divergence therefore means "these two disagree", never "the machine is
 * wrong". The provenance chip on each figure says which side to doubt.
 */

import { useEffect, useState } from 'react'
import {
  AlertTriangle, Ban, CheckCircle2, Download, RefreshCw,
} from 'lucide-react'
import { api } from '../../services/api'
import { selectTwin, useMachine } from '../../stores/machineStore'
import type { Provenance } from '../../types'
import { classNames, num } from '../../utils/format'
import {
  Badge, Button, EmptyState, Note, Panel, ProvenanceTag,
} from '../common/Primitives'

export function TwinStatusPanel() {
  const twin = useMachine(selectTwin)
  const pushToast = useMachine((s) => s.pushToast)
  const [busy, setBusy] = useState(false)

  async function reload() {
    setBusy(true)
    const res = await api.reloadTwin()
    setBusy(false)
    pushToast(
      res.ok
        ? { kind: 'ok', title: 'Twin reference reloaded' }
        : { kind: 'warn', title: 'No twin reference', detail: res.error.message },
    )
  }

  const available = twin?.available ?? false

  return (
    <Panel
      title="Digital twin reference"
      actions={
        <div className="flex items-center gap-2">
          <Badge tone={available ? 'twin' : 'idle'}>
            {available ? 'Reference loaded' : 'No reference'}
          </Badge>
          <Button variant="ghost" size="sm" onClick={reload} disabled={busy}>
            <RefreshCw size={13} className={busy ? 'animate-spin' : undefined} />
            Reload
          </Button>
        </div>
      }
    >
      {!available ? (
        <div className="space-y-3">
          <Note tone="warn">{twin?.error || 'No exported reference is loaded.'}</Note>
          <div className="rounded-lg border border-panel-700 bg-panel-900 p-3">
            <p className="mb-2 flex items-center gap-1.5 text-xs font-semibold text-ink-300">
              <Download size={13} />
              To generate one
            </p>
            <pre className="overflow-x-auto rounded bg-panel-950 p-2.5 font-mono text-xs leading-relaxed text-ink-300">
{`cd Factory_Simulation
matlab -batch "addpath('<path>/scada_platform/tools'); export_twin_reference"`}
            </pre>
          </div>
        </div>
      ) : (
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-4">
            <TwinStat
              label="Real elapsed"
              value={num(twin?.cycle.realElapsed, 1)}
              unit="s"
              provenance="LIVE"
            />
            <TwinStat
              label="Nominal cycle"
              value={num(twin?.cycle.nominalCycleTime, 2)}
              unit="s"
              provenance="PLH"
              hint="12.5 s of the model's nominal cycle is unmeasured operator placeholder time."
            />
            <TwinStat
              label="Predicted state"
              value={twin?.cycle.predictedState ?? '--'}
              provenance="ASM"
            />
            <div>
              <div className="text-xs uppercase tracking-[0.14em] text-ink-500">
                Agreement
              </div>
              <div className="mt-1">
                <AgreementBadge value={twin?.cycle.agreement} />
              </div>
            </div>
          </div>

          {(twin?.modelCaveats?.length ?? 0) > 0 && (
            <details className="rounded-lg border border-state-warn/35 bg-state-warn/6 px-3 py-2">
              <summary className="flex cursor-pointer items-center gap-1.5 text-xs font-semibold text-state-warn">
                <AlertTriangle size={13} />
                Model caveats ({twin?.modelCaveats.length})
              </summary>
              <ul className="mt-1.5 ml-4 list-disc space-y-1 text-xs text-ink-400">
                {twin?.modelCaveats.map((c) => (
                  <li key={c}>{c}</li>
                ))}
              </ul>
            </details>
          )}
        </div>
      )}
    </Panel>
  )
}

function TwinStat({
  label,
  value,
  unit,
  provenance,
  hint,
}: {
  label: string
  value: string
  unit?: string
  provenance: Provenance
  hint?: string
}) {
  return (
    <div title={hint}>
      <div className="flex items-center gap-1.5 text-xs uppercase tracking-[0.14em] text-ink-500">
        <span className="truncate">{label}</span>
        <ProvenanceTag value={provenance} />
      </div>
      <div className="mt-0.5 truncate font-mono text-base text-ink-100">
        {value}
        {unit && <span className="ml-1 text-xs text-ink-500">{unit}</span>}
      </div>
    </div>
  )
}

function AgreementBadge({ value }: { value?: string }) {
  if (value === 'AGREE') {
    return (
      <Badge tone="run" icon={<CheckCircle2 size={11} />}>
        Agree
      </Badge>
    )
  }
  if (value === 'DIVERGENT') {
    return (
      <Badge tone="warn" icon={<AlertTriangle size={11} />}>
        Divergent
      </Badge>
    )
  }
  return <Badge tone="idle">Unknown</Badge>
}

// ---------------------------------------------------------------------------

export function TwinComparisonPanel() {
  const twin = useMachine(selectTwin)

  return (
    <Panel
      title="Real vs predicted"
    >
      <div className="space-y-2">
        {(twin?.conveyors ?? []).map((c) => (
          <div
            key={c.index}
            className={classNames(
              'rounded-lg border p-3',
              c.status === 'MISMATCH'
                ? 'border-state-fault/50 bg-state-fault/8'
                : c.status === 'DIVERGENT'
                  ? 'border-state-warn/45 bg-state-warn/8'
                  : 'border-panel-700 bg-panel-800',
            )}
          >
            <div className="mb-2 flex items-center gap-2">
              <span className="text-sm font-semibold text-ink-200">
                Conveyor {c.index}
              </span>
              <Badge
                tone={
                  c.status === 'OK'
                    ? 'run'
                    : c.status === 'MISMATCH'
                      ? 'fault'
                      : c.status === 'DIVERGENT'
                        ? 'warn'
                        : 'idle'
                }
              >
                {c.status === 'NO_REFERENCE' ? 'No reference' : c.status}
              </Badge>
              <span className="ml-auto text-xs uppercase tracking-wider text-ink-500">
                Run coil {c.runOutput === true ? 'ON' : c.runOutput === false ? 'OFF' : 'N/A'}
              </span>
            </div>

            <div className="grid grid-cols-3 gap-3">
              <CompareCell
                label="Commanded"
                value={num(c.commanded, 3)}
                provenance={c.commandedProvenance}
              />
              <CompareCell
                label="Feedback"
                value={num(c.feedback, 3)}
                provenance={c.feedbackProvenance}
                tone={c.status === 'MISMATCH' ? 'fault' : 'run'}
              />
              <CompareCell
                label="Twin predicted"
                value={num(c.predicted, 3)}
                provenance={c.predictedProvenance}
                tone="twin"
              />
            </div>

            {c.detail && (
              <p className="mt-2 text-xs leading-snug text-ink-400">{c.detail}</p>
            )}
          </div>
        ))}

        {(twin?.signals ?? []).map((s) => (
          <div
            key={s.key}
            className="rounded-lg border border-panel-700 bg-panel-800 p-3"
          >
            <div className="mb-2 text-sm font-semibold text-ink-200">{s.label}</div>
            <div className="grid grid-cols-2 gap-3">
              <CompareCell
                label="Live"
                value={num(s.live, 2)}
                unit={s.unit}
                provenance={s.liveProvenance}
              />
              <CompareCell
                label="Twin predicted"
                value={num(s.predicted, 2)}
                unit={s.unit}
                provenance={s.predictedProvenance}
                tone="twin"
              />
            </div>
          </div>
        ))}
      </div>
    </Panel>
  )
}

function CompareCell({
  label,
  value,
  unit,
  provenance,
  tone = 'idle',
}: {
  label: string
  value: string
  unit?: string
  provenance: Provenance | null | undefined
  tone?: 'idle' | 'run' | 'fault' | 'twin'
}) {
  const colour = {
    idle: 'text-ink-200',
    run: 'text-state-run',
    fault: 'text-state-fault',
    twin: 'text-state-twin',
  }[tone]

  return (
    <div>
      <div className="flex items-center gap-1.5 text-xs uppercase tracking-wider text-ink-500">
        <span>{label}</span>
        <ProvenanceTag value={provenance} />
      </div>
      <div className={classNames('mt-0.5 font-mono text-sm tabular-nums', colour)}>
        {value}
        {unit && <span className="ml-1 text-xs text-ink-500">{unit}</span>}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------

export function TwinMismatchPanel() {
  const twin = useMachine(selectTwin)
  const mismatches = twin?.mismatches ?? []

  return (
    <Panel
      title="Twin mismatches"
      actions={
        <Badge tone={mismatches.length ? 'warn' : 'run'}>
          {mismatches.length || 'none'}
        </Badge>
      }
    >
      {mismatches.length === 0 ? (
        <EmptyState>
          No divergence detected between the live machine and the reference
          trajectory.
        </EmptyState>
      ) : (
        <ul className="space-y-2">
          {mismatches.map((m) => (
            <li
              key={m.key}
              className="rounded-lg border border-state-warn/45 bg-state-warn/8 p-3"
            >
              <div className="mb-1 flex items-center gap-2">
                <AlertTriangle size={13} className="text-state-warn" />
                <span className="text-sm font-semibold text-state-warn">
                  {m.subject}
                </span>
                <Badge tone="warn" className="ml-auto !py-0 !text-xs">
                  {m.status}
                </Badge>
              </div>
              <p className="text-xs leading-relaxed text-ink-300">{m.detail}</p>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  )
}

// ---------------------------------------------------------------------------

export function ProvenanceLegend() {
  const twin = useMachine(selectTwin)
  const legend = twin?.provenanceLegend ?? {}

  return (
    <Panel
      title="Data provenance"
    >
      <ul className="space-y-2">
        {Object.entries(legend).map(([code, info]) => (
          <li key={code} className="flex gap-2.5 text-xs">
            <ProvenanceTag value={code} />
            <div className="min-w-0">
              <div className="font-semibold text-ink-300">{info.label}</div>
              <div className="text-xs leading-snug text-ink-500">{info.meaning}</div>
            </div>
          </li>
        ))}
      </ul>
    </Panel>
  )
}

// ---------------------------------------------------------------------------

export function TwinReferenceDetail() {
  const [meta, setMeta] = useState<Record<string, unknown> | null>(null)

  useEffect(() => {
    void api.twinReference().then((res) => {
      if (res.ok) setMeta(res.data)
    })
  }, [])

  const available = meta?.available === true
  const transitions = (meta?.transitions ?? []) as Array<{
    t: number
    index: number
    state: string
  }>

  return (
    <Panel
      title="Reference trajectory"
      subtitle={
        available
          ? `${transitions.length} state transitions from the exported LOG`
          : 'Not loaded'
      }
    >
      {!available ? (
        <EmptyState>
          <span className="flex flex-col items-center gap-1">
            <Ban size={18} className="text-ink-600" />
            Export a reference from MATLAB to populate this.
          </span>
        </EmptyState>
      ) : (
        <div className="max-h-[420px] overflow-y-auto">
          <table className="w-full text-left text-xs">
            <thead className="sticky top-0 bg-panel-850">
              <tr className="border-b border-panel-700 text-xs uppercase tracking-wider text-ink-500">
                <th className="py-1.5 pr-3 font-medium">t (s)</th>
                <th className="py-1.5 pr-3 font-medium">#</th>
                <th className="py-1.5 font-medium">Twin state</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-panel-800">
              {transitions.map((tr, i) => (
                <tr key={i} className="hover:bg-panel-800/60">
                  <td className="py-1 pr-3 font-mono tabular-nums text-state-twin">
                    {tr.t.toFixed(3)}
                  </td>
                  <td className="py-1 pr-3 font-mono text-ink-500">{tr.index}</td>
                  <td className="py-1 font-mono text-ink-300">{tr.state}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  )
}
