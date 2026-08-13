import SwiftUI
import SwiftData

/// Choosing how hard SinRutina should push one task, and when.
struct InsistenceSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let task: TaskItem

    @State private var level: SRInsistence = .normal
    @State private var wantsReminder = false
    @State private var remindAt = Date().addingTimeInterval(1_800)
    @State private var scheduler = InsistenceScheduler.shared
    /// True when the person prefers SinRutina to pick the moment.
    @State private var wantsContextualTiming = false
    @State private var proposedSlot: ContextualReminderPlanner.Slot?

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("¿Cuánto insistimos?")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(SRDesign.ink)
                        Text(task.title)
                            .font(.subheadline)
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                    .padding(.top, 8)

                    VStack(spacing: 9) {
                        ForEach(SRInsistence.allCases) { option in
                            Button {
                                withAnimation(SRDesign.quickAnimation) { level = option }
                                if option != .gentle { wantsReminder = true }
                                SRHaptics.light()
                            } label: {
                                HStack(alignment: .top, spacing: 13) {
                                    Image(systemName: option.symbolName)
                                        .font(.system(size: 15, weight: .medium))
                                        .foregroundStyle(level == option ? SRDesign.primary : SRDesign.secondaryInk)
                                        .frame(width: 30, height: 30)
                                        .background((level == option ? SRDesign.primary : SRDesign.secondaryInk).opacity(0.12))
                                        .clipShape(Circle())
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(option.rawValue)
                                            .font(.body.weight(.medium))
                                            .foregroundStyle(SRDesign.ink)
                                        Text(option.explanation)
                                            .font(.caption)
                                            .foregroundStyle(SRDesign.secondaryInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    Spacer(minLength: 0)
                                    if level == option {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(SRDesign.primary)
                                    }
                                }
                                .padding(15)
                                .background(SRDesign.surface)
                                .clipShape(.rect(cornerRadius: SRDesign.rowRadius))
                                .overlay {
                                    RoundedRectangle(cornerRadius: SRDesign.rowRadius, style: .continuous)
                                        .stroke(
                                            level == option ? SRDesign.primary.opacity(0.5) : SRDesign.divider.opacity(0.42),
                                            lineWidth: level == option ? 1.2 : 0.7
                                        )
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    if level == .unmissable && !scheduler.isAlarmKitAvailable {
                        Text("Este iPhone no tiene alarmas de app (necesita iOS 26). Usaremos un aviso urgente que sí atraviesa el resumen programado.")
                            .font(.footnote)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(SRDesign.primarySoft.opacity(0.45))
                            .clipShape(.rect(cornerRadius: 14, style: .continuous))
                    }

                    Toggle("Avisarme", isOn: $wantsReminder)
                        .tint(SRDesign.primary)
                        .font(.body.weight(.medium))

                    if wantsReminder {
                        VStack(alignment: .leading, spacing: 12) {
                            Picker("Cuándo", selection: $wantsContextualTiming) {
                                Text("A una hora").tag(false)
                                Text("Cuando haya hueco").tag(true)
                            }
                            .pickerStyle(.segmented)

                            if wantsContextualTiming {
                                contextualBlock
                            } else {
                                DatePicker("Cuándo", selection: $remindAt)
                                    .tint(SRDesign.primary)
                            }
                        }
                        .transition(.opacity)
                    }

                    if scheduler.notificationAuthorization == .denied {
                        Text("Las notificaciones están desactivadas en Ajustes de iOS, así que no podremos avisarte.")
                            .font(.footnote)
                            .foregroundStyle(SRDesign.blush)
                    }

                    Button("Guardar") { save() }
                        .buttonStyle(SRPrimaryButtonStyle())
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
            level = task.insistence
            wantsContextualTiming = task.wantsContextualReminder
            if let existing = task.remindAt {
                remindAt = existing
                wantsReminder = true
            } else if let availableFrom = task.availableFrom {
                remindAt = availableFrom
            }
            await scheduler.refreshAuthorization()
            refreshSlot()
        }
        .onChange(of: wantsContextualTiming) { _, isContextual in
            guard isContextual else { return }
            refreshSlot()
        }
    }

    /// The moment SinRutina would choose, with the reason spelled out. It is a
    /// proposal: nothing is scheduled until "Guardar".
    private var contextualBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let proposedSlot {
                HStack(alignment: .top, spacing: 11) {
                    Image(systemName: proposedSlot.isDeadlineDriven ? "calendar.badge.exclamationmark" : "calendar.badge.clock")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(SRDesign.primary)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Te avisaría \(proposedSlot.label)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(SRDesign.ink)
                        Text(proposedSlot.reason)
                            .font(.caption)
                            .foregroundStyle(SRDesign.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Button {
                        refreshSlot(after: proposedSlot.start.addingTimeInterval(1_800))
                        SRHaptics.light()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(SRDesign.secondaryInk)
                    }
                    .buttonStyle(SRPressStyle())
                    .accessibilityLabel("Proponer otro momento")
                }
                .padding(13)
                .frame(maxWidth: .infinity, alignment: .leading)
                .srSurface(accent: SRDesign.primary)
            } else {
                Text("No encuentro un hueco claro todavía. Puedo avisarte a una hora concreta o volver a mirar cuando cambie tu calendario.")
                    .font(.footnote)
                    .foregroundStyle(SRDesign.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text("Miro tu calendario, la duración, la fecha límite y a qué horas sueles empezar de verdad.")
                .font(.caption2)
                .foregroundStyle(SRDesign.secondaryInk.opacity(0.9))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func refreshSlot(after date: Date = Date()) {
        let slot = ContextualReminderPlanner.proposeSlot(
            for: task,
            profile: BehaviorRecorder.profile(context: modelContext),
            now: date
        )
        withAnimation(SRDesign.quickAnimation) { proposedSlot = slot }
    }

    private func save() {
        if wantsReminder, wantsContextualTiming, let proposedSlot {
            ContextualReminderPlanner.apply(proposedSlot, to: task, context: modelContext)
            task.insistence = level
            try? modelContext.save()
        } else {
            task.wantsContextualReminder = false
            task.proposedSlotStart = nil
            SRTaskCommands.setInsistence(
                level,
                remindAt: wantsReminder ? remindAt : nil,
                for: task,
                context: modelContext
            )
        }
        SRHaptics.success()
        dismiss()
    }
}
