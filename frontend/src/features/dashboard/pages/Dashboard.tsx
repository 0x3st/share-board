import { useEffect, useState } from 'react'
import { useTrafficStore } from '@/store/useTrafficStore'
import { QuotaCard } from '../components/QuotaCard'
import { RealtimeSpeed } from '../components/RealtimeSpeed'

export function Dashboard() {
  const { currentUsage, realtimeSpeed, startPolling, stopPolling } = useTrafficStore()
  const [isLoading, setIsLoading] = useState(true)

  const totalQuota = 107374182400

  useEffect(() => {
    startPolling()
    const timer = setTimeout(() => setIsLoading(false), 1000)

    return () => {
      stopPolling()
      clearTimeout(timer)
    }
  }, [startPolling, stopPolling])

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">Dashboard</h1>
      <div className="grid gap-6 md:grid-cols-2">
        <QuotaCard
          currentUsage={currentUsage}
          totalQuota={totalQuota}
          isLoading={isLoading}
        />
        <RealtimeSpeed
          uploadSpeed={realtimeSpeed}
          downloadSpeed={realtimeSpeed}
          isLoading={isLoading}
        />
      </div>
    </div>
  )
}
