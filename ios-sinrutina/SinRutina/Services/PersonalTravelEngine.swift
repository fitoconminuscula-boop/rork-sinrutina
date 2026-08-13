import CoreLocation
import EventKit
import Foundation
import Observation

/// "Salir a tiempo", built around one personal question: **¿cuánto tardas tú
/// realmente en llegar?**
///
/// This is the façade that ties the pieces together and the only one the interface
/// talks to:
/// - `LocationLearningService` provides location, with the smallest appetite possible;
/// - `TripDetector` recognises that a trip started and finished;
/// - `LearnedRouteStore` remembers durations per place, weekday and band of the day;
/// - `DepartureTimeEngine` turns a duration into "stop now, get ready, leave";
/// - `AppleMapKitTravelTimeProvider` is an optional fallback for places with no
///   history yet.
///
/// The order of trust never changes: personal history, partial history, Apple Maps,
/// a duration the person typed, and then nothing. A time is never invented.
@MainActor
@Observable
final class PersonalTravelEngine {
    static let shared = PersonalTravelEngine()

    /// Upcoming trips, soonest first. At most three: this is not an itinerary app.
    private(set) var plans: [SRDeparturePlan] = []
    private(set) var isRecalculating = false
    /// Honest explanation when nothing could be computed.
    private(set) var lastNotice: String?
    private(set) var lastRefreshAt: Date?
    /// Set when a trip just taught SinRutina something, for a calm confirmation.
    private(set) var lastLearnedMessage: String?

    private let calendar = CalendarService.shared
    private let location = LocationLearningService.shared
    private let detector = TripDetector.shared
    private let store = LearnedRouteStore.shared
    private let preferences = SRTravelPreferences.shared
    private let departures = DepartureTimeEngine()
    private let maps = AppleMapKitTravelTimeProvider.shared

    /// Trips the person closed by hand. In memory only: tomorrow is a new day.
    private var dismissedEventIDs: Set<String> = []
    private var watchTask: Task<Void, Never>?
    /// Addresses already located, so a place is not geocoded on every refresh.
    private var geocodeCache: [String: SRTravelPoint] = [:]
    /// Event IDs already warned about arriving late, to say it only once.
    private var lateWarnedEventIDs: Set<String> = []

    private init() {
        geocodeCache = Self.loadGeocodeCache()
        detector.targetsProvider = { [weak self] in self?.currentTargets() ?? [] }
        detector.onTripCompleted = { [weak self] completed in
            self?.learn(from: completed)
        }
        detector.attach()
    }

    // MARK: - State

    var isEnabled: Bool { preferences.data.isEnabled }
    var activeTrip: SRActiveTrip? { detector.activeTrip }
    var pendingQuestion: SRTripQuestion? { detector.pendingQuestion }
    var isTravelling: Bool { detector.activeTrip != nil }

    /// The trip that matters right now, if any.
    var nextPlan: SRDeparturePlan? {
        plans.first { plan in
            !dismissedEventIDs.contains(plan.eventID)
                && plan.eventStart > Date().addingTimeInterval(-15 * 60)
        }
    }

    /// True when the feature is on but Core Location was never authorised.
    var needsLocationPermission: Bool {
        preferences.data.isEnabled && !location.access.isGranted
    }

    /// Minutes of real work left before the preparation window opens. `nil` means
    /// no departure is close enough to shape what to do next.
    var minutesBeforePreparation: Int? {
        guard let plan = nextPlan, let minutes = plan.minutesUntilPrep() else { return nil }
        guard minutes >= 0, minutes <= 240 else { return nil }
        return minutes
    }

    /// The learned transition time, once it exists and has been confirmed.
    var confirmedTransitionMinutes: Int? {
        guard preferences.data.usesLearnedPrep, preferences.data.learnedPrepMinutes > 0 else {
            return nil
        }
        return preferences.data.learnedPrepMinutes
    }

    // MARK: - Turning the feature on

    /// Called from the explanation screen, never on launch. Permission is only
    /// requested once the person decided they want this.
    func enable() {
        preferences.update { $0.isEnabled = true }
        location.refreshAccessState()
        if location.access == .notDetermined {
            location.requestWhenInUse()
        }
        Task { await refresh(reason: .userChange) }
    }

    func disable() {
        preferences.update {
            $0.isEnabled = false
            $0.learnsInBackground = false
        }
        location.stopPassiveLearning()
        detector.cancelTrip()
        cancelEverything()
        plans = []
        lastNotice = nil
    }

    /// Background learning is opt-in and needs "Siempre". If iOS does not grant it,
    /// the switch goes back off instead of pretending.
    func setBackgroundLearning(_ isOn: Bool) {
        guard isOn else {
            preferences.update { $0.learnsInBackground = false }
            location.stopPassiveLearning()
            return
        }
        location.refreshAccessState()
        switch location.access {
        case .always:
            preferences.update { $0.learnsInBackground = true }
            location.startPassiveLearning()
        case .whenInUse:
            location.requestAlways()
            // The switch turns on only if iOS actually grants it.
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard let self else { return }
                self.location.refreshAccessState()
                if self.location.access.allowsBackgroundLearning {
                    self.preferences.update { $0.learnsInBackground = true }
                    self.location.startPassiveLearning()
                }
            }
        case .notDetermined:
            location.requestWhenInUse()
        case .denied, .restricted:
            break
        }
    }

    // MARK: - Refresh

    /// Recalculates every upcoming trip. Safe to call often.
    func refresh(reason: RefreshReason = .opened) async {
        guard preferences.data.isEnabled else {
            plans = []
            return
        }
        syncConfirmedTransitionLearning()

        let events = locatedEvents()
        guard !events.isEmpty else {
            plans = []
            lastNotice = nil
            return
        }
        location.refreshAccessState()
        guard location.access.isGranted else {
            plans = []
            lastNotice = "Necesito tu ubicación para saber cuánto tardas en llegar."
            return
        }

        isRecalculating = true
        defer { isRecalculating = false }

        let origin = await location.currentPoint()
        if origin == nil {
            lastNotice = "iOS no me dio tu ubicación. Puedo usar tu historial, pero no sé desde dónde sales."
        }

        var computed: [SRDeparturePlan] = []
        for event in events.prefix(3) {
            guard let plan = await plan(for: event, origin: origin) else { continue }
            computed.append(plan)
            await announce(plan, reason: reason)
        }

        plans = computed.sorted { lhs, rhs in
            (lhs.leaveAt ?? lhs.eventStart) < (rhs.leaveAt ?? rhs.eventStart)
        }
        if !computed.isEmpty, origin != nil { lastNotice = nil }
        lastRefreshAt = Date()
    }

    enum RefreshReason {
        case opened
        case timer
        case userChange
    }

    // MARK: - Watching

    /// Keeps the hour honest while the app is in front, and lets a trip finish even
    /// if no new coordinate arrives. Stops the moment the app leaves.
    func startWatching() {
        guard watchTask == nil, preferences.data.isEnabled else { return }
        if preferences.data.learnsInBackground {
            location.startPassiveLearning()
        }
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let interval = self.watchInterval
                try? await Task.sleep(for: .seconds(interval))
                if Task.isCancelled { return }
                self.detector.tick()
                await self.refresh(reason: .timer)
                await self.warnIfLate()
            }
        }
    }

    func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    /// Closer trip, closer looks. Never faster than every two minutes, and slower
    /// still while a trip is being measured.
    private var watchInterval: Double {
        if detector.activeTrip != nil { return 120 }
        guard let minutes = nextPlan?.minutesUntilLeaving() else { return 900 }
        switch minutes {
        case ..<20: return 120
        case ..<60: return 300
        default: return 600
        }
    }

    // MARK: - Actions

    /// "Estoy saliendo": associates the trip, starts measuring, and lets Ahora know
    /// that nothing else should be proposed right now.
    func startLeaving(_ plan: SRDeparturePlan) {
        let target = target(for: plan)
        detector.startTrip(target: target, isSimulated: plan.isSimulated)
        departures.cancelNotifications(eventID: plan.eventID)
        SRDeparturePlanStore.remove(eventID: plan.eventID)
        dismissedEventIDs.insert(plan.eventID)
        plans.removeAll { $0.eventID == plan.eventID }
    }

    /// Called from the notification action.
    func startLeaving(eventID: String) {
        guard let plan = plans.first(where: { $0.eventID == eventID }) else {
            departures.cancelNotifications(eventID: eventID)
            return
        }
        startLeaving(plan)
    }

    func confirmArrival() {
        detector.confirmArrival()
    }

    func cancelTrip() {
        detector.cancelTrip()
        Task { await refresh(reason: .userChange) }
    }

    /// For a trip that could not be measured: the person says how long it took.
    func closeTrip(manualMinutes: Int) {
        detector.closeTripWithManualDuration(minutes: manualMinutes)
    }

    func confirmPendingQuestion() {
        detector.confirmPendingQuestion()
    }

    func dismissPendingQuestion() {
        detector.dismissPendingQuestion()
    }

    func dismiss(_ plan: SRDeparturePlan) {
        dismissedEventIDs.insert(plan.eventID)
        departures.cancelNotifications(eventID: plan.eventID)
    }

    /// Changes the way of getting to a place and recalculates just that trip.
    func setMode(_ mode: SRTravelMode, for plan: SRDeparturePlan) async {
        preferences.rememberMode(mode, forDestination: plan.destinationLabel)
        await refresh(reason: .userChange)
    }

    /// The answer to "primera vez a este lugar, ¿cuánto calculas que demorarás?".
    func saveManualEstimate(minutes: Int, for plan: SRDeparturePlan) async {
        preferences.rememberManualMinutes(minutes, forDestination: plan.destinationLabel)
        await refresh(reason: .userChange)
    }

    /// The person decided not to estimate this trip. Nothing is invented for it.
    func skipEstimate(for plan: SRDeparturePlan) {
        dismiss(plan)
        plans.removeAll { $0.eventID == plan.eventID }
    }

    func setUsesLearnedPrep(_ isOn: Bool) {
        preferences.update { $0.usesLearnedPrep = isOn }
        Task { await refresh(reason: .userChange) }
    }

    // MARK: - Planning

    private func plan(for event: EKEvent, origin: SRTravelPoint?) async -> SRDeparturePlan? {
        guard let start = event.startDate, let destination = destination(for: event) else { return nil }
        let label = destinationLabel(for: event)
        let mode = preferences.mode(forDestination: label) ?? preferences.data.defaultMode
        let resolvedPoint = await point(for: destination)
        let known = resolvedPoint.flatMap { store.destination(for: $0, name: label, createIfMissing: true) }

        let targetArrival = start.addingTimeInterval(-Double(preferences.data.arriveEarlyMinutes) * 60)
        let estimate = await estimate(
            destinationID: known?.id,
            destination: destination,
            destinationLabel: label,
            origin: origin,
            mode: mode,
            departingAt: departureGuess(arrival: targetArrival)
        )

        let finalStretch = store.finalStretchMinutes(for: known?.id)
            ?? (mode.needsParking ? preferences.data.finalStretchMinutes : 0)

        let input = DepartureTimeEngine.Input(
            eventID: event.eventIdentifier ?? "\(label)-\(start.timeIntervalSince1970)",
            eventTitle: event.title ?? "Tu próximo compromiso",
            destinationLabel: label,
            destinationID: known?.id,
            eventStart: start,
            mode: mode,
            estimate: estimate,
            prepMinutes: preferences.effectivePrepMinutes,
            arriveEarlyMinutes: preferences.data.arriveEarlyMinutes,
            finalStretchMinutes: finalStretch,
            notice: notice(for: estimate, mode: mode)
        )
        return departures.plan(from: input)
    }

    /// A first guess of the departure time, used only to pick the right band of the
    /// day before any duration is known.
    private func departureGuess(arrival: Date) -> Date {
        arrival.addingTimeInterval(-45 * 60)
    }

    /// The order of trust, in one place.
    ///
    /// 1. reliable personal history; 2. partial personal history; 3. Apple Maps when
    /// it really answers; 4. a duration the person typed; 5. nothing at all.
    private func estimate(
        destinationID: UUID?,
        destination: SRTravelDestination,
        destinationLabel: String,
        origin: SRTravelPoint?,
        mode: SRTravelMode,
        departingAt date: Date
    ) async -> TravelEstimate? {
        if let destinationID,
           let personal = store.estimate(
               origin: origin,
               destinationID: destinationID,
               mode: mode,
               departingAt: date
           ) {
            return personal
        }

        if preferences.data.usesMapsFallback, mode.canAskMaps, let origin {
            let query = SRTravelQuery(origin: origin, destination: destination, mode: mode, departAt: date)
            if let answer = try? await maps.estimate(for: query) {
                let isReliable = maps.isReliable(for: mode)
                let detail = isReliable
                    ? "Apple Maps, porque todavía no tengo viajes tuyos a este lugar."
                    : "Apple Maps. Su cobertura de transporte público depende de la zona, así que lo trato con cautela."
                return TravelEstimate(
                    source: .mapKit,
                    typicalSeconds: answer.seconds,
                    lowSeconds: answer.seconds,
                    highSeconds: answer.seconds * (isReliable ? 1.12 : 1.25),
                    sampleCount: 0,
                    mode: mode,
                    confidence: isReliable ? .low : .none,
                    detail: detail
                )
            }
        }

        if let minutes = preferences.manualMinutes(forDestination: destinationLabel) {
            return TravelEstimate(
                source: .manual,
                typicalSeconds: Double(minutes) * 60,
                lowSeconds: Double(minutes) * 60,
                highSeconds: Double(minutes) * 60 * 1.15,
                sampleCount: 0,
                mode: mode,
                confidence: .low,
                detail: "La duración que me diste para este lugar. Se ajustará con tu primer viaje real."
            )
        }

#if DEBUG
        if preferences.data.isSimulationEnabled {
            return TravelEstimate(
                source: .simulation,
                typicalSeconds: 36 * 60,
                lowSeconds: 32 * 60,
                highSeconds: 40 * 60,
                mode: mode,
                confidence: .none,
                detail: "Simulación de recorrido. No se guarda como aprendizaje.",
                isSimulated: true
            )
        }
#endif

        return nil
    }

    private func notice(for estimate: TravelEstimate?, mode: SRTravelMode) -> String? {
        guard let estimate else {
            return "Primera vez a este lugar. Dime cuánto calculas que tardarás o sáltalo: no me lo voy a inventar."
        }
        switch estimate.source {
        case .personalConfident:
            return nil
        case .personalPartial:
            return "\(estimate.detail) Uso un margen más amplio hasta tener más viajes."
        case .mapKit:
            return estimate.detail
        case .manual:
            return estimate.detail
        case .simulation:
            return "Simulación. Ninguna duración simulada entra en tu historial."
        }
    }

    // MARK: - Learning

    /// A finished trip becomes a learned duration, and the transition time becomes
    /// an observation that has to be confirmed before it changes anything.
    private func learn(from completed: SRCompletedTrip) {
        let trip = completed.trip
        guard !trip.isSimulated else {
            // A simulated trip teaches nothing. Ever.
            lastLearnedMessage = "Era una simulación: no la guardo en tu historial."
            return
        }
        guard preferences.data.learnsRoutes else { return }

        var destinationID = trip.destinationID
        if destinationID == nil, let point = trip.destinationPoint {
            destinationID = store.destination(for: point, name: trip.destinationLabel)?.id
        }
        guard let destinationID else { return }

        store.record(
            origin: trip.startPoint,
            destinationID: destinationID,
            mode: trip.mode,
            seconds: completed.seconds,
            prepSeconds: trip.transitionSeconds,
            at: completed.arrivedAt,
            isManual: completed.isManualDuration
        )

        if let transition = trip.transitionSeconds {
            SRTransitionMemory.record(seconds: transition, mode: trip.mode)
            observeTransitionIfMeaningful()
        }

        let minutes = Int((completed.seconds / 60).rounded())
        let count = store.sampleCount(for: destinationID)
        lastLearnedMessage = count <= 1
            ? "Primer viaje a \(trip.destinationLabel) registrado: \(minutes) min."
            : "Anotado: \(minutes) min a \(trip.destinationLabel). Ya son \(count) viajes."

        Task { await refresh(reason: .userChange) }
    }

    /// SinRutina writes down only what it can see, and asks before using it.
    private func observeTransitionIfMeaningful() {
        guard let minutes = SRTransitionMemory.typicalMinutes else { return }
        SRLearningStore.shared.observe(
            kind: .departureLag,
            text: "Normalmente necesitas unos \(minutes) minutos desde que decides salir hasta que empiezas el trayecto.",
            value: String(minutes),
            minimumEvidence: 2
        )
    }

    /// Mirrors a confirmed observation into the preferences, so the person can see
    /// it and switch it off in Ajustes.
    private func syncConfirmedTransitionLearning() {
        guard let insight = SRLearningStore.shared.insight(of: .departureLag),
              insight.isConfirmed,
              let minutes = insight.intValue else {
            if preferences.data.usesLearnedPrep, SRLearningStore.shared.insight(of: .departureLag) == nil {
                preferences.update {
                    $0.usesLearnedPrep = false
                    $0.learnedPrepMinutes = 0
                }
            }
            return
        }
        guard preferences.data.learnedPrepMinutes != minutes || !preferences.data.usesLearnedPrep else {
            return
        }
        preferences.update {
            $0.learnedPrepMinutes = minutes
            $0.usesLearnedPrep = true
        }
    }

    // MARK: - Targets

    /// What a trip could be heading to right now: the planned departures first, and
    /// the trip in progress if there is one.
    private func currentTargets() -> [SRTripTarget] {
        plans.compactMap { plan in
            guard plan.eventStart > Date().addingTimeInterval(-30 * 60) else { return nil }
            return target(for: plan)
        }
    }

    private func target(for plan: SRDeparturePlan) -> SRTripTarget {
        let known = plan.destinationID.flatMap { store.destination(id: $0) }
        return SRTripTarget(
            destinationID: plan.destinationID,
            label: plan.destinationLabel,
            point: known?.point,
            radiusMeters: known?.radiusMeters ?? 180,
            eventID: plan.eventID,
            modeRaw: plan.modeRaw,
            suggestedLeaveAt: plan.leaveAt
        )
    }

    // MARK: - Events

    private func locatedEvents() -> [EKEvent] {
        let now = Date()
        let horizon = now.addingTimeInterval(14 * 3_600)
        return calendar.upcomingEvents.filter { event in
            guard let start = event.startDate, start > now.addingTimeInterval(-5 * 60), start < horizon else {
                return false
            }
            guard !event.isAllDay else { return false }
            guard destination(for: event) != nil else { return false }
            return !dismissedEventIDs.contains(event.eventIdentifier ?? "")
        }
    }

    /// Coordinates when the calendar has them, a cleaned address otherwise.
    private func destination(for event: EKEvent) -> SRTravelDestination? {
        if let coordinate = event.structuredLocation?.geoLocation?.coordinate {
            return .coordinate(
                SRTravelPoint(latitude: coordinate.latitude, longitude: coordinate.longitude).coarse
            )
        }
        guard let raw = event.structuredLocation?.title ?? event.location,
              let address = SRTravelPrivacyGuard.sanitiseAddress(raw) else {
            return nil
        }
        return .address(address)
    }

    /// The human name of the place, kept on the device for the interface.
    private func destinationLabel(for event: EKEvent) -> String {
        let raw = event.structuredLocation?.title ?? event.location ?? ""
        let firstLine = raw.split(separator: "\n").first.map(String.init) ?? raw
        let trimmed = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? (event.title ?? "Destino") : trimmed
    }

    /// Turns an address into a coordinate once and remembers it.
    private func point(for destination: SRTravelDestination) async -> SRTravelPoint? {
        switch destination {
        case .coordinate(let point):
            return point
        case .address(let address):
            let key = SRTravelKeys.normalise(address)
            if let known = geocodeCache[key] { return known }
            guard let located = try? await CLGeocoder().geocodeAddressString(address).first?.location else {
                return nil
            }
            let point = SRTravelPoint(
                latitude: located.coordinate.latitude,
                longitude: located.coordinate.longitude
            ).coarse
            geocodeCache[key] = point
            persistGeocodeCache()
            return point
        }
    }

    func forgetGeocodes() {
        geocodeCache = [:]
        SRShared.defaults.removeObject(forKey: SRShared.Key.travelGeocodeCache)
    }

    private func persistGeocodeCache() {
        let trimmed = Dictionary(uniqueKeysWithValues: Array(geocodeCache.prefix(80)))
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        SRShared.defaults.set(data, forKey: SRShared.Key.travelGeocodeCache)
    }

    private static func loadGeocodeCache() -> [String: SRTravelPoint] {
        guard let data = SRShared.defaults.data(forKey: SRShared.Key.travelGeocodeCache),
              let decoded = try? JSONDecoder().decode([String: SRTravelPoint].self, from: data) else {
            return [:]
        }
        return decoded
    }

    // MARK: - Telling the person

    private func announce(_ plan: SRDeparturePlan, reason: RefreshReason) async {
        guard plan.hasEstimate else { return }
        let previous = SRDeparturePlanStore.record(for: plan.eventID)
        let record = await departures.announce(
            plan,
            previous: previous,
            threshold: effectiveThreshold,
            isInterruptionAllowed: mayInterrupt && reason != .userChange
        )
        SRDeparturePlanStore.save(record)
    }

    /// If leaving right now already means arriving late, that is worth saying once.
    private func warnIfLate() async {
        guard mayInterrupt, let plan = nextPlan, let leaveAt = plan.leaveAt else { return }
        guard Date() > leaveAt, !lateWarnedEventIDs.contains(plan.eventID) else { return }
        guard let lateMinutes = plan.lateMinutesIfLeavingNow(), lateMinutes >= 5 else { return }
        lateWarnedEventIDs.insert(plan.eventID)
        await departures.sendLateRiskNotification(plan, lateMinutes: lateMinutes)
    }

    /// The threshold adapts instead of the volume: if trips were already
    /// re-announced today, it takes a bigger change to speak again.
    var effectiveThreshold: Int {
        let base = preferences.data.notifyThresholdMinutes
        let recent = SRDeparturePlanStore.recentChangeNotifications()
        guard recent >= 2 else { return base }
        return min(20, base + 4)
    }

    private var mayInterrupt: Bool {
        guard preferences.data.notifiesDeparture else { return false }
        return SRProactivityPreferences.shared.isEnabled(.calendar)
    }

    private func cancelEverything() {
        for plan in plans {
            departures.cancelNotifications(eventID: plan.eventID)
        }
        SRDeparturePlanStore.clear()
    }

    // MARK: - Erasing

    /// Everything this feature learned, gone. Called from Ajustes.
    func eraseLearning() {
        store.removeAll()
        SRTransitionMemory.clear()
        preferences.update {
            $0.usesLearnedPrep = false
            $0.learnedPrepMinutes = 0
            $0.manualMinutesByDestination = [:]
        }
        forgetGeocodes()
        Task { await refresh(reason: .userChange) }
    }
}
