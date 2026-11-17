import { useEffect } from 'react';
import { flushTranscriptOutbox } from '@/lib/transcriptOutbox';
import { useAuth } from "@/hooks/useAuth";
import { useNotebookSync } from "@/hooks/useNotebookSync";

/** Keeps the account's durable queue moving after Notebook navigation. */
export function NotebookSyncAgent(): JSX.Element | null {
  const { user } = useAuth();
  return user ? <AccountSync key={user.id} owner={user.id} /> : null;
}
function AccountSync({ owner }: { owner: string }): null {
  useNotebookSync(owner, null);
  useEffect(() => {
    const retry = (): void => { if (navigator.onLine) void flushTranscriptOutbox(owner).catch(() => undefined); };
    retry(); const timer = setInterval(retry, 20000); window.addEventListener('online', retry);
    return () => { clearInterval(timer); window.removeEventListener('online', retry); };
  }, [owner]);
  return null;
}
