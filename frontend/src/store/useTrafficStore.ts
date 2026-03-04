import { create } from 'zustand'

interface TrafficState {
  currentUsage: number
  realtimeSpeed: number
  lastUpdated: number | null
  isPolling: boolean
  pollingInterval: number | null
  startPolling: () => void
  stopPolling: () => void
  fetchTrafficData: () => Promise<void>
}

export const useTrafficStore = create<TrafficState>((set, get) => ({
  currentUsage: 0,
  realtimeSpeed: 0,
  lastUpdated: null,
  isPolling: false,
  pollingInterval: null,

  fetchTrafficData: async () => {
    try {
      const token = localStorage.getItem('token')
      if (!token) return

      const response = await fetch('/api/v1/traffic/current', {
        headers: {
          'Authorization': `Bearer ${token}`,
        },
      })

      if (!response.ok) {
        throw new Error('Failed to fetch traffic data')
      }

      const data = await response.json()
      set({
        currentUsage: data.current_usage || 0,
        realtimeSpeed: data.realtime_speed || 0,
        lastUpdated: Date.now(),
      })
    } catch (error) {
      console.error('Failed to fetch traffic data:', error)
    }
  },

  startPolling: () => {
    const { isPolling, fetchTrafficData } = get()
    if (isPolling) return

    fetchTrafficData()

    const interval = window.setInterval(() => {
      fetchTrafficData()
    }, 5000)

    set({
      isPolling: true,
      pollingInterval: interval,
    })
  },

  stopPolling: () => {
    const { pollingInterval } = get()
    if (pollingInterval) {
      clearInterval(pollingInterval)
    }
    set({
      isPolling: false,
      pollingInterval: null,
    })
  },
}))
