/* Runs on the audio rendering thread. Emits self-contained 30-second PCM batches. */
class RecordingPCM extends AudioWorkletProcessor {
  constructor(options) {
    super();
    const seconds = Math.max(5, Math.min(30, Number(options?.processorOptions?.chunkSeconds) || 30));
    this.buffer = new Float32Array(sampleRate * seconds);
    this.count = 0;
    this.start = 0;
    this.active = false;
    this.port.onmessage = (event) => {
      if (event.data === "start") this.active = true;
      if (event.data === "stop") { this.active = false; this.flush(); this.port.postMessage({ stopped: true }); }
    };
  }
  flush() {
    if (!this.count) return;
    const samples = this.buffer.slice(0, this.count);
    this.port.postMessage({ samples, rate: sampleRate, start: this.start, end: this.start + this.count / sampleRate }, [samples.buffer]);
    this.count = 0;
  }
  process(inputs) {
    if (!this.active) return true;
    const input = inputs[0];
    const length = input?.[0]?.length || 128;
    for (let i = 0; i < length; i++) {
      if (this.count === 0) this.start = currentTime + i / sampleRate;
      let value = 0;
      if (input?.length) { for (const channel of input) value += channel[i] || 0; value /= input.length; }
      this.buffer[this.count++] = value;
      if (this.count === this.buffer.length) this.flush();
    }
    return true;
  }
}
registerProcessor("whisper-recording-pcm", RecordingPCM);
