// CyranoChat - App Entry Point

import SwiftUI

@main
struct CyranoChatApp: App {
    init() {
        // Eagerly initialize model managers so they copy bundled models
        // to Documents on first launch
        _ = GLMASRModelManager.shared
        _ = OnDeviceLLMModelManager.shared
    }

    var body: some Scene {
        WindowGroup {
            ChatView()
        }
    }
}
