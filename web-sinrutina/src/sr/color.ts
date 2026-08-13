/**
 * Colour maths, ported from the iPhone app so both versions correct contrast the
 * same way. This is what lets SinRutina offer personalisation without letting
 * anyone build an illegible interface.
 */
export interface RGB {
  red: number;
  green: number;
  blue: number;
}

const clamp01 = (value: number): number => Math.min(Math.max(value, 0), 1);

export const rgb = (red: number, green: number, blue: number): RGB => ({
  red: clamp01(red),
  green: clamp01(green),
  blue: clamp01(blue),
});

export function fromHex(hex: string): RGB | null {
  let trimmed = hex.trim().toUpperCase();
  if (trimmed.startsWith("#")) trimmed = trimmed.slice(1);
  if (trimmed.length !== 6 || !/^[0-9A-F]{6}$/.test(trimmed)) return null;
  const value = parseInt(trimmed, 16);
  return rgb(((value >> 16) & 0xff) / 255, ((value >> 8) & 0xff) / 255, (value & 0xff) / 255);
}

/** Only for literals written in this codebase, which are known to be valid. */
export function hex(value: string): RGB {
  const parsed = fromHex(value);
  if (!parsed) throw new Error(`Invalid hex colour: ${value}`);
  return parsed;
}

export function toHex(color: RGB): string {
  const channel = (value: number): string =>
    Math.round(value * 255)
      .toString(16)
      .padStart(2, "0")
      .toUpperCase();
  return `#${channel(color.red)}${channel(color.green)}${channel(color.blue)}`;
}

export function toCSS(color: RGB, alpha = 1): string {
  const channel = (value: number): number => Math.round(value * 255);
  if (alpha >= 1) return `rgb(${channel(color.red)} ${channel(color.green)} ${channel(color.blue)})`;
  return `rgb(${channel(color.red)} ${channel(color.green)} ${channel(color.blue)} / ${alpha})`;
}

export function blended(color: RGB, other: RGB, amount: number): RGB {
  const t = clamp01(amount);
  return rgb(
    color.red + (other.red - color.red) * t,
    color.green + (other.green - color.green) * t,
    color.blue + (other.blue - color.blue) * t
  );
}

/** WCAG relative luminance. */
export function luminance(color: RGB): number {
  const channel = (value: number): number =>
    value <= 0.03928 ? value / 12.92 : Math.pow((value + 0.055) / 1.055, 2.4);
  return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue);
}

export function contrast(color: RGB, other: RGB): number {
  const a = luminance(color);
  const b = luminance(other);
  return (Math.max(a, b) + 0.05) / (Math.min(a, b) + 0.05);
}

export const WHITE = rgb(1, 1, 1);
export const BLACK = rgb(0, 0, 0);

/**
 * Darkens a colour just enough for white label text to stay readable on top of
 * it. Used for every accent, including colours the person picks freely.
 */
export function madeReadableUnderWhiteText(color: RGB, minimumContrast = 4.3): RGB {
  let candidate = color;
  let steps = 0;
  while (contrast(candidate, WHITE) < minimumContrast && steps < 30) {
    candidate = blended(candidate, BLACK, 0.06);
    steps += 1;
  }
  return candidate;
}

/** Lightens a colour so it can be read as text on a dark surface. */
export function madeReadableOnDarkSurface(color: RGB, surface: RGB, minimumContrast = 4.3): RGB {
  let candidate = color;
  let steps = 0;
  while (contrast(candidate, surface) < minimumContrast && steps < 30) {
    candidate = blended(candidate, WHITE, 0.07);
    steps += 1;
  }
  return candidate;
}
