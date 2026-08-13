import SwiftUI
import SwiftData

/// "Hazlo conmigo".
///
/// One step at a time, with a single button. There is no chat, no coach and no
/// voice: the SinRutina mark simply stays at the edge of the screen while the
/// person works through the list.
struct StepByStepView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics

    let task: TaskItem
    /// Called when every step is done, so the caller can offer "Terminé".
    var onFinished: () -> Void = {}

    @State private var appearance = SRAppearanceStore.shared
    @State private var steps: [String] = []
    @State private var index = 0
    @State private var isThinking = true

    private var profile: SRAppearanceProfile { appearance.profile }
    private var isComplete: Bool { !steps.isEmpty && index >= steps.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                if profile.presence.showsInSheets {
                    SRPresenceView(state: isComplete ? .completed : .focusing, size: 32)
                }
                Text(task.title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button("Cerrar") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            .padding(.bottom, 26)

            if isThinking {
                Text("Buscando los pasos…")
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.secondaryInk)
            } else if isComplete {
                completion
            } else {
                current
            }

            Spacer()

            if !isThinking, !isComplete {
                Button("Hecho") {
                    advance()
                }
                .buttonStyle(SRPrimaryButtonStyle())

                Button("Saltar este paso") {
                    withAnimation(SRDesign.quickAnimation) { index += 1 }
                }
                .buttonStyle(SRQuietButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
            }
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, 22)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SRDesign.background.ignoresSafeArea())
        .task(id: task.id) { await loadSteps() }
    }

    // MARK: - Pieces

    private var current: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paso \(index + 1)")
                .font(.caption.weight(.semibold))
                .tracking(0.8)
                .foregroundStyle(SRDesign.primary)

            Text(steps[min(index, steps.count - 1)])
                .font(.title.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
                .animation(SRDesign.softAnimation, value: index)

            if steps.count > 1, metrics.showsSecondaryDetail {
                Text("\(steps.count - index - 1) después de este.")
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
            }
        }
    }

    private var completion: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Eso era todo.")
                .font(.title.weight(.bold))
                .foregroundStyle(SRDesign.ink)
            Text("Si ya está hecho, ciérralo desde la tarea.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            Button("Volver a la tarea") {
                onFinished()
                dismiss()
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .padding(.top, 8)
        }
    }

    // MARK: - Logic

    private func advance() {
        // The step that unlocked movement is worth remembering.
        if index == 0, let first = steps.first {
            BehaviorRecorder.recordMicroActionWin(first, context: modelContext)
        }
        SRHaptics.light()
        withAnimation(SRDesign.softAnimation) { index += 1 }
    }

    private func loadSteps() async {
        isThinking = true
        var resolved: [String] = []

        // A study session already has its own plan; reuse it instead of inventing.
        if let plan = task.studyPlan, !plan.steps.isEmpty {
            resolved = plan.steps.map(\.text)
        } else if task.isStudy {
            resolved = SRStudyDetector.microActions(
                title: task.title,
                hasMaterial: !task.attachmentNames.isEmpty
            )
        } else {
            resolved = await SRIntelligenceService.shared.split(title: task.title)
        }

        if resolved.isEmpty, let step = task.nextStep {
            resolved = [step]
        }
        withAnimation(SRDesign.softAnimation) {
            steps = resolved
            isThinking = false
        }
    }
}

/// "Avancé, pero no terminé" — asks the one useful question and writes the next
/// action, so progress is never lost between sessions.
struct PartialProgressSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics

    let task: TaskItem
    /// Minutes actually worked, recorded as real duration.
    let minutes: Double
    let onSaved: (String?) -> Void

    @State private var note = ""
    @State private var isWorking = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("¿Dónde quedaste?")
                .font(.title2.weight(.bold))
                .foregroundStyle(SRDesign.ink)

            Text("Una frase basta. La próxima vez empiezas justo ahí.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 8)

            TextField("Por ejemplo: resultados, página 8", text: $note, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .foregroundStyle(SRDesign.ink)
                .lineLimit(2...4)
                .padding(14)
                .background(SRDesign.elevatedSurface)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))
                .padding(.top, 20)

            Button {
                save()
            } label: {
                Text(isWorking ? "Guardando…" : "Guardar y salir")
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .disabled(isWorking)
            .padding(.top, 20)

            Button("Sin nota") {
                save(skipNote: true)
            }
            .buttonStyle(SRQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.top, 14)
        }
        .padding(.horizontal, metrics.pagePadding)
        .padding(.top, 26)
        .padding(.bottom, 30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SRDesign.background.ignoresSafeArea())
    }

    private func save(skipNote: Bool = false) {
        isWorking = true
        let trimmed = skipNote ? "" : note.trimmingCharacters(in: .whitespacesAndNewlines)
        // The progress becomes the next concrete movement, not a diary entry.
        if !trimmed.isEmpty {
            task.shrink(to: "Continuar desde \(trimmed.lowercased())")
            task.notes = trimmed
        }
        task.actualDuration = (task.actualDuration ?? 0) + max(0, minutes)
        if task.isStudy { task.studiedMinutes += max(0, minutes) }
        task.move(to: .after)
        try? modelContext.save()
        BehaviorRecorder.recordPartialProgress(context: modelContext)
        SRTaskCommands.refreshOutsideSurfaces(context: modelContext)
        SRHaptics.success()
        onSaved(trimmed.isEmpty ? nil : trimmed)
        dismiss()
    }
}
