import type { TaskState } from "./types";

/**
 * Deterministic Spanish reader, ported from the iPhone app.
 *
 * This is SinRutina's floor: it always works, offline, in any browser, with no
 * server and no AI service. On iOS an on-device model refines these results, but
 * it never replaces the guarantees — so the web version misses nothing essential.
 */

export interface CaptureSuggestion {
  title: string;
  estimatedMinutes: number;
  suggestedState: TaskState;
  availableFrom: string | null;
  dueDate: string | null;
  context: string | null;
  nextStep: string;
  waitingFor: string | null;
  subtasks: string[];
}

/** Lowercased and stripped of accents, so "mañana" and "manana" read the same. */
export function normalized(text: string): string {
  return text
    .toLowerCase()
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "");
}

// MARK: - Public entry point

export function suggestion(rawText: string, now: Date = new Date()): CaptureSuggestion {
  const text = rawText.trim();
  if (text.length === 0) {
    return {
      title: "Algo pendiente",
      estimatedMinutes: 5,
      suggestedState: "Ahora",
      availableFrom: null,
      dueDate: null,
      context: null,
      nextStep: "Poner delante de ti lo que necesitas para empezar",
      waitingFor: null,
      subtasks: [],
    };
  }

  const lower = normalized(text);
  const waitingFor = detectDependency(text, lower);
  const availableFrom = detectAvailability(lower, now);
  const dueDate = detectDeadline(lower, now);
  const context = detectContext(lower);
  const minutes = detectMinutes(lower, context);
  const title = shortTitle(text);
  const subtasks = splitIfTooBig(lower, minutes);

  const state: TaskState = (() => {
    if (waitingFor !== null) return "Esperando";
    if (availableFrom && availableFrom.getTime() > now.getTime()) return "Después";
    if (lower.includes("algun dia") || lower.includes("cuando pueda")) return "Algún día";
    if (dueDate) return "Después";
    return "Ahora";
  })();

  return {
    title,
    estimatedMinutes: minutes,
    suggestedState: state,
    availableFrom: availableFrom ? availableFrom.toISOString() : null,
    dueDate: dueDate ? dueDate.toISOString() : null,
    context,
    nextStep: nextStep(lower, context),
    waitingFor,
    subtasks,
  };
}

// MARK: - Title

const PREFIXES = [
  "tengo que ",
  "tengo pendiente ",
  "debo ",
  "deberia ",
  "hay que ",
  "necesito ",
  "necesitaria ",
  "recordar ",
  "recordarme ",
  "acordarme de ",
  "no olvidar ",
  "quiero ",
  "me gustaria ",
  "toca ",
  "pendiente de ",
  "por favor ",
];

export function shortTitle(rawText: string): string {
  let text = firstSentence(rawText);

  let didTrim = true;
  while (didTrim) {
    didTrim = false;
    const lower = normalized(text);
    for (const prefix of PREFIXES) {
      if (lower.startsWith(prefix)) {
        const remainder = text.slice(prefix.length).trim();
        if (remainder.length > 0) {
          text = remainder;
          didTrim = true;
          break;
        }
      }
    }
  }

  // Drop trailing time qualifiers: they already live in structured fields.
  for (const marker of [
    " pero despues de",
    " despues de las",
    " a partir de las",
    " antes de las",
  ]) {
    const cut = normalized(text).indexOf(marker);
    if (cut > 6) text = text.slice(0, cut).trim();
  }

  text = text.replace(/^[\s.,;:\-–—]+|[\s.,;:\-–—]+$/g, "");

  if (text.length > 62) {
    const clipped = text.slice(0, 62);
    const lastSpace = clipped.lastIndexOf(" ");
    text = lastSpace > 0 ? clipped.slice(0, lastSpace) : clipped;
  }

  if (text.length === 0) return "Algo pendiente";
  return text.charAt(0).toUpperCase() + text.slice(1);
}

function firstSentence(text: string): string {
  const trimmed = text.trim();
  const match = trimmed.search(/[.!?\n]/);
  if (match < 0) return trimmed;
  const candidate = trimmed.slice(0, match).trim();
  return candidate.length >= 6 ? candidate : trimmed;
}

// MARK: - Duration

export function detectMinutes(lower: string, context: string | null): number {
  if (lower.includes("media hora")) return 30;
  if (lower.includes("un cuarto de hora")) return 15;
  if (lower.includes("hora y media")) return 90;

  const explicit = firstNumberBefore(["minutos", "minuto", "min"], lower);
  if (explicit !== null) return Math.max(1, Math.min(explicit, 480));

  const hours = firstNumberBefore(["horas", "hora"], lower);
  if (hours !== null) return Math.max(15, Math.min(hours * 60, 480));

  if (lower.includes("toda la tarde") || lower.includes("toda la manana")) return 120;

  switch (context) {
    case "comunicación":
      return 10;
    case "administrativo":
      return 25;
    case "trabajo":
      return 30;
    case "casa":
      return 20;
    case "salud":
      return 15;
    case "dinero":
      return 15;
    default:
      break;
  }

  if (lower.includes("llamar") || lower.includes("escribir a") || lower.includes("responder")) return 8;
  if (lower.includes("revisar") || lower.includes("leer")) return 15;
  if (lower.includes("preparar") || lower.includes("organizar")) return 40;
  return 10;
}

// MARK: - Availability ("después de las 6")

export function detectAvailability(lower: string, now: Date): Date | null {
  const markers = ["despues de las ", "a partir de las ", "desde las ", "pasadas las "];
  for (const marker of markers) {
    const time = timeAfter(marker, lower, now);
    if (time) return time;
  }

  if (lower.includes("por la tarde") || lower.includes("esta tarde")) {
    return atHour(dayReference(lower, now), 16);
  }
  if (lower.includes("por la noche") || lower.includes("esta noche")) {
    return atHour(dayReference(lower, now), 20);
  }
  if (lower.includes("manana por la manana")) {
    return atHour(addDays(now, 1), 9);
  }
  if (lower.includes("manana") && !lower.includes("esta manana")) {
    return atHour(addDays(now, 1), 9);
  }

  const time = timeAfter("a las ", lower, now);
  if (time && time.getTime() > now.getTime()) return time;
  return null;
}

// MARK: - Deadline

export function detectDeadline(lower: string, now: Date): Date | null {
  const markers = ["antes del ", "antes de las ", "para el ", "limite ", "vence "];
  for (const marker of markers) {
    if (!lower.includes(marker)) continue;
    const time = timeAfter(marker, lower, now);
    if (time) return time;
  }
  if (lower.includes("hoy mismo") || lower.includes("antes de que acabe el dia")) {
    return atHour(now, 21);
  }
  const weekday = weekdayIndex(lower);
  if (weekday !== null) return nextDateForWeekday(weekday, now, 18);
  return null;
}

// MARK: - Dependency on another person

const DEPENDENCY_CUES = [
  "estoy esperando",
  "espero que",
  "esperando a",
  "esperando que",
  "cuando me responda",
  "cuando me conteste",
  "cuando me envie",
  "depende de",
  "me tiene que",
  "tiene que enviarme",
  "tiene que responderme",
  "pendiente de que",
  "a la espera de",
  "me quedo esperando",
];

export function detectDependency(text: string, lower: string): string | null {
  if (!DEPENDENCY_CUES.some((cue) => lower.includes(cue))) return null;
  return detectPerson(text, lower) ?? "otra persona";
}

const FAMILY: [string, string][] = [
  ["mi mama", "mamá"],
  ["mi madre", "mi madre"],
  ["mi papa", "papá"],
  ["mi padre", "mi padre"],
  ["mi hermano", "mi hermano"],
  ["mi hermana", "mi hermana"],
  ["mi jefe", "mi jefe"],
  ["mi jefa", "mi jefa"],
  ["mi pareja", "mi pareja"],
  ["mi hijo", "mi hijo"],
  ["mi hija", "mi hija"],
  ["el medico", "el médico"],
  ["la doctora", "la doctora"],
  ["el doctor", "el doctor"],
  ["el banco", "el banco"],
  ["la gestoria", "la gestoría"],
];

/**
 * A very conservative rule: only capitalised words after a relationship cue, or
 * explicit family words. Nothing is inferred about the person beyond that.
 */
export function detectPerson(text: string, lower: string): string | null {
  for (const [needle, label] of FAMILY) {
    if (lower.includes(needle)) return label;
  }

  const cues = ["con", "a", "de", "que"];
  const words = text.split(/[\s,\n]+/).filter((word) => word.length > 0);
  for (let index = 1; index < words.length; index += 1) {
    const previous = words[index - 1].toLowerCase();
    if (!cues.includes(previous)) continue;
    const word = words[index];
    const first = word.charAt(0);
    if (first !== first.toUpperCase() || first === first.toLowerCase()) continue;
    const cleaned = word.replace(/[^\p{L}]/gu, "");
    if (cleaned.length < 3) continue;
    return cleaned;
  }
  return null;
}

// MARK: - Context

const CONTEXT_MAP: [string, string[]][] = [
  [
    "comunicación",
    ["llamar", "llamada", "telefono", "hablar con", "escribir a", "responder", "contestar", "mensaje", "whatsapp", "correo", "mail", "email", "avisar", "preguntar a"],
  ],
  [
    "administrativo",
    ["papeles", "papeleo", "formulario", "documento", "tramite", "solicitud", "matricula", "doctorado", "certificado", "renovar", "cita previa", "declaracion", "seguro"],
  ],
  ["dinero", ["factura", "pagar", "pago", "banco", "transferencia", "presupuesto", "impuesto", "hacienda", "nomina", "recibo"]],
  ["salud", ["medico", "dentista", "analitica", "receta", "cita medica", "psicologo", "farmacia"]],
  ["trabajo", ["reunion", "informe", "presentacion", "cliente", "propuesta", "proyecto", "entregar", "revisar codigo", "curriculum"]],
  ["casa", ["limpiar", "lavadora", "compra", "supermercado", "basura", "cocinar", "ordenar", "arreglar", "fontanero", "mudanza"]],
  ["estudio", ["estudiar", "examen", "apuntes", "leer capitulo", "tesis", "practicas"]],
];

export function detectContext(lower: string): string | null {
  for (const [context, needles] of CONTEXT_MAP) {
    if (needles.some((needle) => lower.includes(needle))) return context;
  }
  return null;
}

// MARK: - Next step

export function nextStep(lower: string, context: string | null): string {
  if (lower.includes("llamar") || lower.includes("llamada")) return "Llamarla";
  if (lower.includes("hablar con")) return "Escribirle para buscar hueco";
  if (lower.includes("responder") || lower.includes("contestar")) return "Escribir dos frases y enviar";
  if (lower.includes("correo") || lower.includes("mail") || lower.includes("email")) return "Abrir un correo nuevo";
  if (lower.includes("papeles") || lower.includes("documento") || lower.includes("formulario")) return "Juntar el primer archivo";
  if (lower.includes("pagar") || lower.includes("factura")) return "Abrir la web del banco";
  if (lower.includes("cita")) return "Buscar el número y pedir la cita";
  if (lower.includes("comprar") || lower.includes("compra")) return "Apuntar lo que falta";
  if (lower.includes("leer") || lower.includes("revisar")) return "Leer solo la primera página";
  if (lower.includes("escribir")) return "Escribir la primera frase";

  switch (context) {
    case "comunicación":
      return "Abrir la conversación";
    case "administrativo":
      return "Abrir la carpeta con los papeles";
    case "trabajo":
      return "Abrir el documento y escribir el título";
    case "casa":
      return "Empezar por lo que está más a mano";
    default:
      return "Poner delante de ti lo que necesitas para empezar";
  }
}

// MARK: - Splitting

const BIG_CUES = ["organizar", "preparar todo", "todo el", "proyecto", "mudanza", "planificar", "reformar", "declaracion", "tesis"];

export function splitIfTooBig(lower: string, minutes: number): string[] {
  const hasBigCue = BIG_CUES.some((cue) => lower.includes(cue));
  if (!hasBigCue && minutes < 75) return [];

  if (lower.includes("papeles") || lower.includes("documento") || lower.includes("formulario")) {
    return ["Listar qué papeles hacen falta", "Reunir los que ya tienes", "Pedir el que falta"];
  }
  if (lower.includes("mudanza")) {
    return ["Medir la habitación grande", "Pedir presupuesto a una empresa", "Sacar cajas del trastero"];
  }
  if (lower.includes("reunion") || lower.includes("presentacion")) {
    return ["Escribir los tres puntos clave", "Montar el esquema", "Repasarlo en voz alta"];
  }
  return ["Escribir en una línea cómo se ve terminado", "Hacer solo el primer trozo (10 min)", "Decidir cuándo sigue"];
}

// MARK: - Micro actions for "Estoy saturado"

export function microActions(title: string): string[] {
  const lower = normalized(title);
  if (lower.includes("llamar") || lower.includes("hablar")) {
    return ["Buscar el número", "Respirar y marcar", "Decir solo la primera frase"];
  }
  if (lower.includes("correo") || lower.includes("responder") || lower.includes("escribir")) {
    return ["Abrir un mensaje nuevo", "Escribir el saludo", "Enviar aunque sea corto"];
  }
  if (lower.includes("papeles") || lower.includes("documento")) {
    return ["Abrir la carpeta", "Sacar un solo papel", "Ponerlo encima de la mesa"];
  }
  if (lower.includes("limpiar") || lower.includes("ordenar")) {
    return ["Coger una sola cosa", "Ponerla en su sitio", "Parar ahí si quieres"];
  }
  return ["Ponerlo delante de ti", "Hacer solo dos minutos", "Dejarlo empezado"];
}

// MARK: - Follow-up drafts

export function followUpDraft(taskTitle: string, person: string | null, days: number): string {
  const opening = person ? `Hola ${person},` : "Hola,";
  const subject = taskTitle.trim().toLowerCase();
  const dayPart = days <= 1 ? "ayer" : `hace ${days} días`;
  return `${opening}\n\nTe escribo para retomar ${subject}. Lo dejamos ${dayPart} y quiero cerrarlo.\n¿Puedes decirme cómo va o si necesitas algo de mi parte?\n\nGracias.`;
}

// MARK: - Helpers

const SPELLED: Record<string, number> = {
  un: 1,
  una: 1,
  dos: 2,
  tres: 3,
  cuatro: 4,
  cinco: 5,
  seis: 6,
  siete: 7,
  ocho: 8,
  nueve: 9,
  diez: 10,
  quince: 15,
  veinte: 20,
  treinta: 30,
  cuarenta: 40,
};

function firstNumberBefore(keywords: string[], lower: string): number | null {
  const words = lower.split(/[^\p{L}\p{N}]+/u).filter((word) => word.length > 0);
  for (let index = 0; index < words.length; index += 1) {
    if (!keywords.includes(words[index])) continue;
    if (index === 0) continue;
    const previous = words[index - 1];
    const digits = Number.parseInt(previous, 10);
    if (Number.isFinite(digits) && /^\d+$/.test(previous)) return digits;
    if (previous in SPELLED) return SPELLED[previous];
  }
  return null;
}

/** Reads a clock time right after a marker, understanding "6", "6:30" and "18". */
function timeAfter(marker: string, lower: string, now: Date): Date | null {
  const start = lower.indexOf(marker);
  if (start < 0) return null;
  const scanner = lower.slice(start + marker.length, start + marker.length + 24);

  let digits = "";
  let minuteDigits = "";
  let seenSeparator = false;

  for (const character of scanner) {
    if (character >= "0" && character <= "9") {
      if (seenSeparator) minuteDigits += character;
      else digits += character;
      continue;
    }
    if ((character === ":" || character === "." || character === "y") && digits.length > 0 && !seenSeparator) {
      seenSeparator = true;
      continue;
    }
    if (character === " " && (digits.length === 0 || seenSeparator)) continue;
    if (digits.length > 0) break;
    if (/\p{L}/u.test(character)) break;
  }

  let hour = Number.parseInt(digits, 10);
  if (!Number.isFinite(hour) || hour < 0 || hour > 24) return null;
  const minute = Math.min(Number.parseInt(minuteDigits, 10) || 0, 59);

  const mentionsMorning = lower.includes("de la manana");
  const mentionsAfternoon = lower.includes("de la tarde") || lower.includes("de la noche");
  if (hour < 12) {
    if (mentionsAfternoon) {
      hour += 12;
    } else if (!mentionsMorning && hour <= 8) {
      // "después de las 6" in everyday Spanish means the evening.
      hour += 12;
    }
  }
  if (hour >= 24) hour = 23;

  const day = dayReference(lower, now);
  const candidate = atHour(day, hour, minute);
  if (candidate.getTime() <= now.getTime() && !lower.includes("manana")) {
    return addDays(candidate, 1);
  }
  return candidate;
}

function dayReference(lower: string, now: Date): Date {
  if (lower.includes("manana")) return addDays(now, 1);
  const weekday = weekdayIndex(lower);
  if (weekday !== null) {
    const date = nextDateForWeekday(weekday, now, 9);
    if (date) return date;
  }
  return now;
}

const WEEKDAYS: [string, number][] = [
  ["domingo", 0],
  ["lunes", 1],
  ["martes", 2],
  ["miercoles", 3],
  ["jueves", 4],
  ["viernes", 5],
  ["sabado", 6],
];

function weekdayIndex(lower: string): number | null {
  for (const [name, index] of WEEKDAYS) {
    if (lower.includes(name)) return index;
  }
  return null;
}

function nextDateForWeekday(weekday: number, from: Date, hour: number): Date {
  const candidate = atHour(from, hour);
  let delta = (weekday - candidate.getDay() + 7) % 7;
  if (delta === 0 && candidate.getTime() <= from.getTime()) delta = 7;
  return addDays(candidate, delta);
}

function atHour(date: Date, hour: number, minute = 0): Date {
  const copy = new Date(date.getTime());
  copy.setHours(hour, minute, 0, 0);
  return copy;
}

function addDays(date: Date, days: number): Date {
  const copy = new Date(date.getTime());
  copy.setDate(copy.getDate() + days);
  return copy;
}
