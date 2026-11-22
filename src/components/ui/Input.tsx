import { useId, type ComponentPropsWithRef } from 'react'
import { cn } from '../../lib/cn'
import type { InputSize } from '../../types/ui'
import './Input.css'

export interface InputProps
  extends Omit<ComponentPropsWithRef<'input'>, 'size'> {
  label: string
  hideLabel?: boolean
  hint?: string
  error?: string
  inputSize?: InputSize
  fullWidth?: boolean
}

export function Input({
  id,
  label,
  hideLabel = false,
  hint,
  error,
  inputSize = 'md',
  fullWidth = true,
  required,
  className,
  ...props
}: InputProps) {
  const generatedId = useId()
  const inputId = id ?? generatedId
  const hintId = hint ? `${inputId}-hint` : undefined
  const errorId = error ? `${inputId}-error` : undefined
  const describedBy = [errorId, hintId].filter(Boolean).join(' ') || undefined

  return (
    <div className={cn('tf-field', fullWidth && 'tf-field--full')}>
      <label
        htmlFor={inputId}
        className={hideLabel ? 'sr-only' : 'tf-field__label'}
      >
        <span>{label}</span>
        {required && (
          <span className="tf-field__required" aria-hidden="true">
            *
          </span>
        )}
      </label>

      <input
        id={inputId}
        required={required}
        aria-invalid={error ? true : undefined}
        aria-describedby={describedBy}
        className={cn(
          'tf-input',
          `tf-input--${inputSize}`,
          error && 'tf-input--error',
          className,
        )}
        {...props}
      />

      {error && (
        <p id={errorId} role="alert" className="tf-field__error">
          {error}
        </p>
      )}
      {hint && (
        <p id={hintId} className="tf-field__hint">
          {hint}
        </p>
      )}
    </div>
  )
}
