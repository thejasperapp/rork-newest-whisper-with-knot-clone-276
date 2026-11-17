import { meetingAudioFile, transcribeMeetingAudio } from './meeting-audio';

type GatewayEnv = { OPENAI_API_KEY?: string; EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY?: string; RORK_TOOLKIT_SECRET_KEY?: string; EXPO_PUBLIC_TOOLKIT_URL?: string };

/** Authenticated by the caller before entering. No audio or transcript is logged or placed on shared meeting rows. */
export async function notebookTranscription(request: Request, env: GatewayEnv): Promise<Response> {
  const headers = { "Access-Control-Allow-Origin": "*", "Cache-Control": "no-store" };
  const fail = (error: string, status: number): Response => Response.json({ error }, { status, headers });
  const key = env.RORK_TOOLKIT_SECRET_KEY || env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY;
  if (!key && !env.OPENAI_API_KEY) return fail("Transcription is not configured yet.", 503);
  const declared = Number(request.headers.get("content-length") || 0);
  if (declared > 8_500_000) return fail("Audio segment is too large.", 413);
  const reader = request.body?.getReader();
  if (!reader) return fail("Audio is required.", 400);
  const chunks: Uint8Array[] = []; let size = 0;
  for (;;) { const value = await reader.read(); if (value.done) break; size += value.value.length; if (size > 8_500_000) { await reader.cancel(); return fail("Audio segment is too large.", 413); } chunks.push(value.value); }
  let body: { audio?: unknown; mediaType?: unknown };
  try { const data = new Uint8Array(size); let cursor = 0; for (const chunk of chunks) { data.set(chunk, cursor); cursor += chunk.length; } body = JSON.parse(new TextDecoder().decode(data)); } catch { return fail("Invalid audio request.", 400); }
  if (typeof body.audio !== "string" || !body.audio.length || body.audio.length > 8_000_000 || typeof body.mediaType !== "string" || !["audio/wav", "audio/mp4", "audio/m4a", "audio/x-m4a", "audio/mpeg"].includes(body.mediaType)) return fail("Use a supported audio segment under 6 MB.", 400);
  if (env.OPENAI_API_KEY) {
    try {
      const binary = atob(body.audio); const bytes = new Uint8Array(binary.length);
      for (let index = 0; index < binary.length; index++) bytes[index] = binary.charCodeAt(index);
      return await transcribeMeetingAudio(meetingAudioFile(bytes, body.mediaType), env.OPENAI_API_KEY, true);
    } catch { return fail('invalid_audio', 422); }
  }
  try {
    const response = await fetch(`${(env.EXPO_PUBLIC_TOOLKIT_URL || "https://toolkit.rork.com").replace(/\/+$/, "")}/v2/vercel/v4/ai/transcription-model`, {
      method: "POST", signal: AbortSignal.timeout(45000), headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "ai-model-id": "openai/whisper-1", "ai-gateway-protocol-version": "0.0.1" },
      body: JSON.stringify({ audio: body.audio, mediaType: body.mediaType }),
    });
    if (!response.ok) return fail("Transcription is unavailable. The recording is retained; try again later.", response.status === 429 ? 429 : 502);
    const result = await response.json() as { text?: unknown; segments?: unknown; language?: unknown; durationInSeconds?: unknown };
    if (typeof result.text !== "string") return fail("The transcription service returned an incomplete result.", 502);
    return Response.json({ text: result.text, segments: result.segments, language: result.language, durationInSeconds: result.durationInSeconds }, { headers });
  } catch { return fail("Transcription timed out. The recording is retained.", 504); }
}
