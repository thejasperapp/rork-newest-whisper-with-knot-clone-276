import { useState } from 'react';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Pencil } from 'lucide-react';
import { renameMeeting, type WhisperMeeting } from '@/lib/meetings';
import { Button } from './ui/button';
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from './ui/dialog';
import { Input } from './ui/input';

const schema = z.object({ title: z.string().trim().min(1, 'Enter a meeting name.').max(160, 'Keep the name under 160 characters.') });
/** Shared title, not a private filing label. Never claims success before the update is acknowledged. */
export function MeetingTitleButton({ meeting, owner }: { meeting: WhisperMeeting; owner?: string }): JSX.Element {
  const [open, setOpen] = useState<boolean>(false);
  const client = useQueryClient();
  const form = useForm<z.infer<typeof schema>>({ resolver: zodResolver(schema), defaultValues: { title: meeting.title } });
  const mutation = useMutation({ mutationFn: (values: z.infer<typeof schema>) => renameMeeting(meeting, values.title), onSuccess: (saved) => {
    client.setQueryData(['meeting', meeting.id], saved);
    void client.invalidateQueries({ queryKey: ['meeting-library'] });
    setOpen(false);
  } });
  return <><button type="button" disabled={owner !== meeting.host_id} aria-label={owner === meeting.host_id ? 'Rename meeting' : undefined} className="flex min-h-11 min-w-0 items-center gap-2 truncate text-left text-sm font-medium text-[color:var(--meet-ink)] disabled:cursor-default" onClick={() => { form.reset({ title: meeting.title }); mutation.reset(); setOpen(true); }}><span className="truncate">{meeting.title}</span>{owner === meeting.host_id && <Pencil className="h-3 w-3 shrink-0 opacity-50" />}</button>
    <Dialog open={open} onOpenChange={(next) => { if (!mutation.isPending) setOpen(next); }}><DialogContent><DialogHeader><DialogTitle>Rename meeting</DialogTitle><DialogDescription>Everyone sees the new name. The meeting link, notes and recordings stay connected.</DialogDescription></DialogHeader><form className="space-y-4" onSubmit={form.handleSubmit((values) => mutation.mutate(values))}><label className="block text-sm">Meeting name<Input className="mt-2 h-12" autoFocus maxLength={160} {...form.register('title')} /></label>{(form.formState.errors.title || mutation.error) && <p role="alert" className="text-sm text-destructive">{form.formState.errors.title?.message ?? mutation.error?.message}</p>}<div className="flex justify-end gap-2"><Button type="button" variant="ghost" disabled={mutation.isPending} onClick={() => setOpen(false)}>Cancel</Button><Button type="submit" disabled={mutation.isPending}>{mutation.isPending ? 'Saving…' : 'Save name'}</Button></div></form></DialogContent></Dialog>
  </>;
}
