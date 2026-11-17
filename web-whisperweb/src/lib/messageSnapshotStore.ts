import type { WhisperMessage } from "./types";
import { uniqueHistory } from "./messageHistory";

const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
interface Snapshot { key: string; owner: string; scope: string; epoch?: string; savedAt: number; accessedAt: number; bytes: number; rows: WhisperMessage[] }

/** Intentionally text-only. No signed links, embeds, call signals, pending
 * sends, attachment bytes or access-bearing card payloads enter IndexedDB. */
export function snapshotRows(rows: WhisperMessage[], owner: string, scope: string): WhisperMessage[] {
  if (!/^(direct|dating|group):[0-9a-f-]{36}$/.test(scope) || !uuid.test(scope.slice(scope.indexOf(":") + 1))) return [];
  const me = owner.toLowerCase();
  const eligible = rows.filter(row => {
    if (!uuid.test(row.id) || row.embed != null || ![row.from_user_id, row.to_user_id].some(id => id?.toLowerCase() === me)) return false;
    let text = row.body;
    if (scope.startsWith("group:")) {
      const wire = /^::wg-v1::([^:]+)::([\s\S]*?)::([\s\S]*)$/.exec(text);
      if (!wire || wire[1].toLowerCase() !== scope.slice(6)) return false;
      text = wire[3];
    } else {
      const peer = row.from_user_id.toLowerCase() === me ? row.to_user_id.toLowerCase() : row.from_user_id.toLowerCase();
      if (!scope.endsWith(`:${peer}`)) return false;
    }
    return !!text && new TextEncoder().encode(text).byteLength <= 32_768 && !text.includes("::") && !/https?:\/\//i.test(text);
  });
  // Project explicitly: server rows may contain media columns not represented
  // in the TypeScript interface. Never spread a raw database row onto disk.
  const textRows: WhisperMessage[] = eligible.map(row => ({ id: row.id,
    from_user_id: row.from_user_id, to_user_id: row.to_user_id,
    from_username: row.from_username, to_username: row.to_username, body: row.body,
    created_at: row.created_at, read_at: row.read_at,
    thread_id: row.thread_id, logical_group_message_id: row.logical_group_message_id }));
  const ordered = uniqueHistory([{ messages: textRows, next: null }]);
  if (!scope.startsWith("group:")) return ordered.slice(-100);
  // New-format logical IDs preserve complete fanout. Legacy copies use their
  // sender/body/10-second identity, matching the existing group collapse rule.
  const identity = (row: WhisperMessage) => `${row.from_user_id.toLowerCase()}:${row.logical_group_message_id ?? `${row.body}:${Math.floor(Date.parse(row.created_at ?? "") / 10_000)}`}`;
  const logical = new Map<string, WhisperMessage[]>();
  for (const row of ordered) {
    const id = identity(row);
    const copies = logical.get(id) ?? []; copies.push(row); logical.set(id, copies);
  }
  const selected = [...logical.values()].sort((a, b) => {
    const firstA = a[0], firstB = b[0];
    return Date.parse(firstA.created_at ?? "") - Date.parse(firstB.created_at ?? "") || firstA.id.localeCompare(firstB.id);
  }).slice(-100);
  return uniqueHistory([{ messages: selected.flat(), next: null }]);
}

/** Serialized IndexedDB operations, account-local byte ceiling and conversation
 * LRU. Browser quota/privacy-mode failures never fail the server conversation. */
export class MessageSnapshotStore {
  private tail: Promise<unknown> = Promise.resolve();
  private epochs = new Map<string, number>();
  constructor(private name = "whisper-message-snapshots-v1", private maximumBytes = 25 * 1024 * 1024) {}
  lease(owner: string): number { return this.epochs.get(owner) ?? 0; }
  private enqueue<T>(operation: () => Promise<T>): Promise<T> {
    const next = this.tail.then(operation, operation); this.tail = next.catch(() => undefined); return next;
  }
  private open(): Promise<IDBDatabase> {
    return new Promise((resolve, reject) => {
      const request = indexedDB.open(this.name, 1);
      request.onupgradeneeded = () => {
        const store = request.result.createObjectStore("snapshots", { keyPath: "key" });
        store.createIndex("owner", "owner");
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
      request.onblocked = () => reject(new Error("Storage unavailable"));
    });
  }
  private async transaction<T>(owner: string, update: (rows: Snapshot[], store: IDBObjectStore) => T): Promise<T> {
    const db = await this.open();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction("snapshots", "readwrite");
      const store = transaction.objectStore("snapshots");
      const request = store.index("owner").getAll(owner);
      let result: T;
      request.onsuccess = () => { try { result = update(request.result as Snapshot[], store); } catch { transaction.abort(); } };
      transaction.oncomplete = () => { db.close(); resolve(result); };
      transaction.onerror = transaction.onabort = () => { db.close(); reject(transaction.error ?? new Error("Storage unavailable")); };
    });
  }
  async load(owner: string, scope: string, lease = this.lease(owner), expectedEpoch?: string): Promise<WhisperMessage[]> {
    if (!uuid.test(owner)) return [];
    try {
      const result = await this.enqueue(() => this.transaction(owner, (rows, store) => {
        if (lease !== this.lease(owner)) return [];
        const row = rows.find(row => row.scope === scope);
        if (!row || (expectedEpoch !== undefined && row.epoch !== expectedEpoch) || row.bytes > this.maximumBytes || Date.now() - row.savedAt > 7 * 86_400_000 || row.savedAt > Date.now()) return [];
        store.put({ ...row, accessedAt: Date.now() });
        return snapshotRows(row.rows, owner, scope);
      }));
      return lease === this.lease(owner) ? result : [];
    } catch { return []; }
  }
  async save(rows: WhisperMessage[], owner: string, scope: string, lease = this.lease(owner), isCurrent: () => boolean = () => true, epoch?: string): Promise<void> {
    if (!uuid.test(owner)) return;
    const retained = snapshotRows(rows, owner, scope);
    const entry: Snapshot = { key: `${owner}|${scope}`, owner, scope, epoch, savedAt: Date.now(), accessedAt: Date.now(), bytes: 0, rows: retained };
    // Include metadata/keys in the accounted payload, not just message bodies.
    entry.bytes = new TextEncoder().encode(JSON.stringify(entry)).byteLength + 32;
    try {
      await this.enqueue(() => this.transaction(owner, (previous, store) => {
        if (lease !== this.lease(owner) || !isCurrent()) return;
        store.delete(entry.key);
        const all = previous.filter(row => row.key !== entry.key);
        if (retained.length && entry.bytes <= this.maximumBytes) { all.push(entry); store.put(entry); }
        all.sort((a, b) => a.accessedAt - b.accessedAt || a.savedAt - b.savedAt || a.key.localeCompare(b.key));
        let bytes = all.reduce((sum, row) => sum + row.bytes, 0), count = all.length;
        for (const old of all) {
          if (bytes <= this.maximumBytes && count <= 200) break;
          store.delete(old.key); bytes -= old.bytes; count--;
        }
      }));
    } catch { /* No cache is better than failing a confirmed message read. */ }
  }
  clear(owner: string): Promise<boolean> {
    this.epochs.set(owner, this.lease(owner) + 1);
    return this.enqueue(() => this.transaction(owner, (rows, store) => { rows.forEach(row => store.delete(row.key)); return true; })).catch(() => false);
  }
}
