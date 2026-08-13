import Foundation

/// The single task the widget shows. The app writes it; the widget only reads.
/// Keeping the widget away from the database avoids stale locks and keeps
/// refreshes cheap.
nonisolated struct SRWidgetSnapshot: Codable, Hashable, Sendable {
    /// Drives composition, wording and iconography — not only colour.
    enum Tone: String, Codable, Sendable {
        /// Nothing pending: a calm, quiet card.
        case empty
        /// There is something, but it is not its turn yet.
        case upcoming
        /// This is the task to do now.
        case current
        /// The moment already passed.
        case overdue
        /// The person asked for the reduced mode.
        case saturated
        /// A session is happening right now: the widget shows only that.
        case running
    }

    var taskID: String?
    var title: String
    var estimatedMinutes: Int
    var tone: Tone
    var nextStep: String?
    var availableFrom: Date?
    var dueDate: Date?
    var openCount: Int
    var waitingCount: Int
    /// Minutes free before the next commitment, for the contextual widget style.
    var availableMinutes: Int?
    var nextEventTitle: String?
    /// When the running stretch started, so the widget can count without pushes.
    var runningSince: Date?
    /// Minutes already spent, for a paused session or a stale timeline.
    var runningMinutes: Int?
    var isPausedSession: Bool?
    var updatedAt: Date

    init(
        taskID: String? = nil,
        title: String,
        estimatedMinutes: Int = 10,
        tone: Tone = .empty,
        nextStep: String? = nil,
        availableFrom: Date? = nil,
        dueDate: Date? = nil,
        openCount: Int = 0,
        waitingCount: Int = 0,
        availableMinutes: Int? = nil,
        nextEventTitle: String? = nil,
        runningSince: Date? = nil,
        runningMinutes: Int? = nil,
        isPausedSession: Bool? = nil,
        updatedAt: Date = Date()
    ) {
        self.taskID = taskID
        self.title = title
        self.estimatedMinutes = estimatedMinutes
        self.tone = tone
        self.nextStep = nextStep
        self.availableFrom = availableFrom
        self.dueDate = dueDate
        self.openCount = openCount
        self.waitingCount = waitingCount
        self.availableMinutes = availableMinutes
        self.nextEventTitle = nextEventTitle
        self.runningSince = runningSince
        self.runningMinutes = runningMinutes
        self.isPausedSession = isPausedSession
        self.updatedAt = updatedAt
    }

    static let placeholder = SRWidgetSnapshot(
        title: "Nada urgente ahora",
        estimatedMinutes: 0,
        tone: .empty
    )

    /// Recomputed at render time so a stale timeline still shows honest wording.
    func tone(at date: Date) -> Tone {
        switch tone {
        case .empty, .saturated, .running:
            return tone
        default:
            break
        }
        if let dueDate, dueDate < date { return .overdue }
        if let availableFrom, availableFrom > date { return .upcoming }
        return .current
    }

    /// Short label describing the state, so the widget never relies on colour alone.
    func statusLabel(at date: Date) -> String {
        switch tone(at: date) {
        case .empty: return "Todo tranquilo"
        case .saturated: return "Modo saturado"
        case .running: return isPausedSession == true ? "En pausa" : "En curso"
        case .upcoming:
            guard let availableFrom else { return "Todavía no" }
            return "A partir de \(SRWidgetSnapshot.timeFormatter.string(from: availableFrom))"
        case .current: return "Te toca ahora"
        case .overdue: return "Se pasó la hora"
        }
    }

    func statusSymbol(at date: Date) -> String {
        switch tone(at: date) {
        case .empty: return "checkmark.circle"
        case .saturated: return "sparkles"
        case .running: return isPausedSession == true ? "pause.circle.fill" : "circle.dashed.inset.filled"
        case .upcoming: return "clock"
        case .current: return "arrow.right.circle.fill"
        case .overdue: return "exclamationmark.circle.fill"
        }
    }

    /// "En curso · 7 min" while a session is happening.
    func sessionLabel(at date: Date) -> String? {
        guard tone == .running else { return nil }
        let minutes: Int
        if let runningSince, isPausedSession != true {
            minutes = (runningMinutes ?? 0) + max(0, Int(date.timeIntervalSince(runningSince) / 60))
        } else {
            minutes = runningMinutes ?? 0
        }
        let state = isPausedSession == true ? "En pausa" : "En curso"
        return minutes <= 0 ? state : "\(state) · \(minutes) min"
    }

    /// Free time before the next commitment, worded for a very small space.
    var contextLabel: String? {
        guard let availableMinutes, availableMinutes > 0 else { return nil }
        if let nextEventTitle, !nextEventTitle.isEmpty {
            return "\(availableMinutes) min antes de \(nextEventTitle)"
        }
        return "\(availableMinutes) min libres"
    }

    static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()
}

nonisolated enum SRWidgetStore {
    static func write(_ snapshot: SRWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.widgetSnapshot)
    }

    static func read() -> SRWidgetSnapshot? {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.widgetSnapshot) else { return nil }
        return try? JSONDecoder().decode(SRWidgetSnapshot.self, from: data)
    }
}
