import { validKnotReaction, reconcileKnotReaction, type KnotReaction } from '@/lib/knotReactions';
export { normalizedKnotReaction, confirmedKnotReaction } from '@/lib/knotReactions';
import { groupThemeSession } from '@/lib/groupThemeSession';
import { knotBackendOrigin } from '@/lib/knotBackend';
import { acknowledgeKnotDeletion, isKnotServerConversationID, knotHistoryBackend, pendingKnotDeletions, readKnotDeletedChats, recordKnotDeletion } from '@/lib/knotHistoryDeletions';
import { loadEmberHistory, persistHistory, type EmberConversation, type EmberHistoryMessage } from '@/lib/emberBrain';

export const knotNames = { main: 'Knot', writer: 'Writing Knot', researcher: 'Research Knot', planner: 'Planning Knot', social: 'Community Knot' } as const;
export type KnotBot = keyof typeof knotNames;
// This clone only; the inherited hosted proxy is not assumed to exist.
const base = knotBackendOrigin;
const backendIdentity = knotHistoryBackend;
export const consentChanged = 'knot-consent-changed';
const key = (owner: string) => `knot_ai_consent_v3:${owner.toLowerCase()}`;
export const knotAllowed = (owner: string): boolean => { try { return !!owner && localStorage.getItem(key(owner)) === 'true'; } catch { return false; } };
export const knotProfileAllowed = (owner: string): boolean => { try { return knotAllowed(owner) && localStorage.getItem(`${key(owner)}:profile`) === 'true'; } catch { return false; } };
export function setKnotConsent(owner: string, allowed: boolean, profile = false): void {
  localStorage.setItem(key(owner), String(allowed));
  localStorage.setItem(`${key(owner)}:profile`, String(allowed && profile));
  window.dispatchEvent(new Event(consentChanged));
}
export async function knotRequest<T>(owner: string, path: string, method = 'GET', body?: unknown, signal?: AbortSignal): Promise<T> {
  const auth = await groupThemeSession(owner);
  try {
    auth.check();
    const response = await fetch(base + path, { method, redirect: 'error', headers: { 'Content-Type': 'application/json', 'X-Whisper-Authorization': `Bearer ${auth.token}` }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.any([auth.signal, AbortSignal.timeout(20000), ...(signal ? [signal] : [])]) });
    auth.check();
    if (!response.ok) { await response.body?.cancel(); throw new KnotHTTPError(response.status); }
    const data = await response.text(); auth.check();
    if (data.length > 1000000) throw new Error('Response too large');
    return JSON.parse(data) as T;
  } finally { auth.dispose(); }
}
export class KnotHTTPError extends Error { constructor(public status: number) { super('Knot could not complete this request.'); } }

const activities: Record<string, string> = {
  accepted: 'Request received', connection_check_started: 'Checking workspace connection…', connection_verified: 'Workspace connection verified', work_routing: 'Choosing tools for your request…',
  search_requested: 'Requesting web sources…', search_complete: 'Reading web sources…', search_unavailable: 'Web sources unavailable',
  calculation_started: 'Calculating…', calculation_complete: 'Calculation returned', tool_unavailable: 'Tool unavailable',
  shell_review_ready: 'Workspace command prepared', generating: 'Connected to Knot', finalizing: 'Formatting reply…',
  skill_read_started: 'Reading the relevant skill…', skill_read_complete: 'Skill loaded',
  reaction_guide_cached: 'Using session reaction guidance', reaction_guide_default: 'Using default reaction guidance',
  reaction_unavailable: 'Reaction not confirmed', reaction_unsupported: 'Reactions unavailable on this client',
  tool_selection_retry: 'Repairing tool selection; nothing dispatched', tool_selection_rejected: 'Tool selection rejected; nothing dispatched',
  tool_selection_unavailable: 'Tool selection unavailable', tool_request_rejected: 'Tool request rejected before execution',
  document_proof_started: 'Preparing final document checks…', document_proof_complete: 'Final-file checks passed; file captured', document_proof_unavailable: 'Document checks incomplete; file not delivered',
  document_review_started: 'Reviewing the captured document…', document_review_complete: 'File captured; visual AI review passed', document_review_unavailable: 'Document capture or review incomplete',
  browser_read_started: 'Reading browser…', browser_read_complete: 'Browser observation returned', browser_read_unavailable: 'Browser observation unavailable',
};
export async function knotStream(input: { owner: string; bot: KnotBot; conversationID: string; sourceMessageID?: string; sourceCreatedAt?: number; onReaction: (reaction: KnotReaction) => void; message: string; context: string; history: { role: 'user' | 'assistant'; content: string }[]; signal: AbortSignal; check: () => void; onActivity: (text: string) => void; onText: (text: string) => void }): Promise<string> {
  if (!knotAllowed(input.owner)) throw new Error('Choose whether to share with Knot first.');
  const auth = await groupThemeSession(input.owner), withdrawal = new AbortController();
  const stop = () => withdrawal.abort();
  window.addEventListener(consentChanged, stop);
  const storedConsentChanged = (event: StorageEvent) => { if (event.key === null || event.key === key(input.owner) || event.key === `${key(input.owner)}:profile`) stop(); };
  window.addEventListener('storage', storedConsentChanged);
  const signal = AbortSignal.any([input.signal, auth.signal, withdrawal.signal, AbortSignal.timeout(65000)]);
  const check = () => { auth.check(); input.check(); if (signal.aborted || !knotAllowed(input.owner)) throw new DOMException('Stopped', 'AbortError'); };
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  try {
    check();
    const requestID = crypto.randomUUID();
    const response = await fetch(base + '/knot/chat/stream', {
      method: 'POST', redirect: 'error', headers: { 'Content-Type': 'application/json', Accept: 'text/event-stream', 'X-Whisper-Authorization': `Bearer ${auth.token}` }, signal,
      body: JSON.stringify({ requestID, ...(/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(input.sourceMessageID ?? '') ? { sourceMessageID: input.sourceMessageID, sourceCreatedAt: input.sourceCreatedAt, reactionVersion: 'knot_reactions_v1' } : {}), consentVersion: 'knot_ai_consent_v3', bot: input.bot, conversationID: input.conversationID, message: input.message, healthContext: input.context.slice(0,100000), history: input.history.slice(-10).map(m => ({ ...m, content: m.content.slice(0,16000) })), sharedConversation: false, isWebQuery: false, timezone: Intl.DateTimeFormat().resolvedOptions().timeZone }),
    });
    check();
    if (!response.ok || !response.headers.get('Content-Type')?.includes('text/event-stream') || !response.body) { await response.body?.cancel(); throw new Error('Live connection unavailable'); }
    reader = response.body.getReader();
    const decoder = new TextDecoder(); let buffer = '', data: string[] = [], total = 0, sequence = 0, text = '';
    for (;;) {
      const part = await reader.read(); check(); if (part.done) break;
      total += part.value.byteLength; if (total > 1000000) throw new Error('Response too large');
      buffer += decoder.decode(part.value, { stream: true });
      let at: number;
      while ((at = buffer.indexOf('\n')) >= 0) {
        const line = buffer.slice(0,at).replace(/\r$/, ''); buffer = buffer.slice(at + 1);
        if (!line && data.length) {
          const event = JSON.parse(data.join('\n')) as { v: number; requestID: string; sequence: number; type: string; text?: string; reply?: string; reaction?: unknown; reason?: string }; data = [];
          if (event.v !== 1 || event.requestID !== requestID || event.sequence !== sequence + 1) throw new Error('Interrupted response');
          sequence = event.sequence;
          if (event.type === 'complete' && event.reply?.trim()) { check(); return event.reply; }
          if (event.type === 'rejected' || event.type === 'error') {
            if (event.reason === 'upstream_quota_exhausted') throw new Error('AI replies are unavailable because the response service’s quota is exhausted. Your message is kept; nothing will be retried automatically.');
            if (event.reason === 'upstream_rate_limited') throw new Error('The response service is busy. Please wait before trying again; recorded work will not be replayed automatically.');
            throw new Error('Live connection unavailable');
          }
          if (event.type === 'reaction') {
            if (!validKnotReaction(event.reaction) || event.reaction.messageID !== input.sourceMessageID) throw new Error('Invalid reaction event');
            check(); input.onReaction(event.reaction);
          } else if (event.type === 'text') {
            if (typeof event.text !== 'string') throw new Error('Interrupted response');
            text += event.text; if (text.length > 128000) throw new Error('Response too large');
            // Never show partial protocol or parse provisional text into proposals.
            input.onText(text.split(/`|<|sandbox:/i)[0]); input.onActivity('Receiving reply…');
          } else if (activities[event.type]) input.onActivity(activities[event.type]);
          else throw new Error('Unsupported response event');
        } else if (line.startsWith('data:')) data.push(line.slice(5).replace(/^ /,''));
      }
      if (buffer.length > 300000 || data.join('\n').length > 300000) throw new Error('Response too large');
    }
    throw new Error('Interrupted response');
  } finally { await reader?.cancel().catch(() => undefined); reader?.releaseLock(); auth.dispose(); window.removeEventListener(consentChanged, stop); window.removeEventListener('storage', storedConsentChanged); }
}

export function parseKnotReply(reply: string, bot: KnotBot, conversationID: string): { text: string; metadata: Partial<EmberHistoryMessage> } {
  let metadata: Partial<EmberHistoryMessage> = {};
  const fence = /```message\s*\n?([\s\S]*?)```/i.exec(reply);
  if (fence) {
    try {
      const raw = JSON.parse(fence[1]) as Record<string, unknown>;
      if (raw.shellProposal && typeof raw.shellProposal === 'object') metadata.shell = { spec: raw.shellProposal, state: 'expired', continued: false };
      if (raw.responsibility && typeof raw.responsibility === 'object') metadata.responsibility = { id: crypto.randomUUID(), spec: raw.responsibility, botID: bot, conversationID, createdAt: Date.now() / 1000 - 978307200, state: 'expired' };
      // These remain review-only on web. No model-selected action is auto-opened or dispatched.
      if (Array.isArray(raw.actions) || Array.isArray(raw.requests)) metadata.webReview = true;
    } catch { /* Malformed metadata never becomes controls. */ }
  }
  return { text: reply.replace(/```message[\s\S]*?(?:```|$)/gi, '').trim(), metadata };
}

export const deletedKnotChats = readKnotDeletedChats;
export const rememberKnotDeletion = recordKnotDeletion;
const flights = new Map<string, Promise<EmberConversation[]>>();
const again = new Set<string>();
const versions = new Map<string, number>();
export const historyChanged = 'knot-history-changed';
function storeKnotHistory(chats: EmberConversation[], owner: string): void {
  if (!persistHistory(chats, owner)) throw new Error('Chat history could not be saved in this browser.');
}
export function syncKnotHistory(owner: string): Promise<EmberConversation[]> {
  if (!owner) return Promise.resolve([]);
  const existing = flights.get(owner); if (existing) { again.add(owner); return existing; }
  const work = syncHistory(owner).finally(() => {
    flights.delete(owner);
    if (again.delete(owner)) void syncKnotHistory(owner).catch(() => undefined);
  }); flights.set(owner, work); return work;
}
async function syncHistory(owner: string): Promise<EmberConversation[]> {
  const auth = await groupThemeSession(owner);
  try {
    auth.check();
    // Leave old migration/ack/cursor keys intact. Switching authority is not
    // permission to copy retained chats or replay their deletion queue.
    const backendKey = `knot-history-ready-v2:${backendIdentity}:${owner.toLowerCase()}`;
    if (localStorage.getItem(backendKey) !== backendIdentity) {
      const deleted = deletedKnotChats(owner);
      if (loadEmberHistory(owner).length || deleted.size) {
        throw new Error('Your saved chats are safe in this browser. Moving them to the updated service is not enabled yet.');
      }
      localStorage.setItem(backendKey, backendIdentity);
    }
    const request = async <T>(path: string, method = 'GET', body?: unknown): Promise<T> => { auth.check(); const data = await knotRequest<T>(owner, '/knot/conversations' + path, method, body, auth.signal); auth.check(); return data; };
    for (const id of pendingKnotDeletions(owner)) {
      await request('/' + id, 'DELETE');
      acknowledgeKnotDeletion(owner, id);
    }
    type Header = { id: string; title: string; botID: string; updatedAt: number; deleted: boolean };
    const headers: Header[] = []; let after: string | null = null;
    do { const page = await request<{ conversations: Header[]; next: string | null }>(after ? '?after=' + after : ''); headers.push(...page.conversations); after = page.next; if (headers.length > 10000) throw new Error('History unavailable'); } while (after);
    for (const header of headers.filter(h => h.deleted)) rememberKnotDeletion(owner, header.id, true);
    let syncIncomplete = false;
    try { await syncKnotDeliveries(owner, auth.signal, auth.check); }
    catch { auth.check(); syncIncomplete = true; }
    for (const header of headers.filter(h => !h.deleted).sort((a,b) => b.updatedAt - a.updatedAt).slice(0,40)) {
      if (deletedKnotChats(owner).has(header.id)) continue;
      if (versions.get(`${owner}:${header.id}`) === header.updatedAt && loadEmberHistory(owner).some(c => c.id === header.id)) continue;
      let cursor: { after: number; afterID: string } | null = null; const messages: EmberHistoryMessage[] = [];
      try {
        do {
          const query = cursor ? `?after=${cursor.after}&afterID=${cursor.afterID}` : '';
          const page = await request<{ messages: EmberHistoryMessage[]; next: typeof cursor }>('/' + header.id + query);
          messages.push(...page.messages); cursor = page.next; if (messages.length > 20000) throw new Error('History unavailable');
        } while (cursor);
      } catch (error) {
        auth.check();
        if (error instanceof KnotHTTPError && error.status === 410) rememberKnotDeletion(owner, header.id, true);
        else syncIncomplete = true;
        // Keep the last good snapshot/version. An unavailable remote thread
        // must not prevent dirty local messages from reaching the server.
        continue;
      }
      auth.check();
      const current = loadEmberHistory(owner), local = current.find(c => c.id.toLowerCase() === header.id);
      const merged = mergeKnotMessages(messages, local?.messages ?? []);
      const conversation: EmberConversation = { id: header.id, _syncDirty: local?._syncDirty, title: local?._syncDirty ? local.title : header.title, botID: header.botID, updatedAt: Math.max(header.updatedAt, local?.updatedAt ?? 0), messages: merged };
      if (!deletedKnotChats(owner).has(header.id)) {
        storeKnotHistory([...current.filter(c => c.id.toLowerCase() !== header.id), conversation], owner);
        versions.set(`${owner}:${header.id}`, header.updatedAt);
      }
    }
    // Historical timestamp/random IDs stay local; the server only accepts UUIDs.
    // Do not let one legacy chat block valid history or send an invalid route.
    for (const chat of loadEmberHistory(owner).filter(c => c._syncDirty && isKnotServerConversationID(c.id))) {
      if (deletedKnotChats(owner).has(chat.id.toLowerCase())) continue;
      try {
        for (let start = 0; start < chat.messages.length; start++) {
          if (deletedKnotChats(owner).has(chat.id.toLowerCase())) break;
          const messages = chat.messages.slice(start,start+1);
          if (new TextEncoder().encode(JSON.stringify(messages[0])).byteLength > 100000) throw new Error('A message is too large to sync.');
          await request('/' + chat.id.toLowerCase(), 'POST', { botID: chat.botID ?? 'main', title: chat.title, messages });
        }
      } catch (error) {
        auth.check();
        if (error instanceof KnotHTTPError && error.status === 410) rememberKnotDeletion(owner, chat.id, true);
        else syncIncomplete = true;
        // Retain dirty state until every message in this snapshot is accepted.
        // Continue other uploads rather than letting one thread block the account.
        continue;
      }
      const current = loadEmberHistory(owner);
      if (JSON.stringify(current.find(c => c.id === chat.id)) === JSON.stringify(chat)) storeKnotHistory(current.map(c => c.id === chat.id ? { ...c, _syncDirty: false } : c), owner);
    }
    auth.check();
    const result = loadEmberHistory(owner).filter(c => !deletedKnotChats(owner).has(c.id.toLowerCase())); storeKnotHistory(result, owner);
    if (syncIncomplete) throw new Error('Some chats have not synced across devices yet.');
    return result;
  } finally {
    try { auth.check(); window.dispatchEvent(new Event(historyChanged)); } catch { /* Never publish an outgoing account. */ }
    auth.dispose();
  }
}
export interface KnotResponsibility {
  id: string; bot: KnotBot; conversationID: string; title: string; instruction: string;
  state: string; lastOutcome: string; nextRunAt: number; endsAt: number;
  timezone: string; minIntervalMinutes: number; maxIntervalMinutes: number; quietStart: number; quietEnd: number;
}
export async function listKnotResponsibilities(owner: string): Promise<KnotResponsibility[]> {
  return (await knotRequest<{ rules: KnotResponsibility[] }>(owner, '/knot/background')).rules;
}
export async function manageKnotResponsibility(owner: string, id: string, action: 'pause' | 'delete'): Promise<void> {
  if (!/^[0-9a-f-]{36}$/i.test(id)) throw new Error('Invalid responsibility');
  await knotRequest(owner, '/knot/background/' + id + (action === 'pause' ? '/pause' : ''), action === 'pause' ? 'POST' : 'DELETE');
}
async function syncKnotDeliveries(owner: string, signal: AbortSignal, check: () => void): Promise<void> {
  // Never apply another backend's sequence to this store.
  const cursorKey = `knot-background-cursor:${backendIdentity}:${owner.toLowerCase()}`;
  let cursor = Number(localStorage.getItem(cursorKey) ?? '0');
  if (!Number.isSafeInteger(cursor) || cursor < 0) cursor = 0;
  type Delivery = { sequence: number; id: string; bot: KnotBot; conversationID: string; text: string; createdAt: number };
  for (let count = 0; count < 8; count++) {
    check();
    const page = await knotRequest<{ messages: Delivery[]; next: number }>(owner, `/knot/background/messages?after=${cursor}`, 'GET', undefined, signal);
    check();
    if (!Number.isSafeInteger(page.next) || page.next < cursor || !page.messages.every(m => m.sequence > cursor && m.sequence <= page.next)) throw new Error('Updates could not sync.');
    for (const delivery of page.messages) {
      const id = delivery.conversationID.toLowerCase();
      if (deletedKnotChats(owner).has(id) || !(delivery.bot in knotNames)) continue;
      const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode('background:' + delivery.id));
      check();
      const hex = Array.from(new Uint8Array(digest).slice(0,16), b => b.toString(16).padStart(2,'0')).join('');
      const messageID = `${hex.slice(0,8)}-${hex.slice(8,12)}-${hex.slice(12,16)}-${hex.slice(16,20)}-${hex.slice(20)}`;
      const chats = loadEmberHistory(owner), old = chats.find(c => c.id === id);
      if (old && (old.botID ?? 'main') !== delivery.bot) continue;
      if (old?.messages.some(m => m.backgroundMessageID === delivery.id)) continue;
      const message: EmberHistoryMessage = { id: messageID, role: 'ember', text: delivery.text, createdAt: delivery.createdAt, modifiedAt: delivery.createdAt, backgroundMessageID: delivery.id };
      const chat: EmberConversation = { id, title: old?.title ?? `Updates from ${knotNames[delivery.bot]}`, botID: delivery.bot, updatedAt: Math.max(old?.updatedAt ?? 0, delivery.createdAt), messages: mergeKnotMessages(old?.messages ?? [], [message]), _syncDirty: true };
      storeKnotHistory([...chats.filter(c => c.id !== id), chat], owner);
    }
    check(); cursor = page.next; localStorage.setItem(cursorKey, String(cursor));
    if (page.messages.length < 50) break;
  }
}
export function mergeKnotMessages(first: EmberHistoryMessage[], second: EmberHistoryMessage[]): EmberHistoryMessage[] {
  const map = new Map<string, EmberHistoryMessage>();
  for (const message of [...first,...second]) {
    const identity = message.backgroundMessageID ? `background:${String(message.backgroundMessageID)}` : message.id;
    if (!identity) continue;
    const old = map.get(identity);
    map.set(identity, !old || (message.modifiedAt ?? 0) >= (old.modifiedAt ?? 0) ? reconcileKnotReaction(message, old) : reconcileKnotReaction(old, message));
  }
  return [...map.values()].sort((a,b) => (a.createdAt ?? 0) - (b.createdAt ?? 0) || (a.id ?? '').localeCompare(b.id ?? ''));
}
