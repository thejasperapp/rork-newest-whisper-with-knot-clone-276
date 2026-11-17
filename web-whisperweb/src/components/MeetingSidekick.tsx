import { useCallback, useMemo, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { AudioLines, ChevronDown, Minimize2, RefreshCw, Sparkles } from 'lucide-react';
import { sidekickTranscript } from '@/lib/meetingSidekick';
import { type JasperAnswer } from '@/lib/jasperMeetings';
import { cn } from '@/lib/utils';
import { Button } from './ui/button';
import { JasperMeetingAssistant } from './JasperMeetingAssistant';
import { JasperSidekickMascot } from './JasperSidekickMascot';

/** Transcript-first sidekick. Closing it never owns or stops the meeting's capture. */
export function MeetingSidekick({ owner, meetingID, title, visible, captureStatus, interim, onRetryCapture, onHide, archived = false, docked = false }: { docked?: boolean; archived?: boolean; owner: string; meetingID: string; title: string; visible: boolean; captureStatus: string; interim: string; onRetryCapture: () => void; onHide: () => void }): JSX.Element {
  const [transcriptOpen, setTranscriptOpen] = useState<boolean>(false);
  const [scanning, setScanning] = useState<boolean>(false);
  const [answer, setAnswer] = useState<JasperAnswer | null>(null);
  const transcript = useQuery({ queryKey: ['sidekick-speech', owner, meetingID], queryFn: ({ signal }) => sidekickTranscript(owner, meetingID, signal), refetchInterval: archived ? false : 3000, gcTime: 0 });
  const rows = transcript.data?.rows ?? [];
  const highlights = useMemo(() => {
    const cited = new Set(answer?.result.sections.flatMap((section) => section.items.flatMap((item) => item.sourceIds)) ?? []);
    return new Set(answer?.sources.filter((source) => cited.has(source.id) && source.meetingId === meetingID).map((source) => source.segmentId) ?? []);
  }, [answer, meetingID]);
  const busy = useCallback((value: boolean): void => { setScanning(value); if (value) setTranscriptOpen(true); }, []);
  return <aside aria-label="Jasper meeting sidekick" data-private-meeting-overlay className={cn('flex min-h-0 min-w-0 flex-col overflow-hidden rounded-[28px] border border-border/70 bg-card text-foreground shadow-sm', docked ? 'relative h-full w-full' : 'fixed bottom-24 right-3 top-[22dvh] z-[65] w-[calc(100%-24px)] md:top-16 md:w-[400px]', !visible && 'hidden')}>
    <header className="shrink-0 px-4 pb-2 pt-2"><div className="flex items-center justify-between"><span className="flex min-w-0 items-center gap-2 text-sm font-semibold"><JasperSidekickMascot className="h-9" working={scanning} />Jasper <span className="rounded-full bg-background px-2 py-1 text-[10px] font-medium text-muted-foreground">Private</span></span><Button variant="ghost" size="icon" className="h-11 w-11" aria-label="Minimize Jasper sidekick" onClick={onHide}><Minimize2 className="h-4 w-4" /></Button></div><h2 className="truncate text-xs text-muted-foreground">{title}</h2><p role="status" className="mt-1 flex items-center gap-2 text-[11px] leading-4 text-muted-foreground"><AudioLines className="h-4 w-4" />{captureStatus}</p></header>
    <div className="flex min-h-0 flex-1 flex-col px-4 pb-4">
      <section aria-label="Meeting transcript" className="relative my-2 max-h-[40%] shrink-0 overflow-y-auto overscroll-contain rounded-2xl border border-border/70 bg-background/70"><button className="flex min-h-12 w-full items-center justify-between px-4 text-sm font-medium" aria-expanded={transcriptOpen} onClick={() => setTranscriptOpen((value) => !value)}><span>Transcript <span className="ml-1 text-xs text-muted-foreground">{rows.length ? `${rows.length} saved passages` : ''}</span></span><ChevronDown className={cn('h-4 w-4 transition-transform', !transcriptOpen && '-rotate-90')} /></button>
        {!transcriptOpen && transcript.isError && <p role="alert" className="px-4 pb-3 text-xs text-red-600">{transcript.error.message}</p>}
        {transcriptOpen && <div className="relative"><div className="max-h-40 space-y-3 overflow-y-auto px-4 pb-4" aria-label="Saved meeting speech">{transcript.isError ? <p role="alert" className="text-xs leading-5 text-red-600">{transcript.error.message}</p> : !rows.length && <p className="py-4 text-sm text-muted-foreground">{transcript.isPending ? 'Loading saved transcript…' : archived ? 'No saved speech is available for this meeting. Check its recording for a separately captured transcript.' : 'No saved speech yet. Check microphone access and capture status above.'}</p>}{rows.map((row) => <div key={row.id} className={cn('rounded-lg px-2 py-2 transition-colors', highlights.has(row.id) && 'bg-amber-100/80 dark:bg-amber-900/30')}><p className="mb-1 text-[11px] text-muted-foreground">{row.username || 'Speaker'} · {new Date(row.spoken_at).toLocaleTimeString()}</p><p className="whitespace-pre-wrap text-sm leading-6">{row.text}</p></div>)}{interim && <div className="border-l-2 border-rose-300 pl-3"><p className="text-[10px] text-muted-foreground">Being transcribed · not saved yet</p><p className="text-sm italic leading-6">{interim}</p></div>}{transcript.data && !transcript.data.complete && <p className="text-xs text-muted-foreground">Showing the latest 200 passages. Jasper searches saved meeting history separately.</p>}</div>{scanning && <div aria-label="Scanning transcript" className="pointer-events-none absolute inset-x-3 top-0 z-10 motion-safe:animate-[jasper-scan_2.8s_ease-in-out_infinite_alternate]"><div className="mx-auto flex w-fit items-center gap-2 rounded-full bg-rose-600 px-4 py-2 text-xs text-white shadow-lg"><Sparkles className="h-3 w-3" />Scanning transcript…</div></div>}</div>}
        <div className={cn('flex flex-wrap gap-2 border-t border-border/50 px-3', !transcriptOpen && !transcript.isError && !/retry|error|unavailable|could|connection|attention|gap|paused|sign-in/i.test(captureStatus) && 'hidden')}><Button variant="ghost" className="h-11 text-xs" onClick={() => void transcript.refetch()}><RefreshCw className="mr-1 h-3 w-3" />Refresh transcript</Button>{!archived && <Button variant="ghost" className="h-11 text-xs" onClick={onRetryCapture}>Retry capture</Button>}</div>
      </section>
      <JasperMeetingAssistant key={`${owner}:${meetingID}`} owner={owner} meetingID={meetingID} embedded onBusy={busy} onAnswer={setAnswer} onConnectionsOpen={() => setTranscriptOpen(false)} />
    </div>
  </aside>;
}
