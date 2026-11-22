import type { ComponentPropsWithRef } from 'react'
import { cn } from '../../lib/cn'
import type { CardPadding, CardVariant } from '../../types/ui'
import './Card.css'

export interface CardProps extends ComponentPropsWithRef<'div'> {
  as?: 'div' | 'section' | 'article' | 'aside'
  variant?: CardVariant
  padding?: CardPadding
  interactive?: boolean
}

export function Card({
  as = 'div',
  variant = 'default',
  padding = 'md',
  interactive = false,
  className,
  children,
  ...props
}: CardProps) {
  const Component = as

  return (
    <Component
      className={cn(
        'tf-card',
        variant !== 'default' && `tf-card--${variant}`,
        `tf-card--pad-${padding}`,
        interactive && 'tf-card--interactive',
        className,
      )}
      {...props}
    >
      {children}
    </Component>
  )
}

export function CardHeader({
  className,
  children,
  ...props
}: ComponentPropsWithRef<'div'>) {
  return (
    <div className={cn('tf-card__header', className)} {...props}>
      {children}
    </div>
  )
}

export interface CardTitleProps extends ComponentPropsWithRef<'h2'> {
  as?: 'h2' | 'h3' | 'h4'
}

export function CardTitle({
  as = 'h2',
  className,
  children,
  ...props
}: CardTitleProps) {
  const Heading = as

  return (
    <Heading className={cn('tf-card__title', className)} {...props}>
      {children}
    </Heading>
  )
}

export function CardDescription({
  className,
  children,
  ...props
}: ComponentPropsWithRef<'p'>) {
  return (
    <p className={cn('tf-card__description', className)} {...props}>
      {children}
    </p>
  )
}

export function CardContent({
  className,
  children,
  ...props
}: ComponentPropsWithRef<'div'>) {
  return (
    <div className={cn('tf-card__content', className)} {...props}>
      {children}
    </div>
  )
}

export function CardFooter({
  className,
  children,
  ...props
}: ComponentPropsWithRef<'div'>) {
  return (
    <div className={cn('tf-card__footer', className)} {...props}>
      {children}
    </div>
  )
}
