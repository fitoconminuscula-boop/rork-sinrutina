import SwiftUI
import SwiftData

/// What happens when the same suggestion keeps being walked past.
///
/// The ladder is deliberately downwards: change the moment, then make the task
/// smaller, and only then ask. "Ya no importa" is a first-class answer.
struct AdaptationSheet: View {
    let task: TaskItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    @State private var smallerStep: String?
    @State private var isThinking = true
    @State private var proposedSlot: ContextualReminderPlanner.Slot?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SRPresenceView(state: .suggesting, size: 34)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            .padding(.top, 22)

            Text("Esto sigue apareciendo. ¿Qué hacemos?")
                .font(.title2.weight(.bold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(task.title)
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 10) {
                optionRow(
                    title: "Hacerlo más pequeño",
                    detail: smallerStep ?? (isThinking ? "Buscando el primer paso…" : "Quedarnos solo con el primer movimiento."),
                    symbol: "scissors"
                ) {
                    makeSmaller()
                }

                optionRow(
                    title: "Buscar otro momento",
                    detail: proposedSlot?.label ?? "Dejar que el calendario elija.",
                    symbol: "clock.arrow.circlepath"
                ) {
                    changeTiming()
                }

                optionRow(
                    title: "Ya no importa",
                    detail: "Lo dejamos ir sin borrarlo.",
                    symbol: "wind"
                ) {
                    release()
                }

                optionRow(
                    title: "Mantener como está",
                    detail: "Sigue apareciendo igual.",
                    symbol: "equal"
                ) {
                    keep()
                }
            }

            Spacer(minLength: 0)
        }
        .srContentWidth(metrics)
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, 24)
        .background(SRDesign.background.ignoresSafeArea())
        .task {
            proposedSlot = ContextualReminderPlanner.proposeSlot(
                for: task,
                profile: BehaviorRecorder.profile(context: modelContext)
            )
            let actions = task.isStudy
                ? SRStudyDetector.microActions(title: task.title, hasMaterial: false)
                : await SRIntelligenceService.shared.microActions(
                    for: task.title,
                    context: task.preferredContext
                )
            withAnimation(SRDesign.softAnimation) {
                smallerStep = actions.first
                isThinking = false
            }
        }
    }

    private func optionRow(
        title: String,
        detail: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SRDesign.primary)
                    .frame(width: 32, height: 32)
                    .background(SRDesign.primarySoft)
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srCard(radius: metrics.rowRadius)
        }
        .buttonStyle(SRPressStyle())
    }

    // MARK: - Actions

    private func makeSmaller() {
        guard let smallerStep else { return }
        task.shrink(to: smallerStep, minutes: 3)
        task.ignoredInterventionCount = 0
        BehaviorRecorder.recordMicroActionWin(smallerStep, context: modelContext)
        try? modelContext.save()
        SRTaskCommands.refreshOutsideSurfaces(context: modelContext)
        SRHaptics.success()
        dismiss()
    }

    private func changeTiming() {
        if let proposedSlot {
            ContextualReminderPlanner.apply(proposedSlot, to: task, context: modelContext)
        }
        task.ignoredInterventionCount = 0
        try? modelContext.save()
        SRHaptics.light()
        dismiss()
    }

    private func release() {
        // Nothing is deleted: it moves to "Algún día" and stops asking.
        task.wasReleased = true
        task.ignoredInterventionCount = 0
        SRTaskCommands.postpone(task, to: .someday, context: modelContext)
        SRHaptics.light()
        dismiss()
    }

    private func keep() {
        task.ignoredInterventionCount = 0
        try? modelContext.save()
        dismiss()
    }
}
