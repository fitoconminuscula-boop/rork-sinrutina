import AppIntents
import Foundation
import SwiftData

/// "¿Qué hago ahora?" — answers out loud without opening the app.
struct SRWhatNowIntent: AppIntent {
    static let title: LocalizedStringResource = "Qué hago ahora"
    static let description = IntentDescription(
        "Dice la única cosa que SinRutina recomienda hacer ahora mismo.",
        categoryName: "Decidir"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let context = SRIntentRuntime.context()
        await SRIntentRuntime.warmCalendar()

        guard let task = SRTaskCommands.currentRecommendation(context: context) else {
            return .result(value: "", dialog: IntentDialog("No hay nada urgente ahora. Puedes descansar."))
        }
        var sentence = "\(task.title). \(task.estimatedMinutes) minutos."
        if let step = task.nextStep, !step.isEmpty {
            sentence += " Empieza por: \(step)."
        }
        if let window = CalendarService.shared.freeWindow(), window.minutes > 0 {
            let limit = window.nextEventTitle.map { "antes de \($0)" } ?? "libres"
            sentence += " Tienes \(window.minutes) minutos \(limit)."
        }
        return .result(value: task.title, dialog: IntentDialog(stringLiteral: sentence))
    }
}

/// "Empezar tarea actual" — opens the immersive execution screen and the Live Activity.
struct SRBeginCurrentTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Empezar tarea de SinRutina"
    static let description = IntentDescription(
        "Empieza la tarea que SinRutina recomienda y arranca el temporizador.",
        categoryName: "Decidir"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        guard let task = SRTaskCommands.currentRecommendation(context: context) else {
            throw SRIntentError.nothingToDo
        }
        SRCommandBus.send(SRPendingCommand(kind: .startCurrent, taskID: task.id.uuidString))
        return .result(dialog: IntentDialog("Empezamos: \(task.title)."))
    }
}

/// "Terminé"
struct SRFinishCurrentTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Terminé en SinRutina"
    static let description = IntentDescription(
        "Marca como hecha la tarea que tenías en marcha.",
        categoryName: "Decidir"
    )

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        // Prefer whatever is actually running; fall back to today's recommendation.
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.isCurrent })
        let running = (try? context.fetch(descriptor))?.first { $0.state != .completed }
        guard let task = running ?? SRTaskCommands.currentRecommendation(context: context) else {
            throw SRIntentError.noCurrentTask
        }
        SRTaskCommands.complete(task, context: context)
        return .result(dialog: IntentDialog("Hecho: \(task.title)."))
    }
}

/// "Posponer"
struct SRPostponeCurrentTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Posponer en SinRutina"
    static let description = IntentDescription(
        "Mueve la tarea actual a Después o a Algún día.",
        categoryName: "Decidir"
    )

    @Parameter(title: "Llevar a", default: .after)
    var destination: SRTaskStateAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Posponer la tarea de SinRutina a \(\.$destination)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        guard let task = SRTaskCommands.currentRecommendation(context: context) else {
            throw SRIntentError.noCurrentTask
        }
        let state = destination.taskState
        guard state != .waiting else {
            SRTaskCommands.markWaiting(task, for: nil, context: context)
            return .result(dialog: IntentDialog("\(task.title) queda esperando."))
        }
        SRTaskCommands.postpone(task, to: state, context: context)
        return .result(dialog: IntentDialog("\(task.title) pasa a \(state.rawValue)."))
    }
}

/// "Marcar como Esperando"
struct SRMarkWaitingIntent: AppIntent {
    static let title: LocalizedStringResource = "Marcar como esperando en SinRutina"
    static let description = IntentDescription(
        "Aparta la tarea actual porque depende de otra persona.",
        categoryName: "Decidir"
    )

    @Parameter(title: "Depende de", requestValueDialog: "¿De quién depende?")
    var person: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Marcar como esperando a \(\.$person) en SinRutina")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        guard let task = SRTaskCommands.currentRecommendation(context: context) else {
            throw SRIntentError.noCurrentTask
        }
        SRTaskCommands.markWaiting(task, for: person, context: context)
        return .result(dialog: IntentDialog("\(task.title) queda esperando a \(task.waitingFor ?? "otra persona")."))
    }
}

/// "Estoy saturado"
struct SRSaturatedIntent: AppIntent {
    static let title: LocalizedStringResource = "Estoy saturado"
    static let description = IntentDescription(
        "Reduce SinRutina a una única acción diminuta.",
        categoryName: "Decidir"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        SRCommandBus.send(SRPendingCommand(kind: .saturated))
        guard let task = SRTaskCommands.currentRecommendation(context: context) else {
            return .result(dialog: IntentDialog("No hay nada pendiente. Respira."))
        }
        let actions = await SRIntelligenceService.shared.microActions(
            for: task.title,
            context: task.preferredContext
        )
        let first = actions.first ?? "Ponlo delante de ti"
        return .result(dialog: IntentDialog("Solo haz esto: \(first)."))
    }
}
