import { useState } from "react";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useChatOperationGuard } from "@/hooks/useChatOperationGuard";
import { defaultJasperTuning, loadJasperTuning, saveJasperTuning } from "@/lib/jasperTuning";

export function JasperTuningDialog({ accountID, onClose }: { accountID: string; onClose: () => void }) {
  const [initial] = useState(() => loadJasperTuning(accountID));
  const [more, setMore] = useState<string>(initial.more.join("\n"));
  const [less, setLess] = useState<string>(initial.less.join("\n"));
  const [strength, setStrength] = useState<number>(initial.strength);
  const [error, setError] = useState<string | null>(null);
  const [confirmReset, setConfirmReset] = useState<boolean>(false);
  const capture = useChatOperationGuard(accountID, "jasper-tuning");
  return <Dialog open onOpenChange={value => { if (!value) onClose(); }}><DialogContent className="max-h-[90dvh] overflow-y-auto sm:max-w-lg">
    <DialogHeader><DialogTitle>Tune your Knot</DialogTitle></DialogHeader>
    <p className="text-sm text-muted-foreground">Same Knot, more your style. These preferences shape new text replies—not your feed, permissions, or an existing voice session. Saved in this browser.</p>
    <label className="space-y-2 text-sm font-semibold">Turn up<textarea value={more} onChange={e => setMore(e.target.value)} rows={3} maxLength={647} placeholder="Practical examples\nShorter answers" className="block w-full resize-none rounded-2xl border border-border bg-secondary p-3 font-normal" /></label>
    <label className="space-y-2 text-sm font-semibold">Turn down<textarea value={less} onChange={e => setLess(e.target.value)} rows={3} maxLength={647} placeholder="Jargon\nLong introductions" className="block w-full resize-none rounded-2xl border border-border bg-secondary p-3 font-normal" /></label>
    <p className="text-xs text-muted-foreground">One preference per line, up to eight per list and 80 characters per preference.</p>
    <label className="space-y-2 text-sm">Tuning strength · {Math.round(strength * 100)}%<input type="range" min={0} max={1} step={0.05} value={strength} onChange={e => setStrength(Number(e.target.value))} className="block min-h-11 w-full accent-orange-500" /></label>
    {error && <p role="alert" className="text-sm text-destructive">{error}</p>}
    <button type="button" className="min-h-12 rounded-full bg-foreground font-semibold text-background" onClick={() => {
      try {
        capture()();
        saveJasperTuning(accountID, { version: 1, more: more.split("\n").map(v => v.trim()).filter(Boolean), less: less.split("\n").map(v => v.trim()).filter(Boolean), strength });
        onClose();
      } catch (failure) { setError(failure instanceof Error ? failure.message : "Couldn't save preferences."); }
    }}>Save tuning</button>
    <button type="button" className="min-h-11 text-sm text-muted-foreground" onClick={() => {
      if (!confirmReset) { setConfirmReset(true); return; }
      setMore(defaultJasperTuning.more.join("\n")); setLess(""); setStrength(defaultJasperTuning.strength); setConfirmReset(false);
    }}>{confirmReset ? "Confirm reset draft" : "Reset tuning"}</button>
  </DialogContent></Dialog>;
}
