// CyranoServer - MultipeerConnectivity Service
// Advertises as a nearby service, accepts iOS client connections,
// and provides send/receive primitives

import MultipeerConnectivity
import Logging

/// Connection event for logging
struct MCEvent: Sendable {
    let timestamp: Date
    let message: String

    init(_ message: String) {
        self.timestamp = Date()
        self.message = message
    }
}

@MainActor
final class CyranoMCService: NSObject, ObservableObject {

    static let serviceType = "cyrano-chat"

    // MARK: - Published State

    @Published var connectedPeers: [MCPeerID] = []
    @Published var isAdvertising: Bool = false
    @Published var recentEvents: [MCEvent] = []

    // MARK: - MC Properties

    private let myPeerID: MCPeerID
    private let session: MCSession
    private let advertiser: MCNearbyServiceAdvertiser
    private let logger = Logger(label: "com.cyrano.server.mc")

    /// Callback for incoming messages
    var onMessageReceived: ((Data, MCPeerID) -> Void)?

    /// Callback when a peer disconnects
    var onPeerDisconnected: ((MCPeerID) -> Void)?

    // MARK: - Init

    init(displayName: String) {
        self.myPeerID = MCPeerID(displayName: displayName)
        self.session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        self.advertiser = MCNearbyServiceAdvertiser(
            peer: myPeerID,
            discoveryInfo: ["version": "1", "app": "cyrano"],
            serviceType: Self.serviceType
        )
        super.init()
        self.session.delegate = self
        self.advertiser.delegate = self
    }

    // MARK: - Advertising

    func startAdvertising() {
        advertiser.startAdvertisingPeer()
        isAdvertising = true
        addEvent("Started advertising as \"\(myPeerID.displayName)\"")
        logger.info("MC advertising started")
    }

    func stopAdvertising() {
        advertiser.stopAdvertisingPeer()
        isAdvertising = false
        addEvent("Stopped advertising")
        logger.info("MC advertising stopped")
    }

    // MARK: - Sending

    func send(_ data: Data, to peer: MCPeerID) throws {
        try session.send(data, toPeers: [peer], with: .reliable)
    }

    func broadcast(_ data: Data) throws {
        guard !session.connectedPeers.isEmpty else { return }
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    // MARK: - Helpers

    private func addEvent(_ message: String) {
        let event = MCEvent(message)
        recentEvents.append(event)
        // Keep last 50 events
        if recentEvents.count > 50 {
            recentEvents.removeFirst(recentEvents.count - 50)
        }
    }
}

// MARK: - MCSessionDelegate

extension CyranoMCService: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID,
                             didChange state: MCSessionState) {
        Task { @MainActor in
            self.connectedPeers = session.connectedPeers
            switch state {
            case .connected:
                self.logger.info("Peer connected: \(peerID.displayName)")
                self.addEvent("Connected: \(peerID.displayName)")
            case .notConnected:
                self.logger.info("Peer disconnected: \(peerID.displayName)")
                self.addEvent("Disconnected: \(peerID.displayName)")
                self.onPeerDisconnected?(peerID)
            case .connecting:
                self.logger.info("Peer connecting: \(peerID.displayName)")
                self.addEvent("Connecting: \(peerID.displayName)")
            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data,
                             fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.onMessageReceived?(data, peerID)
        }
    }

    nonisolated func session(_ session: MCSession, didReceive stream: InputStream,
                             withName streamName: String, fromPeer peerID: MCPeerID) {}

    nonisolated func session(_ session: MCSession,
                             didStartReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, with progress: Progress) {}

    nonisolated func session(_ session: MCSession,
                             didFinishReceivingResourceWithName resourceName: String,
                             fromPeer peerID: MCPeerID, at localURL: URL?,
                             withError error: Error?) {}
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension CyranoMCService: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            self.logger.info("Accepting invitation from \(peerID.displayName)")
            self.addEvent("Invitation from \(peerID.displayName) — accepted")
            invitationHandler(true, self.session)
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.logger.error("Advertising failed: \(error.localizedDescription)")
            self.addEvent("Advertising error: \(error.localizedDescription)")
            self.isAdvertising = false
        }
    }
}
