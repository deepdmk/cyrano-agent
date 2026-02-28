// CyranoChat - GLM-ASR Model Manager
// Manages GLM-ASR-Nano on-device speech recognition models
//
// Part of Services/STT

import Foundation
import OSLog

// MARK: - Model Info

/// Static information about the GLM-ASR-Nano model pipeline
public enum GLMASRModelInfo {
    public static let displayName = "GLM-ASR-Nano"
    public static let version = "On-Device Decoder"
    public static let architecture = "4 CoreML Stages + GGUF Decoder"
    public static let totalSizeMB: Float = 2233
    public static let minimumRAMGB = 3
    public static let minimumIOSVersion = "17.0"
    public static let license = "Apache 2.0"
    public static let publisher = "GLM / Kyutai"
    public static let sampleRate = 16000
    public static let typicalLatencyMS = 150

    /// Individual model components (matches actual files from unamentis)
    public static let components: [GLMASRModelComponent] = [
        GLMASRModelComponent(
            name: "Conv Encoder",
            filename: "GLMASRConvEncoder.mlmodelc",
            format: .coreML,
            sizeMB: 10,
            description: "Audio waveform → Initial convolutional features"
        ),
        GLMASRModelComponent(
            name: "Whisper Encoder",
            filename: "GLMASRWhisperEncoder.mlmodelc",
            format: .coreML,
            sizeMB: 1200,
            description: "Mel spectrogram → Audio embeddings (1×1500×1280)"
        ),
        GLMASRModelComponent(
            name: "Audio Adapter",
            filename: "GLMASRAudioAdapter.mlmodelc",
            format: .coreML,
            sizeMB: 56,
            description: "Audio embeddings → Language embeddings (1×375×2048)"
        ),
        GLMASRModelComponent(
            name: "Embed Head",
            filename: "GLMASREmbedHead.mlmodelc",
            format: .coreML,
            sizeMB: 232,
            description: "Language embeddings → Token logits"
        ),
        GLMASRModelComponent(
            name: "GGUF Decoder",
            filename: "glm_decoder.gguf",
            format: .gguf,
            sizeMB: 935,
            description: "Language embeddings → Text tokens via llama.cpp (Q4_K_M)"
        )
    ]
}

// MARK: - Model Component

/// Individual model file in the GLM-ASR pipeline
public struct GLMASRModelComponent: Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let filename: String
    public let format: ModelFormat
    public let sizeMB: Int
    public let description: String

    public enum ModelFormat: String, Sendable {
        case coreML = "CoreML"
        case gguf = "GGUF"
    }
}

// MARK: - Model Manager

/// Manages GLM-ASR-Nano model files for on-device speech recognition
///
/// The GLM-ASR pipeline consists of five models:
/// 1. **Conv Encoder** (CoreML) - Initial convolutional feature extraction
/// 2. **Whisper Encoder** (CoreML) - Mel spectrogram to audio embeddings
/// 3. **Audio Adapter** (CoreML) - Audio embeddings to language embeddings
/// 4. **Embed Head** (CoreML) - Language embeddings to token logits
/// 5. **GGUF Decoder** (llama.cpp) - Language embeddings to text tokens
///
/// Model files are bundled with the app under Models/GLM-ASR/ and copied
/// to Documents/models/GLM-ASR/ on first launch for read-write access.
public actor GLMASRModelManager {
    /// Shared singleton instance
    public static let shared = GLMASRModelManager()

    private let logger = Logger(subsystem: "com.cyrano", category: "GLMASRModelManager")

    // MARK: - Model State

    /// Current state of the model pipeline
    public enum ModelState: Sendable, Equatable {
        case notDownloaded       // Models not present
        case downloading(Float)  // Download in progress
        case available           // All models present
        case decoderPending      // CoreML models present but GGUF decoder missing
        case loading(Float)      // Loading into memory
        case loaded              // Ready for inference
        case error(String)       // Error occurred

        public static func == (lhs: ModelState, rhs: ModelState) -> Bool {
            switch (lhs, rhs) {
            case (.notDownloaded, .notDownloaded),
                 (.available, .available),
                 (.decoderPending, .decoderPending),
                 (.loaded, .loaded):
                return true
            case let (.downloading(p1), .downloading(p2)),
                 let (.loading(p1), .loading(p2)):
                return abs(p1 - p2) < 0.01
            case let (.error(e1), .error(e2)):
                return e1 == e2
            default:
                return false
            }
        }

        public var isReady: Bool {
            self == .loaded
        }

        public var isAvailable: Bool {
            self == .available || self == .loaded || self == .decoderPending
        }

        public var displayText: String {
            switch self {
            case .notDownloaded: return "Not Downloaded"
            case .downloading(let progress): return "Downloading \(Int(progress * 100))%"
            case .available: return "Ready to Load"
            case .decoderPending: return "Decoder Pending"
            case .loading(let progress): return "Loading \(Int(progress * 100))%"
            case .loaded: return "Loaded"
            case .error(let message): return "Error: \(message)"
            }
        }
    }

    public private(set) var state: ModelState = .notDownloaded

    // MARK: - Model Paths

    /// Base directory for GLM-ASR models in Documents
    private var modelDirectory: URL {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        return documentsPath.appendingPathComponent("models/GLM-ASR", isDirectory: true)
    }

    /// All model file paths (matches actual files from unamentis build)
    private var convEncoderPath: URL {
        modelDirectory.appendingPathComponent("GLMASRConvEncoder.mlmodelc")
    }
    private var whisperEncoderPath: URL {
        modelDirectory.appendingPathComponent("GLMASRWhisperEncoder.mlmodelc")
    }
    private var audioAdapterPath: URL {
        modelDirectory.appendingPathComponent("GLMASRAudioAdapter.mlmodelc")
    }
    private var embedHeadPath: URL {
        modelDirectory.appendingPathComponent("GLMASREmbedHead.mlmodelc")
    }
    private var decoderPath: URL {
        modelDirectory.appendingPathComponent("glm_decoder.gguf")
    }

    /// All required component paths
    private var allComponentPaths: [(String, URL)] {
        [
            ("GLMASRConvEncoder.mlmodelc", convEncoderPath),
            ("GLMASRWhisperEncoder.mlmodelc", whisperEncoderPath),
            ("GLMASRAudioAdapter.mlmodelc", audioAdapterPath),
            ("GLMASREmbedHead.mlmodelc", embedHeadPath),
            ("glm_decoder.gguf", decoderPath)
        ]
    }

    /// CoreML-only component paths (without GGUF decoder)
    private var coreMLComponentPaths: [(String, URL)] {
        [
            ("GLMASRConvEncoder.mlmodelc", convEncoderPath),
            ("GLMASRWhisperEncoder.mlmodelc", whisperEncoderPath),
            ("GLMASRAudioAdapter.mlmodelc", audioAdapterPath),
            ("GLMASREmbedHead.mlmodelc", embedHeadPath)
        ]
    }

    // MARK: - Initialization

    public init() {
        Task {
            await checkModelAvailability()
            // Proactively copy models from bundle if not yet in Documents
            if !isModelAvailable() && !areCoreMLModelsAvailable() {
                try? await downloadModels()
                await checkModelAvailability()
            }
        }
    }

    // MARK: - Public API

    /// Get current model state
    nonisolated public func currentState() async -> ModelState {
        await state
    }

    /// Check which components are available
    public func componentStatus() -> [String: Bool] {
        var status: [String: Bool] = [:]
        for (name, path) in allComponentPaths {
            status[name] = FileManager.default.fileExists(atPath: path.path)
        }
        return status
    }

    /// Check if all model files are available locally
    public func isModelAvailable() -> Bool {
        allComponentPaths.allSatisfy { _, path in
            FileManager.default.fileExists(atPath: path.path)
        }
    }

    /// Check if CoreML models are available (even if GGUF decoder is not)
    public func areCoreMLModelsAvailable() -> Bool {
        coreMLComponentPaths.allSatisfy { _, path in
            FileManager.default.fileExists(atPath: path.path)
        }
    }

    /// Get total size of downloaded files in MB
    public func downloadedSizeMB() -> Int {
        var totalBytes: Int64 = 0
        for (_, path) in allComponentPaths {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: path.path),
               let size = attrs[.size] as? Int64 {
                totalBytes += size
            }
        }
        return Int(totalBytes / 1_000_000)
    }

    /// Copy models from app bundle to Documents (called on first launch or from Settings)
    public func downloadModels() async throws {
        if isModelAvailable() {
            state = .available
            return
        }

        state = .downloading(0.0)
        logger.info("Installing GLM-ASR models from app bundle...")

        // Create model directory
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        // Copy from app bundle
        if await copyModelsFromBundle() {
            if isModelAvailable() {
                state = .available
            } else if areCoreMLModelsAvailable() {
                state = .decoderPending
            }
            return
        }

        state = .error("Models not found in app bundle")
        throw GLMASRModelError.modelsNotAvailable
    }

    /// Cancel ongoing download
    public func cancelDownload() {
        state = .notDownloaded
        logger.info("GLM-ASR install cancelled")
    }

    /// Delete all model files from Documents
    public func deleteModels() async throws {
        if FileManager.default.fileExists(atPath: modelDirectory.path) {
            try FileManager.default.removeItem(at: modelDirectory)
            logger.info("GLM-ASR models deleted from Documents")
        }
        state = .notDownloaded
    }

    // MARK: - Private Helpers

    private func checkModelAvailability() {
        if isModelAvailable() {
            state = .available
            logger.info("All GLM-ASR models found at: \(self.modelDirectory.path)")
        } else if areCoreMLModelsAvailable() {
            state = .decoderPending
            logger.info("CoreML models found, GGUF decoder pending")
        } else {
            state = .notDownloaded
            logger.info("GLM-ASR models not found in Documents")
        }
    }

    private func copyModelsFromBundle() async -> Bool {
        guard let bundleURL = Bundle.main.resourceURL else {
            return false
        }

        let bundleModelDir = bundleURL.appendingPathComponent("Models/GLM-ASR")
        guard FileManager.default.fileExists(atPath: bundleModelDir.path) else {
            logger.info("GLM-ASR models not found in app bundle at: \(bundleModelDir.path)")
            return false
        }

        logger.info("Found bundled GLM-ASR models at: \(bundleModelDir.path)")

        do {
            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

            var copiedCount = 0
            for (filename, destPath) in allComponentPaths {
                let bundlePath = bundleModelDir.appendingPathComponent(filename)
                if FileManager.default.fileExists(atPath: bundlePath.path)
                    && !FileManager.default.fileExists(atPath: destPath.path) {
                    try FileManager.default.copyItem(at: bundlePath, to: destPath)
                    logger.info("Copied \(filename)")
                    copiedCount += 1
                }
            }

            logger.info("Copied \(copiedCount) model files to Documents")
            return areCoreMLModelsAvailable()
        } catch {
            logger.error("Failed to copy GLM-ASR models: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - Model Error

/// Errors for GLM-ASR model operations
public enum GLMASRModelError: Error, LocalizedError {
    case modelsNotAvailable
    case modelsNotDownloaded
    case decoderNotImplemented
    case encoderLoadFailed(String)
    case adapterLoadFailed(String)
    case decoderLoadFailed(String)
    case deleteFailed(String)

    public var errorDescription: String? {
        switch self {
        case .modelsNotAvailable:
            return "GLM-ASR models are not available. Ensure they are bundled with the app."
        case .modelsNotDownloaded:
            return "GLM-ASR models are not installed."
        case .decoderNotImplemented:
            return "The GGUF decoder requires llama.cpp Swift interop, which is pending."
        case .encoderLoadFailed(let reason):
            return "Failed to load encoder: \(reason)"
        case .adapterLoadFailed(let reason):
            return "Failed to load adapter: \(reason)"
        case .decoderLoadFailed(let reason):
            return "Failed to load decoder: \(reason)"
        case .deleteFailed(let reason):
            return "Failed to delete models: \(reason)"
        }
    }
}

// MARK: - State Observer

/// Observable wrapper for GLM-ASR model state (for SwiftUI)
@MainActor
public final class GLMASRModelStateObserver: ObservableObject {
    @Published public var state: GLMASRModelManager.ModelState = .notDownloaded

    private let manager: GLMASRModelManager

    public init(manager: GLMASRModelManager) {
        self.manager = manager
        Task {
            await refreshState()
        }
    }

    public func refreshState() async {
        state = await manager.currentState()
    }
}

// MARK: - Preview Support

#if DEBUG
extension GLMASRModelManager {
    public static func preview() -> GLMASRModelManager {
        GLMASRModelManager()
    }
}
#endif
