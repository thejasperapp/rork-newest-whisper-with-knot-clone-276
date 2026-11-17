import { useState } from "react";
import { Link } from "react-router-dom";
import { usePitchReset, usePitchToast } from "@/components/pitch/PitchContext";
import { PitchSheet } from "@/components/pitch/PitchPhoneFrame";
import {
  ArrowLeft,
  ArrowUpRight,
  Briefcase,
  Building2,
  Calendar,
  CheckCircle2,
  ChevronRight,
  DollarSign,
  Flame,
  Grid2x2,
  Loader2,
  Send,
  ShieldCheck,
  Users,
  X,
} from "lucide-react";

import {
  BASIS_LABELS,
  BASIS_SHORT,
  typicalPayText,
  type SponsorBasis,
} from "@/lib/brands";
import {
  SAMPLE_BRANDS,
  SAMPLE_BRAND_PHOTOS,
  type SampleBrand,
} from "@/lib/pitch";
import { cn } from "@/lib/utils";

const BASES: SponsorBasis[] = ["per_post", "per_month", "per_year"];

/**
 * Interactive brand-marketplace demo for Pitch Mode. The card layout, chip
 * styles, and detail view are lifted verbatim from the real /brands directory
 * and /brands/:brandId profile page — same indigo brand pill, same Ember
 * verified badge, same "Typically pays" emerald line, same requirements grid,
 * same apply modal — so a prospect sees the real product, not a mockup. Real
 * generated product photos stand in for brand logos.
 */
export function BrandMarketDemo() {
  const [selected, setSelected] = useState<SampleBrand | null>(null);
  const [appliedIds, setAppliedIds] = useState<Set<string>>(new Set());
  usePitchReset(() => setAppliedIds(new Set()));

  return (
    <div className="space-y-3">
      {SAMPLE_BRANDS.map((brand) => {
        const pay = typicalPayText(brand);
        const applied = appliedIds.has(brand.user_id);
        const photo = SAMPLE_BRAND_PHOTOS[brand.user_id];
        return (
          <button
            key={brand.user_id}
            onClick={() => setSelected(brand)}
            className="group block w-full rounded-[20px] border border-border bg-card p-4 text-left shadow-sm transition-transform active:scale-[0.99]"
          >
            <div className="flex items-center gap-3.5">
              <div
                className="flex shrink-0 items-center justify-center overflow-hidden rounded-xl bg-secondary"
                style={{ width: 52, height: 52 }}
              >
                {photo ? (
                  <img
                    src={photo}
                    alt=""
                    className="h-full w-full object-cover"
                  />
                ) : (
                  <Building2 className="h-5 w-5 text-indigo-500/70" />
                )}
              </div>
              <div className="min-w-0 flex-1">
                <div className="flex items-center gap-1.5">
                  <p className="truncate text-[15px] font-extrabold">
                    {brand.company_name}
                  </p>
                  <span className="flex h-[17px] w-[17px] items-center justify-center rounded-full bg-indigo-500">
                    <Briefcase className="h-2.5 w-2.5 text-white" />
                  </span>
                  {brand.ember_verified && (
                    <span className="inline-flex items-center gap-0.5 rounded-full bg-orange-500/12 px-1.5 py-0.5 text-[10px] font-bold text-orange-500">
                      <Flame className="h-2.5 w-2.5" /> Jasper verified
                    </span>
                  )}
                  {applied && (
                    <span className="ml-auto flex items-center gap-0.5 rounded-full bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-bold text-emerald-600">
                      <CheckCircle2 className="h-3 w-3" /> Applied
                    </span>
                  )}
                </div>
                {brand.industry && (
                  <p className="truncate text-[12.5px] text-muted-foreground">
                    {brand.industry}
                  </p>
                )}
                {pay && (
                  <p className="text-[12.5px] font-bold text-emerald-600">
                    Typically pays {pay}
                  </p>
                )}
              </div>
              <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
            </div>
            <div className="mt-3 flex flex-wrap gap-1.5">
              <span className="rounded-full border border-border px-2.5 py-0.5 text-[11px] font-semibold text-muted-foreground">
                {brand.min_followers.toLocaleString()}+ followers
              </span>
              <span className="rounded-full border border-border px-2.5 py-0.5 text-[11px] font-semibold text-muted-foreground">
                {brand.min_age}+
              </span>
              {brand.min_posts > 0 && (
                <span className="rounded-full border border-border px-2.5 py-0.5 text-[11px] font-semibold text-muted-foreground">
                  {brand.min_posts}+ posts
                </span>
              )}
            </div>
          </button>
        );
      })}

      {selected && (
        <BrandDetailSheet
          brand={selected}
          applied={appliedIds.has(selected.user_id)}
          onApply={() =>
            setAppliedIds((prev) => new Set(prev).add(selected.user_id))
          }
          onClose={() => setSelected(null)}
        />
      )}
    </div>
  );
}

/**
 * The brand detail view — mirrors /brands/:brandId exactly: logo+name+Ember
 * badge header, about, Ember check card, requirements card, payment
 * transparency card, amenities, and the eligibility-gated apply button +
 * ApplyModal. Demo-only: the apply flow simulates success locally.
 */
function BrandDetailSheet({
  brand,
  applied,
  onApply,
  onClose,
}: {
  brand: SampleBrand;
  applied: boolean;
  onApply: () => void;
  onClose: () => void;
}) {
  const [showApply, setShowApply] = useState<boolean>(false);

  const pay = typicalPayText(brand);
  const photo = SAMPLE_BRAND_PHOTOS[brand.user_id];

  return (
    <>
      <PitchSheet open onClose={onClose} zIndex={80}>
        <div className="flex h-full w-full flex-col overflow-hidden bg-card animate-in slide-in-from-bottom-full duration-300">
          {/* Header */}
          <div className="flex shrink-0 items-center justify-between border-b border-border px-4 py-3.5">
            <button
              onClick={onClose}
              aria-label="Back"
              className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary transition-transform active:scale-90"
            >
              <ArrowLeft className="h-5 w-5" />
            </button>
            <p className="text-[15px] font-bold">Brand profile</p>
            <button
              onClick={onClose}
              aria-label="Close"
              className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary transition-transform active:scale-90"
            >
              <X className="h-4 w-4" />
            </button>
          </div>

          {/* Scrollable body */}
          <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-4">
            {/* Brand header */}
            <div className="flex items-center gap-4">
              <div
                className="flex shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-secondary"
                style={{ width: 72, height: 72 }}
              >
                {photo ? (
                  <img
                    src={photo}
                    alt=""
                    className="h-full w-full object-cover"
                  />
                ) : (
                  <Building2 className="h-7 w-7 text-indigo-500/70" />
                )}
              </div>
              <div className="min-w-0">
                <div className="flex items-center gap-2">
                  <h1 className="truncate text-[20px] font-black">
                    {brand.company_name}
                  </h1>
                  <span className="flex h-5 w-5 shrink-0 items-center justify-center rounded-full bg-indigo-500">
                    <Briefcase className="h-3 w-3 text-white" />
                  </span>
                </div>
                {brand.ember_verified && (
                  <span className="mt-0.5 inline-flex items-center gap-1 rounded-full bg-orange-500/12 px-2 py-0.5 text-[11px] font-bold text-orange-500">
                    <Flame className="h-3 w-3" /> Jasper verified brand
                  </span>
                )}
                {brand.industry && (
                  <p className="text-[13px] font-semibold text-muted-foreground">
                    {brand.industry}
                  </p>
                )}
                {brand.website && (
                  <a
                    href={brand.website.startsWith("http") ? brand.website : `https://${brand.website}`}
                    target="_blank"
                    rel="noreferrer"
                    className="inline-flex items-center gap-0.5 text-[12.5px] font-bold text-indigo-500"
                  >
                    {brand.website.replace(/^https?:\/\//, "")}
                    <ArrowUpRight className="h-3 w-3" />
                  </a>
                )}
              </div>
            </div>

            {brand.about && (
              <p className="text-[14px] leading-relaxed text-muted-foreground">
                {brand.about}
              </p>
            )}

            {brand.ember_summary && (
              <div
                className={cn(
                  "rounded-[20px] border p-4",
                  brand.ember_verified
                    ? "border-orange-500/25 bg-orange-500/5"
                    : "border-amber-500/25 bg-amber-500/5"
                )}
              >
                <div className="flex items-center gap-1.5">
                  <Flame className="h-4 w-4 text-orange-500" />
                  <p className="text-[13.5px] font-extrabold">
                    Ember checked this brand
                    {typeof brand.ember_score === "number" &&
                      ` · ${brand.ember_score}/100`}
                  </p>
                </div>
                <p className="mt-1.5 text-[12.5px] leading-snug text-muted-foreground">
                  {brand.ember_summary}
                </p>
                {brand.instagram && (
                  <a
                    href={`https://instagram.com/${brand.instagram}`}
                    target="_blank"
                    rel="noreferrer"
                    className="mt-1.5 inline-block text-[12px] font-bold text-orange-500"
                  >
                    @{brand.instagram} on Instagram
                  </a>
                )}
              </div>
            )}

            {/* Requirements card — verbatim from real profile page */}
            <div className="rounded-[20px] border border-border bg-card p-4">
              <p className="text-[14px] font-extrabold">Sponsorship requirements</p>
              <div className="mt-3 space-y-2.5">
                <div className="flex items-center gap-2.5 text-[13.5px] font-medium">
                  <Users className="h-4 w-4 text-muted-foreground" />
                  {brand.min_followers.toLocaleString()}+ followers
                </div>
                <div className="flex items-center gap-2.5 text-[13.5px] font-medium">
                  <Calendar className="h-4 w-4 text-muted-foreground" />
                  {brand.min_age}+ years old
                </div>
                {brand.min_posts > 0 && (
                  <div className="flex items-center gap-2.5 text-[13.5px] font-medium">
                    <Grid2x2 className="h-4 w-4 text-muted-foreground" />
                    {brand.min_posts}+ posts
                  </div>
                )}
              </div>
            </div>

            {/* Payment transparency card — verbatim */}
            <div className="rounded-[20px] border border-border bg-card p-4">
              <div className="flex items-center gap-2">
                <DollarSign className="h-4.5 w-4.5 text-emerald-600" />
                <p className="text-[14px] font-extrabold">Payment transparency</p>
              </div>
              {pay ? (
                <p className="mt-2 text-[13.5px] font-bold text-emerald-600">
                  This brand typically pays {pay}
                </p>
              ) : (
                <p className="mt-2 text-[13px] text-muted-foreground">
                  This brand hasn't shared a typical pay range yet.
                </p>
              )}
              {brand.payment_terms && (
                <p className="mt-1.5 text-[12.5px] leading-snug text-muted-foreground">
                  {brand.payment_terms}
                </p>
              )}
              <p className="mt-2 flex items-start gap-1.5 text-[11.5px] leading-snug text-muted-foreground">
                <ShieldCheck className="mt-0.5 h-3.5 w-3.5 shrink-0 text-emerald-600" />
                Payments are held by Whisper and only released once your sponsored
                posts are live — you never chase an invoice.
              </p>
            </div>

            {brand.amenities.length > 0 && (
              <div className="rounded-[20px] border border-border bg-card p-4">
                <p className="text-[14px] font-extrabold">What this brand uses</p>
                <div className="mt-2.5 flex flex-wrap gap-1.5">
                  {brand.amenities.map((a) => (
                    <span
                      key={a}
                      className="rounded-full border border-border px-3 py-1 text-[12px] font-semibold text-muted-foreground"
                    >
                      {a}
                    </span>
                  ))}
                </div>
              </div>
            )}

            <p className="text-center text-[11px] text-muted-foreground">
              Sample brand for presentation · funds are escrowed on real deals and
              released when tracked posts go live · Whisper keeps 10%.
            </p>
          </div>

          {/* Sticky footer CTA */}
          <div className="shrink-0 border-t border-border bg-card p-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
            {applied ? (
              <div className="flex items-center justify-center gap-2 rounded-full bg-emerald-500/10 py-3.5 text-[15px] font-bold text-emerald-600">
                <CheckCircle2 className="h-4.5 w-4.5" /> Application sent (demo)
              </div>
            ) : (
              <button
                onClick={() => setShowApply(true)}
                className="flex w-full items-center justify-center gap-2 rounded-full bg-indigo-500 py-3.5 text-[15px] font-bold text-white transition-transform active:scale-[0.98]"
              >
                <CheckCircle2 className="h-4.5 w-4.5" />
                Apply for sponsorship
              </button>
            )}
          </div>
        </div>
      </PitchSheet>

      <ApplyModal
        brand={brand}
        open={showApply}
        onClose={() => setShowApply(false)}
        onApply={onApply}
      />
    </>
  );
}

/** Apply modal — separate full-screen overlay with smooth slide-in. */
function ApplyModal({
  brand,
  open,
  onClose,
  onApply,
}: {
  brand: SampleBrand;
  open: boolean;
  onClose: () => void;
  onApply: () => void;
}) {
  const showToast = usePitchToast();
  const [basis, setBasis] = useState<SponsorBasis>(brand.pay_basis);
  const [amount, setAmount] = useState<string>("");
  const [age, setAge] = useState<string>("");
  const [message, setMessage] = useState<string>("");
  const [sending, setSending] = useState<boolean>(false);
  const [sent, setSent] = useState<boolean>(false);

  const closeApply = (): void => {
    setSent(false);
    setAmount("");
    setAge("");
    setMessage("");
    setBasis(brand.pay_basis);
    onClose();
  };

  const submitApply = (): void => {
    setSending(true);
    setTimeout(() => {
      setSending(false);
      setSent(true);
      showToast(`Application sent to ${brand.company_name}`, "success");
      setTimeout(() => {
        onApply();
        closeApply();
      }, 900);
    }, 700);
  };

  if (!open) return null;

  return (
    <PitchSheet open={open} onClose={closeApply} zIndex={90}>
      <div className="flex h-full w-full flex-col overflow-hidden bg-card animate-in slide-in-from-bottom-full duration-300">
        <div className="flex shrink-0 items-start justify-between border-b border-border p-5">
          <div>
            <p className="text-[16px] font-extrabold">Apply for sponsorship</p>
            <p className="text-[12.5px] text-muted-foreground">
              {brand.company_name} can accept, counter with new terms, or pass.
            </p>
          </div>
          <button
            onClick={closeApply}
            aria-label="Close"
            className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary transition-transform active:scale-90"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="min-h-0 flex-1 space-y-4 overflow-y-auto p-5">
          <div>
            <p className="text-[12px] font-bold uppercase tracking-wide text-muted-foreground">
              Collaboration
            </p>
            <div className="mt-1.5 grid grid-cols-3 gap-1.5">
              {BASES.map((b) => (
                <button
                  key={b}
                  onClick={() => setBasis(b)}
                  className={cn(
                    "rounded-full px-3 py-2 text-[12.5px] font-bold transition-colors",
                    basis === b
                      ? "bg-indigo-500 text-white"
                      : "bg-secondary text-muted-foreground"
                  )}
                >
                  {BASIS_LABELS[b]}
                </button>
              ))}
            </div>
          </div>

          <div>
            <p className="text-[12px] font-bold uppercase tracking-wide text-muted-foreground">
              Desired amount
            </p>
            <div className="mt-1.5 flex items-center rounded-xl border border-border bg-background px-3.5">
              <span className="text-[15px] font-semibold text-muted-foreground">$</span>
              <input
                inputMode="decimal"
                value={amount}
                onChange={(e) => setAmount(e.target.value)}
                placeholder="250"
                className="w-full bg-transparent px-2 py-2.5 text-[15px] outline-none placeholder:text-muted-foreground/60"
              />
              <span className="text-[13px] text-muted-foreground">
                {BASIS_SHORT[basis]}
              </span>
            </div>
          </div>

          <div>
            <p className="text-[12px] font-bold uppercase tracking-wide text-muted-foreground">
              Your age
            </p>
            <input
              inputMode="numeric"
              value={age}
              onChange={(e) => setAge(e.target.value)}
              placeholder={String(brand.min_age)}
              className="mt-1.5 w-full rounded-xl border border-border bg-background px-3.5 py-2.5 text-[15px] outline-none placeholder:text-muted-foreground/60"
            />
          </div>

          <div>
            <p className="text-[12px] font-bold uppercase tracking-wide text-muted-foreground">
              Pitch (optional)
            </p>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="Why you're a great fit…"
              rows={3}
              className="mt-1.5 w-full resize-none rounded-xl border border-border bg-background px-3.5 py-2.5 text-[14px] outline-none placeholder:text-muted-foreground/60"
            />
          </div>
        </div>

        <div className="shrink-0 border-t border-border p-5 pb-[max(1.25rem,env(safe-area-inset-bottom))]">
          {sent ? (
            <div className="flex items-center justify-center gap-2 rounded-full bg-emerald-500/10 py-3 text-[14.5px] font-bold text-emerald-600">
              <CheckCircle2 className="h-4 w-4" /> Application sent
            </div>
          ) : (
            <button
              onClick={submitApply}
              disabled={sending || !amount.trim() || !age.trim()}
              className="flex w-full items-center justify-center gap-2 rounded-full bg-indigo-500 py-3 text-[14.5px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
            >
              {sending ? (
                <Loader2 className="h-4 w-4 animate-spin" />
              ) : (
                <Send className="h-4 w-4" />
              )}
              {sending ? "Sending…" : "Send application"}
            </button>
          )}
        </div>
      </div>
    </PitchSheet>
  );
}

/** Compact brand row used in the brands deck "live brands directory" section. */
export function BrandDirectoryRow({ brand }: { brand: SampleBrand }) {
  const pay = typicalPayText(brand);
  const photo = SAMPLE_BRAND_PHOTOS[brand.user_id];
  return (
    <Link
      to="#"
      onClick={(e) => e.preventDefault()}
      className="block rounded-[20px] border border-border bg-card p-4 shadow-sm transition-transform active:scale-[0.99]"
    >
      <div className="flex items-center gap-3.5">
        <div
          className="flex shrink-0 items-center justify-center overflow-hidden rounded-xl bg-secondary"
          style={{ width: 52, height: 52 }}
        >
          {photo ? (
            <img src={photo} alt="" className="h-full w-full object-cover" />
          ) : (
            <Building2 className="h-5 w-5 text-indigo-500/70" />
          )}
        </div>
        <div className="min-w-0 flex-1">
          <div className="flex items-center gap-1.5">
            <p className="truncate text-[15px] font-extrabold">
              {brand.company_name}
            </p>
            <span className="flex h-[17px] w-[17px] items-center justify-center rounded-full bg-indigo-500">
              <Briefcase className="h-2.5 w-2.5 text-white" />
            </span>
            {brand.ember_verified && (
              <span className="inline-flex items-center gap-0.5 rounded-full bg-orange-500/12 px-1.5 py-0.5 text-[10px] font-bold text-orange-500">
                <Flame className="h-2.5 w-2.5" /> Jasper verified
              </span>
            )}
          </div>
          {brand.industry && (
            <p className="truncate text-[12.5px] text-muted-foreground">
              {brand.industry}
            </p>
          )}
          {pay && (
            <p className="text-[12.5px] font-bold text-emerald-600">
              Typically pays {pay}
            </p>
          )}
        </div>
        <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
      </div>
    </Link>
  );
}
