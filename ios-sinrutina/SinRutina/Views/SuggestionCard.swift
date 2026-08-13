import SwiftUI

/// The one place where SinRutina speaks first.
///
/// It is a single quiet card: presence, one sentence, one action, and a way to ask
/// why. There is never more than one on screen, and dismissing it is as easy as
/// accepting it.
struct SuggestionCard: View {
    let intervention: SRIntervention
    let onAccept: () -> Void
    let onDismiss: () -> Void

    @Environment(\.srMetrics) private var metrics
    @State private var showsReason = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                SRPresenceView(state: .suggesting, size: 38)

                VStack(alignment: .leading, spacing: 6) {
                    Text(intervention.message)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsReason {
                        Text(intervention.reason)
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                            .transition(.opacity)
                    }
                }

                Spacer(minLength: 0)

                Button {
                    SRHaptics.light()
                    onDismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SRDesign.secondaryInk.opacity(0.8))
                        .frame(width: 30, height: 30)
                        .contentShape(Circle())
                }
                .buttonStyle(SRPressStyle())
                .accessibilityLabel("Descartar sugerencia")
            }

            HStack(spacing: 10) {
                Button {
                    SRHaptics.soft()
                    onAccept()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: intervention.symbolName)
                            .font(.system(size: 12, weight: .semibold))
                        Text(intervention.primaryLabel)
                            .font(.subheadline.weight(.semibold))
                    }
                    .foregroundStyle(SRDesign.onPrimary)
                    .padding(.horizontal, 16)
                    .frame(height: 38)
                    .background(SRDesign.primary)
                    .clipShape(Capsule(style: .continuous))
                }
                .buttonStyle(SRPressStyle())

                Button {
                    withAnimation(SRDesign.quickAnimation) { showsReason.toggle() }
                } label: {
                    Text(showsReason ? "Ocultar" : "¿Por qué esta?")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .buttonStyle(SRPressStyle())

                Spacer(minLength: 0)
            }
            .padding(.top, 14)
        }
        .padding(14)
        .srSurface(radius: metrics.rowRadius, accent: SRDesign.primary)
        .accessibilityElement(children: .contain)
        .accessibilityHint(intervention.reason)
    }
}

/// "¿Por qué esta?" for the current recommendation, built only from facts we can
/// point at. If there is no honest reason, it says so instead of inventing one.
struct ReasonExplainer {
    let task: TaskItem
    let availableMinutes: Int?
    let nextEventTitle: String?

    var sentence: String {
        var parts: [String] = []

        if let availableMinutes, availableMinutes > 0 {
            if let nextEventTitle, !nextEventTitle.isEmpty {
                parts.append("tienes \(availableMinutes) minutos antes de \(nextEventTitle)")
            } else {
                parts.append("tienes \(availableMinutes) minutos libres")
            }
        }

        if let actual = task.actualDuration, actual > 0 {
            parts.append("esta suele tomarte \(Int(actual.rounded())) minutos")
        } else {
            parts.append("esta suele tomar \(task.estimatedMinutes)")
        }

        if let due = task.dueDate {
            let days = Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0
            if days < 0 {
                parts.append("la fecha límite ya pasó")
            } else if days == 0 {
                parts.append("es para hoy")
            } else if days <= 3 {
                parts.append("quedan \(days) días para la fecha límite")
            }
        }

        // A neutral fact about time, never a count of the person's postponements.
        if task.procrastinationCount > 0, task.openDays >= 1 {
            parts.append(task.openDays == 1 ? "sigue abierta desde ayer" : "sigue abierta desde hace \(task.openDays) días")
        }

        if task.insistence == .unmissable {
            parts.append("la marcaste como imposible de olvidar")
        }

        guard !parts.isEmpty else {
            return "Está arriba porque es lo único abierto ahora mismo."
        }
        return parts.joined(separator: ", ").srSentenceCased + "."
    }
}

extension String {
    /// Capitalises only the first letter, leaving the rest of the sentence intact.
    var srSentenceCased: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
