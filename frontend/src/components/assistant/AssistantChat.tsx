/**
 * The Assistant chat: LEPS (predictive_maintenance/leps) in the page.
 *
 * Unlike the old read-only Help panel, this assistant CAN operate the cell --
 * through the cell MCP server's guard, and only after the operator's own yes.
 * Two places make that yes explicit:
 *   - a question from the assistant ("Run this plan on the real cell?") shows
 *     as a card with Yes / No buttons; nothing else answers it, and leaving it
 *     unanswered counts as No;
 *   - the cell server refuses any write unless the operator's latest message
 *     was a yes, a start order with quantities, or "eng done" (LEPS's
 *     permit), whatever the AI decides.
 */

import { useEffect, useMemo, useRef, useState, type CSSProperties } from 'react'
import {
  AlertTriangle, Bot, Check, Cpu, ExternalLink, KeyRound, Loader2, RotateCcw, Send, Square, Terminal,
  Trash2, User, WifiOff, X,
} from 'lucide-react'
import {
  assistant, type AssistantAccount, type AssistantEvent, type AssistantStatus,
} from '../../services/assistant'
import { refreshAssistantStatus, useAssistant } from '../../stores/assistantStore'
import { classNames, clock } from '../../utils/format'
import { Badge, Button } from '../common/Primitives'

const QUICK = [
  { label: 'Status', text: 'status' },
  { label: 'Start 1×50', text: 'start 1x50' },
  { label: 'Start 1×25', text: 'start 1x25' },
  { label: 'Eng done', text: 'eng done' },
  { label: 'Watch', text: 'watch' },
  { label: 'Fault?', text: 'fault' },
  { label: 'Stop cycle', text: 'stop' },
]

export function AssistantChat({ compact = false, onClose }: { compact?: boolean; onClose?: () => void }) {
  const link = useAssistant((s) => s.link)
  const events = useAssistant((s) => s.events)
  const busy = useAssistant((s) => s.busy)
  const pending = useAssistant((s) => s.pending)
  const [input, setInput] = useState('')
  const [error, setError] = useState('')
  const endRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' })
  }, [events.length, pending?.id])

  const answers = useMemo(() => {
    const m = new Map<number, AssistantEvent>()
    for (const e of events) if (e.kind === 'answer' && e.askId) m.set(e.askId, e)
    return m
  }, [events])

  async function send(text?: string) {
    const msg = (text ?? input).trim()
    if (!msg) return
    if (pending?.type === 'prompt') {
      setInput('')
      return answer(pending.id, msg)
    }
    if (busy) return
    setError('')
    setInput('')
    try {
      await assistant.send(msg)
    } catch (e) {
      setError(String((e as Error).message))
      setInput(msg)
    }
    inputRef.current?.focus()
  }

  async function answer(id: number, value: boolean | string) {
    try {
      await assistant.answer(id, value)
    } catch (e) {
      setError(String((e as Error).message))
    }
  }

  return (
    <div className={classNames('flex min-h-0 flex-col', compact ? 'h-full' : 'h-full')}>
      <ChatHeader compact={compact} onClose={onClose} />

      {link !== 'online' ? (
        <Offline />
      ) : (
        <div className="min-h-0 flex-1 space-y-2.5 overflow-y-auto px-3 py-3">
          {events.length === 0 && <Welcome />}
          {events.map((e) => (
            <EventView key={e.id} e={e} pendingId={pending?.id} answer={answers.get(e.id)} onAnswer={answer} />
          ))}
          {busy && !pending && (
            <div className="flex items-center gap-2 pl-1 text-xs text-ink-400">
              <Loader2 size={14} className="animate-spin text-state-info" />
              Working…
            </div>
          )}
          <div ref={endRef} />
        </div>
      )}

      <div className="border-t border-panel-700 p-2.5">
        {!compact && (
          <div className="mb-2 flex flex-wrap gap-1.5">
            {QUICK.map((q) => (
              <button
                key={q.text}
                disabled={busy || link !== 'online'}
                onClick={() => void send(q.text)}
                className="rounded-md border border-panel-600 bg-panel-800 px-2 py-1 text-xs font-medium text-ink-300 transition-colors hover:border-state-info/50 hover:text-state-info disabled:opacity-40"
              >
                {q.label}
              </button>
            ))}
          </div>
        )}
        {error && <p className="mb-1.5 text-xs text-state-fault">{error}</p>}
        <div className="flex items-end gap-2">
          <textarea
            ref={inputRef}
            rows={compact ? 2 : 2}
            value={input}
            disabled={link !== 'online'}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault()
                void send()
              }
            }}
            placeholder={
              pending?.type === 'prompt'
                ? pending.question
                : busy
                  ? 'Working… (Stop ends the answer; the cell is not affected)'
                  : 'Ask, or type a command: status · start 1x50 · eng done · help'
            }
            autoComplete="off"
            style={pending?.secret ? ({ WebkitTextSecurity: 'disc' } as unknown as CSSProperties) : undefined}
            className="min-h-[44px] flex-1 resize-none rounded-lg border border-panel-600 bg-panel-900 px-3 py-2 text-sm text-ink-100 placeholder:text-ink-500 focus:border-state-info/60 focus:outline-none"
          />
          {busy && !pending ? (
            <Button variant="warn" onClick={() => void assistant.stop()} title="Stop this answer (not the cell)">
              <Square size={15} /> Stop
            </Button>
          ) : (
            <Button variant="primary" onClick={() => void send()} disabled={!input.trim() || link !== 'online'}>
              <Send size={15} /> Send
            </Button>
          )}
        </div>
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------

function ChatHeader({ compact, onClose }: { compact: boolean; onClose?: () => void }) {
  const status = useAssistant((s) => s.status)
  const busy = useAssistant((s) => s.busy)
  const link = useAssistant((s) => s.link)
  const [keysOpen, setKeysOpen] = useState(false)
  const [msg, setMsg] = useState('')

  async function choose(name: string) {
    setMsg('')
    if (name === 'api' && !status?.api.providers.some((p) => p.saved)) {
      setKeysOpen(true)              // no key yet: the panel adds one and switches the brain
      return
    }
    try {
      const st = await assistant.setEngine(name)
      if (name === 'api' && st.engine !== 'api') setKeysOpen(true)    // a key without a chosen model
    } catch (e) {
      setMsg(String((e as Error).message))
    }
    void refreshAssistantStatus()
  }

  return (
    <div className="border-b border-panel-700 px-3 py-2.5">
      <div className="flex items-center gap-2">
        <span className="grid h-7 w-7 place-items-center rounded-lg bg-state-info/15 text-state-info">
          <Bot size={16} />
        </span>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-2">
            <h2 className="text-sm font-semibold uppercase tracking-[0.13em] text-ink-200">LEPS</h2>
            <Badge tone={status?.target === 'real' ? 'run' : 'warn'} className="!py-0 !text-xs">
              {status?.target === 'real' ? 'real cell' : status?.target ?? '…'}
            </Badge>
          </div>
          {!compact && (
            <p className="truncate text-xs text-ink-500">
              Operates the cell through the guard; every write needs your yes
            </p>
          )}
        </div>
        {status && link === 'online' && (
          <select
            value={status.engine}
            disabled={busy}
            onChange={(e) => void choose(e.target.value)}
            title="The brain"
            className="max-w-[46%] rounded-md border border-panel-600 bg-panel-800 px-2 py-1 text-xs text-ink-200 focus:outline-none focus-visible:ring-2 focus-visible:ring-state-info/60"
          >
            {status.engines.map((e) => (
              <option key={e.name} value={e.name}>
                {SHORT[e.name] ?? e.name}
                {e.availability !== 'always available' && e.availability !== 'installed' && !e.availability.includes('saved')
                  ? ` (${e.availability})`
                  : ''}
              </option>
            ))}
          </select>
        )}
        {status && link === 'online' && (
          <button
            title="API keys: add a key from any provider, switch between keys, choose the model"
            disabled={busy}
            onClick={() => { setKeysOpen((o) => !o); setMsg('') }}
            className={classNames(
              'rounded-md p-1.5 hover:bg-panel-800 disabled:opacity-40',
              keysOpen ? 'text-state-warn' : 'text-ink-400 hover:text-ink-200',
            )}
          >
            <KeyRound size={15} />
          </button>
        )}
        <button
          title="New conversation (the cell is not affected)"
          disabled={busy || link !== 'online'}
          onClick={() => void assistant.newChat()}
          className="rounded-md p-1.5 text-ink-400 hover:bg-panel-800 hover:text-ink-200 disabled:opacity-40"
        >
          <RotateCcw size={15} />
        </button>
        {onClose && (
          <button onClick={onClose} className="rounded-md p-1.5 text-ink-400 hover:bg-panel-800 hover:text-ink-200" title="Close">
            <X size={16} />
          </button>
        )}
      </div>
      {status?.model && !compact && (
        <p className="mt-1 flex items-center gap-1 pl-9 font-mono text-xs text-ink-500">
          <Cpu size={10} />
          {status.engine === 'api'
            ? `${status.api.providers.find((p) => p.name === status.api.provider)?.label ?? ''} · ${status.model}`
            : status.model}
        </p>
      )}
      {status && link === 'online' && status.accounts?.[status.engine] && (
        <AccountLine account={status.accounts[status.engine]} busy={busy} />
      )}
      {keysOpen && status && <ApiKeys status={status} onClose={() => setKeysOpen(false)} />}
      {msg && <p className="mt-1 text-xs text-state-warn">{msg}</p>}
    </div>
  )
}

/**
 * Who the subscription brain is signed in as, with Sign in / Sign out. The buttons send the chat commands
 * "login claude" / "logout claude": LEPS runs the vendor's own sign-in (its page opens in the browser) and
 * asks in the chat before signing out, since that signs out every Claude Code / Codex session of this Windows user.
 */
function AccountLine({ account, busy }: { account: AssistantAccount; busy: boolean }) {
  const name = account.service
  const send = (text: string) => void assistant.send(text).catch(() => undefined)
  if (!account.installed) {
    return <p className="mt-1 pl-9 text-xs text-state-warn">{account.label} is not installed on this PC.</p>
  }
  return (
    <div className="mt-1 flex items-center gap-2 pl-9 text-xs">
      <User size={11} className={account.loggedIn ? 'text-state-run' : 'text-state-warn'} />
      <span className="min-w-0 flex-1 truncate text-ink-400">
        {account.loggedIn
          ? <>Signed in as <span className="text-ink-200">{account.account || 'an account'}</span>{account.detail ? ` · ${account.detail}` : ''}</>
          : <span className="text-state-warn">Not signed in</span>}
      </span>
      {account.loggedIn ? (
        <button disabled={busy} onClick={() => send(`logout ${name}`)}
          className="rounded px-1.5 py-0.5 text-ink-400 hover:bg-panel-800 hover:text-state-fault disabled:opacity-40">
          Sign out
        </button>
      ) : null}
      <button disabled={busy} onClick={() => send(`login ${name}`)}
        className="rounded border border-panel-600 px-1.5 py-0.5 text-state-info hover:border-state-info/60 disabled:opacity-40">
        {account.loggedIn ? 'Switch account' : 'Sign in'}
      </button>
    </div>
  )
}

/**
 * One place for every API key: add a key from any provider (told from the key, or chosen), see the stored
 * keys, switch between them, remove one, and choose the model from the provider's own list. Keys are checked
 * against the provider and stored by LEPS for this Windows user only; the page only ever sees the last
 * 4 characters back.
 */
function ApiKeys({ status, onClose }: { status: AssistantStatus; onClose: () => void }) {
  const providers = status.api.providers
  const saved = providers.filter((p) => p.saved)
  const [provider, setProvider] = useState('')          // '' = tell it from the key
  const [key, setKey] = useState('')
  const [url, setUrl] = useState(status.api.customUrl || 'http://localhost:11434/v1')
  const [models, setModels] = useState<string[]>([])
  const [model, setModel] = useState(status.engine === 'api' ? status.model : '')
  const [working, setWorking] = useState(false)
  const [note, setNote] = useState('')
  const current = status.api.provider
  const chosen = providers.find((p) => p.name === provider)

  useEffect(() => {                                       // the current provider's models, for the model list
    if (!current) return
    assistant.models().then((r) => setModels(r.models)).catch(() => setModels([]))
  }, [current])

  async function run(what: string, fn: () => Promise<unknown>) {
    setWorking(true)
    setNote(what)
    try {
      await fn()
    } catch (e) {
      setNote(String((e as Error).message))
      setWorking(false)
      return false
    }
    setWorking(false)
    void refreshAssistantStatus()
    return true
  }

  const add = () => run('Checking the key with the provider…', async () => {
    const r = await assistant.addKey(key, provider, provider === 'custom' ? url : '')
    setKey('')
    setModels(r.models)
    setModel(r.engine === 'api' ? r.model : '')
    setNote(r.message)
  })
  const use = (name: string) => run('', async () => {
    const st = await assistant.useProvider(name)
    setModel(st.engine === 'api' ? st.model : '')
    setNote(st.engine === 'api' ? '' : 'Choose a model for this key.')
  })
  const remove = (name: string) => run('', () => assistant.removeKey(name))
  const setTheModel = () => run('', async () => {
    const st = await assistant.setModel(model.trim())
    setNote(st.engine === 'api' ? `Model ${st.model}.` : 'That model did not work: see the chat.')
  })

  const field = 'min-w-0 rounded-md border border-panel-600 bg-panel-900 px-2 py-1 text-xs text-ink-100 focus:outline-none focus-visible:ring-2 focus-visible:ring-state-info/60'
  return (
    <div className="mt-2 space-y-2 rounded-lg border border-state-warn/40 bg-state-warn/8 p-2">
      <div className="flex items-center gap-1.5 text-xs text-state-warn">
        <KeyRound size={13} />
        <span className="flex-1">API keys, any provider (stored for this Windows user only, never in the project)</span>
        <button onClick={onClose} title="Close" className="rounded p-0.5 text-ink-400 hover:text-ink-200"><X size={13} /></button>
      </div>

      {saved.length > 0 && (
        <ul className="space-y-1">
          {saved.map((p) => {
            const inUse = status.engine === 'api' && p.name === current
            return (
              <li key={p.name} className="flex items-center gap-1.5 rounded-md bg-panel-900/60 px-2 py-1 text-xs">
                <span className={classNames('flex-1 truncate', inUse ? 'text-state-run' : 'text-ink-200')}>
                  {p.label}
                  <span className="ml-1.5 font-mono text-xs text-ink-500">
                    {p.hint ? `…${p.hint}` : 'no key'} · {p.model || 'no model yet'}
                  </span>
                </span>
                {inUse
                  ? <Badge tone="run" className="!py-0 !text-xs">in use</Badge>
                  : <Button size="sm" disabled={working} onClick={() => void use(p.name)}>Use</Button>}
                <button
                  title={`Remove the ${p.label} key`}
                  disabled={working}
                  onClick={() => void remove(p.name)}
                  className="rounded p-1 text-ink-500 hover:text-state-fault disabled:opacity-40"
                >
                  <Trash2 size={12} />
                </button>
              </li>
            )
          })}
        </ul>
      )}

      <div className="flex flex-wrap gap-1.5">
        <select value={provider} onChange={(e) => setProvider(e.target.value)} className={classNames(field, 'max-w-[45%]')}>
          <option value="">Provider: tell from the key</option>
          {providers.map((p) => <option key={p.name} value={p.name}>{p.label}</option>)}
        </select>
        <input
          type="password"
          value={key}
          onChange={(e) => setKey(e.target.value)}
          onKeyDown={(e) => { if (e.key === 'Enter' && (key.trim() || provider === 'custom')) void add() }}
          placeholder={provider === 'custom' ? 'key (empty if the server needs none)' : 'paste the API key'}
          className={classNames(field, 'flex-1 font-mono')}
        />
        <Button size="sm" variant="primary" disabled={working || (!key.trim() && provider !== 'custom')} onClick={() => void add()}>
          {working ? <Loader2 size={12} className="animate-spin" /> : 'Add'}
        </Button>
      </div>
      {provider === 'custom' && (
        <input
          value={url}
          onChange={(e) => setUrl(e.target.value)}
          placeholder="base URL, e.g. http://localhost:11434/v1"
          className={classNames(field, 'w-full font-mono')}
        />
      )}
      {chosen?.page && (
        <a href={chosen.page} target="_blank" rel="noreferrer" className="inline-flex items-center gap-1 text-xs text-state-info hover:underline">
          Get a {chosen.label} key <ExternalLink size={10} />
        </a>
      )}

      {current && saved.some((p) => p.name === current) && (
        <div className="flex gap-1.5">
          <input
            list="leps-models"
            value={model}
            onChange={(e) => setModel(e.target.value)}
            placeholder={models.length ? `model (${models.length} available)` : 'model name'}
            className={classNames(field, 'flex-1 font-mono')}
          />
          <datalist id="leps-models">
            {models.map((m) => <option key={m} value={m} />)}
          </datalist>
          <Button size="sm" disabled={working || !model.trim()} onClick={() => void setTheModel()}>Set model</Button>
        </div>
      )}
      {note && <p className="text-xs text-ink-300">{note}</p>}
    </div>
  )
}

const SHORT: Record<string, string> = {
  api: 'API key',
  chatgpt: 'ChatGPT plan (Codex)',
  claude: 'Claude plan (Claude Code)',
  none: 'No AI (commands)',
}

function Offline() {
  const link = useAssistant((s) => s.link)
  return (
    <div className="grid flex-1 place-items-center p-6 text-center">
      <div className="max-w-sm">
        <WifiOff size={26} className="mx-auto mb-3 text-ink-500" />
        {link === 'unreachable' ? (
          <>
            <p className="text-sm text-ink-200">LEPS works only on the lab PC.</p>
            <p className="mt-1 text-xs text-ink-500">
              It can confirm writes to the cell, so it is not reachable over the network. Open the dashboard on
              the lab PC at http://127.0.0.1:5050.
            </p>
          </>
        ) : link === 'connecting' ? (
          <p className="text-sm text-ink-300">Connecting to LEPS…</p>
        ) : (
          <>
            <p className="text-sm text-ink-200">LEPS is not running.</p>
            <p className="mt-1 text-xs text-ink-500">
              It starts with the dashboard (“open dashboard”). To start it alone, run{' '}
              <code className="rounded bg-panel-800 px-1 font-mono text-ink-300">cellctl start assistant</code> in the
              project folder. This page reconnects by itself.
            </p>
          </>
        )}
      </div>
    </div>
  )
}

function Welcome() {
  return (
    <div className="rounded-lg border border-dashed border-panel-600 p-4 text-sm text-ink-400">
      <p className="mb-2 text-ink-200">Ask anything about the cell, or give a command.</p>
      <ul className="list-disc space-y-0.5 pl-5 text-xs">
        <li><b className="text-ink-300">start 1x50</b>: asks whether compartment 1 has the block, then starts</li>
        <li><b className="text-ink-300">eng done</b>: after engraving, finishes the cycle</li>
        <li><b className="text-ink-300">status</b>, <b className="text-ink-300">fault</b>, <b className="text-ink-300">watch</b>, <b className="text-ink-300">stop</b>, <b className="text-ink-300">help</b></li>
        <li>With an AI brain: “why did the last cycle stall?”, “show me the logger’s last lines”</li>
      </ul>
    </div>
  )
}

// ---------------------------------------------------------------------------

function EventView({
  e, pendingId, answer, onAnswer,
}: {
  e: AssistantEvent
  pendingId?: number
  answer?: AssistantEvent
  onAnswer: (id: number, v: boolean | string) => void
}) {
  switch (e.kind) {
    case 'user':
      return (
        <div className="flex justify-end gap-2">
          <div className="max-w-[85%] rounded-xl rounded-tr-sm bg-state-info/15 px-3 py-2 text-sm text-ink-100">
            <p className="whitespace-pre-wrap break-words">{e.text}</p>
            <p className="mt-0.5 text-right font-mono text-xs text-ink-500">{clock(e.at)}</p>
          </div>
          <User size={15} className="mt-1.5 shrink-0 text-ink-500" />
        </div>
      )
    case 'ai':
      return (
        <div className="flex gap-2">
          <Bot size={15} className="mt-1.5 shrink-0 text-state-info" />
          <div className="max-w-[90%] rounded-xl rounded-tl-sm border border-panel-700 bg-panel-800 px-3 py-2 text-sm leading-relaxed text-ink-200">
            <Markdown text={e.text} />
          </div>
        </div>
      )
    case 'tool':
      return (
        <p className="truncate pl-6 font-mono text-xs text-ink-500" title={e.text}>
          <Terminal size={10} className="mr-1 inline" />
          {e.text}
        </p>
      )
    case 'cmd':
      return (
        <pre className="ml-6 max-h-80 overflow-auto whitespace-pre-wrap break-words rounded-lg border border-panel-700 bg-panel-900 px-3 py-2 font-mono text-[11.5px] leading-relaxed text-ink-300">
          {e.text}
        </pre>
      )
    case 'info':
      return <p className="whitespace-pre-wrap pl-6 text-xs text-ink-500">{e.text}</p>
    case 'error':
      return (
        <p className="ml-6 flex gap-1.5 whitespace-pre-wrap rounded-lg border border-state-fault/40 bg-state-fault/8 px-3 py-2 text-xs text-state-fault">
          <AlertTriangle size={13} className="mt-0.5 shrink-0" />
          {e.text}
        </p>
      )
    case 'ask':
    case 'prompt':
      return <Question e={e} live={pendingId === e.id} answer={answer} onAnswer={onAnswer} />
    default:
      return null
  }
}

function Question({
  e, live, answer, onAnswer,
}: {
  e: AssistantEvent
  live: boolean
  answer?: AssistantEvent
  onAnswer: (id: number, v: boolean | string) => void
}) {
  const said = answer?.text
  const yes = said === 'True'
  return (
    <div
      className={classNames(
        'ml-6 rounded-lg border px-3 py-2.5',
        live ? 'border-state-warn/60 bg-state-warn/10 shadow-[0_0_0_1px_rgba(245,158,11,0.25)]' : 'border-panel-700 bg-panel-850',
      )}
    >
      <p className={classNames('text-sm', live ? 'font-semibold text-state-warn' : 'text-ink-300')}>{e.text}</p>
      {live && e.kind === 'ask' && (
        <div className="mt-2 flex gap-2">
          <Button variant="success" size="sm" onClick={() => onAnswer(e.id, true)}>
            <Check size={14} /> Yes
          </Button>
          <Button size="sm" onClick={() => onAnswer(e.id, false)}>
            <X size={14} /> No
          </Button>
          <span className="self-center text-xs text-ink-500">No answer in 3 min counts as No</span>
        </div>
      )}
      {live && e.kind === 'prompt' && (
        <p className="mt-1 text-xs text-ink-500">Type the answer in the box below and press Send.</p>
      )}
      {!live && answer && (
        <p className="mt-1 text-xs text-ink-500">
          {e.kind === 'ask'
            ? answer.timedOut ? 'No answer: taken as No.' : yes ? 'You said yes.' : 'You said no.'
            : `You answered: ${said || '(nothing)'}`}
        </p>
      )}
    </div>
  )
}

/** Bold, inline code, bullets and paragraphs; everything else is text (React escapes it). */
function Markdown({ text }: { text: string }) {
  const lines = text.split('\n')
  return (
    <div className="space-y-1">
      {lines.map((line, i) => {
        const bullet = /^\s*[-*•]\s+/.test(line)
        const body = bullet ? line.replace(/^\s*[-*•]\s+/, '') : line
        if (!body.trim()) return <div key={i} className="h-1" />
        return (
          <p key={i} className={bullet ? 'flex gap-1.5 pl-1' : undefined}>
            {bullet && <span className="text-ink-500">•</span>}
            <span className="break-words">{inline(body)}</span>
          </p>
        )
      })}
    </div>
  )
}

const LINK = /^\[([^\]]+)\]\((https?:\/\/[^\s)]+)\)$/     // [text](https://...), web links only

function inline(s: string) {
  const parts = s.split(/(\*\*[^*]+\*\*|`[^`]+`|\[[^\]]+\]\(https?:\/\/[^\s)]+\))/g)
  return parts.map((p, i) =>
    LINK.test(p) ? (
      <a key={i} href={p.replace(LINK, '$2')} target="_blank" rel="noreferrer" className="text-state-info underline">
        {p.replace(LINK, '$1')}
      </a>
    ) : p.startsWith('**') && p.endsWith('**') ? (
      <b key={i} className="text-ink-100">{p.slice(2, -2)}</b>
    ) : p.startsWith('`') && p.endsWith('`') ? (
      <code key={i} className="rounded bg-panel-900 px-1 font-mono text-xs text-ink-100">{p.slice(1, -1)}</code>
    ) : (
      <span key={i}>{p}</span>
    ),
  )
}
