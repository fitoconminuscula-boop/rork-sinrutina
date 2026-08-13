/**
 * The only part of SinRutina that talks to a network.
 *
 * On the iPhone the reading layer is Apple Intelligence, running on the device
 * itself. A browser has no such model, so this file substitutes it. Two rules
 * make that acceptable:
 *
 * 1. It is optional and switchable, and Ajustes states exactly what is sent.
 * 2. It only ever *proposes*. The deterministic reader stays underneath, so if
 *    the network is gone, refuses, or answers nonsense, the app behaves the same,
 *    only less nuanced. Nothing here is ever required for SinRutina to work.
 *
 * Three routes, tried cheapest first, and the app never hides which one answered:
 *
 * 1. **Groq, through SinRutina's own small Worker** (`functions/index.ts`), on a
 *    free tier. The key lives on that Worker and never in this file: anything a
 *    browser can read is public, so a key shipped inside a page is a key given
 *    away. Text only — Groq has no production vision model.
 * 2. **Gemini, through that same Worker**, on a free Google AI Studio key. This
 *    is the one that can look at a picture, which is why it exists here. It also
 *    reads text when Groq has a bad minute, so a free engine backs up a free one.
 * 3. **Gemini, through the Rork proxy.** No key to configure, so it always works
 *    out of the box — but it is metered, so it sits last.
 *
 * If none of them answer, the deterministic reader in `heuristics.ts` still does,
 * and the interface says which one it was.
 */

const BASE_URL: string = import.meta.env.EXPO_PUBLIC_TOOLKIT_URL ?? "https://toolkit.rork.com";

/** Sent when Rork provides it; the browser runtime supplies delegated auth otherwise. */
const SECRET_KEY: string | undefined = import.meta.env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY;

// MARK: - Groq, through SinRutina's own Worker

/**
 * The Worker in `functions/`. It holds the Groq key and nothing else: no
 * database, no accounts, no memory of anybody. Missing or silent, the reader
 * simply runs on the Rork route instead.
 */
const PROXY_URL: string = (import.meta.env.EXPO_PUBLIC_RORK_FUNCTIONS_URL ?? "").replace(/\/+$/, "");

/** Which models the Worker walks is its business; it only reports the first one. */
const MODEL_NAMES: Record<string, string> = {
  "llama-3.3-70b-versatile": "Llama 3.3 70B",
  "openai/gpt-oss-120b": "GPT-OSS 120B",
  "llama-3.1-8b-instant": "Llama 3.1 8B",
  "pixtral-12b-latest": "Pixtral 12B",
  "pixtral-large-latest": "Pixtral Large",
  "mistral-small-latest": "Mistral Small",
  "mistral-medium-latest": "Mistral Medium",
};

// MARK: - Gemini, through Rork

/**
 * The cheapest model on the proxy that can also read a picture, and one that
 * does not think before answering — for "turn this sentence into a task", the
 * thinking would be paid for in latency the person can feel.
 */
const RORK_MODEL = "google/gemini-2.5-flash-lite";

/** Used only if the first one is unavailable, so a bad minute is not a dead feature. */
const RORK_FALLBACK_MODELS: string[] = ["google/gemini-2.5-flash", "openai/gpt-4.1-nano"];

/** Speech to text, for browsers with no dictation of their own. */
const RORK_TRANSCRIPTION_MODEL = "openai/whisper-1";

// MARK: - Engine identity

export type ReaderEngine = "groq" | "mistral" | "gemini" | "rork";

/** What the app calls the Rork route when Ajustes names it. */
export const RORK_ENGINE_NAME = "Gemini 2.5 Flash-Lite";

export interface ReaderStatus {
  engine: ReaderEngine;
  /** Named in Ajustes, so the interface never says a vague "IA". */
  name: string;
  /**
   * The engine that would read a *picture* right now, which is often not the
   * one that reads text: Groq is the fastest reader here and cannot see at all.
   * Named separately so Ajustes can be specific instead of saying "la IA".
   */
  pictureName: string;
  /** True when something real sits underneath this engine if it fails. */
  hasBackup: boolean;
  /**
   * True when the key is still stored under a browser-visible name. Reported
   * instead of hidden: a half-finished move deserves saying out loud.
   */
  keyIsPublic: boolean;
}

const RORK_STATUS: ReaderStatus = {
  engine: "rork",
  name: RORK_ENGINE_NAME,
  pictureName: RORK_ENGINE_NAME,
  hasBackup: false,
  keyIsPublic: false,
};

/**
 * Which free picture-readers the Worker actually reached. Two of them, from two
 * different companies, because free tiers fail on different days — and because
 * neither is ever assumed: this is only ever what `/groq/estado` reported after
 * spending a real request to check.
 */
let hasFreeMistral = false;
let hasFreeGemini = false;

/**
 * What the browser currently believes about the Worker. It starts as the Rork
 * route, because claiming Groq before anyone has answered would be a guess
 * dressed as a fact. `probeReader()` replaces it with what the Worker says.
 */
let readerStatus: ReaderStatus = RORK_STATUS;

interface ProxyStatusPayload {
  ready?: unknown;
  model?: unknown;
  keyIsPublic?: unknown;
  geminiReady?: unknown;
  geminiModel?: unknown;
  mistralReady?: unknown;
  mistralModel?: unknown;
}

/** A model id turned into something worth showing a person. */
function named(model: unknown, fallback: string): string {
  const id = typeof model === "string" ? model : "";
  if (id.length === 0) return fallback;
  return MODEL_NAMES[id] ?? id;
}

/**
 * Asks the Worker which keys it holds. Called once at startup, and again
 * whenever the person switches the extended reader back on.
 *
 * A failure here means "no free engine today", never "no reader": the Rork route
 * and the deterministic local reader are both still underneath.
 */
export async function probeReader(): Promise<ReaderStatus> {
  if (PROXY_URL.length === 0) {
    hasFreeGemini = false;
    readerStatus = RORK_STATUS;
    return readerStatus;
  }

  try {
    const response = await fetch(`${PROXY_URL}/groq/estado`, { signal: AbortSignal.timeout(8_000) });
    if (!response.ok) throw new GatewayError(response.status, messageFor(response.status));

    const payload = (await response.json()) as ProxyStatusPayload;
    hasFreeMistral = payload.mistralReady === true;
    hasFreeGemini = payload.geminiReady === true;

    // Whichever free engine can actually see, in the order the chain tries them.
    // Falls back to the metered route's name only when neither answered.
    const mistralName = named(payload.mistralModel, "Mistral");
    const geminiName = named(payload.geminiModel, "Gemini");
    const pictureName = hasFreeMistral ? mistralName : hasFreeGemini ? geminiName : RORK_ENGINE_NAME;

    if (payload.ready !== true) {
      // No Groq, but a free picture-reader is still a free engine worth naming.
      readerStatus = hasFreeMistral
        ? { engine: "mistral", name: mistralName, pictureName, hasBackup: true, keyIsPublic: false }
        : hasFreeGemini
          ? { engine: "gemini", name: geminiName, pictureName, hasBackup: true, keyIsPublic: false }
          : RORK_STATUS;
      return readerStatus;
    }

    const groqName = named(payload.model, "");
    readerStatus = {
      engine: "groq",
      name: groqName.length > 0 ? `${groqName} en Groq` : "Groq",
      pictureName,
      hasBackup: true,
      keyIsPublic: payload.keyIsPublic === true,
    };
  } catch {
    // A Worker that does not answer is not worth an error message: it only means
    // another engine reads today.
    hasFreeMistral = false;
    hasFreeGemini = false;
    readerStatus = RORK_STATUS;
  }

  return readerStatus;
}

/** The engine that would answer right now, for anything that needs to name it. */
export function currentReader(): ReaderStatus {
  return readerStatus;
}

/** How the reading was produced. The interface always says which one it was. */
export type ReaderSource = "local" | "extended";

export interface AskOptions {
  system: string;
  user: string;
  /** A `data:` URL, when the words are inside a picture instead of in the text. */
  imageDataUrl?: string;
  maxTokens?: number;
  /** Same value across retries of one logical action, so a retry is never billed twice. */
  idempotencyKey: string;
  signal?: AbortSignal;
}

type ContentPart =
  | { type: "text"; text: string }
  | { type: "image_url"; image_url: { url: string } };

interface ChatChoice {
  message?: { content?: string | null };
}

interface ChatResponse {
  choices?: ChatChoice[];
}

/** A failure the person can understand, without leaking internals into the UI. */
export class GatewayError extends Error {
  readonly status: number;
  readonly userMessage: string;

  constructor(status: number, userMessage: string) {
    super(`gateway ${status}`);
    this.name = "GatewayError";
    this.status = status;
    this.userMessage = userMessage;
  }
}

function messageFor(status: number): string {
  if (status === 401) return "La lectura ampliada no está disponible ahora mismo.";
  if (status === 402) return "La lectura ampliada no está disponible temporalmente.";
  if (status === 429) return "Demasiadas peticiones seguidas. Inténtalo en un momento.";
  return "No he podido conectar. He leído tu texto aquí mismo.";
}

/** A key that does not work is a fact worth saying out loud, not routing around. */
const BAD_KEY_MESSAGE = "La clave del lector no es válida o se ha agotado. He leído tu texto aquí mismo.";

function retryDelay(response: Response, attempt: number): number {
  const header = response.headers.get("retry-after");
  if (header) {
    const seconds = Number.parseInt(header, 10);
    if (Number.isFinite(seconds) && seconds >= 0) return Math.min(seconds * 1000, 8000);
    const date = Date.parse(header);
    if (Number.isFinite(date)) return Math.min(Math.max(date - Date.now(), 0), 8000);
  }
  return Math.min(600 * 2 ** attempt, 4000);
}

const wait = (ms: number): Promise<void> => new Promise((resolve) => window.setTimeout(resolve, ms));

/** Nothing arrived, or something arrived that was not an answer. */
function contentOf(payload: ChatResponse): string {
  const content = payload.choices?.[0]?.message?.content;
  if (typeof content === "string" && content.trim().length > 0) return content;
  throw new GatewayError(200, messageFor(0));
}

/**
 * One question, one plain-text answer, down the cheapest route that can do it.
 *
 * Free routes first, metered last, and within the free ones the fastest first:
 * Groq, then Mistral, then Gemini, then the Rork proxy.
 *
 * Pictures skip Groq entirely, because Groq cannot see them — that is not a
 * configuration choice, its catalogue simply has no vision model. So a
 * photographed letter starts at Mistral and has Gemini behind it: two free tiers
 * from two companies, which do not usually run out on the same day.
 *
 * A refused key stops the whole chain — silently rerouting around it would hide
 * a broken setting forever. Everything else (rate limit, outage, dead network)
 * falls through to the next engine, each of which is real, not a pretend one.
 */
export async function ask(options: AskOptions): Promise<string> {
  const wantsPicture = typeof options.imageDataUrl === "string";

  if (readerStatus.engine === "groq" && !wantsPicture) {
    try {
      return await askProxy(options);
    } catch (error) {
      if (options.signal?.aborted) throw error;
      if (error instanceof GatewayError && error.status === 401) throw error;
      console.warn("SinRutina: Groq no ha respondido; probando la siguiente ruta.");
    }
  }

  if (hasFreeMistral) {
    try {
      return await askMistralProxy(options);
    } catch (error) {
      if (options.signal?.aborted) throw error;
      if (error instanceof GatewayError && error.status === 401) throw error;
      console.warn("SinRutina: Mistral no ha respondido; probando la siguiente ruta.");
    }
  }

  if (hasFreeGemini) {
    try {
      return await askGeminiProxy(options);
    } catch (error) {
      if (options.signal?.aborted) throw error;
      if (error instanceof GatewayError && error.status === 401) throw error;
      console.warn("SinRutina: Gemini propio no ha respondido; leyendo por la ruta de Rork.");
    }
  }

  return askRork(options);
}

/**
 * Mistral through SinRutina's own Worker, on a free La Plateforme key.
 *
 * Like the Gemini route, this one can look at a picture without it being
 * metered. Unlike it, its free tier has no fixed daily ceiling, which is why a
 * photographed page tries here first.
 */
async function askMistralProxy(options: AskOptions): Promise<string> {
  const { system, user, imageDataUrl, maxTokens = 320, signal } = options;

  const timeout = new AbortController();
  // A picture takes longer to read than a sentence, and is worth waiting for.
  const timer = window.setTimeout(() => timeout.abort(), imageDataUrl ? 30_000 : 20_000);
  const onAbort = (): void => timeout.abort();
  signal?.addEventListener("abort", onAbort);

  try {
    const response = await fetch(`${PROXY_URL}/mistral/leer`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ system, user, imageDataUrl, maxTokens }),
      signal: timeout.signal,
    });

    const payload = (await response.json().catch(() => null)) as ProxyReply | null;

    if (response.ok && typeof payload?.text === "string" && payload.text.trim().length > 0) {
      return payload.text;
    }

    if (response.status === 401) throw new GatewayError(401, BAD_KEY_MESSAGE);

    // The Worker has no Mistral key after all. Remember it, so the next reading
    // goes straight to the next engine instead of asking again for nothing.
    if (response.status === 503) {
      hasFreeMistral = false;
      throw new GatewayError(503, messageFor(503));
    }

    throw new GatewayError(response.status, messageFor(response.status));
  } catch (error) {
    if (signal?.aborted) throw error;
    if (error instanceof GatewayError) throw error;
    throw new GatewayError(0, messageFor(0));
  } finally {
    window.clearTimeout(timer);
    signal?.removeEventListener("abort", onAbort);
  }
}

interface ProxyReply {
  text?: unknown;
  error?: { code?: unknown; message?: unknown };
}

/**
 * SinRutina's own Worker, which forwards to Groq with the key it holds.
 *
 * The model list and its retries live on the Worker, so this side is one
 * request: a model that is renamed or retired becomes a server fix instead of a
 * stale page sitting in somebody's tab.
 */
async function askProxy(options: AskOptions): Promise<string> {
  const { system, user, maxTokens = 320, signal } = options;

  const timeout = new AbortController();
  const timer = window.setTimeout(() => timeout.abort(), 20_000);
  const onAbort = (): void => timeout.abort();
  signal?.addEventListener("abort", onAbort);

  try {
    const response = await fetch(`${PROXY_URL}/groq/leer`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ system, user, maxTokens }),
      signal: timeout.signal,
    });

    const payload = (await response.json().catch(() => null)) as ProxyReply | null;

    if (response.ok && typeof payload?.text === "string" && payload.text.trim().length > 0) {
      return payload.text;
    }

    // A rejected key is settled, and worth saying rather than routing around.
    if (response.status === 401) throw new GatewayError(401, BAD_KEY_MESSAGE);

    // The Worker has no key after all. Remember that, so the next reading goes
    // straight to the other engine instead of asking again for nothing.
    if (response.status === 503) {
      readerStatus = RORK_STATUS;
      throw new GatewayError(503, messageFor(503));
    }

    throw new GatewayError(response.status, messageFor(response.status));
  } catch (error) {
    if (signal?.aborted) throw error;
    if (error instanceof GatewayError) throw error;
    throw new GatewayError(0, messageFor(0));
  } finally {
    window.clearTimeout(timer);
    signal?.removeEventListener("abort", onAbort);
  }
}

/**
 * Gemini through SinRutina's own Worker, on a free Google AI Studio key.
 *
 * This is the only route that can look at a picture without it being metered,
 * which is why a photograph of a letter costs nothing to read here. The model
 * list and its retries live on the Worker, same as the Groq route.
 */
async function askGeminiProxy(options: AskOptions): Promise<string> {
  const { system, user, imageDataUrl, maxTokens = 320, signal } = options;

  const timeout = new AbortController();
  // A picture takes longer to read than a sentence, and is worth waiting for.
  const timer = window.setTimeout(() => timeout.abort(), imageDataUrl ? 30_000 : 20_000);
  const onAbort = (): void => timeout.abort();
  signal?.addEventListener("abort", onAbort);

  try {
    const response = await fetch(`${PROXY_URL}/gemini/leer`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ system, user, imageDataUrl, maxTokens }),
      signal: timeout.signal,
    });

    const payload = (await response.json().catch(() => null)) as ProxyReply | null;

    if (response.ok && typeof payload?.text === "string" && payload.text.trim().length > 0) {
      return payload.text;
    }

    if (response.status === 401) throw new GatewayError(401, BAD_KEY_MESSAGE);

    // The Worker has no Gemini key after all. Remember it, so the next reading
    // goes straight to the metered route instead of asking again for nothing.
    if (response.status === 503) {
      hasFreeGemini = false;
      throw new GatewayError(503, messageFor(503));
    }

    throw new GatewayError(response.status, messageFor(response.status));
  } catch (error) {
    if (signal?.aborted) throw error;
    if (error instanceof GatewayError) throw error;
    throw new GatewayError(0, messageFor(0));
  } finally {
    window.clearTimeout(timer);
    signal?.removeEventListener("abort", onAbort);
  }
}

/**
 * Gemini through the Rork proxy. Needs no key at all, so it is the route that
 * always works — and it is metered, so it is the last one tried. Retries only
 * what is worth retrying, and gives up quickly: a reader that takes ten seconds
 * is a reader nobody waits for.
 */
async function askRork(options: AskOptions): Promise<string> {
  const { system, user, imageDataUrl, maxTokens = 320, idempotencyKey, signal } = options;

  const content: string | ContentPart[] = imageDataUrl
    ? [
        { type: "text", text: user },
        { type: "image_url", image_url: { url: imageDataUrl } },
      ]
    : user;

  const body = JSON.stringify({
    model: RORK_MODEL,
    temperature: 0,
    max_tokens: maxTokens,
    messages: [
      { role: "system", content: system },
      { role: "user", content },
    ],
    providerOptions: { gateway: { models: RORK_FALLBACK_MODELS } },
  });

  let lastError: GatewayError = new GatewayError(0, messageFor(0));

  for (let attempt = 0; attempt <= 2; attempt += 1) {
    const timeout = new AbortController();
    const timer = window.setTimeout(() => timeout.abort(), 14_000);
    const onAbort = (): void => timeout.abort();
    signal?.addEventListener("abort", onAbort);

    try {
      const response = await fetch(`${BASE_URL}/v2/vercel/v1/chat/completions`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "idempotency-key": idempotencyKey,
          ...authHeaders(),
        },
        body,
        signal: timeout.signal,
      });

      if (response.ok) return contentOf((await response.json()) as ChatResponse);

      // 401 and 402 are settled facts: retrying only burns the person's time.
      if (response.status === 401 || response.status === 402 || response.status === 413) {
        throw new GatewayError(response.status, messageFor(response.status));
      }

      lastError = new GatewayError(response.status, messageFor(response.status));
      if (attempt === 2) throw lastError;
      await wait(retryDelay(response, attempt));
    } catch (error) {
      if (signal?.aborted) throw error;
      if (error instanceof GatewayError && (error.status === 401 || error.status === 402)) throw error;
      lastError = error instanceof GatewayError ? error : new GatewayError(0, messageFor(0));
      if (attempt === 2) throw lastError;
      await wait(Math.min(600 * 2 ** attempt, 4000));
    } finally {
      window.clearTimeout(timer);
      signal?.removeEventListener("abort", onAbort);
    }
  }

  throw lastError;
}

function authHeaders(): Record<string, string> {
  return SECRET_KEY ? { Authorization: `Bearer ${SECRET_KEY}` } : {};
}

/**
 * Models sometimes wrap JSON in prose or a code fence. Rather than fail on that,
 * take the first balanced object and let the caller validate every field.
 */
export function parseObject(raw: string): Record<string, unknown> | null {
  const start = raw.indexOf("{");
  if (start < 0) return null;

  let depth = 0;
  let insideString = false;
  let isEscaped = false;

  for (let index = start; index < raw.length; index += 1) {
    const character = raw[index];

    if (insideString) {
      if (isEscaped) isEscaped = false;
      else if (character === "\\") isEscaped = true;
      else if (character === '"') insideString = false;
      continue;
    }

    if (character === '"') insideString = true;
    else if (character === "{") depth += 1;
    else if (character === "}") {
      depth -= 1;
      if (depth === 0) {
        try {
          const parsed: unknown = JSON.parse(raw.slice(start, index + 1));
          return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : null;
        } catch {
          return null;
        }
      }
    }
  }

  return null;
}

/** A fresh key per logical user action, reused across that action's retries. */
export function newIdempotencyKey(): string {
  return crypto.randomUUID();
}

// MARK: - Speech to text

/**
 * Turns a recording into text. Used only by browsers that have no dictation of
 * their own, and only with the extended reader switched on: the audio leaves the
 * browser for exactly this, and is never stored anywhere.
 */
export async function transcribe(audio: Blob, signal?: AbortSignal): Promise<string> {
  if (readerStatus.engine === "groq") {
    try {
      return await transcribeProxy(audio, signal);
    } catch (error) {
      if (signal?.aborted) throw error;
      if (error instanceof GatewayError && error.status === 401) throw error;
      console.warn("SinRutina: Groq no ha transcrito; probando la ruta de Rork.");
    }
  }
  return transcribeRork(audio, signal);
}

/** Whisper, reached through SinRutina's Worker so the key stays off this page. */
async function transcribeProxy(audio: Blob, signal?: AbortSignal): Promise<string> {
  const form = new FormData();
  form.append("file", audio, `dictado.${extensionFor(audio.type)}`);

  const response = await fetch(`${PROXY_URL}/groq/dictado`, {
    method: "POST",
    body: form,
    signal,
  });

  const payload = (await response.json().catch(() => null)) as ProxyReply | null;

  if (!response.ok) {
    if (response.status === 401) {
      throw new GatewayError(401, "La clave de Groq no es válida. Puedes escribirlo a mano.");
    }
    if (response.status === 503) readerStatus = RORK_STATUS;
    throw new GatewayError(response.status, transcriptionMessage(response.status));
  }

  return readTranscript(payload ?? {});
}

/** Whisper, through the Rork proxy, when the Worker cannot transcribe. */
async function transcribeRork(audio: Blob, signal?: AbortSignal): Promise<string> {
  const base64 = await toBase64(audio);
  const mediaType = audio.type.split(";")[0] || "audio/webm";

  const response = await fetch(`${BASE_URL}/v2/vercel/v4/ai/transcription-model`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "ai-model-id": RORK_TRANSCRIPTION_MODEL,
      "ai-gateway-protocol-version": "0.0.1",
      ...authHeaders(),
    },
    body: JSON.stringify({ audio: base64, mediaType }),
    signal,
  });

  if (!response.ok) {
    throw new GatewayError(response.status, transcriptionMessage(response.status));
  }

  return readTranscript((await response.json()) as { text?: unknown });
}

function readTranscript(payload: { text?: unknown }): string {
  const text = typeof payload.text === "string" ? payload.text.trim() : "";
  if (text.length === 0) throw new GatewayError(200, "No he entendido nada en esa grabación.");
  return text;
}

/** Whisper decides how to decode from the file name, so it has to be right. */
function extensionFor(mimeType: string): string {
  const base = mimeType.split(";")[0]?.trim() ?? "";
  switch (base) {
    case "audio/mp4":
    case "audio/x-m4a":
      return "m4a";
    case "audio/mpeg":
      return "mp3";
    case "audio/ogg":
      return "ogg";
    case "audio/wav":
    case "audio/x-wav":
      return "wav";
    default:
      return "webm";
  }
}

function transcriptionMessage(status: number): string {
  if (status === 401 || status === 402) return "El dictado no está disponible ahora mismo.";
  if (status === 413) return "Esa grabación es demasiado larga. Prueba con una frase más corta.";
  if (status === 429) return "Demasiadas peticiones seguidas. Inténtalo en un momento.";
  return "No he podido transcribir el audio. Puedes escribirlo a mano.";
}

function toBase64(blob: Blob): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => {
      const result = typeof reader.result === "string" ? reader.result : "";
      const comma = result.indexOf(",");
      resolve(comma < 0 ? result : result.slice(comma + 1));
    };
    reader.onerror = () => reject(new GatewayError(0, "No he podido leer la grabación."));
    reader.readAsDataURL(blob);
  });
}
