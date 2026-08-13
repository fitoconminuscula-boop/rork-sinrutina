import { FileText, Loader2, Mic, Paperclip, Square, X } from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type ClipboardEvent, type DragEvent } from "react";

import { SRPrimaryButton, SRSheet } from "./Primitives";
import { fileNameAsSentence } from "@/sr/ai";
import { useHaptics } from "@/sr/AppearanceProvider";
import { AttachmentError, readAttachment, type AttachmentRead } from "@/sr/attachments";
import { formatHour } from "@/sr/engine";
import type { ReaderSource } from "@/sr/gateway";
import { suggestion, type CaptureSuggestion } from "@/sr/heuristics";
import { useIntelligence } from "@/sr/IntelligenceProvider";
import { useTasks } from "@/sr/TasksProvider";
import { CAPTURE_SOURCE } from "@/sr/types";
import { useDictation } from "@/sr/useDictation";
import { DICTATION_EXPLANATION } from "@/sr/voice";
import { cn } from "@/lib/utils";

const ACCEPTED =
  ".txt,.md,.markdown,.csv,.tsv,.json,.log,.eml,.vtt,.srt,.rtf,.ics,.pdf,image/*,text/plain,text/calendar,application/pdf";

/**
 * One field, three ways in: typing, speaking, or handing over a file.
 *
 * Whichever way it arrives, the sentence goes through the same reader and the
 * same visible confirmation before anything is saved — including *who* read it.
 * A reader that guesses in silence is a reader you cannot trust.
 */
export function CaptureSheet({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  const { captureRead } = useTasks();
  const { isEnabled, read, readFile, canReadImages, isThinking } = useIntelligence();
  const haptics = useHaptics();

  const [text, setText] = useState("");
  const [extended, setExtended] = useState<{ forText: string; read: CaptureSuggestion; source: ReaderSource } | null>(
    null
  );
  const [attachment, setAttachment] = useState<AttachmentRead | null>(null);
  const [fileNote, setFileNote] = useState<string | null>(null);
  const [isReadingFile, setIsReadingFile] = useState(false);
  const [isDropping, setIsDropping] = useState(false);

  const inputRef = useRef<HTMLTextAreaElement>(null);
  const fileRef = useRef<HTMLInputElement>(null);

  const appendSpoken = useCallback((spoken: string) => {
    setText((current) => (current.trim().length === 0 ? spoken : `${current.trim()} ${spoken}`));
  }, []);

  const dictation = useDictation({ isExtendedReaderEnabled: isEnabled, onText: appendSpoken });

  useEffect(() => {
    if (!isOpen) return;
    setText("");
    setExtended(null);
    setAttachment(null);
    setFileNote(null);
    const timer = window.setTimeout(() => inputRef.current?.focus(), 120);
    return () => window.clearTimeout(timer);
  }, [isOpen]);

  const trimmed = text.trim();

  // The local reading is immediate and always on screen; it is never replaced by
  // a spinner while the extended one is on its way.
  const local = useMemo<CaptureSuggestion | null>(
    () => (trimmed.length > 2 ? suggestion(trimmed) : null),
    [trimmed]
  );

  // Asking on every keystroke would be noise. This waits until typing stops, and
  // never re-asks for a sentence that has already been read.
  useEffect(() => {
    if (!isOpen || !isEnabled || trimmed.length < 8) return;
    if (extended?.forText === trimmed) return;
    const timer = window.setTimeout(() => {
      void read(trimmed)
        .then((result) => setExtended({ forText: trimmed, read: result.suggestion, source: result.source }))
        .catch(() => {
          // An aborted read is the normal case while typing: keep the local one.
        });
    }, 650);
    return () => window.clearTimeout(timer);
  }, [isOpen, isEnabled, trimmed, read, extended]);

  /**
   * Opens a file, reads what can be read out of it, and puts the result in the
   * field as an ordinary sentence — editable, like everything else here.
   */
  const attach = useCallback(
    async (file: File) => {
      dictation.cancel();
      setIsReadingFile(true);
      setFileNote(null);

      try {
        const opened = await readAttachment(file);
        setAttachment(opened);

        const needsVision = opened.text.trim().length === 0 && opened.image !== null;
        if (needsVision && !canReadImages) {
          setText(fileNameAsSentence(opened.fileName));
          setExtended(null);
          setFileNote(
            isEnabled
              ? `${opened.note} Y ahora mismo no tengo conexión para leerla fuera. Escríbelo tú: el archivo queda anotado en la tarea.`
              : `${opened.note} Para leerla hace falta la lectura ampliada, y la tienes apagada en Ajustes. Escríbelo tú: el archivo queda anotado en la tarea.`
          );
          return;
        }

        setFileNote(opened.note);
        const result = await readFile(opened);
        setText(result.suggestion.title);
        setExtended({ forText: result.suggestion.title, read: result.suggestion, source: result.source });
        haptics.light();
      } catch (error) {
        setAttachment(null);
        setFileNote(
          error instanceof AttachmentError ? error.userMessage : "No he podido abrir ese archivo."
        );
      } finally {
        setIsReadingFile(false);
      }
    },
    [canReadImages, dictation, haptics, isEnabled, readFile]
  );

  const onDrop = (event: DragEvent<HTMLDivElement>): void => {
    event.preventDefault();
    setIsDropping(false);
    const file = event.dataTransfer.files[0];
    if (file) void attach(file);
  };

  const onPaste = (event: ClipboardEvent<HTMLTextAreaElement>): void => {
    const file = event.clipboardData.files[0];
    if (!file) return;
    event.preventDefault();
    void attach(file);
  };

  const isFresh = extended !== null && extended.forText === trimmed;
  const shown = isFresh ? extended.read : local;
  const source: ReaderSource = isFresh ? extended.source : "local";
  const isWaitingForExtended = isEnabled && isThinking && !isFresh && trimmed.length >= 8;

  const save = (): void => {
    if (trimmed.length === 0) return;
    dictation.cancel();
    const chosen = shown ?? suggestion(trimmed);
    captureRead(
      chosen,
      source === "extended" ? CAPTURE_SOURCE.extended : CAPTURE_SOURCE.local,
      attachment ? `Desde ${attachment.fileName}` : undefined
    );
    setText("");
    setExtended(null);
    setAttachment(null);
    setFileNote(null);
    onClose();
  };

  const close = (): void => {
    dictation.cancel();
    onClose();
  };

  return (
    <SRSheet isOpen={isOpen} onClose={close} title="Capturar">
      <div
        className="flex flex-col gap-4 pb-2"
        onDragOver={(event) => {
          event.preventDefault();
          setIsDropping(true);
        }}
        onDragLeave={() => setIsDropping(false)}
        onDrop={onDrop}
      >
        <div className="relative">
          <textarea
            ref={inputRef}
            value={text}
            onChange={(event) => setText(event.target.value)}
            onPaste={onPaste}
            onKeyDown={(event) => {
              if (event.key === "Enter" && (event.metaKey || event.ctrlKey)) save();
            }}
            rows={3}
            placeholder="Llamar al dentista mañana por la tarde"
            aria-label="Qué tienes pendiente"
            className={cn(
              "w-full resize-none rounded-[var(--sr-row-radius)] border bg-[var(--sr-surface)] px-4 py-3 text-[16px] text-[var(--sr-ink)] outline-none placeholder:text-[var(--sr-secondary-ink)]/70 focus:border-[var(--sr-primary)]",
              isDropping ? "border-[var(--sr-primary)]" : "border-[var(--sr-divider)]"
            )}
          />
          {dictation.interim.length > 0 ? (
            <p className="mt-1.5 px-1 text-[14px] italic text-[var(--sr-secondary-ink)]">{dictation.interim}</p>
          ) : null}
        </div>

        <div className="flex flex-wrap items-center gap-2">
          {dictation.isAvailable ? (
            <button
              type="button"
              onClick={() => {
                haptics.light();
                dictation.toggle();
              }}
              disabled={dictation.isTranscribing || isReadingFile}
              aria-pressed={dictation.isListening}
              className={cn(
                "sr-pressable inline-flex items-center gap-2 rounded-full px-3.5 py-2 text-[13px] font-medium disabled:opacity-50",
                dictation.isListening
                  ? "bg-[var(--sr-primary)] text-[var(--sr-on-primary)]"
                  : "bg-[var(--sr-primary-soft)] text-[var(--sr-primary)]"
              )}
            >
              {dictation.isTranscribing ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : dictation.isListening ? (
                <Square className="h-4 w-4 fill-current" />
              ) : (
                <Mic className="h-4 w-4" />
              )}
              {dictation.isTranscribing
                ? "Transcribiendo…"
                : dictation.isListening
                  ? "Escuchando. Toca para parar"
                  : "Dictar"}
            </button>
          ) : null}

          <button
            type="button"
            onClick={() => {
              haptics.light();
              fileRef.current?.click();
            }}
            disabled={isReadingFile || dictation.isListening}
            className="sr-pressable inline-flex items-center gap-2 rounded-full bg-[var(--sr-primary-soft)] px-3.5 py-2 text-[13px] font-medium text-[var(--sr-primary)] disabled:opacity-50"
          >
            {isReadingFile ? <Loader2 className="h-4 w-4 animate-spin" /> : <Paperclip className="h-4 w-4" />}
            {isReadingFile ? "Leyendo el archivo…" : "Adjuntar"}
          </button>

          <input
            ref={fileRef}
            type="file"
            accept={ACCEPTED}
            className="hidden"
            onChange={(event) => {
              const file = event.target.files?.[0];
              event.target.value = "";
              if (file) void attach(file);
            }}
          />
        </div>

        {dictation.isListening || dictation.error ? (
          <p className="text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]" role="status">
            {dictation.error ?? DICTATION_EXPLANATION[dictation.mode]}
          </p>
        ) : null}

        {attachment ? (
          <AttachmentChip
            attachment={attachment}
            onRemove={() => {
              setAttachment(null);
              setFileNote(null);
            }}
          />
        ) : null}

        {fileNote ? (
          <p className="text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">{fileNote}</p>
        ) : null}

        {shown ? (
          <div className="rounded-[var(--sr-row-radius)] bg-[var(--sr-primary-soft)] px-4 py-3">
            <div className="flex items-baseline justify-between gap-3">
              <p className="text-[13px] font-semibold text-[var(--sr-primary)]">Lo he entendido así</p>
              <p className="shrink-0 text-[12px] text-[var(--sr-secondary-ink)]">
                {isWaitingForExtended ? "Releyendo…" : source === "extended" ? "Lectura ampliada" : "Lectura local"}
              </p>
            </div>
            <p className="mt-1.5 text-[15px] font-medium text-[var(--sr-ink)]">{shown.title}</p>
            <ul className="mt-2 flex flex-wrap gap-x-4 gap-y-1 text-[13px] text-[var(--sr-secondary-ink)]">
              <li>{shown.suggestedState}</li>
              <li>{shown.estimatedMinutes} min</li>
              {shown.waitingFor ? <li>Esperas a {shown.waitingFor}</li> : null}
              {shown.dueDate ? <li>Vence {formatDay(shown.dueDate)}</li> : null}
              {shown.availableFrom ? <li>Desde {formatDay(shown.availableFrom)}</li> : null}
            </ul>
            <p className="mt-2 text-[13px] text-[var(--sr-secondary-ink)]">
              Primer paso: <span className="text-[var(--sr-ink)]">{shown.nextStep}</span>
            </p>
          </div>
        ) : (
          <p className="text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">
            {isEnabled
              ? "Escríbelo, dilo o suelta aquí un archivo. Lo leo aquí y, si hace falta, pido una lectura más fina."
              : "Escríbelo, dilo o suelta aquí un archivo. Lo leo aquí mismo, sin enviarlo a ningún sitio."}
          </p>
        )}

        <SRPrimaryButton onClick={save} disabled={trimmed.length === 0 || isReadingFile}>
          Guardar
        </SRPrimaryButton>
      </div>
    </SRSheet>
  );
}

/**
 * What was attached, and the one thing people always assume wrongly: the file
 * itself is not kept. SinRutina saves what it read and the file's name.
 */
function AttachmentChip({ attachment, onRemove }: { attachment: AttachmentRead; onRemove: () => void }) {
  const detail = [
    attachment.kind,
    attachment.pages ? `${attachment.pages} ${attachment.pages === 1 ? "página" : "páginas"}` : null,
  ]
    .filter((part): part is string => part !== null)
    .join(" · ");

  return (
    <div className="flex items-center gap-3 rounded-[var(--sr-row-radius)] border border-[var(--sr-divider)] px-3 py-2.5">
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-[var(--sr-primary-soft)] text-[var(--sr-primary)]">
        <FileText className="h-[17px] w-[17px]" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[14px] font-medium text-[var(--sr-ink)]">{attachment.fileName}</span>
        <span className="block text-[12px] text-[var(--sr-secondary-ink)]">
          {detail} · guardo lo leído y el nombre, no el archivo
        </span>
      </span>
      <button
        type="button"
        onClick={onRemove}
        aria-label="Quitar el archivo"
        className="sr-pressable grid h-7 w-7 shrink-0 place-items-center rounded-full bg-[var(--sr-divider)] text-[var(--sr-secondary-ink)]"
      >
        <X className="h-3.5 w-3.5" />
      </button>
    </div>
  );
}

function formatDay(iso: string): string {
  const date = new Date(iso);
  const today = new Date();
  const isToday = date.toDateString() === today.toDateString();
  const tomorrow = new Date(today.getTime() + 86_400_000);
  const isTomorrow = date.toDateString() === tomorrow.toDateString();

  if (isToday) return `hoy ${formatHour(date)}`;
  if (isTomorrow) return `mañana ${formatHour(date)}`;
  return date.toLocaleDateString("es-ES", { weekday: "short", day: "numeric", month: "short" });
}
