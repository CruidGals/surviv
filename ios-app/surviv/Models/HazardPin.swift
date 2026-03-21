import Foundation
import SwiftData
import CoreLocation

enum PinType: String, Codable {
    case danger
    case safeRoute
}

enum ThreatSource: String, Codable {
    case manual
    case audioDetection
    case meshReceived
}

@Model
final class HazardPin {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var pinType: PinType
    var threatSource: ThreatSource
    var radiusMeters: Double
    var label: String
    var sourceDeviceID: String
    var timestamp: Date

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(
        latitude: Double,
        longitude: Double,
        pinType: PinType,
        threatSource: ThreatSource = .manual,
        radiusMeters: Double = 120,
        label: String = "",
        sourceDeviceID: String = "",
        timestamp: Date = .now
    ) {
        self.id = UUID()
        self.latitude = latitude
        self.longitude = longitude
        self.pinType = pinType
        self.threatSource = threatSource
        self.radiusMeters = radiusMeters
        self.label = label
        self.sourceDeviceID = sourceDeviceID
        self.timestamp = timestamp
    }
}
