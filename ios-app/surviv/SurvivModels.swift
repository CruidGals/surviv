import Foundation
import CoreLocation

enum HazardCategory: String, CaseIterable, Identifiable {
    case drone = "Drone"
    case roadblock = "Roadblock"
    case troops = "Troops"

    var id: String { rawValue }
}

enum ZoneKind: String, CaseIterable, Identifiable {
    case danger = "Danger"
    case safeRoute = "Safe Route"

    var id: String { rawValue }
}

struct ZoneItem: Identifiable {
    let id = UUID()
    let kind: ZoneKind
    let center: CLLocationCoordinate2D
    let radiusMeters: CLLocationDistance
    let createdAt: Date
}

struct ThreatQueueItem: Identifiable {
    let id = UUID()
    let type: String
    let timeLabel: String
    let distanceLabel: String
}
