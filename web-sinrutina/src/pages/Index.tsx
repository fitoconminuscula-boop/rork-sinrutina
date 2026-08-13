import { useCallback, useEffect, useMemo, useState, useSyncExternalStore } from "react";

import { CaptureSheet } from "@/components/sr/CaptureSheet";
import { ExecutionView } from "@/components/sr/ExecutionView";
import { LaunchScreen } from "@/components/sr/LaunchScreen";
import { NowView } from "@/components/sr/NowView";
import { SaturatedView } from "@/components/sr/SaturatedView";
import { SettingsView } from "@/components/sr/SettingsView";
import { TabBar, type AppTab } from "@/components/sr/TabBar";
import { TaskListView } from "@/components/sr/TaskListView";
import { WaitingSheet } from "@/components/sr/WaitingSheet";
import { AppearanceProvider, useAppearance } from "@/sr/AppearanceProvider";
import { IntelligenceProvider } from "@/sr/IntelligenceProvider";
import { updates } from "@/sr/pwa";
import { takeIncomingIntent } from "@/sr/shortcuts";
import { TasksProvider, useTasks } from "@/sr/TasksProvider";
import { useKeyboardShortcuts } from "@/sr/useKeyboardShortcuts";
import type { Task } from "@/sr/types";
import { cn } from "@/lib/utils";

const TAB_ORDER: AppTab[] = ["now", "after", "someday", "settings"];

/**
 * The whole app in one screen stack: four destinations, one dominant action at a
 * time, and two modes that take over completely when they are running — a
 * session and being overwhelmed.
 */
type Mode = { kind: "browsing" } | { kind: "executing"; taskId: string; startedAt: number } | { kind: "saturated" };

function SinRutina() {
  const { tasks, ranked, capture } = useTasks();
  const { isStill } = useAppearance();

  const [showsLaunch, setShowsLaunch] = useState(true);
  const [tab, setTab] = useState<AppTab>("now");
  const [mode, setMode] = useState<Mode>({ kind: "browsing" });
  const [showsCapture, setShowsCapture] = useState(false);
  const [showsWaiting, setShowsWaiting] = useState(false);
  const [arrived, setArrived] = useState<string | null>(null);

  const activeTask = useMemo<Task | null>(() => {
    if (mode.kind !== "executing") return null;
    return tasks.find((task) => task.id === mode.taskId) ?? null;
  }, [mode, tasks]);

  // A session whose task disappeared has nothing left to run.
  useEffect(() => {
    if (mode.kind === "executing" && activeTask === null) setMode({ kind: "browsing" });
  }, [mode, activeTask]);

  const start = useCallback((task: Task) => {
    setMode({ kind: "executing", taskId: task.id, startedAt: Date.now() });
  }, []);

  const leaveMode = useCallback(() => setMode({ kind: "browsing" }), []);

  /**
   * Something opened the app from outside — the capture link, a long press on
   * the icon, or the system share sheet. It is read by the same reader as
   * anything typed here, saved once, and the address is cleaned afterwards.
   */
  useEffect(() => {
    const incoming = takeIncomingIntent();

    if (incoming.screen === "saturated") {
      setMode({ kind: "saturated" });
      return;
    }

    if (incoming.capture === null) return;
    if (incoming.capture.length === 0) {
      setShowsCapture(true);
      return;
    }

    const task = capture(incoming.capture);
    setTab("now");
    setArrived(task.title);
  }, [capture]);

  useEffect(() => {
    if (arrived === null) return;
    const timer = window.setTimeout(() => setArrived(null), 4000);
    return () => window.clearTimeout(timer);
  }, [arrived]);

  const shortcutHandlers = useMemo(
    () => ({
      capture: () => setShowsCapture(true),
      start: () => {
        const next = ranked[0];
        if (next) start(next);
      },
      saturated: () => setMode({ kind: "saturated" }),
      selectTab: (index: number) => {
        const next = TAB_ORDER[index];
        if (next) setTab(next);
      },
    }),
    [ranked, start]
  );

  // Off while a sheet, a session or the overwhelmed screen owns the decision.
  useKeyboardShortcuts(
    shortcutHandlers,
    !showsLaunch && mode.kind === "browsing" && !showsCapture && !showsWaiting
  );

  if (showsLaunch) {
    return (
      <>
        <div className="sr-app" aria-hidden="true" />
        <LaunchScreen onFinished={() => setShowsLaunch(false)} />
      </>
    );
  }

  // A running session and being overwhelmed both own the screen: no tab bar, no
  // capture button, nothing competing with the one thing on it.
  if (mode.kind === "executing" && activeTask) {
    return (
      <div className="sr-app">
        <main className="sr-scroll">
          <ExecutionView
            task={activeTask}
            startedAt={mode.startedAt}
            onFinish={leaveMode}
            onExit={leaveMode}
          />
        </main>
      </div>
    );
  }

  if (mode.kind === "saturated") {
    return (
      <div className="sr-app">
        <main className="sr-scroll">
          <SaturatedView task={ranked[0] ?? null} onStart={(task) => start(task)} onExit={leaveMode} />
        </main>
      </div>
    );
  }

  return (
    <>
      <div className="sr-app">
        {/* Keyed on the tab so a change of destination is a new screen arriving,
            not the old one quietly rewriting itself. The scroll position of the
            place you left is not carried into the place you arrive at. */}
        <main key={tab} className={cn("sr-scroll", !isStill && "sr-screen-in")}>
          {tab === "now" ? (
            <NowView
              onStart={start}
              onSaturated={() => setMode({ kind: "saturated" })}
              onOpenWaiting={() => setShowsWaiting(true)}
            />
          ) : null}

          {tab === "after" ? (
            <TaskListView
              state="Después"
              title="Después"
              emptyText="Aquí van las cosas que tienen su momento más adelante."
            />
          ) : null}

          {tab === "someday" ? (
            <TaskListView
              state="Algún día"
              title="Algún día"
              emptyText="Nada aparcado. Este sitio existe para que algo pueda esperar sin pesar."
            />
          ) : null}

          {tab === "settings" ? <SettingsView /> : null}
        </main>
      </div>

      {arrived ? (
        <div
          role="status"
          className={cn(
            "fixed inset-x-0 top-[max(12px,env(safe-area-inset-top))] z-40 mx-auto w-fit max-w-[92vw] rounded-full bg-[var(--sr-elevated)] px-4 py-2.5 text-[13px] font-medium text-[var(--sr-ink)] shadow-[var(--sr-shadow)]",
            !isStill && "sr-fade-in"
          )}
        >
          Guardado: {arrived}
        </div>
      ) : null}

      <UpdateLine />

      <TabBar active={tab} onSelect={setTab} onCapture={() => setShowsCapture(true)} />

      <CaptureSheet isOpen={showsCapture} onClose={() => setShowsCapture(false)} />
      <WaitingSheet isOpen={showsWaiting} onClose={() => setShowsWaiting(false)} />
    </>
  );
}

/**
 * A new version has finished downloading in the background.
 *
 * It is not applied on its own: a reload while someone is halfway through
 * writing something down is exactly the kind of thing this app exists to avoid.
 * The line sits above the tab bar until it is taken or the tab is closed.
 */
function UpdateLine() {
  const { isStill } = useAppearance();
  const isReady = useSyncExternalStore(updates.subscribe, updates.isReady, () => false);

  if (!isReady) return null;

  return (
    <div
      className={cn(
        "fixed inset-x-0 bottom-[calc(96px+max(12px,env(safe-area-inset-bottom)))] z-40 mx-auto flex w-fit max-w-[92vw] items-center gap-3 rounded-full bg-[var(--sr-elevated)] py-2 pl-4 pr-2 shadow-[0_8px_28px_rgb(0_0_0_/_0.14)]",
        !isStill && "sr-fade-in"
      )}
      role="status"
    >
      <span className="text-[13px] text-[var(--sr-ink)]">Hay una versión nueva lista.</span>
      <button
        type="button"
        onClick={() => updates.activate()}
        className="sr-pressable rounded-full bg-[var(--sr-primary)] px-3 py-1.5 text-[13px] font-semibold text-[var(--sr-on-primary)]"
      >
        Usarla
      </button>
    </div>
  );
}

export default function Index() {
  return (
    <AppearanceProvider>
      <TasksProvider>
        <IntelligenceProvider>
          <SinRutina />
        </IntelligenceProvider>
      </TasksProvider>
    </AppearanceProvider>
  );
}
