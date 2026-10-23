/**
 * Fault and debug centre.
 *
 * The place to answer "why did it do that?" -- findings, latched faults, the
 * event timeline, the watch list and the attributed change history, all on one
 * screen.
 */

import {
  ChangeHistoryPanel, CommandHistoryPanel, EventLogPanel, FaultTimeline,
  FindingsPanel, WatchListPanel,
} from '../components/diagnostics/DiagnosticsPanels'

export function DiagnosticsPage() {
  return (
    <div className="space-y-4">
      <div className="grid gap-4 xl:grid-cols-2">
        <FindingsPanel />
        <FaultTimeline />
      </div>

      <WatchListPanel />

      <div className="grid gap-4 xl:grid-cols-2">
        <EventLogPanel />
        <ChangeHistoryPanel />
      </div>

      <CommandHistoryPanel />
    </div>
  )
}
