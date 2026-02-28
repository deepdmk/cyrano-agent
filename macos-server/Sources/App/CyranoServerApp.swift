// CyranoServer - App Entry Point
// Minimal SwiftUI macOS app for MultipeerConnectivity advertising

import SwiftUI
import Logging

@main
struct CyranoServerApp: App {
    @StateObject private var mcService: CyranoMCService
    @StateObject private var router: MessageRouter

    init() {
        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardOutput(label: label)
            handler.logLevel = .info
            return handler
        }

        do {
            let config = try ServerConfig.load()
            let mc = CyranoMCService(displayName: config.serverDisplayName)
            let claude = ClaudeRelayService(apiKey: config.apiKey, defaultSystemPrompt: config.defaultSystemPrompt)
            let router = MessageRouter(mcService: mc, claudeService: claude, config: config)
            _mcService = StateObject(wrappedValue: mc)
            _router = StateObject(wrappedValue: router)

            Logger(label: "com.cyrano.server").info("Server initialized: \(config.serverDisplayName)")
        } catch {
            // Fatal: can't run without config
            fatalError("Server startup failed: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ServerStatusView(mcService: mcService, router: router)
                .frame(minWidth: 400, minHeight: 300)
                .onAppear {
                    mcService.startAdvertising()
                }
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 500, height: 400)
    }
}
