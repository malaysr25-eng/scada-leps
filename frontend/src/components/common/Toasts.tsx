/**
 * Transient notifications.
 *
 * Refused commands are the most common thing shown here, and that is by
 * design: the command gate refuses writes constantly and on purpose, so a
 * refusal must read as a normal, explained outcome rather than an error the
 * operator caused.
 */

import { useEffect } from 'react'
import { AlertTriangle, CheckCircle2, X, XCircle } from 'lucide-react'
import { useMachine } from '../../stores/machineStore'
import { classNames } from '../../utils/format'

export function Toasts() {
  const toasts = useMachine((s) => s.toasts)
  const dismiss = useMachine((s) => s.dismissToast)

  return (
    <div className="pointer-events-none fixed bottom-4 right-4 z-50 flex w-[360px] flex-col gap-2">
      {toasts.map((t) => (
        <Toast key={t.id} toast={t} onDismiss={() => dismiss(t.id)} />
      ))}
    </div>
  )
}

function Toast({
  toast,
  onDismiss,
}: {
  toast: ReturnType<typeof useMachine.getState>['toasts'][number]
  onDismiss: () => void
}) {
  // Errors linger longer than confirmations: an operator needs time to read
  // why a command was refused.
  useEffect(() => {
    const ms = toast.kind === 'ok' ? 4000 : 9000
    const id = window.setTimeout(onDismiss, ms)
    return () => window.clearTimeout(id)
  }, [toast.id, toast.kind, onDismiss])

  const style = {
    ok: {
      cls: 'border-state-run/50 bg-panel-850',
      icon: <CheckCircle2 size={16} className="text-state-run" />,
      title: 'text-state-run',
    },
    warn: {
      cls: 'border-state-warn/50 bg-panel-850',
      icon: <AlertTriangle size={16} className="text-state-warn" />,
      title: 'text-state-warn',
    },
    error: {
      cls: 'border-state-fault/55 bg-panel-850',
      icon: <XCircle size={16} className="text-state-fault" />,
      title: 'text-state-fault',
    },
  }[toast.kind]

  return (
    <div
      className={classNames(
        'pointer-events-auto flex items-start gap-2.5 rounded-lg border p-3 shadow-panel',
        style.cls,
      )}
      role="status"
    >
      <span className="mt-0.5 shrink-0">{style.icon}</span>
      <div className="min-w-0 flex-1">
        <p className={classNames('text-sm font-semibold', style.title)}>
          {toast.title}
        </p>
        {toast.detail && (
          <p className="mt-0.5 text-xs leading-relaxed text-ink-400">{toast.detail}</p>
        )}
      </div>
      <button
        onClick={onDismiss}
        className="shrink-0 rounded p-0.5 text-ink-500 hover:bg-panel-700 hover:text-ink-200"
        aria-label="Dismiss"
      >
        <X size={14} />
      </button>
    </div>
  )
}
