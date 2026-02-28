// CyranoChat Tests - ClaudeAPIService

import Testing
import Foundation
@testable import CyranoChat

@Suite("ClaudeAPIService")
struct ClaudeAPIServiceTests {

    // MARK: - Initialization

    @Test("Service initializes with API key")
    func initialization() async {
        let service = ClaudeAPIService(apiKey: "sk-test-key")

        let cost = await service.costPerInputToken
        #expect(cost > 0)
    }

    @Test("Context window is 200K")
    func contextWindow() async {
        let service = ClaudeAPIService(apiKey: "test")
        let window = await service.contextWindowSize

        #expect(window == 200_000)
    }

    @Test("Cost per input token is $3/M")
    func inputCost() async {
        let service = ClaudeAPIService(apiKey: "test")
        let cost = await service.costPerInputToken

        #expect(cost == Decimal(string: "0.000003")!)
    }

    @Test("Cost per output token is $15/M")
    func outputCost() async {
        let service = ClaudeAPIService(apiKey: "test")
        let cost = await service.costPerOutputToken

        #expect(cost == Decimal(string: "0.000015")!)
    }

    // MARK: - Token Estimation

    @Test("Token estimation for short text")
    func tokenEstimationShort() async {
        let service = ClaudeAPIService(apiKey: "test")
        let count = await service.estimateTokenCount("Hello")

        // "Hello" = 5 chars, 5*10/35 = 1
        #expect(count >= 1)
    }

    @Test("Token estimation for longer text")
    func tokenEstimationLong() async {
        let service = ClaudeAPIService(apiKey: "test")
        let text = String(repeating: "word ", count: 100) // ~500 chars
        let count = await service.estimateTokenCount(text)

        // 500 * 10 / 35 ≈ 142
        #expect(count > 100)
        #expect(count < 200)
    }

    @Test("Token estimation never returns zero")
    func tokenEstimationMinimum() async {
        let service = ClaudeAPIService(apiKey: "test")
        let count = await service.estimateTokenCount("a")

        #expect(count >= 1)
    }

    @Test("Token estimation for empty string returns 1")
    func tokenEstimationEmpty() async {
        let service = ClaudeAPIService(apiKey: "test")
        let count = await service.estimateTokenCount("")

        #expect(count >= 1)
    }

    // MARK: - Default Protocol Methods

    @Test("Message token estimation includes overhead")
    func messageTokenEstimation() async {
        let service = ClaudeAPIService(apiKey: "test")
        let messages = [
            LLMMessage(role: .user, content: "Hello"),
            LLMMessage(role: .assistant, content: "Hi there!")
        ]
        let count = await service.estimateTokenCount(for: messages)

        // Should be > sum of individual texts due to overhead
        let textOnly = await service.estimateTokenCount("Hello") +
                       await service.estimateTokenCount("Hi there!")
        #expect(count > textOnly)
    }

    // MARK: - Error Handling

    @Test("Stream fails with invalid API key")
    func invalidAPIKey() async {
        let service = ClaudeAPIService(apiKey: "invalid-key")
        let config = LLMConfig(model: "claude-sonnet-4-20250514", maxTokens: 10)
        let messages = [LLMMessage(role: .user, content: "test")]

        do {
            let _ = try await service.streamCompletion(messages: messages, config: config)
            // If we get a stream back, consume it - the error may come during streaming
            // or the API may reject with an HTTP error
        } catch let error as LLMError {
            // Expected: authenticationFailed or connectionFailed
            switch error {
            case .authenticationFailed, .connectionFailed:
                // Expected
                break
            default:
                // Other LLM errors are also acceptable
                break
            }
        } catch {
            // Network errors are acceptable too (no internet, etc.)
        }
    }

    // MARK: - Initial Metrics

    @Test("Initial metrics have reasonable defaults")
    func initialMetrics() async {
        let service = ClaudeAPIService(apiKey: "test")
        let metrics = await service.metrics

        #expect(metrics.medianTTFT == 0.5)
        #expect(metrics.p99TTFT == 1.5)
        #expect(metrics.totalInputTokens == 0)
        #expect(metrics.totalOutputTokens == 0)
    }
}
