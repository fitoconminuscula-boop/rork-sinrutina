import SwiftUI

/// "Pausa concedida."
///
/// A pause is not abandoning. The session stays alive, the clock stops, and
/// SinRutina says when the break is over instead of pretending nothing happened.
struct PauseOptionsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    /// Minutes chosen for the break.
    let onBreak: (Int) -> Void
    /// Ending the environment entirely, keeping the task for later.
    let onEndMode: () -> Void

    @State private var appearance = SRAppearanceStore.shared

    private let options = [5, 10, 15]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appearance.profile.presence.showsInSheets {
                SRPresenceView(state: .waiting, size: 40)
                    .padding(.bottom, 14)
            }

            Text("Pausa concedida")
                .font(.title2.weight(.bold))
                .foregroundStyle(SRDesign.ink)

            Text("Descansar no es abandonar. Te aviso cuando termine.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            VStack(spacing: 9) {
                ForEach(options, id: \.self) { minutes in
                    Button {
                        SRHaptics.soft()
                        onBreak(minutes)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "cup.and.saucer")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(SRDesign.primary)
                                .frame(width: 26)
                            Text("\(minutes) minutos")
                                .font(.body.weight(.medium))
                                .foregroundStyle(SRDesign.ink)
                            Spacer(minLength: 0)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(SRDesign.secondaryInk.opacity(0.7))
                        }
                        .padding(15)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .srCard(radius: metrics.rowRadius)
                    }
                    .buttonStyle(SRPressStyle())
                }
            }
            .padding(.top, 20)

            Button {
                SRHaptics.light()
                onEndMode()
                dismiss()
            } label: {
                Text("Terminar modo")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SRQuietButtonStyle())
            .padding(.top, 18)

            Text("Al terminar el modo, el iPhone vuelve a la normalidad y la tarea queda donde estaba.")
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, 24)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SRDesign.background.ignoresSafeArea())
    }
}

/// "¿Volvemos?" — asked once, when a granted break has run out.
struct BreakEndedSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    let taskTitle: String
    let onResume: () -> Void
    let onStop: () -> Void

    @State private var appearance = SRAppearanceStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if appearance.profile.presence.showsInSheets {
                SRPresenceView(state: .neutral, size: 40)
                    .padding(.bottom, 14)
            }

            Text("¿Volvemos?")
                .font(.title2.weight(.bold))
                .foregroundStyle(SRDesign.ink)

            Text(taskTitle)
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            Button("Seguir con esto") {
                SRHaptics.soft()
                onResume()
                dismiss()
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .padding(.top, 22)

            Button("Dejarlo por hoy") {
                onStop()
                dismiss()
            }
            .buttonStyle(SRQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, 24)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SRDesign.background.ignoresSafeArea())
    }
}

/// Offered after a session where one app had to be released.
struct AppExceptionSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    let appName: String
    let profileName: String
    let onAccept: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Usaste \(appName) durante esta tarea.")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("¿Quieres añadirla al perfil de \(profileName.lowercased())?")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            HStack(spacing: 12) {
                Button("Sí") {
                    SRHaptics.light()
                    onAccept()
                    dismiss()
                }
                .buttonStyle(SRPrimaryButtonStyle())

                Button("No") { dismiss() }
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .frame(maxWidth: .infinity)
                    .frame(height: SRDesign.controlHeight)
            }
            .padding(.top, 22)
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SRDesign.background.ignoresSafeArea())
    }
}
