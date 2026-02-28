// CyranoChat - Playable Segment Protocol
// Defines the interface for segments in the AudioPlaybackOrchestrator

import Foundation

// MARK: - Cached Audio

/// Cached audio data for a segment
public struct CachedSegmentAudio: Sendable {
    public let audioData: Data
    public let format: TTSAudioFormat

    public init(audioData: Data, format: TTSAudioFormat) {
        self.audioData = audioData
        self.format = format
    }

    /// Convert to TTSAudioChunk for playback
    public func toTTSAudioChunk() -> TTSAudioChunk {
        TTSAudioChunk(
            audioData: audioData,
            format: format,
            sequenceNumber: 0,
            isFirst: true,
            isLast: true
        )
    }
}

// MARK: - Playable Segment Protocol

/// Protocol for segments that can be played by the AudioPlaybackOrchestrator
public protocol PlayableSegment: Sendable {
    /// Index of this segment in the playback queue
    var segmentIndex: Int { get }

    /// Text content of this segment (used for TTS synthesis if no cached audio)
    var segmentText: String { get }

    /// Pre-generated cached audio (skips TTS synthesis if available)
    var cachedAudio: CachedSegmentAudio? { get }
}

// MARK: - Simple Text Segment

/// Simple implementation of PlayableSegment for text-based playback
public struct TextSegment: PlayableSegment {
    public let segmentIndex: Int
    public let segmentText: String
    public let cachedAudio: CachedSegmentAudio?

    public init(index: Int, text: String, cachedAudio: CachedSegmentAudio? = nil) {
        self.segmentIndex = index
        self.segmentText = text
        self.cachedAudio = cachedAudio
    }
}
