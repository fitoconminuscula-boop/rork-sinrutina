import Foundation
import Observation

/// The local memory of this feature: which places this person goes to, and how
/// long the trips there actually took.
///
/// Everything lives on this device, in the app group, in summarised form. No GPS
/// trace is ever written down — only a duration, a weekday, a band of the day, and
/// a coarse coordinate.
@MainActor
@Observable
final class LearnedRouteStore {
    static let shared = LearnedRouteStore()

    private(set) var destinations: [LearnedDestination] = []
    private(set) var routes: [LearnedRoute] = []

    /// Bounded on purpose: this is a memory, not a location history.
    private static let destinationLimit = 60
    private static let routeLimit = 400

    private struct Archive: Codable {
        var destinations: [LearnedDestination]
        var routes: [LearnedRoute]
    }

    private init() {
        load()
    }

    // MARK: - Reading

    func destination(id: UUID) -> LearnedDestination? {
        destinations.first { $0.id == id }
    }

    /// The known place a coordinate falls into, if any.
    func destination(near point: SRTravelPoint) -> LearnedDestination? {
        destinations
            .map { (destination: $0, distance: $0.point.distance(to: point)) }
            .filter { $0.distance <= max($0.destination.radiusMeters, 120) }
            .min { $0.distance < $1.distance }?
            .destination
    }

    func routes(for destinationID: UUID) -> [LearnedRoute] {
        routes
            .filter { $0.destinationID == destinationID && $0.sampleCount > 0 }
            .sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    func sampleCount(for destinationID: UUID) -> Int {
        routes(for: destinationID).reduce(0) { $0 + $1.sampleCount }
    }

    /// Places worth showing, most recently useful first.
    var knownDestinations: [LearnedDestination] {
        destinations.sorted { lhs, rhs in
            (lhs.lastVisitAt ?? lhs.createdAt) > (rhs.lastVisitAt ?? rhs.createdAt)
        }
    }

    var totalSampleCount: Int {
        routes.reduce(0) { $0 + $1.sampleCount }
    }

    var hasAnyLearning: Bool { totalSampleCount > 0 }

    // MARK: - Destinations

    /// Finds the place this coordinate belongs to, or starts remembering it.
    ///
    /// A name is only stored when something real provided one: the calendar entry
    /// or the person. SinRutina never guesses what a place is.
    func destination(
        for point: SRTravelPoint,
        name: String?,
        createIfMissing: Bool = true
    ) -> LearnedDestination? {
        if let existing = destination(near: point) {
            if !existing.hasName, let name, !name.isEmpty {
                var updated = existing
                updated.name = String(name.prefix(80))
                replace(updated)
            }
            return existing
        }
        guard createIfMissing else { return nil }
        var created = LearnedDestination(point: point, name: name.map { String($0.prefix(80)) })
        created.visitCount = 0
        destinations.append(created)
        trimDestinations()
        persist()
        return destinations.first { $0.id == created.id } ?? created
    }

    func rename(_ destination: LearnedDestination, to name: String?) {
        var updated = destination
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = (trimmed?.isEmpty ?? true) ? nil : String(trimmed!.prefix(80))
        replace(updated)
        persist()
    }

    func setFinalStretch(minutes: Int?, for destination: LearnedDestination) {
        var updated = destination
        updated.finalStretchSeconds = minutes.map { Double(min(max($0, 0), 45)) * 60 }
        replace(updated)
        persist()
    }

    /// Forgets a place and every trip measured to it.
    func remove(_ destination: LearnedDestination) {
        destinations.removeAll { $0.id == destination.id }
        routes.removeAll { $0.destinationID == destination.id }
        persist()
    }

    /// Forgets every learned route for a place but keeps the place itself.
    func forgetRoutes(for destination: LearnedDestination) {
        routes.removeAll { $0.destinationID == destination.id }
        persist()
    }

    /// Erases the whole travel memory. Offered in Ajustes, and it really erases.
    func removeAll() {
        destinations = []
        routes = []
        SRShared.defaults.removeObject(forKey: SRShared.Key.travelLearnedArchive)
        SRTransitionMemory.clear()
    }

    // MARK: - Learning

    /// Writes down a finished trip. Only measured or explicitly typed durations
    /// arrive here, and simulated ones never do.
    func record(
        origin: SRTravelPoint?,
        destinationID: UUID,
        mode: SRTravelMode?,
        seconds: Double,
        prepSeconds: Double?,
        at date: Date = Date(),
        isManual: Bool = false
    ) {
        guard SRTravelPreferences.shared.data.learnsRoutes else { return }
        guard seconds >= 120 else { return }
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let band = SRTimeBand.containing(date, calendar: calendar)
        let sample = SRTripSample(
            seconds: seconds,
            prepSeconds: prepSeconds,
            modeRaw: mode?.rawValue,
            at: date,
            isManual: isManual
        )
        let originPoint = (origin ?? destination(id: destinationID)?.point ?? SRTravelPoint(latitude: 0, longitude: 0)).coarse

        if let index = routes.firstIndex(where: { route in
            route.destinationID == destinationID
                && route.weekday == weekday
                && route.bandRaw == band.rawValue
                && route.modeRaw == mode?.rawValue
                && route.origin.distance(to: originPoint) <= 400
        }) {
            routes[index].add(sample)
        } else {
            var route = LearnedRoute(
                origin: originPoint,
                destinationID: destinationID,
                weekday: weekday,
                band: band,
                modeRaw: mode?.rawValue
            )
            route.add(sample)
            routes.append(route)
            trimRoutes()
        }

        if var place = destination(id: destinationID) {
            place.visitCount += 1
            place.lastVisitAt = date
            replace(place)
        }
        persist()
    }

    // MARK: - Estimating

    /// What this person's history says about being here, now, heading there.
    ///
    /// Matching widens in three steps, and each step is reported honestly instead
    /// of being presented as the same knowledge:
    /// 1. same weekday and band of the day;
    /// 2. same band any day, or same weekday any band;
    /// 3. any trip to that place.
    func estimate(
        origin: SRTravelPoint?,
        destinationID: UUID,
        mode: SRTravelMode?,
        departingAt date: Date
    ) -> TravelEstimate? {
        let calendar = Calendar.current
        let weekday = calendar.component(.weekday, from: date)
        let band = SRTimeBand.containing(date, calendar: calendar)
        let candidates = routes.filter { $0.destinationID == destinationID && $0.sampleCount > 0 }
        guard !candidates.isEmpty else { return nil }

        let sameMode = { (route: LearnedRoute) in
            mode == nil || route.modeRaw == nil || route.modeRaw == mode?.rawValue
        }
        let nearOrigin = { (route: LearnedRoute) in
            guard let origin else { return true }
            return route.origin.distance(to: origin) <= 1_200
        }

        let exact = candidates.filter {
            $0.weekday == weekday && $0.band == band && sameMode($0) && nearOrigin($0)
        }
        if let estimate = estimate(from: exact, mode: mode, precision: .exact) {
            return estimate
        }

        let nearby = candidates.filter {
            ($0.band == band || $0.weekday == weekday) && sameMode($0) && nearOrigin($0)
        }
        if let estimate = estimate(from: nearby, mode: mode, precision: .nearby) {
            return estimate
        }

        return estimate(from: candidates.filter(sameMode), mode: mode, precision: .loose)
            ?? estimate(from: candidates, mode: mode, precision: .loose)
    }

    private enum MatchPrecision {
        case exact
        case nearby
        case loose

        var detailPrefix: String {
            switch self {
            case .exact: return "a esta hora y este día"
            case .nearby: return "en una franja parecida"
            case .loose: return "en otros momentos"
            }
        }

        /// Looser matches never claim the top confidence level.
        func cap(_ confidence: SRRouteConfidence) -> SRRouteConfidence {
            switch self {
            case .exact: return confidence
            case .nearby: return confidence == .high ? .medium : confidence
            case .loose: return confidence == .none ? .none : .low
            }
        }
    }

    private func estimate(
        from routes: [LearnedRoute],
        mode: SRTravelMode?,
        precision: MatchPrecision
    ) -> TravelEstimate? {
        let samples = routes.flatMap(\.samples)
        guard !samples.isEmpty else { return nil }
        let durations = samples.map(\.seconds)
        guard let median = SRStats.median(durations) else { return nil }
        let p80 = SRStats.percentile(durations, 0.8) ?? median
        let p20 = SRStats.percentile(durations, 0.2) ?? median
        let variability = SRStats.medianAbsoluteDeviation(durations)
        let rawConfidence = SRRouteConfidence.forSamples(
            samples.count,
            variabilitySeconds: variability,
            typicalSeconds: median
        )
        let confidence = precision.cap(rawConfidence)
        // "Confident" is reserved for real evidence at the right time of day.
        let source: SRTravelEstimateSource = (confidence == .high || confidence == .medium)
            ? .personalConfident
            : .personalPartial

        let count = samples.count
        let detail: String
        if source == .personalConfident {
            detail = "\(count) viajes tuyos \(precision.detailPrefix)."
        } else if count == 1 {
            detail = "Solo 1 viaje registrado \(precision.detailPrefix)."
        } else {
            detail = "Solo \(count) viajes registrados \(precision.detailPrefix)."
        }

        return TravelEstimate(
            source: source,
            typicalSeconds: median,
            lowSeconds: min(p20, median),
            highSeconds: max(p80, median),
            sampleCount: count,
            mode: mode ?? routes.first?.mode,
            confidence: confidence,
            detail: detail
        )
    }

    /// The extra minutes a place always costs at the end, if it learned any.
    func finalStretchMinutes(for destinationID: UUID?) -> Int? {
        guard let destinationID,
              let seconds = destination(id: destinationID)?.finalStretchSeconds else {
            return nil
        }
        return Int((seconds / 60).rounded())
    }

    /// The transition time observed on the way to a specific place.
    func prepMinutes(for destinationID: UUID) -> Int? {
        let values = routes(for: destinationID).compactMap(\.prepMedianSeconds)
        guard let median = SRStats.median(values) else { return nil }
        return Int((median / 60).rounded())
    }

    // MARK: - Storage

    private func replace(_ destination: LearnedDestination) {
        guard let index = destinations.firstIndex(where: { $0.id == destination.id }) else { return }
        destinations[index] = destination
    }

    private func trimDestinations() {
        guard destinations.count > Self.destinationLimit else { return }
        let sorted = destinations.sorted { lhs, rhs in
            (lhs.lastVisitAt ?? lhs.createdAt) > (rhs.lastVisitAt ?? rhs.createdAt)
        }
        let kept = Array(sorted.prefix(Self.destinationLimit))
        let keptIDs = Set(kept.map(\.id))
        destinations = kept
        routes.removeAll { !keptIDs.contains($0.destinationID) }
    }

    private func trimRoutes() {
        guard routes.count > Self.routeLimit else { return }
        routes.sort { $0.lastUsedAt > $1.lastUsedAt }
        routes = Array(routes.prefix(Self.routeLimit))
    }

    private func persist() {
        let archive = Archive(destinations: destinations, routes: routes)
        guard let data = try? JSONEncoder().encode(archive) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.travelLearnedArchive)
    }

    private func load() {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.travelLearnedArchive),
              let archive = try? JSONDecoder().decode(Archive.self, from: data) else {
            return
        }
        destinations = archive.destinations
        routes = archive.routes.filter { $0.sampleCount > 0 }
    }
}
