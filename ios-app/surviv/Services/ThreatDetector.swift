import AVFoundation
import CoreML
import Foundation
import SwiftData

@Observable
final class ThreatDetector {
    // MARK: - Configuration

    private let modelResourceName = "MADMelCNN"

    /// All classes the model considers dangerous.
    private let threatLabels: Set<String> = [
        "Shooting", "Shelling", "Helicopter", "Fighter", "Vehicle", "Drone"
    ]

    /// Combined probability of *all* threat classes must reach this to fire.
    private let dangerThreshold: Double = 0.75

    /// Seconds between listen bursts when no danger was detected.
    private let normalInterval: TimeInterval = 5

    /// Seconds of mic capture per burst (should match the model's window).
    private let burstDuration: TimeInterval = 3

    /// After a danger pin is emitted, wait this long before listening again.
    private let dangerCooldown: TimeInterval = 60

    // MARK: - Runtime state

    private var coreModel: MLModel?
    private var ringSampleRate: Double = 16_000
    private var targetSamples = 48_000
    private var waveformInputName = "waveform"

    private let processQueue = DispatchQueue(label: "surviv.threat.audio", qos: .userInitiated)
    private var dutyTask: Task<Void, Never>?
    private var lastDangerTime: Date?

    private let modelContext: ModelContext
    private let locationManager: LocationManager

    private(set) var isListening = false
    private(set) var lastDetectedThreat: String?

    var onThreatDetected: ((String, HazardPin) -> Void)?

    // MARK: - Init

    init(modelContext: ModelContext, locationManager: LocationManager) {
        self.modelContext = modelContext
        self.locationManager = locationManager
    }

    // MARK: - Public API

    func startListening() throws {
        guard !isListening else { return }
        try loadModelIfNeeded()
        isListening = true
        dutyTask = Task { [weak self] in await self?.dutyCycleLoop() }
    }

    func stopListening() {
        dutyTask?.cancel()
        dutyTask = nil
        isListening = false
    }

    // MARK: - Model loading (one-time)

    private func loadModelIfNeeded() throws {
        guard coreModel == nil else { return }
        guard let url = Self.compiledModelURL(bundle: .main, name: modelResourceName) else {
            print("[ThreatDetector] No compiled Core ML model in bundle (expected \(modelResourceName).mlmodelc).")
            return
        }
        let cfg = MLModelConfiguration()
        cfg.computeUnits = .all
        let ml = try MLModel(contentsOf: url, configuration: cfg)
        coreModel = ml
        resolveModelInterface(from: ml.modelDescription)
    }

    private static func compiledModelURL(bundle: Bundle, name: String) -> URL? {
        if let u = bundle.url(forResource: name, withExtension: "mlmodelc") {
            return u
        }
        return (bundle.urls(forResourcesWithExtension: "mlmodelc", subdirectory: nil) ?? [])
            .first { $0.lastPathComponent == "\(name).mlmodelc" }
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
            if shape.count >= 3 { targetSamples = shape[2].intValue }
        }

        for (key, value) in description.metadata {
            guard let s = value as? String else { continue }
            switch key.rawValue {
            case "sample_rate":  if let v = Double(s) { ringSampleRate = v }
            case "target_samples": if let v = Int(s) { targetSamples = v }
            default: break
            }
        }
    }

    // MARK: - Duty-cycle loop

    private func dutyCycleLoop() async {
        while !Task.isCancelled && isListening {
            // Choose sleep interval: longer after a recent danger emission
            let sleepSec: TimeInterval
            if let last = lastDangerTime, Date().timeIntervalSince(last) < dangerCooldown {
                let remaining = dangerCooldown - Date().timeIntervalSince(last)
                sleepSec = remaining
            } else {
                sleepSec = normalInterval
            }

            do {
                try await Task.sleep(nanoseconds: UInt64(sleepSec * 1_000_000_000))
            } catch { break }

            guard !Task.isCancelled else { break }

            let samples = await captureBurst()
            guard !samples.isEmpty else { continue }

            let result = processQueue.sync { runInference(samples: samples) }
            guard let (conf, contributor) = result else { continue }

            if conf >= dangerThreshold {
                await emitDanger(combinedConfidence: conf, topContributor: contributor)
            }
        }
    }

    // MARK: - Short burst capture

    /// Record `burstDuration` seconds of mono audio, then tear down the engine immediately.
    private func captureBurst() async -> [Float] {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .mixWithOthers])
            try session.setActive(true)
        } catch {
            print("[ThreatDetector] AVAudioSession setup failed: \(error)")
            return []
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let hwFormat = inputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else { return [] }

        let captured = UnsafeMutableBufferCapture()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: hwFormat) { buffer, _ in
            guard let ch = buffer.floatChannelData?.pointee else { return }
            let n = Int(buffer.frameLength)
            captured.lock.lock()
            for i in 0..<n { captured.samples.append(ch[i]) }
            captured.lock.unlock()
        }

        engine.prepare()
        do { try engine.start() } catch {
            print("[ThreatDetector] Engine start failed: \(error)")
            return []
        }

        do {
            try await Task.sleep(nanoseconds: UInt64(burstDuration * 1_000_000_000))
        } catch {
            // Cancelled
        }

        inputNode.removeTap(onBus: 0)
        engine.stop()
        try? session.setActive(false, options: .notifyOthersOnDeactivation)

        captured.lock.lock()
        let raw = captured.samples
        captured.lock.unlock()

        return resampleToModel(raw, sourceRate: hwFormat.sampleRate)
    }

    /// Naive linear resample from hardware rate to model's expected rate.
    private func resampleToModel(_ samples: [Float], sourceRate: Double) -> [Float] {
        let targetRate = ringSampleRate
        guard !samples.isEmpty else { return [] }
        if abs(sourceRate - targetRate) < 1 { return samples }

        let ratio = targetRate / sourceRate
        let outCount = Int(Double(samples.count) * ratio)
        var out = [Float]()
        out.reserveCapacity(outCount)
        var idx: Double = 0
        while Int(idx) < samples.count {
            out.append(samples[Int(idx)])
            idx += 1 / max(ratio, 0.0001)
        }
        return out
    }

    // MARK: - Inference

    private func runInference(samples: [Float]) -> (Double, String)? {
        guard let model = coreModel else { return nil }

        let n = targetSamples
        var window: [Float]
        if samples.count >= n {
            let start = (samples.count - n) / 2
            window = Array(samples[start..<(start + n)])
        } else {
            window = samples + [Float](repeating: 0, count: n - samples.count)
        }

        let peak = max(window.map { abs($0) }.max() ?? 1, 1e-8)
        window = window.map { $0 / peak }

        guard let input = try? MLMultiArray(shape: [1, 1, NSNumber(value: n)], dataType: .float32) else { return nil }
        let ptr = input.dataPointer.bindMemory(to: Float32.self, capacity: n)
        for i in 0..<n { ptr[i] = Float32(window[i]) }

        guard let provider = try? MLDictionaryFeatureProvider(dictionary: [waveformInputName: input]),
              let out = try? model.prediction(from: provider) else { return nil }

        return Self.aggregateThreatConfidence(from: out, threatLabels: threatLabels)
    }

    /// Sum probabilities of all threat classes from model output.
    private static func aggregateThreatConfidence(
        from output: MLFeatureProvider,
        threatLabels: Set<String>
    ) -> (Double, String)? {
        if let probs = output.featureValue(for: "classLabelProbs")?.dictionaryValue {
            var combined: Double = 0
            var topLabel: String?
            var topScore: Double = 0
            for (k, v) in probs {
                let label = (k as? String) ?? String(describing: k)
                let score = (v as? NSNumber)?.doubleValue ?? (v as? Double) ?? 0
                guard threatLabels.contains(label) else { continue }
                combined += score
                if score > topScore { topScore = score; topLabel = label }
            }
            guard let best = topLabel else { return nil }
            return (combined, best)
        }
        if let label = output.featureValue(for: "classLabel")?.stringValue, threatLabels.contains(label) {
            return (1.0, label)
        }
        return nil
    }

    // MARK: - Emission

    @MainActor
    private func emitDanger(combinedConfidence: Double, topContributor: String) {
        let now = Date()
        if let last = lastDangerTime, now.timeIntervalSince(last) < dangerCooldown { return }
        lastDangerTime = now

        let pct = Int(round(combinedConfidence * 100))
        let displayLabel = "Danger — \(topContributor) (\(pct)%)"
        lastDetectedThreat = displayLabel
        let pin = createDangerPin(displayLabel: displayLabel)
        onThreatDetected?(displayLabel, pin)
    }

    @MainActor
    func createDangerPin(displayLabel: String) -> HazardPin {
        let lat = locationManager.currentLocation?.coordinate.latitude ?? 0
        let lon = locationManager.currentLocation?.coordinate.longitude ?? 0

        let pin = HazardPin(
            latitude: lat,
            longitude: lon,
            pinType: .danger,
            threatSource: .audioDetection,
            label: displayLabel
        )
        modelContext.insert(pin)
        try? modelContext.save()
        return pin
    }
}

/// Thread-safe accumulator for mic tap samples.
private final class UnsafeMutableBufferCapture {
    let lock = NSLock()
    var samples: [Float] = []
}
