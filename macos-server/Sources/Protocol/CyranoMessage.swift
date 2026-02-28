// CyranoServer - Wire Protocol
// Codable message types for MultipeerConnectivity communication
// This file is duplicated in the iOS client (MCMessageProtocol.swift)

import Foundation

// MARK: - Message Envelope

/// Top-level envelope for all messages between iOS client and macOS server.
/// Each message is JSON-encoded and sent via MCSession.send(_:toPeers:with:.reliable).
struct CyranoMessage: Codable, Sendable {
    let type: MessageType
    let id: String
    let timestamp: Date
    let payload: Data // JSON-encoded inner payload

    enum MessageType: String, Codable, Sendable {
        // Client -> Server
        case chatRequest
        case cancelRequest
        case ping

        // Server -> Client
        case streamToken
        case streamComplete
        case streamError
        case statusUpdate
        case pong
    }

    init(type: MessageType, id: String = UUID().uuidString, payload: Data = Data()) {
        self.type = type
        self.id = id
        self.timestamp = Date()
        self.payload = payload
    }

    static func encode<T: Encodable>(_ type: MessageType, payload: T) throws -> Data {
        let payloadData = try JSONEncoder().encode(payload)
        let message = CyranoMessage(type: type, payload: payloadData)
        return try JSONEncoder().encode(message)
    }

    func decodePayload<T: Decodable>(_ type: T.Type) throws -> T {
        try JSONDecoder().decode(T.self, from: payload)
    }
}

// MARK: - Client -> Server Payloads

/// Chat request: send conversation history for streaming completion
struct ChatRequestPayload: Codable, Sendable {
    let requestId: String
    let messages: [WireMessage]
    let config: WireConfig
}

/// Cancel an in-flight chat request
struct CancelRequestPayload: Codable, Sendable {
    let requestId: String
}

// MARK: - Server -> Client Payloads

/// A single streamed token from the LLM
struct StreamTokenPayload: Codable, Sendable {
    let requestId: String
    let content: String
    let sequenceNumber: Int
}

/// Stream completed successfully
struct StreamCompletePayload: Codable, Sendable {
    let requestId: String
    let stopReason: String?
    let totalTokens: Int
}

/// Stream error
struct StreamErrorPayload: Codable, Sendable {
    let requestId: String
    let errorCode: String
    let errorMessage: String
    let retryAfter: TimeInterval?
}

/// Server status broadcast (sent on connect)
struct StatusUpdatePayload: Codable, Sendable {
    let serverName: String
    let availableModels: [String]
    let currentModel: String
    let isReady: Bool
}

// MARK: - Wire Types

/// Simplified message for the wire (mirrors LLMMessage but fully Codable without protocol deps)
struct WireMessage: Codable, Sendable {
    let role: String  // "user", "assistant", "system"
    let content: String
}

/// Simplified config for the wire (mirrors LLMConfig)
struct WireConfig: Codable, Sendable {
    let model: String
    let maxTokens: Int
    let temperature: Float
    let systemPrompt: String?
}
