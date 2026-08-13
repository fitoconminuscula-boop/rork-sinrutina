import Foundation

// MARK: - Time bands

/// The same route does not take the same time at 08:00 and at 12:00, so every
/// learned duration is filed under a band of the day as well as a weekday.
nonisolated enum SRTimeBand: String, Codable, CaseIterable, Sendable, Identifiable {
    case earlyMorning
    case morning
    case midday
    case afternoon
    case evening
    case night

    var id: String { rawValue }

    static func containing(_ date: Date, calendar: Calendar = .current) -> SRTimeBand {
        let hour = calendar.component(.hour, from: date)
        switch hour {
        case 5..<7: return .earlyMorning
        case 7..<11: return .morning
        case 11..<15: return .midday
        case 15..<19: return .afternoon
        case 19..<23: return .evening
        default: return .night
        }
    }

    var label: String {
        switch self {
        case .earlyMorning: return "Primera hora"
        case .morning: return "Mañana"
        case .midday: return "Mediodía"
        case .afternoon: return "Tarde"
        case .evening: return "Noche"
        case .night: return "Madrugada"
        }
    }

    var rangeLabel: String {
        switch self {
        case .earlyMorning: return "05:00–07:00"
        case .morning: return "07:00–11:00"
        case .midday: return "11:00–15:00"
        case .afternoon: return "15:00–19:00"
        case .evening: return "19:00–23:00"
        case .night: return "23:00–05:00"
        }
    }
}

nonisolated enum SRWeekday {
    /// Monday-first Spanish short names, indexed by `Calendar` weekday (1 = Sunday).
    static func label(_ weekday: Int) -> String {
        switch weekday {
        case 1: return "Domingo"
        case 2: return "Lunes"
        case 3: return "Martes"
        case 4: return "Miércoles"
        case 5: return "Jueves"
        case 6: return "Viernes"
        case 7: return "Sábado"
        default: return "Día"
        }
    }

    static func isWeekend(_ weekday: Int) -> Bool { weekday == 1 || weekday == 7 }
}

// MARK: - Statistics

/// Median and percentiles instead of averages: one exceptional trip must not move
/// the number SinRutina plans with.
nonisolated enum SRStats {
    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[middle - 1] + sorted[middle]) / 2
        }
        return sorted[middle]
    }

    /// Nearest-rank percentile. `p` is 0...1.
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let clamped = min(max(p, 0), 1)
        let rank = Int((clamped * Double(sorted.count - 1)).rounded())
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    /// Median absolute deviation: how much this route usually varies, robust to
    /// the one day the road was closed.
    static func medianAbsoluteDeviation(_ values: [Double]) -> Double? {
        guard let center = median(values), values.count >= 2 else { return nil }
        return median(values.map { abs($0 - center) })
    }
}

// MARK: - Confidence

/// How much SinRutina actually knows about a route. It is never rounded up: two
/// trips are two trips, and the interface says so.
nonisolated enum SRRouteConfidence: String, Codable, Sendable, CaseIterable {
    case none
    case low
    case medium
    case high

    static func forSamples(_ count: Int, variabilitySeconds: Double?, typicalSeconds: Double) -> SRRouteConfidence {
        guard count > 0 else { return .none }
        guard count >= 3 else { return .low }
        // A route that swings wildly is not "known" just because it was measured.
        let spread = (variabilitySeconds ?? 0) / max(typicalSeconds, 1)
        if count >= 6, spread <= 0.22 { return .high }
        if count >= 4, spread <= 0.35 { return .medium }
        return count >= 6 ? .medium : .low
    }

    var label: String {
        switch self {
        case .none: return "Sin datos"
        case .low: return "Pocos viajes"
        case .medium: return "Con bastante historial"
        case .high: return "Recorrido conocido"
        }
    }

    /// Thin data buys extra minutes, never a confident sentence.
    var cautionMinutes: Int {
        switch self {
        case .none: return 0
        case .low: return 8
        case .medium: return 4
        case .high: return 0
        }
    }

    var sortRank: Int {
        switch self {
        case .high: return 3
        case .medium: return 2
        case .low: return 1
        case .none: return 0
        }
    }
}

// MARK: - Learned destination

/// A place this person actually goes to. Nothing is inferred about what it is:
/// the name comes from the calendar or from the person, or it stays empty.
nonisolated struct LearnedDestination: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    /// Coarse coordinate: enough to recognise the place, not to describe a room.
    var point: SRTravelPoint
    /// How close counts as "arrived".
    var radiusMeters: Double
    var name: String?
    var lastVisitAt: Date?
    var visitCount: Int
    /// Extra minutes this place always costs at the end: parking, the walk in.
    var finalStretchSeconds: Double?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        point: SRTravelPoint,
        radiusMeters: Double = 180,
        name: String? = nil,
        lastVisitAt: Date? = nil,
        visitCount: Int = 0,
        finalStretchSeconds: Double? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.point = point.coarse
        self.radiusMeters = radiusMeters
        self.name = name
        self.lastVisitAt = lastVisitAt
        self.visitCount = visitCount
        self.finalStretchSeconds = finalStretchSeconds
        self.createdAt = createdAt
    }

    var displayName: String {
        guard let name, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            return "Lugar sin nombre"
        }
        return name
    }

    var hasName: Bool {
        guard let name else { return false }
        return !name.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

// MARK: - Trip samples

/// One measured trip, summarised. No GPS trace is kept: a duration, when it
/// happened, and how long the person took to actually get going.
nonisolated struct SRTripSample: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var seconds: Double
    /// Gap between deciding to leave and actually moving, when it was observed.
    var prepSeconds: Double?
    var modeRaw: String?
    var at: Date
    /// True when the person typed the duration instead of it being measured.
    var isManual: Bool

    init(
        id: UUID = UUID(),
        seconds: Double,
        prepSeconds: Double? = nil,
        modeRaw: String? = nil,
        at: Date = Date(),
        isManual: Bool = false
    ) {
        self.id = id
        self.seconds = max(60, min(seconds, 6 * 3_600))
        self.prepSeconds = prepSeconds.map { max(0, min($0, 60 * 60)) }
        self.modeRaw = modeRaw
        self.at = at
        self.isManual = isManual
    }
}

// MARK: - Learned route

/// What this person's own history says about getting from roughly here to a known
/// place, on this weekday, in this band of the day.
nonisolated struct LearnedRoute: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var origin: SRTravelPoint
    var destinationID: UUID
    var weekday: Int
    var bandRaw: String
    var modeRaw: String?
    /// Bounded on purpose: recent trips describe the present better than old ones.
    var samples: [SRTripSample]
    var lastUsedAt: Date

    static let sampleLimit = 14

    init(
        id: UUID = UUID(),
        origin: SRTravelPoint,
        destinationID: UUID,
        weekday: Int,
        band: SRTimeBand,
        modeRaw: String? = nil,
        samples: [SRTripSample] = [],
        lastUsedAt: Date = Date()
    ) {
        self.id = id
        self.origin = origin.coarse
        self.destinationID = destinationID
        self.weekday = weekday
        self.bandRaw = band.rawValue
        self.modeRaw = modeRaw
        self.samples = samples
        self.lastUsedAt = lastUsedAt
    }

    var band: SRTimeBand { SRTimeBand(rawValue: bandRaw) ?? .morning }
    var mode: SRTravelMode? { modeRaw.flatMap(SRTravelMode.init(rawValue:)) }
    var sampleCount: Int { samples.count }

    private var durations: [Double] { samples.map(\.seconds) }

    /// The number to talk about.
    var medianSeconds: Double? { SRStats.median(durations) }
    /// The number to plan with: being early is cheap, being late is not.
    var p80Seconds: Double? { SRStats.percentile(durations, 0.8) }
    var minSeconds: Double? { durations.min() }
    var maxSeconds: Double? { durations.max() }
    var variabilitySeconds: Double? { SRStats.medianAbsoluteDeviation(durations) }

    /// How long this person usually needs before actually moving on this route.
    var prepMedianSeconds: Double? {
        SRStats.median(samples.compactMap(\.prepSeconds))
    }

    var confidence: SRRouteConfidence {
        guard let median = medianSeconds else { return .none }
        return SRRouteConfidence.forSamples(
            samples.count,
            variabilitySeconds: variabilitySeconds,
            typicalSeconds: median
        )
    }

    var hasMeasuredSample: Bool { samples.contains { !$0.isManual } }

    mutating func add(_ sample: SRTripSample) {
        samples.append(sample)
        samples.sort { $0.at < $1.at }
        if samples.count > Self.sampleLimit {
            samples.removeFirst(samples.count - Self.sampleLimit)
        }
        lastUsedAt = Date()
        if modeRaw == nil { modeRaw = sample.modeRaw }
    }

    var contextLabel: String {
        "\(SRWeekday.label(weekday)) · \(band.rangeLabel)"
    }
}

// MARK: - Estimate

/// Where a duration came from. The order here is the order SinRutina trusts, and
/// nothing below `manual` exists: a number is never invented.
nonisolated enum SRTravelEstimateSource: String, Codable, CaseIterable, Sendable {
    case personalConfident
    case personalPartial
    case mapKit
    case manual
    case simulation

    var rank: Int {
        switch self {
        case .personalConfident: return 0
        case .personalPartial: return 1
        case .mapKit: return 2
        case .manual: return 3
        case .simulation: return 4
        }
    }

    var label: String {
        switch self {
        case .personalConfident: return "Tu historial"
        case .personalPartial: return "Tu historial parcial"
        case .mapKit: return "Apple Maps"
        case .manual: return "Tu estimación"
        case .simulation: return "Simulación"
        }
    }

    var symbolName: String {
        switch self {
        case .personalConfident: return "chart.line.uptrend.xyaxis"
        case .personalPartial: return "chart.bar"
        case .mapKit: return "map"
        case .manual: return "hand.raised"
        case .simulation: return "testtube.2"
        }
    }

    var isPersonal: Bool { self == .personalConfident || self == .personalPartial }
}

/// A duration SinRutina is willing to stand behind, with its provenance attached
/// so the interface can always say where it came from.
nonisolated struct TravelEstimate: Codable, Hashable, Sendable {
    var sourceRaw: String
    /// The typical duration: median when it comes from history.
    var typicalSeconds: Double
    var lowSeconds: Double
    /// The pessimistic end: P80 when it comes from history.
    var highSeconds: Double
    var sampleCount: Int
    var modeRaw: String?
    var confidenceRaw: String
    /// One honest sentence about the origin of the number.
    var detail: String
    var isSimulated: Bool
    var computedAt: Date

    init(
        source: SRTravelEstimateSource,
        typicalSeconds: Double,
        lowSeconds: Double? = nil,
        highSeconds: Double? = nil,
        sampleCount: Int = 0,
        mode: SRTravelMode? = nil,
        confidence: SRRouteConfidence = .none,
        detail: String,
        isSimulated: Bool = false,
        computedAt: Date = Date()
    ) {
        self.sourceRaw = source.rawValue
        self.typicalSeconds = max(60, typicalSeconds)
        self.lowSeconds = max(60, lowSeconds ?? typicalSeconds)
        self.highSeconds = max(highSeconds ?? typicalSeconds, lowSeconds ?? typicalSeconds)
        self.sampleCount = sampleCount
        self.modeRaw = mode?.rawValue
        self.confidenceRaw = confidence.rawValue
        self.detail = detail
        self.isSimulated = isSimulated || source == .simulation
        self.computedAt = computedAt
    }

    var source: SRTravelEstimateSource {
        SRTravelEstimateSource(rawValue: sourceRaw) ?? .manual
    }

    var mode: SRTravelMode? { modeRaw.flatMap(SRTravelMode.init(rawValue:)) }
    var confidence: SRRouteConfidence {
        SRRouteConfidence(rawValue: confidenceRaw) ?? .none
    }

    /// Planning uses the pessimistic end. Arriving early costs nothing.
    var planningSeconds: Double { max(typicalSeconds, highSeconds) }

    var typicalMinutes: Int { Int((typicalSeconds / 60).rounded()) }
    var lowMinutes: Int { Int((lowSeconds / 60).rounded()) }
    var highMinutes: Int { Int((highSeconds / 60).rounded()) }
    var planningMinutes: Int { Int((planningSeconds / 60).rounded()) }

    /// "41–48 min" when there is a real spread, "44 min" when there is not.
    var rangeLabel: String {
        guard highMinutes - lowMinutes >= 2 else { return "\(typicalMinutes) min" }
        return "\(lowMinutes)–\(highMinutes) min"
    }

    var isFromHistory: Bool { source.isPersonal }
}

// MARK: - Departure phases

/// The four moments this feature is allowed to speak, plus the honest fifth one
/// when leaving now already means arriving late.
nonisolated enum SRDeparturePhase: String, Codable, Sendable, CaseIterable {
    case notYet
    case prepare
    case getReady
    case leaveNow
    case late

    var label: String {
        switch self {
        case .notYet: return "Aún no"
        case .prepare: return "Preparación"
        case .getReady: return "Alistarse"
        case .leaveNow: return "Salir"
        case .late: return "Riesgo de atraso"
        }
    }

    var isActionable: Bool { self != .notYet }
}

// MARK: - Departure plan

/// The answer SinRutina owns: when to stop what you are doing, start getting
/// ready, and walk out. Every minute in it is traceable to something real.
nonisolated struct SRDeparturePlan: Codable, Hashable, Sendable, Identifiable {
    var eventID: String
    /// Stays on the device: it is never part of any request.
    var eventTitle: String
    var destinationLabel: String
    var destinationID: UUID?
    var eventStart: Date
    var modeRaw: String?

    /// Nil when SinRutina has nothing honest to say yet.
    var estimate: TravelEstimate?
    var prepMinutes: Int
    var arriveEarlyMinutes: Int
    /// Extra minutes added only because the data is thin, shown as such.
    var cautionMinutes: Int
    var finalStretchMinutes: Int

    /// Nil when there is no estimate: the interface asks instead of guessing.
    var leaveAt: Date?
    var startPrepAt: Date?
    var notice: String?
    var computedAt: Date

    var id: String { eventID }

    var mode: SRTravelMode? { modeRaw.flatMap(SRTravelMode.init(rawValue:)) }
    var hasEstimate: Bool { estimate != nil }
    var isSimulated: Bool { estimate?.isSimulated ?? false }

    /// Everything between "stop what you are doing" and the start of the event.
    var totalLeadMinutes: Int {
        guard let estimate else { return 0 }
        return estimate.planningMinutes + prepMinutes + cautionMinutes
            + finalStretchMinutes + arriveEarlyMinutes
    }

    func minutesUntilLeaving(at date: Date = Date()) -> Int? {
        guard let leaveAt else { return nil }
        return Int((leaveAt.timeIntervalSince(date) / 60).rounded())
    }

    func minutesUntilPrep(at date: Date = Date()) -> Int? {
        guard let startPrepAt else { return nil }
        return Int((startPrepAt.timeIntervalSince(date) / 60).rounded())
    }

    /// Minutes late if the person walked out right now. Positive means late.
    func lateMinutesIfLeavingNow(at date: Date = Date()) -> Int? {
        guard let estimate else { return nil }
        let arrival = date.addingTimeInterval(
            estimate.planningSeconds + Double(finalStretchMinutes) * 60
        )
        let minutes = Int((arrival.timeIntervalSince(eventStart) / 60).rounded())
        return minutes > 0 ? minutes : nil
    }

    func phase(at date: Date = Date()) -> SRDeparturePhase {
        guard let leaveAt, let startPrepAt else { return .notYet }
        if date >= leaveAt {
            return lateMinutesIfLeavingNow(at: date) != nil ? .late : .leaveNow
        }
        let minutesToLeave = leaveAt.timeIntervalSince(date) / 60
        if minutesToLeave <= 10 { return .getReady }
        if date >= startPrepAt { return .prepare }
        return .notYet
    }

    /// The breakdown, line by line, so the hour is never a black box.
    var reasons: [String] {
        guard let estimate else {
            return ["Todavía no tengo una duración fiable para este recorrido."]
        }
        var lines: [String] = []
        switch estimate.source {
        case .personalConfident:
            lines.append("Tus \(estimate.sampleCount) viajes a esta hora: \(estimate.rangeLabel), planifico con \(estimate.planningMinutes) min")
        case .personalPartial:
            lines.append("Solo \(estimate.sampleCount) viaje(s) registrados: \(estimate.rangeLabel), planifico con \(estimate.planningMinutes) min")
        case .mapKit:
            lines.append("Apple Maps: \(estimate.typicalMinutes) min (aún no tengo viajes tuyos aquí)")
        case .manual:
            lines.append("Tu estimación: \(estimate.typicalMinutes) min")
        case .simulation:
            lines.append("Simulación de recorrido: \(estimate.typicalMinutes) min")
        }
        if prepMinutes > 0 { lines.append("Prepararte y salir de donde estás: \(prepMinutes) min") }
        if finalStretchMinutes > 0 { lines.append("Aparcar y llegar a la puerta: \(finalStretchMinutes) min") }
        if cautionMinutes > 0 { lines.append("Margen por historial escaso: \(cautionMinutes) min") }
        if arriveEarlyMinutes > 0 { lines.append("Llegar \(arriveEarlyMinutes) min antes") }
        return lines
    }
}

// MARK: - Active trip

/// A trip in progress. It exists so a real duration can be measured, and it is
/// discarded the moment it stops making sense.
nonisolated struct SRActiveTrip: Codable, Hashable, Sendable, Identifiable {
    enum Origin: String, Codable, Sendable {
        /// The person pressed "Estoy saliendo".
        case declared
        /// SinRutina detected movement and the person confirmed it.
        case confirmedDetection
    }

    var id: UUID
    var eventID: String?
    var destinationID: UUID?
    var destinationLabel: String
    var destinationPoint: SRTravelPoint?
    var arrivalRadiusMeters: Double
    var modeRaw: String?
    /// When SinRutina said it was time to leave, if it did.
    var suggestedLeaveAt: Date?
    /// When the trip started counting.
    var startedAt: Date
    var startPoint: SRTravelPoint?
    /// When real movement was first seen, used to learn the transition time.
    var movementStartedAt: Date?
    var lastSeenAt: Date?
    /// First moment inside the arrival radius, used for the dwell check.
    var enteredRadiusAt: Date?
    var originRaw: String
    var isSimulated: Bool

    init(
        id: UUID = UUID(),
        eventID: String? = nil,
        destinationID: UUID? = nil,
        destinationLabel: String,
        destinationPoint: SRTravelPoint? = nil,
        arrivalRadiusMeters: Double = 180,
        mode: SRTravelMode? = nil,
        suggestedLeaveAt: Date? = nil,
        startedAt: Date = Date(),
        startPoint: SRTravelPoint? = nil,
        movementStartedAt: Date? = nil,
        origin: Origin = .declared,
        isSimulated: Bool = false
    ) {
        self.id = id
        self.eventID = eventID
        self.destinationID = destinationID
        self.destinationLabel = destinationLabel
        self.destinationPoint = destinationPoint
        self.arrivalRadiusMeters = arrivalRadiusMeters
        self.modeRaw = mode?.rawValue
        self.suggestedLeaveAt = suggestedLeaveAt
        self.startedAt = startedAt
        self.startPoint = startPoint
        self.movementStartedAt = movementStartedAt
        self.lastSeenAt = nil
        self.enteredRadiusAt = nil
        self.originRaw = origin.rawValue
        self.isSimulated = isSimulated
    }

    var mode: SRTravelMode? { modeRaw.flatMap(SRTravelMode.init(rawValue:)) }
    var tripOrigin: Origin { Origin(rawValue: originRaw) ?? .declared }

    /// The clock that will become the learned duration.
    var measuringSince: Date { movementStartedAt ?? startedAt }

    var elapsedMinutes: Int {
        max(0, Int(Date().timeIntervalSince(measuringSince) / 60))
    }

    /// The gap between "I have to leave" and actually moving.
    var transitionSeconds: Double? {
        guard let suggestedLeaveAt else { return nil }
        let reference = movementStartedAt ?? startedAt
        let value = reference.timeIntervalSince(suggestedLeaveAt)
        return value > 0 ? value : nil
    }

    /// A trip nobody closed is not evidence of anything.
    var isStale: Bool {
        Date().timeIntervalSince(startedAt) > 5 * 3_600
    }
}

/// A question SinRutina asks instead of assuming, when detection is not certain.
nonisolated struct SRTripQuestion: Codable, Hashable, Sendable, Identifiable {
    var id: UUID
    var destinationLabel: String
    var destinationID: UUID?
    var eventID: String?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        destinationLabel: String,
        destinationID: UUID? = nil,
        eventID: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.destinationLabel = destinationLabel
        self.destinationID = destinationID
        self.eventID = eventID
        self.createdAt = createdAt
    }

    var prompt: String { "¿Vas camino a \(destinationLabel)?" }
}

/// The result of a finished trip, handed to the store to be learned from.
nonisolated struct SRCompletedTrip: Sendable {
    var trip: SRActiveTrip
    var arrivedAt: Date
    var seconds: Double
    var isManualDuration: Bool
}

// MARK: - Transition memory

/// How long this person really needs between deciding to leave and moving. It is
/// observed, never assumed, and it only becomes a rule after being confirmed.
nonisolated struct SRTransitionSample: Codable, Hashable, Sendable {
    var seconds: Double
    var modeRaw: String?
    var at: Date
}

nonisolated enum SRTransitionMemory {
    private static let limit = 30

    static func record(seconds: Double, mode: SRTravelMode?) {
        guard seconds >= 0, seconds < 60 * 60 else { return }
        var all = samples()
        all.append(SRTransitionSample(seconds: seconds, modeRaw: mode?.rawValue, at: Date()))
        let trimmed = Array(all.suffix(limit))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.travelTransitionMemory)
    }

    static func samples() -> [SRTransitionSample] {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.travelTransitionMemory),
              let decoded = try? JSONDecoder().decode([SRTransitionSample].self, from: data) else {
            return []
        }
        return decoded
    }

    /// Requires real evidence before it is worth mentioning at all.
    static var typicalMinutes: Int? {
        let values = samples().suffix(10).map(\.seconds)
        guard values.count >= 3, let median = SRStats.median(values) else { return nil }
        let minutes = Int((median / 60).rounded())
        return minutes >= 3 ? min(minutes, 30) : nil
    }

    static var sampleCount: Int { samples().count }

    static func clear() {
        SRShared.defaults.removeObject(forKey: SRShared.Key.travelTransitionMemory)
    }
}

// MARK: - Plan records

/// What was already said about a trip, so a rounding difference never becomes a
/// notification and nothing is announced twice.
nonisolated struct SRDeparturePlanRecord: Codable, Hashable, Sendable {
    var eventID: String
    var leaveAt: Date?
    var travelMinutes: Int
    var modeRaw: String?
    var announcedPhases: [String]
    var notifiedChangeAt: Date?
    var updatedAt: Date

    func hasAnnounced(_ phase: SRDeparturePhase) -> Bool {
        announcedPhases.contains(phase.rawValue)
    }
}

nonisolated enum SRDeparturePlanStore {
    static func record(for eventID: String) -> SRDeparturePlanRecord? {
        all()[eventID]
    }

    static func save(_ record: SRDeparturePlanRecord) {
        var current = all()
        current[record.eventID] = record
        let cutoff = Date().addingTimeInterval(-12 * 3_600)
        current = current.filter { $0.value.updatedAt > cutoff }
        guard let data = try? JSONEncoder().encode(current) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.travelPlans)
    }

    static func remove(eventID: String) {
        var current = all()
        current.removeValue(forKey: eventID)
        guard let data = try? JSONEncoder().encode(current) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.travelPlans)
    }

    static func all() -> [String: SRDeparturePlanRecord] {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.travelPlans),
              let decoded = try? JSONDecoder().decode([String: SRDeparturePlanRecord].self, from: data) else {
            return [:]
        }
        return decoded
    }

    /// How many trips were re-announced today: used to widen the threshold rather
    /// than to talk more.
    static func recentChangeNotifications(within hours: Int = 24) -> Int {
        let cutoff = Date().addingTimeInterval(-Double(hours) * 3_600)
        return all().values.filter { ($0.notifiedChangeAt ?? .distantPast) > cutoff }.count
    }

    static func clear() {
        SRShared.defaults.removeObject(forKey: SRShared.Key.travelPlans)
    }
}
