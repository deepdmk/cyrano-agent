# Voice Pipeline Architecture

Complete architecture of the on-device voice AI pipeline. This document describes the full conversation loop from microphone to speaker.

## System Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                     iOS Device (On-Device)                       │
│                                                                  │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │ Mic      │───>│ Audio    │───>│ VAD      │───>│ STT      │  │
│  │ Capture  │    │ Engine   │    │ (Silero) │    │ (Apple)  │  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│       │                │               │               │        │
│       │           Hardware AEC     Speech/Silence   Transcript  │
│       │           + AGC + NS       Detection        Streaming   │
│       │                                                │        │
│       │                                          ┌──────────┐  │
│       │                                          │ LLM      │  │
│       │                                          │(Ministral│  │
│       │                                          │ 3B GGUF) │  │
│       │                                          └──────────┘  │
│       │                                                │        │
│       │                                          Token Stream   │
│       │                                                │        │
│  ┌──────────┐    ┌──────────┐    ┌──────────┐    ┌──────────┐  │
│  │ Speaker  │<───│ Audio    │<───│ Playback │<───│ TTS      │  │
│  │ Output   │    │ Engine   │    │ Orch.    │    │ (Pocket) │  │
│  └──────────┘    └──────────┘    └──────────┘    └──────────┘  │
│                        │                                        │
│                   Barge-In ──> VAD still active during playback │
│                   Detection    Interrupts if user speaks        │
└─────────────────────────────────────────────────────────────────┘
```

## Complete Voice Conversation Loop

### Phase 1: User Speaks

1. **AudioEngine** captures audio via `AVAudioEngine` with an input tap
2. Audio runs through hardware voice processing (AEC, AGC, NS)
3. Each buffer is sent to **SileroVADService** for speech detection
4. VAD result + buffer emitted via Combine `PassthroughSubject`
5. **SessionManager** subscribes and transitions to `userSpeaking` state

### Phase 2: Speech-to-Text

1. Accumulated audio buffers sent to **AppleSpeechSTTService**
2. STT streams partial results (interim transcripts)
3. SessionManager displays partials in UI
4. When silence detected (1.5s threshold), utterance considered complete

### Phase 3: LLM Reasoning

1. Complete transcript sent to **OnDeviceLLMService** (Ministral 3B)
2. LLM tokenizes with Mistral format (`[INST]...[/INST]`)
3. Tokens generated via greedy sampling with llama.cpp
4. Streamed back as `LLMToken` objects
5. SessionManager accumulates tokens into complete sentences

### Phase 4: Text-to-Speech + Playback

1. Sentences sent to **AudioPlaybackOrchestrator**
2. Orchestrator manages prefetching (synthesize next segment while current plays)
3. **KyutaiPocketTTSService** generates 24kHz PCM audio via Rust/Candle
4. Audio chunks streamed to **AudioEngine** for playback
5. `AVAudioPlayerNode` schedules buffers for gapless playback

### Phase 5: Barge-In Detection

1. During AI speech, VAD continues running on microphone input
2. Hardware AEC removes AI voice from mic input (prevents false positives)
3. If VAD confidence >= `bargeInThreshold` (default 0.7):
   - AudioEngine stops playback immediately
   - TTS buffer cleared
   - SessionManager transitions back to `userSpeaking`
   - Cycle restarts from Phase 1

## Session State Machine

```
                    ┌─────────────────┐
                    │      idle       │
                    └────────┬────────┘
                             │ start session
                    ┌────────▼────────┐
              ┌────>│  userSpeaking   │<────────────────────┐
              │     └────────┬────────┘                     │
              │              │ silence detected              │
              │     ┌────────▼────────────────┐             │
              │     │ processingUserUtterance  │             │
              │     └────────┬────────────────┘             │
              │              │ transcript ready              │
              │     ┌────────▼────────┐                     │
              │     │   aiThinking    │                     │
              │     └────────┬────────┘                     │
              │              │ first sentence ready          │
              │     ┌────────▼────────┐     barge-in        │
              │     │   aiSpeaking    │─────────────────────┘
              │     └────────┬────────┘
              │              │ all audio played
              │     ┌────────▼────────┐
              │     │   idle/waiting  │
              └─────┴────────────────┘
```

States:
- **idle**: No active session
- **userSpeaking**: VAD detects speech, capturing audio
- **processingUserUtterance**: STT processing audio into text
- **aiThinking**: LLM generating response tokens
- **aiSpeaking**: TTS playing audio response
- **interrupted**: User barged in during AI speech
- **paused**: Session frozen (app backgrounded, etc.)
- **error**: Recoverable error occurred

## Latency Budget

| Stage | Target | Notes |
|-------|--------|-------|
| VAD frame processing | 20-30ms | Silero on Neural Engine |
| STT processing | 100-300ms | Apple on-device Speech |
| LLM time to first token | 200-500ms | Ministral 3B with GPU offload |
| TTS time to first byte | ~200ms | Pocket TTS streaming |
| Audio scheduling overhead | ~10ms | AVAudioPlayerNode |
| **Total E2E** | **< 500ms median** | With prefetching active |

## Key Design Principles

### 1. Streaming Everything
Every stage streams its output. The LLM streams tokens, accumulated into sentences. TTS streams audio chunks. This eliminates the latency of waiting for complete outputs.

### 2. Prefetching
The AudioPlaybackOrchestrator synthesizes upcoming segments while the current one plays. By the time a segment finishes, the next one is already in cache.

### 3. Echo Cancellation First
Hardware AEC via `AVAudioEngine.inputNode.setVoiceProcessingEnabled(true)` is critical. Without it, the AI's own voice triggers VAD, creating feedback loops.

### 4. Actor Isolation
Every service is a Swift `actor`, ensuring thread safety without manual locking. Audio tap callbacks use `@Sendable` closures with `Task.detached` to avoid actor boundary issues on real-time threads.

### 5. Graceful Degradation
- VAD falls back to RMS-based detection if CoreML model unavailable
- LLM checks multiple model locations (Documents, bundle, dev path)
- TTS model copied from bundle on first launch, downloaded if missing
- STT falls back to on-device-only mode

## Component Dependencies

```
SessionManager
├── AudioEngine
│   ├── AVAudioEngine (system)
│   ├── AVAudioSession (system)
│   └── VADService (Silero)
│       └── CoreML model (silero_vad.mlmodelc)
├── STTService (Apple Speech)
│   └── SFSpeechRecognizer (system)
├── LLMService (On-Device)
│   └── llama.cpp XCFramework
│       └── GGUF model file (~2.15GB)
├── TTSService (Pocket TTS)
│   └── PocketTtsEngine (Rust XCFramework)
│       ├── model.safetensors (~225MB)
│       ├── tokenizer.model
│       └── voices/ (8 voice embeddings)
└── AudioPlaybackOrchestrator
    ├── TTSService (for prefetch synthesis)
    └── AudioEngine (for playback)
```

## Audio Format Flow

```
Microphone → 16/24/48 kHz Float32 Mono
    │
    ▼
VAD (expects 16kHz, 512 samples per frame)
    │
    ▼
STT (Apple Speech handles format internally)
    │
    ▼
LLM (text domain, no audio)
    │
    ▼
TTS → 24kHz Float32 Mono PCM
    │
    ▼
AudioEngine → AVAudioPlayerNode → Speaker
```

## Thermal Adaptation

The system monitors `ProcessInfo.thermalState` and adapts:
- At `.serious` or `.critical`: can reduce sample rate, increase buffer size
- Prevents iOS from throttling the app
- Configuration via `AudioEngineConfig.thermalThrottleThreshold`
