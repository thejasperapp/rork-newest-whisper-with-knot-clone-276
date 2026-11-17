import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import { Button } from "./ui/button";
import type { MeetingSaveStatus } from "@/hooks/useMeetingHost";

/** Remains outside the minimized room so finalization and failures cannot disappear on navigation. */
export function MeetingSaveBanner({ status, onOpen }: { status: MeetingSaveStatus; onOpen: () => void }): JSX.Element {
  const [container, setContainer] = useState<Element>(() => document.fullscreenElement ?? document.body);
  useEffect(() => { const changed = (): void => setContainer(document.fullscreenElement ?? document.body); document.addEventListener("fullscreenchange", changed); return () => document.removeEventListener("fullscreenchange", changed); }, []);
  const saving = status.update.state === "saving" || status.update.state === "starting";
  const ready = status.update.state === "ready";
  return createPortal(<aside className="fixed inset-x-4 bottom-6 z-[110] mx-auto max-w-lg rounded-2xl border border-border bg-background p-4 text-foreground shadow-xl" aria-label="Recording save status">
    <p role="status" aria-live="polite" className="text-sm font-semibold">{saving ? "Finishing your recording…" : ready ? "Recording saved to this browser" : "Recording needs attention"}</p>
    <p className="mt-1 text-xs leading-relaxed text-muted-foreground">{status.update.error ?? (saving ? "Capture has stopped. Keep this tab open while the saved file is checked." : ready ? "Saved media was reopened successfully. Cloud backup is separate; export before clearing browser data." : "Open Notebook to check retained media and export any available backup audio.")}</p>
    <Button className="mt-3 h-11 w-full rounded-full" disabled={saving} onClick={onOpen}>{ready ? "Review recording in Notebook" : "Check retained parts in Notebook"}</Button>
  </aside>, container);
}
