import { AVAILABLE_MODELS } from '../../models/Settings';
import styles from './SettingsModal.module.css';

interface Props {
  selectedModel: string;
  onSelect: (model: string) => void;
}

export function ModelSection({ selectedModel, onSelect }: Props) {
  return (
    <section className={styles.section}>
      <h3 className={styles.sectionHeader}>LLM Model</h3>
      <select
        className={styles.select}
        value={selectedModel}
        onChange={(e) => onSelect(e.target.value)}
      >
        {AVAILABLE_MODELS.map((model) => (
          <option key={model.id} value={model.id}>
            {model.displayName}
          </option>
        ))}
      </select>
    </section>
  );
}
