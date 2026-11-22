import type { ComponentPropsWithRef, ReactNode } from 'react'
import {
  AlertCircle,
  AlertTriangle,
  CheckCircle2,
  Info,
  X,
} from 'lucide-react'
import { cn } from '../../lib/cn'
import type { AlertVariant } from '../../types/ui'
import './Alert.css'

export interface AlertProps extends ComponentPropsWithRef<'div'> {
  variant?: AlertVariant
  title?: string
  onDismiss?: () => void
  children: ReactNode
}

const ALERT_ICONS: Record<AlertVariant, typeof Info> = {
  info: Info,
  success: CheckCircle2,
  warning: AlertTriangle,
  error: AlertCircle,
}

export function Alert({
  variant = 'info',
  title,
  onDismiss,
  className,
  children,
  ...props
}: AlertProps) {
  const Icon = ALERT_ICONS[variant]
  const isUrgent = variant === 'error' || variant === 'warning'

  return (
    <div
      role={isUrgent ? 'alert' : 'status'}
      aria-live={isUrgent ? 'assertive' : 'polite'}
      className={cn('tf-alert', `tf-alert--${variant}`, className)}
      {...props}
    >
      <span className="tf-alert__icon" aria-hidden="true">
        <Icon size={18} strokeWidth={2} />
      </span>

      <div className="tf-alert__body">
        {title && <p className="tf-alert__title">{title}</p>}
        <div className="tf-alert__message">{children}</div>
      </div>

      {onDismiss && (
        <button
          type="button"
          className="tf-alert__dismiss"
          onClick={onDismiss}
          aria-label="Dismiss message"
        >
          <X size={16} aria-hidden="true" />
        </button>
      )}
    </div>
  )
}
