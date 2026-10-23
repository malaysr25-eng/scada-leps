/**
 * Typed REST client.
 *
 * Every call returns a discriminated `ApiResult`, never a thrown string. A
 * refused command is a normal, expected outcome in this application -- the
 * gate refuses writes constantly and on purpose -- so refusal must be
 * something the UI *renders*, not something it catches.
 */

import type {
  ApiResult,
  ChatMessage,
  ChatStatus,
  CommandEntry,
  DataSourcesState,
  EventEntry,
  FaultEntry,
  HistoryAlarm,
  HistoryCycle,
  HistoryEvent,
  HistorySnapshot,
  HistorySummary,
  MachineMode,
  RecordingState,
  Snapshot,
  SourceInfo,
  TagInfo,
} from '../types'

const BASE = ''

async function request<T>(
  path: string,
  init?: RequestInit,
): Promise<ApiResult<T>> {
  try {
    const res = await fetch(BASE + path, {
      headers: { 'Content-Type': 'application/json' },
      ...init,
    })
    const body = await res.json().catch(() => null)

    if (body && typeof body === 'object' && 'ok' in body) {
      return body as ApiResult<T>
    }
    if (res.ok) {
      return { ok: true, data: body as T }
    }
    return {
      ok: false,
      error: { code: 'http_' + res.status, message: res.statusText },
    }
  } catch (err) {
    // Network failure is the normal state during a backend restart. Surface it
    // as data so the UI can show "backend unreachable" instead of blanking.
    return {
      ok: false,
      error: {
        code: 'network',
        message: err instanceof Error ? err.message : String(err),
      },
    }
  }
}

const post = <T>(path: string, body?: unknown) =>
  request<T>(path, { method: 'POST', body: JSON.stringify(body ?? {}) })

// ---------------------------------------------------------------------------

export const api = {
  state: () => request<Snapshot>('/api/state'),

  health: () =>
    request<{
      uptimeSeconds: number
      plc: string
      plcSimulated: boolean
      tags: number
      subscribers: number
      registryWarnings: string[]
    }>('/api/health'),

  // -- tags ---------------------------------------------------------------

  tags: (params: Record<string, string | number | undefined> = {}) => {
    const qs = new URLSearchParams()
    Object.entries(params).forEach(([k, v]) => {
      if (v !== undefined && v !== '') qs.set(k, String(v))
    })
    const suffix = qs.toString() ? `?${qs}` : ''
    return request<{
      tags: TagInfo[]
      groups: string[]
      total: number
      registryWarnings: string[]
    }>(`/api/tags${suffix}`)
  },

  tag: (id: string) =>
    request<TagInfo & { history: unknown[]; writePreview: unknown }>(
      `/api/tags/${encodeURIComponent(id)}`,
    ),

  writeTag: (id: string, value: unknown, confirm = false) =>
    post<CommandEntry>(`/api/tags/${encodeURIComponent(id)}/write`, {
      value,
      confirm,
    }),

  history: (id: string, limit = 100) =>
    request<unknown[]>(`/api/history/${encodeURIComponent(id)}?limit=${limit}`),

  // -- watch list ---------------------------------------------------------

  addWatch: (tagId: string) => post<string[]>('/api/watch', { action: 'add', tagId }),
  removeWatch: (tagId: string) =>
    post<string[]>('/api/watch', { action: 'remove', tagId }),

  // -- mode + cycle -------------------------------------------------------

  setMode: (mode: MachineMode) => post<unknown>('/api/mode', { mode }),

  startCycle: (qty25: number, qty50: number, highSpeed: boolean) =>
    post<{ commands: CommandEntry[] }>('/api/cycle/start', {
      qty25,
      qty50,
      highSpeed,
    }),

  stopCycle: () => post<CommandEntry>('/api/cycle/stop'),
  resetCycle: (force = false) => post<CommandEntry>('/api/cycle/reset', { force }),
  engravingComplete: () => post<CommandEntry>('/api/engraving/complete'),

  // -- diagnostics --------------------------------------------------------

  events: (limit = 200, minSeverity?: string) =>
    request<EventEntry[]>(
      `/api/events?limit=${limit}${minSeverity ? `&minSeverity=${minSeverity}` : ''}`,
    ),

  faults: () => request<FaultEntry[]>('/api/faults'),

  acknowledgeFault: (key: string) =>
    post<unknown>(`/api/faults/${encodeURIComponent(key)}/acknowledge`),

  diagnostics: () => request<Record<string, unknown>>('/api/diagnostics'),

  commands: (limit = 60) => request<CommandEntry[]>(`/api/commands?limit=${limit}`),

  // -- sequence / camera / twin -------------------------------------------

  sequence: () =>
    request<{ catalogue: unknown[]; live: unknown }>('/api/sequence'),

  cameraState: () => request<unknown>('/api/camera/state'),

  twinReference: () => request<Record<string, unknown>>('/api/digital-twin/reference'),
  reloadTwin: () => post<Record<string, unknown>>('/api/digital-twin/reload'),

  // -- data sources -------------------------------------------------------

  sources: () => request<DataSourcesState>('/api/sources'),
  source: (id: string) => request<SourceInfo>(`/api/sources/${id}`),

  /** Hand machine control to a source. Telemetry-only sources are refused. */
  setControlSource: (sourceId: string | null) =>
    post<DataSourcesState>('/api/sources/control', { sourceId }),

  /** Change which source feeds the dashboards. Grants no control. */
  setTelemetrySource: (sourceId: string) =>
    post<DataSourcesState>('/api/sources/telemetry', { sourceId }),

  startSource: (id: string) => post<SourceInfo>(`/api/sources/${id}/start`),
  stopSource: (id: string) => post<SourceInfo>(`/api/sources/${id}/stop`),

  mode: () => request<Record<string, unknown>>('/api/mode'),

  // -- persistence --------------------------------------------------------

  saveSnapshot: (label?: string, note?: string) =>
    post<{ savedAt: number; bytes: number; label: string }>(
      '/api/data/snapshot', { label, note },
    ),

  startRecording: (opts: {
    label?: string; note?: string
    sampleInterval?: number; deadband?: number; tagFilter?: string[]
  } = {}) => post<RecordingState['session']>('/api/data/recording/start', opts),

  stopRecording: () => post<RecordingState['session']>('/api/data/recording/stop'),
  recordingStatus: () => request<RecordingState>('/api/data/recording/status'),

  saveCycle: (note?: string) =>
    post<{ cycleId: string; outcome: string }>('/api/data/cycle/save', { note }),

  dbStatus: () => request<Record<string, unknown>>('/api/db/status'),

  // -- history ------------------------------------------------------------

  historySummary: () => request<HistorySummary>('/api/history/summary'),

  historyEvents: (params: Record<string, string | number | undefined> = {}) =>
    request<HistoryEvent[]>('/api/history/events' + qs(params)),

  historyAlarms: (params: Record<string, string | number | undefined> = {}) =>
    request<HistoryAlarm[]>('/api/history/alarms' + qs(params)),

  historyStates: (params: Record<string, string | number | undefined> = {}) =>
    request<Record<string, unknown>[]>('/api/history/states' + qs(params)),

  historyCycles: (limit = 50) =>
    request<HistoryCycle[]>(`/api/history/cycles?limit=${limit}`),

  historyCycle: (cycleId: string) =>
    request<Record<string, unknown>>(`/api/history/cycles/${encodeURIComponent(cycleId)}`),

  historyCommands: (params: Record<string, string | number | undefined> = {}) =>
    request<Record<string, unknown>[]>('/api/history/commands' + qs(params)),

  historySnapshots: (limit = 50) =>
    request<HistorySnapshot[]>(`/api/history/snapshots?limit=${limit}`),

  historySnapshot: (id: number) =>
    request<Record<string, unknown>>(`/api/history/snapshots/${id}`),

  historySessions: (limit = 50) =>
    request<Record<string, unknown>[]>(`/api/history/sessions?limit=${limit}`),

  historySession: (uid: string) =>
    request<Record<string, unknown>>(`/api/history/sessions/${uid}`),

  historySessionSamples: (uid: string, tagId?: string, limit = 2000) =>
    request<Record<string, unknown>[]>(
      `/api/history/sessions/${uid}/samples` + qs({ tagId, limit }),
    ),

  exportSessionUrl: (uid: string, tagId?: string) =>
    `/api/history/sessions/${uid}/export` + qs({ tagId }),

  // -- help assistant -----------------------------------------------------

  chat: (message: string, sessionId = 'default') =>
    post<ChatMessage>('/api/chat', { message, sessionId }),

  chatHistory: (sessionId = 'default') =>
    request<ChatMessage[]>(`/api/chat/history?sessionId=${sessionId}`),

  chatClear: (sessionId = 'default') =>
    post<{ cleared: boolean }>('/api/chat/clear', { sessionId }),

  chatStatus: () => request<ChatStatus>('/api/chat/status'),

  /** The exact redacted context the assistant is given -- auditable. */
  chatContext: () => request<Record<string, unknown>>('/api/chat/context'),
}

function qs(params: Record<string, string | number | undefined>): string {
  const search = new URLSearchParams()
  Object.entries(params).forEach(([k, v]) => {
    if (v !== undefined && v !== '') search.set(k, String(v))
  })
  const s = search.toString()
  return s ? `?${s}` : ''
}
