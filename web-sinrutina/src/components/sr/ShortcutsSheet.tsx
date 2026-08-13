import {
  CalendarDays,
  Check,
  CheckSquare,
  Copy,
  Download,
  Keyboard,
  Link2,
  Mail,
  Share2,
  Smartphone,
  Wand2,
} from "lucide-react";
import { useMemo, useState, useSyncExternalStore, type ReactNode } from "react";

import { SRSheet } from "./Primitives";
import { useHaptics } from "@/sr/AppearanceProvider";
import { buildAgendaFile, datedTasks, downloadFile, slugFilename } from "@/sr/handoff";
import { installer } from "@/sr/pwa";
import {
  KEYBOARD_SHORTCUTS,
  canRunShortcuts,
  captureLink,
  isIOS,
  isInstalled,
  savedShortcutName,
  saveShortcutName,
} from "@/sr/shortcuts";
import { useTasks } from "@/sr/TasksProvider";

/**
 * Atajos: what stands in for the iPhone capabilities a browser does not have.
 *
 * Everything listed here does a real job. Nothing on this screen is a button
 * that mimics a feature — each one hands the work to something that can
 * actually do it: the system calendar, the mail app, the Atajos app, the home
 * screen, the keyboard, or a file the person keeps themselves.
 *
 * Where a handover ends is always stated. SinRutina prepares and delivers; what
 * happens inside the other app is invisible to it, and it never claims otherwise.
 */
export function ShortcutsSheet({ isOpen, onClose }: { isOpen: boolean; onClose: () => void }) {
  const { realTasks } = useTasks();
  const haptics = useHaptics();

  const [copied, setCopied] = useState(false);
  const [copyFailed, setCopyFailed] = useState(false);
  const [agendaNote, setAgendaNote] = useState<string | null>(null);
  const [shortcutName, setShortcutName] = useState<string>(() => savedShortcutName());
  const [shortcutSaved, setShortcutSaved] = useState(false);

  const link = useMemo(() => (typeof window === "undefined" ? "" : captureLink()), []);
  const installed = isInstalled();
  const onIOS = isIOS();
  const offersShortcutsApp = canRunShortcuts();

  /** Only tasks that already carry a date can move across. Nothing is invented. */
  const dated = useMemo(() => datedTasks(realTasks), [realTasks]);

  // Only Chromium ever hands over a real install dialog. Everywhere else this
  // stays false and the manual steps are shown instead of a dead button.
  const canInstall = useSyncExternalStore(installer.subscribe, installer.canPrompt, () => false);

  const copy = async (): Promise<void> => {
    try {
      await navigator.clipboard.writeText(link);
      setCopyFailed(false);
      setCopied(true);
      window.setTimeout(() => setCopied(false), 2400);
    } catch {
      setCopied(false);
      setCopyFailed(true);
      window.setTimeout(() => setCopyFailed(false), 3600);
    }
  };

  const exportAgenda = (): void => {
    haptics.light();
    const ok = downloadFile(buildAgendaFile(realTasks), slugFilename("agenda", "ics"), "text/calendar");
    setAgendaNote(
      ok
        ? `Listo: ${dated.length} ${dated.length === 1 ? "tarea" : "tareas"} en un archivo. Ábrelo y tu calendario las añade de una vez.`
        : "El navegador no me ha dejado darte el archivo."
    );
  };

  const saveShortcut = (): void => {
    haptics.success();
    saveShortcutName(shortcutName);
    setShortcutSaved(true);
    window.setTimeout(() => setShortcutSaved(false), 2400);
  };

  return (
    <SRSheet isOpen={isOpen} onClose={onClose} title="Atajos">
      <div className="flex flex-col gap-7 pb-2">
        <p className="text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">
          Un navegador no puede sonar en silencio, ni enviar un correo, ni escribir en Recordatorios, ni vivir
          en tu pantalla de inicio. Esto no lo imita: lo prepara y lo deja en manos de quien sí puede hacerlo.
        </p>

        {/* Calendar */}
        <Group title="Calendario">
          <Block
            icon={<CalendarDays />}
            title="Que suene aunque tengas silencio"
            body="En cada tarea, «Más opciones» → «Llevarlo a mi calendario». Eliges la hora y cuánto antes quieres el aviso, y te doy el archivo del evento con esa alarma dentro. Lo abres, se añade a tu calendario y suena él, con las reglas de tu móvil."
          />
          <Block
            icon={<CalendarDays />}
            title="O directo a Google Calendar y Outlook"
            body="En esa misma pantalla puedes abrirlo en cualquiera de los dos con el evento ya escrito. La diferencia: ahí el aviso lo pone su calendario por defecto, porque no puedo elegirlo desde fuera. Para una hora exacta, el archivo."
          />

          <Action
            icon={<Download />}
            label={
              dated.length === 0
                ? "Ninguna tarea tiene fecha todavía"
                : `Llevar ${dated.length} ${dated.length === 1 ? "tarea con fecha" : "tareas con fecha"} de una vez`
            }
            detail="Un solo archivo con todo lo que tiene día y hora. Las que no tienen fecha se quedan aquí: inventarles una hora sería organizarte el día por mi cuenta."
            isDisabled={dated.length === 0}
            onClick={exportAgenda}
            note={agendaNote}
          />
        </Group>

        {/* Reminders */}
        <Group title="Recordatorios">
          <Block
            icon={<CheckSquare />}
            title="Mandarlo a tu app de tareas"
            body="En cada tarea, «Más opciones» → «Llevarlo a mis recordatorios». Te doy un archivo de tarea, que es un formato distinto al de un evento: lleva el título, el primer paso, la fecha límite si la tiene y su aviso."
          />
          <Note>
            Recordatorios en un Mac, Thunderbird y casi cualquier app de tareas lo abren directamente. Un iPhone
            no siempre lo reconoce y a veces ofrece Calendario en su lugar. Te lo digo antes de que lo intentes:
            si el tuyo no lo coge, usa el evento de calendario o el atajo de aquí abajo.
          </Note>

          {offersShortcutsApp ? (
            <div className="flex flex-col gap-2.5">
              <Block
                icon={<Wand2 />}
                title="Con un atajo tuyo, a donde tú quieras"
                body="La app Atajos sí llega a Recordatorios, Notas, Calendario o lo que uses. Crea ahí un atajo que reciba texto y haga lo que necesites, escribe su nombre exacto y aparecerá en cada tarea como una salida más."
              />
              <div className="ml-12 flex flex-col gap-2">
                <input
                  value={shortcutName}
                  onChange={(event) => setShortcutName(event.target.value)}
                  placeholder="Añadir a Recordatorios"
                  aria-label="Nombre de tu atajo"
                  className="w-full rounded-[var(--sr-row-radius)] border border-[var(--sr-divider)] bg-[var(--sr-surface)] px-3.5 py-2.5 text-[16px] text-[var(--sr-ink)] outline-none focus:border-[var(--sr-primary)]"
                />
                <button
                  type="button"
                  onClick={saveShortcut}
                  className="sr-pressable inline-flex w-fit items-center gap-1.5 rounded-full bg-[var(--sr-primary-soft)] px-3.5 py-2 text-[13px] font-semibold text-[var(--sr-primary)]"
                >
                  {shortcutSaved ? <Check className="h-3.5 w-3.5" /> : null}
                  {shortcutSaved
                    ? "Guardado"
                    : shortcutName.trim().length === 0
                      ? "Quitar el atajo"
                      : "Guardar el nombre"}
                </button>
                <p className="text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">
                  El nombre tiene que coincidir letra por letra con el de tu atajo. Si no existe, iOS abrirá la
                  app Atajos y no pasará nada más — y yo no puedo enterarme de si ha funcionado, así que nunca
                  te diré que sí.
                </p>
              </div>
            </div>
          ) : null}
        </Group>

        {/* Mail and messages */}
        <Group title="Correo y mensajes">
          <Block
            icon={<Mail />}
            title="Escribir el correo de una tarea"
            body="En cada tarea, «Más opciones» → «Escribirlo por correo». Se abre tu propio correo con el asunto y el cuerpo ya escritos, y ahí lo terminas tú. SinRutina no tiene cuenta ni forma de enviar nada: la ventana de redactar es donde acaba su trabajo."
          />
          <Block
            icon={<Mail />}
            title="Reclamar lo que estás esperando"
            body="En «Esperando», SinRutina te escribe el borrador para retomar cada cosa parada. Debajo tienes cuatro salidas: correo, WhatsApp, mensaje o copiarlo. Todas abren tu app con el texto puesto y se detienen ahí."
          />
          <Note>
            Si al guardarla apuntaste el correo de esa persona, el borrador va ya dirigido a ella. Si apuntaste
            un nombre, se abre sin destinatario y lo eliges tú.
          </Note>
        </Group>

        {/* Capture from anywhere */}
        <Group title="Escribir aquí desde fuera">
          <Block
            icon={<Link2 />}
            title="Una dirección que guarda una tarea"
            body="Al abrirse, guarda lo que lleve al final. Pégala en la app Atajos del iPhone, en un widget de Android o en un marcador. Se lee igual que si lo hubieras escrito tú."
          />
          <div className="ml-12 rounded-[var(--sr-row-radius)] bg-[var(--sr-primary-soft)] px-3.5 py-3">
            <p className="break-all font-mono text-[12px] leading-relaxed text-[var(--sr-ink)]">
              {link}
              <span className="text-[var(--sr-secondary-ink)]">tu%20tarea</span>
            </p>
            <button
              type="button"
              onClick={() => void copy()}
              className="sr-pressable mt-2 inline-flex items-center gap-1.5 text-[13px] font-semibold text-[var(--sr-primary)]"
            >
              {copied ? <Check className="h-3.5 w-3.5" /> : <Copy className="h-3.5 w-3.5" />}
              {copied ? "Copiado" : copyFailed ? "No me deja copiar, selecciónala tú" : "Copiar la dirección"}
            </button>
          </div>

          {installed && !onIOS ? (
            <Block
              icon={<Share2 />}
              title="Mandar algo aquí desde otra app"
              body="Al estar instalada, SinRutina sale en el menú de compartir de Android. Comparte un texto o un enlace y llega aquí como tarea, sin abrir nada más. En iPhone esto no existe: solo la app de verdad puede recibir lo que compartes."
            />
          ) : null}
        </Group>

        {/* Home screen */}
        <Group title="En tu pantalla de inicio">
          <Block
            icon={<Smartphone />}
            title="Tenerlo como una app"
            body={installed ? INSTALLED_BODY : onIOS ? IOS_INSTALL_BODY : INSTALL_BODY}
          />

          {canInstall ? (
            <button
              type="button"
              onClick={() => void installer.prompt()}
              className="sr-pressable ml-12 inline-flex w-fit items-center gap-2 rounded-full bg-[var(--sr-primary)] px-4 py-2 text-[14px] font-semibold text-[var(--sr-on-primary)]"
            >
              <Download className="h-4 w-4" />
              Instalar SinRutina
            </button>
          ) : null}

          {!installed && !canInstall && !onIOS ? (
            <Note>
              Este navegador no me deja abrir el diálogo de instalación desde aquí. Está en su menú, como
              «Instalar aplicación» o «Añadir a la pantalla de inicio».
            </Note>
          ) : null}

          {installed ? (
            <Note>
              Manteniendo pulsado el icono tienes dos accesos directos: capturar algo y «Estoy saturado».
            </Note>
          ) : null}
        </Group>

        {/* Keyboard */}
        <Group title="Con el teclado">
          <Block
            icon={<Keyboard />}
            title="Sin apuntar con el ratón"
            body="Si estás en un ordenador, lo de siempre está a una tecla."
          />
          <ul className="ml-12 flex flex-col gap-1.5">
            {KEYBOARD_SHORTCUTS.map((shortcut) => (
              <li key={shortcut.keys} className="flex items-center gap-3">
                <kbd className="min-w-[52px] rounded-[8px] bg-[var(--sr-divider)] px-2 py-1 text-center font-mono text-[12px] font-semibold text-[var(--sr-ink)]">
                  {shortcut.keys}
                </kbd>
                <span className="text-[14px] text-[var(--sr-secondary-ink)]">{shortcut.action}</span>
              </li>
            ))}
          </ul>
        </Group>

        <p className="text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">
          Ninguno de estos atajos manda nada a ningún sitio por su cuenta ni deja a SinRutina funcionando por
          detrás. Cada uno prepara algo y te lo entrega: abrirlo, enviarlo o guardarlo lo haces tú. Cuando
          cierras la pestaña, la app deja de existir hasta que vuelvas.
        </p>
      </div>
    </SRSheet>
  );
}

const INSTALLED_BODY =
  "Ya lo estás usando desde la pantalla de inicio: pantalla completa, sin barra de direcciones, y funciona sin conexión porque tus tareas ya estaban en este aparato. Sigue sin haber widget, porque eso solo existe en la app del iPhone.";

const IOS_INSTALL_BODY =
  "Compartir → «Añadir a pantalla de inicio». Safari no deja hacerlo desde un botón, así que hay que pasar por ahí. Luego se abre a pantalla completa, con su icono y sin barra de direcciones, y sigue funcionando sin conexión.";

const INSTALL_BODY =
  "Se instala como una app normal: pantalla completa, su icono y funcionando sin conexión. Ocupa muy poco y no deja nada corriendo por detrás cuando la cierras.";

/** A titled run of related shortcuts, so the sheet reads as sections not a list. */
function Group({ title, children }: { title: string; children: ReactNode }) {
  return (
    <section className="flex flex-col gap-3">
      <p className="text-[11px] font-semibold uppercase tracking-[0.08em] text-[var(--sr-secondary-ink)]">
        {title}
      </p>
      {children}
    </section>
  );
}

function Block({ icon, title, body }: { icon: ReactNode; title: string; body: string }) {
  return (
    <div className="flex items-start gap-3">
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-[var(--sr-primary-soft)] text-[var(--sr-primary)] [&>svg]:h-[17px] [&>svg]:w-[17px]">
        {icon}
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-[15px] font-medium text-[var(--sr-ink)]">{title}</p>
        <p className="mt-1 text-[13px] leading-relaxed text-[var(--sr-secondary-ink)]">{body}</p>
      </div>
    </div>
  );
}

/** Something worth doing right here, rather than a description of where to go. */
function Action({
  icon,
  label,
  detail,
  isDisabled,
  onClick,
  note,
}: {
  icon: ReactNode;
  label: string;
  detail: string;
  isDisabled: boolean;
  onClick: () => void;
  note: string | null;
}) {
  return (
    <div className="ml-12 flex flex-col gap-1.5">
      <button
        type="button"
        onClick={onClick}
        disabled={isDisabled}
        className="sr-pressable inline-flex w-fit items-center gap-1.5 rounded-full bg-[var(--sr-primary-soft)] px-3.5 py-2 text-left text-[13px] font-semibold text-[var(--sr-primary)] disabled:opacity-45"
      >
        <span className="[&>svg]:h-3.5 [&>svg]:w-3.5">{icon}</span>
        {label}
      </button>
      <p className="text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">{detail}</p>
      {note ? (
        <p className="text-[13px] text-[var(--sr-ink)]" role="status">
          {note}
        </p>
      ) : null}
    </div>
  );
}

function Note({ children }: { children: ReactNode }) {
  return (
    <p className="ml-12 text-[12px] leading-relaxed text-[var(--sr-secondary-ink)]">{children}</p>
  );
}
