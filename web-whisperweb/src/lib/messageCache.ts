import { supabase } from "./supabase";
import { MessageSnapshotStore } from "./messageSnapshotStore";
import type { WhisperMessage } from "./types";
import { conversationThreadId } from "./conversationIdentity";

const store = new MessageSnapshotStore();
let activeOwner: string | null = null;
let revision = 0;
const listeners = new Set<() => void>();
const epochKey = (owner: string) => `whisper.message-cache-epoch.v1:${owner}`;
function storageEpoch(): string {
  try { return activeOwner ? localStorage.getItem(epochKey(activeOwner)) ?? "initial" : "signed-out"; }
  catch { return "unavailable"; }
}
function bumpEpoch(owner: string): void {
  try { localStorage.setItem(epochKey(owner), crypto.randomUUID()); } catch { /* Disable persistence below. */ }
}
function invalidateRevision(persist = true): void {
  revision++;
  if (persist && activeOwner) bumpEpoch(activeOwner);
  listeners.forEach(listener => listener());
}
export function subscribeMessageCache(listener: () => void): () => void {
  listeners.add(listener);
  const changed = (event: StorageEvent) => { if (activeOwner && (event.key === epochKey(activeOwner) || event.key === null)) listener(); };
  window.addEventListener("storage", changed);
  return () => { listeners.delete(listener); window.removeEventListener("storage", changed); };
}
export function currentMessageCacheRevision(): string { return `${revision}/${storageEpoch()}`; }

/** Called synchronously before the auth provider renders the incoming owner. */
export function setMessageCacheOwner(owner: string | null): void {
  const next = owner?.toLowerCase() ?? null;
  if (next === activeOwner) return;
  const outgoing = activeOwner;
  activeOwner = next; invalidateRevision(false);
  if (outgoing) { bumpEpoch(outgoing); void store.clear(outgoing); }
}
export async function clearMessageSnapshots(owner: string): Promise<boolean> {
  bumpEpoch(owner.toLowerCase());
  invalidateRevision();
  return store.clear(owner.toLowerCase());
}
export function invalidateMessageSnapshots(): void {
  invalidateRevision();
  if (activeOwner) void store.clear(activeOwner);
}
async function isCurrent(owner: string, expected: string, signal?: AbortSignal): Promise<boolean> {
  if (signal?.aborted || storageEpoch() === "unavailable" || activeOwner !== owner.toLowerCase() || currentMessageCacheRevision() !== expected) return false;
  const { data } = await supabase.auth.getSession();
  return !signal?.aborted && currentMessageCacheRevision() === expected && activeOwner === owner.toLowerCase()
    && data.session?.user.id.toLowerCase() === owner.toLowerCase();
}
async function mayRestore(owner: string, scope: string, expected: string, signal?: AbortSignal): Promise<boolean> {
  if (!await isCurrent(owner, expected, signal)) return false;
  if (!scope.startsWith("group:")) return true;
  let request = supabase.from("whisper_group_threads").select("owner_id,member_ids").eq("id", scope.slice(6)).limit(1);
  if (signal) request = request.abortSignal(signal);
  const { data, error } = await request;
  if (!await isCurrent(owner, expected, signal) || error) return false;
  const allowed = data?.some(row => row.owner_id.toLowerCase() === owner.toLowerCase()
    || row.member_ids?.some(id => id.toLowerCase() === owner.toLowerCase())) ?? false;
  if (!allowed) await clearMessageSnapshots(owner);
  return allowed;
}
async function conversationRows(rows: WhisperMessage[], owner: string, scope: string): Promise<WhisperMessage[]> {
  if (scope.startsWith("group:")) return rows;
  const [kind, peer] = scope.split(":");
  if (!peer || (kind !== "direct" && kind !== "dating")) return [];
  const datingID = await conversationThreadId(owner, peer, "dating");
  return rows.filter(row => kind === "dating" ? row.thread_id?.toLowerCase() === datingID : row.thread_id?.toLowerCase() !== datingID);
}
export async function loadMessageSnapshot(owner: string, scope: string, signal?: AbortSignal): Promise<WhisperMessage[]> {
  const expected = currentMessageCacheRevision();
  try {
    if (!await mayRestore(owner, scope, expected, signal)) return [];
    const rows = await conversationRows(await store.load(owner.toLowerCase(), scope, store.lease(owner.toLowerCase()), storageEpoch()), owner, scope);
    return await isCurrent(owner, expected, signal) ? rows : [];
  } catch { return []; }
}
export async function saveMessageSnapshot(owner: string, scope: string, rows: WhisperMessage[], expected: string, signal?: AbortSignal): Promise<void> {
  try {
    if (!await mayRestore(owner, scope, expected, signal)) return;
    const lease = store.lease(owner.toLowerCase());
    if (!await isCurrent(owner, expected, signal)) return;
    const retained = await conversationRows(rows, owner, scope);
    const epoch = storageEpoch();
    await store.save(retained, owner.toLowerCase(), scope, lease, () => !signal?.aborted
      && activeOwner === owner.toLowerCase() && currentMessageCacheRevision() === expected, epoch);
  } catch { /* Persistence cannot fail a successful server read. */ }
}
