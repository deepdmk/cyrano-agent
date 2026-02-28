// CyranoChat - Apple TTS Service
// On-device Text-to-Speech using AVSpeechSynthesizer, implementing TTSService protocol
//
// v1 fallback TTS provider. Will be replaced by Pocket TTS when Rust XCFramework is compiled.

@preconcurrency import AVFoundation
import Logging

/// On-device TTS using Apple's AVSpeechSynthesizer
///
/// Uses `write(_:toBufferCallback:)` (iOS 16+) to capture PCM audio buffers
/// that can be played through AudioEngine, preserving the protocol abstraction.
public actor AppleTTSService: TTSService {

    // MARK: - Properties

    private let logger = Logger(label: "com.cyrano.tts.apple")
    private let synthesizer = AVSpeechSynthesizer()

    public private(set) var metrics = TTSMetrics(
        medianTTFB: 0.1,
        p99TTFB: 0.3
    )

    public var costPerCharacter: Decimal { 0 }

    public private(set) var voiceConfig: TTSVoiceConfig = .default

    // MARK: - Initialization

    public init() {
        logger.info("AppleTTSService initialized")
    }

    // MARK: - TTSService Protocol

    public func configure(_ config: TTSVoiceConfig) async {
        self.voiceConfig = config
        logger.debug("Configured voice: \(config.voiceId), rate: \(config.rate)")
    }

    public func synthesize(text: String) async throws -> AsyncStream<TTSAudioChunk> {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return AsyncStream { $0.finish() }
        }

        logger.debug("Synthesizing: \(text.prefix(50))...")

        let utterance = AVSpeechUtterance(string: text)

        // Apply voice configuration
        if voiceConfig.voiceId != "default",
           let voice = AVSpeechSynthesisVoice(identifier: voiceConfig.voiceId) {
            utterance.voice = voice
        } else {
            utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        }

        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * voiceConfig.rate
        utterance.pitchMultiplier = 1.0 + voiceConfig.pitch * 0.5
        utterance.volume = voiceConfig.volume

        let startTime = Date()

        return AsyncStream { continuation in
            var sequenceNumber = 0
            var isFirst = true

            self.synthesizer.write(utterance) { buffer in
                guard let pcmBuffer = buffer as? AVAudioPCMBuffer,
                      pcmBuffer.frameLength > 0 else {
                    // Empty buffer signals completion
                    if sequenceNumber > 0 {
                        continuation.finish()
                    }
                    return
                }

                // Extract audio data from buffer
                let format = pcmBuffer.format
                let sampleRate = format.sampleRate
                let channels = format.channelCount

                let audioData: Data
                let ttsFormat: TTSAudioFormat

                if format.commonFormat == .pcmFormatFloat32,
                   let channelData = pcmBuffer.floatChannelData?[0] {
                    let byteCount = Int(pcmBuffer.frameLength) * MemoryLayout<Float>.size
                    audioData = Data(bytes: channelData, count: byteCount)
                    ttsFormat = .pcmFloat32(sampleRate: sampleRate, channels: UInt32(channels))
                } else if format.commonFormat == .pcmFormatInt16,
                          let channelData = pcmBuffer.int16ChannelData?[0] {
                    let byteCount = Int(pcmBuffer.frameLength) * MemoryLayout<Int16>.size
                    audioData = Data(bytes: channelData, count: byteCount)
                    ttsFormat = .pcmInt16(sampleRate: sampleRate, channels: UInt32(channels))
                } else {
                    return
                }

                let ttfb: TimeInterval? = isFirst ? Date().timeIntervalSince(startTime) : nil

                let chunk = TTSAudioChunk(
                    audioData: audioData,
                    format: ttsFormat,
                    sequenceNumber: sequenceNumber,
                    isFirst: isFirst,
                    isLast: false, // We don't know until we get the empty callback
                    timeToFirstByte: ttfb
                )

                isFirst = false
                sequenceNumber += 1
                continuation.yield(chunk)
            }
        }
    }

    public func flush() async throws {
        synthesizer.stopSpeaking(at: .immediate)
    }

    // MARK: - Voice Listing

    /// Get available system voices for the settings UI
    public static func availableVoices() -> [(id: String, name: String, language: String)] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
            .sorted { $0.name < $1.name }
            .map { (id: $0.identifier, name: $0.name, language: $0.language) }
    }
}
