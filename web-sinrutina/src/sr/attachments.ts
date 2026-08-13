/**
 * The attachment reader.
 *
 * Half of what a person postpones arrives as a file: a letter from the bank, a
 * PDF from the town hall, a photo of a form, an invitation. SinRutina opens it,
 * pulls out the words, and hands them to the same reader that reads anything
 * typed by hand — so a file becomes a task with a first step, not another thing
 * to open later.
 *
 * What it can and cannot do is stated file by file, never guessed:
 *
 * - Plain text, Markdown, CSV, email exports: read here, in the browser.
 * - Calendar files (.ics): the event is parsed here, with its real date.
 * - PDFs: the text layer is extracted here, with no network at all.
 * - Images, and PDFs that are only scans: there is no text to extract, and a
 *   browser has no OCR. Those need the extended reader, and if it is off, this
 *   file says so instead of returning an empty task.
 */

export const ATTACHMENT_MAX_BYTES = 12 * 1024 * 1024;

/** Characters handed to a reader. Enough for a letter, short enough to stay fast. */
const MAX_TEXT = 6000;

/** Pages worth reading. What you have to do is never on page nine. */
const MAX_PAGES = 6;

/** Below this, a document has no usable text layer: it is a scan. */
const TEXT_FLOOR = 40;

export type AttachmentKind = "texto" | "calendario" | "pdf" | "imagen" | "otro";

export interface AttachmentImage {
  /** A `data:` URL, already downscaled to something a request can carry. */
  dataUrl: string;
  mediaType: string;
}

export interface AttachmentRead {
  fileName: string;
  kind: AttachmentKind;
  /** Text pulled out of the file. Empty when the file had none. */
  text: string;
  /** Set only when the words live in pixels and cannot be read here. */
  image: AttachmentImage | null;
  /** Plain Spanish account of what happened. Always shown to the person. */
  note: string;
  /** Pages read, for files that have pages. */
  pages: number | null;
}

/** A failure worth showing. Never a stack trace, never silence. */
export class AttachmentError extends Error {
  readonly userMessage: string;

  constructor(userMessage: string) {
    super(userMessage);
    this.name = "AttachmentError";
    this.userMessage = userMessage;
  }
}

const TEXT_EXTENSIONS = ["txt", "md", "markdown", "csv", "tsv", "log", "json", "eml", "vtt", "srt", "rtf"];

function extensionOf(name: string): string {
  const index = name.lastIndexOf(".");
  return index < 0 ? "" : name.slice(index + 1).toLowerCase();
}

export function kindOf(file: File): AttachmentKind {
  const extension = extensionOf(file.name);
  const type = file.type.toLowerCase();

  if (extension === "ics" || type === "text/calendar") return "calendario";
  if (extension === "pdf" || type === "application/pdf") return "pdf";
  if (type.startsWith("image/")) return "imagen";
  if (type.startsWith("text/") || TEXT_EXTENSIONS.includes(extension)) return "texto";
  if (type === "application/json") return "texto";
  return "otro";
}

/** "1,4 MB", the way a person writes it. */
export function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${Math.round(bytes / 1024)} KB`;
  return `${(bytes / (1024 * 1024)).toFixed(1).replace(".", ",")} MB`;
}

/**
 * Opens one file and returns what could be read out of it, plus an honest note
 * about how. Throws only when the file cannot be opened at all.
 */
export async function readAttachment(file: File): Promise<AttachmentRead> {
  if (file.size === 0) {
    throw new AttachmentError("Ese archivo está vacío.");
  }
  if (file.size > ATTACHMENT_MAX_BYTES) {
    throw new AttachmentError(
      `Ese archivo pesa ${formatSize(file.size)} y solo puedo abrir hasta ${formatSize(ATTACHMENT_MAX_BYTES)}.`
    );
  }

  const kind = kindOf(file);

  switch (kind) {
    case "texto":
      return readPlainText(file);
    case "calendario":
      return readCalendar(file);
    case "pdf":
      return readPdf(file);
    case "imagen":
      return readImageFile(file);
    default:
      throw new AttachmentError(
        `No sé abrir un archivo ${extensionOf(file.name).toUpperCase() || "así"}. Puedo con texto, PDF, imágenes y archivos de calendario.`
      );
  }
}

// MARK: - Plain text

async function readPlainText(file: File): Promise<AttachmentRead> {
  const raw = await file.text();
  const text = tidy(raw);
  if (text.length === 0) {
    throw new AttachmentError("Ese archivo no tiene texto dentro.");
  }
  return {
    fileName: file.name,
    kind: "texto",
    text,
    image: null,
    note: "Leído aquí mismo, sin enviarlo a ningún sitio.",
    pages: null,
  };
}

// MARK: - Calendar

interface CalendarEvent {
  summary: string;
  start: Date | null;
  location: string;
}

/**
 * Enough of RFC 5545 to read a real invitation: folded lines, escaped commas,
 * the first VEVENT. Anything it cannot parse becomes plain text, not a guess.
 */
async function readCalendar(file: File): Promise<AttachmentRead> {
  const event = parseCalendar(await file.text());
  if (!event || event.summary.length === 0) {
    throw new AttachmentError("No he encontrado ningún evento dentro de ese archivo.");
  }

  const parts = [event.summary];
  if (event.start) parts.push(`el ${describeDate(event.start)}`);
  if (event.location.length > 0) parts.push(`en ${event.location}`);

  return {
    fileName: file.name,
    kind: "calendario",
    text: parts.join(" "),
    image: null,
    note: event.start
      ? "Evento leído aquí mismo, con su fecha real."
      : "Evento leído aquí mismo. No traía hora.",
    pages: null,
  };
}

function parseCalendar(raw: string): CalendarEvent | null {
  const unfolded = raw.replace(/\r\n/g, "\n").replace(/\n[ \t]/g, "");
  const start = unfolded.indexOf("BEGIN:VEVENT");
  if (start < 0) return null;

  const end = unfolded.indexOf("END:VEVENT", start);
  const block = unfolded.slice(start, end < 0 ? undefined : end);

  const value = (name: string): string => {
    const match = block.match(new RegExp(`^${name}(;[^:\\n]*)?:(.*)$`, "mi"));
    return match ? unescapeCalendar(match[2] ?? "") : "";
  };

  return {
    summary: value("SUMMARY").trim(),
    start: parseCalendarDate(block),
    location: value("LOCATION").trim(),
  };
}

function unescapeCalendar(text: string): string {
  return text.replace(/\\n/gi, " ").replace(/\\,/g, ",").replace(/\\;/g, ";").replace(/\\\\/g, "\\").trim();
}

function parseCalendarDate(block: string): Date | null {
  const match = block.match(/^DTSTART(;[^:\n]*)?:(.*)$/im);
  const raw = match?.[2]?.trim() ?? "";
  const digits = raw.match(/^(\d{4})(\d{2})(\d{2})(?:T(\d{2})(\d{2})(\d{2})(Z)?)?$/);
  if (!digits) return null;

  const [, year, month, day, hour, minute, second, isUtc] = digits;
  const numbers = [year, month, day, hour ?? "0", minute ?? "0", second ?? "0"].map((part) =>
    Number.parseInt(part, 10)
  );
  const [y, mo, d, h, mi, s] = numbers as [number, number, number, number, number, number];

  const date = isUtc
    ? new Date(Date.UTC(y, mo - 1, d, h, mi, s))
    : new Date(y, mo - 1, d, h, mi, s);

  return Number.isNaN(date.getTime()) ? null : date;
}

function describeDate(date: Date): string {
  const day = date.toLocaleDateString("es-ES", { weekday: "long", day: "numeric", month: "long" });
  const hasTime = date.getHours() !== 0 || date.getMinutes() !== 0;
  if (!hasTime) return day;
  return `${day} a las ${date.toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" })}`;
}

// MARK: - PDF

/**
 * The text layer is read in this browser with pdf.js. Nothing is uploaded, and
 * the library is only fetched the first time a PDF is opened.
 */
async function readPdf(file: File): Promise<AttachmentRead> {
  const pdfjs = await import("pdfjs-dist");
  const workerUrl = (await import("pdfjs-dist/build/pdf.worker.min.mjs?url")).default;
  pdfjs.GlobalWorkerOptions.workerSrc = workerUrl;

  const bytes = new Uint8Array(await file.arrayBuffer());
  const task = pdfjs.getDocument({ data: bytes });

  let document: PdfDocument;
  try {
    document = await task.promise;
  } catch {
    void task.destroy();
    throw new AttachmentError("No he podido abrir ese PDF. Puede que esté protegido con contraseña.");
  }

  try {
    const pageCount = Math.min(document.numPages, MAX_PAGES);
    const chunks: string[] = [];

    for (let index = 1; index <= pageCount; index += 1) {
      const page = await document.getPage(index);
      const content = await page.getTextContent();
      const line = content.items
        .map((item) => ("str" in item ? item.str : ""))
        .join(" ");
      chunks.push(line);
      page.cleanup();
    }

    const text = tidy(chunks.join("\n"));
    if (text.length >= TEXT_FLOOR) {
      const readAll = document.numPages <= MAX_PAGES;
      return {
        fileName: file.name,
        kind: "pdf",
        text,
        image: null,
        note: readAll
          ? "Leído aquí mismo, sin enviarlo a ningún sitio."
          : `Leídas las primeras ${MAX_PAGES} páginas de ${document.numPages}, aquí mismo.`,
        pages: pageCount,
      };
    }

    // No text layer: this is a photograph wearing a PDF's clothes.
    const page = await document.getPage(1);
    const image = await renderPage(page);
    page.cleanup();

    return {
      fileName: file.name,
      kind: "pdf",
      text: "",
      image,
      note: "Este PDF es un escaneo: no lleva texto dentro, solo la imagen de la página.",
      pages: 1,
    };
  } finally {
    void task.destroy();
  }
}

type PdfModule = typeof import("pdfjs-dist");
type PdfDocument = Awaited<ReturnType<PdfModule["getDocument"]>["promise"]>;
type PdfPage = Awaited<ReturnType<PdfDocument["getPage"]>>;

async function renderPage(page: PdfPage): Promise<AttachmentImage> {
  const base = page.getViewport({ scale: 1 });
  const scale = Math.min(1400 / Math.max(base.width, base.height), 2.2);
  const viewport = page.getViewport({ scale: scale > 0 ? scale : 1 });

  const canvas = window.document.createElement("canvas");
  canvas.width = Math.round(viewport.width);
  canvas.height = Math.round(viewport.height);

  const context = canvas.getContext("2d");
  if (!context) throw new AttachmentError("Este navegador no me deja dibujar la página para leerla.");

  context.fillStyle = "#FFFFFF";
  context.fillRect(0, 0, canvas.width, canvas.height);
  await page.render({ canvasContext: context, viewport, canvas }).promise;

  return { dataUrl: compress(canvas, 0.78), mediaType: "image/jpeg" };
}

// MARK: - Images

/**
 * There is no OCR in a browser, so an image is never "read" here. It is only
 * prepared: rotated into a size a request can carry, and handed upward.
 */
async function readImageFile(file: File): Promise<AttachmentRead> {
  const bitmap = await decode(file);
  const image = downscale(bitmap);
  bitmap.close?.();

  return {
    fileName: file.name,
    kind: "imagen",
    text: "",
    image,
    note: "Una imagen no se puede leer dentro del navegador: no tiene texto, tiene píxeles.",
    pages: null,
  };
}

interface Decoded {
  width: number;
  height: number;
  close?: () => void;
  source: CanvasImageSource;
}

async function decode(file: File): Promise<Decoded> {
  if (typeof createImageBitmap === "function") {
    try {
      const bitmap = await createImageBitmap(file);
      return { width: bitmap.width, height: bitmap.height, source: bitmap, close: () => bitmap.close() };
    } catch {
      // Safari refuses some formats here but can still decode them below.
    }
  }

  const url = URL.createObjectURL(file);
  try {
    const element = await new Promise<HTMLImageElement>((resolve, reject) => {
      const image = new Image();
      image.onload = () => resolve(image);
      image.onerror = () => reject(new AttachmentError("No he podido abrir esa imagen."));
      image.src = url;
    });
    return { width: element.naturalWidth, height: element.naturalHeight, source: element };
  } catch (error) {
    if (error instanceof AttachmentError) throw error;
    throw new AttachmentError(
      "No he podido abrir esa imagen. Si viene de un iPhone en formato HEIC, exportala como JPG."
    );
  } finally {
    URL.revokeObjectURL(url);
  }
}

/** A ladder, not a fixed size: stop at the first version that fits the budget. */
function downscale(decoded: Decoded): AttachmentImage {
  const steps: { edge: number; quality: number }[] = [
    { edge: 1280, quality: 0.82 },
    { edge: 1024, quality: 0.78 },
    { edge: 832, quality: 0.74 },
    { edge: 640, quality: 0.7 },
    { edge: 512, quality: 0.65 },
  ];

  let last = "";
  for (const step of steps) {
    const longest = Math.max(decoded.width, decoded.height);
    const ratio = longest > step.edge ? step.edge / longest : 1;
    const canvas = window.document.createElement("canvas");
    canvas.width = Math.max(1, Math.round(decoded.width * ratio));
    canvas.height = Math.max(1, Math.round(decoded.height * ratio));

    const context = canvas.getContext("2d");
    if (!context) throw new AttachmentError("Este navegador no me deja preparar la imagen.");
    context.fillStyle = "#FFFFFF";
    context.fillRect(0, 0, canvas.width, canvas.height);
    context.drawImage(decoded.source, 0, 0, canvas.width, canvas.height);

    last = compress(canvas, step.quality);
    if (base64Bytes(last) <= 2_600_000) return { dataUrl: last, mediaType: "image/jpeg" };
  }

  if (last.length === 0) throw new AttachmentError("No he podido preparar esa imagen.");
  return { dataUrl: last, mediaType: "image/jpeg" };
}

function compress(canvas: HTMLCanvasElement, quality: number): string {
  return canvas.toDataURL("image/jpeg", quality);
}

function base64Bytes(dataUrl: string): number {
  const comma = dataUrl.indexOf(",");
  const payload = comma < 0 ? dataUrl : dataUrl.slice(comma + 1);
  return Math.floor((payload.length * 3) / 4);
}

// MARK: - Shared

/** Collapses the whitespace a PDF leaves behind and caps the length. */
function tidy(raw: string): string {
  const text = raw
    .replace(/\u0000/g, "")
    .replace(/[ \t\u00a0]+/g, " ")
    .replace(/\n{3,}/g, "\n\n")
    .trim();
  return text.length > MAX_TEXT ? `${text.slice(0, MAX_TEXT).trimEnd()}…` : text;
}
