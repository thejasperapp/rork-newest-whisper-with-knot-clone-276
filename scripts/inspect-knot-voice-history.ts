// Read-only historical metadata inspection. No calls, tokens, audio or config
// mutations. Output is a fixed allowlist; provider bodies/reasons/IDs stay private.
export {};
const key = process.env.ELEVENLABS_API_KEY;
if (!key) throw new Error('Server-only voice key is not configured.');
type ObjectValue = Record<string, unknown>;
const object = (v: unknown): ObjectValue => v && typeof v === 'object' && !Array.isArray(v) ? v as ObjectValue : {};
function category(raw: unknown): string {
  if (typeof raw !== 'string' || !raw) return 'none';
  if (/agent.*(?:not available|not found|not ready|not initialized|not published)/i.test(raw)) return 'agent_unavailable';
  if (/authenticat|unauthori[sz]ed|permission/i.test(raw)) return 'authentication';
  if (/rate.?limit|concurren/i.test(raw)) return 'rate_limit';
  if (/quota|credit|balance|budget/i.test(raw)) return 'quota';
  if (/client.*disconnect|user.*end/i.test(raw)) return 'client_disconnect';
  if (/timeout|timed out|webrtc|livekit|websocket|connection/i.test(raw)) return 'transport';
  return 'unknown';
}
async function read(path: string): Promise<ObjectValue | undefined> {
  try {
    const response = await fetch('https://api.elevenlabs.io/v1/convai/' + path, {
      headers: { 'xi-api-key': key! }, redirect: 'error', signal: AbortSignal.timeout(15000),
    });
    if (!response.ok) { await response.body?.cancel(); console.log(JSON.stringify({ readHTTP: response.status })); return undefined; }
    return object(await response.json());
  } catch { console.log(JSON.stringify({ readFailure: 'transport' })); return undefined; }
}
for (const [agent, variable] of [['legacy', 'ELEVENLABS_AGENT_ID'], ['relay', 'ELEVENLABS_RELAY_AGENT_ID']] as const) {
  const id = process.env[variable];
  if (!id) { console.log(JSON.stringify({ agent, configured: false })); continue; }
  const query = new URLSearchParams({ agent_id: id, page_size: '20' });
  const listing = await read('conversations?' + query);
  if (!listing) continue;
  const rows = Array.isArray(listing.conversations) ? listing.conversations.slice(0, 20) : [];
  console.log(JSON.stringify({ agent, listed: rows.length, detailsBound: 5 }));
  for (const raw of rows.slice(0, 5)) {
    const row = object(raw);
    if (typeof row.conversation_id !== 'string' || !/^[a-zA-Z0-9_-]{5,120}$/.test(row.conversation_id)) continue;
    const detail = await read('conversations/' + encodeURIComponent(row.conversation_id));
    if (!detail) continue;
    const metadata = object(detail.metadata), error = object(metadata.error);
    const time = metadata.start_time_unix_secs, duration = metadata.call_duration_secs;
    const start = typeof time === 'number' && Number.isFinite(time) ? new Date(time * 1000) : undefined;
    console.log(JSON.stringify({ agent,
      startedAt: start && Number.isFinite(start.getTime()) ? start.toISOString() : null,
      durationSeconds: typeof duration === 'number' && Number.isFinite(duration) ? duration : null,
      status: typeof detail.status === 'string' && ['initiated', 'in-progress', 'processing', 'done', 'failed'].includes(detail.status) ? detail.status : 'unknown',
      termination: category(metadata.termination_reason),
      error: category(typeof metadata.error === 'string' ? metadata.error : error.reason),
      errorCode: typeof error.code === 'number' && Number.isFinite(error.code) ? error.code : null,
    }));
  }
}
