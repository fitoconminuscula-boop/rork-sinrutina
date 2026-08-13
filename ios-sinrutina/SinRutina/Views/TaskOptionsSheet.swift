import SwiftUI
import SwiftData

/// Everything about the current task that is not "empezar".
///
/// It lives in a sheet on purpose: the main screen keeps one dominant action and
/// at most two alternatives, and the rest waits here until it is asked for.
nonisolated enum SRTaskOption: String, Identifiable, Sendable {
    case decline
    case smaller
    case insistence
    case postpone
    case study
    case mail

    var id: String { rawValue }
}

struct TaskOptionsSheet: View {
    let task: TaskItem
    let availableMinutes: Int?
    let nextEventTitle: String?
    /// Recorded by the caller and acted on after this sheet closes, so there is
    /// never more than one thing on screen.
    let onSelect: (SRTaskOption) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics
    @State private var showsDetails = false
    @State private var reason: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Más opciones")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text(task.title)
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)

                actions

                disclosure

                attachments
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 34)
        }
        .background(SRDesign.background.ignoresSafeArea())
    }

    // MARK: - Actions

    private var actions: some View {
        VStack(spacing: 0) {
            if task.isStudy {
                row(title: "Abrir el material", symbol: "book") { select(.study) }
                divider
            }
            if task.isMail {
                row(
                    title: task.mailWasAnswered ? "Ver el correo" : "Ver y responder",
                    symbol: "envelope"
                ) { select(.mail) }
                divider
            }
            row(title: "Hacerlo más pequeño", symbol: "scissors") { select(.smaller) }
            divider
            row(title: "No quiero hacer esto", symbol: "hand.raised") { select(.decline) }
            divider
            row(title: "Dejarlo para después", symbol: "calendar") { select(.postpone) }
            divider
            row(
                title: "Cómo quiero que insista",
                symbol: task.insistence.symbolName,
                detail: task.insistence.rawValue
            ) { select(.insistence) }
        }
        .padding(.horizontal, 16)
        .srCard(radius: metrics.cardRadius)
    }

    // MARK: - Progressive disclosure

    private var disclosure: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button {
                withAnimation(SRDesign.quickAnimation) { showsDetails.toggle() }
                SRHaptics.light()
            } label: {
                HStack(spacing: 8) {
                    Text(showsDetails ? "Ocultar detalles" : "Ver detalles")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(SRDesign.primary)
                    Image(systemName: showsDetails ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SRDesign.primary)
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(SRPressStyle())

            if showsDetails {
                VStack(alignment: .leading, spacing: 10) {
                    detailLine(label: "Duración estimada", value: "\(task.estimatedMinutes) min")
                    if let due = task.dueDate {
                        detailLine(
                            label: "Hora límite",
                            value: SRTaskOptionsFormatter.dateTime.string(from: due)
                        )
                    }
                    if let context = task.preferredContext, !context.isEmpty {
                        detailLine(label: "Contexto", value: context)
                    }
                    if !task.allowedApps.isEmpty {
                        detailLine(label: "Apps que ayudan", value: task.allowedApps.joined(separator: ", "))
                    }
                    if let notes = task.notes, !notes.isEmpty {
                        detailLine(label: "Notas", value: notes)
                    }
                    if !task.detail.isEmpty, task.detail != task.title {
                        detailLine(label: "Descripción", value: task.detail)
                    }
                    if let source = task.source, !source.isEmpty {
                        detailLine(label: "Origen", value: source)
                    }
                }
                .transition(.opacity)
            }

            Button {
                withAnimation(SRDesign.quickAnimation) {
                    reason = reason == nil
                        ? ReasonExplainer(
                            task: task,
                            availableMinutes: availableMinutes,
                            nextEventTitle: nextEventTitle
                        ).sentence
                        : nil
                }
            } label: {
                Text(reason == nil ? "¿Por qué esta?" : "Ocultar el motivo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SRDesign.primary)
            }
            .buttonStyle(SRPressStyle())

            if let reason {
                Text(reason)
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .srCard(radius: metrics.cardRadius)
    }

    // MARK: - Files

    private var attachments: some View {
        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Archivos")

            let names = task.attachmentNames
            if !names.isEmpty {
                SRAttachmentChips(names: names) { name in
                    var remaining = task.attachmentNames
                    remaining.removeAll { $0 == name }
                    task.attachmentNames = remaining
                    AttachmentStore.remove(name)
                    try? modelContext.save()
                }
            }

            SRAttachButton(label: names.isEmpty ? "Adjuntar algo" : "Añadir otro", isCompact: true) { added in
                var current = task.attachmentNames
                for name in added where !current.contains(name) {
                    current.append(name)
                }
                withAnimation(SRDesign.quickAnimation) {
                    task.attachmentNames = current
                }
                try? modelContext.save()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Pieces

    private var divider: some View {
        Divider().overlay(SRDesign.divider).padding(.leading, 38)
    }

    private func row(
        title: String,
        symbol: String,
        detail: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(SRDesign.primary)
                    .frame(width: 24)
                Text(title)
                    .font(.body)
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                if let detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.secondaryInk.opacity(0.7))
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(SRPressStyle())
    }

    private func detailLine(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(SRDesign.secondaryInk)
            Text(value)
                .font(.subheadline)
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func select(_ option: SRTaskOption) {
        SRHaptics.light()
        onSelect(option)
        dismiss()
    }
}

nonisolated enum SRTaskOptionsFormatter {
    static let dateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "es_ES")
        formatter.dateFormat = "d MMM · HH:mm"
        return formatter
    }()
}
