import { memo, useEffect, useMemo, useRef, useState } from "react";
import { createPortal } from "react-dom";
import * as Dialog from "@radix-ui/react-dialog";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  X,
  Image as ImageIcon,
  Smile,
  BarChart2,
  MapPin,
  Music,
  Users,
  Globe,
  UserCheck,
  AtSign,
  ChevronDown,
  Check,
  Search,
  Plus,
  Loader2,
  Send,
} from "lucide-react";
import { toast } from "sonner";

import { dearAlgorithmWish, saveAlgorithmWish } from "@/lib/dearAlgorithm";
import { Avatar } from "@/components/Avatar";
import { GiphyPicker } from "@/components/GiphyPicker";
import { MusicPickerSheet } from "@/components/MusicPickerSheet";
import { cn } from "@/lib/utils";
import {
  createPost,
  createStory,
  searchProfiles,
  uploadMedia,
} from "@/lib/api";
import { useAuth } from "@/hooks/useAuth";
import { currentPlaceName } from "@/lib/geo";
import { encodePostMeta, type PostMeta, type PostMusic } from "@/lib/postMeta";
import {
  clearComposerDraft,
  consumeComposerPrefill,
  loadComposerDraft,
  saveComposerDraft,
} from "@/lib/composerDraft";
import { encodeSharedPost, payloadFromPost } from "@/lib/postShare";
import {
  encodeArticleEmbed,
  encodeFilmEmbed,
  parseContentEmbeds,
  type ArticleEmbedPayload,
  type FilmEmbedPayload,
} from "@/lib/contentEmbeds";
import { EmbedDraftChip } from "@/components/ContentEmbedCards";
import { QuotedPostCard } from "@/components/QuotedPostCard";
import type { MusicTrack } from "@/lib/music";
import type { WhisperPost } from "@/lib/types";
import {
  COMMUNITIES,
  fetchCustomCommunities,
  suggestCommunityForCaption,
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

type Audience = "anyone" | "following" | "mentioned";

const AUDIENCES: { id: Audience; label: string; icon: typeof Globe }[] = [
  { id: "anyone", label: "Anyone can reply", icon: Globe },
  { id: "following", label: "Profiles you follow", icon: UserCheck },
  { id: "mentioned", label: "Mentioned only", icon: AtSign },
];

export type ComposerMode = "thread" | "story";

interface ComposerModalProps {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  mode?: ComposerMode;
  /** When set, the composer becomes a quote-repost of this post. */
  quotedPost?: WhisperPost | null;
  quotedAuthor?: string | null;
  /** Pre-selected community (id preferred; legacy lowercased names resolve too). */
  initialTopic?: string | null;
}

const EMOJIS = [
  "😀", "😂", "🥹", "😍", "😎", "🥳", "😭", "🔥",
  "💪", "👏", "🙌", "💯", "✨", "❤️", "👀", "🏋️",
  "🥗", "🏃", "☕️", "🌶️", "👻", "⚡️", "🎯", "🚀",
];

/** Toolbar icon button — the row beneath the text field in the reference. */
function ToolIcon({
  label,
  active,
  onClick,
  children,
}: {
  label: string;
  active?: boolean;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className={cn(
        "flex h-9 w-9 items-center justify-center rounded-full transition-colors hover:bg-secondary",
        active ? "text-foreground" : "text-muted-foreground"
      )}
    >
      {children}
    </button>
  );
}

function ComposerModalBase({
  open,
  onOpenChange,
  mode = "thread",
  quotedPost = null,
  quotedAuthor = null,
  initialTopic = null,
}: ComposerModalProps) {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const fileRef = useRef<HTMLInputElement>(null);

  const [caption, setCaption] = useState<string>("");
  const [files, setFiles] = useState<File[]>([]);
  const [previews, setPreviews] = useState<string[]>([]);
  const [gifUrls, setGifUrls] = useState<string[]>([]);
  const [showGiphy, setShowGiphy] = useState<boolean>(false);
  const [showEmoji, setShowEmoji] = useState<boolean>(false);
  const [audience, setAudience] = useState<Audience>("anyone");
  const [topic, setTopic] = useState<string | null>(initialTopic);
  const [suggestion, setSuggestion] = useState<Community | null>(null);
  const suggestionDismissed = useRef<boolean>(false);
  // Shared film/article riding this post — parsed OUT of a share draft so
  // the editor never shows the raw embed token; re-attached on publish.
  const [filmEmbed, setFilmEmbed] = useState<FilmEmbedPayload | null>(null);
  const [articleEmbed, setArticleEmbed] = useState<ArticleEmbedPayload | null>(
    null
  );

  // Rich attachments (mirrors the iOS composer toolbar).
  const [music, setMusic] = useState<PostMusic | null>(null);
  const [showMusic, setShowMusic] = useState<boolean>(false);
  const [location, setLocation] = useState<string | null>(null);
  const [locating, setLocating] = useState<boolean>(false);
  const [tagged, setTagged] = useState<string[]>([]);
  const [showTag, setShowTag] = useState<boolean>(false);
  const [tagQuery, setTagQuery] = useState<string>("");
  const [poll, setPoll] = useState<string[] | null>(null);
  const [flying, setFlying] = useState<boolean>(false);

  const isStory = mode === "story";
  const username = profile?.username ?? "you";
  const restoredDraft = useRef<boolean>(false);

  // Every community the picker can file a post into — catalog + the user's
  // custom hubs + cached geo hubs. Private groups only appear when the
  // composer was opened FROM that group's page.
  const customCommunitiesQuery = useQuery({
    queryKey: ["custom-communities"],
    queryFn: fetchCustomCommunities,
    enabled: open && !isStory,
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
      if (c.visibility === "private" && c.id !== initialTopic) continue;
      seen.add(c.id);
      list.push(c);
    }
    return list;
  }, [customCommunitiesQuery.data, user?.id, initialTopic]);

  /** The picked community — resolved by id first, legacy names second. */
  const pickedCommunity = useMemo<Community | null>(() => {
    if (!topic) return null;
    return (
      communityOptions.find((c) => c.id === topic) ??
      communityOptions.find((c) => c.name.toLowerCase() === topic.toLowerCase()) ??
      null
    );
  }, [topic, communityOptions]);

  // Quiet auto-suggest: when the draft clearly reads like a community's
  // topic and none is picked, offer it once — the user confirms, we never
  // auto-file. Dismissing stays dismissed for this compose session.
  useEffect(() => {
    if (!open || isStory || topic || suggestionDismissed.current) {
      setSuggestion(null);
      return;
    }
    const t = window.setTimeout(() => {
      setSuggestion(suggestCommunityForCaption(caption, communityOptions));
    }, 350);
    return () => window.clearTimeout(t);
  }, [open, isStory, topic, caption, communityOptions]);

  // Draft system — restore an Ember prefill or the autosaved draft when the
  // thread composer opens empty.
  useEffect(() => {
    if (!open || isStory || quotedPost) return;
    if (restoredDraft.current) return;
    restoredDraft.current = true;
    const prefill = consumeComposerPrefill();
    if (prefill) {
      // Never show a raw `::whisper-…::` token in the editor — split into
      // clean text + a removable preview card, re-attached on publish.
      const split = parseContentEmbeds(prefill.caption);
      setCaption(split.cleaned);
      setFilmEmbed(split.film);
      setArticleEmbed(split.article);
      if (prefill.topic) setTopic(prefill.topic);
      return;
    }
    const draft = loadComposerDraft();
    if (!draft) return;
    setCaption(draft.caption);
    setTopic(draft.topic ?? initialTopic);
    setPoll(draft.poll);
    setTagged(draft.tagged);
    setLocation(draft.location);
    setMusic(draft.music);
    if (draft.audience === "following" || draft.audience === "mentioned") {
      setAudience(draft.audience);
    }
    toast("Draft restored");
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [open, isStory, quotedPost]);

  // Autosave the restorable parts of the thread draft as they change.
  useEffect(() => {
    if (!open || isStory || quotedPost || !restoredDraft.current) return;
    saveComposerDraft({
      caption,
      topic,
      poll,
      tagged,
      location,
      music,
      audience,
    });
  }, [open, isStory, quotedPost, caption, topic, poll, tagged, location, music, audience]);
  const mediaTotal = files.length + gifUrls.length;
  const pollReady = (poll?.filter((o) => o.trim()).length ?? 0) >= 2;
  const hasMetaContent =
    !!music || !!location || tagged.length > 0 || pollReady;
  const hasContent = isStory
    ? mediaTotal > 0
    : caption.trim().length > 0 ||
      mediaTotal > 0 ||
      hasMetaContent ||
      !!quotedPost ||
      !!filmEmbed ||
      !!articleEmbed;

  const reset = (): void => {
    setCaption("");
    setFiles([]);
    setPreviews([]);
    setGifUrls([]);
    setShowGiphy(false);
    setShowEmoji(false);
    setAudience("anyone");
    setTopic(initialTopic);
    setSuggestion(null);
    suggestionDismissed.current = false;
    setMusic(null);
    setShowMusic(false);
    setLocation(null);
    setLocating(false);
    setTagged([]);
    setShowTag(false);
    setTagQuery("");
    setPoll(null);
    setFilmEmbed(null);
    setArticleEmbed(null);
  };

  const activeAudience = AUDIENCES.find((a) => a.id === audience) ?? AUDIENCES[0];

  const handlePick = (e: React.ChangeEvent<HTMLInputElement>): void => {
    const picked = Array.from(e.target.files ?? []).slice(0, isStory ? 1 : 10);
    if (picked.length === 0) return;
    setFiles(isStory ? picked.slice(0, 1) : picked);
    setPreviews(picked.map((f) => URL.createObjectURL(f)));
  };

  const removeAt = (i: number): void => {
    setFiles((f) => f.filter((_, idx) => idx !== i));
    setPreviews((p) => p.filter((_, idx) => idx !== i));
  };

  const publish = useMutation({
    mutationFn: async (): Promise<"curated" | void> => {
      if (!user || !profile) throw new Error("Set up your profile first.");
      const wish = !isStory ? dearAlgorithmWish(caption) : null;
      if (wish !== null) {
        saveAlgorithmWish(user.id, wish);
        return "curated";
      }
      const urls: string[] = [];
      for (const f of files) urls.push(await uploadMedia(f, user.id));
      // GIFs are already hosted URLs — no upload needed.
      urls.push(...gifUrls);
      if (isStory) {
        await createStory({
          userId: user.id,
          username: profile.username,
          imageUrl: urls[0]!,
          caption: caption.trim() || null,
        });
      } else {
        // The picked community rides as DATA on the post now — never folded
        // into the caption as a hashtag. Captions stay exactly what was typed.
        const meta: PostMeta = {
          music,
          location,
          tagged,
          poll: pollReady
            ? { question: null, options: poll!.map((o) => o.trim()).filter(Boolean) }
            : null,
        };
        let finalCaption = encodePostMeta(meta, caption.trim());
        // Quote-repost: append the shared-post embed so the card renders inline.
        if (quotedPost) {
          const embed = encodeSharedPost(
            payloadFromPost(quotedPost, quotedAuthor ?? quotedPost.username ?? "user")
          );
          finalCaption = `${finalCaption}\n${embed}`;
        }
        // Shared film/article cards ride as embed tokens — the feed strips
        // them back out and renders the tappable cards.
        if (filmEmbed) {
          finalCaption = `${finalCaption}\n${encodeFilmEmbed(filmEmbed)}`;
        }
        if (articleEmbed) {
          finalCaption = `${finalCaption}\n${encodeArticleEmbed(articleEmbed)}`;
        }
        await createPost({
          userId: user.id,
          username: profile.username,
          caption: finalCaption,
          mediaUrls: urls,
          communityId: pickedCommunity?.id ?? topic ?? null,
          communityName: pickedCommunity?.name ?? topic ?? null,
        });
      }
    },
    onSuccess: (result) => {
      queryClient.invalidateQueries({
        queryKey: [isStory ? "stories" : "feed"],
      });
      if (!isStory) clearComposerDraft();
      if (result === "curated") {
        reset();
        onOpenChange(false);
        toast("Knot tuned your feed on this browser. Your request and attachments weren’t posted.");
        return;
      }
      if (isStory) {
        reset();
        onOpenChange(false);
        toast("Story shared");
        return;
      }
      // Launch the paper-plane animation, then close once it has flown off.
      setFlying(true);
      window.setTimeout(() => {
        setFlying(false);
        reset();
        onOpenChange(false);
        toast("Posted");
      }, 750);
    },
    onError: (err) =>
      toast(err instanceof Error ? err.message : "Couldn't publish."),
  });

  const insertEmoji = (e: string): void => {
    setCaption((c) => c + e);
  };

  const addGif = (url: string): void => {
    if (isStory) {
      setGifUrls([url]);
      setFiles([]);
      setPreviews([]);
    } else {
      setGifUrls((g) => [...g, url]);
    }
    setShowGiphy(false);
  };

  const removeGif = (i: number): void => {
    setGifUrls((g) => g.filter((_, idx) => idx !== i));
  };

  const pickLocation = async (): Promise<void> => {
    if (location) {
      setLocation(null);
      return;
    }
    setLocating(true);
    try {
      const place = await currentPlaceName();
      setLocation(place);
    } catch (err) {
      toast(
        err instanceof Error ? err.message : "Couldn't get your location."
      );
    } finally {
      setLocating(false);
    }
  };

  const addTag = (handle: string): void => {
    setTagged((t) => (t.includes(handle) ? t : [...t, handle]));
    setTagQuery("");
  };

  const togglePoll = (): void => {
    setPoll((p) => (p ? null : ["", ""]));
  };

  const close = (): void => {
    // Keep the autosaved draft — closing never eats a post.
    if (!isStory && !quotedPost && caption.trim().length > 0) {
      toast("Draft saved");
    }
    restoredDraft.current = false;
    reset();
    onOpenChange(false);
  };

  return (
    <Dialog.Root
      open={open}
      onOpenChange={(o) => (o ? onOpenChange(true) : close())}
    >
      <Dialog.Portal>
        <Dialog.Overlay className="fixed inset-0 z-50 bg-black/60 backdrop-blur-[2px] data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:fade-out-0 data-[state=open]:fade-in-0" />
        <Dialog.Content
          className="fixed inset-x-0 bottom-0 z-50 mx-auto flex max-h-[90vh] w-full max-w-[560px] flex-col rounded-t-[26px] bg-background shadow-2xl outline-none data-[state=open]:animate-in data-[state=closed]:animate-out data-[state=closed]:slide-out-to-bottom data-[state=open]:slide-in-from-bottom sm:bottom-auto sm:top-1/2 sm:-translate-y-1/2 sm:rounded-[26px]"
          onOpenAutoFocus={(e) => e.preventDefault()}
        >
          {/* Header */}
          <div className="flex items-center justify-between border-b border-border px-4 py-3.5">
            <button
              onClick={close}
              className="flex h-8 w-8 items-center justify-center rounded-full text-foreground transition-colors hover:bg-secondary"
              aria-label="Cancel"
            >
              <X className="h-5 w-5" />
            </button>
            <Dialog.Title className="font-display text-[17px] font-bold">
              {isStory ? "New story" : quotedPost ? "Quote" : "New thread"}
            </Dialog.Title>
            <span className="w-8" />
          </div>

          {/* Body */}
          <div className="min-h-0 flex-1 overflow-y-auto px-4 py-4">
            <div className="flex gap-3">
              {/* Avatar + thread guide line */}
              <div className="flex w-9 flex-col items-center">
                <Avatar
                  url={profile?.profile_image_url}
                  name={username}
                  size={38}
                />
                <div className="mt-1.5 w-0.5 flex-1 rounded-full bg-foreground/10" />
              </div>

              <div className="min-w-0 flex-1">
                {!isStory && dearAlgorithmWish(caption) !== null && <p role="status" className="mb-3 rounded-xl bg-secondary px-3 py-2 text-xs">Dear Algorithm · Private feed tuning for this browser. Your text and attachments won’t be posted.</p>}
                <div className="flex items-center gap-1.5 text-[15px]">
                  <span className="font-semibold">{username}</span>
                  {!isStory && (
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
                          <DropdownMenuItem
                            key={c.id}
                            onClick={() => {
                              setTopic(c.id);
                              suggestionDismissed.current = false;
                            }}
                          >
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
                  placeholder={isStory ? "Add a caption…" : "What's new?"}
                  rows={2}
                  autoFocus
                  className="mt-1 w-full resize-none bg-transparent text-[16px] leading-snug outline-none placeholder:text-muted-foreground"
                />

                {/* Quiet community auto-suggest — confirmed by the user,
                    never auto-filed. */}
                {!isStory && !topic && suggestion && (
                  <div className="mb-1 mt-0.5 flex items-center gap-1.5">
                    <button
                      type="button"
                      onClick={() => {
                        setTopic(suggestion.id);
                        setSuggestion(null);
                      }}
                      className="flex items-center gap-1.5 rounded-full border border-border bg-secondary/60 px-2.5 py-1 text-[12px] font-semibold text-foreground transition-colors hover:bg-secondary"
                    >
                      <suggestion.icon className="h-3.5 w-3.5" />
                      Post in {suggestion.name}?
                    </button>
                    <button
                      type="button"
                      aria-label="Dismiss suggestion"
                      onClick={() => {
                        suggestionDismissed.current = true;
                        setSuggestion(null);
                      }}
                      className="rounded-full p-1 text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
                    >
                      <X className="h-3.5 w-3.5" />
                    </button>
                  </div>
                )}

                {/* Quoted post preview (quote-repost) */}
                {quotedPost && (
                  <QuotedPostCard
                    payload={payloadFromPost(
                      quotedPost,
                      quotedAuthor ?? quotedPost.username ?? "user"
                    )}
                  />
                )}

                {/* Shared film/article card previews — never raw tokens */}
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

                {/* Media previews */}
                {(previews.length > 0 || gifUrls.length > 0) && (
                  <div className="no-scrollbar mb-1 mt-1 flex gap-2 overflow-x-auto">
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
                    {gifUrls.map((src, i) => (
                      <div key={src} className="relative shrink-0">
                        <img
                          src={src}
                          alt=""
                          className="h-40 w-32 rounded-[14px] border border-border object-cover"
                        />
                        <span className="absolute bottom-1.5 left-1.5 rounded-md bg-black/55 px-1.5 py-0.5 text-[9px] font-extrabold text-white">
                          GIF
                        </span>
                        <button
                          onClick={() => removeGif(i)}
                          className="absolute right-1.5 top-1.5 rounded-full bg-black/55 p-1.5 text-white"
                        >
                          <X className="h-3.5 w-3.5" />
                        </button>
                      </div>
                    ))}
                  </div>
                )}

                {/* Toolbar */}
                <div className="-ml-1.5 mt-1 flex items-center gap-0.5">
                  <ToolIcon
                    label="Add photo"
                    onClick={() => fileRef.current?.click()}
                  >
                    <ImageIcon className="h-[22px] w-[22px]" />
                  </ToolIcon>
                  <ToolIcon
                    label="Add GIF"
                    active={showGiphy}
                    onClick={() => {
                      setShowGiphy((v) => !v);
                      setShowEmoji(false);
                    }}
                  >
                    <span className="flex h-[18px] w-[26px] items-center justify-center rounded-[5px] border-2 border-current text-[9px] font-extrabold tracking-tight">
                      GIF
                    </span>
                  </ToolIcon>
                  <ToolIcon
                    label="Add emoji"
                    active={showEmoji}
                    onClick={() => setShowEmoji((v) => !v)}
                  >
                    <Smile className="h-[22px] w-[22px]" />
                  </ToolIcon>
                  {!isStory && (
                    <>
                      <ToolIcon
                        label="Add poll"
                        active={!!poll}
                        onClick={togglePoll}
                      >
                        <BarChart2 className="h-[22px] w-[22px]" />
                      </ToolIcon>
                      <ToolIcon
                        label="Tag people"
                        active={showTag || tagged.length > 0}
                        onClick={() => {
                          setShowTag((v) => !v);
                          setShowGiphy(false);
                          setShowEmoji(false);
                        }}
                      >
                        <Users className="h-[22px] w-[22px]" />
                      </ToolIcon>
                    </>
                  )}
                  <ToolIcon
                    label="Add location"
                    active={!!location || locating}
                    onClick={() => void pickLocation()}
                  >
                    {locating ? (
                      <Loader2 className="h-[22px] w-[22px] animate-spin" />
                    ) : (
                      <MapPin className="h-[22px] w-[22px]" />
                    )}
                  </ToolIcon>
                  <ToolIcon
                    label="Add music"
                    active={!!music}
                    onClick={() => setShowMusic(true)}
                  >
                    <Music className="h-[22px] w-[22px]" />
                  </ToolIcon>
                </div>

                {/* GIF picker */}
                {showGiphy && (
                  <div className="mt-2">
                    <GiphyPicker
                      inline
                      onSelect={addGif}
                      onClose={() => setShowGiphy(false)}
                    />
                  </div>
                )}

                {/* Emoji tray */}
                {showEmoji && (
                  <div className="mt-2 grid grid-cols-8 gap-1 rounded-2xl border border-border bg-card p-2">
                    {EMOJIS.map((e) => (
                      <button
                        key={e}
                        onClick={() => insertEmoji(e)}
                        className="flex h-8 items-center justify-center rounded-lg text-xl transition-colors hover:bg-secondary"
                      >
                        {e}
                      </button>
                    ))}
                  </div>
                )}

                {/* Tag people search */}
                {showTag && (
                  <TagPicker
                    query={tagQuery}
                    setQuery={setTagQuery}
                    selected={tagged}
                    onAdd={addTag}
                    excludeUser={username}
                  />
                )}

                {/* Attachment chips */}
                {(location || tagged.length > 0 || music) && (
                  <div className="mt-2 flex flex-wrap gap-1.5">
                    {location && (
                      <Chip onRemove={() => setLocation(null)}>
                        <MapPin className="h-3.5 w-3.5" />
                        {location}
                      </Chip>
                    )}
                    {tagged.map((t) => (
                      <Chip
                        key={t}
                        onRemove={() =>
                          setTagged((arr) => arr.filter((x) => x !== t))
                        }
                      >
                        @{t}
                      </Chip>
                    ))}
                    {music && (
                      <Chip onRemove={() => setMusic(null)}>
                        <Music className="h-3.5 w-3.5" />
                        {music.title} · {music.artist}
                      </Chip>
                    )}
                  </div>
                )}

                {/* Poll editor */}
                {poll && (
                  <div className="mt-2 space-y-2 rounded-2xl border border-border bg-card p-3">
                    {poll.map((opt, i) => (
                      <div key={i} className="flex items-center gap-2">
                        <input
                          value={opt}
                          onChange={(e) =>
                            setPoll((p) =>
                              (p ?? []).map((o, idx) =>
                                idx === i ? e.target.value : o
                              )
                            )
                          }
                          placeholder={`Option ${i + 1}`}
                          maxLength={60}
                          className="flex-1 rounded-xl border border-border bg-background px-3 py-2 text-sm outline-none focus:border-foreground/40"
                        />
                        {poll.length > 2 && (
                          <button
                            onClick={() =>
                              setPoll((p) =>
                                (p ?? []).filter((_, idx) => idx !== i)
                              )
                            }
                            className="rounded-full p-1 text-muted-foreground hover:bg-secondary"
                            aria-label="Remove option"
                          >
                            <X className="h-4 w-4" />
                          </button>
                        )}
                      </div>
                    ))}
                    {poll.length < 4 && (
                      <button
                        onClick={() => setPoll((p) => [...(p ?? []), ""])}
                        className="flex items-center gap-1.5 text-sm font-semibold text-primary"
                      >
                        <Plus className="h-4 w-4" />
                        Add option
                      </button>
                    )}
                  </div>
                )}
              </div>
            </div>

            {!isStory && (
              <div className="mt-3 flex items-center gap-3 pl-1 opacity-60">
                <Avatar name={username} size={22} />
                <span className="text-[15px] text-muted-foreground">
                  Add to thread
                </span>
              </div>
            )}

            <input
              ref={fileRef}
              type="file"
              accept="image/*"
              multiple={!isStory}
              className="hidden"
              onChange={handlePick}
            />
          </div>

          {/* Footer */}
          <div className="flex items-center justify-between border-t border-border px-4 py-3">
            {isStory ? (
              <span className="flex items-center gap-2 text-[15px] font-semibold text-foreground">
                <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-foreground text-background">
                  <Globe className="h-4 w-4" />
                </span>
                Story · 24h
              </span>
            ) : (
              <DropdownMenu>
                <DropdownMenuTrigger className="flex items-center gap-2 text-[15px] font-semibold text-foreground outline-none">
                  <span className="flex h-7 w-7 items-center justify-center rounded-lg bg-foreground text-background">
                    <activeAudience.icon className="h-4 w-4" />
                  </span>
                  {activeAudience.label}
                  <ChevronDown className="h-4 w-4 text-muted-foreground" />
                </DropdownMenuTrigger>
                <DropdownMenuContent align="start" className="w-56">
                  <DropdownMenuLabel>Who can reply</DropdownMenuLabel>
                  <DropdownMenuSeparator />
                  {AUDIENCES.map((a) => (
                    <DropdownMenuItem
                      key={a.id}
                      onClick={() => setAudience(a.id)}
                    >
                      <a.icon className="mr-2 h-4 w-4" />
                      {a.label}
                      {audience === a.id && (
                        <Check className="ml-auto h-4 w-4" />
                      )}
                    </DropdownMenuItem>
                  ))}
                </DropdownMenuContent>
              </DropdownMenu>
            )}
            <button
              onClick={() => hasContent && publish.mutate()}
              disabled={!hasContent || publish.isPending}
              className={cn(
                "rounded-full px-5 py-2 text-[15px] font-semibold transition-colors",
                hasContent
                  ? "bg-primary text-primary-foreground"
                  : "border border-border text-muted-foreground"
              )}
            >
              {publish.isPending
                ? "Posting…"
                : isStory
                  ? "Share"
                  : "Post"}
            </button>
          </div>
        </Dialog.Content>
      </Dialog.Portal>

      <MusicPickerSheet
        open={showMusic}
        onOpenChange={setShowMusic}
        onPick={(track: MusicTrack) =>
          setMusic({
            id: track.id,
            title: track.title,
            artist: track.artist,
            artworkURL: track.artworkURL,
            previewURL: track.previewURL,
          })
        }
      />

      {flying &&
        createPortal(
          <div className="pointer-events-none fixed inset-0 z-[60] flex items-center justify-center">
            <span className="animate-plane-launch text-primary">
              <Send className="h-16 w-16" fill="currentColor" />
            </span>
          </div>,
          document.body
        )}
    </Dialog.Root>
  );
}

/** Removable attachment chip shown beneath the composer text field. */
function Chip({
  children,
  onRemove,
}: {
  children: React.ReactNode;
  onRemove: () => void;
}) {
  return (
    <span className="inline-flex max-w-full items-center gap-1.5 rounded-full bg-secondary px-2.5 py-1 text-[13px] font-medium text-foreground">
      <span className="flex items-center gap-1 truncate">{children}</span>
      <button
        onClick={onRemove}
        className="shrink-0 rounded-full text-muted-foreground hover:text-foreground"
        aria-label="Remove"
      >
        <X className="h-3.5 w-3.5" />
      </button>
    </span>
  );
}

/** Inline people search used to tag profiles on a post. */
function TagPicker({
  query,
  setQuery,
  selected,
  onAdd,
  excludeUser,
}: {
  query: string;
  setQuery: (v: string) => void;
  selected: string[];
  onAdd: (handle: string) => void;
  excludeUser: string;
}) {
  const [debounced, setDebounced] = useState<string>("");
  useEffect(() => {
    const t = setTimeout(() => setDebounced(query.trim()), 250);
    return () => clearTimeout(t);
  }, [query]);

  const results = useQuery({
    queryKey: ["tag-search", debounced],
    queryFn: () => searchProfiles(debounced),
    enabled: debounced.length > 0,
  });

  const people = (results.data ?? []).filter(
    (p) => p.username !== excludeUser && !selected.includes(p.username)
  );

  return (
    <div className="mt-2 rounded-2xl border border-border bg-card p-2">
      <div className="flex items-center gap-2 rounded-full bg-secondary px-3 py-2">
        <Search className="h-4 w-4 text-muted-foreground" />
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Tag people"
          className="flex-1 bg-transparent text-sm outline-none placeholder:text-muted-foreground"
        />
      </div>
      {debounced.length > 0 && (
        <div className="mt-1 max-h-44 space-y-0.5 overflow-y-auto">
          {people.length === 0 && !results.isLoading && (
            <p className="px-2 py-3 text-center text-sm text-muted-foreground">
              No people found.
            </p>
          )}
          {people.map((p) => (
            <button
              key={p.user_id}
              onClick={() => onAdd(p.username)}
              className="flex w-full items-center gap-2.5 rounded-xl p-1.5 text-left transition-colors hover:bg-secondary"
            >
              <Avatar url={p.profile_image_url} name={p.username} size={32} />
              <span className="min-w-0 flex-1">
                <span className="block truncate text-sm font-semibold">
                  {p.display_name || p.username}
                </span>
                <span className="block truncate text-xs text-muted-foreground">
                  @{p.username}
                </span>
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

export const ComposerModal = memo(ComposerModalBase);
