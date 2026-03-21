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
        
        let packet = SurvivPacket(senderName: myPeerID.displayName, message: message)
        if let data = packet.encode() {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            } catch {
                print("Error sending: \(error.localizedDescription)")
            }
        }
    }
}

extension SurvivNetworker: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        DispatchQueue.main.async {
            self.connectedPeers = session.connectedPeers
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        if let packet = SurvivPacket.decode(from: data) {
            DispatchQueue.main.async {
                self.incomingMessages.append(packet)
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
