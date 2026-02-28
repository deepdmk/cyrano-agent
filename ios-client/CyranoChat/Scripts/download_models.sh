#!/bin/bash
# CyranoChat - Download On-Device Models
# Run this script before building to ensure all model files are present.
# Models are bundled into the app and installed on the device at build time.
#
# Usage: ./Scripts/download_models.sh [--all | --vad | --tts | --asr]
#   --all  Download all available models (default)
#   --vad  Download Silero VAD only
#   --tts  Download Pocket TTS only
#   --asr  Download GLM-ASR CoreML models only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
MODELS_DIR="$PROJECT_DIR/Models"

echo "=== CyranoChat Model Downloader ==="
echo "Project: $PROJECT_DIR"
echo "Models:  $MODELS_DIR"
echo ""

# Parse args
DOWNLOAD_VAD=false
DOWNLOAD_TTS=false
DOWNLOAD_ASR=false

if [ $# -eq 0 ] || [ "$1" = "--all" ]; then
    DOWNLOAD_VAD=true
    DOWNLOAD_TTS=true
    DOWNLOAD_ASR=true
else
    for arg in "$@"; do
        case "$arg" in
            --vad) DOWNLOAD_VAD=true ;;
            --tts) DOWNLOAD_TTS=true ;;
            --asr) DOWNLOAD_ASR=true ;;
            *) echo "Unknown option: $arg"; exit 1 ;;
        esac
    done
fi

# ============================================================
# Silero VAD (~2MB CoreML)
# ============================================================
download_vad() {
    echo "--- Silero VAD ---"
    local VAD_DIR="$MODELS_DIR/VAD"
    mkdir -p "$VAD_DIR"

    if [ -d "$VAD_DIR/silero_vad.mlmodelc" ]; then
        echo "  Already present: silero_vad.mlmodelc"
        return 0
    fi

    # Step 1: Download ONNX model
    local ONNX_FILE="$VAD_DIR/silero_vad.onnx"
    if [ ! -f "$ONNX_FILE" ]; then
        echo "  Downloading Silero VAD ONNX model..."
        curl -sL -o "$ONNX_FILE" \
            "https://github.com/snakers4/silero-vad/raw/master/files/silero_vad.onnx"
        echo "  Downloaded silero_vad.onnx ($(du -h "$ONNX_FILE" | cut -f1))"
    fi

    # Step 2: Convert ONNX -> CoreML
    echo "  Converting ONNX to CoreML..."
    if command -v python3 &>/dev/null && python3 -c "import coremltools" 2>/dev/null; then
        python3 - <<'PYEOF'
import coremltools as ct
import onnx
import os

vad_dir = os.environ.get("VAD_DIR", "Models/VAD")
onnx_path = os.path.join(vad_dir, "silero_vad.onnx")
mlpackage_path = os.path.join(vad_dir, "silero_vad.mlpackage")

model = onnx.load(onnx_path)
ml_model = ct.converters.onnx.convert(model)
ml_model.save(mlpackage_path)
print(f"  Saved {mlpackage_path}")
PYEOF
        # Step 3: Compile to mlmodelc
        if [ -d "$VAD_DIR/silero_vad.mlpackage" ]; then
            xcrun coremlcompiler compile "$VAD_DIR/silero_vad.mlpackage" "$VAD_DIR/"
            echo "  Compiled silero_vad.mlmodelc"
            # Cleanup intermediates
            rm -rf "$VAD_DIR/silero_vad.mlpackage" "$ONNX_FILE"
        fi
    else
        echo "  WARNING: coremltools not installed. Install with: pip3 install coremltools onnx"
        echo "  VAD will use RMS-based fallback detection."
    fi
}

# ============================================================
# Kyutai Pocket TTS (~230MB)
# ============================================================
download_tts() {
    echo "--- Pocket TTS ---"
    local TTS_DIR="$MODELS_DIR/PocketTTS"
    mkdir -p "$TTS_DIR/voices"

    local HF_BASE="https://huggingface.co/kyutai/pocket-tts/resolve/main"
    local NEEDED=0
    local DOWNLOADED=0

    # Main model files
    for file in model.safetensors tokenizer.model; do
        NEEDED=$((NEEDED + 1))
        if [ -f "$TTS_DIR/$file" ]; then
            echo "  Already present: $file"
            DOWNLOADED=$((DOWNLOADED + 1))
        else
            echo "  Downloading $file..."
            if curl -sL -f -o "$TTS_DIR/$file" "$HF_BASE/$file" 2>/dev/null; then
                echo "  Downloaded $file ($(du -h "$TTS_DIR/$file" | cut -f1))"
                DOWNLOADED=$((DOWNLOADED + 1))
            else
                echo "  WARNING: Failed to download $file (may not be publicly available)"
            fi
        fi
    done

    # Voice embeddings
    local VOICES="alba marius javert jean fantine cosette eponine azelma"
    for voice in $VOICES; do
        local vfile="voices/${voice}.safetensors"
        NEEDED=$((NEEDED + 1))
        if [ -f "$TTS_DIR/$vfile" ]; then
            echo "  Already present: $vfile"
            DOWNLOADED=$((DOWNLOADED + 1))
        else
            echo "  Downloading $vfile..."
            if curl -sL -f -o "$TTS_DIR/$vfile" "$HF_BASE/$vfile" 2>/dev/null; then
                echo "  Downloaded $vfile"
                DOWNLOADED=$((DOWNLOADED + 1))
            else
                echo "  WARNING: Failed to download $vfile"
            fi
        fi
    done

    echo "  Pocket TTS: $DOWNLOADED/$NEEDED files present"
}

# ============================================================
# GLM-ASR CoreML Models (~395MB for encoder + adapter)
# ============================================================
download_asr() {
    echo "--- GLM-ASR ---"
    local ASR_DIR="$MODELS_DIR/GLM-ASR"
    mkdir -p "$ASR_DIR"

    echo "  GLM-ASR CoreML models: decoder pending (llama.cpp Swift interop in development)"
    echo "  CoreML encoder and adapter are not yet publicly distributed."
    echo "  STT will use Apple Speech as fallback."

    # Create a marker file so the build phase knows we checked
    echo "pending" > "$ASR_DIR/.status"
}

# ============================================================
# Run requested downloads
# ============================================================
if $DOWNLOAD_VAD; then download_vad; fi
if $DOWNLOAD_TTS; then download_tts; fi
if $DOWNLOAD_ASR; then download_asr; fi

echo ""
echo "=== Model Download Summary ==="
echo "VAD (Silero):    $([ -d "$MODELS_DIR/VAD/silero_vad.mlmodelc" ] && echo 'Ready' || echo 'Not available (RMS fallback)')"
echo "TTS (Pocket):    $([ -f "$MODELS_DIR/PocketTTS/model.safetensors" ] && echo 'Ready' || echo 'Not available (Apple TTS fallback)')"
echo "ASR (GLM-ASR):   Decoder pending (Apple Speech fallback)"
echo "LLM (Ministral): Downloaded at runtime via Settings"
echo ""
echo "Run 'xcodegen generate' to regenerate the Xcode project with bundled models."
