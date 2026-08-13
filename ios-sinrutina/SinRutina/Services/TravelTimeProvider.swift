import Foundation

/// The only thing SinRutina ever asks a maps service for: how long a trip takes.
///
/// It is deliberately a secondary source. The primary one is the person's own
/// history (`LearnedRouteStore`), and deciding *when to stop what you are doing*
/// belongs to `DepartureTimeEngine`. A provider can be added or removed without
/// touching either.
nonisolated protocol TravelTimeProvider: Sendable {
    var providerID: SRRouteProviderID { get }
    /// True when this service can actually be called on this build, with no key,
    /// account or billing required.
    var isConfigured: Bool { get }
    /// Whether it can answer for this way of moving.
    func supports(_ mode: SRTravelMode) -> Bool
    /// Whether its answer for this mode should be treated as reliable everywhere.
    /// Public transport coverage is regional, so it is not assumed.
    func isReliable(for mode: SRTravelMode) -> Bool
    /// Why it cannot be used, in plain Spanish, when `isConfigured` is false.
    var configurationNotice: String? { get }

    func estimate(for query: SRTravelQuery) async throws -> SRProviderEstimate
}

nonisolated enum SRTravelError: LocalizedError, Equatable {
    case notConfigured
    case modeUnsupported(SRTravelMode)
    case noRoute
    case network
    case rateLimited
    case originUnavailable
    case destinationUnknown

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "No hay ningún servicio de rutas disponible en esta versión."
        case .modeUnsupported(let mode):
            return "Apple Maps no calcula trayectos en \(mode.label.lowercased())."
        case .noRoute:
            return "No hay una ruta posible entre esos dos puntos."
        case .network:
            return "No pude consultar Apple Maps ahora mismo."
        case .rateLimited:
            return "Apple Maps está limitando las consultas ahora mismo."
        case .originUnavailable:
            return "Necesito tu ubicación actual para calcular el trayecto."
        case .destinationUnknown:
            return "Ese evento no tiene un lugar que pueda situar en el mapa."
        }
    }
}

/// The privacy boundary of this feature, written down in one place so it can be
/// audited and shown to the person.
///
/// The learning side never sends anything anywhere: it is all local. The only
/// thing that can leave the device is a route question to Apple Maps, and only
/// for a place with no history yet.
nonisolated enum SRTravelPrivacyGuard {
    /// Cleans an address before it can travel: first line, no notes, bounded.
    static func sanitiseAddress(_ raw: String) -> String? {
        let firstLine = raw
            .split(separator: "\n")
            .first
            .map(String.init) ?? raw
        var cleaned = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        // Conference links and meeting notes are not addresses.
        if cleaned.lowercased().hasPrefix("http") { return nil }
        if let range = cleaned.range(of: "http") {
            cleaned = String(cleaned[cleaned.startIndex..<range.lowerBound])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        cleaned = String(cleaned.prefix(140))
        return cleaned.count >= 3 ? cleaned : nil
    }

    /// What SinRutina keeps, and keeps only here.
    static let storedFields = [
        "Origen aproximado del recorrido",
        "Destino aproximado y su radio de llegada",
        "Duración real de cada viaje",
        "Día de la semana y franja horaria",
        "Minutos de preparación observados",
        "Nivel de confianza de cada recorrido",
    ]

    /// What is never written down, not even locally.
    static let neverStoredFields = [
        "El trazado GPS del viaje",
        "Por dónde pasas ni a qué velocidad",
        "Tu ubicación cuando no hay un recorrido que calcular",
        "Nada de esto sale de este iPhone",
    ]

    /// The exact list of what may reach Apple Maps, and only for a place with no
    /// history yet.
    static let outgoingFields = [
        "Tu ubicación aproximada de origen",
        "La dirección o coordenadas del destino",
        "El medio de transporte",
        "La hora de salida",
    ]

    static let withheldFields = [
        "El nombre del evento",
        "Las notas y los participantes",
        "El contenido de tu calendario",
        "Tu historial de recorridos aprendidos",
    ]
}
