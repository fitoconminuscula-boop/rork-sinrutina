import { readJSON, StorageKey, writeJSON } from "./storage";
import type { Task } from "./types";

/**
 * Shortcuts: the browser-side plumbing that lets SinRutina be reached from
 * outside, and reach the keyboard and the home screen.
 *
 * Everything that leaves the app — calendar files, mail drafts, backups, the
 * Atajos bridge — lives in `handoff.ts`. This file is about the doors in.
 */

/** Query parameter that lets anything outside the app write a task into it. */
export const CAPTURE_PARAM = "capturar";

/** The link to paste into Atajos, a bookmark, or another app. */
export function captureLink(origin?: string): string {
  const base = origin ?? window.location.origin + window.location.pathname;
  return `${base.replace(/\/$/, "")}/?${CAPTURE_PARAM}=`;
}

/** What the address bar was carrying when the app opened. */
export interface IncomingIntent {
  /** Text to save. Empty string means "open the capture sheet, I will type it". */
  capture: string | null;
  /** A screen asked for by name, from a long-press shortcut on the icon. */
  screen: "saturated" | null;
}

/**
 * Reads whatever arrived through the address bar and clears it.
 *
 * Three doors lead here, and they all end in the same reader as typing:
 * the capture link, an icon shortcut, and Android's share sheet — which hands
 * over a title, a text and a link as separate fields, so they are joined back
 * into one sentence rather than dropped.
 *
 * The address is cleaned afterwards so a refresh cannot save the same thing
 * twice.
 */
export function takeIncomingIntent(): IncomingIntent {
  const empty: IncomingIntent = { capture: null, screen: null };

  try {
    const params = new URLSearchParams(window.location.search);
    const known = [CAPTURE_PARAM, "titulo", "enlace", "pantalla", "desde"];
    if (!known.some((name) => params.has(name))) return empty;

    const shared = [params.get("titulo"), params.get(CAPTURE_PARAM), params.get("enlace")]
      .map((part) => (part ?? "").trim())
      .filter((part) => part.length > 0);

    // A share where the text already contains the link should not say it twice.
    const parts = shared.filter((part, index) => shared.indexOf(part) === index);
    const capture = params.has(CAPTURE_PARAM) || params.has("titulo") || params.has("enlace")
      ? parts.join(" ").trim()
      : null;

    const screen = params.get("pantalla") === "saturado" ? ("saturated" as const) : null;

    known.forEach((name) => params.delete(name));
    const query = params.toString();
    window.history.replaceState(
      null,
      "",
      `${window.location.pathname}${query.length > 0 ? `?${query}` : ""}${window.location.hash}`
    );

    return { capture, screen };
  } catch (error) {
    console.warn("SinRutina: no se pudo leer lo que venía en la dirección.", error);
    return empty;
  }
}

export function canShare(): boolean {
  return typeof navigator !== "undefined" && typeof navigator.share === "function";
}

/** What a shared task says outside SinRutina. */
export function shareText(task: Task): string {
  const step = task.nextStep?.trim();
  return step && step !== task.title ? `${task.title}\nPrimer paso: ${step}` : task.title;
}

export type HandoffResult = "shared" | "copied" | "failed";

/**
 * Sends a task out through the system share sheet, falling back to the
 * clipboard. The result says which one happened — never both, never neither.
 */
export async function handOff(task: Task): Promise<HandoffResult> {
  const text = shareText(task);

  if (canShare()) {
    try {
      await navigator.share({ title: "SinRutina", text });
      return "shared";
    } catch (error) {
      // A cancelled share is not a failure worth reporting as one.
      if (error instanceof DOMException && error.name === "AbortError") return "failed";
    }
  }

  try {
    await navigator.clipboard.writeText(text);
    return "copied";
  } catch {
    return "failed";
  }
}

/** True when the app is already running from the home screen. */
export function isInstalled(): boolean {
  if (typeof window === "undefined") return false;
  const standalone = (window.navigator as { standalone?: boolean }).standalone === true;
  return standalone || window.matchMedia("(display-mode: standalone)").matches;
}

export function isIOS(): boolean {
  if (typeof navigator === "undefined") return false;
  return /iPad|iPhone|iPod/.test(navigator.userAgent);
}

/** Every keyboard shortcut, in one place, so Atajos can list what truly exists. */
export const KEYBOARD_SHORTCUTS: { keys: string; action: string }[] = [
  { keys: "C", action: "Capturar algo nuevo" },
  { keys: "E", action: "Empezar la tarea de Ahora" },
  { keys: "S", action: "Estoy saturado" },
  { keys: "1 – 4", action: "Cambiar de pestaña" },
  { keys: "Esc", action: "Cerrar lo que esté abierto" },
];

/**
 * The name of the shortcut in the Atajos app this person built for themselves.
 *
 * Empty until they save one, and the row that uses it stays hidden until then:
 * a link to a shortcut that does not exist is a button that does nothing.
 */
export function savedShortcutName(): string {
  const value = readJSON<string>(StorageKey.appleShortcut, "");
  return typeof value === "string" ? value.trim() : "";
}

export function saveShortcutName(name: string): void {
  writeJSON(StorageKey.appleShortcut, name.trim());
}

/** True where the Atajos app can exist at all. */
export function canRunShortcuts(): boolean {
  return isIOS() || /Macintosh/.test(navigator.userAgent);
}
