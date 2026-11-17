import { useCallback, useEffect, useState } from 'react';
import { consentChanged, knotAllowed, type KnotBot } from '@/lib/knotService';
import { readKnotWorkspace, type KnotWorkspaceReplay } from '@/lib/knotWorkspace';

export function useKnotWorkspace(owner: string, bot: KnotBot, conversationID: string, enabled: boolean, observing: boolean) {
  const scope = `${owner}:${bot}:${conversationID}`;
  const [snapshot, setSnapshot] = useState<{ scope: string; replay: KnotWorkspaceReplay } | null>(null);
  const [issue, setIssue] = useState<{ scope: string; text: string } | null>(null);
  const [loading, setLoading] = useState(false);
  const [revision, setRevision] = useState(0);
  const refresh = useCallback(() => setRevision(value => value + 1), []);
  useEffect(() => {
    if (!enabled || !owner) { setLoading(false); return; }
    let disposed = false, busy = false;
    let controller: AbortController | null = null, timer: ReturnType<typeof setTimeout> | undefined;
    const load = async () => {
      if (disposed || busy || document.visibilityState === 'hidden' || !knotAllowed(owner)) return;
      busy = true; controller = new AbortController(); setLoading(true);
      try {
        const replay = await readKnotWorkspace(owner, 'events', bot, conversationID, controller.signal) as KnotWorkspaceReplay;
        if (disposed || controller.signal.aborted) return;
        setSnapshot({ scope, replay }); setIssue(null);
        const pending = replay.records.some(record => !record.result.terminationConfirmed && record.result.status !== 'awaiting_approval');
        if (observing && pending) timer = setTimeout(() => { void load(); }, 4000);
      } catch {
        if (!disposed && !controller.signal.aborted) setIssue({ scope, text: 'Couldn’t refresh Events. Nothing was run again.' });
      } finally { busy = false; if (!disposed) setLoading(false); }
    };
    const visible = () => {
      clearTimeout(timer);
      if (document.visibilityState === 'hidden') controller?.abort();
      else refresh();
    };
    const withdraw = () => { disposed = true; controller?.abort(); clearTimeout(timer); setSnapshot(null); setIssue(null); setLoading(false); refresh(); };
    const storage = (event: StorageEvent) => { if (event.key === null || event.key.startsWith(`knot_ai_consent_v3:${owner.toLowerCase()}`)) withdraw(); };
    document.addEventListener('visibilitychange', visible); window.addEventListener(consentChanged, withdraw); window.addEventListener('storage', storage);
    void load();
    return () => { disposed = true; controller?.abort(); clearTimeout(timer); document.removeEventListener('visibilitychange', visible); window.removeEventListener(consentChanged, withdraw); window.removeEventListener('storage', storage); };
  }, [owner, bot, conversationID, enabled, observing, scope, revision, refresh]);
  return { replay: snapshot?.scope === scope && knotAllowed(owner) ? snapshot.replay : null, issue: issue?.scope === scope ? issue.text : null, loading, refresh };
}
