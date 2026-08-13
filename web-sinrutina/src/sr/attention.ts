import { detectContext, detectMinutes, normalized } from "./heuristics";
import type { Task } from "./types";

/**
 * What the person is in the middle of right now.
 *
 * It decides **how much** the interface draws, never what it is allowed to do.
 * The engines, the data and the actions are identical in every context: the only
 * thing that changes is how many things compete for attention on screen.
 */
export type AttentionContext = "normal" | "overwhelmed" | "executing";

/**
 * Resolves the context from real state, in order of how concrete it is. Being
 * overwhelmed beats everything. The iPhone app also resolves "leaving" and
 * "studying"; neither exists here, because neither layer exists in the browser.
 */
export function resolveContext(isOverwhelmed: boolean, isExecuting: boolean): AttentionContext {
  if (isOverwhelmed) return "overwhelmed";
  if (isExecuting) return "executing";
  return "normal";
}

/**
 * How much the person is managing to start, measured only from what they did.
 * It is not a diagnosis and it is never shown as a score: its single use is to
 * decide whether the visible scope of a task must shrink.
 */
export type Activation = "normal" | "low";

/**
 * The amount of information a screen may draw.
 *
 * Everything on this list is secondary by definition: the title of the task and
 * the primary action are never part of a budget, because they can never be
 * hidden. `maxAlternatives` is the hard ceiling on immediate decisions —
 * anything beyond it lives in a sheet.
 */
export interface InformationBudget {
  context: AttentionContext;
  activation: Activation;
  /** One quiet line of metadata (duration, hour) under the title. */
  showsMeta: boolean;
  /** Counters for the other states of the day. */
  showsOtherStates: boolean;
  /** Immediate alternatives allowed next to the primary action. */
  maxAlternatives: number;
  /** True when the visible scope must shrink to the smallest movement. */
  reducesScope: boolean;
}

export function makeBudget(
  context: AttentionContext,
  activation: Activation = "normal",
  prefersMinimalLayout = false
): InformationBudget {
  switch (context) {
    case "overwhelmed":
      return {
        context,
        activation,
        showsMeta: false,
        showsOtherStates: false,
        maxAlternatives: 0,
        reducesScope: true,
      };
    case "executing":
      return {
        context,
        activation,
        showsMeta: !prefersMinimalLayout,
        showsOtherStates: false,
        maxAlternatives: prefersMinimalLayout ? 0 : 2,
        reducesScope: activation === "low",
      };
    case "normal":
      return {
        context,
        activation,
        showsMeta: !prefersMinimalLayout,
        showsOtherStates: !prefersMinimalLayout,
        maxAlternatives: 2,
        reducesScope: activation === "low",
      };
  }
}

/**
 * How one task is presented, given the current budget.
 *
 * When activation is low the scope on screen shrinks: the same task is shown as
 * its smallest real movement, so the distance between "sé que tengo que hacerlo"
 * and "ya empecé" gets shorter instead of louder.
 */
export interface TaskFraming {
  isReduced: boolean;
  /** The line that answers "¿qué tengo que hacer?". */
  headline: string;
  /** One short line under the headline, or nothing. */
  support: string | null;
  primaryLabel: string;
  minutes: number;
  /** "Abrir el informe · 2 min": the whole decision in one glance. */
  actionLabel: string;
}

export function frameTask(task: Task, microStep: string, budget: InformationBudget): TaskFraming {
  const step = microStep.trim();
  const isReduced = budget.reducesScope && step.length > 0 && step !== task.title;
  const headline = isReduced ? step : task.title;
  const minutes = isReduced ? microMinutes(step, task.estimatedMinutes) : task.estimatedMinutes;

  const support = isReduced
    ? // Where this came from, so shrinking never feels like losing the task.
      `De: ${task.title}`
    : step.length > 0 && step !== task.title
      ? step
      : null;

  return {
    isReduced,
    headline,
    support,
    primaryLabel: isReduced ? "Hacer solo eso" : "Empezar",
    minutes,
    actionLabel: `${headline} · ${minutes} min`,
  };
}

/**
 * A small movement is measured with the same reader as anything else, capped so
 * it can never claim to be longer than the task it belongs to.
 */
export function microMinutes(step: string, ceiling: number): number {
  const lower = normalized(step);
  const detected = detectMinutes(lower, detectContext(lower));
  const bounded = Math.min(Math.max(detected, 1), 5);
  return ceiling > 0 ? Math.min(bounded, ceiling) : bounded;
}

/**
 * Repeated postponement, or repeatedly walking past a suggestion, is the only
 * signal used. Nothing is inferred about the person.
 */
export function activationFor(task: Task): Activation {
  if (task.procrastinationCount >= 2) return "low";
  if (task.ignoredInterventionCount >= 2) return "low";
  return "normal";
}
