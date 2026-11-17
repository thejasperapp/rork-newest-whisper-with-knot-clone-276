import { useEffect, useMemo, useRef, useState } from "react";
import { useNavigate, useSearchParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, ChevronDown, ImagePlus, X, PenSquare, Camera, Film } from "lucide-react";

import { PostModeSelector } from "@/components/PostModeSelector";
import { toast } from "sonner";
import { dearAlgorithmWish, saveAlgorithmWish } from "@/lib/dearAlgorithm";
import { Avatar } from "@/components/Avatar";
import { cn } from "@/lib/utils";
import { createPost, createStory, uploadMedia } from "@/lib/api";
import { FloatingHeader } from "@/components/FloatingHeader";
import { consumeComposerPrefill } from "@/lib/composerDraft";
import {
  encodeArticleEmbed,
  encodeFilmEmbed,
  parseContentEmbeds,
  type ArticleEmbedPayload,
  type FilmEmbedPayload,
} from "@/lib/contentEmbeds";
import { EmbedDraftChip } from "@/components/ContentEmbedCards";
import { useAuth } from "@/hooks/useAuth";
import {
  COMMUNITIES,
  fetchCustomCommunities,
  type Community,
} from "@/lib/communities";
import { loadCachedNearby } from "@/lib/nearbyCommunities";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuLabel,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

type Mode = "post" | "story" | "reel";

const MODE_META: Record<
  Mode,
  { label: string; icon: typeof PenSquare; maxFiles: number; accepts: string }
> = {
  post: { label: "Whisper", icon: PenSquare, maxFiles: 10, accepts: "image/*" },
  story: { label: "Story", icon: Camera, maxFiles: 1, accepts: "image/*" },
  reel: { label: "Reel", icon: Film, maxFiles: 1, accepts: "video/*" },
};

export default function Compose() {
  const { user, profile } = useAuth();
  const navigate = useNavigate();
  const [params] = useSearchParams();
  const queryClient = useQueryClient();
  const fileRef = useRef<HTMLInputElement>(null);

  const rawMode = params.get("mode");
  if (rawMode === "grid") {
    navigate("/compose/grid", { replace: true });
  }

  const initialMode: Mode =
    (rawMode as Mode) ?? "post";
  if (rawMode && !(rawMode in MODE_META)) {
    navigate("/compose", { replace: true });
  }
  const [mode, setMode] = useState<Mode>(initialMode);
  const [caption, setCaption] = useState<string>("");
  // The community this post files into — visible up front ("posting in X"),
  // seeded by ?community= so hub pages can hand the composer a target.
  const [topic, setTopic] = useState<string | null>(
    () => params.get("community")
  );
  // Shared film/article riding this post — parsed OUT of a share draft so
  // the editor never shows the raw embed token; re-attached on publish.
  const [filmEmbed, setFilmEmbed] = useState<FilmEmbedPayload | null>(null);
  const [articleEmbed, setArticleEmbed] = useState<ArticleEmbedPayload | null>(
    null
  );

  // One-shot prefill handed over by Ember's post drafts / share sheets.
  useEffect(() => {
    const prefill = consumeComposerPrefill();
    if (prefill) {
      const split = parseContentEmbeds(prefill.caption);
      setCaption((c) => (c.trim() ? c : split.cleaned));
      setFilmEmbed(split.film);
      setArticleEmbed(split.article);
    }
  }, []);

  const [files, setFiles] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [busy, setBusy] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Same option set as the modal composer — catalog + custom hubs + geo hubs.
  const customCommunitiesQuery = useQuery({
    queryKey: ["custom-communities"],
    queryFn: fetchCustomCommunities,
    enabled: mode === "post",
    staleTime: 5 * 60_000,
  });
  const communityOptions = useMemo<Community[]>(() => {
    const seen = new Set<string>();
    const list: Community[] = [];
    for (const c of [
      ...COMMUNITIES,
      ...(customCommunitiesQuery.data ?? []),
      ...(loadCachedNearby(user?.id) ?? []),
    ]) {
      if (seen.has(c.id)) continue;
      if (c.visibility === "private" && c.id !== topic) continue;
      seen.add(c.id);
      list.push(c);
    }
    return list;
  }, [customCommunitiesQuery.data, user?.id, topic]);
  const pickedCommunity = useMemo<Community | null>(() => {
    if (!topic) return null;
    return (
      communityOptions.find((c) => c.id === topic) ??
      communityOptions.find(
        (c) => c.name.toLowerCase() === topic.toLowerCase()
      ) ??
      null
    );
  }, [topic, communityOptions]);

  const handlePick = (e: React.ChangeEvent<HTMLInputElement>): void => {
    const picked = Array.from(e.target.files ?? []);
    if (picked.length === 0) return;
    const meta = MODE_META[mode];
    const remaining = meta.maxFiles - files.length;
    const next = picked.slice(0, Math.max(0, remaining));
    setFiles((prev) => [...prev, ...next]);
    setPreviews((prev) => [...prev, ...next.map((f) => URL.createObjectURL(f))]);
  };

  const removeAt = (i: number): void => {
    setFiles((f) => f.filter((_, idx) => idx !== i));
    setPreviews((p) => p.filter((_, idx) => idx !== i));
  };

  const submit = async (): Promise<void> => {
    if (!user || !profile) {
      setError("Set up your profile first.");
      return;
    }
    if (
      mode !== "story" &&
      !caption.trim() &&
      files.length === 0 &&
      !filmEmbed &&
      !articleEmbed
    ) {
      setError("Add a photo or write something.");
      return;
    }
    if (mode === "story" && files.length === 0) {
      setError("Pick a photo for your story.");
      return;
    }

    setBusy(true);
    setError(null);
    try {
      const wish = mode === "post" ? dearAlgorithmWish(caption) : null;
      if (wish !== null) {
        saveAlgorithmWish(user.id, wish);
        void queryClient.invalidateQueries({ queryKey: ["feed"] });
        toast("Knot tuned your feed on this browser. Nothing was posted.");
        navigate("/");
        return;
      }
      const urls: string[] = [];
      for (const f of files) {
        urls.push(await uploadMedia(f, user.id));
      }

      if (mode === "post") {
        // Re-attach any shared film/article card as its embed token — the
        // feed strips it back out and renders the tappable card.
        let finalCaption = caption.trim();
        if (filmEmbed) {
          finalCaption = `${finalCaption}\n\n${encodeFilmEmbed(filmEmbed)}`.trim();
        }
        if (articleEmbed) {
          finalCaption = `${finalCaption}\n\n${encodeArticleEmbed(articleEmbed)}`.trim();
        }
        await createPost({
          userId: user.id,
          username: profile.username,
          caption: finalCaption,
          mediaUrls: urls,
          communityId: pickedCommunity?.id ?? topic ?? null,
          communityName: pickedCommunity?.name ?? topic ?? null,
        });
        queryClient.invalidateQueries({ queryKey: ["feed"] });
      } else if (mode === "story") {
        await createStory({
          userId: user.id,
          username: profile.username,
          imageUrl: urls[0]!,
          caption: caption.trim() || null,
        });
        queryClient.invalidateQueries({ queryKey: ["stories"] });
      }
      navigate("/");
    } catch (err) {
      setError(err instanceof Error ? err.message : "Couldn't publish.");
    } finally {
      setBusy(false);
    }
  };

  const username = profile?.username ?? "you";
  const hasContent =
    caption.trim().length > 0 ||
    files.length > 0 ||
    !!filmEmbed ||
    !!articleEmbed;

  return (
    <div className="flex min-h-[100dvh] flex-col">
      {mode === "post" && dearAlgorithmWish(caption) !== null && <p role="status" className="px-4 py-3 text-sm">Dear Algorithm · Private feed tuning on this browser. Your text and attachments won’t be posted.</p>}
      <FloatingHeader
        title={MODE_META[mode].label}
        left={<button onClick={() => navigate(-1)} className="text-[15px] font-semibold text-foreground">Cancel</button>}
        right={
          <PostModeSelector value={mode} canLeave={() => !busy && ((!caption.trim() && files.length === 0 && !filmEmbed && !articleEmbed) || window.confirm("Switch to Grid and discard this draft? Stay here to keep your text and attachments."))} onChange={next => { if (busy) return; if (files.length > MODE_META[next].maxFiles) { toast(`Remove extra attachments before switching to ${MODE_META[next].label}. Your draft is kept.`); return; } if (next === "story" && (filmEmbed || articleEmbed)) { toast("Remove the shared article or film before switching to Story. Your draft is kept."); return; } setMode(next); }} />
        }
      />

      {/* Threads-style composer row */}
      <div className="flex-1 px-4 pt-4">
        <div className="flex gap-3">
          <div className="flex w-10 flex-col items-center">
            <Avatar
              url={profile?.profile_image_url}
              name={username}
              size={40}
            />
            <div className="mt-1.5 w-0.5 flex-1 rounded-full bg-foreground/15" />
          </div>

          <div className="min-w-0 flex-1 pb-2">
            <div className="flex items-center gap-1.5 text-[14px]">
              <span className="font-semibold">{username}</span>
              {mode === "post" && (
                <DropdownMenu>
                  <DropdownMenuTrigger className="flex items-center gap-0.5 text-muted-foreground outline-none transition-colors hover:text-foreground">
                    &rsaquo;&nbsp;
                    {pickedCommunity ? (
                      <span className="flex items-center gap-1 font-medium text-foreground">
                        <pickedCommunity.icon className="h-3.5 w-3.5" />
                        {pickedCommunity.name}
                      </span>
                    ) : topic ? (
                      <span className="font-medium text-foreground">{topic}</span>
                    ) : (
                      "Community or topic"
                    )}
                    <ChevronDown className="h-3.5 w-3.5" />
                  </DropdownMenuTrigger>
                  <DropdownMenuContent
                    align="start"
                    className="max-h-72 w-60 overflow-y-auto"
                  >
                    <DropdownMenuLabel>Post to a community</DropdownMenuLabel>
                    <DropdownMenuSeparator />
                    {topic && (
                      <DropdownMenuItem onClick={() => setTopic(null)}>
                        <X className="mr-2 h-4 w-4" />
                        Remove community
                      </DropdownMenuItem>
                    )}
                    {communityOptions.map((c) => (
                      <DropdownMenuItem key={c.id} onClick={() => setTopic(c.id)}>
                        <c.icon className="mr-2 h-4 w-4" />
                        {c.name}
                        {(topic === c.id || pickedCommunity?.id === c.id) && (
                          <Check className="ml-auto h-4 w-4" />
                        )}
                      </DropdownMenuItem>
                    ))}
                  </DropdownMenuContent>
                </DropdownMenu>
              )}
            </div>

            <textarea
              value={caption}
              onChange={(e) => setCaption(e.target.value)}
              placeholder={
                mode === "story"
                  ? "Add a caption (optional)"
                  : "What's new?"
              }
              rows={3}
              autoFocus
              className="mt-1 w-full resize-none bg-transparent text-[16px] leading-snug outline-none placeholder:text-muted-foreground"
            />

            {previews.length > 0 && (
              <div className="no-scrollbar mb-2 flex gap-2 overflow-x-auto">
                {previews.map((src, i) => (
                  <div key={src} className="relative shrink-0">
                    <img
                      src={src}
                      alt=""
                      className="h-40 w-32 rounded-[14px] border border-border object-cover"
                    />
                    <button
                      onClick={() => removeAt(i)}
                      className="absolute right-1.5 top-1.5 rounded-full bg-black/55 p-1.5 text-white"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                  </div>
                ))}
              </div>
            )}

            {filmEmbed && (
              <EmbedDraftChip
                kicker="WHISPER FILM"
                title={filmEmbed.title}
                subtitle={`A ${filmEmbed.director} film`}
                image={filmEmbed.poster ?? null}
                film
                onRemove={() => setFilmEmbed(null)}
              />
            )}
            {articleEmbed && (
              <EmbedDraftChip
                kicker="WHISPER JOURNAL"
                title={articleEmbed.title}
                subtitle={`By ${articleEmbed.author}`}
                image={articleEmbed.cover ?? null}
                onRemove={() => setArticleEmbed(null)}
              />
            )}

            {/* Inline icon toolbar */}
            <button
              onClick={() => fileRef.current?.click()}
              className="flex items-center gap-2 text-muted-foreground transition-colors hover:text-foreground"
            >
              <ImagePlus className="h-[22px] w-[22px]" />
            </button>
            <input
              ref={fileRef}
              type="file"
              accept={MODE_META[mode].accepts}
              multiple={MODE_META[mode].maxFiles > 1}
              className="hidden"
              onChange={handlePick}
            />

            {error && (
              <p className="mt-3 rounded-xl bg-destructive/15 px-3 py-2 text-sm text-destructive">
                {error}
              </p>
            )}
          </div>
        </div>
      </div>

      {/* Sticky bottom bar */}
      <div className="glass sticky bottom-0 flex items-center justify-between border-t border-border px-4 py-3">
        <span className="flex items-center gap-1.5 text-sm text-muted-foreground">
          {mode === "story" ? (
            "Story · 24h"
          ) : pickedCommunity ? (
            <>
              <pickedCommunity.icon className="h-4 w-4" />
              Posting in {pickedCommunity.name}
            </>
          ) : (
            "Anyone can reply"
          )}
        </span>
        <button
          onClick={submit}
          disabled={busy || !hasContent}
          className="rounded-full bg-primary px-5 py-2 text-sm font-bold text-primary-foreground transition-opacity disabled:opacity-40"
        >
          {busy
            ? "Posting…"
            : mode === "story"
              ? "Share story"
              : "Post"}
        </button>
      </div>
    </div>
  );
}
