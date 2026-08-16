import EventKit
import SwiftUI

/// Reading and managing events from the authorised calendars. Creating is one tap;
/// deleting always asks, because that is the promise SinRutina makes.
struct CalendarAgendaView: View {
    @Environment(\.srMetrics) private var metrics
    @State private var service = CalendarService.shared
    @State private var preferences = CalendarPreferences.shared
    @State private var showComposer = false
    @State private var eventPendingDeletion: EKEvent?
    @State private var errorMessage: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("Calendario")
                        .font(.largeTitle.weight(.bold))
                        .foregroundStyle(SRDesign.ink)
                    Text("Tu día, claro y fácil de escanear.")
                        .font(.body)
                        .foregroundStyle(SRDesign.secondaryInk)
                }
                .padding(.top, 10)

                Button {
                    showComposer = true
                    SRHaptics.light()
                } label: {
                    Label("Crear evento", systemImage: "calendar.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(SRPrimaryButtonStyle())

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(SRDesign.blush)
                }

                if service.upcomingEvents.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(SRDesign.sky)
                        Text("Nada en las próximas horas")
                            .font(.headline)
                            .foregroundStyle(SRDesign.ink)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
                    .srCard()
                } else {
                    VStack(spacing: metrics.rowSpacing) {
                        ForEach(service.upcomingEvents, id: \.eventIdentifier) { event in
                            EventRow(event: event, metrics: metrics) {
                                eventPendingDeletion = event
                            }
                        }
                    }
                }
            }
            .srContentWidth(metrics)
            .padding(.horizontal, metrics.pagePadding)
            .padding(.bottom, 40)
        }
        .background(SRDesign.background.ignoresSafeArea())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showComposer) {
            EventComposerSheet()
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .confirmationDialog(
            "¿Borrar este evento?",
            isPresented: Binding(get: { eventPendingDeletion != nil }, set: { if !$0 { eventPendingDeletion = nil } }),
            titleVisibility: .visible,
            presenting: eventPendingDeletion
        ) { event in
            Button("Borrar del calendario", role: .destructive) {
                delete(event)
            }
            Button("Cancelar", role: .cancel) { eventPendingDeletion = nil }
        } message: { event in
            Text("Se borrará “\(event.title ?? "el evento")” de \(event.calendar?.title ?? "tu calendario"). Esto no se puede deshacer desde SinRutina.")
        }
        .task {
            await service.reloadUpcoming()
        }
    }

    private func delete(_ event: EKEvent) {
        guard let identifier = event.eventIdentifier else { return }
        do {
            // isAutomated: false — this came from a real tap plus a confirmation.
            try service.deleteEvent(withIdentifier: identifier, isAutomated: false)
            SRHaptics.success()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
        eventPendingDeletion = nil
    }
}

private struct EventRow: View {
    let event: EKEvent
    let metrics: SRMetrics
    let onDelete: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            VStack(spacing: 3) {
                Text(timeLabel)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(SRDesign.ink)
                Text(durationLabel)
                    .font(.caption2)
                    .foregroundStyle(SRDesign.secondaryInk)
            }
            .frame(width: 54, alignment: .leading)

            Circle()
                .fill(calendarColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                Text(event.title ?? "Evento")
                    .font(.body.weight(.medium))
                    .foregroundStyle(SRDesign.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(event.calendar?.title ?? "Calendario")
                    .font(.caption)
                    .foregroundStyle(SRDesign.secondaryInk)
            }

            Spacer(minLength: 4)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(SRDesign.secondaryInk)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Borrar \(event.title ?? "evento")")
        }
        .padding(metrics.rowPadding)
        .background(SRDesign.surface)
        .clipShape(.rect(cornerRadius: metrics.rowRadius))
        .overlay {
            RoundedRectangle(cornerRadius: metrics.rowRadius, style: .continuous)
                .stroke(SRDesign.divider.opacity(0.42), lineWidth: 0.7)
        }
    }

    private var calendarColor: Color {
        guard let cgColor = event.calendar?.cgColor else { return SRDesign.sky }
        return Color(uiColor: UIColor(cgColor: cgColor))
    }

    private var timeLabel: String {
        guard let start = event.startDate else { return "--:--" }
        return SRWidgetSnapshot.timeFormatter.string(from: start)
    }

    private var durationLabel: String {
        guard let start = event.startDate, let end = event.endDate else { return "" }
        let minutes = Int(end.timeIntervalSince(start) / 60)
        return minutes >= 60 ? "\(minutes / 60) h" : "\(minutes) min"
    }
}

/// Creating an event, always in an explicitly chosen calendar.
private struct EventComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var service = CalendarService.shared
    @State private var preferences = CalendarPreferences.shared
    @State private var title = ""
    @State private var start = Date().addingTimeInterval(3_600)
    @State private var minutes = 30
    @State private var selectedCalendarID: String?
    @State private var errorMessage: String?

    private var writableCalendars: [SRCalendarInfo] {
        service.calendars.filter { $0.isWritable && preferences.isSelected($0.id) }
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Nuevo evento")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(SRDesign.ink)
                        .padding(.top, 8)

                    TextField("Qué es", text: $title)
                        .font(.title3)
                        .padding(14)
                        .background(SRDesign.primarySoft.opacity(0.5))
                        .clipShape(.rect(cornerRadius: 16))

                    DatePicker("Cuándo", selection: $start)
                        .tint(SRDesign.primary)

                    Stepper("Duración: \(minutes) min", value: $minutes, in: 5...240, step: 5)
                        .tint(SRDesign.primary)

                    VStack(alignment: .leading, spacing: 10) {
                        SRSectionLabel(text: "Calendario")
                        if writableCalendars.isEmpty {
                            Text("Activa al menos un calendario donde se pueda escribir.")
                                .font(.subheadline)
                                .foregroundStyle(SRDesign.secondaryInk)
                        } else {
                            ForEach(writableCalendars) { calendar in
                                Button {
                                    selectedCalendarID = calendar.id
                                    SRHaptics.light()
                                } label: {
                                    HStack(spacing: 11) {
                                        Circle().fill(calendar.color).frame(width: 9, height: 9)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(calendar.title)
                                                .font(.body.weight(.medium))
                                                .foregroundStyle(SRDesign.ink)
                                            Text(calendar.accountName)
                                                .font(.caption)
                                                .foregroundStyle(SRDesign.secondaryInk)
                                        }
                                        Spacer()
                                        if effectiveCalendarID == calendar.id {
                                            Image(systemName: "checkmark")
                                                .font(.subheadline.weight(.bold))
                                                .foregroundStyle(SRDesign.primary)
                                        }
                                    }
                                    .padding(14)
                                    .background(SRDesign.surface)
                                    .clipShape(.rect(cornerRadius: SRDesign.rowRadius))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: SRDesign.rowRadius, style: .continuous)
                                            .stroke(
                                                effectiveCalendarID == calendar.id
                                                    ? SRDesign.primary.opacity(0.5)
                                                    : SRDesign.divider.opacity(0.42),
                                                lineWidth: effectiveCalendarID == calendar.id ? 1.2 : 0.7
                                            )
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(.footnote)
                            .foregroundStyle(SRDesign.blush)
                    }

                    Button("Crear evento") { create() }
                        .buttonStyle(SRPrimaryButtonStyle())
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || effectiveCalendarID == nil)
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
        .task {
            service.loadCalendars()
            selectedCalendarID = selectedCalendarID ?? preferences.writeTargetIdentifier
        }
    }

    private var effectiveCalendarID: String? {
        selectedCalendarID ?? writableCalendars.first?.id
    }

    private func create() {
        let draft = CalendarService.EventDraft(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            start: start,
            minutes: minutes,
            notes: nil,
            calendarIdentifier: effectiveCalendarID
        )
        do {
            _ = try service.createEvent(draft)
            SRHaptics.success()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
