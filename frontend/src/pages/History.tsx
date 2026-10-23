/**
 * Historical data browser.
 *
 * Reads the SQL database rather than the live snapshot, so this is the one
 * screen whose contents survive a restart. Everything is fetched on demand and
 * bounded by a LIMIT — an unbounded query against tag_samples would hold a read
 * transaction long enough to matter.
 */

import { useEffect, useState } from 'react'
import {
  Bell, Clock, Database, FileDown, Loader2, RefreshCw,
} from 'lucide-react'
import { api } from '../services/api'
import { useMachine } from '../stores/machineStore'
import type {
  HistoryAlarm, HistoryCycle, HistoryEvent, HistorySnapshot, HistorySummary,
} from '../types'
import { ago, classNames, clockMs, duration, num } from '../utils/format'
import { Badge, Button, EmptyState, Note, Panel } from '../components/common/Primitives'

type Tab = 'cycles' | 'events' | 'alarms' | 'snapshots' | 'sessions'

const TABS: { id: Tab; label: string }[] = [
  { id: 'cycles', label: 'Cycles' },
  { id: 'events', label: 'Events' },
  { id: 'alarms', label: 'Alarms' },
  { id: 'snapshots', label: 'Snapshots' },
  { id: 'sessions', label: 'Recordings' },
]

export function HistoryPage() {
  const database = useMachine((s) => s.snapshot?.database)
  const [tab, setTab] = useState<Tab>('cycles')
  const [summary, setSummary] = useState<HistorySummary | null>(null)
  const [loading, setLoading] = useState(false)

  async function loadSummary() {
    const res = await api.historySummary()
    if (res.ok) setSummary(res.data)
  }

  useEffect(() => {
    void loadSummary()
  }, [])

  if (database && !database.enabled) {
    return (
      <Panel title="History">
        <Note tone="warn">
          The database is disabled. Set <code className="font-mono">db.enabled</code>{' '}
          to true in <code className="font-mono">config/config.json</code> and
          restart.
        </Note>
      </Panel>
    )
  }

  return (
    <div className="space-y-4">
      <Panel
        title="Stored history"
        actions={
          <Button
            variant="ghost"
            size="sm"
            onClick={() => {
              setLoading(true)
              void loadSummary().finally(() => setLoading(false))
            }}
          >
            {loading ? (
              <Loader2 size={13} className="animate-spin" />
            ) : (
              <RefreshCw size={13} />
            )}
            Refresh
          </Button>
        }
      >
        {summary ? (
          <>
            <div className="grid grid-cols-2 gap-3 sm:grid-cols-4 lg:grid-cols-6">
              {Object.entries(summary.counts).map(([table, count]) => (
                <div
                  key={table}
                  className="rounded-lg border border-panel-700 bg-panel-800 px-2.5 py-2"
                >
                  <div className="truncate text-xs uppercase tracking-wider text-ink-500">
                    {table.replace(/_/g, ' ')}
                  </div>
                  <div className="font-mono text-lg tabular-nums text-ink-100">
                    {count.toLocaleString()}
                  </div>
                </div>
              ))}
            </div>
            <div className="mt-3 flex flex-wrap gap-x-6 gap-y-1 text-xs text-ink-400">
              <span className="flex items-center gap-1.5">
                <Database size={12} />
                {(summary.sizeBytes / 1e6).toFixed(2)} MB on disk
              </span>
              <span>{summary.totalRows.toLocaleString()} rows total</span>
              {summary.oldestEventAt && (
                <span className="flex items-center gap-1.5">
                  <Clock size={12} />
                  oldest {ago(summary.oldestEventAt)}
                </span>
              )}
            </div>
          </>
        ) : (
          <EmptyState>Loading…</EmptyState>
        )}
      </Panel>

      <div className="flex flex-wrap gap-1 rounded-lg border border-panel-700 bg-panel-850 p-1">
        {TABS.map((t) => (
          <button
            key={t.id}
            onClick={() => setTab(t.id)}
            className={classNames(
              'rounded-md px-3.5 py-1.5 text-xs font-semibold transition-colors',
              tab === t.id
                ? 'bg-state-info/20 text-state-info'
                : 'text-ink-400 hover:text-ink-200',
            )}
          >
            {t.label}
          </button>
        ))}
      </div>

      {tab === 'cycles' && <CyclesTab />}
      {tab === 'events' && <EventsTab />}
      {tab === 'alarms' && <AlarmsTab />}
      {tab === 'snapshots' && <SnapshotsTab />}
      {tab === 'sessions' && <SessionsTab />}
    </div>
  )
}

// ---------------------------------------------------------------------------

function useQuery<T>(fetcher: () => Promise<{ ok: boolean; data?: T }>, deps: unknown[] = []) {
  const [data, setData] = useState<T | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    let cancelled = false
    setLoading(true)
    void fetcher().then((res) => {
      if (cancelled) return
      setData(res.ok ? (res.data as T) : null)
      setLoading(false)
    })
    return () => {
      cancelled = true
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps)

  return { data, loading }
}

function Table({
  head,
  children,
}: {
  head: string[]
  children: React.ReactNode
}) {
  return (
    <div className="max-h-[560px] overflow-auto rounded-lg border border-panel-700">
      <table className="w-full text-left text-xs">
        <thead className="sticky top-0 z-10 bg-panel-800">
          <tr className="text-xs uppercase tracking-wider text-ink-400">
            {head.map((h) => (
              <th key={h} className="px-3 py-2 font-medium">
                {h}
              </th>
            ))}
          </tr>
        </thead>
        <tbody className="divide-y divide-panel-800">{children}</tbody>
      </table>
    </div>
  )
}

// ---------------------------------------------------------------------------

function CyclesTab() {
  const { data, loading } = useQuery<HistoryCycle[]>(() => api.historyCycles(100))

  if (loading) return <Panel title="Cycles"><EmptyState>Loading…</EmptyState></Panel>
  if (!data?.length)
    return (
      <Panel title="Cycles">
        <EmptyState>No cycles stored yet. Run one and it appears here.</EmptyState>
      </Panel>
    )

  return (
    <Panel title="Cycles">
      <Table head={['Cycle', 'Started', 'Duration', 'Outcome', '25 mm', '50 mm', 'Done', 'Step', 'Faults']}>
        {data.map((c) => (
          <tr key={c.id} className="hover:bg-panel-800/60">
            <td className="px-3 py-1.5 font-mono text-ink-200">{c.cycle_id}</td>
            <td className="px-3 py-1.5 text-ink-400">{clockMs(c.started_at)}</td>
            <td className="px-3 py-1.5 font-mono text-ink-300">
              {c.duration_s ? duration(c.duration_s) : '--'}
            </td>
            <td className="px-3 py-1.5">
              <Badge tone={c.outcome === 'COMPLETED' ? 'run' : 'warn'} className="!py-0 !text-xs">
                {c.outcome ?? '--'}
              </Badge>
            </td>
            <td className="px-3 py-1.5 font-mono text-ink-300">{c.qty_25mm ?? '--'}</td>
            <td className="px-3 py-1.5 font-mono text-ink-300">{c.qty_50mm ?? '--'}</td>
            <td className="px-3 py-1.5 font-mono text-state-run">{c.products_done ?? '--'}</td>
            <td className="px-3 py-1.5 font-mono text-ink-400">{c.max_step_reached ?? '--'}</td>
            <td className="px-3 py-1.5">
              {c.fault_count > 0 ? (
                <span className="text-state-fault">{c.fault_count}</span>
              ) : (
                <span className="text-ink-600">0</span>
              )}
            </td>
          </tr>
        ))}
      </Table>
    </Panel>
  )
}

function EventsTab() {
  const [severity, setSeverity] = useState('')
  const { data, loading } = useQuery<HistoryEvent[]>(
    () => api.historyEvents({ severity: severity || undefined, limit: 300 }),
    [severity],
  )

  return (
    <Panel
      title="Events"
      actions={
        <select
          value={severity}
          onChange={(e) => setSeverity(e.target.value)}
          className="rounded border border-panel-600 bg-panel-800 px-2 py-1 text-xs text-ink-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-state-info/60"
        >
          <option value="">All severities</option>
          {['EMERGENCY', 'FAULT', 'WARNING', 'COMMAND', 'PLC', 'INFO'].map((s) => (
            <option key={s} value={s}>{s}</option>
          ))}
        </select>
      }
    >
      {loading ? (
        <EmptyState>Loading…</EmptyState>
      ) : !data?.length ? (
        <EmptyState>No stored events at this level.</EmptyState>
      ) : (
        <Table head={['Time', 'Severity', 'Category', 'Message', 'Cycle']}>
          {data.map((e) => (
            <tr key={e.id} className="hover:bg-panel-800/60">
              <td className="whitespace-nowrap px-3 py-1.5 font-mono text-xs text-ink-500">
                {clockMs(e.ts)}
              </td>
              <td className="px-3 py-1.5">
                <span
                  className={classNames(
                    'font-mono text-xs font-bold',
                    e.severity === 'EMERGENCY' || e.severity === 'FAULT'
                      ? 'text-state-fault'
                      : e.severity === 'WARNING'
                        ? 'text-state-warn'
                        : e.severity === 'COMMAND'
                          ? 'text-state-info'
                          : 'text-ink-500',
                  )}
                >
                  {e.severity}
                </span>
              </td>
              <td className="px-3 py-1.5 text-ink-500">{e.category}</td>
              <td className="px-3 py-1.5 text-ink-300">{e.message}</td>
              <td className="px-3 py-1.5 font-mono text-xs text-ink-600">
                {e.cycle_id ?? ''}
              </td>
            </tr>
          ))}
        </Table>
      )}
    </Panel>
  )
}

function AlarmsTab() {
  const { data, loading } = useQuery<HistoryAlarm[]>(() => api.historyAlarms({ limit: 200 }))

  return (
    <Panel title="Alarms">
      {loading ? (
        <EmptyState>Loading…</EmptyState>
      ) : !data?.length ? (
        <EmptyState>No alarms stored.</EmptyState>
      ) : (
        <Table head={['Raised', 'Cleared', 'Open for', 'Severity', 'Message', 'Ref', '×']}>
          {data.map((a) => (
            <tr key={a.id} className="hover:bg-panel-800/60">
              <td className="whitespace-nowrap px-3 py-1.5 font-mono text-xs text-ink-500">
                {clockMs(a.raised_at)}
              </td>
              <td className="whitespace-nowrap px-3 py-1.5 font-mono text-xs">
                {a.cleared_at ? (
                  <span className="text-ink-500">{clockMs(a.cleared_at)}</span>
                ) : (
                  <Badge tone="fault" className="!py-0 !text-xs">
                    <Bell size={9} className="mr-1" /> ACTIVE
                  </Badge>
                )}
              </td>
              <td className="px-3 py-1.5 font-mono text-ink-400">
                {a.cleared_at ? duration(a.cleared_at - a.raised_at) : '--'}
              </td>
              <td className="px-3 py-1.5 font-mono text-xs text-state-fault">
                {a.severity}
              </td>
              <td className="px-3 py-1.5 text-ink-300">{a.message}</td>
              <td className="px-3 py-1.5 font-mono text-xs text-ink-500">
                {a.issue_ref ?? ''}
              </td>
              <td className="px-3 py-1.5 font-mono text-ink-400">{a.occurrences}</td>
            </tr>
          ))}
        </Table>
      )}
    </Panel>
  )
}

function SnapshotsTab() {
  const { data, loading } = useQuery<HistorySnapshot[]>(() => api.historySnapshots(100))
  const [selected, setSelected] = useState<Record<string, unknown> | null>(null)

  async function open(id: number) {
    const res = await api.historySnapshot(id)
    if (res.ok) setSelected(res.data)
  }

  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_400px]">
      <Panel title="Snapshots">
        {loading ? (
          <EmptyState>Loading…</EmptyState>
        ) : !data?.length ? (
          <EmptyState>
            No snapshots. Press <strong>Save Snapshot</strong> on the Data page.
          </EmptyState>
        ) : (
          <Table head={['Time', 'Label', 'Trigger', 'Lifecycle', 'Size', '']}>
            {data.map((s) => (
              <tr key={s.id} className="hover:bg-panel-800/60">
                <td className="whitespace-nowrap px-3 py-1.5 font-mono text-xs text-ink-500">
                  {clockMs(s.ts)}
                </td>
                <td className="px-3 py-1.5 text-ink-200">{s.label}</td>
                <td className="px-3 py-1.5">
                  <Badge tone={s.trigger === 'manual' ? 'info' : 'idle'} className="!py-0 !text-xs">
                    {s.trigger}
                  </Badge>
                </td>
                <td className="px-3 py-1.5 font-mono text-xs text-ink-400">
                  {s.lifecycle}
                </td>
                <td className="px-3 py-1.5 font-mono text-ink-500">
                  {(s.payload_bytes / 1000).toFixed(0)} kB
                </td>
                <td className="px-3 py-1.5">
                  <Button variant="ghost" size="sm" onClick={() => open(s.id)}>
                    View
                  </Button>
                </td>
              </tr>
            ))}
          </Table>
        )}
      </Panel>

      <Panel title="Snapshot detail">
        {!selected ? (
          <EmptyState>Select a snapshot.</EmptyState>
        ) : (
          <pre className="max-h-[520px] overflow-auto rounded-lg bg-panel-950 p-3 font-mono text-xs leading-relaxed text-ink-300">
            {JSON.stringify(selected.payload ?? selected, null, 2)}
          </pre>
        )}
      </Panel>
    </div>
  )
}

function SessionsTab() {
  const { data, loading } = useQuery<Record<string, unknown>[]>(() =>
    api.historySessions(100),
  )

  return (
    <Panel title="Recording sessions">
      {loading ? (
        <EmptyState>Loading…</EmptyState>
      ) : !data?.length ? (
        <EmptyState>
          No recordings. Press <strong>Start Recording</strong> on the Data page.
        </EmptyState>
      ) : (
        <Table head={['Started', 'Label', 'Duration', 'Samples', 'Interval', 'Deadband', 'Status', '']}>
          {data.map((s) => {
            const uid = String(s.session_uid)
            const started = Number(s.started_at)
            const ended = s.ended_at ? Number(s.ended_at) : null
            return (
              <tr key={uid} className="hover:bg-panel-800/60">
                <td className="whitespace-nowrap px-3 py-1.5 font-mono text-xs text-ink-500">
                  {clockMs(started)}
                </td>
                <td className="px-3 py-1.5 text-ink-200">{String(s.label ?? '')}</td>
                <td className="px-3 py-1.5 font-mono text-ink-300">
                  {ended ? duration(ended - started) : 'running'}
                </td>
                <td className="px-3 py-1.5 font-mono text-state-run">
                  {String(s.sample_count ?? 0)}
                </td>
                <td className="px-3 py-1.5 font-mono text-ink-400">
                  {num(Number(s.sample_interval_s), 2)} s
                </td>
                <td className="px-3 py-1.5 font-mono text-ink-400">
                  {num(Number(s.deadband), 4)}
                </td>
                <td className="px-3 py-1.5">
                  <Badge
                    tone={s.status === 'ACTIVE' ? 'fault' : 'run'}
                    className="!py-0 !text-xs"
                  >
                    {String(s.status)}
                  </Badge>
                </td>
                <td className="px-3 py-1.5">
                  <a
                    href={api.exportSessionUrl(uid)}
                    className="inline-flex items-center gap-1 rounded border border-panel-600 px-2 py-1 text-xs text-ink-300 hover:bg-panel-700"
                    title="Download this recording as CSV"
                  >
                    <FileDown size={11} />
                    CSV
                  </a>
                </td>
              </tr>
            )
          })}
        </Table>
      )}
    </Panel>
  )
}
