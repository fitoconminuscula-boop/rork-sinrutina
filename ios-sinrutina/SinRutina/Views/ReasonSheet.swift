import SwiftUI
import SwiftData

struct ReasonSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem
    @State private var selectedReason: String?
    @State private var microActions: [String] = []
    @State private var subtasks: [String] = []
    @State private var isThinking = false

    private let reasons = [
        "No sé por dónde empezar",
        "Es demasiado grande",
        "Me da lata",
        "Me genera ansiedad",
        "No es importante",
        "Ahora no tengo cabeza"
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let selectedReason {
                responseView(for: selectedReason)
            } else {
                Text("¿Qué pasa?")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SRDesign.ink)
                    .padding(.bottom, 20)

                VStack(spacing: 10) {
                    ForEach(reasons, id: \.self) { reason in
                        Button {
                            withAnimation(SRDesign.standardAnimation) {
                                self.selectedReason = reason
                            }
                            BehaviorRecorder.recordActionResponse(reason, context: modelContext)
                            SRHaptics.light()
                        } label: {
                            HStack {
                                Text(reason)
                                    .font(.body)
                                    .foregroundStyle(SRDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                Spacer(minLength: 8)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(SRDesign.secondaryInk)
                            }
                            .padding(.horizontal, 16)
                            .frame(minHeight: 50)
                            .background(SRDesign.surface)
                            .clipShape(.rect(cornerRadius: SRDesign.rowRadius))
                            .overlay {
                                RoundedRectangle(cornerRadius: SRDesign.rowRadius, style: .continuous)
                                    .stroke(SRDesign.divider.opacity(0.45), lineWidth: 0.7)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(.horizontal, SRDesign.pagePadding)
        .padding(.top, 28)
        .padding(.bottom, 18)
        .background(SRDesign.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func responseView(for reason: String) -> some View {
        let step = resolvedStep(for: reason)
        VStack(alignment: .leading, spacing: 16) {
            Text(reason)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SRDesign.primary)
            Text(response(for: reason, step: step))
                .font(.title2.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
                .animation(SRDesign.softAnimation, value: step)

            if isThinking {
                Text("Buscando algo más pequeño…")
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.85))
                    .transition(.opacity)
            }
            // The rest of the steps exist and are kept, but showing them here would
            // turn one movement back into a plan to evaluate.

            Text("No tienes que resolver todo ahora.")
                .font(.body)
                .foregroundStyle(SRDesign.secondaryInk)
            Spacer(minLength: 8)
            Button("Hacer solo eso") {
                task.nextStep = step
                task.detail = step
                if reason == "No es importante" || reason == "Ahora no tengo cabeza" {
                    SRTaskCommands.postpone(task, to: .after, context: modelContext)
                } else {
                    task.procrastinationCount += 1
                    task.updatedAt = Date()
                    try? modelContext.save()
                }
                SRHaptics.soft()
                dismiss()
            }
            .buttonStyle(SRPrimaryButtonStyle())
        }
        .task(id: reason) { await loadHelp(for: reason) }
    }

    private func resolvedStep(for reason: String) -> String {
        if reason == "Es demasiado grande", let first = subtasks.first { return first }
        if let first = microActions.first { return first }
        return NextActionEngine().microStep(for: task)
    }

    /// Asks the intelligence layer for something smaller. It only proposes text;
    /// nothing moves until the person taps.
    private func loadHelp(for reason: String) async {
        isThinking = true
        if reason == "Es demasiado grande" {
            let pieces = await SRIntelligenceService.shared.split(title: task.title)
            withAnimation(SRDesign.softAnimation) { subtasks = pieces }
        } else {
            let actions = await SRIntelligenceService.shared.microActions(
                for: task.title,
                context: task.preferredContext
            )
            withAnimation(SRDesign.softAnimation) { microActions = actions }
        }
        isThinking = false
    }

    private func response(for reason: String, step: String) -> String {
        switch reason {
        case "No sé por dónde empezar": return step
        case "Es demasiado grande": return "Haz solo el primer paso: \(step.lowercased())"
        case "Me da lata": return "Hazlo durante dos minutos. Solo \(step.lowercased())"
        case "Me genera ansiedad": return "Baja la intensidad: \(step)"
        case "No es importante": return "Déjalo en Después por ahora."
        default: return "Está bien dejarlo para Después."
        }
    }
}
