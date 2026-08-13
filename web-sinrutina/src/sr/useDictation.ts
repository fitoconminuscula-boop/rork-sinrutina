import { useCallback, useEffect, useRef, useState } from "react";

import { GatewayError } from "./gateway";
import {
  createRecognizer,
  dictationMode,
  recognitionMessage,
  startRecording,
  transcriptOf,
  type DictationMode,
  type Recording,
  type SpeechRecognizer,
} from "./voice";

/**
 * One microphone button, two very different machines behind it.
 *
 * The hook hides which one is running from the caller, but never from the
 * person: `mode` is shown in the interface, and `error` says out loud when the
 * microphone was refused or the transcription failed. It never silently returns
 * an empty string and lets someone believe they were heard.
 */
export interface Dictation {
  mode: DictationMode;
  isAvailable: boolean;
  /** True while the microphone is open. */
  isListening: boolean;
  /** True while a recording is being turned into words. */
  isTranscribing: boolean;
  /** Words as they are being said. Only the browser recognizer produces these. */
  interim: string;
  error: string | null;
  toggle: () => void;
  cancel: () => void;
}

export function useDictation(options: {
  isExtendedReaderEnabled: boolean;
  onText: (text: string) => void;
}): Dictation {
  const { isExtendedReaderEnabled, onText } = options;

  const [isListening, setIsListening] = useState(false);
  const [isTranscribing, setIsTranscribing] = useState(false);
  const [interim, setInterim] = useState("");
  const [error, setError] = useState<string | null>(null);

  const recognizer = useRef<SpeechRecognizer | null>(null);
  const recording = useRef<Recording | null>(null);
  const emit = useRef(onText);
  emit.current = onText;

  const mode = dictationMode(isExtendedReaderEnabled);

  const finish = useCallback(() => {
    setIsListening(false);
    setInterim("");
  }, []);

  const startBrowser = useCallback(() => {
    const instance = createRecognizer();
    if (!instance) {
      setError("Este navegador no puede dictar.");
      return;
    }

    instance.onresult = (event) => {
      const { finalText, interimText } = transcriptOf(event);
      setInterim(interimText);
      if (finalText.trim().length > 0) emit.current(finalText.trim());
    };

    instance.onerror = (event) => {
      const message = recognitionMessage(event.error);
      if (message) setError(message);
      finish();
    };

    instance.onend = () => {
      recognizer.current = null;
      finish();
    };

    try {
      instance.start();
      recognizer.current = instance;
      setError(null);
      setIsListening(true);
    } catch {
      setError("El dictado ya estaba abierto. Inténtalo otra vez.");
      finish();
    }
  }, [finish]);

  const startTranscription = useCallback(async () => {
    try {
      recording.current = await startRecording();
      setError(null);
      setIsListening(true);
    } catch {
      setError("No me has dado permiso para usar el micrófono, o no hay ninguno.");
      finish();
    }
  }, [finish]);

  const stopTranscription = useCallback(async () => {
    const current = recording.current;
    recording.current = null;
    setIsListening(false);
    if (!current) return;

    setIsTranscribing(true);
    try {
      const text = await current.stop();
      if (text.trim().length > 0) emit.current(text.trim());
      else setError("No he entendido nada en esa grabación.");
    } catch (caught) {
      const message =
        caught instanceof GatewayError
          ? caught.userMessage
          : "No he podido transcribir el audio. Puedes escribirlo a mano.";
      console.warn(`SinRutina: el dictado falló (${caught instanceof GatewayError ? caught.status : "red"}).`);
      setError(message);
    } finally {
      setIsTranscribing(false);
    }
  }, []);

  const toggle = useCallback(() => {
    if (mode === "ninguno") return;

    if (isListening) {
      if (mode === "navegador") recognizer.current?.stop();
      else void stopTranscription();
      return;
    }

    if (mode === "navegador") startBrowser();
    else void startTranscription();
  }, [mode, isListening, startBrowser, startTranscription, stopTranscription]);

  /** Leaves the microphone closed and throws away whatever was captured. */
  const cancel = useCallback(() => {
    recognizer.current?.abort();
    recognizer.current = null;
    recording.current?.cancel();
    recording.current = null;
    finish();
  }, [finish]);

  // A microphone must never outlive the screen that opened it.
  useEffect(() => cancel, [cancel]);

  return {
    mode,
    isAvailable: mode !== "ninguno",
    isListening,
    isTranscribing,
    interim,
    error,
    toggle,
    cancel,
  };
}
