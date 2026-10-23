/**
 * 3-D machine view.
 *
 * The 2-D schematic at /factory is unchanged and still the better tool for
 * sensor diagnostics. This view answers a different question: does the digital
 * twin actually look like the machine in front of me?
 *
 * The inspector on the right is the honest part. Clicking any component shows
 * what drives it, what its confidence is, and — for the cylinders — that
 * nothing drives it, because no supplied source maps actuator numbers to valve
 * numbers.
 */

import { useState } from 'react'
import {
  Box, Camera, Cable, Eye, EyeOff, Info, MousePointerClick,
} from 'lucide-react'
import { MachineScene, type Selection } from '../components/twin3d/MachineScene'
import { UNPLACED_SENSORS } from '../components/twin3d/machineLayout'
import { useMachine } from '../stores/machineStore'
import { classNames } from '../utils/format'
import { Badge, Button, Note, Panel } from '../components/common/Primitives'

const CONFIDENCE_META: Record<
  string,
  { tone: 'run' | 'info' | 'warn' | 'idle'; label: string; meaning: string }
> = {
  PHOTO: {
    tone: 'run', label: 'From photographs',
    meaning: 'Geometry read directly from the reference photographs.',
  },
  PROP: {
    tone: 'info', label: 'Proportioned',
    meaning: 'Scaled against the one measured dimension (76 cm conveyor length).',
  },
  APPROX: {
    tone: 'warn', label: 'Approximated',
    meaning: 'Present in the photographs, but its exact form is not legible. '
           + 'Simplified geometry.',
  },
  DOC: {
    tone: 'info', label: 'From the Sequencing sheet',
    meaning: 'Placed from the process documentation, not from a photograph.',
  },
}

export function Machine3DPage() {
  const [selection, setSelection] = useState<Selection | null>(null)
  const [showTubing, setShowTubing] = useState(true)
  const [showSurroundings, setShowSurroundings] = useState(true)
  const machine = useMachine((s) => s.snapshot?.machine)

  return (
    <div className="grid gap-4 xl:grid-cols-[1fr_360px]">
      <Panel
        title="Machine — 3D"
        subtitle="Modelled from the reference photographs; live state drives the parts"
        actions={
          <div className="flex items-center gap-2">
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowTubing((v) => !v)}
              title="Show or hide pneumatic tubing"
            >
              {showTubing ? <Eye size={12} /> : <EyeOff size={12} />}
              Tubing
            </Button>
            <Button
              variant="ghost"
              size="sm"
              onClick={() => setShowSurroundings((v) => !v)}
              title="Show or hide the cabinet, receiver and desk"
            >
              {showSurroundings ? <Eye size={12} /> : <EyeOff size={12} />}
              Surroundings
            </Button>
            <Badge tone="info">{machine?.lifecycle ?? '--'}</Badge>
          </div>
        }
      >
        <div className="h-[calc(100vh-320px)] min-h-[440px] overflow-hidden rounded-lg border border-panel-700">
          <MachineScene
            onSelect={setSelection}
            showTubing={showTubing}
            showSurroundings={showSurroundings}
          />
        </div>
        <p className="mt-2 flex items-center gap-1.5 text-[11px] text-ink-500">
          <MousePointerClick size={12} />
          Drag to orbit · scroll to zoom · right-drag to pan · click a component
          to inspect it
        </p>
      </Panel>

      <div className="space-y-4">
        <Panel
          title="Component inspector"
          actions={
            selection && (
              <button
                onClick={() => setSelection(null)}
                className="text-xs text-ink-500 hover:text-ink-200"
              >
                Clear
              </button>
            )
          }
        >
          {!selection ? (
            <div className="py-8 text-center">
              <Box size={24} className="mx-auto mb-2 text-ink-600" />
              <p className="text-xs text-ink-500">
                Click any part of the machine.
              </p>
            </div>
          ) : (
            <div className="space-y-3">
              <div>
                <h3 className="text-sm font-semibold text-ink-100">
                  {selection.label}
                </h3>
                <p className="text-[10px] uppercase tracking-wider text-ink-500">
                  {selection.kind}
                </p>
              </div>

              <ConfidenceRow confidence={selection.confidence} />

              {selection.value && (
                <Row label="Live value">
                  <span
                    className={classNames(
                      'font-mono text-xs',
                      selection.value.includes('MISMATCH')
                        ? 'text-state-fault'
                        : 'text-ink-200',
                    )}
                  >
                    {selection.value}
                  </span>
                </Row>
              )}

              {selection.binding && (
                <Row label="Bound to">
                  {selection.binding.startsWith('NONE') ? (
                    <span className="flex items-center gap-1.5 text-xs text-state-warn">
                      <Cable size={11} />
                      No live binding
                    </span>
                  ) : (
                    <code className="font-mono text-[10px] text-state-info">
                      {selection.binding}
                    </code>
                  )}
                </Row>
              )}

              {selection.note && (
                <div className="rounded-lg border border-panel-700 bg-panel-800 p-2.5">
                  <p className="text-[11px] leading-relaxed text-ink-400">
                    {selection.note}
                  </p>
                </div>
              )}
            </div>
          )}
        </Panel>

        <Panel title="Model fidelity">
          <ul className="space-y-2 text-xs">
            {Object.entries(CONFIDENCE_META).map(([code, meta]) => (
              <li key={code} className="flex gap-2">
                <Badge tone={meta.tone} className="!py-0 !text-[9px] shrink-0">
                  {code}
                </Badge>
                <span className="text-ink-400">{meta.meaning}</span>
              </li>
            ))}
          </ul>
          <Note tone="idle">
            The only measured dimension available is the 76 cm conveyor length
            from the lab data sheet. Everything else is proportioned against it,
            so the model is <strong>proportionally faithful and dimensionally
            approximate</strong>. One tape measurement of the table would
            upgrade that.
          </Note>
        </Panel>

        <Panel
          title="Not modelled"
          subtitle="Things no supplied source can place"
        >
          <ul className="space-y-2 text-[11px] leading-relaxed text-ink-400">
            <li className="flex gap-2">
              <Info size={12} className="mt-0.5 shrink-0 text-state-warn" />
              <span>
                <strong className="text-ink-300">Cylinder motion.</strong> No
                source maps actuator numbers to valve numbers, so no cylinder is
                animated from live state. Energising one valve at a time in
                Manual mode would establish the map in about half an hour.
              </span>
            </li>
            <li className="flex gap-2">
              <Info size={12} className="mt-0.5 shrink-0 text-state-warn" />
              <span>
                <strong className="text-ink-300">
                  {UNPLACED_SENSORS.length} proximity sensors
                </strong>{' '}
                ({UNPLACED_SENSORS.map((s) => s.label).join(', ')}) are not
                placed. The Sequencing sheet describes only four position
                checks; nothing records where the rest are mounted.
              </span>
            </li>
            <li className="flex gap-2">
              <Info size={12} className="mt-0.5 shrink-0 text-state-warn" />
              <span>
                <strong className="text-ink-300">Cylinder extension.</strong> No
                reed-switch tag exists, so even a mapped cylinder could only
                show what was <em>commanded</em>, never what moved.
              </span>
            </li>
            <li className="flex gap-2">
              <Camera size={12} className="mt-0.5 shrink-0 text-ink-500" />
              <span>
                Full detail in{' '}
                <code className="font-mono text-[10px]">
                  docs/TWIN_COMPONENT_MAPPING.md
                </code>
                .
              </span>
            </li>
          </ul>
        </Panel>
      </div>
    </div>
  )
}

function ConfidenceRow({ confidence }: { confidence: string }) {
  const meta = CONFIDENCE_META[confidence] ?? CONFIDENCE_META.APPROX
  return (
    <Row label="Confidence">
      <div>
        <Badge tone={meta.tone} className="!py-0 !text-[9px]">
          {confidence}
        </Badge>
        <p className="mt-1 text-[10px] leading-snug text-ink-500">{meta.meaning}</p>
      </div>
    </Row>
  )
}

function Row({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="border-b border-panel-800 pb-2 last:border-0">
      <div className="text-[10px] uppercase tracking-wider text-ink-500">{label}</div>
      <div className="mt-1">{children}</div>
    </div>
  )
}
