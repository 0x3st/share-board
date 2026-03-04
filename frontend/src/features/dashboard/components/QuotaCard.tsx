import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Progress } from '@/components/ui/progress'
import { Skeleton } from '@/components/ui/skeleton'

interface QuotaCardProps {
  currentUsage: number
  totalQuota: number
  isLoading?: boolean
}

function getHealthColor(percentage: number): string {
  if (percentage < 70) return 'text-green-500'
  if (percentage < 90) return 'text-yellow-500'
  return 'text-red-500'
}

function getProgressColor(percentage: number): string {
  if (percentage < 70) return 'bg-green-500'
  if (percentage < 90) return 'bg-yellow-500'
  return 'bg-red-500'
}

function formatBytes(bytes: number): string {
  if (bytes === 0) return '0 B'
  const k = 1024
  const sizes = ['B', 'KB', 'MB', 'GB', 'TB']
  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return `${(bytes / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`
}

export function QuotaCard({ currentUsage, totalQuota, isLoading }: QuotaCardProps) {
  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>流量配额</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Skeleton className="h-4 w-full" />
          <Skeleton className="h-4 w-32" />
        </CardContent>
      </Card>
    )
  }

  const percentage = totalQuota > 0 ? (currentUsage / totalQuota) * 100 : 0
  const healthColor = getHealthColor(percentage)
  const progressColor = getProgressColor(percentage)

  return (
    <Card>
      <CardHeader>
        <CardTitle>流量配额</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <div className="flex justify-between text-sm">
            <span className="text-muted-foreground">已使用</span>
            <span className={healthColor}>
              {formatBytes(currentUsage)} / {formatBytes(totalQuota)}
            </span>
          </div>
          <Progress
            value={currentUsage}
            max={totalQuota}
            indicatorClassName={progressColor}
          />
        </div>
        <div className="flex justify-between text-sm">
          <span className="text-muted-foreground">使用率</span>
          <span className={healthColor}>{percentage.toFixed(1)}%</span>
        </div>
      </CardContent>
    </Card>
  )
}
