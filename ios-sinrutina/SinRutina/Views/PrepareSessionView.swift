import SwiftUI
import SwiftData

/// "¿Qué necesitas para terminar esto?"
///
/// The screen that exists so SinRutina never blocks a tool the task depends on.
/// It shows what will stay available, what will be closed, and hands the decision
/// to the person. Nothing is restricted until "Empezar".
struct PrepareSessionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics

    let task: TaskItem
    /// Called with the level and profile the person confirmed.
    let onStart: (SRFocusLevel, SRFocusProfileDefinition?) -> Void

    @State private var appearance = SRAppearanceStore.shared
    @State private var profiles = SRFocusProfileStore.shared
    @State private var preferences = SRFocusPreferences.shared
    @State private var screenTime = ScreenTimeService.shared

    @State private var level: SRFocusLevel = .gentle
    @State private var selectedProfileID: UUID?
    @State private var extraApps: [String] = []
    @State private var newApp = ""
    @State private var isAddingApp = false
    @State private var acceptedSuggestion = false

    private var profile: SRAppearanceProfile { appearance.profile }

    private var suggestedProfile: SRFocusProfileDefinition? {
        profiles.suggestion(
            context: task.preferredContext,
            title: task.title,
            isStudy: task.isStudy,
            isMail: task.isMail
        )
    }

    private var chosenProfile: SRFocusProfileDefinition? {
        profiles.profile(id: selectedProfileID) ?? suggestedProfile
    }

    /// Everything that will stay reachable, said in the person's own words.
    private var neededApps: [String] {
        var names = chosenProfile?.appNames ?? []
        for app in task.allowedApps where !names.contains(where: { $0.caseInsensitiveCompare(app) == .orderedSame }) {
            names.append(app)
        }
        for app in extraApps where !names.contains(where: { $0.caseInsensitiveCompare(app) == .orderedSame }) {
            names.append(app)
        }
        if !names.contains(where: { $0.caseInsensitiveCompare("SinRutina") == .orderedSame }) {
            names.append("SinRutina")
        }
        return names
    }

    /// Levels that restrict apps are only offered when they can really restrict.
    private func isAvailable(_ option: SRFocusLevel) -> Bool {
        !option.blocksApps || screenTime.canBlockApps
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                Text(task.title)
                    .font(.title.weight(.bold))
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 6)

                if let step = task.nextStep, !step.isEmpty {
                    Text(step)
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 8)
                }

                needsBlock
                    .padding(.top, 22)

                levelBlock
                    .padding(.top, 24)

                if let suggestion = suggestedProfile, selectedProfileID == nil, !acceptedSuggestion {
                    suggestionBlock(suggestion)
                        .padding(.top, 18)
                }

                if !screenTime.canBlockApps {
                    blockingUnavailableNotice
                        .padding(.top, 18)
                }

                Button {
                    start()
                } label: {
                    Text("Empezar")
                }
                .buttonStyle(SRPrimaryButtonStyle())
                .padding(.top, 26)

                Button("Ahora no") {
                    dismiss()
                }
                .buttonStyle(SRQuietButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.top, 14)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.top, 18)
            .padding(.bottom, 34)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .task {
            screenTime.refreshAccessState()
            level = initialLevel()
            selectedProfileID = suggestedProfile.flatMap { profiles.isApproved($0.kind) ? $0.id : nil }
        }
        .onChange(of: screenTime.canBlockApps) { _, canBlock in
            // Never leave an unavailable level selected.
            if !canBlock, level.blocksApps {
                withAnimation(SRDesign.quickAnimation) { level = .gentle }
            }
        }
    }

    // MARK: - Pieces

    private var header: some View {
        HStack(spacing: 12) {
            if profile.presence.showsInSheets {
                SRPresenceView(state: .suggesting, size: 34)
            }
            Text("¿Qué necesitas para terminar esto?")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    private var needsBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Necesitarás")

            if neededApps.isEmpty {
                Text("Nada en particular.")
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.secondaryInk)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(neededApps, id: \.self) { app in
                        appChip(app)
                    }
                }
            }

            if profile.shows(.duration) {
                Text("Duración estimada: \(task.estimatedMinutes) min.")
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
            }

            if isAddingApp {
                HStack(spacing: 10) {
                    TextField("Nombre de la app", text: $newApp)
                        .textFieldStyle(.plain)
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 42)
                        .background(SRDesign.elevatedSurface)
                        .clipShape(.rect(cornerRadius: 12, style: .continuous))
                        .submitLabel(.done)
                        .onSubmit { addApp() }

                    Button("Añadir") { addApp() }
                        .buttonStyle(SRQuietButtonStyle())
                        .disabled(newApp.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                .transition(.opacity)
            } else {
                Button {
                    withAnimation(SRDesign.quickAnimation) { isAddingApp = true }
                    SRHaptics.light()
                } label: {
                    Label("¿Falta algo? Añadir app", systemImage: "plus.circle")
                }
                .buttonStyle(SRQuietButtonStyle())
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard(radius: metrics.cardRadius)
    }

    private func appChip(_ name: String) -> some View {
        Text(name)
            .font(.caption.weight(.medium))
            .foregroundStyle(SRDesign.primary)
            .lineLimit(1)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(maxWidth: .infinity)
            .background(SRDesign.primarySoft.opacity(0.72))
            .clipShape(Capsule(style: .continuous))
    }

    private var levelBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Nivel de concentración")

            VStack(spacing: 8) {
                ForEach(SRFocusLevel.allCases) { option in
                    let available = isAvailable(option)
                    Button {
                        withAnimation(SRDesign.quickAnimation) { level = option }
                        SRHaptics.light()
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: available ? option.symbolName : "lock.slash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(level == option ? SRDesign.primary : SRDesign.secondaryInk)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(available ? option.label : "\(option.label) — no disponible todavía")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SRDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(available ? option.detail : "Necesita el permiso de Tiempo de uso de Apple.")
                                    .font(.caption)
                                    .foregroundStyle(SRDesign.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            if level == option, available {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(SRDesign.primary)
                            }
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .srSurface(radius: metrics.rowRadius, accent: level == option ? SRDesign.primary : nil)
                    }
                    .buttonStyle(SRPressStyle())
                    .disabled(!available)
                    .opacity(available ? 1 : 0.5)
                    .accessibilityHint(available ? "" : "No disponible: falta el permiso de Tiempo de uso.")
                }
            }

            if let suggested = LearningEngine.suggestedFocusLevel, suggested != level {
                Text("Sueles terminar más en \(suggested.label).")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
            }

            if LearningEngine.environmentIsTooTight, level == .deep {
                Text("Últimamente Profundo te genera más fricción que ayuda.")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func suggestionBlock(_ suggestion: SRFocusProfileDefinition) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Parece una tarea de \(suggestion.name.lowercased()).")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text(suggestion.appsLine)
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("Usar este perfil") {
                    withAnimation(SRDesign.quickAnimation) {
                        selectedProfileID = suggestion.id
                        acceptedSuggestion = true
                        level = suggestion.suggestedLevel
                    }
                    profiles.approve(suggestion.kind)
                    SRHaptics.light()
                }
                .buttonStyle(SRQuietButtonStyle())

                Button("No hace falta") {
                    withAnimation(SRDesign.quickAnimation) {
                        acceptedSuggestion = true
                        selectedProfileID = nil
                    }
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(SRDesign.secondaryInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srSurface(radius: metrics.rowRadius, accent: SRDesign.lavender)
    }

    /// Says exactly what is off and why, without offering a block that would not happen.
    private var blockingUnavailableNotice: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 9) {
                Image(systemName: "lock.slash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SRDesign.secondaryInk)
                Text("Bloqueo de apps — no disponible todavía")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(screenTime.access.explanation)
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Text("Suave sí funciona por completo: una sola tarea, recordatorios, segundos de espera al salir y sesión en pantalla bloqueada.")
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if screenTime.access == .notDetermined {
                Button("Dar permiso a SinRutina") {
                    Task { await screenTime.requestAccess() }
                }
                .buttonStyle(SRQuietButtonStyle())
            } else {
                ForEach(screenTime.access.recoverySteps, id: \.self) { step in
                    HStack(alignment: .top, spacing: 7) {
                        Text("•")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                        Text(step)
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srSurface(radius: metrics.rowRadius, accent: SRDesign.blush)
    }

    // MARK: - Actions

    private func initialLevel() -> SRFocusLevel {
        // Without the Screen Time permission there is only one honest level.
        guard screenTime.canBlockApps else { return .gentle }
        if let learned = LearningEngine.suggestedFocusLevel { return learned }
        if let suggestion = suggestedProfile, profiles.isApproved(suggestion.kind) {
            return suggestion.suggestedLevel
        }
        // Short errands never need a wall around them.
        if task.estimatedMinutes <= 8 { return .gentle }
        return preferences.data.defaultLevel
    }

    private func addApp() {
        let trimmed = newApp.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        withAnimation(SRDesign.quickAnimation) {
            extraApps.append(trimmed)
            newApp = ""
            isAddingApp = false
        }
        SRHaptics.light()
    }

    private func start() {
        // Last gate: a level that cannot be applied never reaches the session.
        let effective = isAvailable(level) ? level : .gentle
        // Whatever was added here belongs to the task from now on.
        if !extraApps.isEmpty {
            var apps = task.allowedApps
            for app in extraApps where !apps.contains(app) { apps.append(app) }
            task.allowedApps = apps
            try? modelContext.save()
        }
        SRHaptics.soft()
        onStart(effective, chosenProfile)
        dismiss()
    }
}
