import { useEffect, useRef, useState } from 'react';
import { Globe, Keyboard, RefreshCw, Square, Maximize2 } from 'lucide-react';
import { Dialog, DialogContent, DialogTitle, DialogDescription, DialogTrigger } from '@/components/ui/dialog';
import { KnotPortrait } from '@/components/Knot';
import { supabase } from '@/lib/supabase';
import { consentChanged, knotAllowed, type KnotBot } from '@/lib/knotService';
import { knotBrowserRequest, KnotBrowserError, type BrowserAction, type KnotBrowserState } from '@/lib/knotBrowser';

type Props = { owner: string; bot: KnotBot; conversationID: string; compact?: boolean; enabled?: boolean; onOpen?: () => void };
const button = 'min-h-11 rounded-full border border-white/20 px-4 text-sm font-medium transition-colors hover:bg-white/10 disabled:opacity-40';
export function KnotBrowserView(props: Props) {
  return <BrowserSession key={`${props.owner}:${props.bot}:${props.conversationID}`} {...props} />;
}
function BrowserSession({ owner, bot, conversationID, compact = false, enabled = true, onOpen }: Props) {
  const [expanded, setExpanded] = useState(false);
  const [state, setState] = useState<KnotBrowserState | null>(null), [blob, setBlob] = useState<Blob | null>(null), [image, setImage] = useState<string | null>(null);
  const [capture, setCapture] = useState<Date | null>(null), [issue, setIssue] = useState<string | null>(null), [busy, setBusy] = useState(false), [revision, setRevision] = useState(0);
  const [frameIssue, setFrameIssue] = useState<string | null>(null);
  const frameEpoch = useRef(0), stopping = useRef(false);
  const [address, setAddress] = useState(''), [text, setText] = useState(''), [controls, setControls] = useState(false), [invalid, setInvalid] = useState(false);
  const invalidRef = useRef(false), mutationBusy = useRef(false), epoch = useRef(0), mutation = useRef<AbortController | null>(null), polling = useRef<AbortController | null>(null);
  useEffect(() => {
    if (!blob) { setImage(null); return; }
    const url = URL.createObjectURL(blob); setImage(url);
    return () => URL.revokeObjectURL(url);
  }, [blob]);
  useEffect(() => {
    invalidRef.current = false;
    const clear = () => {
      invalidRef.current = true; epoch.current++; frameEpoch.current++; mutation.current?.abort(); polling.current?.abort();
      setExpanded(false); setInvalid(true); setBlob(null); setImage(null); setState(null); setText(''); setAddress(''); setControls(false);
    };
    const storage = (event: StorageEvent) => { if (event.key === null || event.key.startsWith(`knot_ai_consent_v3:${owner.toLowerCase()}`)) clear(); };
    const { data } = supabase.auth.onAuthStateChange((_event, session) => { if (session?.user.id !== owner) clear(); });
    window.addEventListener(consentChanged, clear); window.addEventListener('storage', storage);
    return () => { invalidRef.current = true; epoch.current++; frameEpoch.current++; mutation.current?.abort(); polling.current?.abort(); data.subscription.unsubscribe(); window.removeEventListener(consentChanged, clear); window.removeEventListener('storage', storage); };
  }, [owner]);
  useEffect(() => {
    if (!enabled || invalid || !knotAllowed(owner)) { setBlob(null); setImage(null); return; }
    let disposed = false, timer: ReturnType<typeof setTimeout> | undefined;
    const controller = new AbortController(); polling.current = controller;
    const valid = () => !disposed && !invalidRef.current && !controller.signal.aborted && document.visibilityState === 'visible';
    const load = async () => {
      if (!valid()) return;
      try {
        if (!stopping.current) {
          const snapshot = frameEpoch.current;
          const validFrame = () => valid() && !stopping.current && snapshot === frameEpoch.current;
          const next = await knotBrowserRequest(owner, bot, conversationID, 'state', controller.signal) as KnotBrowserState;
          if (!validFrame()) return;
          setState(next);
          if (next.outcomeUncertain) { setBlob(null); setImage(null); setCapture(null); return; }
          if (next.live) {
            const frame = await knotBrowserRequest(owner, bot, conversationID, 'screenshot', controller.signal) as Blob;
            if (!validFrame()) return;
            setBlob(frame); setCapture(new Date()); setFrameIssue(null);
          } else { setBlob(null); setImage(null); setCapture(null); setFrameIssue(null); }
        }
      } catch {
        if (valid() && !stopping.current) setFrameIssue('Live image paused. Reconnecting; no input is repeated.');
      } finally { if (valid()) timer = setTimeout(() => { void load(); }, 1500); }
    };
    const visibility = () => {
      clearTimeout(timer); epoch.current++; frameEpoch.current++; controller.abort(); mutation.current?.abort(); setBlob(null); setImage(null); setControls(false);
      if (document.visibilityState === 'visible') setRevision(v => v + 1);
    };
    document.addEventListener('visibilitychange', visibility); void load();
    return () => { disposed = true; controller.abort(); clearTimeout(timer); document.removeEventListener('visibilitychange', visibility); };
  }, [owner, bot, conversationID, compact, enabled, revision, invalid]);
  useEffect(() => { if (!enabled) { epoch.current++; mutation.current?.abort(); setControls(false); setText(''); } }, [enabled]);
  const perform = async (action: BrowserAction, fields: Record<string, unknown> = {}) => {
    if (!enabled || invalidRef.current || mutationBusy.current || document.visibilityState !== 'visible' || !knotAllowed(owner)) return;
    if (action === 'stop') { frameEpoch.current++; stopping.current = true; setBlob(null); setImage(null); setCapture(null); }
    const capturedEpoch = epoch.current; mutationBusy.current = true; setBusy(true); setIssue(null);
    const controller = new AbortController(); mutation.current = controller;
    const valid = () => !invalidRef.current && capturedEpoch === epoch.current && !controller.signal.aborted && document.visibilityState === 'visible';
    try {
      await knotBrowserRequest(owner, bot, conversationID, action, controller.signal, fields);
      if (valid()) {
        if (action === 'stop') { setBlob(null); setImage(null); setState({ live: false }); setControls(false); }
        if (action === 'input') setText('');
      }
    } catch (error) {
      if (valid()) setIssue(error instanceof KnotBrowserError && error.code === 'invalid_browser_url' ? 'Use a public website address, without sign-in credentials in the address.' : error instanceof KnotBrowserError && error.code === 'browser_busy' ? 'Another browser action is still in progress. Refresh before choosing what to do next.' : 'This action wasn’t confirmed. It has not been repeated. Refresh to inspect the browser, or explicitly stop it before continuing.');
    } finally {
      mutationBusy.current = false; stopping.current = false;
      if (!invalidRef.current) { setBusy(false); setRevision(v => v + 1); }
    }
  };
  const input = (value: Record<string, unknown>) => { if (image) void perform('input', { input: value }); };
  const live = state?.live === true;
  const blocked = busy || invalid || !!state?.outcomeUncertain || !!state?.operationPending;
  // The compact card is present only with an actual, current-scope rendered image.
  if (compact && (!enabled || invalid || !live || !image)) return null;
  const content = (wide: boolean) => <section aria-label="Browser" className={`w-full space-y-4 rounded-3xl border border-white/10 bg-[#191b20] p-4 text-white ${wide ? 'max-w-none' : 'max-w-2xl'}`}>
    <div className="flex items-center gap-3"><span className="rounded-xl bg-white/10 p-3"><Globe className="h-5 w-5" /></span><div className="min-w-0 flex-1"><h3 className="text-sm font-semibold">Browser</h3><p className="truncate text-xs text-white/60">{invalid ? 'Connection cleared' : frameIssue ? 'Reconnecting · last frame' : live ? (busy || state?.operationPending ? 'Browser working · updating frames' : 'Browser running · updating frames') : state ? 'Browser stopped' : issue ? 'Browser unavailable' : 'Checking browser…'}</p></div>{!compact && !wide && <DialogTrigger asChild><button type="button" aria-label="Expand browser" className={`${button} px-3`} disabled={invalid}><Maximize2 className="h-4 w-4" /></button></DialogTrigger>}{!compact && <button type="button" aria-label="Refresh browser" className={`${button} px-3`} disabled={busy || invalid} onClick={() => setRevision(v => v + 1)}><RefreshCw className="h-4 w-4" /></button>}</div>
    {image ? <div className="overflow-hidden rounded-2xl border border-white/10 bg-black"><img src={image} alt="Rendered page in your conversation’s browser" width={1280} height={800} draggable={false} className={`block w-full object-contain ${wide ? 'h-[min(65dvh,800px)]' : 'h-auto'} ${controls && !blocked ? 'cursor-crosshair' : ''}`} onClick={event => { if (!compact && controls && !blocked) { const rect = event.currentTarget.getBoundingClientRect(); const scale = Math.min(rect.width / 1280, rect.height / 800); if (scale <= 0) return; const x = (event.clientX - rect.left - (rect.width - 1280 * scale) / 2) / scale; const y = (event.clientY - rect.top - (rect.height - 800 * scale) / 2) / scale; if (x < 0 || y < 0 || x >= 1280 || y >= 800) return; input({ kind: 'click', x: Math.floor(x), y: Math.floor(y) }); } }} /></div> : !compact && <div className="flex min-h-36 flex-col items-center justify-center gap-3 rounded-2xl border border-dashed border-white/15 p-6 text-center"><KnotPortrait size={72} expression="calm" /><p className="text-base font-medium">{invalid ? 'Connection cleared' : live ? 'Waiting for browser image' : state ? 'Ready to start' : 'Checking connection'}</p><p className="text-sm text-white/60">{invalid ? 'Reopen Computer to reconnect.' : live ? 'Only the actual remote page appears here.' : 'Your browser starts only when you choose Start browser.'}</p></div>}
    {image && capture && <p className="truncate text-xs text-white/50">{state?.title || 'Rendered page'} · {frameIssue ? 'Last frame' : 'Captured'} {capture.toLocaleTimeString(undefined, { hour: 'numeric', minute: '2-digit', second: '2-digit' })}</p>}
    {frameIssue && <p role="status" className="text-xs text-amber-200">{frameIssue}</p>}
    {compact ? <button type="button" className={`${button} w-full`} onClick={onOpen}>Open browser</button> : <>
      {issue && <p role="status" className="text-sm leading-relaxed text-amber-200">{issue}</p>}
      {state?.outcomeUncertain && <p role="status" className="text-sm text-amber-200">A previous action is unconfirmed. Only an explicit Stop can release this safety hold; refreshing never repeats input.</p>}
      <div className="flex flex-wrap gap-2">{!live && !state?.outcomeUncertain && <button type="button" className={button} disabled={blocked || !state} onClick={() => { void perform('start'); }}>Start browser</button>}{(live || state?.outcomeUncertain) && <button type="button" className={`${button} inline-flex items-center gap-2`} disabled={busy || invalid || state?.operationPending} onClick={() => { void perform('stop'); }}><Square className="h-3.5 w-3.5" />Stop browser</button>}{live && <button type="button" aria-expanded={controls} className={`${button} inline-flex items-center gap-2`} disabled={blocked} onClick={() => setControls(v => !v)}><Keyboard className="h-4 w-4" />Keyboard & pointer</button>}</div>
      {live && <form className="flex flex-wrap gap-2" onSubmit={event => { event.preventDefault(); void perform('navigate', { url: address.trim() }); }}><input aria-label="Website address" placeholder="Website address" type="text" inputMode="url" autoComplete="off" value={address} onChange={event => setAddress(event.target.value)} disabled={blocked} className="min-h-11 min-w-0 flex-1 rounded-xl border border-white/15 bg-white/5 px-3 text-sm text-white placeholder:text-white/40" /><button className={button} disabled={blocked || !address.trim()}>Go</button></form>}
      {live && controls && <div className="space-y-3 border-t border-white/10 pt-4"><p className="text-xs leading-relaxed text-white/60">Manual controls, not exclusive takeover. Tap the page to focus or click, then type below. Typed input is sent to the remote browser; it may become part of the page Knot can read.</p><form className="flex gap-2" onSubmit={event => { event.preventDefault(); input({ kind: 'type', text }); }}><input aria-label="Text for the browser" autoComplete="off" value={text} maxLength={4000} disabled={blocked} onChange={event => setText(event.target.value)} className="min-h-11 min-w-0 flex-1 rounded-xl border border-white/15 bg-white/5 px-3 text-sm" /><button className={button} disabled={blocked || !text}>Type</button></form><div className="flex flex-wrap gap-2">{['Enter','Tab','Escape','Backspace','ArrowLeft','ArrowRight','ArrowUp','ArrowDown'].map(key => <button type="button" key={key} className={button} disabled={blocked} onClick={() => input({ kind:'key', key })}>{key.replace('Arrow', '')}</button>)}<button type="button" className={button} disabled={blocked} onClick={() => input({ kind:'scroll', dy:-500 })}>Scroll up</button><button type="button" className={button} disabled={blocked} onClick={() => input({ kind:'scroll', dy:500 })}>Scroll down</button></div></div>}
      <p className="text-xs leading-relaxed text-white/50">Pages and input go through Whisper to the operator-managed Knot browser at knot-shell.mydailywhisper.com. While AI sharing is on, Knot can read this page’s visible text through Whisper’s live Knot service and Rork AI Cloud (via Vercel AI Gateway) to OpenAI. Your profile—cookies, sign-ins and site storage—persists in your account’s remote workspace across tasks and bots. The process starts on demand and may stop after 30 idle minutes. Stop closes the process; it does not erase the profile. Images stay in memory only. Personal-account actions keep their separate permissions. Turning off AI sharing clears this viewer and stops new input, but does not erase the profile or close the remote process; use Stop browser first.</p>
    </>}
  </section>;
  return <Dialog open={expanded} onOpenChange={setExpanded}>
    <div className={expanded ? 'invisible' : undefined}>{content(false)}</div>
    <DialogContent className="z-[60] block h-[96dvh] w-[calc(100%-16px)] max-w-none overflow-y-auto rounded-3xl border-white/10 bg-[#111318] p-3 pt-12 text-white sm:max-w-[1440px] sm:rounded-3xl" overlayClassName="z-[60]">
      <DialogTitle className="sr-only">Knot Computer</DialogTitle>
      <DialogDescription className="sr-only">Your conversation’s real remote browser. Manual controls only. Opening this viewer never starts the browser.</DialogDescription>
      {content(true)}
    </DialogContent>
  </Dialog>;
}
