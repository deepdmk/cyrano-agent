# On-Device STT: Apple Speech Recognition

The on-device STT uses Apple's built-in Speech Recognition framework (`SFSpeechRecognizer`) for zero-cost, fully offline speech-to-text.

## Specifications

| Property | Value |
|----------|-------|
| Framework | Apple Speech (SFSpeechRecognizer) |
| Latency | Varies by device, typically 100-300ms |
| Cost | Free (system framework) |
| Offline | Yes (on-device mode enforced) |
| Languages | System-supported languages |
| Word Timestamps | Yes (via SFTranscriptionSegment) |
| Punctuation | iOS 16+ (addsPunctuation) |

## Architecture

```swift
public actor AppleSpeechSTTService: STTService {
    private var recognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
}
```

## Key Features

### On-Device Enforcement
```swift
recognitionRequest.requiresOnDeviceRecognition = true
```
This forces Apple's Speech framework to use on-device models only, ensuring:
- No data sent to Apple servers
- Works without network
- Consistent latency (no network roundtrip)

Exception: On simulator, on-device recognition is not available, so it falls back to server-based.

### Streaming Results
The service produces `STTResult` objects with both partial (interim) and final transcripts:

```swift
public struct STTResult: Sendable {
    public let transcript: String
    public let isFinal: Bool
    public let isEndOfUtterance: Bool
    public let confidence: Float          // 0.0-1.0
    public let timestamp: TimeInterval
    public let latency: TimeInterval      // Audio to result time
    public let wordTimestamps: [WordTimestamp]?
}
```

### Word-Level Timestamps
Extracted from `SFTranscriptionSegment`:
```swift
public struct WordTimestamp: Sendable {
    public let word: String
    public let startTime: TimeInterval
    public let endTime: TimeInterval
    public let confidence: Float?
}
```

## STT Protocol

```swift
public protocol STTService: Actor {
    var metrics: STTMetrics { get }
    var costPerHour: Decimal { get }

    func startStreaming() async throws -> AsyncStream<STTResult>
    func sendAudio(_ buffer: AVAudioPCMBuffer) async
    func stopStreaming() async throws -> STTResult?
    func cancel() async
}
```

## Available STT Providers

The system supports multiple STT providers, though only Apple Speech and GLM-ASR are on-device:

| Provider | On-Device | Cost/Hour | Notes |
|----------|-----------|-----------|-------|
| Apple Speech | Yes | $0.00 | System framework |
| GLM-ASR (nano) | Yes* | $0.00 | *CoreML models defined, llama.cpp decoder pending |
| AssemblyAI | No | $0.37 | WebSocket streaming |
| Deepgram Nova-3 | No | $0.258 | WebSocket streaming |
| OpenAI Whisper | No | $0.36 | REST API |
| Groq Whisper | No | $0.00 | Free tier |
| GLM-ASR (server) | No | $0.00 | Self-hosted |

## GLM-ASR Nano (Future On-Device)

A more capable on-device STT is partially implemented using GLM-ASR Nano:

Pipeline (when enabled):
1. Audio -> Mel Spectrogram (128 x 3000)
2. CoreML Whisper Encoder -> Audio embeddings (1 x 1500 x 1280)
3. CoreML Audio Adapter -> Language embeddings (1 x 375 x 2048)
4. llama.cpp GGUF decoder -> Text tokens

Currently disabled pending llama.cpp Swift interop completion.

## Metrics

```swift
public struct STTMetrics: Sendable {
    public var medianLatency: TimeInterval
    public var p99Latency: TimeInterval
    public var wordEmissionRate: Double    // Words per second
}
```

## Source Files

- Implementation: `reference-code/STT/AppleSpeechSTTService.swift`
- Protocol: `reference-code/Protocols/STTService.swift`
