// Read-only exact-ID lookups in the public voice library. No account changes,
// conversations, previews, synthesis, credentials or full responses are logged.
import { knotVoiceIDs } from '../functions/knot-voice-policy';

const key = process.env.ELEVENLABS_API_KEY;
if (!key) throw new Error('ELEVENLABS_API_KEY is not configured.');
const targets = [
  { choice: 'boy', id: knotVoiceIDs.boy, search: 'Mark - Natural Conversations' },
  { choice: 'girl', id: knotVoiceIDs.girl, search: 'Lauren - Friendly, Comforting and Soft' },
] as const;
for (const target of targets) {
  let found = false;
  for (let page = 0; page < 3; page++) {
    const url = new URL('https://api.elevenlabs.io/v1/shared-voices');
    url.searchParams.set('search', target.search);
    url.searchParams.set('page_size', '100');
    url.searchParams.set('page', String(page));
    const response = await fetch(url, { headers: { 'xi-api-key': key }, signal: AbortSignal.timeout(15000), redirect: 'error' });
    if (!response.ok) {
      await response.body?.cancel();
      console.log(JSON.stringify({ check: target.choice + '_library', http: response.status }));
      break;
    }
    const body = await response.json() as { voices?: Record<string, unknown>[]; has_more?: boolean };
    const voice = Array.isArray(body.voices) ? body.voices.find(item => item.voice_id === target.id) : undefined;
    if (voice) {
      found = true;
      const safe: Record<string, unknown> = { check: target.choice + '_library', exactIDFound: true };
      for (const field of ['name', 'is_added_by_user', 'free_users_allowed', 'rate', 'notice_period', 'disable_at_unix', 'live_moderation_enabled']) {
        const value = voice[field];
        if (typeof value === 'boolean' || typeof value === 'number' || value === null || (field === 'name' && typeof value === 'string' && value.length <= 120)) safe[field] = value;
      }
      console.log(JSON.stringify(safe));
      break;
    }
    if (!body.has_more) break;
    if (page === 2) console.log(JSON.stringify({ check: target.choice + '_library', searchLimitReached: true }));
  }
  if (!found) console.log(JSON.stringify({ check: target.choice + '_library', exactIDFound: false }));
}
export {};
