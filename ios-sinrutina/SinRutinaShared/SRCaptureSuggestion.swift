import Foundation

/// What the intelligence layer proposes after reading a piece of natural language.
/// It is only a proposal: nothing is written until the business rules accept it.
nonisolated struct SRCaptureSuggestion: Codable, Hashable, Sendable {
    var title: String
    var estimatedMinutes: Int
    var suggestedState: TaskState
    var availableFrom: Date?
    var dueDate: Date?
    var context: String?
    var nextStep: String?
    var waitingFor: String?
    var allowedApps: [String]
    var subtasks: [String]
    var summary: String?
    /// True when Apple Intelligence produced this, false when the local
    /// deterministic parser did.
    var usedOnDeviceModel: Bool

    init(
        title: String,
        estimatedMinutes: Int = 10,
        suggestedState: TaskState = .now,
        availableFrom: Date? = nil,
        dueDate: Date? = nil,
        context: String? = nil,
        nextStep: String? = nil,
        waitingFor: String? = nil,
        allowedApps: [String] = [],
        subtasks: [String] = [],
        summary: String? = nil,
        usedOnDeviceModel: Bool = false
    ) {
        self.title = title
        self.estimatedMinutes = max(1, min(estimatedMinutes, 480))
        self.suggestedState = suggestedState
        self.availableFrom = availableFrom
        self.dueDate = dueDate
        self.context = context
        self.nextStep = nextStep
        self.waitingFor = waitingFor
        self.allowedApps = allowedApps
        self.subtasks = subtasks
        self.summary = summary
        self.usedOnDeviceModel = usedOnDeviceModel
    }

    var isTooBig: Bool { subtasks.count >= 2 || estimatedMinutes >= 75 }

    var minutesLabel: String { "\(estimatedMinutes) min" }
}

/// Availability of Apple Intelligence, expressed in language the UI can show.
nonisolated enum SRIntelligenceAvailability: Equatable, Sendable {
    case available
    case notEnabled
    case deviceNotEligible
    case modelNotReady
    case requiresNewerOS

    var isAvailable: Bool { self == .available }

    var shortLabel: String {
        switch self {
        case .available: return "Activa en este iPhone"
        case .notEnabled: return "Apple Intelligence está desactivada"
        case .deviceNotEligible: return "Este iPhone no la admite"
        case .modelNotReady: return "El modelo aún se está preparando"
        case .requiresNewerOS: return "Necesita iOS 26"
        }
    }

    var explanation: String {
        switch self {
        case .available:
            return "Los textos se interpretan dentro del dispositivo."
        case .notEnabled:
            return "Puedes activarla en Ajustes de iOS. SinRutina sigue funcionando con su lector local."
        case .deviceNotEligible:
            return "SinRutina usa su lector local, que también funciona sin conexión."
        case .modelNotReady:
            return "Mientras se descarga usamos el lector local."
        case .requiresNewerOS:
            return "Con iOS 26 SinRutina entenderá frases más largas. Hasta entonces usa su lector local."
        }
    }
}
