/**
 * Operator-controlled persistence.
 *
 * The panel makes the storage policy visible rather than leaving it implicit:
 * it says, on screen, that nothing is stored per poll and that a recording is
 * what changes that. An operator who does not know the difference will either
 * expect data that was never captured, or leave a recording running for a week.
 *
 * Every button posts to a backend endpoint that validates. The UI never writes
 * to the database itself.
 */

import { useState } from 'react'
import {
  Camera, Circle, Database, Disc, Loader2, Save, Square,
} from 'lucide-react'
import { api } from '../../services/api'
import { useMachine } from '../../stores/machineStore'
import { classNames, duration, num } from '../../utils/format'
import { Badge, Button, Note, Panel } from '../common/Primitives'

export function RecordingControls() {
  const recording = useMachine((s) => s.snapshot?.recording)
  const database = useMachine((s) => s.snapshot?.database)
  const machine = useMachine((s) => s.snapshot?.machine)
  const pushToast = useMachine((s) => s.pushToast)

  const [busy, setBusy] = useState<string | null>(null)
  const [label, setLabel] = useState('')
  const [note, setNote] = useState('')
  const [interval, setIntervalValue] = useState('1.0')
  const [deadband, setDeadband] = useState('0.001')
  const [showOptions, setShowOptions] = useState(false)

  const active = recording?.recording ?? false
  const session = recording?.session
  const dbReady = database?.ready ?? false

  async function snapshot() {
    setBusy('snapshot')
    const res = await api.saveSnapshot(label || undefined, note || undefined)
    setBusy(null)
    pushToast(
      res.ok
        ? {
            kind: 'ok',
            title: 'Snapshot saved',
            detail: `${(res.data.bytes / 1000).toFixed(0)} kB of machine state stored.`,
          }
        : { kind: 'error', title: 'Snapshot failed', detail: res.error.message },
    )
  }

  async function start() {
    setBusy('start')
    const res = await api.startRecording({
      label: label || undefined,
      note: note || undefined,
      sampleInterval: parseFloat(interval) || undefined,
      deadband: parseFloat(deadband) || undefined,
    })
    setBusy(null)
    pushToast(
      res.ok
        ? { kind: 'ok', title: 'Recording started' }
        : { kind: 'error', title: 'Could not start recording', detail: res.error.message },
    )
  }

  async function stop() {
    setBusy('stop')
    const res = await api.stopRecording()
    setBusy(null)
    pushToast(
      res.ok
        ? {
            kind: 'ok',
            title: 'Recording stopped',
            detail: `${res.data?.sampleCount ?? 0} samples stored.`,
          }
        : { kind: 'warn', title: 'Stop failed', detail: res.error.message },
    )
  }

  async function saveCycle() {
    setBusy('cycle')
    const res = await api.saveCycle(note || undefined)
    setBusy(null)
    pushToast(
      res.ok
        ? { kind: 'ok', title: `Cycle ${res.data.cycleId} saved` }
        : { kind: 'warn', title: 'Cycle not saved', detail: res.error.message },
    )
  }

  return (
    <Panel
      title="Data capture"
      actions={
        active ? (
          <Badge tone="fault">
            <Circle size={8} className="mr-1 fill-current" />
            RECORDING
          </Badge>
        ) : (
          <Badge tone={dbReady ? 'idle' : 'warn'}>
            {dbReady ? 'Idle' : 'DB unavailable'}
          </Badge>
        )
      }
    >
      {!dbReady && (
        <Note tone="warn">
          Database unavailable. Check{' '}
          <code className="font-mono">db.enabled</code> and{' '}
          <code className="font-mono">db.path</code> in{' '}
          <code className="font-mono">config/config.json</code>.
        </Note>
      )}

      {active && session && (
        <div className="mb-3 rounded-lg border border-state-fault/45 bg-state-fault/8 p-3">
          <div className="mb-2 flex items-center gap-2">
            <Disc size={14} className="animate-spin text-state-fault" />
            <span className="text-sm font-semibold text-state-fault">
              {session.label}
            </span>
          </div>
          <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs sm:grid-cols-4">
            <Stat label="Samples" value={String(session.sampleCount)} />
            <Stat label="Duration" value={duration(session.durationSeconds)} />
            <Stat label="Interval" value={`${num(session.sampleInterval, 2)} s`} />
            <Stat
              label="Dropped"
              value={String(session.droppedCount)}
              tone={session.droppedCount > 0 ? 'fault' : undefined}
            />
          </dl>
          {session.droppedCount > 0 && (
            <p className="mt-2 text-xs leading-snug text-state-fault">
              Samples were dropped because the write queue filled. The control
              loop was never blocked — dropping is the deliberate trade.
            </p>
          )}
        </div>
      )}

      <div className="mb-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
        <input
          value={label}
          onChange={(e) => setLabel(e.target.value)}
          placeholder="Label (optional)"
          className="rounded-lg border border-panel-600 bg-panel-900 px-3 py-2 text-sm text-ink-100 placeholder:text-ink-600 focus:outline-none focus:ring-1 focus:ring-state-info/50"
        />
        <input
          value={note}
          onChange={(e) => setNote(e.target.value)}
          placeholder="Note (optional)"
          className="rounded-lg border border-panel-600 bg-panel-900 px-3 py-2 text-sm text-ink-100 placeholder:text-ink-600 focus:outline-none focus:ring-1 focus:ring-state-info/50"
        />
      </div>

      <div className="grid grid-cols-2 gap-2 lg:grid-cols-4">
        <Button
          variant="primary"
          onClick={snapshot}
          disabled={!dbReady || busy !== null}
          title="Store the complete current machine state as one row"
        >
          {busy === 'snapshot' ? (
            <Loader2 size={15} className="animate-spin" />
          ) : (
            <Camera size={15} />
          )}
          Save Snapshot
        </Button>

        {active ? (
          <Button
            variant="danger"
            onClick={stop}
            disabled={busy !== null}
            title="End the recording session"
          >
            {busy === 'stop' ? (
              <Loader2 size={15} className="animate-spin" />
            ) : (
              <Square size={15} />
            )}
            Stop Recording
          </Button>
        ) : (
          <Button
            variant="success"
            onClick={start}
            disabled={!dbReady || busy !== null}
            title="Begin sampling tag values into the database"
          >
            {busy === 'start' ? (
              <Loader2 size={15} className="animate-spin" />
            ) : (
              <Circle size={15} />
            )}
            Start Recording
          </Button>
        )}

        <Button
          variant="ghost"
          onClick={saveCycle}
          disabled={!dbReady || busy !== null || !machine?.cycleId}
          title={
            machine?.cycleId
              ? `Persist a summary of cycle ${machine.cycleId}`
              : 'No cycle is currently identified'
          }
        >
          {busy === 'cycle' ? (
            <Loader2 size={15} className="animate-spin" />
          ) : (
            <Save size={15} />
          )}
          Save Cycle
        </Button>

        <Button
          variant="ghost"
          onClick={() => setShowOptions((v) => !v)}
          disabled={active}
          title={active ? 'Stop the recording to change settings' : 'Sampling settings'}
        >
          <Database size={15} />
          Options
        </Button>
      </div>

      {showOptions && !active && (
        <div className="mt-3 grid grid-cols-2 gap-3 rounded-lg border border-panel-700 bg-panel-800 p-3">
          <label className="block">
            <span className="mb-1 block text-xs uppercase tracking-wider text-ink-500">
              Sample interval (s)
            </span>
            <input
              value={interval}
              onChange={(e) => setIntervalValue(e.target.value)}
              className="w-full rounded border border-panel-600 bg-panel-900 px-2 py-1.5 font-mono text-sm text-ink-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-state-info/60"
            />
            <span className="mt-1 block text-xs text-ink-500">
              Minimum gap between samples of the same tag.
            </span>
          </label>
          <label className="block">
            <span className="mb-1 block text-xs uppercase tracking-wider text-ink-500">
              Deadband
            </span>
            <input
              value={deadband}
              onChange={(e) => setDeadband(e.target.value)}
              className="w-full rounded border border-panel-600 bg-panel-900 px-2 py-1.5 font-mono text-sm text-ink-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-state-info/60"
            />
            <span className="mt-1 block text-xs text-ink-500">
              A numeric value must move by more than this to be stored.
            </span>
          </label>
        </div>
      )}

      {database && (
        <div className="mt-3 grid grid-cols-2 gap-3 text-xs sm:grid-cols-4">
          <Stat label="Rows written" value={String(database.written)} />
          <Stat
            label="Dropped"
            value={String(database.dropped)}
            tone={database.dropped > 0 ? 'fault' : undefined}
          />
          <Stat
            label="Queue"
            value={`${database.queueDepth} / ${database.queueCapacity}`}
          />
          <Stat label="Avg write" value={`${num(database.writeMsAvg, 2)} ms`} />
        </div>
      )}
    </Panel>
  )
}

function Stat({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone?: 'fault'
}) {
  return (
    <div>
      <div className="text-xs uppercase tracking-wider text-ink-500">{label}</div>
      <div
        className={classNames(
          'font-mono text-sm',
          tone === 'fault' ? 'text-state-fault' : 'text-ink-200',
        )}
      >
        {value}
      </div>
    </div>
  )
}
