import AppIntents
import Foundation
import SwiftData

/// "Guardar material de estudio en SinRutina".
///
/// Atajos can hand over text extracted from a PDF, a page or the Files app.
/// Everything is stored locally and attached to a study task.
struct SRAddStudyMaterialIntent: AppIntent {
    static let title: LocalizedStringResource = "Guardar material de estudio en SinRutina"
    static let description = IntentDescription(
        "Guarda un texto, un PDF leído o una página como material de estudio, y crea la tarea si hace falta.",
        categoryName: "Estudiar"
    )

    @Parameter(title: "Título del material")
    var materialTitle: String?

    @Parameter(title: "Texto", inputOptions: String.IntentInputOptions(multiline: true))
    var text: String

    @Parameter(title: "Tarea de estudio")
    var taskTitle: String?

    @Parameter(title: "Fuentes")
    var sourceMode: SRSourceModeAppEnum?

    static var parameterSummary: some ParameterSummary {
        Summary("Guardar \(\.$text) como material en SinRutina") {
            \.$materialTitle
            \.$taskTitle
            \.$sourceMode
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 40 else { throw SRIntentError.nothingToDo }

        // Reuse an open study task with the same name before creating another one.
        let descriptor = FetchDescriptor<TaskItem>()
        let existing = (try? context.fetch(descriptor)) ?? []
        let wantedTitle = taskTitle?.trimmingCharacters(in: .whitespacesAndNewlines)

        let task: TaskItem
        if let wantedTitle, !wantedTitle.isEmpty,
           let match = existing.first(where: {
               $0.isOpen && SRHeuristics.normalized($0.title) == SRHeuristics.normalized(wantedTitle)
           }) {
            task = match
        } else {
            let summary = await SRIntelligenceService.shared.summarize(trimmed)
            var suggestion = SRCaptureSuggestion(
                title: wantedTitle?.isEmpty == false ? wantedTitle! : "Estudiar \(summary.title)",
                estimatedMinutes: LearningEngine.preferredStudyMinutes ?? 25,
                suggestedState: .after,
                context: "estudio",
                summary: summary.summary
            )
            suggestion.nextStep = "Leer un fragmento"
            task = SRTaskCommands.create(from: suggestion, source: "estudio", context: context)
        }

        let draft = MaterialImporter.material(
            fromText: trimmed,
            title: materialTitle,
            taskID: task.id
        )
        context.insert(draft.makeMaterial())
        task.preferredContext = "estudio"
        if let sourceMode { task.sourceMode = sourceMode.sourceMode }
        if task.studyObjective == nil {
            task.studyObjective = SRStudyDetector.objective(title: task.title, detail: task.detail)
        }
        try? context.save()
        SRTaskCommands.refreshOutsideSurfaces(context: context)

        return .result(
            dialog: IntentDialog("Guardé el material en \(task.title).")
        )
    }
}

/// "Explicar algo con SinRutina" — a one-shot explanation, honouring the source mode.
struct SRExplainIntent: AppIntent {
    static let title: LocalizedStringResource = "Explicar algo con SinRutina"
    static let description = IntentDescription(
        "Explica un fragmento o una duda usando tu material y, si lo permites, fuentes externas.",
        categoryName: "Estudiar"
    )

    @Parameter(title: "Qué explicar", inputOptions: String.IntentInputOptions(multiline: true))
    var fragment: String

    @Parameter(title: "Fuentes", default: .onlyMine)
    var sourceMode: SRSourceModeAppEnum

    static var parameterSummary: some ParameterSummary {
        Summary("Explicar \(\.$fragment) con \(\.$sourceMode)")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog & ReturnsValue<String> {
        let trimmed = fragment.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10 else { throw SRIntentError.nothingToDo }

        var sources: [SRWebSource] = []
        if sourceMode.sourceMode.allowsWeb {
            // Only a short query leaves the device, never the fragment itself.
            let query = await SRIntelligenceService.shared.searchQuery(for: trimmed, materialTitle: nil)
            sources = await WebSearchTool.shared.search(query: query, academicFirst: true, limit: 4)
        }

        let explanation = await SRIntelligenceService.shared.explanation(
            for: trimmed,
            action: LearningEngine.preferredExplainAction ?? .simpler,
            materialTitle: nil,
            externalContext: sources,
            previousBody: nil
        )
        return .result(
            value: explanation.body,
            dialog: IntentDialog("\(explanation.body)")
        )
    }
}

/// "Repasar con SinRutina" — the spaced review, sized to the time available.
struct SRReviewIntent: AppIntent {
    static let title: LocalizedStringResource = "Repasar con SinRutina"
    static let description = IntentDescription(
        "Abre un repaso corto con los conceptos que ya toca recordar.",
        categoryName: "Estudiar"
    )

    static let openAppWhenRun = true

    @Parameter(title: "Minutos disponibles", default: 6)
    var minutes: Int

    static var parameterSummary: some ParameterSummary {
        Summary("Repasar \(\.$minutes) minutos con SinRutina")
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let context = SRIntentRuntime.context()
        let due = ReviewScheduler.dueConcepts(context: context, limit: max(1, minutes / 2))
        guard !due.isEmpty else {
            return .result(dialog: IntentDialog("No hay nada que repasar ahora mismo."))
        }
        SRCommandBus.send(SRPendingCommand(kind: .openReview))
        return .result(
            dialog: IntentDialog(
                due.count == 1
                    ? "Te abro un concepto para repasar."
                    : "Te abro \(due.count) conceptos para repasar."
            )
        )
    }
}
