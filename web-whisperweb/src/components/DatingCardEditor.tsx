import { useEffect, useState } from "react";
import { Heart } from "lucide-react";
import { toast } from "sonner";

import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Textarea } from "@/components/ui/textarea";
import { Button } from "@/components/ui/button";
import {
  DATING_CARD_QUESTIONS,
  loadDatingCardLocal,
  saveDatingCard,
  syncDatingCardFromCloud,
  type DatingCardAnswers,
} from "@/lib/datingCards";

interface DatingCardEditorProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  userId: string;
  onSaved?: () => void;
}

/**
 * The dating card — five saved answers (what you're looking for, interests,
 * non-negotiables, ideal first date, fun fact). Jasper judges speed dates
 * from both people's cards + the live conversation. Mirrors iOS
 * `WhisperDatingCardEditorSheet`.
 */
export function DatingCardEditor({ open, onOpenChange, userId, onSaved }: DatingCardEditorProps) {
  const [answers, setAnswers] = useState<DatingCardAnswers>({});
  const [saving, setSaving] = useState<boolean>(false);

  useEffect(() => {
    if (!open || !userId) return;
    setAnswers(loadDatingCardLocal(userId));
    // Cloud copy fills in quietly underneath (typed edits win).
    void syncDatingCardFromCloud(userId).then((cloud) =>
      setAnswers((cur) => ({ ...cloud, ...cur }))
    );
  }, [open, userId]);

  const save = async (): Promise<void> => {
    setSaving(true);
    await saveDatingCard(userId, answers);
    setSaving(false);
    toast.success("Dating card saved 💘");
    onOpenChange(false);
    onSaved?.();
  };

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-h-[85vh] max-w-md overflow-y-auto">
        <DialogHeader>
          <DialogTitle className="flex items-center gap-2">
            <Heart className="h-4 w-4 fill-rose-500 text-rose-500" />
            Your dating card
          </DialogTitle>
        </DialogHeader>
        <p className="-mt-1 text-[12.5px] leading-snug text-muted-foreground">
          Saved once, used every speed date — Jasper judges compatibility from
          both people's cards and the conversation.
        </p>
        <div className="space-y-3">
          {DATING_CARD_QUESTIONS.map((q) => (
            <div key={q.id}>
              <label className="text-[12px] font-bold text-rose-500">{q.label}</label>
              <Textarea
                value={answers[q.id] ?? ""}
                onChange={(e) =>
                  setAnswers((cur) => ({ ...cur, [q.id]: e.target.value }))
                }
                placeholder={q.placeholder}
                rows={2}
                maxLength={240}
                className="mt-1 resize-none"
              />
            </div>
          ))}
        </div>
        <Button
          onClick={() => void save()}
          disabled={saving}
          className="w-full bg-rose-500 font-bold text-white hover:bg-rose-600"
        >
          {saving ? "Saving…" : "Save my card"}
        </Button>
      </DialogContent>
    </Dialog>
  );
}
