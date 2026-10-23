import type { Tri } from '../types'

/** Wall-clock time with milliseconds. Event logs need the ms to be useful. */
export function clockMs(epochSeconds: number | null | undefined): string {
  if (!epochSeconds) return '--:--:--.---'
  const d = new Date(epochSeconds * 1000)
  const pad = (n: number, w = 2) => String(n).padStart(w, '0')
  return (
    `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}` +
    `.${pad(d.getMilliseconds(), 3)}`
  )
}

export function clock(epochSeconds: number | null | undefined): string {
  if (!epochSeconds) return '--:--:--'
  const d = new Date(epochSeconds * 1000)
  const pad = (n: number) => String(n).padStart(2, '0')
  return `${pad(d.getHours())}:${pad(d.getMinutes())}:${pad(d.getSeconds())}`
}

/** "4.2 s ago" / "3 m ago". Returns "never" for null rather than "NaN ago". */
export function ago(epochSeconds: number | null | undefined): string {
  if (!epochSeconds) return 'never'
  const delta = Date.now() / 1000 - epochSeconds
  if (delta < 0) return 'just now'
  if (delta < 60) return `${delta.toFixed(1)} s ago`
  if (delta < 3600) return `${Math.floor(delta / 60)} m ago`
  return `${Math.floor(delta / 3600)} h ago`
}

export function duration(seconds: number | null | undefined): string {
  if (seconds === null || seconds === undefined) return '--'
  if (seconds < 60) return `${seconds.toFixed(1)} s`
  const m = Math.floor(seconds / 60)
  const s = Math.round(seconds % 60)
  return `${m} m ${String(s).padStart(2, '0')} s`
}

/**
 * The three-state renderer used everywhere a Bool is shown.
 *
 * `null` is NOT rendered as OFF. An unknown signal drawn as OFF is how an HMI
 * misleads an operator into thinking a sensor is clear when in fact nothing is
 * being read from it at all.
 */
export function triLabel(v: Tri, on = 'ON', off = 'OFF'): string {
  if (v === true) return on
  if (v === false) return off
  return 'N/A'
}

export function num(
  v: number | null | undefined,
  digits = 2,
  fallback = '--',
): string {
  if (v === null || v === undefined || Number.isNaN(v)) return fallback
  return v.toFixed(digits)
}

export function pretty(v: unknown): string {
  if (v === true) return 'ON'
  if (v === false) return 'OFF'
  if (v === null || v === undefined) return 'N/A'
  if (typeof v === 'number') return Number.isInteger(v) ? String(v) : v.toFixed(3)
  return String(v)
}

export function classNames(...parts: Array<string | false | null | undefined>) {
  return parts.filter(Boolean).join(' ')
}
