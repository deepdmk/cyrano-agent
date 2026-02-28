import { DEFAULT_MODEL, DEFAULT_SYSTEM_PROMPT } from '../../models/Settings';

const KEYS = {
  apiKey: 'cyrano:api-key',
  model: 'cyrano:model',
  systemPrompt: 'cyrano:system-prompt',
  voiceServerUrl: 'cyrano:voice-server-url',
} as const;

export const StorageService = {
  // API Key
  getAPIKey(): string | null {
    return localStorage.getItem(KEYS.apiKey);
  },

  setAPIKey(key: string): void {
    localStorage.setItem(KEYS.apiKey, key);
  },

  removeAPIKey(): void {
    localStorage.removeItem(KEYS.apiKey);
  },

  hasAPIKey(): boolean {
    return localStorage.getItem(KEYS.apiKey) !== null;
  },

  // Model
  getModel(): string {
    return localStorage.getItem(KEYS.model) ?? DEFAULT_MODEL;
  },

  setModel(model: string): void {
    localStorage.setItem(KEYS.model, model);
  },

  // System Prompt
  getSystemPrompt(): string {
    return localStorage.getItem(KEYS.systemPrompt) ?? DEFAULT_SYSTEM_PROMPT;
  },

  setSystemPrompt(prompt: string): void {
    localStorage.setItem(KEYS.systemPrompt, prompt);
  },

  // Voice Server URL
  getVoiceServerUrl(): string {
    return localStorage.getItem(KEYS.voiceServerUrl) ?? 'ws://localhost:8000/voice';
  },

  setVoiceServerUrl(url: string): void {
    localStorage.setItem(KEYS.voiceServerUrl, url);
  },
};
