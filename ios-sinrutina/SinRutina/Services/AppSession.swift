import Foundation
import Observation

@MainActor
@Observable
final class AppSession {
    var isSaturated = false
    var lastOpenedAt = Date()

    /// True once the screen behind the launch curtain tells the truth: demo data
    /// reconciled, an interrupted focus session restored, alarms re-read. Until
    /// then "Ahora" could show something that is about to change.
    private(set) var isReady = false

    func markReady() {
        guard !isReady else { return }
        isReady = true
    }

    /// Set when an outside surface (widget, Siri, alarm) asked to start a task.
    var requestedStartTaskID: String?
    /// Set when SinRutina should open quick capture on appear.
    var wantsCapture = false
    /// Shared items that still need a decision.
    var pendingInboxItems: [SRInboxItem] = []
    var showsInbox = false

    /// Set when an outside surface asked for the spaced review.
    var wantsReview = false
    /// Set when an outside surface asked to open a study session.
    var requestedStudyTaskID: String?
    /// Set when an outside surface asked to open a mail thread.
    var requestedMailTaskID: String?
    /// Set when an outside surface asked to come back to an interrupted session.
    var requestedResumeTaskID: String?
    /// Set when an outside surface asked "¿cuándo tengo que salir?".
    var showsDeparture = false

    var hasPendingInbox: Bool { !pendingInboxItems.isEmpty }
}

enum AppTab: Hashable {
    case now
    case after
    case someday
    case settings
}
