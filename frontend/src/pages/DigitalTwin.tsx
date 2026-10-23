/**
 * Digital twin: real vs predicted, with full provenance.
 */

import { CameraPanel } from '../components/common/CameraPanel'
import {
  ProvenanceLegend, TwinComparisonPanel, TwinMismatchPanel,
  TwinReferenceDetail, TwinStatusPanel,
} from '../components/digitalTwin/TwinPanels'

export function DigitalTwinPage() {
  return (
    <div className="space-y-4">
      <TwinStatusPanel />

      <div className="grid gap-4 xl:grid-cols-[1fr_380px]">
        <div className="space-y-4">
          <TwinComparisonPanel />
          <TwinMismatchPanel />
        </div>
        <div className="space-y-4">
          <ProvenanceLegend />
          <CameraPanel />
        </div>
      </div>

      <TwinReferenceDetail />
    </div>
  )
}
