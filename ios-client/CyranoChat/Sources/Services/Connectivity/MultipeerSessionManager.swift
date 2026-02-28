// CyranoChat - MultipeerConnectivity Session Manager
// Browses for the macOS server, manages session, and routes incoming data

@preconcurrency import MultipeerConnectivity
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
    nonisolated(unsafe) private var session: MCSession!
    nonisolated(unsafe) private var browser: MCNearbyServiceBrowser!
    private let logger = Logger(label: "com.cyrano.multipeer")

    // MARK: - Response Routing

    /// Active response streams keyed by requestId
    private var responseContinuations: [String: AsyncStream<StreamTokenPayload>.Continuation] = [:]

    /// Error handlers keyed by requestId
    private var errorHandlers: [String: (StreamErrorPayload) -> Void] = [:]

    /// Completion handlers keyed by requestId
    private var completionHandlers: [String: (StreamCompletePayload) -> Void] = [:]

    /// Last error messages keyed by requestId
    private var lastErrors: [String: String] = [:]

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

    /// Register a token stream for a given requestId (returns only the AsyncStream)
    func registerTokenStream(requestId: String) -> AsyncStream<StreamTokenPayload> {
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

        errorHandlers[requestId] = { [weak self] error in
            self?.lastErrors[requestId] = error.errorMessage
            self?.responseContinuations[requestId]?.finish()
            self?.responseContinuations[requestId] = nil
            self?.errorHandlers[requestId] = nil
            self?.completionHandlers[requestId] = nil
        }

        completionHandlers[requestId] = { [weak self] _ in
            self?.responseContinuations[requestId]?.finish()
            self?.responseContinuations[requestId] = nil
            self?.errorHandlers[requestId] = nil
            self?.completionHandlers[requestId] = nil
        }

        return stream
    }

    /// Get the last error message for a request, if any
    func lastError(for requestId: String) -> String? {
        let error = lastErrors[requestId]
        lastErrors[requestId] = nil
        return error
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
        lastErrors.removeAll()
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
        let peerName = peerID.displayName
        Task { @MainActor in
            switch state {
            case .connected:
                self.connectionState = .connected
                self.connectedServerName = peerName
                self.browser.stopBrowsingForPeers()
                self.logger.info("Connected to server: \(peerName)")

            case .notConnected:
                let wasConnected = self.connectionState == .connected
                self.connectionState = .disconnected
                self.connectedServerName = nil
                self.cancelAllStreams()
                self.logger.info("Disconnected from server: \(peerName)")

                // Auto-reconnect if we were previously connected
                if wasConnected {
                    try? await Task.sleep(nanoseconds: 1_000_000_000) // 1s backoff
                    if self.connectionState == .disconnected {
                        self.startBrowsing()
                    }
                }

            case .connecting:
                self.connectionState = .connecting
                self.logger.info("Connecting to server: \(peerName)")

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
        let peerName = peerID.displayName
        // invitePeer must happen on the same thread as the delegate callback
        // to avoid sending non-Sendable MCPeerID across isolation boundaries
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        Task { @MainActor in
            self.logger.info("Found server: \(peerName)")
            self.connectionState = .connecting
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser,
                             lostPeer peerID: MCPeerID) {
        let peerName = peerID.displayName
        Task { @MainActor in
            self.logger.info("Lost server: \(peerName)")
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
