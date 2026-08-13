import { Check, MoreHorizontal, Pause, RotateCcw } from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { SRMark } from "./SRMark";
import { SRPrimaryButton, SRQuietButton, SRSheet, SRSheetRow } from "./Primitives";
import { useAppearance, useHaptics } from "@/sr/AppearanceProvider";
import { makeBudget } from "@/sr/attention";
import { microStep, useTasks } from "@/sr/TasksProvider";
import type { Task } from "@/sr/types";

/**
 * A session in progress. Only the active task is on screen.
 *
 * Primary action plus at most two quiet alternatives; everything else lives
 * behind "Más opciones". The clock counts up rather than down, because a
 * countdown turns a start into a deadline.
 */
export function ExecutionView({
  task,
  startedAt,
  onFinish,
  onExit,
}: {
  task: Task;
  startedAt: number;
  onFinish: () => void;
  onExit: () => void;
}) {
  const { profile, isStill } = useAppearance();
  const { completeTask, postponeTask, markWaiting } = useTasks();
  const haptics = useHaptics();

  const [elapsed, setElapsed] = useState(() => Math.floor((Date.now() - startedAt) / 1000));
  const [showsOptions, setShowsOptions] = useState(false);

  useEffect(() => {
    const timer = window.setInterval(() => {
      setElapsed(Math.floor((Date.now() - startedAt) / 1000));
    }, 1000);
    return () => window.clearInterval(timer);
  }, [startedAt]);

  const budget = useMemo(
    () => makeBudget("executing", "normal", profile.nowLayout === "focus"),
    [profile.nowLayout]
  );

  const step = microStep(task);
  const minutes = Math.floor(elapsed / 60);
  const seconds = elapsed % 60;

  const finish = (): void => {
    haptics.success();
    completeTask(task.id, elapsed / 60);
    onFinish();
  };

  return (
    <div className="flex min-h-full flex-col px-[var(--sr-page-padding)] pb-40 pt-[max(24px,env(safe-area-inset-top))]">
      <div className="mx-auto flex w-full max-w-[560px] flex-1 flex-col">
        <div className="flex items-center gap-3">
          <SRMark state="focusing" size={34} />
          <span className="text-[13px] font-medium text-[var(--sr-secondary-ink)]">En marcha</span>
        </div>

        <div className="flex flex-1 flex-col justify-center py-10">
          <p
            className="text-[16px] tabular-nums text-[var(--sr-secondary-ink)]"
            aria-label={`Llevas ${minutes} minutos`}
            role="timer"
          >
            {minutes}:{seconds.toString().padStart(2, "0")}
          </p>

          <h1 className="mt-3 text-[28px] font-semibold leading-[1.15] tracking-[-0.02em] text-[var(--sr-ink)]">
            {task.title}
          </h1>

          {budget.showsMeta && step !== task.title ? (
            <p className="mt-3 text-[15px] text-[var(--sr-secondary-ink)]">{step}</p>
          ) : null}
        </div>

        <div className="flex flex-col gap-3">
          <SRPrimaryButton onClick={finish}>
            <Check className="h-[18px] w-[18px]" />
            He terminado
          </SRPrimaryButton>

          {budget.maxAlternatives > 0 ? (
            <div className="flex items-center justify-center gap-6 pt-1">
              <SRQuietButton onClick={onExit}>Pausar</SRQuietButton>
              {budget.maxAlternatives > 1 ? (
                <SRQuietButton
                  onClick={() => {
                    postponeTask(task.id);
                    onExit();
                  }}
                >
                  Dejarlo para después
                </SRQuietButton>
              ) : null}
            </div>
          ) : null}

          <button
            type="button"
            onClick={() => setShowsOptions(true)}
            className="sr-pressable mx-auto flex items-center gap-1.5 pt-1 text-[13px] font-medium text-[var(--sr-secondary-ink)]"
          >
            <MoreHorizontal className="h-4 w-4" />
            Más opciones
          </button>
        </div>
      </div>

      <SRSheet isOpen={showsOptions} onClose={() => setShowsOptions(false)} title="Esta sesión">
        <div className={isStill ? "" : "sr-fade-in"}>
          <SRSheetRow
            icon={<Pause />}
            title="Pausar y volver a Ahora"
            detail="El tiempo de esta sesión no se guarda"
            onClick={() => {
              setShowsOptions(false);
              onExit();
            }}
          />
          <SRSheetRow
            icon={<RotateCcw />}
            title="Dejarlo para después"
            onClick={() => {
              postponeTask(task.id);
              setShowsOptions(false);
              onExit();
            }}
          />
          <SRSheetRow
            icon={<Check />}
            title="Estoy esperando a alguien"
            detail="Sale de Ahora hasta que te respondan"
            tone="quiet"
            onClick={() => {
              markWaiting(task.id, task.waitingFor ?? "otra persona");
              setShowsOptions(false);
              onExit();
            }}
          />
        </div>
      </SRSheet>
    </div>
  );
}
