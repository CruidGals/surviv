import MultipeerConnectivity
import Combine

class SurvivNetworker: NSObject, ObservableObject {
    private let serviceType = "surviv"
    private let profileDisplayNameKey = "profile.displayName"
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)

    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!

    private let pendingMeshLock = NSLock()
    private var pendingMeshPayloads: [Data] = []
    private var pendingAdminPayloads: [Data] = []
    private var hadConnectedPeers = false
    private static let maxPendingMeshPayloads = 64
    private static let maxPendingAdminPayloads = 32

    @Published var connectedPeers: [MCPeerID] = []
    @Published var incomingMessages: [SurvivPacket] = []
    @Published var userRole: Role = .scout
    /// Latest high-priority admin text for UI banners (deduped by packet id).
    @Published var latestAdminAnnouncement: SurvivPacket?

    var onHazardPinWire: ((HazardPinWire) -> Void)?
    var onClearHazardPinsByType: ((PinType) -> Void)?
    var onHazardPinDelete: ((UUID) -> Void)?
    /// Fires when at least one peer is connected after having none (mesh usable again).
    var onMeshBecameReachable: (() -> Void)?

    /// Dedup must run synchronously when data arrives: multiple `didReceive` callbacks can enqueue main work before `@Published` updates, so async-only dedup allowed duplicate relays and UI rows.
    private let meshDedupLock = NSLock()
    private var seenSurvivPacketIds = Set<UUID>()
    private var seenPinWireIds = Set<UUID>()
    private var seenClearByTypeCommandIds = Set<UUID>()
    private var seenPinDeleteCommandIds = Set<UUID>()

    @discardableResult
    private func claimSurvivPacketIdIfNew(_ id: UUID) -> Bool {
        meshDedupLock.lock()
        defer { meshDedupLock.unlock() }
        guard !seenSurvivPacketIds.contains(id) else { return false }
        seenSurvivPacketIds.insert(id)
        return true
    }

    @discardableResult
    private func claimPinWireIdIfNew(_ id: UUID) -> Bool {
        meshDedupLock.lock()
        defer { meshDedupLock.unlock() }
        guard !seenPinWireIds.contains(id) else { return false }
        seenPinWireIds.insert(id)
        return true
    }

    @discardableResult
    private func claimClearByTypeCommandIdIfNew(_ id: UUID) -> Bool {
        meshDedupLock.lock()
        defer { meshDedupLock.unlock() }
        guard !seenClearByTypeCommandIds.contains(id) else { return false }
        seenClearByTypeCommandIds.insert(id)
        return true
    }

    @discardableResult
    private func claimPinDeleteCommandIdIfNew(_ id: UUID) -> Bool {
        meshDedupLock.lock()
        defer { meshDedupLock.unlock() }
        guard !seenPinDeleteCommandIds.contains(id) else { return false }
        seenPinDeleteCommandIds.insert(id)
        return true
    }

    private func appendIncomingAdminBroadcast(_ packet: SurvivPacket) {
        guard !incomingMessages.contains(where: { $0.id == packet.id }) else { return }
        incomingMessages = incomingMessages + [packet]
        latestAdminAnnouncement = packet
    }

    func applyAppAdminState(_ isAdmin: Bool) {
        userRole = isAdmin ? .admin : .scout
    }

    func dismissAnnouncementBanner() {
        latestAdminAnnouncement = nil
    }

    func promoteToAdmin(secret: String) {
        if secret == "Surviv" {
            userRole = .admin
        }
    }

    override init() {
        super.init()

        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .optional)
        session.delegate = self

        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()

        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }

    func broadcast(message: String) {
        guard userRole == .admin else {
            print("Access denied: You are not an admin")
            return
        }

        let packet = SurvivPacket(senderName: resolvedSenderName(), role: .admin, message: message)
        guard let data = packet.encode() else { return }

        guard claimSurvivPacketIdIfNew(packet.id) else { return }

        let applyLocal: () -> Void = { [weak self] in
            guard let self else { return }
            self.appendIncomingAdminBroadcast(packet)
        }

        if Thread.isMainThread {
            applyLocal()
        } else {
            DispatchQueue.main.async(execute: applyLocal)
        }

        let peers = session.connectedPeers
        if peers.isEmpty {
            pendingMeshLock.lock()
            if pendingAdminPayloads.count < Self.maxPendingAdminPayloads {
                pendingAdminPayloads.append(data)
            }
            pendingMeshLock.unlock()
            return
        }

        do {
            try session.send(data, toPeers: peers, with: .reliable)
        } catch {
            print("Error sending: \(error.localizedDescription)")
        }
    }

    /// Originator: claim `commandId` before sending so relayed copies are ignored.
    func broadcastHazardPinsClear(pinType: PinType) throws {
        let commandId = UUID()
        guard claimClearByTypeCommandIdIfNew(commandId) else { return }
        let wire = HazardPinsClearByTypeWire(pinType: pinType, commandId: commandId, hopCount: 0)
        let data = try JSONEncoder().encode(wire)
        try broadcastMeshJSON(data)
    }

    func broadcastHazardPinDelete(pinId: UUID) throws {
        let commandId = UUID()
        guard claimPinDeleteCommandIdIfNew(commandId) else { return }
        let wire = HazardPinDeleteWire(pinId: pinId, commandId: commandId, hopCount: 0)
        let data = try JSONEncoder().encode(wire)
        try broadcastMeshJSON(data)
    }

    /// Civilians and admins: broadcast encoded JSON (e.g. ``HazardPinWire``). No role gate.
    /// Queues payloads when offline; flushes when the first peer connects.
    func broadcastMeshJSON(_ data: Data) throws {
        pendingMeshLock.lock()
        if session.connectedPeers.isEmpty {
            if pendingMeshPayloads.count < Self.maxPendingMeshPayloads {
                pendingMeshPayloads.append(data)
            }
            pendingMeshLock.unlock()
            return
        }
        pendingMeshLock.unlock()
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    private func flushPendingMeshPayloadsIfNeeded() {
        pendingMeshLock.lock()
        let batch = pendingMeshPayloads
        pendingMeshPayloads.removeAll()
        let adminBatch = pendingAdminPayloads
        pendingAdminPayloads.removeAll()
        pendingMeshLock.unlock()
        let peers = session.connectedPeers
        guard !peers.isEmpty else {
            pendingMeshLock.lock()
            if !batch.isEmpty {
                pendingMeshPayloads = batch + pendingMeshPayloads
            }
            if !adminBatch.isEmpty {
                pendingAdminPayloads = adminBatch + pendingAdminPayloads
            }
            pendingMeshLock.unlock()
            return
        }
        for data in batch {
            try? session.send(data, toPeers: peers, with: .reliable)
        }
        for data in adminBatch {
            try? session.send(data, toPeers: peers, with: .reliable)
        }
    }

    func send(packet: SurvivPacket, toPeers peers: [MCPeerID]) {
        guard !peers.isEmpty, let data = packet.encode() else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }

    private func resolvedSenderName() -> String {
        let stored = UserDefaults.standard.string(forKey: profileDisplayNameKey) ?? ""
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? myPeerID.displayName : trimmed
    }
}

extension SurvivNetworker: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            let peers = session.connectedPeers
            let nowConnected = !peers.isEmpty
            if nowConnected, !self.hadConnectedPeers {
                self.hadConnectedPeers = true
                self.flushPendingMeshPayloadsIfNeeded()
                self.onMeshBecameReachable?()
            } else if !nowConnected {
                self.hadConnectedPeers = false
            }
            self.connectedPeers = peers
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Resolve admin text packets first (distinct JSON shape from ``HazardPinWire``).
        if let packet = SurvivPacket.decode(from: data) {
            guard claimSurvivPacketIdIfNew(packet.id) else { return }

            DispatchQueue.main.async {
                if packet.role == .admin {
                    self.appendIncomingAdminBroadcast(packet)

                    let otherPeers = self.session.connectedPeers.filter { $0 != peerID }
                    if !otherPeers.isEmpty && packet.hopCount < 10 {
                        var relayPacket = packet
                        relayPacket.hopCount += 1
                        self.send(packet: relayPacket, toPeers: otherPeers)
                    }
                }
            }
            return
        }

        if let clearWire = try? JSONDecoder().decode(HazardPinsClearByTypeWire.self, from: data),
           clearWire.meshMessageKind == HazardPinsClearByTypeWire.meshMessageKindValue {
            guard claimClearByTypeCommandIdIfNew(clearWire.commandId) else { return }

            DispatchQueue.main.async {
                self.onClearHazardPinsByType?(clearWire.pinType)

                let otherPeers = session.connectedPeers.filter { $0 != peerID }
                if !otherPeers.isEmpty && clearWire.hopCount < 10 {
                    var relay = clearWire
                    relay.hopCount += 1
                    if let relayData = try? JSONEncoder().encode(relay) {
                        try? session.send(relayData, toPeers: otherPeers, with: .reliable)
                    }
                }
            }
            return
        }

        if let delWire = try? JSONDecoder().decode(HazardPinDeleteWire.self, from: data),
           delWire.meshMessageKind == HazardPinDeleteWire.meshMessageKindValue {
            guard claimPinDeleteCommandIdIfNew(delWire.commandId) else { return }

            DispatchQueue.main.async {
                self.onHazardPinDelete?(delWire.pinId)

                let otherPeers = session.connectedPeers.filter { $0 != peerID }
                if !otherPeers.isEmpty && delWire.hopCount < 10 {
                    var relay = delWire
                    relay.hopCount += 1
                    if let relayData = try? JSONEncoder().encode(relay) {
                        try? session.send(relayData, toPeers: otherPeers, with: .reliable)
                    }
                }
            }
            return
        }

        if let pinWire = try? JSONDecoder().decode(HazardPinWire.self, from: data) {
            guard claimPinWireIdIfNew(pinWire.id) else { return }

            DispatchQueue.main.async {
                self.onHazardPinWire?(pinWire)

                let otherPeers = session.connectedPeers.filter { $0 != peerID }
                if !otherPeers.isEmpty && pinWire.hopCount < 10 {
                    var relay = pinWire
                    relay.hopCount += 1
                    if let relayData = try? JSONEncoder().encode(relay) {
                        try? session.send(relayData, toPeers: otherPeers, with: .reliable)
                    }
                }
            }
        }
    }

    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}

extension SurvivNetworker: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        invitationHandler(true, self.session)
    }
}

extension SurvivNetworker: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
