# Session Management

The `SessionManager` orchestrates the complete voice conversation flow, managing turn-taking between user and AI through a state machine.

## State Machine

```swift
public enum SessionState: String, Sendable {
    case idle                      // Not running
    case userSpeaking              // VAD detected speech, capturing
    case processingUserUtterance   // STT processing audio
    case aiThinking                // LLM generating response
    case aiSpeaking                // TTS playing audio
    case interrupted               // User barged in
    case paused                    // Session frozen
    case error                     // Recoverable error
}
```

## Session Configuration

```swift
public struct SessionConfig: Codable, Sendable {
    public var audio: AudioEngineConfig
    public var llm: LLMConfig
    public var voice: TTSVoiceConfig
    public var systemPrompt: String
    public var enableCostTracking: Bool
    public var maxDuration: TimeInterval     // 5400s (90 min) default
    public var enableInterruptions: Bool
    public var ttsPlayback: TTSPlaybackConfig
}
```

## TTS Playback Configuration

Fine-tuned playback controls for different use cases:

```swift
public struct TTSPlaybackConfig: Codable, Sendable {
    public var enablePrefetch: Bool
    public var prefetchLookaheadSeconds: TimeInterval
    public var prefetchQueueDepth: Int       // 1-3 recommended
    public var interSentenceSilenceMs: Int
    public var enableMultiBufferScheduling: Bool
    public var scheduledBufferCount: Int
}
```

### TTS Playback Presets

| Preset | Prefetch | Queue Depth | Silence | Multi-Buffer | Use Case |
|--------|----------|-------------|---------|--------------|----------|
| default | Yes | 2 | 150ms | Yes (2) | Balanced |
| lowLatency | Yes | 3 | 50ms | Yes (3) | Conversations |
| conservative | No | 1 | 200ms | No | Reliability |
| disabled | No | 0 | 0ms | No | Testing |

## Conversation Flow

### 1. User Speaks
- VAD detects speech (confidence >= threshold)
- State -> `userSpeaking`
- Audio buffers accumulated for STT
- Partial transcripts displayed in UI

### 2. Silence Detected
- 1.5 seconds of silence after speech
- State -> `processingUserUtterance`
- STT produces final transcript

### 3. AI Thinking
- State -> `aiThinking`
- Transcript sent to LLM with conversation history
- LLM streams tokens
- Tokens accumulated into complete sentences

### 4. AI Speaking
- State -> `aiSpeaking`
- Sentences sent to AudioPlaybackOrchestrator
- TTS synthesizes audio (with prefetching)
- Audio plays through speaker

### 5. Barge-In (Optional)
- During `aiSpeaking`, VAD still active
- User speaks -> confidence >= bargeInThreshold
- State -> `interrupted` -> `userSpeaking`
- TTS playback stopped, cycle restarts

### 6. Completion
- All TTS audio played
- State -> `idle` (waiting for next user speech)
- Or session ended by user

## Sentence-Level TTS Streaming

The SessionManager accumulates LLM tokens into complete sentences before sending to TTS. This balances latency (don't wait for full response) with quality (complete sentences sound better than fragments):

```
LLM tokens: "The" "answer" "is" "42." "However," "there" "are" ...
                                    ^
                              Sentence boundary detected
                              Send "The answer is 42." to TTS
                              Continue accumulating next sentence
```

## Cost Tracking

The SessionManager tracks costs across all providers:

```
STT cost:  provider.costPerHour * audioMinutes
TTS cost:  provider.costPerCharacter * characterCount
LLM cost:  (inputTokens * costPerInputToken) + (outputTokens * costPerOutputToken)
```

On-device providers (Apple Speech, Pocket TTS, Ministral 3B) all report $0 cost.

## Session Persistence

Sessions are saved to Core Data with:
- Conversation history (messages)
- Duration and timestamps
- Cost breakdown
- Performance metrics
- Error counts

## Key Design Decisions

### @MainActor Isolation
SessionManager is `@MainActor` because it drives UI state. All published properties update on the main thread.

### Silence Detection Threshold
1.5 seconds of silence indicates the user has finished speaking. This is a balance between:
- Too short: Cutting off natural pauses
- Too long: Perceived slow response

### Sentence Accumulation
Sentences are detected by punctuation boundaries (`.`, `!`, `?`). This ensures TTS receives complete, natural-sounding units.

### Prefetch Integration
The SessionManager uses `AudioPlaybackOrchestrator` with the `session` preset (shallow prefetch depth 2, no inter-segment silence, no retention). This minimizes memory use while keeping the next sentence ready.
