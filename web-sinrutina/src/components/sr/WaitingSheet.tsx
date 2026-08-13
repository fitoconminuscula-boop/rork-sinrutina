import { Copy, Hourglass, MessageCircle, PenLine, RotateCcw, Send } from "lucide-react";
import { useMemo, useState } from "react";

import { SRSheet, SRSheetRow } from "./Primitives";
import type { ReaderSource } from "@/sr/gateway";
import { addressIn, followUpMail, mailtoLink, smsLink, whatsappLink } from "@/sr/handoff";
import { useIntelligence } from "@/sr/IntelligenceProvider";
import { useTasks } from "@/sr/TasksProvider";
import { waitingDays, type Task } from "@/sr/types";

interface DraftState {
  taskId: string;
  text: string;
  source: ReaderSource;
  isWriting: boolean;
}

/**
 * Esperando is not a tab. It opens from one contextual line inside Ahora, and
 * only when something is actually parked there.
 *
 * For each item SinRutina can write the follow-up message. The draft is shown on
 * screen first, and only leaves if you ask — to the clipboard, or into your own
 * mail, WhatsApp or messages app with the text already written. It always stops
 * at their compose window: SinRutina has no way to send anything, and does not.
 */
export function WaitingSheet({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  const { tasks, moveTask } = useTasks();
  const { followUp } = useIntelligence();

  const [draft, setDraft] = useState<DraftState | null>(null);
  const [copiedId, setCopiedId] = useState<string | null>(null);
  const [copyFailedId, setCopyFailedId] = useState<string | null>(null);

  const waiting = useMemo(() => tasks.filter((task) => task.state === "Esperando"), [tasks]);

  const writeDraft = (task: Task): void => {
    setCopiedId(null);
    setCopyFailedId(null);
    setDraft({ taskId: task.id, text: "", source: "local", isWriting: true });

    void followUp(task.title, task.waitingFor, waitingDays(task)).then((result) => {
      setDraft({ taskId: task.id, text: result.text, source: result.source, isWriting: false });
    });
  };

  const copy = async (taskId: string, text: string): Promise<void> => {
    try {
      await navigator.clipboard.writeText(text);
      setCopyFailedId(null);
      setCopiedId(taskId);
      window.setTimeout(() => setCopiedId(null), 2400);
    } catch {
      // Clipboard access can be refused outright. Say so instead of claiming a
      // copy that never happened — the text is on screen either way.
      setCopiedId(null);
      setCopyFailedId(taskId);
      window.setTimeout(() => setCopyFailedId(null), 3600);
    }
  };

  return (
    <SRSheet isOpen={isOpen} onClose={onClose} title="Esperando">
      <div className="pb-2">
        {waiting.length === 0 ? (
          <p className="py-6 text-center text-[15px] text-[var(--sr-secondary-ink)]">
            No dependes de nadie ahora mismo.
          </p>
        ) : (
          <ul className="flex flex-col gap-4">
            {waiting.map((task) => {
              const days = waitingDays(task);
              const current = draft?.taskId === task.id ? draft : null;

              return (
                <li key={task.id} className="flex flex-col gap-1">
                  <div className="flex items-start gap-3 px-1">
                    <Hourglass className="mt-1 h-4 w-4 shrink-0 text-[var(--sr-lavender)]" />
                    <div className="min-w-0 flex-1">
                      <p className="text-[15px] font-medium text-[var(--sr-ink)]">{task.title}</p>
                      <p className="text-[13px] text-[var(--sr-secondary-ink)]">
                        {task.waitingFor ? `Esperas a ${task.waitingFor}` : "Esperas a otra persona"}
                        {days >= 1 ? ` · ${days} ${days === 1 ? "día" : "días"}` : ""}
                      </p>
                    </div>
                  </div>

                  {current ? (
                    <div className="mx-1 mt-1.5 rounded-[var(--sr-row-radius)] bg-[var(--sr-primary-soft)] px-3.5 py-3">
                      {current.isWriting ? (
                        <p className="text-[14px] text-[var(--sr-secondary-ink)]">Escribiendo un borrador…</p>
                      ) : (
                        <>
                          <p className="whitespace-pre-line text-[14px] leading-relaxed text-[var(--sr-ink)]">
                            {current.text}
                          </p>
                          <div className="mt-2.5 flex flex-wrap items-center gap-2">
                            <Outlet
                              icon={<Send className="h-3.5 w-3.5" />}
                              label={addressIn(task.waitingFor) ? "Correo" : "Abrir el correo"}
                              onClick={() => {
                                const mail = followUpMail(task, current.text);
                                window.location.href = mailtoLink(mail);
                              }}
                            />
                            <Outlet
                              icon={<MessageCircle className="h-3.5 w-3.5" />}
                              label="WhatsApp"
                              onClick={() => {
                                window.open(whatsappLink(current.text), "_blank", "noopener,noreferrer");
                              }}
                            />
                            <Outlet
                              icon={<MessageCircle className="h-3.5 w-3.5" />}
                              label="Mensaje"
                              onClick={() => {
                                window.location.href = smsLink(current.text);
                              }}
                            />
                            <Outlet
                              icon={<Copy className="h-3.5 w-3.5" />}
                              label={
                                copiedId === task.id
                                  ? "Copiado"
                                  : copyFailedId === task.id
                                    ? "No me deja copiar"
                                    : "Copiar"
                              }
                              onClick={() => void copy(task.id, current.text)}
                            />
                          </div>
                          <p className="mt-2 text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">
                            {copyFailedId === task.id
                              ? "Selecciónalo y cópialo tú. No se envía nada solo."
                              : current.source === "extended"
                                ? "Lectura ampliada. Se abre tu app con el texto escrito: enviar lo haces tú."
                                : "Escrito aquí mismo. Se abre tu app con el texto escrito: enviar lo haces tú."}
                          </p>
                          {addressIn(task.waitingFor) ? (
                            <p className="mt-1 text-[12px] text-[var(--sr-secondary-ink)]">
                              El correo irá dirigido a {addressIn(task.waitingFor)}, porque lo apuntaste al
                              guardarla.
                            </p>
                          ) : null}
                        </>
                      )}
                    </div>
                  ) : null}

                  <div className="flex flex-col">
                    <SRSheetRow
                      icon={<PenLine />}
                      title={current ? "Escribir otro mensaje" : "Escribir un mensaje para retomarlo"}
                      detail="Lo verás aquí antes de mandarlo a ningún sitio."
                      onClick={() => writeDraft(task)}
                    />
                    <SRSheetRow
                      icon={<RotateCcw />}
                      title="Ya me respondieron"
                      detail="Vuelve a Ahora"
                      tone="quiet"
                      onClick={() => moveTask(task.id, "Ahora")}
                    />
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </SRSheet>
  );
}

/** One way out for a draft. Small on purpose: the message is what matters. */
function Outlet({
  icon,
  label,
  onClick,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className="sr-pressable inline-flex items-center gap-1.5 rounded-full bg-[var(--sr-surface)] px-3 py-1.5 text-[13px] font-semibold text-[var(--sr-primary)]"
    >
      {icon}
      {label}
    </button>
  );
}
