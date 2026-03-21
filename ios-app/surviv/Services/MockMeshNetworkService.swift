import Foundation
import SwiftData

final class MockMeshNetworkService: MeshNetworkService {
    private var pinReceivedCallback: ((HazardPin) -> Void)?
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func broadcastPin(_ pin: HazardPin) async throws {
        print("[MockMesh] Broadcasting pin: \(pin.pinType.rawValue) at (\(pin.latitude), \(pin.longitude))")
    }

    func onPinReceived(_ callback: @escaping (HazardPin) -> Void) {
        self.pinReceivedCallback = callback
    }

    func startServices() {
        print("[MockMesh] Mesh network started (mock)")
    }

    func stopServices() {
        print("[MockMesh] Mesh network stopped (mock)")
    }

    /// Simulate receiving a pin from the mesh — useful for testing
    func simulateIncomingPin(_ pin: HazardPin) {
        modelContext.insert(pin)
        pinReceivedCallback?(pin)
        print("[MockMesh] Simulated incoming pin: \(pin.pinType.rawValue)")
    }
}
