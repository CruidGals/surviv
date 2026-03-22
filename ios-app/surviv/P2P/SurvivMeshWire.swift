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
    var createdByUsername: String
    var reasonMessage: String
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
        self.createdByUsername = pin.createdByUsername
        self.reasonMessage = pin.reasonMessage
        self.sourceDeviceID = pin.sourceDeviceID
        self.timestamp = pin.timestamp
        self.hopCount = hopCount
    }

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, pinType, threatSource, radiusMeters, label
        case createdByUsername, reasonMessage
        case sourceDeviceID, timestamp, hopCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        latitude = try c.decode(Double.self, forKey: .latitude)
        longitude = try c.decode(Double.self, forKey: .longitude)
        pinType = try c.decode(PinType.self, forKey: .pinType)
        threatSource = try c.decode(ThreatSource.self, forKey: .threatSource)
        radiusMeters = try c.decode(Double.self, forKey: .radiusMeters)
        label = try c.decode(String.self, forKey: .label)
        createdByUsername = try c.decodeIfPresent(String.self, forKey: .createdByUsername) ?? ""
        reasonMessage = try c.decodeIfPresent(String.self, forKey: .reasonMessage) ?? ""
        sourceDeviceID = try c.decode(String.self, forKey: .sourceDeviceID)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        hopCount = try c.decodeIfPresent(Int.self, forKey: .hopCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(latitude, forKey: .latitude)
        try c.encode(longitude, forKey: .longitude)
        try c.encode(pinType, forKey: .pinType)
        try c.encode(threatSource, forKey: .threatSource)
        try c.encode(radiusMeters, forKey: .radiusMeters)
        try c.encode(label, forKey: .label)
        try c.encode(createdByUsername, forKey: .createdByUsername)
        try c.encode(reasonMessage, forKey: .reasonMessage)
        try c.encode(sourceDeviceID, forKey: .sourceDeviceID)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(hopCount, forKey: .hopCount)
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
            createdByUsername: createdByUsername,
            reasonMessage: reasonMessage,
            sourceDeviceID: sourceDeviceID,
            timestamp: timestamp
        )
    }
}
