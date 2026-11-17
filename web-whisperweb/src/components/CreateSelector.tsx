import { memo, useState } from "react";
import { useNavigate } from "react-router-dom";
import * as Dialog from "@radix-ui/react-dialog";
import {
  X,
  PenSquare,
  LayoutGrid,
  Film,
  Camera,
  ChevronRight,
} from "lucide-react";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { canPostGrid } from "@/lib/accountAccess";
import { CreatorMark } from "@/components/CreatorMark";

interface CreateSelectorProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
}

interface CreateOption {
  id: "post" | "grid" | "reel" | "story";
  label: string;
  sublabel: string;
  icon: typeof PenSquare;
  accent: string;
  requiresRole?: boolean;
}

const OPTIONS: CreateOption[] = [
  {
    id: "post",
    label: "Whisper",
    sublabel: "Share a thought, photo, or workout",
    icon: PenSquare,
    accent: "bg-foreground",
  },
  {
    id: "grid",
    label: "Grid post",
    sublabel: "Share up to 10 photos in one post",
    icon: LayoutGrid,
    accent: "bg-emerald-500",
    requiresRole: true,
  },
  {
    id: "reel",
    label: "Wave",
    sublabel: "Share a short video",
    icon: Film,
    accent: "bg-[linear-gradient(135deg,#F22659,#FF7340,#FFA94D)]",
  },
  {
    id: "story",
    label: "Story",
    sublabel: "Photo that disappears after 24h",
    icon: Camera,
    accent: "bg-violet-500",
  },
];

function CreateSelectorBase({ open, onOpenChange }: CreateSelectorProps) {
  const navigate = useNavigate();
  const { profile } = useAuth();
  const [hovered, setHovered] = useState<string | null>(null);

  const canAccessGrid = canPostGrid(profile);

  const handleSelect = (id: CreateOption["id"]): void => {
    onOpenChange(false);
    if (id === "post") navigate("/compose");
    else if (id === "grid") navigate("/compose/grid");
    else if (id === "reel") navigate("/compose?mode=reel");
    else if (id === "story") navigate("/compose?mode=story");
  };

  return (
    <Dialog.Root open={open} onOpenChange={onOpenChange}>
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-50 outline-none data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:slide-out-to-bottom data-[state=open]:slide-in-from-bottom"
          onPointerDownOutside={() => onOpenChange(false)}
        >
          <div className="mx-auto max-w-md rounded-t-[28px] border border-border/50 bg-background p-2 pb-8 shadow-2xl">
            {/* Drag handle */}
            <div className="flex justify-center pt-2 pb-4">
              <div className="h-1.5 w-10 rounded-full bg-muted-foreground/30" />
            </div>

            <div className="mb-4 px-4">
              <p className="text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                Create
              </p>
              <h2 className="text-xl font-bold">What do you want to share?</h2>
            </div>

            <div className="flex flex-col gap-1 px-2">
              {OPTIONS.map((option) => {
                const locked = option.requiresRole && !canAccessGrid;
                return (
                  <button
                    key={option.id}
                    disabled={locked}
                    onMouseEnter={() => setHovered(option.id)}
                    onMouseLeave={() => setHovered(null)}
                    onClick={() => handleSelect(option.id)}
                    className={cn(
                      "flex items-center gap-4 rounded-2xl px-3 py-3.5 text-left transition-all",
                      hovered === option.id
                        ? "bg-secondary/80"
                        : "bg-transparent",
                      locked && "opacity-40"
                    )}
                  >
                    <span
                      className={cn(
                        "flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl text-white",
                        option.accent
                      )}
                    >
                      <option.icon className="h-6 w-6" />
                    </span>
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-2">
                        <span className="text-[16px] font-bold">
                          {option.label}
                        </span>
                        {option.id === "grid" && (
                          <span className="inline-flex items-center gap-1 rounded-full bg-[#FF7340]/10 px-2 py-0.5 text-[10px] font-bold text-[#E8532F]">
                            <CreatorMark size={10} className="-my-1" />
                            Creator
                          </span>
                        )}
                      </div>
                      <p className="text-[13px] text-muted-foreground">
                        {locked
                          ? "Requires approved creator access"
                          : option.sublabel}
                      </p>
                    </div>
                    <ChevronRight
                      className={cn(
                        "h-5 w-5 shrink-0 text-muted-foreground transition-transform",
                        hovered === option.id && "translate-x-0.5"
                      )}
                    />
                  </button>
                );
              })}
            </div>

            <button
              onClick={() => onOpenChange(false)}
              className="mt-4 flex w-full items-center justify-center rounded-2xl bg-secondary py-3 text-[15px] font-bold transition-colors hover:bg-secondary/80 active:scale-95"
            >
              <X className="mr-2 h-4 w-4" />
              Cancel
            </button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>
    </Dialog.Root>
  );
}

export const CreateSelector = memo(CreateSelectorBase);
