import AVFoundation
import Foundation
import SwiftData
import Combine
import CoreLocation

@MainActor
final class Coordinator: ObservableObject {
    let locationManager: LocationManager
    let audioDetector: ThreatDetector
    let meshService: MultipeerMeshService

    private let modelContext: ModelContext

    @Published var threatAlert: String?
    /// Bumps when `LocationManager` reports a new fix; drives map `onChange` for `ObservableObject` views.
    @Published private(set) var locationRevision = 0

    init(modelContainer: ModelContainer, networker: SurvivNetworker) {
        let context = ModelContext(modelContainer)
        self.modelContext = context
        self.locationManager = LocationManager()
        self.audioDetector = ThreatDetector(modelContext: context, locationManager: locationManager)
        self.meshService = MultipeerMeshService(networker: networker)

        locationManager.onLocationFix = { [weak self] in
            self?.locationRevision += 1
        }

        wireUp()
    }

    private func wireUp() {
        audioDetector.onThreatDetected = { [weak self] label, pin in
            guard let self else { return }
            self.threatAlert = label
            Task { try? await self.meshService.broadcastPin(pin) }
        }

        meshService.onPinReceived { [weak self] pin in
            guard let self else { return }
            if self.hasHazardPin(id: pin.id) { return }
            self.modelContext.insert(pin)
            try? self.modelContext.save()
        }
    }

    private func hasHazardPin(id: UUID) -> Bool {
        var descriptor = FetchDescriptor<HazardPin>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor))?.isEmpty == false)
    }

    func dropHazardPin(at coordinate: CLLocationCoordinate2D, pinType: PinType, radiusMeters: Double = 120) {
        let pin = HazardPin(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pinType: pinType,
            threatSource: .manual,
            radiusMeters: radiusMeters
        )
        modelContext.insert(pin)
        try? modelContext.save()
        broadcastPin(pin)
    }

    func start() {
        locationManager.requestPermission()
        locationManager.startUpdating()
        meshService.startServices()
        Task { @MainActor in
            let micOK = await Self.requestMicrophoneAccess()
            guard micOK else { return }
            try? audioDetector.startListening()
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { cont in
                    AVAudioApplication.requestRecordPermission { granted in
                        cont.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        } else {
            let session = AVAudioSession.sharedInstance()
            switch session.recordPermission {
            case .granted:
                return true
            case .denied:
                return false
            case .undetermined:
                return await withCheckedContinuation { cont in
                    session.requestRecordPermission { granted in
                        cont.resume(returning: granted)
                    }
                }
            @unknown default:
                return false
            }
        }
    }

    func broadcastPin(_ pin: HazardPin) {
        Task { try? await meshService.broadcastPin(pin) }
    }

    func dismissThreatAlert() {
        threatAlert = nil
    }
}
