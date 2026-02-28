/**
 * WebSocketVoiceService — Bidirectional WebSocket for server-based STT + TTS.
 * Sends: binary PCM audio frames + JSON control messages.
 * Receives: JSON transcript events + binary TTS audio.
 */
import type { VoiceTransport } from '../interfaces/VoiceTransport';
import type { STTResult, VoiceClientMessage } from '../../models/VoiceTypes';

export class WebSocketVoiceService implements VoiceTransport {
  private ws: WebSocket | null = null;

  onTranscript: ((result: STTResult) => void) | null = null;
  onTTSAudio: ((audioData: ArrayBuffer) => void) | null = null;
  onError: ((error: Error) => void) | null = null;

  get isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }

  async connect(url: string): Promise<void> {
    return new Promise((resolve, reject) => {
      this.ws = new WebSocket(url);
      this.ws.binaryType = 'arraybuffer';

      this.ws.onopen = () => resolve();

      this.ws.onerror = () => {
        const error = new Error('WebSocket connection failed');
        this.onError?.(error);
        reject(error);
      };

      this.ws.onclose = () => {
        this.ws = null;
      };

      this.ws.onmessage = (event) => {
        if (event.data instanceof ArrayBuffer) {
          // Binary frame = TTS audio
          this.onTTSAudio?.(event.data);
        } else {
          // Text frame = JSON control message
          try {
            const msg = JSON.parse(event.data as string);
            this.handleServerMessage(msg);
          } catch {
            // Ignore malformed JSON
          }
        }
      };
    });
  }

  disconnect(): void {
    if (this.ws) {
      this.ws.close();
      this.ws = null;
    }
  }

  sendAudio(pcmData: Int16Array): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(pcmData.buffer);
    }
  }

  sendControl(message: VoiceClientMessage): void {
    if (this.ws?.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify(message));
    }
  }

  private handleServerMessage(msg: Record<string, unknown>): void {
    switch (msg.type) {
      case 'transcript':
        this.onTranscript?.({
          transcript: msg.text as string,
          isFinal: msg.isFinal as boolean,
          confidence: (msg.confidence as number) ?? 1.0,
        });
        break;

      case 'error':
        this.onError?.(new Error(msg.message as string));
        break;

      // tts_start and tts_end could be handled for state tracking
      // but audio binary frames already handle playback flow
    }
  }
}
