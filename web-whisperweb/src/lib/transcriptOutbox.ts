import { z } from 'zod';
import { supabase } from './supabase';

const entrySchema = z.object({ id: z.string().uuid(), meeting_id: z.string().uuid(), user_id: z.string().uuid(), username: z.string(), text: z.string(), spoken_at: z.string() });
type Entry = z.infer<typeof entrySchema>;
const memory = new Map<string, Entry>();
const flights = new Map<string, Promise<void>>();
function database(): Promise<IDBDatabase> {
  return new Promise((resolve, reject) => { const request = indexedDB.open('whisper-transcript-outbox-v1', 1); request.onupgradeneeded = () => { const store = request.result.createObjectStore('speech', { keyPath: 'id' }); store.createIndex('owner', 'user_id'); }; request.onsuccess = () => resolve(request.result); request.onerror = () => reject(new Error('Transcript recovery storage unavailable.')); });
}
async function entries(owner: string): Promise<Entry[]> {
  const db = await database();
  try { return await new Promise((resolve, reject) => { const tx = db.transaction('speech', 'readonly'), request = tx.objectStore('speech').index('owner').getAll(owner); request.onsuccess = () => { try { resolve(z.array(entrySchema).parse(request.result)); } catch { reject(new Error('Transcript recovery could not be verified.')); } }; request.onerror = () => reject(request.error); }); } finally { db.close(); }
}
async function write(entry: Entry, remove = false): Promise<void> {
  const db = await database();
  try { await new Promise<void>((resolve, reject) => { const tx = db.transaction('speech', 'readwrite'); if (remove) tx.objectStore('speech').delete(entry.id); else tx.objectStore('speech').put(entry); tx.oncomplete = () => resolve(); tx.onerror = () => reject(tx.error); tx.onabort = () => reject(tx.error); }); } finally { db.close(); }
}
/** Each phrase gets its identity and capture time before asynchronous storage or upload. */
export async function retainTranscript(input: { meetingId: string; userId: string; username: string; text: string; spokenAt?: string }): Promise<void> {
  const entry = entrySchema.parse({ id: crypto.randomUUID(), meeting_id: input.meetingId, user_id: input.userId, username: input.username, text: input.text.trim(), spoken_at: input.spokenAt && Number.isFinite(Date.parse(input.spokenAt)) ? input.spokenAt : new Date().toISOString() });
  memory.set(entry.id, entry);
  await write(entry); memory.delete(entry.id);
}
/** Atomic per-segment deletion cannot erase concurrent writing from another tab. */
export function flushTranscriptOutbox(owner: string): Promise<void> {
  const existing = flights.get(owner); if (existing) return existing;
  const task = (async (): Promise<void> => {
    let failed = false;
    const attempted = new Set<string>();
    for (;;) {
      const { data } = await supabase.auth.getSession();
      if (data.session?.user.id !== owner) return;
      const volatile = [...memory.values()].filter((entry) => entry.user_id === owner);
      let stored: Entry[] = [];
      try { stored = await entries(owner); } catch { failed = true; }
      const storedIDs = new Set(stored.map((entry) => entry.id));
      const rows = [...new Map([...stored, ...volatile].map((entry) => [entry.id, entry])).values()].filter((entry) => !attempted.has(entry.id));
      if (!rows.length) break;
      for (const entry of rows) {
        attempted.add(entry.id);
        const session = await supabase.auth.getSession(); if (session.data.session?.user.id !== owner) return;
        try {
          const { error } = await supabase.from('whisper_meeting_transcripts').insert(entry).abortSignal(AbortSignal.timeout(15000));
          if (error?.code === '23505') {
            const saved = await supabase.from('whisper_meeting_transcripts').select('id,user_id,meeting_id,text').eq('id', entry.id).eq('user_id', owner).abortSignal(AbortSignal.timeout(15000)).maybeSingle();
            if (saved.error || saved.data?.text !== entry.text || saved.data?.meeting_id !== entry.meeting_id) throw new Error('Speech could not be verified.');
          } else if (error) throw error;
          if (storedIDs.has(entry.id)) await write(entry, true);
          memory.delete(entry.id);
        } catch { failed = true; }
      }
    }
    if (failed) throw new Error('Transcript recovery needs attention. Some speech may still be waiting to save, or this browser’s recovery storage is unavailable. Keep the call open and retry.');
  })().finally(() => { flights.delete(owner); });
  flights.set(owner, task); return task;
}
