import AppIntents
import Foundation
import SwiftData

/// "Capturar en SinRutina" — the smallest possible entry point.
struct SRCaptureTaskIntent: AppIntent {
    static let title: LocalizedStringResource = "Capturar en SinRutina"
    static let description = IntentDescription(
        "Guarda algo en SinRutina sin pedirte proyecto, prioridad ni categoría.",
        categoryName: "Capturar"
    )

    @Parameter(title: "Qué tienes que hacer", requestValueDialog: "¿Qué quieres capturar?")
    var text: String

    @Parameter(title: "Insistencia", default: .normal)
    var insistence: SRInsistenceAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Capturar \(\.$text) en SinRutina") {
            \.$insistence
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        let suggestion = await SRIntelligenceService.shared.suggestion(for: text)
        let task = SRTaskCommands.create(from: suggestion, source: "atajo", context: context)
        if insistence.insistence != .normal {
            SRTaskCommands.setInsistence(
                insistence.insistence,
                remindAt: task.availableFrom ?? task.dueDate,
                for: task,
                context: context
            )
        }
        return .result(dialog: IntentDialog("Guardado: \(task.title). \(task.state.rawValue), \(task.estimatedMinutes) minutos."))
    }
}

/// "Analizar texto en SinRutina" — for anything Atajos can hand over.
struct SRAnalyzeTextIntent: AppIntent {
    static let title: LocalizedStringResource = "Analizar texto en SinRutina"
    static let description = IntentDescription(
        "Lee un texto en el dispositivo y propone una tarea concreta con su primer paso.",
        categoryName: "Capturar"
    )

    @Parameter(title: "Texto", inputOptions: String.IntentInputOptions(multiline: true), requestValueDialog: "¿Qué texto quieres que lea?")
    var text: String

    @Parameter(title: "Procedencia")
    var sourceApp: String?

    @Parameter(title: "Guardar directamente", default: true)
    var shouldSave: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Analizar \(\.$text) en SinRutina") {
            \.$sourceApp
            \.$shouldSave
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let suggestion = await SRIntelligenceService.shared.interpretSharedText(text, sourceApp: sourceApp)
        guard shouldSave else {
            return .result(
                value: suggestion.title,
                dialog: IntentDialog("Propuesta: \(suggestion.title), \(suggestion.minutesLabel).")
            )
        }
        let context = SRIntentRuntime.context()
        let task = SRTaskCommands.create(
            from: suggestion,
            source: sourceApp.map { "atajo·\($0)" } ?? "atajo",
            sharedExcerpt: text,
            context: context
        )
        return .result(
            value: task.title,
            dialog: IntentDialog("Guardado: \(task.title) en \(task.state.rawValue).")
        )
    }
}

/// "Analizar correo en SinRutina" — Atajos hands over whatever Mail exposes.
/// SinRutina never touches Mail's internal storage; it only reads what the person
/// passes through a shortcut.
struct SRAnalyzeMailIntent: AppIntent {
    static let title: LocalizedStringResource = "Analizar correo en SinRutina"
    static let description = IntentDescription(
        "Convierte un correo que le pases desde Atajos en una tarea con su primer paso, y puede prepararte un borrador de respuesta.",
        categoryName: "Capturar"
    )

    @Parameter(title: "Asunto")
    var subject: String?

    @Parameter(title: "Remitente")
    var sender: String?

    @Parameter(title: "Destinatario")
    var recipient: String?

    @Parameter(title: "Cuerpo del correo", inputOptions: String.IntentInputOptions(multiline: true))
    var body: String

    @Parameter(title: "Fecha del correo")
    var receivedAt: Date?

    @Parameter(title: "Preparar borrador de respuesta", default: true)
    var wantsDraft: Bool

    @Parameter(title: "Tono de la respuesta")
    var replyStyle: SRReplyStyleAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("Analizar el correo \(\.$body) en SinRutina") {
            \.$subject
            \.$sender
            \.$recipient
            \.$receivedAt
            \.$wantsDraft
            \.$replyStyle
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let context = SRIntentRuntime.context()

        // The whole email is read on device and turned into one decision.
        let analysis = await SRIntelligenceService.shared.mailAnalysis(
            sender: sender,
            recipient: recipient,
            subject: subject,
            body: body,
            date: receivedAt
        )

        let task = SRTaskCommands.create(
            from: analysis.suggestion(),
            source: "correo",
            sharedExcerpt: analysis.excerpt,
            context: context
        )
        task.mailSender = sender
        task.mailSubject = subject
        task.mailExcerpt = analysis.excerpt
        if analysis.needsAction, let waiting = analysis.waitingFor {
            task.waitingFor = waiting
        }

        guard wantsDraft, analysis.needsAction else {
            try? context.save()
            SRTaskCommands.refreshOutsideSurfaces(context: context)
            return .result(
                value: analysis.summary,
                dialog: IntentDialog(
                    analysis.needsAction
                        ? "Guardado: \(task.title). Primer paso: \(task.nextStep ?? "abrir el correo")."
                        : "Este correo no parece pedir nada. Lo guardé como \(task.title)."
                )
            )
        }

        // The draft is returned to Atajos so the person can continue in Mail.
        // SinRutina never sends anything itself.
        var draft = analysis.replyDraft ?? ""
        let style = replyStyle?.replyStyle ?? LearningEngine.preferredReplyStyle
        if let style, !draft.isEmpty {
            draft = await SRIntelligenceService.shared.restyleReply(
                draft: draft,
                style: style,
                sender: sender,
                subject: subject,
                originalExcerpt: analysis.excerpt
            )
            task.mailReplyStyle = style
        }
        task.mailReplyDraft = draft
        try? context.save()
        SRTaskCommands.refreshOutsideSurfaces(context: context)

        return .result(
            value: draft,
            dialog: IntentDialog("Te dejé el borrador listo y guardé \(task.title) en SinRutina.")
        )
    }
}
