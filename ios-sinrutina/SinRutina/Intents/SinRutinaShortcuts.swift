import AppIntents

/// Only the handful of actions worth saying out loud. Screens are not exposed.
///
/// iOS allows at most ten spoken shortcuts, so several intents deliberately have
/// no phrase and live only inside Atajos: analysing a mail, creating an event,
/// reading a text, releasing one app, ending the mode, Urgencia, and the travel
/// actions ("¿Cuándo tengo que salir?", "Estoy saliendo", "Ya llegué"). The
/// dangerous or ambiguous ones are exactly the ones kept out of voice.
struct SinRutinaShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: SRWhatNowIntent(),
            phrases: [
                "Qué hago ahora en \(.applicationName)",
                "Qué toca ahora en \(.applicationName)",
                "Dime qué hacer en \(.applicationName)",
            ],
            shortTitle: "Qué hago ahora",
            systemImageName: "questionmark.circle"
        )

        AppShortcut(
            intent: SRCaptureTaskIntent(),
            phrases: [
                "Capturar en \(.applicationName)",
                "Apuntar algo en \(.applicationName)",
                "Guardar esto en \(.applicationName)",
            ],
            shortTitle: "Capturar",
            systemImageName: "square.and.pencil"
        )

        AppShortcut(
            intent: SRSaturatedIntent(),
            phrases: [
                "Estoy saturado en \(.applicationName)",
                "Estoy saturada en \(.applicationName)",
                "No puedo con todo en \(.applicationName)",
            ],
            shortTitle: "Estoy saturado",
            systemImageName: "sparkles"
        )

        AppShortcut(
            intent: SRBeginCurrentTaskIntent(),
            phrases: [
                "Empezar esta tarea en \(.applicationName)",
                "Empezar tarea en \(.applicationName)",
                "Empezar ahora en \(.applicationName)",
            ],
            shortTitle: "Empezar",
            systemImageName: "play.circle"
        )

        AppShortcut(
            intent: SRPauseFocusIntent(),
            phrases: [
                "Pausar \(.applicationName)",
                "Pausa en \(.applicationName)",
            ],
            shortTitle: "Pausar",
            systemImageName: "pause.circle"
        )

        AppShortcut(
            intent: SRResumeFocusIntent(),
            phrases: [
                "Volver a la tarea en \(.applicationName)",
                "Continuar en \(.applicationName)",
            ],
            shortTitle: "Volver a la tarea",
            systemImageName: "arrow.turn.down.right"
        )

        AppShortcut(
            intent: SRFinishCurrentTaskIntent(),
            phrases: [
                "Terminé en \(.applicationName)",
                "Ya está hecho en \(.applicationName)",
            ],
            shortTitle: "Terminé",
            systemImageName: "checkmark.circle"
        )

        AppShortcut(
            intent: SRPostponeCurrentTaskIntent(),
            phrases: [
                "Posponer en \(.applicationName)",
                "Dejarlo para después en \(.applicationName)",
            ],
            shortTitle: "Posponer",
            systemImageName: "calendar"
        )

        AppShortcut(
            intent: SRMarkWaitingIntent(),
            phrases: [
                "Marcar como esperando en \(.applicationName)",
                "Esto depende de otra persona en \(.applicationName)",
            ],
            shortTitle: "Esperando",
            systemImageName: "hourglass"
        )

        AppShortcut(
            intent: SRCreateReminderIntent(),
            phrases: [
                "Crear recordatorio en \(.applicationName)",
                "Recordarme algo con \(.applicationName)",
            ],
            shortTitle: "Crear recordatorio",
            systemImageName: "bell.badge"
        )
    }

    static var shortcutTileColor: ShortcutTileColor = .lightBlue
}
