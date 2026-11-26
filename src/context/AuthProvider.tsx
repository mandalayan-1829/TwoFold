import {
    useEffect,
    useState,
    type ReactNode,
} from 'react'
import type { Session } from '@supabase/supabase-js'
import { AuthContext } from './AuthContext'
import { supabase } from '../lib/supabase'

interface AuthProviderProps {
    children: ReactNode
}

export function AuthProvider({ children }: AuthProviderProps) {
    const [session, setSession] = useState<Session | null>(null)
    const [loading, setLoading] = useState(true)

    useEffect(() => {
        let mounted = true

        const {
            data: { subscription },
        } = supabase.auth.onAuthStateChange((_event, currentSession) => {
            if (!mounted) return

            setSession(currentSession)
            setLoading(false)
        })

        supabase.auth
            .getSession()
            .then(({ data, error }) => {
                if (!mounted) return

                if (error) {
                    console.error('Unable to retrieve authentication session.')
                    setSession(null)
                } else {
                    setSession(data.session)
                }

                setLoading(false)
            })
            .catch(() => {
                if (!mounted) return

                console.error('Authentication session initialisation failed.')
                setSession(null)
                setLoading(false)
            })

        return () => {
            mounted = false
            subscription.unsubscribe()
        }
    }, [])

    const value = {
        user: session?.user ?? null,
        session,
        loading,
        isAuthenticated: Boolean(session?.user),
    }

    return (
        <AuthContext.Provider value={value}>
            {children}
        </AuthContext.Provider>
    )
}