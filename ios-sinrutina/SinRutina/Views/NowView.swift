import EventKit
import SwiftUI
import SwiftData

struct NowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AppSession.self) private var session
    @Environment(\.srMetrics) private var metrics
    @Query(sort: \TaskItem.updatedAt, order: .reverse) private var tasks: [TaskItem]
    @Binding var showCapture: Bool
    @Binding var showEndOfDay: Bool
    @State private var recommendationIndex = 0
    @State private var reasonTask: TaskItem?
    @State private var launch: SRFocusLaunch?
    @State private var prepareTask: TaskItem?
    @State private var insistenceTask: TaskItem?
    @State private var optionsTask: TaskItem?
    @State private var pendingOption: NowPendingOption?
    @State private var showWaiting = false
    @State private var dictation = VoiceDictationService()
    @State private var dictationAlert: String?
    @State private var flash: String?
    @State private var calendar = CalendarService.shared
    @State private var appearance = SRAppearanceStore.shared
    @State private var isReadingVoice = false
    @State private var learning = SRLearningStore.shared
    @State private var intervention: SRIntervention?
    @State private var interventionTask: TaskItem?
    @State private var adaptationTask: TaskItem?
    @State private var studyTask: TaskItem?
    @State private var mailTask: TaskItem?
    @State private var reviewConcepts: [ReviewConcept] = []
    @State private var startedAt: Date?
    @State private var focus = FocusSessionManager.shared
    @State private var focusPreferences = SRFocusPreferences.shared
    @State private var profiles = SRFocusProfileStore.shared
    @State private var departure = PersonalTravelEngine.shared
    @State private var manualEstimatePlan: SRDeparturePlan?
    /// Advances on its own so a departure changes phase with the clock.
    @State private var clock = Date()

    private var profile: SRAppearanceProfile { appearance.profile }
    /// "Enfoque" keeps only the task and the way to start it.
    private var isFocusLayout: Bool { profile.nowLayout == .focus }

    private var engine: NextActionEngine {
        NextActionEngine(
            availableMinutes: calendar.availableMinutesNow,
            nextEventTitle: calendar.nextEvent()?.title,
            // A close departure shrinks the window: nothing is proposed that would
            // run into the time needed to get ready and leave.
            minutesBeforeDeparturePrep: departure.minutesBeforePreparation,
            departureLabel: departure.nextPlan?.destinationLabel
        )
    }

    private var candidates: [TaskItem] {
        engine.recommendations(from: tasks)
    }

    private var currentTask: TaskItem? {
        guard !candidates.isEmpty else { return nil }
        return candidates[min(recommendationIndex, candidates.count - 1)]
    }

    private var waitingCount: Int { tasks.filter { $0.state == .waiting }.count }

    // MARK: - How much to show

    /// A departure stops being background context once it asks for something: a
    /// phase that requires action, or a place with no honest estimate yet.
    private var departureNeedsAttention: Bool {
        guard let plan = departure.nextPlan else { return false }
        if !plan.hasEstimate { return true }
        return plan.phase(at: clock) != .notYet
    }

    private var attentionContext: SRAttentionContext {
        SRAttentionContext.resolve(
            isOverwhelmed: session.isSaturated,
            isExecuting: focus.isRunning,
            isLeavingSoon: departureNeedsAttention,
            isStudying: false
        )
    }

    private var budget: SRInformationBudget {
        SRInformationBudget.make(
            context: attentionContext,
            activation: currentTask.map(SRTaskFraming.activation(for:)) ?? .normal,
            prefersMinimalLayout: isFocusLayout
        )
    }

    /// Exactly one unsolicited thing may sit above the task, chosen by how
    /// concrete it is: a trip under way beats a question, a question beats an
    /// hour, and an hour beats anything SinRutina merely thinks.
    private var attentionSlot: NowAttentionSlot? {
        if departure.activeTrip != nil { return .trip }
        if departure.pendingQuestion != nil { return .tripQuestion }
        if departureNeedsAttention { return .departure }
        if reentryTask != nil { return .reentry }
        if learning.pendingConfirmation != nil { return .confirmation }
        if intervention != nil { return .suggestion }
        if session.hasPendingInbox { return .inbox }
        return nil
    }

    private var reentryTask: TaskItem? {
        guard let interrupted = focus.reentry,
              let task = SRTaskCommands.task(withID: interrupted.taskID, context: modelContext),
              task.state != .completed else { return nil }
        return task
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            if session.isSaturated, let currentTask {
                SaturatedView(
                    task: currentTask,
                    onStart: {
                        session.isSaturated = false
                        SRTaskCommands.markSaturated(false, context: modelContext)
                        // Saturated means "lo más pequeño posible": no walls added.
                        launch = SRFocusLaunch(task: currentTask, level: .gentle, profile: nil)
                    },
                    onExit: {
                        withAnimation(SRDesign.standardAnimation) {
                            session.isSaturated = false
                        }
                        SRTaskCommands.markSaturated(false, context: modelContext)
                    }
                )
                .transition(.opacity)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        header
                            .padding(.bottom, metrics.headerBottom)

                        Text("Ahora")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(SRDesign.ink)
                            .padding(.bottom, metrics.titleBottom)

                        attentionCard

                        contextLine

                        if let currentTask {
                            let framing = SRTaskFraming(
                                task: currentTask,
                                microStep: engine.microStep(for: currentTask),
                                budget: budget
                            )
                            CurrentTaskCard(
                                task: currentTask,
                                metrics: metrics,
                                profile: profile,
                                budget: budget,
                                framing: framing,
                                doesNotFit: doesNotFit(currentTask),
                                alternatives: alternatives(for: currentTask),
                                onStart: { begin(currentTask, framing: framing) },
                                onOptions: {
                                    SRHaptics.light()
                                    optionsTask = currentTask
                                }
                            )
                        } else {
                            EmptyCurrentCard(metrics: metrics, onCapture: { showCapture = true })
                        }

                        if waitingCount > 0, budget.showsOtherStates || isFocusLayout {
                            waitingLine
                                .padding(.top, metrics.sectionSpacing)
                        }

                        Button {
                            withAnimation(SRDesign.standardAnimation) {
                                session.isSaturated = true
                            }
                            SRTaskCommands.markSaturated(true, context: modelContext)
                            SRHaptics.soft()
                        } label: {
                            Label("Estoy saturado", systemImage: "sparkles")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(SRQuietButtonStyle())
                        .padding(.top, metrics.isTall ? 26 : 20)

                        if let flash {
                            SRFlashLine(text: flash)
                                .padding(.top, 18)
                                .transition(.opacity)
                        }
                    }
                    .srContentWidth(metrics)
                    .padding(.horizontal, metrics.pagePadding)
                    .padding(.top, metrics.isTall ? 18 : 12)
                    .padding(.bottom, metrics.scrollBottomInset)
                }
            }

            if !session.isSaturated {
                CapturePill(
                    isListening: dictation.isListening,
                    level: dictation.level,
                    transcript: dictation.transcript,
                    onCapture: {
                        if dictation.isListening {
                            _ = dictation.stop()
                        }
                        showCapture = true
                        SRHaptics.light()
                    },
                    onMicToggle: { toggleDictation() }
                )
                .srContentWidth(metrics)
                .padding(.horizontal, metrics.pagePadding)
                .padding(.bottom, metrics.pillBottomInset)
            }
        }
        .background(SRDesign.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $reasonTask) { task in
            ReasonSheet(task: task)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $insistenceTask) { task in
            InsistenceSheet(task: task)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $optionsTask, onDismiss: { resolvePendingOption() }) { task in
            TaskOptionsSheet(
                task: task,
                availableMinutes: calendar.availableMinutesNow,
                nextEventTitle: calendar.nextEvent()?.title,
                onSelect: { option in
                    pendingOption = NowPendingOption(option: option, taskID: task.id.uuidString)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $manualEstimatePlan) { plan in
            ManualTravelEstimateSheet(plan: plan)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: Binding(
            get: { session.showsDeparture },
            set: { session.showsDeparture = $0 }
        )) {
            DepartureDetailView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showWaiting) {
            WaitingView()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .fullScreenCover(item: $launch) { launch in
            ExecutionView(task: launch.task, level: launch.level, profile: launch.profile)
        }
        .sheet(item: $prepareTask) { task in
            PrepareSessionView(task: task) { level, profile in
                SRTaskCommands.start(task, context: modelContext)
                launch = SRFocusLaunch(task: task, level: level, profile: profile)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
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
        .sheet(item: $adaptationTask) { task in
            AdaptationSheet(task: task)
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
        .alert("Dictado", isPresented: Binding(get: { dictationAlert != nil }, set: { if !$0 { dictationAlert = nil } })) {
            Button("Entendido") {
                dictationAlert = nil
                dictation.dismissStatusMessage()
            }
        } message: {
            Text(dictationAlert ?? "")
        }
        .onChange(of: candidates.count) { _, count in
            if count == 0 {
                recommendationIndex = 0
            } else {
                recommendationIndex = min(recommendationIndex, count - 1)
            }
        }
        .task {
            // Phases move with time, not with taps.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                clock = Date()
            }
        }
        .task(id: tasks.count) {
            await refreshIntervention()
        }
        .onChange(of: calendar.availableMinutesNow) { _, _ in
            Task { await refreshIntervention() }
        }
        .onChange(of: session.requestedStartTaskID) { _, identifier in
            guard let identifier,
                  let task = SRTaskCommands.task(withID: identifier, context: modelContext) else { return }
            session.requestedStartTaskID = nil
            begin(task, framing: nil)
        }
        .onChange(of: session.requestedResumeTaskID) { _, identifier in
            guard let identifier,
                  let task = SRTaskCommands.task(withID: identifier, context: modelContext) else { return }
            session.requestedResumeTaskID = nil
            let stored = focus.session ?? focus.reentry
            focus.clearReentry()
            launch = SRFocusLaunch(
                task: task,
                level: stored?.level ?? .gentle,
                profile: profiles.profile(id: stored?.profileID)
            )
        }
    }

    // MARK: - The one card above the task

    @ViewBuilder
    private var attentionCard: some View {
        switch attentionSlot {
        case .trip:
            if let trip = departure.activeTrip {
                TripInProgressCard(
                    trip: trip,
                    metrics: metrics,
                    onArrived: {
                        withAnimation(SRDesign.standardAnimation) {
                            departure.confirmArrival()
                        }
                    },
                    onCancel: {
                        withAnimation(SRDesign.standardAnimation) {
                            departure.cancelTrip()
                        }
                    }
                )
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        case .tripQuestion:
            if let question = departure.pendingQuestion {
                TripQuestionCard(
                    question: question,
                    onYes: {
                        withAnimation(SRDesign.standardAnimation) {
                            departure.confirmPendingQuestion()
                        }
                    },
                    onNo: {
                        withAnimation(SRDesign.quickAnimation) {
                            departure.dismissPendingQuestion()
                        }
                    }
                )
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        case .departure:
            if let plan = departure.nextPlan {
                DepartureCard(
                    plan: plan,
                    metrics: metrics,
                    onDetails: { session.showsDeparture = true },
                    onLeaving: {
                        withAnimation(SRDesign.standardAnimation) {
                            departure.startLeaving(plan)
                        }
                    },
                    onDismiss: {
                        withAnimation(SRDesign.quickAnimation) { departure.dismiss(plan) }
                        SRHaptics.light()
                    },
                    onManualEstimate: { manualEstimatePlan = plan }
                )
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        case .reentry:
            if let interrupted = focus.reentry, let task = reentryTask {
                ReentryCard(
                    snapshot: interrupted,
                    onContinue: {
                        focus.clearReentry()
                        launch = SRFocusLaunch(
                            task: task,
                            level: interrupted.level,
                            profile: profiles.profile(id: interrupted.profileID)
                        )
                    },
                    onChangeTask: {
                        focus.clearReentry()
                        advance()
                    },
                    onClose: { focus.clearReentry() }
                )
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        case .confirmation:
            if let pending = learning.pendingConfirmation {
                LearningConfirmationCard(insight: pending) { accepted in
                    withAnimation(SRDesign.standardAnimation) {
                        if accepted {
                            learning.confirm(pending)
                        } else {
                            learning.decline(pending)
                        }
                    }
                }
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        case .suggestion:
            if let intervention {
                SuggestionCard(
                    intervention: intervention,
                    onAccept: { accept(intervention) },
                    onDismiss: { dismissIntervention(intervention) }
                )
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        case .inbox:
            inboxBanner
                .padding(.bottom, 16)
                .transition(.opacity)
        case .none:
            EmptyView()
        }
    }

    /// One quiet line of context, never two. A real hour wins over free time,
    /// because it is the only limit that cannot be negotiated.
    @ViewBuilder
    private var contextLine: some View {
        if budget.showsTimeContext, profile.shows(.nextEvent) {
            if let plan = departure.nextPlan, !departureNeedsAttention, let leaveAt = plan.leaveAt {
                SRQuietContextLine(
                    symbol: "figure.walk.departure",
                    text: "Sales a las \(SRWidgetSnapshot.timeFormatter.string(from: leaveAt)) · \(plan.destinationLabel)",
                    action: {
                        SRHaptics.light()
                        session.showsDeparture = true
                    }
                )
                .padding(.bottom, 16)
            } else if let timeContext = engine.timeContextLabel {
                SRQuietContextLine(symbol: "calendar.badge.clock", text: timeContext)
                    .padding(.bottom, 16)
            }
        }
    }

    /// Esperando has no tab of its own: it appears here as one contextual row, and
    /// only while something is actually waiting for someone else. The follow-ups
    /// live inside it, not on this screen.
    private var waitingLine: some View {
        Button {
            SRHaptics.light()
            showWaiting = true
        } label: {
            Text(waitingCount == 1
                 ? "Esperando · 1 cosa"
                 : "Esperando · \(waitingCount) cosas")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(SRQuietButtonStyle())
        .accessibilityHint("Abre lo que está esperando a otra persona")
    }

    // MARK: - Alternatives

    /// Ahora only ever offers the same two alternatives to the dominant action:
    /// cambiar de tarea y decir que no. Tools — mail, material de estudio,
    /// concentración — are never buttons here; they are opened by the action that
    /// needs them.
    private func alternatives(for task: TaskItem) -> [NowAlternative] {
        var items: [NowAlternative] = []

        if candidates.count > 1 {
            items.append(NowAlternative(label: "Otra cosa", symbol: "arrow.triangle.2.circlepath") {
                advance()
            })
        }

        items.append(NowAlternative(label: "No quiero hacer esto", symbol: "hand.raised") {
            SRHaptics.light()
            reasonTask = task
        })

        return Array(items.prefix(max(0, budget.maxAlternatives)))
    }

    private func advance() {
        guard !candidates.isEmpty else { return }
        withAnimation(SRDesign.standardAnimation) {
            recommendationIndex = (recommendationIndex + 1) % candidates.count
        }
        SRHaptics.light()
    }

    // MARK: - Options sheet

    /// Runs after the sheet is gone, so the next screen never fights with it.
    private func resolvePendingOption() {
        guard let pending = pendingOption else { return }
        pendingOption = nil
        guard let task = SRTaskCommands.task(withID: pending.taskID, context: modelContext) else { return }

        switch pending.option {
        case .decline:
            reasonTask = task
        case .smaller:
            adaptationTask = task
        case .insistence:
            insistenceTask = task
        case .postpone:
            SRTaskCommands.postpone(task, to: .after, context: modelContext)
            SRHaptics.success()
            showFlash("Lo dejamos para Después")
        case .study:
            studyTask = task
        case .mail:
            mailTask = task
        }
    }

    // MARK: - Proactivity

    /// Asks the engine whether there is one useful thing to say. Most of the time
    /// the answer is nothing, and nothing is drawn.
    private func refreshIntervention() async {
        guard !session.isSaturated else { return }
        let candidate = ProactivityEngine.nextIntervention(
            tasks: tasks,
            profile: BehaviorRecorder.profile(context: modelContext),
            availableMinutes: calendar.availableMinutesNow,
            nextEventTitle: calendar.nextEvent()?.title,
            hasRunningTask: launch != nil || focus.isRunning,
            context: modelContext
        )
        guard let candidate, candidate.id != intervention?.id else { return }
        let task = SRTaskCommands.task(withID: candidate.taskID, context: modelContext)
        ProactivityEngine.log(candidate, task: task, context: modelContext)
        withAnimation(SRDesign.standardAnimation) {
            intervention = candidate
            interventionTask = task
        }
    }

    private func accept(_ candidate: SRIntervention) {
        let task = interventionTask
        ProactivityEngine.resolve(candidate, outcome: .started, task: task, context: modelContext)
        withAnimation(SRDesign.quickAnimation) { intervention = nil }

        switch candidate.domain {
        case .review:
            let due = ReviewScheduler.dueConcepts(context: modelContext, limit: 4)
            if due.isEmpty {
                reviewConcepts = ReviewScheduler.stubbornConcepts(context: modelContext).prefix(1).map { $0 }
            } else {
                reviewConcepts = due
            }
        case .mail:
            mailTask = task
        case .study:
            studyTask = task
        case .waiting:
            showWaiting = true
        case .tasks:
            adaptationTask = task
        case .calendar, .reminders, .web:
            guard let task else { return }
            begin(task, framing: nil)
        }
    }

    /// The whole point of the phase: between "quiero hacerlo" and "ya empecé"
    /// there is at most one screen, and only when it prevents a mistake.
    private func begin(_ task: TaskItem, framing: SRTaskFraming?) {
        SRHaptics.soft()

        // The person asks for the action; SinRutina decides which tool it needs.
        // A correo opens the mail cycle and a material opens the study session,
        // instead of adding buttons to this screen.
        if task.isMail {
            SRTaskCommands.start(task, context: modelContext)
            mailTask = task
            return
        }
        if task.isStudy {
            SRTaskCommands.start(task, context: modelContext)
            studyTask = task
            return
        }

        // Starting with a reduced scope keeps that smaller movement as the step of
        // the session, so the session is about what was actually accepted.
        if let framing, framing.isReduced {
            task.nextStep = framing.headline
            task.updatedAt = Date()
            try? modelContext.save()
            BehaviorRecorder.recordMicroActionWin(framing.headline, context: modelContext)
        }

        let suggestion = profiles.suggestion(
            context: task.preferredContext,
            title: task.title,
            isStudy: task.isStudy,
            isMail: task.isMail
        )
        let level = LearningEngine.suggestedFocusLevel
            ?? suggestion?.suggestedLevel
            ?? focusPreferences.data.defaultLevel
        let isApproved = suggestion.map { profiles.isApproved($0.kind) } ?? false

        guard focusPreferences.needsPreparation(level: level, isApproved: isApproved) else {
            SRTaskCommands.start(task, context: modelContext)
            launch = SRFocusLaunch(task: task, level: level, profile: suggestion)
            return
        }
        prepareTask = task
    }

    private func dismissIntervention(_ candidate: SRIntervention) {
        ProactivityEngine.resolve(
            candidate,
            outcome: .dismissed,
            task: interventionTask,
            context: modelContext
        )
        // Being walked past changes the moment or the size, never the volume.
        if let task = interventionTask,
           ProactivityEngine.adaptation(for: task) == .ask {
            adaptationTask = task
        }
        withAnimation(SRDesign.quickAnimation) {
            intervention = nil
            interventionTask = nil
        }
    }

    /// True when the calendar leaves less room than the task needs.
    private func doesNotFit(_ task: TaskItem) -> Bool {
        guard let available = calendar.availableMinutesNow, available > 0 else { return false }
        return task.estimatedMinutes > available
    }

    private var inboxBanner: some View {
        Button {
            session.showsInbox = true
            SRHaptics.light()
        } label: {
            HStack(spacing: 12) {
                SRIconBadge(symbol: "tray.full", tint: SRDesign.lavender, size: 38)
                VStack(alignment: .leading, spacing: 2) {
                    Text(session.pendingInboxItems.count == 1
                         ? "Algo llegó desde otra app"
                         : "\(session.pendingInboxItems.count) cosas llegaron de otras apps")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SRDesign.ink)
                    Text("Decide una sola cosa por cada una")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            .padding(14)
            .srSurface(radius: metrics.rowRadius, accent: SRDesign.lavender)
        }
        .buttonStyle(SRPressStyle())
    }

    /// Perceptible, short confirmation for actions that would otherwise leave the
    /// person wondering whether the tap registered.
    private func showFlash(_ text: String) {
        withAnimation(SRDesign.standardAnimation) { flash = text }
        Task {
            try? await Task.sleep(for: .seconds(3))
            if flash == text {
                withAnimation(SRDesign.quickAnimation) { flash = nil }
            }
        }
    }

    private func toggleDictation() {
        if dictation.isListening {
            let spoken = dictation.stop()
            dictation.reset()
            guard !spoken.isEmpty else {
                SRHaptics.light()
                return
            }
            isReadingVoice = true
            Task {
                let suggestion = await SRIntelligenceService.shared.suggestion(for: spoken)
                let task = SRTaskCommands.create(from: suggestion, source: "voz", context: modelContext)
                isReadingVoice = false
                SRHaptics.success()
                showFlash("Guardado: \(task.title)")
            }
            return
        }

        SRHaptics.soft()
        withAnimation(SRDesign.standardAnimation) { flash = nil }
        Task {
            let started = await dictation.start()
            if !started {
                dictationAlert = dictation.statusMessage ?? "No pudimos escuchar ahora mismo."
            }
        }
    }

    /// The close of the day is not a permanent function: it only appears when the
    /// day is actually ending.
    private var showsEndOfDayButton: Bool {
        let hour = Calendar.current.component(.hour, from: clock)
        return hour >= 19 || hour < 4
    }

    private var header: some View {
        HStack {
            if profile.shows(.logo) {
                SRLogo(size: metrics.isTall ? 34 : 30, showsWordmark: true)
            }

            Spacer()

            if showsEndOfDayButton {
                Button {
                    showEndOfDay = true
                    SRHaptics.light()
                } label: {
                    Image(systemName: "moon.stars")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(SRDesign.secondaryInk)
                        .frame(width: 44, height: 44)
                        .background(SRDesign.surface)
                        .clipShape(Circle())
                }
                .accessibilityLabel("Cierre del día")
                .transition(.opacity)
            }
        }
        .frame(minHeight: 44)
    }
}

/// Which single card is allowed above the task right now.
private enum NowAttentionSlot: Equatable {
    case trip
    case tripQuestion
    case departure
    case reentry
    case confirmation
    case suggestion
    case inbox
}

/// An immediate alternative to the dominant action. There are never more than two.
private struct NowAlternative: Identifiable {
    let label: String
    let symbol: String
    let action: () -> Void

    var id: String { label }
}

/// A choice made inside the options sheet, resolved once it has closed.
private struct NowPendingOption: Identifiable {
    let option: SRTaskOption
    let taskID: String

    var id: String { "\(option.rawValue)-\(taskID)" }
}

private struct CurrentTaskCard: View {
    let task: TaskItem
    let metrics: SRMetrics
    let profile: SRAppearanceProfile
    let budget: SRInformationBudget
    let framing: SRTaskFraming
    let doesNotFit: Bool
    let alternatives: [NowAlternative]
    let onStart: () -> Void
    let onOptions: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SRSectionLabel(text: framing.isReduced ? "Empieza por aquí" : "Tarea actual")
                    .foregroundStyle(SRDesign.primary)
                if task.isDemo {
                    SRDemoTag()
                }
                Spacer(minLength: 6)
            }
            .padding(.bottom, metrics.isTall ? 18 : 14)

            HStack(alignment: .top, spacing: 16) {
                if budget.showsExtras {
                    SRIconBadge(symbol: iconName, tint: SRDesign.primary, size: metrics.badgeSize)
                }

                VStack(alignment: .leading, spacing: 8) {
                    // The single most prominent thing on the screen.
                    Text(framing.headline)
                        .font(metrics.isTall ? .title.weight(.bold) : .title2.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let support = framing.support, framing.isReduced || profile.shows(.reason) {
                        Text(support)
                            .font(.subheadline)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .lineLimit(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let meta = metaLine {
                        Text(meta)
                            .font(.footnote)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                }
            }

            if doesNotFit, budget.showsMeta, profile.shows(.calendarState) {
                // Temporal facts stay neutral: no warning colour, no exclamation.
                Text("Antes de tu próximo evento entra solo un trozo.")
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            Button(framing.primaryLabel, action: onStart)
                .buttonStyle(SRPrimaryButtonStyle())
                .padding(.top, metrics.isTall ? 26 : 20)

            if !alternatives.isEmpty {
                HStack(spacing: 12) {
                    ForEach(alternatives) { alternative in
                        Button(action: alternative.action) {
                            HStack(spacing: 6) {
                                Image(systemName: alternative.symbol)
                                    .font(.system(size: 12, weight: .semibold))
                                Text(alternative.label)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.9)
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                        }
                        .buttonStyle(SRQuietButtonStyle())
                    }
                }
                .padding(.top, 10)
            }

            Button(action: onOptions) {
                Text("Más opciones")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
            }
            .buttonStyle(SRPressStyle())
            .padding(.top, alternatives.isEmpty ? 8 : 2)
            .accessibilityHint("Insistencia, archivos, detalles y otras salidas")
        }
        .padding(metrics.cardPadding)
        .srCard(radius: metrics.cardRadius)
        .overlay(alignment: .top) {
            Capsule(style: .continuous)
                .fill(SRDesign.primary.opacity(0.85))
                .frame(width: 44, height: 4)
                .padding(.top, 10)
                .allowsHitTesting(false)
        }
        .padding(.top, metrics.heroTopLift)
        .accessibilityElement(children: .contain)
    }

    /// At most one quiet line of metadata, built from what the person left visible.
    private var metaLine: String? {
        guard budget.showsMeta else { return nil }
        var parts: [String] = []
        if profile.shows(.duration) {
            parts.append("\(framing.minutes) min")
        }
        if profile.shows(.dueTime), let due = task.dueDate {
            parts.append(SRWidgetSnapshot.timeFormatter.string(from: due))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private var iconName: String {
        switch task.preferredContext {
        case "comunicación": return "phone"
        case "administrativo": return "doc.text"
        case "dinero": return "creditcard"
        case "salud": return "heart"
        case "trabajo": return "briefcase"
        case "casa": return "house"
        case "estudio": return "book"
        default: break
        }
        let title = task.title.lowercased()
        if title.contains("llamar") { return "phone" }
        if title.contains("enviar") || title.contains("correo") { return "paperplane" }
        if title.contains("revisar") || title.contains("documento") { return "doc.text" }
        return "sparkles"
    }
}

private struct EmptyCurrentCard: View {
    let metrics: SRMetrics
    let onCapture: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(SRDesign.primary)
            Text("No hay nada urgente ahora")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text("Captura cualquier cosa y la veremos cuando toque.")
                .font(.body)
                .foregroundStyle(SRDesign.secondaryInk)
            Button("Capturar algo", action: onCapture)
                .buttonStyle(SRPrimaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(metrics.cardPadding + 2)
        .srCard()
    }
}
