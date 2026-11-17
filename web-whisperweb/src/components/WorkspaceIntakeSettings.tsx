import { useState } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { workRequest, type IntakeSettings, type WorkPerson, type WorkScope } from '@/lib/workspace';
import { WorkspaceForm } from './WorkspaceForm';
import { Button } from './ui/button';
export function WorkspaceIntakeSettings({ owner, scope, members }: { owner: string; scope: WorkScope; members: WorkPerson[] }): JSX.Element {
  const cache = useQueryClient();
  const key = ['jasper-work-intake', owner, scope.space, scope.team];
  const query = useQuery({ queryKey: key, queryFn: ({ signal }) => workRequest<IntakeSettings>(owner, scope, '/intake', undefined, signal), gcTime: 0, retry: false });
  const [edit, setEdit] = useState<{ action: string; revision: number; userId?: string } | null>(null);
  if (query.error) return <p role="alert">{query.error.message}</p>;
  if (!query.data) return <p>Loading intake settings…</p>;
  const settings = query.data;
  return <section className="space-y-3 rounded-2xl border p-4"><h3 className="font-semibold">A front door for requests</h3><p className="text-sm leading-6 text-muted-foreground">Invite a person by their exact Whisper username, then send the restricted intake link. They can submit and follow only their own requests. Removing access hides those requests from them; internal records remain.</p><div className="flex flex-wrap gap-2"><Button variant="outline" onClick={() => setEdit({ action: 'configure_intake', revision: settings.revision })}>Routing & service target</Button><Button variant="outline" onClick={() => setEdit({ action: 'invite_requester', revision: settings.revision })}>Invite requester</Button></div>
    {settings.people.map((p) => <div key={p.id} className="flex min-h-11 items-center justify-between text-sm"><span>@{p.username}</span><Button variant="ghost" onClick={() => setEdit({ action: 'revoke_requester', revision: settings.revision, userId: p.id })}>Revoke</Button></div>)}
    {edit && <WorkspaceForm key={`${edit.action}:${edit.userId ?? ''}:${edit.revision}`} title={edit.action === 'configure_intake' ? 'Configure intake' : edit.action === 'invite_requester' ? 'Invite requester' : 'Revoke requester access'} fields={edit.action === 'configure_intake' ? [{ key: 'instructions', label: 'Request instructions', required: true, multiline: true, max: 2000 }, { key: 'assigneeId', label: 'Default accountable owner / approver', required: true, options: members.map((p) => ({ id: p.id, label: p.username })) }, { key: 'turnaroundDays', label: 'Target calendar days (1–90)', required: true, type: 'number', max: 2 }] : edit.action === 'invite_requester' ? [{ key: 'username', label: 'Exact Whisper username', required: true, max: 40 }] : []} initial={{ instructions: settings.instructions, assigneeId: settings.assigneeId, turnaroundDays: String(settings.turnaroundDays) }} audience="Only invited accounts can submit external requests. Team membership is separate. Targets apply to new requests and are not automatic reminders or guarantees." submit={(values) => workRequest(owner, scope, '/intake', { ...values, ...edit, confirm: true, ...(values.turnaroundDays ? { turnaroundDays: Number(values.turnaroundDays) } : {}) })} done={() => { setEdit(null); void cache.invalidateQueries({ queryKey: key }); }} cancel={() => setEdit(null)} />}
  </section>;
}
