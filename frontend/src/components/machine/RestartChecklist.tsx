/**
 * Restart prerequisites and the frozen fault context.
 *
 * Errors sheet, 2026-08-19: "Even when the actual cycle is terminated midway
 * due to some emergency, the scada hub doesn't show that, and rather just
 * stops working and doesn't allow to restart the cycle."
 *
 * Two things fix that, and both are here:
 *
 * 1. **The frozen context.** The instant the lifecycle enters EMERGENCY or
 *    FAULT the backend captures the sequence step, every sensor, every valve
 *    and every safety bit as they were at that moment. It is preserved and
 *    displayed, so the state that caused the stop survives the stop.
 *
 * 2. **A checklist, not a dead button.** Restart is gated on the documented
 *    start interlocks, and each unsatisfied one is named. "Restart
 *    unavailable" with a reason is actionable; a greyed-out button is not.
 */

import { useState } from 'react'
import { Loader2, RotateCcw, Snowflake } from 'lucide-react'
import { api } from '../../services/api'
import { selectMachine, useMachine } from '../../stores/machineStore'
import { clockMs } from '../../utils/format'
import { Badge, Button, CheckRow, Note, Panel } from '../common/Primitives'

export function RestartChecklist() {
  const snapshot = useMachine((s) => s.snapshot)
  const machine = useMachine(selectMachine)
  const pushToast = useMachine((s) => s.pushToast)
  const [busy, setBusy] = useState(false)
  const [showForce, setShowForce] = useState(false)

  const checklist = snapshot?.restartChecklist ?? []
  const blockers = checklist.filter((i) => i.required && i.satisfied !== true)
  const ready = blockers.length === 0

  async function reset(force: boolean) {
    setBusy(true)
    const res = await api.resetCycle(force)
    setBusy(false)
    setShowForce(false)
    pushToast(
      res.ok
        ? {
            kind: 'ok',
            title: force ? 'Reset FORCED past blockers' : 'Cycle reset issued',
            detail: force ? 'The override is recorded in the event log.' : undefined,
          }
        : { kind: 'warn', title: 'Reset blocked', detail: res.error.message },
    )
  }

  return (
    <Panel
      title="Restart checklist"
      actions={
        <Badge tone={ready ? 'run' : 'fault'}>
          {ready ? 'Ready to restart' : `${blockers.length} blocking`}
        </Badge>
      }
    >
      <ul className="mb-3 divide-y divide-panel-800">
        {checklist.map((item) => (
          <CheckRow
            key={item.key}
            label={item.label}
            satisfied={item.satisfied}
            required={item.required}
            detail={item.detail}
          />
        ))}
      </ul>

      {!ready && (
        <Note tone="fault">
          Restart unavailable. Clear the physical cause first.
        </Note>
      )}

      <div className="mt-3 flex gap-2">
        <Button
          variant={ready ? 'warn' : 'ghost'}
          onClick={() => reset(false)}
          disabled={busy || !ready}
          className="flex-1"
        >
          {busy ? <Loader2 size={15} className="animate-spin" /> : <RotateCcw size={15} />}
          Reset cycle
        </Button>
        {!ready && (
          <Button
            variant="ghost"
            onClick={() => setShowForce((v) => !v)}
            disabled={busy}
            title="Engineering override"
          >
            Override…
          </Button>
        )}
      </div>

      {showForce && (
        <div className="mt-3 rounded-lg border border-state-fault/50 bg-state-fault/8 p-3">
          <p className="mb-2 text-xs leading-relaxed text-state-fault/90">
            Forcing a reset issues Cycle_Reset while{' '}
            {blockers.map((b) => b.label).join(', ')}{' '}
            {blockers.length === 1 ? 'is' : 'are'} not satisfied. The machine may
            not be in a safe or known position. The override is recorded in the
            event log with the blockers listed.
          </p>
          <div className="flex gap-2">
            <Button variant="danger" size="sm" onClick={() => reset(true)} disabled={busy}>
              Force reset anyway
            </Button>
            <Button variant="ghost" size="sm" onClick={() => setShowForce(false)}>
              Cancel
            </Button>
          </div>
        </div>
      )}

      {machine?.frozenContext && <FrozenContext ctx={machine.frozenContext} />}
    </Panel>
  )
}

// ---------------------------------------------------------------------------

function FrozenContext({
  ctx,
}: {
  ctx: NonNullable<ReturnType<typeof selectMachine>>['frozenContext']
}) {
  if (!ctx) return null

  const activeSensors = Object.entries(ctx.sensors).filter(([, v]) => v === true)
  const activeValves = Object.entries(ctx.valves).filter(([, v]) => v === true)

  return (
    <div className="mt-4 rounded-lg border border-state-warn/40 bg-state-warn/6 p-3">
      <div className="mb-2 flex items-center gap-2">
        <Snowflake size={14} className="text-state-warn" />
        <span className="text-xs font-semibold uppercase tracking-wider text-state-warn">
          State preserved at the moment of {ctx.reason}
        </span>
        <span className="ml-auto font-mono text-xs text-ink-500">
          {clockMs(ctx.at)}
        </span>
      </div>

      <dl className="space-y-1.5 text-xs">
        <FrozenRow label="Lifecycle">{ctx.lifecycle}</FrozenRow>
        <FrozenRow label="Mode">{ctx.mode}</FrozenRow>
        <FrozenRow label="Cycle">{ctx.cycleId ?? '--'}</FrozenRow>
        <FrozenRow label="Sequence step">
          {ctx.sequenceStepIndex} &middot; {ctx.sequenceStepName ?? '--'}
        </FrozenRow>
        <FrozenRow label="Waiting for">{ctx.waitingFor ?? 'nothing'}</FrozenRow>
        <FrozenRow label="Sensors active">
          {activeSensors.length
            ? activeSensors.map(([k]) => k.replace('sensor.', '')).join(', ')
            : 'none'}
        </FrozenRow>
        <FrozenRow label="Valves energised">
          {activeValves.length
            ? activeValves.map(([k]) => k.replace('valve.', '').replace('.state', '')).join(', ')
            : 'none'}
        </FrozenRow>
      </dl>
    </div>
  )
}

function FrozenRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex gap-3">
      <dt className="w-28 shrink-0 text-xs uppercase tracking-wider text-ink-500">
        {label}
      </dt>
      <dd className="min-w-0 flex-1 font-mono text-ink-300">{children}</dd>
    </div>
  )
}
