import type { ComponentPropsWithRef, ReactNode } from 'react'
import { cn } from '../../lib/cn'
import './EmptyState.css'

export interface EmptyStateProps extends ComponentPropsWithRef<'div'> {
  icon?: ReactNode
  title: string
  description?: string
  action?: ReactNode
  headingAs?: 'h2' | 'h3'
  compact?: boolean
}

export function EmptyState({
  icon,
  title,
  description,
  action,
  headingAs = 'h2',
  compact = false,
  className,
  ...props
}: EmptyStateProps) {
  const Heading = headingAs

  return (
    <div
      className={cn('tf-empty', compact && 'tf-empty--compact', className)}
      {...props}
    >
      {icon && (
        <div className="tf-empty__icon" aria-hidden="true">
          {icon}
        </div>
      )}
      <Heading className="tf-empty__title">{title}</Heading>
      {description && <p className="tf-empty__description">{description}</p>}
      {action && <div className="tf-empty__action">{action}</div>}
    </div>
  )
}
