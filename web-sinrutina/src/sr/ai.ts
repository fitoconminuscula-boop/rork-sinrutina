import { ask, newIdempotencyKey, parseObject, type ReaderSource } from "./gateway";
import {
  followUpDraft as localFollowUpDraft,
  microActions as localMicroActions,
  normalized,
  splitIfTooBig,
  suggestion as localSuggestion,
  type CaptureSuggestion,
} from "./heuristics";
import type { TaskState } from "./types";

/**
 * SinRutina's reading layer for the browser.
 *
 * Groq and Gemini replace what Apple Intelligence does on the iPhone, under the
 * same three rules the on-device model follows:
 *
 * 1. It only proposes. It never writes, moves, completes or deletes anything.
 * 2. Every field it returns is validated here before the app believes it. A
 *    person it cannot find in the text is discarded; a duration out of range is
 *    clamped; an invented state is ignored.
 * 3. The deterministic reader runs first and stays as the floor. Everything below
 *    returns a usable result even with no network at all.
 */

export interface ReadResult {
  suggestion: CaptureSuggestion;
  source: ReaderSource;
}

export interface StepsResult {
  steps: string[];
  source: ReaderSource;
}

export interface DraftResult {
  text: string;
  source: ReaderSource;
}

const READER_ROLE = `Eres el lector de SinRutina, una app española contra la procrastinación.
Conviertes lo que escribe una persona en datos estructurados.
Reglas estrictas:
- Responde SIEMPRE en español y SOLO con un objeto JSON válido, sin explicaciones ni markdown.
- Sé literal. NO inventes personas, fechas, horas ni tareas que no aparezcan en el texto.
- Si algo no se menciona, devuelve cadena vacía o lista vacía.
- El título describe la acción, en imperativo, y nunca incluye la hora.
- Nada de motivación, ánimos, emojis ni exclamaciones.`;

const CAPTURE_SHAPE = `Devuelve exactamente este JSON:
{
  "title": "título corto en imperativo, máximo 7 palabras, sin fechas ni horas",
  "estimatedMinutes": número entero entre 1 y 240,
  "suggestedState": "ahora" | "despues" | "esperando" | "algun_dia",
  "availableFromTime": "HH:mm o cadena vacía",
  "relativeDay": "hoy" | "manana" | "ninguno",
  "context": "comunicación" | "administrativo" | "dinero" | "salud" | "trabajo" | "casa" | "estudio" | "otro",
  "nextStep": "primera acción concreta, en infinitivo, máximo 6 palabras",
  "waitingFor": "nombre o relación de la persona de la que depende, o cadena vacía",
  "subtasks": ["entre 0 y 3 trozos concretos si es demasiado grande"]
}`;

/**
 * Reads one captured sentence. The local reading is computed first and used as
 * the base, so anything the model leaves out keeps a real value.
 */
export async function readCapture(rawText: string, signal?: AbortSignal): Promise<ReadResult> {
  const now = new Date();
  const trimmed = rawText.trim();
  const local = localSuggestion(trimmed, now);
  if (trimmed.length < 8) return { suggestion: local, source: "local" };

  const raw = await ask({
    system: `${READER_ROLE}\n\n${CAPTURE_SHAPE}`,
    user: `Texto de la persona: "${trimmed.slice(0, 900)}"`,
    maxTokens: 320,
    idempotencyKey: newIdempotencyKey(),
    signal,
  });

  const parsed = parseObject(raw);
  if (!parsed) return { suggestion: local, source: "local" };
  return { suggestion: merge(parsed, local, trimmed, now), source: "extended" };
}

const DOCUMENT_ROLE = `Eres el lector de documentos de SinRutina, una app española contra la procrastinación.
Recibes el texto de un archivo que alguien ha adjuntado: una carta, una factura,
un correo, un aviso. Tu único trabajo es encontrar QUÉ TIENE QUE HACER esa persona.
Reglas estrictas:
- Responde SIEMPRE en español y SOLO con un objeto JSON válido, sin explicaciones ni markdown.
- Sé literal. NO inventes importes, fechas, plazos ni personas que no aparezcan en el documento.
- Si el documento no pide ninguna acción, el título describe lo que hay que revisar.
- El título describe la acción, en imperativo, y nunca incluye la hora.
- Nada de motivación, ánimos, emojis ni exclamaciones.`;

/**
 * Reads a document the person attached. The shape is the same as a typed
 * sentence, so a file and a phrase end up as the same kind of task.
 *
 * The local reader still runs first on the opening lines, so an attachment
 * without network becomes a real task instead of an error.
 */
export async function readDocument(
  text: string,
  fileName: string,
  signal?: AbortSignal
): Promise<ReadResult> {
  const now = new Date();
  const trimmed = text.trim();
  const local = localSuggestion(openingLine(trimmed), now);
  if (trimmed.length === 0) return { suggestion: local, source: "local" };

  const raw = await ask({
    system: `${DOCUMENT_ROLE}\n\n${CAPTURE_SHAPE}`,
    user: `Archivo: "${fileName.slice(0, 120)}"\n\nContenido:\n"""\n${trimmed.slice(0, 6000)}\n"""`,
    maxTokens: 340,
    idempotencyKey: newIdempotencyKey(),
    signal,
  });

  const parsed = parseObject(raw);
  if (!parsed) return { suggestion: local, source: "local" };
  return { suggestion: merge(parsed, local, trimmed, now), source: "extended" };
}

/**
 * Reads what is written inside a picture: a photographed letter, a scanned page,
 * a screenshot. A browser has no OCR, so this path only exists with the extended
 * reader on — the caller checks that before getting here.
 */
export async function readImage(
  imageDataUrl: string,
  fileName: string,
  signal?: AbortSignal
): Promise<ReadResult> {
  const now = new Date();
  const local = localSuggestion(fileNameAsSentence(fileName), now);

  const raw = await ask({
    system: `${DOCUMENT_ROLE}\n\nRecibes la imagen de un documento. Lee lo que pone en ella.\nSi la imagen no tiene texto legible, describe en el título el objeto que se ve.\n\n${CAPTURE_SHAPE}`,
    user: `Imagen adjunta ("${fileName.slice(0, 120)}"). ¿Qué tengo que hacer con esto?`,
    imageDataUrl,
    maxTokens: 340,
    idempotencyKey: newIdempotencyKey(),
    signal,
  });

  const parsed = parseObject(raw);
  if (!parsed) return { suggestion: local, source: "local" };
  // Nothing in the picture is in `rawText`, so the dependency check has nothing
  // to compare against: a person named only in an image is never trusted here.
  return { suggestion: merge(parsed, local, "", now), source: "extended" };
}

/** The first line with actual words in it — what a person's eye lands on. */
function openingLine(text: string): string {
  const line = text
    .split(/\n+/)
    .map((part) => part.trim())
    .find((part) => part.length >= 12);
  return (line ?? text).slice(0, 160);
}

/** "factura-marzo_2026.pdf" reads better as "factura marzo 2026". */
export function fileNameAsSentence(fileName: string): string {
  const withoutExtension = fileName.replace(/\.[a-z0-9]{1,5}$/i, "");
  return withoutExtension.replace(/[_\-.]+/g, " ").replace(/\s+/g, " ").trim();
}

/** The three smallest possible movements, for when starting feels impossible. */
export async function readMicroActions(title: string, signal?: AbortSignal): Promise<StepsResult> {
  const local = localMicroActions(title);

  const raw = await ask({
    system: `${READER_ROLE}

La persona está saturada y necesita acciones diminutas, físicas y concretas, de
menos de dos minutos cada una, en infinitivo.
Devuelve exactamente este JSON: {"actions": ["...", "...", "..."]}`,
    user: `Tarea: "${title.slice(0, 200)}". Dame los tres primeros movimientos.`,
    maxTokens: 200,
    idempotencyKey: newIdempotencyKey(),
    signal,
  });

  const steps = readStringList(raw, "actions", 9);
  return steps.length >= 2 ? { steps, source: "extended" } : { steps: local, source: "local" };
}

/** Breaks a task that is too big into pieces that fit inside twenty minutes. */
export async function readSplit(title: string, signal?: AbortSignal): Promise<StepsResult> {
  const local = splitIfTooBig(normalized(title), 90);

  const raw = await ask({
    system: `${READER_ROLE}

Divides una tarea demasiado grande en trozos pequeños y ordenados. Cada trozo se
puede hacer en menos de 20 minutos, escrito en infinitivo.
Devuelve exactamente este JSON: {"actions": ["...", "...", "..."]}`,
    user: `Divide esto en tres pasos: "${title.slice(0, 200)}"`,
    maxTokens: 220,
    idempotencyKey: newIdempotencyKey(),
    signal,
  });

  const steps = readStringList(raw, "actions", 10);
  return steps.length >= 2 ? { steps, source: "extended" } : { steps: local, source: "local" };
}

/**
 * Writes a follow-up the person can copy. SinRutina never sends anything, so the
 * draft is only ever text on screen.
 */
export async function readFollowUp(
  taskTitle: string,
  person: string | null,
  days: number,
  signal?: AbortSignal
): Promise<DraftResult> {
  const local = localFollowUpDraft(taskTitle, person, days);

  const raw = await ask({
    system: `${READER_ROLE}

Escribes borradores de seguimiento breves, educados y sin rodeos, en español.
Máximo cuatro líneas. No firmes con un nombre que no te hayan dado.
Devuelve exactamente este JSON: {"message": "..."}`,
    user: `Asunto pendiente: "${taskTitle.slice(0, 200)}". Llevamos ${days} ${
      days === 1 ? "día" : "días"
    } esperando. ${person ? `Va dirigido a ${person}.` : "No sabemos el nombre."}`,
    maxTokens: 320,
    idempotencyKey: newIdempotencyKey(),
    signal,
  });

  const parsed = parseObject(raw);
  const message = typeof parsed?.message === "string" ? parsed.message.trim() : "";
  return message.length >= 20 ? { text: message, source: "extended" } : { text: local, source: "local" };
}

// MARK: - Validation

/**
 * Ported field by field from the iPhone app. The model's answer is treated as a
 * set of proposals; each one has to survive its own check before it is used.
 */
function merge(
  generated: Record<string, unknown>,
  fallback: CaptureSuggestion,
  rawText: string,
  now: Date
): CaptureSuggestion {
  const result: CaptureSuggestion = { ...fallback, subtasks: [...fallback.subtasks] };

  const title = sanitize(asString(generated.title), 9);
  if (title.length >= 3) result.title = title;

  const minutes = asNumber(generated.estimatedMinutes);
  if (minutes !== null && minutes >= 1) result.estimatedMinutes = Math.min(Math.max(minutes, 1), 240);

  const state = stateFrom(asString(generated.suggestedState));
  if (state) result.suggestedState = state;

  // A dependency the model cannot name in the person's own words is not a
  // dependency: it is a guess about someone who may not exist.
  const waiting = sanitize(asString(generated.waitingFor), 4);
  const isNamed = waiting.length >= 3 && normalized(rawText).includes(normalized(waiting).slice(0, 4));
  if (isNamed) {
    result.waitingFor = waiting;
    result.suggestedState = "Esperando";
  } else if (fallback.waitingFor === null && result.suggestedState === "Esperando") {
    result.suggestedState = fallback.suggestedState;
  }

  const available = dateFrom(asString(generated.availableFromTime), asString(generated.relativeDay), now);
  if (available) {
    result.availableFrom = available.toISOString();
    if (result.suggestedState === "Ahora") result.suggestedState = "Después";
  }

  const context = asString(generated.context).trim().toLowerCase();
  if (context.length > 0 && context !== "otro") result.context = context;

  const step = sanitize(asString(generated.nextStep), 8);
  if (step.length >= 3) result.nextStep = step;

  const subtasks = asStringArray(generated.subtasks)
    .map((item) => sanitize(item, 10))
    .filter((item) => item.length >= 5);
  if (subtasks.length > 0) result.subtasks = subtasks.slice(0, 3);

  return result;
}

function readStringList(raw: string, key: string, maxWords: number): string[] {
  const parsed = parseObject(raw);
  if (!parsed) return [];
  return asStringArray(parsed[key])
    .map((item) => sanitize(item, maxWords))
    .filter((item) => item.length >= 3)
    .slice(0, 3);
}

function asString(value: unknown): string {
  return typeof value === "string" ? value : "";
}

function asNumber(value: unknown): number | null {
  if (typeof value === "number" && Number.isFinite(value)) return Math.round(value);
  if (typeof value === "string") {
    const parsed = Number.parseInt(value, 10);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

function asStringArray(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return value.filter((item): item is string => typeof item === "string");
}

function stateFrom(raw: string): TaskState | null {
  switch (normalized(raw)) {
    case "ahora":
      return "Ahora";
    case "despues":
      return "Después";
    case "esperando":
      return "Esperando";
    case "algun_dia":
    case "algun dia":
      return "Algún día";
    default:
      return null;
  }
}

function dateFrom(time: string, relativeDay: string, now: Date): Date | null {
  const trimmed = time.trim();
  if (trimmed.length === 0) return null;

  const parts = trimmed.split(":");
  const hour = Number.parseInt(parts[0] ?? "", 10);
  if (!Number.isFinite(hour) || hour < 0 || hour > 23) return null;
  const minute = Math.min(Number.parseInt(parts[1] ?? "0", 10) || 0, 59);

  const isTomorrow = normalized(relativeDay) === "manana";
  const day = new Date(now.getTime());
  if (isTomorrow) day.setDate(day.getDate() + 1);
  day.setHours(hour, minute, 0, 0);

  if (day.getTime() <= now.getTime() && !isTomorrow) {
    day.setDate(day.getDate() + 1);
  }
  return day;
}

/** Strips quotes, trailing punctuation and runaway length from model output. */
function sanitize(raw: string, maxWords: number): string {
  let text = raw.replace(/\n/g, " ").replace(/^[\s"'“”«».,;:\-–—*•]+|[\s"'“”«».,;:\-–—*•]+$/g, "");
  if (text.length === 0) return "";

  const words = text.split(/\s+/).filter((word) => word.length > 0);
  if (words.length > maxWords) text = words.slice(0, maxWords).join(" ");

  return text.charAt(0).toUpperCase() + text.slice(1);
}
