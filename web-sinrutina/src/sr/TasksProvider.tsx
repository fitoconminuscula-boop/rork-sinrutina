import { createContext, useCallback, useContext, useEffect, useMemo, useState, type ReactNode } from "react";

import { buildDemoTasks } from "./demo";
import { microStep, recommendations } from "./engine";
import { suggestion, type CaptureSuggestion } from "./heuristics";
import { canPersist, readJSON, StorageKey, writeJSON } from "./storage";
import { makeTask, movedTo, type NewTaskInput, type SRInsistence, type Task, type TaskState } from "./types";

interface TasksValue {
  tasks: Task[];
  /** Only what the person wrote, never the demo items. */
  realTasks: Task[];
  isDemoMode: boolean;
  isPersistent: boolean;
  setDemoMode: (enabled: boolean) => void;
  capture: (rawText: string) => Task;
  /** Saves a reading that was already produced, whoever produced it. */
  captureRead: (read: CaptureSuggestion, source: string, detail?: string) => Task;
  addTask: (input: NewTaskInput) => Task;
  updateTask: (id: string, patch: Partial<Task>) => void;
  moveTask: (id: string, state: TaskState) => void;
  completeTask: (id: string, actualMinutes: number | null) => void;
  postponeTask: (id: string) => void;
  releaseTask: (id: string) => void;
  markWaiting: (id: string, waitingFor: string) => void;
  setInsistence: (id: string, insistence: SRInsistence) => void;
  /** Makes a task smaller in place, keeping its history. */
  shrinkTask: (id: string, step: string) => void;
  deleteTask: (id: string) => void;
  /** Adds tasks from a backup. Never overwrites and never removes anything. */
  restoreTasks: (incoming: Task[]) => void;
  eraseEverything: () => void;
  ranked: Task[];
  counts: Record<TaskState, number>;
}

const TasksContext = createContext<TasksValue | null>(null);

function decodeTasks(raw: unknown): Task[] {
  if (!Array.isArray(raw)) return [];
  return raw.filter((item): item is Task => {
    if (typeof item !== "object" || item === null) return false;
    const task = item as Partial<Task>;
    return typeof task.id === "string" && typeof task.title === "string" && typeof task.state === "string";
  });
}

export function TasksProvider({ children }: { children: ReactNode }) {
  const [tasks, setTasks] = useState<Task[]>(() => decodeTasks(readJSON<unknown>(StorageKey.tasks, [])));
  const [isDemoMode, setIsDemoMode] = useState<boolean>(() => readJSON<boolean>(StorageKey.demoMode, false));
  const [isPersistent] = useState<boolean>(() => canPersist());

  const persist = useCallback((next: Task[]) => {
    writeJSON(StorageKey.tasks, next);
  }, []);

  const mutate = useCallback(
    (transform: (current: Task[]) => Task[]) => {
      setTasks((current) => {
        const next = transform(current);
        persist(next);
        return next;
      });
    },
    [persist]
  );

  const touch = useCallback(
    (id: string, patch: (task: Task) => Task) => {
      mutate((current) =>
        current.map((task) => (task.id === id ? { ...patch(task), updatedAt: new Date().toISOString() } : task))
      );
    },
    [mutate]
  );

  const setDemoMode = useCallback(
    (enabled: boolean) => {
      setIsDemoMode(enabled);
      writeJSON(StorageKey.demoMode, enabled);
      mutate((current) => {
        const real = current.filter((task) => !task.isDemo);
        return enabled ? [...buildDemoTasks(), ...real] : real;
      });
    },
    [mutate]
  );

  // A demo switch left on from a previous visit must still have its items.
  useEffect(() => {
    if (!isDemoMode) return;
    setTasks((current) => {
      if (current.some((task) => task.isDemo)) return current;
      const next = [...buildDemoTasks(), ...current];
      persist(next);
      return next;
    });
  }, [isDemoMode, persist]);

  const addTask = useCallback(
    (input: NewTaskInput): Task => {
      const task = makeTask(input);
      mutate((current) => [task, ...current]);
      return task;
    },
    [mutate]
  );

  /**
   * Saves an already-produced reading. `source` records which reader made it —
   * the local one or the extended one — so the app never has to guess later.
   */
  const captureRead = useCallback(
    (read: CaptureSuggestion, source: string, detail?: string): Task =>
      addTask({
        title: read.title,
        detail,
        estimatedMinutes: read.estimatedMinutes,
        state: read.suggestedState,
        dueDate: read.dueDate,
        availableFrom: read.availableFrom,
        waitingFor: read.waitingFor,
        preferredContext: read.context,
        nextStep: read.nextStep,
        source,
      }),
    [addTask]
  );

  /** Reads one sentence in Spanish and turns it into a real, structured task. */
  const capture = useCallback(
    (rawText: string): Task => captureRead(suggestion(rawText), "Captura"),
    [captureRead]
  );

  const updateTask = useCallback((id: string, patch: Partial<Task>) => touch(id, (task) => ({ ...task, ...patch })), [touch]);

  const moveTask = useCallback((id: string, state: TaskState) => touch(id, (task) => movedTo(task, state)), [touch]);

  const completeTask = useCallback(
    (id: string, actualMinutes: number | null) =>
      touch(id, (task) => ({ ...movedTo(task, "Completada"), actualMinutes })),
    [touch]
  );

  /**
   * Postponing is recorded because it is the only signal used to shrink a task's
   * scope later. It is never shown back as a count.
   */
  const postponeTask = useCallback(
    (id: string) =>
      touch(id, (task) => ({
        ...movedTo(task, "Después"),
        procrastinationCount: task.procrastinationCount + 1,
      })),
    [touch]
  );

  /** "No quiero hacer esto": the task leaves Ahora without any reproach. */
  const releaseTask = useCallback((id: string) => touch(id, (task) => movedTo(task, "Algún día")), [touch]);

  const markWaiting = useCallback(
    (id: string, waitingFor: string) =>
      touch(id, (task) => ({ ...movedTo(task, "Esperando"), waitingFor: waitingFor.trim() || "otra persona" })),
    [touch]
  );

  const setInsistence = useCallback(
    (id: string, insistence: SRInsistence) => touch(id, (task) => ({ ...task, insistence })),
    [touch]
  );

  const shrinkTask = useCallback(
    (id: string, step: string) =>
      touch(id, (task) => {
        const trimmed = step.trim();
        if (trimmed.length === 0) return task;
        return {
          ...task,
          nextStep: trimmed,
          estimatedMinutes: Math.max(2, Math.min(Math.floor(task.estimatedMinutes / 3) || 2, task.estimatedMinutes)),
        };
      }),
    [touch]
  );

  const deleteTask = useCallback((id: string) => mutate((current) => current.filter((task) => task.id !== id)), [mutate]);

  /**
   * A restore only ever adds. Anything already here keeps its own version, so
   * importing the same backup twice cannot duplicate or undo a day's work.
   */
  const restoreTasks = useCallback(
    (incoming: Task[]) =>
      mutate((current) => {
        const known = new Set(current.map((task) => task.id));
        const fresh = incoming.filter((task) => !known.has(task.id));
        return fresh.length === 0 ? current : [...fresh, ...current];
      }),
    [mutate]
  );

  const eraseEverything = useCallback(() => {
    setIsDemoMode(false);
    writeJSON(StorageKey.demoMode, false);
    mutate(() => []);
  }, [mutate]);

  const realTasks = useMemo(() => tasks.filter((task) => !task.isDemo), [tasks]);
  const ranked = useMemo(() => recommendations(tasks), [tasks]);

  const counts = useMemo<Record<TaskState, number>>(
    () => ({
      Ahora: tasks.filter((task) => task.state === "Ahora").length,
      Después: tasks.filter((task) => task.state === "Después").length,
      Esperando: tasks.filter((task) => task.state === "Esperando").length,
      "Algún día": tasks.filter((task) => task.state === "Algún día").length,
      Completada: tasks.filter((task) => task.state === "Completada").length,
    }),
    [tasks]
  );

  const value = useMemo<TasksValue>(
    () => ({
      tasks,
      realTasks,
      isDemoMode,
      isPersistent,
      setDemoMode,
      capture,
      captureRead,
      addTask,
      updateTask,
      moveTask,
      completeTask,
      postponeTask,
      releaseTask,
      markWaiting,
      setInsistence,
      shrinkTask,
      deleteTask,
      restoreTasks,
      eraseEverything,
      ranked,
      counts,
    }),
    [
      tasks,
      realTasks,
      isDemoMode,
      isPersistent,
      setDemoMode,
      capture,
      captureRead,
      addTask,
      updateTask,
      moveTask,
      completeTask,
      postponeTask,
      releaseTask,
      markWaiting,
      setInsistence,
      shrinkTask,
      deleteTask,
      restoreTasks,
      eraseEverything,
      ranked,
      counts,
    ]
  );

  return <TasksContext.Provider value={value}>{children}</TasksContext.Provider>;
}

export function useTasks(): TasksValue {
  const value = useContext(TasksContext);
  if (!value) throw new Error("useTasks debe usarse dentro de TasksProvider");
  return value;
}

export { microStep };
