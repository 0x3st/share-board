import { useEffect, useState } from 'react'
import { useTrafficStore } from '../store/useTrafficStore'
import { usePolling } from '../hooks/usePolling'

function formatRelativeTime(timestamp: number | null): string {
  if (!timestamp) return '从未更新'

  const seconds = Math.floor((Date.now() - timestamp) / 1000)

  if (seconds < 10) return '刚刚'
  if (seconds < 60) return `${seconds}秒前`

  const minutes = Math.floor(seconds / 60)
  if (minutes < 60) return `${minutes}分钟前`

  const hours = Math.floor(minutes / 60)
  if (hours < 24) return `${hours}小时前`

  const days = Math.floor(hours / 24)
  return `${days}天前`
}

export default function DashboardPage() {
  const { currentUsage, realtimeSpeed, lastUpdated, fetchTrafficData } = useTrafficStore()
  const [relativeTime, setRelativeTime] = useState('')

  usePolling(fetchTrafficData, { interval: 5000 })

  useEffect(() => {
    setRelativeTime(formatRelativeTime(lastUpdated))
    const timer = setInterval(() => {
      setRelativeTime(formatRelativeTime(lastUpdated))
    }, 1000)
    return () => clearInterval(timer)
  }, [lastUpdated])

  return (
    <div className="space-y-6">
      <div className="flex justify-between items-center">
        <h1 className="text-3xl font-bold">Dashboard</h1>
        <span className="text-sm text-muted-foreground">
          最后更新: {relativeTime}
        </span>
      </div>

      <div className="grid gap-4 md:grid-cols-2">
        <div className="rounded-lg border bg-card p-6 transition-all duration-300">
          <h3 className="text-sm font-medium text-muted-foreground">当前用量</h3>
          <p className="mt-2 text-3xl font-bold">{(currentUsage / 1024 / 1024 / 1024).toFixed(2)} GB</p>
        </div>

        <div className="rounded-lg border bg-card p-6 transition-all duration-300">
          <h3 className="text-sm font-medium text-muted-foreground">实时速度</h3>
          <p className="mt-2 text-3xl font-bold">{(realtimeSpeed / 1024 / 1024).toFixed(2)} MB/s</p>
        </div>
      </div>
    </div>
  )
}
