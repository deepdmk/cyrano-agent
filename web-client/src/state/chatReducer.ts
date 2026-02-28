import type { ChatMessage } from '../models/ChatMessage';
import type { VoiceState } from '../models/VoiceState';

export interface ChatState {
  messages: ChatMessage[];
  inputText: string;
  isGenerating: boolean;
  voiceState: VoiceState;
  errorMessage: string | null;
  audioLevel: number;
  partialTranscript: string;
  selectedModel: string;
  systemPrompt: string;
  hasAPIKey: boolean;
  showSettings: boolean;
}

export type ChatAction =
  | { type: 'SET_INPUT_TEXT'; text: string }
  | { type: 'ADD_MESSAGE'; message: ChatMessage }
  | { type: 'UPDATE_MESSAGE'; id: string; content: string }
  | { type: 'FINISH_STREAMING'; id: string }
  | { type: 'SET_GENERATING'; value: boolean }
  | { type: 'SET_VOICE_STATE'; state: VoiceState }
  | { type: 'SET_ERROR'; message: string | null }
  | { type: 'SET_AUDIO_LEVEL'; level: number }
  | { type: 'SET_PARTIAL_TRANSCRIPT'; text: string }
  | { type: 'SET_MODEL'; model: string }
  | { type: 'SET_SYSTEM_PROMPT'; prompt: string }
  | { type: 'SET_HAS_API_KEY'; value: boolean }
  | { type: 'SET_SHOW_SETTINGS'; value: boolean }
  | { type: 'CLEAR_CONVERSATION' };

export function chatReducer(state: ChatState, action: ChatAction): ChatState {
  switch (action.type) {
    case 'SET_INPUT_TEXT':
      return { ...state, inputText: action.text };

    case 'ADD_MESSAGE':
      return { ...state, messages: [...state.messages, action.message] };

    case 'UPDATE_MESSAGE':
      return {
        ...state,
        messages: state.messages.map((msg) =>
          msg.id === action.id ? { ...msg, content: action.content } : msg,
        ),
      };

    case 'FINISH_STREAMING':
      return {
        ...state,
        messages: state.messages.map((msg) =>
          msg.id === action.id ? { ...msg, isStreaming: false } : msg,
        ),
      };

    case 'SET_GENERATING':
      return { ...state, isGenerating: action.value };

    case 'SET_VOICE_STATE':
      return { ...state, voiceState: action.state };

    case 'SET_ERROR':
      return { ...state, errorMessage: action.message };

    case 'SET_AUDIO_LEVEL':
      return { ...state, audioLevel: action.level };

    case 'SET_PARTIAL_TRANSCRIPT':
      return { ...state, partialTranscript: action.text };

    case 'SET_MODEL':
      return { ...state, selectedModel: action.model };

    case 'SET_SYSTEM_PROMPT':
      return { ...state, systemPrompt: action.prompt };

    case 'SET_HAS_API_KEY':
      return { ...state, hasAPIKey: action.value };

    case 'SET_SHOW_SETTINGS':
      return { ...state, showSettings: action.value };

    case 'CLEAR_CONVERSATION':
      return {
        ...state,
        messages: [],
        partialTranscript: '',
        errorMessage: null,
      };

    default:
      return state;
  }
}
