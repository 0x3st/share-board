import { Link, Outlet, useLocation } from 'react-router-dom'

export default function MainLayout() {
  const location = useLocation()

  const isActive = (path: string) => {
    return location.pathname === path
  }

  const navLinkClass = (path: string) => {
    const base = 'px-3 py-2 rounded-md text-sm font-medium transition-colors'
    if (isActive(path)) {
      return base + ' bg-primary text-primary-foreground'
    }
    return base + ' text-muted-foreground hover:bg-accent hover:text-accent-foreground'
  }

  return (
    <div className="min-h-screen bg-background">
      <nav className="border-b">
        <div className="container mx-auto px-4 py-4">
          <div className="flex items-center justify-between">
            <div className="flex items-center space-x-8">
              <h1 className="text-xl font-bold">FQ System</h1>
              <div className="flex space-x-4">
                <Link to="/dashboard" className={navLinkClass('/dashboard')}>
                  Dashboard
                </Link>
                <Link to="/billing" className={navLinkClass('/billing')}>
                  Billing
                </Link>
              </div>
            </div>
          </div>
        </div>
      </nav>
      <main className="container mx-auto px-4 py-8">
        <Outlet />
      </main>
    </div>
  )
}
