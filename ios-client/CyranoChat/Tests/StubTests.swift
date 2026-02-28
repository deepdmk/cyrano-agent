// CyranoChat Tests - Stub Types

import Testing
import Foundation
@testable import CyranoChat

@Suite("Stub Types")
struct StubTests {

    @Test("TelemetryEngine recordEvent does not crash")
    func telemetryRecordEvent() async {
        let engine = TelemetryEngine()
        await engine.recordEvent(.audioEngineStarted)
        await engine.recordEvent(.audioEngineStopped)
        await engine.recordEvent(.vadSpeechDetected(confidence: 0.8))
        await engine.recordEvent(.ttsPlaybackStarted)
        await engine.recordEvent(.ttsPlaybackCompleted)
        await engine.recordEvent(.ttsPlaybackInterrupted)
        await engine.recordEvent(.ttsPlaybackPaused)
        await engine.recordEvent(.ttsPlaybackResumed)
    }

    @Test("TelemetryEngine recordLatency does not crash")
    func telemetryRecordLatency() async {
        let engine = TelemetryEngine()
        await engine.recordLatency(.audioProcessing, 0.05)
        await engine.recordLatency(.ttsTimeToFirstByte, 0.2)
        await engine.recordLatency(.llmTimeToFirstToken, 0.5)
        await engine.recordLatency(.sttLatency, 0.15)
    }

    @Test("TTFAInstrumentation shared instance exists")
    func ttfaSharedInstance() async {
        let instance = TTFAInstrumentation.shared
        // Should not crash
        await instance.markAudioScheduled()
        await instance.markAudioPlaying()
        await instance.markCachedHit()
        await instance.markTTSFirstChunk()
    }

    @Test("TelemetryEvent has all expected cases")
    func telemetryEventCases() {
        // Verify all cases compile - this is a compile-time check
        let events: [TelemetryEvent] = [
            .audioEngineConfigured(.default),
            .audioEngineStarted,
            .audioEngineStopped,
            .vadSpeechDetected(confidence: 0.5),
            .thermalStateChanged(.nominal),
            .adaptiveQualityAdjusted(reason: "test"),
            .ttsPlaybackStarted,
            .ttsPlaybackCompleted,
            .ttsPlaybackInterrupted,
            .ttsPlaybackPaused,
            .ttsPlaybackResumed
        ]
        #expect(events.count == 11)
    }
}
