export interface STTResult {
  transcript: string;
  isFinal: boolean;
  confidence: number;
}

export interface VADResult {
  isSpeech: boolean;
  confidence: number;
  timestamp: number;
}

/** Messages sent from client to voice server */
export type VoiceClientMessage =
  | { type: 'start_session'; sampleRate: number; channels: number; encoding: string }
  | { type: 'end_session' }
  | { type: 'stop_tts' }
  | { type: 'tts_request'; text: string };

/** Messages received from voice server */
export type VoiceServerMessage =
  | { type: 'transcript'; text: string; isFinal: boolean; confidence: number }
  | { type: 'tts_start' }
  | { type: 'tts_end' }
  | { type: 'error'; message: string };
