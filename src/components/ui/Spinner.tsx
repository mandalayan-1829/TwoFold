import type { ComponentPropsWithRef } from 'react'
import { cn } from '../../lib/cn'
import type { SpinnerSize } from '../../types/ui'
import './Spinner.css'

export interface SpinnerProps extends ComponentPropsWithRef<'span'> {
  size?: SpinnerSize
  label?: string
  showLabel?: boolean
}

export function Spinner({
  size = 'md',
  label = 'Loading',
  showLabel = false,
  className,
  ...props
}: SpinnerProps) {
  return (
    <span
      role="status"
      aria-live="polite"
      className={cn('tf-spinner', `tf-spinner--${size}`, className)}
      {...props}
    >
      <span className="tf-spinner__ring" aria-hidden="true" />
      <span className={showLabel ? 'tf-spinner__label' : 'sr-only'}>
        {label}
      </span>
    </span>
  )
}
