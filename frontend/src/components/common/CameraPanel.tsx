/**
 * Camera / YOLO status.
 *
 * The detector runs in its own OS process and publishes JSON; this only reads
 * it. That boundary is deliberate -- a slow inference pass or a dropped USB
 * camera must never stall the PLC poll loop.
 *
 * Staleness is shown prominently because the legacy system could not tell a
 * live camera from one whose process died hours ago still holding the last
 * JSON file. Anything past the staleness budget is reported OFFLINE and its
 * counts are withheld rather than drawn as current.
 */

import { Camera, CameraOff, Clock, Eye } from 'lucide-react'
import { selectCamera, useMachine } from '../../stores/machineStore'
import { ago, classNames, num } from '../../utils/format'
import { Badge, EmptyState, Note, Panel } from '../common/Primitives'

export function CameraPanel({ compact }: { compact?: boolean }) {
  const camera = useMachine(selectCamera)
  const online = camera?.online ?? false
  const status = camera?.status ?? 'OFFLINE'

  return (
    <Panel
      title="Camera detection"
      actions={
        <Badge
          tone={online ? 'run' : status === 'STALE' ? 'warn' : 'idle'}
          icon={online ? <Camera size={11} /> : <CameraOff size={11} />}
        >
          {status}
        </Badge>
      }
    >
      {!camera || status === 'OFFLINE' ? (
        <div className="space-y-3">
          <EmptyState>
            <span className="flex flex-col items-center gap-1.5">
              <CameraOff size={20} className="text-ink-600" />
              No detection feed. Start the bridge:
              <code className="mt-1 rounded bg-panel-900 px-2 py-1 font-mono text-xs text-ink-400">
                python tools/camera_bridge.py
              </code>
            </span>
          </EmptyState>
          {camera?.lastError && (
            <Note tone="warn">Last read error: {camera.lastError}</Note>
          )}
        </div>
      ) : (
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-3">
            <Stat
              label="Objects"
              value={String(camera.totalObjects)}
              tone={camera.totalObjects > 0 ? 'run' : 'idle'}
            />
            <Stat
              label={`Above ${camera.minConfidence}`}
              value={String(camera.confidentObjects)}
              tone={camera.confidentObjects > 0 ? 'run' : 'idle'}
            />
            <Stat
              label="Frame age"
              value={
                camera.frameAgeSeconds != null
                  ? `${num(camera.frameAgeSeconds, 1)} s`
                  : '--'
              }
              tone={
                camera.frameAgeSeconds != null &&
                camera.frameAgeSeconds > camera.staleAfterSeconds
                  ? 'warn'
                  : 'idle'
              }
            />
            <Stat label="Last frame" value={ago(camera.lastFrameAt)} tone="idle" />
          </div>

          {Object.keys(camera.classes).length > 0 && (
            <div className="flex flex-wrap gap-2">
              {Object.entries(camera.classes).map(([cls, count]) => (
                <Badge key={cls} tone="info" icon={<Eye size={10} />}>
                  {cls} × {count}
                </Badge>
              ))}
            </div>
          )}

          {!compact && Object.keys(camera.counts).length > 0 && (
            <div>
              <h3 className="mb-1.5 text-xs uppercase tracking-wider text-ink-500">
                Magazine column counts
              </h3>
              <div className="grid grid-cols-5 gap-1.5">
                {Object.entries(camera.counts).map(([k, v]) => (
                  <div
                    key={k}
                    className="rounded border border-panel-700 bg-panel-800 px-2 py-1.5 text-center"
                  >
                    <div className="text-xs uppercase text-ink-500">{k}</div>
                    <div className="font-mono text-sm text-ink-200">{v}</div>
                  </div>
                ))}
              </div>
            </div>
          )}

          {status === 'STALE' && (
            <Note tone="warn">
              <span className="flex items-start gap-1.5">
                <Clock size={12} className="mt-0.5 shrink-0" />
                No frame for over {camera.staleAfterSeconds} s. Counts withheld.
              </span>
            </Note>
          )}
        </div>
      )}
    </Panel>
  )
}

function Stat({
  label,
  value,
  tone,
}: {
  label: string
  value: string
  tone: 'run' | 'warn' | 'idle'
}) {
  const colour = {
    run: 'text-state-run',
    warn: 'text-state-warn',
    idle: 'text-ink-200',
  }[tone]
  return (
    <div>
      <div className="truncate text-xs uppercase tracking-wider text-ink-500">
        {label}
      </div>
      <div className={classNames('mt-0.5 font-mono text-base', colour)}>{value}</div>
    </div>
  )
}
