import { useState, useEffect } from 'react';
import { EyeIcon, EyeSlashIcon, CheckmarkCircleIcon } from '../Icons/Icons';
import styles from './SettingsModal.module.css';

interface Props {
  hasKey: boolean;
  onSave: (key: string) => void;
  onRemove: () => void;
}

const MASK = '*'.repeat(20);

export function ApiKeySection({ hasKey, onSave, onRemove }: Props) {
  const [input, setInput] = useState('');
  const [showKey, setShowKey] = useState(false);
  const [saved, setSaved] = useState(hasKey);

  useEffect(() => {
    if (hasKey) {
      setInput(MASK);
      setSaved(true);
    }
  }, [hasKey]);

  const handleSave = () => {
    const key = input.trim();
    if (!key || key === MASK) return;
    onSave(key);
    setInput(MASK);
    setShowKey(false);
    setSaved(true);
  };

  const canSave = input.trim().length > 0 && input !== MASK;

  return (
    <section className={styles.section}>
      <h3 className={styles.sectionHeader}>Anthropic API Key</h3>

      <div className={styles.inputRow}>
        <input
          type={showKey ? 'text' : 'password'}
          className={`${styles.textInput} ${showKey ? styles.monoInput : ''}`}
          value={input}
          onChange={(e) => { setInput(e.target.value); setSaved(false); }}
          placeholder="sk-ant-..."
          autoComplete="off"
          autoCorrect="off"
          autoCapitalize="off"
          spellCheck={false}
        />
        <button
          className={styles.iconButton}
          onClick={() => setShowKey(!showKey)}
          aria-label={showKey ? 'Hide API key' : 'Show API key'}
        >
          {showKey ? <EyeSlashIcon size={18} /> : <EyeIcon size={18} />}
        </button>
      </div>

      <button
        className={styles.saveButton}
        onClick={handleSave}
        disabled={!canSave}
      >
        <span>Save API Key</span>
        {saved && <CheckmarkCircleIcon size={18} style={{ color: 'var(--color-green)' }} />}
      </button>

      <p className={styles.sectionFooter}>
        Your API key is stored in your browser's local storage.
      </p>
    </section>
  );
}
