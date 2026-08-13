import MessageUI
import SwiftUI
import SwiftData

struct WaitingView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics
    @Query(sort: \TaskItem.waitingSince, order: .forward) private var tasks: [TaskItem]
    @State private var followUpTask: TaskItem?

    private var waitingTasks: [TaskItem] {
        tasks.filter { $0.state == .waiting }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Esperando")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(SRDesign.ink)
                        Text("Asuntos que no dependen solo de ti.")
                            .font(.body)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                    .padding(.top, 10)

                    if waitingTasks.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "hourglass")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(SRDesign.lavender)
                            Text("No estás esperando nada")
                                .font(.headline)
                                .foregroundStyle(SRDesign.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 48)
                        .srCard()
                    } else {
                        VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                            HStack(spacing: 6) {
                                Image(systemName: "hand.draw")
                                    .font(.caption)
                                Text("Desliza a la derecha cuando ya esté resuelto")
                                    .font(.caption)
                            }
                            .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                            .padding(.leading, 4)

                            LazyVStack(spacing: metrics.rowSpacing) {
                                ForEach(waitingTasks) { task in
                                    SRSwipeToComplete(radius: metrics.rowRadius) {
                                        complete(task)
                                    } content: {
                                        WaitingRow(task: task, metrics: metrics) {
                                            followUpTask = task
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
                .padding(.bottom, metrics.isTall ? 40 : 30)
            }
            .background(SRDesign.background.ignoresSafeArea())
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .sheet(item: $followUpTask) { task in
            FollowUpSheet(task: task)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
        }
    }

    private func complete(_ task: TaskItem) {
        SRTaskCommands.complete(task, context: modelContext)
    }
}

private struct WaitingRow: View {
    let task: TaskItem
    let metrics: SRMetrics
    let onFollowUp: () -> Void

    private var isLongWaiting: Bool {
        task.waitingDays >= 3
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "hourglass")
                    .foregroundStyle(SRDesign.lavender)
                    .frame(width: 30, height: 30)
                    .background(SRDesign.lavender.opacity(0.13))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 5) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SRDesign.ink)
                    Text(task.waitingFor ?? "Sin asunto indicado")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                Spacer()
                Text(waitingDuration)
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
            }

            if isLongWaiting {
                Button {
                    onFollowUp()
                    SRHaptics.light()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.up.right")
                            .font(.system(size: 11, weight: .semibold))
                        Text("Han pasado \(task.waitingDays) días. ¿Hacemos seguimiento?")
                            .font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    .foregroundStyle(SRDesign.primary)
                }
                .buttonStyle(SRPressStyle())
            }
        }
        .padding(metrics.rowPadding)
        .background(SRDesign.surface)
        .clipShape(.rect(cornerRadius: metrics.rowRadius))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.rowRadius, style: .continuous)
                .stroke(
                    isLongWaiting ? SRDesign.lavender.opacity(0.42) : SRDesign.divider.opacity(0.42),
                    lineWidth: isLongWaiting ? 1 : 0.7
                )
        }
    }

    private var waitingDuration: String {
        let days = task.waitingDays
        return days <= 0 ? "hoy" : "\(days)d"
    }
}

/// A follow-up draft, written on device. SinRutina never sends it: the person
/// copies it and decides where it goes.
private struct FollowUpSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem

    @State private var draft = ""
    @State private var isWriting = true
    @State private var didCopy = false
    @State private var showsComposer = false

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Seguimiento")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(SRDesign.ink)
                        Text("\(task.waitingFor ?? "Esta persona") lleva \(task.waitingDays) días sin responder.")
                            .font(.subheadline)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                    .padding(.top, 8)

                    if isWriting {
                        HStack(spacing: 10) {
                            ProgressView().tint(SRDesign.primary)
                            Text("Escribiendo un borrador en este iPhone…")
                                .font(.subheadline)
                                .foregroundStyle(SRDesign.secondaryInk)
                        }
                        .padding(.vertical, 20)
                    } else {
                        Text(draft)
                            .font(.body)
                            .foregroundStyle(SRDesign.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SRDesign.primarySoft.opacity(0.45))
                            .clipShape(.rect(cornerRadius: 18, style: .continuous))
                            .textSelection(.enabled)

                        Text("SinRutina no envía nada. Copia el texto y mándalo donde quieras.")
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }

                    VStack(spacing: 10) {
                        Button(didCopy ? "Copiado" : "Copiar borrador") {
                            UIPasteboard.general.string = draft
                            didCopy = true
                            task.lastFollowUpAt = Date()
                            BehaviorRecorder.recordFollowUp(context: modelContext)
                            try? modelContext.save()
                            SRHaptics.success()
                        }
                        .buttonStyle(SRPrimaryButtonStyle())
                        .disabled(isWriting)

                        if task.isMail {
                            Button("Abrir el compositor de correo") {
                                task.mailReplyDraft = draft
                                task.lastFollowUpAt = Date()
                                BehaviorRecorder.recordFollowUp(context: modelContext)
                                try? modelContext.save()
                                showsComposer = true
                            }
                            .buttonStyle(SRQuietButtonStyle())
                            .frame(maxWidth: .infinity)
                            .disabled(isWriting)
                        }

                        Button("Ya respondió") {
                            SRTaskCommands.complete(task, context: modelContext)
                            SRHaptics.success()
                            dismiss()
                        }
                        .buttonStyle(SRQuietButtonStyle())
                        .frame(maxWidth: .infinity)

                        Button("Lo retomo yo, muévelo a Ahora") {
                            task.lastFollowUpAt = Date()
                            SRTaskCommands.postpone(task, to: .now, context: modelContext)
                            SRHaptics.light()
                            dismiss()
                        }
                        .buttonStyle(SRQuietButtonStyle())
                        .frame(maxWidth: .infinity)

                        Button("Todavía no") {
                            task.lastFollowUpAt = Date()
                            task.updatedAt = Date()
                            try? modelContext.save()
                            dismiss()
                        }
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                    }
                    .padding(.top, 4)
                }
                .padding(.horizontal, SRDesign.pagePadding)
                .padding(.bottom, 24)
            }
            .background(SRDesign.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showsComposer) {
            MailComposerView(
                draft: MailComposerView.Draft(
                    recipients: task.mailSender.map { [$0] } ?? [],
                    subject: followUpSubject,
                    body: draft,
                    attachmentNames: task.attachmentNames
                )
            ) { result in
                if result == .sent {
                    task.lastFollowUpAt = Date()
                    try? modelContext.save()
                    SRHaptics.success()
                    dismiss()
                }
            }
            .ignoresSafeArea()
        }
        .task {
            let text = await SRIntelligenceService.shared.followUpDraft(
                taskTitle: task.title,
                person: task.waitingFor,
                days: max(task.waitingDays, 1)
            )
            withAnimation(SRDesign.softAnimation) {
                draft = text
                isWriting = false
            }
        }
    }

    private var followUpSubject: String {
        guard let subject = task.mailSubject, !subject.isEmpty else { return task.title }
        return subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }
}
