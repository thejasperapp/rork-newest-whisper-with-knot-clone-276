import { useState } from "react";
import { Link } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import { useAuth } from "@/hooks/useAuth";
import { safetyRequest } from "@/lib/safetyReview";

export function DecisionInboxNotice() {
  const { user } = useAuth();
  return user ? <AccountNotice key={user.id} owner={user.id} /> : null;
}
function AccountNotice({ owner }: { owner: string }) {
  const storageKey = `whisper:decision-notice:${owner}`;
  const [seen, setSeen] = useState(() => { try { return localStorage.getItem(storageKey); } catch { return null; } });
  const query = useQuery({ queryKey: ["decision-notice", owner], gcTime: 0, retry: false, refetchInterval: 60000,
    queryFn: ({ signal }) => safetyRequest<{ id: string; updated_at: string }[]>(owner, `whisper_corrections?select=id,updated_at&author_id=eq.${owner}&order=updated_at.desc&limit=1`, undefined, signal),
  });
  const latest = query.data?.[0];
  const version = latest ? `${latest.id}:${latest.updated_at}` : null;
  if (!version || version === seen) return null;
  const acknowledge = () => { setSeen(version); try { localStorage.setItem(storageKey, version); } catch { /* The persistent decisions page remains available. */ } };
  return <aside aria-label="Private decision update" className="m-3 flex items-start justify-between gap-3 rounded-xl border border-border bg-card p-3 text-sm">
    <div><p className="font-semibold">A decision on your post has been updated</p><Link to="/settings#decisions" onClick={acknowledge} className="inline-flex min-h-11 items-center underline">View private decisions & appeals</Link></div>
    <button aria-label="Dismiss decision alert; decisions remain in Settings" onClick={acknowledge} className="min-h-11 px-2">Dismiss</button>
  </aside>;
}
