# Audio Engine

The `AudioEngine` actor is the central manager for all audio I/O. It handles microphone capture, VAD processing, and TTS playback in a unified component.

## Architecture

```swift
public actor AudioEngine: ObservableObject {
    private let engine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var vadService: any VADService

    // Audio stream: emits (buffer, VADResult) pairs
    nonisolated public var audioStream: AnyPublisher<(AVAudioPCMBuffer, VADResult), Never>
}
```

## Audio Session Configuration

```swift
// iOS audio session setup for voice chat
try session.setCategory(
    .playAndRecord,
    mode: .voiceChat,
    options: [.defaultToSpeaker, .allowBluetooth, .allowBluetoothA2DP]
)
try session.setPreferredSampleRate(config.sampleRate)
try session.setPreferredIOBufferDuration(Double(config.bufferSize) / config.sampleRate)
```

Key choices:
- `.playAndRecord` category enables simultaneous mic + speaker
- `.voiceChat` mode optimizes for conversational audio
- `.defaultToSpeaker` routes to loudspeaker (not earpiece)

## Hardware Voice Processing

When `config.enableVoiceProcessing` is true:
```swift
try engine.inputNode.setVoiceProcessingEnabled(true)
```

This enables three critical hardware DSP features:
- **Acoustic Echo Cancellation (AEC)**: Removes AI voice from mic input
- **Automatic Gain Control (AGC)**: Maintains consistent input levels
- **Noise Suppression (NS)**: Reduces background noise

AEC is essential for barge-in detection; without it, the AI's own voice triggers false VAD positives.

## Audio Capture Pipeline

```swift
inputNode.installTap(onBus: 0, bufferSize: config.bufferSize, format: format) {
    @Sendable buffer, _ in
    Task.detached {
        let vadResult = await vadService.processBuffer(buffer)
        streamHolder.send(buffer, vadResult)
    }
}
```

The tap runs on a real-time audio thread. `Task.detached` is used to avoid inheriting any actor context, which would crash in Swift 6's strict concurrency model.

## TTS Playback

### Streaming Chunk Playback
```swift
public func playAudio(_ chunk: TTSAudioChunk) async throws
```

Handles:
1. Converting TTSAudioChunk to AVAudioPCMBuffer
2. Auto-detecting format changes and reconnecting playerNode
3. Scheduling buffers for gapless playback
4. Blocking on last chunk until playback finishes (via `CheckedContinuation`)

### Pause/Resume/Stop (Barge-In Support)
```swift
public func pausePlayback() async -> Bool   // Tentative pause, can resume
public func resumePlayback() async -> Bool   // Resume from pause
public func stopPlayback() async             // Full interruption, clears buffers
```

## Configuration

```swift
public struct AudioEngineConfig: Codable, Sendable, Equatable {
    // Audio format
    public var sampleRate: Double           // 16000, 24000, 48000
    public var channels: AVAudioChannelCount // 1 (mono)
    public var bitDepth: BitDepth           // .float32, .int16, .int32
    public var bufferSize: AVAudioFrameCount // 1024 default

    // Voice processing
    public var enableVoiceProcessing: Bool   // true (AEC/AGC/NS)
    public var enableEchoCancellation: Bool  // true
    public var enableNoiseSuppression: Bool  // true

    // VAD
    public var vadProvider: VADProvider      // .silero
    public var vadThreshold: Float           // 0.5 (0.0-1.0)
    public var vadContextWindow: Int         // 3 frames
    public var vadSmoothingWindow: Int       // 5 frames

    // Barge-in
    public var enableBargeIn: Bool           // true
    public var bargeInThreshold: Float       // 0.7 (higher = harder to interrupt)
    public var ttsClearOnInterrupt: Bool     // true

    // Performance
    public var enableAdaptiveQuality: Bool   // true
    public var thermalThrottleThreshold: ThermalThreshold // .serious

    // Monitoring
    public var enableAudioLevelMonitoring: Bool // true
    public var levelUpdateInterval: TimeInterval // 0.1
}
```

### Presets

| Preset | Sample Rate | Buffer | VAD Threshold | Barge-In | Use Case |
|--------|-------------|--------|---------------|----------|----------|
| default | 48kHz | 1024 | 0.5 | 0.7 | General voice chat |
| lowLatency | 24kHz | 512 | 0.4 | 0.6 | Voice agents |
| privacyFirst | 16kHz | 2048 | 0.6 | 0.8 | Maximum privacy |

## Thread Safety Model

The AudioEngine is a Swift `actor`, but the audio tap callback runs on a real-time thread that cannot enter the actor. Solution:

```swift
// AudioStreamHolder is @unchecked Sendable, created once and shared
private final class AudioStreamHolder: @unchecked Sendable {
    let subject = PassthroughSubject<(AVAudioPCMBuffer, VADResult), Never>()
}

// UncheckedSendableBox wraps non-Sendable types for the tap closure
private struct UncheckedSendableBox<T>: @unchecked Sendable {
    let value: T
}
```

The tap closure captures these wrappers instead of referencing actor-isolated state, preventing Swift 6 data race errors.

## Thermal Monitoring

```swift
ProcessInfo.thermalStateDidChangeNotification → handleThermalStateChange()
```

At `.serious` or `.critical` thermal state, the engine can:
- Reduce sample rate
- Increase buffer size
- Disable optional processing

## Source File

Reference implementation: `reference-code/Audio/AudioEngine.swift`
