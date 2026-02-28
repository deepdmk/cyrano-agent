// CyranoServer - Server Configuration
// Loads API key and settings from environment or .env file

import Foundation

struct ServerConfig {
    let apiKey: String
    let defaultModel: String
    let defaultSystemPrompt: String
    let serverDisplayName: String

    static func load() throws -> ServerConfig {
        let apiKey: String
        if let envKey = ProcessInfo.processInfo.environment["ANTHROPIC_API_KEY"], !envKey.isEmpty {
            apiKey = envKey
        } else if let dotenvKey = loadFromDotenv(key: "ANTHROPIC_API_KEY") {
            apiKey = dotenvKey
        } else {
            throw ConfigError.missingAPIKey(
                "Set ANTHROPIC_API_KEY environment variable or create a .env file in macos-server/"
            )
        }

        let model = ProcessInfo.processInfo.environment["CYRANO_MODEL"]
            ?? "claude-sonnet-4-6-20250620"

        let systemPrompt = ProcessInfo.processInfo.environment["CYRANO_SYSTEM_PROMPT"]
            ?? "You are Cyrano, a helpful AI assistant. Keep responses concise and conversational."

        return ServerConfig(
            apiKey: apiKey,
            defaultModel: model,
            defaultSystemPrompt: systemPrompt,
            serverDisplayName: Host.current().localizedName ?? "CyranoServer"
        )
    }

    private static func loadFromDotenv(key: String) -> String? {
        // Look for .env in the app's working directory
        let candidates = [
            URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent(".env"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent(".env")
        ]

        for envPath in candidates {
            guard let contents = try? String(contentsOf: envPath, encoding: .utf8) else { continue }
            for line in contents.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#") || trimmed.isEmpty { continue }
                let parts = trimmed.split(separator: "=", maxSplits: 1)
                if parts.count == 2 && String(parts[0]).trimmingCharacters(in: .whitespaces) == key {
                    return String(parts[1])
                        .trimmingCharacters(in: .whitespaces)
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                }
            }
        }
        return nil
    }
}

enum ConfigError: Error, LocalizedError {
    case missingAPIKey(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey(let msg): return msg
        }
    }
}
