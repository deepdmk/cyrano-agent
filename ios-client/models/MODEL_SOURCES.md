# Model Sources

Where to obtain each on-device model used in the voice pipeline.

## Silero VAD

**Source**: https://github.com/snakers4/silero-vad

```bash
# Download ONNX model
wget https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx

# Convert to CoreML (requires coremltools)
python3 -c "
import coremltools as ct
import onnx
model = onnx.load('silero_vad.onnx')
# Convert to CoreML with Neural Engine support
ml_model = ct.converters.onnx.convert(model)
ml_model.save('silero_vad.mlpackage')
"

# Compile for deployment (via Xcode or command line)
xcrun coremlcompiler compile silero_vad.mlpackage .
# Produces silero_vad.mlmodelc/
```

Add `silero_vad.mlmodelc` to your app bundle.

## Kyutai Pocket TTS

**Source**: https://github.com/kyutai-labs/pocketlm

### Model Files
Download from Hugging Face: `kyutai/pocket-tts`

```bash
# Install huggingface-cli
pip install huggingface_hub

# Download model files
huggingface-cli download kyutai/pocket-tts \
    model.safetensors \
    tokenizer.model \
    --local-dir ./PocketTTS

# Download voice embeddings
huggingface-cli download kyutai/pocket-tts \
    voices/alba.safetensors \
    voices/marius.safetensors \
    voices/javert.safetensors \
    voices/jean.safetensors \
    voices/fantine.safetensors \
    voices/cosette.safetensors \
    voices/eponine.safetensors \
    voices/azelma.safetensors \
    --local-dir ./PocketTTS
```

### Rust XCFramework

The inference engine requires compiling the Rust/Candle backend for iOS:

```bash
# Prerequisites
rustup target add aarch64-apple-ios
rustup target add aarch64-apple-ios-sim

# Build for device
cargo build --target aarch64-apple-ios --release

# Build for simulator
cargo build --target aarch64-apple-ios-sim --release

# Create XCFramework
xcodebuild -create-xcframework \
    -library target/aarch64-apple-ios/release/libpocket_tts.a \
    -headers include/ \
    -library target/aarch64-apple-ios-sim/release/libpocket_tts.a \
    -headers include/ \
    -output PocketTTS.xcframework
```

### App Bundle Setup
Place model files in the app bundle under `Models/`:
```
Models/
├── model.safetensors
├── tokenizer.model
└── voices/
    ├── alba.safetensors
    └── ... (8 voice files)
```

On first launch, these are copied to `Documents/models/PocketTTS/` for read-write access.

## Ministral 3 3B (LLM)

**Source**: https://huggingface.co/mistralai/Ministral-3-3B-Instruct-2512-GGUF

```bash
# Download the Q4_K_M quantized model (~2.15 GB)
huggingface-cli download mistralai/Ministral-3-3B-Instruct-2512-GGUF \
    Ministral-3-3B-Instruct-2512-Q4_K_M.gguf \
    --local-dir ./LLM
```

### llama.cpp XCFramework

Add the Stanford BDHG llama.cpp Swift Package:

```swift
// In Package.swift or Xcode SPM
dependencies: [
    .package(
        url: "https://github.com/StanfordBDHG/llama.cpp",
        from: "b7263"
    )
]
```

### Storage
The model is downloaded by the app at runtime (not bundled, due to size). Stored at:
```
Documents/models/LLM/Ministral-3-3B-Instruct-2512-Q4_K_M.gguf
```

## Apple Speech Recognition

**Source**: Built into iOS

No download required. Add to your project:

```swift
import Speech

// Request authorization
SFSpeechRecognizer.requestAuthorization { status in
    // Handle authorization
}
```

Required `Info.plist` keys:
```xml
<key>NSSpeechRecognitionUsageDescription</key>
<string>Speech recognition is used for voice conversations.</string>
<key>NSMicrophoneUsageDescription</key>
<string>Microphone access is needed for voice input.</string>
```

## Disk Space Requirements

| Model | Size | Notes |
|-------|------|-------|
| Silero VAD | ~20MB | In app bundle (included in app size) |
| Pocket TTS | ~230MB | Copied from bundle to Documents |
| Ministral 3B | ~2.15GB | Downloaded at runtime |
| Apple Speech | 0 | System-managed |
| **Total** | **~2.4GB** | User storage on device |
