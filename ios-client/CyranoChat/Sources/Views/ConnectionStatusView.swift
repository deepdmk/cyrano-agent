// CyranoChat - Connection Status View
// Small reusable view showing MultipeerConnectivity state

import SwiftUI

struct ConnectionStatusView: View {
    let state: MCConnectionState
    let serverName: String?

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var statusColor: Color {
        switch state {
        case .connected: return .green
        case .browsing, .connecting: return .orange
        case .disconnected: return .gray
        case .error: return .red
        }
    }

    private var statusText: String {
        switch state {
        case .disconnected: return "Disconnected"
        case .browsing: return "Searching..."
        case .connecting: return "Connecting..."
        case .connected: return serverName ?? "Connected"
        case .error(let msg): return msg
        }
    }
}
