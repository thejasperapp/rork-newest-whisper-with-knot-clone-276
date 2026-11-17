// A deletion is one immutable key per account/conversation, not a shared array.
// Concurrent tabs cannot overwrite each other's tombstones. Acknowledgments are
// backend-qualified: deleting on the old store never acknowledges the new one.
export { knotBackendIdentity as knotHistoryBackend } from '@/lib/knotBackend';
import { knotBackendIdentity as knotHistoryBackend } from '@/lib/knotBackend';
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
// Older browsers created local-only IDs with Date.now() and base-36 randomness.
// Retain their deletion evidence, but never use them as server route identities.
const legacyLocalID = /^[0-9]{1,16}-[a-z0-9]{0,16}$/;
export const isKnotServerConversationID = (id: string): boolean => uuid.test(id.toLowerCase());
const supportedID = (id: string) => isKnotServerConversationID(id) || legacyLocalID.test(id);
const prefix = (owner: string) => `knot-history-deletion-v2:${owner.toLowerCase()}:`;
const ackKey = (owner: string, id: string) => `knot-history-delete-ack-v2:${knotHistoryBackend}:${owner.toLowerCase()}:${id}`;
const legacyDeletedKey = (owner: string) => `knot-history-deleted:${owner.toLowerCase()}`;
const legacyPendingKey = (owner: string) => `knot-history-pending-delete:${owner.toLowerCase()}`;

function legacyIDs(key: string): string[] {
  const raw = localStorage.getItem(key);
  if (raw === null) return [];
  const parsed: unknown = JSON.parse(raw);
  if (!Array.isArray(parsed) || parsed.some(id => typeof id !== 'string' || !supportedID(id.toLowerCase()))) throw new Error('Chat deletion records could not be read.');
  return (parsed as string[]).map(id => id.toLowerCase());
}

/** Strict on storage/corruption failures: an unread queue must never authorize
 * uploads, a successful deletion, or overwriting the retained history. */
export function readKnotDeletedChats(owner: string): Set<string> {
  const ids = new Set([...legacyIDs(legacyDeletedKey(owner)), ...legacyIDs(legacyPendingKey(owner))]);
  const start = prefix(owner);
  for (let index = 0; index < localStorage.length; index++) {
    const key = localStorage.key(index);
    if (!key?.startsWith(start)) continue;
    const id = key.slice(start.length);
    if (!supportedID(id) || localStorage.getItem(key) !== '1') throw new Error('Chat deletion records could not be read.');
    ids.add(id);
  }
  return ids;
}

export function pendingKnotDeletions(owner: string): Set<string> {
  return new Set([...readKnotDeletedChats(owner)].filter(id => isKnotServerConversationID(id) && localStorage.getItem(ackKey(owner, id)) !== '1'));
}

export function recordKnotDeletion(owner: string, id: string, remote = false): void {
  id = id.toLowerCase();
  if (!uuid.test(owner.toLowerCase()) || !supportedID(id) || (remote && !isKnotServerConversationID(id))) throw new Error('This conversation could not be deleted.');
  // Check surviving legacy queues before changing anything. Leave them intact;
  // no migration marker or stale array write can drop another tab's deletion.
  readKnotDeletedChats(owner);
  localStorage.setItem(prefix(owner) + id, '1');
  if (remote) acknowledgeKnotDeletion(owner, id);
}

export function acknowledgeKnotDeletion(owner: string, id: string): void {
  id = id.toLowerCase();
  if (!uuid.test(id) || !readKnotDeletedChats(owner).has(id)) throw new Error('Chat deletion could not be confirmed.');
  localStorage.setItem(ackKey(owner, id), '1');
}

export function isKnotDeletionStorageKey(owner: string, key: string | null): boolean {
  return key === null || key === legacyDeletedKey(owner) || key === legacyPendingKey(owner) || key.startsWith(prefix(owner));
}
