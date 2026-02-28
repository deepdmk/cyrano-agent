// CyranoChat - Stub Types
// No-op stubs for dependencies not yet available in v1
// These will be replaced with real implementations as frameworks are integrated

import Foundation

// MARK: - Telemetry Stubs

/// Telemetry events recorded by AudioEngine and other services
public enum TelemetryEvent: Sendable {
    case audioEngineConfigured(AudioEngineConfig)
    case audioEngineStarted
    case audioEngineStopped
    case vadSpeechDetected(confidence: Float)
    case thermalStateChanged(ProcessInfo.ThermalState)
    case adaptiveQualityAdjusted(reason: String)
    case ttsPlaybackStarted
    case ttsPlaybackCompleted
    case ttsPlaybackInterrupted
    case ttsPlaybackPaused
    case ttsPlaybackResumed
}

/// Latency metrics tracked by the system
public enum LatencyMetric: Sendable {
    case audioProcessing
    case ttsTimeToFirstByte
    case llmTimeToFirstToken
    case sttLatency
}

/// No-op telemetry engine for v1
public actor TelemetryEngine {
    public init() {}

    public func recordEvent(_ event: TelemetryEvent) {
        // No-op in v1
    }

    public func recordLatency(_ metric: LatencyMetric, _ value: TimeInterval) {
        // No-op in v1
    }
}

// MARK: - TTFA Instrumentation Stub

/// No-op Time-To-First-Audio instrumentation for v1
public actor TTFAInstrumentation {
    public static let shared = TTFAInstrumentation()

    private init() {}

    public func markAudioScheduled() {}
    public func markAudioPlaying() {}
    public func markCachedHit() {}
    public func markTTSFirstChunk() {}
}
