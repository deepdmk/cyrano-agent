// CyranoChat Tests - ChatViewModel

import Testing
import Foundation
@testable import CyranoChat

@Suite("ChatViewModel", .serialized)
struct ChatViewModelTests {

    // MARK: - Initialization

    @Test("ViewModel initializes with empty messages")
    @MainActor
    func emptyOnInit() {
        let vm = ChatViewModel()

        #expect(vm.messages.isEmpty)
        #expect(vm.inputText.isEmpty)
        #expect(vm.isGenerating == false)
        #expect(vm.voiceState == .idle)
        #expect(vm.errorMessage == nil)
        #expect(vm.partialTranscript.isEmpty)
    }

    @Test("Default model is Claude Sonnet 4")
    @MainActor
    func defaultModel() {
        // Clear any saved preference for test isolation
        UserDefaults.standard.removeObject(forKey: "selectedModel")
        let vm = ChatViewModel()

        #expect(vm.selectedModel == "claude-sonnet-4-6-20250620")
    }

    @Test("Default system prompt is set")
    @MainActor
    func defaultSystemPrompt() {
        UserDefaults.standard.removeObject(forKey: "systemPrompt")
        let vm = ChatViewModel()

        #expect(vm.systemPrompt.contains("helpful AI assistant"))
    }

    // MARK: - Settings Persistence

    @Test("Model selection persists to UserDefaults")
    @MainActor
    func modelPersistence() {
        let vm = ChatViewModel()
        vm.selectedModel = "claude-haiku-4-5-20251001"

        let stored = UserDefaults.standard.string(forKey: "selectedModel")
        #expect(stored == "claude-haiku-4-5-20251001")

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "selectedModel")
    }

    @Test("System prompt persists to UserDefaults")
    @MainActor
    func systemPromptPersistence() {
        let vm = ChatViewModel()
        vm.systemPrompt = "Custom prompt"

        let stored = UserDefaults.standard.string(forKey: "systemPrompt")
        #expect(stored == "Custom prompt")

        // Cleanup
        UserDefaults.standard.removeObject(forKey: "systemPrompt")
    }

    // MARK: - Message Sending

    @Test("sendMessage does nothing with empty input")
    @MainActor
    func sendEmptyMessage() async {
        let vm = ChatViewModel()
        vm.inputText = ""

        await vm.sendMessage()

        #expect(vm.messages.isEmpty)
    }

    @Test("sendMessage does nothing with whitespace-only input")
    @MainActor
    func sendWhitespaceMessage() async {
        let vm = ChatViewModel()
        vm.inputText = "   \n\t  "

        await vm.sendMessage()

        #expect(vm.messages.isEmpty)
    }

    @Test("sendMessage clears input text")
    @MainActor
    func sendClearsInput() async {
        let vm = ChatViewModel()
        vm.inputText = "Hello"

        // This will fail to send (no API key) but should still clear input
        await vm.sendMessage()

        #expect(vm.inputText.isEmpty)
    }

    @Test("sendMessage adds user message even without API key")
    @MainActor
    func sendAddsUserMessage() async {
        // Ensure no API key
        KeychainHelper.anthropicAPIKey = nil

        let vm = ChatViewModel()
        vm.inputText = "Hello"

        await vm.sendMessage()

        // Should have user message
        #expect(vm.messages.count >= 1)
        #expect(vm.messages.first?.role == .user)
        #expect(vm.messages.first?.content == "Hello")
    }

    @Test("sendMessage shows error without API key")
    @MainActor
    func sendErrorWithoutKey() async {
        KeychainHelper.anthropicAPIKey = nil

        let vm = ChatViewModel()
        vm.inputText = "Hello"

        await vm.sendMessage()

        #expect(vm.errorMessage != nil)
        #expect(vm.errorMessage?.contains("API key") == true || vm.errorMessage?.contains("Settings") == true)
    }

    @Test("sendMessage prevents double-send while generating")
    @MainActor
    func preventDoubleSend() async {
        let vm = ChatViewModel()
        vm.isGenerating = true
        vm.inputText = "Hello"

        await vm.sendMessage()

        // Should not have added any messages
        #expect(vm.messages.isEmpty)
        // Input should not be cleared
        #expect(vm.inputText == "Hello")
    }

    // MARK: - Conversation Management

    @Test("clearConversation removes all messages")
    @MainActor
    func clearConversation() {
        let vm = ChatViewModel()
        vm.messages = [
            ChatMessage(role: .user, content: "hi"),
            ChatMessage(role: .assistant, content: "hello")
        ]
        vm.partialTranscript = "partial"
        vm.errorMessage = "error"

        vm.clearConversation()

        #expect(vm.messages.isEmpty)
        #expect(vm.partialTranscript.isEmpty)
        #expect(vm.errorMessage == nil)
    }

    // MARK: - API Key Detection

    @Test("hasAPIKey returns false when no key stored")
    @MainActor
    func noAPIKey() {
        KeychainHelper.anthropicAPIKey = nil
        let vm = ChatViewModel()

        #expect(vm.hasAPIKey == false)
    }

    @Test("hasAPIKey returns true when key stored")
    @MainActor
    func hasAPIKey() {
        KeychainHelper.anthropicAPIKey = "sk-test"
        let vm = ChatViewModel()

        #expect(vm.hasAPIKey == true)

        // Cleanup
        KeychainHelper.anthropicAPIKey = nil
    }

    // MARK: - Voice State

    @Test("VoiceState enum has all expected cases")
    func voiceStateCases() {
        let states: [VoiceState] = [.idle, .listening, .processing, .generating, .speaking]
        #expect(states.count == 5)
    }

    @Test("VoiceState is Equatable")
    func voiceStateEquatable() {
        #expect(VoiceState.idle == VoiceState.idle)
        #expect(VoiceState.idle != VoiceState.listening)
    }

    @Test("Initial voice state is idle")
    @MainActor
    func initialVoiceState() {
        let vm = ChatViewModel()
        #expect(vm.voiceState == .idle)
    }

    // MARK: - Service Configuration

    @Test("reconfigureWithAPIKey stores key and recreates service")
    @MainActor
    func reconfigureAPIKey() {
        let vm = ChatViewModel()
        vm.reconfigureWithAPIKey("sk-new-key")

        #expect(KeychainHelper.anthropicAPIKey == "sk-new-key")

        // Cleanup
        KeychainHelper.anthropicAPIKey = nil
    }
}
