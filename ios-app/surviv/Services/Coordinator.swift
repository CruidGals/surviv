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
    private let networker: SurvivNetworker

    private let modelContext: ModelContext

    @Published var threatAlert: String?
    /// Bumps when `LocationManager` reports a new fix; drives map `onChange` for `ObservableObject` views.
    @Published private(set) var locationRevision = 0

    init(modelContainer: ModelContainer, networker: SurvivNetworker) {
        // Same context SwiftUI `@Query` uses so deletes/saves refresh the map immediately.
        self.modelContext = modelContainer.mainContext
        self.networker = networker
        self.locationManager = LocationManager()
        self.audioDetector = ThreatDetector(modelContext: modelContainer.mainContext, locationManager: locationManager)
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
            Task { @MainActor in
                try? await self.meshService.broadcastPin(pin)
            }
        }

        meshService.onPinReceived { [weak self] pin in
            guard let self else { return }
            if self.hasHazardPin(id: pin.id) { return }
            self.modelContext.insert(pin)
            try? self.modelContext.save()
        }

        meshService.onClearHazardPinsByTypeReceived { [weak self] pinType in
            self?.deleteHazardPinsLocally(wherePinType: pinType)
        }

        meshService.onHazardPinDeleteReceived { [weak self] pinId in
            self?.deleteHazardPinLocally(id: pinId)
        }

        networker.onMeshBecameReachable = { [weak self] in
            self?.broadcastAllLocalPinsToMesh()
        }
    }

    /// Removes every local pin of one type only (no mesh).
    private func deleteHazardPinsLocally(wherePinType pinType: PinType) {
        let descriptor = FetchDescriptor<HazardPin>()
        guard let all = try? modelContext.fetch(descriptor) else { return }
        let toRemove = all.filter { $0.pinType == pinType }
        guard !toRemove.isEmpty else { return }
        for pin in toRemove {
            modelContext.delete(pin)
        }
        try? modelContext.save()
    }

    private func deleteHazardPinLocally(id: UUID) {
        var descriptor = FetchDescriptor<HazardPin>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let pin = try? modelContext.fetch(descriptor).first else { return }
        modelContext.delete(pin)
        try? modelContext.save()
    }

    /// Remove all local pins of `pinType` and tell peers to do the same.
    func clearHazardPinsByTypeAndBroadcast(_ pinType: PinType) {
        deleteHazardPinsLocally(wherePinType: pinType)
        Task { @MainActor in
            try? await meshService.broadcastClearHazardPins(pinType: pinType)
        }
    }

    /// Remove one pin locally and broadcast deletion to the mesh.
    func deleteHazardPinAndBroadcast(id: UUID) {
        deleteHazardPinLocally(id: id)
        Task { @MainActor in
            try? await meshService.broadcastHazardPinDelete(pinId: id)
        }
    }

    /// Re-announce every local pin so late joiners converge with the mesh.
    private func broadcastAllLocalPinsToMesh() {
        let descriptor = FetchDescriptor<HazardPin>()
        guard let pins = try? modelContext.fetch(descriptor) else { return }
        for pin in pins {
            broadcastPin(pin)
        }
    }

    private func hasHazardPin(id: UUID) -> Bool {
        var descriptor = FetchDescriptor<HazardPin>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return ((try? modelContext.fetch(descriptor))?.isEmpty == false)
    }

    func dropHazardPin(
        at coordinate: CLLocationCoordinate2D,
        pinType: PinType,
        radiusMeters: Double = 120,
        threatClassLabel: String,
        reasonMessage: String,
        label: String
    ) {
        let pinId = UUID()
        let pin = HazardPin(
            id: pinId,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            pinType: pinType,
            threatSource: .manual,
            radiusMeters: radiusMeters,
            label: label,
            createdByUsername: SurvivProfile.displayName,
            threatClassLabel: threatClassLabel,
            reasonMessage: reasonMessage
        )
        modelContext.insert(pin)
        try? modelContext.save()
        broadcastPin(pin)
    }

    func start() {
        locationManager.requestPermission()
        locationManager.startUpdating()
        meshService.startServices()
        // `ContentView` / admin map may have run `onAppear` before a cached fix existed; nudge observers once.
        if locationManager.lastKnownMapCoordinate() != nil {
            locationRevision += 1
        }
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
        Task { @MainActor in
            try? await meshService.broadcastPin(pin)
        }
    }

    func dismissThreatAlert() {
        threatAlert = nil
    }
}
