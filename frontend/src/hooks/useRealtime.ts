/**
 * Opens exactly one SSE connection for the whole application.
 *
 * Mounted once in App. Every component then reads from the store, so there is
 * one stream, one snapshot and no per-component polling -- the thing the old
 * dashboards got wrong in both directions at once (the SCADA page polled a
 * file every 2 s, while the PLC dashboard polled the backend every 1 s).
 */

import { useEffect } from 'react'
import { RealtimeClient } from '../services/realtime'
import { useMachine } from '../stores/machineStore'

export function useRealtime(): void {
  useEffect(() => {
    const { setSnapshot, setLink } = useMachine.getState()

    const client = new RealtimeClient({
      onSnapshot: setSnapshot,
      onLinkState: setLink,
    })

    client.start()
    return () => client.stop()
  }, [])
}
