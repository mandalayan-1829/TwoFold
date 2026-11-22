import { Heart, ShieldCheck } from 'lucide-react'
import { Container } from './components/layout/Container'
import {
  Alert,
  Card,
  CardContent,
  CardDescription,
  CardHeader,
  CardTitle,
} from './components/ui'
import './styles/foundation.css'

function App() {
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
              <CardTitle>Design System Foundation Ready</CardTitle>
              <CardDescription>
                Milestone 1 — Task 1.2 complete. Visual tokens, accessible UI
                primitives, and modular architecture are in place.
              </CardDescription>
            </CardHeader>
            <CardContent>
              <p className="tf-foundation__lead">
                Database schema migrations, Row Level Security policies, private
                storage rules, and Supabase authentication will be connected in
                the upcoming tasks.
              </p>

              <Alert variant="info" title="Backend Not Yet Connected">
                No authentication or data storage is active yet. Private routes
                and couple data will only be enabled after PostgreSQL RLS and
                Storage policies are verified.
              </Alert>

              <p className="tf-foundation__eyebrow">
                <ShieldCheck size={15} aria-hidden="true" />
                <span>Default-Deny Security Architecture</span>
              </p>
            </CardContent>
          </Card>
        </div>
      </Container>
    </main>
  )
}

export default App
