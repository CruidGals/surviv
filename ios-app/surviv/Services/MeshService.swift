import Foundation

protocol MeshService {
    func broadcastPin(_ pin: HazardPin) async throws
    func broadcastClearHazardPins(pinType: PinType) async throws
    func broadcastHazardPinDelete(pinId: UUID) async throws
    func onPinReceived(_ callback: @escaping (HazardPin) -> Void)
    func onClearHazardPinsByTypeReceived(_ callback: @escaping (PinType) -> Void)
    func onHazardPinDeleteReceived(_ callback: @escaping (UUID) -> Void)
    func startServices()
    func stopServices()
}
