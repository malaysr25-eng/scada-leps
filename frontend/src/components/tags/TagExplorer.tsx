/**
 * Tag Explorer -- the useful half of the old PLC dashboard, kept and improved.
 *
 * It keeps: search across all tags, live values, DB addresses, descriptions.
 *
 * It adds: filtering by subsystem, data type, access class, provenance and
 * recent change; pinning to the watch list; per-tag change history; and, most
 * importantly, an honest **access class** on every row.
 *
 * The old dashboard offered a Toggle button beside all 121 tags with no
 * distinction between a proximity-sensor input, an output-image mirror and a
 * manual command bit. Writing the first two does nothing useful and the PLC
 * overwrites them on its next scan, which produces exactly the "I toggled it
 * and nothing happened" confusion the Errors sheet is full of. Here the class
 * is shown on the row and enforced by the backend.
 */

import { useEffect, useMemo, useState } from 'react'
import { Loader2, RefreshCw, Search, ShieldAlert } from 'lucide-react'
import { api } from '../../services/api'
import { useMachine } from '../../stores/machineStore'
import type { TagAccess, TagInfo } from '../../types'
import { ago, classNames, pretty } from '../../utils/format'
import { Badge, Button, EmptyState, Note, Panel } from '../common/Primitives'
import { PinButton, SourceBadge } from '../diagnostics/DiagnosticsPanels'

const ACCESS_META: Record<
  TagAccess,
  { tone: 'idle' | 'info' | 'warn' | 'fault'; label: string; hint: string }
> = {
  read_only: {
    tone: 'idle',
    label: 'Read only',
    hint: 'Reports state. Writing it achieves nothing — the PLC drives this address.',
  },
  safe_manual: {
    tone: 'info',
    label: 'Manual',
    hint: 'The sanctioned manual write path. Allowed in MANUAL mode, interlocked.',
  },
  engineering: {
    tone: 'warn',
    label: 'Engineering',
    hint: 'Changes a setpoint the PLC program also writes. MAINTENANCE mode, confirmation required.',
  },
  protected: {
    tone: 'fault',
    label: 'Protected',
    hint: 'Safety or process critical. Reachable only through a dedicated validated endpoint.',
  },
}

export function TagExplorer() {
  const snapshot = useMachine((s) => s.snapshot)
  const pushToast = useMachine((s) => s.pushToast)

  const [tags, setTags] = useState<TagInfo[]>([])
  const [groups, setGroups] = useState<string[]>([])
  const [warnings, setWarnings] = useState<string[]>([])
  const [loading, setLoading] = useState(true)

  const [query, setQuery] = useState('')
  const [group, setGroup] = useState('')
  const [dtype, setDtype] = useState('')
  const [access, setAccess] = useState('')
  const [provenance, setProvenance] = useState('')
  const [recentOnly, setRecentOnly] = useState(false)
  const [selected, setSelected] = useState<string | null>(null)

  // The tag *catalogue* is fetched once; live values ride the SSE snapshot, so
  // this table stays current without re-fetching 158 rows four times a second.
  async function load() {
    setLoading(true)
    const res = await api.tags()
    setLoading(false)
    if (res.ok) {
      setTags(res.data.tags)
      setGroups(res.data.groups)
      setWarnings(res.data.registryWarnings)
    } else {
      pushToast({ kind: 'error', title: 'Could not load tags', detail: res.error.message })
    }
  }

  useEffect(() => {
    void load()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])

  const liveValues = useMemo(() => {
    // Rebuild a tagId -> live value map from the snapshot's device views.
    const map = new Map<string, unknown>()
    snapshot?.sensors.forEach((s) => map.set(s.tagId, s.value))
    snapshot?.actuators.forEach((a) => {
      map.set(a.stateTagId, a.state)
      if (a.manualTagId) map.set(a.manualTagId, a.manualCommand)
    })
    snapshot?.diagnostics.watch.forEach((w) => map.set(w.tagId, w.value))
    return map
  }, [snapshot])

  const watched = useMemo(
    () => new Set((snapshot?.diagnostics.watch ?? []).map((w) => w.tagId)),
    [snapshot?.diagnostics.watch],
  )

  const changedRecently = useMemo(
    () =>
      new Set(
        (snapshot?.diagnostics.recentChanges ?? []).map((c) => c.tagId),
      ),
    [snapshot?.diagnostics.recentChanges],
  )

  const filtered = useMemo(() => {
    const q = query.trim().toLowerCase()
    return tags.filter((t) => {
      if (group && t.group !== group) return false
      if (dtype && t.dtype !== dtype) return false
      if (access && t.access !== access) return false
      if (provenance && t.provenance !== provenance) return false
      if (recentOnly && !changedRecently.has(t.id)) return false
      if (!q) return true
      return (
        t.name.toLowerCase().includes(q) ||
        t.short.toLowerCase().includes(q) ||
        t.address.toLowerCase().includes(q) ||
        t.description.toLowerCase().includes(q) ||
        (t.role ?? '').toLowerCase().includes(q)
      )
    })
  }, [tags, query, group, dtype, access, provenance, recentOnly, changedRecently])

  const selectedTag = tags.find((t) => t.id === selected) ?? null

  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_340px]">
      <Panel
        title="Tag explorer"
        subtitle={`${filtered.length} of ${tags.length} tags`}
        actions={
          <Button variant="ghost" size="sm" onClick={load} disabled={loading}>
            {loading ? (
              <Loader2 size={13} className="animate-spin" />
            ) : (
              <RefreshCw size={13} />
            )}
            Reload
          </Button>
        }
      >
        {warnings.length > 0 && (
          <Note tone="warn">
            <strong>Registry warnings:</strong>
            <ul className="ml-4 mt-1 list-disc">
              {warnings.map((w) => (
                <li key={w}>{w}</li>
              ))}
            </ul>
          </Note>
        )}

        <div className="mb-3 flex flex-wrap gap-2">
          <div className="relative min-w-[200px] flex-1">
            <Search
              size={14}
              className="pointer-events-none absolute left-2.5 top-1/2 -translate-y-1/2 text-ink-600"
            />
            <input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="Search name, address, description or role…"
              className="w-full rounded-lg border border-panel-600 bg-panel-900 py-2 pl-8 pr-3 text-sm text-ink-100 placeholder:text-ink-600 focus:outline-none focus:ring-1 focus:ring-state-info/50"
            />
          </div>

          <Select value={group} onChange={setGroup} placeholder="All subsystems">
            {groups.map((g) => (
              <option key={g} value={g}>
                {g}
              </option>
            ))}
          </Select>

          <Select value={dtype} onChange={setDtype} placeholder="All types">
            {['Bool', 'Int', 'Real'].map((t) => (
              <option key={t} value={t}>
                {t}
              </option>
            ))}
          </Select>

          <Select value={access} onChange={setAccess} placeholder="All access">
            {Object.entries(ACCESS_META).map(([k, v]) => (
              <option key={k} value={k}>
                {v.label}
              </option>
            ))}
          </Select>

          <Select value={provenance} onChange={setProvenance} placeholder="All sources">
            <option value="documented">Documented</option>
            <option value="undocumented">Undocumented</option>
          </Select>

          <button
            onClick={() => setRecentOnly((v) => !v)}
            className={classNames(
              'rounded-lg border px-3 py-2 text-xs font-medium transition-colors',
              recentOnly
                ? 'border-state-info/50 bg-state-info/12 text-state-info'
                : 'border-panel-600 bg-panel-900 text-ink-400 hover:text-ink-200',
            )}
          >
            Changed recently
          </button>
        </div>

        {filtered.length === 0 ? (
          <EmptyState>No tags match these filters.</EmptyState>
        ) : (
          <div className="max-h-[calc(100vh-330px)] overflow-auto rounded-lg border border-panel-700">
            <table className="w-full text-left text-xs">
              <thead className="sticky top-0 z-10 bg-panel-800">
                <tr className="text-[10px] uppercase tracking-wider text-ink-400">
                  <th className="w-8 py-2 pl-2" />
                  <th className="py-2 pr-3 font-medium">Tag</th>
                  <th className="py-2 pr-3 font-medium">Address</th>
                  <th className="py-2 pr-3 font-medium">Type</th>
                  <th className="py-2 pr-3 font-medium">Access</th>
                  <th className="py-2 pr-3 font-medium">Value</th>
                  <th className="py-2 pr-3 font-medium">Changed</th>
                </tr>
              </thead>
              <tbody className="divide-y divide-panel-800">
                {filtered.map((t) => {
                  const live = liveValues.has(t.id) ? liveValues.get(t.id) : t.value
                  const meta = ACCESS_META[t.access]
                  return (
                    <tr
                      key={t.id}
                      onClick={() => setSelected(t.id)}
                      className={classNames(
                        'cursor-pointer hover:bg-panel-800/70',
                        selected === t.id && 'bg-state-info/8',
                      )}
                    >
                      <td className="py-1.5 pl-2" onClick={(e) => e.stopPropagation()}>
                        <PinButton tagId={t.id} pinned={watched.has(t.id)} />
                      </td>
                      <td className="py-1.5 pr-3">
                        <div className="flex items-center gap-1.5">
                          <span className="text-ink-200">{t.short}</span>
                          {t.provenance === 'undocumented' && (
                            <span
                              className="rounded bg-state-warn/20 px-1 text-[9px] font-bold text-state-warn"
                              title="Not present in Tag_list (1).xlsx — meaning unconfirmed"
                            >
                              UNDOC
                            </span>
                          )}
                        </div>
                        <div className="truncate text-[10px] text-ink-600" title={t.name}>
                          {t.group}
                        </div>
                      </td>
                      <td className="py-1.5 pr-3 font-mono text-[10px] text-ink-400">
                        {t.address}
                      </td>
                      <td className="py-1.5 pr-3 text-ink-500">{t.dtype}</td>
                      <td className="py-1.5 pr-3">
                        <Badge tone={meta.tone} title={meta.hint} className="!py-0 !text-[9px]">
                          {meta.label}
                        </Badge>
                      </td>
                      <td
                        className={classNames(
                          'py-1.5 pr-3 font-mono font-semibold',
                          live === true
                            ? 'text-state-run'
                            : live === false
                              ? 'text-ink-400'
                              : 'text-ink-600',
                        )}
                      >
                        {pretty(live)}
                      </td>
                      <td className="py-1.5 pr-3 text-[10px] text-ink-500">
                        {ago(t.lastChangeAt)}
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        )}
      </Panel>

      <div className="space-y-4">
        {selectedTag ? (
          <TagDetail tag={selectedTag} pinned={watched.has(selectedTag.id)} />
        ) : (
          <Panel title="Tag detail">
            <EmptyState>Select a tag to inspect it.</EmptyState>
          </Panel>
        )}

        <Panel title="Access classes">
          <ul className="space-y-2 text-xs">
            {Object.entries(ACCESS_META).map(([k, v]) => (
              <li key={k} className="flex gap-2">
                <Badge tone={v.tone} className="!py-0 !text-[9px] shrink-0">
                  {v.label}
                </Badge>
                <span className="text-ink-400">{v.hint}</span>
              </li>
            ))}
          </ul>
        </Panel>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------

function Select({
  value,
  onChange,
  placeholder,
  children,
}: {
  value: string
  onChange: (v: string) => void
  placeholder: string
  children: React.ReactNode
}) {
  return (
    <select
      value={value}
      onChange={(e) => onChange(e.target.value)}
      className="rounded-lg border border-panel-600 bg-panel-900 px-2.5 py-2 text-xs text-ink-200 focus:outline-none focus:ring-1 focus:ring-state-info/50"
    >
      <option value="">{placeholder}</option>
      {children}
    </select>
  )
}

function TagDetail({ tag, pinned }: { tag: TagInfo; pinned: boolean }) {
  const [detail, setDetail] = useState<
    (TagInfo & { history: unknown[]; writePreview: unknown }) | null
  >(null)

  useEffect(() => {
    let cancelled = false
    void api.tag(tag.id).then((res) => {
      if (!cancelled && res.ok) setDetail(res.data)
    })
    return () => {
      cancelled = true
    }
  }, [tag.id])

  const history = (detail?.history ?? []) as Array<{
    at: number
    previous: unknown
    value: unknown
    source: 'operator' | 'plc' | 'contested'
  }>

  const meta = ACCESS_META[tag.access]

  return (
    <Panel
      title={tag.short}
      subtitle={tag.address}
      actions={<PinButton tagId={tag.id} pinned={pinned} />}
    >
      <dl className="space-y-2 text-xs">
        <DetailRow label="Symbolic">
          <span className="break-all font-mono text-[10px] text-ink-300">{tag.name}</span>
        </DetailRow>
        <DetailRow label="Role">
          <span className="font-mono text-[10px] text-ink-400">{tag.role ?? '--'}</span>
        </DetailRow>
        <DetailRow label="Subsystem">
          <span className="text-ink-300">{tag.group}</span>
        </DetailRow>
        <DetailRow label="Type">
          <span className="text-ink-300">
            {tag.dtype} · DB{tag.db} byte {tag.byte}
            {tag.dtype === 'Bool' ? ` bit ${tag.bit}` : ''}
          </span>
        </DetailRow>
        <DetailRow label="Access">
          <Badge tone={meta.tone} className="!py-0 !text-[9px]">
            {meta.label}
          </Badge>
          <p className="mt-1 text-[11px] leading-snug text-ink-500">{meta.hint}</p>
        </DetailRow>
        <DetailRow label="Source">
          {tag.provenance === 'documented' ? (
            <span className="text-ink-300">
              Documented in Tag_list — sheet “{tag.sheet}”
            </span>
          ) : (
            <span className="flex items-start gap-1.5 text-state-warn">
              <ShieldAlert size={12} className="mt-0.5 shrink-0" />
              Undocumented address
            </span>
          )}
        </DetailRow>
        {tag.description && (
          <DetailRow label="Description">
            <span className="leading-snug text-ink-400">{tag.description}</span>
          </DetailRow>
        )}
        {tag.notes && (
          <DetailRow label="Engineering note">
            <span className="leading-snug text-ink-400">{tag.notes}</span>
          </DetailRow>
        )}
      </dl>

      <div className="mt-3 border-t border-panel-700 pt-3">
        <h3 className="mb-2 text-[10px] uppercase tracking-wider text-ink-500">
          Change history
        </h3>
        {history.length === 0 ? (
          <p className="text-xs text-ink-600">No transitions recorded this session.</p>
        ) : (
          <div className="max-h-56 space-y-0.5 overflow-y-auto">
            {history.map((h, i) => (
              <div
                key={i}
                className="flex items-center gap-2 rounded px-1.5 py-1 font-mono text-[10px] hover:bg-panel-800"
              >
                <span className="text-ink-600">
                  {new Date(h.at * 1000).toLocaleTimeString()}
                </span>
                <span className="text-ink-500">{pretty(h.previous)}</span>
                <span className="text-ink-600">→</span>
                <span
                  className={
                    h.value === true ? 'font-bold text-state-run' : 'text-ink-300'
                  }
                >
                  {pretty(h.value)}
                </span>
                <span className="ml-auto">
                  <SourceBadge source={h.source} />
                </span>
              </div>
            ))}
          </div>
        )}
      </div>
    </Panel>
  )
}

function DetailRow({
  label,
  children,
}: {
  label: string
  children: React.ReactNode
}) {
  return (
    <div className="border-b border-panel-800 pb-1.5 last:border-0">
      <dt className="text-[10px] uppercase tracking-wider text-ink-500">{label}</dt>
      <dd className="mt-0.5">{children}</dd>
    </div>
  )
}
