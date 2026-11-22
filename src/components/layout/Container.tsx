import type { ComponentPropsWithRef } from 'react'
import { cn } from '../../lib/cn'
import type { ContainerSize } from '../../types/ui'
import './Container.css'

export interface ContainerProps extends ComponentPropsWithRef<'div'> {
  size?: ContainerSize
}

export function Container({
  size = 'lg',
  className,
  children,
  ...props
}: ContainerProps) {
  return (
    <div
      className={cn('tf-container', `tf-container--${size}`, className)}
      {...props}
    >
      {children}
    </div>
  )
}
