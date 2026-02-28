import { useChatState, useChatDispatch } from '../../state/ChatContext';
import { useChatActions } from '../../state/useChatActions';
import { useVoicePipeline } from '../../hooks/useVoicePipeline';
import { NavBar } from '../NavBar/NavBar';
import { MessageList } from '../MessageList/MessageList';
import { VoiceIndicator } from '../VoiceIndicator/VoiceIndicator';
import { ChatInputBar } from '../ChatInputBar/ChatInputBar';
import { SettingsModal } from '../SettingsModal/SettingsModal';
import { ErrorAlert } from '../ErrorAlert/ErrorAlert';
import styles from './ChatScreen.module.css';

export function ChatScreen() {
  const state = useChatState();
  const dispatch = useChatDispatch();
  const { sendMessage, clearConversation } = useChatActions();
  const { toggleVoice } = useVoicePipeline();

  return (
    <div className={styles.container}>
      <NavBar
        messagesEmpty={state.messages.length === 0}
        onNewConversation={clearConversation}
        onOpenSettings={() => dispatch({ type: 'SET_SHOW_SETTINGS', value: true })}
      />

      <MessageList messages={state.messages} />

      <div className={styles.bottomBar}>
        <VoiceIndicator
          state={state.voiceState}
          audioLevel={state.audioLevel}
          transcript={state.partialTranscript}
        />
        <ChatInputBar
          text={state.inputText}
          onTextChange={(text) => dispatch({ type: 'SET_INPUT_TEXT', text })}
          isGenerating={state.isGenerating}
          voiceState={state.voiceState}
          onSend={sendMessage}
          onVoiceToggle={toggleVoice}
        />
      </div>

      {state.showSettings && <SettingsModal />}

      <ErrorAlert
        message={state.errorMessage}
        onDismiss={() => dispatch({ type: 'SET_ERROR', message: null })}
      />
    </div>
  );
}
