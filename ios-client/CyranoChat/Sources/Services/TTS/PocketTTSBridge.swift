// CyranoChat - Pocket TTS Rust Bridge Stubs
// Placeholder types for KyutaiPocketTTSService compilation
// Replace with actual PocketTTS XCFramework when Rust build is ready

import Foundation

// MARK: - Rust Bridge Stubs

/// Stub for Rust PocketTtsEngine - replace with XCFramework import
public class PocketTtsEngine {
    private let modelPath: String

    public init(modelPath: String) throws {
        self.modelPath = modelPath
        // Rust engine not yet available
        throw PocketTtsError.engineNotAvailable
    }

    public func configure(config: TtsConfig) throws {
        throw PocketTtsError.engineNotAvailable
    }

    public func startTrueStreaming(text: String, handler: TtsEventHandler) throws {
        throw PocketTtsError.engineNotAvailable
    }

    public func isReady() -> Bool { false }
    public func unload() {}
    public func modelVersion() -> String { "pending" }
    public func parameterCount() -> Int { 0 }

    public func setReferenceAudio(audioData: Data, sampleRate: Int) throws {
        throw PocketTtsError.engineNotAvailable
    }

    public func clearReferenceAudio() {}
}

/// Stub for Rust TtsConfig
public struct TtsConfig {
    public let voiceIndex: UInt32
    public let temperature: Float
    public let topP: Float
    public let speed: Float
    public let consistencySteps: UInt32
    public let useFixedSeed: Bool
    public let seed: Int

    public init(
        voiceIndex: UInt32,
        temperature: Float,
        topP: Float,
        speed: Float,
        consistencySteps: UInt32,
        useFixedSeed: Bool,
        seed: Int
    ) {
        self.voiceIndex = voiceIndex
        self.temperature = temperature
        self.topP = topP
        self.speed = speed
        self.consistencySteps = consistencySteps
        self.useFixedSeed = useFixedSeed
        self.seed = seed
    }
}

/// Stub for Rust TtsEventHandler protocol
public protocol TtsEventHandler: AnyObject {
    func onAudioChunk(chunk: AudioChunk)
    func onProgress(progress: Float)
    func onComplete()
    func onError(message: String)
}

/// Stub for Rust AudioChunk
public struct AudioChunk {
    public let audioData: Data
    public let sampleRate: UInt32
    public let isFinal: Bool

    public init(audioData: Data, sampleRate: UInt32, isFinal: Bool) {
        self.audioData = audioData
        self.sampleRate = sampleRate
        self.isFinal = isFinal
    }
}

/// Stub for Rust PocketTtsError
public enum PocketTtsError: Error, LocalizedError {
    case engineNotAvailable
    case modelLoadFailed(String)
    case synthesisFailed(String)

    public var errorDescription: String? {
        switch self {
        case .engineNotAvailable:
            return "Pocket TTS Rust engine is not yet available. Install the PocketTTS XCFramework."
        case .modelLoadFailed(let msg):
            return "Model load failed: \(msg)"
        case .synthesisFailed(let msg):
            return "Synthesis failed: \(msg)"
        }
    }
}

/// Stub for VoiceInfo from Rust
public struct VoiceInfo {
    public let id: String
    public let name: String
    public let language: String
    public let gender: VoiceGender

    public init(id: String, name: String, language: String, gender: VoiceGender) {
        self.id = id
        self.name = name
        self.language = language
        self.gender = gender
    }
}

/// Stub: Returns built-in voice list (no Rust engine needed)
public func availableVoices() -> [(index: Int, name: String, gender: VoiceGender)] {
    KyutaiPocketVoice.allCases.map { ($0.rawValue, $0.displayName, $0.gender) }
}

/// Stub: Returns version string
public func version() -> String {
    "0.1.0-stub"
}
