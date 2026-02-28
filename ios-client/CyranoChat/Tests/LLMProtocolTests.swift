// CyranoChat Tests - LLM Protocol Types

import Testing
import Foundation
@testable import CyranoChat

@Suite("LLM Protocol Types")
struct LLMProtocolTests {

    // MARK: - LLMMessage

    @Test("LLMMessage stores role and content")
    func messageInit() {
        let msg = LLMMessage(role: .user, content: "Hello")

        #expect(msg.role == .user)
        #expect(msg.content == "Hello")
    }

    @Test("LLMMessage roles have correct raw values")
    func messageRoles() {
        #expect(LLMMessage.Role.system.rawValue == "system")
        #expect(LLMMessage.Role.user.rawValue == "user")
        #expect(LLMMessage.Role.assistant.rawValue == "assistant")
    }

    @Test("LLMMessage is Codable")
    func messageCodable() throws {
        let original = LLMMessage(role: .user, content: "test")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMMessage.self, from: data)

        #expect(decoded.role == original.role)
        #expect(decoded.content == original.content)
    }

    // MARK: - LLMToken

    @Test("LLMToken with content")
    func tokenContent() {
        let token = LLMToken(content: "Hello", isDone: false)

        #expect(token.content == "Hello")
        #expect(token.isDone == false)
        #expect(token.stopReason == nil)
        #expect(token.tokenCount == nil)
    }

    @Test("LLMToken done with stop reason")
    func tokenDone() {
        let token = LLMToken(content: "", isDone: true, stopReason: .endTurn)

        #expect(token.isDone == true)
        #expect(token.stopReason == .endTurn)
    }

    // MARK: - StopReason

    @Test("StopReason raw values match API")
    func stopReasonValues() {
        #expect(StopReason.endTurn.rawValue == "end_turn")
        #expect(StopReason.maxTokens.rawValue == "max_tokens")
        #expect(StopReason.stopSequence.rawValue == "stop_sequence")
    }

    // MARK: - LLMConfig

    @Test("Default config uses gpt-4o model")
    func defaultConfig() {
        let config = LLMConfig.default

        #expect(config.model == "gpt-4o")
        #expect(config.maxTokens == 1024)
        #expect(config.temperature == 0.7)
        #expect(config.stream == true)
    }

    @Test("Custom config preserves all fields")
    func customConfig() {
        let config = LLMConfig(
            model: "claude-sonnet-4-20250514",
            maxTokens: 4096,
            temperature: 0.5,
            topP: 0.9,
            stopSequences: ["STOP"],
            systemPrompt: "Be helpful",
            stream: true
        )

        #expect(config.model == "claude-sonnet-4-20250514")
        #expect(config.maxTokens == 4096)
        #expect(config.temperature == 0.5)
        #expect(config.topP == 0.9)
        #expect(config.stopSequences == ["STOP"])
        #expect(config.systemPrompt == "Be helpful")
    }

    @Test("LLMConfig is Codable")
    func configCodable() throws {
        let original = LLMConfig(
            model: "test",
            maxTokens: 100,
            temperature: 0.5,
            topP: 0.8,
            systemPrompt: "prompt"
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMConfig.self, from: data)

        #expect(decoded.model == original.model)
        #expect(decoded.maxTokens == original.maxTokens)
        #expect(decoded.temperature == original.temperature)
        #expect(decoded.topP == original.topP)
        #expect(decoded.systemPrompt == original.systemPrompt)
    }

    // MARK: - LLMMetrics

    @Test("LLMMetrics stores values")
    func metrics() {
        let m = LLMMetrics(medianTTFT: 0.5, p99TTFT: 1.5, totalInputTokens: 100, totalOutputTokens: 200)

        #expect(m.medianTTFT == 0.5)
        #expect(m.p99TTFT == 1.5)
        #expect(m.totalInputTokens == 100)
        #expect(m.totalOutputTokens == 200)
    }

    // MARK: - LLMProvider

    @Test("All providers have display names")
    func providerDisplayNames() {
        for provider in LLMProvider.allCases {
            #expect(!provider.displayName.isEmpty)
        }
    }

    @Test("Anthropic provider has expected models")
    func anthropicModels() {
        let models = LLMProvider.anthropic.availableModels
        #expect(!models.isEmpty)
        #expect(models.contains(where: { $0.contains("claude") }))
    }

    @Test("Local MLX does not require network")
    func localNoNetwork() {
        #expect(LLMProvider.localMLX.requiresNetwork == false)
    }

    @Test("OpenAI requires network")
    func openAINetwork() {
        #expect(LLMProvider.openAI.requiresNetwork == true)
    }

    // MARK: - LLMError

    @Test("LLMError has localized descriptions")
    func errorDescriptions() {
        let errors: [LLMError] = [
            .connectionFailed("test"),
            .streamFailed("test"),
            .authenticationFailed,
            .rateLimited(retryAfter: 5),
            .rateLimited(retryAfter: nil),
            .quotaExceeded,
            .invalidRequest("bad"),
            .modelNotFound("x"),
            .contentFiltered,
            .contextLengthExceeded(maxTokens: 1000)
        ]

        for error in errors {
            #expect(error.localizedDescription.count > 0)
        }
    }

    // MARK: - TokenEstimation

    @Test("Token estimation utility works")
    func tokenEstimationUtility() {
        let count = TokenEstimation.estimate("Hello world")
        #expect(count >= 1)
    }

    @Test("Token estimation for messages includes overhead")
    func tokenEstimationMessages() {
        let messages = [
            LLMMessage(role: .user, content: "Hello"),
            LLMMessage(role: .assistant, content: "Hi!")
        ]
        let count = TokenEstimation.estimate(messages: messages)

        // Should include 4-token overhead per message
        #expect(count >= 10) // At least message overhead + content
    }

    @Test("fitsInContext checks correctly")
    func fitsInContext() {
        let shortMessages = [LLMMessage(role: .user, content: "Hi")]
        #expect(TokenEstimation.fitsInContext(messages: shortMessages, contextWindow: 10000))

        // Very large message should not fit in tiny window
        let longContent = String(repeating: "word ", count: 10000)
        let longMessages = [LLMMessage(role: .user, content: longContent)]
        #expect(!TokenEstimation.fitsInContext(messages: longMessages, contextWindow: 100))
    }
}
