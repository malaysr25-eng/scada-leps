/**
 * Manual control workspace, plus the command history that proves what actually
 * reached the PLC.
 */

import { ManualWorkspace } from '../components/controls/ManualControl'
import { CommandHistoryPanel } from '../components/diagnostics/DiagnosticsPanels'

export function ManualControlPage() {
  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_420px]">
      <ManualWorkspace />
      <CommandHistoryPanel />
    </div>
  )
}
