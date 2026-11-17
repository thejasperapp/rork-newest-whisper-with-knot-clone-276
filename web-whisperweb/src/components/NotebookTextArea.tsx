import { useMemo, useRef } from "react";
import type { NotebookHighlight, NotebookSelection } from "@/lib/notebookHighlights";

/** Native textarea preserves IME, selection and undo; a noninteractive mirror paints saved ink. */
export function NotebookTextArea({ value, kind, revision, highlights, label, placeholder, onChange, onSelection }: {
  value: string; kind: NotebookSelection["kind"]; revision: number; highlights: NotebookHighlight[]; label: string; placeholder: string;
  onChange: (text: string) => void; onSelection: (selection: NotebookSelection | null) => void;
}): JSX.Element {
  const mirror = useRef<HTMLDivElement | null>(null);
  const parts = useMemo(() => {
    const intervals = highlights.filter((item) => item.kind === kind && !item.stale && value.slice(item.start, item.end) === item.text).sort((a, b) => a.start - b.start);
    const merged: { start: number; end: number }[] = [];
    for (const item of intervals) { const last = merged[merged.length - 1]; if (last && item.start <= last.end) last.end = Math.max(last.end, item.end); else merged.push({ start: item.start, end: item.end }); }
    let cursor = 0;
    const result = merged.flatMap((item) => { const text = value.slice(cursor, item.start); cursor = item.end; return [text, <mark key={item.start} className="rounded-sm bg-amber-300/40 text-transparent motion-safe:animate-in motion-safe:fade-in motion-safe:duration-500">{value.slice(item.start, item.end)}</mark>]; });
    return [...result, value.slice(cursor), "\n"];
  }, [value, highlights, kind]);
  const layout = "col-start-1 row-start-1 h-64 w-full whitespace-pre-wrap break-words px-1 py-2 text-base leading-7 [overflow-wrap:anywhere] [tab-size:4]";
  return <div className="grid min-w-0">
    <div ref={mirror} aria-hidden="true" className={`${layout} pointer-events-none overflow-y-scroll text-transparent [scrollbar-color:transparent_transparent]`}>{parts}</div>
    <textarea aria-label={label} value={value} placeholder={placeholder} className={`${layout} relative resize-none overflow-y-scroll bg-transparent outline-none selection:bg-rose-200/60 dark:selection:bg-rose-700/40`} onChange={(event) => onChange(event.target.value)} onScroll={(event) => { if (mirror.current) mirror.current.scrollTop = event.currentTarget.scrollTop; }} onSelect={(event) => { const area = event.currentTarget; onSelection(area.selectionEnd > area.selectionStart ? { kind, start: area.selectionStart, end: area.selectionEnd, text: area.value.slice(area.selectionStart, area.selectionEnd), revision } : null); }} />
  </div>;
}
