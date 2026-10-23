/**
 * Diagnostics: the fault timeline, findings, watch list, and change history.
 *
 * Each detector maps to a specific line in the Errors sheet, and each finding
 * carries its issue reference so the screen and DEBUGGING_REPORT.md stay tied
 * together.
 *
 * The attribution column on the change history is the point of the whole
 * screen. Every recorded transition says whether a command from this
 * application was in flight at that moment:
 *
 *   operator   we asked for it
 *   plc        nothing of ours was pending — the PLC program did it
 *   contested  we asked for X and it went to something else
 *
 * That single distinction turns "solenoid_valve_8 randomly turns on and off"
 * into a decidable question.
 */

import { useMemo, useState } from 'react'
import {
  Activity, AlertTriangle, Bell, BellOff, Eye, Pin, PinOff, Zap,
} from 'lucide-react'
import { api } from '../../services/api'
import {
  selectDiagnostics, selectEvents, useMachine,
} from '../../stores/machineStore'
import type { Severity } from '../../types'
import { ago, classNames, clockMs, pretty } from '../../utils/format'
import { Badge, Button, EmptyState, Panel } from '../common/Primitives'

const SEVERITY_STYLE: Record<Severity, { tone: string; label: string }> = {
  INFO: { tone: 'text-ink-400', label: 'INFO' },
  COMMAND: { tone: 'text-state-info', label: 'CMD' },
  PLC: { tone: 'text-state-twin', label: 'PLC' },
  WARNING: { tone: 'text-state-warn', label: 'WARN' },
  FAULT: { tone: 'text-state-fault', label: 'FAULT' },
  EMERGENCY: { tone: 'text-state-fault font-bold', label: 'EMERG' },
}

// ---------------------------------------------------------------------------

export function FindingsPanel() {
  const diagnostics = useMachine(selectDiagnostics)
  const findings = diagnostics?.findings ?? []

  return (
    <Panel
      title="Active findings"
      actions={
        <Badge tone={findings.length ? 'fault' : 'run'}>
          {findings.length || 'none'}
        </Badge>
      }
    >
      {findings.length === 0 ? (
        <EmptyState>
          No findings. Detectors are running for chatter, unheld commands,
          conveyor motion, pressure and data staleness.
        </EmptyState>
      ) : (
        <ul className="space-y-2">
          {findings.map((f) => (
            <li
              key={f.key}
              className={classNames(
                'rounded-lg border p-3',
                f.severity === 'FAULT'
                  ? 'border-state-fault/50 bg-state-fault/8'
                  : 'border-state-warn/45 bg-state-warn/8',
              )}
            >
              <div className="mb-1 flex flex-wrap items-center gap-2">
                <AlertTriangle
                  size={14}
                  className={
                    f.severity === 'FAULT' ? 'text-state-fault' : 'text-state-warn'
                  }
                />
                <span
                  className={classNames(
                    'text-sm font-semibold',
                    f.severity === 'FAULT' ? 'text-state-fault' : 'text-state-warn',
                  )}
                >
                  {f.title}
                </span>
                {f.issueRef && (
                  <span
                    className="rounded bg-panel-700 px-1.5 py-0.5 font-mono text-xs text-ink-400"
                    title="Issue reference in DEBUGGING_REPORT.md"
                  >
                    {f.issueRef}
                  </span>
                )}
                <span className="ml-auto font-mono text-xs text-ink-500">
                  {clockMs(f.at)}
                </span>
              </div>
              <p className="text-xs leading-relaxed text-ink-300">{f.detail}</p>
              {f.address && (
                <p className="mt-1 font-mono text-xs text-ink-500">{f.address}</p>
              )}
            </li>
          ))}
        </ul>
      )}
    </Panel>
  )
}

// ---------------------------------------------------------------------------

export function FaultTimeline() {
  const diagnostics = useMachine(selectDiagnostics)
  const pushToast = useMachine((s) => s.pushToast)
  const faults = diagnostics?.activeFaults ?? []

  async function acknowledge(key: string) {
    const res = await api.acknowledgeFault(key)
    if (!res.ok) {
      pushToast({ kind: 'warn', title: 'Acknowledge failed', detail: res.error.message })
    }
  }

  return (
    <Panel title="Latched faults">
      {faults.length === 0 ? (
        <EmptyState>No active faults.</EmptyState>
      ) : (
        <ul className="space-y-2">
          {faults.map((f) => (
            <li
              key={f.key}
              className="rounded-lg border border-state-fault/45 bg-state-fault/8 p-3"
            >
              <div className="flex items-start gap-2">
                <Bell size={14} className="mt-0.5 shrink-0 text-state-fault" />
                <div className="min-w-0 flex-1">
                  <p className="text-sm text-state-fault">{f.message}</p>
                  <p className="mt-1 flex flex-wrap gap-x-3 font-mono text-xs text-ink-500">
                    <span>{f.key}</span>
                    <span>raised {clockMs(f.raisedAt)}</span>
                    {f.occurrences > 1 && <span>×{f.occurrences}</span>}
                  </p>
                </div>
                <Button
                  variant="ghost"
                  size="sm"
                  onClick={() => acknowledge(f.key)}
                  disabled={f.acknowledged}
                  title="Acknowledge — the fault stays latched until the condition clears"
                >
                  {f.acknowledged ? <BellOff size={12} /> : <Bell size={12} />}
                  {f.acknowledged ? 'Acked' : 'Ack'}
                </Button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </Panel>
  )
}

// ---------------------------------------------------------------------------

export function EventLogPanel({ height = 'max-h-[420px]' }: { height?: string }) {
  const events = useMachine(selectEvents)
  const [filter, setFilter] = useState<Severity | 'ALL'>('ALL')

  const filtered = useMemo(
    () =>
      (events ?? []).filter((e) => filter === 'ALL' || e.severity === filter),
    [events, filter],
  )

  const levels: (Severity | 'ALL')[] = [
    'ALL', 'EMERGENCY', 'FAULT', 'WARNING', 'COMMAND', 'PLC', 'INFO',
  ]

  return (
    <Panel
      title="Event timeline"
      actions={
        <select
          value={filter}
          onChange={(e) => setFilter(e.target.value as Severity | 'ALL')}
          className="rounded border border-panel-600 bg-panel-800 px-2 py-1 text-xs text-ink-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-state-info/60"
        >
          {levels.map((l) => (
            <option key={l} value={l}>
              {l}
            </option>
          ))}
        </select>
      }
    >
      <div className={classNames('space-y-0.5 overflow-y-auto pr-1', height)}>
        {filtered.length === 0 && (
          <p className="py-8 text-center text-xs text-ink-500">No events at this level.</p>
        )}
        {filtered.map((e) => {
          const style = SEVERITY_STYLE[e.severity]
          return (
            <div
              key={e.id}
              className="flex items-start gap-2.5 rounded px-2 py-1 font-mono text-xs hover:bg-panel-800"
            >
              <span className="shrink-0 text-ink-600">{clockMs(e.at)}</span>
              <span className={classNames('w-12 shrink-0 font-bold', style.tone)}>
                {style.label}
              </span>
              <span className="w-24 shrink-0 truncate text-ink-500">{e.category}</span>
              <span className="min-w-0 flex-1 font-sans text-ink-300">{e.message}</span>
            </div>
          )
        })}
      </div>
    </Panel>
  )
}

// ---------------------------------------------------------------------------

export function WatchListPanel() {
  const diagnostics = useMachine(selectDiagnostics)
  const pushToast = useMachine((s) => s.pushToast)
  const watch = diagnostics?.watch ?? []

  async function unpin(tagId: string) {
    const res = await api.removeWatch(tagId)
    if (!res.ok) {
      pushToast({ kind: 'warn', title: 'Could not unpin', detail: res.error.message })
    }
  }

  return (
    <Panel
      title="Watch list"
      actions={<Badge tone="info">{watch.length} pinned</Badge>}
    >
      {watch.length === 0 ? (
        <EmptyState>Nothing pinned. Pin tags from the Tag Explorer.</EmptyState>
      ) : (
        <div className="overflow-x-auto">
          <table className="w-full text-left text-xs">
            <thead>
              <tr className="border-b border-panel-700 text-xs uppercase tracking-wider text-ink-500">
                <th className="py-1.5 pr-2 font-medium">Tag</th>
                <th className="py-1.5 pr-2 font-medium">Address</th>
                <th className="py-1.5 pr-2 font-medium">Value</th>
                <th className="py-1.5 pr-2 font-medium">Previous</th>
                <th className="py-1.5 pr-2 font-medium">Changed</th>
                <th className="py-1.5 pr-2 font-medium">By</th>
                <th className="py-1.5 pr-2 text-right font-medium">#</th>
                <th />
              </tr>
            </thead>
            <tbody className="divide-y divide-panel-800">
              {watch.map((w) => (
                <tr key={w.tagId} className="hover:bg-panel-800/60">
                  <td className="py-1.5 pr-2">
                    <span className="text-ink-200">{w.label}</span>
                    {w.provenance === 'undocumented' && (
                      <span
                        className="ml-1.5 rounded bg-state-warn/20 px-1 text-xs text-state-warn"
                        title="Not present in Tag_list (1).xlsx"
                      >
                        UNDOC
                      </span>
                    )}
                  </td>
                  <td className="py-1.5 pr-2 font-mono text-xs text-ink-500">
                    {w.address}
                  </td>
                  <td
                    className={classNames(
                      'py-1.5 pr-2 font-mono font-bold',
                      w.value === true
                        ? 'text-state-run'
                        : w.value === false
                          ? 'text-ink-400'
                          : 'text-ink-500',
                    )}
                  >
                    {pretty(w.value)}
                  </td>
                  <td className="py-1.5 pr-2 font-mono text-ink-500">
                    {pretty(w.previous)}
                  </td>
                  <td className="py-1.5 pr-2 text-ink-400">{ago(w.lastChangeAt)}</td>
                  <td className="py-1.5 pr-2">
                    <SourceBadge source={w.lastChangeSource} />
                  </td>
                  <td className="py-1.5 pr-2 text-right font-mono text-ink-400">
                    {w.transitions}
                  </td>
                  <td className="py-1.5">
                    <button
                      onClick={() => unpin(w.tagId)}
                      className="rounded p-1 text-ink-500 hover:bg-panel-700 hover:text-ink-200"
                      title="Unpin"
                    >
                      <PinOff size={12} />
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  )
}

export function SourceBadge({
  source,
}: {
  source: 'operator' | 'plc' | 'contested' | null | undefined
}) {
  if (!source) return <span className="text-ink-600">--</span>
  const map = {
    operator: { cls: 'bg-state-info/18 text-state-info', label: 'operator', icon: Zap },
    plc: { cls: 'bg-panel-700 text-ink-400', label: 'PLC', icon: Activity },
    contested: {
      cls: 'bg-state-fault/18 text-state-fault',
      label: 'contested',
      icon: AlertTriangle,
    },
  }[source]

  const Icon = map.icon
  return (
    <span
      className={classNames(
        'inline-flex items-center gap-1 rounded px-1.5 py-0.5 text-xs font-semibold uppercase tracking-wide',
        map.cls,
      )}
      title={
        source === 'plc'
          ? 'No command from this application was in flight — the PLC program changed it'
          : source === 'contested'
            ? 'A command was in flight but the value went somewhere else'
            : 'A command from this application was in flight'
      }
    >
      <Icon size={9} />
      {map.label}
    </span>
  )
}

// ---------------------------------------------------------------------------

export function ChangeHistoryPanel() {
  const diagnostics = useMachine(selectDiagnostics)
  const [query, setQuery] = useState('')

  const changes = useMemo(() => {
    const all = diagnostics?.recentChanges ?? []
    const q = query.trim().toLowerCase()
    const filtered = q
      ? all.filter(
          (c) =>
            c.short.toLowerCase().includes(q) ||
            (c.address ?? '').toLowerCase().includes(q) ||
            c.tagId.toLowerCase().includes(q),
        )
      : all
    return [...filtered].reverse()
  }, [diagnostics?.recentChanges, query])

  return (
    <Panel
      title="Tag change history"
      actions={
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Filter by tag…"
          className="w-40 rounded border border-panel-600 bg-panel-800 px-2 py-1 text-xs text-ink-200 placeholder:text-ink-600 focus:outline-none focus:ring-1 focus:ring-state-info/50"
        />
      }
    >
      <div className="max-h-[420px] space-y-0.5 overflow-y-auto pr-1">
        {changes.length === 0 && (
          <p className="py-8 text-center text-xs text-ink-500">
            No changes recorded in this window.
          </p>
        )}
        {changes.map((c, i) => (
          <div
            key={`${c.tagId}-${c.at}-${i}`}
            className="flex items-center gap-2.5 rounded px-2 py-1 font-mono text-xs hover:bg-panel-800"
          >
            <span className="shrink-0 text-ink-600">{clockMs(c.at)}</span>
            <span className="w-48 shrink-0 truncate text-ink-200">{c.short}</span>
            <span className="w-24 shrink-0 truncate text-xs text-ink-600">
              {c.address}
            </span>
            <span className="text-ink-500">{pretty(c.previous)}</span>
            <span className="text-ink-600">→</span>
            <span
              className={classNames(
                'font-bold',
                c.value === true ? 'text-state-run' : 'text-ink-400',
              )}
            >
              {pretty(c.value)}
            </span>
            <span className="ml-auto shrink-0">
              <SourceBadge source={c.source} />
            </span>
          </div>
        ))}
      </div>
    </Panel>
  )
}

// ---------------------------------------------------------------------------

export function CommandHistoryPanel() {
  const commands = useMachine((s) => s.snapshot?.commands ?? [])

  return (
    <Panel
      title="Command history"
      actions={<Badge tone="info">{commands.length}</Badge>}
    >
      {commands.length === 0 ? (
        <EmptyState>No commands issued this session.</EmptyState>
      ) : (
        <div className="max-h-[380px] overflow-y-auto">
          <table className="w-full text-left text-xs">
            <thead className="sticky top-0 bg-panel-850">
              <tr className="border-b border-panel-700 text-xs uppercase tracking-wider text-ink-500">
                <th className="py-1.5 pr-2 font-medium">Time</th>
                <th className="py-1.5 pr-2 font-medium">Address</th>
                <th className="py-1.5 pr-2 font-medium">Wanted</th>
                <th className="py-1.5 pr-2 font-medium">PLC read</th>
                <th className="py-1.5 pr-2 font-medium">Outcome</th>
                <th className="py-1.5 pr-2 text-right font-medium">Latency</th>
              </tr>
            </thead>
            <tbody className="divide-y divide-panel-800">
              {commands
                .slice()
                .reverse()
                .map((c) => (
                  <tr key={c.id} className="hover:bg-panel-800/60" title={c.error}>
                    <td className="py-1.5 pr-2 font-mono text-xs text-ink-500">
                      {clockMs(c.createdAt)}
                    </td>
                    <td className="py-1.5 pr-2 font-mono text-xs text-ink-300">
                      {c.address}
                    </td>
                    <td className="py-1.5 pr-2 font-mono text-ink-200">
                      {pretty(c.requested)}
                    </td>
                    <td className="py-1.5 pr-2 font-mono text-ink-400">
                      {pretty(c.observed)}
                    </td>
                    <td className="py-1.5 pr-2">
                      <CommandBadge state={c.state} />
                    </td>
                    <td className="py-1.5 pr-2 text-right font-mono text-xs text-ink-500">
                      {c.latencyMs != null ? `${c.latencyMs.toFixed(0)} ms` : '--'}
                    </td>
                  </tr>
                ))}
            </tbody>
          </table>
        </div>
      )}
    </Panel>
  )
}

function CommandBadge({ state }: { state: string }) {
  const tone =
    state === 'CONFIRMED'
      ? 'run'
      : state === 'PENDING' || state === 'WRITTEN'
        ? 'warn'
        : 'fault'
  return (
    <Badge tone={tone as 'run' | 'warn' | 'fault'} className="!py-0 !text-xs">
      {state}
    </Badge>
  )
}

// ---------------------------------------------------------------------------

export function PinButton({ tagId, pinned }: { tagId: string; pinned: boolean }) {
  const pushToast = useMachine((s) => s.pushToast)

  async function toggle() {
    const res = pinned ? await api.removeWatch(tagId) : await api.addWatch(tagId)
    if (!res.ok) {
      pushToast({ kind: 'warn', title: 'Watch list update failed', detail: res.error.message })
    }
  }

  return (
    <button
      onClick={toggle}
      className={classNames(
        'rounded p-1 transition-colors',
        pinned
          ? 'text-state-info hover:bg-state-info/15'
          : 'text-ink-600 hover:bg-panel-700 hover:text-ink-300',
      )}
      title={pinned ? 'Remove from watch list' : 'Pin to watch list'}
    >
      {pinned ? <Pin size={13} /> : <Eye size={13} />}
    </button>
  )
}
