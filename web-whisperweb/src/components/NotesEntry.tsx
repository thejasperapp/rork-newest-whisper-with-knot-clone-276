import { LockKeyhole, ArrowUpRight } from "lucide-react";
import { NotesAppIcon } from "@/components/NotesAppIcon";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";

/** Token-free handoff. Chat membership never grants document or signing authority. */
export function NotesEntry({ open, onOpenChange }: { open: boolean; onOpenChange: (value: boolean) => void }) {
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent className="sm:max-w-md">
    <DialogHeader><DialogTitle className="flex items-center gap-3"><NotesAppIcon className="h-[52px] w-[52px] rounded-[13px]" />Whisper Notes</DialogTitle></DialogHeader>
    <p className="text-xl font-semibold">Your documents. The right people.</p>
    <p className="text-sm leading-relaxed text-muted-foreground">Open Notes to review shared documents and manage individual invitations. Opening Notes doesn't send anything or give this chat document access.</p>
    <a href="https://notes.mydailywhisper.com/shared" target="_blank" rel="noopener noreferrer" className="flex min-h-12 items-center justify-center gap-2 rounded-full bg-foreground px-4 font-semibold text-background">Open Whisper Notes<ArrowUpRight className="h-4 w-4" /></a>
    <div className="space-y-2 rounded-2xl bg-secondary p-4"><p className="flex items-center gap-2 text-sm font-semibold"><LockKeyhole className="h-4 w-4" />Document & signature cards</p><p className="text-xs leading-relaxed text-muted-foreground">Reviewed cards will be available when Notes finishes its verified delivery connection. Restricted document links still work. Signing requires review and email verification in Notes.</p></div>
  </DialogContent></Dialog>;
}
