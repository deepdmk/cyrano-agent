import type { ChatMessage } from '../../models/ChatMessage';
import { StreamingDots } from './StreamingDots';
import styles from './MessageBubble.module.css';

interface Props {
  message: ChatMessage;
}

function formatTime(date: Date): string {
  return date.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' });
}

export function MessageBubble({ message }: Props) {
  const isUser = message.role === 'user';
  const showDots = message.isStreaming && message.content === '';

  return (
    <div className={`${styles.row} ${isUser ? styles.userRow : styles.assistantRow}`}>
      <div className={`${styles.bubble} ${isUser ? styles.userBubble : styles.assistantBubble}`}>
        {showDots ? (
          <StreamingDots />
        ) : (
          <span className={styles.text}>{message.content}</span>
        )}
      </div>
      <span className={`${styles.timestamp} ${isUser ? styles.timestampRight : styles.timestampLeft}`}>
        {formatTime(message.timestamp)}
      </span>
    </div>
  );
}
