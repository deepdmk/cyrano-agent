// CyranoChat - Main Chat View

import SwiftUI

struct ChatView: View {
    @StateObject private var viewModel = ChatViewModel()
    @State private var showSettings = false
    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            messageList
                .safeAreaInset(edge: .bottom) {
                    VStack(spacing: 0) {
                        // Voice indicator
                        if viewModel.voiceState != .idle {
                            VoiceIndicatorView(
                                state: viewModel.voiceState,
                                audioLevel: viewModel.audioLevel,
                                transcript: viewModel.partialTranscript
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Input bar
                        ChatInputBar(
                            text: $viewModel.inputText,
                            isGenerating: viewModel.isGenerating,
                            voiceState: viewModel.voiceState,
                            onSend: {
                                Task { await viewModel.sendMessage() }
                            },
                            onVoiceToggle: {
                                Task { await viewModel.toggleVoice() }
                            }
                        )
                        .focused($inputFocused)
                    }
                }
                .navigationTitle("Cyrano")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        HStack(spacing: 8) {
                            Button {
                                viewModel.clearConversation()
                            } label: {
                                Image(systemName: "plus.message")
                            }
                            .disabled(viewModel.messages.isEmpty)

                            if viewModel.serverMode {
                                ConnectionStatusView(
                                    state: viewModel.multipeerSessionManager.connectionState,
                                    serverName: viewModel.multipeerSessionManager.connectedServerName
                                )
                            }
                        }
                    }

                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showSettings = true
                        } label: {
                            Image(systemName: "gear")
                        }
                    }
                }
                .sheet(isPresented: $showSettings) {
                    SettingsView(viewModel: viewModel)
                }
                .onAppear {
                    if !viewModel.serverMode && !viewModel.hasAPIKey {
                        showSettings = true
                    }
                }
                .alert("Error", isPresented: .init(
                    get: { viewModel.errorMessage != nil },
                    set: { if !$0 { viewModel.errorMessage = nil } }
                )) {
                    Button("OK") { viewModel.errorMessage = nil }
                } message: {
                    Text(viewModel.errorMessage ?? "")
                }
                .onTapGesture {
                    inputFocused = false
                }
        }
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    emptyState
                } else {
                    LazyVStack(spacing: 2) {
                        ForEach(viewModel.messages) { message in
                            MessageBubbleView(message: message)
                                .id(message.id)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 4)
                }
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: viewModel.messages.count) { _, _ in
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                }
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo(viewModel.messages.last?.id, anchor: .bottom)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
                .frame(height: 120)
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 56, weight: .thin))
                .foregroundStyle(.tertiary)
            Text("Start a conversation")
                .font(.title2.weight(.medium))
                .foregroundStyle(.secondary)
            Text("Type a message or tap the microphone")
                .font(.subheadline)
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding()
    }
}

#Preview {
    ChatView()
}
