import { Hourglass, MoreHorizontal, Moon, Play } from "lucide-react";
import { useMemo, useState } from "react";

import { SRMark } from "./SRMark";
import { SRCard, SRPrimaryButton, SRQuietButton, SRQuietLine } from "./Primitives";
import { TaskOptionsSheet } from "./TaskOptionsSheet";
import { useAppearance } from "@/sr/AppearanceProvider";
import { activationFor, frameTask, makeBudget, resolveContext } from "@/sr/attention";
import { profileShows } from "@/sr/appearance";
import { recommendationReason } from "@/sr/engine";
import { microStep, useTasks } from "@/sr/TasksProvider";
import { openDays, readerLabel, type Task } from "@/sr/types";

/**
 * The one screen that matters: a single task, a single dominant action.
 *
 * Everything secondary passes through an information budget. Alternatives are
 * hard-capped; whatever does not fit lives in a sheet. The title and the primary
 * action are never part of the budget, because they can never be hidden.
 */
export function NowView({
  onStart,
  onSaturated,
  onOpenWaiting,
}: {
  onStart: (task: Task) => void;
  onSaturated: () => void;
  onOpenWaiting: () => void;
}) {
  const { profile } = useAppearance();
  const { ranked, counts, postponeTask, releaseTask, isDemoMode } = useTasks();
  const [optionsTask, setOptionsTask] = useState<Task | null>(null);

  const task = ranked[0] ?? null;
  const prefersMinimal = profile.nowLayout === "focus";

  const budget = useMemo(() => {
    const context = resolveContext(false, false);
    const activation = task ? activationFor(task) : "normal";
    return makeBudget(context, activation, prefersMinimal);
  }, [task, prefersMinimal]);

  const framing = useMemo(
    () => (task ? frameTask(task, microStep(task), budget) : null),
    [task, budget]
  );

  const hour = new Date().getHours();
  const isEndOfDay = hour >= 19 || hour < 4;
  const waitingCount = counts.Esperando;

  if (!task || !framing) {
    return <EmptyNow isDemoMode={isDemoMode} />;
  }

  const reason = recommendationReason(task);
  const days = openDays(task);
  // Same wording as the capture sheet: a task keeps saying who read it.
  const reader = readerLabel(task);

  // Exactly one unsolicited line is allowed above the task, chosen by how
  // concrete it is. Waiting on a real person beats anything else.
  const attentionSlot =
    waitingCount > 0 && budget.showsOtherStates ? (
      <SRQuietLine
        icon={<Hourglass />}
        text={waitingCount === 1 ? "1 cosa depende de otra persona" : `${waitingCount} cosas dependen de otros`}
        onClick={onOpenWaiting}
      />
    ) : null;

  return (
    <div className="flex min-h-full flex-col px-[var(--sr-page-padding)] pb-40 pt-[max(20px,env(safe-area-inset-top))]">
      <div className="mx-auto flex w-full max-w-[560px] flex-1 flex-col">
        {isDemoMode ? <DemoBanner /> : null}

        <div className="flex items-center gap-3 pb-6">
          {profileShows(profile, "logo") ? <SRMark state="suggesting" size={34} /> : null}
          <span className="text-[13px] font-medium text-[var(--sr-secondary-ink)]">Ahora</span>
        </div>

        {attentionSlot ? <div className="pb-4">{attentionSlot}</div> : null}

        <SRCard className="flex flex-col">
          {framing.isReduced ? (
            <p className="pb-2 text-[13px] font-medium text-[var(--sr-primary)]">Solo esto</p>
          ) : null}

          <h1 className="text-[26px] font-semibold leading-[1.18] tracking-[-0.02em] text-[var(--sr-ink)]">
            {framing.headline}
          </h1>

          {framing.support ? (
            <p className="mt-2 text-[15px] text-[var(--sr-secondary-ink)]">{framing.support}</p>
          ) : null}

          {budget.showsMeta ? (
            <p className="mt-4 flex flex-wrap items-center gap-x-2.5 gap-y-1 text-[13px] text-[var(--sr-secondary-ink)]">
              {profileShows(profile, "duration") ? <span>{framing.minutes} min</span> : null}
              {profileShows(profile, "reason") && reason ? (
                <>
                  <Dot />
                  <span>{reason}</span>
                </>
              ) : null}
              {profileShows(profile, "openDays") && days >= 2 ? (
                <>
                  <Dot />
                  <span>Abierta desde hace {days} días</span>
                </>
              ) : null}
              {reader ? (
                <>
                  <Dot />
                  <span>{reader}</span>
                </>
              ) : null}
            </p>
          ) : null}

          <div className="pt-6">
            <SRPrimaryButton onClick={() => onStart(task)}>
              <Play className="h-[17px] w-[17px]" fill="currentColor" />
              {framing.primaryLabel} · {framing.minutes} min
            </SRPrimaryButton>
          </div>

          {budget.maxAlternatives > 0 ? (
            <div className="flex items-center justify-center gap-6 pt-4">
              <SRQuietButton onClick={() => postponeTask(task.id)}>Otra cosa</SRQuietButton>
              {budget.maxAlternatives > 1 ? (
                <SRQuietButton onClick={() => releaseTask(task.id)}>No quiero hacer esto</SRQuietButton>
              ) : null}
            </div>
          ) : null}
        </SRCard>

        <div className="flex flex-col items-center gap-3 pt-6">
          <button
            type="button"
            onClick={() => setOptionsTask(task)}
            className="sr-pressable flex items-center gap-1.5 text-[13px] font-medium text-[var(--sr-secondary-ink)]"
          >
            <MoreHorizontal className="h-4 w-4" />
            Más opciones
          </button>

          <SRQuietButton onClick={onSaturated}>Estoy saturado</SRQuietButton>

          {isEndOfDay ? (
            <SRQuietLine icon={<Moon />} text="Cerrar el día" onClick={() => setOptionsTask(task)} />
          ) : null}
        </div>
      </div>

      <TaskOptionsSheet task={optionsTask} isOpen={optionsTask !== null} onClose={() => setOptionsTask(null)} />
    </div>
  );
}

function Dot() {
  return <span aria-hidden="true">·</span>;
}

function EmptyNow({ isDemoMode }: { isDemoMode: boolean }) {
  return (
    <div className="flex min-h-full flex-col px-[var(--sr-page-padding)] pb-40 pt-[max(20px,env(safe-area-inset-top))]">
      <div className="mx-auto flex w-full max-w-[560px] flex-1 flex-col">
        {isDemoMode ? <DemoBanner /> : null}
        <div className="flex flex-1 flex-col items-center justify-center text-center">
          <SRMark state="completed" size={54} />
          <h1 className="mt-7 text-[24px] font-semibold leading-[1.2] tracking-[-0.02em] text-[var(--sr-ink)]">
            No hay nada esperándote
          </h1>
          <p className="mt-3 max-w-[300px] text-[15px] text-[var(--sr-secondary-ink)]">
            Cuando te acuerdes de algo, escríbelo con el botón de abajo. Nada más.
          </p>
        </div>
      </div>
    </div>
  );
}

/**
 * Demo data is never silent. While it is on, this banner stays on screen the
 * whole time, on every screen that can show demo items.
 */
export function DemoBanner() {
  return (
    <div className="mb-4 flex items-center gap-2.5 rounded-[var(--sr-row-radius)] bg-[var(--sr-blush-a14)] px-3.5 py-2.5">
      <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-[var(--sr-blush)]" />
      <p className="text-[13px] font-medium text-[var(--sr-ink)]">
        Datos de demostración. Nada de esto es tuyo.
      </p>
    </div>
  );
}
