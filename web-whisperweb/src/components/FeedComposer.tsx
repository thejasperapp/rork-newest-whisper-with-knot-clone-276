import { memo, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  Image as ImageIcon,
  AlignLeft,
  Clapperboard,
  Film,
  LayoutGrid,
  PenLine,
} from "lucide-react";

import { canPostGrid } from "@/lib/accountAccess";
import { Avatar } from "@/components/Avatar";
import { ComposerModal } from "@/components/ComposerModal";
import { CreatorMark } from "@/components/CreatorMark";
import { useAuth } from "@/hooks/useAuth";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

/**
 * Threads-style inline composer row pinned to the top of the feed. The prompt
 * opens the thread composer; the photo icon jumps straight into the grid
 * (photo) composer; the animated cursive C — THE CREATOR MARK — opens the
 * creator menu (wave · grid post · film · article) — every post type is
 * reachable right here, not just behind the + button.
 */
function FeedComposerBase() {
  const { profile } = useAuth();
  const navigate = useNavigate();
  const [open, setOpen] = useState<boolean>(false);
  const username = profile?.username ?? "you";

  return (
    <>
      <div className="social-feed-composer px-4 py-3.5">
        <div className="flex items-center gap-3">
          <Avatar
            url={profile?.profile_image_url}
            name={username}
            size={40}
          />

          <button
            onClick={() => setOpen(true)}
            className="flex h-10 flex-1 items-center text-left text-[15px] text-muted-foreground"
          >
            What's on your mind?
          </button>

          <div className="flex items-center gap-1 text-muted-foreground">
            <button
              onClick={() => navigate(canPostGrid(profile) ? "/compose/grid" : "/compose")}
              aria-label={canPostGrid(profile) ? "New grid photo post" : "New photo whisper"}
              className="flex h-9 w-9 items-center justify-center rounded-full transition-colors hover:bg-secondary"
            >
              <ImageIcon className="h-[20px] w-[20px]" />
            </button>
            <DropdownMenu>
              <DropdownMenuTrigger asChild>
                <button
                  aria-label="Creator posts"
                  className="flex h-9 w-9 items-center justify-center rounded-full transition-colors hover:bg-secondary"
                >
                  <CreatorMark size={20} />
                </button>
              </DropdownMenuTrigger>
              <DropdownMenuContent align="end" className="w-56">
                <DropdownMenuLabel className="flex items-center gap-2 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                  <CreatorMark size={12} className="-my-1" />
                  Creator posts
                </DropdownMenuLabel>
                <DropdownMenuItem onClick={() => navigate("/reels")}>
                  <Clapperboard className="mr-2 h-4 w-4" />
                  New wave
                </DropdownMenuItem>
                <DropdownMenuItem disabled={!canPostGrid(profile)} onClick={() => navigate("/compose/grid")}>
                  <LayoutGrid className="mr-2 h-4 w-4" />
                  Grid post
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => navigate("/director")}>
                  <Film className="mr-2 h-4 w-4" />
                  Upload a film
                </DropdownMenuItem>
                <DropdownMenuItem onClick={() => navigate("/studio/articles")}>
                  <PenLine className="mr-2 h-4 w-4" />
                  Write an article
                </DropdownMenuItem>
              </DropdownMenuContent>
            </DropdownMenu>
            <button
              onClick={() => setOpen(true)}
              aria-label="New thread"
              className="flex h-9 w-9 items-center justify-center rounded-full transition-colors hover:bg-secondary sm:hidden"
            >
              <AlignLeft className="h-[20px] w-[20px]" />
            </button>
          </div>

          <button
            onClick={() => setOpen(true)}
            className="shrink-0 rounded-full bg-foreground px-4 py-2 text-sm font-semibold text-background transition-opacity hover:opacity-80 active:scale-95"
          >
            Post
          </button>
        </div>
      </div>

      <ComposerModal open={open} onOpenChange={setOpen} mode="thread" />
    </>
  );
}

export const FeedComposer = memo(FeedComposerBase);
