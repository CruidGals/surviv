import MultipeerConnectivity
import Combine

class SurvivNetworker: NSObject, ObservableObject {
    private let serviceType = "surviv" // Must match Info.plist
    private let myPeerID = MCPeerID(displayName: UIDevice.current.name)
    
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser!
    private var browser: MCNearbyServiceBrowser!
    
    @Published var connectedPeers: [MCPeerID] = []
    @Published var incomingMessages: [SurvivPacket] = []
    @Published var userRole: Role = .scout
    @Published var seenMessageIds = Set<UUID>() // To prevent seeing a message twice
    
    // Make secret handshake for admin
    private let secretHandshake: String = "Surviv"
    
    func promoteToAdmin(secret: String) {
        if secret == secretHandshake {
            self.userRole = .admin
            print("Promoted to admin")
        }
    }
    
    override init() {
        super.init()
        
        // Setup Session 
        session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        
        // Setup Advertiser 
        advertiser = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: serviceType)
        advertiser.delegate = self
        advertiser.startAdvertisingPeer()
        
        // Setup Browser 
        browser = MCNearbyServiceBrowser(peer: myPeerID, serviceType: serviceType)
        browser.delegate = self
        browser.startBrowsingForPeers()
    }
    
    // Broadcase message to all other users
    func broadcast(message: String) {
        guard !session.connectedPeers.isEmpty else { return }
        
        // permissions
        guard userRole == .admin else {
            print("Access denied: You are not an admin")
            return
        }
        
        let packet = SurvivPacket(senderName: myPeerID.displayName, role: .admin, message: message)
        if let data = packet.encode() {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                self.incomingMessages.append(packet)
                self.seenMessageIds.insert(packet.id)
            } catch {
                print("Error sending: \(error.localizedDescription)")
            }
        }
    }
    
    func send(packet: SurvivPacket, toPeers peers: [MCPeerID]) {
        guard !peers.isEmpty, let data = packet.encode() else { return }
        try? session.send(data, toPeers: peers, with: .reliable)
    }
}

extension SurvivNetworker: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        guard let packet = SurvivPacket.decode(from: data) else { return }
        
        DispatchQueue.main.async {
            // Prevent loop (infinite relaying)
            if self.seenMessageIds.contains(packet.id) { return }
            self.seenMessageIds.insert(packet.id)
            
            if packet.role == .admin {
                self.incomingMessages.append(packet)
                
                // RELAY INFORMATION
                let otherPeers = self.session.connectedPeers.filter {$0 != peerID}
                if !otherPeers.isEmpty && packet.hopCount < 10 {
                    var relayPacket = packet
                    relayPacket.hopCount += 1 // Increase hop count to make sure message doesn't go everywhere
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
        // Auto-accept invitations for the hackathon
        invitationHandler(true, self.session)
    }
}

extension SurvivNetworker: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        // Invite any peer we find immediately
        browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {}
}
