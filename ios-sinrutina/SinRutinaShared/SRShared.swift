import Foundation

/// Constants and the tiny bridge that lets the app, the widget and the share
/// extension speak to each other without a server.
nonisolated enum SRShared {
    static let appGroupIdentifier = "group.app.rork.txdqdl3g4c4eqlv6x06ff"
    static let widgetKind = "SinRutinaWidget"

    static var defaults: UserDefaults {
        UserDefaults(suiteName: appGroupIdentifier) ?? .standard
    }

    /// The shared folder the app, the widget and the share sheet write into.
    ///
    /// `nil` on installs signed with a free Apple ID, where App Groups are not
    /// granted. Everything that can work without it must fall back to the app's
    /// own storage instead of failing.
    static var sharedContainerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
    }

    /// False when this install cannot share data with the widget, Siri's
    /// shortcuts or the share sheet. Surfaces in Ajustes so nothing pretends to
    /// work when it cannot.
    static var hasSharedContainer: Bool {
        sharedContainerURL != nil
    }

    /// Where the shared database lives, with its parent folder guaranteed to exist.
    ///
    /// The system creates the app group container but not the `Library/Application
    /// Support` folder inside it. SwiftData does not create it either, so asking for
    /// a group container alone can fail to open the store on a clean install.
    /// Creating the folder first turns that into a normal launch.
    /// Uses the same file name SwiftData picks by default, so anything saved
    /// before this fix keeps being found.
    static func groupStoreURL(named name: String = "default.store") -> URL? {
        guard let container = sharedContainerURL else { return nil }

        let directory = container
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        return directory.appendingPathComponent(name, isDirectory: false)
    }

    enum Key {
        static let widgetSnapshot = "sr.widget.snapshot"
        static let inbox = "sr.inbox.items"
        static let pendingCommand = "sr.pending.command"
        static let selectedCalendars = "sr.calendars.selected"
        static let calendarForNewEvents = "sr.calendars.writeTarget"
        static let remindersLinkEnabled = "sr.reminders.linkEnabled"
        static let remindersListIdentifier = "sr.reminders.listIdentifier"
        static let autoDeleteRuleEnabled = "sr.calendars.autoDeleteRule"
        static let liveActivityEnabled = "sr.liveActivity.enabled"
        static let appearance = "sr.appearance.profile"
        static let proactivityLevel = "sr.proactivity.level"
        static let proactivityDisabledDomains = "sr.proactivity.disabledDomains"
        static let interventionLog = "sr.proactivity.log"
        static let learnedInsights = "sr.learning.insights"
        static let learningEnabled = "sr.learning.enabled"
        static let defaultSourceMode = "sr.study.sourceMode"
        static let webSearchAllowed = "sr.study.webAllowed"
        static let mailReplyStyle = "sr.mail.replyStyle"

        // MARK: Adaptive behavioural environment
        static let focusProfiles = "sr.focus.profiles"
        static let focusPreferences = "sr.focus.preferences"
        static let focusSession = "sr.focus.session"
        static let focusApprovedProfiles = "sr.focus.approvedProfiles"
        static let distractionLog = "sr.focus.distractionLog"
        static let shieldSignal = "sr.focus.shieldSignal"
        static let shieldContext = "sr.focus.shieldContext"
        /// Screen Time selections, one blob per focus profile identifier.
        static let screenTimeSelectionPrefix = "sr.focus.selection."
        static let screenTimeDistractors = "sr.focus.distractors"

        // MARK: Salir a tiempo
        static let travelPreferences = "sr.travel.preferences"
        static let travelPlans = "sr.travel.plans"
        static let travelGeocodeCache = "sr.travel.geocode"
        /// Observed gaps between "I have to leave" and actually moving.
        static let travelTransitionMemory = "sr.travel.transition"
        /// The trip currently being measured, so it survives a relaunch.
        static let travelActiveTrip = "sr.travel.activeTrip"
        /// Learned destinations and routes, stored on this device only.
        static let travelLearnedArchive = "sr.travel.learned"

        /// True only while the person explicitly turned the demonstration mode on.
        static let demoModeActive = "sr.demo.active"
    }
}

/// Commands handed to the app from outside surfaces (widget, Siri, Shortcuts).
/// The app applies them through its own business rules — the caller never
/// mutates data directly.
nonisolated struct SRPendingCommand: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case startCurrent
        case finishCurrent
        case postponeCurrent
        case waitingCurrent
        case saturated
        case openCapture
        case openInbox
        case whatNow
        case openStudy
        case openReview
        case openMail
        /// The shield asked SinRutina to open the friction screen.
        case requestPause
        case pauseFocus
        case resumeFocus
        case progressedFocus
        case releaseAppTemporarily
        case endFocusMode
        case emergency
        /// "¿Cuándo tengo que salir?" — opens the departure detail.
        case openDeparture
    }

    var kind: Kind
    var taskID: String?
    var createdAt: Date

    init(kind: Kind, taskID: String? = nil, createdAt: Date = Date()) {
        self.kind = kind
        self.taskID = taskID
        self.createdAt = createdAt
    }
}

nonisolated enum SRCommandBus {
    /// Only the most recent command is kept: SinRutina never queues up a backlog
    /// of automated actions the person did not ask for again.
    static func send(_ command: SRPendingCommand) {
        guard let data = try? JSONEncoder().encode(command) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.pendingCommand)
    }

    static func take() -> SRPendingCommand? {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.pendingCommand),
              let command = try? JSONDecoder().decode(SRPendingCommand.self, from: data) else {
            return nil
        }
        SRShared.defaults.removeObject(forKey: SRShared.Key.pendingCommand)
        // Ignore stale commands so a forgotten tap does not fire days later.
        guard Date().timeIntervalSince(command.createdAt) < 600 else { return nil }
        return command
    }
}
