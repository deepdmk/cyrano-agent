// CyranoChat - Chat Message Model

import Foundation

/// A single message in a chat conversation
public struct ChatMessage: Identifiable, Sendable {
    public let id: UUID
    public let role: Role
    public var content: String
    public let timestamp: Date
    public var isStreaming: Bool

    public enum Role: String, Sendable {
        case user
        case assistant
        case system
    }

    public init(
        id: UUID = UUID(),
        role: Role,
        content: String,
        timestamp: Date = Date(),
        isStreaming: Bool = false
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.isStreaming = isStreaming
    }

    /// Convert to LLMMessage for API calls
    public func toLLMMessage() -> LLMMessage {
        LLMMessage(
            role: LLMMessage.Role(rawValue: role.rawValue) ?? .user,
            content: content
        )
    }
}
