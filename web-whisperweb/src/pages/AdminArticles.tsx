import { useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  CircleAlert,
  Eye,
  EyeOff,
  ImagePlus,
  Loader2,
  Pencil,
  Plus,
  ShieldCheck,
  Sparkles,
  Trash2,
  X,
} from "lucide-react";
import { toast } from "sonner";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { uploadMedia } from "@/lib/api";
import {
  adminDeleteArticle,
  adminFetchArticles,
  adminSeedArticles,
  adminUpsertArticle,
  type Article,
} from "@/lib/articles";

interface FormState {
  id: string | null;
  title: string;
  slug: string;
  category: string;
  authorName: string;
  excerpt: string;
  coverUrl: string;
  body: string;
  published: boolean;
}

const EMPTY_FORM: FormState = {
  id: null,
  title: "",
  slug: "",
  category: "Training",
  authorName: "Whisper Team",
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
    slug: a.slug,
    category: a.category,
    authorName: a.author_name,
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

/** Admin editor for the public Articles section. */
export default function AdminArticles() {
  const { session, user, loading } = useAuth();
  const [form, setForm] = useState<FormState | null>(null);
  const [uploading, setUploading] = useState<boolean>(false);
  const queryClient = useQueryClient();
  const token = session?.access_token ?? "";

  const list = useQuery({
    queryKey: ["admin-articles", session?.user.id],
    enabled: !!token,
    queryFn: () => adminFetchArticles(token),
    retry: false,
  });

  const save = useMutation({
    mutationFn: async (f: FormState) =>
      adminUpsertArticle(token, {
        id: f.id ?? undefined,
        slug: f.slug.trim() || undefined,
        title: f.title.trim(),
        excerpt: f.excerpt.trim(),
        cover_url: f.coverUrl,
        category: f.category.trim() || "Training",
        author_name: f.authorName.trim() || "Whisper Team",
        paragraphs: f.body
          .split(/\n\s*\n/)
          .map((p) => p.trim())
          .filter(Boolean),
        published: f.published,
      }),
    onSuccess: () => {
      toast.success("Article saved.");
      setForm(null);
      void queryClient.invalidateQueries({ queryKey: ["admin-articles"] });
      void queryClient.invalidateQueries({ queryKey: ["articles"] });
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Something went wrong.");
    },
  });

  const remove = useMutation({
    mutationFn: (id: string) => adminDeleteArticle(token, id),
    onSuccess: () => {
      toast.success("Article removed.");
      void queryClient.invalidateQueries({ queryKey: ["admin-articles"] });
      void queryClient.invalidateQueries({ queryKey: ["articles"] });
    },
    onError: () => toast.error("Couldn't delete. Try again."),
  });

  const seed = useMutation({
    mutationFn: () => adminSeedArticles(token),
    onSuccess: (res) => {
      toast.success(
        res.inserted > 0
          ? `Added ${res.inserted} starter article${res.inserted === 1 ? "" : "s"}.`
          : "Starter articles are already on the site."
      );
      void queryClient.invalidateQueries({ queryKey: ["admin-articles"] });
      void queryClient.invalidateQueries({ queryKey: ["articles"] });
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Something went wrong.");
    },
  });

  const togglePublish = useMutation({
    mutationFn: async (a: Article) => {
      const f = formFromArticle(a);
      return adminUpsertArticle(token, {
        id: a.id,
        slug: a.slug,
        title: f.title,
        excerpt: f.excerpt,
        cover_url: f.coverUrl,
        category: f.category,
        author_name: f.authorName,
        paragraphs: a.paragraphs,
        published: !a.published,
      });
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["admin-articles"] });
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
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="font-display text-[26px] font-extrabold">Articles</h1>
            <p className="mt-2 max-w-xl text-[14px] leading-relaxed text-muted-foreground">
              Written content shown on the public Articles page. A blank line
              starts a new paragraph.
            </p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" className="rounded-full" asChild>
              <Link to="/admin/featured">Featured profiles</Link>
            </Button>
            <Button variant="outline" className="rounded-full" asChild>
              <Link to="/admin/applications">Account reviews</Link>
            </Button>
          </div>
        </div>

        {loading || (list.isPending && !!token) ? (
          <div className="flex justify-center pt-20">
            <Loader2 className="h-8 w-8 animate-spin text-muted-foreground" />
          </div>
        ) : !session ? (
          <div className="mt-10 rounded-[24px] border border-border bg-card p-8 text-center">
            <ShieldCheck className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <p className="text-[15px] font-semibold">
              Sign in with an admin account to manage articles.
            </p>
            <Button className="mt-5 rounded-full" asChild>
              <a href="/auth?next=%2Fadmin%2Farticles">Sign in</a>
            </Button>
          </div>
        ) : forbidden ? (
          <div className="mt-10 rounded-[24px] border border-border bg-card p-8 text-center">
            <CircleAlert className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <p className="text-[15px] font-semibold">
              This account doesn't have admin permissions.
            </p>
          </div>
        ) : list.isError ? (
          <div className="mt-10 rounded-[24px] border border-border bg-card p-8 text-center">
            <CircleAlert className="mx-auto mb-4 h-10 w-10 text-muted-foreground" />
            <p className="text-[15px] font-semibold">
              Couldn't load articles. If this is the first time, run the
              articles SQL in Supabase.
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
              <div className="mt-6 space-y-2">
                <Button
                  className="h-11 w-full rounded-full text-[14px] font-bold"
                  onClick={() => setForm({ ...EMPTY_FORM })}
                >
                  <Plus className="mr-1.5 h-4 w-4" />
                  New article
                </Button>
                <Button
                  variant="outline"
                  className="h-11 w-full rounded-full text-[14px] font-bold"
                  disabled={seed.isPending}
                  onClick={() => seed.mutate()}
                >
                  {seed.isPending ? (
                    <Loader2 className="mr-1.5 h-4 w-4 animate-spin" />
                  ) : (
                    <Sparkles className="mr-1.5 h-4 w-4" />
                  )}
                  Add 6 Whisper-written starter articles
                </Button>
              </div>
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
                      placeholder="How coach tiers actually work"
                      className={inputClass}
                    />
                  </div>

                  <div className="grid gap-4 sm:grid-cols-3">
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
                      <span className={labelClass}>Author</span>
                      <input
                        value={form.authorName}
                        onChange={(e) => update({ authorName: e.target.value })}
                        className={inputClass}
                      />
                    </div>
                    <div>
                      <span className={labelClass}>Slug (optional)</span>
                      <input
                        value={form.slug}
                        onChange={(e) => update({ slug: e.target.value })}
                        placeholder="auto from title"
                        className={inputClass}
                      />
                    </div>
                  </div>

                  <div>
                    <span className={labelClass}>Cover image</span>
                    <div className="flex items-center gap-3">
                      <div className="h-20 w-32 shrink-0 overflow-hidden rounded-2xl bg-secondary">
                        {form.coverUrl && (
                          <img
                            src={form.coverUrl}
                            alt="Cover"
                            className="h-full w-full object-cover"
                          />
                        )}
                      </div>
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
                    </div>
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
                Articles on the site
              </h2>
              {rows.length === 0 ? (
                <div className="mt-3 rounded-[20px] border border-dashed border-border p-8 text-center text-[14px] text-muted-foreground">
                  No articles yet — write the first one above.
                </div>
              ) : (
                <div className="mt-3 space-y-2">
                  {rows.map((a) => (
                    <div
                      key={a.id}
                      className="flex items-center gap-3 rounded-[18px] border border-border bg-card px-4 py-3"
                    >
                      <div className="h-11 w-16 shrink-0 overflow-hidden rounded-xl bg-secondary">
                        {a.cover_url && (
                          <img
                            src={a.cover_url}
                            alt={a.title}
                            className="h-full w-full object-cover"
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
