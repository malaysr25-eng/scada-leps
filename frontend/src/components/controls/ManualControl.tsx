/**
 * Manual control workspace.
 *
 * WHAT MAKES THIS DIFFERENT FROM THE OLD DASHBOARD
 * ------------------------------------------------
 * The old PLC dashboard rendered all 121 tags as one flat table of Toggle
 * buttons, each of which POSTed straight to `db_write` with no checks and no
 * confirmation. This screen instead:
 *
 * * groups controls by physical subsystem, so an operator is looking at
 *   pneumatics or conveyors, not at a scrollable wall of addresses;
 *
 * * shows the full command lifecycle per control. A valve tile displays the
 *   *commanded* bit and the *output coil* side by side, because they are
 *   different facts and the whole class of "actuator 8 did not retract" bugs
 *   lives in the gap between them;
 *
 * * never claims success from an HTTP 200. The tile goes amber on PENDING and
 *   only turns green when a later, independent PLC read confirms the value.
 *   A write the PLC overwrites shows MISMATCH with an explanation, rather than
 *   a green tick over a valve that never moved.
 */

import { useState, type Dispatch, type SetStateAction } from 'react'
import {
  AlertTriangle, CheckCircle2, ChevronRight, CircleSlash, Gauge, Loader2,
  Lock, Sliders, XCircle, Zap,
} from 'lucide-react'
import { groupCoils } from '../cell/CellPlan'
import {
  actuatorLabel, type Actuator,
} from '../cell/actuatorModel'
import { api } from '../../services/api'
import {
  selectActuators, selectConveyors, selectMachine, useMachine,
} from '../../stores/machineStore'
import type {
  ActuatorView, CommandEntry, CommandState, SpeedTagRef, Tri,
} from '../../types'
import { ago, classNames, num } from '../../utils/format'
import { Badge, Button, Note, Panel } from '../common/Primitives'

const CMD_TONE: Record<CommandState, 'run' | 'warn' | 'fault' | 'idle' | 'info'> = {
  PENDING: 'warn',
  WRITTEN: 'warn',
  CONFIRMED: 'run',
  MISMATCH: 'fault',
  TIMEOUT: 'fault',
  REJECTED: 'fault',
  FAILED: 'fault',
}

const CMD_LABEL: Record<CommandState, string> = {
  PENDING: 'Queued',
  WRITTEN: 'Written — awaiting PLC read-back',
  CONFIRMED: 'PLC confirmed',
  MISMATCH: 'PLC did not hold the value',
  TIMEOUT: 'Timed out',
  REJECTED: 'Rejected',
  FAILED: 'Write failed',
}

export function ManualWorkspace() {
  const machine = useMachine(selectMachine)
  const mode = machine?.mode ?? 'AUTO'
  const locked = mode === 'AUTO'

  return (
    <div className="space-y-4">
      {locked && (
        <Note tone="warn">
          <span className="flex items-start gap-2">
            <Lock size={14} className="mt-0.5 shrink-0" />
            <span>
              <strong>AUTO mode owns the machine.</strong> Switch to MANUAL in
              the top bar to take control.
            </span>
          </span>
        </Note>
      )}

      <PneumaticsPanel locked={locked} />
      <ConveyorPanel locked={locked} mode={mode} />
    </div>
  )
}

// ---------------------------------------------------------------------------

/**
 * The thirteen coils, grouped as the eleven actuators they drive.
 *
 * The backend publishes thirteen flat valve entries because thirteen coil tags
 * is exactly what the tag list contains. Presenting them that way put SV7 and
 * SV8 on screen as unrelated tiles when they are the two ends of one spool --
 * and an operator who energises SV7 while SV8 is still latched is fighting the
 * valve, not commanding it. `factory_actuators.m` is the authority on the
 * pairing; nothing here invents a grouping.
 */
function PneumaticsPanel({ locked }: { locked: boolean }) {
  const actuators = useMachine(selectActuators)
  const { grouped, unmapped } = groupCoils(actuators)

  return (
    <Panel
      title="Pneumatics — 11 actuators, 13 coils"
      actions={<Badge tone={locked ? 'idle' : 'warn'}>{locked ? 'Locked' : 'Armed'}</Badge>}
    >
      <div className="grid grid-cols-1 gap-2.5 lg:grid-cols-2 2xl:grid-cols-3">
        {grouped.map(({ actuator, extend, retract }) => (
          <ActuatorCard
            key={actuator.name}
            actuator={actuator}
            extend={extend}
            retract={retract}
            locked={locked}
          />
        ))}
      </div>

      {unmapped.length > 0 && (
        <Note tone="warn">
          {unmapped.length} coil{unmapped.length === 1 ? '' : 's'} withheld:
          not mapped to an actuator (
          {unmapped.map((u) => `SV${u.index}`).join(', ')}).
        </Note>
      )}
    </Panel>
  )
}

function ActuatorCard({
  actuator,
  extend,
  retract,
  locked,
}: {
  actuator: Actuator
  extend?: ActuatorView
  retract?: ActuatorView
  locked: boolean
}) {
  const isDouble = actuator.kind === 'double'
  const anyCoilOn = extend?.state === true || retract?.state === true

  return (
    <div
      className={classNames(
        'rounded-lg border p-3 transition-colors',
        anyCoilOn
          ? 'border-state-run/45 bg-state-run/6'
          : 'border-panel-700 bg-panel-800',
      )}
    >
      <div className="mb-1 flex flex-wrap items-center gap-x-2 gap-y-1">
        <span className="font-mono text-sm font-semibold text-ink-200">
          {actuatorLabel(actuator)}
        </span>
        {actuator.alias && (
          <span className="font-mono text-xs text-ink-500">
            {actuator.alias}
          </span>
        )}
        <Badge tone={isDouble ? 'twin' : 'idle'} className="ml-auto !py-0">
          {isDouble ? 'Double · latching' : 'Spring-return'}
        </Badge>
      </div>

      <p className="mb-2 text-xs leading-snug text-ink-500">
        {actuator.role}
        {actuator.geometry.travel != null &&
          ` · ${(actuator.geometry.travel * 1000).toFixed(0)} mm stroke`}
      </p>

      <div className="space-y-2">
        <CoilControl
          coil={extend}
          number={actuator.coilExtend}
          action={isDouble ? 'Extend' : 'Energise'}
          release={isDouble ? 'Drop extend coil' : 'Release'}
          locked={locked}
        />
        {isDouble && (
          <CoilControl
            coil={retract}
            number={actuator.coilRetract}
            action="Retract"
            release="Drop retract coil"
            locked={locked}
          />
        )}
      </div>

    </div>
  )
}

function CoilControl({
  coil,
  number,
  action,
  release,
  locked,
}: {
  coil?: ActuatorView
  number: number
  action: string
  release: string
  locked: boolean
}) {
  const pushToast = useMachine((s) => s.pushToast)
  const commands = useMachine((s) => s.snapshot?.commands)
  const [busy, setBusy] = useState(false)
  // The toast disappears; the reason a command was refused should not. It is
  // usually the most useful thing on the screen.
  const [refusal, setRefusal] = useState<{ code: string; message: string } | null>(
    null,
  )

  if (!coil) {
    return (
      <div className="rounded border border-dashed border-panel-600 px-2 py-1.5 text-xs text-ink-500">
        Coil {number}: no tag in the registry, so it cannot be read or commanded.
      </div>
    )
  }

  const recent: CommandEntry | undefined = commands?.find(
    (c) => c.tagId === coil.manualTagId,
  )
  const cmdOn = coil.manualCommand === true
  // Command says one thing, the output coil says another: the exact signature
  // of a PLC program fighting a manual write.
  const contested = cmdOn && coil.state === false

  async function toggle() {
    if (!coil?.manualTagId) return
    setBusy(true)
    setRefusal(null)
    const res = await api.writeTag(coil.manualTagId, !cmdOn)
    setBusy(false)

    if (!res.ok) {
      setRefusal({ code: res.error.code, message: res.error.message })
      pushToast({
        kind: res.error.code === 'confirmation_required' ? 'warn' : 'error',
        title: `Coil ${number} command refused`,
        detail: res.error.message,
      })
    }
  }

  return (
    <div
      className={classNames(
        'rounded border px-2 py-1.5',
        coil.state === true
          ? 'border-state-run/40 bg-state-run/8'
          : contested
            ? 'border-state-fault/50 bg-state-fault/8'
            : 'border-panel-700 bg-panel-900/60',
      )}
    >
      <div className="mb-1.5 flex items-center justify-between gap-2">
        <span className="text-xs font-semibold uppercase tracking-wider text-ink-400">
          {action}
          <span className="ml-1.5 font-mono text-xs normal-case text-ink-600">
            coil {number}
          </span>
        </span>
      </div>

      {/* The two facts, side by side. */}
      <div className="mb-1.5 grid grid-cols-2 gap-1.5 text-xs">
        <StatePill label="Command" value={coil.manualCommand} tone="info" />
        <StatePill label="Output coil" value={coil.state} tone="run" />
      </div>

      <Button
        variant={cmdOn ? 'warn' : 'ghost'}
        size="sm"
        onClick={toggle}
        disabled={locked || busy || !coil.manualTagId}
        className="w-full"
        title={
          locked
            ? 'Switch to MANUAL mode to command this coil'
            : !coil.manualTagId
              ? 'No manual command tag exists for this coil'
              : `Set ${coil.manualAddress} ${cmdOn ? 'OFF' : 'ON'}`
        }
      >
        {busy ? (
          <Loader2 size={13} className="animate-spin" />
        ) : locked ? (
          <Lock size={13} />
        ) : (
          <Zap size={13} />
        )}
        {cmdOn ? release : action}
      </Button>

      {recent && <CommandStrip cmd={recent} />}

      {refusal && (
        <p className="mt-1.5 flex items-start gap-1 text-xs leading-snug text-state-fault">
          <CircleSlash size={11} className="mt-px shrink-0" />
          <span>
            <span className="font-mono">{refusal.code}</span> &mdash;{' '}
            {refusal.message}
          </span>
        </p>
      )}

      {contested && (
        <p className="mt-1.5 flex items-start gap-1 text-xs leading-snug text-state-fault">
          <AlertTriangle size={11} className="mt-px shrink-0" />
          Command bit set but the output coil is off — the PLC program is
          overriding it.
        </p>
      )}

      <div className="mt-1.5 flex justify-between text-xs text-ink-500">
        <span>{coil.transitions}× changes</span>
        <span>{ago(coil.lastChangeAt)}</span>
      </div>
    </div>
  )
}

function StatePill({
  label,
  value,
  tone,
}: {
  label: string
  value: Tri
  tone: 'run' | 'info'
}) {
  const on = value === true
  const unknown = value == null
  return (
    <div
      className={classNames(
        'rounded border px-1.5 py-1 text-center',
        on
          ? tone === 'run'
            ? 'border-state-run/50 bg-state-run/12 text-state-run'
            : 'border-state-info/50 bg-state-info/12 text-state-info'
          : 'border-panel-600 bg-panel-900 text-ink-500',
      )}
    >
      <div className="text-xs uppercase tracking-wider opacity-70">{label}</div>
      <div className="font-mono text-xs font-bold">
        {on ? 'ON' : unknown ? 'N/A' : 'OFF'}
      </div>
    </div>
  )
}

export function CommandStrip({ cmd }: { cmd: CommandEntry }) {
  const tone = CMD_TONE[cmd.state]
  const Icon =
    cmd.state === 'CONFIRMED'
      ? CheckCircle2
      : cmd.state === 'PENDING' || cmd.state === 'WRITTEN'
        ? Loader2
        : cmd.state === 'REJECTED'
          ? CircleSlash
          : XCircle

  const toneClass = {
    run: 'text-state-run',
    warn: 'text-state-warn',
    fault: 'text-state-fault',
    idle: 'text-ink-500',
    info: 'text-state-info',
  }[tone]

  return (
    <div
      className="mt-1.5 flex items-center gap-1.5 rounded border border-panel-700 bg-panel-900 px-1.5 py-1"
      title={cmd.error || CMD_LABEL[cmd.state]}
    >
      <Icon
        size={11}
        className={classNames(
          toneClass,
          (cmd.state === 'PENDING' || cmd.state === 'WRITTEN') && 'animate-spin',
        )}
      />
      <span className={classNames('truncate text-xs font-medium', toneClass)}>
        {CMD_LABEL[cmd.state]}
      </span>
      {cmd.latencyMs != null && (
        <span className="ml-auto shrink-0 font-mono text-xs text-ink-500">
          {cmd.latencyMs.toFixed(0)}ms
        </span>
      )}
    </div>
  )
}

// ---------------------------------------------------------------------------

/**
 * Conveyor speed control.
 *
 * WHY THIS IS MORE THAN ONE INPUT BOX
 * -----------------------------------
 * The commanded speed an operator sees is not simply "the number someone last
 * typed". The PLC's stepper technology object holds *two stored profiles* per
 * conveyor -- HighSpeed_Velocity and LowSpeed_Velocity -- and Set_HighSpeed
 * selects between them. Set_Velocity is the live custom override on top.
 *
 * Exposing only Set_Velocity, as the old dashboard did, means an operator
 * changes the speed, the PLC reloads a profile, and the belt reverts to a
 * value they cannot see and did not choose. That is the Errors-sheet entry
 * about conveyor 2 "not responding to dashboard speed changes", and it is
 * indistinguishable from a drive fault unless all three numbers are on screen.
 *
 * So: both profiles, the selector, and the live setpoint are editable here,
 * each writing its own registry-resolved tag, and each proved by encoder
 * feedback rather than by an HTTP 200.
 */
function ConveyorPanel({ locked, mode }: { locked: boolean; mode: string }) {
  const conveyors = useMachine(selectConveyors)
  const pushToast = useMachine((s) => s.pushToast)
  const commands = useMachine((s) => s.snapshot?.commands)
  const [runBusy, setRunBusy] = useState<number | null>(null)
  const [busyTag, setBusyTag] = useState<string | null>(null)
  const [drafts, setDrafts] = useState<Record<string, string>>({})
  const [refusals, setRefusals] = useState<Record<string, string>>({})

  // The backend permits the four speed roles in MANUAL as well as MAINTENANCE.
  const speedUnlocked = mode === 'MANUAL' || mode === 'MAINTENANCE'

  async function toggleRun(index: number, current: Tri) {
    setRunBusy(index)
    const res = await api.writeTag(
      `manual_commands.conveyor${index}`,
      current !== true,
    )
    setRunBusy(null)
    if (!res.ok) {
      pushToast({
        kind: 'error',
        title: `Conveyor ${index} command refused`,
        detail: res.error.message,
      })
    }
  }

  /** Shared write path for every numeric speed field and the profile selector. */
  async function writeSpeed(
    ref: SpeedTagRef,
    value: number | boolean,
    label: string,
  ) {
    setBusyTag(ref.tagId)
    setRefusals((r) => ({ ...r, [ref.tagId]: '' }))
    // Engineering access always demands confirmation; deliberately choosing
    // this control while speed is unlocked is that confirmation.
    const res = await api.writeTag(ref.tagId, value, true)
    setBusyTag(null)

    if (res.ok) {
      setDrafts((d) => ({ ...d, [ref.tagId]: '' }))
      pushToast({
        kind: 'ok',
        title: `${label} written`,
        detail: 'Queued — the tile confirms only on an independent PLC read-back.',
      })
    } else {
      setRefusals((r) => ({ ...r, [ref.tagId]: res.error.message }))
      pushToast({
        kind: 'error',
        title: `${label} refused`,
        detail: res.error.message,
      })
    }
  }

  return (
    <Panel
      title="Conveyors — run and speed"
      actions={
        <Badge tone={speedUnlocked ? 'twin' : 'idle'}>
          {speedUnlocked ? 'Speed unlocked' : 'Speed needs MANUAL'}
        </Badge>
      }
    >
      <div className="space-y-3">
        {(conveyors ?? []).map((c) => {
          const moving =
            c.feedbackVelocity != null && Math.abs(c.feedbackVelocity) > 1e-6

          // Mirrors Diagnostics._run_without_motion, and for the same reason:
          // the run coil is a station enable, not a motor-running signal. On
          // 2026-09-21 conveyor 2's coil was ON for 66 s while the axis sat
          // correctly parked at its target. Flagging that as "no encoder
          // motion" is how the old check faulted every good cycle.
          const positionError =
            c.setPosition != null && c.position != null
              ? Math.abs(c.setPosition - c.position)
              : null
          const commandedToMove =
            c.running === true && positionError != null && positionError > 0.5
          const mismatch = commandedToMove && !moving
          const parked = c.running === true && positionError != null && !commandedToMove
          const tags = c.speedTags
          const highSelected = c.highSpeedSelected === true

          // The speed command whose lifecycle this tile should report: the most
          // recent one against any of this conveyor's speed tags.
          const speedTagIds = [
            tags?.setVelocity?.tagId,
            tags?.highSpeedVelocity?.tagId,
            tags?.lowSpeedVelocity?.tagId,
            tags?.highSpeedSelect?.tagId,
          ].filter(Boolean) as string[]
          const recent: CommandEntry | undefined = commands?.find((cmd) =>
            speedTagIds.includes(cmd.tagId),
          )

          // The profile the PLC should be running from, and whether the live
          // setpoint actually agrees with it. A disagreement is legitimate --
          // it means someone set a custom override -- but it must be visible.
          const activeProfile = highSelected
            ? c.highSpeedVelocity
            : c.lowSpeedVelocity
          const overridden =
            activeProfile != null &&
            c.commandedVelocity != null &&
            Math.abs(activeProfile - c.commandedVelocity) > 1e-6

          return (
            <div
              key={c.index}
              className={classNames(
                'rounded-lg border p-3',
                mismatch
                  ? 'border-state-fault/50 bg-state-fault/8'
                  : c.running === true
                    ? 'border-state-run/40 bg-state-run/6'
                    : 'border-panel-700 bg-panel-800',
              )}
            >
              <div className="mb-2.5 flex flex-wrap items-center gap-3">
                <span className="text-sm font-semibold text-ink-200">{c.label}</span>
                <Badge tone={c.running === true ? 'run' : 'idle'}>
                  {c.running === true ? 'Run coil ON' : c.running === false ? 'Stopped' : 'Unknown'}
                </Badge>
                <Badge tone={highSelected ? 'warn' : 'idle'} icon={<Gauge size={11} />}>
                  {c.highSpeedSelected == null
                    ? 'Profile unknown'
                    : highSelected
                      ? 'High speed'
                      : 'Low speed'}
                </Badge>
                {mismatch && (
                  <Badge tone="fault" icon={<AlertTriangle size={11} />}>
                    No encoder motion
                  </Badge>
                )}
                {parked && <Badge tone="idle">At target</Badge>}
                {c.error === true && <Badge tone="fault">Drive error</Badge>}
                <Button
                  variant={c.manualCommand === true ? 'warn' : 'ghost'}
                  size="sm"
                  onClick={() => toggleRun(c.index, c.manualCommand)}
                  disabled={locked || runBusy === c.index}
                  className="ml-auto"
                >
                  {runBusy === c.index ? (
                    <Loader2 size={13} className="animate-spin" />
                  ) : (
                    <Sliders size={13} />
                  )}
                  {c.manualCommand === true ? 'Stop' : 'Run'}
                </Button>
              </div>

              {/* --- profile selector ------------------------------------ */}
              <div className="mb-2.5 flex flex-wrap items-center gap-2 rounded border border-panel-700 bg-panel-900/60 px-2 py-1.5">
                <span className="text-xs uppercase tracking-wider text-ink-500">
                  Speed profile
                </span>
                {tags?.highSpeedSelect ? (
                  <>
                    <div className="flex gap-1">
                      <Button
                        variant={highSelected ? 'warn' : 'ghost'}
                        size="sm"
                        onClick={() =>
                          writeSpeed(
                            tags.highSpeedSelect!,
                            true,
                            `Conveyor ${c.index} high-speed profile`,
                          )
                        }
                        disabled={
                          !speedUnlocked ||
                          highSelected ||
                          busyTag === tags.highSpeedSelect.tagId
                        }
                        title="Set Set_HighSpeed — the PLC loads HighSpeed_Velocity"
                      >
                        High
                      </Button>
                      <Button
                        variant={c.highSpeedSelected === false ? 'warn' : 'ghost'}
                        size="sm"
                        onClick={() =>
                          writeSpeed(
                            tags.highSpeedSelect!,
                            false,
                            `Conveyor ${c.index} low-speed profile`,
                          )
                        }
                        disabled={
                          !speedUnlocked ||
                          c.highSpeedSelected === false ||
                          busyTag === tags.highSpeedSelect.tagId
                        }
                        title="Clear Set_HighSpeed — the PLC loads LowSpeed_Velocity"
                      >
                        Low
                      </Button>
                    </div>
                    <span className="font-mono text-xs text-ink-600">
                      {tags.highSpeedSelect.address}
                    </span>
                  </>
                ) : (
                  <span className="text-xs text-ink-500">
                    No Set_HighSpeed tag in the registry — profile cannot be
                    selected from here.
                  </span>
                )}
                {overridden && (
                  <span className="ml-auto text-xs text-state-warn">
                    Live setpoint differs from the selected profile
                  </span>
                )}
              </div>

              {/* --- the three writable speeds --------------------------- */}
              <div className="mb-2.5 grid grid-cols-1 gap-2 sm:grid-cols-3">
                <SpeedField
                  label="High profile"
                  hint="HighSpeed_Velocity"
                  live={c.highSpeedVelocity}
                  active={highSelected}
                  tag={tags?.highSpeedVelocity ?? null}
                  unlocked={speedUnlocked}
                  busy={busyTag}
                  draft={drafts}
                  setDraft={setDrafts}
                  refusal={refusals}
                  onWrite={(ref, v) =>
                    writeSpeed(ref, v, `Conveyor ${c.index} high profile`)
                  }
                  onInvalid={(m) => pushToast({ kind: 'warn', title: m })}
                />
                <SpeedField
                  label="Low profile"
                  hint="LowSpeed_Velocity"
                  live={c.lowSpeedVelocity}
                  active={c.highSpeedSelected === false}
                  tag={tags?.lowSpeedVelocity ?? null}
                  unlocked={speedUnlocked}
                  busy={busyTag}
                  draft={drafts}
                  setDraft={setDrafts}
                  refusal={refusals}
                  onWrite={(ref, v) =>
                    writeSpeed(ref, v, `Conveyor ${c.index} low profile`)
                  }
                  onInvalid={(m) => pushToast({ kind: 'warn', title: m })}
                />
                <SpeedField
                  label="Live setpoint"
                  hint="Set_Velocity — custom override"
                  live={c.commandedVelocity}
                  active
                  tag={tags?.setVelocity ?? null}
                  unlocked={speedUnlocked}
                  busy={busyTag}
                  draft={drafts}
                  setDraft={setDrafts}
                  refusal={refusals}
                  onWrite={(ref, v) =>
                    writeSpeed(ref, v, `Conveyor ${c.index} setpoint`)
                  }
                  onInvalid={(m) => pushToast({ kind: 'warn', title: m })}
                />
              </div>

              {/* The numbers the Errors sheet needs separated. Target sits
                  beside position because their difference is what decides
                  whether zero feedback is a fault or the axis simply being
                  where it was told to be. */}
              <div className="grid grid-cols-2 gap-2 sm:grid-cols-4">
                <SpeedCell label="Commanded" value={c.commandedVelocity} unit="" tone="info" />
                <SpeedCell
                  label="Feedback"
                  value={c.feedbackVelocity}
                  unit=""
                  tone={mismatch ? 'fault' : moving ? 'run' : 'idle'}
                />
                <SpeedCell label="Position" value={c.position} unit="°" tone="idle" />
                <SpeedCell
                  label="Target"
                  value={c.setPosition}
                  unit="°"
                  tone={commandedToMove ? 'info' : 'idle'}
                />
              </div>

              {recent && <CommandStrip cmd={recent} />}

            </div>
          )
        })}
      </div>
    </Panel>
  )
}

function SpeedCell({
  label,
  value,
  unit,
  tone,
}: {
  label: string
  value: number | null
  unit: string
  tone: 'run' | 'fault' | 'idle' | 'info'
}) {
  const colour = {
    run: 'text-state-run',
    fault: 'text-state-fault',
    idle: 'text-ink-300',
    info: 'text-state-info',
  }[tone]
  return (
    <div>
      <div className="text-xs uppercase tracking-wider text-ink-500">{label}</div>
      <div className={classNames('font-mono text-sm tabular-nums', colour)}>
        {num(value, 3)}
        {unit && <span className="ml-0.5 text-xs text-ink-500">{unit}</span>}
      </div>
    </div>
  )
}

/**
 * One editable velocity: the live PLC value, an input, and a write button.
 *
 * Client-side range checking here is a courtesy, not the control. The backend
 * CommandGate range-checks the same bounds, because a UI check is bypassed by
 * anything that is not this UI. When the overlay carries no commissioned
 * limit the field says so rather than implying a bound that does not exist.
 */
function SpeedField({
  label,
  hint,
  live,
  active,
  tag,
  unlocked,
  busy,
  draft,
  setDraft,
  refusal,
  onWrite,
  onInvalid,
}: {
  label: string
  hint: string
  live: number | null
  active: boolean
  tag: SpeedTagRef | null
  unlocked: boolean
  busy: string | null
  draft: Record<string, string>
  setDraft: Dispatch<SetStateAction<Record<string, string>>>
  refusal: Record<string, string>
  onWrite: (ref: SpeedTagRef, value: number) => void
  onInvalid: (message: string) => void
}) {
  if (!tag) {
    return (
      <div className="rounded border border-dashed border-panel-600 px-2 py-1.5">
        <div className="text-xs uppercase tracking-wider text-ink-500">{label}</div>
        <p className="mt-1 text-xs leading-snug text-ink-500">
          No tag for this role in the registry, so it cannot be read or written.
        </p>
      </div>
    )
  }

  const value = draft[tag.tagId] ?? ''
  const isBusy = busy === tag.tagId
  const denial = refusal[tag.tagId]
  const hasRange = tag.min != null || tag.max != null

  function submit() {
    if (!tag) return
    const parsed = parseFloat(value)
    if (!Number.isFinite(parsed)) {
      onInvalid('Enter a numeric velocity first')
      return
    }
    if (tag.min != null && parsed < tag.min) {
      onInvalid(`${label} must be at least ${tag.min}`)
      return
    }
    if (tag.max != null && parsed > tag.max) {
      onInvalid(`${label} must be at most ${tag.max}`)
      return
    }
    onWrite(tag, parsed)
  }

  return (
    <div
      className={classNames(
        'rounded border px-2 py-1.5',
        active
          ? 'border-state-info/40 bg-state-info/6'
          : 'border-panel-700 bg-panel-900/60',
      )}
    >
      <div className="flex items-baseline justify-between gap-2">
        <span className="text-xs uppercase tracking-wider text-ink-500">
          {label}
        </span>
        <span className="font-mono text-sm tabular-nums text-ink-200">
          {num(live, 3)}
          {tag.unit && (
            <span className="ml-0.5 text-xs text-ink-500">{tag.unit}</span>
          )}
        </span>
      </div>

      <div className="mt-1 flex gap-1">
        <input
          value={value}
          onChange={(e) =>
            setDraft((d) => ({ ...d, [tag.tagId]: e.target.value }))
          }
          onKeyDown={(e) => {
            if (e.key === 'Enter') submit()
          }}
          placeholder={num(live, 3, '')}
          disabled={!unlocked || isBusy}
          inputMode="decimal"
          className="w-full min-w-0 rounded border border-panel-600 bg-panel-900 px-1.5 py-1 font-mono text-xs text-ink-100 placeholder:text-ink-600 disabled:opacity-40 focus:outline-none focus:ring-1 focus:ring-state-info/60"
        />
        <Button
          variant="ghost"
          size="sm"
          onClick={submit}
          disabled={!unlocked || isBusy}
          className="!px-2"
          title={
            unlocked
              ? `Write ${tag.address} (engineering command)`
              : 'Switch to MANUAL mode to change speed'
          }
        >
          {isBusy ? (
            <Loader2 size={13} className="animate-spin" />
          ) : unlocked ? (
            <ChevronRight size={13} />
          ) : (
            <Lock size={13} />
          )}
        </Button>
      </div>

      <div className="mt-1 flex flex-wrap items-center gap-x-2 text-xs text-ink-600">
        <span className="font-mono">{hint}</span>
        <span className="ml-auto">
          {hasRange
            ? `range ${tag.min ?? '−∞'} … ${tag.max ?? '∞'}`
            : 'no commissioned limit'}
        </span>
      </div>

      {denial && (
        <p className="mt-1 flex items-start gap-1 text-xs leading-snug text-state-fault">
          <CircleSlash size={11} className="mt-px shrink-0" />
          {denial}
        </p>
      )}
    </div>
  )
}
