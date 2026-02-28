// CyranoServer - Message Router
// Routes incoming MC messages to Claude API and streams responses back

import Foundation
import MultipeerConnectivity
import Logging

@MainActor
final class MessageRouter: ObservableObject {

    private let mcService: CyranoMCService
    private let claudeService: ClaudeRelayService
    private let config: ServerConfig
    private let logger = Logger(label: "com.cyrano.server.router")

    /// Track in-flight requests for cancellation
    private var activeRequests: [String: Task<Void, Never>] = [:]

    @Published var requestCount: Int = 0
    @Published var lastRequestTime: Date?

    init(mcService: CyranoMCService, claudeService: ClaudeRelayService, config: ServerConfig) {
        self.mcService = mcService
        self.claudeService = claudeService
        self.config = config

        mcService.onMessageReceived = { [weak self] data, peer in
            Task { @MainActor in
                self?.handleIncomingMessage(data, from: peer)
            }
        }

        mcService.onPeerDisconnected = { [weak self] peer in
            Task { @MainActor in
                self?.cancelAllRequests()
            }
        }
    }

    // MARK: - Message Handling

    private func handleIncomingMessage(_ data: Data, from peer: MCPeerID) {
        guard let message = try? JSONDecoder().decode(CyranoMessage.self, from: data) else {
            logger.warning("Failed to decode message from \(peer.displayName)")
            return
        }

        switch message.type {
        case .chatRequest:
            handleChatRequest(message, from: peer)
        case .cancelRequest:
            handleCancelRequest(message)
        case .ping:
            handlePing(from: peer)
        default:
            logger.warning("Unexpected message type from client: \(message.type.rawValue)")
        }
    }

    // MARK: - Chat Request

    private func handleChatRequest(_ message: CyranoMessage, from peer: MCPeerID) {
        guard let payload = try? message.decodePayload(ChatRequestPayload.self) else {
            logger.warning("Failed to decode chat request payload")
            sendError(requestId: message.id, code: "invalid_request",
                      message: "Malformed chat request", to: peer)
            return
        }

        let requestId = payload.requestId
        requestCount += 1
        lastRequestTime = Date()

        logger.info("Chat request \(requestId) from \(peer.displayName): \(payload.messages.count) messages")

        let task = Task { [weak self] in
            guard let self else { return }
            var sequenceNumber = 0

            do {
                try await claudeService.streamCompletion(
                    messages: payload.messages,
                    config: payload.config
                ) { content, isDone, stopReason in
                    guard !Task.isCancelled else { return }

                    if !content.isEmpty {
                        sequenceNumber += 1
                        let tokenPayload = StreamTokenPayload(
                            requestId: requestId,
                            content: content,
                            sequenceNumber: sequenceNumber
                        )
                        await self.sendMessage(type: .streamToken, payload: tokenPayload, to: peer)
                    }

                    if isDone {
                        let completePayload = StreamCompletePayload(
                            requestId: requestId,
                            stopReason: stopReason,
                            totalTokens: sequenceNumber
                        )
                        await self.sendMessage(type: .streamComplete, payload: completePayload, to: peer)
                    }
                }
            } catch let error as RelayError {
                await self.sendError(
                    requestId: requestId,
                    code: error.errorCode,
                    message: error.localizedDescription,
                    retryAfter: error.retryAfter,
                    to: peer
                )
            } catch {
                await self.sendError(
                    requestId: requestId,
                    code: "unknown",
                    message: error.localizedDescription,
                    to: peer
                )
            }

            await MainActor.run {
                self.activeRequests[requestId] = nil
            }
        }

        activeRequests[requestId] = task
    }

    // MARK: - Cancel / Ping

    private func handleCancelRequest(_ message: CyranoMessage) {
        guard let payload = try? message.decodePayload(CancelRequestPayload.self) else { return }
        logger.info("Cancel request for \(payload.requestId)")
        activeRequests[payload.requestId]?.cancel()
        activeRequests[payload.requestId] = nil
    }

    private func handlePing(from peer: MCPeerID) {
        let pong = CyranoMessage(type: .pong)
        guard let data = try? JSONEncoder().encode(pong) else { return }
        try? mcService.send(data, to: peer)
    }

    func cancelAllRequests() {
        for (id, task) in activeRequests {
            task.cancel()
            activeRequests[id] = nil
        }
    }

    /// Send status update to a newly connected peer
    func sendStatusUpdate(to peer: MCPeerID) {
        let status = StatusUpdatePayload(
            serverName: config.serverDisplayName,
            availableModels: [
                "claude-sonnet-4-6-20250620",
                "claude-opus-4-6-20250612",
                "claude-haiku-4-5-20251001"
            ],
            currentModel: config.defaultModel,
            isReady: true
        )
        sendMessage(type: .statusUpdate, payload: status, to: peer)
    }

    // MARK: - Sending Helpers

    private func sendMessage<T: Encodable>(type: CyranoMessage.MessageType, payload: T, to peer: MCPeerID) {
        do {
            let data = try CyranoMessage.encode(type, payload: payload)
            try mcService.send(data, to: peer)
        } catch {
            logger.error("Failed to send \(type.rawValue) to \(peer.displayName): \(error)")
        }
    }

    private func sendError(requestId: String, code: String, message: String,
                           retryAfter: TimeInterval? = nil, to peer: MCPeerID) {
        let errorPayload = StreamErrorPayload(
            requestId: requestId,
            errorCode: code,
            errorMessage: message,
            retryAfter: retryAfter
        )
        sendMessage(type: .streamError, payload: errorPayload, to: peer)
    }
}
