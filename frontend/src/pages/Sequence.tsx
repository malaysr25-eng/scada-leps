/**
 * Full sequence view: the whole 40-step timeline, with the plan view above it.
 *
 * The two are linked. Clicking a step highlights the thing on the plan that the
 * step actually acts on -- the barrel, the belt, the sensor -- which is the
 * question an operator is asking when a cycle hangs: *where* is it stuck, not
 * just which row number. When nothing is selected the plan follows the live
 * step, so it tracks the machine on its own.
 */

import { useMemo, useState } from 'react'
import { CellPlan } from '../components/cell/CellPlan'
import { focusLabel, STEP_FOCUS } from '../components/cell/sequenceSources'
import { Badge, Panel } from '../components/common/Primitives'
import { RestartChecklist } from '../components/machine/RestartChecklist'
import { SequenceTimeline } from '../components/machine/SequenceTimeline'
import { SensorEventStream } from '../components/sensors/SensorPanel'
import { useSequenceCatalogue } from '../hooks/useSequenceCatalogue'
import { selectSequence, useMachine } from '../stores/machineStore'

export function SequencePage() {
  const catalogue = useSequenceCatalogue()
  const sequence = useMachine(selectSequence)
  const [pinnedKey, setPinnedKey] = useState<string | null>(null)

  // No pin: the plan follows the machine. Pinned: it follows the operator.
  const shownKey = pinnedKey ?? sequence?.step?.key ?? null
  const focus = shownKey ? STEP_FOCUS[shownKey] : undefined
  const shownStep = useMemo(
    () => catalogue.find((s) => s.key === shownKey) ?? null,
    [catalogue, shownKey],
  )

  return (
    <div className="space-y-4">
      <div className="grid gap-4 2xl:grid-cols-2">
      <Panel
        title="Cell plan"
        subtitle={
          shownStep
            ? `Step ${String(shownStep.index).padStart(2, '0')} · ${shownStep.name}`
            : 'Waiting for a step to be inferred'
        }
        actions={
          pinnedKey ? (
            <button
              type="button"
              onClick={() => setPinnedKey(null)}
              className="rounded-md border border-state-twin/50 bg-state-twin/12 px-2 py-0.5 text-xs font-semibold uppercase tracking-wider text-state-twin"
            >
              Pinned to {focusLabel(focus) ?? 'step'} &mdash; follow the machine
            </button>
          ) : (
            <Badge tone="info">Following the live step</Badge>
          )
        }
      >
        <CellPlan focus={focus} compact />
      </Panel>

        <SequenceTimeline
          catalogue={catalogue}
          selectedKey={pinnedKey}
          onSelectStep={(step) =>
            setPinnedKey((k) => (k === step.key ? null : step.key))
          }
        />
      </div>

      <div className="grid gap-4 xl:grid-cols-2">
        <RestartChecklist />
        <Panel title="Sensor confirmations">
          <SensorEventStream limit={20} />
        </Panel>
      </div>
    </div>
  )
}
