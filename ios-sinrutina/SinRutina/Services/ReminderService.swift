import EventKit
import Foundation
import Observation

/// A Reminders list as iOS exposes it.
struct SRReminderList: Identifiable, Hashable {
    let id: String
    let title: String
    let accountName: String
    let isWritable: Bool
}

/// A reminder proposed for import. Nothing is created in SinRutina until the
/// person accepts it.
struct SRImportableReminder: Identifiable, Hashable {
    let id: String
    let title: String
    let dueDate: Date?
    let listTitle: String
    let notes: String?
    /// True when a TaskItem already points at this reminder.
    var isAlreadyLinked: Bool
}

/// EventKit wrapper for Recordatorios.
///
/// Linking strategy — this is the rule that stops SinRutina from becoming a
/// second, contradictory database:
/// * A `TaskItem` may hold exactly one `reminderIdentifier`.
/// * Import creates a TaskItem *linked* to the reminder; it never copies it twice
///   because `isAlreadyLinked` filters anything already referenced.
/// * Completing on either side propagates once, in one direction at a time:
///   completing in SinRutina completes the reminder; a reminder already completed
///   in Apple's app is simply not offered for import.
/// * Deleting a TaskItem never deletes the reminder. Apple Reminders stays the
///   owner of its own data.
@MainActor
@Observable
final class ReminderService {
    static let shared = ReminderService()

    private let store = EKEventStore()
    private let preferences = CalendarPreferences.shared

    private(set) var access: SRCalendarAccess = .notDetermined
    private(set) var lists: [SRReminderList] = []
    private(set) var lastErrorMessage: String?

    private init() {
        refreshAccessState()
    }

    // MARK: - Permissions

    func refreshAccessState() {
        switch EKEventStore.authorizationStatus(for: .reminder) {
        case .notDetermined: access = .notDetermined
        case .denied: access = .denied
        case .restricted: access = .restricted
        case .fullAccess, .authorized: access = .granted
        case .writeOnly: access = .writeOnly
        @unknown default: access = .notDetermined
        }
    }

    @discardableResult
    func requestAccess() async -> SRCalendarAccess {
        do {
            _ = try await store.requestFullAccessToReminders()
        } catch {
            lastErrorMessage = "iOS no pudo abrir Recordatorios."
        }
        refreshAccessState()
        if access.canRead { loadLists() }
        return access
    }

    // MARK: - Lists

    func loadLists() {
        guard access.canRead || access.canWrite else {
            lists = []
            return
        }
        lists = store.calendars(for: .reminder)
            .map {
                SRReminderList(
                    id: $0.calendarIdentifier,
                    title: $0.title,
                    accountName: $0.source?.title ?? "Este iPhone",
                    isWritable: $0.allowsContentModifications
                )
            }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }

        if preferences.remindersListIdentifier == nil {
            preferences.setRemindersList(store.defaultCalendarForNewReminders()?.calendarIdentifier)
        }
    }

    // MARK: - Reading

    /// Open reminders that SinRutina could adopt, excluding anything already linked.
    func importableReminders(linkedIdentifiers: Set<String>) async -> [SRImportableReminder] {
        guard access.canRead else { return [] }
        let calendars = store.calendars(for: .reminder)
        guard !calendars.isEmpty else { return [] }
        let predicate = store.predicateForIncompleteReminders(
            withDueDateStarting: nil,
            ending: nil,
            calendars: calendars
        )

        let reminders: [EKReminder] = await withCheckedContinuation { continuation in
            store.fetchReminders(matching: predicate) { found in
                continuation.resume(returning: found ?? [])
            }
        }

        return reminders
            .compactMap { reminder in
                let identifier = reminder.calendarItemIdentifier
                guard !identifier.isEmpty else { return nil }
                return SRImportableReminder(
                    id: identifier,
                    title: reminder.title ?? "Recordatorio",
                    dueDate: reminder.dueDateComponents?.date,
                    listTitle: reminder.calendar?.title ?? "Recordatorios",
                    notes: reminder.notes,
                    isAlreadyLinked: linkedIdentifiers.contains(identifier)
                )
            }
            .sorted { lhs, rhs in
                switch (lhs.dueDate, rhs.dueDate) {
                case let (left?, right?): return left < right
                case (nil, _?): return false
                case (_?, nil): return true
                default: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                }
            }
    }

    // MARK: - Writing

    /// Creates a reminder in Apple Reminders and returns its identifier so the
    /// TaskItem can hold the link.
    @discardableResult
    func createReminder(title: String, dueDate: Date?, notes: String?, listIdentifier: String? = nil) throws -> String {
        guard access.canWrite else { throw SRReminderError.noPermission }
        let identifier = listIdentifier ?? preferences.remindersListIdentifier
        let calendar: EKCalendar? = {
            if let identifier, let found = store.calendar(withIdentifier: identifier), found.allowsContentModifications {
                return found
            }
            return store.defaultCalendarForNewReminders()
        }()
        guard let calendar else { throw SRReminderError.noWritableList }

        let reminder = EKReminder(eventStore: store)
        reminder.calendar = calendar
        reminder.title = title
        reminder.notes = notes
        if let dueDate {
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute],
                from: dueDate
            )
        }
        try store.save(reminder, commit: true)
        return reminder.calendarItemIdentifier
    }

    /// Marks the linked reminder as done. Silently no-ops when the reminder is gone
    /// so SinRutina never blocks a completion.
    func completeReminder(identifier: String) {
        guard access.canWrite else { return }
        guard let reminder = store.calendarItem(withIdentifier: identifier) as? EKReminder else { return }
        guard !reminder.isCompleted else { return }
        reminder.isCompleted = true
        do {
            try store.save(reminder, commit: true)
        } catch {
            lastErrorMessage = "No pudimos marcar el recordatorio como hecho."
        }
    }

    func reminderExists(identifier: String) -> Bool {
        guard access.canRead else { return false }
        return store.calendarItem(withIdentifier: identifier) is EKReminder
    }
}

enum SRReminderError: LocalizedError {
    case noPermission
    case noWritableList

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "SinRutina todavía no tiene permiso para Recordatorios."
        case .noWritableList:
            return "No encontramos una lista de Recordatorios donde escribir."
        }
    }
}
