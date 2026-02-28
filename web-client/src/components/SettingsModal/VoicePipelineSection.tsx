import { MicIcon, SpeakerIcon } from '../Icons/Icons';
import styles from './SettingsModal.module.css';

export function VoicePipelineSection() {
  return (
    <section className={styles.section}>
      <h3 className={styles.sectionHeader}>Voice Pipeline</h3>

      <div className={styles.infoRow}>
        <MicIcon size={18} style={{ color: 'var(--color-blue)' }} />
        <span>Voice Input</span>
        <span className={styles.infoValue}>GLM-ASR (Server)</span>
      </div>

      <div className={styles.infoRow}>
        <SpeakerIcon size={18} style={{ color: 'var(--color-blue)' }} />
        <span>Voice Output</span>
        <span className={styles.infoValue}>Server TTS</span>
      </div>

      <p className={styles.sectionFooter}>
        STT: GLM-ASR via server. TTS: Server-side synthesis. Requires voice server connection.
      </p>
    </section>
  );
}
