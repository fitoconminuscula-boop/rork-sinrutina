import SwiftUI
import SwiftData

/// Recordatorios de Apple. SinRutina adopts them with a single link so the two
/// apps never tell you different things about the same asunto.
struct RemindersSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.srMetrics) private var metrics
    @Query private var tasks: [TaskItem]
    @State private var service = ReminderService.shared
    @State private var preferences = CalendarPreferences.shared
    @State private var importable: [SRImportableReminder] = []
    @State private var isLoading = false

    private var linkedIdentifiers: Set<String> {
        Set(tasks.compactMap(\.reminderIdentifier))
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Recordatorios")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("SinRutina no crea una segunda lista paralela: enlaza cada asunto con su recordatorio.")
                        .font(.body)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .padding(.top, 10)

                switch service.access {
                case .notDetermined, .writeOnly:
                    permissionCard
                case .denied, .restricted:
                    deniedCard
                case .granted:
                    grantedContent
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    // MARK: - Granted

    @ViewBuilder
    private var grantedContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            Toggle(isOn: Binding(
                get: { preferences.isRemindersLinkEnabled },
                set: { preferences.setRemindersLinkEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Mantener enlazado")
                        .font(.body.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                    Text("Al completar aquí, el recordatorio también se marca como hecho.")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
            }
            .tint(SRDesign.primary)
            .padding(16)
            .background(SRDesign.surface)
            .clipShape(.rect(cornerRadius: SRDesign.rowRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SRDesign.rowRadius, style: .continuous)
                    .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            HStack {
                SRSectionLabel(text: "Sin importar")
                Spacer()
                if isLoading {
                    ProgressView().controlSize(.small).tint(SRDesign.primary)
                }
            }
            .padding(.leading, 4)

            if pending.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "checkmark.circle")
                        .font(.system(size: 26, weight: .light))
                        .foregroundStyle(SRDesign.mint)
                    Text("Todo lo abierto ya está en SinRutina")
                        .font(.subheadline)
                        .foregroundStyle(SRDesign.secondaryInk)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
                .srCard()
            } else {
                ForEach(pending) { reminder in
                    ReminderRow(reminder: reminder, metrics: metrics) {
                        Task { await adopt(reminder) }
                    }
                }
            }
        }

        if !linked.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SRSectionLabel(text: "Ya enlazados")
                    .padding(.leading, 4)
                VStack(spacing: 0) {
                    ForEach(Array(linked.enumerated()), id: \.element.id) { index, reminder in
                        HStack(spacing: 11) {
                            Image(systemName: "link")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(SRDesign.mint)
                            Text(reminder.title)
                                .font(.subheadline)
                                .foregroundStyle(SRDesign.ink)
                                .lineLimit(1)
                            Spacer()
                            Text(reminder.listTitle)
                                .font(.caption2)
                                .foregroundStyle(SRDesign.secondaryInk)
                        }
                        .padding(.vertical, 13)
                        if index < linked.count - 1 {
                            Divider().overlay(SRDesign.divider)
                        }
                    }
                }
                .padding(.horizontal, 16)
                .background(SRDesign.surface)
                .clipShape(.rect(cornerRadius: SRDesign.cardRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SRDesign.cardRadius, style: .continuous)
                        .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
                }
            }
        }
    }

    private var pending: [SRImportableReminder] {
        importable.filter { !$0.isAlreadyLinked }
    }

    private var linked: [SRImportableReminder] {
        importable.filter(\.isAlreadyLinked)
    }

    // MARK: - Permission states

    private var permissionCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRIconBadge(symbol: "checklist", tint: SRDesign.lavender, size: 46)
            Text("Conectar con Recordatorios")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text("Podrás traer lo que ya tienes apuntado sin duplicarlo, y crear recordatorios desde aquí.")
                .font(.body)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button("Dar acceso") {
                Task {
                    _ = await service.requestAccess()
                    await load()
                    SRHaptics.light()
                }
            }
            .buttonStyle(SRPrimaryButtonStyle())
        }
        .padding(20)
        .srCard()
    }

    private var deniedCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            SRIconBadge(symbol: "hand.raised", tint: SRDesign.blush, size: 46)
            Text("Sin acceso a Recordatorios")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text("SinRutina funciona igual sin ello. Puedes cambiarlo cuando quieras en Ajustes de iOS.")
                .font(.body)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                Link("Abrir Ajustes de iOS", destination: url)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SRDesign.primary)
            }
        }
        .padding(20)
        .srCard()
    }

    // MARK: - Behaviour

    private func load() async {
        service.refreshAccessState()
        guard service.access.canRead else { return }
        service.loadLists()
        isLoading = true
        importable = await service.importableReminders(linkedIdentifiers: linkedIdentifiers)
        isLoading = false
    }

    private func adopt(_ reminder: SRImportableReminder) async {
        let text = [reminder.title, reminder.notes].compactMap { $0 }.joined(separator: ". ")
        let suggestion = await SRIntelligenceService.shared.suggestion(for: text)
        _ = SRTaskCommands.adopt(reminder: reminder, suggestion: suggestion, context: modelContext)
        SRHaptics.success()
        await load()
    }
}

private struct ReminderRow: View {
    let reminder: SRImportableReminder
    let metrics: SRMetrics
    let onImport: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            SRIconBadge(symbol: "circle", tint: SRDesign.lavender, size: 34)
            VStack(alignment: .leading, spacing: 3) {
                Text(reminder.title)
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 8) {
                    Text(reminder.listTitle)
                    if let dueDate = reminder.dueDate {
                        Text(dueDate, style: .date)
                    }
                }
                .font(.caption)
                .foregroundStyle(SRDesign.secondaryInk)
            }
            Spacer(minLength: 4)
            Button("Traer", action: onImport)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(SRDesign.primary)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(SRDesign.primarySoft.opacity(0.6))
                .clipShape(Capsule(style: .continuous))
                .buttonStyle(.plain)
        }
        .padding(metrics.rowPadding)
        .background(SRDesign.surface)
        .clipShape(.rect(cornerRadius: metrics.rowRadius))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.rowRadius, style: .continuous)
                .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
        }
    }
}
