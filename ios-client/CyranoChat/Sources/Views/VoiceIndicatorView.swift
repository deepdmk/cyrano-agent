// CyranoChat - Voice Indicator View
// Shows voice state with pulsing animation during voice mode

import SwiftUI

struct VoiceIndicatorView: View {
    let state: VoiceState
    let audioLevel: Float
    let transcript: String

    @State private var isPulsing = false

    var body: some View {
        VStack(spacing: 8) {
            // Status text
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 8, height: 8)
                    .scaleEffect(isPulsing ? 1.3 : 1.0)
                    .animation(
                        .easeInOut(duration: 0.8).repeatForever(autoreverses: true),
                        value: isPulsing
                    )

                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fontWeight(.medium)
            }

            // Partial transcript
            if !transcript.isEmpty {
                Text(transcript)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
            }

            // Audio level bars
            if state == .listening {
                HStack(spacing: 3) {
                    ForEach(0..<5, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 2)
                            .fill(.blue)
                            .frame(width: 4, height: barHeight(for: index))
                    }
                }
                .frame(height: 24)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .onAppear { isPulsing = true }
        .onDisappear { isPulsing = false }
    }

    private var statusText: String {
        switch state {
        case .idle: return ""
        case .listening: return "Listening..."
        case .processing: return "Processing..."
        case .generating: return "Thinking..."
        case .speaking: return "Speaking..."
        }
    }

    private var statusColor: Color {
        switch state {
        case .idle: return .gray
        case .listening: return .green
        case .processing, .generating: return .orange
        case .speaking: return .blue
        }
    }

    private func barHeight(for index: Int) -> CGFloat {
        let normalized = CGFloat(max(0, min(1, audioLevel)))
        let base: CGFloat = 4
        let maxHeight: CGFloat = 24
        let variation = sin(Double(index) * 1.2 + Double(normalized) * 5) * 0.3 + 0.7
        return base + (maxHeight - base) * normalized * CGFloat(variation)
    }
}

#Preview {
    VStack {
        VoiceIndicatorView(state: .listening, audioLevel: 0.5, transcript: "Hello world")
        VoiceIndicatorView(state: .generating, audioLevel: 0.0, transcript: "")
        VoiceIndicatorView(state: .speaking, audioLevel: 0.0, transcript: "")
    }
}
