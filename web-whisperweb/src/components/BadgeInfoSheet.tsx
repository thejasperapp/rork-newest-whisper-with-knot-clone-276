import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import type { BadgeKind } from "@/lib/badges";
export type BadgeFocus = BadgeKind | "liar" | "verified" | null;
export function BadgeInfoSheet({ open, onOpenChange }: { open: boolean; onOpenChange: (open: boolean) => void; focus?: BadgeFocus }) {
  return <Dialog open={open} onOpenChange={onOpenChange}><DialogContent className="sm:max-w-md"><DialogHeader><DialogTitle>Identity, not a trust score</DialogTitle></DialogHeader>
    <p className="text-sm text-muted-foreground">One indicator beside a name identifies a verified identity or a Whisper staff role: Moderator, Admin, or Owner. It does not guarantee safety, expertise, or that a post is correct.</p>
    <p className="text-sm text-muted-foreground">Professional roles appear as profile text. Age, membership, account age, and report counts are not public badges. Paid access and professional tools are unchanged.</p>
    <p className="text-sm text-muted-foreground">Legacy account labels have been retired. A reviewed correction belongs to a particular post, never to a person’s name. Optional AI analysis is not a moderation decision.</p>
  </DialogContent></Dialog>;
}
