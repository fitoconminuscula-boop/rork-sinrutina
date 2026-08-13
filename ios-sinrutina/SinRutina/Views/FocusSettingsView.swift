import SwiftUI
import SwiftData
#if canImport(FamilyControls)
import FamilyControls
#endif

/// "Modo enfoque" in Ajustes: the environment, the profiles, the friction and the
/// history — all editable, none of it applied without a decision.
struct FocusSettingsView: View {
    @Environment(\.srMetrics) private var metrics

    @State private var preferences = SRFocusPreferences.shared
    @State private var profiles = SRFocusProfileStore.shared
    @State private var screenTime = ScreenTimeService.shared
    @State private var editingProfile: SRFocusProfileDefinition?
    @State private var showsDistractorPicker = false
    @State private var showsHistory = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Modo enfoque")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("SinRutina transforma el iPhone un rato para que puedas hacer algo que tú elegiste. Nunca para controlarte.")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)

                permissionSection
                levelSection
                profilesSection
                frictionSection
                sessionSection
                historySection
            }
            .srContentWidth(metrics)
            .padding(.horizontal, SRDesign.pagePadding)
            .padding(.bottom, 34)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("Modo enfoque")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingProfile) { profile in
            NavigationStack {
                FocusProfileEditorView(profile: profile)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showsHistory) {
            DistractionHistoryView()
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .task {
            screenTime.refreshAccessState()
            // A stored default that can no longer be applied is corrected, not faked.
            if !screenTime.canBlockApps, preferences.data.defaultLevel.blocksApps {
                preferences.update { $0.defaultLevel = .gentle }
            }
        }
        #if canImport(FamilyControls)
        .familyActivityPicker(
            isPresented: $showsDistractorPicker,
            selection: Binding(
                get: { screenTime.loadGlobalDistractors() },
                set: { screenTime.saveGlobalDistractors($0) }
            )
        )
        #endif
    }

    // MARK: - Sections

    private var permissionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Bloqueo de apps")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: screenTime.access.isGranted ? "lock.shield" : "lock.open")
                        .font(.system(size: 17, weight: .medium))
                        .foregroundStyle(SRDesign.primary)
                        .frame(width: 30, height: 30)
                        .background(SRDesign.primarySoft)
                        .clipShape(Circle())
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Tiempo de uso de Apple")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Text(permissionDetail)
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }

                if screenTime.access == .notDetermined {
                    Button("Dar permiso") {
                        Task { await screenTime.requestAccess() }
                    }
                    .buttonStyle(SRQuietButtonStyle())
                } else if !screenTime.canBlockApps {
                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(screenTime.access.recoverySteps, id: \.self) { step in
                            HStack(alignment: .top, spacing: 7) {
                                Text("\u{2022}")
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

                if let notice = screenTime.lastNotice {
                    Text(notice)
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().overlay(SRDesign.divider)

                Button {
                    #if canImport(FamilyControls)
                    showsDistractorPicker = true
                    #endif
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: "app.badge")
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(SRDesign.primary)
                            .frame(width: 30, height: 30)
                            .background(SRDesign.primarySoft)
                            .clipShape(Circle())
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Apps que te distraen")
                                .font(.body.weight(.medium))
                                .foregroundStyle(SRDesign.ink)
                            Text(screenTime.globalDistractorCount == 0
                                 ? "Sin elegir todavía"
                                 : "\(screenTime.globalDistractorCount) elegidas")
                                .font(.caption)
                                .foregroundStyle(SRDesign.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SRDesign.secondaryInk.opacity(0.75))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!screenTime.canBlockApps)
                .opacity(screenTime.canBlockApps ? 1 : 0.55)

                Text(screenTime.canBlockApps
                     ? "Estas apps son las que Enfoque cierra. Profundo usa la lista de cada perfil."
                     : "Elegir apps solo tiene sentido cuando el bloqueo está disponible, así que está desactivado.")
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        }
    }

    private var levelSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Nivel por defecto")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(SRFocusLevel.allCases) { level in
                    let available = !level.blocksApps || screenTime.canBlockApps
                    Button {
                        preferences.update { $0.defaultLevel = level }
                        SRHaptics.light()
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: available ? level.symbolName : "lock.slash")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(preferences.data.defaultLevel == level ? SRDesign.primary : SRDesign.secondaryInk)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(available ? level.label : "\(level.label) — no disponible todavía")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SRDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(available ? level.detail : "Necesita el permiso de Tiempo de uso de Apple.")
                                    .font(.caption)
                                    .foregroundStyle(SRDesign.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            if preferences.data.defaultLevel == level, available {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(SRDesign.primary)
                            }
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .srSurface(radius: metrics.rowRadius, accent: preferences.data.defaultLevel == level ? SRDesign.primary : nil)
                    }
                    .buttonStyle(SRPressStyle())
                    .disabled(!available)
                    .opacity(available ? 1 : 0.5)
                }
            }

            Text("Cada tarea puede usar otro nivel antes de empezar. Esto es solo el punto de partida.")
                .font(.caption2)
                .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.leading, 4)
        }
    }

    private var profilesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Perfiles")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                ForEach(profiles.profiles) { profile in
                    Button {
                        editingProfile = profile
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: profile.kind.symbolName)
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(SRDesign.primary)
                                .frame(width: 30, height: 30)
                                .background(SRDesign.primarySoft)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(profile.name)
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(SRDesign.ink)
                                Text(profile.appsLine)
                                    .font(.caption)
                                    .foregroundStyle(SRDesign.secondaryInk)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SRDesign.secondaryInk.opacity(0.75))
                        }
                        .padding(.vertical, 14)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if profile.id != profiles.profiles.last?.id {
                        Divider().overlay(SRDesign.divider).padding(.leading, 44)
                    }
                }
            }
            .padding(.horizontal, 16)
            .srCard()

            HStack(spacing: 16) {
                Button("Nuevo perfil") {
                    let created = SRFocusProfileDefinition(
                        kind: .custom,
                        name: "Perfil nuevo",
                        isBuiltIn: false
                    )
                    profiles.upsert(created)
                    editingProfile = created
                    SRHaptics.light()
                }
                .buttonStyle(SRQuietButtonStyle())

                Button("Restablecer los de fábrica") {
                    profiles.restoreTemplates()
                    SRHaptics.light()
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(SRDesign.secondaryInk)
            }
            .padding(.top, 12)
            .padding(.leading, 4)
        }
    }

    private var frictionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Salir de una sesión")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Forma de confirmar")
                        .font(.body.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                    ForEach(SRFrictionStyle.allCases) { style in
                        Button {
                            preferences.update { $0.frictionStyle = style }
                            SRHaptics.light()
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: style.symbolName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(preferences.data.frictionStyle == style ? SRDesign.primary : SRDesign.secondaryInk)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(style.label)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(SRDesign.ink)
                                    Text(style.detail)
                                        .font(.caption)
                                        .foregroundStyle(SRDesign.secondaryInk)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                Spacer(minLength: 0)
                                if preferences.data.frictionStyle == style {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(SRDesign.primary)
                                }
                            }
                            .padding(.vertical, 7)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Divider().overlay(SRDesign.divider)

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Segundos")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Spacer()
                        Text(secondsLabel)
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(SRDesign.primary)
                    }
                    HStack(spacing: 8) {
                        Button {
                            preferences.update { $0.fixedFrictionSeconds = nil }
                        } label: {
                            secondsChip("Automático", isSelected: preferences.data.fixedFrictionSeconds == nil)
                        }
                        .buttonStyle(SRPressStyle())

                        ForEach([6.0, 8.0, 10.0, 12.0], id: \.self) { value in
                            Button {
                                preferences.update { $0.fixedFrictionSeconds = value }
                                SRHaptics.light()
                            } label: {
                                secondsChip("\(Int(value)) s", isSelected: preferences.data.fixedFrictionSeconds == value)
                            }
                            .buttonStyle(SRPressStyle())
                        }
                    }
                    Text("En automático varían entre 6 y 12 segundos según lo que te esté funcionando. Nunca suben más.")
                        .font(.caption2)
                        .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Durante la sesión")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                focusToggle(
                    title: "Mostrar tiempo",
                    detail: "Si lo apagas, la sesión se sigue registrando por dentro.",
                    isOn: preferences.data.showsTimer
                ) { data, value in data.showsTimer = value }

                Divider().overlay(SRDesign.divider)

                focusToggle(
                    title: "Solo tarea",
                    detail: "Nombre, siguiente acción y Terminé. Nada más.",
                    isOn: preferences.data.onlyTaskMode
                ) { data, value in data.onlyTaskMode = value }

                Divider().overlay(SRDesign.divider)

                focusToggle(
                    title: "Preguntar siempre antes de empezar",
                    detail: "Verás la pantalla de preparación incluso en Suave.",
                    isOn: preferences.data.alwaysPrepares
                ) { data, value in data.alwaysPrepares = value }

                Divider().overlay(SRDesign.divider)

                focusToggle(
                    title: "Relajar bloqueos en los descansos",
                    detail: "Durante un descanso real el iPhone vuelve a la normalidad.",
                    isOn: preferences.data.relaxesOnBreak
                ) { data, value in data.relaxesOnBreak = value }

                Divider().overlay(SRDesign.divider)

                focusToggle(
                    title: "Proponer apps que te distraen",
                    detail: "Solo sugerencias con tu aprobación. Nunca se bloquea nada solo.",
                    isOn: preferences.data.suggestsDistractors
                ) { data, value in data.suggestsDistractors = value }

                Divider().overlay(SRDesign.divider)

                VStack(alignment: .leading, spacing: 8) {
                    Text("Al terminar")
                        .font(.body.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                    HStack(spacing: 8) {
                        ForEach(SRTransitionMode.allCases) { mode in
                            Button {
                                preferences.update { $0.transitionMode = mode }
                                SRHaptics.light()
                            } label: {
                                secondsChip(mode.label, isSelected: preferences.data.transitionMode == mode)
                            }
                            .buttonStyle(SRPressStyle())
                        }
                    }
                    Text("Unos segundos sin pendientes ni métricas, para que “terminé” no se convierta en abrir otra cosa.")
                        .font(.caption2)
                        .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 15)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .srCard()
        }
    }

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Qué ha pasado en las sesiones")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            Button {
                showsHistory = true
            } label: {
                SettingsNavRow(
                    title: "Historial de esta función",
                    detail: historyDetail,
                    symbol: "clock.arrow.circlepath"
                )
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .srCard()
        }
    }

    // MARK: - Pieces

    private func focusToggle(
        title: String,
        detail: String,
        isOn: Bool,
        set: @escaping (inout SRFocusPreferencesData, Bool) -> Void
    ) -> some View {
        Toggle(isOn: Binding(
            get: { isOn },
            set: { newValue in preferences.update { data in set(&data, newValue) } }
        )) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .tint(SRDesign.primary)
        .padding(.vertical, 15)
    }

    private func secondsChip(_ text: String, isSelected: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundStyle(isSelected ? SRDesign.onPrimary : SRDesign.secondaryInk)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(isSelected ? SRDesign.primary : SRDesign.elevatedSurface)
            .clipShape(Capsule(style: .continuous))
    }

    private var secondsLabel: String {
        guard let fixed = preferences.data.fixedFrictionSeconds else { return "Automático" }
        return "\(Int(fixed)) s"
    }

    private var permissionDetail: String {
        "\(screenTime.access.label). \(screenTime.access.explanation)"
    }

    private var historyDetail: String {
        let attempts = SRDistractionLog.recentAttempts(within: 24 * 7)
        if attempts == 0 { return "Todavía sin nada que contar" }
        return attempts == 1 ? "1 intento esta semana" : "\(attempts) intentos esta semana"
    }
}

/// The honest, non-punitive version of a distraction history: what happened, and
/// the one question it can answer.
struct DistractionHistoryView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    @State private var profiles = SRFocusProfileStore.shared
    @State private var events: [SRDistractionEvent] = []
    @State private var suggestion: (kind: SRFocusProfileKind, app: String)?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Historial")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("Esto no es una nota ni una estadística. Sirve para preparar mejor la próxima sesión.")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)

                if let suggestion {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Durante sesiones de \(suggestion.kind.label.lowercased()) has intentado abrir \(suggestion.app) varias veces. ¿Quieres incluirla entre las apps restringidas?")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 14) {
                            Button("Sí") {
                                if let profile = profiles.profile(kind: suggestion.kind) {
                                    profiles.addApp(suggestion.app, to: profile)
                                }
                                withAnimation(SRDesign.quickAnimation) { self.suggestion = nil }
                                SRHaptics.light()
                            }
                            .buttonStyle(SRQuietButtonStyle())

                            Button("No") {
                                withAnimation(SRDesign.quickAnimation) { self.suggestion = nil }
                            }
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(SRDesign.secondaryInk)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .srSurface(radius: metrics.rowRadius, accent: SRDesign.lavender)
                }

                if events.isEmpty {
                    Text("Todavía no hay nada guardado.")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                } else {
                    VStack(spacing: 0) {
                        ForEach(events.reversed().prefix(40)) { event in
                            HStack(spacing: 12) {
                                Image(systemName: symbol(for: event.kind))
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(SRDesign.secondaryInk)
                                    .frame(width: 24)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(sentence(for: event))
                                        .font(.subheadline)
                                        .foregroundStyle(SRDesign.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(SRWidgetSnapshot.timeFormatter.string(from: event.createdAt))
                                        .font(.caption2)
                                        .foregroundStyle(SRDesign.secondaryInk.opacity(0.85))
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 11)
                        }
                    }
                    .padding(.horizontal, 16)
                    .srCard()

                    Button("Borrar el historial") {
                        SRDistractionLog.clear()
                        withAnimation(SRDesign.quickAnimation) {
                            events = []
                            suggestion = nil
                        }
                        SRHaptics.light()
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 32)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .task {
            events = SRDistractionLog.all()
            guard SRFocusPreferences.shared.data.suggestsDistractors else { return }
            for kind in SRFocusProfileKind.allCases {
                if let candidate = SRDistractionLog.mostAttemptedApp(profileKind: kind) {
                    suggestion = (kind, candidate.name)
                    break
                }
            }
        }
    }

    private func symbol(for kind: SRDistractionEvent.Kind) -> String {
        switch kind {
        case .blockedAppAttempt: return "hand.raised"
        case .pauseRequested: return "pause.circle"
        case .frictionCompleted: return "checkmark.circle"
        case .frictionAbandoned: return "arrow.uturn.backward"
        case .breakGranted: return "cup.and.saucer"
        case .returned: return "arrow.turn.down.right"
        case .leftSession: return "door.left.hand.open"
        case .appReleased: return "lock.open"
        case .emergency: return "bolt"
        }
    }

    private func sentence(for event: SRDistractionEvent) -> String {
        let level = SRFocusLevel(rawValue: event.level)?.label ?? "Suave"
        switch event.kind {
        case .blockedAppAttempt:
            if let app = event.appLabel { return "Intentaste abrir \(app) en \(level)." }
            return "Intentaste salir durante una sesión en \(level)."
        case .pauseRequested: return "Pediste una pausa."
        case .frictionCompleted: return "Completaste los segundos de espera."
        case .frictionAbandoned: return "Dejaste los segundos a medias y seguiste con la tarea."
        case .breakGranted: return "Descanso concedido."
        case .returned: return "Volviste a la tarea."
        case .leftSession: return "Terminaste el modo sin cerrar la tarea."
        case .appReleased:
            if let app = event.appLabel { return "Liberaste \(app) solo para esa tarea." }
            return "Liberaste una app durante la sesión."
        case .emergency: return "Se devolvió el acceso completo al iPhone."
        }
    }
}
