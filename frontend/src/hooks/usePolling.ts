import { useEffect, useRef, useState } from 'react'

interface UsePollingOptions {
  interval?: number
  enabled?: boolean
}

export function usePolling(
  callback: () => void | Promise<void>,
  { interval = 5000, enabled = true }: UsePollingOptions = {}
) {
  const [isPolling, setIsPolling] = useState(false)
  const callbackRef = useRef(callback)
  const intervalRef = useRef<number | null>(null)

  useEffect(() => {
    callbackRef.current = callback
  }, [callback])

  useEffect(() => {
    if (!enabled) {
      if (intervalRef.current) {
        clearInterval(intervalRef.current)
        intervalRef.current = null
        setIsPolling(false)
      }
      return
    }

    const handleVisibilityChange = () => {
      if (document.visibilityState === 'visible') {
        if (!intervalRef.current) {
          callbackRef.current()
          intervalRef.current = window.setInterval(() => {
            callbackRef.current()
          }, interval)
          setIsPolling(true)
        }
      } else {
        if (intervalRef.current) {
          clearInterval(intervalRef.current)
          intervalRef.current = null
          setIsPolling(false)
        }
      }
    }

    if (document.visibilityState === 'visible') {
      callbackRef.current()
      intervalRef.current = window.setInterval(() => {
        callbackRef.current()
      }, interval)
      setIsPolling(true)
    }

    document.addEventListener('visibilitychange', handleVisibilityChange)

    return () => {
      if (intervalRef.current) {
        clearInterval(intervalRef.current)
      }
      document.removeEventListener('visibilitychange', handleVisibilityChange)
      setIsPolling(false)
    }
  }, [interval, enabled])

  return { isPolling }
}
