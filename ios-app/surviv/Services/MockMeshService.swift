import Foundation

final class MockMeshService: MeshService {
    private var pinReceivedCallback: ((HazardPin) -> Void)?

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

    func simulateIncomingPin(_ pin: HazardPin) {
        pinReceivedCallback?(pin)
        print("[MockMesh] Simulated incoming pin: \(pin.pinType.rawValue)")
    }
}
