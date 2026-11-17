import { useState, useEffect, useMemo } from "react";
import { Link, useNavigate, useSearchParams } from "react-router-dom";
import { Heart, MessageCircle, Send, Bookmark, MoreHorizontal, BadgeCheck, User, Sparkles, Briefcase, ChevronLeft } from "lucide-react";

import { supabase } from "@/lib/supabase";
import { BACKEND_URL, resolveBackend } from "@/lib/billing";
import {
  isAddingAccount,
  returnToLastAccount,
  takeReauthEmail,
  useSwitchableAccounts,
} from "@/lib/accountSwitcher";
import {
  clearPendingAccountType,
  stashPendingAccountType,
  type AccountType,
} from "@/lib/accountTypes";
import { WhisperLogo } from "@/components/WhisperLogo";
import { CircleZoomTransition } from "@/components/CircleZoomTransition";

/* ------------------------------------------------------------------ */
/*  Simulated backdrop posts — no real user content on the login page. */
/*  Realistic fake usernames, profile pictures, and a mix of text +    */
/*  image posts that gently auto-scroll and auto-like behind the form. */
/* ------------------------------------------------------------------ */

interface SimPost {
  id: string;
  username: string;
  displayName: string;
  verified: boolean;
  avatar: string;
  caption: string;
  image: string | null;
  likes: number;
  comments: number;
  time: string;
}

const SIM_POSTS: SimPost[] = [
  { id: "s1", username: "maya.runs", displayName: "Maya Chen", verified: true, avatar: "https://i.pravatar.cc/96?img=47", caption: "morning runs hit different when the city is still asleep 🌆", image: "https://picsum.photos/seed/whisper-run/640/480", likes: 142, comments: 8, time: "2h" },
  { id: "s2", username: "devon.films", displayName: "Devon Park", verified: true, avatar: "https://i.pravatar.cc/96?img=12", caption: "just wrapped my first short film. can't believe this is real 🎬", image: null, likes: 389, comments: 24, time: "4h" },
  { id: "s3", username: "aria_lifts", displayName: "Aria Torres", verified: false, avatar: "https://i.pravatar.cc/96?img=32", caption: "training day 47. the grind doesn't stop 💪", image: "https://picsum.photos/seed/whisper-gym/640/480", likes: 67, comments: 3, time: "5h" },
  { id: "s4", username: "coach.eli", displayName: "Eli Brooks", verified: true, avatar: "https://i.pravatar.cc/96?img=56", caption: "three of my athletes hit PRs this week. proud coach moment 🏆", image: null, likes: 218, comments: 19, time: "6h" },
  { id: "s5", username: "nina.creates", displayName: "Nina Okafor", verified: false, avatar: "https://i.pravatar.cc/96?img=5", caption: "golden hour never misses ✨", image: "https://picsum.photos/seed/whisper-golden/640/480", likes: 501, comments: 32, time: "8h" },
  { id: "s6", username: "jax_hoops", displayName: "Jax Rivera", verified: false, avatar: "https://i.pravatar.cc/96?img=68", caption: "5am shootaround. nobody watching, everybody wondering", image: "https://picsum.photos/seed/whisper-court/640/480", likes: 93, comments: 6, time: "9h" },
  { id: "s7", username: "sofia.eats", displayName: "Sofia Marino", verified: false, avatar: "https://i.pravatar.cc/96?img=25", caption: "meal prep sunday — 12 meals, 2 hours, zero excuses 🥗", image: "https://picsum.photos/seed/whisper-meal/640/480", likes: 156, comments: 11, time: "11h" },
  { id: "s8", username: "theo.writes", displayName: "Theo Nakamura", verified: true, avatar: "https://i.pravatar.cc/96?img=15", caption: "new article drops friday. this one's personal.", image: null, likes: 274, comments: 41, time: "12h" },
  { id: "s9", username: "lena.tracks", displayName: "Lena Hoffmann", verified: false, avatar: "https://i.pravatar.cc/96?img=44", caption: "first sub-20 5k!! two years in the making 🏃‍♀️", image: "https://picsum.photos/seed/whisper-track/640/480", likes: 448, comments: 57, time: "14h" },
  { id: "s10", username: "marcus.talks", displayName: "Marcus Reid", verified: true, avatar: "https://i.pravatar.cc/96?img=60", caption: "went live with 3 friends last night — group lives are a game changer 🔴", image: null, likes: 312, comments: 28, time: "16h" },
  { id: "s11", username: "ivy.climbs", displayName: "Ivy Laurent", verified: false, avatar: "https://i.pravatar.cc/96?img=36", caption: "finally sent the V7 I've been projecting all month 🧗‍♀️", image: "https://picsum.photos/seed/whisper-climb/640/480", likes: 187, comments: 14, time: "18h" },
  { id: "s12", username: "omar.codes", displayName: "Omar Haddad", verified: false, avatar: "https://i.pravatar.cc/96?img=53", caption: "shipped the app. now we run it back tomorrow.", image: null, likes: 84, comments: 9, time: "20h" },
];

export default function Auth() {
  const navigate = useNavigate();
  const [searchParams] = useSearchParams();
  const [mode, setMode] = useState<"signin" | "signup">(
    searchParams.get("mode") === "signup" ? "signup" : "signin"
  );
  const rawNext = searchParams.get("next") ?? "";
  const nextPath =
    rawNext.startsWith("/") && !rawNext.startsWith("//") ? rawNext : "/";
  // "Add account" mode — the page is up because the user asked for a second
  // login, so it offers the way back to the account they came from.
  const addingAccount = searchParams.get("add") === "1" || isAddingAccount();
  const savedAccounts = useSwitchableAccounts();
  const lastAccount = savedAccounts[0] ?? null;
  const [returning, setReturning] = useState<boolean>(false);
  const [email, setEmail] = useState<string>(() => takeReauthEmail() ?? "");
  const [password, setPassword] = useState<string>("");
  const [inviteCode, setInviteCode] = useState<string>(
    (searchParams.get("code") ?? "").toUpperCase()
  );
  // Instagram-style account split — chosen at signup, applied when the
  // profile row is born during onboarding, switchable anytime in Settings.
  const [accountType, setAccountType] = useState<AccountType>("personal");
  const [proCategory, setProCategory] = useState<string>("");
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState<boolean>(false);
  const [resetBusy, setResetBusy] = useState<boolean>(false);
  const [resetSent, setResetSent] = useState<boolean>(false);
  const [transitionActive, setTransitionActive] = useState<boolean>(false);
  const [postAuthPath, setPostAuthPath] = useState<string | null>(null);

  const forgotPassword = async (): Promise<void> => {
    const trimmed = email.trim();
    if (!trimmed || !trimmed.includes("@")) {
      setError("Enter your email above so we know where to send the reset link.");
      return;
    }
    setError(null);
    setResetBusy(true);
    try {
      // Newest LIVE deploy — the permanent alias is pinned to an old handler
      // that mailed dead (localhost) recovery links.
      const base = await resolveBackend();
      const res = await fetch(`${base}/auth/password-reset`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ email: trimmed }),
      });
      if (!res.ok) throw new Error("reset_failed");
      setResetSent(true);
    } catch {
      setError("Couldn't send the reset email. Please try again.");
    } finally {
      setResetBusy(false);
    }
  };

  const submit = async (e: React.FormEvent): Promise<void> => {
    e.preventDefault();
    setError(null);
    setBusy(true);
    try {
      if (mode === "signup") {
        const { data, error: err } = await supabase.auth.signUp({ email, password });
        if (err) throw err;
        const code = inviteCode.trim();
        const newUserId = data.user?.id;
        if (code && newUserId) {
          void fetch(`${BACKEND_URL}/referrals/redeem`, {
            method: "POST",
            headers: { "Content-Type": "application/json" },
            body: JSON.stringify({ code, userId: newUserId }),
          }).catch(() => undefined);
        }
      } else {
        const { error: err } = await supabase.auth.signInWithPassword({ email, password });
        if (err) throw err;
      }
      if (mode === "signup") {
        clearPendingAccountType();
        stashPendingAccountType({ accountType, category: proCategory.trim() });
        const code = inviteCode.trim();
        const postOnboard = code
          ? `/apply/questionnaire?code=${encodeURIComponent(code)}`
          : nextPath;
        const onboardNext = encodeURIComponent(postOnboard);
        setPostAuthPath(`/onboarding?next=${onboardNext}`);
        setTransitionActive(true);
      } else {
        navigate(nextPath);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : "Something went wrong");
    } finally {
      setBusy(false);
    }
  };

  const onTransitionComplete = () => {
    if (postAuthPath) navigate(postAuthPath, { replace: true });
  };

  // Split simulated posts into three columns scrolling at different speeds.
  const columns = useMemo(() => {
    const cols: SimPost[][] = [[], [], []];
    SIM_POSTS.forEach((post, i) => cols[i % 3].push(post));
    return cols;
  }, []);

  return (
    <div className="relative min-h-screen overflow-hidden bg-background">
      <CircleZoomTransition
        active={transitionActive}
        color="hsl(var(--foreground))"
        origin="bottom"
        duration={900}
        onComplete={onTransitionComplete}
        onReset={() => setTransitionActive(false)}
      />

      {/* ─── Backdrop: simulated feed flowing edge to edge ─── */}
      <div className="absolute inset-0 flex justify-center gap-4 px-4" aria-hidden="true">
        {columns.map((col, colIdx) => (
          <div
            key={colIdx}
            className={`w-full max-w-[340px] overflow-hidden ${colIdx === 1 ? "hidden sm:block" : ""} ${colIdx === 2 ? "hidden lg:block" : ""}`}
          >
            <div
              className="space-y-3 will-change-transform"
              style={{
                animation: `authFeedScroll ${[52, 66, 44][colIdx]}s linear infinite`,
                animationDelay: `${colIdx * -8}s`,
              }}
            >
              {/* Duplicate the column content for a seamless loop */}
              {[...col, ...col].map((post, i) => (
                <SimPostCard key={`${post.id}-${i}`} post={post} likeDelay={1200 + ((i * 1700) % 9000)} />
              ))}
            </div>
          </div>
        ))}
      </div>

      {/* Soft veil so the centered form always stays readable */}
      <div className="pointer-events-none absolute inset-0 bg-gradient-to-b from-background/70 via-background/35 to-background/75 backdrop-blur-[2px]" />

      {/* Back button */}
      <Link
        to="/welcome"
        className="absolute left-4 top-4 z-30 flex h-10 w-10 items-center justify-center rounded-full border border-border/50 bg-background/80 text-foreground shadow-sm backdrop-blur-md transition-all hover:bg-secondary active:scale-95"
        aria-label="Back to home"
      >
        <span className="text-lg">←</span>
      </Link>

      {/* ─── Centered floating auth card (top layer) ─── */}
      <div className="relative z-20 flex min-h-screen items-center justify-center px-4 py-10">
        <div className="w-full max-w-[400px] animate-rise rounded-[28px] border border-border/60 bg-background/85 p-8 shadow-2xl shadow-black/10 backdrop-blur-xl">
          {/* Header */}
          <div className="mb-7 flex flex-col items-center gap-3 text-center">
            {addingAccount && lastAccount && (
              <button
                type="button"
                disabled={returning}
                onClick={() => {
                  if (returning) return;
                  setReturning(true);
                  void returnToLastAccount().then((ok) => {
                    if (ok) {
                      window.location.assign("/profile");
                    } else {
                      setReturning(false);
                      setError("Couldn't switch back — sign in to continue.");
                    }
                  });
                }}
                className="mb-1 inline-flex items-center gap-1.5 self-start rounded-full bg-secondary/70 px-3 py-1.5 text-[12px] font-semibold text-foreground transition-colors hover:bg-secondary disabled:opacity-60"
              >
                <ChevronLeft className="h-3.5 w-3.5" strokeWidth={2.6} />
                {returning ? "Switching…" : `Back to @${lastAccount.username}`}
              </button>
            )}
            <WhisperLogo size={44} className="animate-wordmark-sway" />
            <div>
              <h1 className="font-display text-[28px] font-black leading-tight tracking-tight">
                {addingAccount
                  ? "Add a Whisper account"
                  : mode === "signup"
                    ? "Join Whisper"
                    : "Welcome back"}
              </h1>
              <p className="mt-1 text-[14px] text-muted-foreground">
                {addingAccount
                  ? "Sign in to another account — your current login stays saved in this browser."
                  : "Your daily whisper. Share moments, find your crew."}
              </p>
            </div>
          </div>

          {/* Mode selector */}
          <div className="mb-6 flex justify-center gap-2">
            {(["signin", "signup"] as const).map((m) => (
              <button
                key={m}
                type="button"
                onClick={() => { setMode(m); setError(null); }}
                className={`rounded-full px-5 py-2 text-[13px] font-bold transition-all tap-scale ${
                  mode === m
                    ? "bg-primary text-primary-foreground shadow-md"
                    : "bg-secondary/60 text-muted-foreground hover:text-foreground hover:bg-secondary"
                }`}
              >
                {m === "signin" ? "Sign in" : "Create account"}
              </button>
            ))}
          </div>

          {/* Form */}
          <form onSubmit={submit} className="space-y-3">
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="Email"
              autoComplete="email"
              className="w-full rounded-2xl border border-border/50 bg-secondary/30 px-4 py-3.5 text-[15px] outline-none transition-all focus:border-foreground/30 focus:bg-background"
            />
            <input
              type="password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Password"
              autoComplete={mode === "signup" ? "new-password" : "current-password"}
              className="w-full rounded-2xl border border-border/50 bg-secondary/30 px-4 py-3.5 text-[15px] outline-none transition-all focus:border-foreground/30 focus:bg-background"
            />
            {mode === "signup" && (
              <input
                type="text"
                value={inviteCode}
                onChange={(e) => setInviteCode(e.target.value.toUpperCase())}
                placeholder="Invite / creator code (optional)"
                autoComplete="off"
                maxLength={32}
                className="w-full rounded-2xl border border-border/50 bg-secondary/30 px-4 py-3.5 text-[15px] uppercase tracking-widest outline-none transition-all focus:border-foreground/30 focus:bg-background"
              />
            )}
            {mode === "signup" && (
              <div className="rounded-2xl border border-border/50 bg-secondary/30 p-3">
                <p className="mb-2 px-1 text-[11px] font-bold uppercase tracking-[0.14em] text-muted-foreground">
                  Account type
                </p>
                <div className="grid grid-cols-3 gap-1.5">
                  {(
                    [
                      { id: "personal" as AccountType, label: "Personal", hint: "Just you", Icon: User },
                      { id: "creator" as AccountType, label: "Creator", hint: "Public figure", Icon: Sparkles },
                      { id: "business" as AccountType, label: "Business", hint: "Company or brand", Icon: Briefcase },
                    ]
                  ).map(({ id, label, hint, Icon }) => (
                    <button
                      key={id}
                      type="button"
                      onClick={() => setAccountType(id)}
                      className={`flex flex-col items-center gap-1 rounded-xl border px-2 py-2.5 text-center transition-all ${
                        accountType === id
                          ? "border-foreground/60 bg-background shadow-sm"
                          : "border-transparent bg-transparent hover:bg-background/60"
                      }`}
                    >
                      <Icon className={`h-4 w-4 ${accountType === id ? "text-foreground" : "text-muted-foreground"}`} />
                      <span className="text-[12px] font-bold leading-none">{label}</span>
                      <span className="text-[10px] leading-tight text-muted-foreground">{hint}</span>
                    </button>
                  ))}
                </div>
                {accountType !== "personal" && (
                  <div className="mt-2">
                    <input
                      type="text"
                      value={proCategory}
                      onChange={(e) => setProCategory(e.target.value)}
                      placeholder={
                        accountType === "creator"
                          ? "Category — e.g. Fitness coach, Artist"
                          : "Category — e.g. Restaurant, Gym, Brand"
                      }
                      maxLength={40}
                      className="w-full rounded-xl border border-border/50 bg-background px-3.5 py-2.5 text-[13.5px] outline-none transition-all focus:border-foreground/30"
                    />
                    <p className="mt-1.5 px-1 text-[11px] leading-snug text-muted-foreground">
                      Professional accounts wear a category on their profile and get the
                      pro dashboards. Switch anytime in Settings.
                    </p>
                  </div>
                )}
              </div>
            )}
            {error && (
              <p className="rounded-xl bg-destructive/15 px-3 py-2 text-sm text-destructive">{error}</p>
            )}
            <button
              type="submit"
              disabled={busy}
              className="mt-2 w-full rounded-2xl bg-primary py-3.5 text-[15px] font-semibold text-primary-foreground transition-all hover:opacity-95 active:scale-[0.98] disabled:opacity-60"
            >
              {busy ? "Please wait…" : mode === "signup" ? "Create account" : "Sign in"}
            </button>
          </form>

          {mode === "signin" && (
            <div className="mt-4 text-center">
              {resetSent ? (
                <p className="text-sm text-muted-foreground">Reset link sent — check your inbox.</p>
              ) : (
                <button
                  type="button"
                  onClick={() => void forgotPassword()}
                  disabled={resetBusy}
                  className="text-sm font-semibold text-foreground underline underline-offset-2 transition-opacity hover:opacity-80 disabled:opacity-60"
                >
                  {resetBusy ? "Sending reset link…" : "Forgot password?"}
                </button>
              )}
            </div>
          )}

          <p className="mt-6 text-center text-[12px] leading-relaxed text-muted-foreground">
            By {mode === "signup" ? "signing up" : "signing in"}, you agree to join the{" "}
            <Link to="/welcome" className="font-medium text-foreground underline-offset-2 hover:underline">Whisper</Link> community.
          </p>
        </div>
      </div>

      <style>{`
        @keyframes authFeedScroll {
          0% { transform: translateY(0); }
          100% { transform: translateY(-50%); }
        }
        @keyframes authHeartPop {
          0% { transform: scale(0); opacity: 0; }
          30% { transform: scale(1.35); opacity: 1; }
          60% { transform: scale(0.95); opacity: 1; }
          100% { transform: scale(1); opacity: 0; }
        }
      `}</style>
    </div>
  );
}

/* ------------------------------------------------------------------ */
/*  One simulated post card — Whisper styling, auto-like animation.    */
/* ------------------------------------------------------------------ */

function SimPostCard({ post, likeDelay }: { post: SimPost; likeDelay: number }) {
  const [liked, setLiked] = useState(false);
  const [heartBurst, setHeartBurst] = useState(false);

  useEffect(() => {
    const timer = setTimeout(() => {
      setLiked(true);
      setHeartBurst(true);
      const cleanup = setTimeout(() => setHeartBurst(false), 900);
      return () => clearTimeout(cleanup);
    }, likeDelay);
    return () => clearTimeout(timer);
  }, [likeDelay]);

  return (
    <div className="relative rounded-[20px] border border-border/40 bg-card/90 p-4">
      {/* Header — simulated profile picture + handle */}
      <div className="mb-3 flex items-center gap-2.5">
        <img
          src={post.avatar}
          alt=""
          loading="lazy"
          className="h-9 w-9 rounded-full object-cover"
        />
        <div className="min-w-0 flex-1">
          <p className="flex items-center gap-1 text-[13px] font-bold leading-tight">
            {post.username}
            {post.verified && <BadgeCheck className="h-3.5 w-3.5 fill-sky-500 text-white" />}
          </p>
          <p className="text-[11px] text-muted-foreground">{post.time} ago</p>
        </div>
        <MoreHorizontal className="h-4 w-4 text-muted-foreground" />
      </div>

      {/* Image post */}
      {post.image && (
        <div className="mb-3 overflow-hidden rounded-2xl">
          <img src={post.image} alt="" loading="lazy" className="h-[180px] w-full object-cover" />
        </div>
      )}

      {/* Caption */}
      <p className="mb-3 text-[13px] leading-snug">{post.caption}</p>

      {/* Engagement bar with auto-like */}
      <div className="flex items-center gap-4">
        <div className="flex items-center gap-1.5">
          <Heart
            className={`h-[17px] w-[17px] transition-all duration-300 ${
              liked ? "scale-110 fill-red-500 text-red-500" : "text-foreground/60"
            }`}
          />
          <span className="text-[12px] font-semibold tabular-nums text-muted-foreground">
            {post.likes + (liked ? 1 : 0)}
          </span>
        </div>
        <div className="flex items-center gap-1.5">
          <MessageCircle className="h-[17px] w-[17px] text-foreground/60" />
          <span className="text-[12px] font-semibold tabular-nums text-muted-foreground">
            {post.comments}
          </span>
        </div>
        <Bookmark className="ml-auto h-[17px] w-[17px] text-foreground/60" />
        <Send className="h-[17px] w-[17px] text-foreground/60" />
      </div>

      {/* Heart burst overlay */}
      {heartBurst && (
        <div className="pointer-events-none absolute inset-0 flex items-center justify-center">
          <Heart
            className="h-12 w-12 fill-red-500 text-red-500 drop-shadow-lg"
            style={{ animation: "authHeartPop 0.9s ease-out forwards" }}
          />
        </div>
      )}
    </div>
  );
}
