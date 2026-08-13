import SwiftUI

/// "Salir a tiempo" in Ajustes.
///
/// The screen states what is actually true right now: whether learning is on,
/// what iOS authorised, whether anything has been learned at all, and how to erase
/// it. Nothing here claims a route was learned when there are no samples.
struct LeaveOnTimeSettingsView: View {
    @Environment(\.srMetrics) private var metrics

    @State private var preferences = SRTravelPreferences.shared
    @State private var location = LocationLearningService.shared
    @State private var engine = PersonalTravelEngine.shared
    @State private var store = LearnedRouteStore.shared
    @State private var showsEraseConfirmation = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 26) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Salir a tiempo")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("SinRutina aprende cuánto tardas tú realmente en tus recorridos habituales para avisarte cuándo conviene salir.")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 14)

                enabledSection

                if preferences.data.isEnabled {
                    statusSection
                    locationSection
                    learningSection
                    marginSection
                    modeSection
                    destinationsSection
                    noticeSection
#if DEBUG
                    simulationSection
#endif
                }

                privacySection
            }
            .srContentWidth(metrics)
            .padding(.horizontal, SRDesign.pagePadding)
            .padding(.bottom, 34)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("Salir a tiempo")
        .navigationBarTitleDisplayMode(.inline)
        .task { location.refreshAccessState() }
        .confirmationDialog(
            "¿Borrar el historial de desplazamientos?",
            isPresented: $showsEraseConfirmation,
            titleVisibility: .visible
        ) {
            Button("Borrar todo", role: .destructive) {
                engine.eraseLearning()
                SRHaptics.light()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("Se borran los destinos aprendidos, las duraciones y los minutos de preparación observados. No se puede recuperar.")
        }
    }

    // MARK: - On / off

    private var enabledSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { preferences.data.isEnabled },
                    set: { value in
                        if value {
                            // Permission is requested here, and only here.
                            engine.enable()
                        } else {
                            engine.disable()
                        }
                        SRHaptics.light()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Aprender mis recorridos")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Text("Solo para eventos que tienen un lugar. Si está apagado, SinRutina no pide tu ubicación nunca.")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(SRDesign.primary)

                if !preferences.data.isEnabled {
                    Text("Al activarlo, iOS te preguntará por la ubicación. El resto de SinRutina funciona igual sin este permiso.")
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

    // MARK: - Status

    /// The honest state of the system, line by line.
    private var statusSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Estado")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                statusRow(
                    symbol: "chart.line.uptrend.xyaxis",
                    title: "Aprendizaje de recorridos",
                    value: preferences.data.learnsRoutes ? "Activo" : "Inactivo",
                    isPositive: preferences.data.learnsRoutes
                )
                Divider().overlay(SRDesign.divider)
                statusRow(
                    symbol: location.access.isGranted ? "location.fill" : "location.slash",
                    title: "Ubicación",
                    value: location.access.label,
                    isPositive: location.access.isGranted
                )
                Divider().overlay(SRDesign.divider)
                statusRow(
                    symbol: "moon.zzz",
                    title: "Aprendizaje en segundo plano",
                    value: backgroundStatusValue,
                    isPositive: preferences.data.learnsInBackground && location.access.allowsBackgroundLearning
                )
                Divider().overlay(SRDesign.divider)
                statusRow(
                    symbol: "mappin.and.ellipse",
                    title: "Destinos aprendidos",
                    value: store.knownDestinations.isEmpty
                        ? "Ninguno todavía"
                        : "\(store.knownDestinations.count) · \(store.totalSampleCount) viajes",
                    isPositive: store.hasAnyLearning
                )
                if let trip = engine.activeTrip {
                    Divider().overlay(SRDesign.divider)
                    statusRow(
                        symbol: "figure.walk.motion",
                        title: "Viaje en curso",
                        value: "\(trip.destinationLabel) · \(trip.elapsedMinutes) min",
                        isPositive: true
                    )
                }
            }
            .padding(.horizontal, 16)
            .srCard()

            if !store.hasAnyLearning {
                Text("Todavía no hay ningún recorrido aprendido. Aparecerán aquí después de tus primeros viajes reales, no antes.")
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .padding(.leading, 4)
            }
        }
    }

    private var backgroundStatusValue: String {
        guard preferences.data.learnsInBackground else { return "Inactivo" }
        return location.access.allowsBackgroundLearning ? "Activo" : "Sin permiso “Siempre”"
    }

    private func statusRow(symbol: String, title: String, value: String, isPositive: Bool) -> some View {
        HStack(spacing: 13) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isPositive ? SRDesign.primary : SRDesign.secondaryInk)
                .frame(width: 26)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(SRDesign.ink)
            Spacer(minLength: 8)
            Text(value)
                .font(.caption.weight(.semibold))
                .foregroundStyle(isPositive ? SRDesign.primary : SRDesign.secondaryInk)
                .multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 14)
    }

    // MARK: - Location

    private var locationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Ubicación")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                Text(location.access.detail)
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)

                if location.access == .notDetermined {
                    Button("Dar permiso de ubicación") {
                        location.requestWhenInUse()
                    }
                    .buttonStyle(SRQuietButtonStyle())
                }

                Toggle(isOn: Binding(
                    get: { preferences.data.learnsInBackground },
                    set: { value in
                        engine.setBackgroundLearning(value)
                        SRHaptics.light()
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Aprender con la app cerrada")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Text("Usa las señales de bajo consumo de iOS: cambios significativos de ubicación y visitas. Requiere el permiso “Siempre”.")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(SRDesign.primary)
                .disabled(!location.access.isGranted)
                .opacity(location.access.isGranted ? 1 : 0.5)

                if !location.access.allowsBackgroundLearning, preferences.data.learnsInBackground {
                    Text("iOS no ha dado el permiso “Siempre”, así que esto no está funcionando. Puedes concederlo en Ajustes de iOS › Privacidad › Localización › SinRutina.")
                        .font(.caption2)
                        .foregroundStyle(SRDesign.blush)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("El GPS preciso se activa solo mientras haya un viaje en curso y se apaga al llegar. No hay seguimiento continuo en ningún momento.")
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        }
    }

    // MARK: - Learning

    private var learningSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Aprendizaje")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { preferences.data.learnsRoutes },
                    set: { value in preferences.update { $0.learnsRoutes = value } }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Guardar la duración de mis viajes")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Text("Solo duración, día, franja horaria y destino aproximado. Nunca el trazado del viaje.")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(SRDesign.primary)

                Divider().overlay(SRDesign.divider)

                Toggle(isOn: Binding(
                    get: { preferences.data.usesMapsFallback },
                    set: { value in
                        preferences.update { $0.usesMapsFallback = value }
                        Task { await engine.refresh(reason: .userChange) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Usar Apple Maps para lugares nuevos")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Text("Solo cuando no tengo ningún viaje tuyo. Su transporte público depende de la zona, así que no lo doy por seguro.")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(SRDesign.primary)

                if let minutes = engine.confirmedTransitionMinutes {
                    Divider().overlay(SRDesign.divider)
                    Toggle(isOn: Binding(
                        get: { preferences.data.usesLearnedPrep },
                        set: { engine.setUsesLearnedPrep($0) }
                    )) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("Contar mis \(minutes) min de transición")
                                .font(.body.weight(.medium))
                                .foregroundStyle(SRDesign.ink)
                            Text("Lo aceptaste en “Lo que he aprendido”: es lo que suele pasar entre decidir salir y empezar a moverte.")
                                .font(.caption)
                                .foregroundStyle(SRDesign.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tint(SRDesign.primary)
                } else if SRTransitionMemory.sampleCount > 0 {
                    Divider().overlay(SRDesign.divider)
                    Text("Estoy observando cuánto tardas desde que decides salir hasta que te mueves (\(SRTransitionMemory.sampleCount) observaciones). Cuando haya suficientes te lo preguntaré antes de usarlo.")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        }
    }

    // MARK: - Margin

    private var marginSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Quiero llegar")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(SRArrivalMargin.allCases) { option in
                        Button {
                            preferences.update { $0.arriveEarlyMinutes = option.rawValue }
                            SRHaptics.light()
                            Task { await engine.refresh(reason: .userChange) }
                        } label: {
                            Text(option.shortLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(isSelected(option) ? SRDesign.onPrimary : SRDesign.secondaryInk)
                                .frame(maxWidth: .infinity)
                                .frame(height: 38)
                                .background(isSelected(option) ? SRDesign.primary : SRDesign.elevatedSurface)
                                .clipShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(SRPressStyle())
                    }
                }

                stepperRow(
                    title: "Margen personalizado",
                    detail: "Minutos de antelación con los que quieres llegar",
                    value: preferences.data.arriveEarlyMinutes,
                    unit: "min",
                    range: 0...45,
                    step: 5
                ) { value in
                    preferences.update { $0.arriveEarlyMinutes = value }
                    Task { await engine.refresh(reason: .userChange) }
                }

                Divider().overlay(SRDesign.divider)

                stepperRow(
                    title: "Prepararme antes de salir",
                    detail: "Cerrar lo que estás haciendo, abrigo, llaves",
                    value: preferences.data.prepMinutes,
                    unit: "min",
                    range: 0...30,
                    step: 1
                ) { value in
                    preferences.update { $0.prepMinutes = value }
                    Task { await engine.refresh(reason: .userChange) }
                }

                Divider().overlay(SRDesign.divider)

                stepperRow(
                    title: "Aparcar y llegar a la puerta",
                    detail: "Solo se aplica cuando vas en auto",
                    value: preferences.data.finalStretchMinutes,
                    unit: "min",
                    range: 0...30,
                    step: 1
                ) { value in
                    preferences.update { $0.finalStretchMinutes = value }
                    Task { await engine.refresh(reason: .userChange) }
                }

                Text("La hora de salida es duración aprendida + preparación + tu margen. Cuando hay pocos viajes, añado unos minutos más y te lo digo.")
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        }
    }

    private func isSelected(_ option: SRArrivalMargin) -> Bool {
        preferences.data.arriveEarlyMinutes == option.rawValue
    }

    private func stepperRow(
        title: String,
        detail: String,
        value: Int,
        unit: String,
        range: ClosedRange<Int>,
        step: Int,
        onChange: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 6)
            Text("\(value) \(unit)")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SRDesign.primary)
                .monospacedDigit()
            Stepper("") {
                onChange(min(value + step, range.upperBound))
            } onDecrement: {
                onChange(max(value - step, range.lowerBound))
            }
            .labelsHidden()
        }
    }

    // MARK: - Mode

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Cómo te mueves normalmente")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(SRTravelMode.allCases) { mode in
                    Button {
                        preferences.update { $0.defaultModeRaw = mode.rawValue }
                        SRHaptics.light()
                        Task { await engine.refresh(reason: .userChange) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(preferences.data.defaultMode == mode ? SRDesign.primary : SRDesign.secondaryInk)
                                .frame(width: 26)
                            Text(mode.label)
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SRDesign.ink)
                            Spacer(minLength: 6)
                            if preferences.data.defaultMode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(SRDesign.primary)
                            }
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .srSurface(
                            radius: metrics.rowRadius,
                            accent: preferences.data.defaultMode == mode ? SRDesign.primary : nil
                        )
                    }
                    .buttonStyle(SRPressStyle())
                }
            }

            Text("SinRutina aprende la duración real sea el medio que sea, así que no necesita conocer ninguna red de transporte.")
                .font(.caption2)
                .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.leading, 4)
        }
    }

    // MARK: - Destinations

    private var destinationsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Destinos aprendidos")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(spacing: 0) {
                NavigationLink {
                    LearnedDestinationsView()
                } label: {
                    HStack(spacing: 13) {
                        Image(systemName: "mappin.and.ellipse")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(SRDesign.primary)
                            .frame(width: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ver y borrar destinos")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(SRDesign.ink)
                            Text(store.hasAnyLearning
                                 ? "\(store.knownDestinations.count) lugares · \(store.totalSampleCount) viajes registrados"
                                 : "Ningún lugar aprendido todavía")
                                .font(.caption)
                                .foregroundStyle(SRDesign.secondaryInk)
                        }
                        Spacer(minLength: 6)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(SRDesign.secondaryInk.opacity(0.7))
                    }
                    .padding(.vertical, 14)
                }
                .buttonStyle(.plain)

                if store.hasAnyLearning {
                    Divider().overlay(SRDesign.divider)
                    Button {
                        showsEraseConfirmation = true
                    } label: {
                        HStack(spacing: 13) {
                            Image(systemName: "trash")
                                .font(.system(size: 15, weight: .medium))
                                .frame(width: 26)
                            Text("Borrar historial de desplazamientos")
                                .font(.subheadline.weight(.medium))
                            Spacer(minLength: 6)
                        }
                        .foregroundStyle(SRDesign.blush)
                        .padding(.vertical, 14)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .srCard()
        }
    }

    // MARK: - Notices

    private var noticeSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Avisos")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: Binding(
                    get: { preferences.data.notifiesDeparture },
                    set: { value in preferences.update { $0.notifiesDeparture = value } }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Avisarme por fases")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Text("Preparación, alistarse y salir. Cada fase habla una sola vez.")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(SRDesign.primary)

                Divider().overlay(SRDesign.divider)

                stepperRow(
                    title: "Volver a avisar si cambia",
                    detail: "Diferencia mínima para decirte que la hora se movió",
                    value: preferences.data.notifyThresholdMinutes,
                    unit: "min",
                    range: 3...20,
                    step: 1
                ) { value in
                    preferences.update { $0.notifyThresholdMinutes = value }
                }

                Text("Si un día ya te avisé de varios cambios, subo el umbral en vez de hablar más.")
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        }
    }

#if DEBUG
    /// Development only. Anything simulated is labelled as such everywhere it
    /// appears, and it never enters the learning store.
    private var simulationSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Desarrollo")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: Binding(
                    get: { preferences.data.isSimulationEnabled },
                    set: { value in
                        preferences.update { $0.isSimulationEnabled = value }
                        Task { await engine.refresh(reason: .userChange) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Modo simulación")
                            .font(.body.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Text("Genera una duración de prueba para lugares sin historial, siempre marcada como “Simulación”.")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .tint(SRDesign.blush)

                Text("Ninguna duración simulada se guarda como aprendizaje real.")
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        }
    }
#endif

    // MARK: - Privacy

    private var privacySection: some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Privacidad")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 12) {
                Text("Lo que se guarda, y solo aquí:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                ForEach(SRTravelPrivacyGuard.storedFields, id: \.self) { field in
                    bullet(field, isPositive: true)
                }
                Divider().overlay(SRDesign.divider)
                Text("Lo que nunca se guarda:")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                ForEach(SRTravelPrivacyGuard.neverStoredFields, id: \.self) { field in
                    bullet(field, isPositive: false)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        }
    }

    private func bullet(_ text: String, isPositive: Bool) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: isPositive ? "checkmark" : "xmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(isPositive ? SRDesign.primary : SRDesign.secondaryInk.opacity(0.7))
                .padding(.top, 3)
            Text(text)
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
