import { useEffect, useState, useSyncExternalStore } from "react";
import { currentMessageCacheRevision, loadMessageSnapshot, subscribeMessageCache } from "@/lib/messageCache";
import type { WhisperMessage } from "@/lib/types";

/** Display-only fallback. It never becomes a successful server query, a cursor,
 * a delivery acknowledgement, or permission to access a protected card. */
export function useMessageSnapshot(owner: string, scope: string, active = true): WhisperMessage[] {
  const revision = useSyncExternalStore(subscribeMessageCache, currentMessageCacheRevision);
  const key = `${owner.toLowerCase()}|${scope}`;
  const [snapshot, setSnapshot] = useState<{ key: string; revision: string; rows: WhisperMessage[] }>();
  useEffect(() => {
    if (!owner || !active) return;
    const abort = new AbortController();
    void loadMessageSnapshot(owner, scope, abort.signal).then(rows => {
      if (!abort.signal.aborted && revision === currentMessageCacheRevision()) setSnapshot({ key, revision, rows });
    });
    return () => abort.abort();
  }, [owner, scope, active, key, revision]);
  return active && snapshot?.key === key && snapshot.revision === revision ? snapshot.rows : [];
}
