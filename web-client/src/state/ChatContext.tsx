import {
  createContext,
  useContext,
  useReducer,
  useEffect,
  type ReactNode,
  type Dispatch,
} from 'react';
import { chatReducer, type ChatState, type ChatAction } from './chatReducer';
import { StorageService } from '../services/storage/StorageService';

const initialState: ChatState = {
  messages: [],
  inputText: '',
  isGenerating: false,
  voiceState: 'idle',
  errorMessage: null,
  audioLevel: 0,
  partialTranscript: '',
  selectedModel: '',
  systemPrompt: '',
  hasAPIKey: false,
  showSettings: false,
};

const ChatStateContext = createContext<ChatState>(initialState);
const ChatDispatchContext = createContext<Dispatch<ChatAction>>(() => {});

export function ChatProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(chatReducer, initialState);

  // Load persisted settings on mount
  useEffect(() => {
    const hasKey = StorageService.hasAPIKey();
    dispatch({ type: 'SET_HAS_API_KEY', value: hasKey });
    dispatch({ type: 'SET_MODEL', model: StorageService.getModel() });
    dispatch({ type: 'SET_SYSTEM_PROMPT', prompt: StorageService.getSystemPrompt() });

    if (!hasKey) {
      dispatch({ type: 'SET_SHOW_SETTINGS', value: true });
    }
  }, []);

  return (
    <ChatStateContext.Provider value={state}>
      <ChatDispatchContext.Provider value={dispatch}>
        {children}
      </ChatDispatchContext.Provider>
    </ChatStateContext.Provider>
  );
}

export function useChatState() {
  return useContext(ChatStateContext);
}

export function useChatDispatch() {
  return useContext(ChatDispatchContext);
}
