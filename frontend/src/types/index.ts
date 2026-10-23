/**
 * The wire contract between the backend snapshot and the UI.
 *
 * These types mirror `backend/core.py::Core._compose` exactly. When the
 * backend snapshot changes, change it here first -- `tsc` will then point at
 * every component that needs updating, which is the whole reason the frontend
 * is typed.
 *
 * A note on `boolean | null`: almost every PLC-derived value is nullable, and
 * the null is meaningful. `null` means "we have no value for this" -- the tag
 * is missing from the registry, or no poll has succeeded yet. It is NOT the
 * same as `false`. Rendering an unknown sensor as OFF is how an HMI quietly
 * lies to an operator, so the types force every consumer to handle the three
 * cases.
 */

export type Tri = boolean | null

// ---------------------------------------------------------------------------
// connection
// ---------------------------------------------------------------------------

export type PlcConnection =
  | 'DISCONNECTED'
  | 'CONNECTING'
  | 'CONNECTED'
  | 'DEGRADED'
  | 'RECONNECTING'
  | 'SIMULATED'

export type ServiceConnection = 'CONNECTED' | 'DEGRADED' | 'DISCONNECTED'
export type CameraStatus = 'ONLINE' | 'OFFLINE' | 'STALE' | 'DEGRADED'

export interface PlcHealth {
  lastSuccess: number | null
  lastAttempt: number | null
  lastError: string
  latencyMs: number
  latencyAvgMs: number
  pollCount: number
  errorCount: number
  reconnectCount: number
  consecutiveErrors: number
}

export interface ConnectionState {
  plc: PlcConnection
  plcSimulated: boolean
  plcHealth: PlcHealth
  staleSeconds: number | null
  staleBudgetSeconds: number
  stale: boolean
  camera: CameraStatus
  digitalTwin: ServiceConnection
}

// ---------------------------------------------------------------------------
// machine
// ---------------------------------------------------------------------------

export type MachineMode = 'AUTO' | 'MANUAL' | 'MAINTENANCE'

export type Lifecycle =
  | 'DISCONNECTED'
  | 'EMERGENCY_STOPPED'
  | 'FAULT'
  | 'RECOVERY_REQUIRED'
  | 'RESETTING'
  | 'IDLE'
  | 'READY'
  | 'STARTING'
  | 'AUTO_RUNNING'
  | 'COMPLETED'
  | 'MANUAL_MODE'
  | 'MAINTENANCE'

export interface FrozenContext {
  reason: string
  at: number
  lifecycle: string
  mode: string
  cycleId: string | null
  sequenceStepIndex: number
  sequenceStepName: string | null
  waitingFor: string | null
  sensors: Record<string, Tri>
  valves: Record<string, Tri>
  conveyors: Record<string, unknown>
  safety: Record<string, Tri>
}

export interface MachineState {
  mode: MachineMode
  lifecycle: Lifecycle
  previousLifecycle: Lifecycle
  lifecycleSince: number
  lifecycleElapsed: number
  cycleId: string | null
  cycleStartedAt: number | null
  cycleEndedAt: number | null
  cycleCount: number
  cycleElapsed: number | null
  frozenContext: FrozenContext | null
}

export interface ModeInfo {
  mode: MachineMode
  permits: string[]
  description: string
}

export interface SafetyState {
  hardwareEmergencyHealthy: Tri
  emergencyInputActive: Tri
  emergencyActive: boolean
  startupHealthy: Tri
  airPressureHealthy: Tri
  allCylindersHome: Tri
  engravingPlateHome: Tri
  pressureLowAlarm: Tri
  pressureHighAlarm: Tri
  pressureBar: number | null
  note: string
}

export interface ChecklistItem {
  key: string
  label: string
  role: string | null
  satisfied: Tri
  required: boolean
  detail: string
}

export interface CanStart {
  allowed: boolean
  reasons: string[]
  orderValid: boolean
  orderReason: string
  interlocksSatisfied: boolean
  plcQty25: number
  plcQty50: number
}

// ---------------------------------------------------------------------------
// sequence
// ---------------------------------------------------------------------------

export type GuardKind =
  | 'sensor'
  | 'immediate'
  | 'timer'
  | 'operator'
  | 'unobservable'
  | 'external'

export interface SequenceStep {
  index: number
  key: string
  name: string
  excelRef: string
  station: string
  guardKind: GuardKind
  guardLabel: string
  guardRole: string | null
  guardExpect: boolean
  twinState: string | null
  implicit: boolean
  anomaly: string
  observable: boolean
  typicalSeconds: number | null
  guardSemantics: 'edge' | 'level'
}

export interface SequenceHistoryEntry {
  stepIndex: number
  name: string
  at: number
  guard: string
}

export interface SequenceState {
  stepIndex: number
  step: SequenceStep | null
  confidence: 'none' | 'low' | 'inferred'
  inferred: boolean
  enteredAt: number
  elapsedSeconds: number
  waitingFor: string | null
  waitingRole: string | null
  waitingSince: number | null
  timeoutSeconds: number
  stalled: boolean
  awaitingOperator: boolean
  lastConfirmedStep: number | null
  lastConfirmedAt: number | null
  history: SequenceHistoryEntry[]
}

// ---------------------------------------------------------------------------
// devices
// ---------------------------------------------------------------------------

export interface SensorView {
  role: string
  tagId: string
  label: string
  kind: 'proximity' | 'limit'
  address: string
  description: string
  value: Tri
  lastChangeAt: number | null
  lastChangeFrom: Tri
  transitions: number
}

export interface ActuatorView {
  index: number
  label: string
  stateRole: string
  stateTagId: string
  stateAddress: string
  state: Tri
  manualRole: string
  manualTagId: string | null
  manualAddress: string | null
  manualCommand: Tri
  lastChangeAt: number | null
  transitions: number
  feedback: Tri
  feedbackNote: string
}

/**
 * One writable speed tag, as the backend resolved it from the registry.
 *
 * The UI never spells a conveyor address out itself: the overlay owns which
 * role lives at which address, and `null` here means the registry carries no
 * such tag, so the control is disabled rather than POSTing into the void.
 */
export interface SpeedTagRef {
  tagId: string
  address: string
  unit: string
  /** Commissioned range; null when nobody has configured a limit. */
  min: number | null
  max: number | null
  access: string
}

export interface ConveyorSpeedTags {
  setVelocity: SpeedTagRef | null
  highSpeedVelocity: SpeedTagRef | null
  lowSpeedVelocity: SpeedTagRef | null
  highSpeedSelect: SpeedTagRef | null
}

export interface ConveyorView {
  index: number
  label: string
  running: Tri
  runAddress: string | null
  manualCommand: Tri
  commandedVelocity: number | null
  feedbackVelocity: number | null
  position: number | null
  setPosition: number | null
  highSpeedSelected: Tri
  highSpeedVelocity: number | null
  lowSpeedVelocity: number | null
  highSpeedPosition: number | null
  lowSpeedPosition: number | null
  speedTags: ConveyorSpeedTags
  error: Tri
  homed: Tri
}

// ---------------------------------------------------------------------------
// inventory / products
// ---------------------------------------------------------------------------

export interface MagazineView {
  index: number
  label: string
  cameraCount: number | null
  cameraOnline: boolean
  plcOk: Tri
  plcLow: Tri
  plcEmpty: Tri
  mismatch: string | null
}

export interface CycleToken {
  tokenId: string
  cycleId: string | null
  createdAt: number
  station: string
  stationLabel: string
  positioning: 'CONFIRMED' | 'ESTIMATED' | 'UNKNOWN'
  lastConfirmedStation: string | null
  lastConfirmedAt: number | null
  lastEvent: string
  expectedNext: string
  completedAt: number | null
  productType: string
  identityNote: string
}

export interface InventoryState {
  magazines: MagazineView[]
  order: { qty25: number; qty50: number; total: number; requestedAt: number | null }
  progress: {
    plcTotalProducts: number | null
    requested: number
    remaining: number | null
    source: string
  }
  activeToken: CycleToken | null
  completedTokens: CycleToken[]
  identityLimitation: string
}

// ---------------------------------------------------------------------------
// camera
// ---------------------------------------------------------------------------

export interface DetectedObject {
  class: string
  confidence: number
  bbox: [number, number, number, number]
}

export interface CameraState {
  status: CameraStatus
  online: boolean
  lastFrameAt: number | null
  frameAgeSeconds: number | null
  staleAfterSeconds: number
  lastError: string
  readErrors: number
  totalObjects: number
  confidentObjects: number
  minConfidence: number
  classes: Record<string, number>
  objects: DetectedObject[]
  counts: Record<string, number>
  framePath: string | null
  detectionsPath: string
  note: string
}

// ---------------------------------------------------------------------------
// digital twin
// ---------------------------------------------------------------------------

export type Provenance =
  | 'LIVE' | 'MEA' | 'CAL' | 'JAN' | 'COMM' | 'EST' | 'ASM' | 'PLH' | 'REF'

export interface TwinConveyor {
  index: number
  runOutput: Tri
  commanded: number | null
  commandedProvenance: Provenance | null
  feedback: number | null
  feedbackProvenance: Provenance | null
  predicted: number | null
  predictedProvenance: Provenance | null
  status: 'OK' | 'MISMATCH' | 'DIVERGENT' | 'NO_REFERENCE'
  detail: string
  note?: string
}

export interface TwinSignal {
  key: string
  label: string
  live: number | null
  liveProvenance: Provenance
  predicted: number | null
  predictedProvenance: Provenance
  unit: string
  note: string
}

export interface TwinMismatch {
  key: string
  subject: string
  status: 'MISMATCH' | 'DIVERGENT' | 'LATE'
  detail: string
}

export interface TwinState {
  status: 'LOADED' | 'UNAVAILABLE' | 'ERROR'
  connection: ServiceConnection
  error: string
  loadedAt: number | null
  referencePath: string
  available: boolean
  provenanceLegend: Record<string, { label: string; meaning: string }>
  modelCaveats: string[]
  modelMeta?: Record<string, unknown>
  conveyors: TwinConveyor[]
  signals: TwinSignal[]
  mismatches: TwinMismatch[]
  cycle: {
    realElapsed?: number | null
    nominalCycleTime?: number | null
    predictedState?: string | null
    predictedStateIndex?: number | null
    inferredStepKey?: string | null
    agreement?: 'AGREE' | 'DIVERGENT' | 'UNKNOWN'
    provenance?: Provenance
    provenanceNote?: string
  }
}

// ---------------------------------------------------------------------------
// diagnostics
// ---------------------------------------------------------------------------

export type Severity =
  | 'INFO' | 'COMMAND' | 'PLC' | 'WARNING' | 'FAULT' | 'EMERGENCY'

export interface EventEntry {
  id: number
  at: number
  severity: Severity
  category: string
  message: string
  source: string
  detail: Record<string, unknown>
}

export interface FaultEntry {
  key: string
  severity: Severity
  message: string
  raisedAt: number
  clearedAt: number | null
  active: boolean
  acknowledged: boolean
  occurrences: number
  detail: Record<string, unknown>
}

export interface Finding {
  key: string
  severity: 'WARNING' | 'FAULT'
  title: string
  detail: string
  tagId?: string
  address?: string | null
  count?: number
  commandId?: string
  issueRef?: string
  at: number
}

export interface WatchEntry {
  tagId: string
  label: string
  address: string
  group: string
  dtype: string
  value: unknown
  previous: unknown
  lastChangeAt: number | null
  lastChangeSource: 'operator' | 'plc' | 'contested' | null
  transitions: number
  provenance: 'documented' | 'undocumented'
}

export interface ChangeEntry {
  tagId: string
  previous: unknown
  value: unknown
  at: number
  source: 'operator' | 'plc' | 'contested'
  commandId: string | null
  role: string | null
  short: string
  address: string | null
  group: string | null
}

export interface DiagnosticsState {
  findings: Finding[]
  activeFaults: FaultEntry[]
  watch: WatchEntry[]
  recentChanges: ChangeEntry[]
}

// ---------------------------------------------------------------------------
// commands
// ---------------------------------------------------------------------------

export type CommandState =
  | 'PENDING' | 'WRITTEN' | 'CONFIRMED' | 'MISMATCH'
  | 'TIMEOUT' | 'REJECTED' | 'FAILED'

export interface CommandEntry {
  id: string
  tagId: string
  address: string
  requested: unknown
  observed: unknown
  dtype: string
  source: string
  operator: string
  state: CommandState
  createdAt: number
  writtenAt: number | null
  settledAt: number | null
  latencyMs: number | null
  error: string
}

// ---------------------------------------------------------------------------
// tags
// ---------------------------------------------------------------------------

export type TagAccess =
  | 'read_only' | 'safe_manual' | 'engineering' | 'protected'

export interface TagInfo {
  id: string
  name: string
  short: string
  dtype: 'Bool' | 'Int' | 'Real' | 'DInt' | 'Word'
  db: number
  byte: number
  bit: number
  address: string
  description: string
  group: string
  access: TagAccess
  provenance: 'documented' | 'undocumented'
  role: string | null
  sheet: string
  unit: string
  notes: string
  writable: boolean
  value?: unknown
  updatedAt?: number | null
  lastChangeAt?: number | null
  lastChangeFrom?: unknown
  lastChangeSource?: string | null
  transitions?: number
  watched?: boolean
}


// ===========================================================================
// data sources / operating mode          (added by the data-source extension)
// ===========================================================================

export type SourceKind = 'PLC' | 'SIMULATION' | 'MOCK'

export type SourceState =
  | 'DISCONNECTED' | 'CONNECTING' | 'CONNECTED'
  | 'DEGRADED' | 'RECONNECTING' | 'STOPPED' | 'ERROR'

/** Quality is the field that stops stale data being shown as live. */
export type Quality = 'GOOD' | 'STALE' | 'UNCERTAIN' | 'BAD'

export type SystemMode =
  | 'PLC_CONNECTED' | 'PLC_CONNECTING'
  | 'SIMULATION_RUNNING' | 'SIMULATION_STOPPED'
  | 'DISCONNECTED' | 'ERROR'

export interface SourceInfo {
  sourceId: string
  name: string
  kind: SourceKind
  state: SourceState
  connected: boolean
  running: boolean
  lastDataAt: number | null
  ageSeconds: number | null
  stale: boolean
  staleAfterSeconds: number
  quality: Quality
  lastError: string
  errorCount: number
  reconnectCount: number
  latencyMs: number
  sequence: number
  canControl: boolean
  available: boolean
  unavailableReason: string
  supportsControl: boolean
  controlActive: boolean
  detail: Record<string, unknown>
}

export interface SourceTransition {
  sourceId: string
  name: string
  kind: SourceKind
  allowed: boolean
  reason: string
  isControl: boolean
  isTelemetry: boolean
}

export interface DataSourcesState {
  mode: SystemMode
  controlSourceId: string | null
  controlSourceName: string | null
  telemetrySourceId: string | null
  telemetrySourceName: string | null
  switchCount: number
  sources: SourceInfo[]
  transitions: SourceTransition[]
  lastDataAt: number | null
  quality: Quality
  stale: boolean
  controlQuality: Quality
  canControlHardware: boolean
  note: string
}

// ===========================================================================
// recording / persistence
// ===========================================================================

export interface RecordingSession {
  sessionUid: string
  label: string
  note: string
  operator: string
  startedAt: number
  endedAt: number | null
  durationSeconds: number
  sampleInterval: number
  deadband: number
  tagFilter: string[]
  tagFilterCount: number
  mode: string
  sourceId: string
  sampleCount: number
  droppedCount: number
  status: 'ACTIVE' | 'COMPLETED' | 'ABORTED'
  active: boolean
}

export interface RecordingState {
  recording: boolean
  session: RecordingSession | null
  snapshotCount: number
  lastSnapshotAt: number | null
  limits: { maxSessionSeconds: number; maxSessionSamples: number }
}

export interface DatabaseState {
  enabled: boolean
  ready: boolean
  queueDepth: number
  queueCapacity: number
  written: number
  dropped: number
  errors: number
  healthy: boolean
  lastWriteAt: number | null
  writeMsAvg: number
}

// ===========================================================================
// chat
// ===========================================================================

export interface ChatMessage {
  id: number
  role: 'user' | 'assistant' | 'system'
  text: string
  at: number
  provider: string
  grounded: boolean
  error: string
  contextSummary: {
    systemMode?: string
    lifecycle?: string
    quality?: string
    stale?: boolean
    activeFaults?: number
    at?: number
  }
}

export interface ChatStatus {
  enabled: boolean
  provider: string
  providerAvailable: boolean
  providerReason: string
  requiresNetwork: boolean
  fallbackProvider: string
  providerErrors: number
  lastProviderError: string
  capabilities: {
    readOnly: boolean
    canIssueCommands: boolean
    canBypassSafety: boolean
    note: string
  }
}

// ===========================================================================
// history rows (snake_case: they come straight from SQL)
// ===========================================================================

export interface HistoryEvent {
  id: number; ts: number; severity: string; category: string
  message: string; source: string | null; cycle_id: string | null
  detail?: Record<string, unknown>
}

export interface HistoryAlarm {
  id: number; alarm_key: string; severity: string; message: string
  raised_at: number; cleared_at: number | null; acknowledged: number
  occurrences: number; issue_ref: string | null
}

export interface HistoryCycle {
  id: number; cycle_id: string; started_at: number; ended_at: number | null
  duration_s: number | null; outcome: string | null
  qty_25mm: number | null; qty_50mm: number | null
  products_done: number | null; mode: string | null
  max_step_reached: number | null; fault_count: number; stall_count: number
}

export interface HistorySnapshot {
  id: number; ts: number; label: string; note: string; operator: string
  trigger: string; mode: string; lifecycle: string; cycle_id: string | null
  quality: string | null; payload_bytes: number
}

export interface HistorySummary {
  counts: Record<string, number>
  totalRows: number
  oldestEventAt: number | null
  newestEventAt: number | null
  sizeBytes: number
}

// ---------------------------------------------------------------------------
// the snapshot
// ---------------------------------------------------------------------------

export interface Snapshot {
  schemaVersion: number
  timestamp: number
  uptimeSeconds: number
  connection: ConnectionState
  machine: MachineState
  mode: ModeInfo
  safety: SafetyState
  restartChecklist: ChecklistItem[]
  canStart: CanStart
  sequence: SequenceState
  sensors: SensorView[]
  actuators: ActuatorView[]
  conveyors: ConveyorView[]
  inventory: InventoryState
  camera: CameraState
  digitalTwin: TwinState
  diagnostics: DiagnosticsState
  commands: CommandEntry[]
  inflightCommands: number

  /** Added by the data-source / persistence extension. Always present. */
  dataSources: DataSourcesState
  recording: RecordingState
  database: DatabaseState

  events: EventEntry[]
}

// ---------------------------------------------------------------------------
// API envelopes
// ---------------------------------------------------------------------------

export interface ApiError {
  code: string
  message: string
  [key: string]: unknown
}

export interface ApiOk<T> {
  ok: true
  data: T
  warnings?: string[]
}

export interface ApiFail {
  ok: false
  error: ApiError
}

export type ApiResult<T> = ApiOk<T> | ApiFail
