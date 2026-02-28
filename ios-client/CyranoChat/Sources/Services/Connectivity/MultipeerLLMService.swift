// CyranoChat - MultipeerConnectivity LLM Service
// Conforms to LLMService protocol, routes chat requests through MC to the macOS server

import Foundation
import Logging

/// LLM service that sends chat requests to the macOS server via MultipeerConnectivity
public actor MultipeerLLMService: LLMService {

    private let sessionManager: MultipeerSessionManager
    private let logger = Logger(label: "com.cyrano.llm.multipeer")

    public private(set) var metrics = LLMMetrics(
        medianTTFT: 0.3,
        p99TTFT: 1.0,
        totalInputTokens: 0,
        totalOutputTokens: 0
    )

    // Server handles billing — costs are irrelevant on the client
    public var costPerInputToken: Decimal { 0 }
    public var costPerOutputToken: Decimal { 0 }
    public var contextWindowSize: Int { 200_000 }

    init(sessionManager: MultipeerSessionManager) {
        self.sessionManager = sessionManager
    }

    public func streamCompletion(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> AsyncStream<LLMToken> {
        // Check connection
        let state = await sessionManager.connectionState
        guard state == .connected else {
            throw LLMError.connectionFailed("Not connected to server")
        }

        let requestId = UUID().uuidString

        // Convert LLMMessage -> WireMessage
        let wireMessages = messages.map { WireMessage(role: $0.role.rawValue, content: $0.content) }
        let wireConfig = WireConfig(
            model: config.model,
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            systemPrompt: config.systemPrompt
        )

        // Register response stream before sending to avoid race
        let tokenStream = await sessionManager.registerTokenStream(requestId: requestId)

        // Build and send chat request
        let requestPayload = ChatRequestPayload(
            requestId: requestId,
            messages: wireMessages,
            config: wireConfig
        )

        do {
            let data = try CyranoMessage.encode(.chatRequest, payload: requestPayload)
            try await sessionManager.send(data)
        } catch {
            await sessionManager.unregisterResponseStream(requestId: requestId)
            throw LLMError.connectionFailed("Failed to send request: \(error.localizedDescription)")
        }

        // Transform token stream into LLMToken stream
        let mgr = sessionManager
        return AsyncStream<LLMToken> { continuation in
            Task { [tokenStream] in
                for await tokenPayload in tokenStream {
                    let token = LLMToken(
                        content: tokenPayload.content,
                        isDone: false
                    )
                    continuation.yield(token)
                }

                // Stream ended — check if there was an error
                if let errorMsg = await mgr.lastError(for: requestId) {
                    continuation.yield(LLMToken(
                        content: "[Error: \(errorMsg)]",
                        isDone: true
                    ))
                } else {
                    continuation.yield(LLMToken(content: "", isDone: true, stopReason: .endTurn))
                }

                continuation.finish()
            }
        }
    }

    public func estimateTokenCount(_ text: String) -> Int {
        max(1, text.count * 10 / 35)
    }
}
