/**
 * SSE client with explicit link state.
 *
 * THE REQUIREMENT THIS SERVES
 * ---------------------------
 * "Manually controlled website needed to be refreshed again and again"
 * (Errors sheet, 2026-08-14).
 *
 * `EventSource` reconnects on its own after a dropped connection, so the
 * browser recovers without anyone pressing F5. What it does *not* do is tell
 * the user anything, and a silently reconnecting stream looks identical to a
 * frozen one. This wrapper therefore reports its own state, and the UI marks
 * every value stale while the link is down rather than continuing to draw
 * numbers as if they were current.
 *
 * Values are deliberately NOT cleared on disconnect. The last known good state
 * is the most useful thing an operator can look at while the link is out --
 * blanking the screen destroys exactly the evidence they need.
 */

import type { Snapshot } from '../types'

export type LinkState = 'connecting' | 'open' | 'reconnecting' | 'closed'

export interface RealtimeHandlers {
  onSnapshot: (snapshot: Snapshot) => void
  onLinkState: (state: LinkState, detail?: string) => void
}

export class RealtimeClient {
  private source: EventSource | null = null
  private handlers: RealtimeHandlers
  private everOpened = false
  private stopped = false
  private pollTimer: number | null = null
  private url: string

  constructor(handlers: RealtimeHandlers, url = '/api/stream') {
    this.handlers = handlers
    this.url = url
  }

  start(): void {
    this.stopped = false
    this.open()
  }

  stop(): void {
    this.stopped = true
    this.clearPoll()
    this.source?.close()
    this.source = null
    this.handlers.onLinkState('closed')
  }

  private open(): void {
    if (this.stopped) return

    this.handlers.onLinkState(this.everOpened ? 'reconnecting' : 'connecting')

    try {
      this.source = new EventSource(this.url)
    } catch (err) {
      this.startFallbackPolling(String(err))
      return
    }

    this.source.addEventListener('open', () => {
      this.everOpened = true
      this.clearPoll()
      this.handlers.onLinkState('open')
    })

    this.source.addEventListener('state', (event) => {
      try {
        const snapshot = JSON.parse((event as MessageEvent).data) as Snapshot
        this.handlers.onSnapshot(snapshot)
      } catch (err) {
        // A malformed frame must not kill the stream; log and keep going.
        console.error('[realtime] bad frame', err)
      }
    })

    this.source.addEventListener('error', () => {
      // EventSource retries by itself unless it has been closed outright.
      if (this.source?.readyState === EventSource.CLOSED) {
        this.handlers.onLinkState('reconnecting', 'stream closed by the server')
        this.startFallbackPolling('stream closed')
        window.setTimeout(() => this.open(), 3000)
      } else {
        this.handlers.onLinkState('reconnecting', 'stream interrupted')
        this.startFallbackPolling('stream interrupted')
      }
    })
  }

  /**
   * While the stream is down, fall back to slow REST polling so the operator
   * still gets numbers, just less often. Explicitly slow (2 s): this is a
   * degraded mode, not a second update path competing with the stream.
   */
  private startFallbackPolling(_reason: string): void {
    if (this.pollTimer !== null || this.stopped) return

    this.pollTimer = window.setInterval(async () => {
      try {
        const res = await fetch('/api/state')
        if (!res.ok) return
        const snapshot = (await res.json()) as Snapshot
        this.handlers.onSnapshot(snapshot)
      } catch {
        /* backend still down; the UI already shows the link state */
      }
    }, 2000)
  }

  private clearPoll(): void {
    if (this.pollTimer !== null) {
      window.clearInterval(this.pollTimer)
      this.pollTimer = null
    }
  }
}
