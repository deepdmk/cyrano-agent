import { useCallback, useRef } from 'react';
import { useChatState, useChatDispatch } from './ChatContext';
import { ClaudeAPIService } from '../services/llm/ClaudeAPIService';
import { StorageService } from '../services/storage/StorageService';
import { createMessage } from '../models/ChatMessage';
import type { LLMMessage } from '../models/LLMTypes';

export function useChatActions() {
  const state = useChatState();
  const dispatch = useChatDispatch();
  const llmServiceRef = useRef<ClaudeAPIService | null>(null);

  // Ensure LLM service is initialized
  const getLLMService = useCallback((): ClaudeAPIService | null => {
    const apiKey = StorageService.getAPIKey();
    if (!apiKey) return null;

    if (!llmServiceRef.current) {
      llmServiceRef.current = new ClaudeAPIService(apiKey);
    }
    return llmServiceRef.current;
  }, []);

  const sendMessage = useCallback(async () => {
    const text = state.inputText.trim();
    if (!text || state.isGenerating) return;

    const llm = getLLMService();
    if (!llm) {
      dispatch({ type: 'SET_ERROR', message: 'Please set your API key in Settings.' });
      return;
    }

    // Clear input immediately
    dispatch({ type: 'SET_INPUT_TEXT', text: '' });

    // Add user message
    const userMsg = createMessage('user', text);
    dispatch({ type: 'ADD_MESSAGE', message: userMsg });

    // Add streaming assistant placeholder
    const assistantMsg = createMessage('assistant', '', true);
    dispatch({ type: 'ADD_MESSAGE', message: assistantMsg });

    dispatch({ type: 'SET_GENERATING', value: true });
    dispatch({ type: 'SET_ERROR', message: null });

    try {
      // Build LLM messages: last 20 non-system messages (excluding the empty placeholder)
      const allMessages = [...state.messages, userMsg];
      const recentMessages = allMessages.slice(-20);
      const llmMessages: LLMMessage[] = recentMessages
        .filter((m) => m.role !== 'system')
        .map((m) => ({ role: m.role, content: m.content }));

      let fullContent = '';

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
          dispatch({ type: 'UPDATE_MESSAGE', id: assistantMsg.id, content: fullContent });
        }
        if (token.isDone) {
          dispatch({ type: 'FINISH_STREAMING', id: assistantMsg.id });
        }
      }

      // Ensure streaming is finished
      dispatch({ type: 'FINISH_STREAMING', id: assistantMsg.id });
    } catch (error) {
      const message = error instanceof Error ? error.message : 'An error occurred';
      dispatch({ type: 'UPDATE_MESSAGE', id: assistantMsg.id, content: `Error: ${message}` });
      dispatch({ type: 'FINISH_STREAMING', id: assistantMsg.id });
      dispatch({ type: 'SET_ERROR', message });
    }

    dispatch({ type: 'SET_GENERATING', value: false });
  }, [state.inputText, state.isGenerating, state.messages, state.selectedModel, state.systemPrompt, dispatch, getLLMService]);

  const clearConversation = useCallback(() => {
    dispatch({ type: 'CLEAR_CONVERSATION' });
  }, [dispatch]);

  const saveAPIKey = useCallback((key: string) => {
    StorageService.setAPIKey(key);
    llmServiceRef.current = new ClaudeAPIService(key);
    dispatch({ type: 'SET_HAS_API_KEY', value: true });
  }, [dispatch]);

  const removeAPIKey = useCallback(() => {
    StorageService.removeAPIKey();
    llmServiceRef.current = null;
    dispatch({ type: 'SET_HAS_API_KEY', value: false });
  }, [dispatch]);

  const setModel = useCallback((model: string) => {
    StorageService.setModel(model);
    dispatch({ type: 'SET_MODEL', model });
  }, [dispatch]);

  const setSystemPrompt = useCallback((prompt: string) => {
    StorageService.setSystemPrompt(prompt);
    dispatch({ type: 'SET_SYSTEM_PROMPT', prompt });
  }, [dispatch]);

  return {
    sendMessage,
    clearConversation,
    saveAPIKey,
    removeAPIKey,
    setModel,
    setSystemPrompt,
  };
}
