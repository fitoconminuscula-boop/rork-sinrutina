/**
 * Everything SinRutina knows stays in this browser, in localStorage. There is no
 * account, no server and no sync: closing the tab changes nothing, clearing the
 * browser's site data erases it for good. That trade is stated plainly in Ajustes.
 */

const PREFIX = "sinrutina.";

export const StorageKey = {
  tasks: `${PREFIX}tasks.v1`,
  appearance: `${PREFIX}appearance.v1`,
  demoMode: `${PREFIX}demoMode.v1`,
  hasLaunched: `${PREFIX}hasLaunched.v1`,
  extendedReader: `${PREFIX}extendedReader.v1`,
  /** Name of the shortcut in the Atajos app this person made for themselves. */
  appleShortcut: `${PREFIX}appleShortcut.v1`,
} as const;

export function readJSON<T>(key: string, fallback: T): T {
  try {
    const raw = window.localStorage.getItem(key);
    if (raw === null) return fallback;
    return JSON.parse(raw) as T;
  } catch (error) {
    console.warn(`SinRutina: no se pudo leer "${key}" del almacenamiento local.`, error);
    return fallback;
  }
}

export function writeJSON(key: string, value: unknown): void {
  try {
    window.localStorage.setItem(key, JSON.stringify(value));
  } catch (error) {
    // Private browsing and full quotas both land here. The app keeps working in
    // memory; only persistence is lost, and nothing pretends otherwise.
    console.warn(`SinRutina: no se pudo guardar "${key}" en el almacenamiento local.`, error);
  }
}

export function removeKey(key: string): void {
  try {
    window.localStorage.removeItem(key);
  } catch (error) {
    console.warn(`SinRutina: no se pudo borrar "${key}".`, error);
  }
}

/** True when this browser will actually keep what we write. */
export function canPersist(): boolean {
  try {
    const probe = `${PREFIX}probe`;
    window.localStorage.setItem(probe, "1");
    window.localStorage.removeItem(probe);
    return true;
  } catch {
    return false;
  }
}
