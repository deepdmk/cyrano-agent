# Barge-In Detection

Barge-in is the ability for the user to interrupt the AI while it is speaking. This creates a natural conversational experience where the user doesn't have to wait for the AI to finish before responding.

## How It Works

```
AI Speaking State:
┌─────────────────────────────────────────────────┐
│                                                  │
│  Speaker ──> AI Voice ──> Room                   │
│                              │                   │
│  Microphone <── Mixed Audio <┘                   │
│       │                                          │
│  AVAudioEngine (Hardware AEC)                    │
│       │                                          │
│  AEC-Cleaned Audio (AI voice removed)            │
│       │                                          │
│  Silero VAD                                      │
│       │                                          │
│  confidence >= bargeInThreshold?                  │
│       │                                          │
│  YES: Stop playback, return to userSpeaking      │
│  NO:  Continue AI playback                       │
│                                                  │
└─────────────────────────────────────────────────┘
```

## Configuration

```swift
// In AudioEngineConfig
public var enableBargeIn: Bool       // true (enable interruption)
public var bargeInThreshold: Float   // 0.7 (VAD confidence threshold)
public var ttsClearOnInterrupt: Bool  // true (clear TTS buffer)
```

The `bargeInThreshold` (0.7) is intentionally higher than the general VAD threshold (0.5). This reduces false interruptions from background noise while still responding to deliberate speech.

## The Role of Echo Cancellation

Hardware AEC is the most critical component for reliable barge-in:

```swift
try engine.inputNode.setVoiceProcessingEnabled(true)
```

Without AEC:
- AI's voice plays through speaker
- Speaker audio bleeds into microphone
- VAD detects AI's own voice as "speech"
- False barge-in triggers constantly

With AEC:
- AVAudioEngine removes AI's voice from mic input
- VAD only sees the user's voice (and ambient noise)
- Barge-in triggers only on genuine user speech

## Three Pause States

The AudioEngine supports a nuanced interruption model:

### 1. Tentative Pause
```swift
public func pausePlayback() async -> Bool
```
- Pauses audio playback (can resume)
- Used when VAD first detects speech
- If detection was a false positive, resume without interruption

### 2. Resume
```swift
public func resumePlayback() async -> Bool
```
- Resumes from paused state
- Used when tentative pause was a false alarm

### 3. Full Stop (Interruption)
```swift
public func stopPlayback() async
```
- Stops playback completely
- Clears pending audio buffers
- Cannot resume, must re-synthesize
- Used when barge-in is confirmed

## Session Manager Integration

The SessionManager orchestrates barge-in across the full pipeline:

1. **During `aiSpeaking` state**: VAD runs on every mic buffer
2. **VAD confidence >= bargeInThreshold**: Transition to `interrupted` state
3. **Clear TTS queue**: Stop AudioPlaybackOrchestrator
4. **Transition to `userSpeaking`**: Begin capturing user's speech
5. **STT starts**: Process user's interruption

The silence detection threshold (1.5 seconds) determines when the user's utterance is complete after barge-in.

## Tuning Guide

| Scenario | Adjust | Direction |
|----------|--------|-----------|
| Too many false interruptions | Increase `bargeInThreshold` | 0.7 -> 0.8 |
| Hard to interrupt | Decrease `bargeInThreshold` | 0.7 -> 0.6 |
| Background noise triggers | Increase `bargeInThreshold` | 0.7 -> 0.85 |
| Noisy environment | Increase `vadSmoothingWindow` | 5 -> 8 |
| Quick responses missed | Decrease `vadSmoothingWindow` | 5 -> 3 |

## Requirements

- `AVAudioSession` category: `.playAndRecord`
- `AVAudioSession` mode: `.voiceChat`
- Voice processing enabled on input node
- Silero VAD model loaded and active
- AudioEngine running with input tap installed
