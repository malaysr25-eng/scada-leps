import { NavLink } from 'react-router-dom'
import {
  Bot, Box, Boxes, Bug, Database, Gauge, HardDriveDownload, LayoutDashboard,
  ListOrdered, Sliders, Tags,
} from 'lucide-react'
import { selectDiagnostics, useMachine } from '../../stores/machineStore'
import { classNames } from '../../utils/format'

const ITEMS = [
  { to: '/', label: 'Overview', icon: LayoutDashboard, end: true },
  { to: '/assistant', label: 'LEPS', icon: Bot },
  { to: '/factory', label: 'Factory', icon: Boxes },
  { to: '/machine3d', label: 'Machine 3D', icon: Box },
  { to: '/sequence', label: 'Sequence', icon: ListOrdered },
  { to: '/manual', label: 'Manual', icon: Sliders },
  { to: '/diagnostics', label: 'Diagnostics', icon: Bug },
  { to: '/twin', label: 'Digital Twin', icon: Gauge },
  { to: '/data', label: 'Data', icon: HardDriveDownload },
  { to: '/history', label: 'History', icon: Database },
  { to: '/tags', label: 'Tags', icon: Tags },
]

export function NavRail() {
  const diagnostics = useMachine(selectDiagnostics)
  const faultCount = diagnostics?.activeFaults.length ?? 0

  return (
    <nav className="flex w-[84px] shrink-0 flex-col gap-1 overflow-y-auto border-r border-panel-700 bg-panel-900 py-3">
      {ITEMS.map(({ to, label, icon: Icon, end }) => (
        <NavLink
          key={to}
          to={to}
          end={end}
          className={({ isActive }) =>
            classNames(
              'relative mx-1.5 flex flex-col items-center gap-1 rounded-lg px-1 py-2',
              'text-xs font-medium transition-colors',
              isActive
                ? 'bg-state-info/12 text-state-info'
                : 'text-ink-400 hover:bg-panel-800 hover:text-ink-200',
            )
          }
        >
          {({ isActive }) => (
            <>
              {isActive && (
                <span className="absolute left-0 top-1/2 h-6 w-0.5 -translate-y-1/2 rounded-r bg-state-info" />
              )}
              <span className="relative">
                <Icon size={19} strokeWidth={1.9} />
                {label === 'Diagnostics' && faultCount > 0 && (
                  <span className="absolute -right-2 -top-1.5 grid h-4 min-w-4 place-items-center rounded-full bg-state-fault px-1 text-xs font-bold text-panel-950">
                    {faultCount}
                  </span>
                )}
              </span>
              <span className="text-center leading-tight">{label}</span>
            </>
          )}
        </NavLink>
      ))}
    </nav>
  )
}
