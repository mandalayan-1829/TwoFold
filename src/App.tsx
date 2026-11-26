import { Navigate, Route, Routes, useNavigate } from 'react-router-dom'
import { Heart, ShieldCheck } from 'lucide-react'
import { ProtectedRoute } from './components/auth/ProtectedRoute'
import { LoginPage } from './pages/LoginPage'
import { Container } from './components/layout/Container'
import { useState } from 'react'
import { Button } from './components/ui/Button'
import { supabase } from './lib/supabase'
import {
  Alert,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from './components/ui'
import './styles/foundation.css'


function HomePage() {
  const navigate = useNavigate()

  const [signingOut, setSigningOut] = useState(false)
  const [signOutError, setSignOutError] = useState('')

  async function handleSignOut() {
    setSigningOut(true)
    setSignOutError('')

    try {
      const { error } = await supabase.auth.signOut()

      if (error) {
        setSignOutError('Unable to sign out. Please try again.')
        return
      }

      navigate('/login', { replace: true })
    } catch {
      setSignOutError('Something went wrong. Please try again.')
    } finally {
      setSigningOut(false)
    }
  }

  return (
    <main className="tf-foundation">
      <Container size="sm">
        <div className="tf-foundation__stack">
          <header>
            <p className="tf-foundation__eyebrow">
              <Heart size={14} aria-hidden="true" />
              <span>Private Space</span>
            </p>
            <h1>TwoFold</h1>
            <p className="tf-foundation__tagline">
              Two Hearts. One Little Universe.
            </p>
          </header>

          <Card as="section" padding="lg">
            <CardHeader>
              <CardTitle>Private Space Protected</CardTitle>
              <CardDescription>
                Authentication and protected routing are being established.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <Alert variant="success" title="Authentication Active">
                You have an authenticated session.
              </Alert>

              <p className="tf-foundation__eyebrow">
                <ShieldCheck size={15} aria-hidden="true" />
                <span>Default-Deny Security Architecture</span>
              </p>
              {signOutError && (
                <Alert variant="error" title="Sign-out failed">
                  {signOutError}
                </Alert>
              )}

              <Button
                variant="secondary"
                fullWidth
                loading={signingOut}
                loadingText="Signing out..."
                onClick={handleSignOut}
              >
                Sign out
              </Button>
            </CardContent>
          </Card>
        </div>
      </Container>
    </main>
  )
}

function App() {
  return (
    <Routes>
      <Route path="/login" element={<LoginPage />} />

      <Route element={<ProtectedRoute />}>
        <Route path="/" element={<HomePage />} />
      </Route>

      <Route path="*" element={<Navigate to="/" replace />} />
    </Routes>
  )
}

export default App