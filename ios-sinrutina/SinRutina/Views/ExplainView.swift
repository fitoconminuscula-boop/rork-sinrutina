import SwiftUI
import SwiftData

/// "Explícame esto".
///
/// One answer at a time, three obvious next moves, and everything else tucked
/// into a quiet menu. It is not a chat: there is no text field waiting for a
/// prompt, and the sources are always one tap away.
struct ExplainView: View {
    let task: TaskItem?
    let material: StudyMaterial?
    /// Text the person selected in the material, if any.
    var initialFragment: String = ""

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics
    @Environment(\.openURL) private var openURL

    @State private var coordinator: StudyCoordinator
    @State private var showsSources = false
    @State private var showsComparison = false
    @State private var recallQuestion: SRRecallQuestion?

    init(task: TaskItem?, material: StudyMaterial?, initialFragment: String = "") {
        self.task = task
        self.material = material
        self.initialFragment = initialFragment
        let mode = task?.sourceMode ?? SRSourceMode.mixed
        _coordinator = State(initialValue: StudyCoordinator(sourceMode: mode))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                sourceModePicker
                    .padding(.top, 18)

                if !initialFragment.isEmpty {
                    fragmentBlock
                        .padding(.top, 18)
                }

                if coordinator.explanations.isEmpty && !coordinator.isWorking {
                    emptyState
                        .padding(.top, 26)
                } else {
                    ForEach(coordinator.explanations) { explanation in
                        explanationBlock(explanation)
                            .padding(.top, 18)
                    }
                }

                if coordinator.isWorking {
                    workingRow
                        .padding(.top, 18)
                }

                if let message = coordinator.errorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .padding(.top, 14)
                }

                actionRow
                    .padding(.top, 22)

                if !coordinator.citedSources.isEmpty {
                    sourcesBlock
                        .padding(.top, 22)
                }

                privacyNote
                    .padding(.top, 24)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .task {
            coordinator.selectedFragment = initialFragment
            guard coordinator.explanations.isEmpty else { return }
            // Open with the shape this person usually asks for.
            let opening = LearningEngine.preferredExplainAction ?? .simpler
            await coordinator.explain(
                action: opening,
                material: material,
                task: task,
                context: modelContext
            )
        }
        .sheet(isPresented: $showsComparison) {
            ComparisonSheet(comparison: coordinator.comparison, isWorking: coordinator.isWorking)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $recallQuestion) { question in
            SingleQuestionSheet(
                question: question,
                origin: material?.title ?? task?.title,
                taskID: task?.id,
                materialID: material?.id
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Pieces

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SRPresenceView(state: coordinator.isWorking ? .focusing : .neutral, size: 34)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            Text("Explícame esto")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(SRDesign.ink)
            if let material {
                Text(material.title)
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .lineLimit(2)
            } else if let task {
                Text(task.title)
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .lineLimit(2)
            }
        }
        .padding(.top, 14)
    }

    private var sourceModePicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Fuentes")
            Picker("Fuentes", selection: Binding(
                get: { coordinator.sourceMode },
                set: { newValue in
                    coordinator.sourceMode = newValue
                    task?.sourceMode = newValue
                    try? modelContext.save()
                    SRHaptics.light()
                }
            )) {
                ForEach(SRSourceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            Text(coordinator.sourceMode.explanation)
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
        }
    }

    private var fragmentBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            SRSectionLabel(text: "Fragmento seleccionado")
            Text(initialFragment)
                .font(.callout)
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(SRDesign.primarySoft.opacity(0.45))
                .clipShape(.rect(cornerRadius: metrics.rowRadius, style: .continuous))
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Elige por dónde empezamos")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text("Puedo explicarlo más simple, ir más a fondo o darte un ejemplo.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private var workingRow: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(coordinator.isLeavingDevice ? "Buscando fuera del iPhone…" : "Pensando aquí dentro…")
                .font(.footnote)
                .foregroundStyle(SRDesign.secondaryInk)
        }
    }

    private func explanationBlock(_ explanation: SRExplanation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: explanation.action.symbolName)
                    .font(.system(size: 11, weight: .semibold))
                Text(explanation.action.label)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Label(explanation.provenance.label, systemImage: explanation.provenance.symbolName)
                    .font(.caption2)
                    .labelStyle(.titleAndIcon)
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            .foregroundStyle(SRDesign.primary)

            Text(explanation.body)
                .font(.body)
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let question = explanation.followUpQuestion {
                Button {
                    recallQuestion = SRRecallQuestion(
                        question: question,
                        concept: SRIntelligenceService.conceptGuess(from: question)
                    )
                    SRHaptics.light()
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "questionmark.circle")
                        Text(question)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(SRDesign.primary)
                    .padding(12)
                    .background(SRDesign.primarySoft.opacity(0.5))
                    .clipShape(.rect(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(SRPressStyle())
            }

            if !explanation.sources.isEmpty {
                Text("\(explanation.sources.count) \(explanation.sources.count == 1 ? "fuente" : "fuentes") usadas")
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk)
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private var actionRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                ForEach(SRExplainAction.primary) { action in
                    Button {
                        ask(action)
                    } label: {
                        Text(action.label)
                            .font(.footnote.weight(.semibold))
                            .frame(maxWidth: .infinity)
                            .frame(height: 40)
                    }
                    .buttonStyle(SRQuietButtonStyle())
                    .disabled(coordinator.isWorking)
                }
            }

            Menu {
                ForEach(SRExplainAction.secondary) { action in
                    Button {
                        if action == .compare {
                            compare()
                        } else {
                            ask(action)
                        }
                    } label: {
                        Label(action.label, systemImage: action.symbolName)
                    }
                }
            } label: {
                HStack(spacing: 6) {
                    Text("Más opciones")
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.bold))
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(SRDesign.secondaryInk)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
            }
            .disabled(coordinator.isWorking)
        }
    }

    private var sourcesBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(SRDesign.quickAnimation) { showsSources.toggle() }
            } label: {
                HStack {
                    SRSectionLabel(text: "Fuentes")
                    Spacer()
                    Image(systemName: showsSources ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SRDesign.secondaryInk)
                }
            }
            .buttonStyle(SRPressStyle())

            if showsSources {
                VStack(spacing: 0) {
                    ForEach(coordinator.citedSources) { source in
                        Button {
                            guard let url = source.url else { return }
                            openURL(url)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: source.tier.symbolName)
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(SRDesign.primary)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(source.title)
                                        .font(.footnote.weight(.medium))
                                        .foregroundStyle(SRDesign.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(source.subtitle)
                                        .font(.caption2)
                                        .foregroundStyle(SRDesign.secondaryInk)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(SRDesign.secondaryInk)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(SRPressStyle())

                        if source.id != coordinator.citedSources.last?.id {
                            Divider().overlay(SRDesign.divider)
                        }
                    }
                }
                .padding(.horizontal, 14)
                .srCard(radius: metrics.rowRadius)
                .padding(.top, 10)
                .transition(.opacity)
            }
        }
    }

    private var privacyNote: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(
                coordinator.sourceMode == .onlyMine
                    ? "Nada sale de este iPhone."
                    : "Al buscar fuera solo se envía una consulta corta.",
                systemImage: coordinator.sourceMode == .onlyMine ? "lock" : "globe"
            )
            .font(.caption)
            .foregroundStyle(SRDesign.secondaryInk)

            if let query = coordinator.lastSentQuery {
                Text("Última consulta enviada: «\(query)»")
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: - Actions

    private func ask(_ action: SRExplainAction) {
        SRHaptics.light()
        Task {
            await coordinator.explain(
                action: action,
                material: material,
                task: task,
                context: modelContext
            )
        }
    }

    private func compare() {
        SRHaptics.light()
        showsComparison = true
        Task {
            await coordinator.compareWithMaterial(
                material: material,
                question: initialFragment.isEmpty ? (task?.title ?? "") : initialFragment,
                context: modelContext
            )
        }
    }
}

/// "¿Coincide con mi texto?" laid out as five short lists, all of which may be empty.
private struct ComparisonSheet: View {
    let comparison: SRComparison?
    let isWorking: Bool

    @Environment(\.srMetrics) private var metrics

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 20) {
                Text("¿Coincide con mi texto?")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(SRDesign.ink)
                    .padding(.top, 20)

                if isWorking {
                    HStack(spacing: 10) {
                        ProgressView().controlSize(.small)
                        Text("Contrastando…")
                            .font(.footnote)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                } else if let comparison, !comparison.isEmpty {
                    group("Coincide", comparison.agreements, symbol: "equal.circle", tint: SRDesign.mint)
                    group("Se diferencia", comparison.differences, symbol: "arrow.left.arrow.right", tint: SRDesign.sky)
                    group("Otra perspectiva", comparison.alternativeViews, symbol: "circle.grid.cross", tint: SRDesign.lavender)
                    group("Contradice", comparison.contradictions, symbol: "exclamationmark.triangle", tint: SRDesign.blush)
                    group("Más reciente", comparison.recentInformation, symbol: "clock.arrow.circlepath", tint: SRDesign.primary)
                } else {
                    Text("No hay nada que contrastar todavía.")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 34)
        }
        .background(SRDesign.background.ignoresSafeArea())
    }

    @ViewBuilder
    private func group(_ title: String, _ items: [String], symbol: String, tint: Color) -> some View {
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                ForEach(items, id: \.self) { item in
                    Text(item)
                        .font(.callout)
                        .foregroundStyle(SRDesign.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .srSurface(accent: tint)
        }
    }
}

/// A single question asked in the middle of an explanation, with no score attached.
private struct SingleQuestionSheet: View {
    let question: SRRecallQuestion
    let origin: String?
    let taskID: UUID?
    let materialID: UUID?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics
    @State private var answer = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SRSectionLabel(text: "Pregúntame")
                .padding(.top, 22)

            Text(question.question)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            TextField("Contéstalo con tus palabras", text: $answer, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(14)
                .frame(minHeight: 96, alignment: .topLeading)
                .background(SRDesign.surface)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 0)

            Button("Listo") { save(outcome: .answered) }
                .buttonStyle(SRPrimaryButtonStyle())
                .disabled(answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("No sé") { save(outcome: .dontKnow) }
                .buttonStyle(SRQuietButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.bottom, 18)
        }
        .srContentWidth(metrics)
        .padding(.horizontal, metrics.pagePadding)
        .background(SRDesign.background.ignoresSafeArea())
    }

    private func save(outcome: SRRecallOutcome) {
        let created = ReviewScheduler.remember(
            questions: [question],
            origin: origin,
            taskID: taskID,
            materialID: materialID,
            context: modelContext
        )
        if let concept = created.first {
            ReviewScheduler.record(outcome: outcome, for: concept, context: modelContext)
        }
        SRHaptics.light()
        dismiss()
    }
}
