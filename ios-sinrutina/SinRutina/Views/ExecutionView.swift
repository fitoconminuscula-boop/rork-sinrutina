import SwiftUI
import SwiftData

/// Everything needed to open the execution screen: the task and the environment
/// the person confirmed for it.
struct SRFocusLaunch: Identifiable {
    var task: TaskItem
    var level: SRFocusLevel
    var profile: SRFocusProfileDefinition?

    var id: UUID { task.id }
}

/// The execution interface.
///
/// While something is running, this screen shows only what is indispensable: the
/// task, the next movement, optionally the time, and the way out. No pending
/// list, no counters, no metrics.
struct ExecutionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics

    let task: TaskItem
    var level: SRFocusLevel = .gentle
    var profile: SRFocusProfileDefinition?
    /// Set when the person is coming back to an interrupted session.
    var isResuming: Bool = false

    @State private var appearance = SRAppearanceStore.shared
    @State private var focusPreferences = SRFocusPreferences.shared
    @State private var manager = FocusSessionManager.shared
    @State private var screenTime = ScreenTimeService.shared

    @State private var showsFriction = false
    @State private var showsPauseOptions = false
    @State private var showsBreakEnded = false
    @State private var showsSteps = false
    @State private var showsPartial = false
    @State private var showsRecall = false
    @State private var showsTransition = false
    @State private var showsAdaptation = false
    @State private var showsAppRelease = false
    @State private var showsAppException = false
    @State private var showsOptions = false
    @State private var pendingOption: SRExecutionOption?
    @State private var wasPartial = false
    /// What the friction is for: leaving, pausing, or releasing one app.
    @State private var frictionPurpose: FrictionPurpose = .changeCourse
    @State private var releasedAppName: String?

    private enum FrictionPurpose {
        case changeCourse
        case pause
        case releaseApp
    }

    private var visual: SRAppearanceProfile { appearance.profile }
    /// The timer can be switched off entirely: the session is still recorded.
    private var showsTimer: Bool {
        focusPreferences.data.showsTimer && visual.shows(.timeProgress)
    }
    private var isOnlyTask: Bool { focusPreferences.data.onlyTaskMode }
    private var activeLevel: SRFocusLevel { manager.isRunning ? manager.level : level }
    private var estimatedSeconds: TimeInterval { max(Double(task.estimatedMinutes) * 60, 120) }

    var body: some View {
        ZStack {
            SRDesign.background.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar

                Spacer(minLength: 8)

                if !isOnlyTask, visual.presence != .minimal {
                    SRPresenceView(state: manager.isPaused || manager.isOnBreak ? .waiting : .focusing, size: 52)
                        .padding(.bottom, 20)
                }

                Text(task.title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(SRDesign.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 26)

                if let step = task.nextStep, !step.isEmpty {
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 30)
                        .padding(.top, 8)
                }

                if !isOnlyTask, visual.shows(.duration) {
                    Text("\(task.estimatedMinutes) min estimados")
                        .font(.headline)
                        .foregroundStyle(SRDesign.primary)
                        .padding(.top, 10)
                }

                if manager.isOnBreak, let endsAt = manager.breakEndsAt {
                    breakBanner(endsAt: endsAt)
                        .padding(.top, 20)
                        .padding(.horizontal, metrics.pagePadding)
                } else if showsTimer, !isOnlyTask {
                    clock
                        .padding(.top, 22)
                }

                if let notice = manager.recoveryNotice, !isOnlyTask {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, metrics.pagePadding)
                        .padding(.top, 16)
                }

                Spacer(minLength: 8)

                actions
            }
        }
        .statusBarHidden(true)
        .task {
            if !manager.isRunning(taskID: task.id) {
                manager.start(task: task, level: level, profile: profile, context: modelContext)
            }
        }
        .onChange(of: manager.pendingPauseRequest?.createdAt) { _, value in
            // The shield asked for the way out: that is where the ten seconds live.
            guard value != nil else { return }
            manager.noteExitAttempt(appLabel: manager.pendingPauseRequest?.appLabel)
            manager.consumePauseRequest()
            frictionPurpose = .pause
            showsFriction = true
        }
        .onChange(of: manager.breakHasEnded()) { _, ended in
            guard ended else { return }
            showsBreakEnded = true
        }
        .fullScreenCover(isPresented: $showsFriction) {
            FrictionGateView(
                seconds: manager.frictionSeconds,
                taskTitle: task.title,
                onCompleted: { frictionPassed() },
                onEmergency: { manager.emergency(context: modelContext) }
            )
        }
        .sheet(isPresented: $showsPauseOptions) {
            PauseOptionsView(
                onBreak: { minutes in manager.grantBreak(minutes: minutes, context: modelContext) },
                onEndMode: { endMode() }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsBreakEnded) {
            BreakEndedSheet(
                taskTitle: task.title,
                onResume: { manager.resume() },
                onStop: { endMode() }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsSteps) {
            StepByStepView(task: task)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showsPartial) {
            PartialProgressSheet(
                task: task,
                minutes: manager.elapsedSeconds() / 60,
                onSaved: { _ in finishPartially() }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAdaptation) {
            AdaptationSheet(task: task)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAppRelease) {
            AppReleaseSheet(
                profile: profile ?? SRFocusProfileStore.shared.profile(id: manager.session?.profileID),
                onRelease: { name in
                    releasedAppName = name
                    manager.release(app: name)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsOptions, onDismiss: { resolveOption() }) {
            ExecutionOptionsSheet(
                canReleaseApp: activeLevel.blocksApps && manager.restrictionsActive,
                onSelect: { pendingOption = $0 }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsAppException) {
            AppExceptionSheet(
                appName: releasedAppName ?? "esa app",
                profileName: profile?.name ?? "este",
                onAccept: {
                    guard let profile, let name = releasedAppName else { return }
                    SRFocusProfileStore.shared.addApp(name, to: profile)
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showsRecall, onDismiss: { openTransition() }) {
            RecallView(task: task, material: nil)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .fullScreenCover(isPresented: $showsTransition) {
            TransitionView(
                taskTitle: task.title,
                wasPartial: wasPartial,
                onSeeWhatsNext: { dismiss() },
                onRest: { dismiss() },
                onClose: { dismiss() }
            )
        }
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack(spacing: 10) {
            Button {
                requestExit()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .frame(width: 44, height: 44)
                    .background(SRDesign.surface)
                    .clipShape(Circle())
            }
            .accessibilityLabel("Salir de la sesión")

            Spacer(minLength: 0)

            if !isOnlyTask {
                levelChip
            }

            if activeLevel.blocksApps {
                Button {
                    urgency()
                } label: {
                    Text("Urgencia")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(SRDesign.secondaryInk)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(SRDesign.surface)
                        .clipShape(Capsule(style: .continuous))
                }
                .accessibilityHint("Devuelve el acceso completo al iPhone")
            }
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, 12)
    }

    private var levelChip: some View {
        HStack(spacing: 5) {
            Image(systemName: activeLevel.symbolName)
                .font(.system(size: 11, weight: .semibold))
            Text(manager.restrictionsActive ? activeLevel.label : "\(activeLevel.label) · sin bloqueo")
                .font(.caption.weight(.semibold))
                .lineLimit(1)
        }
        .foregroundStyle(SRDesign.primary)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(SRDesign.primarySoft.opacity(0.7))
        .clipShape(Capsule(style: .continuous))
    }

    private var clock: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = manager.elapsedSeconds(at: context.date)
            let remaining = max(0, estimatedSeconds - elapsed)
            ZStack {
                Circle()
                    .stroke(SRDesign.primarySoft, lineWidth: 12)
                Circle()
                    .trim(from: 0, to: min(1, elapsed / estimatedSeconds))
                    .stroke(SRDesign.primary, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(SRDesign.quickAnimation, value: elapsed)
                VStack(spacing: 4) {
                    Text(formatTime(remaining))
                        .font(.largeTitle.weight(.medium))
                        .monospacedDigit()
                        .foregroundStyle(SRDesign.ink)
                    Text(manager.isPaused ? "en pausa" : "tiempo restante")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.primary)
                }
            }
            .frame(width: metrics.isTall ? 238 : 214, height: metrics.isTall ? 238 : 214)
        }
    }

    private func breakBanner(endsAt: Date) -> some View {
        VStack(spacing: 6) {
            Text("Descanso hasta \(SRWidgetSnapshot.timeFormatter.string(from: endsAt))")
                .font(.headline)
                .foregroundStyle(SRDesign.ink)
            Text("Te pregunto cuando termine.")
                .font(.footnote)
                .foregroundStyle(SRDesign.secondaryInk)
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .srSurface(radius: metrics.rowRadius, accent: SRDesign.lavender)
    }

    /// During a session the screen holds one dominant action and, at most, two
    /// alternatives. Everything else — leaving, partial progress, releasing an app
    /// — waits behind "Más opciones", where it costs one deliberate tap.
    private var actions: some View {
        VStack(spacing: 0) {
            Button {
                finish()
            } label: {
                Text("Terminé")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .padding(.horizontal, metrics.pagePadding)

            if !isOnlyTask {
                HStack(spacing: 12) {
                    Button {
                        togglePause()
                    } label: {
                        Label(
                            manager.isPaused || manager.isOnBreak ? "Seguir" : "Pausa",
                            systemImage: manager.isPaused || manager.isOnBreak ? "play" : "pause"
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                    }
                    .buttonStyle(SRQuietButtonStyle())

                    Button {
                        SRHaptics.light()
                        showsSteps = true
                    } label: {
                        Label("Hazlo conmigo", systemImage: "list.bullet")
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                    }
                    .buttonStyle(SRQuietButtonStyle())
                }
                .padding(.horizontal, metrics.pagePadding)
                .padding(.top, 10)

                Button {
                    SRHaptics.light()
                    showsOptions = true
                } label: {
                    Text("Más opciones")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(SRDesign.secondaryInk)
                        .frame(maxWidth: .infinity)
                        .frame(height: 38)
                }
                .buttonStyle(SRPressStyle())
                .padding(.horizontal, metrics.pagePadding)
                .accessibilityHint("Salir, guardar lo avanzado o pedir una app")
            }
        }
        .padding(.bottom, 26)
    }

    // MARK: - Actions

    /// Resolved after the sheet closes so two screens never overlap.
    private func resolveOption() {
        guard let option = pendingOption else { return }
        pendingOption = nil
        switch option {
        case .changeCourse:
            requestExit()
        case .partial:
            showsPartial = true
        case .releaseApp:
            frictionPurpose = .releaseApp
            showsFriction = activeLevel == .deep
            if !showsFriction { showsAppRelease = true }
        }
    }

    private func togglePause() {
        if manager.isPaused || manager.isOnBreak {
            manager.resume()
        } else {
            manager.pause(context: modelContext)
            showsPauseOptions = true
        }
        SRHaptics.light()
    }

    /// Leaving mid-session. With restrictions on, it costs the deliberate seconds;
    /// without them, one tap is enough — friction that protects nothing is noise.
    private func requestExit() {
        guard manager.restrictionsActive else {
            leaveSession()
            return
        }
        manager.noteExitAttempt(appLabel: nil)
        frictionPurpose = .changeCourse
        showsFriction = true
    }

    private func frictionPassed() {
        FrictionEngine.record(
            completed: true,
            taskID: task.id.uuidString,
            profileKind: profile?.kind,
            level: activeLevel
        )
        switch frictionPurpose {
        case .pause:
            showsPauseOptions = true
        case .releaseApp:
            showsAppRelease = true
        case .changeCourse:
            // Repeated attempts mean the task is wrong, not that the person is weak.
            if manager.exitAttempts >= 3 {
                showsAdaptation = true
            } else {
                showsPauseOptions = true
            }
        }
    }

    private func urgency() {
        manager.emergency(context: modelContext)
        SRHaptics.success()
    }

    private func leaveSession() {
        _ = manager.finish(completed: false, context: modelContext)
        SRTaskCommands.postpone(task, context: modelContext)
        dismiss()
    }

    /// Ends the environment without touching the task: the phone goes back to
    /// normal and the task keeps its place.
    private func endMode() {
        manager.suspendForReentry()
        dismiss()
    }

    private func finish() {
        let minutes = manager.finish(completed: true, context: modelContext)
        SRTaskCommands.complete(task, actualMinutes: minutes, context: modelContext)
        SRHaptics.success()
        wasPartial = false
        if releasedAppName != nil, profile != nil {
            showsAppException = true
            return
        }
        if task.isStudy, minutes >= 3 {
            showsRecall = true
            return
        }
        openTransition()
    }

    private func finishPartially() {
        _ = manager.finish(completed: false, context: modelContext)
        wasPartial = true
        openTransition()
    }

    private func openTransition() {
        showsTransition = true
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        return String(format: "%02d:%02d", total / 60, total % 60)
    }
}

/// "Necesito esta app": one exception, for this session only.
struct AppReleaseSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    let profile: SRFocusProfileDefinition?
    let onRelease: (String) -> Void

    @State private var custom = ""

    private var candidates: [String] {
        var names = ["Safari", "Archivos", "Notas", "Mail"]
        if let profile {
            names.removeAll { name in
                profile.appNames.contains { $0.caseInsensitiveCompare(name) == .orderedSame }
            }
        }
        return names
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("¿Qué app necesitas?")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)

            Text("Se abre solo durante esta tarea. Al terminar, vuelve a su sitio.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 8) {
                ForEach(candidates, id: \.self) { name in
                    Button {
                        SRHaptics.light()
                        onRelease(name)
                        dismiss()
                    } label: {
                        HStack {
                            Text(name)
                                .font(.body.weight(.medium))
                                .foregroundStyle(SRDesign.ink)
                            Spacer(minLength: 0)
                            Image(systemName: "lock.open")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SRDesign.primary)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .srCard(radius: metrics.rowRadius)
                    }
                    .buttonStyle(SRPressStyle())
                }
            }
            .padding(.top, 18)

            HStack(spacing: 10) {
                TextField("Otra app", text: $custom)
                    .textFieldStyle(.plain)
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(SRDesign.elevatedSurface)
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))

                Button("Abrir") {
                    let trimmed = custom.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { return }
                    onRelease(trimmed)
                    dismiss()
                }
                .buttonStyle(SRQuietButtonStyle())
            }
            .padding(.top, 16)

            Text("SinRutina solo puede liberar apps que ya estén elegidas en el perfil. Si no aparece, añádela en Ajustes.")
                .font(.caption2)
                .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 14)
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SRDesign.background.ignoresSafeArea())
    }
}
