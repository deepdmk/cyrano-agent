import { PlusMessageIcon, GearIcon } from '../Icons/Icons';
import styles from './NavBar.module.css';

interface Props {
  messagesEmpty: boolean;
  onNewConversation: () => void;
  onOpenSettings: () => void;
}

export function NavBar({ messagesEmpty, onNewConversation, onOpenSettings }: Props) {
  return (
    <div className={styles.container}>
      <button
        className={styles.button}
        onClick={onNewConversation}
        disabled={messagesEmpty}
        aria-label="New conversation"
      >
        <PlusMessageIcon size={22} />
      </button>
      <h1 className={styles.title}>Cyrano</h1>
      <button
        className={styles.button}
        onClick={onOpenSettings}
        aria-label="Settings"
      >
        <GearIcon size={22} />
      </button>
    </div>
  );
}
