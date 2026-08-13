import SwiftUI
import SwiftData

struct TaskListView: View {
    let state: TaskState
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics
    @Query(sort: \TaskItem.updatedAt, order: .reverse) private var tasks: [TaskItem]
    @State private var insistenceTask: TaskItem?

    private var visibleTasks: [TaskItem] {
        tasks.filter { $0.state == state }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: metrics.sectionSpacing) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(state.rawValue)
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text(description)
                        .font(.body)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .padding(.top, metrics.isTall ? 26 : 18)

                if visibleTasks.isEmpty {
                    emptyState
                } else {
                    VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                        HStack(spacing: 6) {
                            Image(systemName: "hand.draw")
                                .font(.caption)
                            Text("Desliza a la derecha para completar")
                                .font(.caption)
                        }
                        .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                        .padding(.leading, 4)
                        .padding(.bottom, 2)

                        LazyVStack(spacing: metrics.rowSpacing) {
                            ForEach(visibleTasks) { task in
                                SRSwipeToComplete(radius: metrics.rowRadius) {
                                    complete(task)
                                } content: {
                                    TaskRow(task: task, metrics: metrics, modelContext: modelContext) {
                                        insistenceTask = task
                                    }
                                }
                                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                            }
                        }
                    }
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, metrics.isTall ? 44 : 30)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $insistenceTask) { task in
            InsistenceSheet(task: task)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: emptySymbol)
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(tint)
            Text(emptyTitle)
                .font(.headline)
                .foregroundStyle(SRDesign.ink)
            Text("Cuando aparezca algo, quedará aquí sin pedirte más decisiones.")
                .font(.subheadline)
                .foregroundStyle(SRDesign.secondaryInk)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, metrics.isTall ? 68 : 56)
        .padding(.horizontal, 20)
        .srCard()
    }

    private func complete(_ task: TaskItem) {
        SRTaskCommands.complete(task, context: modelContext)
    }

    private var description: String {
        switch state {
        case .after: return "No hace falta decidirlo hoy."
        case .someday: return "Ideas y asuntos para cuando haya espacio."
        default: return ""
        }
    }

    private var emptyTitle: String {
        state == .after ? "Nada esperando tu atención" : "Todavía está despejado"
    }

    private var emptySymbol: String {
        state == .after ? "calendar" : "leaf"
    }

    private var tint: Color {
        state == .after ? SRDesign.sky : SRDesign.mint
    }
}

private struct TaskRow: View {
    let task: TaskItem
    let metrics: SRMetrics
    let modelContext: ModelContext
    let onInsistence: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: task.state == .after ? "calendar" : "leaf")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(task.state == .after ? SRDesign.sky : SRDesign.mint)
                .frame(width: 32, height: 32)
                .background((task.state == .after ? SRDesign.sky : SRDesign.mint).opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                if task.isDemo {
                    SRDemoTag()
                }
                HStack(spacing: 8) {
                    Label("\(task.estimatedMinutes) min", systemImage: "clock")
                    if let availableFrom = task.availableFrom {
                        Label(SRWidgetSnapshot.timeFormatter.string(from: availableFrom), systemImage: "clock.badge")
                    } else if let dueDate = task.dueDate {
                        Text(dueDate, style: .date)
                    }
                    if task.reminderIdentifier != nil {
                        Image(systemName: "link")
                            .accessibilityLabel("Enlazado con Recordatorios")
                    }
                    if task.insistence == .unmissable || task.insistence == .important {
                        Image(systemName: task.insistence.symbolName)
                            .accessibilityLabel("Insistencia \(task.insistence.rawValue)")
                    }
                }
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
            }

            Spacer(minLength: 4)

            Menu {
                Button("Llevar a Ahora") {
                    SRTaskCommands.start(task, context: modelContext)
                    SRHaptics.light()
                }
                Button("Marcar como esperando") {
                    SRTaskCommands.markWaiting(task, for: task.waitingFor, context: modelContext)
                    SRHaptics.light()
                }
                Button("Completar") {
                    SRTaskCommands.complete(task, context: modelContext)
                    SRHaptics.success()
                }
                Divider()
                Button {
                    onInsistence()
                } label: {
                    Label("Insistencia: \(task.insistence.rawValue)", systemImage: task.insistence.symbolName)
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Acciones para \(task.title)")
        }
        .padding(metrics.rowPadding)
        .background(SRDesign.surface)
        .clipShape(.rect(cornerRadius: metrics.rowRadius))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.rowRadius, style: .continuous)
                .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
        }
        .shadow(color: SRDesign.shadow.opacity(0.7), radius: 10, y: 4)
    }
}
