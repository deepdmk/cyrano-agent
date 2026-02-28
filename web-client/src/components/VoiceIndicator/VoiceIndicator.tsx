import type { VoiceState } from '../../models/VoiceState';
import { AudioLevelBars } from './AudioLevelBars';
import styles from './VoiceIndicator.module.css';

interface Props {
  state: VoiceState;
  audioLevel: number;
  transcript: string;
}

function getStatusText(state: VoiceState): string {
  switch (state) {
    case 'listening': return 'Listening...';
    case 'processing': return 'Processing...';
    case 'generating': return 'Thinking...';
    case 'speaking': return 'Speaking...';
    default: return '';
  }
}

function getDotClass(state: VoiceState): string {
  switch (state) {
    case 'listening': return styles.dotListening;
    case 'processing':
    case 'generating': return styles.dotProcessing;
    case 'speaking': return styles.dotSpeaking;
    default: return styles.dotIdle;
  }
}

export function VoiceIndicator({ state, audioLevel, transcript }: Props) {
  if (state === 'idle') return null;

  return (
    <div className={styles.container}>
      <div className={styles.statusRow}>
        <div className={`${styles.dot} ${getDotClass(state)}`} />
        <span className={styles.statusText}>{getStatusText(state)}</span>
      </div>

      {transcript && (
        <p className={styles.transcript}>{transcript}</p>
      )}

      <AudioLevelBars level={audioLevel} visible={state === 'listening'} />
    </div>
  );
}
