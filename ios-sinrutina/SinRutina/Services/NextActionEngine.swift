import Foundation

/// Deterministic, local recommendation logic. It never returns a waiting item.
///
/// The engine now also knows how much real time the person has before their next
/// commitment, so it will not propose a 90 minute task 24 minutes before a meeting.
struct NextActionEngine {
    /// Minutes available before the next calendar event. Nil means "no limit known".
    var availableMinutes: Int?
    /// Title of the event that closes the window, used only for wording.
    var nextEventTitle: String?
    /// Minutes left before the preparation window of a real departure opens.
    /// A task must not invade the time needed to get ready and leave.
    var minutesBeforeDeparturePrep: Int?
    /// Where that departure goes, used only for wording.
    var departureLabel: String?

    init(
        availableMinutes: Int? = nil,
        nextEventTitle: String? = nil,
        minutesBeforeDeparturePrep: Int? = nil,
        departureLabel: String? = nil
    ) {
        self.availableMinutes = availableMinutes
        self.nextEventTitle = nextEventTitle
        self.minutesBeforeDeparturePrep = minutesBeforeDeparturePrep
        self.departureLabel = departureLabel
    }

    /// The real window: the tighter of the calendar gap and the departure.
    var effectiveMinutes: Int? {
        switch (availableMinutes, minutesBeforeDeparturePrep) {
        case let (calendarMinutes?, departureMinutes?): return min(calendarMinutes, departureMinutes)
        case let (calendarMinutes?, nil): return calendarMinutes
        case let (nil, departureMinutes?): return departureMinutes
        case (nil, nil): return nil
        }
    }

    func recommendations(from tasks: [TaskItem], now: Date = Date()) -> [TaskItem] {
        let candidates = tasks.filter { task in
            guard task.state != .completed, task.state != .waiting else { return false }
            if let availableFrom = task.availableFrom, availableFrom > now { return false }
            return true
        }

        // Anything that does not fit the free window goes to the back rather than
        // disappearing: the person must still be able to reach it.
        let sorted = candidates.sorted { lhs, rhs in
            score(lhs, now: now) > score(rhs, now: now)
        }
        guard let window = effectiveMinutes, window > 0 else { return sorted }
        let fitting = sorted.filter { fits($0, in: window) }
        let notFitting = sorted.filter { !fits($0, in: window) }
        return fitting + notFitting
    }

    /// A task fits when it can be finished, or at least meaningfully started,
    /// before the next commitment.
    func fits(_ task: TaskItem, in minutes: Int) -> Bool {
        task.estimatedMinutes <= max(5, minutes)
    }

    func score(_ task: TaskItem, now: Date = Date()) -> Double {
        var value: Double = 0
        if task.state == .now { value += 320 }
        if task.state == .after { value += 90 }
        if task.state == .someday { value += 10 }
        if let dueDate = task.dueDate {
            let days = dueDate.timeIntervalSince(now) / 86_400
            if days < 0 {
                value += 1_000 + min(abs(days) * 25, 500)
            } else {
                value += max(0, 260 - days * 32)
            }
        }
        if task.estimatedMinutes <= 15 { value += 70 }
        if task.estimatedMinutes <= 5 { value += 22 }
        value += Double(task.procrastinationCount) * 36
        if task.isCurrent { value += 80 }
        if let availableFrom = task.availableFrom, availableFrom > now {
            value -= 10_000
        }

        // Real pressure, from the calendar or from a departure: prefer what fits.
        if let window = effectiveMinutes, window > 0 {
            if task.estimatedMinutes <= window {
                let slack = Double(window - task.estimatedMinutes)
                value += 140 - min(slack, 120)
            } else {
                value -= 420
            }
        }

        switch task.insistence {
        case .unmissable: value += 180
        case .important: value += 90
        case .normal: break
        case .gentle: value -= 30
        }
        return value
    }

    func microStep(for task: TaskItem) -> String {
        if let nextStep = task.nextStep, !nextStep.isEmpty { return nextStep }
        let lower = SRHeuristics.normalized(task.title)
        return SRHeuristics.nextStep(for: task.title, lower: lower, context: task.preferredContext)
    }

    /// A calm sentence explaining what is shaping the recommendation.
    var timeContextLabel: String? {
        // A departure is the tighter, more concrete limit, so it is named first.
        if let departureMinutes = minutesBeforeDeparturePrep,
           departureMinutes > 0,
           departureMinutes <= (availableMinutes ?? Int.max) {
            if let departureLabel, !departureLabel.isEmpty {
                return "\(departureMinutes) min antes de prepararte para \(departureLabel)"
            }
            return "\(departureMinutes) min antes de empezar a prepararte"
        }
        guard let availableMinutes, availableMinutes > 0 else { return nil }
        if let nextEventTitle, !nextEventTitle.isEmpty {
            return "\(availableMinutes) min libres antes de \(nextEventTitle)"
        }
        return "\(availableMinutes) min libres antes de lo siguiente"
    }
}

/// Kept as a thin bridge so existing call sites keep working, now backed by the
/// shared deterministic reader.
enum QuickCaptureParser {
    static func title(from rawText: String) -> String {
        SRHeuristics.shortTitle(from: rawText)
    }

    static func estimatedMinutes(from text: String) -> Int {
        let lower = SRHeuristics.normalized(text)
        return SRHeuristics.detectMinutes(lower, context: SRHeuristics.detectContext(lower))
    }
}
