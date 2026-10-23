/**
 * The live process timeline.
 *
 * Every step is drawn with its guard, and the guard's *kind* is what makes the
 * display honest:
 *
 *   sensor       a real PLC input we watch. Confirmation means something.
 *   operator     waits on an explicit human acknowledgement.
 *   immediate    the PLC falls straight through; nothing to observe.
 *   timer        an operator action with no duration in any source. The
 *                digital twin's own docs call 12.5 s of the 31 s cycle
 *                placeholder time, so it is labelled as such.
 *   unobservable a real physical guard with NO tag in the tag list. Cylinder
 *                extend/retract is the big one: there is no reed-switch
 *                address anywhere, so the HMI says it cannot confirm rather
 *                than inventing a green tick.
 *   external     outside the PLC entirely (the camera).
 *
 * The stall banner is the part that earns its keep. When the machine hangs it
 * names the exact signal, how long it has been waiting, and what that signal
 * currently reads -- which is the difference between "it's stuck again" and
 * "PX3 has been low for 41 s".
 */

import { useEffect, useRef } from 'react'
import {
  AlertTriangle, Ban, CheckCircle2, Circle, Eye, EyeOff, Hand, Loader2,
  Radio, Timer,
} from 'lucide-react'
import {
  GUARD_CONFLICTS, hasConflict,
} from '../cell/sequenceSources'
import { selectSequence, selectSensors, useMachine } from '../../stores/machineStore'
import type { GuardKind, SequenceStep } from '../../types'
import { classNames, duration } from '../../utils/format'
import { Badge, Panel } from '../common/Primitives'

const GUARD_ICON: Record<GuardKind, typeof Radio> = {
  sensor: Radio,
  operator: Hand,
  immediate: Circle,
  timer: Timer,
  unobservable: EyeOff,
  external: Eye,
}

const GUARD_HINT: Record<GuardKind, string> = {
  sensor: 'Confirmed by a documented PLC input.',
  operator: 'Waits for an explicit operator acknowledgement.',
  immediate: 'The PLC falls straight through; there is nothing to observe.',
  timer: 'Operator action. No duration is recorded in any source — the twin treats it as placeholder time.',
  unobservable: 'Real physical guard, but no tag exists for it in Tag_list (1).xlsx. Cannot be confirmed.',
  external: 'Outside the PLC — provided by the camera service.',
}

export function SequenceTimeline({
  catalogue,
  compact,
  selectedKey,
  onSelectStep,
}: {
  catalogue: SequenceStep[]
  compact?: boolean
  /** Key of the step the caller is showing on the plan view, if any. */
  selectedKey?: string | null
  onSelectStep?: (step: SequenceStep) => void
}) {
  const sequence = useMachine(selectSequence)
  const sensors = useMachine(selectSensors)
  const activeRef = useRef<HTMLLIElement>(null)

  const activeIndex = sequence?.stepIndex ?? 0
  const lastConfirmed = sequence?.lastConfirmedStep ?? -1

  useEffect(() => {
    activeRef.current?.scrollIntoView({ block: 'center', behavior: 'smooth' })
  }, [activeIndex])

  const waitingSensor = sensors?.find((s) => s.role === sequence?.waitingRole)

  return (
    <Panel
      title="Process sequence"
      actions={
        <Badge tone={sequence?.stalled ? 'fault' : 'info'}>
          {sequence?.confidence === 'inferred' ? 'Inferred from sensors' : 'Awaiting first confirmation'}
        </Badge>
      }
    >
      {sequence?.awaitingOperator && !sequence?.stalled && (
        <div className="mb-3 rounded-lg border border-state-warn/55 bg-state-warn/10 p-3">
          <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-state-warn">
            <Hand size={14} />
            Awaiting operator
          </div>
          <p className="mt-1 text-sm text-ink-300">
            Holding at step {sequence.stepIndex} for a manual action. Confirm
            engraving on the Overview page.
          </p>
        </div>
      )}

      {sequence?.stalled && (
        <div className="mb-3 rounded-lg border border-state-fault/55 bg-state-fault/10 p-3">
          <div className="mb-1.5 flex items-center gap-2 text-xs font-bold uppercase tracking-wider text-state-fault">
            <Loader2 size={14} className="animate-spin" />
            Sequence stalled
          </div>
          <dl className="grid grid-cols-2 gap-x-4 gap-y-1 text-xs sm:grid-cols-4">
            <StallStat label="Waiting for" value={sequence.waitingFor ?? '--'} wide />
            <StallStat
              label="Elapsed"
              value={duration(
                sequence.waitingSince
                  ? Date.now() / 1000 - sequence.waitingSince
                  : sequence.elapsedSeconds,
              )}
            />
            <StallStat label="Budget" value={duration(sequence.timeoutSeconds)} />
            <StallStat
              label="Actual state"
              value={
                waitingSensor
                  ? waitingSensor.value === true
                    ? 'ACTIVE'
                    : waitingSensor.value === false
                      ? 'OFF'
                      : 'UNKNOWN'
                  : 'no tag'
              }
            />
          </dl>
        </div>
      )}

      <ol
        className={classNames(
          'mt-3 space-y-0.5 overflow-y-auto pr-1',
          compact ? 'max-h-[340px]' : 'max-h-[560px]',
        )}
      >
        {catalogue.map((step) => {
          const done = step.index <= lastConfirmed
          const active = step.index === activeIndex
          const selected = selectedKey === step.key
          const Icon = GUARD_ICON[step.guardKind]
          const conflict = hasConflict(step.key, step.guardRole)
            ? GUARD_CONFLICTS[step.key]
            : null

          return (
            <li
              key={step.key}
              ref={active ? activeRef : undefined}
              onClick={() => onSelectStep?.(step)}
              className={classNames(
                'flex items-start gap-2.5 rounded-lg border px-2.5 py-1.5 transition-colors',
                onSelectStep && 'cursor-pointer hover:bg-panel-800/60',
                active
                  ? sequence?.stalled
                    ? 'border-state-fault/60 bg-state-fault/10'
                    : 'border-state-info/60 bg-state-info/10'
                  : selected
                    ? 'border-state-twin/50 bg-state-twin/8'
                    : done
                      ? 'border-transparent bg-panel-800/40'
                      : 'border-transparent',
              )}
            >
              <span className="mt-0.5 shrink-0">
                {done ? (
                  <CheckCircle2 size={15} className="text-state-run" />
                ) : active ? (
                  <Loader2
                    size={15}
                    className={classNames(
                      'animate-spin',
                      sequence?.stalled ? 'text-state-fault' : 'text-state-info',
                    )}
                  />
                ) : step.guardKind === 'unobservable' ? (
                  <Ban size={15} className="text-ink-600 opacity-50" />
                ) : (
                  <Circle size={15} className="text-ink-600 opacity-50" />
                )}
              </span>

              <span className="min-w-0 flex-1">
                <span className="flex flex-wrap items-baseline gap-x-2">
                  <span className="font-mono text-xs text-ink-500">
                    {String(step.index).padStart(2, '0')}
                  </span>
                  <span
                    className={classNames(
                      'text-sm',
                      active
                        ? 'font-semibold text-ink-100'
                        : done
                          ? 'text-ink-300'
                          : 'text-ink-400',
                    )}
                  >
                    {step.name}
                  </span>
                  {step.implicit && (
                    <span
                      className="rounded bg-panel-700 px-1 text-xs uppercase tracking-wide text-ink-400"
                      title="Engineering addition: the Sequencing sheet never commands a retract, but a rod left extended blocks the next transport."
                    >
                      implicit
                    </span>
                  )}
                  {step.anomaly && (
                    <span
                      className="rounded bg-state-warn/20 px-1 text-xs uppercase tracking-wide text-state-warn"
                      title={step.anomaly}
                    >
                      sheet anomaly
                    </span>
                  )}
                  {conflict && (
                    <span
                      className="inline-flex items-center gap-1 rounded bg-state-warn/20 px-1 text-xs uppercase tracking-wide text-state-warn"
                      title={`${conflict.corroboration}\n\n${conflict.consequence}`}
                    >
                      <AlertTriangle size={9} />
                      sources disagree
                    </span>
                  )}
                </span>

                <span
                  className="mt-0.5 flex items-center gap-1.5 text-xs text-ink-500"
                  title={GUARD_HINT[step.guardKind]}
                >
                  <Icon size={11} />
                  <span className="truncate">{step.guardLabel}</span>
                  {step.guardKind === 'timer' && step.typicalSeconds && (
                    <span className="text-state-warn/70">
                      ~{step.typicalSeconds}s
                    </span>
                  )}
                </span>

              </span>

              {step.station && (
                <span className="mt-0.5 shrink-0 text-xs uppercase tracking-wider text-ink-600">
                  {step.station}
                </span>
              )}
            </li>
          )
        })}
      </ol>
    </Panel>
  )
}

function StallStat({
  label,
  value,
  wide,
}: {
  label: string
  value: string
  wide?: boolean
}) {
  return (
    <div className={wide ? 'col-span-2' : undefined}>
      <dt className="text-xs uppercase tracking-wider text-ink-500">{label}</dt>
      <dd className="truncate font-mono text-xs text-state-fault">{value}</dd>
    </div>
  )
}
