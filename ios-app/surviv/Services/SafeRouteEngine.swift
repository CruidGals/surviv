import Foundation
import CoreLocation
import MapKit

/// Computes and dynamically updates the optimal walking route from the
/// user's current location to the nearest safe-zone pin, while avoiding
/// known danger zones.
///
/// Future work:
///   - Find nearest `.safeRoute` HazardPin from user location
///   - Build an MKDirections request that avoids danger-zone radii
///   - Re-compute when user location changes or pins are added/removed
///   - Expose a published route polyline for the map layer to render
final class SafeRouteEngine: ObservableObject {

}
