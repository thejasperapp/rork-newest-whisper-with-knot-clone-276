import { useEffect, useRef, useState } from 'react';
import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { CalendarDays, Bell } from 'lucide-react';
import { toast } from 'sonner';
import { supabase } from '@/lib/supabase';
import { jasperMeetingRequest, type JasperCalendarEvent } from '@/lib/jasperMeetings';
import { type CalendarEvent } from '@/lib/calendar';
import { Button } from './ui/button';

export function JasperUpcomingMeetings({ owner }: { owner: string }): JSX.Element {
  const client = useQueryClient();
  const [reminders, setReminders] = useState<boolean>(false);
  const notified = useRef<Set<string>>(new Set());
  const status = useQuery({ queryKey: ['jasper-google-status', owner], queryFn: ({ signal }) => jasperMeetingRequest<{ configured: boolean; connected: boolean }>(owner, 'google/status', undefined, signal) });
  const google = useQuery({ queryKey: ['jasper-google-events', owner], enabled: status.data?.connected === true, queryFn: ({ signal }) => jasperMeetingRequest<{ events: JasperCalendarEvent[]; partial: boolean }>(owner, 'google/events', undefined, signal), refetchInterval: 60000 });
  const whisper = useQuery({ queryKey: ['jasper-upcoming', owner], queryFn: async ({ signal }) => {
    const { data, error } = await supabase.from('whisper_calendar_events').select('*').or(`created_by.eq.${owner},tagged_user_ids.cs.{${owner}}`).gte('start_time', new Date().toISOString()).lt('start_time', new Date(Date.now() + 30 * 86400000).toISOString()).order('start_time').limit(251).abortSignal(signal);
    if (error) throw new Error('Whisper Calendar could not load. Please refresh.');
    return (data as CalendarEvent[] ?? []).map((event): JasperCalendarEvent => ({ id: `whisper:${event.id}`, title: event.title, start: event.start_time, end: event.end_time ?? '', allDay: false, link: event.meeting_link ?? '', source: 'Whisper Calendar' }));
  }, refetchInterval: 60000 });
  const connect = useMutation({ mutationFn: () => jasperMeetingRequest<{ url: string }>(owner, 'google/connect', {}), onSuccess: ({ url }) => { if (url.startsWith('https://')) window.location.assign(url); } });
  const disconnect = useMutation({ mutationFn: () => jasperMeetingRequest<{ revoked: boolean }>(owner, 'google/disconnect', {}), onSuccess: (result) => { void client.invalidateQueries({ queryKey: ['jasper-google-status', owner] }); client.removeQueries({ queryKey: ['jasper-google-events', owner] }); if (!result.revoked) toast('Disconnected here. You can also revoke access in your Google account settings.'); } });
  const events = [...(whisper.data ?? []), ...(google.data?.events ?? [])].sort((a, b) => a.start.localeCompare(b.start));
  const eventKey = events.map((event) => `${event.id}:${event.start}`).join('|');
  useEffect(() => {
    if (!reminders) return;
    const timer = setInterval(() => { for (const event of events) { const delta = Date.parse(event.start) - Date.now(); const id = `${event.id}:${event.start}`; if (!event.allDay && delta > 0 && delta <= 5 * 60000 && !notified.current.has(id)) { notified.current.add(id); toast(`${event.title} starts in ${Math.ceil(delta / 60000)} minutes.`, { duration: 10000 }); } } }, 15000);
    return () => clearInterval(timer);
    // The key includes every event's start time, so rescheduled meetings get a fresh reminder.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [reminders, eventKey]);
  return <section className="space-y-4"><div className="flex items-center gap-2"><CalendarDays className="h-5 w-5 text-rose-500" /><h2 className="text-xl font-semibold tracking-tight">Coming up</h2></div><p className="text-sm text-muted-foreground">Your Whisper events and connected Google primary calendar. Read-only; Jasper won’t change your events. Connect the Google account with the same email as your Whisper account.</p>{status.data?.configured === false && <div role="status" className="rounded-2xl border bg-secondary/40 p-4 text-sm leading-6"><p className="font-semibold">Google Calendar needs setup</p><p>The app owner must configure a Google Web OAuth client, enable the Calendar API, and authorize the redirect below. Your Whisper events still work.</p><p className="mt-2 break-all text-xs">https://e1p9ya2tdy09t3sy62x1s-backend.rork.app/jasper-meetings/google/callback</p></div>}<div className="flex flex-wrap gap-2"><Button variant="outline" className="h-11 rounded-full text-xs" disabled={connect.isPending || disconnect.isPending || status.isPending || (!status.data?.connected && status.data?.configured === false)} onClick={() => status.data?.connected ? disconnect.mutate() : connect.mutate()}>{status.data?.connected ? 'Disconnect Google Calendar' : 'Connect Google Calendar'}</Button><Button variant="ghost" className="h-11 text-xs" onClick={() => { void status.refetch(); void whisper.refetch(); if (status.data?.connected) void google.refetch(); }}>Refresh calendars</Button></div><label className="flex min-h-11 items-center gap-2 text-xs"><input type="checkbox" checked={reminders} onChange={(event) => setReminders(event.target.checked)} /><Bell className="h-4 w-4" />Remind me five minutes before, while this page is open</label>{(status.error || google.error || whisper.error || connect.error || disconnect.error) && <p role="alert" className="text-xs text-red-600">{(connect.error ?? disconnect.error ?? status.error ?? google.error ?? whisper.error)?.message}</p>}{events.slice(0, 30).map((event) => <article key={event.id} className="flex items-start gap-3 rounded-2xl border border-border p-4"><div className="min-w-0 flex-1"><h3 className="font-medium">{event.title}</h3><p className="mt-1 text-xs text-muted-foreground">{event.allDay ? `${event.start} · All day` : new Date(event.start).toLocaleString()} · {event.source}</p></div>{/^https:\/\//.test(event.link) && <a className="inline-flex min-h-11 items-center text-xs underline" href={event.link} target="_blank" rel="noopener noreferrer">Open</a>}</article>)}{(whisper.isPending || (status.data?.connected && google.isPending)) && <p role="status" className="text-sm">Loading upcoming meetings…</p>}{!whisper.isPending && !whisper.error && !events.length && <p className="py-4 text-sm text-muted-foreground">No upcoming events were returned for the next 30 days.</p>}{(google.data?.partial || events.length > 30) && <p className="text-xs text-muted-foreground">Showing the nearest 30 events. Open your calendar for the full schedule.</p>}</section>;
}
