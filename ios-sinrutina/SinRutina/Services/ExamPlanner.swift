import Foundation
import SwiftData

/// Spreads study work over the days before an exam or a delivery.
///
/// It proposes; it never creates several calendar events on its own. Every session
/// is a row the person can accept or drop, and skipping one reshapes the rest
/// instead of piling it up.
@MainActor
enum ExamPlanner {

    /// One proposed sitting.
    struct Session: Identifiable, Hashable {
        var id: Date { start }
        var start: Date
        var minutes: Int
        var focus: String
        /// True when the session only exists because the deadline is close.
        var isCrunch: Bool

        var dayLabel: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_ES")
            if Calendar.current.isDateInToday(start) { return "Hoy" }
            if Calendar.current.isDateInTomorrow(start) { return "Mañana" }
            formatter.dateFormat = "EEEE d"
            return formatter.string(from: start).capitalized
        }

        var timeLabel: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_ES")
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: start)
        }
    }

    /// A whole proposal, with the honest picture of whether it actually fits.
    struct Plan {
        var sessions: [Session]
        var deadline: Date
        var totalMinutes: Int
        /// Minutes the material needs that did not fit before the deadline.
        var unplacedMinutes: Int

        var isOverloaded: Bool { unplacedMinutes > 0 }

        var summary: String {
            let days = Set(sessions.map { Calendar.current.startOfDay(for: $0.start) }).count
            if sessions.isEmpty { return "No encontré huecos antes de la fecha." }
            return "\(sessions.count) sesiones en \(days) \(days == 1 ? "día" : "días")."
        }
    }

    /// Builds the proposal for a study task with a date.
    /// - Parameter materialMinutes: reading time of the attached material, when known.
    static func plan(
        for task: TaskItem,
        materialMinutes: Int?,
        now: Date = Date()
    ) -> Plan? {
        guard let deadline = task.dueDate, deadline > now else { return nil }

        let sessionLength = max(
            10,
            min(
                LearningEngine.preferredStudyMinutes ?? LearningEngine.preferredSessionMinutes ?? 25,
                50
            )
        )
        // What is left to cover: the material if we know it, the estimate otherwise.
        var remaining = max(sessionLength, materialMinutes ?? task.estimatedMinutes)
        remaining = max(0, remaining - Int(task.studiedMinutes))
        guard remaining > 0 else { return nil }

        // A day of rest before the date, when there is room for it.
        let softDeadline = deadline.timeIntervalSince(now) > 3 * 86_400
            ? deadline.addingTimeInterval(-86_400)
            : deadline

        var sessions: [Session] = []
        var cursor = now.addingTimeInterval(900)
        var placedPerDay: [Date: Int] = [:]
        // Two sittings a day is the ceiling: more is how plans get abandoned.
        let dailyCeiling = 2

        while remaining > 0, cursor < softDeadline, sessions.count < 14 {
            guard let window = CalendarService.shared.freeWindow(from: cursor, horizonHours: 24) else {
                cursor = cursor.addingTimeInterval(6 * 3_600)
                continue
            }
            let day = Calendar.current.startOfDay(for: window.start)
            let hour = Calendar.current.component(.hour, from: window.start)

            let alreadyPlaced = placedPerDay[day] ?? 0
            let isReasonable = hour >= 8 && hour < 22
            let isPreferredHour = LearningEngine.preferredHour.map { abs(hour - $0) <= 2 } ?? true
            let fits = window.minutes >= min(sessionLength, remaining)

            if isReasonable, fits, alreadyPlaced < dailyCeiling, window.start < softDeadline {
                let minutes = min(sessionLength, remaining, window.minutes)
                sessions.append(
                    Session(
                        start: window.start,
                        minutes: minutes,
                        focus: focusLine(index: sessions.count, task: task, isFirst: sessions.isEmpty),
                        isCrunch: !isPreferredHour
                    )
                )
                placedPerDay[day] = alreadyPlaced + 1
                remaining -= minutes
                cursor = window.start.addingTimeInterval(Double(minutes + 15) * 60)
            } else {
                cursor = window.end.addingTimeInterval(600)
            }
        }

        guard !sessions.isEmpty || remaining > 0 else { return nil }
        return Plan(
            sessions: sessions,
            deadline: deadline,
            totalMinutes: sessions.reduce(0) { $0 + $1.minutes },
            unplacedMinutes: max(0, remaining)
        )
    }

    /// Reshapes what is left when a session was skipped, without doubling anything.
    static func replan(for task: TaskItem, materialMinutes: Int?, now: Date = Date()) -> Plan? {
        plan(for: task, materialMinutes: materialMinutes, now: now)
    }

    /// Turns one accepted session into a task in "Después". Calendar events are a
    /// separate, explicit decision.
    @discardableResult
    static func accept(
        _ session: Session,
        for task: TaskItem,
        context: ModelContext
    ) -> TaskItem {
        let child = TaskItem(
            title: session.focus,
            detail: "Sesión de \(task.title)",
            estimatedMinutes: session.minutes,
            state: .after,
            dueDate: task.dueDate,
            availableFrom: session.start,
            source: "sesión de estudio"
        )
        child.preferredContext = "estudio"
        child.studyObjective = task.studyObjective
        child.sourceModeRaw = task.sourceModeRaw
        child.nextStep = session.focus
        child.insistence = task.insistence == .unmissable ? .important : task.insistence
        child.remindAt = session.start
        context.insert(child)
        try? context.save()
        Task { await InsistenceScheduler.shared.schedule(for: child) }
        SRTaskCommands.refreshOutsideSurfaces(context: context)
        return child
    }

    private static func focusLine(index: Int, task: TaskItem, isFirst: Bool) -> String {
        let base = task.title
            .replacingOccurrences(of: "Estudiar ", with: "")
            .replacingOccurrences(of: "estudiar ", with: "")
        if isFirst { return "Empezar \(base)" }
        return "Sesión \(index + 1) de \(base)"
    }
}
