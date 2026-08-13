import EventKit
import Foundation
import Observation
import SwiftUI

/// A calendar exactly as iOS exposes it, plus the discreet mark SinRutina uses to
/// tell accounts apart without turning Ajustes into a colour chart.
struct SRCalendarInfo: Identifiable, Hashable {
    let id: String
    let title: String
    /// "iCloud", "Google", "Exchange", "Local"… whatever the account is called.
    let accountName: String
    let sourceKind: String
    let isWritable: Bool
    let colorHex: String

    var color: Color {
        Color(uiColor: UIColor(srHex: colorHex) ?? UIColor.systemBlue)
    }
}

/// A gap between events. This is what makes "¿Qué hago ahora?" honest.
struct SRFreeWindow: Hashable {
    let start: Date
    let end: Date
    /// The event that closes the window, when there is one.
    let nextEventTitle: String?

    var minutes: Int { max(0, Int(end.timeIntervalSince(start) / 60)) }
}

enum SRCalendarAccess: Equatable {
    case notDetermined
    case granted
    case writeOnly
    case denied
    case restricted

    var canRead: Bool { self == .granted }
    var canWrite: Bool { self == .granted || self == .writeOnly }
}

/// EventKit wrapper for events. Reads only the calendars the person selected and
/// refuses to write anywhere else.
@MainActor
@Observable
final class CalendarService {
    static let shared = CalendarService()

    private let store = EKEventStore()
    private let preferences = CalendarPreferences.shared

    private(set) var access: SRCalendarAccess = .notDetermined
    private(set) var calendars: [SRCalendarInfo] = []
    private(set) var upcomingEvents: [EKEvent] = []
    private(set) var lastErrorMessage: String?

    private init() {
        refreshAccessState()
    }

    // MARK: - Permissions

    func refreshAccessState() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .notDetermined:
            access = .notDetermined
        case .denied:
            access = .denied
        case .restricted:
            access = .restricted
        case .fullAccess:
            access = .granted
        case .writeOnly:
            access = .writeOnly
        case .authorized:
            access = .granted
        @unknown default:
            access = .notDetermined
        }
    }

    /// Asks for full access because SinRutina needs to read free time, not just write.
    @discardableResult
    func requestAccess() async -> SRCalendarAccess {
        do {
            _ = try await store.requestFullAccessToEvents()
        } catch {
            lastErrorMessage = "iOS no pudo abrir los calendarios."
        }
        refreshAccessState()
        if access.canRead {
            loadCalendars()
            await reloadUpcoming()
        }
        return access
    }

    // MARK: - Calendars

    func loadCalendars() {
        guard access.canRead || access.canWrite else {
            calendars = []
            return
        }
        let all = store.calendars(for: .event)
        calendars = all
            .map { calendar in
                SRCalendarInfo(
                    id: calendar.calendarIdentifier,
                    title: calendar.title,
                    accountName: calendar.source?.title ?? "Este iPhone",
                    sourceKind: Self.describe(calendar.source?.sourceType),
                    isWritable: calendar.allowsContentModifications,
                    colorHex: UIColor(cgColor: calendar.cgColor ?? UIColor.systemBlue.cgColor).srHexString
                )
            }
            .sorted { lhs, rhs in
                lhs.accountName == rhs.accountName
                    ? lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
                    : lhs.accountName.localizedStandardCompare(rhs.accountName) == .orderedAscending
            }

        let writableDefault = store.defaultCalendarForNewEvents?.calendarIdentifier
        preferences.seedIfEmpty(
            with: calendars.filter { $0.isWritable }.map(\.id),
            defaultWriteTarget: writableDefault
        )
    }

    /// Calendars grouped by account, so Ajustes can show them the way iOS does.
    var calendarsByAccount: [(account: String, calendars: [SRCalendarInfo])] {
        let grouped = Dictionary(grouping: calendars, by: \.accountName)
        return grouped
            .map { (account: $0.key, calendars: $0.value) }
            .sorted { $0.account.localizedStandardCompare($1.account) == .orderedAscending }
    }

    var selectedCalendars: [EKCalendar] {
        let selected = preferences.selectedCalendarIdentifiers
        return store.calendars(for: .event).filter { selected.contains($0.calendarIdentifier) }
    }

    func calendarInfo(for identifier: String?) -> SRCalendarInfo? {
        guard let identifier else { return nil }
        return calendars.first { $0.id == identifier }
    }

    // MARK: - Reading

    func reloadUpcoming(within hours: Int = 36) async {
        guard access.canRead else {
            upcomingEvents = []
            return
        }
        let calendars = selectedCalendars
        guard !calendars.isEmpty else {
            upcomingEvents = []
            return
        }
        let now = Date()
        let end = now.addingTimeInterval(Double(hours) * 3_600)
        let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3_600), end: end, calendars: calendars)
        upcomingEvents = store.events(matching: predicate)
            .filter { !$0.isAllDay }
            .sorted { ($0.startDate ?? now) < ($1.startDate ?? now) }
    }

    func events(on day: Date) -> [EKEvent] {
        guard access.canRead else { return [] }
        let calendars = selectedCalendars
        guard !calendars.isEmpty else { return [] }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let predicate = store.predicateForEvents(withStart: start, end: end, calendars: calendars)
        return store.events(matching: predicate).sorted { ($0.startDate ?? start) < ($1.startDate ?? start) }
    }

    /// The next commitment after `date`, ignoring all-day entries.
    func nextEvent(after date: Date = Date()) -> EKEvent? {
        upcomingEvents.first { ($0.startDate ?? date) > date }
    }

    /// How long the person really has before the next commitment.
    /// Returns nil when there is nothing scheduled, which means "no limit".
    func freeWindow(from date: Date = Date(), horizonHours: Int = 12) -> SRFreeWindow? {
        guard access.canRead else { return nil }
        let horizon = date.addingTimeInterval(Double(horizonHours) * 3_600)

        // If something is happening right now, the window starts when it ends.
        if let current = upcomingEvents.first(where: { event in
            guard let start = event.startDate, let end = event.endDate else { return false }
            return start <= date && end > date
        }), let end = current.endDate {
            let next = upcomingEvents.first { ($0.startDate ?? horizon) > end }
            return SRFreeWindow(
                start: end,
                end: next?.startDate ?? horizon,
                nextEventTitle: next?.title
            )
        }

        guard let next = nextEvent(after: date), let start = next.startDate else { return nil }
        guard start < horizon else { return nil }
        return SRFreeWindow(start: date, end: start, nextEventTitle: next.title)
    }

    /// Minutes available right now, or nil when the calendar imposes no limit.
    var availableMinutesNow: Int? {
        guard let window = freeWindow() else { return nil }
        guard window.start <= Date().addingTimeInterval(60) else { return nil }
        return window.minutes
    }

    // MARK: - Writing

    struct EventDraft {
        var title: String
        var start: Date
        var minutes: Int
        var notes: String?
        var calendarIdentifier: String?
    }

    /// Creates an event in an explicitly chosen calendar. Refuses to guess.
    @discardableResult
    func createEvent(_ draft: EventDraft) throws -> String {
        guard access.canWrite else { throw SRCalendarError.noPermission }
        let identifier = draft.calendarIdentifier ?? preferences.writeTargetIdentifier
        guard let identifier,
              let calendar = store.calendar(withIdentifier: identifier),
              calendar.allowsContentModifications else {
            throw SRCalendarError.noWritableCalendar
        }
        guard preferences.isSelected(identifier) else { throw SRCalendarError.calendarNotAuthorised }

        let event = EKEvent(eventStore: store)
        event.calendar = calendar
        event.title = draft.title
        event.startDate = draft.start
        event.endDate = draft.start.addingTimeInterval(Double(max(5, draft.minutes)) * 60)
        event.notes = draft.notes
        try store.save(event, span: .thisEvent, commit: true)
        Task { await reloadUpcoming() }
        return event.eventIdentifier ?? ""
    }

    func event(withIdentifier identifier: String) -> EKEvent? {
        guard access.canRead else { return nil }
        return store.event(withIdentifier: identifier)
    }

    /// Deletes an event. `isAutomated` requests come from rules, not taps, so they
    /// are rejected unless the person switched the rule on themselves.
    func deleteEvent(withIdentifier identifier: String, isAutomated: Bool) throws {
        guard access.canWrite else { throw SRCalendarError.noPermission }
        if isAutomated && !preferences.allowsAutomaticEventDeletion {
            throw SRCalendarError.automationNotAllowed
        }
        guard let event = store.event(withIdentifier: identifier) else { throw SRCalendarError.eventNotFound }
        guard let calendarIdentifier = event.calendar?.calendarIdentifier,
              preferences.isSelected(calendarIdentifier) else {
            throw SRCalendarError.calendarNotAuthorised
        }
        try store.remove(event, span: .thisEvent, commit: true)
        Task { await reloadUpcoming() }
    }

    // MARK: - Helpers

    private static func describe(_ type: EKSourceType?) -> String {
        switch type {
        case .local: return "En este iPhone"
        case .exchange: return "Exchange"
        case .calDAV: return "iCloud o Google"
        case .mobileMe: return "iCloud"
        case .subscribed: return "Suscripción"
        case .birthdays: return "Cumpleaños"
        default: return "Calendario"
        }
    }
}

enum SRCalendarError: LocalizedError {
    case noPermission
    case noWritableCalendar
    case calendarNotAuthorised
    case eventNotFound
    case automationNotAllowed

    var errorDescription: String? {
        switch self {
        case .noPermission:
            return "SinRutina todavía no tiene permiso para tus calendarios."
        case .noWritableCalendar:
            return "Elige en Ajustes en qué calendario quieres crear eventos."
        case .calendarNotAuthorised:
            return "Ese calendario no está entre los que has activado."
        case .eventNotFound:
            return "Ese evento ya no existe."
        case .automationNotAllowed:
            return "Solo puedes borrar eventos a mano, salvo que actives la regla en Ajustes."
        }
    }
}

extension UIColor {
    convenience init?(srHex hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6, let number = UInt32(value, radix: 16) else { return nil }
        self.init(
            red: CGFloat((number & 0xFF0000) >> 16) / 255,
            green: CGFloat((number & 0x00FF00) >> 8) / 255,
            blue: CGFloat(number & 0x0000FF) / 255,
            alpha: 1
        )
    }

    var srHexString: String {
        var red: CGFloat = 0
        var green: CGFloat = 0
        var blue: CGFloat = 0
        var alpha: CGFloat = 0
        getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return String(
            format: "#%02X%02X%02X",
            Int((red * 255).rounded()),
            Int((green * 255).rounded()),
            Int((blue * 255).rounded())
        )
    }
}
