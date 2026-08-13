import SwiftUI
import SwiftData

/// "Antes de terminar".
///
/// One to five questions at the end of a study session. There is no score, no
/// streak and no percentage: an answer only decides when the concept comes back.
struct RecallView: View {
    let task: TaskItem
    let material: StudyMaterial?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    @State private var coordinator = StudyCoordinator()
    @State private var questions: [SRRecallQuestion] = []
    @State private var index = 0
    @State private var answer = ""
    @State private var isLoading = true
    @State private var didFinish = false

    private var current: SRRecallQuestion? {
        guard index < questions.count else { return nil }
        return questions[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if isLoading {
                loadingState
            } else if didFinish || current == nil {
                closingState
            } else if let current {
                questionState(current)
            }

            Spacer(minLength: 0)
        }
        .srContentWidth(metrics)
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, 24)
        .background(SRDesign.background.ignoresSafeArea())
        .task {
            let count = min(max(2, task.estimatedMinutes / 8), 5)
            let result = await coordinator.recallQuestions(
                for: task,
                material: material,
                count: count
            )
            withAnimation(SRDesign.softAnimation) {
                questions = result
                isLoading = false
            }
        }
    }

    // MARK: - States

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SRPresenceView(state: didFinish ? .completed : .suggesting, size: 34)
                Spacer()
                Button(didFinish ? "Cerrar" : "Saltar todo") {
                    if didFinish {
                        dismiss()
                    } else {
                        skipAll()
                    }
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SRDesign.secondaryInk)
            }
            Text("Antes de terminar")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(SRDesign.ink)
            if !isLoading, !didFinish, !questions.isEmpty {
                Text("\(index + 1) de \(questions.count)")
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
            }
        }
        .padding(.top, 20)
        .padding(.bottom, 22)
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Preparando un par de preguntas…")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
        }
    }

    private func questionState(_ question: SRRecallQuestion) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(question.question)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
                .id(question.id)

            TextField("Contéstalo con tus palabras", text: $answer, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(14)
                .frame(minHeight: 110, alignment: .topLeading)
                .background(SRDesign.surface)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))

            VStack(spacing: 10) {
                Button("Responder") { record(.answered) }
                    .buttonStyle(SRPrimaryButtonStyle())
                    .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                HStack(spacing: 10) {
                    Button("No sé") { record(.dontKnow) }
                        .buttonStyle(SRQuietButtonStyle())
                        .frame(maxWidth: .infinity)
                    Button("Saltar") { record(.skipped) }
                        .buttonStyle(SRQuietButtonStyle())
                        .frame(maxWidth: .infinity)
                }
            }

            Text("No hay nota. Solo decide cuándo vuelve a aparecer.")
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
        }
        .animation(SRDesign.softAnimation, value: index)
    }

    private var closingState: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(questions.isEmpty ? "Nada que preguntar todavía." : "Listo.")
                .font(.title2.weight(.bold))
                .foregroundStyle(SRDesign.ink)

            Text(
                questions.isEmpty
                    ? "Cuando haya material con texto podré prepararte preguntas."
                    : "Guardé los conceptos. Volverán cuando toque, no antes."
            )
            .font(.body)
            .foregroundStyle(SRDesign.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)

            Button("Cerrar") { dismiss() }
                .buttonStyle(SRPrimaryButtonStyle())
                .padding(.top, 6)
        }
    }

    // MARK: - Actions

    private func record(_ outcome: SRRecallOutcome) {
        guard let question = current else { return }
        let created = ReviewScheduler.remember(
            questions: [question],
            origin: material?.title ?? task.title,
            taskID: task.id,
            materialID: material?.id,
            context: modelContext
        )
        if let concept = created.first {
            ReviewScheduler.record(
                outcome: outcome,
                for: concept,
                confidence: outcome == .answered ? min(4, answer.count / 40 + 1) : nil,
                context: modelContext
            )
        }
        SRHaptics.light()
        answer = ""
        withAnimation(SRDesign.softAnimation) {
            if index + 1 < questions.count {
                index += 1
            } else {
                didFinish = true
            }
        }
    }

    private func skipAll() {
        // Skipping still saves the concepts: they are worth remembering even if
        // this is not the moment to be asked.
        ReviewScheduler.remember(
            questions: questions,
            origin: material?.title ?? task.title,
            taskID: task.id,
            materialID: material?.id,
            context: modelContext
        )
        dismiss()
    }
}

/// The review that fits a gap: "Tienes 6 minutos. Repasar tres conceptos."
struct ReviewSessionView: View {
    let concepts: [ReviewConcept]

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    @State private var index = 0
    @State private var isRevealed = false
    @State private var didFinish = false

    private var current: ReviewConcept? {
        guard index < concepts.count else { return nil }
        return concepts[index]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                SRPresenceView(state: didFinish ? .completed : .focusing, size: 34)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            .padding(.top, 20)

            Text(didFinish ? "Cerrado." : "Repaso")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(SRDesign.ink)
                .padding(.top, 12)

            if didFinish || current == nil {
                Text("Ya no tienes que acordarte de esto por ahora.")
                    .font(.body)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .padding(.top, 12)
                Button("Cerrar") { dismiss() }
                    .buttonStyle(SRPrimaryButtonStyle())
                    .padding(.top, 22)
            } else if let current {
                Text("\(index + 1) de \(concepts.count)")
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 16) {
                    Text(current.question ?? "¿Qué recuerdas de \(current.concept.lowercased())?")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(SRDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    if let origin = current.origin, !origin.isEmpty {
                        Text(origin)
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }

                    if isRevealed, let idea = current.expectedIdea, !idea.isEmpty {
                        Text(idea)
                            .font(.callout)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SRDesign.primarySoft.opacity(0.5))
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                            .transition(.opacity)
                    }
                }
                .padding(.top, 20)

                Spacer(minLength: 0)

                VStack(spacing: 10) {
                    Button("Lo recuerdo") { record(.answered) }
                        .buttonStyle(SRPrimaryButtonStyle())
                    HStack(spacing: 10) {
                        Button("No sé") { record(.dontKnow) }
                            .buttonStyle(SRQuietButtonStyle())
                            .frame(maxWidth: .infinity)
                        Button("Saltar") { record(.skipped) }
                            .buttonStyle(SRQuietButtonStyle())
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .srContentWidth(metrics)
        .padding(.horizontal, metrics.pagePadding)
        .padding(.bottom, 24)
        .background(SRDesign.background.ignoresSafeArea())
    }

    private func record(_ outcome: SRRecallOutcome) {
        guard let current else { return }
        ReviewScheduler.record(outcome: outcome, for: current, context: modelContext)
        SRHaptics.light()
        withAnimation(SRDesign.softAnimation) {
            isRevealed = false
            if index + 1 < concepts.count {
                index += 1
            } else {
                didFinish = true
            }
        }
    }
}
