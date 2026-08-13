import SwiftUI
import SwiftData

/// "Lo que SinRutina ha aprendido".
///
/// Every line is an observable behaviour, written in plain Spanish, and every line
/// can be edited, switched off or deleted. Nothing here is a diagnosis, a score or
/// a personality reading — and the person can turn the whole layer off.
struct LearnedView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics
    @State private var store = SRLearningStore.shared
    @State private var editingInsight: SRLearnedInsight?
    @State private var editedText = ""
    @State private var showsClearConfirmation = false

    private var insights: [SRLearnedInsight] {
        store.insights.sorted { lhs, rhs in
            if lhs.isEnabled != rhs.isEnabled { return lhs.isEnabled }
            return lhs.updatedAt > rhs.updatedAt
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                header

                if insights.isEmpty {
                    emptyState
                } else {
                    ForEach(insights) { insight in
                        insightRow(insight)
                    }
                }

                masterSwitch

                if !insights.isEmpty {
                    Button {
                        showsClearConfirmation = true
                    } label: {
                        Text("Olvidar todo lo aprendido")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SRDesign.blush)
                            .frame(maxWidth: .infinity)
                            .frame(height: 46)
                            .background(SRDesign.blush.opacity(0.1))
                            .clipShape(.rect(cornerRadius: metrics.rowRadius, style: .continuous))
                    }
                    .buttonStyle(SRPressStyle())
                }

                Label(
                    "Todo esto vive solo en este iPhone y no se comparte con nadie.",
                    systemImage: "lock"
                )
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("Lo aprendido")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog(
            "¿Olvidar todo?",
            isPresented: $showsClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Olvidar", role: .destructive) {
                store.removeAll()
                SRHaptics.light()
            }
            Button("Cancelar", role: .cancel) { }
        } message: {
            Text("SinRutina volverá a empezar de cero con las recomendaciones.")
        }
        .sheet(item: $editingInsight) { insight in
            editSheet(insight)
                .presentationDetents([.height(280)])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Lo que SinRutina ha aprendido")
                .font(.title.weight(.bold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Observaciones sobre cómo trabajas, no sobre cómo eres. Corrige o borra lo que no encaje.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 10) {
            SRPresenceView(state: .neutral, size: 38)
            Text("Todavía no hay nada")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text("Cuando termines algunas cosas empezaré a notar duraciones, horas y qué te desatasca.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private func insightRow(_ insight: SRLearnedInsight) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: insight.kind.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(insight.isEnabled ? SRDesign.primary : SRDesign.secondaryInk)
                    .frame(width: 30, height: 30)
                    .background(
                        (insight.isEnabled ? SRDesign.primarySoft : SRDesign.divider.opacity(0.4))
                    )
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 4) {
                    Text(insight.text)
                        .font(.body)
                        .foregroundStyle(insight.isEnabled ? SRDesign.ink : SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Text(insight.kind.domain.label)
                        if insight.kind.needsConfirmation && !insight.isConfirmed {
                            Text("· sin confirmar")
                        }
                        if !insight.isEnabled {
                            Text("· desactivada")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk)
                }

                Spacer(minLength: 0)

                Toggle("", isOn: Binding(
                    get: { insight.isEnabled },
                    set: { store.setEnabled($0, for: insight) }
                ))
                .labelsHidden()
                .tint(SRDesign.primary)
            }

            if insight.kind.needsConfirmation && !insight.isConfirmed && insight.isEnabled {
                HStack(spacing: 9) {
                    Button("Tenlo en cuenta") {
                        store.confirm(insight)
                        SRHaptics.light()
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.onPrimary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(SRDesign.primary)
                    .clipShape(Capsule(style: .continuous))
                    .buttonStyle(SRPressStyle())

                    Button("No") {
                        store.decline(insight)
                        SRHaptics.light()
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .buttonStyle(SRPressStyle())

                    Spacer(minLength: 0)
                }
            }

            HStack(spacing: 14) {
                Button {
                    editedText = insight.text
                    editingInsight = insight
                } label: {
                    Label("Editar", systemImage: "pencil")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .buttonStyle(SRPressStyle())

                Button {
                    store.remove(insight)
                    SRHaptics.light()
                } label: {
                    Label("Eliminar", systemImage: "trash")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .buttonStyle(SRPressStyle())

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard(radius: metrics.rowRadius)
    }

    private var masterSwitch: some View {
        VStack(alignment: .leading, spacing: 0) {
            Toggle(isOn: Binding(
                get: { store.isLearningEnabled },
                set: { store.setLearningEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Dejar que SinRutina aprenda")
                        .font(.body.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                    Text("Si lo apagas, las recomendaciones siguen funcionando con reglas fijas.")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .tint(SRDesign.primary)
            .padding(.vertical, 15)
        }
        .padding(.horizontal, 16)
        .srCard(radius: metrics.rowRadius)
    }

    private func editSheet(_ insight: SRLearnedInsight) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Corregir")
                .font(.title3.weight(.bold))
                .foregroundStyle(SRDesign.ink)
                .padding(.top, 22)

            TextField("Escríbelo con tus palabras", text: $editedText, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(14)
                .frame(minHeight: 86, alignment: .topLeading)
                .background(SRDesign.surface)
                .clipShape(.rect(cornerRadius: 16, style: .continuous))

            Spacer(minLength: 0)

            Button("Guardar") {
                store.updateText(editedText, for: insight)
                editingInsight = nil
                SRHaptics.light()
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .disabled(editedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .padding(.bottom, 18)
        }
        .srContentWidth(metrics)
        .padding(.horizontal, metrics.pagePadding)
        .background(SRDesign.background.ignoresSafeArea())
    }
}

/// The one question SinRutina asks before an inference starts changing behaviour.
/// It appears at most once at a time, and never for small patterns.
struct LearningConfirmationCard: View {
    let insight: SRLearnedInsight
    let onAnswer: (Bool) -> Void

    @Environment(\.srMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                SRPresenceView(state: .suggesting, size: 34)
                Text(insight.confirmationQuestion)
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                Button("Sí") {
                    SRHaptics.light()
                    onAnswer(true)
                }
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SRDesign.onPrimary)
                .padding(.horizontal, 20)
                .frame(height: 36)
                .background(SRDesign.primary)
                .clipShape(Capsule(style: .continuous))
                .buttonStyle(SRPressStyle())

                Button("No") {
                    SRHaptics.light()
                    onAnswer(false)
                }
                .font(.subheadline.weight(.medium))
                .foregroundStyle(SRDesign.secondaryInk)
                .padding(.horizontal, 14)
                .frame(height: 36)
                .buttonStyle(SRPressStyle())

                Spacer(minLength: 0)
            }
        }
        .padding(14)
        .srSurface(radius: metrics.rowRadius, accent: SRDesign.lavender)
    }
}
