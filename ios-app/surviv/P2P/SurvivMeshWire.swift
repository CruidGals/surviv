import Foundation

/// JSON payloads sent over Multipeer (distinct from ``SurvivPacket`` text announcements).
struct HazardPinWire: Codable, Equatable {
    var id: UUID
    var latitude: Double
    var longitude: Double
    var pinType: PinType
    var threatSource: ThreatSource
    var radiusMeters: Double
    var label: String
    var sourceDeviceID: String
    var timestamp: Date
    var hopCount: Int

    init(from pin: HazardPin, hopCount: Int = 0) {
        self.id = pin.id
        self.latitude = pin.latitude
        self.longitude = pin.longitude
        self.pinType = pin.pinType
        self.threatSource = pin.threatSource
        self.radiusMeters = pin.radiusMeters
        self.label = pin.label
        self.sourceDeviceID = pin.sourceDeviceID
        self.timestamp = pin.timestamp
        self.hopCount = hopCount
    }

    func toHazardPin() -> HazardPin {
        HazardPin(
            id: id,
            latitude: latitude,
            longitude: longitude,
            pinType: pinType,
            threatSource: .meshReceived,
            radiusMeters: radiusMeters,
            label: label,
            sourceDeviceID: sourceDeviceID,
            timestamp: timestamp
        )
    }
}
