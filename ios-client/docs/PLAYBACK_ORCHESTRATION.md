# Audio Playback Orchestration

The `AudioPlaybackOrchestrator` is a shared playback engine used by all voice-producing modules. It handles prefetching, caching, inter-segment silence, and playback state management.

## Architecture

```swift
public actor AudioPlaybackOrchestrator {
    private let ttsService: any TTSService
    private let audioEngine: AudioEngine
    public weak var delegate: (any PlaybackOrchestratorDelegate)?

    private var segments: [any PlayableSegment] = []
    private var prefetchCache: [Int: [TTSAudioChunk]] = [:]
    private var prefetchTasks: [Int: Task<[TTSAudioChunk]?, Never>] = [:]
}
```

## Playback Priority (Four Levels)

When playing a segment, the orchestrator checks these sources in order:

```
1. Segment Cached Audio    ──> Pre-generated at import time (fastest)
        │ miss
2. Prefetch Cache          ──> Synthesized ahead of playback
        │ miss
3. In-Progress Prefetch    ──> Wait for synthesis to complete
        │ miss
4. Direct TTS Stream       ──> Synthesize on-demand (slowest)
```

This cascading strategy minimizes perceived latency. Most segments play from cache with zero synthesis delay.

## Configuration

```swift
public struct PlaybackOrchestratorConfig: Sendable {
    public let prefetchDepth: Int           // Segments to prefetch ahead
    public let interSegmentSilenceMs: Int   // Silence between segments
    public let retainBehindCount: Int       // Cached segments to keep behind
    public let bufferTimeoutSeconds: Double // Max wait for prefetch
}
```

### Presets

| Preset | Prefetch | Silence | Retain | Use Case |
|--------|----------|---------|--------|----------|
| readingList | 5 | 600ms | 6 | Reading aloud (deep prefetch) |
| session | 2 | 0ms | 0 | Conversations (low latency) |
| knowledgeBowl | 0 | 0ms | 0 | Single questions |
| default | 3 | 200ms | 2 | General purpose |

## Prefetch Loop

```
Current: Playing segment 3
Prefetch loop: Synthesizing segments 4, 5, 6 (depth=3)

Timeline:
  Seg 3: ████████ (playing)
  Seg 4: ░░░░░░   (prefetching, will be in cache)
  Seg 5: ░░░      (prefetching)
  Seg 6: ░        (prefetching)
```

The prefetch loop runs as a separate `Task`, continuously synthesizing segments ahead of the current playback position. When playback reaches a prefetched segment, it plays instantly from cache.

## Dynamic Segment Append

For streaming use cases (LLM generating sentences in real-time):

```swift
// SessionManager adds sentences as they arrive
await orchestrator.setExpectsMoreSegments(true)
await orchestrator.appendSegments([sentence1])
await orchestrator.startPlayback()

// Later, as more sentences arrive:
await orchestrator.appendSegments([sentence2, sentence3])

// When LLM finishes:
await orchestrator.signalNoMoreSegments()
```

The playback loop automatically waits (polling every 50ms) when it runs out of segments in dynamic mode.

## Playback Controls

```swift
// Start from beginning or specific index
await orchestrator.startPlayback(from: 0)

// Pause/Resume (for barge-in)
await orchestrator.pausePlayback()
await orchestrator.resumePlayback()

// Stop completely (clears all state)
await orchestrator.stopPlayback()

// Suspend (preserves cache, lighter than stop)
await orchestrator.suspendPlayback()

// Skip to specific segment
await orchestrator.skipToSegment(5)
```

## Delegate Protocol

```swift
public protocol PlaybackOrchestratorDelegate: Actor {
    func orchestratorWillPlaySegment(at index: Int) async -> Bool  // Skip?
    func orchestratorDidFinishSegment(at index: Int) async
    func orchestratorDidChangeSegment(index: Int, total: Int) async
    func orchestratorDidComplete() async
    func orchestratorDidEncounterError(_ error: Error) async
}
```

All delegate methods have default no-op implementations, so modules only override what they need.

## Cache Eviction

Old prefetch entries are evicted as playback advances:

```swift
let evictBefore = currentIndex - config.retainBehindCount
for key in prefetchCache.keys where key < evictBefore {
    prefetchCache.removeValue(forKey: key)
}
```

With `retainBehindCount = 2`, the cache keeps 2 segments behind the current position for potential backward navigation.

## Source Files

- Orchestrator: `reference-code/Audio/AudioPlaybackOrchestrator.swift`
- Config: `reference-code/Audio/PlaybackOrchestratorConfig.swift`
