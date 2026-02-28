// CyranoChat - LLM Loadable Service Protocol
// Extension protocol for on-device LLM services that require model loading

import Foundation

// MARK: - LLM Loadable Service

/// Protocol for LLM services that require explicit model loading/unloading
/// On-device models need to be loaded into memory before inference
public protocol LLMLoadableService: LLMService {
    /// Load the model into memory
    func loadModel() async throws

    /// Unload the model to free memory
    func unloadModel() async
}
