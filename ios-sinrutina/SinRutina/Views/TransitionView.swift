import SwiftUI

/// The seconds after finishing, so "terminé" does not become "Instagram".
///
/// No metrics, no pending list, no confetti. One sentence, three ways out, and a
/// short quiet stretch if the person asked for it.
struct TransitionView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    /// What just finished, only used for the closing sentence.
    let taskTitle: String
    /// True when the person said "avancé, pero no terminé".
    var wasPartial: Bool = false
    let onSeeWhatsNext: () -> Void
    let onRest: () -> Void
    let onClose: () -> Void

    @State private var appearance = SRAppearanceStore.shared
    @State private var preferences = SRFocusPreferences.shared
    @State private var remaining: Double = 0
    @State private var isQuietStretch = false

    private var profile: SRAppearanceProfile { appearance.profile }

    var body: some View {
        ZStack {
            SRDesign.background.ignoresSafeArea()

            if isQuietStretch {
                quietStretch
                    .transition(.opacity)
            } else {
                closing
                    .transition(.opacity)
            }
        }
        .task {
            let seconds = preferences.data.transitionMode.seconds
            guard seconds > 0 else { return }
            remaining = seconds
            withAnimation(SRDesign.softAnimation) { isQuietStretch = true }
            while remaining > 0 {
                try? await Task.sleep(for: .milliseconds(200))
                remaining = max(0, remaining - 0.2)
            }
            withAnimation(SRDesign.softAnimation) { isQuietStretch = false }
        }
    }

    // MARK: - Pieces

    private var closing: some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer()

            if profile.presence != .minimal {
                SRPresenceView(state: .completed, size: 54)
                    .padding(.bottom, 22)
            }

            Text(wasPartial ? "Avanzaste." : "Listo.")
                .font(.system(size: 42, weight: .bold))
                .foregroundStyle(SRDesign.ink)

            Text(wasPartial
                 ? "Guardé dónde te quedaste. Mañana no empiezas de cero."
                 : "Ya no tienes que acordarte de esto.")
                .font(.title3)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 12)

            Spacer()

            VStack(spacing: 10) {
                Button("Ver qué sigue") {
                    SRHaptics.light()
                    onSeeWhatsNext()
                    dismiss()
                }
                .buttonStyle(SRPrimaryButtonStyle())

                Button("Descansar") {
                    onRest()
                    dismiss()
                }
                .buttonStyle(SRQuietButtonStyle())
                .frame(maxWidth: .infinity)
                .frame(height: 44)

                Button("Cerrar SinRutina") {
                    onClose()
                    dismiss()
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(SRDesign.secondaryInk)
                .frame(maxWidth: .infinity)
                .frame(height: 40)
            }
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Thirty to sixty seconds with nothing to react to. That is the whole point.
    private var quietStretch: some View {
        VStack(spacing: 24) {
            Spacer()

            if profile.presence != .minimal {
                SRPresenceView(state: .completed, size: 62)
            }

            Text(wasPartial ? "Avanzaste." : "Listo.")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(SRDesign.ink)

            Text("Un momento sin nada que decidir.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)

            Spacer()

            Button("Saltar") {
                withAnimation(SRDesign.softAnimation) {
                    remaining = 0
                    isQuietStretch = false
                }
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(SRDesign.secondaryInk.opacity(0.8))
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, 34)
        .frame(maxWidth: .infinity)
    }
}

/// "Quedaste aquí" — offered when a session was interrupted and the person came
/// back later. It never restarts anything: it continues.
struct ReentryCard: View {
    let snapshot: SRFocusSessionSnapshot
    let onContinue: () -> Void
    let onChangeTask: () -> Void
    let onClose: () -> Void

    @Environment(\.srMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 11) {
                SRPresenceView(state: .waiting, size: 32)
                Text("Quedaste aquí")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                Spacer(minLength: 0)
                Button {
                    SRHaptics.light()
                    onClose()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SRDesign.secondaryInk)
                        .frame(width: 30, height: 30)
                }
                .accessibilityLabel("Cerrar")
            }

            Text(snapshot.lastProgressNote ?? snapshot.nextStep ?? snapshot.title)
                .font(.body.weight(.medium))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                Button("Continuar") {
                    SRHaptics.soft()
                    onContinue()
                }
                .buttonStyle(SRQuietButtonStyle())

                Button("Cambiar tarea") {
                    onChangeTask()
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(SRDesign.secondaryInk)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srSurface(radius: metrics.rowRadius, accent: SRDesign.sky)
    }
}
