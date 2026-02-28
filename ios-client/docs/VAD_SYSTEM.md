# Voice Activity Detection (VAD)

The VAD system detects when the user is speaking. It runs continuously on every captured audio frame, enabling real-time speech/silence discrimination for turn-taking and barge-in detection.

## Model: Silero VAD

- **Architecture**: LSTM-based neural network
- **Framework**: CoreML (optimized for Neural Engine)
- **Compute Units**: `.cpuAndNeuralEngine`
- **Expected Sample Rate**: 16kHz
- **Frame Size**: 512 samples (32ms at 16kHz)
- **Model File**: `silero_vad.mlmodelc` (bundled in app)
- **Latency**: ~20-30ms per frame
- **Hidden State**: 2x1x64 LSTM tensors (maintained across frames)

## Protocol

```swift
public protocol VADService: Actor {
    var configuration: VADConfiguration { get }
    var isActive: Bool { get }

    func configure(threshold: Float, contextWindow: Int) async
    func configure(_ configuration: VADConfiguration) async
    func processBuffer(_ buffer: AVAudioPCMBuffer) async -> VADResult
    func reset() async
    func prepare() async throws
    func shutdown() async
}
```

## VAD Result

```swift
public struct VADResult: Sendable {
    public let isSpeech: Bool          // Whether speech was detected
    public let confidence: Float        // 0.0 to 1.0
    public let timestamp: TimeInterval  // When this was processed
    public let segmentDuration: TimeInterval // Duration analyzed
}
```

## Configuration

```swift
public struct VADConfiguration: Sendable {
    public var threshold: Float           // 0.0-1.0, default 0.5
    public var contextWindow: Int         // Frames for context, default 3
    public var smoothingWindow: Int       // Frames for smoothing, default 5
    public var minSpeechDuration: TimeInterval  // Min speech to trigger
    public var minSilenceDuration: TimeInterval // Min silence to end speech
}
```

## Processing Flow

1. **Extract** float channel data from `AVAudioPCMBuffer`
2. **Inference**: Run CoreML model prediction with LSTM hidden/cell state
3. **Smoothing**: Average confidence over last N frames (configurable)
4. **Threshold**: Compare smoothed confidence against threshold
5. **Result**: Emit `VADResult` with speech/silence classification

## Smoothing Algorithm

```swift
private func applySmoothing(_ confidence: Float) -> Float {
    smoothingBuffer.append(confidence)
    while smoothingBuffer.count > configuration.smoothingWindow {
        smoothingBuffer.removeFirst()
    }
    return smoothingBuffer.reduce(0, +) / Float(smoothingBuffer.count)
}
```

The smoothing window (default 5 frames = ~160ms at 16kHz/512) prevents rapid toggling between speech and silence states.

## Fallback: RMS-Based Detection

When the CoreML model is unavailable (e.g., missing model file), the system falls back to a dB-based heuristic:

```swift
let rms = sqrt(sum_of_squares / frameLength)
let db = 20 * log10(max(rms, 1e-10))

// Map dB to 0-1 confidence: -60dB -> 0.0, -20dB -> 1.0
let normalized = max(0, min(1, (db - (-60)) / ((-20) - (-60))))
```

This provides basic speech detection without the neural model, though with lower accuracy.

## Barge-In Integration

The VAD system is central to barge-in detection:

1. During AI speech, the AudioEngine continues running the input tap
2. Hardware AEC removes the AI's voice from the microphone input
3. VAD processes AEC-cleaned audio
4. If `VADResult.confidence >= bargeInThreshold` (default 0.7):
   - SessionManager detects interrupt
   - AudioEngine stops TTS playback
   - Conversation returns to "user speaking" state

The `bargeInThreshold` is set higher (0.7) than the general VAD threshold (0.5) to prevent accidental interruptions from background noise.

## Available VAD Providers

```swift
public enum VADProvider: String, Codable, Sendable, CaseIterable {
    case silero    // On-device Neural Engine (recommended)
    case ten       // TEN framework
    case webrtc    // WebRTC VAD
}
```

Only Silero is implemented for on-device use. The others are placeholder for future server-side options.

## Source Files

- Protocol: `reference-code/Protocols/VADService.swift`
- Implementation: `reference-code/VAD/SileroVADService.swift`
