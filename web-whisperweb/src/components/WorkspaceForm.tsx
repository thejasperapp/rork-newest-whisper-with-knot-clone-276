import { useState } from 'react';
import { useForm } from 'react-hook-form';
import { useMutation } from '@tanstack/react-query';
import { zodResolver } from '@hookform/resolvers/zod';
import { z } from 'zod';
import { Button } from './ui/button';
import { Input } from './ui/input';
import { Textarea } from './ui/textarea';
export type WorkField = { key: string; label: string; required?: boolean; max?: number; multiline?: boolean; type?: string; options?: { id: string; label: string }[] };
/** Every consequential workspace write has a visible audience and a review step. */
export function WorkspaceForm({ title, fields, initial, audience, submitLabel = 'Save reviewed changes', submit, done, cancel }: { title: string; fields: WorkField[]; initial?: Record<string, string>; audience: string; submitLabel?: string; submit: (values: Record<string, string>) => Promise<unknown>; done: () => void; cancel: () => void }): JSX.Element {
  const [approved, setApproved] = useState<boolean>(false);
  const schema = z.object(Object.fromEntries(fields.map((f) => [f.key, z.string().trim().min(f.required ? 1 : 0).max(f.max ?? 8000)])));
  const form = useForm<Record<string, string>>({ resolver: zodResolver(schema), defaultValues: Object.fromEntries(fields.map((f) => [f.key, initial?.[f.key] ?? ''])) });
  const mutation = useMutation({ mutationFn: async (values: Record<string, string>) => { if (!approved) throw new Error('Review the changes first.'); return submit(values); }, onSuccess: done });
  return <form aria-label={title} onSubmit={form.handleSubmit((values) => mutation.mutate(values))} className="space-y-4 rounded-2xl border bg-card p-4 sm:p-5">
    <h3 className="text-lg font-semibold">{title}</h3><p className="text-sm leading-6 text-muted-foreground">{audience}</p>
    <fieldset disabled={mutation.isPending} className="space-y-4" onChange={() => setApproved(false)}>{fields.map((field) => <label key={field.key} className="block space-y-1.5 text-sm font-medium"><span>{field.label}</span>{field.options ? <select className="min-h-11 w-full rounded-xl border bg-background px-3" {...form.register(field.key)}>{field.options.map((o) => <option key={o.id} value={o.id}>{o.label}</option>)}</select> : field.multiline ? <Textarea className="min-h-28 font-normal leading-6" maxLength={field.max ?? 8000} {...form.register(field.key)} /> : <Input className="min-h-11" type={field.type ?? 'text'} maxLength={field.max ?? 8000} {...form.register(field.key)} />}</label>)}</fieldset>
    {Object.keys(form.formState.errors).length > 0 && <p role="alert" className="text-sm text-destructive">Complete the required fields within the displayed limits.</p>}
    <label className="flex min-h-11 items-center gap-3 text-sm"><input type="checkbox" checked={approved} disabled={mutation.isPending} onChange={(e) => setApproved(e.target.checked)} />I reviewed this content and who can see it.</label>
    {mutation.error && <p role="alert" className="text-sm text-destructive">{mutation.error.message}</p>}
    <div className="flex flex-wrap gap-2"><Button type="submit" className="min-h-11 rounded-full" disabled={!approved || mutation.isPending}>{mutation.isPending ? 'Confirming save…' : submitLabel}</Button><Button type="button" variant="ghost" disabled={mutation.isPending} onClick={cancel}>Cancel</Button></div>
  </form>;
}
