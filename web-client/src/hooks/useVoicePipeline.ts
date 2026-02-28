/**
 * useVoicePipeline — Orchestrates the WebSocket-based voice pipeline.
 * Mirrors ChatViewModel voice methods:
 *   idle → listening → generating → speaking → listening (loop)
 * With barge-in detection and silence timer.
 */
import { useCallback, useRef } from 'react';
import { useChatState, useChatDispatch } from '../state/ChatContext';
import { ClaudeAPIService } from '../services/llm/ClaudeAPIService';
import { WebSocketVoiceService } from '../services/voice/WebSocketVoiceService';
import { AudioCapture } from '../services/voice/AudioCapture';
import { AudioPlayback } from '../services/voice/AudioPlayback';
import { ClientVAD } from '../services/voice/ClientVAD';
import { StorageService } from '../services/storage/StorageService';
import { createMessage } from '../models/ChatMessage';
import type { LLMMessage } from '../models/LLMTypes';
import type { STTResult } from '../models/VoiceTypes';

const SILENCE_TIMEOUT_MS = 2000;
const BARGE_IN_THRESHOLD = 0.7;
const SENTENCE_BOUNDARY = /[.!?]$/;
const MIN_SENTENCE_LENGTH = 10;

export function useVoicePipeline() {
  const state = useChatState();
  const dispatch = useChatDispatch();

  const voiceServiceRef = useRef<WebSocketVoiceService | null>(null);
  const audioCaptureRef = useRef<AudioCapture | null>(null);
  const audioPlaybackRef = useRef<AudioPlayback | null>(null);
  const vadRef = useRef<ClientVAD | null>(null);
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const llmServiceRef = useRef<ClaudeAPIService | null>(null);

  // Use refs for state that needs to be accessed in callbacks
  const voiceStateRef = useRef(state.voiceState);
  voiceStateRef.current = state.voiceState;
  const messagesRef = useRef(state.messages);
  messagesRef.current = state.messages;

  const clearSilenceTimer = useCallback(() => {
    if (silenceTimerRef.current) {
      clearTimeout(silenceTimerRef.current);
      silenceTimerRef.current = null;
    }
  }, []);

  const sendUserMessageWithVoice = useCallback(async (text: string) => {
    const apiKey = StorageService.getAPIKey();
    if (!apiKey) return;

    if (!llmServiceRef.current) {
      llmServiceRef.current = new ClaudeAPIService(apiKey);
    }

    // Add user message
    const userMsg = createMessage('user', text);
    dispatch({ type: 'ADD_MESSAGE', message: userMsg });

    // Add streaming assistant placeholder
    const assistantMsg = createMessage('assistant', '', true);
    dispatch({ type: 'ADD_MESSAGE', message: assistantMsg });
    dispatch({ type: 'SET_GENERATING', value: true });

    try {
      // Build LLM messages
      const allMessages = [...messagesRef.current, userMsg];
      const recentMessages = allMessages.slice(-20);
      const llmMessages: LLMMessage[] = recentMessages
        .filter((m) => m.role !== 'system')
        .map((m) => ({ role: m.role, content: m.content }));

      let fullContent = '';
      let sentenceBuffer = '';

      const stream = llmServiceRef.current.streamCompletion(llmMessages, {
        model: state.selectedModel,
        maxTokens: 4096,
        temperature: 0.7,
        systemPrompt: state.systemPrompt,
        stream: true,
      });

      for await (const token of stream) {
        if (token.content) {
          fullContent += token.content;
          sentenceBuffer += token.content;
          dispatch({ type: 'UPDATE_MESSAGE', id: assistantMsg.id, content: fullContent });

          // Check for sentence boundary — send to server for TTS
          if (
            SENTENCE_BOUNDARY.test(sentenceBuffer) &&
            sentenceBuffer.length > MIN_SENTENCE_LENGTH
          ) {
            const sentence = sentenceBuffer;
            sentenceBuffer = '';

            if (voiceStateRef.current !== 'idle') {
              dispatch({ type: 'SET_VOICE_STATE', state: 'speaking' });
              voiceServiceRef.current?.sendControl({ type: 'tts_request', text: sentence });
            }
          }
        }

        if (token.isDone) {
          dispatch({ type: 'FINISH_STREAMING', id: assistantMsg.id });

          // Flush remaining buffer to TTS
          if (sentenceBuffer.trim() && voiceStateRef.current !== 'idle') {
            dispatch({ type: 'SET_VOICE_STATE', state: 'speaking' });
            voiceServiceRef.current?.sendControl({ type: 'tts_request', text: sentenceBuffer });
          }
        }
      }

      dispatch({ type: 'FINISH_STREAMING', id: assistantMsg.id });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'An error occurred';
      dispatch({ type: 'UPDATE_MESSAGE', id: assistantMsg.id, content: `Error: ${message}` });
      dispatch({ type: 'FINISH_STREAMING', id: assistantMsg.id });
    }

    dispatch({ type: 'SET_GENERATING', value: false });

    // Return to listening if voice is still active
    if (voiceStateRef.current !== 'idle') {
      dispatch({ type: 'SET_VOICE_STATE', state: 'listening' });
    }
  }, [state.selectedModel, state.systemPrompt, dispatch]);

  const handleTranscript = useCallback((result: STTResult) => {
    if (result.isFinal && result.transcript.trim()) {
      // Final transcript — send to LLM
      clearSilenceTimer();
      dispatch({ type: 'SET_PARTIAL_TRANSCRIPT', text: '' });
      dispatch({ type: 'SET_VOICE_STATE', state: 'generating' });
      sendUserMessageWithVoice(result.transcript);
    } else if (result.transcript.trim()) {
      // Partial transcript — show in UI and start silence timer
      dispatch({ type: 'SET_PARTIAL_TRANSCRIPT', text: result.transcript });

      clearSilenceTimer();
      silenceTimerRef.current = setTimeout(() => {
        // Treat partial as final after 2s silence
        const transcript = result.transcript.trim();
        if (transcript && voiceStateRef.current === 'listening') {
          dispatch({ type: 'SET_PARTIAL_TRANSCRIPT', text: '' });
          dispatch({ type: 'SET_VOICE_STATE', state: 'generating' });
          sendUserMessageWithVoice(transcript);
        }
      }, SILENCE_TIMEOUT_MS);
    }
  }, [dispatch, clearSilenceTimer, sendUserMessageWithVoice]);

  const startVoice = useCallback(async () => {
    try {
      // Initialize services
      const voiceService = new WebSocketVoiceService();
      const audioCapture = new AudioCapture();
      const audioPlayback = new AudioPlayback();
      const vad = new ClientVAD();

      voiceServiceRef.current = voiceService;
      audioCaptureRef.current = audioCapture;
      audioPlaybackRef.current = audioPlayback;
      vadRef.current = vad;

      // Connect to voice server
      const voiceServerUrl = StorageService.getVoiceServerUrl();
      await voiceService.connect(voiceServerUrl);

      // Set up transcript handler
      voiceService.onTranscript = handleTranscript;

      // Set up TTS audio playback
      voiceService.onTTSAudio = (audioData) => {
        audioPlayback.play(audioData);
      };

      audioPlayback.onPlaybackComplete = () => {
        if (voiceStateRef.current === 'speaking') {
          dispatch({ type: 'SET_VOICE_STATE', state: 'listening' });
        }
      };

      voiceService.onError = (error) => {
        dispatch({ type: 'SET_ERROR', message: `Voice error: ${error.message}` });
      };

      // Start audio capture
      await audioCapture.start();

      // Pipe audio to WebSocket and VAD
      audioCapture.onAudioData = (pcmData) => {
        voiceService.sendAudio(pcmData);
      };
      audioCapture.onRawFloat = (data) => {
        vad.processBuffer(data);
      };

      // Start VAD for barge-in and levels
      vad.onResult = (result) => {
        // Barge-in: if speech detected during speaking, stop playback
        if (
          voiceStateRef.current === 'speaking' &&
          result.isSpeech &&
          result.confidence >= BARGE_IN_THRESHOLD
        ) {
          audioPlayback.flush();
          voiceService.sendControl({ type: 'stop_tts' });
          dispatch({ type: 'SET_VOICE_STATE', state: 'listening' });
        }
      };
      vad.onAudioLevel = (level) => {
        dispatch({ type: 'SET_AUDIO_LEVEL', level });
      };
      vad.start();

      // Send session start
      voiceService.sendControl({
        type: 'start_session',
        sampleRate: 48000,
        channels: 1,
        encoding: 'pcm_s16le',
      });

      dispatch({ type: 'SET_VOICE_STATE', state: 'listening' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to start voice';
      dispatch({ type: 'SET_ERROR', message });
      await stopVoice();
    }
  }, [handleTranscript, dispatch]);

  const stopVoice = useCallback(async () => {
    clearSilenceTimer();

    voiceServiceRef.current?.sendControl({ type: 'end_session' });
    voiceServiceRef.current?.disconnect();
    voiceServiceRef.current = null;

    audioCaptureRef.current?.stop();
    audioCaptureRef.current = null;

    audioPlaybackRef.current?.flush();
    audioPlaybackRef.current?.destroy();
    audioPlaybackRef.current = null;

    vadRef.current?.stop();
    vadRef.current = null;

    dispatch({ type: 'SET_VOICE_STATE', state: 'idle' });
    dispatch({ type: 'SET_PARTIAL_TRANSCRIPT', text: '' });
    dispatch({ type: 'SET_AUDIO_LEVEL', level: 0 });
  }, [dispatch, clearSilenceTimer]);

  const toggleVoice = useCallback(async () => {
    if (voiceStateRef.current === 'idle') {
      await startVoice();
    } else {
      await stopVoice();
    }
  }, [startVoice, stopVoice]);

  return { toggleVoice };
}
