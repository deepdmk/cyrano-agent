export type LLMRole = 'system' | 'user' | 'assistant';

export interface LLMMessage {
  role: LLMRole;
  content: string;
}

export type StopReason = 'end_turn' | 'max_tokens' | 'stop_sequence';

export interface LLMToken {
  content: string;
  isDone: boolean;
  stopReason?: StopReason;
}

export interface LLMConfig {
  model: string;
  maxTokens: number;
  temperature: number;
  topP?: number;
  stopSequences?: string[];
  systemPrompt?: string;
  stream: boolean;
}
