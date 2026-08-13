import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";

import {
  fileNameAsSentence,
  readCapture,
  readDocument,
  readFollowUp,
  readImage,
  readMicroActions,
  readSplit,
  type DraftResult,
  type ReadResult,
  type StepsResult,
} from "./ai";
import type { AttachmentRead } from "./attachments";
import {
  currentReader,
  GatewayError,
  probeReader,
  RORK_ENGINE_NAME,
  type ReaderEngine,
  type ReaderStatus,
} from "./gateway";
import {
  followUpDraft as localFollowUpDraft,
  microActions as localMicroActions,
  normalized,
  splitIfTooBig,
  suggestion as localSuggestion,
} from "./heuristics";
import { readJSON, StorageKey, writeJSON } from "./storage";

/**
 * The reading layer, and the switch that governs it.
 *
 * On the iPhone this work happens on the device with Apple Intelligence. A
 * browser has no on-device model, so SinRutina can borrow one — but that means a
 * sentence leaves the browser, and the person decides whether that trade is
 * worth it. Every result carries where it came from, and the interface always
 * says so.
 */
interface IntelligenceValue {
  /** True when the person allows the extended reader to be used. */
  isEnabled: boolean;
  setEnabled: (enabled: boolean) => void;
  /** Which engine reads text first, so Ajustes can name it instead of saying "IA". */
  engineName: string;
  /** Which engine reads pictures. Not always the same one, so it is named apart. */
  imageEngineName: string;
  /** Which engine reads text first: `rork` is the metered route, the rest are free. */
  engine: ReaderEngine;
  /** True when the reader can fall back to a second engine before giving up. */
  hasBackupEngine: boolean;
  /**
   * True when the key is still stored under a browser-visible name. Ajustes says
   * so rather than letting a half-finished move look finished.
   */
  keyIsPublic: boolean;
  /** True while a request is in flight, for the one place that shows it. */
  isThinking: boolean;
  /** Last failure, in plain Spanish. Cleared as soon as anything succeeds. */
  lastFailure: string | null;
  read: (rawText: string) => Promise<ReadResult>;
  /** Reads an opened attachment: its text, or what is written inside its image. */
  readFile: (attachment: AttachmentRead) => Promise<ReadResult>;
  /**
   * True when a picture could actually be read right now. A browser has no OCR,
   * so this needs the extended reader and a connection — and when it is false,
   * the interface says why instead of returning an empty task.
   */
  canReadImages: boolean;
  microActions: (title: string) => Promise<StepsResult>;
  split: (title: string) => Promise<StepsResult>;
  followUp: (title: string, person: string | null, days: number) => Promise<DraftResult>;
}

const IntelligenceContext = createContext<IntelligenceValue | null>(null);

/** Offline is a normal state, not an error: the local reader covers it silently. */
function isOffline(): boolean {
  return typeof navigator !== "undefined" && navigator.onLine === false;
}

export function IntelligenceProvider({ children }: { children: ReactNode }) {
  const [isEnabled, setIsEnabled] = useState<boolean>(() => readJSON<boolean>(StorageKey.extendedReader, true));
  const [pending, setPending] = useState(0);
  const [lastFailure, setLastFailure] = useState<string | null>(null);
  const [isOnline, setIsOnline] = useState<boolean>(() => !isOffline());
  const [reader, setReader] = useState<ReaderStatus>(() => currentReader());
  const inFlight = useRef<AbortController | null>(null);

  /**
   * Which engine actually answers is a fact held by the Worker, not something
   * the browser can assume. Ask once, and again whenever the reader is switched
   * back on or the connection returns — until then Ajustes names the Rork route,
   * which is the one that would really answer.
   */
  useEffect(() => {
    if (!isEnabled || !isOnline) return;
    let isCurrent = true;
    void probeReader().then((status) => {
      if (isCurrent) setReader(status);
    });
    return () => {
      isCurrent = false;
    };
  }, [isEnabled, isOnline]);

  useEffect(() => {
    const update = (): void => setIsOnline(!isOffline());
    window.addEventListener("online", update);
    window.addEventListener("offline", update);
    return () => {
      window.removeEventListener("online", update);
      window.removeEventListener("offline", update);
    };
  }, []);

  const setEnabled = useCallback((enabled: boolean) => {
    setIsEnabled(enabled);
    writeJSON(StorageKey.extendedReader, enabled);
    if (!enabled) {
      inFlight.current?.abort();
      inFlight.current = null;
      setLastFailure(null);
    }
  }, []);

  /**
   * Runs one remote reading. Any failure is turned into the local result, so a
   * caller never has to handle an error to keep working.
   */
  const run = useCallback(
    async <T,>(remote: (signal: AbortSignal) => Promise<T>, local: () => T, isLatestOnly: boolean): Promise<T> => {
      if (!isEnabled || isOffline()) return local();

      if (isLatestOnly) {
        inFlight.current?.abort();
        inFlight.current = new AbortController();
      }
      const controller = isLatestOnly ? inFlight.current : new AbortController();
      if (!controller) return local();

      setPending((count) => count + 1);
      try {
        const result = await remote(controller.signal);
        setLastFailure(null);
        return result;
      } catch (error) {
        if (controller.signal.aborted) throw error;
        // Never log what the person wrote: only the shape of the failure.
        const message =
          error instanceof GatewayError
            ? error.userMessage
            : "No he podido conectar. He leído tu texto aquí mismo.";
        console.warn(`SinRutina: la lectura ampliada falló (${error instanceof GatewayError ? error.status : "red"}).`);
        setLastFailure(message);
        return local();
      } finally {
        setPending((count) => Math.max(0, count - 1));
      }
    },
    [isEnabled]
  );

  const read = useCallback(
    (rawText: string): Promise<ReadResult> =>
      run(
        (signal) => readCapture(rawText, signal),
        () => ({ suggestion: localSuggestion(rawText), source: "local" as const }),
        true
      ),
    [run]
  );

  /**
   * A file becomes a task through the same door as a typed sentence. Text is
   * read as a document; an image is read as an image; and if neither can be
   * done, the file's own name is used, which is honest about knowing nothing
   * more than the name.
   */
  const readFile = useCallback(
    (attachment: AttachmentRead): Promise<ReadResult> => {
      const named = (): ReadResult => ({
        suggestion: localSuggestion(fileNameAsSentence(attachment.fileName)),
        source: "local" as const,
      });

      if (attachment.text.trim().length > 0) {
        return run(
          (signal) => readDocument(attachment.text, attachment.fileName, signal),
          () => ({ suggestion: localSuggestion(attachment.text.slice(0, 220)), source: "local" as const }),
          false
        );
      }

      const image = attachment.image;
      if (image) {
        return run((signal) => readImage(image.dataUrl, attachment.fileName, signal), named, false);
      }

      return Promise.resolve(named());
    },
    [run]
  );

  const microActions = useCallback(
    (title: string): Promise<StepsResult> =>
      run(
        (signal) => readMicroActions(title, signal),
        () => ({ steps: localMicroActions(title), source: "local" as const }),
        false
      ),
    [run]
  );

  const split = useCallback(
    (title: string): Promise<StepsResult> =>
      run(
        (signal) => readSplit(title, signal),
        () => ({ steps: splitIfTooBig(normalized(title), 90), source: "local" as const }),
        false
      ),
    [run]
  );

  const followUp = useCallback(
    (title: string, person: string | null, days: number): Promise<DraftResult> =>
      run(
        (signal) => readFollowUp(title, person, days, signal),
        () => ({ text: localFollowUpDraft(title, person, days), source: "local" as const }),
        false
      ),
    [run]
  );

  const value = useMemo<IntelligenceValue>(
    () => ({
      isEnabled,
      setEnabled,
      engineName: reader.name,
      imageEngineName: reader.pictureName,
      engine: reader.engine,
      hasBackupEngine: reader.hasBackup,
      keyIsPublic: reader.keyIsPublic,
      isThinking: pending > 0,
      lastFailure,
      read,
      readFile,
      canReadImages: isEnabled && isOnline,
      microActions,
      split,
      followUp,
    }),
    [isEnabled, setEnabled, reader, pending, lastFailure, read, readFile, isOnline, microActions, split, followUp]
  );

  return <IntelligenceContext.Provider value={value}>{children}</IntelligenceContext.Provider>;
}

export function useIntelligence(): IntelligenceValue {
  const value = useContext(IntelligenceContext);
  if (!value) throw new Error("useIntelligence debe usarse dentro de IntelligenceProvider");
  return value;
}
