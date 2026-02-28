// CyranoChat - App Entry Point

import SwiftUI

@main
struct CyranoChatApp: App {
    init() {
        // Eagerly initialize model managers and copy bundled models
        // to Documents on first launch
        let glmManager = GLMASRModelManager.shared
        _ = OnDeviceLLMModelManager.shared
        Task {
            await glmManager.installFromBundleIfNeeded()
        }
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
        }
    }
}
