import Foundation

/// Broadcast to remove every local pin of one type (relayed like ``HazardPinWire``).
struct HazardPinsClearByTypeWire: Codable, Equatable {
    static let meshMessageKindValue = "clearHazardPinsByType"

    let meshMessageKind: String
    let pinType: PinType
    let commandId: UUID
    var hopCount: Int

    enum CodingKeys: String, CodingKey {
        case meshMessageKind, pinType, commandId, hopCount
    }

    init(pinType: PinType, commandId: UUID, hopCount: Int = 0) {
        self.meshMessageKind = Self.meshMessageKindValue
        self.pinType = pinType
        self.commandId = commandId
        self.hopCount = hopCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        meshMessageKind = try c.decode(String.self, forKey: .meshMessageKind)
        let raw = try c.decode(String.self, forKey: .pinType)
        guard let parsed = PinType(rawValue: raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .pinType,
                in: c,
                debugDescription: "Unknown pinType \(raw)"
            )
        }
        pinType = parsed
        commandId = try c.decode(UUID.self, forKey: .commandId)
        hopCount = try c.decodeIfPresent(Int.self, forKey: .hopCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(meshMessageKind, forKey: .meshMessageKind)
        try c.encode(pinType.rawValue, forKey: .pinType)
        try c.encode(commandId, forKey: .commandId)
        try c.encode(hopCount, forKey: .hopCount)
    }
}

/// Broadcast to remove one pin by id on every peer.
struct HazardPinDeleteWire: Codable, Equatable {
    static let meshMessageKindValue = "deleteHazardPin"

    let meshMessageKind: String
    let pinId: UUID
    let commandId: UUID
    var hopCount: Int

    init(pinId: UUID, commandId: UUID, hopCount: Int = 0) {
        self.meshMessageKind = Self.meshMessageKindValue
        self.pinId = pinId
        self.commandId = commandId
        self.hopCount = hopCount
    }
}

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
    var threatClassLabel: String
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
        self.threatClassLabel = pin.threatClassLabel
        self.reasonMessage = pin.reasonMessage
        self.sourceDeviceID = pin.sourceDeviceID
        self.timestamp = pin.timestamp
        self.hopCount = hopCount
    }

    enum CodingKeys: String, CodingKey {
        case id, latitude, longitude, pinType, threatSource, radiusMeters, label
        case createdByUsername, threatClassLabel, reasonMessage
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
        threatClassLabel = try c.decodeIfPresent(String.self, forKey: .threatClassLabel) ?? ""
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
        try c.encode(threatClassLabel, forKey: .threatClassLabel)
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
            threatClassLabel: threatClassLabel,
            reasonMessage: reasonMessage,
            sourceDeviceID: sourceDeviceID,
            timestamp: timestamp
        )
    }
}
