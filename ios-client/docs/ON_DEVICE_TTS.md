# On-Device TTS: Kyutai Pocket TTS

Pocket TTS is a 100M parameter on-device text-to-speech model that generates high-quality 24kHz speech with ~200ms time to first audio.

## Model Specifications

| Property | Value |
|----------|-------|
| Parameters | 117,856,642 (~100M) |
| Output Sample Rate | 24,000 Hz |
| Output Format | PCM Float32 Mono |
| Model Size | ~230MB total |
| WER (Word Error Rate) | 1.84% (best in class for on-device) |
| Typical TTFB | ~200ms |
| Realtime Factor | ~6x on M-series (6 seconds audio per 1 second compute) |
| Voices | 8 built-in (Les Miserables characters) |
| Voice Cloning | 5-second reference audio |
| License | CC-BY-4.0 |
| Inference Backend | Rust/Candle (native CPU on iOS) |

## Model Components

| File | Size | Purpose |
|------|------|---------|
| `model.safetensors` | 225MB | Main transformer weights |
| `tokenizer.model` | ~1MB | SentencePiece vocabulary |
| `voices/*.safetensors` | ~4MB | 8 voice embedding files |

Storage location: `Documents/models/PocketTTS/`

## Architecture

```swift
public actor KyutaiPocketTTSService: TTSService {
    private var engine: PocketTtsEngine?      // Rust engine instance
    private let modelManager: KyutaiPocketModelManager
    private var config: KyutaiPocketTTSConfig
}
```

The Swift service wraps a Rust inference engine (`PocketTtsEngine`) compiled as an XCFramework. Rust/Candle was chosen over CoreML because:
- CoreML has limited support for stateful streaming transformers
- Candle provides better CPU inference performance on iOS
- Native control over streaming chunk boundaries

## Streaming Synthesis

```swift
public func synthesize(text: String) async throws -> AsyncStream<TTSAudioChunk>
```

The synthesis pipeline:
1. Text is tokenized by the Rust engine
2. `startTrueStreaming()` begins non-blocking synthesis
3. `StreamingEventHandler` receives callbacks as audio chunks are generated
4. Each chunk is yielded to the `AsyncStream`
5. First chunk includes `timeToFirstByte` measurement

```swift
// StreamingEventHandler bridges Rust callbacks to AsyncStream
private final class StreamingEventHandler: TtsEventHandler {
    func onAudioChunk(chunk: AudioChunk) {
        let ttsChunk = TTSAudioChunk(
            audioData: chunk.audioData,
            format: .pcmFloat32(sampleRate: Double(chunk.sampleRate), channels: 1),
            sequenceNumber: sequenceNumber,
            isFirst: isFirst,
            isLast: chunk.isFinal,
            timeToFirstByte: isFirst ? ttfb : nil
        )
        continuation.yield(ttsChunk)
    }
}
```

## Built-In Voices

| Index | Name | Gender | Character |
|-------|------|--------|-----------|
| 0 | Alba | Female | Warm and welcoming |
| 1 | Marius | Male | Clear and articulate |
| 2 | Javert | Male | Authoritative and firm |
| 3 | Jean | Male | Gentle and compassionate |
| 4 | Fantine | Female | Soft and tender |
| 5 | Cosette | Female | Bright and optimistic |
| 6 | Eponine | Female | Expressive and dynamic |
| 7 | Azelma | Female | Youthful and energetic |

## Configuration

```swift
public struct KyutaiPocketTTSConfig: Codable, Sendable, Equatable {
    public var voiceIndex: Int           // 0-7
    public var referenceAudioPath: String? // Voice cloning (5+ sec)
    public var temperature: Float         // 0.0-1.5 (randomness)
    public var topP: Float                // 0.1-1.0 (nucleus sampling)
    public var speed: Float               // 0.5-2.0 (speaking rate)
    public var consistencySteps: Int      // 1-4 (quality steps)
    public var useNeuralEngine: Bool      // Neural Engine vs CPU
    public var enablePrefetch: Bool       // Token prefetching
    public var seed: Int?                 // Reproducible generation
}
```

### Presets

| Preset | Temperature | Top-P | Speed | Steps | Neural Engine | Use Case |
|--------|-------------|-------|-------|-------|---------------|----------|
| default | 0.7 | 0.9 | 1.0 | 2 | Yes | General use |
| lowLatency | 0.5 | 0.85 | 1.1 | 1 | Yes | Voice agents, conversations |
| highQuality | 0.7 | 0.95 | 1.0 | 4 | Yes | Pre-rendered content |
| batterySaver | 0.6 | 0.9 | 1.0 | 1 | No (CPU) | Extended battery life |

## Model Loading

The `KyutaiPocketModelManager` handles model lifecycle:

1. **First launch**: Copy models from app bundle to `Documents/models/PocketTTS/`
2. **Subsequent launches**: Load from Documents directory
3. **Cold start**: `PocketTtsEngine(modelPath:)` loads all model components
4. **Configuration**: `engine.configure(config:)` applies voice/sampling settings
5. **Unload**: `engine.unload()` frees memory

```swift
actor KyutaiPocketModelManager {
    enum ModelState: Sendable, Equatable {
        case notDownloaded
        case downloading(Float)
        case available
        case loading(Float)
        case loaded
        case error(String)
    }
}
```

## Voice Cloning

Pocket TTS supports 5-second voice cloning:

```swift
// Set reference audio for voice cloning
let audioData = try Data(contentsOf: URL(fileURLWithPath: audioPath))
try engine.setReferenceAudio(audioData: audioData, sampleRate: 24000)

// Clear to return to built-in voice
engine.clearReferenceAudio()
```

Requirements: 5+ seconds of clean speech audio at 24kHz.

## UserDefaults Storage

All Pocket TTS settings persist to UserDefaults:

| Key | Type | Default |
|-----|------|---------|
| `kyutai_pocket_voice_index` | Int | 0 |
| `kyutai_pocket_temperature` | Double | 0.7 |
| `kyutai_pocket_top_p` | Double | 0.9 |
| `kyutai_pocket_speed` | Double | 1.0 |
| `kyutai_pocket_consistency_steps` | Int | 2 |
| `kyutai_pocket_use_neural_engine` | Bool | true |
| `kyutai_pocket_enable_prefetch` | Bool | true |
| `kyutai_pocket_preset` | String | "default" |

## Source Files

- Service: `reference-code/TTS/KyutaiPocketTTSService.swift`
- Config: `reference-code/TTS/KyutaiPocketTTSConfig.swift`
- Model Manager: `reference-code/TTS/KyutaiPocketModelManager.swift`
- Protocol: `reference-code/Protocols/TTSService.swift`
