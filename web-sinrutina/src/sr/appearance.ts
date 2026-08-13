/**
 * Everything the person has chosen about how SinRutina looks.
 *
 * This mirrors the iPhone profile, minus the options that only exist on iOS
 * (widget style, Live Activity style, alternate app icons). Those are not
 * offered here because there is nothing behind them in a browser.
 */

export type SRTheme = "pastel" | "blue" | "lavender" | "mint" | "warm" | "mono" | "dark" | "system";

export const THEME_LABELS: Record<SRTheme, { label: string; summary: string }> = {
  pastel: { label: "Pastel", summary: "El original de SinRutina" },
  blue: { label: "Azul", summary: "Sobrio y monocromático" },
  lavender: { label: "Lavanda", summary: "Lavanda y periwinkle" },
  mint: { label: "Menta", summary: "Fresco y neutro" },
  warm: { label: "Cálido", summary: "Blush, arena y melocotón" },
  mono: { label: "Monocromo", summary: "Blancos, grises y un color" },
  dark: { label: "Oscuro", summary: "Oscuro de verdad" },
  system: { label: "Seguir sistema", summary: "Claro u oscuro según el navegador" },
};

export const THEME_ORDER: SRTheme[] = [
  "pastel",
  "blue",
  "lavender",
  "mint",
  "warm",
  "mono",
  "dark",
  "system",
];

export type SRAccent =
  | "theme"
  | "periwinkle"
  | "pastelBlue"
  | "lavender"
  | "blush"
  | "mint"
  | "peach"
  | "slate"
  | "custom";

export const ACCENT_LABELS: Record<SRAccent, string> = {
  theme: "Del tema",
  periwinkle: "Periwinkle",
  pastelBlue: "Azul pastel",
  lavender: "Lavanda",
  blush: "Rosa blush",
  mint: "Menta",
  peach: "Melocotón",
  slate: "Gris azulado",
  custom: "Personalizado",
};

/** The base colour before contrast correction. `null` means "use the theme's own". */
export const ACCENT_BASE: Record<SRAccent, string | null> = {
  theme: null,
  custom: null,
  periwinkle: "#4B5FE3",
  pastelBlue: "#1668E3",
  lavender: "#7C4DE8",
  blush: "#D22E5E",
  mint: "#0D8068",
  peach: "#B9532D",
  slate: "#4A5C73",
};

export const PICKABLE_ACCENTS: SRAccent[] = [
  "periwinkle",
  "pastelBlue",
  "lavender",
  "blush",
  "mint",
  "peach",
  "slate",
];

export type SRButtonShape = "soft" | "minimal" | "compact";

export const BUTTON_SHAPES: Record<SRButtonShape, { label: string; detail: string; radius: number; height: number }> = {
  soft: { label: "Suave", detail: "Radios algo mayores", radius: 20, height: 54 },
  minimal: { label: "Minimal", detail: "Más recto y discreto", radius: 11, height: 52 },
  compact: { label: "Compacto", detail: "Menos alto", radius: 14, height: 46 },
};

export type SRDensity = "airy" | "normal" | "compact";

export const DENSITIES: Record<
  SRDensity,
  { label: string; spacing: number; padding: number; rows: number; showsSecondaryDetail: boolean }
> = {
  airy: { label: "Aireada", spacing: 1.14, padding: 1.1, rows: 1.12, showsSecondaryDetail: true },
  normal: { label: "Normal", spacing: 1, padding: 1, rows: 1, showsSecondaryDetail: true },
  compact: { label: "Compacta", spacing: 0.78, padding: 0.84, rows: 0.82, showsSecondaryDetail: false },
};

export type SRVisualScale = "small" | "system" | "large";

export const VISUAL_SCALES: Record<SRVisualScale, { label: string; factor: number }> = {
  small: { label: "Pequeña", factor: 0.94 },
  system: { label: "Sistema", factor: 1 },
  large: { label: "Grande", factor: 1.12 },
};

export type SRCardStyle = "flat" | "subtle" | "separated";

export const CARD_STYLES: Record<
  SRCardStyle,
  { label: string; detail: string; borderOpacity: number; shadowRadius: number; usesSurfaceFill: boolean }
> = {
  flat: { label: "Sin tarjetas", detail: "Interfaz casi plana", borderOpacity: 0, shadowRadius: 0, usesSurfaceFill: false },
  subtle: { label: "Sutiles", detail: "Fondos apenas diferenciados", borderOpacity: 0.62, shadowRadius: 12, usesSurfaceFill: true },
  separated: { label: "Separadas", detail: "Contenidos más definidos", borderOpacity: 0.95, shadowRadius: 14, usesSurfaceFill: true },
};

export type SRMotionLevel = "full" | "subtle" | "reduced";

export const MOTION_LABELS: Record<SRMotionLevel, string> = {
  full: "Completas",
  subtle: "Sutiles",
  reduced: "Reducidas",
};

export type SRHapticLevel = "none" | "soft" | "normal";

export const HAPTIC_LABELS: Record<SRHapticLevel, string> = {
  none: "Ninguna",
  soft: "Suave",
  normal: "Normal",
};

/** How present the SinRutina mark is. Never a face, never a permanent animation. */
export type SRPresenceLevel = "minimal" | "normal" | "expressive";

export const PRESENCE_LABELS: Record<SRPresenceLevel, string> = {
  minimal: "Mínima",
  normal: "Normal",
  expressive: "Expresiva",
};

export const PRESENCE_SCALE: Record<SRPresenceLevel, number> = {
  minimal: 0.86,
  normal: 1,
  expressive: 1.1,
};

export type SRNowLayout = "focus" | "context";

export const NOW_LAYOUTS: Record<SRNowLayout, { label: string; detail: string }> = {
  focus: { label: "Enfoque", detail: "Solo la tarea y Empezar" },
  context: { label: "Contexto", detail: "Añade tiempo y motivo" },
};

/**
 * Individual pieces of secondary information. Title and primary action are not
 * on this list on purpose: they can never be hidden.
 */
export type SRMetadataField = "duration" | "dueTime" | "reason" | "openDays" | "logo";

export const METADATA_LABELS: Record<SRMetadataField, string> = {
  duration: "Duración estimada",
  dueTime: "Hora límite",
  reason: "Razón de la recomendación",
  openDays: "Días abierto",
  logo: "Símbolo de SinRutina",
};

export const ALL_METADATA: SRMetadataField[] = ["duration", "dueTime", "reason", "openDays", "logo"];

export interface SRAppearanceProfile {
  theme: SRTheme;
  accent: SRAccent;
  customAccentHex: string | null;
  density: SRDensity;
  buttonShape: SRButtonShape;
  cardStyle: SRCardStyle;
  visualScale: SRVisualScale;
  motion: SRMotionLevel;
  haptics: SRHapticLevel;
  presence: SRPresenceLevel;
  nowLayout: SRNowLayout;
  visibleMetadata: SRMetadataField[];
}

export const DEFAULT_PROFILE: SRAppearanceProfile = {
  theme: "pastel",
  accent: "theme",
  customAccentHex: null,
  density: "airy",
  buttonShape: "soft",
  cardStyle: "subtle",
  visualScale: "system",
  motion: "full",
  haptics: "normal",
  presence: "normal",
  nowLayout: "context",
  visibleMetadata: [...ALL_METADATA],
};

export function profileShows(profile: SRAppearanceProfile, field: SRMetadataField): boolean {
  return profile.visibleMetadata.includes(field);
}

/** True when nothing has been personalised, used to hide "Restablecer". */
export function isOriginalProfile(profile: SRAppearanceProfile): boolean {
  return (
    profile.theme === DEFAULT_PROFILE.theme &&
    profile.accent === DEFAULT_PROFILE.accent &&
    profile.customAccentHex === DEFAULT_PROFILE.customAccentHex &&
    profile.density === DEFAULT_PROFILE.density &&
    profile.buttonShape === DEFAULT_PROFILE.buttonShape &&
    profile.cardStyle === DEFAULT_PROFILE.cardStyle &&
    profile.visualScale === DEFAULT_PROFILE.visualScale &&
    profile.motion === DEFAULT_PROFILE.motion &&
    profile.haptics === DEFAULT_PROFILE.haptics &&
    profile.presence === DEFAULT_PROFILE.presence &&
    profile.nowLayout === DEFAULT_PROFILE.nowLayout &&
    profile.visibleMetadata.length === ALL_METADATA.length
  );
}

/**
 * Reads a stored profile field by field, so a profile saved by an older build
 * keeps working and any new option simply starts at its default.
 */
export function decodeProfile(raw: unknown): SRAppearanceProfile {
  if (typeof raw !== "object" || raw === null) return { ...DEFAULT_PROFILE };
  const source = raw as Record<string, unknown>;

  const pick = <T extends string>(key: string, allowed: readonly T[], fallback: T): T => {
    const value = source[key];
    return typeof value === "string" && (allowed as readonly string[]).includes(value) ? (value as T) : fallback;
  };

  const metadata = Array.isArray(source.visibleMetadata)
    ? source.visibleMetadata.filter((field): field is SRMetadataField =>
        ALL_METADATA.includes(field as SRMetadataField)
      )
    : [...ALL_METADATA];

  return {
    theme: pick("theme", THEME_ORDER, DEFAULT_PROFILE.theme),
    accent: pick("accent", Object.keys(ACCENT_LABELS) as SRAccent[], DEFAULT_PROFILE.accent),
    customAccentHex: typeof source.customAccentHex === "string" ? source.customAccentHex : null,
    density: pick("density", Object.keys(DENSITIES) as SRDensity[], DEFAULT_PROFILE.density),
    buttonShape: pick("buttonShape", Object.keys(BUTTON_SHAPES) as SRButtonShape[], DEFAULT_PROFILE.buttonShape),
    cardStyle: pick("cardStyle", Object.keys(CARD_STYLES) as SRCardStyle[], DEFAULT_PROFILE.cardStyle),
    visualScale: pick("visualScale", Object.keys(VISUAL_SCALES) as SRVisualScale[], DEFAULT_PROFILE.visualScale),
    motion: pick("motion", Object.keys(MOTION_LABELS) as SRMotionLevel[], DEFAULT_PROFILE.motion),
    haptics: pick("haptics", Object.keys(HAPTIC_LABELS) as SRHapticLevel[], DEFAULT_PROFILE.haptics),
    presence: pick("presence", Object.keys(PRESENCE_LABELS) as SRPresenceLevel[], DEFAULT_PROFILE.presence),
    nowLayout: pick("nowLayout", Object.keys(NOW_LAYOUTS) as SRNowLayout[], DEFAULT_PROFILE.nowLayout),
    visibleMetadata: metadata,
  };
}
