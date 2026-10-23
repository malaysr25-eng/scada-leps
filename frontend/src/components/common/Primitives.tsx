/**
 * Shared UI primitives.
 *
 * Two rules hold across all of them:
 *
 * 1. **Colour is never the only channel.** Every state carries a text label,
 *    and usually an icon or a shape as well, so the interface survives a
 *    colour-blind operator and a washed-out projector.
 *
 * 2. **Unknown is a first-class state.** `null` renders as a distinct grey
 *    "N/A", never as OFF. See utils/format.ts::triLabel.
 */

import type { ReactNode } from 'react'
import { AlertTriangle, Check, HelpCircle, Minus } from 'lucide-react'
import type { Tri } from '../../types'
import { classNames } from '../../utils/format'

// ---------------------------------------------------------------------------

export function Panel({
  title,
  subtitle,
  actions,
  children,
  className,
  dense,
}: {
  title?: ReactNode
  subtitle?: ReactNode
  actions?: ReactNode
  children: ReactNode
  className?: string
  dense?: boolean
}) {
  return (
    <section
      className={classNames(
        'rounded-xl border border-panel-700 bg-panel-850 shadow-panel',
        className,
      )}
    >
      {(title || actions) && (
        <header className="flex items-start justify-between gap-3 border-b border-panel-700 px-4 py-3">
          <div className="min-w-0">
            {title && (
              <h2 className="truncate text-sm font-semibold uppercase tracking-[0.13em] text-ink-300">
                {title}
              </h2>
            )}
            {subtitle && (
              <p className="mt-0.5 text-xs text-ink-400">{subtitle}</p>
            )}
          </div>
          {actions && <div className="shrink-0">{actions}</div>}
        </header>
      )}
      <div className={dense ? 'p-2' : 'p-4'}>{children}</div>
    </section>
  )
}

// ---------------------------------------------------------------------------

type Tone = 'run' | 'idle' | 'warn' | 'fault' | 'info' | 'twin'

const TONE_CLASS: Record<Tone, string> = {
  run: 'border-state-run/45 bg-state-run/12 text-state-run',
  idle: 'border-panel-600 bg-panel-800 text-ink-400',
  warn: 'border-state-warn/45 bg-state-warn/12 text-state-warn',
  fault: 'border-state-fault/50 bg-state-fault/14 text-state-fault',
  info: 'border-state-info/45 bg-state-info/12 text-state-info',
  twin: 'border-state-twin/45 bg-state-twin/12 text-state-twin',
}

export function Badge({
  tone = 'idle',
  children,
  icon,
  className,
  title,
}: {
  tone?: Tone
  children: ReactNode
  icon?: ReactNode
  className?: string
  title?: string
}) {
  return (
    <span
      title={title}
      className={classNames(
        'inline-flex items-center gap-1.5 rounded-md border px-2 py-0.5',
        'text-xs font-semibold uppercase tracking-wider',
        TONE_CLASS[tone],
        className,
      )}
    >
      {icon}
      {children}
    </span>
  )
}

// ---------------------------------------------------------------------------

/**
 * A boolean signal lamp. Shape and label both encode the state, so the lamp is
 * readable without colour: filled circle = ON, hollow = OFF, "?" = unknown.
 */
export function Lamp({
  value,
  size = 'md',
  tone,
}: {
  value: Tri
  size?: 'sm' | 'md' | 'lg'
  tone?: 'run' | 'fault' | 'info' | 'warn'
}) {
  const px = size === 'sm' ? 'h-2.5 w-2.5' : size === 'lg' ? 'h-4 w-4' : 'h-3 w-3'
  const activeTone = tone ?? 'run'
  const colour =
    value === true
      ? {
          run: 'bg-state-run',
          fault: 'bg-state-fault',
          info: 'bg-state-info',
          warn: 'bg-state-warn',
        }[activeTone]
      : value === false
        ? 'bg-transparent border border-panel-500'
        : 'bg-transparent border border-dashed border-ink-500'

  return (
    <span
      className={classNames('inline-block shrink-0 rounded-full', px, colour)}
      aria-label={value === true ? 'on' : value === false ? 'off' : 'unknown'}
    />
  )
}

// ---------------------------------------------------------------------------

export function TriIcon({ value }: { value: Tri }) {
  if (value === true) return <Check size={14} className="text-state-run" />
  if (value === false) return <Minus size={14} className="text-ink-500" />
  return <HelpCircle size={14} className="text-ink-500" />
}

export function CheckRow({
  label,
  satisfied,
  required,
  detail,
}: {
  label: string
  satisfied: Tri
  required: boolean
  detail?: string
}) {
  const ok = satisfied === true
  return (
    <li className="flex items-start gap-2.5 py-1.5">
      <span className="mt-0.5">
        {ok ? (
          <Check size={15} className="text-state-run" />
        ) : required ? (
          <AlertTriangle size={15} className="text-state-fault" />
        ) : (
          <AlertTriangle size={15} className="text-state-warn" />
        )}
      </span>
      <span className="min-w-0 flex-1">
        <span
          className={classNames(
            'text-sm',
            ok ? 'text-ink-200' : required ? 'text-state-fault' : 'text-state-warn',
          )}
        >
          {label}
        </span>
        {!required && (
          <span className="ml-2 text-xs uppercase tracking-wider text-ink-500">
            advisory
          </span>
        )}
        {!ok && detail && (
          <p className="mt-0.5 text-xs leading-snug text-ink-400">{detail}</p>
        )}
      </span>
    </li>
  )
}

// ---------------------------------------------------------------------------

export function Metric({
  label,
  value,
  unit,
  tone = 'idle',
  hint,
  provenance,
}: {
  label: string
  value: ReactNode
  unit?: string
  tone?: Tone
  hint?: string
  provenance?: ReactNode
}) {
  const valueColour: Record<Tone, string> = {
    run: 'text-state-run',
    idle: 'text-ink-100',
    warn: 'text-state-warn',
    fault: 'text-state-fault',
    info: 'text-state-info',
    twin: 'text-state-twin',
  }
  return (
    <div className="min-w-0" title={hint}>
      <div className="flex items-center gap-1.5 text-xs font-medium uppercase tracking-[0.14em] text-ink-500">
        <span className="truncate">{label}</span>
        {provenance}
      </div>
      <div
        className={classNames(
          'mt-0.5 font-mono text-lg leading-tight tabular-nums',
          valueColour[tone],
        )}
      >
        {value}
        {unit && <span className="ml-1 text-xs text-ink-400">{unit}</span>}
      </div>
    </div>
  )
}

// ---------------------------------------------------------------------------

export function Button({
  children,
  onClick,
  variant = 'ghost',
  size = 'md',
  disabled,
  title,
  className,
  type = 'button',
}: {
  children: ReactNode
  onClick?: () => void
  variant?: 'primary' | 'danger' | 'ghost' | 'warn' | 'success'
  size?: 'sm' | 'md' | 'lg'
  disabled?: boolean
  title?: string
  className?: string
  type?: 'button' | 'submit'
}) {
  const variants: Record<string, string> = {
    primary:
      'bg-state-info/15 border-state-info/50 text-state-info hover:bg-state-info/25',
    success:
      'bg-state-run/15 border-state-run/50 text-state-run hover:bg-state-run/25',
    danger:
      'bg-state-fault/15 border-state-fault/55 text-state-fault hover:bg-state-fault/25',
    warn: 'bg-state-warn/15 border-state-warn/50 text-state-warn hover:bg-state-warn/25',
    ghost: 'bg-panel-800 border-panel-600 text-ink-200 hover:bg-panel-700',
  }
  const sizes: Record<string, string> = {
    // Deliberately generous hit targets: this is operated standing up, at a
    // machine, sometimes wearing gloves.
    sm: 'px-2.5 py-1 text-xs',
    md: 'px-3.5 py-2 text-sm',
    lg: 'px-5 py-3 text-base',
  }
  return (
    <button
      type={type}
      title={title}
      onClick={onClick}
      disabled={disabled}
      className={classNames(
        'inline-flex items-center justify-center gap-2 rounded-lg border font-semibold',
        'transition-colors focus:outline-none focus-visible:ring-2 focus-visible:ring-state-info/60',
        'disabled:cursor-not-allowed disabled:opacity-40 disabled:hover:bg-inherit',
        variants[variant],
        sizes[size],
        className,
      )}
    >
      {children}
    </button>
  )
}

// ---------------------------------------------------------------------------

export function EmptyState({ children }: { children: ReactNode }) {
  return (
    <div className="flex min-h-[120px] items-center justify-center rounded-lg border border-dashed border-panel-600 px-4 py-8 text-center text-sm text-ink-500">
      {children}
    </div>
  )
}

export function Note({
  children,
  tone = 'idle',
}: {
  children: ReactNode
  tone?: 'idle' | 'warn' | 'info' | 'fault'
}) {
  const tones = {
    idle: 'border-panel-600 bg-panel-800/60 text-ink-400',
    warn: 'border-state-warn/35 bg-state-warn/8 text-state-warn/90',
    info: 'border-state-info/35 bg-state-info/8 text-state-info/90',
    fault: 'border-state-fault/40 bg-state-fault/8 text-state-fault/90',
  }
  return (
    <p
      className={classNames(
        'rounded-lg border px-3 py-2 text-xs leading-relaxed',
        tones[tone],
      )}
    >
      {children}
    </p>
  )
}

/** Small provenance chip: LIVE / EST / ASM / PLH ... */
export function ProvenanceTag({
  value,
  title,
}: {
  value: string | null | undefined
  title?: string
}) {
  if (!value) return null
  const live = value === 'LIVE' || value === 'MEA'
  const bad = value === 'PLH'
  return (
    <span
      title={title}
      className={classNames(
        'rounded px-1 py-px font-mono text-xs font-bold tracking-wider',
        live
          ? 'bg-state-run/18 text-state-run'
          : bad
            ? 'bg-state-fault/18 text-state-fault'
            : 'bg-state-twin/18 text-state-twin',
      )}
    >
      {value}
    </span>
  )
}
