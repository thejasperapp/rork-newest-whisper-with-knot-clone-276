import {
  BarChart3,
  Clapperboard,
  Film,
  ImageIcon,
  MapPin,
  Newspaper,
  Paperclip,
  Play,
  Smile,
  Sparkles,
  UserRound,
  UtensilsCrossed,
  Video,
  type LucideIcon,
} from "lucide-react";
import { cn } from "@/lib/utils";
import type { QuoteCardKind } from "@/lib/groupChats";

const ICONS: Record<QuoteCardKind, LucideIcon> = {
  wave: Play,
  post: ImageIcon,
  photo: ImageIcon,
  gif: Film,
  sticker: Smile,
  profile: UserRound,
  chart: BarChart3,
  map: MapPin,
  recipe: UtensilsCrossed,
  film: Clapperboard,
  article: Newspaper,
  meeting: Video,
  jasper: Sparkles,
  card: Paperclip,
};

const KIND_LABEL: Record<QuoteCardKind, string> = {
  wave: "Wave",
  post: "Post",
  photo: "Photo",
  gif: "GIF",
  sticker: "Sticker",
  profile: "Profile",
  chart: "Chart",
  map: "Map",
  recipe: "Recipe",
  film: "Film",
  article: "Article",
  meeting: "Meeting",
  jasper: "Jasper",
  card: "Card",
};

/**
 * The MINI version of a quoted card inside a reply — an icon tile beside the
 * card's friendly line — instead of the full card (mirrors iOS
 * `WhisperChatReplyQuoteView.miniCard`). `quotedMine` picks the fill: a
 * lighter copy of the original sender's bubble.
 */
export function ChatQuoteMiniCard({
  quoteText,
  kind,
  quotedMine,
  className,
}: {
  quoteText: string;
  kind: QuoteCardKind;
  quotedMine: boolean;
  className?: string;
}) {
  const Icon = ICONS[kind];
  const raw = quoteText.trim();
  const label = raw.startsWith("::") || raw.startsWith("{") ? "Shared a card" : raw;
  return (
    <div
      className={cn(
        "flex max-w-[240px] items-center gap-2.5 rounded-2xl px-2.5 py-2",
        quotedMine ? "bg-foreground/40 text-background" : "bg-secondary/70 text-muted-foreground",
        className
      )}
    >
      <span
        className={cn(
          "flex h-9 w-9 shrink-0 items-center justify-center rounded-[10px]",
          quotedMine ? "bg-background/15" : "bg-foreground/10"
        )}
      >
        <Icon className="h-4 w-4" strokeWidth={2} />
      </span>
      <div className="min-w-0">
        <p className="line-clamp-2 text-[14px] font-semibold leading-snug">{label}</p>
        <p className="text-[11.5px] opacity-70">{KIND_LABEL[kind]}</p>
      </div>
    </div>
  );
}
