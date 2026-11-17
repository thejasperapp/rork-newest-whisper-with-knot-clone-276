import { useEffect, useRef, useState } from "react";
import { useMutation } from "@tanstack/react-query";
import { ImagePlus, Sparkles } from "lucide-react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { GroupThemeSurface } from "@/components/GroupThemeSurface";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { usePersonalChatAppearance } from "@/hooks/usePersonalChatAppearance";
import { appearanceEvent, appearanceKey, generateWallpaper, saveWallpaper } from "@/lib/chatWallpapers";
import { groupThemePresets, themeTitle, type GroupThemeDesign } from "@/lib/groupThemes";
import { cn } from "@/lib/utils";

export function PersonalChatSettings({ accountID, thread, colors = true }: { accountID: string; thread: string; colors?: boolean }) {
  const [open, setOpen] = useState<boolean>(false);
  const current = usePersonalChatAppearance(accountID, thread);
  const [draft, setDraft] = useState<GroupThemeDesign>(current.design);
  const [prompt, setPrompt] = useState<string>("");
  const [preview, setPreview] = useState<{ blob: Blob; url: string } | null>(null);
  const active = useRef<AbortController | null>(null);
  const capture = useChatOperationGuard(accountID, thread);
  useEffect(() => () => { active.current?.abort(); }, []);
  useEffect(() => () => { if (preview) URL.revokeObjectURL(preview.url); }, [preview]);
  const generate = useMutation({ mutationFn: async () => {
    const check = capture();
    active.current?.abort(); const controller = new AbortController(); active.current = controller;
    const blob = await generateWallpaper(accountID, prompt, controller.signal);
    check(); if (controller.signal.aborted) return;
    setPreview({ blob, url: URL.createObjectURL(blob) });
  }, retry: false });
  const save = useMutation({ mutationFn: async (remove: boolean) => {
    const check = capture(); check();
    const key = appearanceKey(accountID, thread);
    active.current?.abort(); const controller = new AbortController(); active.current = controller;
    if (remove || preview) await saveWallpaper(key, remove ? null : preview!.blob, check, controller.signal);
    if (controller.signal.aborted) return;
    check();
    if (colors && !remove) localStorage.setItem(key, JSON.stringify(draft));
    window.dispatchEvent(new Event(appearanceEvent));
    setPreview(null); setOpen(false);
  }, retry: false });
  const busy = generate.isPending || save.isPending;
  return <Dialog open={open} onOpenChange={value => { if (save.isPending) return; if (!value) { active.current?.abort(); setPreview(null); } setOpen(value); }}>
    <button type="button" className="flex min-h-11 items-center gap-2 rounded-full border border-border bg-background/80 px-3 text-xs font-medium" onClick={() => { setDraft(current.design); generate.reset(); save.reset(); setOpen(true); }}><ImagePlus className="h-4 w-4" />{colors ? "Themes & wallpaper" : "My wallpaper"}</button>
    <DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-xl">
      <DialogHeader><DialogTitle>A world behind your words</DialogTitle></DialogHeader>
      <GroupThemeSurface design={draft} wallpaper={preview?.url ?? current.wallpaper} className="space-y-6 p-6"><p className="group-incoming w-fit rounded-2xl p-3 text-sm">A little change of scenery?</p><p className="group-outgoing ml-auto w-fit rounded-2xl p-3 text-sm">This feels like us.</p></GroupThemeSurface>
      {colors && <div className="grid grid-cols-2 gap-2 sm:grid-cols-3">{groupThemePresets.map(preset => <button type="button" disabled={busy} key={preset} onClick={() => setDraft({ version: 1, preset, title: themeTitle(preset) })} aria-pressed={draft.preset === preset} className={cn("min-h-11 rounded-xl border px-2 text-sm", draft.preset === preset ? "border-foreground font-semibold" : "border-border")}>{themeTitle(preset)}</button>)}</div>}
      <label className="space-y-2 text-sm font-medium">Design with AI<textarea value={prompt} onChange={e => setPrompt(e.target.value)} maxLength={400} rows={3} disabled={busy} placeholder="Pearl dunes, sea glass, a moonlit garden…" className="block w-full resize-none rounded-xl border border-border bg-secondary p-3 font-normal" /></label>
      <p className="text-xs leading-relaxed text-muted-foreground">Only your prompt goes to AI—not your messages or Notes. Generated wallpapers are personal and saved in this browser, not shared with the group or synced to another device.</p>
      <button type="button" disabled={busy || !prompt.trim()} onClick={() => generate.mutate()} className="flex min-h-11 items-center justify-center gap-2 rounded-full border border-border px-4 text-sm disabled:opacity-50"><Sparkles className="h-4 w-4" />{generate.isPending ? "Creating wallpaper…" : "Generate preview"}</button>
      {(generate.error || save.error) && <p role="alert" className="text-sm text-destructive">{(generate.error ?? save.error)?.message}</p>}
      <button type="button" disabled={busy || (!colors && !preview)} onClick={() => save.mutate(false)} className="min-h-12 rounded-full bg-foreground px-4 font-semibold text-background disabled:opacity-50">Apply for me</button>
      <button type="button" disabled={busy} onClick={() => save.mutate(true)} className="min-h-11 text-sm text-muted-foreground">Remove personal wallpaper</button>
    </DialogContent>
  </Dialog>;
}
