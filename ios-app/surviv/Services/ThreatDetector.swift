import AVFoundation
import CoreML
import Foundation
import SoundAnalysis
import SwiftData

private final class SoundResultsBridge: NSObject, SNResultsObserving {
    var onResult: ((SNClassificationResult) -> Void)?

    func request(_ request: SNRequest, didProduce result: SNResult) {
        guard let classification = result as? SNClassificationResult else { return }
        onResult?(classification)
    }
}

@Observable
final class ThreatDetector {
    private var audioEngine: AVAudioEngine?
    private var streamAnalyzer: SNAudioStreamAnalyzer?
    private let soundBridge = SoundResultsBridge()
    private var coreModel: MLModel?
    private var usesSoundAnalysis = false

    private let processQueue = DispatchQueue(label: "surviv.threat.audio", qos: .userInitiated)
    private var ring: [Float] = []
    private var ringSampleRate: Double = 16_000
    private var targetSamples = 48_000
    private var waveformInputName = "waveform"
    private var lastThreatTime: Date?
    private let threatCooldown: TimeInterval = 25

    private let modelResourceName = "MADMelCNN"

    private let threatLabels: Set<String> = [
        "Shooting", "Shelling", "Helicopter", "Fighter", "Vehicle", "Drone"
    ]

    private let modelContext: ModelContext
    private let locationManager: LocationManager

    private(set) var isListening = false
    private(set) var lastDetectedThreat: String?

    var onThreatDetected: ((String, HazardPin) -> Void)?

    init(modelContext: ModelContext, locationManager: LocationManager) {
        self.modelContext = modelContext
        self.locationManager = locationManager
    }

    func startListening() throws {
        guard !isListening else { return }

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setActive(true)

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let format = inputNode.outputFormat(forBus: 0)

        if let url = Self.compiledModelURL(bundle: .main, name: modelResourceName) {
            let cfg = MLModelConfiguration()
            cfg.computeUnits = .all
            let ml = try MLModel(contentsOf: url, configuration: cfg)
            coreModel = ml
            let description = ml.modelDescription
            resolveModelInterface(from: description)

            let hasMultiArrayInput = description.inputDescriptionsByName.values.contains {
                $0.type == .multiArray && $0.multiArrayConstraint != nil
            }
            if !hasMultiArrayInput, let req = try? SNClassifySoundRequest(mlModel: ml) {
                let analyzer = SNAudioStreamAnalyzer(format: format)
                soundBridge.onResult = { [weak self] result in
                    self?.processQueue.async {
                        self?.handleClassification(result)
                    }
                }
                try analyzer.add(req, withObserver: soundBridge)
                streamAnalyzer = analyzer
                usesSoundAnalysis = true
            }
        } else {
            print("[ThreatDetector] No compiled Core ML model in bundle (expected \(modelResourceName).mlmodelc). Check target membership for the .mlpackage.")
        }

        inputNode.installTap(onBus: 0, bufferSize: 8192, format: format) { [weak self] buffer, time in
            guard let self else { return }
            self.processQueue.async {
                if self.usesSoundAnalysis {
                    self.streamAnalyzer?.analyze(buffer, atAudioFramePosition: time.sampleTime)
                } else {
                    self.appendAndMaybePredict(buffer: buffer, sourceRate: format.sampleRate)
                }
            }
        }

        engine.prepare()
        try engine.start()
        audioEngine = engine
        isListening = true
    }

    func stopListening() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        streamAnalyzer = nil
        processQueue.sync {
            ring.removeAll()
        }
        usesSoundAnalysis = false
        isListening = false
    }

    private static func compiledModelURL(bundle: Bundle, name: String) -> URL? {
        if let u = bundle.url(forResource: name, withExtension: "mlmodelc") {
            return u
        }
        let matches = bundle.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil)
            ?? []
        return matches.first { $0.lastPathComponent == "\(name).mlmodelc" }
    }

    private func resolveModelInterface(from description: MLModelDescription) {
        waveformInputName = "waveform"
        targetSamples = 48_000
        ringSampleRate = 16_000

        if description.inputDescriptionsByName["waveform"] != nil {
            waveformInputName = "waveform"
        } else if let firstMulti = description.inputDescriptionsByName.first(where: { _, d in
            d.type == .multiArray && d.multiArrayConstraint != nil
        }) {
            waveformInputName = firstMulti.key
        }

        if let input = description.inputDescriptionsByName[waveformInputName],
           let constraint = input.multiArrayConstraint {
            let shape = constraint.shape
            if shape.count >= 3 {
                targetSamples = shape[2].intValue
            }
        }

        for (key, value) in description.metadata {
            guard let s = value as? String else { continue }
            switch key.rawValue {
            case "sample_rate":
                if let v = Double(s) { ringSampleRate = v }
            case "target_samples":
                if let v = Int(s) { targetSamples = v }
            default:
                break
            }
        }
    }

    private func handleClassification(_ result: SNClassificationResult) {
        guard let top = result.classifications.first else { return }
        let label = top.identifier
        let conf = Double(top.confidence)
        guard conf >= 0.42, threatLabels.contains(label) else { return }
        emitThreatIfNeeded(label: label)
    }

    private func appendAndMaybePredict(buffer: AVAudioPCMBuffer, sourceRate: Double) {
        guard let model = coreModel else { return }
        guard let samples = Self.floatSamples(from: buffer), !samples.isEmpty else { return }

        let targetRate = ringSampleRate
        if abs(sourceRate - targetRate) < 1 {
            ring.append(contentsOf: samples)
        } else {
            let ratio = targetRate / sourceRate
            var i: Double = 0
            while Int(i) < samples.count {
                ring.append(samples[Int(i)])
                i += 1 / max(ratio, 0.0001)
            }
        }

        let maxKeep = targetSamples * 2
        if ring.count > maxKeep {
            ring.removeFirst(ring.count - maxKeep)
        }
        guard ring.count >= targetSamples else { return }

        let window = Array(ring.suffix(targetSamples))
        let peak = max(window.map { abs($0) }.max() ?? 1, 1e-8)
        let normalized = window.map { $0 / peak }

        guard let input = try? MLMultiArray(shape: [1, 1, NSNumber(value: targetSamples)], dataType: .float32) else { return }
        let ptr = input.dataPointer.bindMemory(to: Float32.self, capacity: targetSamples)
        for i in 0..<targetSamples {
            ptr[i] = Float32(normalized[i])
        }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [waveformInputName: input]),
              let out = try? model.prediction(from: provider) else { return }

        let label = Self.classLabel(from: out) ?? ""
        guard !label.isEmpty, threatLabels.contains(label) else { return }
        emitThreatIfNeeded(label: label)
        ring.removeFirst(min(ring.count, targetSamples / 2))
    }

    private static func classLabel(from output: MLFeatureProvider) -> String? {
        if let s = output.featureValue(for: "classLabel")?.stringValue {
            return s
        }
        if let probs = output.featureValue(for: "classLabelProbs")?.dictionaryValue {
            var bestKey: String?
            var bestScore = -Double.infinity
            for (k, v) in probs {
                let labelKey = (k as? String) ?? String(describing: k)
                let score = (v as? NSNumber)?.doubleValue ?? (v as? Double) ?? 0
                if score > bestScore {
                    bestScore = score
                    bestKey = labelKey
                }
            }
            return bestKey
        }
        for name in output.featureNames {
            if name.lowercased().contains("label"), let s = output.featureValue(for: name)?.stringValue {
                return s
            }
        }
        return nil
    }

    private static func floatSamples(from buffer: AVAudioPCMBuffer) -> [Float]? {
        let n = Int(buffer.frameLength)
        guard n > 0 else { return nil }

        if let ch = buffer.floatChannelData?.pointee {
            return (0..<n).map { ch[$0] }
        }
        if let ch = buffer.int16ChannelData?.pointee {
            return (0..<n).map { Float(ch[$0]) / 32_768.0 }
        }
        return nil
    }

    private func emitThreatIfNeeded(label: String) {
        let now = Date()
        if let last = lastThreatTime, now.timeIntervalSince(last) < threatCooldown { return }
        lastThreatTime = now

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.lastDetectedThreat = label
            let pin = self.createThreatPin(label: label)
            self.onThreatDetected?(label, pin)
        }
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
}
