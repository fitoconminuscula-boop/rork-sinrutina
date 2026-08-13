import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics
    @Query private var tasks: [TaskItem]
    @State private var showDeleteConfirmation = false
    @State private var calendars = CalendarService.shared
    @State private var reminders = ReminderService.shared
    @State private var preferences = CalendarPreferences.shared
    @State private var intelligence: SRIntelligenceAvailability = .requiresNewerOS
    @State private var appearance = SRAppearanceStore.shared
    @State private var learning = SRLearningStore.shared
    @State private var proactivity = SRProactivityPreferences.shared
    @State private var focusPreferences = SRFocusPreferences.shared
    @State private var screenTime = ScreenTimeService.shared
    @State private var travelPreferences = SRTravelPreferences.shared
    @State private var travelStore = LearnedRouteStore.shared
    @State private var travelLocation = LocationLearningService.shared
    @State private var demo = DemoDataMode.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 14) {
                    SRLogo(size: 44, showsWordmark: true)
                    Text("Ajustes")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                }
                .padding(.top, 18)

                // MARK: Appearance
                VStack(alignment: .leading, spacing: 0) {
                    SRSectionLabel(text: "Cómo se ve")
                        .padding(.bottom, 10)
                        .padding(.leading, 4)

                    NavigationLink {
                        AppearanceView()
                    } label: {
                        SettingsNavRow(
                            title: "Apariencia",
                            detail: appearanceDetail,
                            symbol: "paintpalette"
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 16)
                    .srCard()
                }

                // MARK: How SinRutina behaves
                VStack(alignment: .leading, spacing: 0) {
                    SRSectionLabel(text: "Cómo se comporta")
                        .padding(.bottom, 10)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        NavigationLink {
                            FocusSettingsView()
                        } label: {
                            SettingsNavRow(
                                title: "Modo enfoque",
                                detail: focusDetail,
                                symbol: "circle.lefthalf.filled"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(SRDesign.divider).padding(.leading, 54)

                        NavigationLink {
                            ProactivityView()
                        } label: {
                            SettingsNavRow(
                                title: "Sugerencias de SinRutina",
                                detail: proactivityDetail,
                                symbol: "bubble.left.and.exclamationmark.bubble.right"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(SRDesign.divider).padding(.leading, 54)

                        NavigationLink {
                            LearnedView()
                        } label: {
                            SettingsNavRow(
                                title: "Lo que SinRutina ha aprendido",
                                detail: learningDetail,
                                symbol: "brain"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .srCard()
                }

                // MARK: Ecosystem
                VStack(alignment: .leading, spacing: 0) {
                    SRSectionLabel(text: "Conectado con tu iPhone")
                        .padding(.bottom, 10)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        NavigationLink {
                            CalendarSettingsView()
                        } label: {
                            SettingsNavRow(
                                title: "Calendarios usados por SinRutina",
                                detail: calendarDetail,
                                symbol: "calendar"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(SRDesign.divider).padding(.leading, 54)

                        NavigationLink {
                            RemindersSettingsView()
                        } label: {
                            SettingsNavRow(
                                title: "Recordatorios de Apple",
                                detail: reminderDetail,
                                symbol: "checklist"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(SRDesign.divider).padding(.leading, 54)

                        NavigationLink {
                            LeaveOnTimeSettingsView()
                        } label: {
                            SettingsNavRow(
                                title: "Salir a tiempo",
                                detail: travelDetail,
                                symbol: "figure.walk.departure"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(SRDesign.divider).padding(.leading, 54)

                        NavigationLink {
                            IntegrationsView()
                        } label: {
                            SettingsNavRow(
                                title: "Siri, Atajos y widget",
                                detail: "Frases, acciones y avisos",
                                symbol: "sparkles"
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 16)
                    .srCard()
                }

                // MARK: Intelligence + privacy
                VStack(alignment: .leading, spacing: 0) {
                    SRSectionLabel(text: "Inteligencia y privacidad")
                        .padding(.bottom, 10)
                        .padding(.leading, 4)

                    VStack(spacing: 0) {
                        SettingsRow(
                            title: "Apple Intelligence",
                            detail: intelligence.isAvailable
                                ? "Activa. Todo se lee en este iPhone."
                                : "\(intelligence.shortLabel). Usamos el lector local.",
                            symbol: intelligence.isAvailable ? "cpu" : "cpu.fill"
                        )

                        Divider().overlay(SRDesign.divider).padding(.leading, 54)

                        Toggle(isOn: Binding(
                            get: { preferences.isLiveActivityEnabled },
                            set: { preferences.setLiveActivityEnabled($0) }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Actividad en vivo al empezar")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(SRDesign.ink)
                                Text("Muestra la tarea en marcha en la pantalla bloqueada.")
                                    .font(.caption)
                                    .foregroundStyle(SRDesign.secondaryInk)
                            }
                        }
                        .tint(SRDesign.primary)
                        .padding(.vertical, 15)

                        Divider().overlay(SRDesign.divider).padding(.leading, 54)

                        NavigationLink {
                            PrivacyView()
                        } label: {
                            SettingsNavRow(
                                title: "Privacidad",
                                detail: "Qué se procesa aquí y qué permisos hay",
                                symbol: "lock.shield"
                            )
                        }
                        .buttonStyle(.plain)

                        Divider().overlay(SRDesign.divider).padding(.leading, 54)

                        SettingsRow(
                            title: "Datos locales",
                            detail: "\(tasks.count) asuntos guardados en este iPhone",
                            symbol: "internaldrive"
                        )
                    }
                    .padding(.horizontal, 16)
                    .srCard()
                }

                // MARK: Demonstration mode
                VStack(alignment: .leading, spacing: 0) {
                    SRSectionLabel(text: "Datos de demostración")
                        .padding(.bottom, 10)
                        .padding(.leading, 4)

                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: Binding(
                            get: { demo.isActive },
                            set: { wantsDemo in
                                if wantsDemo {
                                    demo.activate(context: modelContext)
                                    SRHaptics.light()
                                } else {
                                    showDeleteConfirmation = true
                                }
                            }
                        )) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Activar modo demostración")
                                    .font(.body.weight(.medium))
                                    .foregroundStyle(SRDesign.ink)
                                Text("Añade asuntos, un correo y un material de ejemplo para ver cómo funciona la app.")
                                    .font(.caption)
                                    .foregroundStyle(SRDesign.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .tint(SRDesign.primary)

                        Text("Mientras esté activo verás un aviso permanente arriba y cada elemento inventado irá marcado como Demostración. Al desactivarlo se borran todos. Nada más en SinRutina inventa datos: si algo no se puede calcular o consultar de verdad, se dice.")
                            .font(.caption2)
                            .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .srCard()
                }

                SRLogoLockup(
                    size: 40,
                    caption: "SinRutina te ayuda a empezar, no a tenerlo todo controlado."
                )
                .padding(.top, 6)
                .opacity(0.9)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, SRDesign.pagePadding)
            .padding(.bottom, 32)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .confirmationDialog("¿Salir del modo demostración?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Salir y borrar los ejemplos", role: .destructive) {
                demo.deactivate(context: modelContext)
                SRHaptics.light()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se borrarán solo los elementos de ejemplo. Lo que hayas creado tú se queda.")
        }
        .task {
            intelligence = SRIntelligenceService.shared.availability
            screenTime.refreshAccessState()
            travelLocation.refreshAccessState()
            calendars.refreshAccessState()
            reminders.refreshAccessState()
            if calendars.access.canRead { calendars.loadCalendars() }
        }
    }

    private var appearanceDetail: String {
        let profile = appearance.profile
        return "\(profile.theme.label) · \(profile.density.label) · \(profile.nowLayout.label)"
    }

    private var focusDetail: String {
        let level = focusPreferences.data.defaultLevel.label
        guard screenTime.canBlockApps else {
            return "\(level) · bloqueo de apps no disponible"
        }
        return "\(level) · puede cerrar apps"
    }

    /// Says exactly what is true: no permission, nothing learned yet, or how many
    /// real trips are behind the estimates.
    private var travelDetail: String {
        guard travelPreferences.data.isEnabled else { return "Desactivado" }
        guard travelLocation.access.isGranted else { return "Falta el permiso de ubicación" }
        guard travelStore.hasAnyLearning else { return "Aprendiendo · aún sin recorridos" }
        let places = travelStore.knownDestinations.count
        return "\(places) destino(s) · \(travelStore.totalSampleCount) viajes aprendidos"
    }

    private var proactivityDetail: String {
        let disabled = SRProactivityDomain.allCases.count - SRProactivityDomain.allCases.filter { proactivity.isEnabled($0) }.count
        if disabled == 0 { return "\(proactivity.level.label) · todas las áreas" }
        return "\(proactivity.level.label) · \(disabled) área(s) en silencio"
    }

    private var learningDetail: String {
        guard learning.isLearningEnabled else { return "Desactivado" }
        let active = learning.activeInsights.count
        if active == 0 { return "Todavía sin observaciones" }
        return active == 1 ? "1 observación" : "\(active) observaciones"
    }

    private var calendarDetail: String {
        switch calendars.access {
        case .granted:
            let count = preferences.selectedCalendarIdentifiers.count
            return count == 0 ? "Ninguno activado todavía" : "\(count) activado(s)"
        case .writeOnly: return "Solo escritura"
        case .denied, .restricted: return "Sin acceso"
        case .notDetermined: return "Sin conectar"
        }
    }

    private var reminderDetail: String {
        switch reminders.access {
        case .granted:
            let linked = tasks.filter { $0.reminderIdentifier != nil }.count
            return linked == 0 ? "Conectado, nada enlazado" : "\(linked) enlazado(s)"
        case .writeOnly: return "Solo escritura"
        case .denied, .restricted: return "Sin acceso"
        case .notDetermined: return "Sin conectar"
        }
    }
}

struct SettingsRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(SRDesign.primary)
                .frame(width: 30, height: 30)
                .background(SRDesign.primarySoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 15)
    }
}

struct SettingsNavRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(SRDesign.primary)
                .frame(width: 30, height: 30)
                .background(SRDesign.primarySoft)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            Spacer(minLength: 6)
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(SRDesign.secondaryInk.opacity(0.75))
        }
        .padding(.vertical, 15)
        .contentShape(Rectangle())
    }
}
