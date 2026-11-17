import { useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { Button } from '@/components/ui/button';
import { Textarea } from '@/components/ui/textarea';
import { jasperMeetingRequest } from '@/lib/jasperMeetings';
import { clientStageLabels, type ClientTeam, type ClientTeamCard } from '@/lib/recruiterClients';
import type { Prospect } from '@/lib/recruiter';

/** Team access returns only explicitly reviewed snapshots, never private person profiles. */
export function RecruiterTeamPipeline({ owner, prospect }: { owner: string; prospect?: Prospect }): JSX.Element {
  const [business, setBusiness] = useState<string>('');
  const [update, setUpdate] = useState<string>('');
  const [reviewed, setReviewed] = useState<string>('');
  const cache = useQueryClient();
  const teams = useQuery({ queryKey: ['client-teams', owner], queryFn: ({ signal }) => jasperMeetingRequest<{ teams: ClientTeam[] }>(owner, 'clients/teams', undefined, signal), gcTime: 0, retry: false });
  const board = useQuery({ queryKey: ['client-team-cards', owner, business], enabled: !!business, queryFn: ({ signal }) => jasperMeetingRequest<{ cards: ClientTeamCard[]; revisions: Record<string, number> }>(owner, `clients/team?businessId=${business}`, undefined, signal), refetchInterval: 15000, retry: false, gcTime: 0 });
  const previous = board.data?.cards.find((c) => c.id === prospect?.id && c.publisherId === owner);
  const preview = prospect ? { name: prospect.prospect_display_name || prospect.prospect_username || 'Unnamed', role: prospect.suggested_role || 'unspecified', stage: prospect.status, update } : null;
  const revision = board.data?.revisions?.[prospect?.id ?? ''] ?? previous?.revision ?? 0;
  const fingerprint = JSON.stringify({ business, preview, revision });
  const publish = useMutation({ mutationFn: (revoke: boolean) => jasperMeetingRequest(owner, `clients/team?businessId=${business}`, revoke ? { action: 'revoke', id: prospect?.id, confirm: true } : { ...preview, id: prospect?.id, revision, confirm: reviewed === fingerprint }), onSuccess: () => { setReviewed(''); void cache.invalidateQueries({ queryKey: ['client-team-cards', owner, business] }); } });
  return <section className="space-y-3 rounded-2xl border p-3">
    <h3 className="font-semibold">Team pipeline</h3>
    <p className="text-xs text-muted-foreground">Private by default. Only published names, roles, stages and the update you write below are shared. No contact details, private notes, recordings or Jasper conversations.</p>
    {teams.error ? <p role="alert" className="text-xs">Couldn’t verify teams. <Button variant="ghost" onClick={() => void teams.refetch()}>Retry</Button></p> : <select className="min-h-11 w-full rounded-xl border bg-background px-3 text-sm" aria-label="Team pipeline" value={business} onChange={(e) => { setBusiness(e.target.value); setReviewed(''); }}><option value="">Choose a team</option>{teams.data?.teams.map((t) => <option key={t.id} value={t.id}>{t.name}</option>)}</select>}
    {teams.data?.teams.length === 0 && <p className="text-xs text-muted-foreground">Join or create an existing Business team to share. Your private pipeline works without one.</p>}
    {business && (board.error ? <p role="alert" className="text-xs">{board.error.message}<Button variant="ghost" onClick={() => void board.refetch()}>Recheck access</Button></p> : !board.data ? <p className="text-xs">Verifying team access…</p> : <>
      {prospect && preview && <div className="space-y-2"><Textarea aria-label="Team update" maxLength={1200} placeholder="Write only what this team should see…" value={update} onChange={(e) => { setUpdate(e.target.value); setReviewed(''); }} /><div className="rounded-xl bg-muted/50 p-3 text-sm"><strong>{preview.name}</strong><p>{preview.role} · {clientStageLabels[preview.stage]}</p><p className="whitespace-pre-wrap">{update || 'No team update'}</p></div><label className="flex min-h-11 items-center gap-2 text-xs"><input type="checkbox" checked={reviewed === fingerprint} onChange={(e) => setReviewed(e.target.checked ? fingerprint : '')} />I reviewed this exact card for the selected team.</label><Button disabled={publish.isPending || reviewed !== fingerprint} onClick={() => publish.mutate(false)}>{previous ? 'Publish reviewed replacement' : 'Publish reviewed card'}</Button>{previous && <Button variant="outline" disabled={publish.isPending} onClick={() => publish.mutate(true)}>Revoke my card</Button>}<p className="text-xs text-muted-foreground">Stage changes do not silently update a published card.</p></div>}
      {(prospect ? board.data.cards.filter((c) => c.id === prospect.id && c.publisherId === owner) : board.data.cards).map((card) => <article key={`${card.publisherId}:${card.id}`} className="rounded-xl bg-muted/40 p-3 text-sm"><strong>{card.name}</strong><p>{card.role} · {clientStageLabels[card.stage] ?? card.stage}</p><p className="whitespace-pre-wrap">{card.update}</p><p className="mt-2 text-xs text-muted-foreground">Published {new Date(card.publishedAt).toLocaleString()} · {card.publisherId === owner ? 'By you' : 'Team recruiter'}</p></article>)}
      {!board.data.cards.length && <p className="text-sm text-muted-foreground">No reviewed cards published yet.</p>}
    </>)}
    {publish.error && <p role="alert" className="text-xs text-destructive">{publish.error.message}</p>}
  </section>;
}
