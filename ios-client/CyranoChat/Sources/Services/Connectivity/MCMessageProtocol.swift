// CyranoChat - MC Wire Protocol
// Codable message types for MultipeerConnectivity communication
// Mirror of macos-server/Sources/Protocol/CyranoMessage.swift

import Foundation

// MARK: - Message Envelope

/// Top-level envelope for all messages between iOS client and macOS server.
struct CyranoMessage: Codable, Sendable {
    let type: MessageType
    let id: String
    let timestamp: Date
    let payload: Data

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

struct ChatRequestPayload: Codable, Sendable {
    let requestId: String
    let messages: [WireMessage]
    let config: WireConfig
}

struct CancelRequestPayload: Codable, Sendable {
    let requestId: String
}

// MARK: - Server -> Client Payloads

struct StreamTokenPayload: Codable, Sendable {
    let requestId: String
    let content: String
    let sequenceNumber: Int
}

struct StreamCompletePayload: Codable, Sendable {
    let requestId: String
    let stopReason: String?
    let totalTokens: Int
}

struct StreamErrorPayload: Codable, Sendable {
    let requestId: String
    let errorCode: String
    let errorMessage: String
    let retryAfter: TimeInterval?
}

struct StatusUpdatePayload: Codable, Sendable {
    let serverName: String
    let availableModels: [String]
    let currentModel: String
    let isReady: Bool
}

// MARK: - Wire Types

struct WireMessage: Codable, Sendable {
    let role: String
    let content: String
}

struct WireConfig: Codable, Sendable {
    let model: String
    let maxTokens: Int
    let temperature: Float
    let systemPrompt: String?
}
