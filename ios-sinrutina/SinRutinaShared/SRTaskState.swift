import Foundation

/// The small set of states SinRutina uses to reduce decision load.
/// Lives in the shared folder so extensions can propose a state without
/// touching the database.
nonisolated enum TaskState: String, CaseIterable, Codable, Identifiable, Sendable {
    case now = "Ahora"
    case after = "Después"
    case waiting = "Esperando"
    case someday = "Algún día"
    case completed = "Completada"

    var id: String { rawValue }

    var symbolName: String {
        switch self {
        case .now: return "checkmark.circle"
        case .after: return "calendar"
        case .waiting: return "hourglass"
        case .someday: return "leaf"
        case .completed: return "checkmark.seal"
        }
    }
}

/// How hard SinRutina should push a single task. Higher levels use stronger
/// system APIs (time sensitive notifications, then AlarmKit).
nonisolated enum SRInsistence: String, CaseIterable, Codable, Identifiable, Sendable {
    case gentle = "Suave"
    case normal = "Normal"
    case important = "Importante"
    case unmissable = "No me dejes olvidarlo"

    var id: String { rawValue }

    var explanation: String {
        switch self {
        case .gentle: return "Un aviso silencioso, sin sonido."
        case .normal: return "Una notificación normal."
        case .important: return "Notificación urgente que atraviesa el resumen."
        case .unmissable: return "Alarma real: suena aunque tengas silencio o concentración."
        }
    }

    var symbolName: String {
        switch self {
        case .gentle: return "bell.slash"
        case .normal: return "bell"
        case .important: return "bell.badge"
        case .unmissable: return "alarm.waves.left.and.right"
        }
    }

    /// Only the top level is allowed to break through Focus and silent mode.
    var usesAlarmKit: Bool { self == .unmissable }
}
