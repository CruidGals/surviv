import Foundation

/// Multipeer-backed mesh: JSON ``HazardPinWire`` for pins; ``SurvivPacket`` for admin text (existing path).
final class MultipeerMeshService: MeshService {
    private weak var networker: SurvivNetworker?
    private var pinReceivedCallback: ((HazardPin) -> Void)?

    init(networker: SurvivNetworker) {
        self.networker = networker
        networker.onHazardPinWire = { [weak self] wire in
            let pin = wire.toHazardPin()
            self?.pinReceivedCallback?(pin)
        }
    }

    func broadcastPin(_ pin: HazardPin) async throws {
        guard let networker else { return }
        let wire = HazardPinWire(from: pin, hopCount: 0)
        let data = try JSONEncoder().encode(wire)
        try networker.broadcastMeshJSON(data)
    }

    func onPinReceived(_ callback: @escaping (HazardPin) -> Void) {
        pinReceivedCallback = callback
    }

    func startServices() {
        // Browser/advertiser start in SurvivNetworker.init
    }

    func stopServices() {}
}
