/**
 * SinRutina's only server.
 *
 * The web version has no backend of its own: everything a person writes lives in
 * their own browser. This Worker exists for exactly one reason — a browser
 * cannot hold an API key. Anything sent to the browser is readable by anyone who
 * opens the developer tools, so the Groq key stays here and the browser asks
 * this Worker instead.
 *
 * What this file is NOT: it is not a database, it is not an account system, and
 * it does not remember anybody. Nothing that passes through is stored, and no
 * request body is ever logged — the text a person is about to turn into a task
 * is theirs, not something to keep in a server log.
 *
 * Three upstreams, all on free tiers, chosen so the reading layer costs nothing:
 *
 * - **Groq** reads text and transcribes dictation. It is very fast, which is the
 *   whole point: a reader nobody waits for. It cannot see pictures — this key's
 *   catalogue has no vision model at all.
 * - **Mistral**, on a La Plateforme key, reads text *and* pictures through
 *   Pixtral. Its free tier needs no card and has no fixed daily cap, which makes
 *   it the steadiest free way to read a photograph of a letter.
 * - **Google Gemini**, on an AI Studio key, does the same job. Kept as a second
 *   pair of eyes: free tiers change without notice, and two of them fail on
 *   different days.
 *
 * Any of them can be absent, and being *configured* is never taken as proof of
 * working — each is probed with a real request before the app promises it.
 * `/groq/estado` reports what genuinely answered, and the browser keeps a
 * deterministic reader underneath regardless.
 */

type Env = {
  /** Preferred: a server-only key, never sent to any browser. */
  GROQ_API_KEY?: string;
  /**
   * Google AI Studio key, free to create and free to use within its rate
   * limits. Server-only, deliberately without a `VITE_` prefix so no build can
   * inline it into a page.
   */
  GEMINI_API_KEY?: string;
  /**
   * Mistral La Plateforme key. Free to create, no card required, and the free
   * tier carries no fixed daily request cap — only a rate limit. Server-only,
   * deliberately without a `VITE_` prefix so no build can inline it into a page.
   */
  MISTRAL_API_KEY?: string;
  /**
   * Accepted only so an existing install keeps working while the key is moved
   * to `GROQ_API_KEY`. The name is misleading here: inside the Worker it is a
   * normal server value, but the `VITE_` prefix means the web build *may* also
   * inline it into the browser bundle, which is the very thing this proxy is
   * built to avoid. `/groq/estado` reports it so Ajustes can say so out loud.
   */
  VITE_GROQ_API_KEY?: string;
};

const GROQ_URL = "https://api.groq.com/openai/v1";

/**
 * Preference order, and this one is measured rather than assumed. `/groq/modelos
 * ?probar=1` asks each candidate the app's real question, in the JSON mode the
 * reader depends on. On this key, only these two answered it:
 *
 *   llama-3.3-70b-versatile  200, ~220 ms  — better Spanish, better structure
 *   llama-3.1-8b-instant     200,  ~97 ms  — faster, shallower
 *
 * Two plausible-looking candidates were rejected by that same probe, which is
 * exactly why the probe exists:
 *
 *   qwen/qwen3.6-27b   400 "Failed to validate JSON"
 *   openai/gpt-oss-120b  400 "Failed to validate JSON"
 *
 * Both are real, listed, capable models — they simply do not honour Groq's JSON
 * mode reliably, and this reader asks for nothing else. Kimi is not offered by
 * this key at all. Re-run the probe before changing this list.
 */
const GROQ_PREFERRED: string[] = ["llama-3.3-70b-versatile", "llama-3.1-8b-instant"];

/** Never chat models, whatever else the catalogue happens to list. */
const NOT_CHAT = ["whisper", "prompt-guard", "safeguard", "tts"];

/** What this key actually reaches, learned once per Worker instance. */
let knownGroqModels: string[] | null = null;

const TRANSCRIPTION_MODEL = "whisper-large-v3-turbo";

const MISTRAL_URL = "https://api.mistral.ai/v1";

/**
 * Vision-capable first, because pictures are the whole reason this engine is
 * here — Groq cannot see, and this is the free tier that reads a photographed
 * letter without a card on file.
 *
 * As with Groq, this is a preference and not an assumption: `resolveMistralModels`
 * keeps only the names the key genuinely reaches, and `/mistral/modelos?probar=1`
 * hands each one a real PNG. On this key that probe found:
 *
 *   pixtral-12b-latest      not reachable — absent from this key's catalogue
 *   pixtral-large-latest    not reachable — absent from this key's catalogue
 *   mistral-small-latest    200, ~560 ms, read the picture
 *   mistral-medium-latest   200, ~413 ms, read the picture
 *
 * So the Pixtral names stay as a preference for keys that do reach them, while
 * this key quietly lands on mistral-small-latest — which turned out to see just
 * as well. Worth knowing before assuming "no Pixtral" meant "no eyes".
 */
const MISTRAL_PREFERRED: string[] = [
  "pixtral-12b-latest",
  "mistral-small-latest",
  "pixtral-large-latest",
  "mistral-medium-latest",
];

/** Not readers, whatever else the catalogue lists. */
const NOT_READERS = ["embed", "moderation", "ocr", "codestral", "voxtral", "devstral"];

let knownMistralModels: string[] | null = null;

/**
 * Whether the Mistral key can actually generate, not merely list. Same reasoning
 * as Gemini's health check: a key with no quota left answers the catalogue
 * perfectly and refuses every real request, which would let the app promise
 * picture reading and fail at the exact moment it was needed.
 */
let mistralHealth: GeminiHealth | null = null;

const GEMINI_URL = "https://generativelanguage.googleapis.com/v1beta/models";

/**
 * Cheapest first, and both on the free tier. Flash-Lite does not think before
 * answering, which for "turn this sentence into a task" is exactly right: the
 * thinking tokens would be paid for in latency the person can feel.
 *
 * This is a *preference*, not an assumption. Google renames and retires model
 * ids on its own schedule, and a hard-coded name that quietly 404s looks exactly
 * like "the AI is broken" from the outside. `resolveGeminiModels` asks the key
 * what it can actually reach and keeps only the names that really answer.
 */
const GEMINI_PREFERRED: string[] = [
  "gemini-flash-lite-latest",
  "gemini-flash-latest",
  "gemini-2.5-flash-lite",
  "gemini-2.5-flash",
];

/**
 * What this key genuinely offers, learned once per Worker instance. Null means
 * "not asked yet" — never "none", which is a different thing and would be a
 * guess dressed as a fact.
 */
let knownGeminiModels: string[] | null = null;

/**
 * Whether this key can actually *generate*, which is a different question from
 * whether it can list models. A key with no credit left answers the catalogue
 * perfectly and then refuses every real request — so listing alone would let the
 * app promise picture reading and fail at the exact moment it was needed.
 *
 * Re-checked periodically rather than remembered forever, because a depleted
 * account can be topped up and a quota window does reopen.
 */
interface GeminiHealth {
  canGenerate: boolean;
  /** Google's own words, so Ajustes can say why instead of just "no". */
  reason: string;
  at: number;
}

let geminiHealth: GeminiHealth | null = null;

const HEALTH_TTL_MS = 10 * 60_000;

/** A photo of a page, not a photo library. Bigger than this is a mistake. */
const MAX_IMAGE_BYTES = 6 * 1024 * 1024;

/** Bounds, so a stray caller cannot turn one request into a large bill. */
const MAX_SYSTEM_CHARS = 4_000;
const MAX_USER_CHARS = 12_000;
const MAX_OUTPUT_TOKENS = 600;
const MAX_AUDIO_BYTES = 8 * 1024 * 1024;
const UPSTREAM_TIMEOUT_MS = 20_000;

/**
 * Best-effort throttle, and deliberately described as such.
 *
 * A Worker is not one long-lived process: this map lives in whichever instance
 * happens to serve the request and is emptied whenever that instance recycles.
 * It reliably stops one browser hammering the endpoint in a loop. It is NOT a
 * hard spending guarantee — the real ceiling is the spend limit set on the Groq
 * key itself, which is where a limit actually belongs.
 */
const RATE_WINDOW_MS = 60_000;
const RATE_MAX_REQUESTS = 30;
const recentCalls = new Map<string, number[]>();

const ALLOWED_ORIGIN_SUFFIXES: string[] = [".rork.live", ".rork.app", ".rork.com"];

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin");
    const cors = corsHeaders(origin);

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: cors });
    }

    if (url.pathname === "/ping") {
      return json({ ok: true, now: new Date().toISOString() }, 200, cors);
    }

    // A browser call from an unknown site is refused. This keeps the endpoint
    // from being casually embedded in someone else's page; it is not a security
    // boundary, because a request made outside a browser carries no Origin at
    // all. The spend limit on the key is the real backstop.
    if (origin !== null && !isAllowedOrigin(origin)) {
      return json({ error: { code: "origen", message: "Origen no permitido." } }, 403, cors);
    }

    if (url.pathname === "/groq/estado") {
      return json(await status(env, request.signal), 200, cors);
    }

    // Same diagnostic for Groq. Model ids get renamed and retired without
    // notice, and "which names does this key actually reach today?" is the
    // first question worth asking when reading breaks.
    if (url.pathname === "/groq/modelos") {
      const key = keyOf(env);
      if (key.length === 0) return json({ configured: false, models: [] }, 200, cors);
      const listed = await fetch(`${GROQ_URL}/models`, {
        headers: { Authorization: `Bearer ${key}` },
        signal: withTimeout(request.signal),
      });
      const payload = (await listed.json().catch(() => null)) as { data?: { id?: string }[] } | null;
      const models = (payload?.data ?? []).map((model) => model.id ?? "").filter((id) => id.length > 0);

      // `?probar=1` goes further and actually asks each candidate to answer.
      // Being listed and being usable are different things — a model can appear
      // in the catalogue and still refuse the JSON mode this app depends on.
      if (url.searchParams.get("probar") === "1") {
        return json({ configured: true, probes: await probeGroq(key, request.signal) }, 200, cors);
      }

      return json({ configured: true, models: models.sort() }, 200, cors);
    }

    // Diagnostic, and deliberately kept: when reading stops working the first
    // question is always "does this key still reach a model?". It returns model
    // names only — never the key, never anything a person wrote.
    if (url.pathname === "/gemini/modelos") {
      const key = geminiKeyOf(env);
      if (key.length === 0) {
        return json({ configured: false, models: [] }, 200, cors);
      }
      return json({ configured: true, models: await resolveGeminiModels(key, request.signal) }, 200, cors);
    }

    if (url.pathname === "/groq/leer" && request.method === "POST") {
      return guarded(request, keyOf(env), cors, readText);
    }

    if (url.pathname === "/groq/dictado" && request.method === "POST") {
      return guarded(request, keyOf(env), cors, transcribe);
    }

    // Text or a picture. Same route either way: what changes is whether the
    // words arrived typed or photographed.
    if (url.pathname === "/gemini/leer" && request.method === "POST") {
      return guarded(request, geminiKeyOf(env), cors, readGemini);
    }

    if (url.pathname === "/mistral/modelos") {
      const key = mistralKeyOf(env);
      if (key.length === 0) return json({ configured: false, models: [] }, 200, cors);

      // `?probar=1` hands each candidate an actual picture. A catalogue saying
      // `vision: true` is a claim; accepting an image is the fact. Picking the
      // model that reads photographs deserves the fact.
      if (url.searchParams.get("probar") === "1") {
        return json({ configured: true, probes: await probeMistral(key, request.signal) }, 200, cors);
      }

      return json({ configured: true, models: await resolveMistralModels(key, request.signal) }, 200, cors);
    }

    // The other pair of eyes. Same contract as `/gemini/leer`, so the browser
    // can fall from one to the other without changing how it asks.
    if (url.pathname === "/mistral/leer" && request.method === "POST") {
      return guarded(request, mistralKeyOf(env), cors, readMistral);
    }

    return json({ error: { code: "ruta", message: "No existe esa ruta." } }, 404, cors);
  },
} satisfies ExportedHandler<Env>;

// MARK: - Status

interface Status {
  /**
   * True when this Worker's Groq key actually reaches a chat model — not merely
   * that someone filled in the setting. The browser names the engine from this,
   * so a hopeful `true` here would become a promise the app cannot keep.
   */
  ready: boolean;
  /** The model that answers first, so Ajustes can name it instead of saying "IA". */
  model: string;
  transcription: string;
  /**
   * True when the key is still stored under the `VITE_` name, which the web
   * build may also inline into the browser. Surfaced rather than hidden: a
   * half-finished move is worth telling the truth about.
   */
  keyIsPublic: boolean;
  /**
   * True when a Gemini key is configured here. The browser uses this to decide
   * whether pictures can be read for free through this Worker, or have to take
   * the metered route. It is never assumed — only ever reported.
   */
  geminiReady: boolean;
  geminiModel: string;
  /**
   * Why Gemini is unavailable, in Google's own words, when it is. Empty when it
   * works. Carried all the way to Ajustes so a broken key reads as a fixable
   * fact rather than as the app being mysteriously worse today.
   */
  geminiNote: string;
  /**
   * The same three facts for Mistral. Reported separately rather than merged
   * into one "can read pictures" flag, because when picture reading stops
   * working the useful question is *which* engine stopped and why.
   */
  mistralReady: boolean;
  mistralModel: string;
  mistralNote: string;
}

/**
 * A key being present is not the same as a key that works, and this endpoint is
 * what Ajustes believes. So `geminiReady` means "this key reached a real model",
 * not "someone filled in the setting" — otherwise the app would promise picture
 * reading and then fail at the moment it is needed.
 */
async function status(env: Env, signal: AbortSignal): Promise<Status> {
  const isPrivate = (env.GROQ_API_KEY ?? "").trim().length > 0;
  const geminiKey = geminiKeyOf(env);
  const health = geminiKey.length > 0 ? await checkGemini(geminiKey, signal) : null;
  const models = geminiKey.length > 0 ? await resolveGeminiModels(geminiKey, signal) : [];

  const groqKey = keyOf(env);
  const groqModels = groqKey.length > 0 ? await resolveGroqModels(groqKey, signal) : [];

  const mistralKey = mistralKeyOf(env);
  const mistralOk = mistralKey.length > 0 ? await checkMistral(mistralKey, signal) : null;
  const mistralModels = mistralKey.length > 0 ? await resolveMistralModels(mistralKey, signal) : [];

  return {
    ready: groqModels.length > 0,
    model: groqModels[0] ?? "",
    transcription: TRANSCRIPTION_MODEL,
    keyIsPublic: !isPrivate && (env.VITE_GROQ_API_KEY ?? "").trim().length > 0,
    geminiReady: health?.canGenerate === true,
    geminiModel: health?.canGenerate === true ? (models[0] ?? "") : "",
    geminiNote: health === null ? "" : health.canGenerate ? "" : health.reason,
    mistralReady: mistralOk?.canGenerate === true,
    mistralModel: mistralOk?.canGenerate === true ? (mistralModels[0] ?? "") : "",
    mistralNote: mistralOk === null ? "" : mistralOk.canGenerate ? "" : mistralOk.reason,
  };
}

/**
 * The same tiny spend-one-request check used for Gemini, for the same reason: a
 * configured key and a working key are different things, and only one of them
 * is worth telling the person about.
 */
async function checkMistral(key: string, signal: AbortSignal): Promise<GeminiHealth> {
  const now = Date.now();
  if (mistralHealth !== null && now - mistralHealth.at < HEALTH_TTL_MS) return mistralHealth;

  const models = await resolveMistralModels(key, signal);
  if (models.length === 0) {
    mistralHealth = { canGenerate: false, reason: "Esta clave no llega a ning\u00fan modelo.", at: now };
    return mistralHealth;
  }

  try {
    const response = await callMistral(key, models[0], "Responde solo con {}", "ok", null, 8, signal);
    if (response.ok) {
      mistralHealth = { canGenerate: true, reason: "", at: now };
      return mistralHealth;
    }
    mistralHealth = { canGenerate: false, reason: await upstreamDetail(response), at: now };
  } catch (error) {
    // A network blip is not proof the key is dead, so it is not remembered.
    return {
      canGenerate: false,
      reason: error instanceof Error ? error.message : "No he podido comprobarlo.",
      at: 0,
    };
  }

  return mistralHealth;
}

/**
 * Spends one deliberately tiny request to find out whether this key still
 * works. That is the only way to tell a healthy key from an exhausted one, and
 * a wrong answer here becomes a promise the app cannot keep.
 */
async function checkGemini(key: string, signal: AbortSignal): Promise<GeminiHealth> {
  const now = Date.now();
  if (geminiHealth !== null && now - geminiHealth.at < HEALTH_TTL_MS) return geminiHealth;

  const models = await resolveGeminiModels(key, signal);
  if (models.length === 0) {
    geminiHealth = { canGenerate: false, reason: "Esta clave no llega a ning\u00fan modelo.", at: now };
    return geminiHealth;
  }

  try {
    const response = await callGemini(key, models[0], "Responde solo con {}", [{ text: "ok" }], 8, signal);
    if (response.ok) {
      geminiHealth = { canGenerate: true, reason: "", at: now };
      return geminiHealth;
    }
    geminiHealth = { canGenerate: false, reason: await upstreamDetail(response), at: now };
  } catch (error) {
    // A network blip is not proof the key is dead, so it is not remembered.
    return {
      canGenerate: false,
      reason: error instanceof Error ? error.message : "No he podido comprobarlo.",
      at: 0,
    };
  }

  return geminiHealth;
}

function keyOf(env: Env): string {
  const preferred = (env.GROQ_API_KEY ?? "").trim();
  return preferred.length > 0 ? preferred : (env.VITE_GROQ_API_KEY ?? "").trim();
}

function geminiKeyOf(env: Env): string {
  return (env.GEMINI_API_KEY ?? "").trim();
}

function mistralKeyOf(env: Env): string {
  return (env.MISTRAL_API_KEY ?? "").trim();
}

// MARK: - Shared guard

type Handler = (request: Request, key: string) => Promise<Response>;

/**
 * Everything every route needs before it can do its job: a key, a request rate
 * that is not a loop, and an upstream failure translated into something a person
 * can read. The browser always has a deterministic reader underneath, so a
 * refusal here degrades the app rather than breaking it.
 */
async function guarded(request: Request, key: string, cors: HeadersInit, handler: Handler): Promise<Response> {
  if (key.length === 0) {
    return json(
      { error: { code: "sin-clave", message: "La lectura ampliada no está configurada en el servidor." } },
      503,
      cors,
    );
  }

  if (isOverRate(request)) {
    return json(
      { error: { code: "ritmo", message: "Demasiadas peticiones seguidas. Inténtalo en un momento." } },
      429,
      cors,
    );
  }

  try {
    const response = await handler(request, key);
    const headers = new Headers(response.headers);
    for (const [name, value] of Object.entries(cors as Record<string, string>)) headers.set(name, value);
    return new Response(response.body, { status: response.status, headers });
  } catch (error) {
    // The message is logged, never the body: what someone is about to turn into
    // a task does not belong in a server log.
    console.error("SinRutina: la lectura ha fallado", error instanceof Error ? error.message : "desconocido");
    return json({ error: { code: "red", message: "No he podido conectar con la lectura ampliada." } }, 502, cors);
  }
}

function isOverRate(request: Request): boolean {
  const ip = request.headers.get("CF-Connecting-IP") ?? "desconocida";
  const now = Date.now();
  const calls = (recentCalls.get(ip) ?? []).filter((at) => now - at < RATE_WINDOW_MS);
  calls.push(now);
  recentCalls.set(ip, calls);

  // Keep the map from growing without bound in a long-lived instance.
  if (recentCalls.size > 500) {
    for (const [address, times] of recentCalls) {
      if (times.every((at) => now - at >= RATE_WINDOW_MS)) recentCalls.delete(address);
    }
  }

  return calls.length > RATE_MAX_REQUESTS;
}

// MARK: - Reading text

interface ReadBody {
  system?: unknown;
  user?: unknown;
  maxTokens?: unknown;
}

interface ChatResponse {
  choices?: { message?: { content?: string | null } }[];
}

/**
 * One question, one answer. The model list is walked here instead of in the
 * browser: a model that is renamed or retired should be a server fix, not a
 * stale page in someone's tab.
 */
async function readText(request: Request, key: string): Promise<Response> {
  const body = (await request.json().catch(() => null)) as ReadBody | null;
  const system = trimmedString(body?.system, MAX_SYSTEM_CHARS);
  const user = trimmedString(body?.user, MAX_USER_CHARS);

  if (system.length === 0 || user.length === 0) {
    return json({ error: { code: "peticion", message: "Falta el texto que hay que leer." } }, 400);
  }

  const maxTokens = clampTokens(body?.maxTokens);
  const models = await resolveGroqModels(key, request.signal);

  if (models.length === 0) {
    return json({ error: { code: "sin-modelo", message: "Esta clave no llega a ning\u00fan modelo." } }, 503);
  }

  let lastStatus = 502;

  for (const model of models) {
    for (let attempt = 0; attempt <= 1; attempt += 1) {
      const response = await callGroq(key, model, system, user, maxTokens, request.signal);

      if (response.ok) {
        const payload = (await response.json()) as ChatResponse;
        const text = payload.choices?.[0]?.message?.content;
        if (typeof text === "string" && text.trim().length > 0) {
          return json({ text, model });
        }
        lastStatus = 502;
        break;
      }

      // A rejected key is settled. Retrying it wastes the person's time, and
      // quietly rerouting would hide a broken setting forever.
      if (response.status === 401 || response.status === 403) {
        return json({ error: { code: "clave", message: "La clave de Groq no es válida o se ha agotado." } }, 401);
      }

      // This model is gone, renamed, or will not take the request. Next model,
      // and forget the learned list so the next request re-asks instead of
      // walking into the same dead name forever.
      if (response.status === 400 || response.status === 404) {
        if (response.status === 404) knownGroqModels = null;
        lastStatus = response.status;
        break;
      }

      lastStatus = response.status;
      if (attempt === 1) break;
      await wait(retryDelay(response, attempt));
    }
  }

  return json({ error: { code: "arriba", message: "La lectura ampliada no ha respondido." } }, lastStatus);
}

function callGroq(
  key: string,
  model: string,
  system: string,
  user: string,
  maxTokens: number,
  signal: AbortSignal,
): Promise<Response> {
  return fetch(`${GROQ_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      max_completion_tokens: maxTokens,
      // Every prompt in this app asks for one JSON object; saying so up front
      // removes the code fences and the apologies around them.
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
    }),
    signal: withTimeout(signal),
  });
}

// MARK: - Reading with Mistral, including pictures

interface MistralModelList {
  data?: { id?: string; capabilities?: { vision?: boolean } }[];
}

/**
 * Asks the key what it reaches, then puts anything that can actually see at the
 * front. Vision is the whole reason this engine exists, so a text-only model
 * being technically available is not a reason to hand it a photograph.
 */
async function resolveMistralModels(key: string, signal: AbortSignal): Promise<string[]> {
  if (knownMistralModels !== null) return knownMistralModels;

  let available: string[] = [];
  let sighted: string[] = [];

  try {
    const response = await fetch(`${MISTRAL_URL}/models`, {
      headers: { Authorization: `Bearer ${key}` },
      signal: withTimeout(signal),
    });

    if (response.ok) {
      const payload = (await response.json()) as MistralModelList;
      const usable = (payload.data ?? []).filter((model) => {
        const id = model.id ?? "";
        return id.length > 0 && !NOT_READERS.some((word) => id.includes(word));
      });
      available = usable.map((model) => model.id ?? "");
      sighted = usable.filter((model) => model.capabilities?.vision === true).map((model) => model.id ?? "");
    } else {
      console.error("SinRutina: Mistral no ha listado modelos", response.status);
    }
  } catch (error) {
    console.error("SinRutina: no he podido listar Mistral", error instanceof Error ? error.message : "desconocido");
    return MISTRAL_PREFERRED;
  }

  if (available.length === 0) {
    knownMistralModels = [];
    return knownMistralModels;
  }

  // Preference order first, but only among models that can see; then any other
  // model the key reports as sighted; then the rest, as a last resort.
  const chosen = [
    ...MISTRAL_PREFERRED.filter((name) => sighted.includes(name)),
    ...sighted.filter((name) => !MISTRAL_PREFERRED.includes(name)),
    ...MISTRAL_PREFERRED.filter((name) => available.includes(name) && !sighted.includes(name)),
  ];

  knownMistralModels = (chosen.length > 0 ? chosen : available).slice(0, 4);
  return knownMistralModels;
}

/**
 * Same job and same contract as `readGemini`, on a different company's free
 * tier. Two engines that can read a photograph means a bad afternoon at one
 * provider is not a broken feature for the person holding the phone.
 */
async function readMistral(request: Request, key: string): Promise<Response> {
  const body = (await request.json().catch(() => null)) as GeminiBody | null;
  const system = trimmedString(body?.system, MAX_SYSTEM_CHARS);
  const user = trimmedString(body?.user, MAX_USER_CHARS);

  if (system.length === 0 || user.length === 0) {
    return json({ error: { code: "peticion", message: "Falta el texto que hay que leer." } }, 400);
  }

  const picture = typeof body?.imageDataUrl === "string" ? decodeDataUrl(body.imageDataUrl) : null;
  if (picture === "demasiado-grande") {
    return json({ error: { code: "tamano", message: "Esa imagen es demasiado grande." } }, 413);
  }

  // Rebuilt from the decoded parts rather than forwarded as it arrived, so a
  // malformed data URL cannot be passed along unchecked.
  const dataUrl = picture === null ? null : `data:${picture.mime_type};base64,${picture.data}`;

  const maxTokens = clampTokens(body?.maxTokens);
  const models = await resolveMistralModels(key, request.signal);

  if (models.length === 0) {
    return json({ error: { code: "sin-modelo", message: "Esta clave de Mistral no llega a ning\u00fan modelo." } }, 503);
  }

  let lastStatus = 502;

  for (const model of models) {
    for (let attempt = 0; attempt <= 1; attempt += 1) {
      const response = await callMistral(key, model, system, user, dataUrl, maxTokens, request.signal);

      if (response.ok) {
        const payload = (await response.json()) as ChatResponse;
        const text = payload.choices?.[0]?.message?.content;
        if (typeof text === "string" && text.trim().length > 0) {
          return json({ text, model });
        }
        lastStatus = 502;
        break;
      }

      const detail = await upstreamDetail(response);

      if (response.status === 401 || response.status === 403) {
        console.error("SinRutina: Mistral ha rechazado la clave", detail);
        mistralHealth = { canGenerate: false, reason: detail, at: Date.now() };
        return json(
          { error: { code: "clave", message: "La clave de Mistral no es v\u00e1lida o no tiene permiso.", detail } },
          401,
        );
      }

      // Gone, renamed, or unwilling to take this request — including a text-only
      // model being handed a picture. Next model, and re-ask the catalogue.
      if (response.status === 400 || response.status === 404 || response.status === 422) {
        if (response.status === 404) knownMistralModels = null;
        lastStatus = response.status;
        break;
      }

      lastStatus = response.status;
      if (attempt === 1) break;
      await wait(retryDelay(response, attempt));
    }
  }

  return json({ error: { code: "arriba", message: "La lectura ampliada no ha respondido." } }, lastStatus);
}

interface MistralTextPart {
  type: "text";
  text: string;
}

interface MistralImagePart {
  type: "image_url";
  image_url: string;
}

function callMistral(
  key: string,
  model: string,
  system: string,
  user: string,
  dataUrl: string | null,
  maxTokens: number,
  signal: AbortSignal,
): Promise<Response> {
  const parts: (MistralTextPart | MistralImagePart)[] = [{ type: "text", text: user }];
  if (dataUrl !== null) parts.push({ type: "image_url", image_url: dataUrl });

  return fetch(`${MISTRAL_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Accept: "application/json",
      Authorization: `Bearer ${key}`,
    },
    body: JSON.stringify({
      model,
      temperature: 0,
      max_tokens: maxTokens,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: system },
        { role: "user", content: dataUrl === null ? user : parts },
      ],
    }),
    signal: withTimeout(signal),
  });
}

// MARK: - Reading with Gemini, including pictures

interface GeminiBody extends ReadBody {
  /** A `data:` URL, when the words are inside a picture instead of typed. */
  imageDataUrl?: unknown;
}

interface GeminiResponse {
  candidates?: { content?: { parts?: { text?: string }[] }; finishReason?: string }[];
}

/**
 * The same job as `readText`, on a different engine, and with one extra ability:
 * it can look at a picture. That is the reason this route exists at all.
 *
 * A picture is passed straight through and never written down. What the app
 * keeps afterwards is the text that was read and the file name — not the file.
 */
async function readGemini(request: Request, key: string): Promise<Response> {
  const body = (await request.json().catch(() => null)) as GeminiBody | null;
  const system = trimmedString(body?.system, MAX_SYSTEM_CHARS);
  const user = trimmedString(body?.user, MAX_USER_CHARS);

  if (system.length === 0 || user.length === 0) {
    return json({ error: { code: "peticion", message: "Falta el texto que hay que leer." } }, 400);
  }

  const picture = typeof body?.imageDataUrl === "string" ? decodeDataUrl(body.imageDataUrl) : null;
  if (picture === "demasiado-grande") {
    return json({ error: { code: "tamano", message: "Esa imagen es demasiado grande." } }, 413);
  }

  const parts: GeminiPart[] = [{ text: user }];
  if (picture !== null) parts.push({ inline_data: picture });

  const maxTokens = clampTokens(body?.maxTokens);
  const models = await resolveGeminiModels(key, request.signal);

  if (models.length === 0) {
    return json(
      { error: { code: "sin-modelo", message: "Esta clave de Gemini no llega a ningún modelo." } },
      503,
    );
  }

  let lastStatus = 502;
  let lastDetail = "";

  for (const model of models) {
    for (let attempt = 0; attempt <= 1; attempt += 1) {
      const response = await callGemini(key, model, system, parts, maxTokens, request.signal);

      if (response.ok) {
        const payload = (await response.json()) as GeminiResponse;
        const text = payload.candidates?.[0]?.content?.parts?.map((part) => part.text ?? "").join("");
        if (typeof text === "string" && text.trim().length > 0) {
          return json({ text, model });
        }

        // An empty answer with a reason attached is usually the model stopping
        // for safety or running out of room. Worth naming, not worth retrying.
        lastDetail = payload.candidates?.[0]?.finishReason ?? "sin-texto";
        lastStatus = 502;
        break;
      }

      const detail = await upstreamDetail(response);

      // Settled: a bad key, or a free tier that is not offered in this country.
      // Saying so beats retrying something that will never start working.
      if (response.status === 401 || response.status === 403) {
        console.error("SinRutina: Gemini ha rechazado la clave", detail);
        geminiHealth = { canGenerate: false, reason: detail, at: Date.now() };
        return json(
          { error: { code: "clave", message: "La clave de Gemini no es válida o no tiene permiso.", detail } },
          401,
        );
      }

      // Quota belongs to the whole key, not to one model. Walking the rest of
      // the list would just spend the same exhausted allowance four more times
      // and make the wait longer for everyone.
      if (response.status === 429) {
        console.error("SinRutina: Gemini sin cuota", detail);
        // Stop offering it until the window is re-checked, instead of letting
        // every later reading discover the same wall on its own.
        geminiHealth = { canGenerate: false, reason: detail, at: Date.now() };
        return json(
          {
            error: {
              code: "cuota",
              message: "La lectura gratuita de Gemini ha agotado su cuota por ahora.",
              detail,
            },
          },
          429,
        );
      }

      // Gone, renamed, or refusing this request. Try the next model, and forget
      // the learned list so the next request re-asks instead of walking into
      // the same dead name forever.
      if (response.status === 400 || response.status === 404) {
        if (response.status === 404) knownGeminiModels = null;
        lastStatus = response.status;
        lastDetail = detail;
        break;
      }

      lastStatus = response.status;
      lastDetail = detail;
      if (attempt === 1) break;
      await wait(retryDelay(response, attempt));
    }
  }

  console.error("SinRutina: Gemini no ha respondido", lastStatus, lastDetail);
  return json(
    { error: { code: "arriba", message: "La lectura ampliada no ha respondido.", detail: lastDetail } },
    lastStatus,
  );
}

/**
 * Google's own explanation, trimmed to something loggable. Only the upstream
 * status text is taken — never the request that caused it, which is the
 * person's own words.
 */
async function upstreamDetail(response: Response): Promise<string> {
  try {
    const raw = await response.text();
    const parsed = JSON.parse(raw) as { error?: { status?: string; message?: string } };
    const status = parsed.error?.status ?? "";
    const message = parsed.error?.message ?? "";
    const joined = [status, message].filter((part) => part.length > 0).join(": ");
    return joined.slice(0, 300) || raw.slice(0, 200);
  } catch {
    return `http ${response.status}`;
  }
}

type GeminiPart = { text: string } | { inline_data: { mime_type: string; data: string } };

interface GroqModelList {
  data?: { id?: string }[];
}

/**
 * Asks the key which chat models it can actually call, instead of trusting a
 * name written months ago.
 *
 * Untested models sit behind the known-good ones and are used only when none of
 * the preferred names survive. That ordering matters: two listed models fail the
 * app's JSON mode outright, so trying them routinely would spend ~200 ms per
 * request to be told "no". As a last resort they are still better than nothing.
 */
async function resolveGroqModels(key: string, signal: AbortSignal): Promise<string[]> {
  if (knownGroqModels !== null) return knownGroqModels;

  let available: string[] = [];
  try {
    const response = await fetch(`${GROQ_URL}/models`, {
      headers: { Authorization: `Bearer ${key}` },
      signal: withTimeout(signal),
    });

    if (response.ok) {
      const payload = (await response.json()) as GroqModelList;
      available = (payload.data ?? [])
        .map((model) => model.id ?? "")
        .filter((id) => id.length > 0 && !NOT_CHAT.some((word) => id.includes(word)));
    } else {
      console.error("SinRutina: Groq no ha listado modelos", response.status);
    }
  } catch (error) {
    console.error("SinRutina: no he podido listar modelos", error instanceof Error ? error.message : "desconocido");
    // A network blip should not be remembered as "this key is useless".
    return GROQ_PREFERRED;
  }

  if (available.length === 0) {
    knownGroqModels = [];
    return knownGroqModels;
  }

  const known = GROQ_PREFERRED.filter((name) => available.includes(name));
  const untested = available.filter((name) => !GROQ_PREFERRED.includes(name));

  knownGroqModels = known.length > 0 ? known : untested.slice(0, 3);
  return knownGroqModels;
}

interface GroqProbe {
  model: string;
  ok: boolean;
  status: number;
  /** Groq's own explanation when it refuses, so a choice rests on evidence. */
  detail: string;
  ms: number;
}

/**
 * Asks every preferred model the same tiny question, under the exact conditions
 * this app uses — JSON mode included. Speed and refusals both show up here,
 * which is what makes picking an order a measurement rather than a guess.
 */
async function probeGroq(key: string, signal: AbortSignal): Promise<GroqProbe[]> {
  const system = "Devuelve SOLO un objeto JSON con la clave titulo.";
  const user = "comprar pan";
  const probes: GroqProbe[] = [];

  for (const model of GROQ_PREFERRED) {
    const started = Date.now();
    try {
      const response = await callGroq(key, model, system, user, 40, signal);
      const ms = Date.now() - started;
      probes.push({
        model,
        ok: response.ok,
        status: response.status,
        detail: response.ok ? "" : await upstreamDetail(response),
        ms,
      });
    } catch (error) {
      probes.push({
        model,
        ok: false,
        status: 0,
        detail: error instanceof Error ? error.message : "desconocido",
        ms: Date.now() - started,
      });
    }
  }

  return probes;
}

/**
 * A real 96x48 PNG: a black letter on white. Deliberately not a 1x1 pixel — some
 * providers reject an image that small before ever looking at it, which would
 * make the probe measure the wrong thing.
 */
const PROBE_PNG =
  "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAGAAAAAwCAAAAADLfSATAAAAPklEQVR42u3XsQ0AIBACQPZfWifQwvgxeY8BuIqCjOIEAAA8AnIYAKATsBzNpujKkgEAAAAAAHwCOCCApsAERB+BUn1j4+wAAAAASUVORK5CYII=";

interface MistralProbe {
  model: string;
  /** What the catalogue claims about this model's eyes. */
  claimsVision: boolean;
  /** Whether it actually accepted a picture. The only part that decides order. */
  ok: boolean;
  status: number;
  detail: string;
  ms: number;
}

/**
 * Hands every candidate a real picture, under the exact conditions the reader
 * uses — JSON mode included. Text-only models refuse here, which is precisely
 * the point: this key reaches no Pixtral, so which of the remaining models can
 * genuinely see had to be measured rather than hoped for.
 */
async function probeMistral(key: string, signal: AbortSignal): Promise<MistralProbe[]> {
  const system = "Devuelve SOLO un objeto JSON con la clave titulo.";
  const user = "¿Qué letra aparece en la imagen?";

  let claimed: string[] = [];
  try {
    const listed = await fetch(`${MISTRAL_URL}/models`, {
      headers: { Authorization: `Bearer ${key}` },
      signal: withTimeout(signal),
    });
    if (listed.ok) {
      const payload = (await listed.json()) as MistralModelList;
      claimed = (payload.data ?? [])
        .filter((model) => model.capabilities?.vision === true)
        .map((model) => model.id ?? "");
    }
  } catch {
    // The probe below is the real answer anyway; the claim is only context.
  }

  const candidates = await resolveMistralModels(key, signal);
  const probes: MistralProbe[] = [];

  for (const model of candidates) {
    const started = Date.now();
    try {
      const response = await callMistral(key, model, system, user, PROBE_PNG, 40, signal);
      probes.push({
        model,
        claimsVision: claimed.includes(model),
        ok: response.ok,
        status: response.status,
        detail: response.ok ? "" : await upstreamDetail(response),
        ms: Date.now() - started,
      });
    } catch (error) {
      probes.push({
        model,
        claimsVision: claimed.includes(model),
        ok: false,
        status: 0,
        detail: error instanceof Error ? error.message : "desconocido",
        ms: Date.now() - started,
      });
    }
  }

  return probes;
}

interface GeminiModelList {
  models?: { name?: string; supportedGenerationMethods?: string[] }[];
}

/**
 * Asks the key which models it can actually call, instead of trusting a name
 * written months ago. Kept in preference order — cheapest and fastest first —
 * with anything else Google offers behind it, so a rename degrades into a
 * slightly different model rather than into a dead feature.
 *
 * An empty result is honest: it means this key reaches nothing, and the caller
 * says so rather than retrying a name that will never work.
 */
async function resolveGeminiModels(key: string, signal: AbortSignal): Promise<string[]> {
  if (knownGeminiModels !== null) return knownGeminiModels;

  let available: string[] = [];
  try {
    const response = await fetch(`${GEMINI_URL}?pageSize=200`, {
      headers: { "x-goog-api-key": key },
      signal: withTimeout(signal),
    });

    if (response.ok) {
      const payload = (await response.json()) as GeminiModelList;
      available = (payload.models ?? [])
        .filter((model) => (model.supportedGenerationMethods ?? []).includes("generateContent"))
        .map((model) => (model.name ?? "").replace(/^models\//, ""))
        .filter((name) => name.length > 0);
    } else {
      console.error("SinRutina: Gemini no ha listado modelos", response.status);
    }
  } catch (error) {
    console.error("SinRutina: no he podido listar modelos", error instanceof Error ? error.message : "desconocido");
    // A network blip should not be remembered as "this key is useless".
    return GEMINI_PREFERRED;
  }

  if (available.length === 0) {
    knownGeminiModels = [];
    return knownGeminiModels;
  }

  const chosen = [
    ...GEMINI_PREFERRED.filter((name) => available.includes(name)),
    ...available.filter((name) => name.includes("flash-lite") && !GEMINI_PREFERRED.includes(name)),
    ...available.filter((name) => name.includes("flash") && !name.includes("lite") && !GEMINI_PREFERRED.includes(name)),
  ];

  // Never end up with nothing usable just because the naming changed shape.
  knownGeminiModels = chosen.length > 0 ? chosen.slice(0, 4) : available.slice(0, 2);
  return knownGeminiModels;
}

function callGemini(
  key: string,
  model: string,
  system: string,
  parts: GeminiPart[],
  maxTokens: number,
  signal: AbortSignal,
): Promise<Response> {
  return fetch(`${GEMINI_URL}/${model}:generateContent`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-goog-api-key": key,
    },
    body: JSON.stringify({
      system_instruction: { parts: [{ text: system }] },
      contents: [{ role: "user", parts }],
      generationConfig: {
        temperature: 0,
        maxOutputTokens: maxTokens,
        // Every prompt in this app asks for one JSON object. Saying so removes
        // the code fences and the polite sentence wrapped around them.
        responseMimeType: "application/json",
      },
    }),
    signal: withTimeout(signal),
  });
}

/** Splits a `data:` URL into the two things Gemini wants, or refuses it. */
function decodeDataUrl(value: string): { mime_type: string; data: string } | null | "demasiado-grande" {
  const match = /^data:([^;,]+);base64,(.+)$/s.exec(value.trim());
  if (match === null) return null;

  const data = match[2];
  // base64 carries about 3 bytes for every 4 characters.
  if ((data.length * 3) / 4 > MAX_IMAGE_BYTES) return "demasiado-grande";

  return { mime_type: match[1], data };
}

// MARK: - Dictation

/**
 * A recording becomes text and then stops existing. The audio is streamed
 * straight through to Groq and never written down anywhere, here or in a log.
 */
async function transcribe(request: Request, key: string): Promise<Response> {
  const incoming = await request.formData().catch(() => null);
  const file = incoming?.get("file");

  if (!(file instanceof File) || file.size === 0) {
    return json({ error: { code: "peticion", message: "No ha llegado ninguna grabación." } }, 400);
  }

  if (file.size > MAX_AUDIO_BYTES) {
    return json(
      { error: { code: "tamano", message: "Esa grabación es demasiado larga. Prueba con una frase más corta." } },
      413,
    );
  }

  const form = new FormData();
  form.append("file", file, file.name || "dictado.webm");
  form.append("model", TRANSCRIPTION_MODEL);
  form.append("language", "es");
  form.append("response_format", "json");
  form.append("temperature", "0");

  const response = await fetch(`${GROQ_URL}/audio/transcriptions`, {
    method: "POST",
    headers: { Authorization: `Bearer ${key}` },
    body: form,
    signal: withTimeout(request.signal),
  });

  if (!response.ok) {
    if (response.status === 401 || response.status === 403) {
      return json({ error: { code: "clave", message: "La clave de Groq no es válida o se ha agotado." } }, 401);
    }
    return json({ error: { code: "arriba", message: "No he podido transcribir el audio." } }, response.status);
  }

  const payload = (await response.json()) as { text?: unknown };
  const text = typeof payload.text === "string" ? payload.text.trim() : "";

  if (text.length === 0) {
    return json({ error: { code: "vacio", message: "No he entendido nada en esa grabación." } }, 422);
  }

  return json({ text });
}

// MARK: - Small helpers

function json(payload: unknown, status = 200, extra?: HeadersInit): Response {
  const headers = new Headers(extra);
  headers.set("Content-Type", "application/json; charset=utf-8");
  // Nothing here is ever worth reusing from a cache.
  headers.set("Cache-Control", "no-store");
  return new Response(JSON.stringify(payload), { status, headers });
}

function corsHeaders(origin: string | null): Record<string, string> {
  return {
    "Access-Control-Allow-Origin": origin !== null && isAllowedOrigin(origin) ? origin : "null",
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Access-Control-Max-Age": "86400",
    Vary: "Origin",
  };
}

function isAllowedOrigin(origin: string): boolean {
  let host: string;
  try {
    host = new URL(origin).hostname;
  } catch {
    return false;
  }

  if (host === "localhost" || host === "127.0.0.1") return true;
  return ALLOWED_ORIGIN_SUFFIXES.some((suffix) => host.endsWith(suffix));
}

function trimmedString(value: unknown, limit: number): string {
  return typeof value === "string" ? value.trim().slice(0, limit) : "";
}

function clampTokens(value: unknown): number {
  const asNumber = typeof value === "number" ? Math.floor(value) : Number.NaN;
  if (!Number.isFinite(asNumber) || asNumber <= 0) return 320;
  return Math.min(asNumber, MAX_OUTPUT_TOKENS);
}

/** Gives up before the person does, and lets go if the browser already has. */
function withTimeout(signal: AbortSignal): AbortSignal {
  return AbortSignal.any([signal, AbortSignal.timeout(UPSTREAM_TIMEOUT_MS)]);
}

function retryDelay(response: Response, attempt: number): number {
  const header = response.headers.get("retry-after");
  if (header) {
    const seconds = Number.parseInt(header, 10);
    if (Number.isFinite(seconds) && seconds >= 0) return Math.min(seconds * 1000, 6_000);
  }
  return Math.min(600 * 2 ** attempt, 3_000);
}

const wait = (ms: number): Promise<void> => new Promise((resolve) => setTimeout(resolve, ms));
