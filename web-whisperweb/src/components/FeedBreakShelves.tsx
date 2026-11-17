import { useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { ChevronRight, FileText, Heart, Play, Users } from "lucide-react";
import { toast } from "sonner";

import { ArticleCover } from "@/components/ArticleCover";
import { Avatar } from "@/components/Avatar";
import { Dialog, DialogContent, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { useAuth } from "@/hooks/useAuth";
import { fetchFollowing, fetchSuggestions, toggleFollow } from "@/lib/api";
import { fetchArticles, type Article } from "@/lib/articles";
import { compactCount } from "@/lib/format";
import { waveCoverUrl } from "@/lib/postMeta";
import type { WhisperPost } from "@/lib/types";
import { cn } from "@/lib/utils";

/**
 * THE FEED'S BREAK SHELVES (iOS parity) — three native content breaks that
 * slot between posts: WAVES (tall 9:16 tiles), FROM THE JOURNAL (article
 * cards), and PEOPLE TO FOLLOW (people cards with Follow). Every shelf
 * header carries "See all ›", which unrolls the shelf into a full GRID
 * dialog of the same cards.
 */

function ShelfHeader({
  icon,
  title,
  onSeeAll,
}: {
  icon: React.ReactNode;
  title: string;
  onSeeAll: () => void;
}) {
  return (
    <div className="mb-2.5 flex items-center gap-2 px-4">
      <span className="text-foreground">{icon}</span>
      <p className="text-[14px] font-bold">{title}</p>
      <div className="flex-1" />
      <button
        type="button"
        onClick={onSeeAll}
        className="flex items-center gap-0.5 py-1 text-[12px] font-bold text-muted-foreground transition-colors hover:text-foreground"
      >
        See all
        <ChevronRight className="h-3 w-3" strokeWidth={2.8} />
      </button>
    </div>
  );
}

// ─── Waves ───────────────────────────────────────────────────────────────────

function WaveTile({
  post,
  className,
  onClick,
}: {
  post: WhisperPost;
  className?: string;
  onClick: () => void;
}) {
  const url = (post.media_urls ?? [])[0];
  const handle = post.username ?? "creator";
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "group relative overflow-hidden rounded-[14px] bg-black text-left transition-transform active:scale-[0.97]",
        className
      )}
      aria-label={`Wave by @${handle}`}
    >
      {url && (
        <video
          src={url}
          poster={waveCoverUrl(post.caption)}
          muted
          playsInline
          preload={waveCoverUrl(post.caption) ? "none" : "metadata"}
          className="absolute inset-0 h-full w-full object-cover transition-transform duration-300 group-hover:scale-[1.03]"
        />
      )}
      <span className="pointer-events-none absolute inset-x-0 top-0 h-12 bg-gradient-to-b from-black/50 to-transparent" />
      <span className="pointer-events-none absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-black/60 to-transparent" />
      <Play className="absolute left-2 top-2 h-3.5 w-3.5 fill-white text-white drop-shadow" />
      <span className="absolute bottom-2 left-2 right-2 flex flex-col gap-0.5">
        <span className="truncate text-[11px] font-bold text-white drop-shadow">{handle}</span>
        <span className="flex items-center gap-1 text-[10.5px] font-semibold text-white/90 drop-shadow">
          <Heart className="h-2.5 w-2.5 fill-white" />
          {compactCount(post.likes_count ?? 0)}
        </span>
      </span>
    </button>
  );
}

export function FeedWavesShelf({ posts }: { posts: WhisperPost[] }) {
  const navigate = useNavigate();
  const [open, setOpen] = useState<boolean>(false);
  const waves = useMemo(
    () => posts.filter((p) => !p.is_ghost && p.is_reel === true && (p.media_urls ?? []).length > 0),
    [posts]
  );
  if (waves.length === 0) return null;
  const openWave = (p: WhisperPost): void => {
    setOpen(false);
    navigate(`/reels?wave=${p.id}`);
  };
  return (
    <section className="border-t border-border py-3.5">
      <ShelfHeader
        icon={<Play className="h-4 w-4 fill-current" />}
        title="Waves"
        onSeeAll={() => setOpen(true)}
      />
      <div className="flex gap-2 overflow-x-auto px-4 pb-1 [scrollbar-width:none]">
        {waves.slice(0, 8).map((p) => (
          <WaveTile key={p.id} post={p} className="h-[220px] w-[124px] shrink-0" onClick={() => openWave(p)} />
        ))}
      </div>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[85vh] max-w-[560px] overflow-y-auto rounded-[24px]">
          <DialogHeader>
            <DialogTitle>Waves</DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-3 gap-1">
            {waves.map((p) => (
              <WaveTile key={p.id} post={p} className="aspect-[9/16] w-full rounded-[10px]" onClick={() => openWave(p)} />
            ))}
          </div>
        </DialogContent>
      </Dialog>
    </section>
  );
}

// ─── From the journal ────────────────────────────────────────────────────────

function ArticleCard({
  article,
  wide,
  onClick,
}: {
  article: Article;
  wide?: boolean;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      className={cn(
        "flex flex-col overflow-hidden rounded-[18px] bg-secondary text-left transition-transform active:scale-[0.98]",
        wide ? "w-[260px] shrink-0" : "w-full"
      )}
    >
      <div className={cn("relative w-full overflow-hidden", wide ? "h-[150px]" : "aspect-[4/3]")}>
        <ArticleCover cover={article.cover_url} alt="" className="h-full w-full" imgClassName="h-full w-full object-cover" />
        <span className="pointer-events-none absolute inset-x-0 bottom-0 h-16 bg-gradient-to-t from-black/55 to-transparent" />
        {article.category && (
          <span className="absolute bottom-2.5 left-2.5 rounded-full bg-white/20 px-2 py-0.5 text-[9.5px] font-black uppercase tracking-[0.05em] text-white backdrop-blur-sm">
            {article.category}
          </span>
        )}
      </div>
      <div className="flex flex-col gap-1 p-3">
        <p className="line-clamp-2 text-[14px] font-bold leading-snug">{article.title}</p>
        {wide && article.excerpt && (
          <p className="line-clamp-2 text-[12px] text-muted-foreground">{article.excerpt}</p>
        )}
        <p className="truncate text-[11px] text-muted-foreground">{article.author_name || "Whisper Team"}</p>
      </div>
    </button>
  );
}

export function FeedArticlesShelf() {
  const navigate = useNavigate();
  const [open, setOpen] = useState<boolean>(false);
  const query = useQuery({
    queryKey: ["feed-shelf-articles"],
    queryFn: fetchArticles,
    staleTime: 10 * 60_000,
  });
  const articles = useMemo(() => (query.data ?? []).filter((a) => a.published), [query.data]);
  if (articles.length === 0) return null;
  const openArticle = (a: Article): void => {
    setOpen(false);
    navigate(`/articles/${a.slug}`);
  };
  return (
    <section className="border-t border-border py-3.5">
      <ShelfHeader icon={<FileText className="h-4 w-4" />} title="From the journal" onSeeAll={() => setOpen(true)} />
      <div className="flex gap-3 overflow-x-auto px-4 pb-1 [scrollbar-width:none]">
        {articles.slice(0, 8).map((a) => (
          <ArticleCard key={a.id} article={a} wide onClick={() => openArticle(a)} />
        ))}
      </div>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[85vh] max-w-[620px] overflow-y-auto rounded-[24px]">
          <DialogHeader>
            <DialogTitle>From the journal</DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-3">
            {articles.map((a) => (
              <ArticleCard key={a.id} article={a} onClick={() => openArticle(a)} />
            ))}
          </div>
        </DialogContent>
      </Dialog>
    </section>
  );
}

// ─── People to follow ────────────────────────────────────────────────────────

export function FeedPeopleShelf() {
  const { user } = useAuth();
  const navigate = useNavigate();
  const queryClient = useQueryClient();
  const [open, setOpen] = useState<boolean>(false);

  const suggestionsQuery = useQuery({
    queryKey: ["feed-shelf-people", user?.id],
    queryFn: () => fetchSuggestions(user!.id, 24),
    enabled: !!user,
    staleTime: 5 * 60_000,
  });
  const followingQuery = useQuery({
    queryKey: ["following", user?.id],
    queryFn: () => fetchFollowing(user!.id),
    enabled: !!user,
  });
  const followingSet = useMemo(
    () => new Set((followingQuery.data ?? []).map((f) => f.userId)),
    [followingQuery.data]
  );

  const follow = useMutation({
    mutationFn: async (p: { id: string; username: string; following: boolean }) => {
      if (!user) return;
      await toggleFollow(user.id, p.id, p.username, p.following);
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["following", user?.id] });
    },
    onError: () => toast.error("Couldn't update follow. Try again."),
  });

  const people = suggestionsQuery.data ?? [];
  if (!user || people.length === 0) return null;

  const card = (p: (typeof people)[number], compact: boolean): React.ReactNode => {
    const following = followingSet.has(p.userId);
    const profile = p.profile;
    return (
      <div
        key={p.userId}
        className={cn(
          "flex flex-col items-center gap-2.5 rounded-2xl bg-secondary p-3 text-center",
          compact ? "w-[140px] shrink-0" : "w-full"
        )}
      >
        <button
          type="button"
          onClick={() => {
            setOpen(false);
            navigate(`/u/${p.username}`);
          }}
          className="flex flex-col items-center gap-2"
        >
          <Avatar url={profile?.profile_image_url} name={p.username} size={compact ? 64 : 72} />
          <span className="w-full truncate text-[13px] font-bold">{p.username}</span>
          <span className="line-clamp-2 min-h-[30px] text-[11px] leading-snug text-muted-foreground">
            {profile?.bio || profile?.display_name || "Suggested"}
          </span>
        </button>
        <button
          type="button"
          disabled={follow.isPending}
          onClick={() => follow.mutate({ id: p.userId, username: p.username, following })}
          className={cn(
            "w-full rounded-lg py-1.5 text-[12px] font-bold transition-colors",
            following ? "border border-border bg-background text-foreground" : "bg-foreground text-background"
          )}
        >
          {following ? "Following" : "Follow"}
        </button>
      </div>
    );
  };

  return (
    <section className="border-t border-border py-3.5">
      <ShelfHeader icon={<Users className="h-4 w-4" />} title="People to follow" onSeeAll={() => setOpen(true)} />
      <div className="flex gap-2.5 overflow-x-auto px-4 pb-1 [scrollbar-width:none]">
        {people.slice(0, 10).map((p) => card(p, true))}
      </div>
      <Dialog open={open} onOpenChange={setOpen}>
        <DialogContent className="max-h-[85vh] max-w-[560px] overflow-y-auto rounded-[24px]">
          <DialogHeader>
            <DialogTitle>People to follow</DialogTitle>
          </DialogHeader>
          <div className="grid grid-cols-2 gap-3 sm:grid-cols-3">{people.map((p) => card(p, false))}</div>
        </DialogContent>
      </Dialog>
    </section>
  );
}
