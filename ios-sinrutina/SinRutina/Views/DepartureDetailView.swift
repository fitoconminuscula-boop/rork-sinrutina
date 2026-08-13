import SwiftUI

/// The whole trip: where the hour comes from, how the person gets there, and what
/// SinRutina has actually learned about this route so far.
struct DepartureDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    @State private var engine = PersonalTravelEngine.shared
    @State private var preferences = SRTravelPreferences.shared
    @State private var store = LearnedRouteStore.shared
    @State private var location = LocationLearningService.shared
    @State private var manualPlan: SRDeparturePlan?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("¿Cuándo tengo que salir?")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("SinRutina no intenta sustituir un mapa. Aprende cuánto tardas tú realmente y usa eso para decirte cuándo dejar lo que estás haciendo.")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 20)

                if let trip = engine.activeTrip {
                    tripSection(trip)
                } else if let plan = engine.nextPlan {
                    if plan.hasEstimate {
                        hourSection(plan)
                        breakdownSection(plan)
                    } else {
                        unknownSection(plan)
                    }
                    modeSection(plan)
                    historySection(plan)
                } else {
                    emptySection
                }

                if engine.activeTrip == nil {
                    Button {
                        Task { await engine.refresh(reason: .userChange) }
                        SRHaptics.light()
                    } label: {
                        Label(
                            engine.isRecalculating ? "Recalculando…" : "Recalcular ahora",
                            systemImage: "arrow.clockwise"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(SRQuietButtonStyle())
                    .disabled(engine.isRecalculating)
                }

                Text("Tu historial de recorridos se queda en este iPhone. Solo cuando un lugar es nuevo puedo preguntar a Apple Maps, y entonces salen únicamente origen, destino, medio y hora.")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 32)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .sheet(item: $manualPlan) { plan in
            ManualTravelEstimateSheet(plan: plan)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private func hourSection(_ plan: SRDeparturePlan) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if plan.isSimulated {
                SRSimulationTag()
            }
            if let leaveAt = plan.leaveAt {
                Text(SRWidgetSnapshot.timeFormatter.string(from: leaveAt))
                    .font(.system(size: 38, weight: .bold, design: .rounded))
                    .foregroundStyle(SRDesign.ink)
                    .monospacedDigit()
            }
            if let startPrepAt = plan.startPrepAt {
                Text("Empieza a prepararte a las \(SRWidgetSnapshot.timeFormatter.string(from: startPrepAt)).")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Para \(plan.eventTitle), que empieza a las \(SRWidgetSnapshot.timeFormatter.string(from: plan.eventStart)).")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let estimate = plan.estimate {
                Text("\(estimate.source.label) · \(estimate.detail)")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private func unknownSection(_ plan: SRDeparturePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Primera vez a \(plan.destinationLabel)")
                .font(.headline)
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("No tengo ningún viaje tuyo a este lugar, así que no hay hora de salida que pueda calcular con honestidad.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button("Decir cuánto calculo que tardaré") {
                manualPlan = plan
                SRHaptics.light()
            }
            .buttonStyle(SRPrimaryButtonStyle())

            Button("Estoy saliendo · mide este viaje") {
                SRHaptics.success()
                engine.startLeaving(plan)
            }
            .buttonStyle(SRQuietButtonStyle())

            Button("Omitir el cálculo esta vez") {
                SRHaptics.light()
                engine.skipEstimate(for: plan)
                dismiss()
            }
            .buttonStyle(SRPressStyle())
            .font(.footnote.weight(.medium))
            .foregroundStyle(SRDesign.secondaryInk)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private func tripSection(_ trip: SRActiveTrip) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                SRSectionLabel(text: "En camino")
                    .foregroundStyle(SRDesign.sky)
                if trip.isSimulated { SRSimulationTag() }
            }
            Text(trip.destinationLabel)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text("Salida registrada a las \(SRWidgetSnapshot.timeFormatter.string(from: trip.startedAt)) · \(trip.elapsedMinutes) min en ruta.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Text(location.isTrackingPrecisely
                 ? "Estoy midiendo el trayecto con más precisión solo hasta que llegues. Después vuelvo al modo de bajo consumo."
                 : "No estoy midiendo con precisión ahora mismo. Puedes decirme cuándo llegaste y lo registro igual.")
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)

            Button("Ya llegué") {
                SRHaptics.success()
                engine.confirmArrival()
            }
            .buttonStyle(SRPrimaryButtonStyle())

            Button("No era un viaje") {
                SRHaptics.light()
                engine.cancelTrip()
            }
            .buttonStyle(SRQuietButtonStyle())
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private var emptySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(engine.lastNotice ?? "Ahora mismo no hay ningún desplazamiento que preparar.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if !preferences.data.isEnabled {
                Button("Activar Salir a tiempo") {
                    engine.enable()
                    SRHaptics.light()
                }
                .buttonStyle(SRQuietButtonStyle())
            } else if location.access == .notDetermined {
                Button("Dar permiso de ubicación") {
                    location.requestWhenInUse()
                }
                .buttonStyle(SRQuietButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private func modeSection(_ plan: SRDeparturePlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Cómo voy a \(plan.destinationLabel)")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(spacing: 8) {
                ForEach(SRTravelMode.allCases) { mode in
                    Button {
                        SRHaptics.light()
                        Task { await engine.setMode(mode, for: plan) }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: mode.symbolName)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(plan.mode == mode ? SRDesign.primary : SRDesign.secondaryInk)
                                .frame(width: 26)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.label)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(SRDesign.ink)
                                Text(detail(for: mode, plan: plan))
                                    .font(.caption)
                                    .foregroundStyle(SRDesign.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer(minLength: 6)
                            if plan.mode == mode {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(SRDesign.primary)
                            }
                        }
                        .padding(13)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .srSurface(radius: metrics.rowRadius, accent: plan.mode == mode ? SRDesign.primary : nil)
                    }
                    .buttonStyle(SRPressStyle())
                }
            }

            Text("El medio no cambia de dónde sale la duración: SinRutina aprende lo que tardas tú, sea metro, coche o una mezcla.")
                .font(.caption2)
                .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
                .padding(.leading, 4)
        }
    }

    /// What each mode really means for this destination, based on samples.
    private func detail(for mode: SRTravelMode, plan: SRDeparturePlan) -> String {
        if let destinationID = plan.destinationID {
            let routes = store.routes(for: destinationID).filter { $0.mode == mode }
            let samples = routes.reduce(0) { $0 + $1.sampleCount }
            if samples > 0 {
                return samples == 1 ? "1 viaje tuyo registrado" : "\(samples) viajes tuyos registrados"
            }
        }
        if mode.canAskMaps, preferences.data.usesMapsFallback {
            return "Sin viajes tuyos todavía · Apple Maps puede dar una primera idea"
        }
        return "Sin viajes tuyos todavía · lo aprendo con tu primer viaje"
    }

    private func breakdownSection(_ plan: SRDeparturePlan) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "De dónde sale la hora")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            VStack(alignment: .leading, spacing: 9) {
                ForEach(plan.reasons, id: \.self) { line in
                    HStack(alignment: .top, spacing: 9) {
                        Circle()
                            .fill(SRDesign.primary.opacity(0.5))
                            .frame(width: 4, height: 4)
                            .padding(.top, 7)
                        Text(line)
                            .font(.subheadline)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Divider().overlay(SRDesign.divider)
                Text("Total: dejas lo que estás haciendo \(plan.totalLeadMinutes) min antes de que empiece.")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard()
        }
    }

    /// What has actually been measured for this place, per weekday and band.
    @ViewBuilder
    private func historySection(_ plan: SRDeparturePlan) -> some View {
        if let destinationID = plan.destinationID {
            let routes = store.routes(for: destinationID)
            VStack(alignment: .leading, spacing: 0) {
                SRSectionLabel(text: "Lo que sé de este recorrido")
                    .padding(.bottom, 10)
                    .padding(.leading, 4)

                if routes.isEmpty {
                    Text("Todavía nada. Después de tu primer viaje real empiezo a aprender.")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .srCard()
                } else {
                    VStack(spacing: 0) {
                        ForEach(Array(routes.prefix(6))) { route in
                            LearnedRouteRow(route: route)
                            if route.id != routes.prefix(6).last?.id {
                                Divider().overlay(SRDesign.divider)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .srCard()
                }
            }
        }
    }
}

/// One learned route: the day, the band, the median and the pessimistic end.
struct LearnedRouteRow: View {
    let route: LearnedRoute

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text(route.contextLabel)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                Spacer(minLength: 6)
                if let median = route.medianSeconds {
                    Text("\(Int((median / 60).rounded())) min")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(SRDesign.primary)
                        .monospacedDigit()
                }
            }
            Text(detailLine)
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var detailLine: String {
        var parts: [String] = []
        parts.append(route.sampleCount == 1 ? "1 viaje" : "\(route.sampleCount) viajes")
        if let p80 = route.p80Seconds {
            parts.append("P80 \(Int((p80 / 60).rounded())) min")
        }
        if let prep = route.prepMedianSeconds, prep >= 60 {
            parts.append("preparación \(Int((prep / 60).rounded())) min")
        }
        if let mode = route.mode {
            parts.append(mode.shortLabel.lowercased())
        }
        parts.append(route.confidence.label.lowercased())
        return parts.joined(separator: " · ")
    }
}

/// "Primera vez a este lugar. ¿Cuánto calculas que demorarás?"
///
/// The number the person types is stored as theirs, labelled as theirs, and
/// replaced by the real one after the first measured trip.
struct ManualTravelEstimateSheet: View {
    let plan: SRDeparturePlan

    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics
    @State private var minutes: Int = 30
    @State private var engine = PersonalTravelEngine.shared

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Primera vez a \(plan.destinationLabel)")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("¿Cuánto calculas que tardarás? Lo uso solo hasta que mida tu primer viaje real.")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 18)

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("\(minutes) min")
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                            .foregroundStyle(SRDesign.ink)
                            .monospacedDigit()
                        Spacer()
                        Stepper("") {
                            minutes = min(minutes + 5, 300)
                        } onDecrement: {
                            minutes = max(minutes - 5, 5)
                        }
                        .labelsHidden()
                    }

                    HStack(spacing: 8) {
                        ForEach([10, 20, 30, 45, 60], id: \.self) { preset in
                            Button {
                                minutes = preset
                                SRHaptics.light()
                            } label: {
                                Text("\(preset)")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(minutes == preset ? SRDesign.onPrimary : SRDesign.secondaryInk)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 38)
                                    .background(minutes == preset ? SRDesign.primary : SRDesign.elevatedSurface)
                                    .clipShape(Capsule(style: .continuous))
                            }
                            .buttonStyle(SRPressStyle())
                        }
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .srCard()

                Button("Usar esta duración") {
                    SRHaptics.success()
                    Task { await engine.saveManualEstimate(minutes: minutes, for: plan) }
                    dismiss()
                }
                .buttonStyle(SRPrimaryButtonStyle())

                Button("Mejor no calcular nada") {
                    SRHaptics.light()
                    engine.skipEstimate(for: plan)
                    dismiss()
                }
                .buttonStyle(SRQuietButtonStyle())

                Text("Nunca me invento una duración. Si no me la das y no tengo historial, no muestro hora de salida.")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 28)
        }
        .background(SRDesign.background.ignoresSafeArea())
    }
}
