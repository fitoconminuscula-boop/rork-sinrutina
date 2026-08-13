import { detectContext, nextStep, normalized } from "./heuristics";
import type { Task } from "./types";

/**
 * Deterministic, local recommendation logic. It never returns a waiting item.
 *
 * Ported unchanged from the iPhone app, minus the calendar and departure inputs:
 * a browser cannot read the person's calendar, so the window is simply unknown
 * rather than guessed at.
 */
export function score(task: Task, now: Date = new Date()): number {
  let value = 0;
  if (task.state === "Ahora") value += 320;
  if (task.state === "Después") value += 90;
  if (task.state === "Algún día") value += 10;

  if (task.dueDate) {
    const days = (new Date(task.dueDate).getTime() - now.getTime()) / 86_400_000;
    if (days < 0) {
      value += 1_000 + Math.min(Math.abs(days) * 25, 500);
    } else {
      value += Math.max(0, 260 - days * 32);
    }
  }

  if (task.estimatedMinutes <= 15) value += 70;
  if (task.estimatedMinutes <= 5) value += 22;
  value += task.procrastinationCount * 36;
  if (task.isCurrent) value += 80;
  if (task.availableFrom && new Date(task.availableFrom).getTime() > now.getTime()) value -= 10_000;

  switch (task.insistence) {
    case "No me dejes olvidarlo":
      value += 180;
      break;
    case "Importante":
      value += 90;
      break;
    case "Normal":
      break;
    case "Suave":
      value -= 30;
      break;
  }

  return value;
}

export function recommendations(tasks: Task[], now: Date = new Date()): Task[] {
  const candidates = tasks.filter((task) => {
    if (task.state === "Completada" || task.state === "Esperando") return false;
    if (task.availableFrom && new Date(task.availableFrom).getTime() > now.getTime()) return false;
    return true;
  });
  return [...candidates].sort((lhs, rhs) => score(rhs, now) - score(lhs, now));
}

/** The smallest concrete movement for a task, always a real sentence. */
export function microStep(task: Task): string {
  if (task.nextStep && task.nextStep.length > 0) return task.nextStep;
  const lower = normalized(task.title);
  return nextStep(lower, task.preferredContext ?? detectContext(lower));
}

/**
 * A calm sentence explaining what is shaping the recommendation. Neutral facts
 * only: never a reproach, never a count of postponements shown back.
 */
export function recommendationReason(task: Task, now: Date = new Date()): string | null {
  if (task.dueDate) {
    const due = new Date(task.dueDate);
    const hours = (due.getTime() - now.getTime()) / 3_600_000;
    if (hours < 0) return "La fecha límite ya pasó";
    if (hours <= 24) return `Vence hoy a las ${formatHour(due)}`;
    const days = Math.round(hours / 24);
    return days === 1 ? "Vence mañana" : `Vence en ${days} días`;
  }
  if (task.estimatedMinutes <= 5) return "Es de las cortas";
  if (task.isCurrent) return "Es la que dejaste en marcha";
  if (task.state === "Ahora") return "Está en Ahora";
  return null;
}

export function formatHour(date: Date): string {
  return date.toLocaleTimeString("es-ES", { hour: "2-digit", minute: "2-digit" });
}
