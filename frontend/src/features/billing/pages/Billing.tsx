import { useEffect, useState } from 'react'
import { CostSharingCard } from '../components/CostSharingCard'
import { TransactionLedger } from '../components/TransactionLedger'
import axiosInstance from '@/lib/axios'

interface BillingData {
  totalCost: number
  personalShare: number
  trafficRatio: number
  transactions: Array<{
    id: string
    date: string
    operation: string
    traffic: number
    amount: number
  }>
}

export default function Billing() {
  const [data, setData] = useState<BillingData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  useEffect(() => {
    const fetchBillingData = async () => {
      try {
        setLoading(true)
        const response = await axiosInstance.get<BillingData>('/billing/cost-sharing')
        setData(response.data)
        setError(null)
      } catch (err) {
        setError('加载账单数据失败')
        console.error('Failed to fetch billing data:', err)
      } finally {
        setLoading(false)
      }
    }

    fetchBillingData()
  }, [])

  if (error) {
    return (
      <div className="space-y-6">
        <h1 className="text-3xl font-bold">账单</h1>
        <div className="rounded-lg border border-destructive bg-destructive/10 p-4 text-destructive">
          {error}
        </div>
      </div>
    )
  }

  return (
    <div className="space-y-6">
      <h1 className="text-3xl font-bold">账单</h1>

      <div className="grid gap-6 md:grid-cols-3">
        <div className="md:col-span-1">
          <CostSharingCard
            totalCost={data?.totalCost ?? 0}
            personalShare={data?.personalShare ?? 0}
            trafficRatio={data?.trafficRatio ?? 0}
            loading={loading}
          />
        </div>

        <div className="md:col-span-2">
          <TransactionLedger
            transactions={data?.transactions ?? []}
            loading={loading}
          />
        </div>
      </div>
    </div>
  )
}
