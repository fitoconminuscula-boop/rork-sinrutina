/**
 * Installing the app and keeping it up to date.
 *
 * Two jobs a browser only half-exposes, handled honestly:
 *
 *  - Installing. Chromium hands over a real prompt; Safari never does, and no
 *    amount of wishing changes that. So `installer` reports which of the two
 *    situations we are in, and the UI either offers a button that truly opens
 *    the system dialog or explains the manual steps. It never draws a button
 *    that does nothing.
 *
 *  - Updating. A new version is never swapped in mid-sentence. It waits, and
 *    the app offers to take it.
 */

/** Chromium's install event, which is not in the DOM typings. */
interface InstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: "accepted" | "dismissed" }>;
}

type Listener = () => void;

let deferredPrompt: InstallPromptEvent | null = null;
const installListeners = new Set<Listener>();

function notifyInstall(): void {
  installListeners.forEach((listener) => listener());
}

if (typeof window !== "undefined") {
  window.addEventListener("beforeinstallprompt", (event) => {
    event.preventDefault();
    deferredPrompt = event as InstallPromptEvent;
    notifyInstall();
  });

  window.addEventListener("appinstalled", () => {
    deferredPrompt = null;
    notifyInstall();
  });
}

export const installer = {
  /** True only when a real system dialog is one tap away. */
  canPrompt: (): boolean => deferredPrompt !== null,

  subscribe: (listener: Listener): (() => void) => {
    installListeners.add(listener);
    return () => installListeners.delete(listener);
  },

  /**
   * Opens the browser's own install dialog. Returns what the person actually
   * chose, so the UI never claims an installation that did not happen.
   */
  prompt: async (): Promise<"accepted" | "dismissed" | "unavailable"> => {
    const event = deferredPrompt;
    if (!event) return "unavailable";
    try {
      await event.prompt();
      const { outcome } = await event.userChoice;
      // The prompt is single-use; Chromium fires a fresh one if it still applies.
      deferredPrompt = null;
      notifyInstall();
      return outcome;
    } catch (error) {
      console.warn("SinRutina: el navegador no abrió el diálogo de instalación.", error);
      return "unavailable";
    }
  },
};

let pendingUpdate: (() => void) | null = null;
const updateListeners = new Set<Listener>();

/**
 * A version that has finished downloading and is waiting for permission.
 *
 * Nothing reloads on its own. Someone mid-sentence in the capture field should
 * not lose it because a deploy happened to land.
 */
export const updates = {
  isReady: (): boolean => pendingUpdate !== null,
  subscribe: (listener: Listener): (() => void) => {
    updateListeners.add(listener);
    return () => updateListeners.delete(listener);
  },
  activate: (): void => {
    const activate = pendingUpdate;
    pendingUpdate = null;
    updateListeners.forEach((listener) => listener());
    activate?.();
  },
};

/** Everything the app needs from the browser shell, started once. */
export function startPWA(): void {
  registerServiceWorker((activate) => {
    pendingUpdate = activate;
    updateListeners.forEach((listener) => listener());
  });
  trackKeyboard();
}

/**
 * Registers the offline worker and calls back when a new version is sitting
 * ready. Only in a real build: a service worker in front of the dev server
 * serves yesterday's code and turns every change into a mystery.
 */
function registerServiceWorker(onUpdateReady: (activate: () => void) => void): void {
  if (!import.meta.env.PROD) return;
  if (typeof navigator === "undefined" || !("serviceWorker" in navigator)) return;

  window.addEventListener("load", () => {
    void navigator.serviceWorker
      .register("/sw.js")
      .then((registration) => {
        const offer = (worker: ServiceWorker): void => {
          onUpdateReady(() => {
            worker.postMessage("sr-activar-actualizacion");
          });
        };

        // Already waiting from a previous visit.
        if (registration.waiting && navigator.serviceWorker.controller) offer(registration.waiting);

        registration.addEventListener("updatefound", () => {
          const installing = registration.installing;
          if (!installing) return;
          installing.addEventListener("statechange", () => {
            // No controller means this is the first install, not an update:
            // there is nothing to interrupt and nothing to announce.
            if (installing.state === "installed" && navigator.serviceWorker.controller) offer(installing);
          });
        });
      })
      .catch((error) => {
        console.warn("SinRutina: no se pudo preparar el modo sin conexión.", error);
      });

    let hasReloaded = false;
    navigator.serviceWorker.addEventListener("controllerchange", () => {
      if (hasReloaded) return;
      hasReloaded = true;
      window.location.reload();
    });
  });
}

/**
 * Publishes the on-screen keyboard's height as a custom property.
 *
 * Without this, a sheet with a text field sits underneath the keyboard on iOS,
 * which is the single most obviously "a website" thing an app can do.
 */
function trackKeyboard(): void {
  const viewport = window.visualViewport;
  if (!viewport) return;

  const update = (): void => {
    const overlap = Math.max(0, window.innerHeight - viewport.height - viewport.offsetTop);
    document.documentElement.style.setProperty("--sr-keyboard", `${Math.round(overlap)}px`);
  };

  viewport.addEventListener("resize", update);
  viewport.addEventListener("scroll", update);
  update();
}
