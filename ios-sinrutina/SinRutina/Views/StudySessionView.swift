import SwiftUI
import SwiftData

/// The study surface.
///
/// Study is not a separate app inside SinRutina: it is the same one task at a
/// time, with an objective, its material and a way to ask about what does not fit
/// in your head yet.
struct StudySessionView: View {
    let task: TaskItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics
    @Query private var allMaterials: [StudyMaterial]

    @State private var coordinator = StudyCoordinator()
    @State private var plan: SRStudyPlan?
    @State private var isPlanning = false
    @State private var showsImporter = false
    @State private var explainTarget: ExplainTarget?
    @State private var showsRecall = false
    @State private var showsExamPlan = false
    @State private var readingMaterial: StudyMaterial?
    @State private var appearance = SRAppearanceStore.shared

    private var materials: [StudyMaterial] {
        allMaterials
            .filter { $0.taskID == task.id }
            .sorted { $0.addedAt > $1.addedAt }
    }

    private var mainMaterial: StudyMaterial? { materials.first }

    private var objective: String? {
        task.studyObjective ?? SRStudyDetector.objective(title: task.title, detail: task.detail)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                if let objective {
                    objectiveBlock(objective)
                        .padding(.top, 16)
                }

                sessionBlock
                    .padding(.top, metrics.sectionSpacing)

                materialBlock
                    .padding(.top, metrics.sectionSpacing)

                if task.dueDate != nil {
                    examBlock
                        .padding(.top, metrics.sectionSpacing)
                }

                actions
                    .padding(.top, metrics.sectionSpacing)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.top, 14)
            .padding(.bottom, 44)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .task(id: task.id) {
            plan = task.studyPlan
            coordinator.sourceMode = task.sourceMode
            guard plan == nil else { return }
            await buildPlan()
        }
        .sheet(isPresented: $showsImporter) {
            MaterialImportSheet(task: task)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $explainTarget) { target in
            ExplainView(
                task: task,
                material: target.material ?? mainMaterial,
                initialFragment: target.fragment
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showsRecall) {
            RecallView(task: task, material: mainMaterial)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(isPresented: $showsExamPlan) {
            ExamPlanView(task: task, materialMinutes: mainMaterial?.estimatedReadingMinutes)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
        .sheet(item: $readingMaterial) { material in
            MaterialReaderView(material: material) { fragment in
                explainTarget = ExplainTarget(material: material, fragment: fragment)
            }
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationContentInteraction(.scrolls)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SRPresenceView(state: .focusing, size: 36)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            Text(task.title)
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            if appearance.profile.shows(.duration) {
                Text("\(plan?.totalMinutes ?? task.estimatedMinutes) min")
                    .font(.headline)
                    .foregroundStyle(SRDesign.primary)
            }
        }
    }

    private func objectiveBlock(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            SRSectionLabel(text: "Objetivo")
            Text(text)
                .font(.body)
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srSurface(radius: metrics.rowRadius, accent: SRDesign.primary)
    }

    private var sessionBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SRSectionLabel(text: "Esta sesión")
                Spacer()
                Button {
                    Task { await buildPlan(force: true) }
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .buttonStyle(SRPressStyle())
                .accessibilityLabel("Proponer otra división")
                .disabled(isPlanning)
            }

            if isPlanning {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Dividiendo el objetivo…")
                        .font(.footnote)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
            } else if let plan, !plan.steps.isEmpty {
                VStack(spacing: 0) {
                    ForEach(Array(plan.steps.enumerated()), id: \.element.id) { index, step in
                        HStack(alignment: .top, spacing: 13) {
                            Image(systemName: step.kind.symbolName)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(SRDesign.primary)
                                .frame(width: 26, height: 26)
                                .background(SRDesign.primarySoft)
                                .clipShape(Circle())
                            VStack(alignment: .leading, spacing: 3) {
                                Text(step.text)
                                    .font(.body)
                                    .foregroundStyle(SRDesign.ink)
                                    .fixedSize(horizontal: false, vertical: true)
                                if appearance.profile.shows(.duration) {
                                    Text("\(step.minutes) min")
                                        .font(.caption)
                                        .foregroundStyle(SRDesign.secondaryInk)
                                }
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 12)

                        if index < plan.steps.count - 1 {
                            Divider().overlay(SRDesign.divider).padding(.leading, 39)
                        }
                    }
                }
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private var materialBlock: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SRSectionLabel(text: "Material")
                Spacer()
                Button {
                    showsImporter = true
                    SRHaptics.light()
                } label: {
                    Label("Añadir", systemImage: "plus")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SRDesign.primary)
                }
                .buttonStyle(SRPressStyle())
            }

            if materials.isEmpty {
                Text("Sin material todavía. Puedes añadir un PDF, un texto, una nota o una página.")
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(spacing: 0) {
                    ForEach(materials) { material in
                        Button {
                            material.lastOpenedAt = Date()
                            try? modelContext.save()
                            readingMaterial = material
                            SRHaptics.light()
                        } label: {
                            HStack(spacing: 13) {
                                Image(systemName: material.kind.symbolName)
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(SRDesign.primary)
                                    .frame(width: 30, height: 30)
                                    .background(SRDesign.primarySoft)
                                    .clipShape(Circle())
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(material.title)
                                        .font(.body.weight(.medium))
                                        .foregroundStyle(SRDesign.ink)
                                        .lineLimit(2)
                                        .multilineTextAlignment(.leading)
                                    Text(material.subtitle)
                                        .font(.caption)
                                        .foregroundStyle(SRDesign.secondaryInk)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(SRDesign.secondaryInk)
                            }
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(SRPressStyle())
                        .contextMenu {
                            Button(role: .destructive) {
                                remove(material)
                            } label: {
                                Label("Quitar de esta tarea", systemImage: "trash")
                            }
                        }

                        if material.id != materials.last?.id {
                            Divider().overlay(SRDesign.divider).padding(.leading, 43)
                        }
                    }
                }
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private var examBlock: some View {
        Button {
            showsExamPlan = true
            SRHaptics.light()
        } label: {
            HStack(spacing: 13) {
                SRIconBadge(symbol: "calendar.badge.clock", tint: SRDesign.sky, size: 38)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Reparto hasta la fecha")
                        .font(.body.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                    Text(dueLabel)
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            .padding(14)
            .srSurface(radius: metrics.rowRadius, accent: SRDesign.sky)
        }
        .buttonStyle(SRPressStyle())
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button {
                explainTarget = ExplainTarget(material: mainMaterial, fragment: "")
                SRHaptics.soft()
            } label: {
                Label("Explícame esto", systemImage: "text.bubble")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SRPrimaryButtonStyle())

            Button {
                showsRecall = true
                SRHaptics.light()
            } label: {
                Text("Antes de terminar")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SRQuietButtonStyle())
        }
    }

    private var dueLabel: String {
        guard let due = task.dueDate else { return "Sin fecha" }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: due).day ?? 0
        if days < 0 { return "La fecha ya pasó" }
        if days == 0 { return "Es hoy" }
        if days == 1 { return "Es mañana" }
        return "Quedan \(days) días"
    }

    // MARK: - Actions

    private func buildPlan(force: Bool = false) async {
        guard !isPlanning else { return }
        isPlanning = true
        defer { isPlanning = false }
        if force { task.studyPlanJSON = nil }
        let result = await coordinator.plan(for: task, material: mainMaterial, context: modelContext)
        withAnimation(SRDesign.softAnimation) { plan = result }
    }

    private func remove(_ material: StudyMaterial) {
        if let fileName = material.fileName {
            AttachmentStore.remove(fileName)
        }
        modelContext.delete(material)
        try? modelContext.save()
        SRHaptics.light()
    }
}

/// Identifies which fragment an explanation was requested for.
struct ExplainTarget: Identifiable {
    var id = UUID()
    var material: StudyMaterial?
    var fragment: String
}
