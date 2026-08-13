import AppIntents
import Foundation
import SwiftData

/// Shared plumbing for SinRutina's App Intents.
///
/// Every intent opens the same database the app uses and goes through
/// `SRTaskCommands`, so Siri and Atajos can never bypass the app's rules.
@MainActor
enum SRIntentRuntime {
    /// One container per process, stored in the App Group so the app, Siri, the
    /// widget's intents and the share sheet all agree on the same data.
    static let container: ModelContainer = {
        let schema = Schema([TaskItem.self, BehaviorProfile.self, StudyMaterial.self, ReviewConcept.self])

        // An explicit URL inside the app group, after making sure the folder is
        // there. Handing SwiftData only the group identifier leaves the directory
        // to the system, and on a clean install it may not exist yet.
        if let url = SRShared.groupStoreURL() {
            let shared = ModelConfiguration(schema: schema, url: url)
            if let container = try? ModelContainer(for: schema, configurations: shared) {
                return container
            }
        }
        // If the App Group is unavailable, keep working with the app's own store.
        if let container = try? ModelContainer(for: schema) {
            return container
        }
        let memory = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        // Last resort: an in-memory store, so the app opens instead of crashing.
        return try! ModelContainer(for: schema, configurations: memory)
    }()

    static func context() -> ModelContext {
        ModelContext(container)
    }

    /// Prepares calendar knowledge so recommendations from Siri respect real free time.
    static func warmCalendar() async {
        CalendarService.shared.refreshAccessState()
        guard CalendarService.shared.access.canRead else { return }
        CalendarService.shared.loadCalendars()
        await CalendarService.shared.reloadUpcoming()
    }
}

enum SRIntentError: LocalizedError {
    case storeUnavailable
    case nothingToDo
    case noCurrentTask
    case calendarUnavailable
    case remindersUnavailable

    var errorDescription: String? {
        switch self {
        case .storeUnavailable:
            return "No pudimos abrir tus datos de SinRutina."
        case .nothingToDo:
            return "No hay nada urgente ahora mismo."
        case .noCurrentTask:
            return "No hay ninguna tarea en curso."
        case .calendarUnavailable:
            return "SinRutina todavía no tiene permiso para tus calendarios."
        case .remindersUnavailable:
            return "SinRutina todavía no tiene permiso para Recordatorios."
        }
    }
}

/// Fixed choices offered to Atajos, instead of free strings.
enum SRTaskStateAppEnum: String, AppEnum {
    case now
    case after
    case waiting
    case someday

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Estado")

    static let caseDisplayRepresentations: [SRTaskStateAppEnum: DisplayRepresentation] = [
        .now: "Ahora",
        .after: "Después",
        .waiting: "Esperando",
        .someday: "Algún día",
    ]

    var taskState: TaskState {
        switch self {
        case .now: return .now
        case .after: return .after
        case .waiting: return .waiting
        case .someday: return .someday
        }
    }
}

enum SRInsistenceAppEnum: String, AppEnum {
    case gentle
    case normal
    case important
    case unmissable

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Insistencia")

    static let caseDisplayRepresentations: [SRInsistenceAppEnum: DisplayRepresentation] = [
        .gentle: "Suave",
        .normal: "Normal",
        .important: "Importante",
        .unmissable: "No me dejes olvidarlo",
    ]

    var insistence: SRInsistence {
        switch self {
        case .gentle: return .gentle
        case .normal: return .normal
        case .important: return .important
        case .unmissable: return .unmissable
        }
    }
}

/// Registers a reply can be asked for from Atajos.
enum SRReplyStyleAppEnum: String, AppEnum {
    case brief
    case formal
    case warm
    case direct
    case human
    case concise

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Tono")

    static let caseDisplayRepresentations: [SRReplyStyleAppEnum: DisplayRepresentation] = [
        .brief: "Breve",
        .formal: "Formal",
        .warm: "Cálida",
        .direct: "Directa",
        .human: "Más humana",
        .concise: "Más concisa",
    ]

    var replyStyle: SRReplyStyle {
        switch self {
        case .brief: return .brief
        case .formal: return .formal
        case .warm: return .warm
        case .direct: return .direct
        case .human: return .human
        case .concise: return .concise
        }
    }
}

/// Where an answer may come from, offered to Atajos as fixed choices.
enum SRSourceModeAppEnum: String, AppEnum {
    case onlyMine
    case mixed
    case fromScratch

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "Fuentes")

    static let caseDisplayRepresentations: [SRSourceModeAppEnum: DisplayRepresentation] = [
        .onlyMine: "Solo mi material",
        .mixed: "Material + web",
        .fromScratch: "Buscar desde cero",
    ]

    var sourceMode: SRSourceMode {
        switch self {
        case .onlyMine: return .onlyMine
        case .mixed: return .mixed
        case .fromScratch: return .fromScratch
        }
    }
}
