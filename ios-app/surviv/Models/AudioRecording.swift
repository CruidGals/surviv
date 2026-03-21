import Foundation
import SwiftData

enum AudioLabel: String, Codable, CaseIterable {
    case gunfire
    case drone
    case artillery
    case siren
    case explosion
    case background
    case unknown
}

@Model
final class AudioRecording {
    var id: UUID
    var fileName: String
    var fileSize: Int
    var duration: TimeInterval
    var sampleRate: Double
    var latitude: Double
    var longitude: Double
    var label: AudioLabel
    var confidence: Double
    var isExported: Bool
    var timestamp: Date

    /// Raw audio bytes stored in the database for small clips.
    /// For larger files, use `fileURL` to read from disk.
    @Attribute(.externalStorage)
    var audioData: Data?

    var fileURL: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("recordings/\(fileName)")
    }

    init(
        fileName: String,
        fileSize: Int = 0,
        duration: TimeInterval,
        sampleRate: Double = 44100,
        latitude: Double = 0,
        longitude: Double = 0,
        label: AudioLabel = .unknown,
        confidence: Double = 0,
        audioData: Data? = nil
    ) {
        self.id = UUID()
        self.fileName = fileName
        self.fileSize = fileSize
        self.duration = duration
        self.sampleRate = sampleRate
        self.latitude = latitude
        self.longitude = longitude
        self.label = label
        self.confidence = confidence
        self.isExported = false
        self.audioData = audioData
        self.timestamp = .now
    }
}
