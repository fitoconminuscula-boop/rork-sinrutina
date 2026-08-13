import Foundation
import SwiftData

/// Spaced review without decks. Concepts arrive from study sessions and recall
/// answers, and come back only when there is a real gap to use.
@MainActor
enum ReviewScheduler {

    // MARK: - Creating

    /// Stores concepts from a recall round. Duplicates are strengthened, not copied.
    @discardableResult
    static func remember(
        questions: [SRRecallQuestion],
        origin: String?,
        taskID: UUID?,
        materialID: UUID?,
        context: ModelContext
    ) -> [ReviewConcept] {
        let existing = allConcepts(context: context)
        var created: [ReviewConcept] = []

        for question in questions {
            let concept = question.concept.trimmingCharacters(in: .whitespacesAndNewlines)
            guard concept.count >= 3 else { continue }
            let normalized = SRHeuristics.normalized(concept)
            if let match = existing.first(where: { SRHeuristics.normalized($0.concept) == normalized }) {
                if match.question == nil { match.question = question.question }
                match.isArchived = false
                continue
            }
            let item = ReviewConcept(
                concept: concept,
                origin: origin,
                question: question.question,
                expectedIdea: question.expectedIdea,
                taskID: taskID,
                materialID: materialID
            )
            context.insert(item)
            created.append(item)
        }
        try? context.save()
        return created
    }

    /// Records how a recall answer went, spacing the next look accordingly.
    static func record(
        outcome: SRRecallOutcome,
        for concept: ReviewConcept,
        confidence: Int? = nil,
        context: ModelContext
    ) {
        concept.record(outcome: outcome, confidence: confidence)
        if outcome != .skipped {
            BehaviorRecorder.recordRecall(hit: outcome == .answered, context: context)
        }
        try? context.save()
    }

    // MARK: - Reading

    static func allConcepts(context: ModelContext) -> [ReviewConcept] {
        let descriptor = FetchDescriptor<ReviewConcept>(sortBy: [SortDescriptor(\.nextReviewAt)])
        return (try? context.fetch(descriptor)) ?? []
    }

    static func dueConcepts(context: ModelContext, limit: Int = 3) -> [ReviewConcept] {
        let now = Date()
        return Array(
            allConcepts(context: context)
                .filter { !$0.isArchived && $0.nextReviewAt <= now }
                // Hardest first: those are the ones that pay off.
                .sorted { lhs, rhs in
                    if lhs.difficulty != rhs.difficulty { return lhs.difficulty > rhs.difficulty }
                    return lhs.nextReviewAt < rhs.nextReviewAt
                }
                .prefix(limit)
        )
    }

    static func stubbornConcepts(context: ModelContext) -> [ReviewConcept] {
        allConcepts(context: context).filter { $0.isStubborn && !$0.isArchived }
    }

    /// How many minutes a review of this many concepts realistically needs.
    static func minutes(forConceptCount count: Int) -> Int {
        max(2, count * 2)
    }

    /// The offer that appears when a gap shows up: "Tienes 6 minutos."
    static func gapOffer(availableMinutes: Int?, context: ModelContext) -> ReviewOffer? {
        guard let availableMinutes, availableMinutes >= 3, availableMinutes <= 25 else { return nil }
        let due = dueConcepts(context: context, limit: min(4, max(1, availableMinutes / 2)))
        guard !due.isEmpty else { return nil }
        return ReviewOffer(
            concepts: due,
            availableMinutes: availableMinutes,
            minutes: min(availableMinutes, minutes(forConceptCount: due.count))
        )
    }

    static func archive(_ concept: ReviewConcept, context: ModelContext) {
        concept.isArchived = true
        try? context.save()
    }
}

/// A concrete, time-bounded review proposal.
struct ReviewOffer: Identifiable {
    var id: String { concepts.map { $0.id.uuidString }.joined() }
    var concepts: [ReviewConcept]
    var availableMinutes: Int
    var minutes: Int

    var headline: String { "Tienes \(availableMinutes) minutos." }

    var detail: String {
        concepts.count == 1
            ? "Repasar un concepto."
            : "Repasar \(concepts.count) conceptos."
    }
}
