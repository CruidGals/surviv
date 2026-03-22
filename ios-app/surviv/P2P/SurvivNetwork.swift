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
    private var hadConnectedPeers = false
    private static let maxPendingMeshPayloads = 64

    @Published var connectedPeers: [MCPeerID] = []
    @Published var incomingMessages: [SurvivPacket] = []
    @Published var userRole: Role = .scout
    @Published var seenMessageIds = Set<UUID>()
    /// Latest high-priority admin text for UI banners (deduped by packet id).
    @Published var latestAdminAnnouncement: SurvivPacket?

    var onHazardPinWire: ((HazardPinWire) -> Void)?

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
        guard !session.connectedPeers.isEmpty else { return }
        guard userRole == .admin else {
            print("Access denied: You are not an admin")
            return
        }

        let packet = SurvivPacket(senderName: resolvedSenderName(), role: .admin, message: message)
        if let data = packet.encode() {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                incomingMessages.append(packet)
                seenMessageIds.insert(packet.id)
                latestAdminAnnouncement = packet
            } catch {
                print("Error sending: \(error.localizedDescription)")
            }
        }
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
        pendingMeshLock.unlock()
        guard !batch.isEmpty, !session.connectedPeers.isEmpty else { return }
        for data in batch {
            try? session.send(data, toPeers: session.connectedPeers, with: .reliable)
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
            } else if !nowConnected {
                self.hadConnectedPeers = false
            }
            self.connectedPeers = peers
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let pinWire = try? JSONDecoder().decode(HazardPinWire.self, from: data) {
            DispatchQueue.main.async {
                if self.seenMessageIds.contains(pinWire.id) { return }
                self.seenMessageIds.insert(pinWire.id)

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
            return
        }

        guard let packet = SurvivPacket.decode(from: data) else { return }

        DispatchQueue.main.async {
            if self.seenMessageIds.contains(packet.id) { return }
            self.seenMessageIds.insert(packet.id)

            if packet.role == .admin {
                self.incomingMessages.append(packet)
                self.latestAdminAnnouncement = packet

                let otherPeers = self.session.connectedPeers.filter { $0 != peerID }
                if !otherPeers.isEmpty && packet.hopCount < 10 {
                    var relayPacket = packet
                    relayPacket.hopCount += 1
                    self.send(packet: relayPacket, toPeers: otherPeers)
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
