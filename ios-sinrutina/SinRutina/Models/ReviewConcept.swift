import Foundation
import SwiftData

/// A concept worth remembering, scheduled for review without decks, grades or
/// streaks. Difficulty is recorded to space the next look, never to score anyone.
@Model
final class ReviewConcept {
    var id: UUID
    var concept: String
    /// Where it came from, in plain words: "Capítulo 4" or "Correo de Julieta".
    var origin: String?
    /// The question SinRutina asks to bring it back.
    var question: String?
    /// The idea that counts as remembering it.
    var expectedIdea: String?
    var createdAt: Date
    var lastReviewedAt: Date?
    var nextReviewAt: Date
    /// 0 easy … 3 hard. Only used to space reviews.
    var difficulty: Int
    /// 0 none … 4 solid. The person's own sense of it.
    var confidence: Int
    var reviewCount: Int
    /// Compact history of outcomes, most recent last: "a" answered, "d" don't know, "s" skipped.
    var outcomeHistory: String
    var taskID: UUID?
    var materialID: UUID?
    var isArchived: Bool

    init(
        concept: String,
        origin: String? = nil,
        question: String? = nil,
        expectedIdea: String? = nil,
        taskID: UUID? = nil,
        materialID: UUID? = nil,
        now: Date = Date()
    ) {
        self.id = UUID()
        self.concept = concept
        self.origin = origin
        self.question = question
        self.expectedIdea = expectedIdea
        self.createdAt = now
        self.lastReviewedAt = nil
        // First look happens the same day: recall is cheapest while it is fresh.
        self.nextReviewAt = now.addingTimeInterval(4 * 3_600)
        self.difficulty = 1
        self.confidence = 1
        self.reviewCount = 0
        self.outcomeHistory = ""
        self.taskID = taskID
        self.materialID = materialID
        self.isArchived = false
    }

    var isDue: Bool { !isArchived && nextReviewAt <= Date() }

    /// The gap, in days, that follows the current difficulty and confidence.
    private var nextIntervalDays: Double {
        let base: Double
        switch difficulty {
        case 0: base = 6
        case 1: base = 3
        case 2: base = 1.5
        default: base = 0.6
        }
        let confidenceBoost = 1 + Double(max(0, confidence - 1)) * 0.55
        let maturity = min(Double(reviewCount), 6) * 0.35 + 1
        return min(base * confidenceBoost * maturity, 120)
    }

    /// Records how the recall went and books the next look.
    func record(outcome: SRRecallOutcome, confidence newConfidence: Int? = nil, now: Date = Date()) {
        reviewCount += 1
        lastReviewedAt = now
        switch outcome {
        case .answered:
            difficulty = max(0, difficulty - 1)
            confidence = min(4, (newConfidence ?? confidence) + 1)
            outcomeHistory.append("a")
        case .dontKnow:
            difficulty = min(3, difficulty + 1)
            confidence = max(0, (newConfidence ?? confidence) - 1)
            outcomeHistory.append("d")
        case .skipped:
            outcomeHistory.append("s")
        }
        if outcomeHistory.count > 24 {
            outcomeHistory = String(outcomeHistory.suffix(24))
        }
        let days = outcome == .skipped ? 0.5 : nextIntervalDays
        nextReviewAt = now.addingTimeInterval(days * 86_400)
    }

    /// True when this concept keeps coming back hard. Used to offer help, never
    /// to label the person.
    var isStubborn: Bool {
        outcomeHistory.suffix(3).filter { $0 == "d" }.count >= 2
    }

    var dueLabel: String {
        guard !isDue else { return "Toca ahora" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: nextReviewAt).day ?? 0
        if days <= 0 { return "Hoy" }
        if days == 1 { return "Mañana" }
        return "En \(days) días"
    }
}
