/**
 * The Assistant conversation, shared by the Assistant page and the docked
 * Help panel: one long-poll loop (`useAssistantFeed`, mounted once in App),
 * so both show the same conversation and nothing is fetched twice.
 *
 * The conversation itself lives in LEPS's server, not here: a page reload
 * or a second tab picks it up again from the server's event list.
 */

import { useEffect } from 'react'
import { create } from 'zustand'
import {
  assistant, assistantReachable,
  type AssistantEvent, type AssistantPending, type AssistantStatus,
} from '../services/assistant'

export type AssistantLink = 'connecting' | 'online' | 'offline' | 'unreachable'

interface AssistantStore {
  link: AssistantLink
  status: AssistantStatus | null
  events: AssistantEvent[]
  lastId: number
  busy: boolean
  pending: AssistantPending | null
  setStatus: (s: AssistantStatus) => void
}

const MAX_EVENTS = 400

export const useAssistant = create<AssistantStore>((set) => ({
  link: assistantReachable() ? 'connecting' : 'unreachable',
  status: null,
  events: [],
  lastId: 0,
  busy: false,
  pending: null,
  setStatus: (status) => set({ status, busy: status.busy, pending: status.pending }),
}))

let running = false

async function loop() {
  if (running || !assistantReachable()) return
  running = true
  const set = useAssistant.setState
  let statusAt = 0
  for (;;) {
    try {
      if (Date.now() - statusAt > 10_000 || useAssistant.getState().link !== 'online') {
        const st = await assistant.status()
        useAssistant.getState().setStatus(st)
        statusAt = Date.now()
        if (st.lastEvent < useAssistant.getState().lastId) {
          set({ events: [], lastId: 0 })          // the server restarted: start over
        }
      }
      const after = useAssistant.getState().lastId
      const r = await assistant.events(after, 20)
      set((s) => {
        const events = r.gap && after > 0 ? r.events : [...s.events, ...r.events]
        return {
          link: 'online',
          events: events.slice(-MAX_EVENTS),
          lastId: r.events.length ? r.events[r.events.length - 1].id : s.lastId,
          busy: r.busy,
          pending: r.pending,
        }
      })
      if (r.events.some((e) => e.kind === 'info' && e.text.startsWith('Brain:'))) statusAt = 0
    } catch {
      set({ link: 'offline' })
      await new Promise((ok) => setTimeout(ok, 3000))
    }
  }
}

/** Mount once (App). Starts the shared long-poll loop. */
export function useAssistantFeed() {
  useEffect(() => {
    void loop()
  }, [])
}

/** Refresh the brain/model status now (after the user changed it). */
export async function refreshAssistantStatus() {
  try {
    useAssistant.getState().setStatus(await assistant.status())
  } catch {
    /* the loop reports offline */
  }
}
