/**
 * ClientVAD — Client-side voice activity detection using RMS energy.
 * Provides barge-in detection and audio level visualization.
 * Mirrors iOS SileroVADService fallback logic.
 */
import type { VADResult } from '../../models/VoiceTypes';

const MIN_DB = -60;
const MAX_DB = -20;
const SMOOTHING_WINDOW = 5;
const UPDATE_INTERVAL_MS = 100;

export class ClientVAD {
  private smoothingBuffer: number[] = [];
  private intervalId: ReturnType<typeof setInterval> | null = null;
  private latestRMS = 0;

  onResult: ((result: VADResult) => void) | null = null;
  onAudioLevel: ((level: number) => void) | null = null;

  /** Feed raw Float32 audio data from AudioCapture */
  processBuffer(data: Float32Array): void {
    // Calculate RMS
    let sum = 0;
    for (let i = 0; i < data.length; i++) {
      sum += data[i] * data[i];
    }
    this.latestRMS = Math.sqrt(sum / data.length);
  }

  start(): void {
    this.smoothingBuffer = [];

    this.intervalId = setInterval(() => {
      const rms = this.latestRMS;

      // Convert to dB and normalize to 0-1
      const db = 20 * Math.log10(Math.max(rms, 1e-10));
      const confidence = Math.max(0, Math.min(1, (db - MIN_DB) / (MAX_DB - MIN_DB)));

      // Apply smoothing
      this.smoothingBuffer.push(confidence);
      if (this.smoothingBuffer.length > SMOOTHING_WINDOW) {
        this.smoothingBuffer.shift();
      }
      const smoothed =
        this.smoothingBuffer.reduce((a, b) => a + b, 0) / this.smoothingBuffer.length;

      // Report VAD result
      this.onResult?.({
        isSpeech: smoothed >= 0.5,
        confidence: smoothed,
        timestamp: Date.now(),
      });

      // Report audio level for UI bars
      this.onAudioLevel?.(smoothed);
    }, UPDATE_INTERVAL_MS);
  }

  stop(): void {
    if (this.intervalId !== null) {
      clearInterval(this.intervalId);
      this.intervalId = null;
    }
    this.smoothingBuffer = [];
    this.latestRMS = 0;
  }

  reset(): void {
    this.smoothingBuffer = [];
    this.latestRMS = 0;
  }
}
