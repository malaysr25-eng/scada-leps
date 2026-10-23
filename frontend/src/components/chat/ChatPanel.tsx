/**
 * Help assistant — a dockable chat panel.
 *
 * The one thing this UI must communicate clearly is what the assistant *is*:
 * a read-only helper. So the header carries a permanent "read-only · cannot
 * operate the machine" badge, and every assistant reply shows the context it
 * was grounded in (mode, lifecycle, data quality, fault count) so an operator
 * can judge whether the answer is current rather than trusting it blind.
 *
 * Answers are rendered as light markdown — bold, bullets, inline code. A full
 * markdown library would be a dependency for four constructs, so the renderer
 * below handles exactly those and escapes everything else.
 */

import { useEffect, useRef, useState } from 'react'
import {
  Bot, Eraser, Loader2, Send, Shield, User, X,
} from 'lucide-react'
import { api } from '../../services/api'
import type { ChatMessage, ChatStatus } from '../../types'
import { classNames, clock } from '../../utils/format'
import { Badge } from '../common/Primitives'

const SUGGESTIONS = [
  'What mode is the system in?',
  "Why can't I start a cycle?",
  'What alarms are active?',
  'How do I start recording?',
  'Why is the sequence stuck?',
  'What data source is active?',
]

export function ChatPanel({ onClose }: { onClose: () => void }) {
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [input, setInput] = useState('')
  const [busy, setBusy] = useState(false)
  const [status, setStatus] = useState<ChatStatus | null>(null)
  const endRef = useRef<HTMLDivElement>(null)
  const inputRef = useRef<HTMLTextAreaElement>(null)

  useEffect(() => {
    void api.chatStatus().then((r) => r.ok && setStatus(r.data))
    void api.chatHistory().then((r) => r.ok && setMessages(r.data))
    inputRef.current?.focus()
  }, [])

  useEffect(() => {
    endRef.current?.scrollIntoView({ behavior: 'smooth' })
  }, [messages, busy])

  async function send(text?: string) {
    const message = (text ?? input).trim()
    if (!message || busy) return

    setInput('')
    setBusy(true)

    // Optimistic echo: the operator should see their question immediately.
    const pending: ChatMessage = {
      id: -Date.now(),
      role: 'user',
      text: message,
      at: Date.now() / 1000,
      provider: '',
      grounded: true,
      error: '',
      contextSummary: {},
    }
    setMessages((m) => [...m, pending])

    const res = await api.chat(message)
    setBusy(false)

    if (res.ok) {
      setMessages((m) => [...m, res.data])
    } else {
      setMessages((m) => [
        ...m,
        {
          id: -Date.now() - 1,
          role: 'assistant',
          text: `I couldn't answer that: ${res.error.message}`,
          at: Date.now() / 1000,
          provider: 'error',
          grounded: false,
          error: res.error.message,
          contextSummary: {},
        },
      ])
    }
  }

  async function clear() {
    await api.chatClear()
    setMessages([])
  }

  return (
    <aside className="flex h-full w-[400px] shrink-0 flex-col border-l border-panel-700 bg-panel-900">
      {/* header */}
      <header className="flex items-center gap-2 border-b border-panel-700 px-3 py-2.5">
        <Bot size={17} className="text-state-info" />
        <div className="min-w-0 flex-1">
          <div className="text-sm font-semibold text-ink-100">Help assistant</div>
          <div className="truncate text-xs text-ink-500">
            {status?.provider ?? '…'}
            {status && !status.providerAvailable && ' · falling back to builtin'}
          </div>
        </div>
        <button
          onClick={clear}
          className="rounded p-1.5 text-ink-500 hover:bg-panel-700 hover:text-ink-200"
          title="Clear conversation"
        >
          <Eraser size={14} />
        </button>
        <button
          onClick={onClose}
          className="rounded p-1.5 text-ink-400 hover:bg-panel-700 hover:text-ink-100"
          title="Close"
        >
          <X size={16} />
        </button>
      </header>

      {/* the permanent capability statement */}
      <div className="flex items-start gap-2 border-b border-panel-800 bg-panel-850 px-3 py-2">
        <Shield size={13} className="mt-0.5 shrink-0 text-state-run" />
        <p className="text-xs leading-relaxed text-ink-400">
          <strong className="text-ink-300">Read-only.</strong> The assistant
          cannot operate the machine.
        </p>
      </div>

      {/* messages */}
      <div className="min-h-0 flex-1 space-y-3 overflow-y-auto p-3">
        {messages.length === 0 && (
          <div className="space-y-3">
            <div className="space-y-1.5">
              {SUGGESTIONS.map((s) => (
                <button
                  key={s}
                  onClick={() => send(s)}
                  className="w-full rounded-lg border border-panel-700 bg-panel-850 px-3 py-2 text-left text-xs text-ink-300 transition-colors hover:border-state-info/50 hover:text-ink-100"
                >
                  {s}
                </button>
              ))}
            </div>
          </div>
        )}

        {messages.map((m) => (
          <Message key={m.id} message={m} />
        ))}

        {busy && (
          <div className="flex items-center gap-2 text-xs text-ink-500">
            <Loader2 size={13} className="animate-spin" />
            Thinking…
          </div>
        )}
        <div ref={endRef} />
      </div>

      {/* composer */}
      <div className="border-t border-panel-700 p-3">
        <div className="flex items-end gap-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === 'Enter' && !e.shiftKey) {
                e.preventDefault()
                void send()
              }
            }}
            rows={2}
            placeholder="Ask about the system…"
            className="min-w-0 flex-1 resize-none rounded-lg border border-panel-600 bg-panel-950 px-3 py-2 text-sm text-ink-100 placeholder:text-ink-600 focus:outline-none focus:ring-1 focus:ring-state-info/50"
          />
          <button
            onClick={() => send()}
            disabled={busy || !input.trim()}
            className="rounded-lg border border-state-info/50 bg-state-info/15 p-2.5 text-state-info transition-colors hover:bg-state-info/25 disabled:opacity-40"
            title="Send  (Enter)"
          >
            <Send size={16} />
          </button>
        </div>
      </div>
    </aside>
  )
}

// ---------------------------------------------------------------------------

function Message({ message }: { message: ChatMessage }) {
  const isUser = message.role === 'user'
  const ctx = message.contextSummary

  return (
    <div className={classNames('flex gap-2', isUser && 'flex-row-reverse')}>
      <div
        className={classNames(
          'mt-0.5 grid h-6 w-6 shrink-0 place-items-center rounded-full',
          isUser ? 'bg-panel-700' : 'bg-state-info/20',
        )}
      >
        {isUser ? (
          <User size={12} className="text-ink-300" />
        ) : (
          <Bot size={12} className="text-state-info" />
        )}
      </div>

      <div className={classNames('min-w-0 max-w-[85%]', isUser && 'text-right')}>
        <div
          className={classNames(
            'inline-block rounded-lg px-3 py-2 text-left text-xs leading-relaxed',
            isUser
              ? 'bg-panel-700 text-ink-100'
              : message.error
                ? 'border border-state-warn/40 bg-state-warn/8 text-ink-200'
                : 'border border-panel-700 bg-panel-850 text-ink-200',
          )}
        >
          <Markdown text={message.text} />
        </div>

        <div
          className={classNames(
            'mt-1 flex flex-wrap items-center gap-1.5 text-xs text-ink-600',
            isUser && 'justify-end',
          )}
        >
          <span>{clock(message.at)}</span>
          {!isUser && ctx.systemMode && (
            <>
              <span className="text-ink-700">·</span>
              <span title="System state the answer was grounded in">
                {ctx.systemMode} / {ctx.lifecycle}
              </span>
              {ctx.stale && (
                <Badge tone="warn" className="!py-0 !text-xs">
                  stale data
                </Badge>
              )}
              {(ctx.activeFaults ?? 0) > 0 && (
                <Badge tone="fault" className="!py-0 !text-xs">
                  {ctx.activeFaults} fault{ctx.activeFaults === 1 ? '' : 's'}
                </Badge>
              )}
            </>
          )}
        </div>
      </div>
    </div>
  )
}

/**
 * Minimal markdown: **bold**, `code`, bullet lines, blank-line paragraphs.
 *
 * A full parser would be a dependency for four constructs. React escapes the
 * text nodes, so nothing here can inject markup.
 */
function Markdown({ text }: { text: string }) {
  const lines = text.split('\n')
  return (
    <>
      {lines.map((line, i) => {
        if (!line.trim()) return <div key={i} className="h-2" />
        const bullet = /^\s*[-*]\s+/.test(line)
        const content = bullet ? line.replace(/^\s*[-*]\s+/, '') : line
        return (
          <div
            key={i}
            className={classNames(bullet && 'flex gap-1.5 pl-1')}
          >
            {bullet && <span className="text-ink-500">•</span>}
            <span>{inline(content)}</span>
          </div>
        )
      })}
    </>
  )
}

function inline(text: string): React.ReactNode[] {
  const parts: React.ReactNode[] = []
  const pattern = /(\*\*[^*]+\*\*|`[^`]+`)/g
  let last = 0
  let match: RegExpExecArray | null
  let key = 0

  while ((match = pattern.exec(text)) !== null) {
    if (match.index > last) parts.push(text.slice(last, match.index))
    const token = match[0]
    if (token.startsWith('**')) {
      parts.push(
        <strong key={key++} className="font-semibold text-ink-100">
          {token.slice(2, -2)}
        </strong>,
      )
    } else {
      parts.push(
        <code
          key={key++}
          className="rounded bg-panel-950 px-1 py-px font-mono text-xs text-state-info"
        >
          {token.slice(1, -1)}
        </code>,
      )
    }
    last = match.index + token.length
  }
  if (last < text.length) parts.push(text.slice(last))
  return parts
}

