import Foundation

// MARK: - Modes

/// How the person actually gets there. "Otro" exists because not every trip fits
/// a maps service: a lift from someone, a taxi, a scooter.
///
/// SinRutina learns the real duration whatever the mode is, so no official route
/// network needs to be known.
nonisolated enum SRTravelMode: String, Codable, CaseIterable, Sendable, Identifiable {
    case car
    case transit
    case walking
    case cycling
    case mixed
    case other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .car: return "Auto"
        case .transit: return "Transporte público"
        case .walking: return "Caminando"
        case .cycling: return "Bicicleta"
        case .mixed: return "Mixto"
        case .other: return "Otro"
        }
    }

    var shortLabel: String {
        switch self {
        case .car: return "Auto"
        case .transit: return "Transporte"
        case .walking: return "A pie"
        case .cycling: return "Bici"
        case .mixed: return "Mixto"
        case .other: return "Otro"
        }
    }

    var symbolName: String {
        switch self {
        case .car: return "car"
        case .transit: return "tram"
        case .walking: return "figure.walk"
        case .cycling: return "bicycle"
        case .mixed: return "arrow.triangle.swap"
        case .other: return "ellipsis.circle"
        }
    }

    /// True when parking and the walk to the door are part of the trip.
    var needsParking: Bool { self == .car }

    /// Modes a maps service could conceivably answer for. Everything else relies
    /// on the person's own history, which is the primary source anyway.
    var canAskMaps: Bool {
        switch self {
        case .car, .transit, .walking: return true
        case .cycling, .mixed, .other: return false
        }
    }

    /// Typical walking-ish speed in metres per second, used only to tell "moving"
    /// from "standing still", never to estimate a duration.
    static let movementThresholdMeters: Double = 300
}

// MARK: - Providers

/// The maps services SinRutina knows about.
///
/// Only Apple Maps is present: this version needs no key, no account and no
/// billing. Adding another one means adding a case plus a `TravelTimeProvider`
/// implementation — the engines never change.
nonisolated enum SRRouteProviderID: String, Codable, CaseIterable, Sendable, Identifiable {
    case apple

    var id: String { rawValue }

    var label: String {
        switch self {
        case .apple: return "Apple Maps"
        }
    }

    var detail: String {
        switch self {
        case .apple: return "MapKit, dentro del iPhone. Sin clave ni cuenta."
        }
    }
}

// MARK: - Geometry

/// A point on the map. Coordinates only: nothing about why you are going there.
nonisolated struct SRTravelPoint: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double

    /// Four decimals is roughly 11 metres — enough to recognise a place, coarse
    /// enough not to describe which desk you are sitting at.
    var coarse: SRTravelPoint {
        SRTravelPoint(
            latitude: (latitude * 10_000).rounded() / 10_000,
            longitude: (longitude * 10_000).rounded() / 10_000
        )
    }

    var queryValue: String {
        String(format: "%.4f,%.4f", latitude, longitude)
    }

    /// Great-circle distance in metres. Pure maths so the shared layer stays free
    /// of framework dependencies.
    func distance(to other: SRTravelPoint) -> Double {
        let earthRadius: Double = 6_371_000
        let lat1 = latitude * .pi / 180
        let lat2 = other.latitude * .pi / 180
        let deltaLat = (other.latitude - latitude) * .pi / 180
        let deltaLon = (other.longitude - longitude) * .pi / 180
        let a = sin(deltaLat / 2) * sin(deltaLat / 2)
            + cos(lat1) * cos(lat2) * sin(deltaLon / 2) * sin(deltaLon / 2)
        return 2 * earthRadius * atan2(sqrt(a), sqrt(1 - a))
    }
}

/// Where the trip ends: a resolved coordinate when we have one, a plain address
/// when we do not. Never an event title.
nonisolated enum SRTravelDestination: Codable, Hashable, Sendable {
    case coordinate(SRTravelPoint)
    case address(String)

    var addressValue: String? {
        if case let .address(value) = self { return value }
        return nil
    }

    var pointValue: SRTravelPoint? {
        if case let .coordinate(point) = self { return point }
        return nil
    }

    var cacheKey: String {
        switch self {
        case .coordinate(let point): return point.queryValue
        case .address(let value): return SRTravelKeys.normalise(value)
        }
    }
}

/// Everything a maps service is allowed to receive, and nothing else.
nonisolated struct SRTravelQuery: Codable, Hashable, Sendable {
    var origin: SRTravelPoint
    var destination: SRTravelDestination
    var mode: SRTravelMode
    var departAt: Date?

    init(
        origin: SRTravelPoint,
        destination: SRTravelDestination,
        mode: SRTravelMode,
        departAt: Date? = nil
    ) {
        self.origin = origin.coarse
        self.destination = destination
        self.mode = mode
        self.departAt = departAt
    }

    var routeKey: String {
        "\(origin.queryValue)|\(destination.cacheKey)|\(mode.rawValue)"
    }
}

// MARK: - Provider answer

/// What a maps service answered. It is one candidate among several, and never the
/// first choice: the person's own history outranks it.
nonisolated struct SRProviderEstimate: Codable, Hashable, Sendable {
    var providerRaw: String
    var mode: SRTravelMode
    var seconds: Double
    var meters: Double?
    var computedAt: Date

    init(
        provider: SRRouteProviderID,
        mode: SRTravelMode,
        seconds: Double,
        meters: Double? = nil,
        computedAt: Date = Date()
    ) {
        self.providerRaw = provider.rawValue
        self.mode = mode
        self.seconds = max(0, seconds)
        self.meters = meters
        self.computedAt = computedAt
    }

    var provider: SRRouteProviderID {
        SRRouteProviderID(rawValue: providerRaw) ?? .apple
    }

    var minutes: Int { Int((seconds / 60).rounded()) }
}

// MARK: - Arrival margin

/// How early this person wants to be there.
nonisolated enum SRArrivalMargin: Int, Codable, CaseIterable, Sendable, Identifiable {
    case onTime = 0
    case five = 5
    case ten = 10
    case fifteen = 15

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .onTime: return "Justo a la hora"
        case .five: return "5 min antes"
        case .ten: return "10 min antes"
        case .fifteen: return "15 min antes"
        }
    }

    var shortLabel: String {
        switch self {
        case .onTime: return "Justo"
        case .five: return "5 min"
        case .ten: return "10 min"
        case .fifteen: return "15 min"
        }
    }
}

// MARK: - Preferences

nonisolated struct SRTravelPreferencesData: Codable, Hashable, Sendable {
    /// The whole feature. Off means SinRutina never asks for your location.
    var isEnabled: Bool = false
    /// Whether finished trips are turned into learned routes at all.
    var learnsRoutes: Bool = true
    /// Whether SinRutina may learn while it is not open. Needs "Siempre".
    var learnsInBackground: Bool = false
    /// How early the person wants to arrive.
    var arriveEarlyMinutes: Int = 10
    /// Coat, keys, closing what you were doing.
    var prepMinutes: Int = 5
    /// Only true after the person confirmed the learned transition time.
    var usesLearnedPrep: Bool = false
    /// The confirmed number of minutes, kept separate from the observation.
    var learnedPrepMinutes: Int = 0
    /// Parking and the walk to the door, only when driving.
    var finalStretchMinutes: Int = 5
    var defaultModeRaw: String = SRTravelMode.car.rawValue
    /// destination key → mode raw value.
    var modeByDestination: [String: String] = [:]
    /// destination key → minutes the person typed for a place with no history.
    var manualMinutesByDestination: [String: Int] = [:]
    var remembersModePerDestination: Bool = true
    /// Whether departure notifications are allowed at all.
    var notifiesDeparture: Bool = true
    /// How big a change has to be before it is worth speaking again.
    var notifyThresholdMinutes: Int = 8
    /// Apple Maps as a fallback for routes with no history yet.
    var usesMapsFallback: Bool = true
    /// Development only, and always labelled as a simulation on screen.
    var isSimulationEnabled: Bool = false

    var defaultMode: SRTravelMode {
        SRTravelMode(rawValue: defaultModeRaw) ?? .car
    }

    var arrivalMargin: SRArrivalMargin? {
        SRArrivalMargin(rawValue: arriveEarlyMinutes)
    }
}

/// Local preferences for "Salir a tiempo". Nothing in here is decided by SinRutina
/// on its own except the numbers it learns and asks about first.
@Observable
final class SRTravelPreferences {
    static let shared = SRTravelPreferences()

    private(set) var data: SRTravelPreferencesData

    private init() {
        data = Self.load()
    }

    func update(_ transform: (inout SRTravelPreferencesData) -> Void) {
        var copy = data
        transform(&copy)
        copy.arriveEarlyMinutes = min(max(copy.arriveEarlyMinutes, 0), 60)
        copy.prepMinutes = min(max(copy.prepMinutes, 0), 45)
        copy.finalStretchMinutes = min(max(copy.finalStretchMinutes, 0), 45)
        copy.learnedPrepMinutes = min(max(copy.learnedPrepMinutes, 0), 30)
        copy.notifyThresholdMinutes = min(max(copy.notifyThresholdMinutes, 3), 20)
        // Background learning cannot be on while the feature itself is off.
        if !copy.isEnabled {
            copy.learnsInBackground = false
        }
        data = copy
        persist()
    }

    /// The prep minutes actually used: the manual value plus the learned
    /// transition time only if the person accepted it.
    var effectivePrepMinutes: Int {
        data.prepMinutes + (data.usesLearnedPrep ? data.learnedPrepMinutes : 0)
    }

    /// The usual way of getting to a place, when there is one.
    func mode(forDestination key: String) -> SRTravelMode? {
        guard data.remembersModePerDestination else { return nil }
        guard let raw = data.modeByDestination[SRTravelKeys.normalise(key)] else { return nil }
        return SRTravelMode(rawValue: raw)
    }

    func rememberMode(_ mode: SRTravelMode, forDestination key: String) {
        let normalised = SRTravelKeys.normalise(key)
        guard !normalised.isEmpty else { return }
        update { $0.modeByDestination[normalised] = mode.rawValue }
    }

    func forgetMode(forDestination key: String) {
        update { $0.modeByDestination.removeValue(forKey: SRTravelKeys.normalise(key)) }
    }

    /// A duration the person typed for a place SinRutina knows nothing about.
    func manualMinutes(forDestination key: String) -> Int? {
        data.manualMinutesByDestination[SRTravelKeys.normalise(key)]
    }

    func rememberManualMinutes(_ minutes: Int, forDestination key: String) {
        let normalised = SRTravelKeys.normalise(key)
        guard !normalised.isEmpty, minutes > 0 else { return }
        update { $0.manualMinutesByDestination[normalised] = min(minutes, 300) }
    }

    func forgetManualMinutes(forDestination key: String) {
        update { $0.manualMinutesByDestination.removeValue(forKey: SRTravelKeys.normalise(key)) }
    }

    /// Remembered places, for the settings screen.
    var rememberedDestinations: [(key: String, mode: SRTravelMode)] {
        data.modeByDestination
            .compactMap { entry in
                guard let mode = SRTravelMode(rawValue: entry.value) else { return nil }
                return (key: entry.key, mode: mode)
            }
            .sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }

    private func persist() {
        guard let encoded = try? JSONEncoder().encode(data) else { return }
        SRShared.defaults.set(encoded, forKey: SRShared.Key.travelPreferences)
    }

    private static func load() -> SRTravelPreferencesData {
        guard let stored = SRShared.defaults.data(forKey: SRShared.Key.travelPreferences),
              let decoded = try? JSONDecoder().decode(SRTravelPreferencesData.self, from: stored) else {
            return SRTravelPreferencesData()
        }
        return decoded
    }
}

// MARK: - Keys

nonisolated enum SRTravelKeys {
    /// Turns "Universidad — Facultad de Letras\nAula 3" into a stable, short key.
    static func normalise(_ value: String) -> String {
        let firstLine = value
            .split(separator: "\n")
            .first
            .map(String.init) ?? value
        let folded = firstLine
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "es_ES"))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let collapsed = folded
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return String(collapsed.prefix(80))
    }
}
