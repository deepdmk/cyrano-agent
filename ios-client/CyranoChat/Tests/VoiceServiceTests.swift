// CyranoChat Tests - Voice Service Protocol Types

import Testing
import Foundation
@testable import CyranoChat

@Suite("Voice Service Types")
struct VoiceServiceTests {

    // MARK: - VADResult

    @Test("VADResult stores speech detection")
    func vadResultSpeech() {
        let result = VADResult(isSpeech: true, confidence: 0.9)

        #expect(result.isSpeech == true)
        #expect(result.confidence == 0.9)
    }

    @Test("VADResult clamps confidence to 0-1")
    func vadResultClamping() {
        let over = VADResult(isSpeech: true, confidence: 1.5)
        #expect(over.confidence == 1.0)

        let under = VADResult(isSpeech: false, confidence: -0.5)
        #expect(under.confidence == 0.0)
    }

    @Test("VADResult has timestamp")
    func vadResultTimestamp() {
        let before = Date().timeIntervalSince1970
        let result = VADResult(isSpeech: false, confidence: 0)
        let after = Date().timeIntervalSince1970

        #expect(result.timestamp >= before)
        #expect(result.timestamp <= after)
    }

    // MARK: - VADConfiguration

    @Test("Default VAD configuration values")
    func vadConfigDefault() {
        let config = VADConfiguration.default

        #expect(config.threshold == 0.5)
        #expect(config.contextWindow == 3)
        #expect(config.smoothingWindow == 5)
        #expect(config.minSpeechDuration == 0.1)
        #expect(config.minSilenceDuration == 0.5)
    }

    @Test("Custom VAD configuration")
    func vadConfigCustom() {
        let config = VADConfiguration(
            threshold: 0.7,
            contextWindow: 5,
            smoothingWindow: 3,
            minSpeechDuration: 0.2,
            minSilenceDuration: 1.0
        )

        #expect(config.threshold == 0.7)
        #expect(config.contextWindow == 5)
    }

    // MARK: - STTResult

    @Test("STTResult stores transcript")
    func sttResult() {
        let result = STTResult(
            transcript: "Hello world",
            isFinal: true,
            isEndOfUtterance: true,
            confidence: 0.95
        )

        #expect(result.transcript == "Hello world")
        #expect(result.isFinal == true)
        #expect(result.isEndOfUtterance == true)
        #expect(result.confidence == 0.95)
    }

    @Test("STTResult partial result")
    func sttPartialResult() {
        let result = STTResult(
            transcript: "Hel",
            isFinal: false,
            isEndOfUtterance: false,
            confidence: 0.5
        )

        #expect(result.isFinal == false)
        #expect(result.isEndOfUtterance == false)
    }

    // MARK: - TTSVoiceConfig

    @Test("Default voice config")
    func ttsVoiceConfigDefault() {
        let config = TTSVoiceConfig.default

        #expect(config.voiceId == "default")
        #expect(config.rate == 1.0)
        #expect(config.pitch == 0.0)
        #expect(config.volume == 1.0)
    }

    @Test("Custom voice config")
    func ttsVoiceConfigCustom() {
        let config = TTSVoiceConfig(
            voiceId: "com.apple.voice.compact.en-US.Samantha",
            rate: 1.2,
            pitch: 0.3,
            volume: 0.8
        )

        #expect(config.voiceId == "com.apple.voice.compact.en-US.Samantha")
        #expect(config.rate == 1.2)
        #expect(config.pitch == 0.3)
        #expect(config.volume == 0.8)
    }

    @Test("TTSVoiceConfig is Codable")
    func ttsVoiceConfigCodable() throws {
        let original = TTSVoiceConfig(voiceId: "test", rate: 1.5, pitch: -0.5, volume: 0.7)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TTSVoiceConfig.self, from: data)

        #expect(decoded.voiceId == original.voiceId)
        #expect(decoded.rate == original.rate)
        #expect(decoded.pitch == original.pitch)
        #expect(decoded.volume == original.volume)
    }

    // MARK: - TTSMetrics

    @Test("TTS metrics store values")
    func ttsMetrics() {
        let metrics = TTSMetrics(medianTTFB: 0.1, p99TTFB: 0.3)

        #expect(metrics.medianTTFB == 0.1)
        #expect(metrics.p99TTFB == 0.3)
    }

    // MARK: - STTMetrics

    @Test("STT metrics store values")
    func sttMetrics() {
        let metrics = STTMetrics(medianLatency: 0.15, p99Latency: 0.3, wordEmissionRate: 2.5)

        #expect(metrics.medianLatency == 0.15)
        #expect(metrics.p99Latency == 0.3)
        #expect(metrics.wordEmissionRate == 2.5)
    }

    // MARK: - Provider Enums

    @Test("STT providers include Apple Speech")
    func sttProviders() {
        let apple = STTProvider.appleSpeech
        #expect(apple.isOnDevice == true)
        #expect(apple.requiresNetwork == false)
        #expect(apple.costPerHour == 0)
    }

    @Test("STT providers include GLM-ASR")
    func sttGLMASR() {
        let glm = STTProvider.glmASROnDevice
        #expect(glm.isOnDevice == true)
        #expect(glm.costPerHour == 0)
    }

    @Test("TTS providers include Apple TTS")
    func ttsProviders() {
        let apple = TTSProvider.appleTTS
        #expect(apple.isOnDevice == true)
        #expect(apple.requiresNetwork == false)
        #expect(apple.requiresAPIKey == false)
    }

    @Test("TTS providers include Pocket TTS")
    func ttsPocketTTS() {
        let pocket = TTSProvider.pocketTTS
        #expect(pocket.isOnDevice == true)
        #expect(pocket.requiresNetwork == false)
        #expect(pocket.sampleRate == 24000)
    }

    @Test("All TTS providers have display names")
    func ttsProviderNames() {
        for provider in TTSProvider.allCases {
            #expect(!provider.displayName.isEmpty)
            #expect(!provider.identifier.isEmpty)
            #expect(!provider.providerDescription.isEmpty)
        }
    }

    @Test("All STT providers have identifiers")
    func sttProviderIdentifiers() {
        for provider in STTProvider.allCases {
            #expect(!provider.displayName.isEmpty)
            #expect(!provider.identifier.isEmpty)
        }
    }

    // MARK: - Audio Config

    @Test("Default audio config has expected values")
    func audioConfigDefault() {
        let config = AudioEngineConfig.default

        #expect(config.sampleRate == 48000)
        #expect(config.channels == 1)
        #expect(config.enableVoiceProcessing == true)
        #expect(config.enableEchoCancellation == true)
        #expect(config.enableBargeIn == true)
        #expect(config.bargeInThreshold == 0.7)
        #expect(config.bufferSize == 1024)
    }

    @Test("Low latency config has lower thresholds")
    func audioConfigLowLatency() {
        let config = AudioEngineConfig.lowLatency

        #expect(config.sampleRate == 24000)
        #expect(config.vadThreshold == 0.4)
        #expect(config.bargeInThreshold == 0.6)
        #expect(config.bufferSize == 512)
    }

    @Test("BitDepth maps to correct AVAudioCommonFormat")
    func bitDepthMapping() {
        #expect(BitDepth.float32.avFormat == .pcmFormatFloat32)
        #expect(BitDepth.int16.avFormat == .pcmFormatInt16)
        #expect(BitDepth.int32.avFormat == .pcmFormatInt32)
    }

    // MARK: - Error Types

    @Test("STT errors have descriptions")
    func sttErrors() {
        let errors: [STTError] = [
            .connectionFailed("test"),
            .streamingFailed("test"),
            .invalidAudioFormat,
            .notStreaming,
            .alreadyStreaming,
            .authenticationFailed,
            .rateLimited,
            .quotaExceeded
        ]

        for error in errors {
            #expect(error.localizedDescription.count > 0)
        }
    }

    @Test("TTS errors have descriptions")
    func ttsErrors() {
        let errors: [TTSError] = [
            .synthesizeFailed("test"),
            .invalidAudioFormat,
            .bufferCreationFailed,
            .connectionFailed("test"),
            .authenticationFailed,
            .rateLimited,
            .quotaExceeded,
            .voiceNotFound("test")
        ]

        for error in errors {
            #expect(error.localizedDescription.count > 0)
        }
    }

    @Test("VAD errors have descriptions")
    func vadErrors() {
        let errors: [VADError] = [
            .modelLoadFailed("test"),
            .processingFailed("test"),
            .invalidAudioFormat,
            .notPrepared,
            .configurationError("test")
        ]

        for error in errors {
            #expect(error.localizedDescription.count > 0)
        }
    }

    @Test("AudioEngine errors have descriptions")
    func audioErrors() {
        let errors: [AudioEngineError] = [
            .audioSessionConfigurationFailed("test"),
            .engineStartFailed("test"),
            .voiceProcessingNotAvailable,
            .invalidConfiguration("test"),
            .notRunning,
            .alreadyRunning,
            .playbackFailed("test"),
            .bufferConversionFailed
        ]

        for error in errors {
            #expect(error.localizedDescription.count > 0)
        }
    }
}
