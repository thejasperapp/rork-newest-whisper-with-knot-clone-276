import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  Camera,
  Check,
  Loader2,
  X,
  Heart,
  ShieldCheck,
  Users,
  Eye,
  Lock,
  Flag,
  ExternalLink,
  Link2,
} from "lucide-react";

import { Avatar } from "@/components/Avatar";
import { AvatarCropDialog } from "@/components/AvatarCropDialog";
import { WhisperLogo } from "@/components/WhisperLogo";
import {
  upsertProfile,
  uploadMedia,
  updateInterests,
  fetchSuggestions,
  toggleFollow,
} from "@/lib/api";
import { COMMUNITIES, DATING_COMMUNITY, type Community } from "@/lib/communities";
import { fetchJasperLinkStatus, redeemJasperLinkCode } from "@/lib/jasperLink";
import { supabase } from "@/lib/supabase";
import { useAuth } from "@/hooks/useAuth";
import { clearPendingAccountType, readPendingAccountType } from "@/lib/accountTypes";
import type { WhisperFollowUser } from "@/lib/types";
import { cn } from "@/lib/utils";

/**
 * Whisper onboarding — the Instagram / Threads flow, one decision per screen:
 *
 *   0. Profile      — photo, username (required), name, bio
 *   1. Communities  — join real communities from the catalog (Dating featured)
 *   2. People       — follow suggested accounts
 *   3. Jasper       — optional: link the Jasper account with a one-time code
 *   4. Guidelines   — how Whisper works + agree to the Terms
 *
 * Every step persists to the same Supabase tables iOS writes to. Community
 * picks are stored as interests (community names) — the membership signal
 * both apps read.
 */

const STEP_COUNT = 5;
const JASPER_APP_STORE_URL = "https://apps.apple.com/us/app/jasper-fitness-made-easy/id6753958717";

/** Community groups shown in onboarding — ordered by id, sections in display order. */
const COMMUNITY_SECTIONS: { title: string; ids: string[] }[] = [
  {
    title: "Fitness & wellness",
    ids: ["workouts", "running", "lifting", "yoga", "cycling", "swimming", "nutrition", "sleep", "mindset", "mindfulness", "outdoors"],
  },
  {
    title: "Culture & interests",
    ids: ["coffee", "books", "music", "movies", "gaming", "sports"],
  },
];

type UsernameStatus = "idle" | "checking" | "available" | "taken" | "invalid";

interface OnboardingFlowProps {
  nextPath: string;
}

export function OnboardingFlow({ nextPath }: OnboardingFlowProps) {
  const { user, refreshProfile } = useAuth();
  const [step, setStep] = useState<number>(0);
  const [direction, setDirection] = useState<"forward" | "back">("forward");
  const [busy, setBusy] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // Step 0 — profile
  const [username, setUsername] = useState<string>("");
  const [displayName, setDisplayName] = useState<string>("");
  const [bio, setBio] = useState<string>("");
  const [avatarUrl, setAvatarUrl] = useState<string | null>(null);
  const [cropFile, setCropFile] = useState<File | null>(null);
  const [uploading, setUploading] = useState<boolean>(false);
  const fileRef = useRef<HTMLInputElement>(null);

  // Step 1 — communities (ids)
  const [selectedCommunities, setSelectedCommunities] = useState<Set<string>>(new Set());

  // Step 2 — follows
  const [selectedFollows, setSelectedFollows] = useState<Set<string>>(new Set());

  // Step 3 — Jasper
  const [jasperLinked, setJasperLinked] = useState<boolean>(false);

  useEffect(() => {
    const meta = user?.user_metadata as { full_name?: string; name?: string } | undefined;
    const seed = meta?.full_name ?? meta?.name ?? "";
    if (seed && !displayName) setDisplayName(seed);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [user?.id]);

  const normalizedHandle = useMemo(
    () => username.trim().replace(/^@/, "").toLowerCase(),
    [username]
  );
  const usernameValid = /^[a-z0-9_.]{3,20}$/.test(normalizedHandle);
  const availability = useQuery({
    queryKey: ["onboarding-username-check", normalizedHandle],
    queryFn: async (): Promise<"available" | "taken" | "self"> => {
      if (!normalizedHandle) return "available";
      const { data } = await supabase
        .from("whisper_profiles")
        .select("user_id")
        .ilike("username", normalizedHandle)
        .limit(1)
        .maybeSingle();
      if (!data) return "available";
      if (user && (data as { user_id: string }).user_id === user.id) return "self";
      return "taken";
    },
    enabled: usernameValid && normalizedHandle.length > 0,
    staleTime: 30_000,
  });
  const usernameStatus: UsernameStatus = !normalizedHandle
    ? "idle"
    : !usernameValid
      ? "invalid"
      : availability.isLoading
        ? "checking"
        : availability.data === "available" || availability.data === "self"
          ? "available"
          : availability.data === "taken"
            ? "taken"
            : "idle";

  const suggestions = useQuery({
    queryKey: ["onboarding-suggestions", user?.id],
    queryFn: () => fetchSuggestions(user!.id, 18),
    enabled: !!user && step >= 1,
    staleTime: 60_000,
  });

  const canAdvance =
    step === 0 ? usernameValid && usernameStatus === "available" : true;

  const go = (next: number): void => {
    setDirection(next > step ? "forward" : "back");
    setStep(next);
    window.scrollTo({ top: 0 });
  };

  const handlePick = (e: React.ChangeEvent<HTMLInputElement>): void => {
    const file = e.target.files?.[0];
    e.target.value = "";
    if (!file) return;
    setCropFile(file);
  };

  const handleCropped = async (blob: Blob): Promise<void> => {
    if (!user) return;
    setUploading(true);
    setError(null);
    try {
      const file = new File([blob], "avatar.jpg", { type: "image/jpeg" });
      const url = await uploadMedia(file, user.id);
      setAvatarUrl(url);
      setCropFile(null);
    } catch {
      setError("Couldn't upload that photo. Try another.");
    } finally {
      setUploading(false);
    }
  };

  const complete = (): void => {
    window.dispatchEvent(new CustomEvent("whisper-onboarding-complete", { detail: { nextPath } }));
  };

  const advance = async (): Promise<void> => {
    setError(null);
    if (!user) return;
    if (step === 0) {
      setBusy(true);
      try {
        const pendingType = readPendingAccountType();
        await upsertProfile({
          userId: user.id,
          username: normalizedHandle,
          displayName: displayName.trim() || normalizedHandle,
          bio: bio.trim(),
          profileImageUrl: avatarUrl,
          accountType: pendingType?.accountType,
          professionalCategory: pendingType?.category,
        });
        clearPendingAccountType();
        await refreshProfile();
      } catch (err) {
        setError(err instanceof Error ? err.message : "Couldn't save your profile.");
        setBusy(false);
        return;
      }
      setBusy(false);
      go(1);
      return;
    }
    if (step === 1) {
      if (selectedCommunities.size > 0) {
        setBusy(true);
        try {
          const names = COMMUNITIES.filter((c) => selectedCommunities.has(c.id)).map((c) => c.name);
          await updateInterests(user.id, names);
        } catch {
          // Non-fatal — communities can be joined later from the tab.
        }
        setBusy(false);
      }
      go(2);
      return;
    }
    if (step === 2) {
      if (selectedFollows.size > 0) {
        setBusy(true);
        const rows = suggestions.data ?? [];
        await Promise.all(
          Array.from(selectedFollows).map((uid) => {
            const row = rows.find((r) => r.userId === uid);
            if (!row) return Promise.resolve();
            return toggleFollow(user.id, uid, row.username, false).catch(() => undefined);
          })
        );
        setBusy(false);
      }
      go(3);
      return;
    }
    if (step === 3) {
      go(4);
      return;
    }
    if (step === 4) {
      setBusy(true);
      try {
        await refreshProfile();
      } finally {
        setBusy(false);
      }
      complete();
    }
  };

  const primaryLabel = (): string => {
    if (busy) return "Saving…";
    if (step === 1) return selectedCommunities.size > 0 ? `Join ${selectedCommunities.size} & continue` : "Continue";
    if (step === 2) return selectedFollows.size > 0 ? `Follow ${selectedFollows.size} & continue` : "Continue";
    if (step === 3) return jasperLinked ? "Continue" : "Continue without Jasper";
    if (step === 4) return "Agree and continue";
    return "Next";
  };

  const skippable = step === 1 || step === 2 || step === 3;

  return (
    <div className="relative flex min-h-screen flex-col bg-background">
      {/* Top bar — back, wordmark, skip; progress underneath */}
      <div className="sticky top-0 z-20 border-b border-border/40 bg-background/90 backdrop-blur-md">
        <div className="mx-auto flex h-14 w-full max-w-md items-center justify-between px-3">
          <div className="w-16">
            {step > 0 && (
              <button
                type="button"
                onClick={() => go(step - 1)}
                className="flex h-10 w-10 items-center justify-center rounded-full transition-colors hover:bg-secondary"
                aria-label="Go back"
              >
                <ArrowLeft className="h-5 w-5" />
              </button>
            )}
          </div>
          <WhisperLogo variant="wordmark" size={30} />
          <div className="flex w-16 justify-end">
            {skippable && (
              <button
                type="button"
                onClick={() => go(step + 1)}
                className="rounded-full px-3 py-1.5 text-sm font-semibold text-muted-foreground transition-colors hover:bg-secondary"
              >
                Skip
              </button>
            )}
          </div>
        </div>
        <div className="mx-auto flex h-1 w-full max-w-md gap-1 px-4 pb-3">
          {Array.from({ length: STEP_COUNT }, (_, i) => (
            <div
              key={i}
              className={cn(
                "h-1 flex-1 rounded-full transition-all duration-500 ease-out",
                i <= step ? "bg-foreground" : "bg-secondary"
              )}
            />
          ))}
        </div>
      </div>

      <div className="relative mx-auto flex w-full max-w-md flex-1 flex-col px-5 pt-6 pb-32">
        {error && (
          <p className="mb-4 rounded-xl bg-destructive/15 px-3 py-2 text-sm text-destructive">{error}</p>
        )}

        <div
          key={step}
          className={cn("flex-1", direction === "forward" ? "animate-rise" : "animate-rise")}
        >
          {step === 0 && (
            <StepProfile
              username={username}
              setUsername={setUsername}
              displayName={displayName}
              setDisplayName={setDisplayName}
              bio={bio}
              setBio={setBio}
              avatarUrl={avatarUrl}
              fileRef={fileRef}
              onPick={handlePick}
              usernameStatus={usernameStatus}
              uploading={uploading}
            />
          )}
          {step === 1 && (
            <StepCommunities
              selected={selectedCommunities}
              toggle={(id) =>
                setSelectedCommunities((prev) => {
                  const next = new Set(prev);
                  if (next.has(id)) next.delete(id);
                  else next.add(id);
                  return next;
                })
              }
            />
          )}
          {step === 2 && (
            <StepPeople
              suggestions={suggestions.data ?? []}
              loading={suggestions.isLoading}
              selected={selectedFollows}
              toggle={(uid) =>
                setSelectedFollows((prev) => {
                  const next = new Set(prev);
                  if (next.has(uid)) next.delete(uid);
                  else next.add(uid);
                  return next;
                })
              }
              onFollowAll={() =>
                setSelectedFollows(new Set((suggestions.data ?? []).slice(0, 12).map((p) => p.userId)))
              }
            />
          )}
          {step === 3 && <StepJasper linked={jasperLinked} onLinked={() => setJasperLinked(true)} />}
          {step === 4 && <StepGuidelines />}
        </div>
      </div>

      {/* Primary action — one full-width button, Instagram grammar */}
      <div className="fixed inset-x-0 bottom-0 z-20 border-t border-border/40 bg-background/95 backdrop-blur-md">
        <div className="mx-auto w-full max-w-md px-5 pt-3 pb-[max(1rem,env(safe-area-inset-bottom))]">
          {step === 4 && (
            <p className="mb-2 text-center text-[11px] leading-relaxed text-muted-foreground">
              By continuing you agree to Whisper's{" "}
              <a href="/terms" target="_blank" rel="noreferrer" className="font-semibold text-foreground underline-offset-2 hover:underline">Terms</a>
              {" "}and{" "}
              <a href="/privacy" target="_blank" rel="noreferrer" className="font-semibold text-foreground underline-offset-2 hover:underline">Privacy Policy</a>
              {" "}and confirm you'll follow the community guidelines above.
            </p>
          )}
          <button
            type="button"
            onClick={() => void advance()}
            disabled={!canAdvance || busy}
            className="flex h-12 w-full items-center justify-center gap-2 rounded-xl bg-primary text-[15px] font-bold text-primary-foreground transition-transform active:scale-[0.98] disabled:opacity-40"
          >
            {busy && <Loader2 className="h-4 w-4 animate-spin" />}
            {primaryLabel()}
          </button>
        </div>
      </div>

      <AvatarCropDialog
        file={cropFile}
        busy={uploading}
        onCancel={() => setCropFile(null)}
        onCropped={(blob) => void handleCropped(blob)}
      />
    </div>
  );
}

// ---------------------------------------------------------------------------
// Shared header
// ---------------------------------------------------------------------------

function StepHeader({ title, subtitle }: { title: string; subtitle: string }) {
  return (
    <div className="mb-6">
      <h1 className="font-display text-[26px] font-extrabold leading-tight tracking-tight">{title}</h1>
      <p className="mt-2 text-[15px] leading-relaxed text-muted-foreground">{subtitle}</p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Step 0 — Profile
// ---------------------------------------------------------------------------

function StepProfile({
  username,
  setUsername,
  displayName,
  setDisplayName,
  bio,
  setBio,
  avatarUrl,
  fileRef,
  onPick,
  usernameStatus,
  uploading,
}: {
  username: string;
  setUsername: (v: string) => void;
  displayName: string;
  setDisplayName: (v: string) => void;
  bio: string;
  setBio: (v: string) => void;
  avatarUrl: string | null;
  fileRef: React.RefObject<HTMLInputElement | null>;
  onPick: (e: React.ChangeEvent<HTMLInputElement>) => void;
  usernameStatus: UsernameStatus;
  uploading: boolean;
}) {
  return (
    <div>
      <StepHeader title="Create your profile" subtitle="This is how people will find and recognize you on Whisper." />

      <div className="mb-7 flex flex-col items-center gap-3">
        <button
          type="button"
          onClick={() => fileRef.current?.click()}
          className="relative"
          disabled={uploading}
          aria-label="Add profile photo"
        >
          <Avatar url={avatarUrl} name={displayName || username || "you"} size={104} />
          <span className="absolute -bottom-0.5 -right-0.5 flex h-9 w-9 items-center justify-center rounded-full border-[3px] border-background bg-primary text-primary-foreground">
            {uploading ? <Loader2 className="h-4 w-4 animate-spin" /> : <Camera className="h-4 w-4" />}
          </span>
        </button>
        <input ref={fileRef} type="file" accept="image/*" className="hidden" onChange={onPick} />
        <button
          type="button"
          onClick={() => fileRef.current?.click()}
          className="text-sm font-semibold text-foreground"
        >
          {avatarUrl ? "Change photo" : "Add a photo"}
        </button>
      </div>

      <div className="space-y-4">
        <Field label="Username" hint={
          usernameStatus === "taken"
            ? "That username is taken."
            : usernameStatus === "invalid"
              ? "3–20 characters: lowercase letters, numbers, _ and ."
              : usernameStatus === "available"
                ? `@${username} is available`
                : "Lowercase letters, numbers, _ and . — 3 to 20 characters."
        } hintTone={usernameStatus === "taken" || usernameStatus === "invalid" ? "error" : usernameStatus === "available" ? "ok" : "muted"}>
          <div className="relative">
            <span className="pointer-events-none absolute left-4 top-1/2 -translate-y-1/2 text-muted-foreground">@</span>
            <input
              value={username}
              onChange={(e) => setUsername(e.target.value.replace(/^@+/, "").toLowerCase().replace(/\s+/g, "_"))}
              placeholder="username"
              autoComplete="username"
              autoCapitalize="none"
              maxLength={20}
              className="h-12 w-full rounded-xl border border-border bg-card pl-8 pr-10 text-[15px] outline-none ring-primary/40 focus:ring-2"
            />
            <span className="absolute right-4 top-1/2 -translate-y-1/2">
              {usernameStatus === "checking" && <Loader2 className="h-4 w-4 animate-spin text-muted-foreground" />}
              {usernameStatus === "available" && <Check className="h-4 w-4 text-emerald-500" />}
              {(usernameStatus === "taken" || usernameStatus === "invalid") && <X className="h-4 w-4 text-destructive" />}
            </span>
          </div>
        </Field>

        <Field label="Name">
          <input
            value={displayName}
            onChange={(e) => setDisplayName(e.target.value)}
            placeholder="Your name"
            autoComplete="name"
            maxLength={50}
            className="h-12 w-full rounded-xl border border-border bg-card px-4 text-[15px] outline-none ring-primary/40 focus:ring-2"
          />
        </Field>

        <Field label="Bio" hint={`${bio.length}/150 · optional`}>
          <textarea
            value={bio}
            onChange={(e) => setBio(e.target.value.slice(0, 150))}
            placeholder="A line about you"
            rows={3}
            maxLength={150}
            className="w-full resize-none rounded-xl border border-border bg-card px-4 py-3 text-[15px] outline-none ring-primary/40 focus:ring-2"
          />
        </Field>
      </div>
    </div>
  );
}

function Field({
  label,
  hint,
  hintTone = "muted",
  children,
}: {
  label: string;
  hint?: string;
  hintTone?: "muted" | "error" | "ok";
  children: React.ReactNode;
}) {
  return (
    <div>
      <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">{label}</label>
      {children}
      {hint && (
        <p
          className={cn(
            "mt-1.5 text-xs",
            hintTone === "error" ? "text-destructive" : hintTone === "ok" ? "text-emerald-600" : "text-muted-foreground"
          )}
        >
          {hint}
        </p>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Step 1 — Communities (the real catalog, Dating featured)
// ---------------------------------------------------------------------------

function StepCommunities({ selected, toggle }: { selected: Set<string>; toggle: (id: string) => void }) {
  const catalog = COMMUNITIES.filter((c) => !c.requiresJasperLink && c.id !== DATING_COMMUNITY.id);
  const placed = new Set<string>();
  const sections = COMMUNITY_SECTIONS.map((section) => {
    const items = section.ids
      .map((id) => catalog.find((c) => c.id === id))
      .filter((c): c is Community => !!c);
    items.forEach((c) => placed.add(c.id));
    return { title: section.title, items };
  }).filter((s) => s.items.length > 0);
  const rest = catalog.filter((c) => !placed.has(c.id));
  if (rest.length > 0) sections.push({ title: "More", items: rest });

  const datingOn = selected.has(DATING_COMMUNITY.id);

  return (
    <div>
      <StepHeader
        title="Join your communities"
        subtitle="Each community has its own feed. Pick what you're into — your home feed starts here."
      />

      {/* Featured — Whisper Dating */}
      <button
        type="button"
        onClick={() => toggle(DATING_COMMUNITY.id)}
        className={cn(
          "relative mb-6 w-full overflow-hidden rounded-2xl border p-4 text-left transition-all active:scale-[0.99]",
          datingOn ? "border-[#E8467C]" : "border-border"
        )}
        style={{
          background: "linear-gradient(135deg, rgba(232,70,124,0.10), rgba(255,158,184,0.10))",
        }}
      >
        <div className="flex items-start gap-3">
          <span
            className="flex h-12 w-12 shrink-0 items-center justify-center rounded-2xl text-white"
            style={{ background: "linear-gradient(135deg, #E8467C, #FF9EB8)" }}
          >
            <Heart className="h-6 w-6" fill="currentColor" />
          </span>
          <div className="min-w-0 flex-1">
            <div className="flex items-center gap-2">
              <p className="text-[15px] font-bold">Whisper Dating</p>
              <span className="rounded-full bg-[#E8467C]/15 px-2 py-0.5 text-[10px] font-bold text-[#C73352]">18+</span>
            </div>
            <p className="mt-0.5 text-[13px] leading-snug text-muted-foreground">
              Blind video dates, an icebreaker every hour, and real people near you. Private by default — you decide what's shared.
            </p>
          </div>
          <span
            className={cn(
              "mt-1 flex h-7 w-7 shrink-0 items-center justify-center rounded-full border transition-colors",
              datingOn ? "border-[#E8467C] bg-[#E8467C] text-white" : "border-border bg-background text-transparent"
            )}
          >
            <Check className="h-4 w-4" />
          </span>
        </div>
      </button>

      {sections.map((section) => (
        <div key={section.title} className="mb-6">
          <p className="mb-2.5 text-xs font-bold uppercase tracking-wider text-muted-foreground">{section.title}</p>
          <div className="grid grid-cols-2 gap-2.5">
            {section.items.map((community) => {
              const active = selected.has(community.id);
              const Icon = community.icon;
              return (
                <button
                  key={community.id}
                  type="button"
                  onClick={() => toggle(community.id)}
                  className={cn(
                    "flex items-center gap-3 rounded-2xl border bg-card p-3 text-left transition-all active:scale-[0.98]",
                    active ? "border-foreground" : "border-border hover:bg-secondary/50"
                  )}
                >
                  <span
                    className="flex h-10 w-10 shrink-0 items-center justify-center rounded-xl text-white"
                    style={{ background: `linear-gradient(135deg, ${community.gradient[0]}, ${community.gradient[1]})` }}
                  >
                    <Icon className="h-5 w-5" />
                  </span>
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-bold">{community.name}</p>
                    <p className="truncate text-[11px] text-muted-foreground">{community.tagline}</p>
                  </div>
                  <span
                    className={cn(
                      "flex h-6 w-6 shrink-0 items-center justify-center rounded-full border transition-colors",
                      active ? "border-foreground bg-foreground text-background" : "border-border text-transparent"
                    )}
                  >
                    <Check className="h-3.5 w-3.5" />
                  </span>
                </button>
              );
            })}
          </div>
        </div>
      ))}

      <p className="text-center text-xs text-muted-foreground">
        {selected.size > 0 ? `${selected.size} selected · ` : ""}Join or leave any community later from the Communities tab.
      </p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Step 2 — People
// ---------------------------------------------------------------------------

function StepPeople({
  suggestions,
  loading,
  selected,
  toggle,
  onFollowAll,
}: {
  suggestions: WhisperFollowUser[];
  loading: boolean;
  selected: Set<string>;
  toggle: (uid: string) => void;
  onFollowAll: () => void;
}) {
  const rows = suggestions.slice(0, 12);
  return (
    <div>
      <StepHeader title="Follow people" subtitle="Your feed is built from who you follow. Here are some accounts to start with." />

      {loading ? (
        <div className="flex justify-center py-12">
          <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
        </div>
      ) : rows.length === 0 ? (
        <div className="rounded-2xl border border-border bg-card px-4 py-10 text-center">
          <Users className="mx-auto h-6 w-6 text-muted-foreground" />
          <p className="mt-3 text-sm font-semibold">No suggestions yet</p>
          <p className="mt-1 text-sm text-muted-foreground">You can find people from Search once the community grows.</p>
        </div>
      ) : (
        <>
          <div className="mb-3 flex items-center justify-between">
            <p className="text-xs font-bold uppercase tracking-wider text-muted-foreground">Suggested for you</p>
            <button type="button" onClick={onFollowAll} className="text-sm font-semibold text-foreground">
              Follow all
            </button>
          </div>
          <div className="overflow-hidden rounded-2xl border border-border bg-card">
            {rows.map((person, index) => {
              const active = selected.has(person.userId);
              const name = person.profile?.display_name || person.username;
              return (
                <div
                  key={person.userId}
                  className={cn("flex items-center gap-3 px-3 py-2.5", index > 0 && "border-t border-border")}
                >
                  <Avatar url={person.profile?.profile_image_url ?? null} name={name} size={44} />
                  <div className="min-w-0 flex-1">
                    <p className="truncate text-sm font-bold">{name}</p>
                    <p className="truncate text-xs text-muted-foreground">
                      @{person.username}
                      {person.profile?.bio ? ` · ${person.profile.bio}` : ""}
                    </p>
                  </div>
                  <button
                    type="button"
                    onClick={() => toggle(person.userId)}
                    className={cn(
                      "h-8 shrink-0 rounded-lg px-4 text-xs font-bold transition-colors",
                      active ? "border border-border bg-background text-foreground" : "bg-primary text-primary-foreground"
                    )}
                  >
                    {active ? "Following" : "Follow"}
                  </button>
                </div>
              );
            })}
          </div>
        </>
      )}
    </div>
  );
}

// ---------------------------------------------------------------------------
// Step 3 — Link Jasper (one-time code — the web path)
// ---------------------------------------------------------------------------

function StepJasper({ linked, onLinked }: { linked: boolean; onLinked: () => void }) {
  const { user } = useAuth();
  const queryClient = useQueryClient();
  const [code, setCode] = useState<string>("");
  const [message, setMessage] = useState<string | null>(null);

  const status = useQuery({
    queryKey: ["jasper-link", user?.id],
    queryFn: () => fetchJasperLinkStatus(user!.id),
    enabled: !!user?.id,
    staleTime: 10_000,
  });

  useEffect(() => {
    if (status.data?.isLinked && !linked) onLinked();
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status.data?.isLinked]);

  const redeem = useMutation({
    mutationFn: () => redeemJasperLinkCode(code),
    onSuccess: (result) => {
      if (result.ok) {
        setMessage(null);
        setCode("");
        void queryClient.invalidateQueries({ queryKey: ["jasper-link", user?.id] });
        onLinked();
      } else if (result.error === "cannot link an account to itself") {
        setMessage("That code belongs to this same account — sign into a different Jasper account to link it.");
      } else if (result.error === "not authenticated") {
        setMessage("Your session expired — sign in again to link Jasper.");
      } else {
        setMessage("That code is invalid or has expired. Codes last 10 minutes — grab a fresh one in Jasper.");
      }
    },
    onError: () => setMessage("Couldn't reach Jasper — check your connection and try again."),
  });

  const canRedeem = code.trim().length >= 6 && !redeem.isPending;

  return (
    <div>
      <StepHeader
        title="Link Jasper"
        subtitle="Jasper is the AI fitness app Whisper partners with. Link your account and Jasper answers with your real workouts, meals, and sleep."
      />

      <div className="overflow-hidden rounded-2xl border border-border bg-card">
        <div className="flex items-start gap-3 border-b border-border p-4">
          <img src="/jasper-ghost.png" alt="" className="h-12 w-12 shrink-0 rounded-2xl object-cover" />
          <div className="min-w-0 flex-1">
            <p className="text-[15px] font-bold">{linked ? "Jasper is linked" : "What you get"}</p>
            <ul className="mt-1.5 space-y-1 text-[13px] leading-snug text-muted-foreground">
              <li>Jasper answers with your real training, nutrition, and readiness.</li>
              <li>Coaches you hire see only what you choose to share.</li>
              <li>Unlocks the Jasper Circle community.</li>
            </ul>
          </div>
        </div>

        {!linked && status.isPending ? <p role="status" className="p-4 text-sm text-muted-foreground">Checking your saved Jasper link…</p> : !linked && status.isError ? <div role="alert" className="p-4 text-sm text-muted-foreground">Your account link couldn’t be checked. Nothing has been disconnected. <button type="button" className="underline" onClick={() => void status.refetch()}>Retry</button></div> : linked ? (
          <div className="flex items-center gap-3 p-4">
            <span className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-emerald-500/12 text-emerald-500">
              <Check className="h-5 w-5" />
            </span>
            <div>
              <p className="text-sm font-bold">Connected</p>
              <p className="text-xs text-muted-foreground">Your Jasper data now flows into Whisper. Manage it anytime in Settings → Jasper.</p>
            </div>
          </div>
        ) : (
          <div className="p-4">
            <ol className="mb-3 space-y-1.5 text-[13px] text-muted-foreground">
              <li className="flex gap-2"><span className="font-bold text-foreground">1.</span> Open the Jasper app → Settings → Connect to Whisper.</li>
              <li className="flex gap-2"><span className="font-bold text-foreground">2.</span> Copy the 8-character code it shows you.</li>
              <li className="flex gap-2"><span className="font-bold text-foreground">3.</span> Paste it here.</li>
            </ol>
            <div className="flex gap-2">
              <input
                value={code}
                onChange={(e) => setCode(e.target.value.toUpperCase())}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && canRedeem) {
                    e.preventDefault();
                    redeem.mutate();
                  }
                }}
                placeholder="8-character code"
                autoCapitalize="characters"
                autoCorrect="off"
                spellCheck={false}
                maxLength={12}
                className="h-11 min-w-0 flex-1 rounded-xl border border-border bg-background px-3.5 text-sm font-semibold uppercase tracking-[0.2em] outline-none placeholder:tracking-normal placeholder:normal-case focus:border-foreground/40"
              />
              <button
                type="button"
                onClick={() => redeem.mutate()}
                disabled={!canRedeem}
                className="flex h-11 items-center gap-1.5 rounded-xl bg-primary px-4 text-sm font-bold text-primary-foreground transition-transform active:scale-95 disabled:opacity-50"
              >
                {redeem.isPending ? <Loader2 className="h-4 w-4 animate-spin" /> : <Link2 className="h-4 w-4" />}
                Link
              </button>
            </div>
            {message && <p className="mt-2 text-xs text-destructive">{message}</p>}
            <a
              href={JASPER_APP_STORE_URL}
              target="_blank"
              rel="noreferrer"
              className="mt-4 inline-flex items-center gap-1.5 text-xs font-semibold text-foreground"
            >
              Don't have Jasper? Get it on the App Store <ExternalLink className="h-3 w-3" />
            </a>
          </div>
        )}
      </div>

      <p className="mt-4 text-center text-xs text-muted-foreground">Optional — you can link Jasper later from Settings.</p>
    </div>
  );
}

// ---------------------------------------------------------------------------
// Step 4 — Community guidelines (Threads' "How it works" screen)
// ---------------------------------------------------------------------------

const GUIDELINES: { icon: typeof Users; title: string; body: string }[] = [
  {
    icon: Users,
    title: "Real people, real names",
    body: "One account per person. Be who you say you are — impersonation and fake accounts are removed.",
  },
  {
    icon: ShieldCheck,
    title: "Zero tolerance",
    body: "No hate, harassment, sexual content, violence, or anything that endangers minors. Accounts that cross these lines are removed without warning.",
  },
  {
    icon: Eye,
    title: "You control what people see",
    body: "Switch to a private account, block or mute anyone, and choose what Jasper data your coaches can see.",
  },
  {
    icon: Flag,
    title: "Report anything, right here",
    body: "Every post, message, profile, and live room has a report option. Reports are reviewed by a real person.",
  },
  {
    icon: Lock,
    title: "Your data stays yours",
    body: "Health data linked from Jasper is never sold or shown publicly. Dating preferences and location are shared only as a rounded distance.",
  },
];

function StepGuidelines() {
  return (
    <div>
      <StepHeader title="How Whisper works" subtitle="A few things everyone agrees to before joining." />
      <div className="space-y-5">
        {GUIDELINES.map((item) => {
          const Icon = item.icon;
          return (
            <div key={item.title} className="flex items-start gap-4">
              <span className="mt-0.5 flex h-10 w-10 shrink-0 items-center justify-center rounded-full bg-secondary text-foreground">
                <Icon className="h-5 w-5" />
              </span>
              <div>
                <p className="text-[15px] font-bold">{item.title}</p>
                <p className="mt-0.5 text-[13.5px] leading-relaxed text-muted-foreground">{item.body}</p>
              </div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

export default OnboardingFlow;
