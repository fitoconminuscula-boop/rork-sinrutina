import EventKit
import SwiftUI

/// "Calendarios usados por SinRutina": one switch per calendar, grouped by account
/// exactly as iOS shows them. Accounts are distinguished with a small colour dot
/// and the account name — never with loud colour blocks.
struct CalendarSettingsView: View {
    @Environment(\.srMetrics) private var metrics
    @State private var service = CalendarService.shared
    @State private var preferences = CalendarPreferences.shared
    @State private var showWriteTargetPicker = false

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Calendarios")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("SinRutina solo lee y escribe en los que actives aquí.")
                        .font(.body)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .padding(.top, 10)

                switch service.access {
                case .notDetermined:
                    permissionCard(
                        title: "Todavía sin permiso",
                        detail: "Para saber cuánto tiempo libre tienes de verdad, SinRutina necesita ver tus calendarios.",
                        actionTitle: "Dar acceso"
                    )
                case .denied, .restricted:
                    deniedCard
                case .writeOnly:
                    permissionCard(
                        title: "Solo puede escribir",
                        detail: "Con acceso completo SinRutina también puede evitar proponerte algo que no cabe antes de tu próxima reunión.",
                        actionTitle: "Pedir acceso completo"
                    )
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
        .task {
            service.refreshAccessState()
            if service.access.canRead || service.access.canWrite {
                service.loadCalendars()
                await service.reloadUpcoming()
            }
        }
    }

    // MARK: - Granted

    @ViewBuilder
    private var grantedContent: some View {
        if let window = service.freeWindow(), window.minutes > 0 {
            HStack(spacing: 12) {
                SRIconBadge(symbol: "clock.badge.checkmark", tint: SRDesign.mint, size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(window.minutes) min libres")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(SRDesign.ink)
                    Text(window.nextEventTitle.map { "Antes de \($0)" } ?? "Antes de tu próximo evento")
                        .font(.caption)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                Spacer(minLength: 0)
            }
            .padding(16)
            .srCard()
        }

        ForEach(service.calendarsByAccount, id: \.account) { group in
            VStack(alignment: .leading, spacing: 0) {
                SRSectionLabel(text: group.account)
                    .padding(.bottom, 10)
                    .padding(.leading, 4)

                VStack(spacing: 0) {
                    ForEach(Array(group.calendars.enumerated()), id: \.element.id) { index, calendar in
                        CalendarToggleRow(
                            calendar: calendar,
                            isOn: preferences.isSelected(calendar.id)
                        ) { isOn in
                            preferences.setSelected(isOn, for: calendar.id)
                            Task { await service.reloadUpcoming() }
                            SRHaptics.light()
                        }
                        if index < group.calendars.count - 1 {
                            Divider().overlay(SRDesign.divider).padding(.leading, 40)
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

        VStack(alignment: .leading, spacing: 0) {
            SRSectionLabel(text: "Crear eventos en")
                .padding(.bottom, 10)
                .padding(.leading, 4)

            Button {
                showWriteTargetPicker = true
            } label: {
                HStack(spacing: 12) {
                    if let info = service.calendarInfo(for: preferences.writeTargetIdentifier) {
                        Circle().fill(info.color).frame(width: 9, height: 9)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.title)
                                .font(.body.weight(.medium))
                                .foregroundStyle(SRDesign.ink)
                            Text(info.accountName)
                                .font(.caption)
                                .foregroundStyle(SRDesign.secondaryInk)
                        }
                    } else {
                        Text("Elige un calendario")
                            .font(.body)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .padding(16)
                .background(SRDesign.surface)
                .clipShape(.rect(cornerRadius: SRDesign.rowRadius))
                .overlay {
                    RoundedRectangle(cornerRadius: SRDesign.rowRadius, style: .continuous)
                        .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
                }
            }
            .buttonStyle(.plain)
            .confirmationDialog("¿Dónde creamos los eventos?", isPresented: $showWriteTargetPicker, titleVisibility: .visible) {
                ForEach(writableSelected) { calendar in
                    Button("\(calendar.title) · \(calendar.accountName)") {
                        preferences.setWriteTarget(calendar.id)
                    }
                }
                Button("Cancelar", role: .cancel) { }
            }
        }

        VStack(alignment: .leading, spacing: 12) {
            SRSectionLabel(text: "Borrado de eventos")
                .padding(.leading, 4)

            Toggle(isOn: Binding(
                get: { preferences.allowsAutomaticEventDeletion },
                set: { preferences.setAllowsAutomaticEventDeletion($0) }
            )) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Permitir borrado automático")
                        .font(.body.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                    Text("Desactivado, SinRutina siempre te pedirá confirmación antes de borrar un evento.")
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

        NavigationLink {
            CalendarAgendaView()
        } label: {
            HStack(spacing: 12) {
                SRIconBadge(symbol: "list.bullet.rectangle", tint: SRDesign.sky, size: 38)
                Text("Ver y gestionar eventos")
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            .padding(16)
            .background(SRDesign.surface)
            .clipShape(.rect(cornerRadius: SRDesign.rowRadius))
            .overlay {
                RoundedRectangle(cornerRadius: SRDesign.rowRadius, style: .continuous)
                    .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
            }
        }
        .buttonStyle(.plain)
    }

    private var writableSelected: [SRCalendarInfo] {
        service.calendars.filter { $0.isWritable && preferences.isSelected($0.id) }
    }

    // MARK: - Permission states

    private func permissionCard(title: String, detail: String, actionTitle: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            SRIconBadge(symbol: "calendar.badge.exclamationmark", tint: SRDesign.sky, size: 46)
            Text(title)
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text(detail)
                .font(.body)
                .foregroundStyle(SRDesign.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle) {
                Task {
                    _ = await service.requestAccess()
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
            Text("Sin acceso a los calendarios")
                .font(.title3.weight(.semibold))
                .foregroundStyle(SRDesign.ink)
            Text("SinRutina sigue funcionando igual: simplemente no sabrá cuánto tiempo libre tienes. Puedes cambiarlo en Ajustes de iOS.")
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
}

private struct CalendarToggleRow: View {
    let calendar: SRCalendarInfo
    let isOn: Bool
    let onChange: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: onChange)) {
            HStack(spacing: 11) {
                // The only colour cue, kept deliberately small.
                Circle()
                    .fill(calendar.color)
                    .frame(width: 9, height: 9)
                VStack(alignment: .leading, spacing: 2) {
                    Text(calendar.title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(SRDesign.ink)
                    if !calendar.isWritable {
                        Text("Solo lectura")
                            .font(.caption2)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                }
            }
        }
        .tint(SRDesign.primary)
        .padding(.vertical, 13)
    }
}
