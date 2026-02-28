import { useChatState, useChatDispatch } from '../../state/ChatContext';
import { useChatActions } from '../../state/useChatActions';
import { ServerSection } from './ServerSection';
import { ApiKeySection } from './ApiKeySection';
import { ModelSection } from './ModelSection';
import { SystemPromptSection } from './SystemPromptSection';
import { VoicePipelineSection } from './VoicePipelineSection';
import { AboutSection } from './AboutSection';
import { StorageService } from '../../services/storage/StorageService';
import styles from './SettingsModal.module.css';

export function SettingsModal() {
  const state = useChatState();
  const dispatch = useChatDispatch();
  const { saveAPIKey, removeAPIKey, setModel, setSystemPrompt, saveCyranoServerUrl, removeCyranoServerUrl } = useChatActions();

  const handleClose = () => {
    dispatch({ type: 'SET_SHOW_SETTINGS', value: false });
  };

  return (
    <div className={styles.overlay} onClick={handleClose}>
      <div className={styles.modal} onClick={(e) => e.stopPropagation()}>
        <div className={styles.header}>
          <div className={styles.headerSpacer} />
          <h2 className={styles.headerTitle}>Settings</h2>
          <button className={styles.doneButton} onClick={handleClose}>
            Done
          </button>
        </div>

        <div className={styles.content}>
          <ServerSection
            serverUrl={StorageService.getCyranoServerUrl()}
            onSave={saveCyranoServerUrl}
            onRemove={removeCyranoServerUrl}
          />
          <ApiKeySection
            hasKey={state.hasAPIKey}
            onSave={saveAPIKey}
            onRemove={removeAPIKey}
          />
          <ModelSection
            selectedModel={state.selectedModel}
            onSelect={setModel}
          />
          <SystemPromptSection
            prompt={state.systemPrompt}
            onChange={setSystemPrompt}
          />
          <VoicePipelineSection />
          <AboutSection
            hasKey={state.hasAPIKey}
            onRemoveKey={removeAPIKey}
          />
        </div>
      </div>
    </div>
  );
}
