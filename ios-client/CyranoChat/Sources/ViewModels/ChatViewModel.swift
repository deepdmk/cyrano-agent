// CyranoChat - Chat View Model
// Orchestrates text chat and voice pipeline, simplified SessionManager

import Foundation
import Combine
@preconcurrency import AVFoundation
import Logging

/// Voice session states
public enum VoiceState: Sendable, Equatable {
    case idle
    case listening
    case processing
    case generating
    case speaking
}

@MainActor
public final class ChatViewModel: ObservableObject {

    // MARK: - Published State

    @Published public var messages: [ChatMessage] = []
    @Published public var inputText: String = ""
    @Published public var isGenerating: Bool = false
    @Published public var voiceState: VoiceState = .idle
    @Published public var errorMessage: String?
    @Published public var audioLevel: Float = -160.0
    @Published public var partialTranscript: String = ""

    // MARK: - Configuration

    @Published public var selectedModel: String {
        didSet { UserDefaults.standard.set(selectedModel, forKey: "selectedModel") }
    }
    @Published public var systemPrompt: String {
        didSet { UserDefaults.standard.set(systemPrompt, forKey: "systemPrompt") }
    }

    // MARK: - Services

    private var llmService: ClaudeAPIService?
    private var sttService: AppleSpeechSTTService?
    private var ttsService: AppleTTSService?
    private var vadService: SileroVADService?
    private var audioEngine: AudioEngine?
    private let telemetry = TelemetryEngine()

    private let logger = Logger(label: "com.cyrano.chat.viewmodel")
    private var audioSubscription: AnyCancellable?
    private var sttStream: AsyncStream<STTResult>?
    private var sttTask: Task<Void, Never>?
    private var voiceTask: Task<Void, Never>?
    private var silenceTimer: Task<Void, Never>?

    /// Whether an API key is configured
    public var hasAPIKey: Bool {
        KeychainHelper.anthropicAPIKey != nil
    }

    // MARK: - Initialization

    public init() {
        self.selectedModel = UserDefaults.standard.string(forKey: "selectedModel")
            ?? "claude-sonnet-4-20250514"
        self.systemPrompt = UserDefaults.standard.string(forKey: "systemPrompt")
            ?? "You are a helpful AI assistant. Keep responses concise and conversational."

        configureServices()
    }

    // MARK: - Service Configuration

    public func configureServices() {
        guard let apiKey = KeychainHelper.anthropicAPIKey else {
            logger.warning("No API key configured")
            return
        }

        llmService = ClaudeAPIService(apiKey: apiKey)
        sttService = AppleSpeechSTTService()
        ttsService = AppleTTSService()
        vadService = SileroVADService()

        audioEngine = AudioEngine(
            config: .default,
            vadService: vadService!,
            telemetry: telemetry
        )

        logger.info("Services configured")
    }

    /// Reconfigure after API key change
    public func reconfigureWithAPIKey(_ apiKey: String) {
        KeychainHelper.anthropicAPIKey = apiKey
        llmService = ClaudeAPIService(apiKey: apiKey)
        logger.info("LLM service reconfigured with new API key")
    }

    // MARK: - Text Chat

    /// Send the current text input as a message
    public func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        guard !isGenerating else { return }

        inputText = ""
        await sendUserMessage(text)
    }

    /// Send a user message and get a response
    private func sendUserMessage(_ text: String) async {
        // Add user message first so it's always visible in the conversation
        let userMessage = ChatMessage(role: .user, content: text)
        messages.append(userMessage)

        guard let llm = llmService else {
            errorMessage = "Please set your API key in Settings."
            return
        }

        // Add placeholder assistant message
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        isGenerating = true
        errorMessage = nil

        do {
            // Build message history for API
            var llmMessages: [LLMMessage] = []

            // Add system prompt
            if !systemPrompt.isEmpty {
                llmMessages.append(LLMMessage(role: .system, content: systemPrompt))
            }

            // Add conversation history (last 20 messages to stay in context)
            let historyMessages = messages.dropLast() // Exclude the empty assistant placeholder
            let recentMessages = historyMessages.suffix(20)
            for msg in recentMessages {
                if msg.role != .system {
                    llmMessages.append(msg.toLLMMessage())
                }
            }

            let config = LLMConfig(
                model: selectedModel,
                maxTokens: 4096,
                temperature: 0.7
            )

            let stream = try await llm.streamCompletion(messages: llmMessages, config: config)

            for await token in stream {
                if !token.content.isEmpty {
                    messages[assistantIndex].content += token.content
                }
                if token.isDone {
                    messages[assistantIndex].isStreaming = false
                }
            }

            // Ensure streaming flag is cleared
            messages[assistantIndex].isStreaming = false

        } catch {
            messages[assistantIndex].content = "Error: \(error.localizedDescription)"
            messages[assistantIndex].isStreaming = false
            errorMessage = error.localizedDescription
            logger.error("LLM error: \(error.localizedDescription)")
        }

        isGenerating = false
    }

    // MARK: - Voice

    /// Toggle voice mode on/off
    public func toggleVoice() async {
        if voiceState == .idle {
            await startVoice()
        } else {
            await stopVoice()
        }
    }

    private func startVoice() async {
        guard let engine = audioEngine,
              let stt = sttService else {
            errorMessage = "Voice services not configured. Check API key."
            return
        }

        do {
            // Configure and start audio engine
            try await engine.configure(config: .default)
            try await engine.start()

            // Subscribe to audio level updates
            audioSubscription = await engine.audioStream
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _, vadResult in
                    Task { @MainActor in
                        self?.audioLevel = vadResult.confidence
                        await self?.handleVADResult(vadResult)
                    }
                }

            // Start STT
            guard let format = await engine.format else {
                throw AudioEngineError.invalidConfiguration("No audio format")
            }

            let stream = try await stt.startStreaming(audioFormat: format)
            sttStream = stream

            // Process STT results
            sttTask = Task {
                for await result in stream {
                    await handleSTTResult(result)
                }
            }

            // Forward audio to STT
            voiceTask = Task {
                let audioPublisher = await engine.audioStream
                let sub = audioPublisher.sink { [weak self] buffer, _ in
                    Task {
                        guard let stt = self?.sttService else { return }
                        try? await stt.sendAudio(buffer)
                    }
                }

                // Keep subscription alive until cancelled
                while !Task.isCancelled {
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
                sub.cancel()
            }

            voiceState = .listening
            logger.info("Voice started - listening")

        } catch {
            errorMessage = "Failed to start voice: \(error.localizedDescription)"
            logger.error("Voice start error: \(error.localizedDescription)")
            await stopVoice()
        }
    }

    /// Stop voice mode completely
    public func stopVoice() async {
        voiceTask?.cancel()
        voiceTask = nil
        sttTask?.cancel()
        sttTask = nil
        silenceTimer?.cancel()
        silenceTimer = nil
        audioSubscription?.cancel()
        audioSubscription = nil

        if let stt = sttService, await stt.isStreaming {
            try? await stt.stopStreaming()
        }

        if let engine = audioEngine {
            await engine.stopPlayback()
            await engine.stop()
        }

        if let tts = ttsService {
            try? await tts.flush()
        }

        voiceState = .idle
        partialTranscript = ""
        logger.info("Voice stopped")
    }

    // MARK: - VAD Handling

    private func handleVADResult(_ result: VADResult) async {
        guard voiceState == .speaking else { return }

        // Barge-in detection: if user speaks during AI output, stop playback
        if result.isSpeech && result.confidence >= 0.7 {
            logger.info("Barge-in detected, stopping playback")
            await audioEngine?.stopPlayback()
            if let tts = ttsService {
                try? await tts.flush()
            }
            voiceState = .listening
        }
    }

    // MARK: - STT Handling

    private func handleSTTResult(_ result: STTResult) async {
        if result.isFinal && !result.transcript.isEmpty {
            // Final transcript - send as message
            partialTranscript = ""
            voiceState = .generating

            // Stop STT while processing
            if let stt = sttService, await stt.isStreaming {
                try? await stt.stopStreaming()
            }

            await sendUserMessageWithVoice(result.transcript)
        } else if !result.transcript.isEmpty {
            // Partial transcript - show in UI
            partialTranscript = result.transcript

            // Reset silence timer
            silenceTimer?.cancel()
            silenceTimer = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
                guard !Task.isCancelled else { return }

                // If we still have the same partial after 2s of silence, treat as final
                if !partialTranscript.isEmpty {
                    let text = partialTranscript
                    partialTranscript = ""
                    voiceState = .generating

                    if let stt = sttService, await stt.isStreaming {
                        try? await stt.stopStreaming()
                    }

                    await sendUserMessageWithVoice(text)
                }
            }
        }
    }

    /// Send user message and speak the response
    private func sendUserMessageWithVoice(_ text: String) async {
        guard let llm = llmService else { return }

        // Add user message
        messages.append(ChatMessage(role: .user, content: text))

        // Add streaming assistant message
        let assistantMessage = ChatMessage(role: .assistant, content: "", isStreaming: true)
        messages.append(assistantMessage)
        let assistantIndex = messages.count - 1

        isGenerating = true

        do {
            var llmMessages: [LLMMessage] = []
            if !systemPrompt.isEmpty {
                llmMessages.append(LLMMessage(role: .system, content: systemPrompt))
            }
            for msg in messages.dropLast().suffix(20) where msg.role != .system {
                llmMessages.append(msg.toLLMMessage())
            }

            let config = LLMConfig(
                model: selectedModel,
                maxTokens: 4096,
                temperature: 0.7
            )

            let stream = try await llm.streamCompletion(messages: llmMessages, config: config)

            // Accumulate tokens into sentences for TTS
            var fullResponse = ""
            var sentenceBuffer = ""

            for await token in stream {
                if !token.content.isEmpty {
                    fullResponse += token.content
                    sentenceBuffer += token.content
                    messages[assistantIndex].content = fullResponse

                    // Check for sentence boundary
                    if let lastChar = sentenceBuffer.last,
                       ".!?".contains(lastChar),
                       sentenceBuffer.count > 10 {
                        let sentence = sentenceBuffer
                        sentenceBuffer = ""

                        // Speak sentence
                        if voiceState != .idle {
                            voiceState = .speaking
                            await speakText(sentence)
                        }
                    }
                }

                if token.isDone {
                    messages[assistantIndex].isStreaming = false

                    // Speak remaining buffer
                    if !sentenceBuffer.isEmpty && voiceState != .idle {
                        voiceState = .speaking
                        await speakText(sentenceBuffer)
                    }
                }
            }

            messages[assistantIndex].isStreaming = false

        } catch {
            messages[assistantIndex].content = "Error: \(error.localizedDescription)"
            messages[assistantIndex].isStreaming = false
            logger.error("Voice LLM error: \(error.localizedDescription)")
        }

        isGenerating = false

        // Return to listening if voice is still active
        if voiceState == .speaking {
            voiceState = .listening

            // Restart STT
            if let stt = sttService, let engine = audioEngine, let format = await engine.format {
                do {
                    let newStream = try await stt.startStreaming(audioFormat: format)
                    sttTask = Task {
                        for await result in newStream {
                            await handleSTTResult(result)
                        }
                    }
                } catch {
                    logger.error("Failed to restart STT: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Speak text through TTS and AudioEngine
    private func speakText(_ text: String) async {
        guard let tts = ttsService,
              let engine = audioEngine else { return }

        do {
            let chunks = try await tts.synthesize(text: text)
            for await chunk in chunks {
                guard voiceState == .speaking else { break }
                try await engine.playAudio(chunk)
            }
        } catch {
            logger.error("TTS playback error: \(error.localizedDescription)")
        }
    }

    // MARK: - Conversation Management

    public func clearConversation() {
        messages.removeAll()
        partialTranscript = ""
        errorMessage = nil
    }
}
