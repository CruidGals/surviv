import Foundation

enum Role: String, Codable {
    case admin
    case scout
}

struct SurvivPacket: Codable, Equatable {
    /// Stable logical id for dedup and relay (must match on every hop).
    let id: UUID
    let senderName: String
    let role: Role
    let message: String
    let timestamp: Date
    var hopCount: Int

    init(senderName: String, role: Role, message: String) {
        self.id = UUID()
        self.senderName = senderName
        self.role = role
        self.message = message
        self.timestamp = Date()
        self.hopCount = 0
    }

    init(id: UUID, senderName: String, role: Role, message: String, timestamp: Date, hopCount: Int) {
        self.id = id
        self.senderName = senderName
        self.role = role
        self.message = message
        self.timestamp = timestamp
        self.hopCount = hopCount
    }

    enum CodingKeys: String, CodingKey {
        case id, senderName, role, message, timestamp, hopCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        senderName = try c.decode(String.self, forKey: .senderName)
        role = try c.decode(Role.self, forKey: .role)
        message = try c.decode(String.self, forKey: .message)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        hopCount = try c.decodeIfPresent(Int.self, forKey: .hopCount) ?? 0
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(senderName, forKey: .senderName)
        try c.encode(role, forKey: .role)
        try c.encode(message, forKey: .message)
        try c.encode(timestamp, forKey: .timestamp)
        try c.encode(hopCount, forKey: .hopCount)
    }

    func encode() -> Data? {
        try? JSONEncoder().encode(self)
    }

    static func decode(from data: Data) -> SurvivPacket? {
        try? JSONDecoder().decode(SurvivPacket.self, from: data)
    }
}
