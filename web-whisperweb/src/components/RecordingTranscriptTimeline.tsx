import { useEffect, useMemo, useRef, useState } from 'react';
import { AudioLines, MessageCircle } from 'lucide-react';
import { Button } from './ui/button';
import { cn } from '@/lib/utils';
import { recordingTime, type TimedPassage } from '@/lib/meetingRecordingModel';

/** Follows the actual media clock. Silence has no active passage; no timestamps are inferred. */
export function RecordingTranscriptTimeline({ passages, position, onSeek, onAsk }: { passages: TimedPassage[]; position: number; onSeek: (seconds: number) => void; onAsk?: (passages: TimedPassage[]) => void }): JSX.Element {
  const [follow, setFollow] = useState<boolean>(true);
  const [open, setOpen] = useState<boolean>(true);
  const container = useRef<HTMLDivElement | null>(null);
  const activeElement = useRef<HTMLDivElement | null>(null);
  const active = useMemo(() => passages.find((p) => position >= p.start && position < p.end)?.id, [passages, position]);
  const canAskAll = passages.length > 0 && passages.reduce((sum, p) => sum + Math.ceil(p.text.length / 1100), 0) <= 160 && passages.reduce((sum, p) => sum + p.text.length, 0) <= 24000;
  useEffect(() => {
    const scroller = container.current, row = activeElement.current;
    if (!follow || !open || !scroller || !row) return;
    // Scroll only this pane, never yank the surrounding meeting notes or the whole page.
    const top = row.getBoundingClientRect().top - scroller.getBoundingClientRect().top + scroller.scrollTop;
    scroller.scrollTo?.({ top: Math.max(0, top - scroller.clientHeight / 3), behavior: window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth' });
  }, [active, follow, open]);
  return <section aria-label="Recording transcript timeline" className="overflow-hidden rounded-2xl border border-border bg-muted/20">
    <div className="flex items-center justify-between gap-2 px-3"><button className="flex min-h-12 items-center gap-2 text-xs font-semibold" aria-expanded={open} onClick={() => setOpen((value) => !value)}><AudioLines className="h-4 w-4 text-rose-500" />Recording transcript</button><button className={cn('min-h-11 rounded-full px-3 text-[11px]', follow ? 'text-rose-600 dark:text-rose-300' : 'text-muted-foreground')} aria-pressed={follow} onClick={() => setFollow((value) => !value)}>{follow ? 'Following playback' : 'Follow playback'}</button></div>
    {open && <><div ref={container} className="relative max-h-64 space-y-1 overflow-y-auto overscroll-contain px-2 pb-2" onWheel={() => setFollow(false)} onTouchMove={() => setFollow(false)}>
      {passages.map((p) => <div key={p.id} ref={p.id === active ? activeElement : undefined} data-active={p.id === active} className={cn('rounded-xl p-2 transition-colors', p.id === active && 'bg-rose-100/70 dark:bg-rose-950/40')}><button type="button" className="flex min-h-11 w-full gap-3 text-left" aria-current={p.id === active ? 'true' : undefined} onClick={() => onSeek(p.start)}><span className="w-12 shrink-0 pt-1 text-[11px] font-semibold tabular-nums text-rose-600 dark:text-rose-300">{recordingTime(p.start)}{p.timing === 'chunk' && <span className="block text-[9px] font-normal">Approx.</span>}</span><span className="whitespace-pre-wrap text-sm leading-6">{p.speakerName && <span className="block text-[11px] font-semibold text-muted-foreground">{p.speakerName}</span>}{p.text}</span></button>{onAsk && !canAskAll && <Button variant="ghost" className="ml-12 h-11 text-[11px]" onClick={() => onAsk([p])}>Ask about this passage</Button>}</div>)}
      {!passages.length && <p className="p-4 text-xs leading-6 text-muted-foreground">No timed transcript yet. The recording is still available; open recording options to transcribe missing audio if permission allows it.</p>}
    </div><div className="flex flex-wrap items-center justify-between gap-1 border-t border-border/50 px-3 py-1"><span className="text-[10px] text-muted-foreground">Private · Times from recording start</span>{onAsk && canAskAll && <Button variant="ghost" className="h-11 text-xs" onClick={() => onAsk(passages)}><MessageCircle className="mr-2 h-3.5 w-3.5" />Ask Jasper about this recording</Button>}</div></>}
  </section>;
}
