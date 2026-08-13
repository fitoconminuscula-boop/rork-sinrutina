import SwiftUI

struct SaturatedView: View {
    let task: TaskItem
    let onStart: () -> Void
    let onExit: () -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var microActions: [String] = []
    @State private var isThinking = true

    private var fallbackStep: String {
        NextActionEngine().microStep(for: task)
    }

    private var firstAction: String {
        microActions.first ?? fallbackStep
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Spacer()
                Button("Salir") { onExit() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
            }

            Spacer()

            // Saturated is the one screen with nothing to read: the smallest
            // movement, and no second step to consider.
            Text(firstAction)
                .font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
                .animation(SRDesign.softAnimation, value: firstAction)

            if isThinking {
                Text("Buscando el movimiento más pequeño…")
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.8))
                    .padding(.top, 14)
                    .transition(.opacity)
            }

            Spacer()

            Button("Hacer solo eso") {
                // The movement that unlocked things is worth remembering.
                BehaviorRecorder.recordMicroActionWin(firstAction, context: modelContext)
                onStart()
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .padding(.bottom, 12)
        }
        .padding(.horizontal, SRDesign.pagePadding)
        .padding(.top, 22)
        .background(SRDesign.background.ignoresSafeArea())
        .task(id: task.id) {
            isThinking = true
            // Studying stuck is its own kind of stuck: the goal is opening the file,
            // not finishing the chapter.
            let actions: [String]
            if task.isStudy {
                actions = SRStudyDetector.microActions(
                    title: task.title,
                    hasMaterial: !task.attachmentNames.isEmpty
                )
            } else {
                actions = await SRIntelligenceService.shared.microActions(
                    for: task.title,
                    context: task.preferredContext
                )
            }
            withAnimation(SRDesign.softAnimation) {
                microActions = actions
                isThinking = false
            }
        }
    }
}
