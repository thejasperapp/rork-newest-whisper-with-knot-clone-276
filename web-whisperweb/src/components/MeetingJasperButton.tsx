import { ArrowUp } from 'lucide-react';
import { EmberMascot } from '@/components/EmberMascot';
import { JasperKitKeyframes, JasperMintPill } from '@/components/JasperIntelKit';
import type { EmberCoachMode } from '@/lib/emberBrain';
import { cn } from '@/lib/utils';

/** Original bottom-left question pill. Opening and typing are separate from explicitly sending. */
export function MeetingJasperButton({ open, onToggle, mode = 'regular', draft, onDraftChange, onSubmit, busy = false }: {
  open: boolean;
  onToggle: () => void;
  mode?: EmberCoachMode;
  draft: string;
  onDraftChange: (value: string) => void;
  onSubmit: (question: string) => void;
  busy?: boolean;
}): JSX.Element {
  return <div data-jasper-launcher className={cn('fixed bottom-[calc(6rem+env(safe-area-inset-bottom))] left-[max(16px,env(safe-area-inset-left))] z-20 w-[min(320px,calc(100vw-32px))] lg:bottom-6', open && 'hidden')}>
    <JasperKitKeyframes />
    <div className="relative motion-safe:animate-[jasper-peek-in_750ms_cubic-bezier(0.34,1.45,0.64,1)_350ms_both]">
      <button type="button" aria-label="Ask Jasper" aria-expanded={open} onClick={onToggle} title="Open Jasper questions" className="absolute -top-[27px] left-4 z-0 min-h-11 min-w-11 rounded-full transition-transform hover:scale-105 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white active:scale-95">
        <span aria-hidden className="pointer-events-none block motion-safe:animate-[jasper-mascot-bob_1.7s_ease-in-out_infinite]"><EmberMascot size={50} coachMode={mode} expression={busy ? 'thinking' : 'calm'} cyclesExpressions={!busy} /></span>
      </button>
      <form aria-label="Ask Jasper question" onSubmit={(event) => {
        event.preventDefault();
        const question = draft.trim();
        if (!question || busy) return;
        onSubmit(question);
      }}>
        <JasperMintPill mode={mode} className="relative z-10 min-h-11 w-full gap-1 pl-4 pr-0 font-bold text-[#0A1712]">
          <input aria-label="Ask Jasper question" placeholder={busy ? 'Thinking…' : 'Ask Jasper'} value={draft} onChange={(event) => onDraftChange(event.target.value)} onKeyDown={(event) => { if (event.nativeEvent.isComposing && event.key === 'Enter') event.preventDefault(); }} className="h-11 min-w-0 flex-1 bg-transparent text-base outline-none placeholder:text-inherit placeholder:opacity-70" />
          <button type="submit" aria-label="Send to Jasper" disabled={!draft.trim() || busy} className="grid min-h-11 min-w-11 place-items-center rounded-full transition-opacity focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-current disabled:opacity-35"><ArrowUp className="h-4 w-4" strokeWidth={2.6} /></button>
        </JasperMintPill>
      </form>
    </div>
  </div>;
}
