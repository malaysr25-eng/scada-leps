/**
 * The single client-side store.
 *
 * ONE SNAPSHOT, SELECTOR-SCOPED READS
 * -----------------------------------
 * The backend publishes a complete snapshot 4x a second. Holding that in React
 * context and consuming it whole would re-render the entire tree on every
 * poll -- 40+ components recomputing because one proximity bit flipped.
 *
 * Zustand lets each component subscribe to just the slice it draws:
 *
 *     const sensors = useMachine(s => s.snapshot?.sensors)
 *
 * That component re-renders only when `sensors` changes identity. The store is
 * the only place the snapshot lives, so there is no duplicated state to drift.
 *
 * `lastGoodAt` is tracked separately from the snapshot timestamp so the UI can
 * distinguish "the backend is alive but the PLC is stale" from "the backend
 * itself has gone away" -- two very different problems with the same symptom.
 */

import { create } from 'zustand'
import type { CommandEntry, MachineMode, Snapshot } from '../types'
import type { LinkState } from '../services/realtime'

export interface Toast {
  id: number
  kind: 'ok' | 'warn' | 'error'
  title: string
  detail?: string
  at: number
}

interface MachineStore {
  snapshot: Snapshot | null
  link: LinkState
  linkDetail: string
  lastGoodAt: number | null
  toasts: Toast[]
  /** Commands this browser issued, for optimistic display in the command rail. */
  localCommands: CommandEntry[]

  setSnapshot: (snapshot: Snapshot) => void
  setLink: (link: LinkState, detail?: string) => void
  pushToast: (t: Omit<Toast, 'id' | 'at'>) => void
  dismissToast: (id: number) => void
  trackCommand: (cmd: CommandEntry) => void
}

let toastSeq = 0

export const useMachine = create<MachineStore>((set) => ({
  snapshot: null,
  link: 'connecting',
  linkDetail: '',
  lastGoodAt: null,
  toasts: [],
  localCommands: [],

  setSnapshot: (snapshot) =>
    set({ snapshot, lastGoodAt: Date.now() }),

  setLink: (link, detail = '') => set({ link, linkDetail: detail }),

  pushToast: (t) =>
    set((s) => ({
      toasts: [...s.toasts, { ...t, id: ++toastSeq, at: Date.now() }].slice(-5),
    })),

  dismissToast: (id) =>
    set((s) => ({ toasts: s.toasts.filter((t) => t.id !== id) })),

  trackCommand: (cmd) =>
    set((s) => ({ localCommands: [cmd, ...s.localCommands].slice(0, 40) })),
}))

// ---------------------------------------------------------------------------
// selectors -- exported so components share one definition and one identity
// ---------------------------------------------------------------------------

export const selectConnection = (s: MachineStore) => s.snapshot?.connection
export const selectMachine = (s: MachineStore) => s.snapshot?.machine
export const selectSafety = (s: MachineStore) => s.snapshot?.safety
export const selectSequence = (s: MachineStore) => s.snapshot?.sequence
export const selectSensors = (s: MachineStore) => s.snapshot?.sensors
export const selectActuators = (s: MachineStore) => s.snapshot?.actuators
export const selectConveyors = (s: MachineStore) => s.snapshot?.conveyors
export const selectInventory = (s: MachineStore) => s.snapshot?.inventory
export const selectDiagnostics = (s: MachineStore) => s.snapshot?.diagnostics
export const selectTwin = (s: MachineStore) => s.snapshot?.digitalTwin
export const selectCamera = (s: MachineStore) => s.snapshot?.camera
export const selectEvents = (s: MachineStore) => s.snapshot?.events
export const selectMode = (s: MachineStore): MachineMode =>
  s.snapshot?.machine.mode ?? 'AUTO'

/**
 * True when the values on screen should be rendered as stale.
 *
 * Two independent conditions, because they fail independently: the PLC link
 * can drop while the backend is fine, and the backend can die while the PLC is
 * fine. Either one makes the numbers untrustworthy.
 */
export const selectStale = (s: MachineStore): boolean => {
  if (s.link !== 'open' && s.link !== 'connecting') return true
  if (!s.snapshot) return true
  return s.snapshot.connection.stale
}
