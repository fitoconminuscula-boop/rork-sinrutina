import SwiftUI

/// The ways out of a running session that are not "Terminé".
nonisolated enum SRExecutionOption: String, Sendable {
    case changeCourse
    case partial
    case releaseApp
}

/// Kept out of the session screen on purpose: during execution only the active
/// task is visible, and every other decision costs one deliberate tap.
struct ExecutionOptionsSheet: View {
    let canReleaseApp: Bool
    let onSelect: (SRExecutionOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Más opciones")
                .font(.title2.weight(.bold))
                .foregroundStyle(SRDesign.ink)
                .padding(.top, 8)

            VStack(spacing: 0) {
                row(
                    title: "Avancé, pero no terminé",
                    detail: "Guarda hasta dónde llegaste",
                    symbol: "bookmark"
                ) { select(.partial) }

                divider

                row(
                    title: "Necesito otra cosa",
                    detail: "Sales de la sesión",
                    symbol: "arrow.uturn.left"
                ) { select(.changeCourse) }

                if canReleaseApp {
                    divider
                    row(
                        title: "Necesito esta app",
                        detail: "Libera una app durante la sesión",
                        symbol: "app.badge"
                    ) { select(.releaseApp) }
                }
            }
            .padding(.horizontal, 16)
            .srCard(radius: metrics.cardRadius)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .srContentWidth(metrics)
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, 24)
        .background(SRDesign.background.ignoresSafeArea())
    }

    private var divider: some View {
        Divider().overlay(SRDesign.divider).padding(.leading, 38)
    }

    private func row(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SRDesign.primary)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body)
                        .foregroundStyle(SRDesign.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.7))
            }
            .frame(minHeight: 58)
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
    }

    private func select(_ option: SRExecutionOption) {
        SRHaptics.light()
        onSelect(option)
        dismiss()
    }
}
