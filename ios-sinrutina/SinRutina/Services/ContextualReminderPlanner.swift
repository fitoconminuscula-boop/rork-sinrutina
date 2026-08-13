import Foundation
import SwiftData

/// Turns "avísame cuando tenga un hueco" into an actual moment.
///
/// It reads the calendar, the deadline, the duration, how often the task has been
/// postponed and when this person historically starts things — then proposes one
/// slot. It never writes to the calendar and never schedules without a decision.
@MainActor
enum ContextualReminderPlanner {

    /// A moment SinRutina believes is a good one, with the reason spelled out.
    struct Slot: Identifiable, Hashable {
        var id: Date { start }
        var start: Date
        var minutes: Int
        var reason: String
        /// True when the deadline forces the slot rather than the calendar choosing it.
        var isDeadlineDriven: Bool

        var label: String {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "es_ES")
            formatter.calendar = Calendar.current
            if Calendar.current.isDateInToday(start) {
                formatter.dateFormat = "'hoy a las' HH:mm"
            } else if Calendar.current.isDateInTomorrow(start) {
                formatter.dateFormat = "'mañana a las' HH:mm"
            } else {
                formatter.dateFormat = "EEEE d 'a las' HH:mm"
            }
            return formatter.string(from: start)
        }
    }

    /// Detects the phrasing that means "you decide when".
    static func wantsContextualTiming(_ text: String) -> Bool {
        let lower = SRHeuristics.normalized(text)
        let markers = [
            "cuando tenga un hueco", "cuando tenga tiempo", "cuando pueda",
            "cuando haya un rato", "cuando encuentre un momento", "dime cuando",
            "cuando convenga", "en algun hueco", "algun hueco", "cuando veas"
        ]
        return markers.contains { lower.contains(SRHeuristics.normalized($0)) }
    }

    /// Proposes the best next moment for a task, or nil when nothing fits.
    static func proposeSlot(
        for task: TaskItem,
        profile: BehaviorProfile?,
        now: Date = Date()
    ) -> Slot? {
        let needed = max(5, task.estimatedMinutes)
        let calendar = Calendar.current

        // 1. A window that starts right now, if it is genuinely big enough.
        if let window = CalendarService.shared.freeWindow(from: now, horizonHours: 12),
           window.minutes >= needed,
           window.start.timeIntervalSince(now) < 3_600 {
            let start = max(window.start, now.addingTimeInterval(300))
            return Slot(
                start: start,
                minutes: min(window.minutes, needed),
                reason: "Tienes \(window.minutes) minutos libres antes de lo siguiente.",
                isDeadlineDriven: false
            )
        }

        // 2. The next real gap in the calendar over the following day.
        if let window = nextGap(minimumMinutes: needed, from: now.addingTimeInterval(900)) {
            return Slot(
                start: window.start,
                minutes: min(window.minutes, needed),
                reason: "Es el primer hueco de \(needed) minutos que encuentro.",
                isDeadlineDriven: false
            )
        }

        // 3. The hour where this person actually starts things.
        if let hour = profile?.mostProductiveHour,
           let candidate = nextOccurrence(ofHour: hour, after: now.addingTimeInterval(1_800), calendar: calendar) {
            if let due = task.dueDate, candidate > due {
                return deadlineSlot(for: task, due: due, now: now)
            }
            return Slot(
                start: candidate,
                minutes: needed,
                reason: "Suele funcionarte empezar a esta hora.",
                isDeadlineDriven: false
            )
        }

        // 4. The deadline decides.
        if let due = task.dueDate {
            return deadlineSlot(for: task, due: due, now: now)
        }
        return nil
    }

    /// A slot that exists because something is due, placed before the pressure.
    private static func deadlineSlot(for task: TaskItem, due: Date, now: Date) -> Slot? {
        let buffer = TimeInterval(max(task.estimatedMinutes * 60 * 2, 3_600))
        let candidate = due.addingTimeInterval(-buffer)
        guard candidate > now else {
            return Slot(
                start: now.addingTimeInterval(600),
                minutes: max(5, task.estimatedMinutes),
                reason: "La fecha límite ya está encima.",
                isDeadlineDriven: true
            )
        }
        return Slot(
            start: candidate,
            minutes: max(5, task.estimatedMinutes),
            reason: "Deja margen antes de la fecha límite.",
            isDeadlineDriven: true
        )
    }

    /// Walks the upcoming events looking for the first gap big enough.
    private static func nextGap(minimumMinutes: Int, from date: Date) -> SRFreeWindow? {
        var cursor = date
        for _ in 0..<8 {
            guard let window = CalendarService.shared.freeWindow(from: cursor, horizonHours: 24) else { return nil }
            if window.minutes >= minimumMinutes, isReasonableHour(window.start) {
                return window
            }
            cursor = window.end.addingTimeInterval(600)
        }
        return nil
    }

    private static func nextOccurrence(ofHour hour: Int, after date: Date, calendar: Calendar) -> Date? {
        guard let today = calendar.date(bySettingHour: hour, minute: 0, second: 0, of: date) else { return nil }
        if today > date { return today }
        return calendar.date(byAdding: .day, value: 1, to: today)
    }

    /// Nobody wants a nudge at four in the morning, whatever the calendar says.
    private static func isReasonableHour(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return hour >= 8 && hour < 22
    }

    /// Applies a proposed slot as the task's reminder, keeping the insistence level.
    static func apply(_ slot: Slot, to task: TaskItem, context: ModelContext) {
        task.wantsContextualReminder = true
        task.proposedSlotStart = slot.start
        SRTaskCommands.setInsistence(
            task.insistence == .gentle ? .gentle : task.insistence,
            remindAt: slot.start,
            for: task,
            context: context
        )
    }

    /// Re-proposes a moment when a slot passed without anything happening.
    static func reschedule(_ task: TaskItem, profile: BehaviorProfile?, context: ModelContext) -> Slot? {
        guard task.wantsContextualReminder else { return nil }
        guard let slot = proposeSlot(for: task, profile: profile, now: Date().addingTimeInterval(600)) else {
            return nil
        }
        apply(slot, to: task, context: context)
        return slot
    }
}
