import { useState, type FormEvent } from 'react'
import { Navigate, useLocation, useNavigate } from 'react-router-dom'
import { Eye, EyeOff, Heart } from 'lucide-react'

import { Container } from '../components/layout/Container'
import { Spinner } from '../components/ui/Spinner'
import { Button } from '../components/ui/Button'
import { Input } from '../components/ui/Input'
import {
  Alert,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from '../components/ui'

import { useAuth } from '../hooks/useAuth'
import { supabase } from '../lib/supabase'

import '../styles/foundation.css'

export function LoginPage() {
  const { isAuthenticated, loading: authLoading } = useAuth()

  const navigate = useNavigate()
  const location = useLocation()

  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [showPassword, setShowPassword] = useState(false)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')

  const requestedPath = location.state?.from?.pathname

  const from =
    typeof requestedPath === 'string' &&
      requestedPath.startsWith('/') &&
      !requestedPath.startsWith('//') &&
      requestedPath !== '/login'
      ? requestedPath
      : '/'

  if (authLoading) {
    return (
      <main className="tf-foundation">
        <Spinner
          size="lg"
          label="Checking your session"
          showLabel
        />
      </main>
    )
  }

  if (isAuthenticated) {
    return <Navigate to="/" replace />
  }

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault()

    setError('')
    setSubmitting(true)

    try {
      const { error: signInError } =
        await supabase.auth.signInWithPassword({
          email: email.trim(),
          password,
        })

      if (signInError) {
        setError('Invalid email or password. Please try again.')
        return
      }

      navigate(from, { replace: true })
    } catch {
      setError('Unable to sign in right now. Please try again.')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <main className="tf-foundation">
      <Container size="sm">
        <Card as="section" padding="lg">
          <CardHeader>
            <p className="tf-foundation__eyebrow">
              <Heart size={14} aria-hidden="true" />
              <span>Private Space</span>
            </p>

            <CardTitle>Welcome to TwoFold</CardTitle>

            <CardDescription>
              Your little universe is waiting.
            </CardDescription>
          </CardHeader>

          <CardContent>
            {error && (
              <Alert variant="error" title="Sign-in failed">
                {error}
              </Alert>
            )}

            <form onSubmit={handleSubmit}>
              <Input
                label="Email address"
                type="email"
                autoComplete="email"
                placeholder="Enter your email"
                value={email}
                onChange={(event) => setEmail(event.target.value)}
                required
              />

              <div>
                <Input
                  label="Password"
                  type={showPassword ? 'text' : 'password'}
                  autoComplete="current-password"
                  placeholder="Enter your password"
                  value={password}
                  onChange={(event) => setPassword(event.target.value)}
                  required
                />

                <Button
                  type="button"
                  variant="ghost"
                  size="sm"
                  onClick={() =>
                    setShowPassword((current) => !current)
                  }
                  aria-label={
                    showPassword ? 'Hide password' : 'Show password'
                  }
                >
                  {showPassword ? (
                    <EyeOff size={16} />
                  ) : (
                    <Eye size={16} />
                  )}
                </Button>
              </div>

              <Button
                type="submit"
                fullWidth
                loading={submitting}
                loadingText="Signing in..."
                disabled={!email.trim() || !password}
              >
                Sign in
              </Button>
            </form>
          </CardContent>
        </Card>
      </Container>
    </main>
  )
}