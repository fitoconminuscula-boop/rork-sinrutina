import Foundation
import SwiftData

/// Runs the study conversation: material → understand → detect a gap → search →
/// contrast → explain.
///
/// It is deliberately not a chat. Each request produces one answer with its
/// sources attached, and the person chooses the next move from a short list.
@Observable
final class StudyCoordinator {
    /// The thread of answers, newest last. Bounded so it never becomes a chat log.
    private(set) var explanations: [SRExplanation] = []
    private(set) var comparison: SRComparison?
    private(set) var isWorking = false
    private(set) var lastSentQuery: String?
    private(set) var errorMessage: String?
    /// True while a request needs the network, so the UI can say it out loud.
    private(set) var isLeavingDevice = false

    var sourceMode: SRSourceMode
    /// The fragment the person selected, if any. Highest priority source.
    var selectedFragment: String = ""

    private let maximumThread = 6

    init(sourceMode: SRSourceMode = .mixed) {
        self.sourceMode = sourceMode
    }

    var latest: SRExplanation? { explanations.last }

    /// Every source cited so far, deduplicated, for the quiet "Fuentes" block.
    var citedSources: [SRWebSource] {
        var seen = Set<String>()
        return explanations
            .flatMap(\.sources)
            .filter { seen.insert($0.id).inserted }
    }

    func reset() {
        explanations.removeAll()
        comparison = nil
        errorMessage = nil
        lastSentQuery = nil
    }

    // MARK: - Explaining

    /// Answers "Explícame esto" following the source priority in the annex:
    /// selection → document → notes → session → web.
    func explain(
        action: SRExplainAction,
        material: StudyMaterial?,
        task: TaskItem?,
        context: ModelContext
    ) async {
        isWorking = true
        errorMessage = nil
        defer { isWorking = false }

        let fragment = resolvedFragment(material: material, task: task)
        var sources: [SRWebSource] = []

        let wantsWeb = action.needsWeb || sourceMode == .fromScratch
        let needsWeb = wantsWeb || (sourceMode == .mixed && fragment.count < 120)

        if needsWeb, sourceMode.allowsWeb {
            sources = await gatherSources(
                question: questionText(action: action, material: material, task: task),
                materialTitle: material?.title,
                context: context
            )
        }

        let explanation = await SRIntelligenceService.shared.explanation(
            for: fragment,
            action: action,
            materialTitle: material?.title,
            externalContext: sources,
            previousBody: latest?.body
        )
        append(explanation)
        BehaviorRecorder.recordExplainAction(action, context: context)
    }

    /// Explicit web request, used by "Buscar en la web" and by source mode changes.
    func searchWeb(
        question: String,
        material: StudyMaterial?,
        context: ModelContext
    ) async {
        guard sourceMode.allowsWeb else {
            errorMessage = "Estás en «Solo mi material». Cambia el modo de fuentes para buscar fuera."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let sources = await gatherSources(
            question: question,
            materialTitle: material?.title,
            context: context
        )
        guard !sources.isEmpty else {
            errorMessage = "No encontré fuentes claras para esto."
            return
        }
        let explanation = await SRIntelligenceService.shared.explanation(
            for: resolvedFragment(material: material, task: nil),
            action: .searchWeb,
            materialTitle: material?.title,
            externalContext: sources,
            previousBody: latest?.body
        )
        append(explanation)
    }

    /// "¿Coincide con mi texto?"
    func compareWithMaterial(
        material: StudyMaterial?,
        question: String,
        context: ModelContext
    ) async {
        guard let material, material.hasText else {
            errorMessage = "Añade material para poder compararlo."
            return
        }
        guard sourceMode.allowsWeb else {
            errorMessage = "Comparar necesita fuentes externas. Cambia el modo de fuentes."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let sources = await gatherSources(
            question: question,
            materialTitle: material.title,
            context: context
        )
        guard !sources.isEmpty else {
            errorMessage = "No encontré fuentes con las que contrastar."
            return
        }
        comparison = await SRIntelligenceService.shared.comparison(
            materialFragment: selectedFragment.isEmpty ? material.fragment() : selectedFragment,
            sources: sources
        )
    }

    // MARK: - Sessions and recall

    /// Builds the session plan for a study task, sized by what really works.
    func plan(
        for task: TaskItem,
        material: StudyMaterial?,
        context: ModelContext
    ) async -> SRStudyPlan {
        isWorking = true
        defer { isWorking = false }

        let minutes = LearningEngine.preferredStudyMinutes
            ?? LearningEngine.preferredSessionMinutes
            ?? task.estimatedMinutes
        let plan = await SRIntelligenceService.shared.studyPlan(
            title: task.title,
            objective: task.studyObjective ?? SRStudyDetector.objective(title: task.title, detail: task.detail),
            minutes: minutes,
            materialTitle: material?.title,
            materialFragment: material?.fragment(limit: 900)
        )
        task.studyPlan = plan
        if task.studyObjective == nil { task.studyObjective = plan.objective }
        try? context.save()
        return plan
    }

    func recallQuestions(
        for task: TaskItem,
        material: StudyMaterial?,
        count: Int
    ) async -> [SRRecallQuestion] {
        isWorking = true
        defer { isWorking = false }
        let fragment = material?.fragment(limit: 1_400)
            ?? [task.title, task.detail, task.studyObjective ?? ""].joined(separator: ". ")
        return await SRIntelligenceService.shared.recallQuestions(
            materialFragment: fragment,
            objective: task.studyObjective,
            count: count
        )
    }

    // MARK: - Internals

    /// Source priority: selection, then document, then notes, then session context.
    private func resolvedFragment(material: StudyMaterial?, task: TaskItem?) -> String {
        let selection = selectedFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        if selection.count >= 20 { return selection }
        if let material, material.hasText {
            return material.fragment(around: selection.isEmpty ? nil : selection)
        }
        if let notes = task?.notes, notes.count > 40 { return notes }
        if let detail = task?.detail, detail.count > 40 { return detail }
        if let excerpt = task?.sharedExcerpt, excerpt.count > 40 { return excerpt }
        return task?.title ?? ""
    }

    private func questionText(action: SRExplainAction, material: StudyMaterial?, task: TaskItem?) -> String {
        let selection = selectedFragment.trimmingCharacters(in: .whitespacesAndNewlines)
        if !selection.isEmpty { return String(selection.prefix(200)) }
        if let objective = task?.studyObjective, !objective.isEmpty { return objective }
        if let title = material?.title { return title }
        return task?.title ?? action.label
    }

    /// The privacy boundary. The model turns the doubt into a short query; only
    /// that query travels.
    private func gatherSources(
        question: String,
        materialTitle: String?,
        context: ModelContext
    ) async -> [SRWebSource] {
        isLeavingDevice = true
        defer { isLeavingDevice = false }

        let query = await SRIntelligenceService.shared.searchQuery(
            for: question,
            materialTitle: materialTitle
        )
        lastSentQuery = query
        let results = await WebSearchTool.shared.search(query: query, academicFirst: true)
        if !results.isEmpty {
            BehaviorRecorder.recordWebSearch(context: context)
        }
        return results
    }

    private func append(_ explanation: SRExplanation) {
        explanations.append(explanation)
        if explanations.count > maximumThread {
            explanations.removeFirst(explanations.count - maximumThread)
        }
    }
}
