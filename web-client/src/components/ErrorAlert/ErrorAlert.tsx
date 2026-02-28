import styles from './ErrorAlert.module.css';

interface Props {
  message: string | null;
  onDismiss: () => void;
}

export function ErrorAlert({ message, onDismiss }: Props) {
  if (!message) return null;

  return (
    <div className={styles.overlay} onClick={onDismiss}>
      <div className={styles.dialog} onClick={(e) => e.stopPropagation()}>
        <h2 className={styles.title}>Error</h2>
        <p className={styles.message}>{message}</p>
        <button className={styles.button} onClick={onDismiss}>
          OK
        </button>
      </div>
    </div>
  );
}
