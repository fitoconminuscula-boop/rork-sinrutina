/**
 * The voice reader.
 *
 * Saying a thing out loud is the shortest path between remembering it and having
 * it written down — shorter than opening a keyboard, which is where a lot of
 * captures die. A browser can do this in two different ways, and they are not
 * equivalent, so SinRutina says which one it is using instead of calling both
 * "dictado" and hoping nobody asks.
 *
 * - `navegador`: the browser's own speech recognition. Instant, with words
 *   appearing as you speak. Chrome and Safari send the audio to their own speech
 *   service to do it; that is their behaviour, not SinRutina's, and Ajustes says
 *   so rather than implying the voice never leaves the device.
 * - `transcripcion`: no recognition in this browser, so the phrase is recorded
 *   and transcribed through the extended reader. Only available when that reader
 *   is switched on, because the audio leaves the browser for it.
 * - `ninguno`: neither is possible. The microphone button is not shown at all.
 */

import { transcribe } from "./gateway";

export type DictationMode = "navegador" | "transcripcion" | "ninguno";

export const DICTATION_EXPLANATION: Record<DictationMode, string> = {
  navegador:
    "Tu navegador transcribe la voz con su propio servicio. SinRutina no graba nada ni guarda el audio.",
  transcripcion:
    "Este navegador no sabe dictar, así que grabo la frase y la transcribo con la lectura ampliada. El audio se envía solo para eso y no se guarda.",
  ninguno:
    "Este navegador no puede dictar: no tiene reconocimiento de voz y no me deja usar el micrófono.",
};

// MARK: - Browser speech recognition

interface RecognitionAlternative {
  readonly transcript: string;
}

interface RecognitionResult {
  readonly isFinal: boolean;
  readonly length: number;
  [index: number]: RecognitionAlternative;
}

interface RecognitionResultList {
  readonly length: number;
  [index: number]: RecognitionResult;
}

interface RecognitionEvent {
  readonly resultIndex: number;
  readonly results: RecognitionResultList;
}

interface RecognitionErrorEvent {
  readonly error: string;
}

export interface SpeechRecognizer {
  lang: string;
  continuous: boolean;
  interimResults: boolean;
  maxAlternatives: number;
  start: () => void;
  stop: () => void;
  abort: () => void;
  onresult: ((event: RecognitionEvent) => void) | null;
  onerror: ((event: RecognitionErrorEvent) => void) | null;
  onend: (() => void) | null;
}

type RecognizerConstructor = new () => SpeechRecognizer;

interface SpeechWindow {
  SpeechRecognition?: RecognizerConstructor;
  webkitSpeechRecognition?: RecognizerConstructor;
}

function recognizerConstructor(): RecognizerConstructor | null {
  if (typeof window === "undefined") return null;
  const candidate = window as unknown as SpeechWindow;
  return candidate.SpeechRecognition ?? candidate.webkitSpeechRecognition ?? null;
}

/** A recognizer set up for Spanish, or null when this browser has none. */
export function createRecognizer(): SpeechRecognizer | null {
  const Recognizer = recognizerConstructor();
  if (!Recognizer) return null;

  const recognizer = new Recognizer();
  recognizer.lang = "es-ES";
  recognizer.continuous = true;
  recognizer.interimResults = true;
  recognizer.maxAlternatives = 1;
  return recognizer;
}

/** Reads one event into the text so far. Interim words are kept apart. */
export function transcriptOf(event: RecognitionEvent): { finalText: string; interimText: string } {
  let finalText = "";
  let interimText = "";

  for (let index = event.resultIndex; index < event.results.length; index += 1) {
    const result = event.results[index];
    if (!result) continue;
    const alternative = result[0];
    if (!alternative) continue;
    if (result.isFinal) finalText += alternative.transcript;
    else interimText += alternative.transcript;
  }

  return { finalText, interimText };
}

/** What went wrong, in words a person can act on. */
export function recognitionMessage(error: string): string | null {
  switch (error) {
    case "no-speech":
      return "No te he oído. Prueba otra vez.";
    case "not-allowed":
    case "service-not-allowed":
      return "El navegador no me deja usar el micrófono. Puedes darle permiso desde la barra de direcciones.";
    case "audio-capture":
      return "No encuentro ningún micrófono.";
    case "network":
      return "El dictado del navegador se ha quedado sin conexión.";
    case "aborted":
      return null;
    default:
      return "El dictado se ha cortado. Puedes escribirlo a mano.";
  }
}

// MARK: - Recording, for browsers with no recognition

function canRecord(): boolean {
  return (
    typeof window !== "undefined" &&
    typeof window.MediaRecorder !== "undefined" &&
    typeof navigator !== "undefined" &&
    navigator.mediaDevices !== undefined &&
    typeof navigator.mediaDevices.getUserMedia === "function"
  );
}

/**
 * Which of the two paths this browser can actually take, given whether the
 * extended reader is allowed. Recomputed rather than cached: a person can turn
 * the extended reader off between one capture and the next.
 */
export function dictationMode(isExtendedReaderEnabled: boolean): DictationMode {
  if (recognizerConstructor() !== null) return "navegador";
  if (isExtendedReaderEnabled && canRecord()) return "transcripcion";
  return "ninguno";
}

/** True when a microphone path exists at all, ignoring the reader switch. */
export function hasAnyDictation(): boolean {
  return recognizerConstructor() !== null || canRecord();
}

const RECORDING_TYPES = ["audio/webm;codecs=opus", "audio/webm", "audio/mp4", "audio/ogg"];

function bestRecordingType(): string | undefined {
  if (typeof MediaRecorder === "undefined") return undefined;
  return RECORDING_TYPES.find((type) => MediaRecorder.isTypeSupported(type));
}

export interface Recording {
  /** Ends the recording and resolves with what was said, already transcribed. */
  stop: () => Promise<string>;
  /** Throws the recording away without transcribing it. */
  cancel: () => void;
}

/**
 * Records from the microphone and transcribes on stop. The track is released the
 * moment recording ends, so the browser's recording indicator never outlives the
 * capture.
 */
export async function startRecording(): Promise<Recording> {
  const stream = await navigator.mediaDevices.getUserMedia({ audio: true });
  const mimeType = bestRecordingType();
  const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined);
  const chunks: BlobPart[] = [];
  let isCancelled = false;

  recorder.ondataavailable = (event: BlobEvent) => {
    if (event.data.size > 0) chunks.push(event.data);
  };

  const release = (): void => {
    stream.getTracks().forEach((track) => track.stop());
  };

  const finished = new Promise<Blob>((resolve) => {
    recorder.onstop = () => {
      release();
      resolve(new Blob(chunks, { type: recorder.mimeType || mimeType || "audio/webm" }));
    };
  });

  recorder.start();

  return {
    stop: async () => {
      if (recorder.state !== "inactive") recorder.stop();
      const blob = await finished;
      if (isCancelled || blob.size === 0) return "";
      return transcribe(blob);
    },
    cancel: () => {
      isCancelled = true;
      if (recorder.state !== "inactive") recorder.stop();
      else release();
    },
  };
}
