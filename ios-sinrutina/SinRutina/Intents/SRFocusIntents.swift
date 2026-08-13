import AppIntents
import Foundation
import SwiftData

/// Levels offered to Atajos as fixed choices instead of free text.
enum SRFocusLevelAppEnum: String, AppEnum {
    case gentle
    case focus
    case deep

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Nivel de concentración")

    static let caseDisplayRepresentations: [SRFocusLevelAppEnum: DisplayRepresentation] = [
        .gentle: "Suave",
        .focus: "Enfoque",
        .deep: "Profundo",
    ]

    var level: SRFocusLevel {
        switch self {
        case .gentle: return .gentle
        case .focus: return .focus
        case .deep: return .deep
        }
    }
}

/// "Empezar modo enfoque" — prepares the environment for the recommended task.
///
/// It always opens SinRutina: an environment that changes the phone is never set
/// up behind the person's back.
struct SRStartFocusModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Empezar modo enfoque"
    static let description = IntentDescription(
        "Prepara el iPhone para la tarea que SinRutina recomienda y empieza la sesión.",
        categoryName: "Enfoque"
    )
    static let openAppWhenRun: Bool = true

    @Parameter(title: "Nivel", default: .gentle)
    var level: SRFocusLevelAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Empezar modo enfoque en nivel \(\.$level)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        guard let task = SRTaskCommands.currentRecommendation(context: context) else {
            throw SRIntentError.nothingToDo
        }
        SRFocusPreferences.shared.update { $0.defaultLevel = level.level }
        SRCommandBus.send(SRPendingCommand(kind: .startCurrent, taskID: task.id.uuidString))
        return .result(dialog: IntentDialog("Preparando \(task.title) en nivel \(level.level.label)."))
    }
}

/// "Pausar" — stops the clock without ending the session.
struct SRPauseFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Pausar SinRutina"
    static let description = IntentDescription(
        "Pausa la sesión en curso sin cerrar la tarea.",
        categoryName: "Enfoque"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard FocusSessionManager.shared.isRunning || SRFocusSessionStore.read() != nil else {
            throw SRIntentError.noCurrentTask
        }
        SRCommandBus.send(SRPendingCommand(kind: .pauseFocus))
        let context = SRIntentRuntime.context()
        FocusSessionManager.shared.pause(context: context)
        return .result(dialog: IntentDialog("En pausa. Cuando quieras seguimos."))
    }
}

/// "Continuar" / "Volver a la tarea".
struct SRResumeFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Continuar en SinRutina"
    static let description = IntentDescription(
        "Vuelve a la tarea que tenías en marcha.",
        categoryName: "Enfoque"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SRFocusSessionStore.read() else {
            throw SRIntentError.noCurrentTask
        }
        SRCommandBus.send(SRPendingCommand(kind: .resumeFocus, taskID: snapshot.taskID))
        return .result(dialog: IntentDialog("Volvemos a \(snapshot.title)."))
    }
}

/// "Avancé" — closes the session keeping the progress.
struct SRProgressedFocusIntent: AppIntent {
    static let title: LocalizedStringResource = "Avancé en SinRutina"
    static let description = IntentDescription(
        "Cierra la sesión guardando que avanzaste, sin marcarla como terminada.",
        categoryName: "Enfoque"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SRFocusSessionStore.read() else {
            throw SRIntentError.noCurrentTask
        }
        SRCommandBus.send(SRPendingCommand(kind: .progressedFocus, taskID: snapshot.taskID))
        return .result(dialog: IntentDialog("Guardo que avanzaste en \(snapshot.title)."))
    }
}

/// "Liberar temporalmente" — one app, for this session only.
struct SRReleaseAppIntent: AppIntent {
    static let title: LocalizedStringResource = "Liberar una app temporalmente"
    static let description = IntentDescription(
        "Abre una app concreta solo durante la sesión en curso.",
        categoryName: "Enfoque"
    )
    static let openAppWhenRun: Bool = true

    @Parameter(title: "App", requestValueDialog: "¿Qué app necesitas?")
    var appName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Liberar \(\.$appName) durante la sesión de SinRutina")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard SRFocusSessionStore.read() != nil else {
            throw SRIntentError.noCurrentTask
        }
        SRCommandBus.send(SRPendingCommand(kind: .releaseAppTemporarily, taskID: appName))
        return .result(dialog: IntentDialog("Abro \(appName) solo para esta tarea."))
    }
}

/// "Terminar modo" — the environment ends, the task stays where it was.
struct SREndFocusModeIntent: AppIntent {
    static let title: LocalizedStringResource = "Terminar modo enfoque"
    static let description = IntentDescription(
        "Devuelve el iPhone a la normalidad sin cerrar la tarea.",
        categoryName: "Enfoque"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        FocusSessionManager.shared.suspendForReentry()
        ScreenTimeService.shared.reconcile(hasLiveSession: false)
        SRCommandBus.send(SRPendingCommand(kind: .endFocusMode))
        return .result(dialog: IntentDialog("Modo terminado. La tarea sigue donde estaba."))
    }
}

/// Urgency. It never asks for the ten seconds and never needs the app open: the
/// point is getting the phone back immediately.
struct SREmergencyIntent: AppIntent {
    static let title: LocalizedStringResource = "Devolver el acceso al iPhone"
    static let description = IntentDescription(
        "Retira ahora mismo cualquier bloqueo que SinRutina haya puesto.",
        categoryName: "Enfoque"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        FocusSessionManager.shared.emergency(context: context)
        ScreenTimeService.shared.clear()
        SRCommandBus.send(SRPendingCommand(kind: .emergency))
        return .result(dialog: IntentDialog("Listo. El iPhone vuelve a estar completo."))
    }
}
