import { useState } from "react";
import { useNavigate, useParams } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  ArrowUpRight,
  BadgeCheck,
  Briefcase,
  Building2,
  Calendar,
  CheckCircle2,
  ChevronRight,
  DollarSign,
  Flame,
  Grid2x2,
  Loader2,
  ShieldCheck,
  Sparkles,
  Users,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { useAuth } from "@/hooks/useAuth";
import {
  applyForSponsorship,
  BASIS_LABELS,
  fetchBrand,
  fetchEligibility,
  typicalPayText,
  type SponsorBasis,
} from "@/lib/brands";

const BASES: SponsorBasis[] = ["per_post", "per_month", "per_year"];

/**
 * Premium apply modal — a focused, editorial sheet that mirrors the
 * marketplace's calm confidence. The creator picks a collaboration basis,
 * states their ask, and writes a short pitch. The brand can accept, counter,
 * or pass.
 */
function ApplyModal({
  brandUserId,
  brandName,
  brandLogo,
  minAge,
  pay,
  onClose,
}: {
  brandUserId: string;
  brandName: string;
  brandLogo: string | null;
  minAge: number;
  pay: string | null;
  onClose: () => void;
}) {
  const [basis, setBasis] = useState<SponsorBasis>("per_post");
  const [amount, setAmount] = useState<string>("");
  const [age, setAge] = useState<string>("");
  const [message, setMessage] = useState<string>("");
  const queryClient = useQueryClient();

  const apply = useMutation({
    mutationFn: async () => {
      const dollars = Number(amount.replace(/[^0-9.]/g, ""));
      if (!Number.isFinite(dollars) || dollars < 1) {
        throw new Error("Enter a valid amount.");
      }
      const parsedAge = Number(age);
      if (!Number.isFinite(parsedAge) || parsedAge < minAge) {
        throw new Error(`You must be ${minAge} or older to apply to this brand.`);
      }
      await applyForSponsorship({
        brandUserId,
        basis,
        amountCents: Math.round(dollars * 100),
        message: message.trim(),
        age: Math.round(parsedAge),
      });
    },
    onSuccess: () => {
      toast.success("Application sent — track it in My Sponsorships.");
      queryClient.invalidateQueries({ queryKey: ["sponsorship-applications"] });
      onClose();
    },
    onError: (err) =>
      toast.error(err instanceof Error ? err.message : "Couldn't apply."),
  });

  const inputClass =
    "w-full rounded-2xl border border-border bg-background px-4 py-3 text-[15px] outline-none placeholder:text-muted-foreground/50 transition-colors focus:border-foreground/40";

  return (
    <div className="fixed inset-0 z-[80] flex items-end justify-center sm:items-center">
      <button
        aria-label="Close"
        onClick={onClose}
        className="absolute inset-0 bg-black/60 backdrop-blur-md"
      />
      <div className="relative flex max-h-[92vh] w-full max-w-md flex-col overflow-hidden rounded-t-[28px] bg-background shadow-2xl sm:rounded-[28px]">
        {/* Header — brand identity recap */}
        <div className="flex items-center gap-3 border-b border-border px-5 py-4">
          <div
            className="flex shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-secondary ring-1 ring-border"
            style={{ width: 44, height: 44 }}
          >
            {brandLogo ? (
              <img src={brandLogo} alt="" className="h-full w-full object-cover" />
            ) : (
              <Building2 className="h-5 w-5 text-muted-foreground/60" />
            )}
          </div>
          <div className="min-w-0 flex-1">
            <p className="truncate text-[15px] font-extrabold leading-tight">
              Apply to {brandName}
            </p>
            <p className="text-[12px] text-muted-foreground">
              They can accept, counter, or pass.
            </p>
          </div>
          <button
            onClick={onClose}
            aria-label="Close"
            className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary transition-transform active:scale-90"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="min-h-0 flex-1 overflow-y-auto px-5 py-5 pb-[max(1.25rem,env(safe-area-inset-bottom))]">
          {pay && (
            <div className="mb-5 flex items-center gap-2 rounded-2xl bg-emerald-500/8 px-4 py-3">
              <DollarSign className="h-4 w-4 text-emerald-600" />
              <p className="text-[13px] font-bold text-emerald-700 dark:text-emerald-500">
                Typically pays {pay}
              </p>
            </div>
          )}

          <p className="text-[12px] font-bold uppercase tracking-[0.14em] text-muted-foreground">
            Collaboration
          </p>
          <div className="mt-2 grid grid-cols-3 gap-2">
            {BASES.map((b) => (
              <button
                key={b}
                onClick={() => setBasis(b)}
                className={`rounded-2xl px-3 py-2.5 text-[12.5px] font-bold transition-all ${
                  basis === b
                    ? "bg-foreground text-background shadow-sm"
                    : "bg-secondary text-muted-foreground hover:bg-foreground/5"
                }`}
              >
                {BASIS_LABELS[b]}
              </button>
            ))}
          </div>

          <p className="mt-5 text-[12px] font-bold uppercase tracking-[0.14em] text-muted-foreground">
            Your ask
          </p>
          <div className="mt-2 flex items-center rounded-2xl border border-border bg-background px-4 transition-colors focus-within:border-foreground/40">
            <span className="text-[16px] font-semibold text-muted-foreground">$</span>
            <input
              inputMode="decimal"
              value={amount}
              onChange={(e) => setAmount(e.target.value)}
              placeholder="250"
              className="w-full bg-transparent px-2.5 py-3 text-[16px] outline-none placeholder:text-muted-foreground/50"
            />
            <span className="text-[13px] font-semibold text-muted-foreground">
              {basis === "per_post" ? "/post" : basis === "per_month" ? "/mo" : "/yr"}
            </span>
          </div>

          <p className="mt-5 text-[12px] font-bold uppercase tracking-[0.14em] text-muted-foreground">
            Your age
          </p>
          <input
            inputMode="numeric"
            value={age}
            onChange={(e) => setAge(e.target.value)}
            placeholder={String(minAge)}
            className={`${inputClass} mt-2`}
          />

          <p className="mt-5 text-[12px] font-bold uppercase tracking-[0.14em] text-muted-foreground">
            Pitch <span className="font-bold normal-case text-muted-foreground/70">(optional)</span>
          </p>
          <textarea
            value={message}
            onChange={(e) => setMessage(e.target.value)}
            placeholder="Why you're a great fit for this brand…"
            rows={4}
            className={`${inputClass} mt-2 resize-none`}
          />

          <button
            onClick={() => apply.mutate()}
            disabled={apply.isPending || !amount.trim() || !age.trim()}
            className="mt-6 flex w-full items-center justify-center gap-2 rounded-full bg-foreground py-3.5 text-[15px] font-bold text-background transition-transform active:scale-[0.98] disabled:opacity-40"
          >
            {apply.isPending ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              <Sparkles className="h-4 w-4" />
            )}
            Send application
          </button>

          <p className="mt-3 flex items-center justify-center gap-1.5 text-center text-[11.5px] text-muted-foreground">
            <ShieldCheck className="h-3.5 w-3.5 text-emerald-600" />
            Payments are held by Whisper until your posts are live.
          </p>
        </div>
      </div>
    </div>
  );
}

/**
 * Premium brand profile — the page a creator lands on when they're considering
 * applying. Full-bleed cover (when present), editorial hero with logo +
 * verification seal, the brand's voice in their own words, transparent pay,
 * requirements presented as quiet chips, and a confident apply CTA. Reads like
 * a feature, not a directory listing.
 */
export default function BrandProfilePage() {
  const { brandId = "" } = useParams();
  const navigate = useNavigate();
  const { user } = useAuth();
  const [showApply, setShowApply] = useState<boolean>(false);

  const brandQuery = useQuery({
    queryKey: ["brand", brandId],
    queryFn: () => fetchBrand(brandId),
    enabled: !!brandId,
  });

  const isMe = !!user && user.id === brandId;

  const eligibilityQuery = useQuery({
    queryKey: ["brand-eligibility", brandId, user?.id ?? ""],
    queryFn: () => fetchEligibility(brandId),
    enabled: !!brandId && !!user && !isMe && !!brandQuery.data,
  });

  const brand = brandQuery.data;

  if (brandQuery.isLoading) {
    return (
      <div className="flex justify-center py-24">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }
  if (!brand) {
    return (
      <div className="py-24 text-center">
        <p className="text-[15px] font-bold">Brand not found</p>
        <button
          onClick={() => navigate("/brands")}
          className="mt-3 rounded-full bg-foreground px-5 py-2 text-[13px] font-bold text-background"
        >
          Back to brands
        </button>
      </div>
    );
  }

  const pay = typicalPayText(brand);
  const eligibility = eligibilityQuery.data;
  const showcase = [
    ...(brand.cover_url ? [brand.cover_url] : []),
    ...brand.media_urls,
  ];

  return (
    <div className="mx-auto w-full max-w-xl px-4 pb-28 pt-3">
      <button
        onClick={() => navigate(-1)}
        className="mb-3 inline-flex items-center gap-1.5 text-[13.5px] font-bold text-muted-foreground"
      >
        <ArrowLeft className="h-4 w-4" /> Back
      </button>

      {/* Premium hero — full-bleed cover when present, otherwise a clean
          gradient slab. Logo + verification seal layered on top. */}
      <div className="relative overflow-hidden rounded-[28px] border border-border bg-card shadow-[0_8px_30px_rgba(0,0,0,0.06)]">
        <div className="relative h-40 w-full overflow-hidden">
          {brand.cover_url ? (
            <img
              src={brand.cover_url}
              alt=""
              className="h-full w-full object-cover"
            />
          ) : (
            <div className="h-full w-full bg-gradient-to-br from-foreground/[0.07] via-card to-foreground/[0.02]" />
          )}
          <div className="absolute inset-0 bg-gradient-to-t from-card via-card/40 to-transparent" />
          {brand.ember_verified && (
            <div className="absolute right-3 top-3 inline-flex items-center gap-1 rounded-full bg-orange-500/15 px-2.5 py-1 text-[11px] font-bold text-orange-500 backdrop-blur-md">
              <Flame className="h-3 w-3" /> Jasper verified
            </div>
          )}
        </div>

        <div className="px-5 pb-5">
          <div className="-mt-9 flex items-end gap-3">
            <div
              className="flex shrink-0 items-center justify-center overflow-hidden rounded-3xl bg-secondary ring-4 ring-card"
              style={{ width: 76, height: 76 }}
            >
              {brand.logo_url ? (
                <img src={brand.logo_url} alt="" className="h-full w-full object-cover" />
              ) : (
                <Building2 className="h-8 w-8 text-indigo-500/70" />
              )}
            </div>
            <div className="min-w-0 flex-1 pb-1">
              <div className="flex items-center gap-1.5">
                <h1 className="truncate text-[22px] font-black tracking-tight">
                  {brand.company_name}
                </h1>
                <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-indigo-500">
                  <Briefcase className="h-3 w-3 text-white" />
                </span>
              </div>
              {brand.industry && (
                <p className="mt-0.5 text-[13px] font-semibold text-muted-foreground">
                  {brand.industry}
                </p>
              )}
            </div>
          </div>

          {brand.website && (
            <a
              href={brand.website.startsWith("http") ? brand.website : `https://${brand.website}`}
              target="_blank"
              rel="noreferrer"
              className="mt-3 inline-flex items-center gap-1 text-[12.5px] font-bold text-indigo-500"
            >
              {brand.website.replace(/^https?:\/\//, "")}
              <ArrowUpRight className="h-3 w-3" />
            </a>
          )}

          {brand.about && (
            <p className="mt-3 text-[14px] leading-relaxed text-foreground/80">
              {brand.about}
            </p>
          )}
        </div>
      </div>

      {/* Showcase gallery — the brand's visual identity, if they've uploaded one. */}
      {showcase.length > 0 && (
        <div className="mt-3 grid grid-cols-3 gap-1.5">
          {showcase.slice(0, 6).map((url, i) => (
            <div
              key={`${url}-${i}`}
              className="aspect-square overflow-hidden rounded-xl bg-secondary"
            >
              <img src={url} alt="" className="h-full w-full object-cover" />
            </div>
          ))}
        </div>
      )}

      {/* Ember verification card — the trust signal creators care about. */}
      {brand.ember_summary && (
        <div
          className={`mt-3 rounded-[24px] border p-5 ${
            brand.ember_verified
              ? "border-orange-500/25 bg-orange-500/[0.04]"
              : "border-amber-500/25 bg-amber-500/[0.04]"
          }`}
        >
          <div className="flex items-center gap-2">
            <span
              className={`flex h-9 w-9 items-center justify-center rounded-2xl ${
                brand.ember_verified
                  ? "bg-orange-500/15 text-orange-500"
                  : "bg-amber-500/15 text-amber-600"
              }`}
            >
              <Flame className="h-4 w-4" />
            </span>
            <div>
              <p className="text-[14px] font-extrabold">
                Jasper checked this brand
                {typeof brand.ember_score === "number" &&
                  ` · ${brand.ember_score}/100`}
              </p>
              <p className="text-[11.5px] font-semibold uppercase tracking-wider text-muted-foreground">
                {brand.ember_verified ? "Verified" : "Under review"}
              </p>
            </div>
          </div>
          <p className="mt-3 text-[13px] leading-relaxed text-foreground/75">
            {brand.ember_summary}
          </p>
          {brand.instagram && (
            <a
              href={`https://instagram.com/${brand.instagram}`}
              target="_blank"
              rel="noreferrer"
              className="mt-2 inline-flex items-center gap-1 text-[12px] font-bold text-orange-500"
            >
              @{brand.instagram} on Instagram
              <ArrowUpRight className="h-3 w-3" />
            </a>
          )}
        </div>
      )}

      {/* Two-column requirement + pay grid — quiet, scannable. */}
      <div className="mt-3 grid gap-3 sm:grid-cols-2">
        <div className="rounded-[24px] border border-border bg-card p-5">
          <p className="text-[11px] font-bold uppercase tracking-[0.16em] text-muted-foreground">
            Requirements
          </p>
          <div className="mt-3 space-y-3">
            <ReqRow icon={<Users className="h-4 w-4" />} label="Followers">
              {brand.min_followers.toLocaleString()}+
            </ReqRow>
            <ReqRow icon={<Calendar className="h-4 w-4" />} label="Minimum age">
              {brand.min_age}+
            </ReqRow>
            {brand.min_posts > 0 && (
              <ReqRow icon={<Grid2x2 className="h-4 w-4" />} label="Posts">
                {brand.min_posts}+
              </ReqRow>
            )}
          </div>
        </div>

        <div className="rounded-[24px] border border-border bg-card p-5">
          <p className="text-[11px] font-bold uppercase tracking-[0.16em] text-muted-foreground">
            Payment
          </p>
          {pay ? (
            <p className="mt-3 text-[18px] font-black text-emerald-600">
              {pay}
            </p>
          ) : (
            <p className="mt-3 text-[13px] text-muted-foreground">
              No typical pay range shared yet.
            </p>
          )}
          {brand.payment_terms && (
            <p className="mt-2 text-[12.5px] leading-relaxed text-muted-foreground">
              {brand.payment_terms}
            </p>
          )}
          <p className="mt-3 flex items-start gap-1.5 text-[11.5px] leading-snug text-muted-foreground">
            <ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-600" />
            Held by Whisper, released once your sponsored posts are live.
          </p>
        </div>
      </div>

      {/* Amenities — what the brand uses internally. */}
      {brand.amenities.length > 0 && (
        <div className="mt-3 rounded-[24px] border border-border bg-card p-5">
          <p className="text-[11px] font-bold uppercase tracking-[0.16em] text-muted-foreground">
            What this brand uses
          </p>
          <div className="mt-3 flex flex-wrap gap-2">
            {brand.amenities.map((a) => (
              <span
                key={a}
                className="inline-flex items-center gap-1.5 rounded-full bg-foreground/5 px-3 py-1.5 text-[12px] font-semibold text-foreground/80"
              >
                <BadgeCheck className="h-3 w-3 text-muted-foreground" />
                {a}
              </span>
            ))}
          </div>
        </div>
      )}

      {/* Apply CTA — the page's purpose. */}
      {!isMe && (
        <div className="mt-6">
          {eligibilityQuery.isLoading ? (
            <div className="flex justify-center py-4">
              <Loader2 className="h-5 w-5 animate-spin text-muted-foreground" />
            </div>
          ) : eligibility && !eligibility.eligible ? (
            <div className="rounded-[24px] border border-border bg-card p-5">
              <p className="text-[14px] font-extrabold">
                You're not eligible to apply yet
              </p>
              <ul className="mt-2 space-y-1.5">
                {eligibility.reasons.map((r) => (
                  <li
                    key={r}
                    className="flex items-start gap-2 text-[12.5px] text-muted-foreground"
                  >
                    <span className="mt-1.5 h-1 w-1 shrink-0 rounded-full bg-muted-foreground/50" />
                    {r}
                  </li>
                ))}
              </ul>
            </div>
          ) : (
            <button
              onClick={() => setShowApply(true)}
              className="flex w-full items-center justify-center gap-2 rounded-full bg-foreground py-4 text-[16px] font-bold text-background transition-transform active:scale-[0.98] shadow-[0_8px_24px_rgba(0,0,0,0.12)]"
            >
              <CheckCircle2 className="h-5 w-5" />
              Apply for sponsorship
              <ChevronRight className="h-4 w-4" />
            </button>
          )}
        </div>
      )}

      {showApply && (
        <ApplyModal
          brandUserId={brand.user_id}
          brandName={brand.company_name}
          brandLogo={brand.logo_url}
          minAge={brand.min_age}
          pay={pay}
          onClose={() => setShowApply(false)}
        />
      )}
    </div>
  );
}

function ReqRow({
  icon,
  label,
  children,
}: {
  icon: React.ReactNode;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-center gap-3">
      <span className="flex h-8 w-8 items-center justify-center rounded-xl bg-foreground/5 text-muted-foreground">
        {icon}
      </span>
      <div className="min-w-0 flex-1">
        <p className="text-[11px] font-semibold uppercase tracking-wider text-muted-foreground/80">
          {label}
        </p>
        <p className="text-[14px] font-bold">{children}</p>
      </div>
    </div>
  );
}
