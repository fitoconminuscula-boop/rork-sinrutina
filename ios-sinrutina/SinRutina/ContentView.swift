import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSession.self) private var session
    @Environment(\.dynamicTypeSize) private var systemTypeSize
    @State private var appearance = SRAppearanceStore.shared
    @State private var selectedTab: AppTab = .now
    @State private var showCapture = false
    @State private var showEndOfDay = false
    @State private var reviewConcepts: [ReviewConcept] = []
    @State private var studyTask: TaskItem?
    @State private var mailTask: TaskItem?
    @State private var focus = FocusSessionManager.shared
    @State private var departure = PersonalTravelEngine.shared

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                NowView(showCapture: $showCapture, showEndOfDay: $showEndOfDay)
            }
            .tabItem {
                Label("Ahora", systemImage: "checkmark.circle")
            }
            .tag(AppTab.now)

            NavigationStack {
                CalendarAgendaView()
            }
            .tabItem {
                Label("Calendario", systemImage: "calendar")
            }
            .tag(AppTab.calendar)

            NavigationStack {
                TasksHubView()
            }
            .tabItem {
                Label("Tareas", systemImage: "checklist")
            }
            .tag(AppTab.tasks)

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Ajustes", systemImage: "gearshape")
            }
            .tag(AppTab.settings)
        }
        .tint(SRDesign.primary)
        .background(SRDesign.background)
        // Invented content is never silent: the sign lives above everything.
        .safeAreaInset(edge: .top, spacing: 0) {
            SRDemoBanner()
        }
        .srMeasureMetrics()
        // The theme decides light or dark on purpose; "Seguir sistema" hands the
        // decision back to iOS. The visual scale only nudges Dynamic Type.
        .preferredColorScheme(appearance.profile.theme.forcedColorScheme)
        .dynamicTypeSize(appearance.profile.visualScale.adjusted(systemTypeSize))
        .animation(SRDesign.standardAnimation, value: appearance.profile)
        .sheet(isPresented: $showCapture) {
            CaptureSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showEndOfDay) {
            EndOfDayView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { !reviewConcepts.isEmpty },
            set: { if !$0 { reviewConcepts = [] } }
        )) {
            ReviewSessionView(concepts: reviewConcepts)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $studyTask) { task in
            NavigationStack {
                StudySessionView(task: task)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $mailTask) { task in
            MailActionView(task: task)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: Binding(get: { session.showsInbox }, set: { session.showsInbox = $0 })) {
            ShareInboxView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .task {
            // Nothing invented survives outside the demonstration mode.
            DemoDataMode.shared.reconcile(context: modelContext)
            InsistenceScheduler.shared.configure()
            LiveActivityController.shared.reattachOrClear()
            // Before anything else: no restriction may outlive its session.
            focus.restore(context: modelContext)
            // From here on the screen is truthful, so the launch curtain can go.
            // Everything below refines it and must never hold the person back.
            session.markReady()
            await SRIntelligenceService.shared.prepare()
            await refreshEcosystem()
            // The leave time is only honest while it is being recalculated, and a
            // trip left open has to be able to finish.
            await departure.refresh(reason: .opened)
            departure.startWatching()
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else {
                // Nothing keeps looking while the app is not in front, except the
                // low-power learning the person explicitly enabled.
                if phase == .background { departure.stopWatching() }
                return
            }
            session.lastOpenedAt = Date()
            departure.startWatching()
            Task { await departure.refresh(reason: .opened) }
            appearance.reloadFromDisk()
            focus.restore(context: modelContext)
            if focus.pendingPauseRequest != nil {
                // The shield sent the person here on purpose.
                selectedTab = .now
                if let running = focus.session {
                    session.requestedResumeTaskID = running.taskID
                }
            }
            Task { await refreshEcosystem() }
        }
        .onChange(of: session.wantsCapture) { _, wants in
            guard wants else { return }
            showCapture = true
            selectedTab = .now
            session.wantsCapture = false
        }
        .onChange(of: session.wantsReview) { _, wants in
            guard wants else { return }
            session.wantsReview = false
            openReview()
        }
        .onChange(of: session.requestedStudyTaskID) { _, identifier in
            guard let identifier,
                  let task = SRTaskCommands.task(withID: identifier, context: modelContext) else { return }
            session.requestedStudyTaskID = nil
            studyTask = task
        }
        .onChange(of: session.requestedMailTaskID) { _, identifier in
            guard let identifier,
                  let task = SRTaskCommands.task(withID: identifier, context: modelContext) else { return }
            session.requestedMailTaskID = nil
            mailTask = task
        }
    }

    /// Brings the outside world back in: calendar knowledge, shared items and any
    /// command left by the widget, Siri or an alarm.
    private func refreshEcosystem() async {
        CalendarService.shared.refreshAccessState()
        ReminderService.shared.refreshAccessState()
        if CalendarService.shared.access.canRead {
            CalendarService.shared.loadCalendars()
            await CalendarService.shared.reloadUpcoming()
        }
        await InsistenceScheduler.shared.refreshAuthorization()

        session.pendingInboxItems = SRTaskCommands.drainResolvedInboxItems(context: modelContext)
        SRTaskCommands.refreshOutsideSurfaces(context: modelContext)
        applyPendingCommand()
    }

    private func applyPendingCommand() {
        guard let command = SRCommandBus.take() else { return }
        switch command.kind {
        case .startCurrent:
            selectedTab = .now
            session.isSaturated = false
            let task = SRTaskCommands.task(withID: command.taskID, context: modelContext)
                ?? SRTaskCommands.currentRecommendation(context: modelContext)
            session.requestedStartTaskID = task?.id.uuidString
        case .finishCurrent:
            if let task = SRTaskCommands.task(withID: command.taskID, context: modelContext)
                ?? SRTaskCommands.currentRecommendation(context: modelContext) {
                SRTaskCommands.complete(task, context: modelContext)
                SRHaptics.success()
            }
        case .postponeCurrent:
            if let task = SRTaskCommands.task(withID: command.taskID, context: modelContext)
                ?? SRTaskCommands.currentRecommendation(context: modelContext) {
                SRTaskCommands.postpone(task, context: modelContext)
            }
        case .waitingCurrent:
            if let task = SRTaskCommands.task(withID: command.taskID, context: modelContext) {
                SRTaskCommands.markWaiting(task, for: nil, context: modelContext)
            }
        case .saturated:
            selectedTab = .now
            withAnimation(SRDesign.standardAnimation) { session.isSaturated = true }
            SRTaskCommands.markSaturated(true, context: modelContext)
        case .openCapture:
            selectedTab = .now
            showCapture = true
        case .openInbox:
            session.showsInbox = true
        case .whatNow:
            selectedTab = .now
            session.isSaturated = false
        case .openStudy:
            selectedTab = .now
            studyTask = SRTaskCommands.task(withID: command.taskID, context: modelContext)
                ?? SRTaskCommands.currentRecommendation(context: modelContext).flatMap { $0.isStudy ? $0 : nil }
        case .openReview:
            selectedTab = .now
            openReview()
        case .openMail:
            selectedTab = .now
            mailTask = SRTaskCommands.task(withID: command.taskID, context: modelContext)
        case .requestPause, .resumeFocus:
            selectedTab = .now
            session.requestedResumeTaskID = command.taskID ?? focus.session?.taskID ?? focus.reentry?.taskID
        case .pauseFocus:
            focus.pause(context: modelContext)
        case .progressedFocus:
            if let task = SRTaskCommands.task(withID: command.taskID ?? focus.session?.taskID, context: modelContext) {
                let minutes = focus.finish(completed: false, context: modelContext)
                task.actualDuration = (task.actualDuration ?? 0) + minutes
                task.move(to: .after)
                try? modelContext.save()
                BehaviorRecorder.recordPartialProgress(context: modelContext)
                SRTaskCommands.refreshOutsideSurfaces(context: modelContext)
            }
        case .releaseAppTemporarily:
            if let name = command.taskID, !name.isEmpty {
                focus.release(app: name)
            }
        case .endFocusMode:
            focus.suspendForReentry()
            SRTaskCommands.refreshOutsideSurfaces(context: modelContext)
        case .emergency:
            focus.emergency(context: modelContext)
        case .openDeparture:
            selectedTab = .now
            session.showsDeparture = true
            Task { await departure.refresh(reason: .userChange) }
        }
    }

    /// Opens the spaced review with whatever is actually due.
    private func openReview() {
        let due = ReviewScheduler.dueConcepts(context: modelContext, limit: 5)
        guard !due.isEmpty else { return }
        reviewConcepts = due
    }
}

#Preview {
    ContentView()
        .modelContainer(
            for: [TaskItem.self, BehaviorProfile.self, StudyMaterial.self, ReviewConcept.self],
            inMemory: true
        )
        .environment(AppSession())
}
