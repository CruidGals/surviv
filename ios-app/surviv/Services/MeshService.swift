import Foundation

protocol MeshService {
    func broadcastPin(_ pin: HazardPin) async throws
    func onPinReceived(_ callback: @escaping (HazardPin) -> Void)
    func startServices()
    func stopServices()
}
