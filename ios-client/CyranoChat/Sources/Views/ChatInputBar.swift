// CyranoChat - Chat Input Bar

import SwiftUI

struct ChatInputBar: View {
    @Binding var text: String
    let isGenerating: Bool
    let voiceState: VoiceState
    let onSend: () -> Void
    let onVoiceToggle: () -> Void

    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            HStack(alignment: .bottom, spacing: 10) {
                // Microphone button
                Button(action: onVoiceToggle) {
                    Image(systemName: voiceIcon)
                        .font(.system(size: 20))
                        .foregroundStyle(voiceState != .idle ? .red : .blue)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .disabled(isGenerating && voiceState == .idle)
                .accessibilityLabel(voiceState != .idle ? "Stop voice" : "Start voice")

                // Text input
                TextField("Message", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...6)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 20)
                            .fill(.fill.tertiary)
                    )
                    .focused($isFocused)
                    .onSubmit {
                        if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            onSend()
                        }
                    }
                    .submitLabel(.send)
                    .disabled(voiceState != .idle)

                // Send button
                Button(action: onSend) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(canSend ? .blue : .gray.opacity(0.4))
                }
                .disabled(!canSend)
                .accessibilityLabel("Send message")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.bar)
        }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating
            && voiceState == .idle
    }

    private var voiceIcon: String {
        switch voiceState {
        case .idle:
            return "mic.fill"
        case .listening:
            return "waveform"
        case .processing, .generating:
            return "ellipsis.circle.fill"
        case .speaking:
            return "speaker.wave.2.fill"
        }
    }
}

#Preview {
    VStack {
        Spacer()
        ChatInputBar(
            text: .constant("Hello"),
            isGenerating: false,
            voiceState: .idle,
            onSend: {},
            onVoiceToggle: {}
        )
    }
}
