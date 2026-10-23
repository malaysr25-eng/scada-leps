/**
 * The always-visible global bar.
 *
 * Everything an operator must be able to see without scrolling and without
 * navigating lives here: link health, machine state, mode, cycle, and the
 * safety controls.
 *
 * ON THE STOP CONTROL
 * -------------------
 * The red control is labelled "SOFTWARE STOP", not "EMERGENCY STOP", and it
 * says so on its face. It clears CMD_START. It does not remove power, vent
 * air, or open the safety circuit. Presenting a browser button as an E-Stop
 * would be a safety misrepresentation: a web app on a general-purpose PC over
 * a general-purpose network provides no functional safety.
 *
 * The hardware E-Stop *status* is displayed beside it, read from
 * Start_interlocks.Emergency Healthy, so the operator can see the state of the
 * real safety circuit -- which is genuinely useful, and honest.
 */

import { useState } from 'react'
import {
  Activity, AlertOctagon, Camera, Cpu, Gauge, Hand, OctagonX,
  RotateCcw, ShieldCheck, ShieldAlert, Wifi, WifiOff, Wrench, Zap,
} from 'lucide-react'
import { api } from '../../services/api'
import {
  selectConnection, selectMachine, selectSafety, selectSequence, useMachine,
} from '../../stores/machineStore'
import type { Lifecycle, MachineMode } from '../../types'
import { classNames, duration, num } from '../../utils/format'
import { Badge, Button } from '../common/Primitives'

const LIFECYCLE_TONE: Record<Lifecycle, 'run' | 'idle' | 'warn' | 'fault' | 'info'> = {
  DISCONNECTED: 'fault',
  EMERGENCY_STOPPED: 'fault',
  FAULT: 'fault',
  RECOVERY_REQUIRED: 'warn',
  RESETTING: 'warn',
  IDLE: 'idle',
  READY: 'info',
  STARTING: 'warn',
  AUTO_RUNNING: 'run',
  COMPLETED: 'run',
  MANUAL_MODE: 'info',
  MAINTENANCE: 'warn',
}

const LIFECYCLE_LABEL: Record<Lifecycle, string> = {
  DISCONNECTED: 'PLC Disconnected',
  EMERGENCY_STOPPED: 'Emergency Stopped',
  FAULT: 'Fault',
  RECOVERY_REQUIRED: 'Recovery Required',
  RESETTING: 'Resetting',
  IDLE: 'Idle',
  READY: 'Ready',
  STARTING: 'Starting',
  AUTO_RUNNING: 'Auto Running',
  COMPLETED: 'Cycle Complete',
  MANUAL_MODE: 'Manual Mode',
  MAINTENANCE: 'Maintenance',
}

const MODES: { id: MachineMode; label: string; icon: typeof Cpu }[] = [
  { id: 'AUTO', label: 'Auto', icon: Cpu },
  { id: 'MANUAL', label: 'Manual', icon: Hand },
  { id: 'MAINTENANCE', label: 'Maint', icon: Wrench },
]

export function TopBar() {
  const connection = useMachine(selectConnection)
  const machine = useMachine(selectMachine)
  const safety = useMachine(selectSafety)
  const sequence = useMachine(selectSequence)
  const link = useMachine((s) => s.link)
  const pushToast = useMachine((s) => s.pushToast)
  const [busy, setBusy] = useState<string | null>(null)

  const lifecycle = machine?.lifecycle ?? 'DISCONNECTED'
  const emergency = safety?.emergencyActive === true
  const plc = connection?.plc ?? 'DISCONNECTED'
  const stale = connection?.stale ?? true
  const backendDown = link === 'reconnecting' || link === 'closed'

  async function changeMode(mode: MachineMode) {
    setBusy('mode')
    const res = await api.setMode(mode)
    setBusy(null)
    if (!res.ok) {
      pushToast({ kind: 'warn', title: 'Mode change refused', detail: res.error.message })
    }
  }

  async function softwareStop() {
    setBusy('stop')
    const res = await api.stopCycle()
    setBusy(null)
    pushToast(
      res.ok
        ? {
            kind: 'ok',
            title: 'Software stop issued',
            detail: 'CMD_START cleared. This is not a functional-safety stop.',
          }
        : { kind: 'error', title: 'Stop refused', detail: res.error.message },
    )
  }

  async function reset() {
    setBusy('reset')
    const res = await api.resetCycle(false)
    setBusy(null)
    pushToast(
      res.ok
        ? { kind: 'ok', title: 'Cycle reset issued' }
        : {
            kind: 'warn',
            title: 'Reset blocked',
            detail: res.error.message + ' See the restart checklist.',
          },
    )
  }

  return (
    <header
      className={classNames(
        'sticky top-0 z-40 border-b bg-panel-900/95 backdrop-blur',
        emergency
          ? 'border-state-fault/60'
          : 'border-panel-700',
      )}
    >
      {/* Emergency ribbon: unmistakable, and it names what is actually true. */}
      {emergency && (
        <div className="relative overflow-hidden bg-state-fault/20">
          <div className="absolute inset-y-0 -left-1/3 w-1/3 animate-sweep bg-state-fault/25" />
          <div className="relative flex items-center justify-center gap-3 px-4 py-1.5">
            <AlertOctagon size={16} className="text-state-fault" />
            <span className="text-sm font-bold uppercase tracking-[0.14em] text-state-fault">
              Emergency circuit unhealthy &mdash; machine stopped &mdash; process commands blocked
            </span>
          </div>
        </div>
      )}

      {backendDown && (
        <div className="bg-state-warn/15 px-4 py-1 text-center text-sm font-semibold uppercase tracking-wider text-state-warn">
          Backend unreachable &mdash; retrying. Values below are the last known good state.
        </div>
      )}

      <div className="flex flex-wrap items-center gap-x-5 gap-y-2 px-4 py-2.5">
        {/* identity */}
        <div className="flex items-center gap-2.5">
          <div className="grid h-8 w-8 place-items-center rounded-lg border border-panel-600 bg-panel-800">
            <Activity size={17} className="text-state-info" />
          </div>
          <div className="leading-tight">
            <div className="text-sm font-bold tracking-wide text-ink-100">
              CELL&nbsp;CONTROL
            </div>
            <div className="text-xs uppercase tracking-wider text-ink-500">
              S7-1200 &middot; Digital Twin
            </div>
          </div>
        </div>

        <Divider />

        {/* machine state */}
        <div className="flex items-center gap-3">
          <Badge tone={LIFECYCLE_TONE[lifecycle]} className="!text-sm !px-2.5 !py-1">
            {LIFECYCLE_LABEL[lifecycle]}
          </Badge>
          <StatChip
            label="Cycle"
            value={machine?.cycleId ?? '--'}
            sub={
              machine?.cycleElapsed != null
                ? duration(machine.cycleElapsed)
                : machine?.cycleCount
                  ? `${machine.cycleCount} run${machine.cycleCount === 1 ? '' : 's'}`
                  : 'none'
            }
          />
          <StatChip
            label="Step"
            value={
              sequence?.step
                ? `${sequence.step.index} · ${sequence.step.name}`
                : '--'
            }
            sub={
              sequence?.waitingFor
                ? `waiting: ${sequence.waitingFor}`
                : 'inferred from sensors'
            }
            tone={sequence?.stalled ? 'warn' : undefined}
            wide
          />
        </div>

        <Divider />

        {/* links */}
        <div className="flex items-center gap-3">
          <LinkChip
            icon={plc === 'DISCONNECTED' ? WifiOff : Wifi}
            label="PLC"
            value={plc}
            tone={
              plc === 'CONNECTED'
                ? 'run'
                : plc === 'SIMULATED'
                  ? 'info'
                  : plc === 'DEGRADED' || plc === 'RECONNECTING'
                    ? 'warn'
                    : 'fault'
            }
            sub={
              connection?.plcHealth
                ? `${num(connection.plcHealth.latencyAvgMs, 0)} ms · ${
                    connection.staleSeconds != null
                      ? `${num(connection.staleSeconds, 1)} s old`
                      : 'no read'
                  }`
                : undefined
            }
            warn={stale}
          />
          <LinkChip
            icon={Camera}
            label="Camera"
            value={connection?.camera ?? 'OFFLINE'}
            tone={connection?.camera === 'ONLINE' ? 'run' : 'idle'}
          />
          <LinkChip
            icon={Gauge}
            label="Twin"
            value={connection?.digitalTwin ?? 'DISCONNECTED'}
            tone={connection?.digitalTwin === 'CONNECTED' ? 'twin' : 'idle'}
          />
        </div>

        <div className="ml-auto flex items-center gap-3">
          {/* mode selector */}
          <div className="flex items-center rounded-lg border border-panel-600 bg-panel-850 p-0.5">
            {MODES.map(({ id, label, icon: Icon }) => {
              const active = machine?.mode === id
              return (
                <button
                  key={id}
                  onClick={() => changeMode(id)}
                  disabled={busy === 'mode'}
                  title={`Switch to ${label} mode`}
                  className={classNames(
                    'flex items-center gap-1.5 rounded-md px-2.5 py-1.5 text-xs font-semibold transition-colors',
                    active
                      ? id === 'AUTO'
                        ? 'bg-state-info/20 text-state-info'
                        : id === 'MANUAL'
                          ? 'bg-state-warn/20 text-state-warn'
                          : 'bg-state-twin/20 text-state-twin'
                      : 'text-ink-400 hover:text-ink-200',
                  )}
                >
                  <Icon size={13} />
                  {label}
                </button>
              )
            })}
          </div>

          {/* hardware safety circuit STATUS -- read only, never a control */}
          <div
            className={classNames(
              'flex items-center gap-2 rounded-lg border px-2.5 py-1.5',
              emergency
                ? 'border-state-fault/50 bg-state-fault/10'
                : 'border-panel-600 bg-panel-850',
            )}
            title="Status of the hardware safety circuit, read from the PLC. This application cannot drive it."
          >
            {emergency ? (
              <ShieldAlert size={15} className="text-state-fault" />
            ) : (
              <ShieldCheck size={15} className="text-state-run" />
            )}
            <div className="leading-none">
              <div className="text-xs uppercase tracking-wider text-ink-500">
                HW E-Stop
              </div>
              <div
                className={classNames(
                  'mt-0.5 text-sm font-bold',
                  emergency ? 'text-state-fault' : 'text-state-run',
                )}
              >
                {emergency ? 'TRIPPED' : 'HEALTHY'}
              </div>
            </div>
          </div>

          <Button
            variant="warn"
            size="sm"
            onClick={reset}
            disabled={busy !== null}
            title="Issue Cycle_Reset. Blocked unless the restart checklist passes."
          >
            <RotateCcw size={14} />
            Reset
          </Button>

          <Button
            variant="danger"
            size="md"
            onClick={softwareStop}
            disabled={busy !== null || plc === 'DISCONNECTED'}
            title="Clears CMD_START. NOT a functional-safety stop -- use the hardware E-Stop for that."
            className="!px-4 font-bold"
          >
            <OctagonX size={17} />
            <span className="leading-none">
              SOFTWARE
              <span className="ml-1 opacity-80">STOP</span>
            </span>
          </Button>
        </div>
      </div>

      {/* safety strip */}
      <div className="flex flex-wrap items-center gap-x-4 gap-y-1 border-t border-panel-800 bg-panel-950/60 px-4 py-1.5 text-xs">
        <SafetyPip label="Air pressure" value={safety?.airPressureHealthy} />
        <SafetyPip label="Cylinders home" value={safety?.allCylindersHome} />
        <SafetyPip label="Plate home" value={safety?.engravingPlateHome} />
        <SafetyPip label="Startup" value={safety?.startupHealthy} />
        <span className="flex items-center gap-1.5 text-ink-400">
          <Zap size={11} className="text-ink-500" />
          {num(safety?.pressureBar, 2)} bar
        </span>
        {connection?.plcSimulated && (
          <Badge tone="info" className="!py-0">
            Simulated PLC &mdash; not live plant data
          </Badge>
        )}
        <span
          className="min-w-0 flex-1 basis-0 truncate text-right text-ink-500"
          title={safety?.note}
        >
          {safety?.note}
        </span>
      </div>
    </header>
  )
}

// ---------------------------------------------------------------------------

function Divider() {
  return <span className="hidden h-8 w-px bg-panel-700 lg:block" />
}

function StatChip({
  label, value, sub, tone, wide,
}: {
  label: string
  value: string
  sub?: string
  tone?: 'warn'
  wide?: boolean
}) {
  return (
    <div className={classNames('leading-tight', wide && 'max-w-[260px]')}>
      <div className="text-xs uppercase tracking-wider text-ink-500">
        {label}
      </div>
      <div
        className={classNames(
          'truncate font-mono text-sm',
          tone === 'warn' ? 'text-state-warn' : 'text-ink-200',
        )}
      >
        {value}
      </div>
      {sub && (
        <div
          className={classNames(
            'truncate text-xs',
            tone === 'warn' ? 'text-state-warn/80' : 'text-ink-500',
          )}
        >
          {sub}
        </div>
      )}
    </div>
  )
}

function LinkChip({
  icon: Icon, label, value, tone, sub, warn,
}: {
  icon: typeof Wifi
  label: string
  value: string
  tone: 'run' | 'warn' | 'fault' | 'idle' | 'info' | 'twin'
  sub?: string
  warn?: boolean
}) {
  const colour = {
    run: 'text-state-run',
    warn: 'text-state-warn',
    fault: 'text-state-fault',
    idle: 'text-ink-500',
    info: 'text-state-info',
    twin: 'text-state-twin',
  }[tone]

  return (
    <div className="flex items-center gap-1.5 leading-tight">
      <Icon size={14} className={colour} />
      <div>
        <div className="text-xs uppercase tracking-wider text-ink-500">
          {label}
        </div>
        <div className={classNames('text-sm font-semibold', colour)}>
          {value}
          {warn && tone === 'run' && (
            <span className="ml-1 text-state-warn">stale</span>
          )}
        </div>
        {sub && <div className="font-mono text-xs text-ink-500">{sub}</div>}
      </div>
    </div>
  )
}

function SafetyPip({ label, value }: { label: string; value?: boolean | null }) {
  const tone =
    value === true ? 'text-state-run'
      : value === false ? 'text-state-fault'
        : 'text-ink-500'
  const glyph = value === true ? '✓' : value === false ? '✕' : '?'
  return (
    <span className={classNames('flex items-center gap-1.5', tone)}>
      <span className="font-bold">{glyph}</span>
      {label}
    </span>
  )
}
