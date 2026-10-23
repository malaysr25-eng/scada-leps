/**
 * Client for LEPS's server (predictive_maintenance/leps/web.py).
 *
 * It is a separate process on this PC (port 5052), started with the dashboard.
 * It only listens on 127.0.0.1 and only answers this page's own origin, so the
 * Assistant works in a browser on the lab PC itself and nowhere else -- the
 * chat can confirm writes to the cell, which must never be reachable over the
 * network. POSTs carry X-LEPS: 1 (the server refuses them without it).
 */

export type AssistantEventKind =
  | 'user' | 'ai' | 'tool' | 'cmd' | 'info' | 'error'
  | 'ask' | 'prompt' | 'answer' | 'done'

export interface AssistantEvent {
  id: number
  kind: AssistantEventKind
  text: string
  at: number
  askId?: number
  timedOut?: boolean
}

export interface AssistantPending {
  id: number
  type: 'ask' | 'prompt'
  question: string
  secret?: boolean     // a sign-in code: hidden while typed, never shown back
}

/** Who a subscription brain (Claude Code, Codex) is signed in as, on this Windows user. */
export interface AssistantAccount {
  service: string
  label: string
  installed: boolean
  loggedIn: boolean
  account: string
  detail: string
}

export interface AssistantEngine {
  name: string
  label: string
  availability: string
}

/** One provider of the "API key" brain (Anthropic, OpenAI, Gemini, ... or a custom URL). */
export interface AssistantProvider {
  name: string
  label: string
  saved: boolean
  page: string
  hint: string        // the stored key's last 4 characters
  model: string
}

export interface AssistantStatus {
  engine: string
  engineLabel: string
  model: string
  target: string
  engines: AssistantEngine[]
  api: { provider: string; customUrl: string; providers: AssistantProvider[] }
  accounts: Record<string, AssistantAccount>
  busy: boolean
  pending: AssistantPending | null
  tools: number
  lastEvent: number
}

export interface AssistantProgram {
  component: string
  state: string
  pid?: number
  since?: string
  port?: string
  health?: string
}

export interface AssistantTask {
  token: string
  title: string
  state: string
  started?: string
}

const PORT = 5052   // not 5060: browsers refuse that port (SIP, ERR_UNSAFE_PORT)

/** Only a page opened on this PC can reach the assistant. */
export function assistantReachable(): boolean {
  const h = window.location.hostname
  return h === '127.0.0.1' || h === 'localhost'
}

function base(): string {
  return `http://${window.location.hostname}:${PORT}`
}

async function call<T>(path: string, body?: unknown, signal?: AbortSignal): Promise<T> {
  const res = await fetch(base() + path, {
    method: body === undefined ? 'GET' : 'POST',
    headers: body === undefined ? undefined : { 'Content-Type': 'application/json', 'X-LEPS': '1' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal,
  })
  const data = await res.json().catch(() => ({}))
  if (!res.ok) throw new Error((data as { error?: string }).error ?? `HTTP ${res.status}`)
  return data as T
}

export const assistant = {
  status: () => call<AssistantStatus>('/api/status'),
  events: (after: number, wait: number, signal?: AbortSignal) =>
    call<{ events: AssistantEvent[]; gap: boolean; busy: boolean; pending: AssistantPending | null }>(
      `/api/events?after=${after}&wait=${wait}`, undefined, signal),
  send: (text: string) => call<{ ok: boolean }>('/api/send', { text }),
  answer: (id: number, value: boolean | string) => call<{ ok: boolean }>('/api/answer', { id, value }),
  stop: () => call<{ ok: boolean }>('/api/stop', {}),
  newChat: () => call<{ ok: boolean }>('/api/new', {}),
  setEngine: (engine: string) => call<AssistantStatus>('/api/engine', { engine }),
  setModel: (model: string) => call<AssistantStatus>('/api/model', { model }),
  /** provider '' = told from the key; url only for the custom provider. */
  addKey: (key: string, provider: string, url: string) =>
    call<AssistantStatus & { message: string; models: string[] }>('/api/key', { key, provider, url }),
  useProvider: (provider: string) => call<AssistantStatus>('/api/provider', { provider }),
  removeKey: (provider: string) => call<AssistantStatus>('/api/key/remove', { provider }),
  models: (provider = '') =>
    call<{ models: string[] }>(`/api/models${provider ? `?provider=${encodeURIComponent(provider)}` : ''}`),
  programs: () => call<{ programs: AssistantProgram[]; tasks: AssistantTask[] }>('/api/programs'),
  program: (name: string, action: 'start' | 'stop') =>
    call<{ result: string }>('/api/program', { name, action }),
}
