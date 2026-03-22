import Foundation

final class MockMeshService: MeshService {
    private var pinReceivedCallback: ((HazardPin) -> Void)?
    private var clearByTypeReceivedCallback: ((PinType) -> Void)?
    private var pinDeleteReceivedCallback: ((UUID) -> Void)?

    func broadcastPin(_ pin: HazardPin) async throws {
        print("[MockMesh] Broadcasting pin: \(pin.pinType.rawValue) at (\(pin.latitude), \(pin.longitude))")
    }

    func broadcastClearHazardPins(pinType: PinType) async throws {
        print("[MockMesh] Broadcast clear hazard pins: \(pinType.rawValue)")
    }

    func broadcastHazardPinDelete(pinId: UUID) async throws {
        print("[MockMesh] Broadcast delete pin \(pinId)")
    }

    func onPinReceived(_ callback: @escaping (HazardPin) -> Void) {
        self.pinReceivedCallback = callback
    }

    func onClearHazardPinsByTypeReceived(_ callback: @escaping (PinType) -> Void) {
        clearByTypeReceivedCallback = callback
    }

    func onHazardPinDeleteReceived(_ callback: @escaping (UUID) -> Void) {
        pinDeleteReceivedCallback = callback
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
