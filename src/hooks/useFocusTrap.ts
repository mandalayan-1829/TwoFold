import { useEffect, type RefObject } from 'react'

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'area[href]',
  'button:not([disabled])',
  'input:not([disabled]):not([type="hidden"])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
].join(', ')

interface UseFocusTrapOptions {
  active: boolean
  containerRef: RefObject<HTMLElement | null>
  initialFocusRef?: RefObject<HTMLElement | null>
  onEscape?: () => void
}

function getFocusableElements(container: HTMLElement): HTMLElement[] {
  return Array.from(container.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR))
}

export function useFocusTrap({
  active,
  containerRef,
  initialFocusRef,
  onEscape,
}: UseFocusTrapOptions): void {
  useEffect(() => {
    if (!active) return

    const container = containerRef.current
    if (!container) return

    const previousActive =
      document.activeElement instanceof HTMLElement
        ? document.activeElement
        : null

    const focusInitial = () => {
      if (initialFocusRef?.current && !initialFocusRef.current.hasAttribute('disabled')) {
        initialFocusRef.current.focus()
        return
      }
      const focusables = getFocusableElements(container)
      const first = focusables[0]
      if (first) {
        first.focus()
      } else {
        container.focus()
      }
    }

    focusInitial()

    const handleKeyDown = (event: KeyboardEvent) => {
      if (event.key === 'Escape') {
        if (onEscape) {
          event.preventDefault()
          onEscape()
        }
        return
      }

      if (event.key !== 'Tab') return

      const focusables = getFocusableElements(container)
      const first = focusables[0]
      const last = focusables[focusables.length - 1]

      if (!first || !last) {
        event.preventDefault()
        container.focus()
        return
      }

      const activeElement = document.activeElement

      if (event.shiftKey) {
        if (activeElement === first || !container.contains(activeElement)) {
          event.preventDefault()
          last.focus()
        }
      } else if (activeElement === last || !container.contains(activeElement)) {
        event.preventDefault()
        first.focus()
      }
    }

    document.addEventListener('keydown', handleKeyDown)

    return () => {
      document.removeEventListener('keydown', handleKeyDown)
      if (previousActive && previousActive.isConnected) {
        previousActive.focus()
      }
    }
  }, [active, containerRef, initialFocusRef, onEscape])
}
