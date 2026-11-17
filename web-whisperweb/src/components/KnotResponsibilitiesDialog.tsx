import { useCallback, useEffect, useRef, useState } from 'react';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { listKnotResponsibilities, manageKnotResponsibility, knotNames, type KnotBot, type KnotResponsibility } from '@/lib/knotService';

export function KnotResponsibilitiesDialog({ owner, bot, open, onClose }: { owner: string; bot: KnotBot; open: boolean; onClose: () => void }) {
  const [rules, setRules] = useState<KnotResponsibility[]>([]);
  const [loading, setLoading] = useState(false);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [deleting, setDeleting] = useState<string | null>(null);
  const epoch = useRef(0);
  const refresh = useCallback(async () => {
    const lease = ++epoch.current; setLoading(true);
    try {
      const result = await listKnotResponsibilities(owner);
      if (lease !== epoch.current) return;
      setRules(result); setError(null);
    } catch {
      if (lease === epoch.current) setError('Responsibilities couldn’t refresh. Your last confirmed rules are still shown.');
    } finally { if (lease === epoch.current) setLoading(false); }
  }, [owner]);
  useEffect(() => {
    if (open) { setDeleting(null); setBusy(false); void refresh(); }
    return () => { ++epoch.current; };
  }, [open, refresh]);
  const change = async (id: string, action: 'pause' | 'delete') => {
    if (busy || loading) return;
    const lease = epoch.current; setBusy(true); setError(null);
    try {
      await manageKnotResponsibility(owner, id, action);
      if (lease !== epoch.current) return;
      setDeleting(null); setBusy(false); await refresh();
    } catch {
      if (lease === epoch.current) { setError('Couldn’t confirm this change. Refresh before trying again; it may already be saved.'); setBusy(false); }
    }
  };
  const visible = rules.filter(rule => rule.bot === bot);
  const date = (value: number, zone: string) => { try { return new Date(value).toLocaleString(undefined, { timeZone: zone }); } catch { return new Date(value).toLocaleString(); } };
  return <Dialog open={open} onOpenChange={value => { if (!value) onClose(); }}><DialogContent className="max-h-[88dvh] overflow-y-auto sm:max-w-lg">
    <DialogHeader><DialogTitle>Responsibilities</DialogTitle><DialogDescription>{knotNames[bot]}’s saved background checks. New approvals, resuming checks and contact permissions are reviewed in the native app.</DialogDescription></DialogHeader>
    <button type="button" className="min-h-11 w-fit rounded-full border px-4 text-sm" disabled={loading || busy} onClick={() => void refresh()}>{loading ? 'Refreshing…' : 'Refresh'}</button>
    {error && <p role="status" className="text-sm text-muted-foreground">{error}</p>}
    {!loading && !visible.length && <p className="py-6 text-center text-sm text-muted-foreground">Nothing assigned to this Knot yet.</p>}
    <ul className="divide-y divide-border">{visible.map(rule => <li key={rule.id} className="space-y-2 py-4">
      <h3 className="font-semibold">{rule.title}</h3>
      <p className="text-sm text-muted-foreground">{rule.state} · {rule.lastOutcome}</p>
      <p className="whitespace-pre-wrap text-sm">{rule.instruction}</p>
      <p className="text-xs text-muted-foreground">{rule.state === 'active' ? `Next check ${date(rule.nextRunAt, rule.timezone)} · ` : ''}Ends {date(rule.endsAt, rule.timezone)} · {rule.timezone}</p>
      <div className="flex flex-wrap gap-2">
        {rule.state === 'active' && <button type="button" disabled={busy || loading} className="min-h-11 rounded-full border px-4 text-sm" onClick={() => void change(rule.id, 'pause')}>Pause</button>}
        <button type="button" disabled={busy || loading} className="min-h-11 px-3 text-sm text-destructive" onClick={() => setDeleting(rule.id)}>Delete…</button>
      </div>
      {deleting === rule.id && <div className="rounded-xl border p-3 text-sm"><p>Stop this responsibility and delete its server updates? Copies already imported into chats remain.</p><div className="mt-2 flex gap-2"><button type="button" disabled={busy || loading} className="min-h-11 px-3 font-semibold text-destructive" onClick={() => void change(rule.id, 'delete')}>Delete responsibility</button><button type="button" disabled={busy} className="min-h-11 px-3" onClick={() => setDeleting(null)}>Cancel</button></div></div>}
    </li>)}</ul>
    <p className="text-xs leading-relaxed text-muted-foreground">Only server-confirmed updates appear in chat. A next-check time is not proof a check ran or a notification arrived. Pausing or deleting a rule never runs a command.</p>
  </DialogContent></Dialog>;
}
