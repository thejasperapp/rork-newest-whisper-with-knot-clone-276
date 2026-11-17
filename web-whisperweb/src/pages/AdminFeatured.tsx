import { useEffect, useMemo, useState } from "react";
import { Link } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  BadgeCheck,
  CalendarCheck,
  CircleAlert,
  Dumbbell,
  Eye,
  EyeOff,
  ImagePlus,
  Link as LinkIcon,
  Loader2,
  Mail,
  Medal,
  Pencil,
  Plus,
  Search,
  ShieldCheck,
  Trash2,
  UserSearch,
  X,
} from "lucide-react";
import { toast } from "sonner";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Avatar } from "@/components/Avatar";
import { FeaturedProfileCard } from "@/components/FeaturedProfileCard";
import { Button } from "@/components/ui/button";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { searchProfiles, uploadMedia } from "@/lib/api";
import {
  adminDeleteFeatured,
  adminFetchFeatured,
  adminUpsertFeatured,
  HUDSON_TEMPLATE,
  TAYLOR_BROOKE_TEMPLATE,
  type FeaturedActionButton,
  type FeaturedActionType,
  type FeaturedKind,
  type FeaturedProfile,
  type FeaturedTestimonial,
} from "@/lib/featured";

const KIND_TABS: { kind: FeaturedKind; label: string; icon: React.ReactNode }[] = [
  { kind: "coach", label: "Coaches", icon: <Dumbbell className="h-4 w-4" /> },
  { kind: "athlete", label: "Athletes", icon: <Medal className="h-4 w-4" /> },
  { kind: "creator", label: "Creators", icon: <BadgeCheck className="h-4 w-4" /> },
  { kind: "recruiter", label: "Recruiters", icon: <UserSearch className="h-4 w-4" /> },
];

interface FormState {
  id: string | null;
  kind: FeaturedKind;
  name: string;
  username: string;
  photoUrl: string;
  tier: string;
  discipline: string;
  age: string;
  chips: string;
  bio: string;
  highlights: string;
  testimonials: FeaturedTestimonial[];
  ctaLabel: string;
  ctaUrl: string;
  actionButtons: FeaturedActionButton[];
  sortOrder: string;
  published: boolean;
}

const EMPTY_FORM: FormState = {
  id: null,
  kind: "coach",
  name: "",
  username: "",
  photoUrl: "",
  tier: "1",
  discipline: "",
  age: "",
  chips: "",
  bio: "",
  highlights: "",
  testimonials: [],
  ctaLabel: "",
  ctaUrl: "",
  actionButtons: [],
  sortOrder: "0",
  published: true,
};

function formFromProfile(p: FeaturedProfile): FormState {
  // Prefer typed action_buttons; fall back to synthesizing one from the
  // legacy cta_label/cta_url so older rows still render an editable button.
  const actionButtons: FeaturedActionButton[] =
    p.action_buttons.length > 0
      ? p.action_buttons
      : p.cta_label
        ? [
            {
              label: p.cta_label,
              type: p.cta_url ? "link" : "profile",
              href: p.cta_url ?? "",
            },
          ]
        : [];
  return {
    id: p.id,
    kind: p.kind,
    name: p.name,
    username: p.username ?? "",
    photoUrl: p.photo_url,
    tier: p.tier ? String(p.tier) : "",
    discipline: p.discipline ?? "",
    age: p.age ?? "",
    chips: p.chips.join(", "),
    bio: p.paragraphs.join("\n\n"),
    highlights: p.highlights.join("\n"),
    testimonials: p.testimonials,
    ctaLabel: p.cta_label ?? "",
    ctaUrl: p.cta_url ?? "",
    actionButtons,
    sortOrder: String(p.sort_order),
    published: p.published,
  };
}

function previewFromForm(form: FormState): FeaturedProfile {
  const cleanButtons: FeaturedActionButton[] = form.actionButtons
    .map((b) => ({
      label: b.label.trim(),
      type: b.type,
      href: b.href.trim(),
    }))
    .filter((b) => b.label.length > 0)
    .slice(0, 3);
  return {
    id: form.id ?? "preview",
    kind: form.kind,
    name: form.name || "Name",
    username: form.username.trim().replace(/^@/, "") || null,
    user_id: null,
    photo_url: form.photoUrl,
    tier:
      form.kind === "coach" && form.tier ? Number.parseInt(form.tier, 10) : null,
    discipline: form.discipline.trim() || null,
    age: form.age.trim() || null,
    chips: form.chips
      .split(",")
      .map((c) => c.trim())
      .filter(Boolean),
    paragraphs: form.bio
      .split(/\n\s*\n/)
      .map((p) => p.trim())
      .filter(Boolean),
    highlights: form.highlights
      .split("\n")
      .map((h) => h.trim())
      .filter(Boolean),
    testimonials: form.testimonials.filter((t) => t.quote.trim().length > 0),
    cta_label: form.ctaLabel.trim() || null,
    cta_url: form.ctaUrl.trim() || null,
    action_buttons: cleanButtons,
    sort_order: Number.parseInt(form.sortOrder, 10) || 0,
    published: form.published,
  };
}

const inputClass =
  "h-10 w-full rounded-full border border-border bg-background px-4 text-[14px] outline-none focus:border-foreground";
const areaClass =
  "w-full rounded-2xl border border-border bg-background px-4 py-3 text-[14px] leading-relaxed outline-none focus:border-foreground";
const labelClass =
  "mb-1.5 block text-[12px] font-extrabold uppercase tracking-wider text-muted-foreground";

/**
 * Tracks which built-in templates (Hudson, Taylor Brooke) an admin has
 * explicitly dismissed via the delete button, so the dashed "Import" card
 * doesn't reappear the instant the DB row is removed.
 */
const DISMISSED_KEY = "whisper_admin_dismissed_templates";
function loadDismissed(): Set<string> {
  try {
    const raw = localStorage.getItem(DISMISSED_KEY);
    return new Set((raw ? JSON.parse(raw) : []) as string[]);
  } catch {
    return new Set();
  }
}
function saveDismissed(ids: Set<string>): void {
  try {
    localStorage.setItem(DISMISSED_KEY, JSON.stringify([...ids]));
  } catch {
    /* ignore */
  }
}

/**
 * Admin editor for featured spotlight profiles — the "Hudson" template.
 * Fill in the fields, search-select the person's Whisper username, and the
 * card appears on the public Coaches / Athletes / Creators pages exactly
 * like the Hudson feature.
 */
export default function AdminFeatured() {
  const { session, user, loading } = useAuth();
  const [tab, setTab] = useState<FeaturedKind>("coach");
  const [form, setForm] = useState<FormState | null>(null);
  const [userQuery, setUserQuery] = useState<string>("");
  const [debouncedQuery, setDebouncedQuery] = useState<string>("");
  const [uploading, setUploading] = useState<boolean>(false);
  const [dismissed, setDismissed] = useState<Set<string>>(() => loadDismissed());
  const queryClient = useQueryClient();
  const token = session?.access_token ?? "";

  useEffect(() => {
    const t = setTimeout(() => setDebouncedQuery(userQuery.trim()), 250);
    return () => clearTimeout(t);
  }, [userQuery]);

  const list = useQuery({
    queryKey: ["admin-featured", session?.user.id],
    enabled: !!token,
    queryFn: () => adminFetchFeatured(token),
    retry: false,
  });

  const userResults = useQuery({
    queryKey: ["admin-featured-user-search", session?.user.id, debouncedQuery],
    enabled: !!session && !!form && debouncedQuery.length > 0,
    queryFn: () => searchProfiles(debouncedQuery),
  });

  const save = useMutation({
    mutationFn: async (f: FormState) => {
      const preview = previewFromForm(f);
      return adminUpsertFeatured(token, {
        id: f.id ?? undefined,
        kind: preview.kind,
        name: preview.name,
        username: preview.username,
        photo_url: preview.photo_url,
        tier: preview.tier,
        discipline: preview.discipline,
        age: preview.age,
        chips: preview.chips,
        paragraphs: preview.paragraphs,
        highlights: preview.highlights,
        testimonials: preview.testimonials,
        cta_label: preview.cta_label,
        cta_url: preview.cta_url,
        action_buttons: preview.action_buttons,
        sort_order: preview.sort_order,
        published: preview.published,
      });
    },
    onSuccess: () => {
      toast.success("Profile saved — it's live on the public page.");
      setForm(null);
      setUserQuery("");
      void queryClient.invalidateQueries({ queryKey: ["admin-featured"] });
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Something went wrong.");
    },
  });

  const remove = useMutation({
    mutationFn: async (p: FeaturedProfile) => {
      await adminDeleteFeatured(token, p.id);
      // Suppress the built-in template card for deleted DB rows so the dashed
      // "Import" row doesn't reappear the instant the row is removed.
      if (p.kind === "coach" && p.name.trim().toLowerCase() === "hudson") {
        const next = new Set(dismissed);
        next.add("hudson");
        setDismissed(next);
        saveDismissed(next);
      } else if (
        p.kind === "creator" &&
        p.name.trim().toLowerCase() === "taylor brooke"
      ) {
        const next = new Set(dismissed);
        next.add("taylor-brooke");
        setDismissed(next);
        saveDismissed(next);
      }
    },
    onSuccess: () => {
      toast.success("Profile removed.");
      void queryClient.invalidateQueries({ queryKey: ["admin-featured"] });
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Something went wrong.");
    },
  });

  const togglePublish = useMutation({
    mutationFn: async (p: FeaturedProfile) => {
      const f = formFromProfile(p);
      f.published = !p.published;
      const preview = previewFromForm(f);
      return adminUpsertFeatured(token, {
        id: p.id,
        kind: preview.kind,
        name: preview.name,
        username: preview.username,
        photo_url: preview.photo_url,
        tier: preview.tier,
        discipline: preview.discipline,
        age: preview.age,
        chips: preview.chips,
        paragraphs: preview.paragraphs,
        highlights: preview.highlights,
        testimonials: preview.testimonials,
        cta_label: preview.cta_label,
        cta_url: preview.cta_url,
        action_buttons: preview.action_buttons,
        sort_order: preview.sort_order,
        published: f.published,
      });
    },
    onSuccess: () => {
      void queryClient.invalidateQueries({ queryKey: ["admin-featured"] });
    },
    onError: () => toast.error("Couldn't update. Try again."),
  });

  const forbidden =
    list.error instanceof Error && list.error.message === "forbidden";

  const rows = useMemo(
    () => (list.data ?? []).filter((p) => p.kind === tab),
    [list.data, tab]
  );

  // The built-in Hudson card lives in code until an admin imports it here.
  // Importing pre-fills the editor so the real account can be search-linked;
  // once saved, the database row replaces the built-in one on the site.
  const hudsonInDb = useMemo(
    () =>
      (list.data ?? []).some(
        (p) => p.kind === "coach" && p.name.trim().toLowerCase() === "hudson"
      ),
    [list.data]
  );
  const hudsonDismissed = dismissed.has("hudson");

  const taylorInDb = useMemo(
    () =>
      (list.data ?? []).some(
        (p) =>
          p.kind === "creator" &&
          p.name.trim().toLowerCase() === "taylor brooke"
      ),
    [list.data]
  );
  const taylorDismissed = dismissed.has("taylor-brooke");

  const importHudson = (): void => {
    const f = formFromProfile(HUDSON_TEMPLATE);
    f.id = null;
    setForm(f);
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const importTaylor = (): void => {
    const f = formFromProfile(TAYLOR_BROOKE_TEMPLATE);
    f.id = null;
    setForm(f);
    window.scrollTo({ top: 0, behavior: "smooth" });
  };

  const handlePhoto = async (file: File | null): Promise<void> => {
    if (!file || !form || !user) return;
    setUploading(true);
    try {
      const url = await uploadMedia(file, user.id);
      setForm({ ...form, photoUrl: url });
    } catch {
      toast.error("Photo upload failed. Try again.");
    } finally {
      setUploading(false);
    }
  };

  const update = (patch: Partial<FormState>): void => {
    setForm((f) => (f ? { ...f, ...patch } : f));
  };

  const ACTION_TYPES: { value: FeaturedActionType; label: string; icon: React.ReactNode; hint: string }[] = [
    { value: "profile", label: "In-app profile", icon: <UserSearch className="h-4 w-4" />, hint: "Opens the linked Whisper profile (or signup for visitors)." },
    { value: "calendar", label: "Schedule a call", icon: <CalendarCheck className="h-4 w-4" />, hint: "Opens the internal Whisper calendar (badged members / recruiter)." },
    { value: "email", label: "Email", icon: <Mail className="h-4 w-4" />, hint: "Opens a compose window — enter the email address." },
    { value: "link", label: "External link", icon: <LinkIcon className="h-4 w-4" />, hint: "Opens any URL in a new tab — enter the full https:// link." },
  ];

  const addButton = (): void => {
    if (!form) return;
    if (form.actionButtons.length >= 3) return;
    update({
      actionButtons: [
        ...form.actionButtons,
        { label: "", type: "profile", href: "" },
      ],
    });
  };

  const updateButton = (index: number, patch: Partial<FeaturedActionButton>): void => {
    if (!form) return;
    const next = form.actionButtons.map((b, i) => (i === index ? { ...b, ...patch } : b));
    update({ actionButtons: next });
  };

  const removeButton = (index: number): void => {
    if (!form) return;
    update({ actionButtons: form.actionButtons.filter((_, i) => i !== index) });
  };

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <PublicNav />

      <main className="mx-auto w-full max-w-3xl flex-1 px-4 pb-16 pt-28 sm:px-6">
        <div className="flex flex-wrap items-center justify-between gap-3">
          <div>
            <h1 className="font-display text-[26px] font-extrabold">
              Featured profiles
            </h1>
            <p className="mt-2 max-w-xl text-[14px] leading-relaxed text-muted-foreground">
              Spotlight cards shown on the public Coaches, Athlete, and Creator
              pages — same template as the Hudson feature. Link a real Whisper
              account so the button opens their profile.
            </p>
          </div>
          <div className="flex gap-2">
            <Button variant="outline" className="rounded-full" asChild>
              <Link to="/admin/articles">Articles</Link>
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
              Sign in with an admin account to manage featured profiles.
            </p>
            <Button className="mt-5 rounded-full" asChild>
              <a href="/auth?next=%2Fadmin%2Ffeatured">Sign in</a>
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
              Couldn't load featured profiles. If this is the first time, run
              the featured-profiles SQL in Supabase.
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
            <div className="mt-6 flex gap-2">
              {KIND_TABS.map((t) => {
                const count = (list.data ?? []).filter(
                  (p) => p.kind === t.kind
                ).length;
                const selected = tab === t.kind;
                return (
                  <button
                    key={t.kind}
                    onClick={() => setTab(t.kind)}
                    className={cn(
                      "flex flex-1 items-center justify-center gap-2 rounded-full border px-3 py-2.5 text-[13.5px] font-bold transition-colors",
                      selected
                        ? "border-foreground bg-foreground text-background"
                        : "border-border bg-card text-foreground hover:bg-accent"
                    )}
                  >
                    {t.icon}
                    {t.label}
                    {count > 0 && (
                      <span
                        className={cn(
                          "rounded-full px-1.5 py-0.5 text-[11px] font-extrabold",
                          selected
                            ? "bg-background text-foreground"
                            : "bg-foreground text-background"
                        )}
                      >
                        {count}
                      </span>
                    )}
                  </button>
                );
              })}
            </div>

            {!form && (
              <Button
                className="mt-6 h-11 w-full rounded-full text-[14px] font-bold"
                onClick={() => setForm({ ...EMPTY_FORM, kind: tab })}
              >
                <Plus className="mr-1.5 h-4 w-4" />
                New {tab} profile
              </Button>
            )}

            {form && (
              <section className="mt-6 rounded-[24px] border border-border bg-card p-5 sm:p-6">
                <div className="flex items-center justify-between">
                  <h2 className="text-[16px] font-extrabold">
                    {form.id ? "Edit profile" : `New ${form.kind} profile`}
                  </h2>
                  <button
                    onClick={() => {
                      setForm(null);
                      setUserQuery("");
                    }}
                    className="flex h-8 w-8 items-center justify-center rounded-full bg-secondary text-muted-foreground hover:text-foreground"
                    aria-label="Close editor"
                  >
                    <X className="h-4 w-4" />
                  </button>
                </div>

                <div className="mt-5 space-y-4">
                  {/* Kind + published */}
                  <div className="flex flex-wrap items-center gap-2">
                    {KIND_TABS.map((t) => (
                      <button
                        key={t.kind}
                        onClick={() => update({ kind: t.kind })}
                        className={cn(
                          "rounded-full border px-4 py-2 text-[13px] font-bold",
                          form.kind === t.kind
                            ? "border-foreground bg-foreground text-background"
                            : "border-border bg-background"
                        )}
                      >
                        {t.label.replace(/s$/, "")}
                      </button>
                    ))}
                    <label className="ml-auto flex items-center gap-2 text-[13.5px] font-semibold">
                      <input
                        type="checkbox"
                        checked={form.published}
                        onChange={(e) => update({ published: e.target.checked })}
                        className="h-4 w-4 accent-foreground"
                      />
                      Published
                    </label>
                  </div>

                  {/* Photo */}
                  <div>
                    <span className={labelClass}>Photo</span>
                    <div className="flex items-center gap-3">
                      <div className="h-20 w-20 shrink-0 overflow-hidden rounded-2xl bg-secondary">
                        {form.photoUrl && (
                          <img
                            src={form.photoUrl}
                            alt="Profile"
                            className="h-full w-full object-cover object-top"
                          />
                        )}
                      </div>
                      <label className="flex cursor-pointer items-center gap-2 rounded-full border border-border bg-background px-4 py-2.5 text-[13.5px] font-bold hover:bg-secondary">
                        {uploading ? (
                          <Loader2 className="h-4 w-4 animate-spin" />
                        ) : (
                          <ImagePlus className="h-4 w-4" />
                        )}
                        {form.photoUrl ? "Replace photo" : "Upload photo"}
                        <input
                          type="file"
                          accept="image/*"
                          className="hidden"
                          onChange={(e) =>
                            void handlePhoto(e.target.files?.[0] ?? null)
                          }
                        />
                      </label>
                    </div>
                  </div>

                  {/* Name + username search */}
                  <div className="grid gap-4 sm:grid-cols-2">
                    <div>
                      <span className={labelClass}>Display name</span>
                      <input
                        value={form.name}
                        onChange={(e) => update({ name: e.target.value })}
                        placeholder="Hudson"
                        className={inputClass}
                      />
                    </div>
                    <div className="relative">
                      <span className={labelClass}>
                        Linked Whisper account
                      </span>
                      {form.username ? (
                        <div className="flex h-10 items-center justify-between rounded-full border border-border bg-background px-4">
                          <span className="text-[14px] font-semibold">
                            @{form.username}
                          </span>
                          <button
                            onClick={() => update({ username: "" })}
                            className="text-muted-foreground hover:text-foreground"
                            aria-label="Unlink account"
                          >
                            <X className="h-4 w-4" />
                          </button>
                        </div>
                      ) : (
                        <>
                          <div className="flex h-10 items-center gap-2 rounded-full border border-border bg-background px-4">
                            <Search className="h-4 w-4 text-muted-foreground" />
                            <input
                              value={userQuery}
                              onChange={(e) => setUserQuery(e.target.value)}
                              placeholder="Search username…"
                              className="flex-1 bg-transparent text-[14px] outline-none"
                            />
                          </div>
                          {userQuery.trim().length > 0 && (
                            <div className="absolute inset-x-0 top-full z-20 mt-1 max-h-56 overflow-y-auto rounded-2xl border border-border bg-card p-1.5 shadow-lg">
                              {userResults.isPending ? (
                                <div className="flex justify-center py-4">
                                  <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />
                                </div>
                              ) : (userResults.data ?? []).length === 0 ? (
                                <p className="px-3 py-3 text-[13px] text-muted-foreground">
                                  No one found.
                                </p>
                              ) : (
                                (userResults.data ?? []).map((p) => (
                                  <button
                                    key={p.user_id}
                                    onClick={() => {
                                      update({
                                        username: p.username,
                                        name: form.name || (p.display_name ?? p.username),
                                        photoUrl:
                                          form.photoUrl ||
                                          (p.profile_image_url ?? ""),
                                      });
                                      setUserQuery("");
                                    }}
                                    className="flex w-full items-center gap-2.5 rounded-xl px-2.5 py-2 text-left hover:bg-secondary"
                                  >
                                    <Avatar
                                      url={p.profile_image_url}
                                      name={p.username}
                                      size={30}
                                    />
                                    <span className="min-w-0">
                                      <span className="block truncate text-[13.5px] font-bold">
                                        {p.display_name || p.username}
                                      </span>
                                      <span className="block truncate text-[12px] text-muted-foreground">
                                        @{p.username}
                                      </span>
                                    </span>
                                  </button>
                                ))
                              )}
                            </div>
                          )}
                        </>
                      )}
                    </div>
                  </div>

                  {/* Tier / discipline / age */}
                  <div className="grid gap-4 sm:grid-cols-3">
                    {form.kind === "coach" && (
                      <div>
                        <span className={labelClass}>Tier</span>
                        <select
                          value={form.tier}
                          onChange={(e) => update({ tier: e.target.value })}
                          className={inputClass}
                        >
                          <option value="">No tier</option>
                          <option value="1">Tier 1</option>
                          <option value="2">Tier 2</option>
                          <option value="3">Tier 3</option>
                        </select>
                      </div>
                    )}
                    <div>
                      <span className={labelClass}>
                        {form.kind === "coach"
                          ? "Coaching style"
                          : form.kind === "athlete"
                            ? "Sport"
                            : "Content focus"}
                      </span>
                      <input
                        value={form.discipline}
                        onChange={(e) => update({ discipline: e.target.value })}
                        placeholder={
                          form.kind === "coach" ? "Bodybuilding" : "Sprinting"
                        }
                        className={inputClass}
                      />
                    </div>
                    <div>
                      <span className={labelClass}>Age chip</span>
                      <input
                        value={form.age}
                        onChange={(e) => update({ age: e.target.value })}
                        placeholder="27 years old"
                        className={inputClass}
                      />
                    </div>
                  </div>

                  <div>
                    <span className={labelClass}>
                      Interest chips (comma separated)
                    </span>
                    <input
                      value={form.chips}
                      onChange={(e) => update({ chips: e.target.value })}
                      placeholder="Golf, Family"
                      className={inputClass}
                    />
                  </div>

                  <div>
                    <span className={labelClass}>
                      Bio (blank line = new paragraph)
                    </span>
                    <textarea
                      value={form.bio}
                      onChange={(e) => update({ bio: e.target.value })}
                      rows={5}
                      placeholder="Who they are, how they work…"
                      className={areaClass}
                    />
                  </div>

                  <div>
                    <span className={labelClass}>
                      Highlights (one per line, up to 4 look best)
                    </span>
                    <textarea
                      value={form.highlights}
                      onChange={(e) => update({ highlights: e.target.value })}
                      rows={4}
                      placeholder={
                        "Structured hypertrophy blocks\nWeekly check-ins & progress photos"
                      }
                      className={areaClass}
                    />
                  </div>

                  {/* Testimonials */}
                  <div>
                    <span className={labelClass}>Testimonials</span>
                    <div className="space-y-3">
                      {form.testimonials.map((t, i) => (
                        <div
                          key={`testimonial-${i}`}
                          className="rounded-2xl border border-border bg-background p-3"
                        >
                          <div className="flex items-start gap-2">
                            <textarea
                              value={t.quote}
                              onChange={(e) => {
                                const next = [...form.testimonials];
                                next[i] = { ...t, quote: e.target.value };
                                update({ testimonials: next });
                              }}
                              rows={2}
                              placeholder="Quote"
                              className={cn(areaClass, "flex-1")}
                            />
                            <button
                              onClick={() =>
                                update({
                                  testimonials: form.testimonials.filter(
                                    (_, j) => j !== i
                                  ),
                                })
                              }
                              className="mt-1 rounded-full p-2 text-muted-foreground hover:bg-secondary hover:text-red-500"
                              aria-label="Remove testimonial"
                            >
                              <Trash2 className="h-4 w-4" />
                            </button>
                          </div>
                          <div className="mt-2 grid gap-2 sm:grid-cols-2">
                            <input
                              value={t.name}
                              onChange={(e) => {
                                const next = [...form.testimonials];
                                next[i] = { ...t, name: e.target.value };
                                update({ testimonials: next });
                              }}
                              placeholder="Client name (e.g. Tyler M.)"
                              className={inputClass}
                            />
                            <input
                              value={t.result}
                              onChange={(e) => {
                                const next = [...form.testimonials];
                                next[i] = { ...t, result: e.target.value };
                                update({ testimonials: next });
                              }}
                              placeholder="Result (e.g. +25 lbs bench · 8 weeks)"
                              className={inputClass}
                            />
                          </div>
                        </div>
                      ))}
                      <Button
                        variant="outline"
                        className="rounded-full text-[13px] font-bold"
                        onClick={() =>
                          update({
                            testimonials: [
                              ...form.testimonials,
                              { quote: "", name: "", result: "" },
                            ],
                          })
                        }
                      >
                        <Plus className="mr-1 h-4 w-4" />
                        Add testimonial
                      </Button>
                    </div>
                  </div>

                  {/* Action buttons — up to 3, each typed (profile, calendar, email, link) */}
                  <div>
                    <div className="mb-1.5 flex items-center justify-between">
                      <span className={labelClass}>
                        Action buttons (up to 3)
                      </span>
                      <span className="text-[11.5px] text-muted-foreground">
                        First button is primary
                      </span>
                    </div>
                    <div className="space-y-3">
                      {form.actionButtons.map((btn, i) => {
                        const typeMeta =
                          ACTION_TYPES.find((t) => t.value === btn.type) ??
                          ACTION_TYPES[0];
                        const needsHref = btn.type === "link" || btn.type === "email";
                        return (
                          <div
                            key={`btn-${i}`}
                            className="rounded-2xl border border-border bg-background p-3"
                          >
                            <div className="flex items-center gap-2">
                              <span
                                className="flex h-7 w-7 shrink-0 items-center justify-center rounded-full bg-secondary text-foreground"
                                aria-hidden
                              >
                                {typeMeta.icon}
                              </span>
                              <input
                                value={btn.label}
                                onChange={(e) =>
                                  updateButton(i, { label: e.target.value })
                                }
                                placeholder={
                                  btn.type === "email"
                                    ? "Email me"
                                    : btn.type === "calendar"
                                      ? "Schedule a call"
                                      : btn.type === "link"
                                        ? "Visit website"
                                        : "Train with …"
                                }
                                className={cn(inputClass, "flex-1")}
                              />
                              <button
                                onClick={() => removeButton(i)}
                                className="rounded-full p-2 text-muted-foreground hover:bg-secondary hover:text-red-500"
                                aria-label="Remove button"
                              >
                                <Trash2 className="h-4 w-4" />
                              </button>
                            </div>
                            <div className="mt-2 flex flex-wrap gap-1.5">
                              {ACTION_TYPES.map((t) => (
                                <button
                                  key={t.value}
                                  onClick={() => updateButton(i, { type: t.value })}
                                  className={cn(
                                    "flex items-center gap-1.5 rounded-full border px-3 py-1.5 text-[12.5px] font-bold",
                                    btn.type === t.value
                                      ? "border-foreground bg-foreground text-background"
                                      : "border-border bg-card text-foreground hover:bg-secondary"
                                  )}
                                >
                                  {t.icon}
                                  {t.label}
                                </button>
                              ))}
                            </div>
                            {needsHref && (
                              <input
                                value={btn.href}
                                onChange={(e) =>
                                  updateButton(i, { href: e.target.value })
                                }
                                placeholder={
                                  btn.type === "email"
                                    ? "name@example.com"
                                    : "https://their-website.com"
                                }
                                className={cn(inputClass, "mt-2")}
                              />
                            )}
                            <p className="mt-2 text-[12px] text-muted-foreground">
                              {typeMeta.hint}
                            </p>
                          </div>
                        );
                      })}
                      {form.actionButtons.length < 3 && (
                        <Button
                          variant="outline"
                          className="rounded-full text-[13px] font-bold"
                          onClick={addButton}
                        >
                          <Plus className="mr-1 h-4 w-4" />
                          Add button
                        </Button>
                      )}
                    </div>
                  </div>

                  <div className="grid gap-4 sm:grid-cols-2">
                    <div>
                      <span className={labelClass}>
                        Legacy button label (fallback only)
                      </span>
                      <input
                        value={form.ctaLabel}
                        onChange={(e) => update({ ctaLabel: e.target.value })}
                        placeholder="Used only if no action buttons are set"
                        className={inputClass}
                      />
                    </div>
                    <div>
                      <span className={labelClass}>
                        Legacy button URL (fallback only)
                      </span>
                      <input
                        value={form.ctaUrl}
                        onChange={(e) => update({ ctaUrl: e.target.value })}
                        placeholder="https://their-website.com"
                        className={inputClass}
                      />
                    </div>
                  </div>

                  <div>
                    <span className={labelClass}>Sort order</span>
                    <input
                      value={form.sortOrder}
                      onChange={(e) => update({ sortOrder: e.target.value })}
                      inputMode="numeric"
                      className={inputClass}
                    />
                  </div>

                  <Button
                    className="h-12 w-full rounded-full text-[14.5px] font-bold"
                    disabled={save.isPending || !form.name.trim()}
                    onClick={() => save.mutate(form)}
                  >
                    {save.isPending ? (
                      <Loader2 className="h-4 w-4 animate-spin" />
                    ) : form.id ? (
                      "Save changes"
                    ) : (
                      "Publish profile"
                    )}
                  </Button>
                </div>

                {/* Live preview */}
                <div className="mt-8">
                  <span className={labelClass}>Live preview</span>
                  <div className="pointer-events-none origin-top-left">
                    <FeaturedProfileCard profile={previewFromForm(form)} />
                  </div>
                </div>
              </section>
            )}

            {/* Existing profiles */}
            <section className="mt-8">
              <h2 className="text-[13px] font-extrabold uppercase tracking-wider text-muted-foreground">
                {KIND_TABS.find((t) => t.kind === tab)?.label} on the site
              </h2>
              {tab === "coach" && !hudsonInDb && !hudsonDismissed && (
                <div className="mt-3 flex items-center gap-3 rounded-[18px] border border-dashed border-border bg-card px-4 py-3">
                  <div className="h-11 w-11 shrink-0 overflow-hidden rounded-xl bg-secondary">
                    <img
                      src={HUDSON_TEMPLATE.photo_url}
                      alt="Hudson"
                      className="h-full w-full object-cover object-top"
                    />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[14.5px] font-bold">
                      Hudson
                      <span className="ml-2 text-[12.5px] font-semibold text-muted-foreground">
                        built-in card
                      </span>
                    </p>
                    <p className="truncate text-[12.5px] text-muted-foreground">
                      Import to link his Whisper account &amp; manage him here
                    </p>
                  </div>
                  <Button
                    variant="outline"
                    className="rounded-full text-[13px] font-bold"
                    onClick={importHudson}
                  >
                    <Pencil className="mr-1.5 h-3.5 w-3.5" />
                    Import &amp; edit
                  </Button>
                </div>
              )}
              {tab === "creator" && !taylorInDb && !taylorDismissed && (
                <div className="mt-3 flex items-center gap-3 rounded-[18px] border border-dashed border-border bg-card px-4 py-3">
                  <div className="h-11 w-11 shrink-0 overflow-hidden rounded-xl bg-secondary">
                    <img
                      src={TAYLOR_BROOKE_TEMPLATE.photo_url}
                      alt="Taylor Brooke"
                      className="h-full w-full object-cover object-top"
                    />
                  </div>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-[14.5px] font-bold">
                      Taylor Brooke
                      <span className="ml-2 text-[12.5px] font-semibold text-muted-foreground">
                        built-in template
                      </span>
                    </p>
                    <p className="truncate text-[12.5px] text-muted-foreground">
                      Import to link her account &amp; manage her spotlight here
                    </p>
                  </div>
                  <Button
                    variant="outline"
                    className="rounded-full text-[13px] font-bold"
                    onClick={importTaylor}
                  >
                    <Pencil className="mr-1.5 h-3.5 w-3.5" />
                    Import &amp; edit
                  </Button>
                </div>
              )}
              {rows.length === 0 ? (
                tab === "coach" && (!hudsonInDb && !hudsonDismissed) ? null : tab === "creator" && (!taylorInDb && !taylorDismissed) ? null : (
                  <div className="mt-3 rounded-[20px] border border-dashed border-border p-8 text-center text-[14px] text-muted-foreground">
                    No featured {tab} profiles yet — create one above.
                  </div>
                )
              ) : (
                <div className="mt-3 space-y-2">
                  {rows.map((p) => (
                    <div
                      key={p.id}
                      className="flex items-center gap-3 rounded-[18px] border border-border bg-card px-4 py-3"
                    >
                      <div className="h-11 w-11 shrink-0 overflow-hidden rounded-xl bg-secondary">
                        {p.photo_url && (
                          <img
                            src={p.photo_url}
                            alt={p.name}
                            className="h-full w-full object-cover object-top"
                          />
                        )}
                      </div>
                      <div className="min-w-0 flex-1">
                        <p className="truncate text-[14.5px] font-bold">
                          {p.name}
                          {p.username && (
                            <span className="ml-2 text-[12.5px] font-semibold text-muted-foreground">
                              @{p.username}
                            </span>
                          )}
                        </p>
                        <p className="truncate text-[12.5px] text-muted-foreground">
                          {[
                            p.tier ? `Tier ${p.tier}` : null,
                            p.discipline,
                            p.published ? "Published" : "Hidden",
                          ]
                            .filter(Boolean)
                            .join(" · ")}
                        </p>
                      </div>
                      <button
                        onClick={() => togglePublish.mutate(p)}
                        disabled={togglePublish.isPending}
                        className="rounded-full p-2 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                        aria-label={p.published ? "Hide" : "Publish"}
                        title={p.published ? "Hide from site" : "Publish"}
                      >
                        {p.published ? (
                          <Eye className="h-4 w-4" />
                        ) : (
                          <EyeOff className="h-4 w-4" />
                        )}
                      </button>
                      <button
                        onClick={() => {
                          setForm(formFromProfile(p));
                          window.scrollTo({ top: 0, behavior: "smooth" });
                        }}
                        className="rounded-full p-2 text-muted-foreground transition-colors hover:bg-accent hover:text-foreground"
                        aria-label={`Edit ${p.name}`}
                      >
                        <Pencil className="h-4 w-4" />
                      </button>
                      <button
                        onClick={() => {
                          if (window.confirm(`Remove ${p.name} from the site?`)) {
                            remove.mutate(p);
                          }
                        }}
                        disabled={remove.isPending}
                        className="rounded-full p-2 text-muted-foreground transition-colors hover:bg-accent hover:text-red-500"
                        aria-label={`Delete ${p.name}`}
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
