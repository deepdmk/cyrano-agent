# Voice Settings

Complete reference of all configurable voice settings in the system. These settings control every aspect of the audio pipeline, from microphone capture to TTS playback.

## Settings Architecture

Settings are organized into a hierarchical structure:

```
SessionConfig
├── audio: AudioEngineConfig       # Mic, VAD, barge-in
├── llm: LLMConfig                 # Model, temperature, tokens
├── voice: TTSVoiceConfig          # Voice selection, rate
├── ttsPlayback: TTSPlaybackConfig # Prefetch, buffer scheduling
├── systemPrompt: String
├── enableCostTracking: Bool
├── maxDuration: TimeInterval
└── enableInterruptions: Bool
```

All settings persist to `UserDefaults` with typed keys.

## Audio Settings

### Sample Rate
- **Key**: `audioSampleRate`
- **Options**: 16000 Hz, 24000 Hz, 48000 Hz
- **Default**: 48000
- **Impact**: Higher = better quality, more processing. 16kHz is minimum for VAD.

### Voice Processing
- **Key**: `enableVoiceProcessing`
- **Default**: true
- **Impact**: Enables hardware AEC/AGC/NS. Critical for barge-in.

### Echo Cancellation
- **Key**: `enableEchoCancellation`
- **Default**: true
- **Impact**: Removes AI voice from mic input. Disable only for headphone-only use.

### Noise Suppression
- **Key**: `enableNoiseSuppression`
- **Default**: true
- **Impact**: Reduces background noise in mic input.

## VAD Settings

### Detection Threshold
- **Key**: `vadThreshold`
- **Range**: 0.3 to 0.9
- **Default**: 0.5
- **Impact**: Lower = more sensitive (catches quiet speech), Higher = fewer false positives.

### Context Window
- **Key**: `vadContextWindow`
- **Default**: 3 frames
- **Impact**: Number of frames used for contextual speech detection.

### Smoothing Window
- **Key**: `vadSmoothingWindow`
- **Default**: 5 frames (~160ms at 16kHz/512)
- **Impact**: More smoothing = fewer rapid toggles, but slower response.

## Barge-In Settings

### Enable Barge-In
- **Key**: `enableBargeIn`
- **Default**: true
- **Impact**: Whether user can interrupt AI speech.

### Interruption Threshold
- **Key**: `bargeInThreshold`
- **Range**: 0.5 to 0.95
- **Default**: 0.7
- **Impact**: Higher = harder to interrupt, fewer false triggers.

### TTS Clear on Interrupt
- **Key**: `ttsClearOnInterrupt`
- **Default**: true
- **Impact**: Whether to clear TTS buffer when interrupted.

## STT Settings

### Provider
- **Key**: `sttProvider`
- **Options**: Apple Speech, AssemblyAI, Deepgram, OpenAI, Groq, GLM-ASR
- **Default**: Apple Speech (on-device, free)

## LLM Settings

### Provider
- **Key**: `llmProvider`
- **Options**: On-Device (Ministral 3B), OpenAI, Anthropic, Self-Hosted
- **Default**: On-Device

### Temperature
- **Key**: `llmTemperature`
- **Range**: 0.0 to 1.0
- **Default**: 0.7
- **Impact**: Controls response creativity/randomness.

### Max Tokens
- **Key**: `llmMaxTokens`
- **Default**: 1024
- **Impact**: Maximum response length in tokens.

## TTS Settings

### Provider
- **Options**: Pocket TTS (on-device), Deepgram, ElevenLabs, Apple, Chatterbox, Piper
- **Default**: Pocket TTS (on-device, free)

### Voice Selection (Pocket TTS)
- **Key**: `kyutai_pocket_voice_index`
- **Options**: 0-7 (Alba, Marius, Javert, Jean, Fantine, Cosette, Eponine, Azelma)
- **Default**: 0 (Alba)

### Speaking Rate
- **Key**: `kyutai_pocket_speed`
- **Range**: 0.5 to 2.0
- **Default**: 1.0

### Temperature
- **Key**: `kyutai_pocket_temperature`
- **Range**: 0.0 to 1.5
- **Default**: 0.7

### Top-P
- **Key**: `kyutai_pocket_top_p`
- **Range**: 0.1 to 1.0
- **Default**: 0.9

### Consistency Steps
- **Key**: `kyutai_pocket_consistency_steps`
- **Range**: 1 to 4
- **Default**: 2

### Neural Engine
- **Key**: `kyutai_pocket_use_neural_engine`
- **Default**: true

### Prefetch
- **Key**: `kyutai_pocket_enable_prefetch`
- **Default**: true

## TTS Playback Settings

### Enable Prefetch
- **Default**: true
- **Impact**: Synthesize next sentence while current plays.

### Prefetch Queue Depth
- **Range**: 1 to 3
- **Default**: 2
- **Impact**: How many segments to synthesize ahead.

### Inter-Sentence Silence
- **Default**: 150ms
- **Impact**: Pause between sentences during AI speech.

### Multi-Buffer Scheduling
- **Default**: true
- **Impact**: Schedule multiple buffers to AVAudioPlayerNode for gapless playback.

## Preset System

Five built-in presets that configure all settings as a group:

### Balanced (Default)
Standard quality/latency tradeoff for general use.

### Low Latency
- 24kHz sample rate
- Lower VAD threshold
- Deeper prefetch
- Minimal inter-sentence silence
- Optimized for conversations

### High Quality
- 48kHz sample rate
- Enhanced voice processing
- Higher consistency steps (TTS)
- Longer inter-sentence silence for naturalness

### Cost Optimized
- Uses on-device providers exclusively
- No cloud API calls
- $0 running cost

### Self-Hosted
- Uses self-hosted server providers
- GLM-ASR for STT, Piper for TTS
- No third-party API dependency

## Settings UI

The `VoiceSettingsView` provides a SwiftUI interface with:
- Preset selection at the top
- Collapsible sections for each category
- Sliders for continuous values (thresholds, rates)
- Pickers for provider selection
- Toggle switches for boolean settings
- Model status indicators (downloaded, loaded, etc.)
- Server capability discovery (auto-detect available providers)

All settings take effect immediately without restart.
