import Foundation
import CoreLocation

@Observable
final class LocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()

    /// Set to a coordinate to override GPS in the simulator. Set to nil for real device GPS.
    #if DEBUG
    static let simulatedLocation = CLLocation(latitude: 38.0438, longitude: -78.5095)
    #endif

    var currentLocation: CLLocation?
    var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Bumps on each `didUpdateLocations` so SwiftUI can react before `CLLocation` is `Equatable`.
    private(set) var locationFixCount = 0
    /// Notifies owning `Coordinator` so `ObservableObject` views refresh (nested `@Observable` does not).
    var onLocationFix: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest

        #if DEBUG
        if currentLocation == nil {
            currentLocation = Self.simulatedLocation
            locationFixCount += 1
        }
        #endif
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func startUpdating() {
        manager.startUpdatingLocation()
    }

    func stopUpdating() {
        manager.stopUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        currentLocation = locations.last
        locationFixCount += 1
        onLocationFix?()
    }

    /// Cached fix from `CLLocationManager` or last delegate update (whichever is available).
    func lastKnownMapCoordinate() -> CLLocationCoordinate2D? {
        if let c = currentLocation?.coordinate, CLLocationCoordinate2DIsValid(c) { return c }
        if let c = manager.location?.coordinate, CLLocationCoordinate2DIsValid(c) { return c }
        return nil
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] Error: \(error.localizedDescription)")
    }
}
