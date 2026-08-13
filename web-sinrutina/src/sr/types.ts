/** The small set of states SinRutina uses to reduce decision load. */
export type TaskState = "Ahora" | "Después" | "Esperando" | "Algún día" | "Completada";

export const TASK_STATES: TaskState[] = ["Ahora", "Después", "Esperando", "Algún día", "Completada"];

/** How hard SinRutina should push a single task. */
export type SRInsistence = "Suave" | "Normal" | "Importante" | "No me dejes olvidarlo";

export const INSISTENCE_ORDER: SRInsistence[] = ["Suave", "Normal", "Importante", "No me dejes olvidarlo"];

/**
 * What each level can actually do in a browser. The top level of the iPhone app
 * uses a real alarm that breaks through silent mode; the web cannot do that, so
 * it is not offered here rather than promised and quietly downgraded.
 */
export const INSISTENCE_EXPLANATION: Record<SRInsistence, string> = {
  Suave: "Sin aviso. Solo aparece cuando abres SinRutina.",
  Normal: "Sin aviso. Solo aparece cuando abres SinRutina.",
  Importante: "Aviso del navegador, si lo permites y esta pestaña sigue abierta.",
  "No me dejes olvidarlo": "Solo en el iPhone: suena aunque tengas silencio.",
};

/** Levels a browser can honour. The unmissable alarm is deliberately absent. */
export const WEB_INSISTENCE: SRInsistence[] = ["Suave", "Normal", "Importante"];

export interface Task {
  id: string;
  title: string;
  detail: string;
  createdAt: string;
  updatedAt: string;
  state: TaskState;
  estimatedMinutes: number;
  dueDate: string | null;
  availableFrom: string | null;
  completedAt: string | null;
  waitingSince: string | null;
  waitingFor: string | null;
  source: string | null;
  isCurrent: boolean;
  procrastinationCount: number;
  actualMinutes: number | null;
  preferredContext: string | null;
  isDemo: boolean;
  /** First concrete movement, proposed by the deterministic reader. */
  nextStep: string | null;
  insistence: SRInsistence;
  remindAt: string | null;
  /** How many unsolicited suggestions about this task were walked past. */
  ignoredInterventionCount: number;
}

export interface NewTaskInput {
  title: string;
  detail?: string;
  estimatedMinutes?: number;
  state?: TaskState;
  dueDate?: string | null;
  availableFrom?: string | null;
  waitingFor?: string | null;
  preferredContext?: string | null;
  nextStep?: string | null;
  source?: string | null;
  isDemo?: boolean;
}

export function makeTask(input: NewTaskInput): Task {
  const now = new Date().toISOString();
  const state = input.state ?? "Ahora";
  return {
    id: crypto.randomUUID(),
    title: input.title,
    detail: input.detail ?? "",
    createdAt: now,
    updatedAt: now,
    state,
    estimatedMinutes: Math.max(1, input.estimatedMinutes ?? 10),
    dueDate: input.dueDate ?? null,
    availableFrom: input.availableFrom ?? null,
    completedAt: null,
    waitingSince: state === "Esperando" ? now : null,
    waitingFor: input.waitingFor ?? null,
    source: input.source ?? null,
    isCurrent: state === "Ahora",
    procrastinationCount: 0,
    actualMinutes: null,
    preferredContext: input.preferredContext ?? null,
    isDemo: input.isDemo ?? false,
    nextStep: input.nextStep ?? null,
    insistence: "Normal",
    remindAt: null,
    ignoredInterventionCount: 0,
  };
}

/**
 * Who read the sentence that created a task. Stored on `source` at capture time
 * so the app never has to guess afterwards.
 */
export const CAPTURE_SOURCE = {
  local: "Captura",
  extended: "Captura \u00b7 lectura ampliada",
} as const;

export type ReaderLabel = "Lectura local" | "Lectura ampliada";

/**
 * The same wording the capture sheet uses, so a task says on Ahora exactly what
 * it said when it was written. Returns null for anything not produced by a
 * reader — demo items and tasks saved before this existed — rather than
 * claiming a reading that never happened.
 */
export function readerLabel(task: Task): ReaderLabel | null {
  if (task.isDemo) return null;
  if (task.source === CAPTURE_SOURCE.extended) return "Lectura ampliada";
  if (task.source === CAPTURE_SOURCE.local) return "Lectura local";
  return null;
}

export function isOpen(task: Task): boolean {
  return task.state !== "Completada" && task.state !== "Esperando";
}

/**
 * Days this item has been open. A neutral temporal fact: it replaces counting
 * postponements back at the person, which reads as a reproach.
 */
export function openDays(task: Task): number {
  const created = new Date(task.createdAt).getTime();
  return Math.max(0, Math.floor((Date.now() - created) / 86_400_000));
}

export function waitingDays(task: Task): number {
  if (!task.waitingSince) return 0;
  const since = new Date(task.waitingSince).getTime();
  return Math.max(0, Math.floor((Date.now() - since) / 86_400_000));
}

/** Applies a state change with the same rules the iPhone app uses. */
export function movedTo(task: Task, state: TaskState): Task {
  const now = new Date().toISOString();
  const next: Task = { ...task, state, updatedAt: now, isCurrent: state === "Ahora" };

  if (state === "Esperando") {
    next.waitingSince = task.waitingSince ?? now;
  } else {
    next.waitingSince = null;
    if (state !== "Completada") next.waitingFor = null;
  }

  if (state === "Completada") {
    next.completedAt = now;
    next.isCurrent = false;
  } else {
    next.completedAt = null;
  }

  return next;
}
