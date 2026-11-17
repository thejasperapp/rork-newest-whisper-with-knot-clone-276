import { useState } from "react";
import { Link, useParams } from "react-router-dom";
import { useQuery } from "@tanstack/react-query";
import {
  BadgeCheck,
  Check,
  CircleAlert,
  Dumbbell,
  Loader2,
  Lock,
  RefreshCcw,
  ShieldCheck,
} from "lucide-react";
import { toast } from "sonner";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { EmbeddedCheckoutSheet } from "@/components/EmbeddedCheckoutSheet";
import { TestModeBanner } from "@/components/TestModeBanner";
import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/lib/supabase";
import {
  fetchCoachRate,
  formatCents,
  startEmbeddedHireCheckout,
} from "@/lib/coachPay";

const DEFAULT_PERKS: string[] = [
  "Direct line to your coach in DMs",
  "Personalized programming & check-ins",
  "Cancel anytime — no lock-in",
  "Your coach keeps 90% of every payment",
];

/** Warm cream/orange palette — fixed, theme-independent (a branded page). */
const CREAM = "#FAF2E3";
const CARD = "#FFFDF8";
const INK = "#43301D";
const MUTED = "#8B7052";
const LINE = "#EDDCC2";
const ORANGE = "#F27E17";

/**
 * Public "hire this coach" page — the shareable link a coach sends to
 * clients. Cream-and-orange identity card with the coach's photo straddling
 * the top edge (half in, half out), published plan tiers as selectable
 * cards, and checkout stays in the app via the embedded Stripe sheet.
 */
export default function HireCoach() {
  const { coachId } = useParams<{ coachId: string }>();
  const { session, loading } = useAuth();
  const [starting, setStarting] = useState<boolean>(false);
  const [tierId, setTierId] = useState<string | null>(null);
  const [embedded, setEmbedded] = useState<{ clientSecret: string; publishableKey: string } | null>(null);

  const rate = useQuery({
    queryKey: ["coach-rate", coachId ?? ""],
    queryFn: () => fetchCoachRate(coachId!),
    enabled: !!coachId,
  });

  // The coach's real photo for the straddling avatar (best-effort).
  const photo = useQuery({
    queryKey: ["coach-photo", coachId ?? ""],
    enabled: !!coachId,
    staleTime: 5 * 60 * 1000,
    queryFn: async (): Promise<{ image: string | null; name: string | null }> => {
      const { data } = await supabase
        .from("whisper_profiles")
        .select("profile_image_url, display_name")
        .eq("user_id", coachId!)
        .maybeSingle();
      const row = data as {
        profile_image_url: string | null;
        display_name: string | null;
      } | null;
      return {
        image: row?.profile_image_url ?? null,
        name: row?.display_name ?? null,
      };
    },
  });

  const selfPath = `/hire/${coachId ?? ""}`;

  const name =
    rate.data?.displayName ||
    rate.data?.username ||
    photo.data?.name ||
    "This coach";
  const tiers = rate.data?.tiers ?? [];
  const selectedTier = tiers.find((t) => t.id === tierId) ?? tiers[0] ?? null;
  const priceCents =
    selectedTier?.monthlyPriceCents ?? rate.data?.monthlyPriceCents ?? null;
  const ready =
    !!rate.data?.acceptingPayments &&
    ((rate.data.active && !!rate.data.monthlyPriceCents) || tiers.length > 0);

  const handleHire = async () => {
    if (!coachId || !session?.user) return;
    setStarting(true);
    try {
      const result = await startEmbeddedHireCheckout({
        coachUserId: coachId,
        tierId: selectedTier?.id,
        userId: session.user.id,
        email: session.user.email ?? "",
        cancelPath: selfPath,
      });
      setEmbedded(result);
      setStarting(false);
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Couldn't start checkout."
      );
      setStarting(false);
    }
  };

  /** The coach's circular photo, half in the card and half out. */
  const straddleAvatar = (
    <div className="absolute -top-14 left-1/2 -translate-x-1/2">
      <div
        className="relative h-28 w-28 overflow-hidden rounded-full shadow-[0_14px_34px_-12px_rgba(180,110,30,0.55)] ring-[6px]"
        style={{ backgroundColor: "#FA9452", "--tw-ring-color": CREAM } as React.CSSProperties}
      >
        <span className="flex h-full w-full items-center justify-center bg-gradient-to-br from-orange-400 to-amber-500 text-[40px] font-black uppercase text-white">
          {(rate.data?.username ?? name).trim().slice(0, 1) || (
            <Dumbbell className="h-10 w-10" />
          )}
        </span>
        {photo.data?.image && (
          <img
            src={photo.data.image}
            alt={name}
            loading="lazy"
            className="absolute inset-0 h-full w-full object-cover"
            onError={(e) => {
              (e.target as HTMLImageElement).style.display = "none";
            }}
          />
        )}
      </div>
      <span
        className="absolute -bottom-0.5 -right-0.5 flex h-9 w-9 items-center justify-center rounded-full text-white ring-4"
        style={{ backgroundColor: ORANGE, "--tw-ring-color": CARD } as React.CSSProperties}
        title="Verified coach"
      >
        <BadgeCheck className="h-5 w-5" />
      </span>
    </div>
  );

  return (
    <div
      className="flex min-h-screen flex-col"
      style={{ backgroundColor: CREAM, color: INK }}
    >
      {embedded && (
        <EmbeddedCheckoutSheet
          clientSecret={embedded.clientSecret}
          publishableKey={embedded.publishableKey}
          brief={{
            title: `Coaching with ${name}`,
            price: priceCents ? formatCents(priceCents) : "—",
            cadence: "/month",
            note: selectedTier
              ? `${selectedTier.name}${selectedTier.tagline ? ` — ${selectedTier.tagline}` : ""}`
              : "Cancel anytime · your coach keeps 90%",
            perks:
              selectedTier && selectedTier.perks.length > 0
                ? selectedTier.perks
                : DEFAULT_PERKS,
            refundDays: 7,
          }}
          onClose={() => setEmbedded(null)}
          onComplete={() => {
            setEmbedded(null);
            window.location.href = "/billing/success?embedded=1";
          }}
        />
      )}
      <PublicNav />
      <main className="relative flex flex-1 items-start justify-center overflow-x-clip px-4 pb-16 pt-28 sm:px-6">
        {/* Warm bloom behind the card. */}
        <div
          aria-hidden
          className="pointer-events-none absolute left-1/2 top-10 h-72 w-[520px] max-w-[92vw] -translate-x-1/2 rounded-full opacity-50 blur-3xl"
          style={{
            background:
              "radial-gradient(closest-side, rgba(242,126,23,0.28), transparent)",
          }}
        />
        <div className="relative w-full max-w-lg">
          <TestModeBanner className="mb-4" />

          {rate.isPending ? (
            <div
              className="rounded-[34px] border p-10 text-center"
              style={{ backgroundColor: CARD, borderColor: LINE }}
            >
              <Loader2
                className="mx-auto mb-5 h-10 w-10 animate-spin"
                style={{ color: MUTED }}
              />
              <h1 className="font-display text-[24px] font-extrabold">
                Loading coach…
              </h1>
            </div>
          ) : rate.isError || !coachId ? (
            <div
              className="rounded-[34px] border p-10 text-center"
              style={{ backgroundColor: CARD, borderColor: LINE }}
            >
              <CircleAlert className="mx-auto mb-5 h-12 w-12" style={{ color: MUTED }} />
              <h1 className="font-display text-[24px] font-extrabold">
                Coach not found
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed" style={{ color: MUTED }}>
                This coaching link doesn&rsquo;t look right — ask your coach to
                send it again.
              </p>
            </div>
          ) : !ready ? (
            <div
              className="relative mt-14 rounded-[34px] border px-8 pb-10 pt-[72px] text-center"
              style={{ backgroundColor: CARD, borderColor: LINE }}
            >
              {straddleAvatar}
              <ShieldCheck className="mx-auto mb-4 h-10 w-10" style={{ color: MUTED }} />
              <h1 className="font-display text-[24px] font-extrabold">
                {name} isn&rsquo;t accepting payments yet
              </h1>
              <p className="mt-3 text-[15px] leading-relaxed" style={{ color: MUTED }}>
                Once they finish setting up their rate and bank account, this
                page will let you subscribe in one tap.
              </p>
            </div>
          ) : (
            <div
              className="relative mt-14 rounded-[34px] border px-5 pb-7 pt-[72px] shadow-[0_30px_80px_-40px_rgba(170,105,30,0.4)] sm:px-7"
              style={{ backgroundColor: CARD, borderColor: LINE }}
            >
              {/* Soft inner glow behind the avatar's lower half. */}
              <div
                aria-hidden
                className="pointer-events-none absolute inset-x-0 top-0 h-36 overflow-hidden rounded-t-[34px]"
              >
                <div
                  className="absolute left-1/2 top-[-40px] h-44 w-72 -translate-x-1/2 rounded-full opacity-60 blur-2xl"
                  style={{
                    background:
                      "radial-gradient(closest-side, rgba(250,148,82,0.35), transparent)",
                  }}
                />
              </div>

              {straddleAvatar}

              {/* Identity. */}
              <div className="relative text-center">
                <p
                  className="text-[10.5px] font-black uppercase tracking-[0.24em]"
                  style={{ color: ORANGE }}
                >
                  Verified Coach
                </p>
                <h1 className="mt-1.5 font-display text-[27px] font-extrabold leading-tight">
                  Train with{" "}
                  {rate.data?.username ? `@${rate.data.username}` : name}
                </h1>
                <p
                  className="mx-auto mt-2 max-w-[350px] text-[13.5px] leading-relaxed"
                  style={{ color: MUTED }}
                >
                  Monthly coaching — programs, check-ins, and DM access, direct
                  with your coach on Whisper.
                </p>
              </div>

              <div
                className="my-5 h-px w-full"
                style={{ backgroundColor: LINE }}
              />

              {/* Plans. */}
              {tiers.length > 0 ? (
                <>
                  <p
                    className="text-[11px] font-black uppercase tracking-[0.16em]"
                    style={{ color: MUTED }}
                  >
                    Pick your plan
                  </p>
                  <div className="mt-3 space-y-2.5">
                    {tiers.map((t) => {
                      const active = t.id === (selectedTier?.id ?? "");
                      return (
                        <button
                          key={t.id}
                          type="button"
                          onClick={() => setTierId(t.id)}
                          className={cn(
                            "w-full rounded-2xl border p-4 text-left transition-all",
                            active && "shadow-sm"
                          )}
                          style={{
                            borderColor: active ? ORANGE : LINE,
                            backgroundColor: active ? "#FFF4E3" : CARD,
                            boxShadow: active
                              ? "0 6px 18px -10px rgba(242,126,23,0.45)"
                              : undefined,
                          }}
                        >
                          <div className="flex items-center gap-3">
                            <span
                              className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full border-2 transition-colors"
                              style={{ borderColor: active ? ORANGE : LINE }}
                            >
                              {active && (
                                <span
                                  className="h-2.5 w-2.5 rounded-full"
                                  style={{ backgroundColor: ORANGE }}
                                />
                              )}
                            </span>
                            <div className="min-w-0 flex-1">
                              <p className="text-[15px] font-bold">{t.name}</p>
                              {t.tagline && (
                                <p
                                  className="truncate text-[12.5px]"
                                  style={{ color: MUTED }}
                                >
                                  {t.tagline}
                                </p>
                              )}
                            </div>
                            <p
                              className="shrink-0 text-[15px] font-extrabold"
                              style={{ color: ORANGE }}
                            >
                              {formatCents(t.monthlyPriceCents)}
                              <span
                                className="text-[11px] font-semibold"
                                style={{ color: MUTED }}
                              >
                                /mo
                              </span>
                            </p>
                          </div>
                          {t.perks.length > 0 && (
                            <ul className="mt-2.5 space-y-1 pl-8">
                              {t.perks.map((p) => (
                                <li
                                  key={p}
                                  className="flex items-start gap-1.5 text-[12.5px]"
                                  style={{ color: MUTED }}
                                >
                                  <Check
                                    className="mt-0.5 h-3.5 w-3.5 shrink-0"
                                    style={{ color: ORANGE }}
                                  />
                                  {p}
                                </li>
                              ))}
                            </ul>
                          )}
                        </button>
                      );
                    })}
                  </div>
                </>
              ) : (
                <>
                  <div className="flex items-end justify-center gap-1.5">
                    <p className="font-display text-[38px] font-extrabold leading-none">
                      {formatCents(priceCents ?? 0)}
                    </p>
                    <p
                      className="pb-1 text-[13px] font-semibold"
                      style={{ color: MUTED }}
                    >
                      /month
                    </p>
                  </div>
                  <ul className="mx-auto mt-4 max-w-[320px] space-y-2">
                    {DEFAULT_PERKS.map((p) => (
                      <li
                        key={p}
                        className="flex items-start gap-2 text-[13.5px]"
                        style={{ color: MUTED }}
                      >
                        <Check
                          className="mt-0.5 h-4 w-4 shrink-0"
                          style={{ color: ORANGE }}
                        />
                        {p}
                      </li>
                    ))}
                  </ul>
                </>
              )}

              {/* Checkout. */}
              {loading ? (
                <Loader2
                  className="mx-auto mt-6 h-6 w-6 animate-spin"
                  style={{ color: MUTED }}
                />
              ) : !session ? (
                <>
                  <p
                    className="mt-5 text-center text-[13px]"
                    style={{ color: MUTED }}
                  >
                    Sign in (or create a free account) so your coach knows
                    who&rsquo;s subscribing.
                  </p>
                  <Link
                    to={`/auth?next=${encodeURIComponent(selfPath)}`}
                    className="earn-shine mt-3 flex h-[52px] w-full items-center justify-center gap-2 rounded-full bg-gradient-to-r from-orange-500 to-amber-500 text-[15px] font-bold text-white shadow-lg shadow-orange-500/25 transition-transform active:scale-[0.98]"
                  >
                    Sign in to continue
                  </Link>
                </>
              ) : (
                <button
                  onClick={handleHire}
                  disabled={starting}
                  className="earn-shine mt-5 flex h-[52px] w-full items-center justify-center gap-2 rounded-full bg-gradient-to-r from-orange-500 to-amber-500 text-[15px] font-bold text-white shadow-lg shadow-orange-500/25 transition-transform active:scale-[0.98] disabled:opacity-50 disabled:shadow-none"
                >
                  {starting ? (
                    <Loader2 className="h-4.5 w-4.5 animate-spin" />
                  ) : (
                    <BadgeCheck className="h-4.5 w-4.5" />
                  )}
                  Subscribe — {formatCents(priceCents ?? 0)}/month
                </button>
              )}

              {/* Trust strip. */}
              <div
                className="mt-4 flex flex-wrap items-center justify-center gap-x-4 gap-y-1.5 text-[11.5px] font-semibold"
                style={{ color: MUTED }}
              >
                <span className="flex items-center gap-1.5">
                  <Lock className="h-3.5 w-3.5" style={{ color: ORANGE }} />
                  Secured by Stripe
                </span>
                <span className="flex items-center gap-1.5">
                  <RefreshCcw className="h-3.5 w-3.5" style={{ color: ORANGE }} />
                  7-day refund window
                </span>
                <span className="flex items-center gap-1.5">
                  <Check className="h-3.5 w-3.5" style={{ color: ORANGE }} />
                  Cancel anytime
                </span>
              </div>

              <p
                className="mt-3 text-center text-[11.5px] leading-relaxed"
                style={{ color: MUTED }}
              >
                Billed monthly through Stripe ·{" "}
                <Link
                  to="/policies#coaching"
                  className="underline"
                  style={{ color: INK }}
                >
                  coaching &amp; refund policy
                </Link>
              </p>
            </div>
          )}
        </div>
      </main>
      <PublicFooter />
    </div>
  );
}
