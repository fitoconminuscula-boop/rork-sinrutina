/// <reference types="vite/client" />

/**
 * Rork writes public configuration with the EXPO_PUBLIC_ prefix so the same names
 * work across the iPhone app and this one. `vite.config.ts` exposes that prefix.
 */
interface ImportMetaEnv {
  readonly EXPO_PUBLIC_TOOLKIT_URL?: string;
  readonly EXPO_PUBLIC_PROJECT_ID?: string;
  readonly EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY?: string;
  /**
   * The small Cloudflare Worker in `functions/` that holds the reading keys:
   * Groq for text and dictation, Gemini for text and pictures. Both free tiers.
   *
   * The keys themselves are deliberately absent from this file. Anything a
   * browser can read is public, so they stay on the Worker and the browser asks
   * the Worker instead. Without this URL the reader simply falls back to Gemini
   * through the Rork proxy, which needs no key but is metered.
   */
  readonly EXPO_PUBLIC_RORK_FUNCTIONS_URL?: string;
}

interface ImportMeta {
  readonly env: ImportMetaEnv;
}
