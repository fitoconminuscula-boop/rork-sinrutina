import Foundation

/// Turns local numbers into sentences a person can read, edit or delete.
///
/// Hard rules:
/// - Only observable behaviour. Durations, hours, choices. Never a trait, never a
///   mood, never a diagnosis.
/// - An inference that would change persistent behaviour is stored as unconfirmed
///   and has to be accepted before it affects anything.
/// - Small patterns never generate a question.
@MainActor
enum LearningEngine {

    /// Re-derives the notes from the profile. Cheap and idempotent, so it can run
    /// after any recorded signal.
    static func refresh(from profile: BehaviorProfile) {
        let store = SRLearningStore.shared
        guard store.isLearningEnabled else { return }

        if let minutes = profile.typicalSessionMinutes, minutes >= 5 {
            store.observe(
                kind: .sessionLength,
                text: "Prefieres sesiones de \(minutes) minutos.",
                value: String(minutes),
                minimumEvidence: 1
            )
        }

        if let hour = profile.mostProductiveHour {
            store.observe(
                kind: .activeHour,
                text: "Sueles empezar cosas \(Self.dayPart(hour)).",
                value: String(hour),
                minimumEvidence: 1
            )
        }

        if let hour = profile.leastReceptiveHour {
            store.observe(
                kind: .ignoredHour,
                text: "Los avisos \(Self.dayPart(hour)) casi nunca funcionan.",
                value: String(hour),
                minimumEvidence: 1
            )
        }

        if let minutes = profile.typicalStudyMinutes, minutes >= 5 {
            store.observe(
                kind: .studyLength,
                text: "Estudias mejor en tramos de \(minutes) minutos.",
                value: String(minutes),
                minimumEvidence: 1
            )
        }

        if let drift = profile.durationDriftFactor, drift > 1.25 {
            store.observe(
                kind: .splitLongMaterial,
                text: "Lo largo te funciona mejor dividido: suele costarte más de lo previsto.",
                value: String(format: "%.2f", drift),
                minimumEvidence: 1
            )
        }

        if let favourite = profile.favouriteExplainAction,
           let action = SRExplainAction(rawValue: favourite) {
            store.observe(
                kind: .explanationStyle,
                text: Self.explanationSentence(for: action),
                value: favourite,
                minimumEvidence: 1
            )
        }

        if let micro = profile.favouriteMicroAction {
            store.observe(
                kind: .microActionWorks,
                text: "Empezar por «\(micro.lowercased())» te desatasca.",
                value: micro,
                minimumEvidence: 1
            )
        }

        if let style = profile.favouriteReplyStyle,
           let reply = SRReplyStyle(rawValue: style) {
            store.observe(
                kind: .mailTone,
                text: "Prefieres correos en tono \(reply.label.lowercased()).",
                value: style,
                minimumEvidence: 1
            )
        }

        if let share = profile.webSearchShare, share > 0.45 {
            store.observe(
                kind: .webUse,
                text: "Casi siempre acabas contrastando fuera de tu material.",
                value: String(format: "%.2f", share),
                minimumEvidence: 1
            )
        } else if let share = profile.webSearchShare, share < 0.1 {
            store.observe(
                kind: .webUse,
                text: "Trabajas casi siempre solo con tu material.",
                value: String(format: "%.2f", share),
                minimumEvidence: 1
            )
        }

        if let average = profile.averageMinutesToStart, average > 0 {
            let rounded = Int(average.rounded())
            store.observe(
                kind: .timeToStart,
                text: rounded <= 2
                    ? "Cuando algo te encaja, empiezas casi al momento."
                    : "Tardas unos \(rounded) minutos en arrancar tras una sugerencia.",
                value: String(rounded),
                minimumEvidence: 1
            )
        }

        // Which environment actually finishes work. Never applied on its own: this
        // one asks before it changes how sessions are prepared.
        if let best = profile.bestFocusLevel, let level = SRFocusLevel(rawValue: best) {
            store.observe(
                kind: .focusLevel,
                text: "Terminas más cuando la sesión va en \(level.label).",
                value: best,
                minimumEvidence: 1
            )
        }

        // Too much friction is a design failure, not a discipline failure.
        if let pressure = profile.exitPressure, pressure > 1.5 {
            store.observe(
                kind: .environmentTooTight,
                text: "Este nivel de bloqueo te genera más fricción que ayuda: conviene bajarlo.",
                value: String(format: "%.2f", pressure),
                minimumEvidence: 1
            )
        }

        if SRDistractionLog.frictionIsIneffective() {
            store.observe(
                kind: .frictionLength,
                text: "Los segundos de espera ya no te frenan, así que los estoy acortando.",
                value: "ineffective",
                minimumEvidence: 1
            )
        }

        let postponements = profile.actionResponses["Posponer"] ?? 0
        if postponements >= 6, profile.completedTaskCount > 0 {
            let ratio = Double(postponements) / Double(max(profile.completedTaskCount, 1))
            if ratio > 0.8 {
                store.observe(
                    kind: .postponePattern,
                    text: "Cuando algo se posterga varias veces, hacerlo más pequeño funciona mejor que insistir.",
                    value: String(format: "%.2f", ratio),
                    minimumEvidence: 1
                )
            }
        }
    }

    /// Notes derived from how SinRutina's own messages landed.
    static func refreshFromInterventions() {
        let store = SRLearningStore.shared
        guard store.isLearningEnabled else { return }
        let preferences = SRProactivityPreferences.shared
        let records = preferences.records
        guard records.count >= 6 else { return }

        let style = preferences.bestStyle()
        let shown = records.filter { $0.style == style }.count
        if shown >= 3 {
            store.observe(
                kind: .messageStyle,
                text: "Respondes mejor a avisos en tono \(style.label.lowercased()).",
                value: style.rawValue,
                minimumEvidence: 1
            )
        }

        // Did suggestions that landed inside a real gap work better?
        let withGap = records.filter { $0.domain == .calendar }
        if withGap.count >= 3 {
            let useful = withGap.filter(\.wasUseful).count
            if Double(useful) / Double(withGap.count) > 0.5 {
                store.observe(
                    kind: .gapReminders,
                    text: "Sueles responder mejor a avisos dentro de huecos reales de tiempo.",
                    value: "gap",
                    minimumEvidence: 1
                )
            }
        }

        let ignoredRatio = preferences.budget.ignoredRatio
        if ignoredRatio > 0.6 {
            store.observe(
                kind: .reminderResponse,
                text: "Últimamente los avisos no te sirven: conviene que hable menos.",
                value: String(format: "%.2f", ignoredRatio),
                minimumEvidence: 1
            )
        }
    }

    // MARK: - Reading the notes back

    /// Session length the person accepted, if any. Used to size proposals.
    static var preferredSessionMinutes: Int? {
        SRLearningStore.shared.value(for: .sessionLength)
    }

    static var preferredStudyMinutes: Int? {
        SRLearningStore.shared.value(for: .studyLength)
    }

    /// Hour the person confirmed as their good one.
    static var preferredHour: Int? {
        SRLearningStore.shared.value(for: .activeHour)
    }

    static var hourToAvoid: Int? {
        SRLearningStore.shared.insight(of: .ignoredHour)?.intValue
    }

    static var preferredExplainAction: SRExplainAction? {
        SRLearningStore.shared.insight(of: .explanationStyle)?.value
            .flatMap(SRExplainAction.init(rawValue:))
    }

    static var preferredReplyStyle: SRReplyStyle? {
        SRLearningStore.shared.insight(of: .mailTone)?.value
            .flatMap(SRReplyStyle.init(rawValue:))
    }

    static var prefersSplitMaterial: Bool {
        SRLearningStore.shared.insight(of: .splitLongMaterial) != nil
    }

    static var prefersGapReminders: Bool {
        SRLearningStore.shared.insight(of: .gapReminders) != nil
    }

    /// The level the person confirmed works better, if any. Only a suggestion:
    /// the level of every session is still chosen before starting.
    static var suggestedFocusLevel: SRFocusLevel? {
        SRLearningStore.shared.insight(of: .focusLevel)?.value
            .flatMap(SRFocusLevel.init(rawValue:))
    }

    /// True when the evidence says the environment should be gentler.
    static var environmentIsTooTight: Bool {
        SRLearningStore.shared.insight(of: .environmentTooTight) != nil
    }

    // MARK: - Wording

    private static func dayPart(_ hour: Int) -> String {
        switch hour {
        case 5..<12: return "por la mañana"
        case 12..<15: return "a mediodía"
        case 15..<20: return "por la tarde"
        case 20..<24: return "por la noche"
        default: return "de madrugada"
        }
    }

    private static func explanationSentence(for action: SRExplainAction) -> String {
        switch action {
        case .simpler: return "Prefieres explicaciones simples y cortas."
        case .deeper: return "Prefieres explicaciones con más profundidad."
        case .example: return "Prefieres explicaciones con ejemplos."
        case .compare: return "Entiendes mejor cuando algo se compara con otra idea."
        case .quizMe: return "Te sirve que te pregunte al final."
        case .didntUnderstand: return "Suele hacerte falta un segundo ángulo para entender algo."
        case .searchWeb: return "Te gusta contrastar con fuentes externas."
        }
    }
}
