// CyranoChat - MultipeerConnectivity Session Manager
// Browses for the macOS server, manages session, and routes incoming data

import MultipeerConnectivity
import Combine
import Logging

/// Connection state for the MC session
enum MCConnectionState: Equatable, Sendable {
    case disconnected
    case browsing
    case connecting
    case connected
    case error(String)

    var isError: Bool {
        if case .error = self { return true }
        return false
    }
}

@MainActor
final class MultipeerSessionManager: NSObject, ObservableObject {

    // MARK: - Published State

    @Published var connectionState: MCConnectionState = .disconnected
    @Published var connectedServerName: String?

    // MARK: - MC Properties

    static let serviceType = "cyrano-chat"

    private let myPeerID: MCPeerID
    private var session: MCSession!
    private var browser: MCNearbyServiceBrowser!
    private let logger = Logger(label: "com.cyrano.multipeer")

    // MARK: - Response Routing

    /// Active response streams keyed by requestId
    private var responseContinuations: [String: AsyncStream<StreamTokenPayload>.Continuation] = []

    /// Error handlers keyed by requestId
    private var errorHandlers: [String: (StreamErrorPayload) -> Void] = [:]

    /// Completion handlers keyed by requestId
    private var completionHandlers: [String: (StreamCompletePayload) -> Void] = [:]

    /// Server status callback
    var onStatusUpdate: ((StatusUpdatePayload) -> Void)?

    // MARK: - Init

    override init() {
        self.myPeerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
        setupSession()
    }

    private func setupSession() {
        session = MCSession(
            peer: myPeerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        session.delegate = self

        browser = MCNearbyServiceBrowser(
            peer: myPeerID,
            serviceType: Self.serviceType
        )
        browser.delegate = self
    }

    // MARK: - Browsing

    func startBrowsing() {
        guard connectionState != .connected else { return }
        browser.startBrowsingForPeers()
        connectionState = .browsing
        logger.info("Started browsing for Cyrano servers")
    }

    func stopBrowsing() {
        browser.stopBrowsingForPeers()
        if connectionState == .browsing {
            connectionState = .disconnected
        }
        logger.info("Stopped browsing")
    }

    func disconnect() {
        browser.stopBrowsingForPeers()
        session.disconnect()
        connectedServerName = nil
        connectionState = .disconnected
        cancelAllStreams()
        logger.info("Disconnected")
    }

    // MARK: - Sending

    func send(_ data: Data) throws {
        guard !session.connectedPeers.isEmpty else {
            throw MCError.notConnected
        }
        try session.send(data, toPeers: session.connectedPeers, with: .reliable)
    }

    // MARK: - Response Stream Registration

    /// Register a stream for receiving tokens for a given requestId
    func registerResponseStream(requestId: String) -> (
        tokens: AsyncStream<StreamTokenPayload>,
        onError: @escaping (StreamErrorPayload) -> Void,
        onComplete: @escaping (StreamCompletePayload) -> Void
    ) {
        var errorHandler: ((StreamErrorPayload) -> Void)?
        var completeHandler: ((StreamCompletePayload) -> Void)?

        let stream = AsyncStream<StreamTokenPayload> { continuation in
            self.responseContinuations[requestId] = continuation

            continuation.onTermination = { @Sendable _ in
                Task { @MainActor in
                    self.responseContinuations[requestId] = nil
                    self.errorHandlers[requestId] = nil
                    self.completionHandlers[requestId] = nil
                }
            }
        }

        errorHandler = { [weak self] error in
            self?.responseContinuations[requestId]?.finish()
            self?.responseContinuations[requestId] = nil
            self?.errorHandlers[requestId] = nil
            self?.completionHandlers[requestId] = nil
        }

        completeHandler = { [weak self] complete in
            self?.responseContinuations[requestId]?.finish()
            self?.responseContinuations[requestId] = nil
            self?.errorHandlers[requestId] = nil
            self?.completionHandlers[requestId] = nil
        }

        errorHandlers[requestId] = errorHandler!
        completionHandlers[requestId] = completeHandler!

        return (stream, errorHandler!, completeHandler!)
    }

    func unregisterResponseStream(requestId: String) {
        responseContinuations[requestId]?.finish()
        responseContinuations[requestId] = nil
        errorHandlers[requestId] = nil
        completionHandlers[requestId] = nil
    }

    private func cancelAllStreams() {
        for (_, continuation) in responseContinuations {
            continuation.finish()
        }
        responseContinuations.removeAll()
        errorHandlers.removeAll()
        completionHandlers.removeAll()
    }

    // MARK: - Incoming Message Routing

    private func handleIncomingData(_ data: Data) {
        guard let message = try? JSONDecoder().decode(CyranoMessage.self, from: data) else {
            logger.warning("Failed to decode incoming MC message")
            return
        }

        switch message.type {
        case .streamToken:
            if let payload = try? message.decodePayload(StreamTokenPayload.self) {
                responseContinuations[payload.requestId]?.yield(payload)
            }

        case .streamComplete:
            if let payload = try? message.decodePayload(StreamCompletePayload.self) {
                completionHandlers[payload.requestId]?(payload)
            }

        case .streamError:
            if let payload = try? message.decodePayload(StreamErrorPayload.self) {
                errorHandlers[payload.requestId]?(payload)
            }

        case .statusUpdate:
            if let payload = try? message.decodePayload(StatusUpdatePayload.self) {
                connectedServerName = payload.serverName
                onStatusUpdate?(payload)
            }

        case .pong:
            logger.debug("Received pong")

        default:
            logger.warning("Unexpected message type from server: \(message.type.rawValue)")
        }
    }
}

// MARK: - MCSessionDelegate

extension MultipeerSessionManager: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID,
                             didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.connectionState = .connected
                self.connectedServerName = peerID.displayName
                self.browser.stopBrowsingForPeers()
                self.logger.info("Connected to server: \(peerID.displayName)")

            case .notConnected:
                let wasConnected = self.connectionState == .connected
                self.connectionState = .disconnected
                self.connectedServerName = nil
                self.cancelAllStreams()
                self.logger.info("Disconnected from server: \(peerID.displayName)")

                // Auto-reconnect if we were previously connected
                if wasConnected {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s backoff
                    if self.connectionState == .disconnected {
                        self.startBrowsing()
                    }
                }

            case .connecting:
                self.connectionState = .connecting
                self.logger.info("Connecting to server: \(peerID.displayName)")

            @unknown default:
                break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data,
                             fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.handleIncomingData(data)
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

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerSessionManager: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            // Auto-invite the first server found (demo simplicity)
            self.logger.info("Found server: \(peerID.displayName)")
            self.connectionState = .connecting
            browser.invitePeer(peerID, to: self.session, withContext: nil, timeout: 10)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.logger.info("Lost server: \(peerID.displayName)")
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.connectionState = .error(error.localizedDescription)
            self.logger.error("Browse failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Errors

enum MCError: Error, LocalizedError {
    case notConnected

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Not connected to server"
        }
    }
}
