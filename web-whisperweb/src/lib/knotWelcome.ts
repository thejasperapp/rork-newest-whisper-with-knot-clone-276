import { groupThemeSession } from '@/lib/groupThemeSession';
import { knotBackendOrigin } from '@/lib/knotBackend';

export const welcomeConsent = 'knot_welcome_rork_voice_v2';
export interface KnotWelcomeInvitation { id: string; version: string; expiresAt: number }
export interface KnotWelcomeAnswer { welcomeID: string; deviceID: string; answerID: string; welcomeConsentVersion: string; displayName: string }
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
export function welcomeDeviceID(): string {
  const key = 'knot_welcome_device_v1';
  try {
    const saved = localStorage.getItem(key); if (saved && uuid.test(saved)) return saved;
    const id = crypto.randomUUID(); localStorage.setItem(key, id); return id;
  } catch { return crypto.randomUUID(); }
}
/** No shared text/profile consent is inferred; these endpoints carry only
 * delivery metadata until the member explicitly answers the disclosed call. */
export async function welcomeRequest<T>(owner: string, path: string, fields: Record<string, unknown>, signal: AbortSignal): Promise<T> {
  const lease = await groupThemeSession(owner);
  const combined = AbortSignal.any([signal, lease.signal, AbortSignal.timeout(18000)]);
  const check = () => { lease.check(); if (combined.aborted || document.hidden) throw new DOMException('Stopped', 'AbortError'); };
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  try {
    check();
    const response = await fetch(knotBackendOrigin + '/' + path, { method: 'POST', cache: 'no-store', redirect: 'error', signal: combined,
      headers: { 'Content-Type': 'application/json', 'X-Whisper-Authorization': `Bearer ${lease.token}`, Authorization: `Bearer ${lease.token}` }, body: JSON.stringify(fields) });
    check(); if (!response.ok || !response.body) throw new Error('Welcome call unavailable');
    reader = response.body.getReader(); let text = '', size = 0; const decoder = new TextDecoder();
    for (;;) { const part = await reader.read(); check(); if (part.done) break; size += part.value.byteLength; if (size > 24000) throw new Error('Welcome unavailable'); text += decoder.decode(part.value, { stream: true }); }
    check(); return JSON.parse(text + decoder.decode()) as T;
  } finally { await reader?.cancel().catch(() => undefined); reader?.releaseLock(); lease.dispose(); }
}
export function validWelcome(value: unknown): value is KnotWelcomeInvitation {
  if (!value || typeof value !== 'object') return false;
  const item = value as KnotWelcomeInvitation;
  return typeof item.id === 'string' && uuid.test(item.id) && item.version === 'knot_welcome_2026_11_10' && Number.isFinite(item.expiresAt) && item.expiresAt > Date.now();
}
let humanIncoming = false;
export const humanCallChanged = 'whisper-human-incoming-changed';
export function humanCallIsIncoming(): boolean { return humanIncoming; }
export function setHumanCallIncoming(value: boolean): void {
  if (humanIncoming === value) return;
  humanIncoming = value; window.dispatchEvent(new Event(humanCallChanged));
}
