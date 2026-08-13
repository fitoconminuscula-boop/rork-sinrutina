import SwiftUI
import SwiftData

/// The permanent sign that the demonstration mode is on.
///
/// It sits above every screen so invented content can never be mistaken for the
/// real thing, and it can be turned off from where it is seen.
struct SRDemoBanner: View {
    @Environment(\.modelContext) private var modelContext

    @State private var demo = DemoDataMode.shared

    var body: some View {
        if demo.isActive {
            HStack(spacing: 10) {
                Image(systemName: "theatermasks")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(SRDesign.onPrimary)

                VStack(alignment: .leading, spacing: 1) {
                    Text("Datos de demostración")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(SRDesign.onPrimary)
                    Text("Los asuntos marcados son de ejemplo, no reales.")
                        .font(.caption2)
                        .foregroundStyle(SRDesign.onPrimary.opacity(0.85))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 6)

                Button("Salir") {
                    demo.deactivate(context: modelContext)
                    SRHaptics.light()
                }
                .font(.caption.weight(.bold))
                .foregroundStyle(SRDesign.onPrimary)
                .padding(.horizontal, 11)
                .padding(.vertical, 6)
                .background(SRDesign.onPrimary.opacity(0.22))
                .clipShape(Capsule(style: .continuous))
                .buttonStyle(SRPressStyle())
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity)
            .background(SRDesign.primary)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Modo de demostración activo. Los datos son de ejemplo.")
        }
    }
}

/// The label every invented item carries, wherever it appears.
struct SRDemoTag: View {
    var body: some View {
        Text("Demostración")
            .font(.caption2.weight(.bold))
            .foregroundStyle(SRDesign.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(SRDesign.primarySoft)
            .clipShape(Capsule(style: .continuous))
            .accessibilityLabel("Asunto de ejemplo, no real")
    }
}
