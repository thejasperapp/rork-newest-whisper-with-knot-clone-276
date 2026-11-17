/** Choose an extension from the actual container, not a hard-coded WebM suffix. */
export function meetingAudioFile(bytes: Uint8Array, declaredType: string): File {
  const ascii = (start: number, length: number): string => String.fromCharCode(...bytes.subarray(start, start + length));
  const type = declaredType.split(';')[0].toLowerCase().trim();
  let extension: string;
  let mediaType: string;
  if (ascii(0, 4) === 'RIFF' && ascii(8, 4) === 'WAVE') { extension = 'wav'; mediaType = 'audio/wav'; }
  else if (ascii(4, 4) === 'ftyp') { extension = 'm4a'; mediaType = 'audio/mp4'; }
  else if (bytes[0] === 0x1a && bytes[1] === 0x45 && bytes[2] === 0xdf && bytes[3] === 0xa3) { extension = 'webm'; mediaType = 'audio/webm'; }
  else if (ascii(0, 3) === 'ID3' || (bytes[0] === 0xff && (bytes[1] & 0xe0) === 0xe0)) { extension = 'mp3'; mediaType = 'audio/mpeg'; }
  else { throw new Error('invalid_audio_container'); }
  if (type === 'audio/wav' && extension !== 'wav') throw new Error('invalid_audio_container');
  return new File([bytes as Uint8Array<ArrayBuffer>], `speech.${extension}`, { type: mediaType });
}

/** Existing server-side provider, bounded request and normalized real segment timing. */
export async function transcribeMeetingAudio(file: File, key: string, timed: boolean): Promise<Response> {
  const headers = { 'Access-Control-Allow-Origin': '*', 'Cache-Control': 'no-store' };
  const fail = (error: string, status: number, retryable: boolean): Response => Response.json({ error, retryable }, { status, headers });
  const form = new FormData(); form.append('file', file);
  form.append('model', timed ? 'whisper-1' : 'gpt-4o-mini-transcribe');
  if (timed) { form.append('response_format', 'verbose_json'); form.append('timestamp_granularities[]', 'segment'); }
  try {
    const response = await fetch('https://api.openai.com/v1/audio/transcriptions', { method: 'POST', headers: { Authorization: `Bearer ${key}` }, body: form, signal: AbortSignal.timeout(35000) });
    if (!response.ok) {
      console.warn('Meeting transcription rejected', { status: response.status, format: file.type });
      return fail(response.status === 400 ? 'invalid_audio' : response.status === 429 ? 'transcription_busy' : 'transcription_unavailable', response.status === 400 ? 422 : response.status === 429 ? 429 : 502, response.status !== 400);
    }
    const result = await response.json() as { text?: unknown; duration?: number; language?: string; segments?: { text: string; start: number; end: number }[] };
    if (typeof result.text !== 'string') return fail('incomplete_transcription', 502, true);
    return Response.json({ text: result.text.trim(), ...(timed ? { segments: result.segments?.map((s) => ({ text: s.text, startSecond: s.start, endSecond: s.end })), durationInSeconds: result.duration, language: result.language } : {}) }, { headers });
  } catch { return fail('transcription_timeout', 504, true); }
}
