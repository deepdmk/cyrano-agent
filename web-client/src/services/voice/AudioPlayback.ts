/**
 * AudioPlayback — Plays TTS audio received from the server.
 * Queues AudioBuffers for gapless playback via Web Audio API.
 */
export class AudioPlayback {
  private audioContext: AudioContext | null = null;
  private queue: AudioBuffer[] = [];
  private currentSource: AudioBufferSourceNode | null = null;
  private isPlaying = false;

  onPlaybackComplete: (() => void) | null = null;

  get isSpeaking(): boolean {
    return this.isPlaying;
  }

  private ensureContext(): AudioContext {
    if (!this.audioContext) {
      this.audioContext = new AudioContext({ sampleRate: 24000 });
    }
    return this.audioContext;
  }

  /** Queue audio data (PCM bytes) for playback */
  async play(audioData: ArrayBuffer): Promise<void> {
    const ctx = this.ensureContext();

    try {
      const audioBuffer = await ctx.decodeAudioData(audioData.slice(0));
      this.queue.push(audioBuffer);

      if (!this.isPlaying) {
        this.playNext();
      }
    } catch {
      // If decodeAudioData fails (e.g., raw PCM without headers),
      // try creating buffer directly assuming 16-bit PCM mono 24kHz
      const pcm16 = new Int16Array(audioData);
      const floats = new Float32Array(pcm16.length);
      for (let i = 0; i < pcm16.length; i++) {
        floats[i] = pcm16[i] / 32768;
      }

      const audioBuffer = ctx.createBuffer(1, floats.length, 24000);
      audioBuffer.copyToChannel(floats, 0);
      this.queue.push(audioBuffer);

      if (!this.isPlaying) {
        this.playNext();
      }
    }
  }

  private playNext(): void {
    const ctx = this.audioContext;
    if (!ctx) return;

    const buffer = this.queue.shift();
    if (!buffer) {
      this.isPlaying = false;
      this.onPlaybackComplete?.();
      return;
    }

    this.isPlaying = true;
    this.currentSource = ctx.createBufferSource();
    this.currentSource.buffer = buffer;
    this.currentSource.connect(ctx.destination);

    this.currentSource.onended = () => {
      this.currentSource = null;
      this.playNext();
    };

    this.currentSource.start();
  }

  /** Stop playback immediately and clear queue */
  flush(): void {
    this.queue = [];
    if (this.currentSource) {
      try {
        this.currentSource.stop();
      } catch {
        // Already stopped
      }
      this.currentSource = null;
    }
    this.isPlaying = false;
  }

  destroy(): void {
    this.flush();
    this.audioContext?.close();
    this.audioContext = null;
  }
}
