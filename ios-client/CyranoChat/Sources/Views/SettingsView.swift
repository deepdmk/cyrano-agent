// CyranoChat - Settings View

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput: String = ""
    @State private var hasKey: Bool = false
    @State private var showKey: Bool = false

    private let availableModels = [
        "claude-sonnet-4-20250514",
        "claude-haiku-4-20250414",
        "claude-opus-4-20250514"
    ]

    var body: some View {
        NavigationStack {
            Form {
                // API Key Section
                Section {
                    HStack {
                        if showKey {
                            TextField("sk-ant-...", text: $apiKeyInput)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .font(.system(.body, design: .monospaced))
                        } else {
                            SecureField("sk-ant-...", text: $apiKeyInput)
                                .textContentType(.password)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                        }

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }

                    Button {
                        saveAPIKey()
                    } label: {
                        HStack {
                            Text("Save API Key")
                            Spacer()
                            if hasKey {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                } header: {
                    Text("Anthropic API Key")
                } footer: {
                    Text("Your API key is stored securely in the iOS Keychain.")
                }

                // Model Selection
                Section("Model") {
                    Picker("Claude Model", selection: $viewModel.selectedModel) {
                        ForEach(availableModels, id: \.self) { model in
                            Text(displayName(for: model))
                                .tag(model)
                        }
                    }
                }

                // System Prompt
                Section("System Prompt") {
                    TextEditor(text: $viewModel.systemPrompt)
                        .frame(minHeight: 80)
                        .font(.subheadline)
                }

                // Voice Settings
                Section {
                    HStack {
                        Image(systemName: "mic.fill")
                            .foregroundStyle(.blue)
                        Text("Voice Input")
                        Spacer()
                        Text("Apple Speech")
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Image(systemName: "speaker.wave.2.fill")
                            .foregroundStyle(.blue)
                        Text("Voice Output")
                        Spacer()
                        Text("Apple TTS")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Voice Pipeline")
                } footer: {
                    Text("STT: Apple Speech (on-device). TTS: Apple TTS (v1). GLM-ASR and Pocket TTS coming soon.")
                }

                // About
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundStyle(.secondary)
                    }

                    if hasKey {
                        Button("Remove API Key", role: .destructive) {
                            KeychainHelper.anthropicAPIKey = nil
                            apiKeyInput = ""
                            hasKey = false
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                hasKey = KeychainHelper.anthropicAPIKey != nil
                if hasKey {
                    apiKeyInput = String(repeating: "*", count: 20)
                }
            }
        }
    }

    private func saveAPIKey() {
        let key = apiKeyInput.trimmingCharacters(in: .whitespaces)
        guard !key.isEmpty, !key.allSatisfy({ $0 == "*" }) else { return }

        viewModel.reconfigureWithAPIKey(key)
        hasKey = true
        apiKeyInput = String(repeating: "*", count: 20)
        showKey = false
    }

    private func displayName(for model: String) -> String {
        switch model {
        case "claude-sonnet-4-20250514": return "Claude Sonnet 4"
        case "claude-haiku-4-20250414": return "Claude Haiku 4"
        case "claude-opus-4-20250514": return "Claude Opus 4"
        default: return model
        }
    }
}

#Preview {
    SettingsView(viewModel: ChatViewModel())
}
