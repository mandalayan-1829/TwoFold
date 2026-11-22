import type { ComponentPropsWithRef, ReactNode } from 'react'
import { cn } from '../../lib/cn'
import type { ButtonSize, ButtonVariant } from '../../types/ui'
import { Spinner } from './Spinner'
import './Button.css'

export interface ButtonProps extends ComponentPropsWithRef<'button'> {
  variant?: ButtonVariant
  size?: ButtonSize
  fullWidth?: boolean
  loading?: boolean
  loadingText?: string
  leftIcon?: ReactNode
  rightIcon?: ReactNode
}

export function Button({
  type = 'button',
  variant = 'primary',
  size = 'md',
  fullWidth = false,
  loading = false,
  loadingText,
  leftIcon,
  rightIcon,
  disabled,
  className,
  children,
  ...props
}: ButtonProps) {
  const isDisabled = Boolean(disabled || loading)

  return (
    <button
      type={type}
      disabled={isDisabled}
      aria-busy={loading || undefined}
      className={cn(
        'tf-btn',
        `tf-btn--${variant}`,
        `tf-btn--${size}`,
        fullWidth && 'tf-btn--full',
        className,
      )}
      {...props}
    >
      {loading ? (
        <Spinner size="sm" label={loadingText ?? 'Working'} />
      ) : (
        leftIcon && (
          <span className="tf-btn__icon" aria-hidden="true">
            {leftIcon}
          </span>
        )
      )}
      <span>{loading && loadingText ? loadingText : children}</span>
      {!loading && rightIcon && (
        <span className="tf-btn__icon" aria-hidden="true">
          {rightIcon}
        </span>
      )}
    </button>
  )
}
