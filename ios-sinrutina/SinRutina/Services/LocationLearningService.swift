import CoreLocation
import Foundation
import Observation

/// Core Location, used with the smallest possible appetite.
///
/// Three modes, and never more than one at a time:
/// - **asleep**: nothing running. This is the default.
/// - **passive**: significant location changes and visits. Low power, only with
///   "Siempre", only when the person asked for background learning.
/// - **precise**: a temporary window during a real trip, stopped on arrival.
///
/// It also answers the one-shot question "where am I now" for a route that needs
/// computing. There is no continuous high-accuracy tracking anywhere.
@MainActor
@Observable
final class LocationLearningService: NSObject {
    static let shared = LocationLearningService()

    enum Access: Equatable {
        case notDetermined
        case whenInUse
        case always
        case denied
        case restricted

        /// Enough to compute a route while the person is looking at the app.
        var isGranted: Bool { self == .whenInUse || self == .always }
        /// Enough to learn a trip that finishes with the app closed.
        var allowsBackgroundLearning: Bool { self == .always }

        var label: String {
            switch self {
            case .notDetermined: return "Sin conceder"
            case .whenInUse: return "Al usar la app"
            case .always: return "Siempre"
            case .denied: return "Denegado"
            case .restricted: return "Restringido"
            }
        }

        var detail: String {
            switch self {
            case .notDetermined:
                return "SinRutina no ha pedido tu ubicación todavía."
            case .whenInUse:
                return "Puedo calcular y medir recorridos mientras SinRutina está abierta."
            case .always:
                return "Puedo aprender recorridos también cuando la app está cerrada."
            case .denied:
                return "Sin ubicación no puedo saber cuánto tardas. Puedes cambiarlo en Ajustes de iOS › Privacidad › Localización › SinRutina."
            case .restricted:
                return "La ubicación está restringida en este iPhone."
            }
        }
    }

    enum Mode: Equatable {
        case asleep
        case passive
        case precise
    }

    private(set) var access: Access = .notDetermined
    private(set) var mode: Mode = .asleep
    private(set) var lastErrorMessage: String?
    /// The most recent coarse point, whatever produced it.
    private(set) var lastKnownPoint: SRTravelPoint?
    private(set) var lastKnownAt: Date?
    /// True while a precise window is open, so the interface can be honest about it.
    var isTrackingPrecisely: Bool { mode == .precise }

    /// Handed every new point while any mode is running. Set by `TripDetector`.
    var onPoint: ((SRTravelPoint, Date) -> Void)?
    /// Handed the arrival/departure of a `CLVisit`, the cheapest learning signal.
    var onVisit: ((SRTravelPoint, Date, Date?) -> Void)?

    private let manager = CLLocationManager()
    private var continuations: [CheckedContinuation<SRTravelPoint?, Never>] = []
    private var isRequestingOneShot = false
    /// Guards against a precise window that outlives the trip that opened it.
    private var preciseDeadline: Date?
    private var preciseWatchdog: Task<Void, Never>?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.pausesLocationUpdatesAutomatically = true
        refreshAccessState()
    }

    // MARK: - Authorisation

    func refreshAccessState() {
        switch manager.authorizationStatus {
        case .notDetermined: access = .notDetermined
        case .restricted: access = .restricted
        case .denied: access = .denied
        case .authorizedWhenInUse: access = .whenInUse
        case .authorizedAlways: access = .always
        @unknown default: access = .notDetermined
        }
    }

    /// Asked only when the person turns "Salir a tiempo" on, after the explanation.
    func requestWhenInUse() {
        guard manager.authorizationStatus == .notDetermined else { return }
        manager.requestWhenInUseAuthorization()
    }

    /// Asked only when the person opts into learning with the app closed. iOS shows
    /// this prompt once, so it is never requested speculatively.
    func requestAlways() {
        guard manager.authorizationStatus == .authorizedWhenInUse else { return }
        manager.requestAlwaysAuthorization()
    }

    // MARK: - Passive learning

    /// Significant location changes plus visits: the two lowest-power signals iOS
    /// offers. Nothing else runs in the background.
    func startPassiveLearning() {
        refreshAccessState()
        guard access.allowsBackgroundLearning else { return }
        guard CLLocationManager.significantLocationChangeMonitoringAvailable() else {
            lastErrorMessage = "Este iPhone no ofrece cambios de ubicación de bajo consumo."
            return
        }
        guard mode != .precise else { return }
        manager.startMonitoringSignificantLocationChanges()
        manager.startMonitoringVisits()
        mode = .passive
    }

    func stopPassiveLearning() {
        manager.stopMonitoringSignificantLocationChanges()
        manager.stopMonitoringVisits()
        if mode == .passive { mode = .asleep }
    }

    // MARK: - Precise window

    /// Opens a higher-accuracy window for a trip that is actually happening.
    /// `maxMinutes` is a hard ceiling: if arrival is never detected, the GPS still
    /// goes back to sleep.
    func startPreciseTracking(maxMinutes: Int = 150) {
        refreshAccessState()
        guard access.isGranted else { return }
        manager.stopMonitoringSignificantLocationChanges()
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 120
        if access.allowsBackgroundLearning {
            // Only legal, and only useful, with "Siempre".
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
        mode = .precise
        preciseDeadline = Date().addingTimeInterval(Double(maxMinutes) * 60)
        startWatchdog()
    }

    /// Closes the precise window and returns to whatever low-power mode applies.
    func stopPreciseTracking() {
        preciseWatchdog?.cancel()
        preciseWatchdog = nil
        preciseDeadline = nil
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        manager.showsBackgroundLocationIndicator = false
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
        mode = .asleep
        // Passive learning resumes only if it was the person's choice.
        if SRTravelPreferences.shared.data.learnsInBackground {
            startPassiveLearning()
        }
    }

    private func startWatchdog() {
        preciseWatchdog?.cancel()
        preciseWatchdog = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self else { return }
                guard let deadline = self.preciseDeadline else { return }
                if Date() >= deadline {
                    self.stopPreciseTracking()
                    return
                }
            }
        }
    }

    // MARK: - One shot

    /// One coordinate, or nil. Never throws: not having a location is a normal
    /// outcome the caller has to explain honestly.
    func currentPoint(maxAge: TimeInterval = 120) async -> SRTravelPoint? {
        refreshAccessState()
        guard access.isGranted else { return nil }

        if let lastKnownPoint, let lastKnownAt, Date().timeIntervalSince(lastKnownAt) < maxAge {
            return lastKnownPoint
        }

        return await withCheckedContinuation { continuation in
            continuations.append(continuation)
            guard !isRequestingOneShot else { return }
            isRequestingOneShot = true
            manager.requestLocation()
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(8))
                self?.finishOneShot(with: nil, isTimeout: true)
            }
        }
    }

    private func finishOneShot(with point: SRTravelPoint?, isTimeout: Bool = false) {
        guard isRequestingOneShot else { return }
        let answer = point ?? (isTimeout ? lastKnownPoint : nil)
        isRequestingOneShot = false
        let waiting = continuations
        continuations = []
        for continuation in waiting {
            continuation.resume(returning: answer)
        }
    }

    // MARK: - Ingest

    fileprivate func ingest(_ location: CLLocation) {
        // Wildly inaccurate fixes are noise, not evidence.
        guard location.horizontalAccuracy > 0, location.horizontalAccuracy < 500 else { return }
        let point = SRTravelPoint(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        ).coarse
        lastKnownPoint = point
        lastKnownAt = Date()
        lastErrorMessage = nil
        finishOneShot(with: point)
        onPoint?(point, location.timestamp)
    }

    fileprivate func ingest(_ visit: CLVisit) {
        guard visit.horizontalAccuracy < 500 else { return }
        let point = SRTravelPoint(
            latitude: visit.coordinate.latitude,
            longitude: visit.coordinate.longitude
        ).coarse
        let arrival = visit.arrivalDate == Date.distantPast ? Date() : visit.arrivalDate
        let departure = visit.departureDate == Date.distantFuture ? nil : visit.departureDate
        lastKnownPoint = point
        lastKnownAt = Date()
        onVisit?(point, arrival, departure)
        onPoint?(point, arrival)
    }

    fileprivate func handleFailure() {
        lastErrorMessage = "iOS no pudo darme tu ubicación ahora mismo."
        finishOneShot(with: nil)
    }
}

extension LocationLearningService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            let service = LocationLearningService.shared
            service.refreshAccessState()
            // Losing "Siempre" must stop background learning instead of pretending.
            if !service.access.allowsBackgroundLearning, service.mode == .passive {
                service.stopPassiveLearning()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            LocationLearningService.shared.ingest(location)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        Task { @MainActor in
            LocationLearningService.shared.ingest(visit)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            LocationLearningService.shared.handleFailure()
        }
    }
}
