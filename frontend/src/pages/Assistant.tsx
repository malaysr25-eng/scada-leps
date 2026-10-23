/**
 * Assistant -- the chat in the middle, what it talks about around it.
 *
 *   left    the cell: lifecycle, mode, air (with its last 10 minutes), the
 *           start interlocks, and what is NOT sensed (the magazine)
 *   middle  the conversation (AssistantChat)
 *   right   the cycle now (step, waiting for, order progress) and the
 *           background programs and plan tasks the assistant can start/stop
 *
 * The side panels read the same snapshot as every other page, so they agree
 * with Overview to the millisecond; only the programs list comes from the
 * assistant's server.
 */

import { useEffect, useRef, useState } from 'react'
import { Activity, Cpu, Gauge, Play, RefreshCw, Square, Wind } from 'lucide-react'
import { AssistantChat } from '../components/assistant/AssistantChat'
import { Badge, Button, CheckRow, Lamp, Metric, Note, Panel } from '../components/common/Primitives'
import { assistant, type AssistantProgram, type AssistantTask } from '../services/assistant'
import { useAssistant } from '../stores/assistantStore'
import {
  selectInventory, selectMachine, selectSafety, selectSequence, useMachine,
} from '../stores/machineStore'
import { classNames, duration, num } from '../utils/format'

const AIR_LOW = 3.5            // bar: below this, report it (the cell runs at ~4.4)

export function AssistantPage() {
  return (
    <div className="grid h-[calc(100vh-150px)] min-h-[560px] gap-4 xl:grid-cols-[300px_minmax(0,1fr)_320px]">
      <div className="hidden min-h-0 space-y-4 overflow-y-auto xl:block">
        <CellNow />
        <AirPanel />
      </div>
      <section className="flex min-h-0 flex-col overflow-hidden rounded-xl border border-panel-700 bg-panel-850 shadow-panel">
        <AssistantChat />
      </section>
      <div className="hidden min-h-0 space-y-4 overflow-y-auto xl:block">
        <CycleNow />
        <Programs />
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------
// left
// ---------------------------------------------------------------------------

function CellNow() {
  const machine = useMachine(selectMachine)
  const safety = useMachine(selectSafety)
  const canStart = useMachine((s) => s.snapshot?.canStart)
  const life = machine?.lifecycle ?? 'DISCONNECTED'
  const tone =
    life === 'AUTO_RUNNING' || life === 'STARTING' ? 'run'
      : life === 'READY' || life === 'IDLE' || life === 'COMPLETED' ? 'info'
        : life === 'FAULT' || life === 'EMERGENCY_STOPPED' || life === 'RECOVERY_REQUIRED' ? 'fault'
          : 'warn'

  return (
    <Panel title="Cell" actions={<Badge tone={tone}>{life.replace(/_/g, ' ')}</Badge>}>
      <div className="mb-3 grid grid-cols-2 gap-3">
        <Metric label="Mode" value={machine?.mode ?? '--'} />
        <Metric label="Cycles today" value={machine?.cycleCount ?? '--'} />
      </div>
      <ul className="-my-1">
        <CheckRow label="Emergency circuit healthy" satisfied={safety?.hardwareEmergencyHealthy ?? null} required />
        <CheckRow label="Air pressure OK" satisfied={safety?.airPressureHealthy ?? null} required />
        <CheckRow label="Engraving plate at home" satisfied={safety?.engravingPlateHome ?? null} required />
        <CheckRow
          label="All cylinders home"
          satisfied={safety?.allCylindersHome ?? null}
          required
          detail="Computed by the PLC, not sensed. If you see every cylinder retracted, tell LEPS."
        />
        <CheckRow label="Startup healthy" satisfied={safety?.startupHealthy ?? null} required />
      </ul>
      {canStart && !canStart.allowed && canStart.reasons.length > 0 && (
        <p className="mt-2 text-xs leading-snug text-ink-500">
          Start not possible yet: {canStart.reasons.join('; ')}
        </p>
      )}
      <div className="mt-3">
        <Note tone="warn">
          Magazine not sensed. Before a start LEPS asks which compartment has a block
          (50 mm → 1, 25 mm → 2).
        </Note>
      </div>
    </Panel>
  )
}

/** Pressure now, and a 10-minute line drawn from the live snapshots (kept in this page only). */
function AirPanel() {
  const bar = useMachine((s) => s.snapshot?.safety.pressureBar ?? null)
  const at = useMachine((s) => s.snapshot?.timestamp ?? 0)       // every snapshot, even when the value holds
  const hist = useRef<Array<[number, number]>>([])
  const [, tick] = useState(0)

  useEffect(() => {
    if (bar == null) return
    const now = Date.now()
    const h = hist.current
    if (!h.length || now - h[h.length - 1][0] >= 2000) {
      h.push([now, bar])
      while (h.length && now - h[0][0] > 600_000) h.shift()
      tick((n) => n + 1)
    }
  }, [bar, at])

  const pts = hist.current
  const low = bar != null && bar < AIR_LOW
  const min = Math.min(3, ...pts.map((p) => p[1]))
  const max = Math.max(5, ...pts.map((p) => p[1]))
  const W = 260
  const H = 64
  const t0 = pts.length ? pts[0][0] : 0
  const span = Math.max(60_000, pts.length ? pts[pts.length - 1][0] - t0 : 1)
  const y = (v: number) => H - ((v - min) / (max - min)) * H
  const line = pts.map(([t, v]) => `${((t - t0) / span) * W},${y(v)}`).join(' ')

  return (
    <Panel
      title="Air"
      actions={<Badge tone={bar == null ? 'idle' : low ? 'warn' : 'run'} icon={<Wind size={12} />}>{low ? 'low' : bar == null ? '--' : 'ok'}</Badge>}
    >
      <Metric label="Pressure" value={num(bar, 2)} unit="bar" tone={low ? 'warn' : 'idle'} />
      <svg viewBox={`0 0 ${W} ${H}`} className="mt-2 h-16 w-full" preserveAspectRatio="none">
        <line x1="0" x2={W} y1={y(AIR_LOW)} y2={y(AIR_LOW)} className="stroke-state-warn/50" strokeDasharray="4 4" />
        {pts.length > 1 && <polyline points={line} fill="none" className="stroke-state-info" strokeWidth="1.6" />}
      </svg>
      <p className="mt-1 text-xs text-ink-500">
        Since this page opened (up to 10 min). Dashed: {AIR_LOW} bar; normal is about 4.4 bar.
        {low && ' Check the compressor before the next cycle.'}
      </p>
    </Panel>
  )
}

// ---------------------------------------------------------------------------
// right
// ---------------------------------------------------------------------------

function CycleNow() {
  const machine = useMachine(selectMachine)
  const seq = useMachine(selectSequence)
  const inv = useMachine(selectInventory)
  const running = machine?.lifecycle === 'AUTO_RUNNING' || machine?.lifecycle === 'STARTING'
  const done = inv?.progress.plcTotalProducts ?? null
  const total = inv?.order.total ?? 0

  return (
    <Panel
      title="Cycle now"
      actions={
        seq?.stalled ? <Badge tone="fault">stalled</Badge>
          : seq?.awaitingOperator ? <Badge tone="warn">your turn</Badge>
            : running ? <Badge tone="run" icon={<Activity size={12} />}>running</Badge>
              : <Badge>idle</Badge>
      }
    >
      <div className="mb-3 grid grid-cols-2 gap-3">
        <Metric label="Cycle" value={<span className="text-sm">{machine?.cycleId ?? '--'}</span>} />
        <Metric label="Elapsed" value={duration(machine?.cycleElapsed ?? null)} />
      </div>
      <div className="rounded-lg border border-panel-700 bg-panel-900 p-2.5">
        <div className="flex items-baseline gap-2">
          <span className="font-mono text-xs text-ink-500">step {seq?.stepIndex ?? '--'}</span>
          <span className="truncate text-sm text-ink-100">{seq?.step?.name ?? '--'}</span>
        </div>
        {seq?.waitingFor && (
          <p className="mt-1 text-xs text-ink-400">
            Waiting for {seq.waitingFor}
            {seq.elapsedSeconds ? ` · ${duration(seq.elapsedSeconds)}` : ''}
          </p>
        )}
        {seq?.awaitingOperator && (
          <p className="mt-1 text-xs font-semibold text-state-warn">Engrave, then type “eng done”.</p>
        )}
      </div>
      {total > 0 && (
        <div className="mt-3">
          <div className="mb-1 flex justify-between text-xs uppercase tracking-wider text-ink-500">
            <span>Order {inv?.order.qty50 ?? 0}×50 · {inv?.order.qty25 ?? 0}×25</span>
            <span>{done ?? '--'} / {total}</span>
          </div>
          <div className="h-1.5 overflow-hidden rounded-full bg-panel-700">
            <div
              className="h-full rounded-full bg-state-run transition-all"
              style={{ width: `${Math.min(100, ((done ?? 0) / Math.max(1, total)) * 100)}%` }}
            />
          </div>
        </div>
      )}
      {seq && seq.history.length > 0 && (
        <ol className="mt-3 max-h-40 space-y-0.5 overflow-y-auto font-mono text-[10.5px] text-ink-500">
          {seq.history.slice(-8).reverse().map((h) => (
            <li key={`${h.stepIndex}-${h.at}`} className="truncate">
              {new Date(h.at * 1000).toLocaleTimeString()} · {h.stepIndex} {h.name}
            </li>
          ))}
        </ol>
      )}
    </Panel>
  )
}

const CONTROLLABLE = new Set(['logger', 'twin_bridge'])
const NAMES: Record<string, string> = {
  dashboard: 'Dashboard', assistant: 'LEPS', logger: 'PLC logger', twin_bridge: 'Twin bridge',
  replay: 'Twin replay', nx_mcd: 'NX MCD', fake_cell: 'Fake cell',
}

function Programs() {
  const link = useAssistant((s) => s.link)
  const [programs, setPrograms] = useState<AssistantProgram[]>([])
  const [taskList, setTasks] = useState<AssistantTask[]>([])
  const [busy, setBusy] = useState('')
  const [msg, setMsg] = useState('')

  async function load() {
    try {
      const r = await assistant.programs()
      setPrograms(r.programs.filter((p) => p.component !== 'nx_mcd' || p.state.startsWith('running')))
      setTasks(r.tasks)
    } catch {
      /* offline: the chat says so */
    }
  }

  useEffect(() => {
    if (link !== 'online') return
    void load()
    const t = setInterval(() => void load(), 10_000)
    return () => clearInterval(t)
  }, [link])

  async function act(name: string, action: 'start' | 'stop') {
    if (action === 'stop' && !window.confirm(`Stop the ${NAMES[name] ?? name}?`)) return
    setBusy(name)
    setMsg('')
    try {
      const r = await assistant.program(name, action)
      setMsg(r.result.split('\n')[0])
    } catch (e) {
      setMsg(String((e as Error).message))
    }
    setBusy('')
    void load()
  }

  return (
    <Panel
      title="Background programs"
      actions={
        <button onClick={() => void load()} className="rounded p-1 text-ink-400 hover:text-ink-200" title="Refresh">
          <RefreshCw size={14} />
        </button>
      }
    >
      {link !== 'online' ? (
        <p className="text-xs text-ink-500">Shown when LEPS is running.</p>
      ) : (
        <ul className="space-y-2">
          {programs.map((p) => {
            const on = p.state.startsWith('running')
            return (
              <li key={p.component} className="flex items-center gap-2.5">
                <Lamp value={on} size="sm" />
                <div className="min-w-0 flex-1">
                  <p className="text-sm text-ink-200">{NAMES[p.component] ?? p.component}</p>
                  <p className="truncate text-xs text-ink-500" title={p.state}>
                    {on ? (p.health ?? (p.since ? `since ${p.since}` : 'running')) : 'not running'}
                  </p>
                </div>
                {CONTROLLABLE.has(p.component) && (
                  on ? (
                    <Button size="sm" variant="ghost" disabled={!!busy} onClick={() => void act(p.component, 'stop')}>
                      <Square size={12} /> Stop
                    </Button>
                  ) : (
                    <Button size="sm" variant="primary" disabled={!!busy} onClick={() => void act(p.component, 'start')}>
                      <Play size={12} /> Start
                    </Button>
                  )
                )}
              </li>
            )
          })}
        </ul>
      )}
      {msg && <p className="mt-2 break-words text-xs text-ink-400">{msg}</p>}
      {taskList.length > 0 && (
        <div className="mt-3 border-t border-panel-700 pt-2">
          <h3 className="mb-1 flex items-center gap-1.5 text-xs uppercase tracking-wider text-ink-500">
            <Cpu size={11} /> Plan tasks
          </h3>
          <ul className="space-y-1">
            {taskList.map((t) => (
              <li key={t.token} className="flex items-center gap-2 text-xs">
                <span
                  className={classNames(
                    'rounded px-1 font-mono text-xs uppercase',
                    t.state === 'done' ? 'bg-state-run/15 text-state-run'
                      : t.state === 'running' ? 'bg-state-info/15 text-state-info'
                        : 'bg-state-warn/15 text-state-warn',
                  )}
                >
                  {t.state}
                </span>
                <span className="truncate text-ink-300" title={t.title}>{t.title}</span>
              </li>
            ))}
          </ul>
        </div>
      )}
      <p className="mt-3 flex items-center gap-1 text-xs text-ink-600">
        <Gauge size={10} /> Without any browser: <code className="font-mono">cellctl status</code>
      </p>
    </Panel>
  )
}
