import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  CircleAlert,
  Eye,
  EyeOff,
  Film,
  ImagePlus,
  Loader2,
  Pencil,
  PenLine,
  Plus,
  Trash2,
  X,
} from "lucide-react";
import { toast } from "sonner";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { ArticleCover } from "@/components/ArticleCover";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { uploadMedia } from "@/lib/api";
import {
  authorDeleteArticle,
  authorFetchArticles,
  authorUpsertArticle,
  type Article,
} from "@/lib/articles";
import { fetchFilms, fetchFilmTimestamps, formatTimecode } from "@/lib/films";

interface FormState {
  id: string | null;
  title: string;
  category: string;
  excerpt: string;
  coverUrl: string;
  body: string;
  published: boolean;
}

const EMPTY_FORM: FormState = {
  id: null,
  title: "",
  category: "Training",
  excerpt: "",
  coverUrl: "",
  body: "",
  published: true,
};

const CATEGORIES = ["Training", "Nutrition", "Coaching", "Athletes", "Community", "News"];

function formFromArticle(a: Article): FormState {
  return {
    id: a.id,
    title: a.title,
    category: a.category,
    excerpt: a.excerpt,
    coverUrl: a.cover_url,
    body: a.paragraphs.join("\n\n"),
    published: a.published,
  };
}

const inputClass =
  "h-10 w-full rounded-full border border-border bg-background px-4 text-[14px] outline-none focus:border-foreground";
const areaClass =
  "w-full rounded-2xl border border-border bg-background px-4 py-3 text-[14px] leading-relaxed outline-none focus:border-foreground";
const labelClass =
  "mb-1.5 block text-[12px] font-extrabold uppercase tracking-wider text-muted-foreground";

/**
 * Article studio for coaches, athletes, and verified creators — they write
 * and manage their own pieces on the public Articles page. The byline is
 * locked to their profile server-side.
 */
export default function WriteArticles() {
  const { session, user, profile, loading } = useAuth();
  const [form, setForm] = useState<FormState | null>(null);
  const [uploading, setUploading] = useState<boolean>(false);
  const [showFilmClips, setShowFilmClips] = useState<boolean>(false);
  const [selectedFilmId, setSelectedFilmId] = useState<string | null>(null);
  const queryClient = useQueryClient();
  const token = session?.access_token ?? "";

  // Films + timestamps for the film-clip placeholder picker. Lets bloggers
  // use a timestamped film frame as the article cover instead of an upload.
  const filmsQuery = useQuery({
    queryKey: ["films-for-clips"],
    queryFn: () => fetchFilms(),
    enabled: showFilmClips,
  });
  const timestampsQuery = useQuery({
    queryKey: ["film-timestamps-for-clips", selectedFilmId],
    queryFn: () => fetchFilmTimestamps(selectedFilmId!),
    enabled: !!selectedFilmId,
  });

  const list = useQuery({
    queryKey: ["author-articles", session?.user.id],
    enabled: !!token,
    queryFn: () => authorFetchArticles(token),
    retry: false,
  });

  const save = useMutation({
    mutationFn: async (f: FormState) =>
      authorUpsertArticle(token, {
        id: f.id ?? undefined,
        title: f.title.trim(),
        excerpt: f.excerpt.trim(),
        cover_url: f.coverUrl,
        category: f.category.trim() || "Training",
        author_name: "", // ignored — the backend locks the byline
        paragraphs: f.body
          .split(/\n\s*\n/)
          .map((p) => p.trim())
          .filter(Boolean),
        published: f.published,
      }),
    onSuccess: () => {
      toast.success("Article saved.");
      setForm(null);
      void queryClient.invalidateQueries({ queryKey: ["author-articles"] });
      void queryClient.invalidateQueries({ queryKey: ["articles"] });
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Something went wrong.");
    },
  });

  const remove = useMutation({
    mutationFn: (id: string) => authorDeleteArticle(token, id),
    onSuccess: () => {
      toast.success("Article removed.");
      void queryClient.invalidateQueries({ queryKey: ["author-articles"] });
      void queryClient.invalidateQueries({ queryKey: ["articles"] });
    },
    onError: () => toast.error("Couldn't delete. Try again."),
  });

  const togglePublish = useMutation({
    mutationFn: async (a: Article) =>
      authorUpsertArticle(token, {
        id: a.id,
        title: a.title,
        excerpt: a.excerpt,
        cover_url: a.cover_url,
        category: a.category,
        author_name: "",
        paragraphs: a.paragraphs,
        published: !a.published,
      }),
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["author-articles"] });
      void queryClient.invalidateQueries({ queryKey: ["articles"] });
    },
    onError: () => toast.error("Couldn't update. Try again."),
  });

  const forbidden =
    list.error instanceof Error && list.error.message === "forbidden";

  const rows = useMemo(() => list.data ?? [], [list.data]);

  const handleCover = async (file: File | null): Promise<void> => {
    if (!file || !form || !user) return;
    setUploading(true);
    try {
      const url = await uploadMedia(file, user.id);
      setForm({ ...form, coverUrl: url });
    } catch {
      toast.error("Cover upload failed. Try again.");
    } finally {
      setUploading(false);
    }
  };

  const update = (patch: Partial<FormState>): void => {
    setForm((f) => (f ? { ...f, ...patch } : f));
  };

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <PublicNav />

      <main className="mx-auto w-full max-w-3xl flex-1 px-4 pb-16 pt-28 sm:px-6">
        <div className="flex items-center gap-3">
          <div className="flex h-11 w-11 items-center justify-center rounded-2xl bg-foreground text-background">
            <PenLine className="h-5 w-5" />
          </div>
          <div>
            <h1 className="font-display text-[26px] font-extrabold">
              Write for Whisper
            </h1>
            <p className="text-[13.5px] text-muted-foreground">
              Published under {profile?.display_name || `@${profile?.username ?? "you"}`} on the public Articles page.
            </p>
          </div>
        </div>

        {loading || (list.isPending && !!token) ? (
          <div className="flex justify-center pt-20">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : !session ? (
          <div className="mt-10 rounded-[24px] border border-border bg-card p-8 text-center">
            <CircleAlert className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <p className="text-[15px] font-semibold">
              Sign in to write articles.
            </p>
            <Button className="mt-5 rounded-full" asChild>
              <a href="/auth?next=%2Fstudio%2Farticles">Sign in</a>
            </Button>
          </div>
        ) : forbidden ? (
          <div className="mt-10 rounded-[24px] border border-border bg-card p-8 text-center">
            <CircleAlert className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <p className="text-[15px] font-semibold">
              Writing is open to coaches, athletes, and verified creators.
            </p>
            <p className="mt-2 text-[13.5px] text-muted-foreground">
              Apply for a badge in Settings → Special accounts to unlock it.
            </p>
            <Button className="mt-5 rounded-full" asChild>
              <Link to="/settings">Open Settings</Link>
            </Button>
          </div>
        ) : list.isError ? (
          <div className="mt-10 rounded-[24px] border border-border bg-card p-8 text-center">
            <CircleAlert className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <p className="text-[15px] font-semibold">
              Couldn't load your articles. Try again in a moment.
            </p>
            <Button
              variant="outline"
              className="mt-5 rounded-full"
              onClick={() => void list.refetch()}
            >
              Retry
            </Button>
          </div>
        ) : (
          <>
            {!form && (
              <Button
                className="mt-6 h-11 w-full rounded-full text-[14px] font-bold"
                onClick={() => setForm({ ...EMPTY_FORM })}
              >
                <Plus className="mr-1.5 h-4 w-4" />
                New article
              </Button>
            )}

            {form && (
              <section className="mt-6 rounded-[24px] border border-border bg-card p-5 sm:p-6">
                <div className="flex items-center justify-between">
                  <h2 className="text-[16px] font-extrabold">
                    {form.id ? "Edit article" : "New article"}
                  </h2>
                  <button
                    onClick={() => setForm(null)}
                    className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-muted-foreground hover:text-foreground"
                    aria-label="Close editor"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>

                <div className="mt-5 space-y-4">
                  <div>
                    <span className={labelClass}>Title</span>
                    <input
                      value={form.title}
                      onChange={(e) => update({ title: e.target.value })}
                      placeholder="My off-season training philosophy"
                      className={inputClass}
                    />
                  </div>

                  <div>
                    <span className={labelClass}>Category</span>
                    <select
                      value={form.category}
                      onChange={(e) => update({ category: e.target.value })}
                      className={inputClass}
                    >
                      {CATEGORIES.map((c) => (
                        <option key={c} value={c}>
                          {c}
                        </option>
                      ))}
                    </select>
                  </div>

                  <div>
                    <span className={labelClass}>Cover image</span>
                    <div className="flex items-center gap-3">
                      <div className="relative h-20 w-32 shrink-0 overflow-hidden rounded-2xl bg-secondary">
                        {form.coverUrl && (
                          <ArticleCover
                            cover={form.coverUrl}
                            alt="Cover"
                            className="absolute inset-0"
                          />
                        )}
                      </div>
                      <div className="flex flex-col gap-2">
                        <label className="flex cursor-pointer items-center gap-2 rounded-full border border-border bg-background px-4 py-2.5 text-[13.5px] font-bold hover:bg-secondary">
                          {uploading ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : (
                            <ImagePlus className="h-4 w-4" />
                          )}
                          {form.coverUrl ? "Replace cover" : "Upload cover"}
                          <input
                            type="file"
                            accept="image/*"
                            className="hidden"
                            onChange={(e) =>
                              void handleCover(e.target.files?.[0] ?? null)
                            }
                          />
                        </label>
                        <button
                          type="button"
                          onClick={() => setShowFilmClips((v) => !v)}
                          className="flex items-center gap-2 rounded-full border border-border bg-background px-4 py-2.5 text-[13.5px] font-bold hover:bg-secondary"
                        >
                          <Film className="h-4 w-4" />
                          Use film clip
                        </button>
                      </div>
                    </div>

                    {showFilmClips && (
                      <div className="mt-3 rounded-2xl border border-border bg-secondary/30 p-3">
                        <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                          Pick a film timestamp
                        </p>
                        <select
                          value={selectedFilmId ?? ""}
                          onChange={(e) => setSelectedFilmId(e.target.value || null)}
                          className="mb-2 w-full rounded-lg border border-border bg-background px-3 py-2 text-[13px] outline-none"
                        >
                          <option value="">Choose a film…</option>
                          {(filmsQuery.data ?? []).map((f) => (
                            <option key={f.id} value={f.id}>
                              {f.title}
                            </option>
                          ))}
                        </select>
                        {selectedFilmId && (timestampsQuery.data ?? []).length > 0 && (
                          <div className="space-y-1.5">
                            {(timestampsQuery.data ?? []).map((ts) => (
                              <button
                                key={ts.id}
                                type="button"
                                onClick={() => {
                                  setForm((prev) =>
                                    prev ? { ...prev, coverUrl: ts.poster_url ?? "" } : prev
                                  );
                                  setShowFilmClips(false);
                                  toast.success(`Film clip set: ${formatTimecode(ts.time_seconds)} — ${ts.label.slice(0, 40)}`);
                                }}
                                className="flex w-full items-center gap-2 rounded-lg border border-border bg-background px-3 py-2 text-left text-[12.5px] transition-colors hover:bg-secondary"
                              >
                                <span className="rounded bg-foreground px-1.5 py-0.5 font-mono text-[11px] font-bold text-background">
                                  {formatTimecode(ts.time_seconds)}
                                </span>
                                <span className="min-w-0 flex-1 truncate">{ts.label}</span>
                              </button>
                            ))}
                          </div>
                        )}
                        {selectedFilmId && (timestampsQuery.data ?? []).length === 0 && (
                          <p className="py-2 text-center text-[12px] text-muted-foreground">
                            No timestamps on this film yet. Mark one from the film page.
                          </p>
                        )}
                      </div>
                    )}
                  </div>

                  <div>
                    <span className={labelClass}>
                      Excerpt (shown on the article card)
                    </span>
                    <textarea
                      value={form.excerpt}
                      onChange={(e) => update({ excerpt: e.target.value })}
                      rows={2}
                      placeholder="One or two sentences…"
                      className={areaClass}
                    />
                  </div>

                  <div>
                    <span className={labelClass}>
                      Body (blank line = new paragraph)
                    </span>
                    <textarea
                      value={form.body}
                      onChange={(e) => update({ body: e.target.value })}
                      rows={12}
                      placeholder="Write the article…"
                      className={areaClass}
                    />
                  </div>

                  <label className="flex items-center gap-2 text-[13.5px] font-semibold">
                    <input
                      type="checkbox"
                      checked={form.published}
                      onChange={(e) => update({ published: e.target.checked })}
                      className="h-4 w-4 accent-foreground"
                    />
                    Published
                  </label>

                  <Button
                    className="h-12 w-full rounded-full text-[14.5px] font-bold"
                    disabled={save.isPending || !form.title.trim() || !form.body.trim()}
                    onClick={() => save.mutate(form)}
                  >
                    {save.isPending ? (
                      <Loader2 className="h-4 w-4 animate-spin" />
                    ) : form.id ? (
                      "Save changes"
                    ) : (
                      "Publish article"
                    )}
                  </Button>
                </div>
              </section>
            )}

            <section className="mt-8">
              <h2 className="text-[13px] font-extrabold uppercase tracking-wider text-muted-foreground">
                Your articles
              </h2>
              {rows.length === 0 ? (
                <div className="mt-3 rounded-[20px] border border-dashed border-border p-8 text-center text-[14px] text-muted-foreground">
                  Nothing yet — write your first article above.
                </div>
              ) : (
                <div className="mt-3 space-y-2">
                  {rows.map((a) => (
                    <div
                      key={a.id}
                      className="flex items-center gap-3 rounded-[18px] border border-border bg-card px-4 py-3"
                    >
                      <div className="relative h-11 w-16 shrink-0 overflow-hidden rounded-xl bg-secondary">
                        {a.cover_url && (
                          <ArticleCover
                            cover={a.cover_url}
                            alt={a.title}
                            className="absolute inset-0"
                          />
                        )}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[14.5px] font-bold">{a.title}</p>
                        <p className="truncate text-[12.5px] text-muted-foreground">
                          {[a.category, a.published ? "Published" : "Draft"].join(" · ")}
                        </p>
                      </div>
                      <button
                        onClick={() => togglePublish.mutate(a)}
                        disabled={togglePublish.isPending}
                        className="rounded-full p-2 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                        aria-label={a.published ? "Unpublish" : "Publish"}
                        title={a.published ? "Unpublish" : "Publish"}
                      >
                        {a.published ? (
                          <Eye className="h-4 w-4" />
                        ) : (
                          <EyeOff className="h-4 w-4" />
                        )}
                      </button>
                      <button
                        onClick={() => {
                          setForm(formFromArticle(a));
                          window.scrollTo({ top: 0, behavior: "smooth" });
                        }}
                        className="rounded-full p-2 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                        aria-label={`Edit ${a.title}`}
                      >
                        <Pencil className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => {
                          if (window.confirm(`Delete "${a.title}"?`)) {
                            remove.mutate(a.id);
                          }
                        }}
                        disabled={remove.isPending}
                        className="rounded-full p-2 text-muted-foreground transition-colors hover:bg-accent hover:text-red-500"
                        aria-label={`Delete ${a.title}`}
                      >
                        <Trash2 className="h-4 w-4" />
                      </button>
                    </div>
                  ))}
                </div>
              )}
            </section>
          </>
        )}
      </main>

      <PublicFooter />
    </div>
  );
}
