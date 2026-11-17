import Foundation
import CoreLocation

nonisolated struct EmberLocationContext: Sendable {
    let latitude: Double
    let longitude: Double
    let city: String?
    let region: String?
    let country: String?
    let name: String?

    var displayLine: String {
        var parts: [String] = []
        if let name, !name.isEmpty { parts.append(name) }
        if let city, !city.isEmpty { parts.append(city) }
        if let region, !region.isEmpty { parts.append(region) }
        return parts.joined(separator: ", ")
    }
}

extension Notification.Name {
    /// Posted on the main queue the moment the user flips Whisper's location
    /// permission from notDetermined/denied to authorizedWhenInUse/Always.
    /// Chat layers listen so they can auto-resume any reply that was blocked
    /// on a missing GPS fix (e.g. "food near me", "gyms nearby").
    static let emberLocationAuthorizationGranted = Notification.Name("emberLocationAuthorizationGranted")
}

@MainActor
final class EmberLocationService: NSObject, CLLocationManagerDelegate {
    static let shared = EmberLocationService()

    /// Tracks the previously-seen authorization status so we only post the
    /// `granted` notification on a real transition, not on every callback.
    private var lastObservedStatus: CLAuthorizationStatus = .notDetermined

    /// Quick readable accessor for callers that want to short-circuit the
    /// async path (e.g. show a different UI when location is already on).
    var isAuthorized: Bool {
        let status = manager.authorizationStatus
        return status == .authorizedWhenInUse || status == .authorizedAlways
    }

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?
    private var authContinuations: [CheckedContinuation<CLAuthorizationStatus, Never>] = []

    /// Cached last good fix — reused if it's recent enough to avoid cold-start failures.
    private var cachedLocation: CLLocation?
    private var cachedAt: Date?
    /// Short TTL so we don't reuse a stale fix when the user moves (in a car, walking, etc.).
    private let cacheTTL: TimeInterval = 15 // seconds
    /// Reject any fix worse than this for restaurant/nearby lookups.
    private let maxAcceptableAccuracyMeters: CLLocationAccuracy = 200
    /// Coalesce in-flight requests so racing callers don't tear down each other's continuation.
    private var inflightTask: Task<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.activityType = .other
        lastObservedStatus = manager.authorizationStatus
    }

    /// Requests a single, current location. Resolves with reverse-geocoded context.
    func requestCurrentContext() async throws -> EmberLocationContext {
        let location = try await obtainLocation()
        let geocoder = CLGeocoder()
        // Distinguish geocoder failure from a missing location — callers can still use lat/lon.
        let placemarks: [CLPlacemark]
        do {
            placemarks = try await geocoder.reverseGeocodeLocation(location)
        } catch {
            placemarks = []
        }
        let placemark = placemarks.first
        return EmberLocationContext(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            city: placemark?.locality,
            region: placemark?.administrativeArea,
            country: placemark?.country,
            name: placemark?.name
        )
    }

    private func obtainLocation() async throws -> CLLocation {
        // 1. Ensure we have authorization (wait for the prompt if needed).
        var status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
            status = await waitForAuthorizationChange()
        }
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            throw EmberLocationError.permissionDenied
        }

        // 2. Reuse a recent fix only if it's fresh AND reasonably accurate.
        if let cached = cachedLocation,
           let at = cachedAt,
           Date().timeIntervalSince(at) < cacheTTL,
           cached.horizontalAccuracy > 0,
           cached.horizontalAccuracy <= maxAcceptableAccuracyMeters {
            return cached
        }

        // 3. Coalesce concurrent callers onto one Task so racing requests don't fight
        //    over the single CLLocationManager continuation.
        if let existing = inflightTask {
            return try await existing.value
        }
        let task = Task<CLLocation, Error> { [weak self] in
            guard let self else { throw EmberLocationError.unavailable }
            defer { self.inflightTask = nil }
            return try await self.performLocationFetch()
        }
        inflightTask = task
        return try await task.value
    }

    private func performLocationFetch() async throws -> CLLocation {
        var attempt = 0
        var lastError: Error?
        while attempt < 3 {
            attempt += 1
            do {
                let loc = try await singleRequest()
                cachedLocation = loc
                cachedAt = Date()
                return loc
            } catch {
                lastError = error
                let nsError = error as NSError
                let isTransient = nsError.domain == kCLErrorDomain &&
                    (nsError.code == CLError.locationUnknown.rawValue || nsError.code == CLError.network.rawValue)
                if !isTransient { break }
                try? await Task.sleep(for: .milliseconds(700))
            }
        }

        // Last-resort fallback: any cached fix we have, even if stale.
        if let cached = cachedLocation { return cached }
        if let last = lastError as NSError?,
           last.domain == kCLErrorDomain,
           last.code == CLError.network.rawValue {
            throw EmberLocationError.networkUnavailable
        }
        throw lastError ?? EmberLocationError.unavailable
    }

    private func singleRequest() async throws -> CLLocation {
        // Drop any stale continuation defensively.
        if let stale = locationContinuation {
            locationContinuation = nil
            stale.resume(throwing: EmberLocationError.unavailable)
        }

        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<CLLocation, Error>) in
            self.locationContinuation = cont
            manager.requestLocation()
        }
    }

    private func waitForAuthorizationChange() async -> CLAuthorizationStatus {
        await withCheckedContinuation { (cont: CheckedContinuation<CLAuthorizationStatus, Never>) in
            self.authContinuations.append(cont)
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let loc = locations.last else { return }
        Task { @MainActor in
            self.cachedLocation = loc
            self.cachedAt = Date()
            self.locationContinuation?.resume(returning: loc)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            self.locationContinuation?.resume(throwing: error)
            self.locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            let previous = self.lastObservedStatus
            self.lastObservedStatus = status

            // Unblock anyone waiting for the prompt result.
            let waiters = self.authContinuations
            self.authContinuations.removeAll()
            for w in waiters { w.resume(returning: status) }

            if status == .denied || status == .restricted {
                self.locationContinuation?.resume(throwing: EmberLocationError.permissionDenied)
                self.locationContinuation = nil
            }

            // Detect a real grant transition so chat can auto-resume the reply
            // the user kicked off before turning location on.
            let wasGranted = (previous == .authorizedWhenInUse || previous == .authorizedAlways)
            let isGranted = (status == .authorizedWhenInUse || status == .authorizedAlways)
            if isGranted && !wasGranted {
                NotificationCenter.default.post(name: .emberLocationAuthorizationGranted, object: nil)
            }
        }
    }
}

nonisolated enum EmberLocationError: Error, LocalizedError, Sendable {
    case permissionDenied
    case unavailable
    case networkUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied: return "Location permission is needed to look up nearby spots."
        case .unavailable: return "Couldn't get your current location."
        case .networkUnavailable: return "Couldn't reach the location network. Check your connection."
        }
    }
}
