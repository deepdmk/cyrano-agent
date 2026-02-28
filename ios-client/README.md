# Claude Voice AI

A standalone reference architecture for building an on-device voice AI pipeline on iOS. Extracted from the UnaMentis learning platform, this project documents a complete, self-contained voice conversation system that runs entirely on-device with no cloud dependency.

## What This Is

This repository contains the complete technical blueprint for an iOS voice AI system featuring:

- **Full audio pipeline** with hardware echo cancellation, noise suppression, and adaptive quality
- **On-device Voice Activity Detection (VAD)** using Silero on the Neural Engine
- **On-device Text-to-Speech (TTS)** using Kyutai Pocket TTS (100M parameters, Rust/Candle backend)
- **On-device Speech-to-Text (STT)** using Apple Speech Recognition
- **On-device Large Language Model** using Ministral 3 3B via llama.cpp
- **Barge-in detection** for natural conversational interruptions
- **Audio playback orchestration** with intelligent prefetching
- **Voice session management** with state machine turn-taking

All components run on-device. No network required. No API costs.

## Performance Targets

| Metric | Target |
|--------|--------|
| End-to-end turn latency | < 500ms median, < 1000ms P99 |
| TTS time to first audio | ~ 200ms |
| VAD frame processing | ~ 20-30ms |
| Memory growth (90 min) | < 50MB |
| Session stability | 90+ minutes without crashes |

## On-Device Models

| Component | Model | Size | Format |
|-----------|-------|------|--------|
| VAD | Silero VAD | ~20MB | CoreML (.mlmodelc) |
| TTS | Kyutai Pocket TTS | ~230MB | Safetensors + voices |
| LLM | Ministral 3 3B | ~2.15GB | GGUF (Q4_K_M) |
| STT | Apple Speech | Built-in | System framework |

Total on-device model storage: ~2.4 GB

## Repository Structure

```
claude-voice-ai/
├── README.md                          # This file
├── docs/
│   ├── VOICE_PIPELINE_ARCHITECTURE.md # Complete pipeline architecture
│   ├── AUDIO_ENGINE.md                # Audio capture/playback details
│   ├── VAD_SYSTEM.md                  # Voice Activity Detection
│   ├── ON_DEVICE_TTS.md               # Kyutai Pocket TTS
│   ├── ON_DEVICE_LLM.md              # Ministral 3B via llama.cpp
│   ├── ON_DEVICE_STT.md              # Apple Speech Recognition
│   ├── BARGE_IN_DETECTION.md          # Interruption handling
│   ├── SESSION_MANAGEMENT.md          # Turn-taking and state machine
│   ├── VOICE_SETTINGS.md             # All configuration options
│   ├── PLAYBACK_ORCHESTRATION.md      # Audio prefetch and scheduling
│   ├── MODEL_GUIDE.md                # Model files, download, storage
│   ├── AGNO_FRAMEWORK.md             # Agno agent framework research
│   └── AGNO_IOS_FEASIBILITY.md       # Agno + iOS feasibility analysis
├── reference-code/                    # Extracted Swift source files
│   ├── Audio/                         # AudioEngine, AudioPlaybackOrchestrator
│   ├── VAD/                           # SileroVADService
│   ├── STT/                           # AppleSpeechSTTService
│   ├── TTS/                           # KyutaiPocketTTSService + config
│   ├── LLM/                           # OnDeviceLLMService + model manager
│   ├── Session/                       # SessionManager
│   ├── Protocols/                     # Service protocols (VAD, STT, TTS, LLM)
│   └── Settings/                      # VoiceSettingsView
└── models/
    └── MODEL_SOURCES.md               # Where to get each model
```

## Key Architecture Decisions

### Swift 6 Strict Concurrency
All services are `actor`-based for thread safety. Data crossing actor boundaries uses `Sendable` types. Real-time audio threads use `@Sendable` closures with `@unchecked Sendable` wrappers.

### Rust/Candle for TTS Inference
Kyutai Pocket TTS uses a Rust backend (via Candle) compiled as an XCFramework. This provides better performance for stateful streaming transformers than CoreML on iOS.

### llama.cpp for LLM Inference
The on-device LLM uses Stanford's llama.cpp XCFramework with C++ interop. Supports GPU layer offloading (99 layers default) for maximum performance on Apple Silicon.

### Cascading Playback Strategy
The AudioPlaybackOrchestrator uses a four-level priority system:
1. Pre-generated cached audio (fastest)
2. Prefetch cache (synthesized ahead)
3. Wait for in-progress prefetch
4. Stream directly from TTS (fallback)

## Technology Stack

- **Language**: Swift 6.0 / SwiftUI
- **Audio**: AVFoundation (AVAudioEngine, AVAudioSession)
- **VAD Model**: CoreML (Neural Engine compute units)
- **TTS Engine**: Rust/Candle (compiled as XCFramework)
- **LLM Engine**: llama.cpp (Stanford BDHG XCFramework)
- **STT**: Apple Speech framework (on-device mode)
- **Concurrency**: Swift structured concurrency (actors, async/await)
- **Reactive**: Combine (PassthroughSubject for audio stream)
- **Minimum iOS**: 17.0

## Agno Agent Framework

This repository also includes research on the Agno agent framework (formerly Phidata) and its feasibility for iOS integration. See:
- [docs/AGNO_FRAMEWORK.md](docs/AGNO_FRAMEWORK.md) - Complete framework overview
- [docs/AGNO_IOS_FEASIBILITY.md](docs/AGNO_IOS_FEASIBILITY.md) - iOS integration analysis

**Summary**: Agno is Python-only with no iOS SDK. It cannot run on-device. It could serve as a server-side orchestration layer for non-latency-critical tasks, but cannot replace any on-device voice pipeline component.
