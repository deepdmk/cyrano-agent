# On-Device LLM: Ministral 3 3B

The on-device LLM provides fully local language model inference with no network required, no API costs, and complete data privacy.

## Model Specifications

| Property | Value |
|----------|-------|
| Model | Ministral 3 3B (December 2025) |
| Publisher | Mistral AI |
| Format | GGUF (Q4_K_M quantization) |
| File | `Ministral-3-3B-Instruct-2512-Q4_K_M.gguf` |
| Size | ~2.15 GB |
| Context Window | 4,096 tokens |
| Inference Backend | llama.cpp (Stanford BDHG XCFramework) |
| GPU Layers | 99 (full GPU offload on device, 0 on simulator) |
| License | Apache 2.0 |
| Source | Hugging Face: `mistralai/Ministral-3-3B-Instruct-2512-GGUF` |
| Minimum RAM | 4 GB (6 GB recommended) |
| Cost | Free (no API charges) |

## Architecture

```swift
public actor OnDeviceLLMService: LLMService, LLMLoadableService {
    private var model: OpaquePointer?    // llama_model pointer
    private var context: OpaquePointer?  // llama_context pointer
    private var isLoaded: Bool = false
}
```

The service uses llama.cpp's C API directly via Swift C++ interop. The `llama` module is imported from the Stanford BDHG llama.cpp XCFramework.

## Model Loading

```swift
public func loadModel() async throws {
    // 1. Initialize backend
    llama_backend_init()

    // 2. Configure model parameters
    var modelParams = llama_model_default_params()
    modelParams.n_gpu_layers = 99  // All layers on GPU (device)

    // 3. Load GGUF file (~2.15GB, takes several seconds)
    model = llama_load_model_from_file(modelPath, modelParams)

    // 4. Create context with thread configuration
    var ctxParams = llama_context_default_params()
    ctxParams.n_ctx = 4096  // Context size
    ctxParams.n_threads = processorCount - 2  // Leave 2 cores free
    context = llama_new_context_with_model(model, ctxParams)
}
```

Thread count is automatically determined: `max(1, min(8, processorCount - 2))`.

## Streaming Completion

```swift
public func streamCompletion(
    messages: [LLMMessage],
    config: LLMConfig
) async throws -> AsyncStream<LLMToken>
```

Generation loop:
1. Format messages into Mistral prompt format (`[INST]...[/INST]`)
2. Tokenize prompt via `llama_tokenize()`
3. Process prompt through decoder via `llama_decode()`
4. Generate tokens with greedy sampling via `llama_sampler_init_greedy()`
5. Check for end-of-generation via `llama_vocab_is_eog()`
6. Convert tokens to text via `llama_token_to_piece()`
7. Yield `LLMToken` objects to `AsyncStream`

## Prompt Format (Mistral)

```
[INST] {system_prompt}

{user_message} [/INST]{assistant_response}</s>[INST] {next_user_message} [/INST]
```

The system prompt is included with the first user message. Subsequent turns follow the `[INST]...[/INST]` pattern.

## Model Storage Locations (Fallback Chain)

1. **Primary**: `Documents/models/LLM/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf`
2. **Legacy bundle**: `Bundle.main/ministral-3b-instruct-q4_k_m.gguf`
3. **Dev path**: `models/ministral-3b-instruct-q4_k_m.gguf`

## Model Download

The `OnDeviceLLMModelManager` handles downloading from Hugging Face CDN:

```swift
// Download URL
https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/
    Ministral-3-3B-Instruct-2512-Q4_K_M.gguf
```

Features:
- Progress tracking via `URLSession` observation
- File size verification (with 100MB tolerance)
- Cancel support
- Delete to free storage

## Device Capability Check

```swift
public static var isDeviceSupported: Bool {
    let memoryGB = ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)
    return memoryGB >= 6
}
```

Requires 6+ GB physical memory. On simulator, GPU layers are set to 0 (CPU only).

## Performance Metrics

```swift
public struct LLMMetrics {
    let medianTTFT: TimeInterval     // Time to first token
    let p99TTFT: TimeInterval
    let totalInputTokens: Int
    let totalOutputTokens: Int
}
```

## LLM Protocol

```swift
public protocol LLMService: Actor {
    var metrics: LLMMetrics { get }
    var costPerInputToken: Decimal { get }
    var costPerOutputToken: Decimal { get }

    func streamCompletion(
        messages: [LLMMessage],
        config: LLMConfig
    ) async throws -> AsyncStream<LLMToken>
}
```

## Key Types

```swift
public struct LLMMessage: Codable, Sendable {
    public enum Role: String, Codable { case system, user, assistant }
    public let role: Role
    public let content: String
}

public struct LLMToken: Sendable {
    public let content: String
    public let isDone: Bool
    public let stopReason: StopReason?
    public let tokenCount: Int?
}

public struct LLMConfig: Codable, Sendable {
    public var model: String?
    public var maxTokens: Int          // Default: 1024
    public var temperature: Double     // Default: 0.7
    public var topP: Double?           // Default: 0.9
    public var systemPrompt: String?
    public var stream: Bool            // Default: true
}
```

## Source Files

- Service: `reference-code/LLM/OnDeviceLLMService.swift`
- Model Manager: `reference-code/LLM/OnDeviceLLMModelManager.swift`
- Protocol: `reference-code/Protocols/LLMService.swift`
