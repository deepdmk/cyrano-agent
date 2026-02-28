import type { STTResult, VoiceClientMessage } from '../../models/VoiceTypes';

export interface VoiceTransport {
  connect(url: string): Promise<void>;
  disconnect(): void;
  sendAudio(pcmData: Int16Array): void;
  sendControl(message: VoiceClientMessage): void;
  onTranscript: ((result: STTResult) => void) | null;
  onTTSAudio: ((audioData: ArrayBuffer) => void) | null;
  onError: ((error: Error) => void) | null;
  readonly isConnected: boolean;
}
