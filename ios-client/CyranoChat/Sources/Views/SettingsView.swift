// CyranoChat - Settings View

import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: ChatViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var apiKeyInput: String = ""
    @State private var hasKey: Bool = false
    @State private var showKey: Bool = false

    // On-device model state
    @State private var pocketTTSModelState: KyutaiPocketModelManager.ModelState = .notDownloaded
    @State private var llmModelState: OnDeviceLLMModelManager.ModelState = .notDownloaded
    @State private var asrModelState: GLMASRModelManager.ModelState = .notDownloaded
    @State private var isDownloadingTTS = false
    @State private var isDownloadingLLM = false
    @State private var isDownloadingASR = false
    @State private var showDeleteTTSConfirm = false
    @State private var showDeleteLLMConfirm = false
    @State private var showDeleteASRConfirm = false

    private let pocketModelManager = KyutaiPocketModelManager()
    private let llmModelManager = OnDeviceLLMModelManager.shared
    private let asrModelManager = GLMASRModelManager.shared

    private let availableModels = [
        "claude-sonnet-4-6-20250620",
        "claude-opus-4-6-20250612",
        "claude-haiku-4-5-20251001"
    ]

    var body: some View {
        NavigationStack {
            Form {
                apiKeySection
                sttSection
                ttsSection
                llmSection
                systemPromptSection
                aboutSection
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
                refreshModelStates()
            }
        }
    }

    // MARK: - API Key Section

    private var apiKeySection: some View {
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
    }

    // MARK: - Speech Recognition (STT + GLM-ASR Model)

    private var sttSection: some View {
        Section {
            // Provider picker
            Picker("Provider", selection: $viewModel.selectedSTTProvider) {
                ForEach(ChatViewModel.availableSTTProviders, id: \.self) { provider in
                    Label {
                        Text(sttDisplayName(provider))
                    } icon: {
                        Image(systemName: provider.isOnDevice ? "iphone" : "cloud")
                    }
                    .tag(provider)
                }
            }

            // GLM-ASR model info (always shown since it's a key feature)
            DisclosureGroup {
                // Pipeline components
                ForEach(GLMASRModelInfo.components) { component in
                    HStack {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(component.name)
                                .font(.subheadline)
                            Text(component.description)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(component.format.rawValue)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("\(component.sizeMB) MB")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                HStack {
                    Text("Total Size")
                    Spacer()
                    Text("\(Int(GLMASRModelInfo.totalSizeMB)) MB")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Latency")
                    Spacer()
                    Text("~\(GLMASRModelInfo.typicalLatencyMS)ms")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Min RAM")
                    Spacer()
                    Text("\(GLMASRModelInfo.minimumRAMGB) GB")
                        .foregroundStyle(.secondary)
                }

                // Download / Delete actions
                asrModelActions
            } label: {
                HStack {
                    Label {
                        Text(GLMASRModelInfo.displayName)
                    } icon: {
                        Image(systemName: "ear")
                    }
                    Spacer()
                    asrStatusBadge
                }
            }
        } header: {
            Label("Speech Recognition (STT)", systemImage: "waveform")
        } footer: {
            Text(sttFooterText)
        }
    }

    @ViewBuilder
    private var asrModelActions: some View {
        switch asrModelState {
        case .notDownloaded:
            Button {
                downloadASRModels()
            } label: {
                Label("Download Models (~\(Int(GLMASRModelInfo.totalSizeMB)) MB)", systemImage: "arrow.down.circle")
            }

        case .downloading(let progress):
            HStack {
                ProgressView(value: Double(progress))
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            Button(role: .destructive) {
                cancelASRDownload()
            } label: {
                Text("Cancel")
            }

        case .decoderPending:
            VStack(alignment: .leading, spacing: 4) {
                Label("GGUF Decoder Pending", systemImage: "clock")
                    .foregroundStyle(.orange)
                    .font(.subheadline)
                Text("CoreML models ready. llama.cpp decoder under development. Using Apple Speech fallback.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button(role: .destructive) {
                showDeleteASRConfirm = true
            } label: {
                Label("Delete Models", systemImage: "trash")
            }
            .confirmationDialog("Delete GLM-ASR Models?", isPresented: $showDeleteASRConfirm) {
                Button("Delete (~\(Int(GLMASRModelInfo.totalSizeMB)) MB)", role: .destructive) {
                    deleteASRModels()
                }
            } message: {
                Text("Speech recognition will continue using Apple Speech.")
            }

        case .available, .loaded:
            Button(role: .destructive) {
                showDeleteASRConfirm = true
            } label: {
                Label("Delete Models", systemImage: "trash")
            }
            .confirmationDialog("Delete GLM-ASR Models?", isPresented: $showDeleteASRConfirm) {
                Button("Delete (~\(Int(GLMASRModelInfo.totalSizeMB)) MB)", role: .destructive) {
                    deleteASRModels()
                }
            } message: {
                Text("Speech recognition will fall back to Apple Speech.")
            }

        case .loading(let progress):
            HStack {
                Text("Loading models...")
                Spacer()
                ProgressView(value: Double(progress))
                    .frame(width: 100)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Error", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                downloadASRModels()
            } label: {
                Label("Retry Download", systemImage: "arrow.clockwise")
            }
        }
    }

    @ViewBuilder
    private var asrStatusBadge: some View {
        switch asrModelState {
        case .decoderPending:
            Text("Decoder Pending")
                .font(.caption.weight(.medium))
                .foregroundStyle(.orange)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(
                    Capsule()
                        .fill(Color.orange.opacity(0.12))
                )
        default:
            modelStatusBadge(for: asrModelState)
        }
    }

    // MARK: - Text-to-Speech (TTS + Pocket TTS Model)

    private var ttsSection: some View {
        Section {
            // Provider picker
            Picker("Provider", selection: $viewModel.selectedTTSProvider) {
                ForEach(ChatViewModel.availableTTSProviders, id: \.self) { provider in
                    Label {
                        Text(ttsDisplayName(provider))
                    } icon: {
                        Image(systemName: provider.isOnDevice ? "iphone" : "cloud")
                    }
                    .tag(provider)
                }
            }

            // Pocket TTS voice/preset when selected
            if viewModel.selectedTTSProvider == .pocketTTS {
                Picker("Voice", selection: $viewModel.selectedPocketVoice) {
                    ForEach(KyutaiPocketVoice.allCases, id: \.self) { voice in
                        VStack(alignment: .leading) {
                            Text(voice.displayName)
                            Text(voice.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .tag(voice)
                    }
                }

                Picker("Quality Preset", selection: $viewModel.selectedPocketPreset) {
                    ForEach(KyutaiPocketPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName)
                            .tag(preset)
                    }
                }
            }

            Toggle("Voice Output", isOn: $viewModel.voiceOutputEnabled)

            // Pocket TTS model info
            DisclosureGroup {
                HStack {
                    Text("Size")
                    Spacer()
                    Text("\(KyutaiPocketModelInfo.totalSizeMB) MB")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Latency")
                    Spacer()
                    Text("~\(KyutaiPocketModelInfo.typicalLatencyMS)ms TTFA")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Word Error Rate")
                    Spacer()
                    Text(String(format: "%.2f%%", KyutaiPocketModelInfo.wordErrorRate * 100))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("License")
                    Spacer()
                    Text(KyutaiPocketModelInfo.license)
                        .foregroundStyle(.secondary)
                }

                // Download / Delete actions
                pocketTTSModelActions
            } label: {
                HStack {
                    Label {
                        Text("Pocket TTS")
                    } icon: {
                        Image(systemName: "waveform")
                    }
                    Spacer()
                    modelStatusBadge(for: pocketTTSModelState)
                }
            }
        } header: {
            Label("Text-to-Speech (TTS)", systemImage: "speaker.wave.2")
        } footer: {
            Text(ttsFooterText)
        }
    }

    @ViewBuilder
    private var pocketTTSModelActions: some View {
        switch pocketTTSModelState {
        case .notDownloaded:
            Button {
                downloadPocketTTSModel()
            } label: {
                Label("Download Model", systemImage: "arrow.down.circle")
            }

        case .downloading(let progress):
            HStack {
                ProgressView(value: Double(progress))
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }

        case .available, .loaded:
            Button(role: .destructive) {
                showDeleteTTSConfirm = true
            } label: {
                Label("Delete Model", systemImage: "trash")
            }
            .confirmationDialog("Delete Pocket TTS Model?", isPresented: $showDeleteTTSConfirm) {
                Button("Delete (~\(KyutaiPocketModelInfo.totalSizeMB) MB)", role: .destructive) {
                    deletePocketTTSModel()
                }
            } message: {
                Text("Voice output will fall back to Apple TTS.")
            }

        case .loading(let progress):
            HStack {
                Text("Loading model...")
                Spacer()
                ProgressView(value: Double(progress))
                    .frame(width: 100)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Error", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                downloadPocketTTSModel()
            } label: {
                Label("Retry Download", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - LLM Section (Claude API + On-Device Model)

    private var llmSection: some View {
        Section {
            Picker("Claude Model", selection: $viewModel.selectedModel) {
                ForEach(availableModels, id: \.self) { model in
                    Text(displayName(for: model))
                        .tag(model)
                }
            }

            // On-device LLM model info
            DisclosureGroup {
                HStack {
                    Text("Size")
                    Spacer()
                    Text(String(format: "%.1f GB", OnDeviceLLMModelInfo.totalSizeMB / 1000))
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Context Window")
                    Spacer()
                    Text("\(OnDeviceLLMModelInfo.contextSize) tokens")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Min RAM")
                    Spacer()
                    Text("\(OnDeviceLLMModelInfo.minimumRAMGB) GB")
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("Publisher")
                    Spacer()
                    Text(OnDeviceLLMModelInfo.publisher)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    Text("License")
                    Spacer()
                    Text(OnDeviceLLMModelInfo.license)
                        .foregroundStyle(.secondary)
                }

                // Download / Delete actions
                llmModelActions
            } label: {
                HStack {
                    Label {
                        Text(OnDeviceLLMModelInfo.displayName)
                    } icon: {
                        Image(systemName: "cpu")
                    }
                    Spacer()
                    modelStatusBadge(for: llmModelState)
                }
            }
        } header: {
            Label("Language Model (LLM)", systemImage: "brain")
        } footer: {
            Text("Cloud models use your API key. On-device model runs offline with no API costs.")
        }
    }

    @ViewBuilder
    private var llmModelActions: some View {
        switch llmModelState {
        case .notDownloaded:
            Button {
                downloadLLMModel()
            } label: {
                Label("Download Model (~2.2 GB)", systemImage: "arrow.down.circle")
            }

        case .downloading(let progress):
            HStack {
                ProgressView(value: Double(progress))
                Text("\(Int(progress * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 40)
            }
            Button(role: .destructive) {
                cancelLLMDownload()
            } label: {
                Text("Cancel")
            }

        case .verifying:
            HStack {
                Text("Verifying download...")
                Spacer()
                ProgressView()
            }

        case .available, .loaded:
            Button(role: .destructive) {
                showDeleteLLMConfirm = true
            } label: {
                Label("Delete Model", systemImage: "trash")
            }
            .confirmationDialog("Delete On-Device LLM?", isPresented: $showDeleteLLMConfirm) {
                Button("Delete (~2.2 GB)", role: .destructive) {
                    deleteLLMModel()
                }
            } message: {
                Text("The app will use Claude API instead. You can re-download anytime.")
            }

        case .loading(let progress):
            HStack {
                Text("Loading into memory...")
                Spacer()
                ProgressView(value: Double(progress))
                    .frame(width: 100)
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label("Error", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                downloadLLMModel()
            } label: {
                Label("Retry Download", systemImage: "arrow.clockwise")
            }
        }
    }

    // MARK: - System Prompt

    private var systemPromptSection: some View {
        Section("System Prompt") {
            TextEditor(text: $viewModel.systemPrompt)
                .frame(minHeight: 80)
                .font(.subheadline)
        }
    }

    // MARK: - About Section

    private var aboutSection: some View {
        Section("About") {
            HStack {
                Text("Version")
                Spacer()
                Text("1.0.0")
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Voice Pipeline")
                Spacer()
                Text("Reference v1")
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

    // MARK: - Model Status Badge

    @ViewBuilder
    private func modelStatusBadge(for state: some Equatable) -> some View {
        if let ttsState = state as? KyutaiPocketModelManager.ModelState {
            statusLabel(text: ttsState.displayText, isReady: ttsState.isReady)
        } else if let llmState = state as? OnDeviceLLMModelManager.ModelState {
            statusLabel(text: llmState.displayText, isReady: llmState.isReady)
        } else if let asrState = state as? GLMASRModelManager.ModelState {
            statusLabel(text: asrState.displayText, isReady: asrState.isReady)
        }
    }

    private func statusLabel(text: String, isReady: Bool) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(isReady ? .green : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(isReady ? Color.green.opacity(0.12) : Color(.systemGray5))
            )
    }

    // MARK: - Model Actions

    private func refreshModelStates() {
        Task {
            pocketTTSModelState = await pocketModelManager.currentState()
            llmModelState = await llmModelManager.currentState()
            asrModelState = await asrModelManager.currentState()
        }
    }

    private func downloadPocketTTSModel() {
        isDownloadingTTS = true
        Task {
            do {
                try await pocketModelManager.ensureModelsAvailable()
                pocketTTSModelState = await pocketModelManager.currentState()
            } catch {
                pocketTTSModelState = .error(error.localizedDescription)
            }
            isDownloadingTTS = false
        }
    }

    private func deletePocketTTSModel() {
        Task {
            await pocketModelManager.unloadModels()
            pocketTTSModelState = await pocketModelManager.currentState()
        }
    }

    private func downloadLLMModel() {
        isDownloadingLLM = true
        Task {
            do {
                try await llmModelManager.downloadModel()
                llmModelState = await llmModelManager.currentState()
            } catch {
                llmModelState = await llmModelManager.currentState()
            }
            isDownloadingLLM = false
        }
    }

    private func cancelLLMDownload() {
        Task {
            await llmModelManager.cancelDownload()
            llmModelState = await llmModelManager.currentState()
        }
    }

    private func deleteLLMModel() {
        Task {
            do {
                try await llmModelManager.deleteModel()
            } catch {}
            llmModelState = await llmModelManager.currentState()
        }
    }

    private func downloadASRModels() {
        isDownloadingASR = true
        Task {
            do {
                try await asrModelManager.downloadModels()
                asrModelState = await asrModelManager.currentState()
            } catch {
                asrModelState = await asrModelManager.currentState()
            }
            isDownloadingASR = false
        }
    }

    private func cancelASRDownload() {
        Task {
            await asrModelManager.cancelDownload()
            asrModelState = await asrModelManager.currentState()
        }
    }

    private func deleteASRModels() {
        Task {
            do {
                try await asrModelManager.deleteModels()
            } catch {}
            asrModelState = await asrModelManager.currentState()
        }
    }

    // MARK: - Helpers

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
        case "claude-sonnet-4-6-20250620": return "Claude Sonnet 4.6"
        case "claude-opus-4-6-20250612": return "Claude Opus 4.6"
        case "claude-haiku-4-5-20251001": return "Claude Haiku 4.5"
        default: return model
        }
    }

    private func sttDisplayName(_ provider: STTProvider) -> String {
        switch provider {
        case .appleSpeech: return "Apple Speech"
        case .glmASROnDevice: return "GLM-ASR (On-Device)"
        default: return provider.displayName
        }
    }

    private func ttsDisplayName(_ provider: TTSProvider) -> String {
        switch provider {
        case .pocketTTS: return "Pocket TTS"
        case .appleTTS: return "Apple TTS"
        default: return provider.displayName
        }
    }

    private var sttFooterText: String {
        switch viewModel.selectedSTTProvider {
        case .appleSpeech:
            return "On-device speech recognition via Apple Speech framework. Free, no network required."
        case .glmASROnDevice:
            return "GLM-ASR on-device decoder (pending). Falls back to Apple Speech until available."
        default:
            return ""
        }
    }

    private var ttsFooterText: String {
        switch viewModel.selectedTTSProvider {
        case .pocketTTS:
            return "On-device Pocket TTS with 8 voices, ~200ms latency, 24kHz audio."
        case .appleTTS:
            return "Built-in iOS text-to-speech. Works offline with system voices."
        default:
            return ""
        }
    }
}

#Preview {
    SettingsView(viewModel: ChatViewModel())
}
