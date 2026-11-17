import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { jasperMeetingRequest } from '@/lib/jasperMeetings';
import { Input } from '@/components/ui/input';
import { Button } from '@/components/ui/button';
type Records = { period: string; recordCount: number; peopleCount: number; records: { id: string; promoted_username: string; role: string; created_at: string }[] };
/** Deterministic counts from the recruiter's promotion ledger, never inferred from mentions. */
export function RecruiterPromotionRecords({ owner }: { owner: string }): JSX.Element {
  const [period, setPeriod] = useState<string>(new Date().toISOString().slice(0, 7));
  const query = useQuery({ queryKey: ['client-promotion-records', owner, period], queryFn: ({ signal }) => jasperMeetingRequest<Records>(owner, `clients/promotions?period=${period}`, undefined, signal), enabled: /^20\d{2}-(0[1-9]|1[0-2])$/.test(period), gcTime: 0 });
  return <details className="rounded-2xl border p-3 text-sm"><summary className="cursor-pointer font-semibold">Recorded promotion totals</summary><div className="mt-3 space-y-2"><label className="block text-xs">Month (UTC)<Input type="month" min="2000-01" max="2099-12" value={period} onChange={(e) => setPeriod(e.target.value)} /></label>{query.error ? <p role="alert">Couldn’t verify the ledger.<Button variant="ghost" onClick={() => void query.refetch()}>Retry</Button></p> : query.data ? <><p><strong>{query.data.peopleCount} people</strong> · {query.data.recordCount} recorded role promotions</p><p className="text-xs text-muted-foreground">Your promotion records, not meeting-reported claims or contracts. If a meeting gives a different number, check its period and these records; neither is silently changed.</p><div className="max-h-48 overflow-y-auto">{query.data.records.map((r) => <p key={r.id} className="border-t py-2 text-xs">@{r.promoted_username} · {r.role} · {new Date(r.created_at).toLocaleDateString()}</p>)}</div></> : <p>Loading recorded totals…</p>}</div></details>;
}
