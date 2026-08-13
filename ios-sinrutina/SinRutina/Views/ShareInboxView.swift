import SwiftUI
import SwiftData

/// What arrived from WhatsApp, Mail, Safari or Atajos and still needs one decision.
struct ShareInboxView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics
    @Environment(AppSession.self) private var session

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("Llegó desde otras apps")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(SRDesign.ink)
                        Text("Se leyó en este iPhone. Decide una sola cosa por cada uno.")
                            .font(.body)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 6)

                    if session.pendingInboxItems.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: "tray")
                                .font(.system(size: 28, weight: .light))
                                .foregroundStyle(SRDesign.sky)
                            Text("Nada pendiente de decidir")
                                .font(.headline)
                                .foregroundStyle(SRDesign.ink)
                            Text("Comparte un mensaje con SinRutina y aparecerá aquí.")
                                .font(.subheadline)
                                .foregroundStyle(SRDesign.secondaryInk)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 54)
                        .padding(.horizontal, 20)
                        .srCard()
                    } else {
                        ForEach(session.pendingInboxItems) { item in
                            InboxCard(item: item, metrics: metrics) { state in
                                apply(item, state: state)
                            } onDiscard: {
                                discard(item)
                            }
                            .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
                        }
                    }
                }
                .srContentWidth(metrics)
                .padding(.horizontal, metrics.pagePadding)
                .padding(.bottom, metrics.isTall ? 40 : 30)
            }
            .background(SRDesign.background.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
            }
        }
    }

    private func apply(_ item: SRInboxItem, state: TaskState) {
        SRTaskCommands.create(
            from: item.suggestion,
            source: item.sourceApp.map { "compartido·\($0)" } ?? "compartido",
            forcedState: state,
            sharedExcerpt: item.rawText,
            context: modelContext
        )
        remove(item)
        SRHaptics.success()
    }

    private func discard(_ item: SRInboxItem) {
        remove(item)
        SRHaptics.light()
    }

    private func remove(_ item: SRInboxItem) {
        SRShareInbox.remove(id: item.id)
        withAnimation(SRDesign.standardAnimation) {
            session.pendingInboxItems.removeAll { $0.id == item.id }
        }
        if session.pendingInboxItems.isEmpty { dismiss() }
    }
}

private struct InboxCard: View {
    let item: SRInboxItem
    let metrics: SRMetrics
    let onChoose: (TaskState) -> Void
    let onDiscard: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol)
                    .font(.system(size: 11, weight: .bold))
                Text(sourceLabel.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(0.7)
                Spacer(minLength: 0)
                Button(action: onDiscard) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(SRDesign.secondaryInk)
                        .frame(width: 30, height: 30)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Descartar")
            }
            .foregroundStyle(SRDesign.primary)
            .padding(.bottom, 10)

            Text(item.suggestion.title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let step = item.suggestion.nextStep, !step.isEmpty {
                Text(step)
                    .font(.subheadline)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .padding(.top, 5)
            }

            HStack(spacing: 8) {
                Label("\(item.suggestion.estimatedMinutes) min", systemImage: "clock")
                if let waitingFor = item.suggestion.waitingFor, !waitingFor.isEmpty {
                    Label(waitingFor, systemImage: "person")
                }
            }
            .font(.caption)
            .foregroundStyle(SRDesign.secondaryInk)
            .padding(.top, 10)

            if item.rawText.count > 60 {
                Text(item.rawText)
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .lineLimit(2)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(SRDesign.primarySoft.opacity(0.4))
                    .clipShape(.rect(cornerRadius: 12, style: .continuous))
                    .padding(.top, 12)
            }

            HStack(spacing: 8) {
                chipButton("Ahora", symbol: "bolt") { onChoose(.now) }
                chipButton("Después", symbol: "calendar") { onChoose(.after) }
                chipButton("Esperando", symbol: "hourglass") { onChoose(.waiting) }
                chipButton("Algún día", symbol: "leaf") { onChoose(.someday) }
            }
            .padding(.top, 16)
        }
        .padding(metrics.rowPadding + 2)
        .background(SRDesign.surface)
        .clipShape(.rect(cornerRadius: metrics.rowRadius + 3))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.rowRadius + 3, style: .continuous)
                .stroke(SRDesign.divider.opacity(0.45), lineWidth: 0.7)
        }
        .shadow(color: SRDesign.shadow, radius: 12, y: 5)
    }

    private func chipButton(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(SRDesign.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(SRDesign.primarySoft.opacity(0.55))
            .clipShape(.rect(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(SRPressStyle())
    }

    private var sourceLabel: String {
        item.sourceApp ?? (item.linkURL != nil ? "Enlace compartido" : "Compartido")
    }

    private var symbol: String {
        if item.attachmentName != nil { return "paperclip" }
        if item.linkURL != nil { return "link" }
        return "square.and.arrow.down"
    }
}
