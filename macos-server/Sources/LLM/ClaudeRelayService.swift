// CyranoServer - Claude Relay Service
// Calls Claude API and relays streaming tokens via callback
// Adapted from ios-client ClaudeAPIService.swift

import Foundation
import Logging

actor ClaudeRelayService {

    private let logger = Logger(label: "com.cyrano.server.claude")
    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let apiVersion = "2023-06-01"
    private let session: URLSession
    private let defaultSystemPrompt: String

    init(apiKey: String, defaultSystemPrompt: String) {
        self.apiKey = apiKey
        self.defaultSystemPrompt = defaultSystemPrompt
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 120
        config.timeoutIntervalForResource = 300
        self.session = URLSession(configuration: config)
        logger.info("ClaudeRelayService initialized")
    }

    /// Stream a completion, calling tokenHandler for each token.
    /// tokenHandler receives (content, isDone, stopReason).
    func streamCompletion(
        messages: [WireMessage],
        config: WireConfig,
        tokenHandler: @Sendable (String, Bool, String?) async -> Void
    ) async throws {
        let request = try buildRequest(messages: messages, config: config)

        logger.info("Starting Claude stream", metadata: [
            "model": .string(config.model),
            "maxTokens": .stringConvertible(config.maxTokens)
        ])

        let (bytes, response) = try await session.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RelayError.connectionFailed("Invalid response type")
        }

        try validateResponse(httpResponse)

        var eventType = ""

        for try await line in bytes.lines {
            if Task.isCancelled { break }

            if line.hasPrefix("event: ") {
                eventType = String(line.dropFirst(7))
                continue
            }

            if line.hasPrefix("data: ") {
                let data = String(line.dropFirst(6))
                if let (content, isDone, stopReason) = parseSSEData(eventType: eventType, data: data) {
                    await tokenHandler(content, isDone, stopReason)
                    if isDone { break }
                }
                eventType = ""
            }
        }
    }

    // MARK: - Request Building

    private func buildRequest(messages: [WireMessage], config: WireConfig) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(apiVersion, forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        // Separate system prompt from messages
        var systemPrompt = config.systemPrompt ?? defaultSystemPrompt
        var apiMessages: [[String: String]] = []

        for message in messages {
            if message.role == "system" {
                systemPrompt = message.content
            } else {
                apiMessages.append([
                    "role": message.role,
                    "content": message.content
                ])
            }
        }

        var body: [String: Any] = [
            "model": config.model,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "stream": true
        ]

        if !systemPrompt.isEmpty {
            body["system"] = systemPrompt
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
            throw RelayError.authenticationFailed
        case 429:
            let retryAfter = response.value(forHTTPHeaderField: "retry-after")
                .flatMap { TimeInterval($0) }
            throw RelayError.rateLimited(retryAfter: retryAfter)
        case 400:
            throw RelayError.invalidRequest("Bad request (400)")
        case 404:
            throw RelayError.modelNotFound
        case 529:
            throw RelayError.serviceUnavailable
        default:
            throw RelayError.connectionFailed("HTTP \(response.statusCode)")
        }
    }

    private nonisolated func parseSSEData(eventType: String, data: String) -> (String, Bool, String?)? {
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
            return (text, false, nil)

        case "message_stop":
            return ("", true, "end_turn")

        case "message_delta":
            if let delta = json["delta"] as? [String: Any],
               let stopReason = delta["stop_reason"] as? String {
                return ("", true, stopReason)
            }
            return nil

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                return ("[Error: \(message)]", true, nil)
            }
            return nil

        default:
            return nil
        }
    }
}

// MARK: - Errors

enum RelayError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed
    case rateLimited(retryAfter: TimeInterval?)
    case invalidRequest(String)
    case modelNotFound
    case serviceUnavailable

    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authenticationFailed: return "Invalid API key"
        case .rateLimited(let r):
            if let delay = r { return "Rate limited. Retry after \(Int(delay))s." }
            return "Rate limited"
        case .invalidRequest(let msg): return "Invalid request: \(msg)"
        case .modelNotFound: return "Model not found"
        case .serviceUnavailable: return "Claude API overloaded"
        }
    }

    var errorCode: String {
        switch self {
        case .connectionFailed: return "connection_failed"
        case .authenticationFailed: return "auth_failed"
        case .rateLimited: return "rate_limited"
        case .invalidRequest: return "invalid_request"
        case .modelNotFound: return "model_not_found"
        case .serviceUnavailable: return "service_unavailable"
        }
    }

    var retryAfter: TimeInterval? {
        if case .rateLimited(let r) = self { return r }
        return nil
    }
}
