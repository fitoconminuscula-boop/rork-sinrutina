import type { SRHapticLevel } from "./appearance";

/**
 * Feedback for moments that mean something: starting, finishing, changing state,
 * confirming something important.
 *
 * On iPhone this is the Taptic Engine. In a browser the only real equivalent is
 * `navigator.vibrate`, which Safari on iOS does not implement — so on an iPhone
 * browser these calls do nothing at all. That is why Ajustes says "solo en
 * Android" next to the setting instead of offering a switch that quietly does
 * nothing.
 */

export function supportsVibration(): boolean {
  return typeof navigator !== "undefined" && typeof navigator.vibrate === "function";
}

function vibrate(pattern: number | number[], level: SRHapticLevel): void {
  if (level === "none") return;
  if (!supportsVibration()) return;
  try {
    navigator.vibrate(pattern);
  } catch {
    // A browser that refuses to vibrate is not an error worth surfacing.
  }
}

export const feedback = {
  light(level: SRHapticLevel): void {
    vibrate(level === "soft" ? 6 : 10, level);
  },
  soft(level: SRHapticLevel): void {
    vibrate(level === "soft" ? 10 : 16, level);
  },
  success(level: SRHapticLevel): void {
    vibrate(level === "soft" ? [10, 40, 14] : [16, 50, 24], level);
  },
};
