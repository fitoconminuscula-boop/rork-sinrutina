import { makeTask, type Task } from "./types";

/**
 * Demo data exists so someone can see how SinRutina behaves before trusting it
 * with anything real. It is never mixed in silently: it only appears after an
 * explicit switch in Ajustes, every item carries a "Demo" tag, a banner stays on
 * screen the whole time, and turning it off removes exactly these items and
 * nothing the person wrote.
 */
export function buildDemoTasks(): Task[] {
  const now = new Date();
  const inHours = (hours: number): string => new Date(now.getTime() + hours * 3_600_000).toISOString();
  const daysAgo = (days: number): string => new Date(now.getTime() - days * 86_400_000).toISOString();

  const tasks: Task[] = [
    makeTask({
      title: "Enviar los antecedentes al doctorado",
      estimatedMinutes: 7,
      state: "Ahora",
      nextStep: "Abrir el correo y adjuntar el primero",
      preferredContext: "administrativo",
      dueDate: inHours(6),
      isDemo: true,
    }),
    makeTask({
      title: "Llamar al dentista para la revisión",
      estimatedMinutes: 5,
      state: "Ahora",
      nextStep: "Buscar el número",
      preferredContext: "salud",
      isDemo: true,
    }),
    makeTask({
      title: "Pagar la factura de la luz",
      estimatedMinutes: 8,
      state: "Después",
      nextStep: "Abrir la web del banco",
      preferredContext: "dinero",
      dueDate: inHours(52),
      isDemo: true,
    }),
    makeTask({
      title: "Preparar el guion de la reunión del jueves",
      estimatedMinutes: 40,
      state: "Después",
      nextStep: "Escribir los tres puntos clave",
      preferredContext: "trabajo",
      isDemo: true,
    }),
    makeTask({
      title: "Respuesta del banco sobre la hipoteca",
      estimatedMinutes: 10,
      state: "Esperando",
      waitingFor: "el banco",
      isDemo: true,
    }),
    makeTask({
      title: "Mirar cursos de fotografía",
      estimatedMinutes: 20,
      state: "Algún día",
      isDemo: true,
    }),
  ];

  // One item deliberately looks stuck, so reduced scope can be seen at work.
  const stuck = tasks[0];
  stuck.procrastinationCount = 3;
  stuck.createdAt = daysAgo(9);

  const waiting = tasks[4];
  waiting.waitingSince = daysAgo(6);
  waiting.createdAt = daysAgo(11);

  return tasks;
}
