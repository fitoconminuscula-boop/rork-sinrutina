import SwiftUI

/// Ajustes → Apariencia.
///
/// Everything here changes the app immediately, and every combination on offer was
/// designed to still look like SinRutina: the person personalises inside the design
/// system rather than replacing it. Title and primary action can never be hidden,
/// contrast is corrected automatically, and Reduce Motion always wins.
struct AppearanceView: View {
    @Environment(\.srMetrics) private var metrics
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.colorScheme) private var colorScheme
    @State private var appearance = SRAppearanceStore.shared
    @State private var iconService = AppIconService.shared
    @State private var showResetConfirmation = false
    @State private var dismissedSuggestionID: String?

    private var profile: SRAppearanceProfile { appearance.profile }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                titleBlock

                AppearancePreview()

                if let suggestion {
                    suggestionCard(suggestion)
                }

                group {
                    SRSettingBlock(title: "Tema", detail: "Paletas completas, pensadas una a una.") {
                        SRThemeStrip(selection: bind(\.theme))
                    }

                    divider

                    SRSettingBlock(title: "Color principal", detail: "Afecta al botón principal, los iconos activos, la tarea actual, el widget y la Actividad en vivo. No tiñe toda la interfaz.") {
                        SRAccentPicker(accent: bind(\.accent), customHex: bind(\.customAccentHex))
                    }
                }

                group {
                    SRSettingBlock(title: "Botones", detail: "Siempre planos y sólidos. Solo cambia la forma.") {
                        SRSegmented(options: SRButtonShape.allCases, label: { $0.label }, selection: bind(\.buttonShape))
                    }

                    divider

                    SRSettingBlock(title: "Densidad de interfaz", detail: densityDetail) {
                        SRSegmented(options: SRDensity.allCases, label: { $0.label }, selection: bind(\.density))
                    }

                    divider

                    SRSettingBlock(title: "Tarjetas", detail: profile.cardStyle.detail) {
                        SRSegmented(options: SRCardStyle.allCases, label: { $0.label }, selection: bind(\.cardStyle))
                    }

                    divider

                    SRSettingBlock(title: "Escala visual de SinRutina", detail: "Se aplica sobre el tamaño de texto de iOS, nunca en su lugar. Si usas tamaños de accesibilidad, se respetan tal cual.") {
                        SRSegmented(options: SRVisualScale.allCases, label: { $0.label }, selection: bind(\.visualScale))
                    }
                }

                group {
                    SRSettingBlock(title: "Animaciones", detail: motionDetail) {
                        SRSegmented(options: SRMotionLevel.allCases, label: { $0.label }, selection: bind(\.motion))
                    }

                    divider

                    SRSettingBlock(title: "Respuesta háptica", detail: "Solo en momentos que significan algo: empezar, completar, cambiar de estado o confirmar.") {
                        SRSegmented(options: SRHapticLevel.allCases, label: { $0.label }, selection: bind(\.haptics))
                    }

                    divider

                    SRSettingBlock(title: "Presencia de SinRutina", detail: "Cuánto aparece el símbolo. Siempre abstracto y discreto: nunca una cara ni un personaje.") {
                        SRSegmented(options: SRPresenceLevel.allCases, label: { $0.label }, selection: bind(\.presence))
                    }
                }

                group {
                    SRSettingBlock(title: "Pantalla Ahora", detail: nil) {
                        SRNowLayoutPicker(selection: bind(\.nowLayout))
                    }

                    divider

                    SRSettingBlock(title: "Información visible", detail: "El título y la acción principal no se pueden ocultar.") {
                        metadataToggles
                    }
                }

                group {
                    SRSettingBlock(title: "Widget", detail: profile.widgetStyle.detail) {
                        SRSegmented(options: SRWidgetStyle.allCases, label: { $0.label }, selection: bind(\.widgetStyle))
                    }

                    divider

                    SRSettingBlock(title: "Actividad en vivo", detail: profile.liveActivityStyle.detail) {
                        SRSegmented(options: SRLiveActivityStyle.allCases, label: { $0.label }, selection: bind(\.liveActivityStyle))
                    }

                    divider

                    Text("Dentro del widget y de la Dynamic Island, iOS decide el modo de color final. SinRutina se acerca todo lo que WidgetKit permite.")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }

                group {
                    SRSettingBlock(title: "Icono de la app", detail: "Todos usan el mismo símbolo.") {
                        SRAppIconPicker(
                            selection: Binding(
                                get: { profile.appIcon },
                                set: { option in changeIcon(to: option) }
                            ),
                            isSupported: iconService.isSupported,
                            errorMessage: iconService.lastErrorMessage
                        )
                    }
                }

                if !profile.isOriginal {
                    Button {
                        showResetConfirmation = true
                        SRHaptics.light()
                    } label: {
                        Label("Restablecer apariencia", systemImage: "arrow.counterclockwise")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SRQuietButtonStyle())
                    .padding(.top, 4)
                }

                Text("Tus preferencias visuales se guardan solo en este iPhone.")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 2)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("Apariencia")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("¿Volver al diseño original?", isPresented: $showResetConfirmation, titleVisibility: .visible) {
            Button("Restablecer", role: .destructive) {
                withAnimation(SRDesign.standardAnimation) {
                    appearance.resetToOriginal()
                }
                changeIcon(to: .original)
                SRHaptics.success()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se recupera el Pastel original, con densidad aireada y todo visible.")
        }
        .onAppear {
            iconService.reconcileStoredPreference()
        }
    }

    // MARK: - Sections

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Apariencia")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(SRDesign.ink)
            Text("Haz que SinRutina se sienta tuya. Cada opción está pensada para seguir pareciendo SinRutina.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 6)
    }

    private var metadataToggles: some View {
        VStack(spacing: 0) {
            ForEach(SRMetadataField.allCases) { field in
                Toggle(isOn: Binding(
                    get: { profile.shows(field) },
                    set: { isVisible in
                        appearance.update { draft in
                            if isVisible {
                                draft.visibleMetadata.insert(field)
                            } else {
                                draft.visibleMetadata.remove(field)
                            }
                        }
                        SRHaptics.light()
                    }
                )) {
                    Text(field.label)
                        .font(.footnote)
                        .foregroundStyle(SRDesign.ink)
                }
                .tint(SRDesign.primary)
                .padding(.vertical, 9)

                if field != SRMetadataField.allCases.last {
                    Divider().overlay(SRDesign.divider.opacity(0.6))
                }
            }
        }
    }

    private func suggestionCard(_ suggestion: SRAppearanceSuggestion) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 9) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SRDesign.primary)
                Text("Una idea, si te sirve")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.primary)
            }

            Text(suggestion.message)
                .font(.footnote)
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(suggestion.acceptLabel) {
                    withAnimation(SRDesign.standardAnimation) {
                        appearance.update { draft in
                            suggestion.change(&draft)
                            draft.answeredSuggestions.insert(suggestion.id)
                        }
                    }
                    SRHaptics.success()
                }
                .buttonStyle(SRPrimaryButtonStyle())

                Button("No, gracias") {
                    appearance.update { $0.answeredSuggestions.insert(suggestion.id) }
                    withAnimation(SRDesign.quickAnimation) {
                        dismissedSuggestionID = suggestion.id
                    }
                    SRHaptics.light()
                }
                .buttonStyle(SRQuietButtonStyle())
                .fixedSize()
            }
        }
        .padding(16)
        .srSurface(radius: metrics.rowRadius, accent: SRDesign.primary)
        .transition(.opacity)
    }

    @ViewBuilder
    private func group<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            content()
        }
        .padding(16)
        .srCard()
    }

    private var divider: some View {
        Divider().overlay(SRDesign.divider.opacity(0.6))
    }

    // MARK: - Wiring

    /// Writes straight through to the store so the whole app — and the preview
    /// above — updates without leaving this screen.
    private func bind<Value>(_ keyPath: WritableKeyPath<SRAppearanceProfile, Value>) -> Binding<Value> {
        Binding(
            get: { profile[keyPath: keyPath] },
            set: { newValue in
                appearance.update { $0[keyPath: keyPath] = newValue }
            }
        )
    }

    private func changeIcon(to option: SRAppIconOption) {
        Task {
            let didChange = await iconService.apply(option)
            guard didChange else { return }
            appearance.update { $0.appIcon = option }
        }
    }

    private var suggestion: SRAppearanceSuggestion? {
        guard let candidate = SRAppearanceAdvisor.suggestion(
            for: profile,
            typeSize: typeSize,
            systemScheme: colorScheme
        ) else { return nil }
        guard !profile.answeredSuggestions.contains(candidate.id),
              dismissedSuggestionID != candidate.id else { return nil }
        return candidate
    }

    private var densityDetail: String {
        switch profile.density {
        case .airy: return "Separación, padding, tarjetas y filas más holgadas."
        case .normal: return "El equilibrio intermedio."
        case .compact: return "Todo más ajustado y con menos información secundaria."
        }
    }

    private var motionDetail: String {
        if UIAccessibility.isReduceMotionEnabled {
            return "Tienes Reducir movimiento activado en iOS, y eso manda: las animaciones están desactivadas."
        }
        return "Breves y sobrias en cualquier caso. Nada decorativo permanente."
    }
}
