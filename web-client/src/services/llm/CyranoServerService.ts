import type { LLMMessage, LLMToken, LLMConfig } from '../../models/LLMTypes';
import type { LLMService } from '../interfaces/LLMService';

export class CyranoServerService implements LLMService {
  private serverUrl: string;
  private abortController: AbortController | null = null;
  private sessionId: string | null = null;
  private userId: string;

  constructor(serverUrl: string, userId: string = 'web_user') {
    this.serverUrl = serverUrl.replace(/\/+$/, '');
    this.userId = userId;
  }

  abort(): void {
    this.abortController?.abort();
    this.abortController = null;
  }

  getSessionId(): string | null {
    return this.sessionId;
  }

  async *streamCompletion(
    messages: LLMMessage[],
    _config: LLMConfig,
  ): AsyncGenerator<LLMToken, void, unknown> {
    this.abortController = new AbortController();

    // Extract the last user message — the agno server manages its own history
    const lastUserMessage = [...messages].reverse().find((m) => m.role === 'user');
    if (!lastUserMessage) {
      yield { content: 'No user message found.', isDone: true };
      return;
    }

    const response = await fetch(`${this.serverUrl}/chat`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify({
        message: lastUserMessage.content,
        user_id: this.userId,
        session_id: this.sessionId,
      }),
      signal: this.abortController.signal,
    });

    if (!response.ok) {
      throw new Error(`Cyrano server error (HTTP ${response.status})`);
    }

    const reader = response.body!.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    try {
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;

        buffer += decoder.decode(value, { stream: true });
        const lines = buffer.split('\n');
        buffer = lines.pop()!;

        let currentEvent = '';
        for (const line of lines) {
          if (line.startsWith('event: ')) {
            currentEvent = line.slice(7);
          } else if (line.startsWith('data: ')) {
            const data = JSON.parse(line.slice(6));

            if (currentEvent === 'session') {
              this.sessionId = data.session_id;
            } else if (currentEvent === 'token') {
              yield { content: data.content, isDone: false };
            } else if (currentEvent === 'done') {
              yield { content: '', isDone: true, stopReason: 'end_turn' };
              return;
            } else if (currentEvent === 'error') {
              yield { content: `[Error: ${data.error}]`, isDone: true };
              return;
            }
            currentEvent = '';
          }
        }
      }
    } finally {
      reader.releaseLock();
      this.abortController = null;
    }
  }
}
