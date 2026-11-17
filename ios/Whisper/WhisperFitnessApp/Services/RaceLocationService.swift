import Foundation
import CoreLocation

@Observable
class RaceLocationService: NSObject, CLLocationManagerDelegate {
    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    var totalDistance: Double = 0
    var currentSpeed: Double = 0
    var routeCoordinates: [CLLocationCoordinate2D] = []

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var isTracking = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.activityType = .fitness
        manager.distanceFilter = 5
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        } else if manager.authorizationStatus == .authorizedWhenInUse {
            manager.requestAlwaysAuthorization()
        }
    }

    func startTracking() {
        totalDistance = 0
        currentSpeed = 0
        routeCoordinates = []
        lastLocation = nil
        isTracking = true
        if hasBackgroundLocationCapability {
            manager.allowsBackgroundLocationUpdates = true
            manager.showsBackgroundLocationIndicator = true
        }
        manager.startUpdatingLocation()
    }

    func stopTracking() {
        isTracking = false
        if hasBackgroundLocationCapability {
            manager.allowsBackgroundLocationUpdates = false
            manager.showsBackgroundLocationIndicator = false
        }
        manager.stopUpdatingLocation()
    }

    private var hasBackgroundLocationCapability: Bool {
        guard let modes = Bundle.main.infoDictionary?["UIBackgroundModes"] as? [String] else { return false }
        return modes.contains("location")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard isTracking else { return }
            for location in locations {
                guard location.horizontalAccuracy <= 20 else { continue }
                currentLocation = location
                currentSpeed = max(location.speed, 0)
                routeCoordinates.append(location.coordinate)

                if let last = lastLocation {
                    totalDistance += location.distance(from: last)
                }
                lastLocation = location
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
}
