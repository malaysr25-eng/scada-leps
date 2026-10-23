/**
 * Application shell.
 *
 * One SSE connection is opened here and only here (`useRealtime`). Every page
 * reads from the store, so there is exactly one realtime channel for the whole
 * application no matter how many panels are mounted.
 *
 * HashRouter rather than BrowserRouter: the HMI is served from a plain Flask
 * static handler and is routinely opened from a file path or a bookmark on a
 * lab PC. Hash routing means a deep link and a page refresh both work without
 * any server-side rewrite rules to get wrong.
 */

import { lazy, Suspense, useState } from 'react'
import { HashRouter, Route, Routes, useLocation } from 'react-router-dom'
import { Bot } from 'lucide-react'
import { AssistantChat } from './components/assistant/AssistantChat'
import { Toasts } from './components/common/Toasts'
import { ModeBanner } from './components/layout/ModeBanner'
import { NavRail } from './components/layout/NavRail'
import { TopBar } from './components/layout/TopBar'
import { useRealtime } from './hooks/useRealtime'
import { AssistantPage } from './pages/Assistant'
import { DataPage } from './pages/Data'
import { DiagnosticsPage } from './pages/Diagnostics'
import { DigitalTwinPage } from './pages/DigitalTwin'
import { FactoryTwinPage } from './pages/FactoryTwin'
import { HistoryPage } from './pages/History'
import { ManualControlPage } from './pages/ManualControl'
import { OverviewPage } from './pages/Overview'
import { SequencePage } from './pages/Sequence'
import { TagsPage } from './pages/Tags'

/**
 * The 3-D view pulls in three.js and @react-three/*, roughly 900 kB. It is
 * the only route that needs them, so it is code-split: the Overview page an
 * operator stares at all shift does not pay for a view it never renders.
 */
const Machine3DPage = lazy(() =>
  import('./pages/Machine3D').then((m) => ({ default: m.Machine3DPage })),
)
import { useAssistantFeed } from './stores/assistantStore'
import { useMachine } from './stores/machineStore'

export function App() {
  useRealtime()
  useAssistantFeed()

  return (
    <HashRouter>
      <div className="flex h-full flex-col bg-panel-950">
        <TopBar />
        {/* Mode is stated in full width, above everything: knowing whether you
            are looking at plant data or a simulation is the one thing that
            must never require a second glance. */}
        <ModeBanner />
        <div className="flex min-h-0 flex-1">
          <NavRail />
          <main className="min-w-0 flex-1 overflow-y-auto p-4">
            <BootGate>
              <Routes>
                <Route path="/" element={<OverviewPage />} />
                <Route path="/assistant" element={<AssistantPage />} />
                <Route path="/factory" element={<FactoryTwinPage />} />
                <Route
                  path="/machine3d"
                  element={
                    <Suspense fallback={<SceneLoading />}>
                      <Machine3DPage />
                    </Suspense>
                  }
                />
                <Route path="/sequence" element={<SequencePage />} />
                <Route path="/manual" element={<ManualControlPage />} />
                <Route path="/diagnostics" element={<DiagnosticsPage />} />
                <Route path="/twin" element={<DigitalTwinPage />} />
                <Route path="/data" element={<DataPage />} />
                <Route path="/history" element={<HistoryPage />} />
                <Route path="/tags" element={<TagsPage />} />
                <Route path="*" element={<OverviewPage />} />
              </Routes>
            </BootGate>
          </main>
          <AssistantDock />
        </div>

        <Toasts />
      </div>
    </HashRouter>
  )
}

/**
 * The Help button on every page opens the same Assistant conversation as a
 * docked panel, so a question can be asked without leaving the screen it is
 * about. Hidden on the Assistant page itself, where the chat is the page.
 */
function AssistantDock() {
  const [open, setOpen] = useState(false)
  const { pathname } = useLocation()
  if (pathname === '/assistant') return null
  if (open) {
    return (
      <aside className="flex w-[400px] shrink-0 flex-col border-l border-panel-700 bg-panel-850">
        <AssistantChat compact onClose={() => setOpen(false)} />
      </aside>
    )
  }
  return (
    <button
      onClick={() => setOpen(true)}
      className="fixed bottom-5 right-5 z-40 flex items-center gap-2 rounded-full border border-state-info/50 bg-panel-850 px-4 py-3 text-sm font-semibold text-state-info shadow-panel transition-colors hover:bg-state-info/15"
      title="Open LEPS"
    >
      <Bot size={18} />
      LEPS
    </button>
  )
}

/**
 * Holds the first paint until a snapshot arrives.
 *
 * Only until the FIRST one: after that the UI keeps rendering the last known
 * good state even when the link drops, marked stale. Blanking the screen on
 * disconnect would destroy exactly the evidence an operator needs, which is
 * the behaviour the Errors sheet complains about on 2026-08-19.
 */
function BootGate({ children }: { children: React.ReactNode }) {
  const snapshot = useMachine((s) => s.snapshot)
  const link = useMachine((s) => s.link)

  if (snapshot) return <>{children}</>

  return (
    <div className="grid h-full place-items-center">
      <div className="text-center">
        <div className="mx-auto mb-4 h-8 w-8 animate-spin rounded-full border-2 border-panel-600 border-t-state-info" />
        <p className="text-sm text-ink-300">
          {link === 'reconnecting' || link === 'closed'
            ? 'Backend unreachable — retrying'
            : 'Connecting to the control backend…'}
        </p>
        <p className="mt-1 font-mono text-xs text-ink-600">
          {link === 'reconnecting' || link === 'closed'
            ? 'Is run.py running?'
            : 'Waiting for the first PLC snapshot'}
        </p>
      </div>
    </div>
  )
}

/** Shown while the 3-D chunk downloads. */
function SceneLoading() {
  return (
    <div className="grid h-full place-items-center">
      <div className="text-center">
        <div className="mx-auto mb-4 h-8 w-8 animate-spin rounded-full border-2 border-panel-600 border-t-state-info" />
        <p className="text-sm text-ink-300">Loading the 3-D machine model…</p>
        <p className="mt-1 font-mono text-xs text-ink-600">
          three.js is loaded only for this view
        </p>
      </div>
    </div>
  )
}
