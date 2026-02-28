export interface ModelOption {
  id: string;
  displayName: string;
}

export const AVAILABLE_MODELS: ModelOption[] = [
  { id: 'claude-sonnet-4-20250514', displayName: 'Claude Sonnet 4' },
  { id: 'claude-haiku-4-20250414', displayName: 'Claude Haiku 4' },
  { id: 'claude-opus-4-20250514', displayName: 'Claude Opus 4' },
];

export const DEFAULT_MODEL = 'claude-sonnet-4-20250514';

export const DEFAULT_SYSTEM_PROMPT =
  'You are a helpful AI assistant. Keep responses concise and conversational.';
