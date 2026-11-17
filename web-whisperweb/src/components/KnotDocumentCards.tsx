import { useEffect, useRef, useState } from 'react';
import { Download, FileText, Loader2, MoreHorizontal } from 'lucide-react';
import { Dialog, DialogContent, DialogDescription, DialogTitle } from '@/components/ui/dialog';
import { consentChanged, knotAllowed, type KnotBot } from '@/lib/knotService';
import { readKnotDocument, knotDocumentTitle, knotDocumentIdentity, knotDocumentDetails, knotDocumentStyle, knotDocumentReviewDescription, type KnotDocument } from '@/lib/knotDocuments';
import { DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuTrigger } from '@/components/ui/dropdown-menu';

export function KnotDocumentCards({ owner, bot, conversationID, documents }: { owner: string; bot: KnotBot; conversationID: string; documents: KnotDocument[] }) {
  const [selected, setSelected] = useState<KnotDocument | null>(null);
  const [active, setActive] = useState(document.visibilityState !== 'hidden');
  const [allowed, setAllowed] = useState(() => knotAllowed(owner));
  useEffect(() => {
    const clear = () => { setSelected(null); setAllowed(knotAllowed(owner)); };
    const visibility = () => { setActive(document.visibilityState !== 'hidden'); if (document.visibilityState === 'hidden') clear(); };
    const stored = (event: StorageEvent) => { if (event.key === null || event.key.startsWith(`knot_ai_consent_v3:${owner.toLowerCase()}`)) clear(); };
    clear();
    window.addEventListener(consentChanged, clear); window.addEventListener('storage', stored); document.addEventListener('visibilitychange', visibility);
    return () => { window.removeEventListener(consentChanged, clear); window.removeEventListener('storage', stored); document.removeEventListener('visibilitychange', visibility); };
  }, [owner, bot, conversationID]);
  const rows = active && allowed && knotAllowed(owner) ? documents : [];
  const current = selected && rows.find(d => d.id === selected.id);
  return <div className="space-y-2">{rows.map(file => <DocumentCard key={`${owner}:${bot}:${conversationID}:${file.id}`} owner={owner} bot={bot} conversationID={conversationID} file={file} open={() => setSelected(file)} />)}<Dialog open={!!current} onOpenChange={open => { if (!open) setSelected(null); }}><DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-3xl">{current && <DocumentDetail key={`${owner}:${bot}:${conversationID}:${current.id}`} owner={owner} bot={bot} conversationID={conversationID} file={current} />}</DialogContent></Dialog></div>;
}

type DocumentScope = { owner: string; bot: KnotBot; conversationID: string; file: KnotDocument };
const textFormats = new Set(['md', 'txt', 'csv', 'json', 'js', 'css', 'py', 'ts', 'yaml', 'yml', 'rst', 'tex', 'log']);

function DocumentCard({ owner, bot, conversationID, file, open }: DocumentScope & { open: () => void }) {
  const container = useRef<HTMLDivElement>(null);
  const [nearby, setNearby] = useState(false), [image, setImage] = useState<string | null>(null), [excerpt, setExcerpt] = useState<string | null>(null);
  const { save, saving, issue } = useOriginalDownload({ owner, bot, conversationID, file });
  const textFile = textFormats.has(file.format);
  const pagePreview = file.format === 'pdf' || (!textFile && file.proofPages[0] === 1);
  const title = knotDocumentTitle(file.name, file.title);
  const color = ({ pdf: 'text-red-500', docx: 'text-blue-500', xlsx: 'text-emerald-600', csv: 'text-emerald-600', pptx: 'text-orange-500' } as Record<string, string>)[file.format];
  useEffect(() => {
    if (!container.current) return;
    const observer = new IntersectionObserver(entries => { if (entries.some(entry => entry.isIntersecting)) { setNearby(true); observer.disconnect(); } }, { rootMargin: '200px' });
    observer.observe(container.current);
    return () => observer.disconnect();
  }, []);
  useEffect(() => {
    if (!nearby) return;
    const controller = new AbortController(); let disposed = false, url: string | null = null;
    setImage(null); setExcerpt(null);
    const load = async () => {
      if (pagePreview && file.proofPages[0] === 1) {
        const blob = await readKnotDocument(owner, bot, conversationID, file, controller.signal, 0);
        if (disposed || controller.signal.aborted) return;
        url = URL.createObjectURL(blob); setImage(url);
      } else if (textFile && file.size <= 1000000) {
        const blob = await readKnotDocument(owner, bot, conversationID, file, controller.signal);
        // A display-only excerpt of verified bytes, never document-completeness evidence.
        const value = (await blob.slice(0, 4096).text()).trim().slice(0, 420);
        if (!disposed && !controller.signal.aborted) setExcerpt(value);
      }
    };
    void load().catch(() => { /* The card still opens the original/download retry. */ });
    return () => { disposed = true; controller.abort(); if (url) URL.revokeObjectURL(url); };
  }, [nearby, owner, bot, conversationID, file, textFile, pagePreview]);
  return <div ref={container} className={`overflow-hidden rounded-[22px] bg-secondary ${pagePreview ? 'w-[85%] max-w-[374px]' : 'w-full max-w-[300px]'}`}>
    <div className="relative">
    <button type="button" onClick={open} aria-label={`Open ${title}`} className="block w-full text-left outline-none transition-colors hover:bg-foreground/[0.03] focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-ring">
      {pagePreview && <div className="px-1 pt-1"><div className="relative aspect-[1.5] overflow-hidden rounded-[18px] bg-muted">{image ? <img src={image} alt={`Document thumbnail, page 1 of ${file.pages}`} className="absolute inset-0 h-full w-full object-cover object-top" onError={() => setImage(null)} /> : <div className="flex h-full items-center justify-center text-muted-foreground/40"><FileText className="h-10 w-10" aria-label="Preview unavailable; open the original" /></div>}</div></div>}
      {textFile && <div className="px-1 pt-1"><div className="rounded-[18px] bg-foreground/[0.04] p-3"><p className="line-clamp-3 min-h-[60px] whitespace-pre-wrap break-words text-sm leading-5 text-muted-foreground">{excerpt || 'Open the original to read this file.'}</p></div></div>}
      <div className="flex min-h-[68px] items-center gap-3 py-3 pl-3.5 pr-12">
        <span aria-hidden="true" className="relative flex h-10 w-[30px] shrink-0 items-center justify-center"><FileText className={`h-10 w-[30px] ${color || 'text-zinc-300 dark:text-zinc-100'}`} fill="currentColor" strokeWidth={1} /><span className={`absolute inset-x-0 bottom-[7px] truncate px-0.5 text-center text-[7px] font-bold leading-none ${color ? 'text-white' : 'text-zinc-600'}`}>{file.format.toUpperCase()}</span></span>
        <span className="min-w-0 flex-1"><span className="block truncate text-base font-normal text-foreground">{title}</span><span className="mt-0.5 block truncate text-sm text-muted-foreground">{knotDocumentDetails(file)}</span></span>
      </div>
    </button>
    <DropdownMenu><DropdownMenuTrigger asChild><button type="button" aria-label={`Options for ${title}`} className="absolute bottom-3 right-1 flex h-11 w-11 items-center justify-center rounded-full text-muted-foreground outline-none hover:bg-foreground/5 focus-visible:ring-2 focus-visible:ring-ring"><MoreHorizontal className="h-5 w-5" /></button></DropdownMenuTrigger><DropdownMenuContent align="end"><DropdownMenuItem onSelect={open}><FileText className="mr-2 h-4 w-4" />Open document</DropdownMenuItem><DropdownMenuItem disabled={saving} onSelect={() => { void save(); }}><Download className="mr-2 h-4 w-4" />{saving ? 'Preparing download…' : 'Download original'}</DropdownMenuItem></DropdownMenuContent></DropdownMenu>
    </div>
    {issue && <p role="status" className="px-4 pb-3 text-xs text-muted-foreground">{issue}</p>}
  </div>;
}

function useOriginalDownload({ owner, bot, conversationID, file }: DocumentScope) {
  const [saving, setSaving] = useState(false), [issue, setIssue] = useState<string | null>(null);
  const download = useRef<AbortController | null>(null), downloadURL = useRef<string | null>(null);
  useEffect(() => () => { download.current?.abort(); if (downloadURL.current) URL.revokeObjectURL(downloadURL.current); }, []);
  const save = async () => {
    if (download.current) return;
    const controller = new AbortController(); download.current = controller; setSaving(true); setIssue(null);
    try {
      const blob = await readKnotDocument(owner, bot, conversationID, file, controller.signal);
      if (controller.signal.aborted) return;
      if (downloadURL.current) URL.revokeObjectURL(downloadURL.current);
      const url = URL.createObjectURL(blob); downloadURL.current = url;
      const link = document.createElement('a'); link.href = url; link.download = file.name;
      document.body.append(link); link.click(); link.remove();
    } catch { if (!controller.signal.aborted) setIssue('The file could not be downloaded.'); }
    finally { if (download.current === controller) { download.current = null; if (!controller.signal.aborted) setSaving(false); } }
  };
  return { save, saving, issue };
}

function DocumentDetail({ owner, bot, conversationID, file }: DocumentScope) {
  const [page, setPage] = useState(0), [image, setImage] = useState<string | null>(null), [issue, setIssue] = useState<string | null>(null), [loading, setLoading] = useState(true);
  const { save, saving, issue: downloadIssue } = useOriginalDownload({ owner, bot, conversationID, file });
  useEffect(() => {
    const controller = new AbortController(); let disposed = false, url: string | null = null;
    setImage(null); setIssue(null);
    if (!file.proofPages.length) { setLoading(false); return () => { disposed = true; controller.abort(); }; }
    setLoading(true);
    void readKnotDocument(owner, bot, conversationID, file, controller.signal, page).then(blob => {
      if (disposed || controller.signal.aborted) return;
      url = URL.createObjectURL(blob); setImage(url);
    }).catch(() => { if (!disposed && !controller.signal.aborted) setIssue('Preview unavailable.'); }).finally(() => { if (!disposed) setLoading(false); });
    return () => { disposed = true; controller.abort(); if (url) URL.revokeObjectURL(url); };
  }, [owner, bot, conversationID, file, page]);
  return <div className="space-y-4"><DialogTitle className="break-words pr-6 text-xl">{knotDocumentTitle(file.name, file.title)}</DialogTitle><DialogDescription>{knotDocumentStyle(file)} · {knotDocumentIdentity(file)}</DialogDescription>
    {loading && <div role="status" className="flex min-h-48 items-center justify-center gap-2 text-sm text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin motion-reduce:animate-none" />Loading captured preview…</div>}
    {image && <img src={image} alt={`Actual captured rendered proof, ${file.format === 'html' ? (page === 0 ? 'desktop' : 'mobile') : 'page ' + file.proofPages[page]}`} className="mx-auto max-h-[65dvh] max-w-full rounded-lg border border-border object-contain" />}
    {file.proofPages.length > 1 && <label className="flex min-h-11 items-center gap-3 text-sm">Rendered page<select className="min-h-11 rounded-xl border border-border bg-background px-3" value={page} onChange={e => setPage(Number(e.target.value))}>{file.proofPages.map((p, i) => <option key={p} value={i}>{file.format === 'html' ? (i === 0 ? 'Desktop' : 'Mobile') : `Page ${p}`}</option>)}</select></label>}
    <details className="rounded-xl border border-border px-4"><summary className="min-h-11 cursor-pointer py-3 text-sm">File identity & review details</summary><div className="space-y-2 pb-4 text-xs text-muted-foreground"><p className="leading-relaxed">{knotDocumentReviewDescription(file)}</p><p>SHA-256</p><p className="break-all font-mono">{file.sha256}</p><p>The receipt and hash bind the captured bytes. The original is retrieved by its recorded identity, never regenerated. Full command and source-path records remain in Events.</p></div></details>
    <button type="button" disabled={saving} onClick={() => { void save(); }} className="flex min-h-11 items-center gap-2 rounded-full bg-foreground px-5 text-sm font-semibold text-background disabled:opacity-50"><Download className="h-4 w-4" />{saving ? 'Preparing download…' : 'Download file'}</button>{(downloadIssue || issue) && <p role="status" className="text-xs text-muted-foreground">{downloadIssue || issue}</p>}
  </div>;
}
