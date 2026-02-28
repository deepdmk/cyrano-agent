// CyranoChat - Claude API Service
// Anthropic Messages API with SSE streaming, implementing LLMService protocol

import Foundation
import Logging

/// Claude API service using the Anthropic Messages API
///
/// Supports streaming completions via Server-Sent Events (SSE).
/// Configurable model selection (Sonnet, Haiku, Opus).
public actor ClaudeAPIService: LLMService {

    // MARK: - Properties

    private let logger = Logger(label: "com.cyrano.llm.claude")
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let session: URLSession

    public private(set) var metrics = LLMMetrics(
        medianTTFT: 0.5,
        p99TTFT: 1.5,
        totalInputTokens: 0,
        totalOutputTokens: 0
    )

    public var costPerInputToken: Decimal {
        // Claude Sonnet: $3/M input tokens
        Decimal(string: "0.000003")!
    }

    public var costPerOutputToken: Decimal {
        // Claude Sonnet: $15/M output tokens
        Decimal(string: "0.000015")!
    }

    public var contextWindowSize: Int { 200_000 }

    // MARK: - Initialization

    public init(apiKey: String) {
        self.apiKey = apiKey
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        logger.info("ClaudeAPIService initialized")
    }

    // MARK: - LLMService Protocol

    public func streamCompletion(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> AsyncStream<LLMToken> {
        let request = try buildRequest(messages: messages, config: config)
        let startTime = Date()

        logger.info("Starting Claude stream", metadata: [
            "model": .string(config.model),
            "maxTokens": .stringConvertible(config.maxTokens)
        ])

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.connectionFailed("Invalid response type")
        }

        try validateResponse(httpResponse)

        return AsyncStream { continuation in
            let task = Task {
                var isFirstToken = true
                var eventType = ""
                var dataBuffer = ""

                do {
                    for try await line in bytes.lines {
                        if Task.isCancelled { break }

                        if line.hasPrefix("event: ") {
                            eventType = String(line.dropFirst(7))
                            continue
                        }

                        if line.hasPrefix("data: ") {
                            dataBuffer = String(line.dropFirst(6))

                            if let token = parseSSEData(
                                eventType: eventType,
                                data: dataBuffer,
                                isFirstToken: &isFirstToken,
                                startTime: startTime
                            ) {
                                continuation.yield(token)
                                if token.isDone {
                                    break
                                }
                            }

                            eventType = ""
                            dataBuffer = ""
                        }
                    }
                } catch {
                    if !Task.isCancelled {
                        logger.error("Stream error: \(error.localizedDescription)")
                    }
                }

                continuation.finish()
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    // MARK: - Request Building

    private func buildRequest(messages: [LLMMessage], config: LLMConfig) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // Separate system prompt from messages
        var systemPrompt: String? = config.systemPrompt
        var apiMessages: [[String: String]] = []

        for message in messages {
            if message.role == .system {
                systemPrompt = message.content
            } else {
                apiMessages.append([
                    "role": message.role.rawValue,
                    "content": message.content
                ])
            }
        }

        // Build request body
        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "stream": true
        ]

        body["temperature"] = config.temperature

        if let topP = config.topP {
            body["top_p"] = topP
        }

        if let system = systemPrompt {
            body["system"] = system
        }

        if let stopSequences = config.stopSequences, !stopSequences.isEmpty {
            body["stop_sequences"] = stopSequences
        }

        body["messages"] = apiMessages

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    // MARK: - Response Parsing

    private func validateResponse(_ response: HTTPURLResponse) throws {
        switch response.statusCode {
        case 200:
            return
        case 401:
            throw LLMError.authenticationFailed
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "retry-after")
                .flatMap { TimeInterval($0) }
            throw LLMError.rateLimited(retryAfter: retryAfter)
        case 400:
            throw LLMError.invalidRequest("Bad request (400)")
        case 404:
            throw LLMError.modelNotFound("Model not found")
        case 529:
            throw LLMError.connectionFailed("API overloaded (529)")
        default:
            throw LLMError.connectionFailed("HTTP \(response.statusCode)")
        }
    }

    private nonisolated func parseSSEData(
        eventType: String,
        data: String,
        isFirstToken: inout Bool,
        startTime: Date
    ) -> LLMToken? {
        guard let jsonData = data.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
              let type = json["type"] as? String else {
            return nil
        }

        switch type {
        case "content_block_delta":
            guard let delta = json["delta"] as? [String: Any],
                  let text = delta["text"] as? String else {
                return nil
            }

            var ttft: TimeInterval? = nil
            if isFirstToken {
                ttft = Date().timeIntervalSince(startTime)
                isFirstToken = false
            }
            _ = ttft // TTFT tracking for future metrics

            return LLMToken(content: text, isDone: false)

        case "message_stop":
            return LLMToken(content: "", isDone: true, stopReason: .endTurn)

        case "message_delta":
            if let delta = json["delta"] as? [String: Any],
               let stopReason = delta["stop_reason"] as? String {
                let reason = StopReason(rawValue: stopReason) ?? .endTurn
                return LLMToken(content: "", isDone: true, stopReason: reason)
            }
            return nil

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                // Return as a token so the UI can display it
                return LLMToken(content: "[Error: \(message)]", isDone: true)
            }
            return nil

        default:
            return nil
        }
    }

    // MARK: - Token Estimation

    public func estimateTokenCount(_ text: String) -> Int {
        // Claude uses ~3.5 chars per token for English
        max(1, text.count * 10 / 35)
    }
}
