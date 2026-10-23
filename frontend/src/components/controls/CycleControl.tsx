/**
 * Automatic cycle control.
 *
 * THE RULE THIS PANEL EXISTS TO ENFORCE
 * -------------------------------------
 * Errors sheet, 2026-08-19: "if 25mm and 50mm blocks are selected as 0, the
 * machine starts but doesn't stop unless few actuators are activated."
 *
 * Start is disabled here whenever qty25 + qty50 <= 0, and the reason is
 * spelled out on screen rather than left as a dead button. The identical rule
 * is enforced in `POST /api/cycle/start`, so a client that ignores this UI --
 * a stale tab, a curl one-liner, a future mobile view -- still cannot start a
 * zero-quantity cycle. UI validation is courtesy; backend validation is the
 * control.
 */

import { useEffect, useState } from 'react'
import { Loader2, Play, Rocket, ShieldAlert } from 'lucide-react'
import { api } from '../../services/api'
import { useMachine } from '../../stores/machineStore'
import { classNames } from '../../utils/format'
import { Badge, Button, Note, Panel } from '../common/Primitives'

export function CycleControl() {
  const snapshot = useMachine((s) => s.snapshot)
  const pushToast = useMachine((s) => s.pushToast)
  const trackCommand = useMachine((s) => s.trackCommand)

  const [qty25, setQty25] = useState(0)
  const [qty50, setQty50] = useState(1)
  const [highSpeed, setHighSpeed] = useState(false)
  const [busy, setBusy] = useState(false)

  // Seed the inputs from the PLC's own setpoints once, so the operator sees
  // what the controller currently holds rather than an arbitrary default.
  const [seeded, setSeeded] = useState(false)
  useEffect(() => {
    if (seeded || !snapshot) return
    setQty25(snapshot.canStart.plcQty25 ?? 0)
    setQty50(snapshot.canStart.plcQty50 ?? 0)
    setHighSpeed(false)
    setSeeded(true)
  }, [snapshot, seeded])

  const total = qty25 + qty50
  const localValid = total > 0
  const backend = snapshot?.canStart
  const lifecycle = snapshot?.machine.lifecycle
  const mode = snapshot?.machine.mode ?? 'AUTO'

  const blocked =
    !localValid ||
    busy ||
    mode !== 'AUTO' ||
    !backend?.interlocksSatisfied ||
    lifecycle === 'AUTO_RUNNING' ||
    lifecycle === 'STARTING' ||
    lifecycle === 'EMERGENCY_STOPPED' ||
    lifecycle === 'DISCONNECTED'

  const reasons: string[] = []
  if (!localValid) reasons.push('Select at least one product before starting the cycle.')
  if (mode !== 'AUTO') reasons.push(`Switch to AUTO mode (currently ${mode}).`)
  backend?.reasons
    .filter((r) => !r.includes('at least one product') && !r.includes('AUTO mode'))
    .forEach((r) => reasons.push(r))

  async function start() {
    setBusy(true)
    const res = await api.startCycle(qty25, qty50, highSpeed)
    setBusy(false)

    if (res.ok) {
      res.data.commands.forEach(trackCommand)
      pushToast({
        kind: 'ok',
        title: 'Cycle start issued',
        detail: `${qty25} × 25 mm, ${qty50} × 50 mm. Quantities written before CMD_START.`,
      })
    } else {
      pushToast({
        kind: 'error',
        title: 'Start refused by the backend',
        detail: res.error.message,
      })
    }
  }

  async function engravingDone() {
    setBusy(true)
    const res = await api.engravingComplete()
    setBusy(false)
    pushToast(
      res.ok
        ? { kind: 'ok', title: 'Engraving acknowledged' }
        : { kind: 'error', title: 'Acknowledgement refused', detail: res.error.message },
    )
  }

  const awaitingOperator = snapshot?.sequence.waitingRole === 'cmd.engraving_completed'

  return (
    <Panel
      title="Automatic cycle"
      actions={
        <Badge tone={mode === 'AUTO' ? 'info' : 'warn'}>{mode} mode</Badge>
      }
    >
      <div className="space-y-4">
        <div className="grid grid-cols-2 gap-3">
          <QtyInput label="25 mm" value={qty25} onChange={setQty25} />
          <QtyInput label="50 mm" value={qty50} onChange={setQty50} />
        </div>

        <div className="flex items-center justify-between rounded-lg border border-panel-700 bg-panel-800 px-3 py-2">
          <span className="text-xs uppercase tracking-wider text-ink-400">
            Total ordered
          </span>
          <span
            className={classNames(
              'font-mono text-xl font-bold tabular-nums',
              localValid ? 'text-ink-100' : 'text-state-fault',
            )}
          >
            {total}
          </span>
        </div>

        <div className="flex items-center gap-2">
          <span className="text-xs uppercase tracking-wider text-ink-400">Profile</span>
          <div className="ml-auto flex rounded-lg border border-panel-600 bg-panel-850 p-0.5">
            {[
              { id: false, label: 'Normal' },
              { id: true, label: 'High speed' },
            ].map((opt) => (
              <button
                key={String(opt.id)}
                onClick={() => setHighSpeed(opt.id)}
                className={classNames(
                  'rounded-md px-3 py-1.5 text-xs font-semibold transition-colors',
                  highSpeed === opt.id
                    ? 'bg-state-info/20 text-state-info'
                    : 'text-ink-400 hover:text-ink-200',
                )}
              >
                {opt.label}
              </button>
            ))}
          </div>
        </div>

        <Button
          variant="success"
          size="lg"
          onClick={start}
          disabled={blocked}
          className="w-full"
          title={blocked ? reasons[0] : 'Write quantities and raise CMD_START'}
        >
          {busy ? <Loader2 size={18} className="animate-spin" /> : <Play size={18} />}
          Start cycle
        </Button>

        {reasons.length > 0 && (
          <Note tone={localValid ? 'warn' : 'fault'}>
            <span className="mb-1 flex items-center gap-1.5 font-semibold">
              <ShieldAlert size={13} />
              Start unavailable
            </span>
            <ul className="ml-4 list-disc space-y-0.5">
              {reasons.map((r) => (
                <li key={r}>{r}</li>
              ))}
            </ul>
          </Note>
        )}

        {/* The genuine manual step of the sequence (Sequencing rows 28-29). */}
        <div
          className={classNames(
            'rounded-lg border p-3 transition-colors',
            awaitingOperator
              ? 'border-state-warn/60 bg-state-warn/10'
              : 'border-panel-700 bg-panel-800/60',
          )}
        >
          <div className="mb-2 flex items-center gap-2">
            <Rocket
              size={14}
              className={awaitingOperator ? 'text-state-warn' : 'text-ink-500'}
            />
            <span className="text-xs font-semibold uppercase tracking-wider text-ink-300">
              Engraving step
            </span>
            {awaitingOperator && (
              <Badge tone="warn" className="ml-auto">
                Waiting for operator
              </Badge>
            )}
          </div>
          <Button
            variant={awaitingOperator ? 'warn' : 'ghost'}
            onClick={engravingDone}
            disabled={busy}
            className="w-full"
          >
            Engraving complete
          </Button>
        </div>
      </div>
    </Panel>
  )
}

// ---------------------------------------------------------------------------

function QtyInput({
  label,
  value,
  onChange,
}: {
  label: string
  value: number
  onChange: (n: number) => void
}) {
  return (
    <label className="block">
      <span className="mb-1 block text-xs uppercase tracking-[0.14em] text-ink-500">
        {label}
      </span>
      <div className="flex items-stretch overflow-hidden rounded-lg border border-panel-600 bg-panel-900">
        <button
          onClick={() => onChange(Math.max(0, value - 1))}
          className="w-10 shrink-0 text-lg text-ink-400 hover:bg-panel-700 hover:text-ink-100"
          aria-label={`Decrease ${label}`}
        >
          −
        </button>
        <input
          type="number"
          min={0}
          max={32767}
          value={value}
          onChange={(e) => {
            const n = parseInt(e.target.value, 10)
            onChange(Number.isNaN(n) ? 0 : Math.max(0, Math.min(32767, n)))
          }}
          className="min-w-0 flex-1 border-x border-panel-600 bg-transparent py-2 text-center font-mono text-lg tabular-nums text-ink-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-state-info/60"
        />
        <button
          onClick={() => onChange(Math.min(32767, value + 1))}
          className="w-10 shrink-0 text-lg text-ink-400 hover:bg-panel-700 hover:text-ink-100"
          aria-label={`Increase ${label}`}
        >
          +
        </button>
      </div>
    </label>
  )
}
