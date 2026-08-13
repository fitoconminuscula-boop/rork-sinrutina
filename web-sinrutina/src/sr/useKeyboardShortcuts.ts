import { useEffect } from "react";

export interface ShortcutHandlers {
  capture: () => void;
  start: () => void;
  saturated: () => void;
  selectTab: (index: number) => void;
}

/**
 * Keyboard shortcuts for the one screen that owns them: the browsing stack.
 *
 * They are switched off while a session, the overwhelmed screen or any sheet is
 * up, because those screens deliberately hold a single decision and a stray key
 * would be a second one. Typing anywhere never triggers anything.
 */
export function useKeyboardShortcuts(handlers: ShortcutHandlers, isEnabled: boolean): void {
  useEffect(() => {
    if (!isEnabled) return;

    const onKey = (event: KeyboardEvent): void => {
      if (event.metaKey || event.ctrlKey || event.altKey) return;

      const target = event.target as HTMLElement | null;
      if (target) {
        const tag = target.tagName;
        if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT" || target.isContentEditable) return;
      }

      switch (event.key.toLowerCase()) {
        case "c":
          event.preventDefault();
          handlers.capture();
          return;
        case "e":
          event.preventDefault();
          handlers.start();
          return;
        case "s":
          event.preventDefault();
          handlers.saturated();
          return;
        case "1":
        case "2":
        case "3":
        case "4":
          event.preventDefault();
          handlers.selectTab(Number(event.key) - 1);
          return;
        default:
      }
    };

    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [isEnabled, handlers]);
}
