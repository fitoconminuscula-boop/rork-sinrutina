import EventKit
import Foundation
import SwiftData
import WidgetKit

/// The one place where data actually changes.
///
/// Apple Intelligence, Siri, the widget, the share sheet and alarms all *propose*;
/// this type decides what is allowed. It refuses to delete anything, and every
/// destructive-looking action is really a state change that stays recoverable.
@MainActor
enum SRTaskCommands {

    // MARK: - Creating

    /// Materialises an intelligence proposal into a real task, with the rules
    /// SinRutina guarantees regardless of what the model said.
    @discardableResult
    static func create(
        from suggestion: SRCaptureSuggestion,
        source: String,
        forcedState: TaskState? = nil,
        sharedExcerpt: String? = nil,
        context: ModelContext
    ) -> TaskItem {
        var safe = suggestion
        // Rule: the model may never park something in "Completada".
        if safe.suggestedState == .completed { safe.suggestedState = .now }
        // Rule: "Esperando" requires knowing who we wait for.
        if safe.suggestedState == .waiting, (safe.waitingFor ?? "").isEmpty {
            safe.suggestedState = .after
        }
        if let forcedState, forcedState != .completed {
            safe.suggestedState = forcedState
            if forcedState != .waiting { safe.waitingFor = nil }
        }

        let task = TaskItem(suggestion: safe, source: source)
        if let sharedExcerpt, !sharedExcerpt.isEmpty {
            task.sharedExcerpt = String(sharedExcerpt.prefix(2_000))
        }
        context.insert(task)
        try? context.save()
        refreshOutsideSurfaces(context: context)
        return task
    }

    /// Applies everything waiting in the share inbox that the person already
    /// resolved in the share sheet, and returns the items still needing a decision.
    static func drainResolvedInboxItems(context: ModelContext) -> [SRInboxItem] {
        let items = SRShareInbox.all()
        var pending: [SRInboxItem] = []
        for item in items {
            guard let state = item.chosenState else {
                pending.append(item)
                continue
            }
            create(
                from: item.suggestion,
                source: item.sourceApp.map { "compartido·\($0)" } ?? "compartido",
                forcedState: state,
                sharedExcerpt: item.rawText,
                context: context
            )
            SRShareInbox.remove(id: item.id)
        }
        return pending
    }

    // MARK: - Moving

    static func start(_ task: TaskItem, context: ModelContext) {
        task.move(to: .now)
        task.isCurrent = true
        try? context.save()
        LiveActivityController.shared.start(task: task)
        refreshOutsideSurfaces(context: context)
    }

    static func complete(_ task: TaskItem, actualMinutes: Double? = nil, context: ModelContext) {
        let minutes = actualMinutes ?? Double(task.estimatedMinutes)
        task.markCompleted(actualMinutes: minutes)
        BehaviorRecorder.recordCompletion(for: task, actualMinutes: minutes, context: context)

        // Keep Apple Recordatorios in sync, one direction only, and only while the
        // person has the link switched on.
        if let reminderIdentifier = task.reminderIdentifier,
           CalendarPreferences.shared.isRemindersLinkEnabled {
            ReminderService.shared.completeReminder(identifier: reminderIdentifier)
        }
        Task { await InsistenceScheduler.shared.cancel(for: task) }
        LiveActivityController.shared.end()
        try? context.save()
        refreshOutsideSurfaces(context: context)
    }

    static func postpone(_ task: TaskItem, to state: TaskState = .after, context: ModelContext) {
        guard state != .completed else { return }
        task.procrastinationCount += 1
        task.move(to: state)
        BehaviorRecorder.recordActionResponse("Posponer", context: context)
        LiveActivityController.shared.end(immediately: true)
        try? context.save()
        refreshOutsideSurfaces(context: context)
    }

    static func markWaiting(_ task: TaskItem, for subject: String?, context: ModelContext) {
        let who = (subject?.trimmingCharacters(in: .whitespacesAndNewlines)).flatMap { $0.isEmpty ? nil : $0 }
        task.markWaiting(for: who ?? task.waitingFor ?? "otra persona")
        BehaviorRecorder.recordActionResponse("Esperando", context: context)
        Task { await InsistenceScheduler.shared.cancel(for: task) }
        LiveActivityController.shared.end(immediately: true)
        try? context.save()
        refreshOutsideSurfaces(context: context)
    }

    // MARK: - Insistence

    static func setInsistence(
        _ level: SRInsistence,
        remindAt: Date?,
        for task: TaskItem,
        context: ModelContext
    ) {
        task.insistence = level
        task.remindAt = remindAt
        try? context.save()
        Task { await InsistenceScheduler.shared.schedule(for: task) }
    }

    // MARK: - Reminders link

    /// Adopts an Apple reminder as a SinRutina task, keeping one single link so the
    /// two apps never disagree about the same thing.
    @discardableResult
    static func adopt(
        reminder: SRImportableReminder,
        suggestion: SRCaptureSuggestion,
        context: ModelContext
    ) -> TaskItem? {
        guard !reminder.isAlreadyLinked else { return nil }
        let descriptor = FetchDescriptor<TaskItem>()
        let existing = (try? context.fetch(descriptor)) ?? []
        guard !existing.contains(where: { $0.reminderIdentifier == reminder.id }) else { return nil }

        var safe = suggestion
        if let dueDate = reminder.dueDate { safe.dueDate = dueDate }
        let task = create(from: safe, source: "recordatorio", context: context)
        task.reminderIdentifier = reminder.id
        try? context.save()
        return task
    }

    /// Pushes a SinRutina task into Apple Recordatorios and stores the link.
    static func mirrorToReminders(_ task: TaskItem, context: ModelContext) throws {
        guard task.reminderIdentifier == nil else { return }
        let identifier = try ReminderService.shared.createReminder(
            title: task.title,
            dueDate: task.remindAt ?? task.dueDate,
            notes: task.nextStep
        )
        task.reminderIdentifier = identifier
        try? context.save()
    }

    // MARK: - Outside surfaces

    /// Recomputes the widget snapshot. Called after every change so home screen and
    /// app never contradict each other.
    static func refreshOutsideSurfaces(context: ModelContext) {
        // A session in progress owns every outside surface: the widget shows that
        // one task and nothing else.
        if FocusSessionManager.shared.isRunning { return }
        let descriptor = FetchDescriptor<TaskItem>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        let engine = NextActionEngine(
            availableMinutes: CalendarService.shared.availableMinutesNow,
            nextEventTitle: CalendarService.shared.nextEvent()?.title
        )
        let openTasks = tasks.filter { $0.state != .completed && $0.state != .waiting }
        let waitingCount = tasks.filter { $0.state == .waiting }.count
        let candidate = engine.recommendations(from: tasks).first

        let snapshot: SRWidgetSnapshot
        if let candidate {
            snapshot = SRWidgetSnapshot(
                taskID: candidate.id.uuidString,
                title: candidate.title,
                estimatedMinutes: candidate.estimatedMinutes,
                tone: candidate.dueDate.map { $0 < Date() ? .overdue : .current } ?? .current,
                nextStep: engine.microStep(for: candidate),
                availableFrom: candidate.availableFrom,
                dueDate: candidate.dueDate,
                openCount: openTasks.count,
                waitingCount: waitingCount,
                availableMinutes: CalendarService.shared.availableMinutesNow,
                nextEventTitle: CalendarService.shared.nextEvent()?.title
            )
        } else if let upcoming = openTasks
            .filter({ ($0.availableFrom ?? .distantPast) > Date() })
            .min(by: { ($0.availableFrom ?? .distantFuture) < ($1.availableFrom ?? .distantFuture) }) {
            snapshot = SRWidgetSnapshot(
                taskID: upcoming.id.uuidString,
                title: upcoming.title,
                estimatedMinutes: upcoming.estimatedMinutes,
                tone: .upcoming,
                nextStep: upcoming.nextStep,
                availableFrom: upcoming.availableFrom,
                dueDate: upcoming.dueDate,
                openCount: openTasks.count,
                waitingCount: waitingCount
            )
        } else {
            snapshot = SRWidgetSnapshot(
                title: "Nada urgente ahora",
                estimatedMinutes: 0,
                tone: .empty,
                openCount: openTasks.count,
                waitingCount: waitingCount
            )
        }

        SRWidgetStore.write(snapshot)
        WidgetCenter.shared.reloadTimelines(ofKind: SRShared.widgetKind)
    }

    /// Writes the reduced snapshot used while "Estoy saturado" is on.
    static func markSaturated(_ isSaturated: Bool, context: ModelContext) {
        guard isSaturated else {
            refreshOutsideSurfaces(context: context)
            return
        }
        let descriptor = FetchDescriptor<TaskItem>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        let engine = NextActionEngine()
        guard let candidate = engine.recommendations(from: tasks).first else {
            refreshOutsideSurfaces(context: context)
            return
        }
        SRWidgetStore.write(
            SRWidgetSnapshot(
                taskID: candidate.id.uuidString,
                title: candidate.title,
                estimatedMinutes: candidate.estimatedMinutes,
                tone: .saturated,
                nextStep: engine.microStep(for: candidate),
                openCount: 1,
                waitingCount: 0
            )
        )
        WidgetCenter.shared.reloadTimelines(ofKind: SRShared.widgetKind)
    }

    // MARK: - Lookup

    static func task(withID identifier: String?, context: ModelContext) -> TaskItem? {
        guard let identifier, let uuid = UUID(uuidString: identifier) else { return nil }
        let descriptor = FetchDescriptor<TaskItem>(predicate: #Predicate { $0.id == uuid })
        return (try? context.fetch(descriptor))?.first
    }

    static func currentRecommendation(context: ModelContext) -> TaskItem? {
        let descriptor = FetchDescriptor<TaskItem>()
        let tasks = (try? context.fetch(descriptor)) ?? []
        let engine = NextActionEngine(
            availableMinutes: CalendarService.shared.availableMinutesNow,
            nextEventTitle: CalendarService.shared.nextEvent()?.title
        )
        return engine.recommendations(from: tasks).first
    }
}
