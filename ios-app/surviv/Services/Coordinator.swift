import Foundation
import SwiftData
import Combine

@MainActor
final class Coordinator: ObservableObject {
    let locationManager: LocationManager
    let audioDetector: ThreatDetector
    let meshService: MockMeshService

    private let modelContext: ModelContext

    @Published var threatAlert: String?

    init(modelContainer: ModelContainer) {
        let context = ModelContext(modelContainer)
        self.modelContext = context
        self.locationManager = LocationManager()
        self.audioDetector = ThreatDetector(modelContext: context, locationManager: locationManager)
        self.meshService = MockMeshService()

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
            self.modelContext.insert(pin)
            try? self.modelContext.save()
        }
    }

    func start() {
        locationManager.requestPermission()
        locationManager.startUpdating()
        meshService.startServices()
    }

    func broadcastPin(_ pin: HazardPin) {
        Task { try? await meshService.broadcastPin(pin) }
    }

    func dismissThreatAlert() {
        threatAlert = nil
    }
}
