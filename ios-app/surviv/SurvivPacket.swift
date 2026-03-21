import Foundation

struct SurvivPacket: Codable {
    let id: UUID = UUID()
    let senderName: String
    let message: String
    let timestamp: Date = Date()
    
    // Convert this struct to Data to send over the air
    func encode() -> Data? {
        return try? JSONEncoder().encode(self)
    }
    
    // Convert received Data back into this struct
    static func decode(from data: Data) -> SurvivPacket? {
        return try? JSONDecoder().decode(SurvivPacket.self, from: data)
    }
}