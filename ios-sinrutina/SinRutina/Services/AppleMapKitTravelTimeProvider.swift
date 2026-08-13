import CoreLocation
import Foundation
import MapKit

/// Apple MapKit as an optional fallback for places with no history yet.
///
/// It runs through the person's own device and needs no key, no account and no
/// billing. It is never the first source, and its public transport answers are not
/// treated as dependable: coverage depends on the region, so when MapKit cannot
/// answer, SinRutina asks the person instead of inventing a number.
nonisolated final class AppleMapKitTravelTimeProvider: TravelTimeProvider {
    static let shared = AppleMapKitTravelTimeProvider()

    let providerID: SRRouteProviderID = .apple

    private init() {}

    /// MapKit ships with iOS, so this provider is always callable.
    var isConfigured: Bool { true }

    var configurationNotice: String? { nil }

    func supports(_ mode: SRTravelMode) -> Bool {
        switch mode {
        case .car, .walking, .transit: return true
        case .cycling, .mixed, .other: return false
        }
    }

    /// Driving and walking are dependable anywhere. Public transport depends on
    /// regional coverage, so it is asked but never trusted as a single source.
    func isReliable(for mode: SRTravelMode) -> Bool {
        switch mode {
        case .car, .walking: return true
        case .transit, .cycling, .mixed, .other: return false
        }
    }

    func estimate(for query: SRTravelQuery) async throws -> SRProviderEstimate {
        guard supports(query.mode) else { throw SRTravelError.modeUnsupported(query.mode) }
        let destination = try await coordinate(for: query.destination)

        let request = MKDirections.Request()
        request.source = MKMapItem(
            placemark: MKPlacemark(
                coordinate: CLLocationCoordinate2D(
                    latitude: query.origin.latitude,
                    longitude: query.origin.longitude
                )
            )
        )
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination))
        request.transportType = Self.transportType(query.mode)
        request.requestsAlternateRoutes = false
        if let departAt = query.departAt, departAt > Date() {
            request.departureDate = departAt
        }

        do {
            let response = try await MKDirections(request: request).calculateETA()
            return SRProviderEstimate(
                provider: .apple,
                mode: query.mode,
                seconds: response.expectedTravelTime,
                meters: response.distance
            )
        } catch let error as MKError {
            switch error.code {
            case .directionsNotFound, .placemarkNotFound: throw SRTravelError.noRoute
            case .loadingThrottled: throw SRTravelError.rateLimited
            default: throw SRTravelError.network
            }
        } catch {
            throw SRTravelError.network
        }
    }

    private func coordinate(for destination: SRTravelDestination) async throws -> CLLocationCoordinate2D {
        switch destination {
        case .coordinate(let point):
            return CLLocationCoordinate2D(latitude: point.latitude, longitude: point.longitude)
        case .address(let address):
            guard let resolved = try? await CLGeocoder().geocodeAddressString(address).first?.location else {
                throw SRTravelError.destinationUnknown
            }
            return resolved.coordinate
        }
    }

    private static func transportType(_ mode: SRTravelMode) -> MKDirectionsTransportType {
        switch mode {
        case .car: return .automobile
        case .walking: return .walking
        case .transit: return .transit
        case .cycling, .mixed, .other: return .any
        }
    }
}
