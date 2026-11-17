import * as Y from 'yjs';
import { checkedSharedJSON, seedSharedDocument, encodeSharedBytes } from './sharedNotesDocument';

/** Converts an authorized server-returned seed to the initial update; performs no network requests.
 * Persist these exact bytes and an operation UUID before sending initialize. Never reseed seq > 0.
 */
export function seedToUpdate(seed: unknown): string {
 const content = checkedSharedJSON(seed);
 if (content.type !== 'doc') throw new Error('Expected a document seed.');
 const doc = seedSharedDocument(content);
 try {
  const update = encodeSharedBytes(Y.encodeStateAsUpdate(doc));
  if (update.length > 1_500_000) throw new Error('Document update too large.');
  return update;
 } finally { doc.destroy(); }
}
