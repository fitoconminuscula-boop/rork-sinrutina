import {
  ACCENT_BASE,
  type SRAppearanceProfile,
  type SRTheme,
} from "./appearance";
import {
  blended,
  contrast,
  fromHex,
  hex,
  madeReadableOnDarkSurface,
  madeReadableUnderWhiteText,
  type RGB,
  WHITE,
} from "./color";

/**
 * The raw colour values of one palette in one appearance. Every theme is written
 * out by hand — the dark theme is a real design, not an inverted light one.
 */
export interface ThemeTokens {
  background: RGB;
  surface: RGB;
  elevatedSurface: RGB;
  primary: RGB;
  ink: RGB;
  secondaryInk: RGB;
  sky: RGB;
  periwinkle: RGB;
  lavender: RGB;
  blush: RGB;
  mint: RGB;
  divider: RGB;
  isDark: boolean;
}

const PASTEL: ThemeTokens = {
  background: hex("#FAFAF8"),
  surface: hex("#FFFFFF"),
  elevatedSurface: hex("#FFFFFF"),
  primary: hex("#4B5FE3"),
  ink: hex("#14172B"),
  secondaryInk: hex("#666D85"),
  sky: hex("#6FA8F0"),
  periwinkle: hex("#8B9BF5"),
  lavender: hex("#A78BFA"),
  blush: hex("#F87FA6"),
  mint: hex("#3FCFA5"),
  divider: hex("#ECECE8"),
  isDark: false,
};

const BLUE: ThemeTokens = {
  background: hex("#F7F9FC"),
  surface: hex("#FFFFFF"),
  elevatedSurface: hex("#FFFFFF"),
  primary: hex("#1668E3"),
  ink: hex("#0D1A2B"),
  secondaryInk: hex("#5C6B80"),
  sky: hex("#62A8F0"),
  periwinkle: hex("#6E93EC"),
  lavender: hex("#8B93E0"),
  blush: hex("#E8809A"),
  mint: hex("#3BBFA6"),
  divider: hex("#E6EBF2"),
  isDark: false,
};

const LAVENDER: ThemeTokens = {
  background: hex("#FAF8FD"),
  surface: hex("#FFFFFF"),
  elevatedSurface: hex("#FFFFFF"),
  primary: hex("#7C4DE8"),
  ink: hex("#1F1733"),
  secondaryInk: hex("#6C6488"),
  sky: hex("#A6A9F5"),
  periwinkle: hex("#9384EE"),
  lavender: hex("#B292F5"),
  blush: hex("#EE8FBC"),
  mint: hex("#56C9B4"),
  divider: hex("#EDE7F7"),
  isDark: false,
};

const MINT: ThemeTokens = {
  background: hex("#F5FBF8"),
  surface: hex("#FFFFFF"),
  elevatedSurface: hex("#FFFFFF"),
  primary: hex("#0E826A"),
  ink: hex("#0D2A24"),
  secondaryInk: hex("#547A70"),
  sky: hex("#6FBBD4"),
  periwinkle: hex("#6FA3C7"),
  lavender: hex("#93A8D0"),
  blush: hex("#E09182"),
  mint: hex("#2CBF9B"),
  divider: hex("#DFEFE8"),
  isDark: false,
};

const WARM: ThemeTokens = {
  background: hex("#FDF8F3"),
  surface: hex("#FFFFFF"),
  elevatedSurface: hex("#FFFFFF"),
  primary: hex("#BB542E"),
  ink: hex("#33231B"),
  secondaryInk: hex("#856E5D"),
  sky: hex("#E5B394"),
  periwinkle: hex("#DC9878"),
  lavender: hex("#CE96A2"),
  blush: hex("#F09A92"),
  mint: hex("#9EB894"),
  divider: hex("#F1E4D8"),
  isDark: false,
};

const MONO: ThemeTokens = {
  background: hex("#F7F7F6"),
  surface: hex("#FFFFFF"),
  elevatedSurface: hex("#FFFFFF"),
  primary: hex("#1A1A1C"),
  ink: hex("#0F0F11"),
  secondaryInk: hex("#6B6B70"),
  sky: hex("#A5A5AA"),
  periwinkle: hex("#939398"),
  lavender: hex("#8B8B90"),
  blush: hex("#77777C"),
  mint: hex("#87878C"),
  divider: hex("#E8E8E6"),
  isDark: false,
};

const DARK: ThemeTokens = {
  background: hex("#0C0D12"),
  surface: hex("#14161D"),
  elevatedSurface: hex("#1C1F28"),
  primary: hex("#8B9DFF"),
  ink: hex("#F2F3F8"),
  secondaryInk: hex("#9AA0B4"),
  sky: hex("#74AEF5"),
  periwinkle: hex("#8E9DFA"),
  lavender: hex("#B49BFB"),
  blush: hex("#FB8FB0"),
  mint: hex("#45D3AA"),
  divider: hex("#262A36"),
  isDark: true,
};

const WARM_DARK: ThemeTokens = {
  background: hex("#14100D"),
  surface: hex("#1E1815"),
  elevatedSurface: hex("#29211C"),
  primary: hex("#F0956A"),
  ink: hex("#F8EFE8"),
  secondaryInk: hex("#BFA694"),
  sky: hex("#E0AE8C"),
  periwinkle: hex("#DC9A76"),
  lavender: hex("#D29CA8"),
  blush: hex("#F5A093"),
  mint: hex("#A8BE9C"),
  divider: hex("#332821"),
  isDark: true,
};

const MONO_DARK: ThemeTokens = {
  background: hex("#0D0D0F"),
  surface: hex("#16161A"),
  elevatedSurface: hex("#1F1F24"),
  primary: hex("#F0F0F3"),
  ink: hex("#F7F7F9"),
  secondaryInk: hex("#97979E"),
  sky: hex("#8C8C94"),
  periwinkle: hex("#9E9EA6"),
  lavender: hex("#88888F"),
  blush: hex("#B2B2BA"),
  mint: hex("#9A9AA2"),
  divider: hex("#2A2A31"),
  isDark: true,
};

/** Keeps a theme recognisable in dark mode by swapping only its action colour. */
const retinted = (tokens: ThemeTokens, primary: RGB): ThemeTokens => ({ ...tokens, primary });

export function tokensFor(theme: SRTheme, isDarkScheme: boolean): ThemeTokens {
  switch (theme) {
    case "dark":
      return DARK;
    case "system":
    case "pastel":
      return isDarkScheme ? DARK : PASTEL;
    case "blue":
      return isDarkScheme ? retinted(DARK, hex("#6FA6FF")) : BLUE;
    case "lavender":
      return isDarkScheme ? retinted(DARK, hex("#B08BFA")) : LAVENDER;
    case "mint":
      return isDarkScheme ? retinted(DARK, hex("#3EDCB0")) : MINT;
    case "warm":
      return isDarkScheme ? WARM_DARK : WARM;
    case "mono":
      return isDarkScheme ? MONO_DARK : MONO;
  }
}

/** Small strip used in the theme picker, so the choice is made by looking. */
export function themeSwatch(theme: SRTheme): RGB[] {
  const tokens = tokensFor(theme, theme === "dark");
  return [tokens.background, tokens.primary, tokens.sky, tokens.lavender, tokens.blush];
}

export interface ResolvedPalette extends Omit<ThemeTokens, "isDark"> {
  primarySoft: RGB;
  onPrimary: RGB;
  isDark: boolean;
}

/**
 * One appearance of one profile: theme tokens with the chosen accent applied and
 * every derived colour checked for contrast.
 */
export function resolvePalette(profile: SRAppearanceProfile, isDarkScheme: boolean): ResolvedPalette {
  const tokens = tokensFor(profile.theme, isDarkScheme);

  // The accent replaces the action colour only. Backgrounds, text and the rest
  // of the palette keep belonging to the theme.
  const requested: RGB | null =
    profile.accent === "theme"
      ? null
      : profile.accent === "custom"
        ? (profile.customAccentHex ? fromHex(profile.customAccentHex) : null)
        : (() => {
            const base = ACCENT_BASE[profile.accent];
            return base ? fromHex(base) : null;
          })();

  let action = requested ?? tokens.primary;
  let onPrimary: RGB;

  if (tokens.isDark) {
    // On dark surfaces the accent is also used as text, so it has to be light
    // enough to read.
    action = madeReadableOnDarkSurface(action, tokens.surface);
    onPrimary = contrast(action, WHITE) >= 3.4 ? WHITE : hex("#12141F");
  } else {
    if (requested !== null) action = madeReadableUnderWhiteText(action);
    onPrimary = contrast(action, WHITE) >= 3.4 ? WHITE : tokens.ink;
  }

  const primarySoft = tokens.isDark
    ? blended(action, tokens.background, 0.74)
    : blended(action, WHITE, 0.87);

  return {
    background: tokens.background,
    surface: tokens.surface,
    elevatedSurface: tokens.elevatedSurface,
    primary: action,
    primarySoft,
    ink: tokens.ink,
    secondaryInk: tokens.secondaryInk,
    sky: tokens.sky,
    periwinkle: tokens.periwinkle,
    lavender: tokens.lavender,
    blush: tokens.blush,
    mint: tokens.mint,
    divider: tokens.divider,
    onPrimary,
    isDark: tokens.isDark,
  };
}
