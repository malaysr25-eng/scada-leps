/**
 * The 40-step sequence catalogue.
 *
 * Fetched once and cached in a module-level promise: it is static reference
 * data derived from factory_states.m and the Sequencing sheet, so re-fetching
 * it per page mount would be pure waste.
 */

import { useEffect, useState } from 'react'
import { api } from '../services/api'
import type { SequenceStep } from '../types'

let cache: Promise<SequenceStep[]> | null = null

function fetchCatalogue(): Promise<SequenceStep[]> {
  if (!cache) {
    cache = api.sequence().then((res) =>
      res.ok ? ((res.data.catalogue ?? []) as SequenceStep[]) : [],
    )
  }
  return cache
}

export function useSequenceCatalogue(): SequenceStep[] {
  const [steps, setSteps] = useState<SequenceStep[]>([])

  useEffect(() => {
    let cancelled = false
    void fetchCatalogue().then((s) => {
      if (!cancelled) setSteps(s)
    })
    return () => {
      cancelled = true
    }
  }, [])

  return steps
}
