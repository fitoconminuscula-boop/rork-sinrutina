import MessageUI
import SwiftUI
import SwiftData

/// The email cycle: understand → summarise → reply → send or park → Esperando →
/// follow-up.
///
/// SinRutina prepares everything and then stops. The composer is Apple's, the send
/// button is the person's, and "Esperando" is offered rather than assumed.
struct MailActionView: View {
    let task: TaskItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics
    @Environment(\.openURL) private var openURL

    @State private var draft: String = ""
    @State private var style: SRReplyStyle?
    @State private var isRewriting = false
    @State private var showsComposer = false
    @State private var showsOriginal = false
    @State private var showsWaitingOffer = false
    @State private var errorMessage: String?

    private var person: String? {
        task.mailSender?.srDisplayName
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header

                summaryBlock
                    .padding(.top, 18)

                if let excerpt = task.mailExcerpt, !excerpt.isEmpty {
                    originalBlock(excerpt)
                        .padding(.top, 14)
                }

                draftBlock
                    .padding(.top, 20)

                styleRow
                    .padding(.top, 14)

                if !task.attachmentNames.isEmpty {
                    attachmentsBlock
                        .padding(.top, 18)
                }

                actions
                    .padding(.top, 24)

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(SRDesign.blush)
                        .padding(.top, 14)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Label("Nada se envía sin que lo mandes tú.", systemImage: "hand.raised")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .padding(.top, 22)
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .task {
            draft = task.mailReplyDraft ?? ""
            style = task.mailReplyStyle ?? LearningEngine.preferredReplyStyle
            if draft.isEmpty { await prepareDraft() }
        }
        .sheet(isPresented: $showsComposer) {
            MailComposerView(
                draft: MailComposerView.Draft(
                    recipients: task.mailSender.map { [$0] } ?? [],
                    subject: replySubject,
                    body: draft,
                    attachmentNames: task.attachmentNames
                )
            ) { result in
                handleComposer(result)
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsWaitingOffer) {
            WaitingOfferSheet(task: task, person: person)
                .presentationDetents([.medium])
                .presentationDragIndicator(.visible)
        }
    }

    // MARK: - Sections

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SRPresenceView(state: task.mailWasAnswered ? .waiting : .suggesting, size: 34)
                Spacer()
                Button("Cerrar") { dismiss() }
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            Text(person.map { "Correo de \($0)" } ?? "Correo")
                .font(.largeTitle.weight(.bold))
                .foregroundStyle(SRDesign.ink)
            if let subject = task.mailSubject, !subject.isEmpty {
                Text(subject)
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .lineLimit(2)
            }
        }
        .padding(.top, 20)
    }

    private var summaryBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(task.mailWasAnswered ? "Ya respondiste" : "Parece requerir respuesta.")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(task.mailWasAnswered ? SRDesign.mint : SRDesign.primary)

            SRSectionLabel(text: "Resumen")
            Text(task.detail.isEmpty ? (task.nextStep ?? "Sin resumen todavía.") : task.detail)
                .font(.body)
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let due = task.dueDate {
                Label(
                    "Fecha mencionada: \(due.formatted(date: .abbreviated, time: .omitted))",
                    systemImage: "calendar"
                )
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
            }
        }
        .padding(metrics.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard()
    }

    private func originalBlock(_ excerpt: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(SRDesign.quickAnimation) { showsOriginal.toggle() }
            } label: {
                HStack {
                    Text(showsOriginal ? "Ocultar el original" : "Ver el correo original")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(SRDesign.secondaryInk)
                    Spacer()
                    Image(systemName: showsOriginal ? "chevron.up" : "chevron.down")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(SRDesign.secondaryInk)
                }
            }
            .buttonStyle(SRPressStyle())

            if showsOriginal {
                Text(excerpt)
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SRDesign.surface)
                    .clipShape(.rect(cornerRadius: metrics.rowRadius, style: .continuous))
                    .transition(.opacity)
            }
        }
    }

    private var draftBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SRSectionLabel(text: "Respuesta sugerida")
                Spacer()
                if isRewriting {
                    ProgressView().controlSize(.small)
                }
            }

            TextField("Escribe la respuesta", text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.body)
                .padding(14)
                .frame(minHeight: 150, alignment: .topLeading)
                .background(SRDesign.surface)
                .clipShape(.rect(cornerRadius: 18, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(SRDesign.divider.opacity(0.5), lineWidth: 0.7)
                }
                .onChange(of: draft) { _, newValue in
                    task.mailReplyDraft = newValue
                }
        }
    }

    private var styleRow: some View {
        VStack(alignment: .leading, spacing: 9) {
            SRSectionLabel(text: "Tono")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(SRReplyStyle.allCases) { option in
                        Button {
                            rewrite(as: option)
                        } label: {
                            Text(option.label)
                                .font(.footnote.weight(.medium))
                                .foregroundStyle(style == option ? SRDesign.onPrimary : SRDesign.secondaryInk)
                                .padding(.horizontal, 14)
                                .frame(height: 34)
                                .background(style == option ? SRDesign.primary : SRDesign.surface)
                                .clipShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(SRPressStyle())
                        .disabled(isRewriting)
                    }
                }
            }
            .contentMargins(.horizontal, 0)
        }
    }

    private var attachmentsBlock: some View {
        VStack(alignment: .leading, spacing: 9) {
            SRSectionLabel(text: "Adjuntos")
            ForEach(task.attachmentNames, id: \.self) { name in
                HStack(spacing: 11) {
                    Image(systemName: "paperclip")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(SRDesign.primary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.footnote.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                            .lineLimit(1)
                        if let size = AttachmentStore.sizeLabel(for: name) {
                            Text(size)
                                .font(.caption2)
                                .foregroundStyle(SRDesign.secondaryInk)
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)
            }
            Text("Se añadirán al correo cuando abras el compositor.")
                .font(.caption2)
                .foregroundStyle(SRDesign.secondaryInk)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .srCard(radius: metrics.rowRadius)
    }

    private var actions: some View {
        VStack(spacing: 11) {
            Button {
                openComposer()
            } label: {
                Label("Responder", systemImage: "paperplane")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(SRPrimaryButtonStyle())
            .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

            Button("Responder más tarde") { replyLater() }
                .buttonStyle(SRQuietButtonStyle())
                .frame(maxWidth: .infinity)

            Button("No requiere respuesta") { noReplyNeeded() }
                .buttonStyle(SRQuietButtonStyle())
                .frame(maxWidth: .infinity)
        }
    }

    private var replySubject: String {
        guard let subject = task.mailSubject, !subject.isEmpty else { return "Re:" }
        return subject.lowercased().hasPrefix("re:") ? subject : "Re: \(subject)"
    }

    // MARK: - Actions

    private func prepareDraft() async {
        isRewriting = true
        defer { isRewriting = false }
        let analysis = await SRIntelligenceService.shared.mailAnalysis(
            sender: task.mailSender,
            recipient: nil,
            subject: task.mailSubject,
            body: task.mailExcerpt ?? task.sharedExcerpt ?? task.detail,
            date: task.createdAt
        )
        let proposed = analysis.replyDraft ?? ""
        withAnimation(SRDesign.softAnimation) { draft = proposed }
        task.mailReplyDraft = proposed
        if task.detail.isEmpty { task.detail = analysis.summary }
        try? modelContext.save()
    }

    private func rewrite(as option: SRReplyStyle) {
        SRHaptics.light()
        style = option
        task.mailReplyStyle = option
        isRewriting = true
        Task {
            let rewritten = await SRIntelligenceService.shared.restyleReply(
                draft: draft,
                style: option,
                sender: task.mailSender,
                subject: task.mailSubject,
                originalExcerpt: task.mailExcerpt
            )
            withAnimation(SRDesign.softAnimation) { draft = rewritten }
            task.mailReplyDraft = rewritten
            try? modelContext.save()
            isRewriting = false
        }
    }

    private func openComposer() {
        if let style { BehaviorRecorder.recordReplyStyle(style, context: modelContext) }
        guard MailComposerView.canSendMail else {
            // No Mail account configured: hand the draft to whatever handles mailto.
            guard let url = MailFallback.url(
                for: MailComposerView.Draft(
                    recipients: task.mailSender.map { [$0] } ?? [],
                    subject: replySubject,
                    body: draft
                )
            ) else {
                errorMessage = "No hay una app de correo configurada en este iPhone."
                return
            }
            if !task.attachmentNames.isEmpty {
                errorMessage = "Sin Mail configurado no puedo adjuntar archivos: el borrador se abrirá sin ellos."
            }
            openURL(url)
            markAnswered()
            return
        }
        showsComposer = true
    }

    private func handleComposer(_ result: MFMailComposeResult) {
        switch result {
        case .sent:
            markAnswered()
            SRHaptics.success()
            showsWaitingOffer = true
        case .saved:
            errorMessage = nil
            markAnswered()
        case .failed:
            errorMessage = "Mail no pudo enviar el correo."
        case .cancelled:
            break
        @unknown default:
            break
        }
    }

    private func markAnswered() {
        task.mailWasAnswered = true
        task.updatedAt = Date()
        try? modelContext.save()
    }

    private func replyLater() {
        task.mailReplyDraft = draft
        SRTaskCommands.postpone(task, to: .after, context: modelContext)

        // A contextual moment beats a fixed hour for something like this.
        let profile = BehaviorRecorder.profile(context: modelContext)
        if let slot = ContextualReminderPlanner.proposeSlot(for: task, profile: profile) {
            ContextualReminderPlanner.apply(slot, to: task, context: modelContext)
        }
        SRHaptics.light()
        dismiss()
    }

    private func noReplyNeeded() {
        SRTaskCommands.complete(task, actualMinutes: 1, context: modelContext)
        SRHaptics.success()
        dismiss()
    }
}

/// After answering: offer to park the thread in "Esperando" instead of assuming it.
private struct WaitingOfferSheet: View {
    let task: TaskItem
    let person: String?

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.srMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                SRPresenceView(state: .waiting, size: 34)
                Spacer()
            }
            .padding(.top, 22)

            Text("¿Esperando respuesta?")
                .font(.title2.weight(.bold))
                .foregroundStyle(SRDesign.ink)

            Text(
                person.map { "Puedo dejar esto esperando a \($0) y avisarte si pasan los días sin novedad." }
                    ?? "Puedo dejar esto esperando y avisarte si pasan los días sin novedad."
            )
            .font(.body)
            .foregroundStyle(SRDesign.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)

            Button("Dejarlo esperando") {
                SRTaskCommands.markWaiting(task, for: task.mailSender ?? person, context: modelContext)
                SRHaptics.light()
                dismiss()
            }
            .buttonStyle(SRPrimaryButtonStyle())

            Button("Ya está cerrado") {
                SRTaskCommands.complete(task, context: modelContext)
                SRHaptics.success()
                dismiss()
            }
            .buttonStyle(SRQuietButtonStyle())
            .frame(maxWidth: .infinity)
            .padding(.bottom, 18)
        }
        .srContentWidth(metrics)
        .padding(.horizontal, metrics.pagePadding)
        .background(SRDesign.background.ignoresSafeArea())
    }
}
