import { useState } from 'react';
import { CheckmarkCircleIcon } from '../Icons/Icons';
import styles from './SettingsModal.module.css';

interface Props {
  serverUrl: string | null;
  onSave: (url: string) => void;
  onRemove: () => void;
}

export function ServerSection({ serverUrl, onSave, onRemove }: Props) {
  const [input, setInput] = useState(serverUrl ?? '');
  const [saved, setSaved] = useState(!!serverUrl);

  const handleSave = () => {
    const url = input.trim();
    if (!url) return;
    onSave(url);
    setSaved(true);
  };

  const handleRemove = () => {
    onRemove();
    setInput('');
    setSaved(false);
  };

  const canSave = input.trim().length > 0 && input.trim() !== serverUrl;

  return (
    <section className={styles.section}>
      <h3 className={styles.sectionHeader}>Cyrano Server</h3>

      <div className={styles.inputRow}>
        <input
          type="text"
          className={styles.textInput}
          value={input}
          onChange={(e) => { setInput(e.target.value); setSaved(false); }}
          placeholder="http://localhost:8080"
          autoComplete="off"
          autoCorrect="off"
          spellCheck={false}
        />
      </div>

      <button
        className={styles.saveButton}
        onClick={handleSave}
        disabled={!canSave}
      >
        <span>Connect</span>
        {saved && <CheckmarkCircleIcon size={18} style={{ color: 'var(--color-green)' }} />}
      </button>

      {serverUrl && (
        <button className={styles.destructiveButton} onClick={handleRemove}>
          Disconnect
        </button>
      )}

      <p className={styles.sectionFooter}>
        When connected to a Cyrano server, the API key is not needed.
        The server handles its own AI model configuration.
      </p>
    </section>
  );
}
