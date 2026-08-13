import SwiftUI

/// The one thing this feature says in "Ahora": when to stop what you are doing.
///
/// It never shows a number nobody computed. With no history and no fallback it
/// asks, and with a trip under way it becomes a quiet trip card instead.
struct DepartureCard: View {
    let plan: SRDeparturePlan
    let metrics: SRMetrics
    let onDetails: () -> Void
    let onLeaving: () -> Void
    let onDismiss: () -> Void
    let onManualEstimate: () -> Void

    @State private var showsReasons = false
    @State private var now = Date()

    private var phase: SRDeparturePhase { plan.phase(at: now) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.bottom, 14)

            if plan.hasEstimate {
                estimateBody
            } else {
                unknownBody
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srSurface(radius: metrics.cardRadius, accent: accent)
        .accessibilityElement(children: .contain)
        .task {
            // The phase changes with the clock, not with a tap.
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            SRSectionLabel(text: headerLabel)
                .foregroundStyle(accent)
            if plan.isSimulated {
                SRSimulationTag()
            }
            Spacer(minLength: 6)
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.7))
                    .frame(width: 28, height: 28)
                    .background(SRDesign.secondaryInk.opacity(0.09))
                    .clipShape(Circle())
            }
            .buttonStyle(SRPressStyle())
            .accessibilityLabel("Ocultar el aviso de salida")
        }
    }

    private var headerLabel: String {
        switch phase {
        case .notYet: return "Salir a tiempo"
        case .prepare: return "Preparación"
        case .getReady: return "Alistarse"
        case .leaveNow: return "Es hora de salir"
        case .late: return "Riesgo de atraso"
        }
    }

    private var accent: Color {
        switch phase {
        case .notYet: return SRDesign.primary
        case .prepare: return SRDesign.sky
        case .getReady: return SRDesign.primary
        case .leaveNow, .late: return SRDesign.blush
        }
    }

    // MARK: - With an estimate

    @ViewBuilder
    private var estimateBody: some View {
        if let leaveAt = plan.leaveAt {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(SRWidgetSnapshot.timeFormatter.string(from: leaveAt))
                    .font(.system(size: metrics.isTall ? 40 : 34, weight: .bold, design: .rounded))
                    .foregroundStyle(SRDesign.ink)
                    .monospacedDigit()
                Text(countdownLabel)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(phase == .leaveNow || phase == .late ? SRDesign.blush : SRDesign.secondaryInk)
            }
        }

        Text("\(plan.eventTitle) · \(plan.destinationLabel)")
            .font(.subheadline)
            .foregroundStyle(SRDesign.secondaryInk)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)

        if let phaseSentence {
            Text(phaseSentence)
                .font(.footnote.weight(.medium))
                .foregroundStyle(phase == .late ? SRDesign.blush : SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }

        if let estimate = plan.estimate {
            HStack(spacing: 8) {
                if let mode = plan.mode {
                    chip(symbol: mode.symbolName, text: "\(estimate.rangeLabel) \(mode.shortLabel.lowercased())")
                } else {
                    chip(symbol: "clock", text: estimate.rangeLabel)
                }
                chip(
                    symbol: estimate.source.symbolName,
                    text: sourceChipLabel(estimate),
                    isWarm: !estimate.isFromHistory
                )
            }
            .padding(.top, 14)
        }

        if let notice = plan.notice {
            Text(notice)
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)
        }

        if showsReasons {
            reasonList
                .padding(.top, 12)
                .transition(.opacity)
        }

        Button("Estoy saliendo") {
            SRHaptics.success()
            onLeaving()
        }
        .buttonStyle(SRPrimaryButtonStyle())
        .padding(.top, metrics.isTall ? 20 : 16)

        HStack(spacing: 12) {
            Button {
                withAnimation(SRDesign.quickAnimation) { showsReasons.toggle() }
            } label: {
                Text(showsReasons ? "Ocultar el cálculo" : "¿Por qué a esa hora?")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(SRPressStyle())

            Button {
                SRHaptics.light()
                onDetails()
            } label: {
                Text("Cambiar cómo voy")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(SRPressStyle())
        }
        .padding(.top, 8)
    }

    private var phaseSentence: String? {
        switch phase {
        case .notYet:
            guard let minutes = plan.minutesUntilPrep(at: now), minutes > 0 else { return nil }
            return "Tienes \(minutes) min de trabajo tranquilo antes de empezar a cerrar."
        case .prepare:
            guard let minutes = plan.minutesUntilLeaving(at: now) else { return nil }
            return "Tienes que salir en \(minutes) minutos. Empieza a cerrar lo que estás haciendo."
        case .getReady:
            guard let minutes = plan.minutesUntilLeaving(at: now) else { return nil }
            return "Sales en \(max(1, minutes)) minutos."
        case .leaveNow:
            return "Es hora de salir."
        case .late:
            guard let late = plan.lateMinutesIfLeavingNow(at: now) else { return "Es hora de salir." }
            return "Si sales ahora, probablemente llegues unos \(late) minutos tarde."
        }
    }

    private func sourceChipLabel(_ estimate: TravelEstimate) -> String {
        switch estimate.source {
        case .personalConfident: return "tus \(estimate.sampleCount) viajes"
        case .personalPartial:
            return estimate.sampleCount == 1 ? "1 viaje tuyo" : "\(estimate.sampleCount) viajes tuyos"
        case .mapKit: return "Apple Maps"
        case .manual: return "tu estimación"
        case .simulation: return "simulación"
        }
    }

    private var reasonList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(plan.reasons, id: \.self) { line in
                HStack(alignment: .top, spacing: 8) {
                    Circle()
                        .fill(SRDesign.primary.opacity(0.55))
                        .frame(width: 4, height: 4)
                        .padding(.top, 6)
                    Text(line)
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    // MARK: - Without an estimate

    @ViewBuilder
    private var unknownBody: some View {
        Text(plan.destinationLabel)
            .font(.title3.weight(.semibold))
            .foregroundStyle(SRDesign.ink)
            .fixedSize(horizontal: false, vertical: true)

        Text("\(plan.eventTitle) · empieza a las \(SRWidgetSnapshot.timeFormatter.string(from: plan.eventStart))")
            .font(.subheadline)
            .foregroundStyle(SRDesign.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 6)

        Text("Primera vez a este lugar. No tengo ningún viaje tuyo y no voy a inventarme una duración.")
            .font(.footnote)
            .foregroundStyle(SRDesign.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 12)

        Button("¿Cuánto calculas que tardarás?") {
            SRHaptics.light()
            onManualEstimate()
        }
        .buttonStyle(SRPrimaryButtonStyle())
        .padding(.top, 16)

        Button("Estoy saliendo · mide el viaje") {
            SRHaptics.success()
            onLeaving()
        }
        .buttonStyle(SRQuietButtonStyle())
        .padding(.top, 8)
    }

    // MARK: - Bits

    private var countdownLabel: String {
        guard let minutes = plan.minutesUntilLeaving(at: now) else { return "" }
        if minutes <= -2 { return "hace \(abs(minutes)) min" }
        if minutes <= 0 { return "ahora" }
        if minutes < 60 { return "en \(minutes) min" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "en \(hours) h" : "en \(hours) h \(rest) min"
    }

    private func chip(symbol: String, text: String, isWarm: Bool = false) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(isWarm ? SRDesign.blush : SRDesign.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background((isWarm ? SRDesign.blush : SRDesign.primary).opacity(0.12))
        .clipShape(Capsule(style: .continuous))
    }
}

/// The card shown while a trip is actually being measured. Nothing else is
/// proposed: the person is on their way.
struct TripInProgressCard: View {
    let trip: SRActiveTrip
    let metrics: SRMetrics
    let onArrived: () -> Void
    let onCancel: () -> Void

    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                SRSectionLabel(text: "En camino")
                    .foregroundStyle(SRDesign.sky)
                if trip.isSimulated {
                    SRSimulationTag()
                }
                Spacer(minLength: 6)
            }
            .padding(.bottom, 14)

            Text(trip.destinationLabel)
                .font(metrics.isTall ? .title2.weight(.semibold) : .title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                chip(
                    symbol: "arrow.up.forward",
                    text: "Salida: \(SRWidgetSnapshot.timeFormatter.string(from: trip.startedAt))"
                )
                chip(symbol: "clock", text: "\(elapsedMinutes) min en ruta")
                if let mode = trip.mode {
                    chip(symbol: mode.symbolName, text: mode.shortLabel.lowercased())
                }
            }
            .padding(.top, 14)

            Text(explanation)
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Button("Ya llegué") {
                SRHaptics.success()
                onArrived()
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .padding(.top, metrics.isTall ? 20 : 16)

            Button("No era un viaje") {
                SRHaptics.light()
                onCancel()
            }
            .buttonStyle(SRPressStyle())
            .font(.footnote.weight(.medium))
            .foregroundStyle(SRDesign.secondaryInk)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .padding(.top, 4)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srSurface(radius: metrics.cardRadius, accent: SRDesign.sky)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(30))
                now = Date()
            }
        }
    }

    private var elapsedMinutes: Int {
        max(0, Int(now.timeIntervalSince(trip.measuringSince) / 60))
    }

    private var explanation: String {
        if trip.isSimulated {
            return "Simulación: este viaje no entra en tu historial."
        }
        if LocationLearningService.shared.access.allowsBackgroundLearning {
            return "Detecto la llegada por ti. Mientras tanto no te propongo nada más."
        }
        return "Con el permiso “al usar la app” detecto la llegada mientras SinRutina esté abierta. Si no, dime “Ya llegué” y lo registro igual."
    }

    private func chip(symbol: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
            Text(text)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .foregroundStyle(SRDesign.primary)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(SRDesign.primary.opacity(0.12))
        .clipShape(Capsule(style: .continuous))
    }
}

/// "¿Vas camino a Consulta?" — detection with doubt becomes a question, never a
/// decision.
struct TripQuestionCard: View {
    let question: SRTripQuestion
    let onYes: () -> Void
    let onNo: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(question.prompt)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Vi que te has movido. Si me lo confirmas, mido cuánto tardas de verdad.")
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button("Sí") {
                    SRHaptics.success()
                    onYes()
                }
                .buttonStyle(SRPrimaryButtonStyle())

                Button("No") {
                    SRHaptics.light()
                    onNo()
                }
                .buttonStyle(SRQuietButtonStyle())
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srSurface(radius: SRDesign.cardRadius, accent: SRDesign.sky)
    }
}

/// A small, unmissable label. Nothing simulated is ever shown without it.
struct SRSimulationTag: View {
    var body: some View {
        Text("Simulación")
            .font(.caption2.weight(.bold))
            .foregroundStyle(SRDesign.blush)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(SRDesign.blush.opacity(0.14))
            .clipShape(Capsule(style: .continuous))
            .accessibilityLabel("Dato simulado")
    }
}
