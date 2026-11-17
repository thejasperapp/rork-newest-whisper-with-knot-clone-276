import { afterEach, describe, expect, it, vi } from 'vitest';
import { meetingAudioFile, transcribeMeetingAudio } from '../../../functions/meeting-audio';

function wav(): Uint8Array {
  const bytes = new Uint8Array(44 + 48000); const view = new DataView(bytes.buffer);
  const text = (offset: number, value: string): void => { [...value].forEach((c, i) => { bytes[offset + i] = c.charCodeAt(0); }); };
  text(0, 'RIFF'); text(8, 'WAVE'); text(12, 'fmt '); text(36, 'data'); view.setUint32(4, bytes.length - 8, true); view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true); view.setUint32(24, 24000, true); view.setUint32(28, 48000, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true); view.setUint32(40, 48000, true); return bytes;
}
afterEach(() => vi.unstubAllGlobals());
describe('meeting audio provider boundary', () => {
  it('sends WAV as a WAV file even when an older client calls it WebM', () => { const file = meetingAudioFile(wav(), 'audio/webm'); expect(file.name).toBe('speech.wav'); expect(file.type).toBe('audio/wav'); expect(file.size).toBe(48044); });
  it('rejects a headerless media slice rather than repeatedly sending corrupt audio', () => { expect(() => meetingAudioFile(new Uint8Array(100), 'audio/webm')).toThrow('invalid_audio_container'); });
  it('requests real segment timestamps and normalizes them for recording playback', async () => {
    const fetcher = vi.fn().mockResolvedValue(Response.json({ text: 'Test sentence.', segments: [{ text: 'Test sentence.', start: 1.25, end: 2.5 }], duration: 4 })); vi.stubGlobal('fetch', fetcher);
    const response = await transcribeMeetingAudio(meetingAudioFile(wav(), 'audio/wav'), 'test-only', true);
    expect(await response.json()).toMatchObject({ segments: [{ startSecond: 1.25, endSecond: 2.5, text: 'Test sentence.' }] });
    const body = fetcher.mock.calls[0][1].body as FormData;
    expect((body.get('file') as File).name).toBe('speech.wav'); expect(body.get('response_format')).toBe('verbose_json');
  });
  it('returns a nonretryable audio error without logging the provider response body', async () => {
    vi.stubGlobal('fetch', vi.fn().mockResolvedValue(new Response('private provider diagnostics', { status: 400 })));
    const response = await transcribeMeetingAudio(meetingAudioFile(wav(), 'audio/wav'), 'test-only', false);
    expect(response.status).toBe(422); expect(await response.json()).toEqual({ error: 'invalid_audio', retryable: false });
  });
});
