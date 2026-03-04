import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Skeleton } from '@/components/ui/skeleton'

interface RealtimeSpeedProps {
  uploadSpeed: number
  downloadSpeed: number
  isLoading?: boolean
}

function formatSpeed(bytesPerSecond: number): string {
  if (bytesPerSecond === 0) return '0 B/s'
  const k = 1024
  const sizes = ['B/s', 'KB/s', 'MB/s', 'GB/s']
  const i = Math.floor(Math.log(bytesPerSecond) / Math.log(k))
  return `${(bytesPerSecond / Math.pow(k, i)).toFixed(2)} ${sizes[i]}`
}

export function RealtimeSpeed({ uploadSpeed, downloadSpeed, isLoading }: RealtimeSpeedProps) {
  if (isLoading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>实时速率</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <Skeleton className="h-6 w-32" />
          <Skeleton className="h-6 w-32" />
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>实时速率</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="flex justify-between items-center">
          <span className="text-sm text-muted-foreground">上传速率</span>
          <span className="text-lg font-semibold">{formatSpeed(uploadSpeed)}</span>
        </div>
        <div className="flex justify-between items-center">
          <span className="text-sm text-muted-foreground">下载速率</span>
          <span className="text-lg font-semibold">{formatSpeed(downloadSpeed)}</span>
        </div>
      </CardContent>
    </Card>
  )
}
