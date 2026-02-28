import type { LLMMessage, LLMToken, LLMConfig } from '../../models/LLMTypes';
import type { LLMService } from '../interfaces/LLMService';

export class ClaudeAPIService implements LLMService {
  private apiKey: string;
  private abortController: AbortController | null = null;
  private readonly baseURL = 'https://api.anthropic.com/v1/messages';
  private readonly apiVersion = '2023-06-01';

  constructor(apiKey: string) {
    this.apiKey = apiKey;
  }

  abort(): void {
    this.abortController?.abort();
    this.abortController = null;
  }

  async *streamCompletion(
    messages: LLMMessage[],
    config: LLMConfig,
  ): AsyncGenerator<LLMToken, void, unknown> {
    this.abortController = new AbortController();

    // Separate system prompt from messages
    let systemPrompt: string | undefined = config.systemPrompt;
    const apiMessages: Array<{ role: string; content: string }> = [];

    for (const message of messages) {
      if (message.role === 'system') {
        systemPrompt = message.content;
      } else {
        apiMessages.push({ role: message.role, content: message.content });
      }
    }

    // Build request body
    const body: Record<string, unknown> = {
      model: config.model,
      max_tokens: config.maxTokens,
      temperature: config.temperature,
      stream: true,
      messages: apiMessages,
    };

    if (systemPrompt) {
      body.system = systemPrompt;
    }
    if (config.topP !== undefined) {
      body.top_p = config.topP;
    }
    if (config.stopSequences?.length) {
      body.stop_sequences = config.stopSequences;
    }

    const response = await fetch(this.baseURL, {
      method: 'POST',
      headers: {
        'x-api-key': this.apiKey,
        'anthropic-version': this.apiVersion,
        'content-type': 'application/json',
        'anthropic-dangerous-direct-browser-access': 'true',
      },
      body: JSON.stringify(body),
      signal: this.abortController.signal,
    });

    if (!response.ok) {
      throw this.mapResponseError(response.status);
    }

    const reader = response.body!.getReader();
    const decoder = new TextDecoder();
    let buffer = '';
    let currentEventType = '';

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop()!;

        for (const line of lines) {
          if (line.startsWith('event: ')) {
            currentEventType = line.slice(7);
            continue;
          }

          if (line.startsWith('data: ')) {
            const token = this.parseSSEData(currentEventType, line.slice(6));
            if (token) {
              yield token;
              if (token.isDone) return;
            }
            currentEventType = '';
          }
        }
      }
    } finally {
      reader.releaseLock();
      this.abortController = null;
    }
  }

  private parseSSEData(_eventType: string, data: string): LLMToken | null {
    let json: Record<string, unknown>;
    try {
      json = JSON.parse(data);
    } catch {
      return null;
    }

    const type = json.type as string;

    switch (type) {
      case 'content_block_delta': {
        const delta = json.delta as Record<string, unknown> | undefined;
        const text = delta?.text as string | undefined;
        if (text) {
          return { content: text, isDone: false };
        }
        return null;
      }

      case 'message_stop':
        return { content: '', isDone: true, stopReason: 'end_turn' };

      case 'message_delta': {
        const delta = json.delta as Record<string, unknown> | undefined;
        const stopReason = delta?.stop_reason as string | undefined;
        if (stopReason) {
          return {
            content: '',
            isDone: true,
            stopReason: (stopReason === 'end_turn' || stopReason === 'max_tokens' || stopReason === 'stop_sequence')
              ? stopReason
              : 'end_turn',
          };
        }
        return null;
      }

      case 'error': {
        const error = json.error as Record<string, unknown> | undefined;
        const message = error?.message as string | undefined;
        return { content: `[Error: ${message ?? 'Unknown error'}]`, isDone: true };
      }

      default:
        return null;
    }
  }

  private mapResponseError(status: number): Error {
    switch (status) {
      case 401:
        return new Error('Invalid API key. Please check your key in Settings.');
      case 429:
        return new Error('Rate limited. Please wait a moment and try again.');
      case 400:
        return new Error('Bad request. Please check your message and try again.');
      case 404:
        return new Error('Model not found. Try selecting a different model in Settings.');
      case 529:
        return new Error('Service temporarily unavailable. Please try again later.');
      default:
        return new Error(`API error (HTTP ${status}). Please try again.`);
    }
  }
}
