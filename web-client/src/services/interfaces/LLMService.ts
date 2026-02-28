import type { LLMMessage, LLMToken, LLMConfig } from '../../models/LLMTypes';

export interface LLMService {
  streamCompletion(
    messages: LLMMessage[],
    config: LLMConfig,
  ): AsyncGenerator<LLMToken, void, unknown>;

  abort(): void;
}
