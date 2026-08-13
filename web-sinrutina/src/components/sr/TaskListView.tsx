import { ChevronRight } from "lucide-react";
import { useMemo, useState } from "react";

import { DemoBanner } from "./NowView";
import { TaskOptionsSheet } from "./TaskOptionsSheet";
import { useAppearance } from "@/sr/AppearanceProvider";
import { DENSITIES, profileShows } from "@/sr/appearance";
import { formatHour } from "@/sr/engine";
import { useTasks } from "@/sr/TasksProvider";
import { openDays, waitingDays, type Task, type TaskState } from "@/sr/types";

/**
 * The other states, as a plain list.
 *
 * The same attention rules apply here: one line of metadata per row at most, and
 * everything else behind the row's own sheet. A list is for finding something,
 * not for deciding — so no row competes with another.
 */
export function TaskListView({
  state,
  title,
  emptyText,
}: {
  state: TaskState;
  title: string;
  emptyText: string;
}) {
  const { profile } = useAppearance();
  const { tasks, isDemoMode } = useTasks();
  const [optionsTask, setOptionsTask] = useState<Task | null>(null);

  const visible = useMemo(
    () =>
      tasks
        .filter((task) => task.state === state)
        .sort((lhs, rhs) => new Date(rhs.updatedAt).getTime() - new Date(lhs.updatedAt).getTime()),
    [tasks, state]
  );

  const showsDetail = DENSITIES[profile.density].showsSecondaryDetail;

  return (
    <div className="flex min-h-full flex-col px-[var(--sr-page-padding)] pb-40 pt-[max(20px,env(safe-area-inset-top))]">
      <div className="mx-auto w-full max-w-[560px]">
        {isDemoMode ? <DemoBanner /> : null}

        <h1 className="pb-5 text-[28px] font-semibold tracking-[-0.02em] text-[var(--sr-ink)]">{title}</h1>

        {visible.length === 0 ? (
          <p className="pt-10 text-center text-[15px] text-[var(--sr-secondary-ink)]">{emptyText}</p>
        ) : (
          <ul className="flex flex-col" style={{ gap: "var(--sr-row-gap)" }}>
            {visible.map((task) => (
              <li key={task.id}>
                <button
                  type="button"
                  onClick={() => setOptionsTask(task)}
                  className="sr-card sr-pressable flex w-full items-center gap-3 text-left"
                  style={{ padding: "var(--sr-row-padding)", borderRadius: "var(--sr-row-radius)" }}
                >
                  <span className="min-w-0 flex-1">
                    <span className="block truncate text-[16px] font-medium text-[var(--sr-ink)]">
                      {task.title}
                    </span>
                    {showsDetail ? (
                      <span className="mt-0.5 block truncate text-[13px] text-[var(--sr-secondary-ink)]">
                        {metaLine(task, profileShows(profile, "duration"), profileShows(profile, "dueTime"))}
                      </span>
                    ) : null}
                  </span>
                  {task.isDemo ? (
                    <span className="shrink-0 rounded-full bg-[var(--sr-blush-a14)] px-2 py-0.5 text-[11px] font-semibold text-[var(--sr-ink)]">
                      Demo
                    </span>
                  ) : null}
                  <ChevronRight className="h-4 w-4 shrink-0 text-[var(--sr-secondary-ink)]/70" />
                </button>
              </li>
            ))}
          </ul>
        )}
      </div>

      <TaskOptionsSheet task={optionsTask} isOpen={optionsTask !== null} onClose={() => setOptionsTask(null)} />
    </div>
  );
}

/** One quiet line, never more. Neutral facts only — no urgency as punishment. */
function metaLine(task: Task, showsDuration: boolean, showsDue: boolean): string {
  const parts: string[] = [];

  if (task.state === "Esperando" && task.waitingFor) {
    const days = waitingDays(task);
    parts.push(days >= 1 ? `Esperas a ${task.waitingFor} · ${days} d` : `Esperas a ${task.waitingFor}`);
  } else {
    if (showsDuration) parts.push(`${task.estimatedMinutes} min`);
    if (showsDue && task.dueDate) {
      const due = new Date(task.dueDate);
      const isToday = due.toDateString() === new Date().toDateString();
      parts.push(isToday ? `Hoy ${formatHour(due)}` : due.toLocaleDateString("es-ES", { day: "numeric", month: "short" }));
    }
    const days = openDays(task);
    if (parts.length < 2 && days >= 3) parts.push(`Abierta ${days} d`);
  }

  return parts.join(" · ");
}
