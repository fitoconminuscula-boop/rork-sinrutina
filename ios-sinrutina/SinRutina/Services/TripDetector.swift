import Foundation
import Observation

/// A place a trip could be heading to right now. Built by `PersonalTravelEngine`
/// from the calendar and from the learned destinations.
nonisolated struct SRTripTarget: Sendable, Hashable {
    var destinationID: UUID?
    var label: String
    var point: SRTravelPoint?
    var radiusMeters: Double
    var eventID: String?
    var modeRaw: String?
    /// The hour SinRutina suggested for leaving, when it suggested one.
    var suggestedLeaveAt: Date?

    var mode: SRTravelMode? { modeRaw.flatMap(SRTravelMode.init(rawValue:)) }
}

/// Recognises that a trip started and that it finished, so a real duration can be
/// measured.
///
/// It refuses to guess: a trip is only started by hand or after the person says
/// yes. Detection with low confidence produces a question, never a fact.
@MainActor
@Observable
final class TripDetector {
    static let shared = TripDetector()

    private(set) var activeTrip: SRActiveTrip?
    /// Set when movement looked like a trip but SinRutina is not sure.
    private(set) var pendingQuestion: SRTripQuestion?

    /// Where the trip could be going. Supplied by the engine.
    var targetsProvider: (() -> [SRTripTarget])?
    /// Called with a finished trip so it can be learned from.
    var onTripCompleted: ((SRCompletedTrip) -> Void)?

    /// How long inside the arrival radius counts as "arrived".
    private static let dwellSeconds: Double = 180
    /// How far from the starting point counts as "actually moving".
    private static let movementMeters: Double = 300
    /// A question nobody answered is dropped instead of nagging.
    private static let questionLifetimeSeconds: Double = 25 * 60

    private let location = LocationLearningService.shared
    private let store = LearnedRouteStore.shared

    private init() {
        activeTrip = Self.loadTrip()
        if activeTrip?.isStale == true {
            // A trip nobody closed is not evidence of anything.
            activeTrip = nil
            Self.clearTrip()
        }
    }

    // MARK: - Wiring

    /// Starts listening to whatever location mode is currently running.
    func attach() {
        location.onPoint = { [weak self] point, date in
            self?.note(point: point, at: date)
        }
        location.onVisit = { [weak self] point, arrival, _ in
            self?.note(visit: point, arrival: arrival)
        }
    }

    // MARK: - Starting

    /// "Estoy saliendo". The only fully trusted way to start a trip.
    func startTrip(target: SRTripTarget, isSimulated: Bool = false) {
        pendingQuestion = nil
        let trip = SRActiveTrip(
            eventID: target.eventID,
            destinationID: target.destinationID,
            destinationLabel: target.label,
            destinationPoint: target.point,
            arrivalRadiusMeters: target.radiusMeters,
            mode: target.mode,
            suggestedLeaveAt: target.suggestedLeaveAt,
            startedAt: Date(),
            startPoint: location.lastKnownPoint,
            origin: .declared,
            isSimulated: isSimulated
        )
        activeTrip = trip
        persist()
        // Simulated trips never touch the GPS or the learning store.
        guard !isSimulated else { return }
        location.startPreciseTracking()
        Task { [weak self] in
            // A fresh fix makes the starting point real rather than assumed.
            let point = await LocationLearningService.shared.currentPoint(maxAge: 60)
            guard let self, var current = self.activeTrip, current.id == trip.id else { return }
            if current.startPoint == nil { current.startPoint = point }
            self.activeTrip = current
            self.persist()
        }
    }

    /// Answers the question with "yes". Only now does the trip become a fact.
    func confirmPendingQuestion() {
        guard let question = pendingQuestion else { return }
        let targets = targetsProvider?() ?? []
        let target = targets.first { candidate in
            candidate.destinationID == question.destinationID && question.destinationID != nil
        } ?? targets.first { $0.eventID == question.eventID && question.eventID != nil }
        pendingQuestion = nil
        guard let target else { return }
        var trip = SRActiveTrip(
            eventID: target.eventID,
            destinationID: target.destinationID,
            destinationLabel: target.label,
            destinationPoint: target.point,
            arrivalRadiusMeters: target.radiusMeters,
            mode: target.mode,
            suggestedLeaveAt: target.suggestedLeaveAt,
            startedAt: Date(),
            startPoint: location.lastKnownPoint,
            origin: .confirmedDetection
        )
        // Movement was already visible when the question was asked.
        trip.movementStartedAt = Date()
        activeTrip = trip
        persist()
        location.startPreciseTracking()
    }

    func dismissPendingQuestion() {
        pendingQuestion = nil
    }

    // MARK: - Finishing

    /// "Ya llegué". Closes the trip with the person's own confirmation.
    func confirmArrival(at date: Date = Date()) {
        guard let trip = activeTrip else { return }
        complete(trip, arrivedAt: date)
    }

    /// Drops the trip without learning anything from it.
    func cancelTrip() {
        activeTrip = nil
        Self.clearTrip()
        location.stopPreciseTracking()
    }

    /// Replaces a measured duration with one the person typed, for a trip that
    /// could not be measured.
    func closeTripWithManualDuration(minutes: Int) {
        guard let trip = activeTrip, minutes > 0 else { return }
        let seconds = Double(min(minutes, 300)) * 60
        finish(
            SRCompletedTrip(
                trip: trip,
                arrivedAt: trip.measuringSince.addingTimeInterval(seconds),
                seconds: seconds,
                isManualDuration: true
            )
        )
    }

    // MARK: - Signals

    /// Every new coordinate passes through here, whatever mode produced it.
    func note(point: SRTravelPoint, at date: Date = Date()) {
        expireQuestionIfNeeded()

        guard var trip = activeTrip else {
            considerAutomaticStart(point: point)
            return
        }

        trip.lastSeenAt = date

        // Real movement starts the clock that becomes the learned duration.
        if trip.movementStartedAt == nil,
           let start = trip.startPoint,
           start.distance(to: point) >= Self.movementMeters {
            trip.movementStartedAt = date
        }
        if trip.startPoint == nil { trip.startPoint = point }

        // Arrival: inside the radius, and still there a few minutes later.
        if let destinationPoint = trip.destinationPoint {
            let distance = destinationPoint.distance(to: point)
            if distance <= trip.arrivalRadiusMeters {
                if let entered = trip.enteredRadiusAt {
                    if date.timeIntervalSince(entered) >= Self.dwellSeconds {
                        activeTrip = trip
                        complete(trip, arrivedAt: entered)
                        return
                    }
                } else {
                    trip.enteredRadiusAt = date
                }
            } else if distance > trip.arrivalRadiusMeters * 1.6 {
                // Passing by is not arriving.
                trip.enteredRadiusAt = nil
            }
        }

        activeTrip = trip
        persist()
    }

    /// A visit is the cheapest arrival signal iOS gives, and the only one available
    /// when the app was never opened during the trip.
    func note(visit point: SRTravelPoint, arrival: Date) {
        guard let trip = activeTrip else {
            // Visits still teach SinRutina which places matter to this person.
            noteVisitedPlace(point, at: arrival)
            return
        }
        guard let destinationPoint = trip.destinationPoint else { return }
        guard destinationPoint.distance(to: point) <= max(trip.arrivalRadiusMeters, 200) else { return }
        guard arrival > trip.measuringSince else { return }
        complete(trip, arrivedAt: arrival)
    }

    /// Called by the engine's timer so a trip can finish even if no new coordinate
    /// arrives after the one that entered the radius.
    func tick() {
        expireQuestionIfNeeded()
        guard let trip = activeTrip else { return }
        if trip.isStale {
            // Never keep the GPS awake for a trip that clearly ended untold.
            cancelTrip()
            return
        }
        guard let entered = trip.enteredRadiusAt,
              Date().timeIntervalSince(entered) >= Self.dwellSeconds else {
            return
        }
        complete(trip, arrivedAt: entered)
    }

    // MARK: - Automatic start

    /// Movement towards a known target becomes a question, never a decision.
    private func considerAutomaticStart(point: SRTravelPoint) {
        guard SRTravelPreferences.shared.data.isEnabled else { return }
        guard pendingQuestion == nil else { return }
        let targets = targetsProvider?() ?? []
        guard !targets.isEmpty else { return }

        for target in targets {
            guard let destinationPoint = target.point else { continue }
            let distance = destinationPoint.distance(to: point)
            // Already there: nothing to travel.
            if distance <= max(target.radiusMeters, 200) { continue }
            // Only ask when the trip is plausibly under way: the suggested leaving
            // time is near, and the person is not where they usually start.
            guard let leaveAt = target.suggestedLeaveAt else { continue }
            let minutesFromLeave = Date().timeIntervalSince(leaveAt) / 60
            guard minutesFromLeave > -10, minutesFromLeave < 45 else { continue }
            pendingQuestion = SRTripQuestion(
                destinationLabel: target.label,
                destinationID: target.destinationID,
                eventID: target.eventID
            )
            return
        }
    }

    private func expireQuestionIfNeeded() {
        guard let question = pendingQuestion else { return }
        if Date().timeIntervalSince(question.createdAt) > Self.questionLifetimeSeconds {
            pendingQuestion = nil
        }
    }

    /// A place visited often enough is worth remembering, with no name attached.
    private func noteVisitedPlace(_ point: SRTravelPoint, at date: Date) {
        guard SRTravelPreferences.shared.data.learnsRoutes,
              SRTravelPreferences.shared.data.learnsInBackground else {
            return
        }
        guard let existing = store.destination(near: point) else { return }
        store.rename(existing, to: existing.name)
    }

    // MARK: - Completion

    private func complete(_ trip: SRActiveTrip, arrivedAt: Date) {
        let seconds = arrivedAt.timeIntervalSince(trip.measuringSince)
        // Under two minutes is not a trip; it is noise.
        guard seconds >= 120 else {
            cancelTrip()
            return
        }
        finish(
            SRCompletedTrip(
                trip: trip,
                arrivedAt: arrivedAt,
                seconds: seconds,
                isManualDuration: false
            )
        )
    }

    private func finish(_ completed: SRCompletedTrip) {
        activeTrip = nil
        Self.clearTrip()
        location.stopPreciseTracking()
        onTripCompleted?(completed)
    }

    // MARK: - Storage

    private func persist() {
        guard let trip = activeTrip, let data = try? JSONEncoder().encode(trip) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.travelActiveTrip)
    }

    private static func clearTrip() {
        SRShared.defaults.removeObject(forKey: SRShared.Key.travelActiveTrip)
    }

    private static func loadTrip() -> SRActiveTrip? {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.travelActiveTrip),
              let trip = try? JSONDecoder().decode(SRActiveTrip.self, from: data) else {
            return nil
        }
        return trip
    }
}
