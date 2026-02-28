// CyranoChat Tests - ChatMessage Model

import Testing
import Foundation
@testable import CyranoChat

@Suite("ChatMessage")
struct ChatMessageTests {

    @Test("Default initializer sets expected values")
    func defaultInit() {
        let msg = ChatMessage(role: .user, content: "Hello")

        #expect(msg.role == .user)
        #expect(msg.content == "Hello")
        #expect(msg.isStreaming == false)
        #expect(msg.timestamp <= Date())
    }

    @Test("Streaming flag can be set")
    func streamingInit() {
        let msg = ChatMessage(role: .assistant, content: "", isStreaming: true)

        #expect(msg.isStreaming == true)
        #expect(msg.content.isEmpty)
    }

    @Test("Each message gets unique ID")
    func uniqueIDs() {
        let a = ChatMessage(role: .user, content: "a")
        let b = ChatMessage(role: .user, content: "b")

        #expect(a.id != b.id)
    }

    @Test("Content is mutable for streaming updates")
    func mutableContent() {
        var msg = ChatMessage(role: .assistant, content: "", isStreaming: true)
        msg.content += "Hello"
        msg.content += " world"
        msg.isStreaming = false

        #expect(msg.content == "Hello world")
        #expect(msg.isStreaming == false)
    }

    @Test("toLLMMessage maps user role correctly")
    func toLLMMessageUser() {
        let msg = ChatMessage(role: .user, content: "test")
        let llm = msg.toLLMMessage()

        #expect(llm.role == .user)
        #expect(llm.content == "test")
    }

    @Test("toLLMMessage maps assistant role correctly")
    func toLLMMessageAssistant() {
        let msg = ChatMessage(role: .assistant, content: "response")
        let llm = msg.toLLMMessage()

        #expect(llm.role == .assistant)
        #expect(llm.content == "response")
    }

    @Test("toLLMMessage maps system role correctly")
    func toLLMMessageSystem() {
        let msg = ChatMessage(role: .system, content: "prompt")
        let llm = msg.toLLMMessage()

        #expect(llm.role == .system)
        #expect(llm.content == "prompt")
    }

    @Test("All three roles exist")
    func allRoles() {
        let roles: [ChatMessage.Role] = [.user, .assistant, .system]
        #expect(roles.count == 3)
        #expect(ChatMessage.Role.user.rawValue == "user")
        #expect(ChatMessage.Role.assistant.rawValue == "assistant")
        #expect(ChatMessage.Role.system.rawValue == "system")
    }

    @Test("Custom timestamp is preserved")
    func customTimestamp() {
        let date = Date(timeIntervalSince1970: 1000)
        let msg = ChatMessage(role: .user, content: "hi", timestamp: date)

        #expect(msg.timestamp == date)
    }

    @Test("Custom ID is preserved")
    func customID() {
        let id = UUID()
        let msg = ChatMessage(id: id, role: .user, content: "hi")

        #expect(msg.id == id)
    }
}
