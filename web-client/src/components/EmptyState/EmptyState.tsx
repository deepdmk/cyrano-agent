import { ChatBubblesIcon } from '../Icons/Icons';
import styles from './EmptyState.module.css';

export function EmptyState() {
  return (
    <div className={styles.container}>
      <div className={styles.spacer} />
      <ChatBubblesIcon size={56} className={styles.icon} />
      <h2 className={styles.title}>Start a conversation</h2>
      <p className={styles.subtitle}>Type a message or tap the microphone</p>
      <div className={styles.spacer} />
    </div>
  );
}
