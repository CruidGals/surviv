import Foundation
import AVFoundation
import CoreML

@Observable
final class AudioThreatDetector {
    private var audioEngine: AVAudioEngine?
    private(set) var isListening = false
    private(set) var lastDetectedThreat: String?

    var onThreatDetected: ((String) -> Void)?

    func startListening() throws {
        guard !isListening else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 8192, format: recordingFormat) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }

        engine.prepare()
        try engine.start()

        self.audioEngine = engine
        isListening = true
        print("[AudioThreatDetector] Listening started")
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isListening = false
        print("[AudioThreatDetector] Listening stopped")
    }

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        // TODO: Feed buffer into CoreML model once .mlmodel is provided
        // Pipeline: buffer → MLMultiArray → model.prediction() → check label
        //
        // When the real model is ready, replace this with:
        //   let prediction = try model.prediction(input: ...)
        //   if prediction.label != "background" {
        //       lastDetectedThreat = prediction.label
        //       onThreatDetected?(prediction.label)
        //   }
    }
}
