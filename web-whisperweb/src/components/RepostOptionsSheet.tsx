import { memo } from "react";
import * as Dialog from "@radix-ui/react-dialog";
import { Quote, Repeat2 } from "lucide-react";

import { cn } from "@/lib/utils";

interface RepostOptionsSheetProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  isReposted: boolean;
  onQuote: () => void;
  onRepostOnly: () => void;
}

/**
 * Bottom sheet shown when tapping the repost glyph — mirrors the iOS
 * `WhisperRepostOptionsSheet` with Quote + Repost only actions.
 */
function RepostOptionsSheetBase({
  open,
  onOpenChange,
  isReposted,
  onQuote,
  onRepostOnly,
}: RepostOptionsSheetProps) {
  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/50 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-50 mx-auto flex w-full max-w-[480px] flex-col gap-3 rounded-t-[26px] bg-background p-4 pb-7 shadow-2xl outline-none data-[state=open]:animate-in data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-[26px]"
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          <Dialog.Title className="text-center text-[15px] font-bold">
            Repost options
          </Dialog.Title>

          <div className="overflow-hidden rounded-2xl border border-border">
            <Row icon={<Quote className="h-5 w-5" />} label="Quote" onClick={onQuote} />
          </div>

          <div className="overflow-hidden rounded-2xl border border-border">
            <Row
              icon={<Repeat2 className="h-5 w-5" />}
              label={isReposted ? "Undo repost" : "Repost only"}
              destructiveTint={isReposted}
              onClick={onRepostOnly}
            />
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

function Row({
  icon,
  label,
  onClick,
  destructiveTint = false,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
  destructiveTint?: boolean;
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex w-full items-center justify-between px-4 py-4 text-left text-[16px] transition-colors hover:bg-secondary/60",
        destructiveTint ? "text-repost" : "text-foreground"
      )}
    >
      {label}
      <span className={destructiveTint ? "text-repost" : "text-foreground"}>
        {icon}
      </span>
    </button>
  );
}

export const RepostOptionsSheet = memo(RepostOptionsSheetBase);
