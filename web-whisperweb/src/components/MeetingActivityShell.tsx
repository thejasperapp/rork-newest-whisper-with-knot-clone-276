import { useEffect, useLayoutEffect, useRef, useState, type ReactNode } from "react";
import { createPortal } from "react-dom";
import { ArrowLeft, X } from "lucide-react";

/** Non-modal meeting tools: the call stays visible and usable beside the panel. */
export function MeetingActivityShell({ title, onClose, onBack, children }: { title: string; onClose: () => void; onBack?: () => void; children: ReactNode }): JSX.Element {
  const close = useRef<HTMLButtonElement | null>(null);
  const [container, setContainer] = useState<Element>(() => document.fullscreenElement ?? document.body);
  useEffect(() => {
    const changed = (): void => setContainer(document.fullscreenElement ?? document.body);
    document.addEventListener("fullscreenchange", changed);
    return () => document.removeEventListener("fullscreenchange", changed);
  }, []);
  useLayoutEffect(() => {
    const previous = document.activeElement;
    return () => { if (previous instanceof HTMLElement && previous.isConnected) previous.focus(); };
  }, []);
  useLayoutEffect(() => { close.current?.focus(); }, [container]);
  return createPortal(<aside role="region" aria-label={title} className="pointer-events-auto fixed bottom-[88px] right-3 top-[max(1rem,env(safe-area-inset-top))] z-[90] flex w-[min(360px,calc(100%-1.5rem))] flex-col overflow-hidden rounded-[28px] border border-border bg-background text-foreground shadow-xl" onKeyDown={(event) => { if (event.key === "Escape") { event.stopPropagation(); onClose(); } }}>
    <header className="flex shrink-0 items-center gap-2 border-b border-border px-3 py-2">
      {onBack && <button type="button" className="grid h-11 w-11 shrink-0 place-items-center rounded-full hover:bg-muted" aria-label="Back to tools" onClick={onBack}><ArrowLeft className="h-5 w-5" /></button>}
      <h2 className="min-w-0 flex-1 px-2 text-lg font-semibold">{title}</h2>
      <button ref={close} type="button" className="grid h-11 w-11 shrink-0 place-items-center rounded-full hover:bg-muted" aria-label={`Close ${title.toLowerCase()}`} onClick={onClose}><X className="h-5 w-5" /></button>
    </header>
    <div className="min-h-0 flex-1 space-y-4 overflow-y-auto overscroll-contain p-5">{children}</div>
  </aside>, container);
}
