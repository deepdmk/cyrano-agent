// CyranoServer - Server Status View
// Minimal macOS window showing server state, connected peers, and event log

import SwiftUI

struct ServerStatusView: View {
    @ObservedObject var mcService: CyranoMCService
    @ObservedObject var router: MessageRouter

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            headerSection
            Divider()

            // Peers
            peersSection
            Divider()

            // Event log
            eventLogSection
        }
        .padding()
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Cyrano Server")
                    .font(.title2.weight(.semibold))
                HStack(spacing: 6) {
                    Circle()
                        .fill(mcService.isAdvertising ? .green : .red)
                        .frame(width: 8, height: 8)
                    Text(mcService.isAdvertising ? "Advertising" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(router.requestCount) requests")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let lastTime = router.lastRequestTime {
                    Text(lastTime, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            Button {
                if mcService.isAdvertising {
                    mcService.stopAdvertising()
                } else {
                    mcService.startAdvertising()
                }
            } label: {
                Image(systemName: mcService.isAdvertising ? "stop.circle" : "play.circle")
                    .font(.title2)
            }
            .buttonStyle(.plain)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Peers

    private var peersSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Connected Peers")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            if mcService.connectedPeers.isEmpty {
                Text("No peers connected")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .padding(.vertical, 4)
            } else {
                ForEach(mcService.connectedPeers, id: \.displayName) { peer in
                    HStack(spacing: 6) {
                        Image(systemName: "iphone")
                            .foregroundStyle(.blue)
                            .font(.caption)
                        Text(peer.displayName)
                            .font(.callout)
                    }
                }
            }
        }
        .padding(.bottom, 8)
    }

    // MARK: - Event Log

    private var eventLogSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Event Log")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(mcService.recentEvents.enumerated()), id: \.offset) { index, event in
                            HStack(alignment: .top, spacing: 8) {
                                Text(event.timestamp, style: .time)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .frame(width: 70, alignment: .leading)
                                Text(event.message)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            .id(index)
                        }
                    }
                    .onChange(of: mcService.recentEvents.count) { _, newCount in
                        if newCount > 0 {
                            proxy.scrollTo(newCount - 1, anchor: .bottom)
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }
}
