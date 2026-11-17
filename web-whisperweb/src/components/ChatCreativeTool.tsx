import { useRef, useState, type PointerEvent } from "react";
import { Loader2, RotateCcw, Send, Wand2 } from "lucide-react";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { uploadChatMedia } from "@/lib/chatMedia";
import { emberImagine } from "@/lib/ember";
import { buildNearbyPayload, encodeMap } from "@/lib/dmEmber";
import { EmberDmCard } from "@/components/EmberDmCard";

export type ChatCreativeMode = "draw" | "imagine" | "stickers" | "nearby";
const titles = { draw: "Draw", imagine: "Imagine", stickers: "Stickers", nearby: "Nearby" };
const stickers = ["ember", "ember_headphones", "ghost_beach", "ghost_bolt", "ghost_book", "ghost_boost", "ghost_cookie", "ghost_couple", "ghost_crown", "ghost_dragon", "ghost_home", "ghost_king", "ghost_kraken", "ghost_sad", "ghost_send", "ghost_sleepy", "ghost_trophy", "jasper_beachball"];

/** Preparation is private; only the explicit Send action writes to the existing guarded chat wire. */
export function ChatCreativeTool({ mode, owner, thread, onClose, onSend }: {
  mode: ChatCreativeMode; owner: string; thread: string; onClose: () => void;
  onSend: (body: string, check: () => void) => Promise<boolean>;
}) {
  const canvas = useRef<HTMLCanvasElement>(null);
  const pointer = useRef<number | null>(null);
  const [ink, setInk] = useState("#202729");
  const [hasDrawing, setHasDrawing] = useState(false);
  const [prompt, setPrompt] = useState("");
  const [preview, setPreview] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const begin = useChatOperationGuard(owner, thread);
  const point = (event: PointerEvent<HTMLCanvasElement>): [number, number] => {
    const rect = event.currentTarget.getBoundingClientRect();
    return [(event.clientX - rect.left) * 600 / rect.width, (event.clientY - rect.top) * 420 / rect.height];
  };
  const draw = (event: PointerEvent<HTMLCanvasElement>, start: boolean): void => {
    if (busy || (!start && pointer.current !== event.pointerId)) return;
    const context = event.currentTarget.getContext("2d");
    if (!context) return;
    const [x, y] = point(event);
    if (start) {
      pointer.current = event.pointerId;
      event.currentTarget.setPointerCapture(event.pointerId);
      context.beginPath(); context.moveTo(x, y); context.lineTo(x + 0.1, y + 0.1);
    } else context.lineTo(x, y);
    context.lineWidth = 5; context.lineCap = "round"; context.lineJoin = "round"; context.strokeStyle = ink; context.stroke(); setHasDrawing(true);
  };
  const prepare = async (): Promise<void> => {
    if (busy) return;
    const check = begin(); setBusy(true); setError(null);
    try {
      if (mode === "nearby") {
        const result = await buildNearbyPayload(); check(); setPreview(encodeMap(result));
      } else {
        const image = await emberImagine(prompt, check); check();
        if (!image) throw new Error("Imagine is unavailable. Try again in a moment.");
        setPreview(image);
      }
    } catch (reason) { try { check(); setError(reason instanceof Error ? reason.message : "Couldn’t prepare this attachment."); } catch { /* Previous account/thread. */ } }
    finally { try { check(); setBusy(false); } catch { /* Closed. */ } }
  };
  const send = async (): Promise<void> => {
    if (busy) return;
    const check = begin(); setBusy(true); setError(null);
    try {
      let body = preview;
      if (mode === "draw") {
        const source = canvas.current;
        if (!source || !hasDrawing) throw new Error("Draw something first.");
        const opaque = document.createElement("canvas"); opaque.width = 600; opaque.height = 420;
        const context = opaque.getContext("2d");
        if (!context) throw new Error("Drawing export is unavailable.");
        context.fillStyle = "#FFFFFF"; context.fillRect(0, 0, 600, 420); context.drawImage(source, 0, 0);
        const blob = await new Promise<Blob | null>(resolve => opaque.toBlob(resolve, "image/png")); check();
        if (!blob) throw new Error("Couldn’t export your drawing.");
        body = await uploadChatMedia(new File([blob], "drawing.png", { type: "image/png" }), owner, check);
      } else if (mode === "imagine" && body) {
        // Persist generated data/temporary URLs as real chat attachments before sharing.
        const result = await fetch(body); check();
        if (!result.ok) throw new Error("Couldn’t save this image. Try generating it again.");
        const blob = await result.blob(); check();
        body = await uploadChatMedia(new File([blob], "imagine.png", { type: blob.type || "image/png" }), owner, check);
      }
      if (!body) throw new Error("Choose an attachment first.");
      check();
      if (!await onSend(body, check)) throw new Error("The attachment wasn’t sent. Please try again.");
      check(); onClose();
    } catch (reason) { try { check(); setError(reason instanceof Error ? reason.message : "Couldn’t send this attachment."); } catch { /* Previous account/thread. */ } }
    finally { try { check(); setBusy(false); } catch { /* Closed. */ } }
  };
  return <Dialog open onOpenChange={open => { if (!open && !busy) onClose(); }}><DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-xl" onEscapeKeyDown={event => { if (busy) event.preventDefault(); }} onPointerDownOutside={event => { if (busy) event.preventDefault(); }}>
    <DialogHeader><DialogTitle>{titles[mode]}</DialogTitle><DialogDescription>{mode === "nearby" ? "Find nearby food using your location. Review the map before sharing it with this chat." : "Prepare an attachment, then choose Send to conversation. Nothing is shared automatically."}</DialogDescription></DialogHeader>
    {mode === "draw" && <>
      <canvas ref={canvas} width={600} height={420} aria-label="Drawing canvas" className="w-full touch-none rounded-2xl border border-border bg-white" onPointerDown={event => draw(event, true)} onPointerMove={event => draw(event, false)} onPointerUp={() => { pointer.current = null; }} onPointerCancel={() => { pointer.current = null; }} />
      <div className="flex items-center gap-3"><label className="flex min-h-11 items-center gap-2 text-sm">Ink<input type="color" aria-label="Drawing ink color" value={ink} onChange={event => setInk(event.target.value)} disabled={busy} /></label><button type="button" disabled={busy} className="ml-auto flex min-h-11 items-center gap-2 text-sm" onClick={() => { canvas.current?.getContext("2d")?.clearRect(0, 0, 600, 420); setHasDrawing(false); }}><RotateCcw className="h-4 w-4" />Clear</button></div>
    </>}
    {mode === "stickers" && <div className="grid grid-cols-4 gap-2">{stickers.map(name => <button type="button" key={name} disabled={busy} aria-label={`Choose ${name.replace(/_/g, " ")} sticker`} aria-pressed={preview === `jasper-sticker://${name}`} className={`rounded-xl border p-2 ${preview === `jasper-sticker://${name}` ? "border-foreground bg-secondary" : "border-transparent"}`} onClick={() => setPreview(`jasper-sticker://${name}`)}><img src={`/stickers/${name}.png`} alt="" className="aspect-square w-full object-contain" /></button>)}</div>}
    {mode === "imagine" && <><label className="text-sm font-medium" htmlFor="chat-imagine-prompt">Describe your image</label><textarea id="chat-imagine-prompt" value={prompt} maxLength={1200} disabled={busy} onChange={event => { setPrompt(event.target.value); setPreview(null); }} className="min-h-24 rounded-xl border border-border bg-background p-3 text-sm" /><button type="button" disabled={busy || !prompt.trim()} className="flex min-h-11 items-center justify-center gap-2 rounded-full bg-secondary text-sm disabled:opacity-50" onClick={() => void prepare()}><Wand2 className="h-4 w-4" />{busy ? "Working…" : "Generate image"}</button>{preview && <img src={preview} alt="Generated preview" className="max-h-72 w-full rounded-xl object-contain" />}</>}
    {mode === "nearby" && <>{preview ? <EmberDmCard body={preview} mine /> : <button type="button" className="min-h-11 rounded-full bg-secondary text-sm" disabled={busy} onClick={() => void prepare()}>{busy ? "Finding nearby places…" : "Use my location"}</button>}</>}
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <button type="button" disabled={busy || (mode === "draw" ? !hasDrawing : !preview)} onClick={() => void send()} className="flex min-h-11 items-center justify-center gap-2 rounded-full bg-foreground px-4 text-sm font-semibold text-background disabled:opacity-50">{busy ? <Loader2 className="h-4 w-4 animate-spin" /> : <Send className="h-4 w-4" />}Send to conversation</button>
  </DialogContent></Dialog>;
}
