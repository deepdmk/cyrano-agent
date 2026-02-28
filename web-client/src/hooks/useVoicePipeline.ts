/**
 * useVoicePipeline — Browser-native voice pipeline using Web Speech API.
 *   idle → listening → generating → speaking → listening (loop)
 * STT via SpeechRecognition, TTS via SpeechSynthesis.
 * Text flows through the agno server (CyranoServerService) or direct API.
 */
import { useCallback, useRef } from 'react';
import { useChatState, useChatDispatch } from '../state/ChatContext';
import { BrowserVoiceService } from '../services/voice/BrowserVoiceService';
import { ClaudeAPIService } from '../services/llm/ClaudeAPIService';
import { CyranoServerService } from '../services/llm/CyranoServerService';
import { StorageService } from '../services/storage/StorageService';
import { createMessage } from '../models/ChatMessage';
import type { LLMService } from '../services/interfaces/LLMService';
import type { LLMMessage } from '../models/LLMTypes';
import type { STTResult } from '../models/VoiceTypes';

const SILENCE_TIMEOUT_MS = 2000;
const SENTENCE_BOUNDARY = /[.!?]$/;
const MIN_SENTENCE_LENGTH = 10;

export function useVoicePipeline() {
  const state = useChatState();
  const dispatch = useChatDispatch();

  const voiceRef = useRef<BrowserVoiceService | null>(null);
  const silenceTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const llmServiceRef = useRef<LLMService | null>(null);

  // Refs for state accessed inside callbacks
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

  const getLLMService = useCallback((): LLMService | null => {
    const serverUrl = StorageService.getCyranoServerUrl();
    if (serverUrl) {
      if (!llmServiceRef.current || !(llmServiceRef.current instanceof CyranoServerService)) {
        llmServiceRef.current = new CyranoServerService(serverUrl);
      }
      return llmServiceRef.current;
    }

    const apiKey = StorageService.getAPIKey();
    if (!apiKey) return null;

    if (!llmServiceRef.current || !(llmServiceRef.current instanceof ClaudeAPIService)) {
      llmServiceRef.current = new ClaudeAPIService(apiKey);
    }
    return llmServiceRef.current;
  }, []);

  const sendUserMessageWithVoice = useCallback(async (text: string) => {
    const llm = getLLMService();
    if (!llm) {
      dispatch({ type: 'SET_ERROR', message: 'Please set a Cyrano Server URL or API key in Settings.' });
      return;
    }

    // Pause STT while generating/speaking to avoid echo
    voiceRef.current?.stopListening();

    // Add user message
    const userMsg = createMessage('user', text);
    dispatch({ type: 'ADD_MESSAGE', message: userMsg });

    // Add streaming assistant placeholder
    const assistantMsg = createMessage('assistant', '', true);
    dispatch({ type: 'ADD_MESSAGE', message: assistantMsg });
    dispatch({ type: 'SET_GENERATING', value: true });

    try {
      const allMessages = [...messagesRef.current, userMsg];
      const recentMessages = allMessages.slice(-20);
      const llmMessages: LLMMessage[] = recentMessages
        .filter((m) => m.role !== 'system')
        .map((m) => ({ role: m.role, content: m.content }));

      let fullContent = '';
      let sentenceBuffer = '';

      const stream = llm.streamCompletion(llmMessages, {
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

          // Speak complete sentences via browser TTS
          if (
            SENTENCE_BOUNDARY.test(sentenceBuffer) &&
            sentenceBuffer.length > MIN_SENTENCE_LENGTH
          ) {
            const sentence = sentenceBuffer;
            sentenceBuffer = '';

            if (voiceStateRef.current !== 'idle') {
              dispatch({ type: 'SET_VOICE_STATE', state: 'speaking' });
              voiceRef.current?.speak(sentence);
            }
          }
        }

        if (token.isDone) {
          dispatch({ type: 'FINISH_STREAMING', id: assistantMsg.id });

          // Flush remaining buffer to TTS
          if (sentenceBuffer.trim() && voiceStateRef.current !== 'idle') {
            dispatch({ type: 'SET_VOICE_STATE', state: 'speaking' });
            voiceRef.current?.speak(sentenceBuffer);
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

    // If no TTS was queued (e.g. empty response), resume listening directly
    if (voiceStateRef.current !== 'idle' && voiceStateRef.current !== 'speaking') {
      dispatch({ type: 'SET_VOICE_STATE', state: 'listening' });
      voiceRef.current?.resumeListening();
    }
  }, [state.selectedModel, state.systemPrompt, dispatch, getLLMService]);

  const handleTranscript = useCallback((result: STTResult) => {
    // Barge-in: if speech detected during speaking, cancel TTS
    if (voiceStateRef.current === 'speaking' && result.transcript.trim()) {
      voiceRef.current?.cancelSpeech();
      dispatch({ type: 'SET_VOICE_STATE', state: 'listening' });
    }

    if (result.isFinal && result.transcript.trim()) {
      clearSilenceTimer();
      dispatch({ type: 'SET_PARTIAL_TRANSCRIPT', text: '' });
      dispatch({ type: 'SET_VOICE_STATE', state: 'generating' });
      sendUserMessageWithVoice(result.transcript);
    } else if (result.transcript.trim()) {
      dispatch({ type: 'SET_PARTIAL_TRANSCRIPT', text: result.transcript });

      clearSilenceTimer();
      silenceTimerRef.current = setTimeout(() => {
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
      const voice = new BrowserVoiceService();
      voiceRef.current = voice;

      voice.onTranscript = handleTranscript;

      voice.onSpeechEnd = () => {
        if (voiceStateRef.current === 'speaking') {
          dispatch({ type: 'SET_VOICE_STATE', state: 'listening' });
          voice.resumeListening();
        }
      };

      voice.onError = (error) => {
        dispatch({ type: 'SET_ERROR', message: error.message });
      };

      voice.startListening();
      dispatch({ type: 'SET_VOICE_STATE', state: 'listening' });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'Failed to start voice';
      dispatch({ type: 'SET_ERROR', message });
      await stopVoice();
    }
  }, [handleTranscript, dispatch]);

  const stopVoice = useCallback(async () => {
    clearSilenceTimer();
    voiceRef.current?.destroy();
    voiceRef.current = null;

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
