import styles from './SettingsModal.module.css';

interface Props {
  hasKey: boolean;
  onRemoveKey: () => void;
}

export function AboutSection({ hasKey, onRemoveKey }: Props) {
  return (
    <section className={styles.section}>
      <h3 className={styles.sectionHeader}>About</h3>

      <div className={styles.infoRow}>
        <span>Version</span>
        <span className={styles.infoValue}>1.0.0</span>
      </div>

      {hasKey && (
        <button
          className={styles.destructiveButton}
          onClick={onRemoveKey}
        >
          Remove API Key
        </button>
      )}
    </section>
  );
}
