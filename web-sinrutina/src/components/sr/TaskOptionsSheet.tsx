import {
  Bell,
  CalendarClock,
  CalendarPlus,
  CheckSquare,
  Clock,
  ExternalLink,
  Hourglass,
  Leaf,
  Mail,
  Minimize2,
  Share2,
  Trash2,
  Wand2,
} from "lucide-react";
import { useEffect, useMemo, useState } from "react";

import { SRSegmented, SRSheet, SRSheetRow } from "./Primitives";
import {
  buildTodoFile,
  downloadFile,
  downloadReminder,
  googleCalendarLink,
  mailtoLink,
  outlookCalendarLink,
  shortcutLink,
  slugFilename,
  taskAsText,
  type CalendarRequest,
} from "@/sr/handoff";
import { useIntelligence } from "@/sr/IntelligenceProvider";
import { canRunShortcuts, handOff, savedShortcutName, type HandoffResult } from "@/sr/shortcuts";
import { microStep, useTasks } from "@/sr/TasksProvider";
import { WEB_INSISTENCE, INSISTENCE_EXPLANATION, type Task } from "@/sr/types";

/** How much warning the calendar event carries. The file honours all of these. */
const LEAD_OPTIONS: { id: string; label: string; minutes: number }[] = [
  { id: "0", label: "A la hora", minutes: 0 },
  { id: "10", label: "10 min antes", minutes: 10 },
  { id: "60", label: "1 h antes", minutes: 60 },
  { id: "1440", label: "1 día antes", minutes: 1440 },
];

/**
 * Everything that is not the dominant action. It exists so the main screen can
 * hold exactly one decision while nothing becomes unreachable.
 */
export function TaskOptionsSheet({
  task,
  isOpen,
  onClose,
}: {
  task: Task | null;
  isOpen: boolean;
  onClose: () => void;
}) {
  const { moveTask, markWaiting, postponeTask, shrinkTask, deleteTask, setInsistence } = useTasks();
  const { split, isEnabled } = useIntelligence();
  const [waitingFor, setWaitingFor] = useState("");
  const [showsWaiting, setShowsWaiting] = useState(false);
  const [showsReminder, setShowsReminder] = useState(false);
  const [reminderAt, setReminderAt] = useState("");
  const [lead, setLead] = useState("0");
  const [reminderFailed, setReminderFailed] = useState(false);
  const [handoff, setHandoff] = useState<HandoffResult | null>(null);
  const [todoSaved, setTodoSaved] = useState(false);
  const [finerStep, setFinerStep] = useState<{ taskId: string; step: string } | null>(null);

  // The Atajos bridge only exists once the person has built a shortcut and told
  // SinRutina its name. Until then there is nothing to open, so nothing is shown.
  const shortcutName = useMemo(() => (isOpen ? savedShortcutName() : ""), [isOpen]);
  const offersShortcut = shortcutName.length > 0 && canRunShortcuts();

  // A smaller first piece can be proposed while the sheet is open, but the
  // deterministic one is already on the row: nothing here ever waits.
  useEffect(() => {
    if (!isOpen || !task || !isEnabled) return;
    let isCurrent = true;
    void split(task.title).then((result) => {
      const first = result.steps[0];
      if (isCurrent && first) setFinerStep({ taskId: task.id, step: first });
    });
    return () => {
      isCurrent = false;
    };
  }, [isOpen, task, isEnabled, split]);

  if (!task) return null;

  const close = (): void => {
    setShowsWaiting(false);
    setShowsReminder(false);
    setWaitingFor("");
    setReminderFailed(false);
    setHandoff(null);
    setTodoSaved(false);
    onClose();
  };

  const step = finerStep?.taskId === task.id ? finerStep.step : microStep(task);

  const openReminder = (): void => {
    // The hour is never invented: it starts from the task's own deadline, or from
    // one hour ahead, and the person confirms it before anything is written.
    const start = task.dueDate ? new Date(task.dueDate) : new Date(Date.now() + 3_600_000);
    setReminderAt(localInputValue(start));
    setLead("0");
    setReminderFailed(false);
    setShowsReminder(true);
  };

  /** The event as everyone downstream needs it, or null if the hour is not real. */
  const buildRequest = (): CalendarRequest | null => {
    const at = new Date(reminderAt);
    if (Number.isNaN(at.getTime())) return null;
    return {
      title: task.title,
      detail: step !== task.title ? `Primer paso: ${step}` : "",
      at,
      minutes: task.estimatedMinutes,
      leadMinutes: LEAD_OPTIONS.find((option) => option.id === lead)?.minutes ?? 0,
    };
  };

  const sendToCalendar = (): void => {
    const request = buildRequest();
    if (!request || !downloadReminder(request)) {
      setReminderFailed(true);
      return;
    }
    close();
  };

  /**
   * A web calendar opens in its own tab with the event already filled in. It
   * cannot carry our alarm, so the screen says which reminder will apply.
   */
  const openWebCalendar = (build: (request: CalendarRequest) => string): void => {
    const request = buildRequest();
    if (!request) {
      setReminderFailed(true);
      return;
    }
    window.open(build(request), "_blank", "noopener,noreferrer");
    close();
  };

  /** A VTODO, which is what a task app expects instead of an appointment. */
  const sendToReminders = (): void => {
    const due = task.dueDate ? new Date(task.dueDate) : null;
    const ok = downloadFile(
      buildTodoFile(task, due && !Number.isNaN(due.getTime()) ? due : null),
      slugFilename(task.title, "ics", "sinrutina-tarea"),
      "text/calendar"
    );
    setTodoSaved(ok);
    if (!ok) return;
    window.setTimeout(() => setTodoSaved(false), 3200);
  };

  /** Opens the person's own mail app with the draft written. Nothing is sent. */
  const openMail = (): void => {
    const body = [taskAsText(task), "", task.detail.trim()].filter((part) => part.length > 0).join("\n");
    window.location.href = mailtoLink({ subject: task.title, body });
  };

  return (
    <SRSheet isOpen={isOpen} onClose={close} title={task.title}>
      {showsReminder ? (
        <div className="flex flex-col gap-3 pb-2">
          <p className="text-[14px] leading-relaxed text-[var(--sr-secondary-ink)]">
            SinRutina no puede sonar con el móvil en silencio, pero tu calendario sí. Elige la hora y te doy el
            evento con aviso: lo abres una vez y a partir de ahí suena él.
          </p>
          <input
            type="datetime-local"
            value={reminderAt}
            onChange={(event) => {
              setReminderAt(event.target.value);
              setReminderFailed(false);
            }}
            aria-label="Hora del aviso"
            className="w-full rounded-[var(--sr-row-radius)] border border-[var(--sr-divider)] bg-[var(--sr-surface)] px-4 py-3 text-[16px] text-[var(--sr-ink)] outline-none focus:border-[var(--sr-primary)]"
          />

          <div>
            <p className="mb-1.5 text-[13px] font-medium text-[var(--sr-ink)]">Avisar</p>
            <SRSegmented
              label="Cuánto antes avisar"
              value={lead}
              onChange={setLead}
              options={LEAD_OPTIONS.map((option) => ({ id: option.id, label: option.label }))}
            />
          </div>

          {reminderFailed ? (
            <p className="text-[13px] text-[var(--sr-secondary-ink)]">
              Esa hora no me vale, o el navegador no me ha dejado darte el archivo. Prueba otra vez.
            </p>
          ) : null}

          <button type="button" onClick={sendToCalendar} className="sr-primary-button">
            Descargar el evento
          </button>
          <p className="text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">
            El archivo lleva el aviso dentro, así que suena a la hora que has elegido pase lo que pase.
          </p>

          <div className="border-t border-[var(--sr-divider)] pt-3">
            <p className="text-[13px] font-medium text-[var(--sr-ink)]">O abrirlo en un calendario web</p>
            <div className="mt-2 flex flex-wrap gap-2">
              <button
                type="button"
                onClick={() => openWebCalendar(googleCalendarLink)}
                className="sr-pressable inline-flex items-center gap-1.5 rounded-full bg-[var(--sr-primary-soft)] px-3.5 py-2 text-[13px] font-semibold text-[var(--sr-primary)]"
              >
                <ExternalLink className="h-3.5 w-3.5" />
                Google Calendar
              </button>
              <button
                type="button"
                onClick={() => openWebCalendar(outlookCalendarLink)}
                className="sr-pressable inline-flex items-center gap-1.5 rounded-full bg-[var(--sr-primary-soft)] px-3.5 py-2 text-[13px] font-semibold text-[var(--sr-primary)]"
              >
                <ExternalLink className="h-3.5 w-3.5" />
                Outlook
              </button>
            </div>
            <p className="mt-2 text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">
              Estos dos se abren con el evento escrito, pero el aviso lo pone su calendario por defecto: no puedo
              elegirlo desde aquí. Si lo que quieres es que suene a una hora exacta, descarga el archivo.
            </p>
          </div>

          <p className="text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">
            El aviso pasa a vivir en tu calendario, no aquí. Si luego cambias la tarea, el evento no se entera.
          </p>
        </div>
      ) : showsWaiting ? (
        <div className="flex flex-col gap-3 pb-2">
          <p className="text-[14px] text-[var(--sr-secondary-ink)]">¿A quién esperas?</p>
          <input
            value={waitingFor}
            onChange={(event) => setWaitingFor(event.target.value)}
            placeholder="mi gestoría"
            aria-label="A quién esperas"
            autoFocus
            className="w-full rounded-[var(--sr-row-radius)] border border-[var(--sr-divider)] bg-[var(--sr-surface)] px-4 py-3 text-[16px] text-[var(--sr-ink)] outline-none focus:border-[var(--sr-primary)]"
          />
          <button
            type="button"
            onClick={() => {
              markWaiting(task.id, waitingFor);
              close();
            }}
            className="sr-primary-button"
          >
            Moverla a Esperando
          </button>
        </div>
      ) : (
        <div className="pb-2">
          <SRSheetRow
            icon={<Clock />}
            title="Dejarlo para después"
            onClick={() => {
              postponeTask(task.id);
              close();
            }}
          />
          <SRSheetRow
            icon={<Hourglass />}
            title="Estoy esperando a alguien"
            detail="Sale de Ahora sin desaparecer"
            onClick={() => setShowsWaiting(true)}
          />
          <SRSheetRow
            icon={<Leaf />}
            title="Moverla a Algún día"
            onClick={() => {
              moveTask(task.id, "Algún día");
              close();
            }}
          />
          {step !== task.title ? (
            <SRSheetRow
              icon={<Minimize2 />}
              title="Hacerla más pequeña"
              detail={step}
              onClick={() => {
                shrinkTask(task.id, step);
                close();
              }}
            />
          ) : null}
          {task.state !== "Ahora" ? (
            <SRSheetRow
              icon={<CalendarClock />}
              title="Traerla a Ahora"
              onClick={() => {
                moveTask(task.id, "Ahora");
                close();
              }}
            />
          ) : null}

          <div className="mt-4 border-t border-[var(--sr-divider)] pt-4">
            <p className="px-3 text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--sr-secondary-ink)]">
              Sacarla de aquí
            </p>
            <div className="mt-1">
              <SRSheetRow
                icon={<CalendarPlus />}
                title="Llevarlo a mi calendario"
                detail="Con aviso: suena aunque tengas el móvil en silencio"
                onClick={openReminder}
              />
              <SRSheetRow
                icon={<CheckSquare />}
                title={todoSaved ? "Archivo descargado" : "Llevarlo a mis recordatorios"}
                detail={
                  todoSaved
                    ? "Ábrelo y elige la app que quieras"
                    : "Archivo de tarea para Recordatorios y apps parecidas"
                }
                onClick={sendToReminders}
              />
              <SRSheetRow
                icon={<Mail />}
                title="Escribirlo por correo"
                detail="Se abre tu correo con el borrador. No se envía nada."
                onClick={openMail}
              />
              {offersShortcut ? (
                <SRSheetRow
                  icon={<Wand2 />}
                  title={`Mandarla a «tu atajo»`}
                  detail={`Abre «${shortcutName}» en la app Atajos con esta tarea dentro`}
                  onClick={() => {
                    window.location.href = shortcutLink(shortcutName, taskAsText(task));
                  }}
                />
              ) : null}
              <SRSheetRow
                icon={<Share2 />}
                title={
                  handoff === "shared"
                    ? "Compartida"
                    : handoff === "copied"
                      ? "Copiada al portapapeles"
                      : handoff === "failed"
                        ? "No he podido: cópiala a mano"
                        : "Mandarla a otra app"
                }
                detail="Solo el título y el primer paso"
                tone="quiet"
                onClick={() => {
                  void handOff(task).then(setHandoff);
                }}
              />
            </div>
            <p className="mt-1.5 px-3 text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">
              Todo esto prepara algo y te lo entrega. Lo abres tú, y a partir de ahí vive en la otra app:
              SinRutina no se entera de lo que pase después.
            </p>
          </div>

          <div className="mt-4 border-t border-[var(--sr-divider)] pt-4">
            <p className="px-3 text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--sr-secondary-ink)]">
              Insistencia
            </p>
            <div className="mt-2 flex flex-col gap-1">
              {WEB_INSISTENCE.map((level) => (
                <button
                  key={level}
                  type="button"
                  onClick={() => setInsistence(task.id, level)}
                  aria-pressed={task.insistence === level}
                  className="sr-pressable flex items-center gap-3 rounded-[var(--sr-row-radius)] px-3 py-2.5 text-left hover:bg-[var(--sr-primary-soft)]"
                >
                  <Bell
                    className="h-4 w-4 shrink-0"
                    style={{
                      color: task.insistence === level ? "var(--sr-primary)" : "var(--sr-secondary-ink)",
                    }}
                  />
                  <span className="min-w-0 flex-1">
                    <span className="block text-[15px] font-medium text-[var(--sr-ink)]">{level}</span>
                    <span className="block text-[13px] text-[var(--sr-secondary-ink)]">
                      {INSISTENCE_EXPLANATION[level]}
                    </span>
                  </span>
                </button>
              ))}
            </div>
            <p className="mt-2 px-3 text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">
              «No me dejes olvidarlo» solo existe en el iPhone: un navegador no puede sonar con el móvil en
              silencio, así que no aparece aquí. Para eso está «Llevarlo a mi calendario».
            </p>
          </div>

          <div className="mt-4 border-t border-[var(--sr-divider)] pt-2">
            <SRSheetRow
              icon={<Trash2 />}
              title="Borrarla"
              detail="No se puede deshacer"
              tone="quiet"
              onClick={() => {
                deleteTask(task.id);
                close();
              }}
            />
          </div>
        </div>
      )}
    </SRSheet>
  );
}

/** `datetime-local` wants local wall-clock time, never an ISO UTC string. */
function localInputValue(date: Date): string {
  const pad = (value: number): string => value.toString().padStart(2, "0");
  return (
    `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(date.getDate())}` +
    `T${pad(date.getHours())}:${pad(date.getMinutes())}`
  );
}
