import Foundation
import SwiftData

/// One thing SinRutina wants to say, with the reason attached.
struct SRIntervention: Identifiable {
    var id: UUID
    var domain: SRProactivityDomain
    var level: SRInterventionLevel
    var style: SRMessageStyle
    var message: String
    /// The plain-language answer to "¿Por qué esta?". Built from facts only.
    var reason: String
    var taskID: String?
    var primaryLabel: String
    var symbolName: String

    init(
        id: UUID = UUID(),
        domain: SRProactivityDomain,
        level: SRInterventionLevel,
        style: SRMessageStyle,
        message: String,
        reason: String,
        taskID: String? = nil,
        primaryLabel: String,
        symbolName: String
    ) {
        self.id = id
        self.domain = domain
        self.level = level
        self.style = style
        self.message = message
        self.reason = reason
        self.taskID = taskID
        self.primaryLabel = primaryLabel
        self.symbolName = symbolName
    }
}

/// Decides whether SinRutina speaks first, and if so, how loudly.
///
/// The whole point is subtraction: most of the time the answer is silence. Being
/// ignored never escalates anything — it changes the timing, then the size of the
/// task, and finally asks the person what to do.
@MainActor
enum ProactivityEngine {

    /// Picks at most one intervention. One useful thing beats three mediocre ones.
    static func nextIntervention(
        tasks: [TaskItem],
        profile: BehaviorProfile?,
        availableMinutes: Int?,
        nextEventTitle: String?,
        hasRunningTask: Bool,
        context: ModelContext,
        now: Date = Date()
    ) -> SRIntervention? {
        let preferences = SRProactivityPreferences.shared
        preferences.closeStaleRecords(now: now)

        let candidates = buildCandidates(
            tasks: tasks,
            profile: profile,
            availableMinutes: availableMinutes,
            nextEventTitle: nextEventTitle,
            context: context,
            now: now
        )
        guard !candidates.isEmpty else { return nil }

        let budget = preferences.budget
        let style = preferences.bestStyle()

        for candidate in candidates {
            guard preferences.isEnabled(candidate.domain) else { continue }

            let receptivity = SRReceptivityScore.compute(
                hour: Calendar.current.component(.hour, from: now),
                hourlyCompletions: profile?.hourlyCounts ?? [],
                availableMinutes: availableMinutes,
                taskMinutes: candidate.taskMinutes,
                isInFocus: false,
                hasRunningTask: hasRunningTask,
                ignoredRatio: budget.ignoredRatio
            )
            guard receptivity.value >= preferences.level.receptivityFloor else { continue }

            let level = receptivity.suggestedLevel(importance: candidate.importance)
            guard level >= .suggestion, budget.allows(level: level) else { continue }

            // An hour the person told us not to use is respected literally.
            if let avoid = LearningEngine.hourToAvoid,
               Calendar.current.component(.hour, from: now) == avoid {
                continue
            }

            let message = candidate.message(style: style, availableMinutes: availableMinutes)
            return SRIntervention(
                domain: candidate.domain,
                level: level,
                style: style,
                message: message,
                reason: candidate.reason,
                taskID: candidate.taskID,
                primaryLabel: candidate.primaryLabel,
                symbolName: candidate.domain.symbolName
            )
        }
        return nil
    }

    /// Registers that SinRutina spoke, so the budget and the learning are honest.
    static func log(_ intervention: SRIntervention, task: TaskItem?, context: ModelContext) {
        SRProactivityPreferences.shared.log(
            SRInterventionRecord(
                id: intervention.id,
                domain: intervention.domain,
                level: intervention.level,
                style: intervention.style,
                taskID: intervention.taskID
            )
        )
        if let task {
            task.lastInterventionAt = Date()
            try? context.save()
        }
    }

    static func resolve(
        _ intervention: SRIntervention,
        outcome: SRInterventionRecord.Outcome,
        task: TaskItem?,
        context: ModelContext
    ) {
        let preferences = SRProactivityPreferences.shared
        var minutesToAction: Double?
        if outcome == .started,
           let record = preferences.records.first(where: { $0.id == intervention.id }) {
            minutesToAction = Date().timeIntervalSince(record.createdAt) / 60
            if let minutesToAction {
                BehaviorRecorder.recordTimeToStart(minutes: minutesToAction, context: context)
            }
        }
        preferences.resolve(id: intervention.id, outcome: outcome, minutesToAction: minutesToAction)

        if let task, outcome == .ignored || outcome == .dismissed {
            task.ignoredInterventionCount += 1
            try? context.save()
            BehaviorRecorder.recordIgnoredReminder(context: context)
        }
        LearningEngine.refreshFromInterventions()
    }

    /// What to do about a task whose suggestions keep being walked past.
    /// First time: change the moment. Second: make it smaller. After that, ask.
    static func adaptation(for task: TaskItem) -> SRAdaptation? {
        let ignored = max(task.ignoredInterventionCount, SRProactivityPreferences.shared.ignoredStreak(taskID: task.id.uuidString))
        guard !task.wasReleased else { return nil }
        switch ignored {
        case 0: return nil
        case 1: return .changeTiming
        case 2: return .makeSmaller
        default: return .ask
        }
    }

    // MARK: - Candidates

    private struct Candidate {
        var domain: SRProactivityDomain
        var importance: SRInterventionLevel
        var taskID: String?
        var taskTitle: String
        var taskMinutes: Int
        var reason: String
        var primaryLabel: String
        /// Overrides the learned wording when the situation needs its own sentence.
        var fixedMessage: String?

        func message(style: SRMessageStyle, availableMinutes: Int?) -> String {
            if let fixedMessage { return fixedMessage }
            return style.message(
                title: taskTitle,
                minutes: taskMinutes,
                availableMinutes: availableMinutes
            )
        }
    }

    private static func buildCandidates(
        tasks: [TaskItem],
        profile: BehaviorProfile?,
        availableMinutes: Int?,
        nextEventTitle: String?,
        context: ModelContext,
        now: Date
    ) -> [Candidate] {
        var candidates: [Candidate] = []
        let open = tasks.filter { $0.isOpen && !$0.wasReleased }

        // 1. A real gap that a real task fits into.
        if let availableMinutes, availableMinutes >= 5 {
            let fitting = open
                .filter { $0.estimatedMinutes <= availableMinutes }
                .sorted { $0.estimatedMinutes > $1.estimatedMinutes }
            if let task = fitting.first, task.lastInterventionAt.map({ now.timeIntervalSince($0) > 5_400 }) ?? true {
                var reason = "Tienes \(availableMinutes) minutos"
                if let nextEventTitle, !nextEventTitle.isEmpty { reason += " antes de \(nextEventTitle)" }
                reason += ", esta tarea suele tomar \(task.estimatedMinutes)"
                if task.procrastinationCount > 0, task.openDays >= 1 {
                    reason += task.openDays == 1
                        ? " y sigue abierta desde ayer"
                        : " y sigue abierta desde hace \(task.openDays) días"
                }
                reason += "."
                candidates.append(
                    Candidate(
                        domain: .calendar,
                        importance: .suggestion,
                        taskID: task.id.uuidString,
                        taskTitle: task.title,
                        taskMinutes: task.estimatedMinutes,
                        reason: reason,
                        primaryLabel: "Empezar"
                    )
                )
            }
        }

        // 2. A concept that came back hard yesterday.
        let stubborn = ReviewScheduler.stubbornConcepts(context: context)
        if let concept = stubborn.first {
            candidates.append(
                Candidate(
                    domain: .review,
                    importance: .suggestion,
                    taskID: nil,
                    taskTitle: concept.concept,
                    taskMinutes: 3,
                    reason: "«\(concept.concept)» te costó las últimas veces que apareció.",
                    primaryLabel: "Hazme una pregunta",
                    fixedMessage: "Ayer este concepto costó. ¿Te hago una pregunta?"
                )
            )
        }

        // 3. A review that fits a small gap.
        if let offer = ReviewScheduler.gapOffer(availableMinutes: availableMinutes, context: context) {
            candidates.append(
                Candidate(
                    domain: .review,
                    importance: .suggestion,
                    taskID: nil,
                    taskTitle: offer.detail,
                    taskMinutes: offer.minutes,
                    reason: "Hay \(offer.concepts.count) conceptos que tocan y cabe en \(offer.availableMinutes) minutos.",
                    primaryLabel: "Repasar",
                    fixedMessage: "\(offer.headline) \(offer.detail)"
                )
            )
        }

        // 4. An email still unanswered.
        if let mail = open
            .filter({ $0.isMail && !$0.mailWasAnswered })
            .max(by: { $0.createdAt > $1.createdAt }) {
            let days = Calendar.current.dateComponents([.day], from: mail.createdAt, to: now).day ?? 0
            if days >= 2 {
                candidates.append(
                    Candidate(
                        domain: .mail,
                        importance: .suggestion,
                        taskID: mail.id.uuidString,
                        taskTitle: mail.title,
                        taskMinutes: mail.estimatedMinutes,
                        reason: "Este correo entró hace \(days) días y sigue sin respuesta.",
                        primaryLabel: "Ver el correo",
                        fixedMessage: "Este correo sigue sin respuesta después de \(days) días."
                    )
                )
            }
        }

        // 5. Something parked on another person for too long.
        if let waiting = tasks
            .filter({ $0.state == .waiting && $0.waitingDays >= 4 })
            .filter({ task in
                guard let last = task.lastFollowUpAt else { return true }
                return now.timeIntervalSince(last) > 3 * 86_400
            })
            .max(by: { $0.waitingDays < $1.waitingDays }) {
            candidates.append(
                Candidate(
                    domain: .waiting,
                    importance: .suggestion,
                    taskID: waiting.id.uuidString,
                    taskTitle: waiting.title,
                    taskMinutes: 5,
                    reason: "Lleva \(waiting.waitingDays) días esperando\(waiting.waitingFor.map { " a \($0)" } ?? "").",
                    primaryLabel: "Preparar seguimiento",
                    fixedMessage: "Han pasado \(waiting.waitingDays) días. ¿Quieres hacer seguimiento?"
                )
            )
        }

        // 6. A task that keeps being pushed: offer to shrink it, never to insist.
        if let stuck = open
            .filter({ $0.procrastinationCount >= 3 })
            .max(by: { $0.procrastinationCount < $1.procrastinationCount }) {
            candidates.append(
                Candidate(
                    domain: .tasks,
                    importance: .suggestion,
                    taskID: stuck.id.uuidString,
                    taskTitle: stuck.title,
                    taskMinutes: stuck.estimatedMinutes,
                    reason: "Sigue del mismo tamaño desde que entró.",
                    primaryLabel: "Hacerla más pequeña",
                    fixedMessage: "Esta tarea sigue igual de grande. ¿La hacemos más pequeña?"
                )
            )
        }

        // 7. Study with a date that is getting close.
        if let exam = open
            .filter({ $0.isStudy })
            .filter({ task in
                guard let due = task.dueDate else { return false }
                let days = Calendar.current.dateComponents([.day], from: now, to: due).day ?? 0
                return days >= 0 && days <= 10
            })
            .min(by: { ($0.dueDate ?? .distantFuture) < ($1.dueDate ?? .distantFuture) }) {
            let days = Calendar.current.dateComponents([.day], from: now, to: exam.dueDate ?? now).day ?? 0
            candidates.append(
                Candidate(
                    domain: .study,
                    importance: days <= 2 ? .important : .suggestion,
                    taskID: exam.id.uuidString,
                    taskTitle: exam.title,
                    taskMinutes: LearningEngine.preferredStudyMinutes ?? exam.estimatedMinutes,
                    reason: days == 0
                        ? "Es hoy y todavía queda material por ver."
                        : "Quedan \(days) días y el material aún no está repartido.",
                    primaryLabel: "Ver sesiones"
                )
            )
        }

        // 8. A contextual reminder whose proposed slot has arrived.
        if let contextual = open.first(where: { task in
            guard task.wantsContextualReminder, let slot = task.proposedSlotStart else { return false }
            return slot <= now && now.timeIntervalSince(slot) < 3_600
        }) {
            candidates.append(
                Candidate(
                    domain: .reminders,
                    importance: contextual.insistence == .important ? .important : .suggestion,
                    taskID: contextual.id.uuidString,
                    taskTitle: contextual.title,
                    taskMinutes: contextual.estimatedMinutes,
                    reason: "Pediste que te avisara cuando hubiera hueco, y este es el hueco.",
                    primaryLabel: "Empezar"
                )
            )
        }

        return candidates
    }
}

/// What SinRutina does when its suggestions keep being ignored.
enum SRAdaptation {
    case changeTiming
    case makeSmaller
    case ask

    var question: String {
        switch self {
        case .changeTiming: return "Buscamos otro momento para esto."
        case .makeSmaller: return "Vamos a dejarlo en un primer paso más pequeño."
        case .ask: return "Esto sigue apareciendo. ¿Qué hacemos?"
        }
    }
}
