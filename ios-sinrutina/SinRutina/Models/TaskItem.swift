import Foundation
import SwiftData

@Model
final class TaskItem {
    var id: UUID
    var title: String
    var detail: String
    var createdAt: Date
    var updatedAt: Date
    var stateRaw: String
    var estimatedMinutes: Int
    var dueDate: Date?
    var availableFrom: Date?
    var completedAt: Date?
    var waitingSince: Date?
    var waitingFor: String?
    var source: String?
    var isCurrent: Bool
    var procrastinationCount: Int
    var actualDuration: Double?
    var preferredContext: String?
    var notes: String?
    var isDemo: Bool

    // MARK: - Ecosystem layer (added in the Apple integrations phase).
    // All new properties carry defaults so SwiftData can migrate silently.

    /// First concrete movement, proposed by the intelligence layer.
    var nextStep: String?
    /// Apps that make sense for this task, as plain names ("Teléfono", "WhatsApp").
    var allowedAppsRaw: String?
    /// How hard SinRutina may push this one.
    var insistenceRaw: String = SRInsistence.normal.rawValue
    /// When the person wants to be reminded. Nil means never.
    var remindAt: Date?
    /// Identifier of the linked reminder in Apple Recordatorios, if any.
    var reminderIdentifier: String?
    /// Identifier of the linked event in Apple Calendario, if any.
    var eventIdentifier: String?
    /// Identifier of the scheduled AlarmKit alarm, if any.
    var alarmIdentifier: String?
    /// True when Apple Intelligence produced the structured fields.
    var wasEnrichedOnDevice: Bool = false
    /// Last time SinRutina offered a follow-up for a waiting item.
    var lastFollowUpAt: Date?
    /// Text shared from another app, kept so the person can reread the original.
    var sharedExcerpt: String?

    // MARK: - Study, mail and adherence layer.
    // Again, every property has a default so existing stores migrate silently.

    /// What understanding this session is aiming at.
    var studyObjective: String?
    /// Where answers may come from while working on this. Only the person changes it.
    var sourceModeRaw: String = SRSourceMode.mixed.rawValue
    /// Steps of the current study session, encoded as JSON.
    var studyPlanJSON: String?
    /// Minutes actually spent studying this, accumulated across sessions.
    var studiedMinutes: Double = 0

    /// Sender of the email this task came from.
    var mailSender: String?
    /// Subject line of that email.
    var mailSubject: String?
    /// A bounded excerpt of the body, so the person can reread without leaving.
    var mailExcerpt: String?
    /// The draft SinRutina proposed. Never sent automatically.
    var mailReplyDraft: String?
    /// Register of the draft, so regenerating keeps the person's preference.
    var mailReplyStyleRaw: String?
    /// True once the person opened the composer for this task.
    var mailWasAnswered: Bool = false

    /// Files associated with this task, as app-group file names joined by "|".
    var attachmentsRaw: String?

    /// True when the person asked to be reminded "when there is a gap" instead of
    /// at a fixed time.
    var wantsContextualReminder: Bool = false
    /// The slot SinRutina proposed for a contextual reminder.
    var proposedSlotStart: Date?

    /// Last time SinRutina spoke about this task on its own initiative.
    var lastInterventionAt: Date?
    /// How many unsolicited suggestions about this task were walked past.
    var ignoredInterventionCount: Int = 0
    /// True once the person answered "ya no importa" to the adaptation question.
    var wasReleased: Bool = false

    var state: TaskState {
        get { TaskState(rawValue: stateRaw) ?? .after }
        set {
            stateRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var insistence: SRInsistence {
        get { SRInsistence(rawValue: insistenceRaw) ?? .normal }
        set {
            insistenceRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var sourceMode: SRSourceMode {
        get { SRSourceMode(rawValue: sourceModeRaw) ?? .mixed }
        set {
            sourceModeRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var mailReplyStyle: SRReplyStyle? {
        get { mailReplyStyleRaw.flatMap(SRReplyStyle.init(rawValue:)) }
        set { mailReplyStyleRaw = newValue?.rawValue }
    }

    /// True when this task carries an email worth answering.
    var isMail: Bool { mailSender != nil || mailSubject != nil }

    /// True when this is learning work rather than an errand.
    var isStudy: Bool {
        SRStudyDetector.isStudy(title: title, detail: detail, context: preferredContext)
    }

    var studyPlan: SRStudyPlan? {
        get {
            guard let studyPlanJSON, let data = studyPlanJSON.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(SRStudyPlan.self, from: data)
        }
        set {
            guard let newValue, let data = try? JSONEncoder().encode(newValue) else {
                studyPlanJSON = nil
                return
            }
            studyPlanJSON = String(data: data, encoding: .utf8)
            updatedAt = Date()
        }
    }

    var attachmentNames: [String] {
        get {
            guard let attachmentsRaw, !attachmentsRaw.isEmpty else { return [] }
            return attachmentsRaw
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set { attachmentsRaw = newValue.isEmpty ? nil : newValue.joined(separator: "|") }
    }

    var allowedApps: [String] {
        get {
            guard let allowedAppsRaw, !allowedAppsRaw.isEmpty else { return [] }
            return allowedAppsRaw
                .split(separator: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
        }
        set { allowedAppsRaw = newValue.isEmpty ? nil : newValue.joined(separator: "|") }
    }

    var isOpen: Bool {
        state != .completed && state != .waiting
    }

    /// Days this item has been open. A neutral temporal fact: it replaces counting
    /// postponements back at the person, which reads as a reproach.
    var openDays: Int {
        Calendar.current.dateComponents([.day], from: createdAt, to: Date()).day ?? 0
    }

    /// Days this item has been parked waiting for someone else.
    var waitingDays: Int {
        guard let waitingSince else { return 0 }
        return Calendar.current.dateComponents([.day], from: waitingSince, to: Date()).day ?? 0
    }

    init(
        title: String,
        detail: String = "",
        estimatedMinutes: Int = 10,
        state: TaskState = .now,
        dueDate: Date? = nil,
        availableFrom: Date? = nil,
        waitingFor: String? = nil,
        source: String? = nil,
        isDemo: Bool = false
    ) {
        let now = Date()
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.createdAt = now
        self.updatedAt = now
        self.stateRaw = state.rawValue
        self.estimatedMinutes = max(1, estimatedMinutes)
        self.dueDate = dueDate
        self.availableFrom = availableFrom
        self.completedAt = nil
        self.waitingSince = state == .waiting ? now : nil
        self.waitingFor = waitingFor
        self.source = source
        self.isCurrent = state == .now
        self.procrastinationCount = 0
        self.actualDuration = nil
        self.preferredContext = nil
        self.notes = nil
        self.isDemo = isDemo
        self.nextStep = nil
        self.allowedAppsRaw = nil
        self.insistenceRaw = SRInsistence.normal.rawValue
        self.remindAt = nil
        self.reminderIdentifier = nil
        self.eventIdentifier = nil
        self.alarmIdentifier = nil
        self.wasEnrichedOnDevice = false
        self.lastFollowUpAt = nil
        self.sharedExcerpt = nil
        self.studyObjective = nil
        self.sourceModeRaw = SRSourceMode.mixed.rawValue
        self.studyPlanJSON = nil
        self.studiedMinutes = 0
        self.mailSender = nil
        self.mailSubject = nil
        self.mailExcerpt = nil
        self.mailReplyDraft = nil
        self.mailReplyStyleRaw = nil
        self.mailWasAnswered = false
        self.attachmentsRaw = nil
        self.wantsContextualReminder = false
        self.proposedSlotStart = nil
        self.lastInterventionAt = nil
        self.ignoredInterventionCount = 0
        self.wasReleased = false
    }

    /// Builds a task from an intelligence proposal. The proposal decides the
    /// content; this initialiser decides what is legal to store.
    convenience init(suggestion: SRCaptureSuggestion, source: String) {
        self.init(
            title: suggestion.title,
            estimatedMinutes: suggestion.estimatedMinutes,
            state: suggestion.suggestedState,
            dueDate: suggestion.dueDate,
            availableFrom: suggestion.availableFrom,
            waitingFor: suggestion.waitingFor,
            source: source
        )
        preferredContext = suggestion.context
        nextStep = suggestion.nextStep
        allowedApps = suggestion.allowedApps
        wasEnrichedOnDevice = suggestion.usedOnDeviceModel
        if let summary = suggestion.summary, !summary.isEmpty {
            detail = summary
        }
    }

    func move(to newState: TaskState) {
        state = newState
        isCurrent = newState == .now
        if newState == .waiting && waitingSince == nil {
            waitingSince = Date()
        }
        if newState != .waiting {
            waitingSince = nil
            waitingFor = newState == .completed ? waitingFor : nil
        }
        if newState == .completed {
            completedAt = Date()
            isCurrent = false
        }
    }

    func markWaiting(for personOrSubject: String) {
        waitingFor = personOrSubject.trimmingCharacters(in: .whitespacesAndNewlines)
        waitingSince = waitingSince ?? Date()
        move(to: .waiting)
    }

    func markCompleted(actualMinutes: Double) {
        actualDuration = max(0, actualMinutes)
        if isStudy { studiedMinutes += max(0, actualMinutes) }
        move(to: .completed)
    }

    /// Makes the task smaller in place, keeping its history. Used when a suggestion
    /// keeps being walked past: shrink instead of pushing harder.
    func shrink(to step: String, minutes: Int? = nil) {
        let trimmed = step.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        nextStep = trimmed
        estimatedMinutes = max(2, min(minutes ?? max(2, estimatedMinutes / 3), estimatedMinutes))
        updatedAt = Date()
    }
}
