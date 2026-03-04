import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from '@/components/ui/dialog'

interface CostSharingCardProps {
  totalCost: number
  personalShare: number
  trafficRatio: number
  loading?: boolean
}

export function CostSharingCard({
  totalCost,
  personalShare,
  trafficRatio,
  loading = false,
}: CostSharingCardProps) {
  if (loading) {
    return (
      <Card>
        <CardHeader>
          <CardTitle>成本分摊</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="h-8 bg-muted animate-pulse rounded" />
          <div className="h-8 bg-muted animate-pulse rounded" />
          <div className="h-8 bg-muted animate-pulse rounded" />
        </CardContent>
      </Card>
    )
  }

  return (
    <Card>
      <CardHeader>
        <CardTitle>成本分摊</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-2">
          <div className="text-sm text-muted-foreground">本月总支出</div>
          <div className="text-2xl font-bold">¥{totalCost.toFixed(2)}</div>
        </div>

        <div className="space-y-2">
          <div className="text-sm text-muted-foreground">个人分摊金额</div>
          <div className="text-2xl font-bold text-primary">
            ¥{personalShare.toFixed(2)}
          </div>
        </div>

        <div className="space-y-2">
          <div className="text-sm text-muted-foreground">流量占比</div>
          <div className="text-xl font-semibold">
            {(trafficRatio * 100).toFixed(2)}%
          </div>
        </div>

        <Dialog>
          <DialogTrigger asChild>
            <Button variant="outline" className="w-full">
              查看计算公式
            </Button>
          </DialogTrigger>
          <DialogContent>
            <DialogHeader>
              <DialogTitle>成本分摊计算公式</DialogTitle>
              <DialogDescription>
                基于流量占比的公平分摊机制
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-4 py-4">
              <div className="rounded-lg bg-muted p-4">
                <div className="font-mono text-sm">
                  个人分摊 = 总成本 × (个人流量 / 总流量)
                </div>
              </div>
              <div className="space-y-2 text-sm">
                <div className="flex justify-between">
                  <span className="text-muted-foreground">总成本:</span>
                  <span className="font-medium">¥{totalCost.toFixed(2)}</span>
                </div>
                <div className="flex justify-between">
                  <span className="text-muted-foreground">流量占比:</span>
                  <span className="font-medium">
                    {(trafficRatio * 100).toFixed(2)}%
                  </span>
                </div>
                <div className="flex justify-between border-t pt-2">
                  <span className="text-muted-foreground">个人分摊:</span>
                  <span className="font-bold text-primary">
                    ¥{personalShare.toFixed(2)}
                  </span>
                </div>
              </div>
            </div>
          </DialogContent>
        </Dialog>
      </CardContent>
    </Card>
  )
}
