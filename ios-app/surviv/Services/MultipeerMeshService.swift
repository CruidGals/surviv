import Foundation

/// Multipeer-backed mesh: JSON ``HazardPinWire`` for pins; ``SurvivPacket`` for admin text (existing path).
final class MultipeerMeshService: MeshService {
    private weak var networker: SurvivNetworker?
    private var pinReceivedCallback: ((HazardPin) -> Void)?
    private var clearByTypeReceivedCallback: ((PinType) -> Void)?
    private var pinDeleteReceivedCallback: ((UUID) -> Void)?

    init(networker: SurvivNetworker) {
        self.networker = networker
        networker.onHazardPinWire = { [weak self] wire in
            let pin = wire.toHazardPin()
            self?.pinReceivedCallback?(pin)
        }
        networker.onClearHazardPinsByType = { [weak self] pinType in
            self?.clearByTypeReceivedCallback?(pinType)
        }
        networker.onHazardPinDelete = { [weak self] pinId in
            self?.pinDeleteReceivedCallback?(pinId)
        }
    }

    func broadcastPin(_ pin: HazardPin) async throws {
        guard let networker else { return }
        let wire = HazardPinWire(from: pin, hopCount: 0)
        let data = try JSONEncoder().encode(wire)
        try networker.broadcastMeshJSON(data)
    }

    func broadcastClearHazardPins(pinType: PinType) async throws {
        guard let networker else { return }
        try networker.broadcastHazardPinsClear(pinType: pinType)
    }

    func broadcastHazardPinDelete(pinId: UUID) async throws {
        guard let networker else { return }
        try networker.broadcastHazardPinDelete(pinId: pinId)
    }

    func onPinReceived(_ callback: @escaping (HazardPin) -> Void) {
        pinReceivedCallback = callback
    }

    func onClearHazardPinsByTypeReceived(_ callback: @escaping (PinType) -> Void) {
        clearByTypeReceivedCallback = callback
    }

    func onHazardPinDeleteReceived(_ callback: @escaping (UUID) -> Void) {
        pinDeleteReceivedCallback = callback
    }

    func startServices() {
        // Browser/advertiser start in SurvivNetworker.init
    }

    func stopServices() {}
}
