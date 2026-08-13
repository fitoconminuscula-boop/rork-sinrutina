import Foundation
import Observation

/// Which calendars the person has authorised SinRutina to use. Stored in the app
/// group so every surface agrees, and never guessed: an empty selection means
/// "no calendars yet", not "all of them".
@MainActor
@Observable
final class CalendarPreferences {
    static let shared = CalendarPreferences()

    private(set) var selectedCalendarIdentifiers: Set<String>
    private(set) var writeTargetIdentifier: String?
    private(set) var remindersListIdentifier: String?
    private(set) var isRemindersLinkEnabled: Bool
    /// Explicit rule the person must switch on before any automation may delete
    /// an event without asking.
    private(set) var allowsAutomaticEventDeletion: Bool
    private(set) var isLiveActivityEnabled: Bool

    private let defaults = SRShared.defaults

    private init() {
        let stored = defaults.stringArray(forKey: SRShared.Key.selectedCalendars) ?? []
        self.selectedCalendarIdentifiers = Set(stored)
        self.writeTargetIdentifier = defaults.string(forKey: SRShared.Key.calendarForNewEvents)
        self.remindersListIdentifier = defaults.string(forKey: SRShared.Key.remindersListIdentifier)
        self.isRemindersLinkEnabled = defaults.bool(forKey: SRShared.Key.remindersLinkEnabled)
        self.allowsAutomaticEventDeletion = defaults.bool(forKey: SRShared.Key.autoDeleteRuleEnabled)
        self.isLiveActivityEnabled = defaults.object(forKey: SRShared.Key.liveActivityEnabled) as? Bool ?? true
    }

    func isSelected(_ identifier: String) -> Bool {
        selectedCalendarIdentifiers.contains(identifier)
    }

    func setSelected(_ isSelected: Bool, for identifier: String) {
        if isSelected {
            selectedCalendarIdentifiers.insert(identifier)
        } else {
            selectedCalendarIdentifiers.remove(identifier)
            if writeTargetIdentifier == identifier { setWriteTarget(nil) }
        }
        persistSelection()
    }

    /// Called the first time access is granted so the person sees something useful
    /// immediately, but only with calendars iOS itself marks as writable defaults.
    func seedIfEmpty(with identifiers: [String], defaultWriteTarget: String?) {
        guard selectedCalendarIdentifiers.isEmpty else { return }
        selectedCalendarIdentifiers = Set(identifiers)
        persistSelection()
        if writeTargetIdentifier == nil {
            setWriteTarget(defaultWriteTarget)
        }
    }

    func setWriteTarget(_ identifier: String?) {
        writeTargetIdentifier = identifier
        if let identifier {
            defaults.set(identifier, forKey: SRShared.Key.calendarForNewEvents)
        } else {
            defaults.removeObject(forKey: SRShared.Key.calendarForNewEvents)
        }
    }

    func setRemindersList(_ identifier: String?) {
        remindersListIdentifier = identifier
        if let identifier {
            defaults.set(identifier, forKey: SRShared.Key.remindersListIdentifier)
        } else {
            defaults.removeObject(forKey: SRShared.Key.remindersListIdentifier)
        }
    }

    func setRemindersLinkEnabled(_ isEnabled: Bool) {
        isRemindersLinkEnabled = isEnabled
        defaults.set(isEnabled, forKey: SRShared.Key.remindersLinkEnabled)
    }

    func setAllowsAutomaticEventDeletion(_ isAllowed: Bool) {
        allowsAutomaticEventDeletion = isAllowed
        defaults.set(isAllowed, forKey: SRShared.Key.autoDeleteRuleEnabled)
    }

    func setLiveActivityEnabled(_ isEnabled: Bool) {
        isLiveActivityEnabled = isEnabled
        defaults.set(isEnabled, forKey: SRShared.Key.liveActivityEnabled)
    }

    private func persistSelection() {
        defaults.set(Array(selectedCalendarIdentifiers), forKey: SRShared.Key.selectedCalendars)
    }
}
