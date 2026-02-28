/**
 * BrowserVoiceService — Uses Web Speech API for STT and TTS.
 * No external voice server required.
 */
import type { STTResult } from '../../models/VoiceTypes';

export class BrowserVoiceService {
  private recognition: SpeechRecognition | null = null;
  private listening = false;
  private pendingUtterances = 0;

  onTranscript: ((result: STTResult) => void) | null = null;
  onSpeechEnd: (() => void) | null = null;
  onError: ((error: Error) => void) | null = null;

  startListening(): void {
    const SpeechRecognitionCtor =
      window.SpeechRecognition ?? window.webkitSpeechRecognition;

    if (!SpeechRecognitionCtor) {
      this.onError?.(new Error('Speech recognition not supported in this browser. Use Chrome or Edge.'));
      return;
    }

    const recognition = new SpeechRecognitionCtor();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = 'en-US';

    recognition.onresult = (event: SpeechRecognitionEvent) => {
      const last = event.results[event.results.length - 1];
      if (!last) return;

      this.onTranscript?.({
        transcript: last[0].transcript,
        isFinal: last.isFinal,
        confidence: last[0].confidence,
      });
    };

    recognition.onerror = (event: SpeechRecognitionErrorEvent) => {
      // 'no-speech' and 'aborted' are normal — don't surface as errors
      if (event.error === 'no-speech' || event.error === 'aborted') return;
      this.onError?.(new Error(`Speech recognition error: ${event.error}`));
    };

    // Chrome stops recognition after silence — auto-restart if still listening
    recognition.onend = () => {
      if (this.listening) {
        try {
          recognition.start();
        } catch {
          // Already started or destroyed — ignore
        }
      }
    };

    this.recognition = recognition;
    this.listening = true;
    recognition.start();
  }

  stopListening(): void {
    this.listening = false;
    try {
      this.recognition?.stop();
    } catch {
      // Already stopped — ignore
    }
  }

  resumeListening(): void {
    if (this.recognition) {
      this.listening = true;
      try {
        this.recognition.start();
      } catch {
        // Already running — ignore
      }
    }
  }

  speak(text: string): void {
    const utterance = new SpeechSynthesisUtterance(text);
    this.pendingUtterances++;

    utterance.onend = () => {
      this.pendingUtterances--;
      if (this.pendingUtterances <= 0 && !speechSynthesis.pending) {
        this.pendingUtterances = 0;
        this.onSpeechEnd?.();
      }
    };

    utterance.onerror = () => {
      this.pendingUtterances--;
      if (this.pendingUtterances <= 0) {
        this.pendingUtterances = 0;
        this.onSpeechEnd?.();
      }
    };

    speechSynthesis.speak(utterance);
  }

  cancelSpeech(): void {
    speechSynthesis.cancel();
    this.pendingUtterances = 0;
  }

  destroy(): void {
    this.stopListening();
    this.cancelSpeech();
    this.recognition = null;
    this.onTranscript = null;
    this.onSpeechEnd = null;
    this.onError = null;
  }
}
