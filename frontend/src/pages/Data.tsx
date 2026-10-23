/**
 * Data capture page.
 *
 * Manual persistence controls beside the data-source detail, because the two
 * questions belong together: what you are recording depends on which source is
 * feeding the dashboards.
 */

import { RecordingControls } from '../components/data/RecordingControls'
import { SourcePanel } from '../components/data/SourcePanel'

export function DataPage() {
  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_420px]">
      <RecordingControls />
      <SourcePanel />
    </div>
  )
}
