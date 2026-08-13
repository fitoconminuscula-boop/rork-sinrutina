import type { Task } from "./types";

/**
 * Handoff: everything that leaves SinRutina and lands somewhere that can do more
 * than a browser tab.
 *
 * A tab cannot ring through silent mode, cannot send an email, cannot write into
 * Recordatorios and cannot survive a cleared cache. So none of that is imitated
 * here. Instead each function hands the work to something that genuinely does
 * it — the system calendar, the mail app, the Atajos app, a file on disk — and
 * says plainly where the handover ends.
 *
 * The rule these all share: SinRutina prepares, the person confirms, another app
 * acts. Nothing is sent, scheduled or written by SinRutina on its own.
 */

/* -------------------------------------------------------------------------- */
/* iCalendar plumbing                                                          */
/* -------------------------------------------------------------------------- */

/** A dated thing the system calendar can take over, alarm included. */
export interface CalendarRequest {
  title: string;
  detail: string;
  /** Local date and time the block starts. */
  at: Date;
  minutes: number;
  /** Minutes of warning before it starts. 0 rings on the dot. */
  leadMinutes: number;
}

function pad(value: number): string {
  return value.toString().padStart(2, "0");
}

/** iCalendar UTC stamp: 20260813T170000Z. */
function stamp(date: Date): string {
  return (
    `${date.getUTCFullYear()}${pad(date.getUTCMonth() + 1)}${pad(date.getUTCDate())}` +
    `T${pad(date.getUTCHours())}${pad(date.getUTCMinutes())}${pad(date.getUTCSeconds())}Z`
  );
}

/** RFC 5545 escaping. A comma in a title must not split the field. */
function escapeText(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

/** Long lines must be folded at 75 octets or strict calendars reject the file. */
function fold(line: string): string {
  if (line.length <= 74) return line;
  const parts: string[] = [line.slice(0, 74)];
  let rest = line.slice(74);
  while (rest.length > 73) {
    parts.push(` ${rest.slice(0, 73)}`);
    rest = rest.slice(73);
  }
  if (rest.length > 0) parts.push(` ${rest}`);
  return parts.join("\r\n");
}

function wrapCalendar(body: string[]): string {
  return [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//SinRutina//ES",
    "CALSCALE:GREGORIAN",
    "METHOD:PUBLISH",
    ...body,
    "END:VCALENDAR",
  ]
    .map(fold)
    .join("\r\n");
}

function eventLines(request: CalendarRequest): string[] {
  const end = new Date(request.at.getTime() + Math.max(1, request.minutes) * 60_000);
  const alarm = Math.max(0, Math.round(request.leadMinutes));

  return [
    "BEGIN:VEVENT",
    `UID:${crypto.randomUUID()}@sinrutina`,
    `DTSTAMP:${stamp(new Date())}`,
    `DTSTART:${stamp(request.at)}`,
    `DTEND:${stamp(end)}`,
    `SUMMARY:${escapeText(request.title)}`,
    `DESCRIPTION:${escapeText(request.detail)}`,
    "BEGIN:VALARM",
    "ACTION:DISPLAY",
    `DESCRIPTION:${escapeText(request.title)}`,
    `TRIGGER:-PT${alarm}M`,
    "END:VALARM",
    "END:VEVENT",
  ];
}

/**
 * A real .ics event with an alarm. Opened on a phone, the system calendar takes
 * it over — and the system calendar *can* ring through silent mode.
 */
export function buildReminderFile(request: CalendarRequest): string {
  return wrapCalendar(eventLines(request));
}

/**
 * A VTODO: the calendar format for a task rather than an appointment.
 *
 * Recordatorios on a Mac, Thunderbird, Nextcloud and most task apps import this
 * directly. An iPhone is inconsistent about it — sometimes it offers Calendario
 * instead. That uncertainty is the person's to see, not ours to paper over, so
 * the screen that offers this says exactly that.
 */
export function buildTodoFile(task: Task, due: Date | null): string {
  const step = task.nextStep?.trim();
  const lines: string[] = [
    "BEGIN:VTODO",
    `UID:${crypto.randomUUID()}@sinrutina`,
    `DTSTAMP:${stamp(new Date())}`,
    `SUMMARY:${escapeText(task.title)}`,
  ];

  const detail = [step && step !== task.title ? `Primer paso: ${step}` : "", task.detail.trim()]
    .filter((part) => part.length > 0)
    .join("\n");
  if (detail.length > 0) lines.push(`DESCRIPTION:${escapeText(detail)}`);

  if (due) {
    lines.push(`DUE:${stamp(due)}`);
    // A todo with a due date and no alarm is a todo nobody sees again.
    lines.push("BEGIN:VALARM", "ACTION:DISPLAY", `DESCRIPTION:${escapeText(task.title)}`, "TRIGGER:-PT0M", "END:VALARM");
  }

  // Importante and above map onto the calendar's own high priority band.
  lines.push(`PRIORITY:${task.insistence === "Importante" ? 1 : 5}`);
  lines.push("STATUS:NEEDS-ACTION");
  lines.push("END:VTODO");

  return wrapCalendar(lines);
}

/**
 * Every dated task in one file, so a whole week moves across in a single import
 * instead of one download per row.
 *
 * Only tasks that already carry a date are included — inventing an hour for the
 * rest would be scheduling the person's day for them.
 */
export function buildAgendaFile(tasks: Task[]): string {
  const body = datedTasks(tasks).flatMap((task) => {
    const step = task.nextStep?.trim();
    return eventLines({
      title: task.title,
      detail: step && step !== task.title ? `Primer paso: ${step}` : task.detail,
      at: new Date(task.dueDate as string),
      minutes: task.estimatedMinutes,
      leadMinutes: 0,
    });
  });

  return wrapCalendar(body);
}

/** The tasks an agenda export would actually carry. Used to label the button. */
export function datedTasks(tasks: Task[]): Task[] {
  return tasks
    .filter((task) => !task.isDemo && task.state !== "Completada" && task.dueDate !== null)
    .filter((task) => !Number.isNaN(new Date(task.dueDate as string).getTime()))
    .sort((a, b) => new Date(a.dueDate as string).getTime() - new Date(b.dueDate as string).getTime());
}

/* -------------------------------------------------------------------------- */
/* Web calendars                                                               */
/* -------------------------------------------------------------------------- */

/**
 * Google Calendar's event template. Real and long-standing, but it carries no
 * alarm: Google applies whatever default that calendar has. Anyone who needs the
 * alarm guaranteed wants the file instead, and the screen says so.
 */
export function googleCalendarLink(request: CalendarRequest): string {
  const end = new Date(request.at.getTime() + Math.max(1, request.minutes) * 60_000);
  const params = new URLSearchParams({
    action: "TEMPLATE",
    text: request.title,
    dates: `${stamp(request.at)}/${stamp(end)}`,
    details: request.detail,
  });
  return `https://calendar.google.com/calendar/render?${params.toString()}`;
}

/** Outlook on the web. Same caveat about alarms as Google. */
export function outlookCalendarLink(request: CalendarRequest): string {
  const end = new Date(request.at.getTime() + Math.max(1, request.minutes) * 60_000);
  const params = new URLSearchParams({
    path: "/calendar/action/compose",
    rru: "addevent",
    subject: request.title,
    body: request.detail,
    startdt: request.at.toISOString(),
    enddt: end.toISOString(),
  });
  return `https://outlook.live.com/calendar/0/deeplink/compose?${params.toString()}`;
}

/* -------------------------------------------------------------------------- */
/* Mail and messages                                                           */
/* -------------------------------------------------------------------------- */

/** Anything that looks like an address is used as the recipient, and nothing else is. */
export function addressIn(value: string | null): string | null {
  if (!value) return null;
  const match = value.match(/[^\s<>@]+@[^\s<>@]+\.[^\s<>@]+/);
  return match ? match[0] : null;
}

/**
 * Opens the person's own mail app with the draft already written.
 *
 * `mailto:` is the one door a browser has into email, and it stops at the compose
 * window on purpose: SinRutina has no account, no server and no way to send. The
 * person reads it, changes it and presses send — or does not.
 */
export function mailtoLink(options: { to?: string | null; subject: string; body: string }): string {
  const params = new URLSearchParams();
  params.set("subject", options.subject);
  params.set("body", options.body);
  // URLSearchParams encodes spaces as "+", which several mail clients paste
  // literally into the body. %20 is understood by all of them.
  const query = params.toString().replace(/\+/g, "%20");
  return `mailto:${encodeURIComponent(options.to ?? "").replace(/%40/g, "@")}?${query}`;
}

/** The subject and body for chasing something parked in Esperando. */
export function followUpMail(task: Task, draft: string): { to: string | null; subject: string; body: string } {
  return {
    to: addressIn(task.waitingFor),
    subject: task.title,
    body: draft,
  };
}

/** WhatsApp's own share link. Opens the app or the web client, never sends. */
export function whatsappLink(text: string): string {
  return `https://wa.me/?text=${encodeURIComponent(text)}`;
}

/** The SMS compose window, with the body filled in. */
export function smsLink(text: string): string {
  // iOS wants "&body=", everything else accepts "?body=". The "?" form is the
  // one both understand when there is no recipient.
  return `sms:?body=${encodeURIComponent(text)}`;
}

/* -------------------------------------------------------------------------- */
/* The Atajos app                                                              */
/* -------------------------------------------------------------------------- */

/**
 * Runs a shortcut the person built themselves, passing the task as input.
 *
 * This is the only honest route from a browser into Recordatorios, Notas,
 * Calendario or anything else on an iPhone: SinRutina cannot reach those apps,
 * but a shortcut can, and the person owns it. It only appears once a name has
 * been saved, because a link to a shortcut that does not exist is a dead button.
 *
 * What happens after the handover is invisible to SinRutina — it cannot know
 * whether the shortcut ran, so it never claims that it did.
 */
export function shortcutLink(name: string, text: string): string {
  const params = new URLSearchParams({ name, input: "text", text });
  return `shortcuts://x-callback-url/run-shortcut?${params.toString()}`;
}

/** What a task says when it is handed to a shortcut or another app. */
export function taskAsText(task: Task): string {
  const step = task.nextStep?.trim();
  const lines: string[] = [task.title];
  if (step && step !== task.title) lines.push(`Primer paso: ${step}`);
  if (task.dueDate) {
    const due = new Date(task.dueDate);
    if (!Number.isNaN(due.getTime())) {
      lines.push(`Para el ${due.toLocaleDateString("es-ES", { day: "numeric", month: "long" })}`);
    }
  }
  return lines.join("\n");
}

/* -------------------------------------------------------------------------- */
/* Files in and out                                                            */
/* -------------------------------------------------------------------------- */

/** A filename the person will recognise in their downloads. */
export function slugFilename(title: string, extension: string, prefix = "sinrutina"): string {
  const slug = title
    .normalize("NFD")
    .replace(/[\u0300-\u036f]/g, "")
    .replace(/[^a-zA-Z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 40)
    .toLowerCase();
  return `${prefix}-${slug.length > 0 ? slug : "aviso"}.${extension}`;
}

/** Kept for callers that only ever wanted a calendar filename. */
export function reminderFilename(title: string): string {
  return slugFilename(title, "ics");
}

/**
 * Hands a file to the browser. Returns false when the browser refuses, so the
 * caller can say so instead of claiming a download that never started.
 */
export function downloadFile(contents: string, filename: string, mime: string): boolean {
  try {
    const blob = new Blob([contents], { type: `${mime};charset=utf-8` });
    const url = URL.createObjectURL(blob);
    const anchor = document.createElement("a");
    anchor.href = url;
    anchor.download = filename;
    document.body.appendChild(anchor);
    anchor.click();
    anchor.remove();
    window.setTimeout(() => URL.revokeObjectURL(url), 4000);
    return true;
  } catch (error) {
    console.warn("SinRutina: el navegador no dejó descargar el archivo.", error);
    return false;
  }
}

export function downloadReminder(request: CalendarRequest): boolean {
  return downloadFile(buildReminderFile(request), reminderFilename(request.title), "text/calendar");
}

/**
 * A backup file.
 *
 * Nothing here syncs, so the only thing standing between the person and a
 * cleared cache is a copy they hold themselves. This is that copy: plain,
 * readable, and restorable in any browser.
 */
export interface BackupFile {
  app: "SinRutina";
  version: 1;
  exportedAt: string;
  tasks: Task[];
}

export function buildBackup(tasks: Task[]): string {
  const backup: BackupFile = {
    app: "SinRutina",
    version: 1,
    exportedAt: new Date().toISOString(),
    // Demo items are not the person's data and have no business in a backup.
    tasks: tasks.filter((task) => !task.isDemo),
  };
  return JSON.stringify(backup, null, 2);
}

export function backupFilename(): string {
  const today = new Date();
  return `sinrutina-${today.getFullYear()}-${pad(today.getMonth() + 1)}-${pad(today.getDate())}.json`;
}

/** Why a backup could not be used, in terms the screen can say out loud. */
export type RestoreProblem = "unreadable" | "foreign" | "empty";

/**
 * What a restore found. `problem` is null when the file was readable; `tasks`
 * holds only the items that are genuinely new to this browser.
 */
export interface RestoreResult {
  problem: RestoreProblem | null;
  added: number;
  skipped: number;
  tasks: Task[];
}

function restoreFailed(problem: RestoreProblem): RestoreResult {
  return { problem, added: 0, skipped: 0, tasks: [] };
}

/**
 * Reads a backup and returns only the tasks that are not already here.
 *
 * A restore never overwrites and never deletes: whatever is in this browser
 * stays exactly as it is, and only genuinely new items are added. Restoring the
 * same file twice therefore changes nothing the second time.
 */
export function readBackup(raw: string, existing: Task[]): RestoreResult {
  let parsed: unknown;
  try {
    parsed = JSON.parse(raw);
  } catch {
    return restoreFailed("unreadable");
  }

  if (typeof parsed !== "object" || parsed === null) return restoreFailed("unreadable");
  const file = parsed as Partial<BackupFile>;
  if (file.app !== "SinRutina" || !Array.isArray(file.tasks)) return restoreFailed("foreign");

  const valid = file.tasks.filter((item): item is Task => {
    if (typeof item !== "object" || item === null) return false;
    const task = item as Partial<Task>;
    return typeof task.id === "string" && typeof task.title === "string" && typeof task.state === "string";
  });

  if (valid.length === 0) return restoreFailed("empty");

  const known = new Set(existing.map((task) => task.id));
  const fresh = valid.filter((task) => !known.has(task.id));

  return { problem: null, added: fresh.length, skipped: valid.length - fresh.length, tasks: fresh };
}
