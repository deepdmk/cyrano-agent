import styles from './SettingsModal.module.css';

interface Props {
  prompt: string;
  onChange: (prompt: string) => void;
}

export function SystemPromptSection({ prompt, onChange }: Props) {
  return (
    <section className={styles.section}>
      <h3 className={styles.sectionHeader}>System Prompt</h3>
      <textarea
        className={styles.promptEditor}
        value={prompt}
        onChange={(e) => onChange(e.target.value)}
      />
    </section>
  );
}
