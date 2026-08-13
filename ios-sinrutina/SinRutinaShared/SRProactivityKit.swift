import Foundation

/// How often SinRutina is allowed to speak first.
nonisolated enum SRProactivityLevel: String, Codable, CaseIterable, Sendable, Identifiable {
    case minimal
    case balanced
    case proactive

    var id: String { rawValue }

    var label: String {
        switch self {
        case .minimal: return "Mínimas"
        case .balanced: return "Equilibradas"
        case .proactive: return "Proactivas"
        }
    }

    var explanation: String {
        switch self {
        case .minimal: return "Casi nunca habla primero. Tú preguntas."
        case .balanced: return "Habla cuando hay una razón clara."
        case .proactive: return "Aprovecha huecos y avisa antes."
        }
    }

    /// Maximum number of times SinRutina may interrupt in a day.
    var dailyBudget: Int {
        switch self {
        case .minimal: return 2
        case .balanced: return 5
        case .proactive: return 9
        }
    }

    /// Minimum quiet time between two interruptions.
    var minimumGapMinutes: Int {
        switch self {
        case .minimal: return 240
        case .balanced: return 90
        case .proactive: return 45
        }
    }

    /// Receptivity needed before saying anything at all.
    var receptivityFloor: Double {
        switch self {
        case .minimal: return 0.72
        case .balanced: return 0.48
        case .proactive: return 0.3
        }
    }
}

/// The areas that may produce an unsolicited suggestion, each independently
/// switchable so the person can keep, say, study but silence mail.
nonisolated enum SRProactivityDomain: String, Codable, CaseIterable, Sendable, Identifiable {
    case study
    case calendar
    case tasks
    case mail
    case waiting
    case review
    case web
    case reminders

    var id: String { rawValue }

    var label: String {
        switch self {
        case .study: return "Estudio"
        case .calendar: return "Calendario"
        case .tasks: return "Tareas"
        case .mail: return "Correos"
        case .waiting: return "Esperando"
        case .review: return "Repasos"
        case .web: return "Búsquedas"
        case .reminders: return "Recordatorios"
        }
    }

    var explanation: String {
        switch self {
        case .study: return "Sesiones, material y dudas pendientes."
        case .calendar: return "Huecos reales entre eventos."
        case .tasks: return "Tareas que se repiten o se atascan."
        case .mail: return "Correos sin responder."
        case .waiting: return "Asuntos que dependen de otra persona."
        case .review: return "Conceptos que toca repasar."
        case .web: return "Cuando conviene contrastar fuera."
        case .reminders: return "Avisos en el momento adecuado."
        }
    }

    var symbolName: String {
        switch self {
        case .study: return "book"
        case .calendar: return "calendar"
        case .tasks: return "checkmark.circle"
        case .mail: return "envelope"
        case .waiting: return "hourglass"
        case .review: return "arrow.clockwise"
        case .web: return "globe"
        case .reminders: return "bell"
        }
    }
}

/// The intervention ladder. SinRutina picks a rung by receptivity and importance,
/// never by frustration: being ignored does not escalate anything.
nonisolated enum SRInterventionLevel: Int, Codable, CaseIterable, Sendable, Comparable {
    case silent = 0
    case widget = 1
    case suggestion = 2
    case notification = 3
    case important = 4
    case unmissable = 5

    static func < (lhs: SRInterventionLevel, rhs: SRInterventionLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    var label: String {
        switch self {
        case .silent: return "Silencioso"
        case .widget: return "Widget"
        case .suggestion: return "Sugerencia"
        case .notification: return "Notificación"
        case .important: return "Importante"
        case .unmissable: return "No me dejes olvidarlo"
        }
    }

    /// Only the two lowest rungs are free: everything above spends budget.
    var spendsBudget: Bool { self >= .suggestion }

    var ceiling: SRInterventionLevel {
        self == .unmissable ? .unmissable : .important
    }
}

/// The four voices SinRutina tries out. The winner is learned locally, quietly.
nonisolated enum SRMessageStyle: String, Codable, CaseIterable, Sendable, Identifiable {
    case direct
    case collaborative
    case minimal
    case unstick

    var id: String { rawValue }

    var label: String {
        switch self {
        case .direct: return "Directo"
        case .collaborative: return "Colaborativo"
        case .minimal: return "Minimalista"
        case .unstick: return "Desatascar"
        }
    }

    /// Builds the sentence. Never guilt, never exclamation marks.
    func message(title: String, minutes: Int, availableMinutes: Int?) -> String {
        switch self {
        case .direct:
            if let availableMinutes {
                return "Tienes \(availableMinutes) minutos. Haz esta ahora."
            }
            return "Esta se puede hacer ya. \(minutes) min."
        case .collaborative:
            if let availableMinutes {
                return "Esta cabe en tus \(availableMinutes) minutos. ¿La hacemos?"
            }
            return "Esta cabe ahora. ¿La hacemos?"
        case .minimal:
            return "\(title) · \(minutes) min"
        case .unstick:
            return "Hagamos solo el primer paso."
        }
    }
}

/// One thing SinRutina said, and what happened next. Stored locally so timing
/// and wording can improve without any server.
nonisolated struct SRInterventionRecord: Codable, Hashable, Sendable, Identifiable {
    nonisolated enum Outcome: String, Codable, Sendable {
        case pending
        case started
        case postponed
        case ignored
        case dismissed
    }

    var id: UUID
    var domain: SRProactivityDomain
    var level: SRInterventionLevel
    var style: SRMessageStyle
    var taskID: String?
    var createdAt: Date
    var outcome: Outcome
    var minutesToAction: Double?

    init(
        id: UUID = UUID(),
        domain: SRProactivityDomain,
        level: SRInterventionLevel,
        style: SRMessageStyle,
        taskID: String? = nil,
        createdAt: Date = Date(),
        outcome: Outcome = .pending,
        minutesToAction: Double? = nil
    ) {
        self.id = id
        self.domain = domain
        self.level = level
        self.style = style
        self.taskID = taskID
        self.createdAt = createdAt
        self.outcome = outcome
        self.minutesToAction = minutesToAction
    }

    var wasUseful: Bool { outcome == .started }
}

/// Reads the recent history and answers one question: may SinRutina speak now?
///
/// The budget exists so the app prefers one useful interruption over several
/// mediocre ones.
nonisolated struct SRInterruptionBudget: Sendable {
    var level: SRProactivityLevel
    var records: [SRInterventionRecord]
    var now: Date

    init(level: SRProactivityLevel, records: [SRInterventionRecord], now: Date = Date()) {
        self.level = level
        self.records = records
        self.now = now
    }

    private var todaysSpending: [SRInterventionRecord] {
        records.filter { Calendar.current.isDate($0.createdAt, inSameDayAs: now) && $0.level.spendsBudget }
    }

    var spentToday: Int { todaysSpending.count }

    var remainingToday: Int { max(0, level.dailyBudget - spentToday) }

    var lastInterruption: Date? {
        todaysSpending.map(\.createdAt).max()
    }

    var minutesSinceLastInterruption: Double? {
        guard let lastInterruption else { return nil }
        return now.timeIntervalSince(lastInterruption) / 60
    }

    /// Share of recent interruptions the person walked past.
    var ignoredRatio: Double {
        let recent = records
            .filter { $0.level.spendsBudget && now.timeIntervalSince($0.createdAt) < 7 * 86_400 }
            .suffix(12)
        guard recent.count >= 3 else { return 0 }
        let ignored = recent.filter { $0.outcome == .ignored || $0.outcome == .dismissed }.count
        return Double(ignored) / Double(recent.count)
    }

    /// A quiet hour is never a good time, whatever the budget says.
    private var isQuietHour: Bool {
        let hour = Calendar.current.component(.hour, from: now)
        return hour < 8 || hour >= 22
    }

    func allows(level requested: SRInterventionLevel) -> Bool {
        guard requested.spendsBudget else { return true }
        if requested == .unmissable { return true }
        if isQuietHour { return false }
        guard remainingToday > 0 else { return false }
        if let gap = minutesSinceLastInterruption, gap < Double(level.minimumGapMinutes) {
            return false
        }
        // Somebody who keeps walking past gets asked less, not more.
        if ignoredRatio > 0.6, requested >= .notification { return false }
        return true
    }
}

/// How likely the person is to act right now. Never shown: it only decides
/// whether SinRutina stays quiet, nudges the widget, or speaks.
nonisolated struct SRReceptivityScore: Sendable {
    var value: Double
    var reasons: [String]

    static let unknown = SRReceptivityScore(value: 0.5, reasons: [])

    /// - Parameters:
    ///   - hour: current hour of day.
    ///   - hourlyCompletions: how often work actually finished at each hour.
    ///   - availableMinutes: free minutes before the next commitment.
    ///   - taskMinutes: what the candidate task needs.
    ///   - isInFocus: an iOS Focus mode is on.
    ///   - hasRunningTask: something is already in progress.
    ///   - ignoredRatio: share of recent interruptions walked past.
    static func compute(
        hour: Int,
        hourlyCompletions: [Int],
        availableMinutes: Int?,
        taskMinutes: Int,
        isInFocus: Bool,
        hasRunningTask: Bool,
        ignoredRatio: Double
    ) -> SRReceptivityScore {
        var value = 0.5
        var reasons: [String] = []

        // Real evidence beats assumptions: hours where things got finished.
        if hourlyCompletions.count == 24 {
            let total = hourlyCompletions.reduce(0, +)
            if total >= 4 {
                let share = Double(hourlyCompletions[min(max(hour, 0), 23)]) / Double(total)
                value += min(share * 3.2, 0.28)
                if share > 0.12 { reasons.append("suele empezar a esta hora") }
            }
        }

        if let availableMinutes {
            if availableMinutes >= taskMinutes {
                value += 0.2
                reasons.append("la tarea cabe en el hueco")
            } else if availableMinutes < max(5, taskMinutes / 3) {
                value -= 0.3
                reasons.append("apenas hay hueco")
            }
        }

        if hasRunningTask {
            value -= 0.45
            reasons.append("ya hay algo en marcha")
        }
        if isInFocus {
            value -= 0.25
            reasons.append("hay un modo de concentración activo")
        }
        value -= min(ignoredRatio * 0.35, 0.35)

        return SRReceptivityScore(value: min(max(value, 0), 1), reasons: reasons)
    }

    /// The highest rung this receptivity justifies.
    func suggestedLevel(importance: SRInterventionLevel) -> SRInterventionLevel {
        if importance == .unmissable { return .unmissable }
        switch value {
        case ..<0.3: return .silent
        case ..<0.45: return .widget
        case ..<0.68: return min(.suggestion, importance)
        default: return min(importance, .important)
        }
    }
}

/// Everything the person decided about being interrupted, kept in the app group
/// so widget and extensions read the same rules.
@Observable
final class SRProactivityPreferences {
    static let shared = SRProactivityPreferences()

    private(set) var level: SRProactivityLevel
    private(set) var disabledDomains: Set<SRProactivityDomain>
    private(set) var records: [SRInterventionRecord]

    private init() {
        let defaults = SRShared.defaults
        if let raw = defaults.string(forKey: SRShared.Key.proactivityLevel),
           let stored = SRProactivityLevel(rawValue: raw) {
            level = stored
        } else {
            level = .balanced
        }
        let rawDomains = defaults.stringArray(forKey: SRShared.Key.proactivityDisabledDomains) ?? []
        disabledDomains = Set(rawDomains.compactMap(SRProactivityDomain.init(rawValue:)))
        records = Self.loadRecords()
    }

    func isEnabled(_ domain: SRProactivityDomain) -> Bool {
        !disabledDomains.contains(domain)
    }

    func setEnabled(_ isEnabled: Bool, for domain: SRProactivityDomain) {
        if isEnabled {
            disabledDomains.remove(domain)
        } else {
            disabledDomains.insert(domain)
        }
        SRShared.defaults.set(disabledDomains.map(\.rawValue), forKey: SRShared.Key.proactivityDisabledDomains)
    }

    func setLevel(_ newLevel: SRProactivityLevel) {
        level = newLevel
        SRShared.defaults.set(newLevel.rawValue, forKey: SRShared.Key.proactivityLevel)
    }

    var budget: SRInterruptionBudget {
        SRInterruptionBudget(level: level, records: records)
    }

    /// Records that SinRutina spoke. Only the last 60 entries are kept.
    func log(_ record: SRInterventionRecord) {
        records.append(record)
        if records.count > 60 { records.removeFirst(records.count - 60) }
        persistRecords()
    }

    func resolve(id: UUID, outcome: SRInterventionRecord.Outcome, minutesToAction: Double? = nil) {
        guard let index = records.firstIndex(where: { $0.id == id }) else { return }
        records[index].outcome = outcome
        records[index].minutesToAction = minutesToAction
        persistRecords()
    }

    /// Anything still pending after two hours was, in practice, ignored.
    func closeStaleRecords(now: Date = Date()) {
        var changed = false
        for index in records.indices where records[index].outcome == .pending {
            if now.timeIntervalSince(records[index].createdAt) > 7_200 {
                records[index].outcome = .ignored
                changed = true
            }
        }
        if changed { persistRecords() }
    }

    /// How many times in a row a given task's suggestion was walked past.
    func ignoredStreak(taskID: String) -> Int {
        var streak = 0
        for record in records.reversed() where record.taskID == taskID {
            if record.outcome == .ignored || record.outcome == .dismissed {
                streak += 1
            } else if record.outcome == .started {
                break
            }
        }
        return streak
    }

    /// The wording that actually led to starting, with a light exploration bias
    /// so a style that was never tried still gets a turn.
    func bestStyle(default fallback: SRMessageStyle = .collaborative) -> SRMessageStyle {
        var starts: [SRMessageStyle: Int] = [:]
        var shows: [SRMessageStyle: Int] = [:]
        for record in records.suffix(40) {
            shows[record.style, default: 0] += 1
            if record.wasUseful { starts[record.style, default: 0] += 1 }
        }
        if let untried = SRMessageStyle.allCases.first(where: { (shows[$0] ?? 0) == 0 }) {
            return untried
        }
        let ranked = SRMessageStyle.allCases.max { lhs, rhs in
            rate(starts: starts, shows: shows, style: lhs) < rate(starts: starts, shows: shows, style: rhs)
        }
        return ranked ?? fallback
    }

    private func rate(
        starts: [SRMessageStyle: Int],
        shows: [SRMessageStyle: Int],
        style: SRMessageStyle
    ) -> Double {
        let shown = Double(shows[style] ?? 0)
        guard shown > 0 else { return 0 }
        return Double(starts[style] ?? 0) / shown
    }

    private func persistRecords() {
        guard let data = try? JSONEncoder().encode(records) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.interventionLog)
    }

    private static func loadRecords() -> [SRInterventionRecord] {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.interventionLog),
              let decoded = try? JSONDecoder().decode([SRInterventionRecord].self, from: data) else {
            return []
        }
        return decoded
    }
}
