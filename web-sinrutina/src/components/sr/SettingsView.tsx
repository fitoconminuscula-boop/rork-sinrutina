import {
  AlertTriangle,
  ArrowUpRight,
  Check,
  Download,
  KeyRound,
  Smartphone,
  Upload,
  WifiOff,
} from "lucide-react";
import { useRef, useState } from "react";

import { DemoBanner } from "./NowView";
import { SRCard, SRSectionLabel, SRSegmented } from "./Primitives";
import { ShortcutsSheet } from "./ShortcutsSheet";
import { DICTATION_EXPLANATION, dictationMode } from "@/sr/voice";
import { SRMark } from "./SRMark";
import { useAppearance, useHaptics } from "@/sr/AppearanceProvider";
import {
  ACCENT_LABELS,
  ALL_METADATA,
  BUTTON_SHAPES,
  CARD_STYLES,
  DENSITIES,
  HAPTIC_LABELS,
  METADATA_LABELS,
  MOTION_LABELS,
  NOW_LAYOUTS,
  PICKABLE_ACCENTS,
  PRESENCE_LABELS,
  THEME_LABELS,
  THEME_ORDER,
  VISUAL_SCALES,
  isOriginalProfile,
  type SRAccent,
  type SRMetadataField,
} from "@/sr/appearance";
import { ACCENT_BASE } from "@/sr/appearance";
import { toCSS } from "@/sr/color";
import { supportsVibration } from "@/sr/feedback";
import { backupFilename, buildBackup, downloadFile, readBackup } from "@/sr/handoff";
import { useIntelligence } from "@/sr/IntelligenceProvider";
import { themeSwatch } from "@/sr/theme";
import { useTasks } from "@/sr/TasksProvider";

/**
 * Ajustes carries the appearance profile and, just as importantly, the honest
 * account of what this version cannot do. Nothing here is a switch that pretends.
 */
export function SettingsView() {
  const { profile, palette, update, reset, effectiveMotion } = useAppearance();
  const { isDemoMode, setDemoMode, isPersistent, realTasks, tasks, restoreTasks, eraseEverything } = useTasks();
  const {
    isEnabled: readsExtended,
    setEnabled: setReadsExtended,
    engineName,
    imageEngineName,
    hasBackupEngine,
    keyIsPublic,
    lastFailure,
  } = useIntelligence();
  const haptics = useHaptics();
  const [confirmsErase, setConfirmsErase] = useState(false);
  const [showsShortcuts, setShowsShortcuts] = useState(false);
  const [restoreNote, setRestoreNote] = useState<string | null>(null);
  const restoreInput = useRef<HTMLInputElement>(null);
  const dictation = dictationMode(readsExtended);

  /**
   * Nothing here syncs, so a copy the person holds themselves is the only thing
   * standing between them and a cleared cache. The file is plain and readable.
   */
  const saveBackup = (): void => {
    haptics.light();
    const ok = downloadFile(buildBackup(realTasks), backupFilename(), "application/json");
    setRestoreNote(ok ? "Copia guardada en tus descargas." : "El navegador no me ha dejado darte el archivo.");
  };

  /** A restore only adds. Whatever is already here stays exactly as it is. */
  const loadBackup = async (file: File): Promise<void> => {
    const result = readBackup(await file.text(), tasks);

    if (result.problem !== null) {
      setRestoreNote(
        result.problem === "foreign"
          ? "Ese archivo no es una copia de SinRutina."
          : result.problem === "empty"
            ? "Esa copia no tiene ninguna tarea dentro."
            : "No he podido leer ese archivo."
      );
      return;
    }

    restoreTasks(result.tasks);
    haptics.success();
    setRestoreNote(
      result.added === 0
        ? "Ya tenías todo lo que había en esa copia. No he cambiado nada."
        : `He añadido ${result.added} ${result.added === 1 ? "tarea" : "tareas"}.${
            result.skipped > 0 ? ` Las otras ${result.skipped} ya estaban.` : ""
          }`
    );
  };

  const toggleMetadata = (field: SRMetadataField): void => {
    const has = profile.visibleMetadata.includes(field);
    update({
      visibleMetadata: has
        ? profile.visibleMetadata.filter((item) => item !== field)
        : [...profile.visibleMetadata, field],
    });
  };

  return (
    <div className="flex min-h-full flex-col px-[var(--sr-page-padding)] pb-40 pt-[max(20px,env(safe-area-inset-top))]">
      <div className="mx-auto w-full max-w-[560px]">
        {isDemoMode ? <DemoBanner /> : null}

        <h1 className="pb-6 text-[28px] font-semibold tracking-[-0.02em] text-[var(--sr-ink)]">Ajustes</h1>

        <div className="flex flex-col" style={{ gap: "var(--sr-section-gap)" }}>
          {/* Preview */}
          <SRCard className="flex items-center gap-4">
            <SRMark state="suggesting" size={44} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[16px] font-medium text-[var(--sr-ink)]">Enviar los antecedentes</p>
              <p className="text-[13px] text-[var(--sr-secondary-ink)]">7 min · Vence hoy</p>
            </div>
            <span
              className="grid h-9 shrink-0 place-items-center px-4 text-[13px] font-semibold"
              style={{
                backgroundColor: toCSS(palette.primary),
                color: toCSS(palette.onPrimary),
                borderRadius: "var(--sr-control-radius)",
              }}
            >
              Empezar
            </span>
          </SRCard>

          {/* Theme */}
          <section className="flex flex-col gap-3">
            <SRSectionLabel>Tema</SRSectionLabel>
            <div className="grid grid-cols-2 gap-2">
              {THEME_ORDER.map((theme) => {
                const isActive = profile.theme === theme;
                return (
                  <button
                    key={theme}
                    type="button"
                    onClick={() => {
                      haptics.light();
                      update({ theme });
                    }}
                    aria-pressed={isActive}
                    className="sr-pressable flex flex-col gap-2 rounded-[var(--sr-row-radius)] p-3 text-left"
                    style={{
                      backgroundColor: "var(--sr-card-fill)",
                      border: `${isActive ? "1.5px" : "var(--sr-card-border-width)"} solid ${
                        isActive ? "var(--sr-primary)" : "var(--sr-card-border)"
                      }`,
                    }}
                  >
                    <span className="flex gap-1">
                      {themeSwatch(theme).map((color, index) => (
                        <span
                          key={index}
                          className="h-4 w-4 rounded-full"
                          style={{ backgroundColor: toCSS(color) }}
                        />
                      ))}
                    </span>
                    <span className="block text-[14px] font-medium text-[var(--sr-ink)]">
                      {THEME_LABELS[theme].label}
                    </span>
                    <span className="block text-[12px] leading-tight text-[var(--sr-secondary-ink)]">
                      {THEME_LABELS[theme].summary}
                    </span>
                  </button>
                );
              })}
            </div>
          </section>

          {/* Accent */}
          <section className="flex flex-col gap-3">
            <SRSectionLabel>Color de acción</SRSectionLabel>
            <div className="flex flex-wrap gap-2.5">
              <AccentSwatch
                accent="theme"
                isActive={profile.accent === "theme"}
                color={toCSS(palette.primary)}
                onSelect={() => update({ accent: "theme" })}
              />
              {PICKABLE_ACCENTS.map((accent) => (
                <AccentSwatch
                  key={accent}
                  accent={accent}
                  isActive={profile.accent === accent}
                  color={ACCENT_BASE[accent] ?? "#000000"}
                  onSelect={() => update({ accent })}
                />
              ))}
              <label
                className="sr-pressable relative grid h-11 w-11 cursor-pointer place-items-center rounded-full"
                style={{
                  background:
                    "conic-gradient(#F6A7B5, #B09BEC, #9CC3F6, #7CD1BA, #F6A7B5)",
                  outline: profile.accent === "custom" ? "2.5px solid var(--sr-primary)" : "none",
                  outlineOffset: 2,
                }}
                title={ACCENT_LABELS.custom}
              >
                <input
                  type="color"
                  value={profile.customAccentHex ?? "#6487F1"}
                  onChange={(event) => update({ accent: "custom", customAccentHex: event.target.value })}
                  className="absolute inset-0 cursor-pointer opacity-0"
                  aria-label="Color personalizado"
                />
              </label>
            </div>
            <p className="text-[12px] text-[var(--sr-secondary-ink)]">
              Cualquier color que elijas se oscurece o aclara automáticamente hasta que el texto encima se lea.
            </p>
          </section>

          {/* Shape and rhythm */}
          <section className="flex flex-col gap-4">
            <SRSectionLabel>Forma y ritmo</SRSectionLabel>

            <Field label="Densidad">
              <SRSegmented
                label="Densidad"
                value={profile.density}
                onChange={(density) => update({ density })}
                options={(Object.keys(DENSITIES) as (keyof typeof DENSITIES)[]).map((id) => ({
                  id,
                  label: DENSITIES[id].label,
                }))}
              />
            </Field>

            <Field label="Botones">
              <SRSegmented
                label="Botones"
                value={profile.buttonShape}
                onChange={(buttonShape) => update({ buttonShape })}
                options={(Object.keys(BUTTON_SHAPES) as (keyof typeof BUTTON_SHAPES)[]).map((id) => ({
                  id,
                  label: BUTTON_SHAPES[id].label,
                }))}
              />
            </Field>

            <Field label="Tarjetas">
              <SRSegmented
                label="Tarjetas"
                value={profile.cardStyle}
                onChange={(cardStyle) => update({ cardStyle })}
                options={(Object.keys(CARD_STYLES) as (keyof typeof CARD_STYLES)[]).map((id) => ({
                  id,
                  label: CARD_STYLES[id].label,
                }))}
              />
            </Field>

            <Field label="Tamaño">
              <SRSegmented
                label="Tamaño"
                value={profile.visualScale}
                onChange={(visualScale) => update({ visualScale })}
                options={(Object.keys(VISUAL_SCALES) as (keyof typeof VISUAL_SCALES)[]).map((id) => ({
                  id,
                  label: VISUAL_SCALES[id].label,
                }))}
              />
            </Field>
          </section>

          {/* Motion, haptics, presence */}
          <section className="flex flex-col gap-4">
            <SRSectionLabel>Movimiento y presencia</SRSectionLabel>

            <Field
              label="Animaciones"
              detail={
                effectiveMotion === "reduced" && profile.motion !== "reduced"
                  ? "Tu navegador pide movimiento reducido, y eso manda sobre esta opción."
                  : undefined
              }
            >
              <SRSegmented
                label="Animaciones"
                value={profile.motion}
                onChange={(motion) => update({ motion })}
                options={(Object.keys(MOTION_LABELS) as (keyof typeof MOTION_LABELS)[]).map((id) => ({
                  id,
                  label: MOTION_LABELS[id],
                }))}
              />
            </Field>

            <Field
              label="Vibración"
              detail={
                supportsVibration()
                  ? undefined
                  : "Este navegador no puede vibrar, así que esta opción no hace nada aquí. En el iPhone sí."
              }
            >
              <SRSegmented
                label="Vibración"
                value={profile.haptics}
                onChange={(haptics: keyof typeof HAPTIC_LABELS) => update({ haptics })}
                options={(Object.keys(HAPTIC_LABELS) as (keyof typeof HAPTIC_LABELS)[]).map((id) => ({
                  id,
                  label: HAPTIC_LABELS[id],
                }))}
              />
            </Field>

            <Field label="Símbolo">
              <SRSegmented
                label="Símbolo"
                value={profile.presence}
                onChange={(presence) => update({ presence })}
                options={(Object.keys(PRESENCE_LABELS) as (keyof typeof PRESENCE_LABELS)[]).map((id) => ({
                  id,
                  label: PRESENCE_LABELS[id],
                }))}
              />
            </Field>
          </section>

          {/* Ahora layout */}
          <section className="flex flex-col gap-4">
            <SRSectionLabel>Pantalla Ahora</SRSectionLabel>

            <Field label="Disposición" detail={NOW_LAYOUTS[profile.nowLayout].detail}>
              <SRSegmented
                label="Disposición"
                value={profile.nowLayout}
                onChange={(nowLayout) => update({ nowLayout })}
                options={(Object.keys(NOW_LAYOUTS) as (keyof typeof NOW_LAYOUTS)[]).map((id) => ({
                  id,
                  label: NOW_LAYOUTS[id].label,
                }))}
              />
            </Field>

            <div className="flex flex-col gap-1.5">
              <p className="text-[14px] font-medium text-[var(--sr-ink)]">Qué se ve debajo del título</p>
              <div className="flex flex-wrap gap-2 pt-1">
                {ALL_METADATA.map((field) => {
                  const isOn = profile.visibleMetadata.includes(field);
                  return (
                    <button
                      key={field}
                      type="button"
                      onClick={() => {
                        haptics.light();
                        toggleMetadata(field);
                      }}
                      aria-pressed={isOn}
                      className="sr-pressable flex items-center gap-1.5 rounded-full px-3 py-1.5 text-[13px] font-medium"
                      style={{
                        backgroundColor: isOn ? "var(--sr-primary-soft)" : "var(--sr-divider)",
                        color: isOn ? "var(--sr-primary)" : "var(--sr-secondary-ink)",
                      }}
                    >
                      {isOn ? <Check className="h-3.5 w-3.5" /> : null}
                      {METADATA_LABELS[field]}
                    </button>
                  );
                })}
              </div>
              <p className="pt-1 text-[12px] text-[var(--sr-secondary-ink)]">
                El título y el botón de empezar no están en esta lista: nunca se pueden ocultar.
              </p>
            </div>
          </section>

          {!isOriginalProfile(profile) ? (
            <button
              type="button"
              onClick={() => {
                haptics.soft();
                reset();
              }}
              className="sr-pressable self-start text-[14px] font-medium text-[var(--sr-primary)]"
            >
              Restablecer el aspecto original
            </button>
          ) : null}

          {/* Extended reading */}
          <section className="flex flex-col gap-3">
            <SRSectionLabel>Cómo se lee lo que escribes</SRSectionLabel>
            <SRCard className="flex flex-col gap-3">
              <div className="flex items-start gap-3">
                <div className="min-w-0 flex-1">
                  <p className="text-[15px] font-medium text-[var(--sr-ink)]">Lectura ampliada</p>
                  <p className="mt-1 text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">
                    En el iPhone lee Apple Intelligence, dentro del propio móvil. Aquí no existe, así que
                    SinRutina puede pedir esa lectura a {engineName} para afinar el título, la duración, la
                    fecha y el primer paso.
                  </p>
                </div>
                <Switch
                  isOn={readsExtended}
                  label="Lectura ampliada"
                  onChange={(next) => {
                    haptics.soft();
                    setReadsExtended(next);
                  }}
                />
              </div>

              <ul className="flex flex-col gap-1.5 pl-3.5 text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">
                <Limit>Solo sale la frase que acabas de escribir, o el archivo que adjuntas. Nunca tus tareas guardadas.</Limit>
                <Limit>Solo propone. No mueve, no completa, no borra y no cambia ajustes.</Limit>
                <Limit>Cada dato que devuelve se comprueba aquí antes de usarse.</Limit>
                {hasBackupEngine ? (
                  <>
                    <Limit>
                      La frase no va directa a {engineName}: pasa por un pequeño servidor propio de SinRutina que
                      guarda la clave. Es lo único que hace. No tiene base de datos ni se acuerda de nadie.
                    </Limit>
                    <Limit>
                      Si {engineName} no responde, la lectura pasa por {imageEngineName}. Si tampoco responde, hay
                      otra ruta detrás, y si fallan todas se lee aquí mismo. Las gratuitas van primero.
                    </Limit>
                  </>
                ) : null}
                <Limit>Si lo apagas, SinRutina sigue leyendo en español dentro de este navegador.</Limit>
              </ul>

              {keyIsPublic ? (
                <p className="flex items-start gap-2 rounded-[var(--sr-row-radius)] bg-[var(--sr-blush-a14)] px-3 py-2.5 text-[13px] text-[var(--sr-ink)]">
                  <KeyRound className="mt-0.5 h-4 w-4 shrink-0 text-[var(--sr-blush)]" />
                  La clave sigue guardada con un nombre que el navegador puede ver. El servidor ya la usa desde su
                  lado, pero conviene moverla a GROQ_API_KEY y borrar la antigua.
                </p>
              ) : null}

              <div className="border-t border-[var(--sr-divider)] pt-3">
                <p className="text-[15px] font-medium text-[var(--sr-ink)]">Al dictar y al adjuntar</p>
                <ul className="mt-1.5 flex flex-col gap-1.5 pl-3.5 text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">
                  <Limit>{DICTATION_EXPLANATION[dictation]}</Limit>
                  <Limit>
                    El texto, los PDF y los archivos de calendario se leen dentro de este navegador. No salen a
                    ningún sitio salvo que la lectura ampliada esté encendida.
                  </Limit>
                  <Limit>
                    Una imagen no se puede leer aquí: no hay OCR en un navegador. La lee {imageEngineName}, porque
                    {" "}{engineName} no ve imágenes. Con la lectura ampliada apagada, adjuntarla no inventa nada
                    {" "}— te pide que lo escribas tú. La imagen no se guarda en ningún sitio.
                  </Limit>
                  <Limit>De un archivo guardo lo que he leído y su nombre. El archivo en sí no se queda.</Limit>
                </ul>
              </div>

              {readsExtended && lastFailure ? (
                <p className="flex items-start gap-2 rounded-[var(--sr-row-radius)] bg-[var(--sr-blush-a14)] px-3 py-2.5 text-[13px] text-[var(--sr-ink)]">
                  <WifiOff className="mt-0.5 h-4 w-4 shrink-0 text-[var(--sr-blush)]" />
                  {lastFailure}
                </p>
              ) : null}
            </SRCard>
          </section>

          {/* Demo data */}
          <section className="flex flex-col gap-3">
            <SRSectionLabel>Datos de demostración</SRSectionLabel>
            <SRCard className="flex items-start gap-3">
              <div className="min-w-0 flex-1">
                <p className="text-[15px] font-medium text-[var(--sr-ink)]">Ver SinRutina con ejemplos</p>
                <p className="mt-1 text-[13px] text-[var(--sr-secondary-ink)]">
                  Añade seis tareas de ejemplo, marcadas como «Demo». Al apagarlo desaparecen solo ellas; lo que
                  hayas escrito tú se queda.
                </p>
              </div>
              <Switch
                isOn={isDemoMode}
                label="Datos de demostración"
                onChange={(next) => {
                  haptics.soft();
                  setDemoMode(next);
                }}
              />
            </SRCard>
          </section>

          {/* Honest limits */}
          <section className="flex flex-col gap-3">
            <SRSectionLabel>Qué no puede hacer esta versión</SRSectionLabel>
            <SRCard className="flex flex-col gap-3">
              <p className="flex items-start gap-2.5 text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">
                <Smartphone className="mt-0.5 h-4 w-4 shrink-0 text-[var(--sr-primary)]" />
                <span>
                  Un navegador no tiene acceso a lo que sí tiene el iPhone. Estas funciones no están aquí, y
                  tampoco hay botones que finjan hacerlas:
                </span>
              </p>
              <ul className="flex flex-col gap-1.5 pl-7 text-[13px] text-[var(--sr-secondary-ink)]">
                <Limit>Alarmas que suenan con el móvil en silencio</Limit>
                <Limit>Bloqueo de otras apps durante una sesión</Limit>
                <Limit>Widget en la pantalla de inicio y Live Activity</Limit>
                <Limit>Compartir desde otras apps hacia SinRutina</Limit>
                <Limit>Leer tu calendario y tus recordatorios</Limit>
                <Limit>Apple Intelligence dentro del dispositivo, sin conexión</Limit>
                <Limit>«Salir a tiempo» con tu historial real de trayectos</Limit>
              </ul>
              <p className="text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">
                Lo que sí está es el núcleo entero: el mismo lector en español, el mismo motor que elige la
                tarea y la misma jerarquía de atención que en el iPhone. Y para varias de esas cosas hay un
                atajo que las deja en manos de quien sí puede hacerlas.
              </p>
              <button
                type="button"
                onClick={() => {
                  haptics.light();
                  setShowsShortcuts(true);
                }}
                className="sr-pressable inline-flex items-center gap-1.5 self-start text-[14px] font-semibold text-[var(--sr-primary)]"
              >
                Ver los atajos
                <ArrowUpRight className="h-4 w-4" />
              </button>
            </SRCard>
          </section>

          {/* Privacy and data */}
          <section className="flex flex-col gap-3">
            <SRSectionLabel>Tus datos</SRSectionLabel>
            <SRCard className="flex flex-col gap-3">
              <p className="text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">
                Todo se guarda en este navegador y en ningún sitio más. No hay cuenta, no hay servidor y nada
                de lo que escribes sale de aquí. Si borras los datos del sitio, se borra también SinRutina.
              </p>

              {!isPersistent ? (
                <p className="flex items-start gap-2 rounded-[var(--sr-row-radius)] bg-[var(--sr-blush-a14)] px-3 py-2.5 text-[13px] text-[var(--sr-ink)]">
                  <AlertTriangle className="mt-0.5 h-4 w-4 shrink-0 text-[var(--sr-blush)]" />
                  Este navegador no me deja guardar nada. SinRutina funciona, pero al cerrar la pestaña se
                  pierde lo que escribas. Suele pasar en ventanas privadas.
                </p>
              ) : null}

              <div className="border-t border-[var(--sr-divider)] pt-3">
                <p className="text-[15px] font-medium text-[var(--sr-ink)]">Una copia que te llevas tú</p>
                <p className="mt-1 text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">
                  Como no hay servidor, esto es lo único que sobrevive a borrar los datos del navegador o a
                  cambiar de aparato. Es un archivo normal: lo guardas donde quieras y lo vuelves a meter aquí
                  cuando haga falta.
                </p>
                <div className="mt-2.5 flex flex-wrap gap-2">
                  <button
                    type="button"
                    onClick={saveBackup}
                    disabled={realTasks.length === 0}
                    className="sr-pressable inline-flex items-center gap-1.5 rounded-full bg-[var(--sr-primary-soft)] px-3.5 py-2 text-[13px] font-semibold text-[var(--sr-primary)] disabled:opacity-45"
                  >
                    <Download className="h-3.5 w-3.5" />
                    Guardar una copia
                  </button>
                  <button
                    type="button"
                    onClick={() => {
                      haptics.light();
                      restoreInput.current?.click();
                    }}
                    className="sr-pressable inline-flex items-center gap-1.5 rounded-full bg-[var(--sr-primary-soft)] px-3.5 py-2 text-[13px] font-semibold text-[var(--sr-primary)]"
                  >
                    <Upload className="h-3.5 w-3.5" />
                    Recuperar una copia
                  </button>
                </div>
                <input
                  ref={restoreInput}
                  type="file"
                  accept="application/json,.json"
                  className="hidden"
                  onChange={(event) => {
                    const file = event.target.files?.[0];
                    event.target.value = "";
                    if (file) void loadBackup(file);
                  }}
                />
                {restoreNote ? (
                  <p className="mt-2 text-[13px] text-[var(--sr-ink)]" role="status">
                    {restoreNote}
                  </p>
                ) : null}
                <p className="mt-2 text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">
                  Recuperar solo añade: nunca borra ni pisa lo que ya tienes aquí. Si metes la misma copia dos
                  veces, la segunda no cambia nada.
                </p>
              </div>

              <button
                type="button"
                onClick={() => {
                  if (!confirmsErase) {
                    setConfirmsErase(true);
                    return;
                  }
                  haptics.success();
                  eraseEverything();
                  setConfirmsErase(false);
                }}
                className="sr-pressable self-start text-[14px] font-medium"
                style={{ color: confirmsErase ? toCSS(palette.blush) : "var(--sr-secondary-ink)" }}
              >
                {confirmsErase
                  ? `Toca otra vez para borrar ${realTasks.length} ${realTasks.length === 1 ? "tarea" : "tareas"}`
                  : "Borrar todo lo que hay aquí"}
              </button>
            </SRCard>
          </section>
        </div>
      </div>

      <ShortcutsSheet isOpen={showsShortcuts} onClose={() => setShowsShortcuts(false)} />
    </div>
  );
}

function Field({ label, detail, children }: { label: string; detail?: string; children: React.ReactNode }) {
  return (
    <div className="flex flex-col gap-1.5">
      <p className="text-[14px] font-medium text-[var(--sr-ink)]">{label}</p>
      {children}
      {detail ? <p className="text-[12px] text-[var(--sr-secondary-ink)]">{detail}</p> : null}
    </div>
  );
}

function Limit({ children }: { children: React.ReactNode }) {
  return (
    <li className="relative before:absolute before:-left-3.5 before:top-[9px] before:h-1 before:w-1 before:rounded-full before:bg-[var(--sr-secondary-ink)]">
      {children}
    </li>
  );
}

function AccentSwatch({
  accent,
  isActive,
  color,
  onSelect,
}: {
  accent: SRAccent;
  isActive: boolean;
  color: string;
  onSelect: () => void;
}) {
  const haptics = useHaptics();
  return (
    <button
      type="button"
      onClick={() => {
        haptics.light();
        onSelect();
      }}
      aria-pressed={isActive}
      aria-label={ACCENT_LABELS[accent]}
      title={ACCENT_LABELS[accent]}
      className="sr-pressable grid h-11 w-11 place-items-center rounded-full"
      style={{
        backgroundColor: color,
        outline: isActive ? "2.5px solid var(--sr-primary)" : "none",
        outlineOffset: 2,
      }}
    >
      {isActive ? <Check className="h-4 w-4 text-white drop-shadow" /> : null}
    </button>
  );
}

function Switch({
  isOn,
  label,
  onChange,
}: {
  isOn: boolean;
  label: string;
  onChange: (next: boolean) => void;
}) {
  return (
    <button
      type="button"
      role="switch"
      aria-checked={isOn}
      aria-label={label}
      onClick={() => onChange(!isOn)}
      className="relative h-[31px] w-[51px] shrink-0 rounded-full transition-colors"
      style={{ backgroundColor: isOn ? "var(--sr-primary)" : "var(--sr-divider)" }}
    >
      <span
        className="absolute top-[2px] h-[27px] w-[27px] rounded-full bg-white shadow transition-transform"
        style={{ transform: `translateX(${isOn ? 22 : 2}px)`, transitionDuration: "var(--sr-duration-quick)" }}
      />
    </button>
  );
}
