import Foundation
import AVFoundation
import CoreML
import SwiftData

@Observable
final class AudioThreatDetector {
    private var audioEngine: AVAudioEngine?
    private var audioFile: AVAudioFile?
    private var recordingStartTime: Date?
    private var currentFileName: String?

    private let modelContext: ModelContext
    private let locationManager: LocationManager

    private(set) var isListening = false
    private(set) var lastDetectedThreat: String?

    var onThreatDetected: ((String, HazardPin) -> Void)?

    init(modelContext: ModelContext, locationManager: LocationManager) {
        self.modelContext = modelContext
        self.locationManager = locationManager
        ensureRecordingsDirectory()
    }

    func startListening() throws {
        guard !isListening else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement)
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        let fileName = "rec_\(UUID().uuidString).wav"
        let fileURL = recordingsDirectory.appendingPathComponent(fileName)
        let file = try AVAudioFile(forWriting: fileURL, settings: recordingFormat.settings)

        self.audioFile = file
        self.currentFileName = fileName
        self.recordingStartTime = .now

        inputNode.installTap(onBus: 0, bufferSize: 8192, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        isListening = true
        print("[AudioThreatDetector] Listening started — writing to \(fileName)")
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil

        if let fileName = currentFileName, let startTime = recordingStartTime {
            saveRecording(fileName: fileName, startTime: startTime)
        }

        audioFile = nil
        currentFileName = nil
        recordingStartTime = nil
        isListening = false
        print("[AudioThreatDetector] Listening stopped")
    }

    // MARK: - Processing

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        try? audioFile?.write(from: buffer)

        // TODO: Feed buffer into CoreML model once .mlmodel is provided
        // Pipeline: buffer → MLMultiArray → model.prediction() → check label
        //
        // When the real model is ready, replace this with:
        //   let prediction = try model.prediction(input: ...)
        //   if prediction.label != "background" {
        //       lastDetectedThreat = prediction.label
        //       let pin = createThreatPin(label: prediction.label)
        //       onThreatDetected?(prediction.label, pin)
        //   }
    }

    // MARK: - Database

    private func saveRecording(fileName: String, startTime: Date) {
        let duration = Date.now.timeIntervalSince(startTime)
        let lat = locationManager.currentLocation?.coordinate.latitude ?? 0
        let lon = locationManager.currentLocation?.coordinate.longitude ?? 0

        let fileURL = recordingsDirectory.appendingPathComponent(fileName)
        let fileSize = (try? FileManager.default.attributesOfItem(atPath: fileURL.path)[.size] as? Int) ?? 0

        let recording = AudioRecording(
            fileName: fileName,
            fileSize: fileSize,
            duration: duration,
            latitude: lat,
            longitude: lon
        )
        modelContext.insert(recording)
        try? modelContext.save()
        print("[AudioThreatDetector] Saved recording: \(fileName) (\(String(format: "%.1f", duration))s)")
    }

    func createThreatPin(label: String) -> HazardPin {
        let lat = locationManager.currentLocation?.coordinate.latitude ?? 0
        let lon = locationManager.currentLocation?.coordinate.longitude ?? 0

        let pin = HazardPin(
            latitude: lat,
            longitude: lon,
            pinType: .danger,
            threatSource: .audioDetection,
            label: label
        )
        modelContext.insert(pin)
        try? modelContext.save()
        return pin
    }

    // MARK: - File Management

    private var recordingsDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return docs.appendingPathComponent("recordings")
    }

    private func ensureRecordingsDirectory() {
        let dir = recordingsDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
