import Foundation

/// The kinds of things SinRutina is allowed to notice. Every case is an
/// observable behaviour — never a trait, a diagnosis or a judgement.
nonisolated enum SRLearnedInsightKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case sessionLength
    case activeHour
    case ignoredHour
    case splitLongMaterial
    case explanationStyle
    case microActionWorks
    case gapReminders
    case mailTone
    case studyLength
    case webUse
    case postponePattern
    case timeToStart
    case messageStyle
    case reminderResponse
    /// Which level of concentration ends with the task actually finished.
    case focusLevel
    /// An app reached for again and again during one kind of work.
    case distractors
    /// Whether the deliberate seconds are helping or only annoying.
    case frictionLength
    /// Whether restrictions are being lifted through Urgencia too often.
    case environmentTooTight
    /// The gap between the departure time proposed and the real one.
    case departureLag

    var id: String { rawValue }

    var domain: SRProactivityDomain {
        switch self {
        case .sessionLength, .timeToStart, .microActionWorks, .postponePattern: return .tasks
        case .activeHour, .ignoredHour, .gapReminders, .reminderResponse: return .reminders
        case .splitLongMaterial, .explanationStyle, .studyLength: return .study
        case .mailTone: return .mail
        case .webUse: return .web
        case .messageStyle: return .tasks
        case .focusLevel, .distractors, .frictionLength, .environmentTooTight: return .tasks
        case .departureLag: return .calendar
        }
    }

    var symbolName: String {
        switch self {
        case .sessionLength, .studyLength: return "timer"
        case .activeHour, .ignoredHour, .gapReminders, .timeToStart: return "clock"
        case .splitLongMaterial: return "square.split.2x1"
        case .explanationStyle: return "text.bubble"
        case .microActionWorks: return "arrow.turn.down.right"
        case .mailTone: return "envelope"
        case .webUse: return "globe"
        case .postponePattern: return "arrow.uturn.forward"
        case .messageStyle: return "quote.bubble"
        case .reminderResponse: return "bell"
        case .focusLevel: return "circle.lefthalf.filled"
        case .distractors: return "app.badge"
        case .frictionLength: return "hand.point.up.left"
        case .environmentTooTight: return "lock.open"
        case .departureLag: return "figure.walk.departure"
        }
    }

    /// Only the inferences that would change persistent behaviour need a yes.
    var needsConfirmation: Bool {
        switch self {
        case .sessionLength, .activeHour, .gapReminders, .mailTone, .studyLength, .splitLongMaterial,
             .focusLevel, .distractors, .departureLag:
            return true
        case .ignoredHour, .explanationStyle, .microActionWorks, .webUse,
             .postponePattern, .timeToStart, .messageStyle, .reminderResponse,
             .frictionLength, .environmentTooTight:
            return false
        }
    }
}

/// One sentence SinRutina believes about how this person works. Editable,
/// deletable and switchable off — the person is the final authority.
nonisolated struct SRLearnedInsight: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var kind: SRLearnedInsightKind
    /// The sentence shown in Ajustes, in plain Spanish.
    var text: String
    /// Machine-readable payload, e.g. "20" for a session length in minutes.
    var value: String?
    var isEnabled: Bool
    /// False while it still needs a yes from the person.
    var isConfirmed: Bool
    var evidenceCount: Int
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        kind: SRLearnedInsightKind,
        text: String,
        value: String? = nil,
        isEnabled: Bool = true,
        isConfirmed: Bool = false,
        evidenceCount: Int = 1,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.value = value
        self.isEnabled = isEnabled
        self.isConfirmed = isConfirmed
        self.evidenceCount = evidenceCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    /// Only confirmed, enabled insights are allowed to change behaviour.
    var isActive: Bool { isEnabled && (isConfirmed || !kind.needsConfirmation) }

    var intValue: Int? { value.flatMap(Int.init) }

    /// The question asked before an inference starts changing anything.
    var confirmationQuestion: String {
        "\(text) ¿Lo tengo en cuenta?"
    }
}

/// Local, editable memory of what SinRutina has noticed. Nothing here ever
/// leaves the device and nothing here is presented as a diagnosis.
@Observable
final class SRLearningStore {
    static let shared = SRLearningStore()

    private(set) var insights: [SRLearnedInsight]
    /// True when the person switched the whole learning layer off.
    private(set) var isLearningEnabled: Bool

    private init() {
        insights = Self.load()
        let defaults = SRShared.defaults
        isLearningEnabled = defaults.object(forKey: SRShared.Key.learningEnabled) as? Bool ?? true
    }

    var activeInsights: [SRLearnedInsight] {
        guard isLearningEnabled else { return [] }
        return insights.filter(\.isActive)
    }

    /// The first insight still waiting for a yes, if any.
    var pendingConfirmation: SRLearnedInsight? {
        guard isLearningEnabled else { return nil }
        return insights.first { $0.kind.needsConfirmation && !$0.isConfirmed && $0.isEnabled }
    }

    func insight(of kind: SRLearnedInsightKind) -> SRLearnedInsight? {
        insights.first { $0.kind == kind && $0.isActive }
    }

    func value(for kind: SRLearnedInsightKind) -> Int? {
        insight(of: kind)?.intValue
    }

    func setLearningEnabled(_ isEnabled: Bool) {
        isLearningEnabled = isEnabled
        SRShared.defaults.set(isEnabled, forKey: SRShared.Key.learningEnabled)
    }

    /// Adds or strengthens an observation. Repeated evidence never re-asks a
    /// question the person already answered.
    func observe(
        kind: SRLearnedInsightKind,
        text: String,
        value: String?,
        minimumEvidence: Int = 3
    ) {
        guard isLearningEnabled else { return }
        if let index = insights.firstIndex(where: { $0.kind == kind }) {
            var existing = insights[index]
            let sameValue = existing.value == value
            existing.evidenceCount = sameValue ? existing.evidenceCount + 1 : 1
            existing.text = text
            existing.updatedAt = Date()
            if !sameValue {
                existing.value = value
                // A changed conclusion has to earn its yes again.
                if existing.kind.needsConfirmation { existing.isConfirmed = false }
            }
            insights[index] = existing
            persist()
            return
        }
        guard minimumEvidence <= 1 else {
            // Hold the observation until it has been seen enough times.
            bumpCandidate(kind: kind, text: text, value: value, minimumEvidence: minimumEvidence)
            return
        }
        insights.append(SRLearnedInsight(kind: kind, text: text, value: value))
        persist()
    }

    func confirm(_ insight: SRLearnedInsight) {
        guard let index = insights.firstIndex(where: { $0.id == insight.id }) else { return }
        insights[index].isConfirmed = true
        insights[index].updatedAt = Date()
        persist()
    }

    func decline(_ insight: SRLearnedInsight) {
        // Declining keeps the note visible but stops it changing anything.
        guard let index = insights.firstIndex(where: { $0.id == insight.id }) else { return }
        insights[index].isConfirmed = false
        insights[index].isEnabled = false
        insights[index].updatedAt = Date()
        persist()
    }

    func setEnabled(_ isEnabled: Bool, for insight: SRLearnedInsight) {
        guard let index = insights.firstIndex(where: { $0.id == insight.id }) else { return }
        insights[index].isEnabled = isEnabled
        insights[index].updatedAt = Date()
        persist()
    }

    func updateText(_ text: String, for insight: SRLearnedInsight) {
        guard let index = insights.firstIndex(where: { $0.id == insight.id }) else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insights[index].text = trimmed
        insights[index].updatedAt = Date()
        persist()
    }

    func remove(_ insight: SRLearnedInsight) {
        insights.removeAll { $0.id == insight.id }
        candidates.removeValue(forKey: insight.kind.rawValue)
        persist()
    }

    func removeAll() {
        insights.removeAll()
        candidates.removeAll()
        persist()
    }

    // MARK: - Candidates

    /// Observations that have not been seen often enough to become a note.
    private var candidates: [String: (value: String?, count: Int, text: String)] = [:]

    private func bumpCandidate(
        kind: SRLearnedInsightKind,
        text: String,
        value: String?,
        minimumEvidence: Int
    ) {
        let key = kind.rawValue
        var current = candidates[key] ?? (value, 0, text)
        if current.value != value {
            current = (value, 0, text)
        }
        current.count += 1
        current.text = text
        candidates[key] = current
        guard current.count >= minimumEvidence else { return }
        candidates.removeValue(forKey: key)
        insights.append(
            SRLearnedInsight(kind: kind, text: text, value: value, evidenceCount: current.count)
        )
        persist()
    }

    // MARK: - Storage

    private func persist() {
        guard let data = try? JSONEncoder().encode(insights) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.learnedInsights)
    }

    private static func load() -> [SRLearnedInsight] {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.learnedInsights),
              let decoded = try? JSONDecoder().decode([SRLearnedInsight].self, from: data) else {
            return []
        }
        return decoded
    }
}
