import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

import {
  BUTTON_SHAPES,
  CARD_STYLES,
  DEFAULT_PROFILE,
  DENSITIES,
  VISUAL_SCALES,
  decodeProfile,
  type SRAppearanceProfile,
  type SRMotionLevel,
} from "./appearance";
import { toCSS } from "./color";
import { feedback } from "./feedback";
import { readJSON, StorageKey, writeJSON } from "./storage";
import { resolvePalette, type ResolvedPalette } from "./theme";

interface AppearanceValue {
  profile: SRAppearanceProfile;
  palette: ResolvedPalette;
  /** Reduce Motion always wins over the app's own preference. */
  effectiveMotion: SRMotionLevel;
  isStill: boolean;
  update: (patch: Partial<SRAppearanceProfile>) => void;
  reset: () => void;
  haptic: typeof feedback;
}

const AppearanceContext = createContext<AppearanceValue | null>(null);

function useMediaQuery(query: string): boolean {
  const [matches, setMatches] = useState<boolean>(() => {
    if (typeof window === "undefined") return false;
    return window.matchMedia(query).matches;
  });

  useEffect(() => {
    const list = window.matchMedia(query);
    const listener = (event: MediaQueryListEvent): void => setMatches(event.matches);
    setMatches(list.matches);
    list.addEventListener("change", listener);
    return () => list.removeEventListener("change", listener);
  }, [query]);

  return matches;
}

export function AppearanceProvider({ children }: { children: ReactNode }) {
  const [profile, setProfile] = useState<SRAppearanceProfile>(() =>
    decodeProfile(readJSON<unknown>(StorageKey.appearance, DEFAULT_PROFILE))
  );

  const prefersDark = useMediaQuery("(prefers-color-scheme: dark)");
  const prefersReducedMotion = useMediaQuery("(prefers-reduced-motion: reduce)");

  const isDarkScheme = profile.theme === "dark" || (profile.theme === "system" && prefersDark);
  const palette = useMemo(() => resolvePalette(profile, isDarkScheme), [profile, isDarkScheme]);

  const effectiveMotion: SRMotionLevel = prefersReducedMotion ? "reduced" : profile.motion;
  const isStill = effectiveMotion === "reduced";

  const update = useCallback((patch: Partial<SRAppearanceProfile>) => {
    setProfile((current) => {
      const next = { ...current, ...patch };
      writeJSON(StorageKey.appearance, next);
      return next;
    });
  }, []);

  const reset = useCallback(() => {
    const next = { ...DEFAULT_PROFILE, visibleMetadata: [...DEFAULT_PROFILE.visibleMetadata] };
    writeJSON(StorageKey.appearance, next);
    setProfile(next);
  }, []);

  // Publishing the palette as custom properties keeps every component reading one
  // source of truth, and makes a theme change a single repaint.
  useEffect(() => {
    const root = document.documentElement;
    const density = DENSITIES[profile.density];
    const scale = VISUAL_SCALES[profile.visualScale];
    const shape = BUTTON_SHAPES[profile.buttonShape];
    const card = CARD_STYLES[profile.cardStyle];

    const set = (name: string, value: string): void => root.style.setProperty(name, value);

    set("--sr-background", toCSS(palette.background));
    set("--sr-surface", toCSS(palette.surface));
    set("--sr-elevated", toCSS(palette.elevatedSurface));
    set("--sr-primary", toCSS(palette.primary));
    set("--sr-primary-soft", toCSS(palette.primarySoft));
    set("--sr-on-primary", toCSS(palette.onPrimary));
    set("--sr-ink", toCSS(palette.ink));
    set("--sr-secondary-ink", toCSS(palette.secondaryInk));
    set("--sr-sky", toCSS(palette.sky));
    set("--sr-lavender", toCSS(palette.lavender));
    set("--sr-blush", toCSS(palette.blush));
    set("--sr-mint", toCSS(palette.mint));
    set("--sr-divider", toCSS(palette.divider));
    // Depth is carried by hairlines and space, not by haze. On near-black the
    // shadow has to work harder to separate a surface from the page at all.
    set("--sr-shadow", palette.isDark ? "rgb(0 0 0 / 0.44)" : "rgb(0 0 0 / 0.035)");

    set("--sr-primary-a12", toCSS(palette.primary, 0.12));
    set("--sr-primary-a24", toCSS(palette.primary, 0.24));
    set("--sr-mint-a14", toCSS(palette.mint, 0.14));
    set("--sr-blush-a14", toCSS(palette.blush, 0.14));

    set("--sr-page-padding", `${Math.round(20 * density.padding * scale.factor)}px`);
    set("--sr-card-padding", `${Math.round(22 * density.padding * scale.factor)}px`);
    set("--sr-section-gap", `${Math.round(26 * density.spacing * scale.factor)}px`);
    set("--sr-row-gap", `${Math.round(11 * density.spacing * scale.factor)}px`);
    set("--sr-row-padding", `${Math.round(16 * density.padding * scale.factor)}px`);
    set("--sr-card-radius", `${profile.cardStyle === "flat" ? 20 : 26}px`);
    set("--sr-row-radius", `${profile.cardStyle === "flat" ? 15 : 18}px`);
    set("--sr-control-radius", `${shape.radius}px`);
    set("--sr-control-height", `${Math.round(shape.height * scale.factor)}px`);
    set("--sr-text-scale", `${scale.factor}`);

    set("--sr-card-border", card.borderOpacity > 0 ? toCSS(palette.divider, card.borderOpacity) : "transparent");
    set("--sr-card-border-width", card.borderOpacity > 0 ? (profile.cardStyle === "separated" ? "1px" : "0.7px") : "0px");
    set("--sr-card-fill", card.usesSurfaceFill ? toCSS(palette.surface) : toCSS(palette.surface, 0.42));
    set(
      "--sr-card-shadow",
      card.shadowRadius > 0
        ? `0 4px ${card.shadowRadius}px ${palette.isDark ? "rgb(0 0 0 / 0.44)" : "rgb(0 0 0 / 0.035)"}`
        : "none"
    );

    set("--sr-duration-quick", isStill ? "0ms" : effectiveMotion === "subtle" ? "140ms" : "180ms");
    set("--sr-duration-standard", isStill ? "0ms" : effectiveMotion === "subtle" ? "200ms" : "320ms");
    set("--sr-press-scale", isStill ? "1" : effectiveMotion === "subtle" ? "0.994" : "0.985");

    root.style.colorScheme = palette.isDark ? "dark" : "light";
    root.classList.toggle("dark", palette.isDark);

    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.setAttribute("content", toCSS(palette.background));
  }, [palette, profile, effectiveMotion, isStill]);

  const value = useMemo<AppearanceValue>(
    () => ({ profile, palette, effectiveMotion, isStill, update, reset, haptic: feedback }),
    [profile, palette, effectiveMotion, isStill, update, reset]
  );

  return <AppearanceContext.Provider value={value}>{children}</AppearanceContext.Provider>;
}

export function useAppearance(): AppearanceValue {
  const value = useContext(AppearanceContext);
  if (!value) throw new Error("useAppearance debe usarse dentro de AppearanceProvider");
  return value;
}

/** Fires the chosen level of feedback without every caller reading the profile. */
export function useHaptics() {
  const { profile } = useAppearance();
  return useMemo(
    () => ({
      light: () => feedback.light(profile.haptics),
      soft: () => feedback.soft(profile.haptics),
      success: () => feedback.success(profile.haptics),
    }),
    [profile.haptics]
  );
}
