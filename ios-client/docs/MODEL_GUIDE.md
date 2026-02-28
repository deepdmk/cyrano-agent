# Model Guide

Complete guide to the on-device AI models used in the voice pipeline. Covers where to get them, how they're stored, and how they're loaded.

## Model Summary

| Model | Component | Size | Format | Source | Storage |
|-------|-----------|------|--------|--------|---------|
| Silero VAD | VAD | ~20MB | CoreML (.mlmodelc) | App Bundle | Bundle (read-only) |
| Kyutai Pocket TTS | TTS | ~230MB | Safetensors | App Bundle -> Documents | Documents/models/PocketTTS/ |
| Ministral 3 3B | LLM | ~2.15GB | GGUF (Q4_K_M) | Hugging Face CDN | Documents/models/LLM/ |
| Apple Speech | STT | Built-in | System | iOS System | System-managed |

**Total user storage**: ~2.4 GB (excluding system-managed Apple Speech)

## Silero VAD

### What It Is
A small LSTM neural network for voice activity detection, converted to CoreML format for Apple Neural Engine execution.

### Model File
- **Name**: `silero_vad.mlmodelc`
- **Location**: App bundle (compiled CoreML model)
- **Size**: ~20MB
- **Compute**: CPU + Neural Engine

### How It Loads
```swift
guard let modelURL = Bundle.main.url(
    forResource: "silero_vad", withExtension: "mlmodelc"
) else { throw VADError.modelLoadFailed(...) }

let config = MLModelConfiguration()
config.computeUnits = .cpuAndNeuralEngine
model = try MLModel(contentsOf: modelURL, configuration: config)
```

### Hidden State
Silero VAD is stateful (LSTM). It maintains hidden and cell state tensors:
- Shape: `[2, 1, 64]` (Float32)
- Initialized to zeros on prepare()
- Reset on `reset()` call

### Getting the Model
The Silero VAD model is available from: https://github.com/snakers4/silero-vad

To convert for CoreML:
1. Download the ONNX model from Silero's repository
2. Convert to CoreML using `coremltools`
3. Compile with Xcode into `.mlmodelc` format
4. Add to app bundle

## Kyutai Pocket TTS

### What It Is
A 100M parameter text-to-speech transformer model by Kyutai, using Rust/Candle for native CPU inference on iOS.

### Model Files
```
Documents/models/PocketTTS/
├── model.safetensors    # 225MB - Main transformer weights
├── tokenizer.model      # ~1MB  - SentencePiece vocabulary
└── voices/              # ~4MB  - Voice embeddings
    ├── alba.safetensors
    ├── marius.safetensors
    ├── javert.safetensors
    ├── jean.safetensors
    ├── fantine.safetensors
    ├── cosette.safetensors
    ├── eponine.safetensors
    └── azelma.safetensors
```

### Loading Strategy
1. **First launch**: Models copied from app bundle (`Models/` directory) to Documents
2. **Subsequent launches**: Loaded directly from Documents
3. **If missing**: Attempts download from server (not yet implemented)

```swift
// Model manager checks availability and copies from bundle
func ensureModelsAvailable() async throws {
    if await isModelAvailable() { return }
    if await copyModelsFromBundle() { return }
    try await downloadModels()
}
```

### Rust Engine Initialization
```swift
engine = try PocketTtsEngine(modelPath: modelDirectory.path)
try engine.configure(config: rustConfig)
```

The Rust engine loads all model components from the directory path.

### Getting the Models
Kyutai Pocket TTS models: https://github.com/kyutai-labs/pocketlm

The Rust/Candle inference engine must be compiled as an XCFramework. This requires:
1. Rust toolchain with iOS targets
2. Candle framework
3. Custom FFI bridge for Swift interop

## Ministral 3 3B

### What It Is
A 3B parameter instruction-tuned language model by Mistral AI, quantized to Q4_K_M for efficient on-device inference.

### Model File
- **Name**: `Ministral-3-3B-Instruct-2512-Q4_K_M.gguf`
- **Location**: `Documents/models/LLM/`
- **Size**: ~2.15 GB
- **Quantization**: Q4_K_M (4-bit with K-quant medium)
- **Context Window**: 4,096 tokens

### Download URL
```
https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF/resolve/main/
    Ministral-3-3B-Instruct-2512-Q4_K_M.gguf
```

### Loading Strategy
The model manager checks multiple locations:
1. `Documents/models/LLM/` (downloaded via app)
2. App bundle (legacy bundled model)
3. Development filesystem path
4. If missing, offers download with progress tracking

### llama.cpp Initialization
```swift
llama_backend_init()

var modelParams = llama_model_default_params()
modelParams.n_gpu_layers = 99  // Full GPU offload
model = llama_load_model_from_file(path, modelParams)

var ctxParams = llama_context_default_params()
ctxParams.n_ctx = 4096
ctxParams.n_threads = max(1, min(8, processorCount - 2))
context = llama_new_context_with_model(model, ctxParams)
```

### Getting the Model
Download from Hugging Face:
```bash
huggingface-cli download mistralai/Ministral-3-3B-Instruct-2512-GGUF \
    Ministral-3-3B-Instruct-2512-Q4_K_M.gguf
```

Or download directly via the app's model manager UI (Settings > On-Device LLM > Download).

### llama.cpp XCFramework
The app uses Stanford BDHG's llama.cpp Swift Package. To add to your project:
```swift
// Package.swift dependency
.package(url: "https://github.com/StanfordBDHG/llama.cpp", from: "b7263")
```

## Apple Speech

### What It Is
Apple's built-in speech recognition framework. Models are managed by iOS.

### No Manual Setup Required
- Framework: `Speech` (system)
- On-device models downloaded automatically by iOS
- No model files to manage
- Available on iOS 10+, on-device recognition iOS 13+

### Usage
```swift
import Speech

let recognizer = SFSpeechRecognizer()
let request = SFSpeechAudioBufferRecognitionRequest()
request.requiresOnDeviceRecognition = true  // Force on-device
```

## Device Requirements

| Device | RAM | Storage | Notes |
|--------|-----|---------|-------|
| iPhone 15 Pro+ | 8GB | 2.4GB free | Full pipeline, all models |
| iPhone 14 Pro | 6GB | 2.4GB free | Full pipeline, all models |
| iPhone 14 | 6GB | 2.4GB free | Full pipeline, may be slower |
| iPhone 13 | 4GB | 2.4GB free | LLM may be memory-constrained |
| iPad Pro M-series | 8-16GB | 2.4GB free | Best performance |

Minimum 6GB RAM recommended for running the full pipeline (LLM alone needs ~4GB).

## Storage Management

Users can manage model storage in Settings:
- View model sizes and download status
- Download LLM model with progress tracking
- Delete LLM model to reclaim ~2.15GB
- TTS models are automatically managed (copied from bundle)
- VAD model is in the app bundle (cannot be removed)
