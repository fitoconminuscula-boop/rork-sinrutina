/**
 * SinRutina offline.
 *
 * This is worth doing here in a way it usually is not: every task a person
 * writes already lives in their own browser, in localStorage. Nothing is
 * fetched to show the list, so with the shell cached the app genuinely works
 * with no connection at all — it is not a placeholder screen apologising.
 *
 * What stays out of the cache, deliberately:
 *  - The reading service. An answer from an AI is not a thing to replay from
 *    disk; if there is no connection, the local reader takes over and says so.
 *  - Anything that is not this origin.
 *
 * Bump CACHE_VERSION when the shell changes shape. Build assets are already
 * content-hashed, so their names change on their own.
 */

const CACHE_VERSION = "sinrutina-v2";
const SHELL = ["/", "/manifest.webmanifest", "/icon-192.png", "/icon-512.png", "/apple-touch-icon.png", "/favicon.png"];

self.addEventListener("install", (event) => {
  event.waitUntil(
    (async () => {
      const cache = await caches.open(CACHE_VERSION);
      // One missing file must not abandon the whole install.
      await Promise.allSettled(SHELL.map((path) => cache.add(new Request(path, { cache: "reload" }))));
      await self.skipWaiting();
    })()
  );
});

self.addEventListener("activate", (event) => {
  event.waitUntil(
    (async () => {
      const names = await caches.keys();
      await Promise.all(names.filter((name) => name !== CACHE_VERSION).map((name) => caches.delete(name)));
      await self.clients.claim();
    })()
  );
});

/** The person asked for a page: always try the network, so an update lands. */
async function handlePage(request) {
  try {
    const response = await fetch(request);
    const cache = await caches.open(CACHE_VERSION);
    cache.put("/", response.clone());
    return response;
  } catch {
    const cached = (await caches.match("/")) ?? (await caches.match(request));
    if (cached) return cached;
    throw new Error("offline sin copia del arranque");
  }
}

/** Hashed build files never change under the same name: disk first is safe. */
async function handleAsset(request) {
  const cached = await caches.match(request);
  if (cached) return cached;

  const response = await fetch(request);
  if (response.ok && response.type === "basic") {
    const cache = await caches.open(CACHE_VERSION);
    cache.put(request, response.clone());
  }
  return response;
}

self.addEventListener("fetch", (event) => {
  const { request } = event;
  if (request.method !== "GET") return;

  const url = new URL(request.url);
  if (url.origin !== self.location.origin) return;

  if (request.mode === "navigate") {
    event.respondWith(handlePage(request));
    return;
  }

  if (/\.(?:js|mjs|css|png|svg|webp|woff2?|json|webmanifest)$/.test(url.pathname)) {
    event.respondWith(handleAsset(request));
  }
});

// The page decides when to take an update; a reload under someone's fingers
// while they are reading is its own small betrayal.
self.addEventListener("message", (event) => {
  if (event.data === "sr-activar-actualizacion") void self.skipWaiting();
});
