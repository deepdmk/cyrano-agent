import { useEffect } from 'react';
import type { VoiceState } from '../../models/VoiceState';
import { useTextareaAutoResize } from '../../hooks/useTextareaAutoResize';
import { MicIcon, WaveformIcon, EllipsisCircleIcon, SpeakerIcon, SendIcon } from '../Icons/Icons';
import styles from './ChatInputBar.module.css';

interface Props {
  text: string;
  onTextChange: (text: string) => void;
  isGenerating: boolean;
  voiceState: VoiceState;
  onSend: () => void;
  onVoiceToggle: () => void;
}

function getVoiceIcon(voiceState: VoiceState) {
  switch (voiceState) {
    case 'idle': return <MicIcon size={20} />;
    case 'listening': return <WaveformIcon size={20} />;
    case 'processing':
    case 'generating': return <EllipsisCircleIcon size={20} />;
    case 'speaking': return <SpeakerIcon size={20} />;
  }
}

export function ChatInputBar({ text, onTextChange, isGenerating, voiceState, onSend, onVoiceToggle }: Props) {
  const { textareaRef, adjustHeight } = useTextareaAutoResize();
  const isVoiceActive = voiceState !== 'idle';
  const canSend = text.trim().length > 0 && !isGenerating && !isVoiceActive;

  useEffect(() => {
    adjustHeight();
  }, [text, adjustHeight]);

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault();
      if (canSend) onSend();
    }
  };

  return (
    <div className={styles.wrapper}>
      <div className={styles.divider} />
      <div className={styles.container}>
        <button
          className={`${styles.micButton} ${isVoiceActive ? styles.micActive : ''}`}
          onClick={onVoiceToggle}
          disabled={isGenerating && !isVoiceActive}
          aria-label={isVoiceActive ? 'Stop voice' : 'Start voice'}
        >
          {getVoiceIcon(voiceState)}
        </button>

        <div className={styles.inputWrapper}>
          <textarea
            ref={textareaRef}
            className={styles.input}
            value={text}
            onChange={(e) => onTextChange(e.target.value)}
            onKeyDown={handleKeyDown}
            placeholder="Message"
            rows={1}
            disabled={isVoiceActive}
          />
        </div>

        <button
          className={`${styles.sendButton} ${canSend ? styles.sendEnabled : styles.sendDisabled}`}
          onClick={onSend}
          disabled={!canSend}
          aria-label="Send message"
        >
          <SendIcon size={32} />
        </button>
      </div>
    </div>
  );
}
