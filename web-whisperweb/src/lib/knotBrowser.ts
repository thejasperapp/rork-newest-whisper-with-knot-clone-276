import { groupThemeSession } from '@/lib/groupThemeSession';
import { knotBackendOrigin } from '@/lib/knotBackend';
import { consentChanged, knotAllowed, type KnotBot } from '@/lib/knotService';

export type BrowserAction = 'state' | 'screenshot' | 'content' | 'start' | 'navigate' | 'input' | 'stop';
export interface KnotBrowserState { live: boolean; url?: string; title?: string; profile_persists?: boolean; outcomeUncertain?: boolean; operationPending?: boolean }
export class KnotBrowserError extends Error {
  constructor(readonly code: string) { super(code); }
}
/** Separate from read-only shell evidence. All mutations originate from an explicit
 * member action, carry one identity, and are never retried. Nothing is persisted. */
export async function knotBrowserRequest(owner: string, bot: KnotBot, conversationID: string, action: BrowserAction, signal: AbortSignal, fields: Record<string, unknown> = {}): Promise<KnotBrowserState | Blob> {
  if (!/^[0-9a-f-]{36}$/i.test(conversationID)) throw new KnotBrowserError('invalid_context');
  const withdrawal = new AbortController();
  const stop = () => withdrawal.abort();
  const storage = (event: StorageEvent) => { if (event.key === null || event.key.startsWith(`knot_ai_consent_v3:${owner.toLowerCase()}`)) stop(); };
  window.addEventListener(consentChanged, stop); window.addEventListener('storage', storage);
  const auth = await groupThemeSession(owner).catch(error => { window.removeEventListener(consentChanged, stop); window.removeEventListener('storage', storage); throw error; });
  const combined = AbortSignal.any([signal, withdrawal.signal, auth.signal, AbortSignal.timeout(action === 'navigate' ? 55000 : 25000)]);
  const check = () => { auth.check(); if (combined.aborted || !knotAllowed(owner)) throw new DOMException('Stopped', 'AbortError'); };
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  try {
    check();
    const response = await fetch(knotBackendOrigin + '/knot/browser/' + action, {
      method: 'POST', redirect: 'error', cache: 'no-store', signal: combined,
      headers: { 'Content-Type': 'application/json', 'X-Whisper-Authorization': `Bearer ${auth.token}` },
      body: JSON.stringify({ ...fields, bot, conversationID: conversationID.toLowerCase(), consentVersion: 'knot_browser_v1', ...(['start','navigate','input','stop'].includes(action) ? { actionID: crypto.randomUUID(), expiresAt: Date.now() + 45000 } : {}) }),
    });
    check();
    if (!response.body) throw new KnotBrowserError('browser_unavailable');
    reader = response.body.getReader(); const chunks: Uint8Array[] = []; let size = 0;
    const limit = !response.ok ? 4096 : action === 'screenshot' ? 4000000 : action === 'content' ? 850000 : 100000;
    for (;;) { const part = await reader.read(); check(); if (part.done) break; size += part.value.byteLength; if (size > limit) throw new KnotBrowserError('browser_response_limit'); chunks.push(part.value); }
    const bytes = new Uint8Array(size); let at = 0; for (const part of chunks) { bytes.set(part, at); at += part.byteLength; }
    check();
    if (!response.ok) {
      const failure = JSON.parse(new TextDecoder().decode(bytes)) as { error?: string };
      throw new KnotBrowserError(typeof failure.error === 'string' ? failure.error : 'browser_unavailable');
    }
    if (action === 'screenshot') {
      if (!response.headers.get('Content-Type')?.startsWith('image/png') || bytes.length < 24 || ![137,80,78,71,13,10,26,10].every((n,i) => bytes[i] === n)) throw new KnotBrowserError('browser_image_unavailable');
      const view = new DataView(bytes.buffer); if (view.getUint32(16) !== 1280 || view.getUint32(20) !== 800) throw new KnotBrowserError('browser_image_unavailable');
      return new Blob([bytes], { type: 'image/png' });
    }
    const value = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(bytes)) as KnotBrowserState;
    if (!value || typeof value !== 'object' || (action === 'state' && typeof value.live !== 'boolean')) throw new KnotBrowserError('browser_unavailable');
    return value;
  } finally {
    await reader?.cancel().catch(() => undefined); reader?.releaseLock(); auth.dispose();
    window.removeEventListener(consentChanged, stop); window.removeEventListener('storage', storage);
  }
}
