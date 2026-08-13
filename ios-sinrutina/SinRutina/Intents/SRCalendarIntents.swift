import AppIntents
import Foundation
import SwiftData

/// "Crear evento" — always in a calendar the person authorised, never guessed.
struct SRCreateEventIntent: AppIntent {
    static let title: LocalizedStringResource = "Crear evento en SinRutina"
    static let description = IntentDescription(
        "Crea un evento en uno de los calendarios que has activado en SinRutina.",
        categoryName: "Calendario"
    )

    @Parameter(title: "Título", requestValueDialog: "¿Cómo se llama el evento?")
    var title: String

    @Parameter(title: "Cuándo")
    var startDate: Date

    @Parameter(title: "Duración en minutos", default: 30, controlStyle: .field, inclusiveRange: (5, 480))
    var minutes: Int

    @Parameter(title: "Notas")
    var notes: String?

    static var parameterSummary: some ParameterSummary {
        Summary("Crear \(\.$title) el \(\.$startDate) en SinRutina") {
            \.$minutes
            \.$notes
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = CalendarService.shared
        service.refreshAccessState()
        if service.access == .notDetermined {
            _ = await service.requestAccess()
        }
        guard service.access.canWrite else { throw SRIntentError.calendarUnavailable }
        service.loadCalendars()

        let draft = CalendarService.EventDraft(
            title: title,
            start: startDate,
            minutes: minutes,
            notes: notes,
            calendarIdentifier: nil
        )
        _ = try service.createEvent(draft)
        let calendarName = service.calendarInfo(for: CalendarPreferences.shared.writeTargetIdentifier)?.title ?? "tu calendario"
        return .result(dialog: IntentDialog("Creado en \(calendarName): \(title)."))
    }
}

/// "Crear recordatorio" — writes into Apple Recordatorios, the owner of that data.
struct SRCreateReminderIntent: AppIntent {
    static let title: LocalizedStringResource = "Crear recordatorio en SinRutina"
    static let description = IntentDescription(
        "Crea un recordatorio en la app Recordatorios de Apple y lo enlaza con SinRutina.",
        categoryName: "Recordatorios"
    )

    @Parameter(title: "Qué recordar", requestValueDialog: "¿Qué quieres recordar?")
    var text: String

    @Parameter(title: "Cuándo")
    var dueDate: Date?

    @Parameter(title: "Guardar también en SinRutina", default: true)
    var alsoInSinRutina: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Recordar \(\.$text) en SinRutina") {
            \.$dueDate
            \.$alsoInSinRutina
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let service = ReminderService.shared
        service.refreshAccessState()
        if service.access == .notDetermined {
            _ = await service.requestAccess()
        }
        guard service.access.canWrite else { throw SRIntentError.remindersUnavailable }
        service.loadLists()

        let suggestion = await SRIntelligenceService.shared.suggestion(for: text)
        let identifier = try service.createReminder(
            title: suggestion.title,
            dueDate: dueDate ?? suggestion.availableFrom,
            notes: suggestion.nextStep
        )

        guard alsoInSinRutina else {
            return .result(dialog: IntentDialog("Recordatorio creado: \(suggestion.title)."))
        }
        let context = SRIntentRuntime.context()
        let task = SRTaskCommands.create(from: suggestion, source: "recordatorio", context: context)
        task.reminderIdentifier = identifier
        try? context.save()
        return .result(dialog: IntentDialog("Recordatorio creado y enlazado: \(task.title)."))
    }
}

/// Deleting an event is intentionally not exposed as a silent automation.
/// This intent always sends the person back into SinRutina to confirm, which is
/// the rule the app promises: nothing gets deleted behind your back.
struct SRReviewEventDeletionIntent: AppIntent {
    static let title: LocalizedStringResource = "Revisar un evento para borrar"
    static let description = IntentDescription(
        "Abre SinRutina para que confirmes a mano el borrado de un evento. SinRutina nunca borra eventos sin confirmación, salvo que actives esa regla en Ajustes.",
        categoryName: "Calendario"
    )
    static let openAppWhenRun: Bool = true

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        SRCommandBus.send(SRPendingCommand(kind: .whatNow))
        return .result(dialog: IntentDialog("Te llevo a SinRutina para confirmarlo."))
    }
}
