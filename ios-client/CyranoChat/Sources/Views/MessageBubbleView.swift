// CyranoChat - Message Bubble View

import SwiftUI

struct MessageBubbleView: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == .user {
                Spacer(minLength: 48)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                Text(message.content.isEmpty && message.isStreaming ? " " : message.content)
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(bubbleBackground)
                    .foregroundStyle(bubbleForeground)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay {
                        if message.isStreaming {
                            streamingIndicator
                        }
                    }

                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
            }

            if message.role == .assistant {
                Spacer(minLength: 48)
            }
        }
    }

    // MARK: - Styling

    private var bubbleBackground: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(.blue)
        } else {
            return AnyShapeStyle(.fill.secondary)
        }
    }

    private var bubbleForeground: some ShapeStyle {
        if message.role == .user {
            return AnyShapeStyle(.white)
        } else {
            return AnyShapeStyle(.primary)
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: message.timestamp)
    }

    @ViewBuilder
    private var streamingIndicator: some View {
        if message.content.isEmpty {
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Circle()
                        .fill(.secondary)
                        .frame(width: 6, height: 6)
                        .opacity(0.6)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: message.isStreaming
                        )
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        MessageBubbleView(message: ChatMessage(role: .user, content: "Hello!"))
        MessageBubbleView(message: ChatMessage(role: .assistant, content: "Hi! How can I help you today?"))
        MessageBubbleView(message: ChatMessage(role: .assistant, content: "", isStreaming: true))
    }
    .padding()
}
