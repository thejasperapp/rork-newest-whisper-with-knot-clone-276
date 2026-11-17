import { newNotebookDocument, notebookDocumentSchema, type NotebookDocument } from "./notebookDocument";

import type { NotebookCloudRow } from "./notebookSync";

type StoredDocument = { key: string; ownerId: string; document: NotebookDocument };
let database: Promise<IDBDatabase> | null = null;

function openDatabase(): Promise<IDBDatabase> {
  if (!database) {
    database = new Promise<IDBDatabase>((resolve, reject) => {
      if (typeof indexedDB === "undefined") { reject(new Error("This browser cannot save notebooks. Try a regular browser window.")); return; }
      const request = indexedDB.open("whisper-personal-notebook-v1", 1);
      request.onupgradeneeded = () => {
        const store = request.result.createObjectStore("documents", { keyPath: "key" });
        store.createIndex("ownerId", "ownerId");
      };
      request.onsuccess = () => { request.result.onversionchange = () => { request.result.close(); database = null; }; resolve(request.result); };
      request.onerror = () => reject(new Error("Notebook storage is unavailable. Your text has not been saved."));
      request.onblocked = () => reject(new Error("Close other Whisper tabs and try again to open your notebook."));
    }).catch((error: unknown) => { database = null; throw error; });
  }
  return database;
}

/** Lists only this account's browser-local notes, never shared meeting data. */
export async function listNotebookDocuments(ownerId: string, includeDeleted = false): Promise<NotebookDocument[]> {
  const db = await openDatabase();
  return new Promise((resolve, reject) => {
    const request = db.transaction("documents", "readonly").objectStore("documents").index("ownerId").getAll(ownerId);
    request.onsuccess = () => {
      try {
        const rows = request.result as StoredDocument[];
        const documents = rows.map((row) => notebookDocumentSchema.parse(row.document));
        if (documents.some((doc) => doc.ownerId !== ownerId)) throw new Error();
        resolve(documents.filter((doc) => includeDeleted || !doc.deletedAt).sort((a, b) => b.updatedAt.localeCompare(a.updatedAt)));
      } catch { reject(new Error("Some saved notes couldn't be read. They have not been removed or replaced.")); }
    };
    request.onerror = () => reject(new Error("Couldn't load this browser's notes. Try again."));
  });
}

/** Atomic compare-and-save prevents another tab from silently overwriting an entry. */
export async function saveNotebookDocument(input: NotebookDocument, assertCurrent: () => void): Promise<NotebookDocument> {
  const document = notebookDocumentSchema.parse(input);
  assertCurrent();
  const db = await openDatabase();
  assertCurrent();
  return new Promise((resolve, reject) => {
    const transaction = db.transaction("documents", "readwrite");
    const store = transaction.objectStore("documents");
    const key = `${document.ownerId}:${document.id}`;
    const request = store.get(key);
    let saved: NotebookDocument | null = null;
    let failure = "Couldn't save. Keep this note open and try again, or export a copy.";
    request.onsuccess = () => {
      try {
        assertCurrent();
        const existing = request.result as StoredDocument | undefined;
        if ((existing?.document.storageRevision ?? 0) !== document.storageRevision) {
          failure = "This note changed in another tab. Export your draft, then close and reopen it before editing.";
          transaction.abort(); return;
        }
        if (existing?.document.deletedAt) { failure = "This note was deleted. Recover your writing as a new copy."; transaction.abort(); return; }
        saved = { ...document, cloudRevision: existing?.document.cloudRevision ?? document.cloudRevision, syncedStorageRevision: existing?.document.syncedStorageRevision ?? document.syncedStorageRevision, syncEnabled: existing?.document.syncEnabled || document.syncEnabled, syncOperationId: crypto.randomUUID(), storageRevision: document.storageRevision + 1, updatedAt: new Date().toISOString() };
        store.put({ key, ownerId: document.ownerId, document: saved } satisfies StoredDocument);
      } catch { failure = "Your session changed. Reopen Notebook before saving."; transaction.abort(); }
    };
    transaction.oncomplete = () => { if (saved) { window.dispatchEvent(new Event("notebook-saved")); resolve(saved); } else reject(new Error(failure)); };
    transaction.onabort = transaction.onerror = () => reject(new Error(failure));
  });
}

/** Creates a stable recording note once. Serialized with normal writes/deletes; never replaces writing or a tombstone. */
export async function createNotebookDocumentIfAbsent(input: NotebookDocument, assertCurrent: () => void, origin: "recording" | "meeting" = "recording"): Promise<NotebookDocument> {
  const document = notebookDocumentSchema.parse(input);
  assertCurrent(); const db = await openDatabase(); assertCurrent();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("documents", "readwrite");
    const store = tx.objectStore("documents");
    const key = `${document.ownerId}:${document.id}`;
    const read = store.index("ownerId").getAll(document.ownerId);
    let result: NotebookDocument | null = null;
    let failure = origin === "meeting" ? "Couldn't add the meeting note. Retry; the archived original is unchanged." : "Recording saved, but its note could not be added. Retry from Notebook; the media is kept.";
    read.onsuccess = () => {
      try {
        assertCurrent();
        const rows = read.result as StoredDocument[];
        const existing = rows.find((row) => row.key === key);
        if (existing) {
          const note = notebookDocumentSchema.parse(existing.document);
          if (note.deletedAt) { failure = origin === "meeting" ? "Your private copy was deleted. The archived original is unchanged; create a separate note if needed." : "This recording's note was deleted. Its media is still available; create a separate note if needed."; tx.abort(); return; }
          if (note.ownerId !== document.ownerId || note.meetingId !== document.meetingId) { tx.abort(); return; }
          result = note; return;
        }
        if (rows.filter((row) => !row.document.deletedAt).length >= 200) { failure = origin === "meeting" ? "Notebook is full (200 notes); export and remove a note, then retry. The archived original is unchanged." : "Recording saved. Notebook is full (200 notes); export and remove a note, then retry."; tx.abort(); return; }
        result = { ...document, storageRevision: 1, syncOperationId: crypto.randomUUID() };
        store.add({ key, ownerId: document.ownerId, document: result } satisfies StoredDocument);
      } catch { tx.abort(); }
    };
    tx.oncomplete = () => result ? resolve(result) : reject(new Error(failure));
    tx.onabort = tx.onerror = () => reject(new Error(failure));
  });
}

/** Reconcile atomically. A concurrent editor always wins locally; conflicts retain both versions. */
export async function applyNotebookCloud(row: NotebookCloudRow, assertCurrent: () => void, sent?: NotebookDocument): Promise<number> {
  assertCurrent();
  if (row.document && (row.document.ownerId !== row.owner_id || row.document.id !== row.id)) throw new Error("Invalid notebook owner.");
  if (row.deleted !== (row.document === null)) throw new Error("Invalid notebook state.");
  if (sent && (sent.ownerId !== row.owner_id || sent.id !== row.id || sent.syncOperationId !== row.operation_id)) throw new Error("Could not verify sync acknowledgment.");
  const db = await openDatabase(); assertCurrent();
  return new Promise((resolve, reject) => {
    const tx = db.transaction("documents", "readwrite"); const store = tx.objectStore("documents");
    const key = `${row.owner_id}:${row.id}`; const read = store.get(key); let conflicts = 0;
    read.onsuccess = () => {
      try {
        assertCurrent(); const current = (read.result as StoredDocument | undefined)?.document;
        if ((current?.cloudRevision ?? 0) > row.revision) return;
        if (sent) {
          if (!current) return;
          store.put({ key, ownerId: row.owner_id, document: { ...current, cloudRevision: row.revision, syncedStorageRevision: sent.storageRevision } });
          return;
        }
        if (current && (current.cloudRevision ?? 0) === row.revision) return;
        if (current && current.syncOperationId === row.operation_id) {
          store.put({ key, ownerId: row.owner_id, document: { ...current, cloudRevision: row.revision, syncedStorageRevision: current.storageRevision } }); return;
        }
        if (current?.deletedAt && current.syncedStorageRevision !== current.storageRevision && row.document) {
          const copy = { ...row.document, id: crypto.randomUUID(), title: `Recovered remote edits · ${row.document.title || "Untitled note"}`.slice(0, 160), syncEnabled: false, isMeetingWriting: false, cloudRevision: undefined, syncedStorageRevision: undefined, syncOperationId: undefined, deletedAt: undefined, storageRevision: 1 };
          store.put({ key: `${row.owner_id}:${copy.id}`, ownerId: row.owner_id, document: copy }); conflicts = 1;
          store.put({ key, ownerId: row.owner_id, document: { ...current, cloudRevision: row.revision } }); return;
        }
        if (current && !current.deletedAt && current.syncedStorageRevision !== current.storageRevision) {
          const copy = { ...current, id: current.syncOperationId ?? crypto.randomUUID(), title: `Recovered edits · ${current.title || "Untitled note"}`.slice(0, 160), syncEnabled: false, isMeetingWriting: false, cloudRevision: undefined, syncedStorageRevision: undefined, syncOperationId: undefined, deletedAt: undefined, storageRevision: 1 };
          store.put({ key: `${row.owner_id}:${copy.id}`, ownerId: row.owner_id, document: copy }); conflicts = 1;
        }
        // Keep a lightweight local tombstone, preventing stale editors from resurrecting a deletion.
        const document = row.document ? { ...row.document, storageRevision: (current?.storageRevision ?? 0) + 1, syncEnabled: true, deletedAt: undefined } : { ...(current ?? { ...newNotebookDocument(row.owner_id), id: row.id }), title: "", folder: "", people: "", instructions: "", notes: "", transcript: "", enhancement: null, commitments: [], highlights: [], deletedAt: row.updated_at, syncEnabled: true, storageRevision: (current?.storageRevision ?? 0) + 1 };
        if (document) store.put({ key, ownerId: row.owner_id, document: { ...document, cloudRevision: row.revision, syncedStorageRevision: document.storageRevision, syncOperationId: row.operation_id } });
      } catch { tx.abort(); }
    };
    tx.oncomplete = () => resolve(conflicts); tx.onabort = tx.onerror = () => reject(new Error("Sync couldn't update local storage. Your writing was not replaced."));
  });
}

/** Explicit deletion queues an enabled entry's deletion for the other devices too. */
export async function deleteNotebookDocument(document: NotebookDocument, assertCurrent: () => void): Promise<void> {
  assertCurrent();
  const db = await openDatabase();
  assertCurrent();
  await new Promise<void>((resolve, reject) => {
    const transaction = db.transaction("documents", "readwrite");
    const store = transaction.objectStore("documents");
    const key = `${document.ownerId}:${document.id}`;
    const request = store.get(key);
    let failure = "Couldn't delete this note. Try again.";
    request.onsuccess = () => {
      try {
        assertCurrent();
        const existing = request.result as StoredDocument | undefined;
        if (existing && existing.document.storageRevision !== document.storageRevision) {
          failure = "This note changed in another tab. Refresh the notebook and review it before deleting.";
          transaction.abort(); return;
        }
        if (existing) {
          store.put({ ...existing, document: { ...existing.document, title: "", folder: "", people: "", instructions: "", notes: "", transcript: "", enhancement: null, commitments: [], highlights: [], deletedAt: new Date().toISOString(), syncOperationId: crypto.randomUUID(), storageRevision: existing.document.storageRevision + 1 } });
        } else store.delete(key);
      } catch { failure = "Your account changed. Reopen Notebook before deleting."; transaction.abort(); }
    };
    transaction.oncomplete = () => resolve();
    transaction.onabort = transaction.onerror = () => reject(new Error(failure));
  });
}
