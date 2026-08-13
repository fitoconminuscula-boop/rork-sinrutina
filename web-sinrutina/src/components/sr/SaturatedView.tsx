import { useEffect, useState } from "react";

import { SRMark } from "./SRMark";
import { SRPrimaryButton, SRQuietButton } from "./Primitives";
import { microActions } from "@/sr/heuristics";
import { useIntelligence } from "@/sr/IntelligenceProvider";
import { useTasks } from "@/sr/TasksProvider";
import type { Task } from "@/sr/types";

/**
 * Overwhelmed: the screen strips down to the smallest possible movement, the
 * primary action, and the way out. Nothing else is drawn — no metadata, no
 * alternatives, no counters.
 *
 * The extended reader can propose a smaller movement than the local one, but it
 * is never waited for: a first step is on screen instantly, and only quietly
 * replaced if a better one arrives before the person acts.
 */
export function SaturatedView({
  task,
  onStart,
  onExit,
}: {
  task: Task | null;
  onStart: (task: Task, step: string) => void;
  onExit: () => void;
}) {
  const { shrinkTask } = useTasks();
  const { microActions: askForSteps, isEnabled } = useIntelligence();

  const local = task ? microActions(task.title)[0] : null;
  const [step, setStep] = useState<string | null>(local);

  useEffect(() => {
    setStep(task ? microActions(task.title)[0] : null);
  }, [task]);

  useEffect(() => {
    if (!task || !isEnabled) return;
    let isCurrent = true;
    void askForSteps(task.title).then((result) => {
      const first = result.steps[0];
      if (isCurrent && first) setStep(first);
    });
    return () => {
      isCurrent = false;
    };
  }, [task, isEnabled, askForSteps]);

  return (
    <div className="flex min-h-full flex-col justify-center px-[var(--sr-page-padding)] pb-40 pt-[max(24px,env(safe-area-inset-top))]">
      <div className="mx-auto w-full max-w-[460px] text-center">
        <SRMark state="waiting" size={54} className="mx-auto" />

        {task && step ? (
          <>
            <p className="mt-8 text-[15px] text-[var(--sr-secondary-ink)]">Solo esto</p>
            <h1 className="mt-2 text-[27px] font-semibold leading-[1.2] tracking-[-0.02em] text-[var(--sr-ink)]">
              {step}
            </h1>

            <div className="mt-10">
              <SRPrimaryButton
                onClick={() => {
                  shrinkTask(task.id, step);
                  onStart(task, step);
                }}
              >
                Hacer solo eso
              </SRPrimaryButton>
            </div>
          </>
        ) : (
          <>
            <h1 className="mt-8 text-[27px] font-semibold leading-[1.2] tracking-[-0.02em] text-[var(--sr-ink)]">
              No hay nada que tengas que hacer ahora
            </h1>
            <p className="mt-3 text-[15px] text-[var(--sr-secondary-ink)]">Puedes cerrar esto y volver luego.</p>
          </>
        )}

        <div className="mt-6">
          <SRQuietButton onClick={onExit}>Salir de aquí</SRQuietButton>
        </div>
      </div>
    </div>
  );
}
