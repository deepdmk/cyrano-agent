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

    public init(sessionManager: MultipeerSessionManager) {
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
        let registration = await sessionManager.registerResponseStream(requestId: requestId)

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

        // Track errors for the stream
        let errorRef = ErrorRef()

        // Set up error handler
        let onError = registration.onError
        let onComplete = registration.onComplete

        // Wrap error/complete into the stream lifecycle
        // Errors from the server will terminate the token stream
        Task { @MainActor in
            // Replace the handlers to capture error info
            let originalErrorHandler = onError
            sessionManager.errorHandlers[requestId] = { payload in
                Task {
                    await errorRef.set(LLMError.streamFailed(payload.errorMessage))
                }
                originalErrorHandler(payload)
            }
        }

        // Transform token stream into LLMToken stream
        return AsyncStream<LLMToken> { continuation in
            Task {
                for await tokenPayload in registration.tokens {
                    let token = LLMToken(
                        content: tokenPayload.content,
                        isDone: false
                    )
                    continuation.yield(token)
                }

                // Stream ended — check if it was an error or normal completion
                if let error = await errorRef.get() {
                    // Yield an error token so the UI shows it
                    continuation.yield(LLMToken(
                        content: "[Error: \(error.localizedDescription)]",
                        isDone: true
                    ))
                } else {
                    // Normal completion
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

// Thread-safe error holder
private actor ErrorRef {
    private var error: LLMError?

    func set(_ error: LLMError) {
        self.error = error
    }

    func get() -> LLMError? {
        error
    }
}
