/**
 * AudioCapture — Captures microphone audio as PCM Int16 for WebSocket streaming.
 * Uses AudioContext + MediaStream + ScriptProcessorNode (AudioWorklet upgrade planned).
 */
export class AudioCapture {
  private audioContext: AudioContext | null = null;
  private mediaStream: MediaStream | null = null;
  private sourceNode: MediaStreamAudioSourceNode | null = null;
  private processorNode: ScriptProcessorNode | null = null;

  onAudioData: ((pcmData: Int16Array) => void) | null = null;
  onRawFloat: ((data: Float32Array) => void) | null = null;

  readonly sampleRate = 48000;
  readonly channels = 1;

  async start(): Promise<void> {
    this.mediaStream = await navigator.mediaDevices.getUserMedia({
      audio: {
        sampleRate: this.sampleRate,
        channelCount: this.channels,
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    });

    this.audioContext = new AudioContext({ sampleRate: this.sampleRate });
    this.sourceNode = this.audioContext.createMediaStreamSource(this.mediaStream);

    // ScriptProcessorNode with 1024-frame buffer (matches iOS)
    this.processorNode = this.audioContext.createScriptProcessor(1024, 1, 1);
    this.processorNode.onaudioprocess = (event) => {
      const inputData = event.inputBuffer.getChannelData(0);

      // Emit raw float for VAD
      this.onRawFloat?.(new Float32Array(inputData));

      // Convert Float32 to Int16 for WebSocket transport
      const pcm16 = new Int16Array(inputData.length);
      for (let i = 0; i < inputData.length; i++) {
        const s = Math.max(-1, Math.min(1, inputData[i]));
        pcm16[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
      }
      this.onAudioData?.(pcm16);
    };

    this.sourceNode.connect(this.processorNode);
    this.processorNode.connect(this.audioContext.destination);
  }

  stop(): void {
    this.processorNode?.disconnect();
    this.sourceNode?.disconnect();
    this.mediaStream?.getTracks().forEach((t) => t.stop());
    this.audioContext?.close();

    this.processorNode = null;
    this.sourceNode = null;
    this.mediaStream = null;
    this.audioContext = null;
  }

  get isActive(): boolean {
    return this.audioContext !== null && this.audioContext.state === 'running';
  }
}
