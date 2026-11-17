import { useState } from "react";
import { usePitchReset, usePitchToast } from "@/components/pitch/PitchContext";
import {
  ArrowLeft,
  Briefcase,
  Building2,
  CheckCircle2,
  ChevronRight,
  Flame,
  Handshake,
  Heart,
  Loader2,
  Lock,
  MessageCircle,
  Pencil,
  ShieldAlert,
  ShieldCheck,
  ShieldX,
  Undo2,
} from "lucide-react";

import {
  BASIS_LABELS,
  formatSponsorAmount,
  type SponsorBasis,
} from "@/lib/brands";
import {
  SAMPLE_BRANDS,
  SAMPLE_BRAND_APPLICATIONS,
  SAMPLE_BRAND_DEALS,
  SAMPLE_BRAND_PAYMENTS,
  SAMPLE_BRAND_POSTS,
  SAMPLE_BRAND_PHOTOS,
  formatUsd,
  type SampleApplication,
  type SampleBrand,
} from "@/lib/pitch";
import { cn } from "@/lib/utils";

const BASES: SponsorBasis[] = ["per_post", "per_month", "per_year"];

function StatusPill({ status }: { status: string }) {
  const styles: Record<string, string> = {
    pending: "bg-amber-500/15 text-amber-600",
    countered: "bg-indigo-500/15 text-indigo-500",
    accepted: "bg-emerald-500/15 text-emerald-600",
    active: "bg-emerald-500/15 text-emerald-600",
    released: "bg-emerald-500/15 text-emerald-600",
    denied: "bg-red-500/15 text-red-500",
    withdrawn: "bg-muted text-muted-foreground",
  };
  const labels: Record<string, string> = {
    countered: "New terms",
    released: "Released",
  };
  return (
    <span
      className={cn(
        "rounded-full px-2.5 py-0.5 text-[11px] font-bold capitalize",
        styles[status] ?? "bg-muted text-muted-foreground"
      )}
    >
      {labels[status] ?? status}
    </span>
  );
}

/**
 * Brand dashboard demo for Pitch Mode — the brand-side view of sponsorships.
 * Mirrors /brand/dashboard exactly: header with brand avatar + edit affordance,
 * the Applications section (with the editable terms form — accept / counter /
 * deny), the Deals section (with escrow funding, tracked-post reach, dispute),
 * and the History list. The brand selector at the top lets a pitch switch
 * between the 3 sample brands so prospects see how their dashboard scales.
 * Every action is local demo state — nothing posts.
 */
export function BrandDashboardDemo() {
  const [activeBrandId, setActiveBrandId] = useState<string>(SAMPLE_BRANDS[0].user_id);
  const [apps, setApps] = useState<SampleApplication[]>(SAMPLE_BRAND_APPLICATIONS);
  const [fundingDealId, setFundingDealId] = useState<string | null>(null);
  const showToast = usePitchToast();
  usePitchReset(() => {
    setActiveBrandId(SAMPLE_BRANDS[0].user_id);
    setApps(SAMPLE_BRAND_APPLICATIONS);
    setFundingDealId(null);
  });

  const activeBrand = SAMPLE_BRANDS.find((b) => b.user_id === activeBrandId) ?? SAMPLE_BRANDS[0];
  const myApps = apps.filter((a) => a.brand_user_id === activeBrandId);
  const open = myApps.filter((a) => ["pending", "countered"].includes(a.status));
  const decided = myApps.filter((a) => !["pending", "countered"].includes(a.status));
  const myDeals = SAMPLE_BRAND_DEALS.filter((d) => d.brand_user_id === activeBrandId);

  const respond = (id: string, action: "accept" | "deny" | "counter"): void => {
    const app = apps.find((a) => a.id === id);
    const actionLabel = action === "accept" ? "accepted" : action === "deny" ? "denied" : "countered";
    if (app) showToast(`${app.creator_username ?? "Creator"} ${actionLabel}`, "success");
    setApps((prev) =>
      prev.map((a) =>
        a.id === id
          ? {
              ...a,
              status:
                action === "accept"
                  ? "accepted"
                  : action === "deny"
                    ? "denied"
                    : "countered",
            }
          : a
      )
    );
  };

  const activeBrandPhoto = SAMPLE_BRAND_PHOTOS[activeBrandId];

  return (
    <div className="space-y-5">
      {/* Brand switcher — pick which sample brand dashboard to show */}
      <div className="no-scrollbar -mx-1 flex gap-2 overflow-x-auto px-1 pb-1">
        {SAMPLE_BRANDS.map((b) => {
          const photo = SAMPLE_BRAND_PHOTOS[b.user_id];
          const active = b.user_id === activeBrandId;
          return (
            <button
              key={b.user_id}
              onClick={() => setActiveBrandId(b.user_id)}
              className={cn(
                "flex shrink-0 items-center gap-2 rounded-full border py-1.5 pl-1.5 pr-3.5 text-[12.5px] font-bold transition-all active:scale-[0.98]",
                active
                  ? "border-foreground bg-foreground text-background"
                  : "border-border bg-card text-foreground/70 hover:text-foreground"
              )}
            >
              <span
                className="flex h-7 w-7 items-center justify-center overflow-hidden rounded-full bg-secondary"
              >
                {photo ? (
                  <img
                    src={photo}
                    alt=""
                    className="h-full w-full object-cover"
                  />
                ) : (
                  <Building2 className="h-3.5 w-3.5" />
                )}
              </span>
              {b.company_name}
            </button>
          );
        })}
      </div>

      {/* Brand dashboard header — mirrors the real page */}
      <div className="flex items-center justify-between">
        <div className="flex items-center gap-3">
          <div
            className="flex shrink-0 items-center justify-center overflow-hidden rounded-2xl bg-secondary"
            style={{ width: 48, height: 48 }}
          >
            {activeBrandPhoto ? (
              <img src={activeBrandPhoto} alt="" className="h-full w-full object-cover" />
            ) : (
              <Building2 className="h-5 w-5 text-indigo-500/70" />
            )}
          </div>
          <div>
            <h1 className="text-[18px] font-black leading-tight">
              {activeBrand.company_name} dashboard
            </h1>
            <p className="text-[13px] text-muted-foreground">
              Applications, deals, and escrow payments.
            </p>
          </div>
        </div>
        <span className="flex h-10 w-10 items-center justify-center rounded-full border border-border bg-card">
          <Pencil className="h-4 w-4" />
        </span>
      </div>

      {/* Applications section */}
      <div className="space-y-2.5">
        <p className="text-[14px] font-extrabold">
          Applications{" "}
          <span className="ml-1 rounded-full bg-indigo-500 px-2 py-0.5 text-[11px] font-bold text-white">
            {open.length}
          </span>
        </p>
        {open.length === 0 ? (
          <p className="rounded-[16px] border border-border bg-card p-4 text-[13px] text-muted-foreground">
            No open applications. Creators who meet your requirements can apply
            from your brand profile.
          </p>
        ) : (
          open.map((app) => (
            <ApplicationCard
              key={app.id}
              app={app}
              onRespond={respond}
            />
          ))
        )}
      </div>

      {/* Deals section */}
      <div className="space-y-2.5">
        <p className="text-[14px] font-extrabold">
          Deals{" "}
          <span className="ml-1 rounded-full bg-emerald-600 px-2 py-0.5 text-[11px] font-bold text-white">
            {myDeals.length}
          </span>
        </p>
        {myDeals.length === 0 ? (
          <p className="rounded-[16px] border border-border bg-card p-4 text-[13px] text-muted-foreground">
            Accepted applications become deals here — fund them into escrow and
            watch tracked posts land.
          </p>
        ) : (
          myDeals.map((deal) => {
            const payments = SAMPLE_BRAND_PAYMENTS.filter((p) => p.deal_id === deal.id);
            const posts = SAMPLE_BRAND_POSTS.filter((p) => p.deal_id === deal.id);
            return (
              <BrandDealCard
                key={deal.id}
                deal={deal}
                payments={payments}
                posts={posts}
                funding={fundingDealId === deal.id}
                onFund={() => {
                  setFundingDealId(deal.id);
                  showToast(`Funding ${deal.amount_cents / 100} into escrow for @${deal.creator_username ?? "creator"}`, "success");
                  setTimeout(() => setFundingDealId(null), 1200);
                }}
              />
            );
          })
        )}
      </div>

      {/* History */}
      {decided.length > 0 && (
        <div className="space-y-2">
          <p className="text-[14px] font-extrabold">History</p>
          <div className="space-y-2">
            {decided.map((app) => (
              <div
                key={app.id}
                className="flex items-center justify-between rounded-[14px] border border-border bg-card px-4 py-2.5"
              >
                <p className="text-[13px] font-semibold">
                  @{app.creator_username ?? "creator"}
                </p>
                <StatusPill status={app.status} />
              </div>
            ))}
          </div>
        </div>
      )}

      <p className="text-center text-[11px] text-muted-foreground">
        Sample dashboard for presentation · no real Stripe checkout, no real
        escrow transfers
      </p>
    </div>
  );
}

/** Real ApplicationCard layout from BrandDashboard — accept / counter / deny. */
function ApplicationCard({
  app,
  onRespond,
}: {
  app: SampleApplication;
  onRespond: (id: string, action: "accept" | "deny" | "counter") => void;
}) {
  const [basis, setBasis] = useState<SponsorBasis>(app.terms_basis ?? app.desired_basis);
  const [amount, setAmount] = useState<string>(
    String((app.terms_amount_cents ?? app.desired_amount_cents) / 100)
  );
  const [notes, setNotes] = useState<string>(app.terms_notes ?? "");
  const [deliverables, setDeliverables] = useState<string>(app.terms_deliverables ?? "");
  const [exclusive, setExclusive] = useState<boolean>(app.terms_exclusive === true);
  const [acting, setActing] = useState<"accept" | "deny" | "counter" | null>(null);

  const act = (action: "accept" | "deny" | "counter"): void => {
    setActing(action);
    setTimeout(() => {
      onRespond(app.id, action);
      setActing(null);
    }, 500);
  };

  return (
    <div className="rounded-[20px] border border-border bg-card p-4">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="text-[15px] font-extrabold">@{app.creator_username ?? "creator"}</p>
          <p className="text-[12.5px] text-muted-foreground">
            {app.creator_followers != null &&
              `${app.creator_followers.toLocaleString()} followers`}
            {app.creator_age != null && ` · ${app.creator_age} yrs`}
          </p>
          <p className="mt-1 text-[13px] font-bold text-indigo-500">
            Asking {formatSponsorAmount(app.desired_amount_cents, app.desired_basis)}
          </p>
        </div>
        <StatusPill status={app.status} />
      </div>

      {app.message && (
        <p className="mt-2 rounded-xl bg-secondary/60 p-3 text-[13px] leading-snug text-muted-foreground">
          {app.message}
        </p>
      )}

      <p className="mt-3.5 text-[12px] font-bold uppercase tracking-wide text-muted-foreground">
        Terms (edit to counter)
      </p>
      <div className="mt-1.5 grid grid-cols-3 gap-1.5">
        {BASES.map((b) => (
          <button
            key={b}
            onClick={() => setBasis(b)}
            className={cn(
              "rounded-full px-2 py-1.5 text-[12px] font-bold transition-colors",
              basis === b ? "bg-indigo-500 text-white" : "bg-secondary text-muted-foreground"
            )}
          >
            {BASIS_LABELS[b]}
          </button>
        ))}
      </div>
      <div className="mt-2 flex items-center rounded-xl border border-border bg-background px-3.5">
        <span className="text-[14px] font-semibold text-muted-foreground">$</span>
        <input
          inputMode="decimal"
          value={amount}
          onChange={(e) => setAmount(e.target.value)}
          className="w-full bg-transparent px-2 py-2.5 text-[14.5px] outline-none"
        />
      </div>
      <textarea
        value={deliverables}
        onChange={(e) => setDeliverables(e.target.value)}
        placeholder="Deliverables brief — e.g. 2 feed posts + 1 story, product visible, tag @yourbrand…"
        rows={2}
        className="mt-2 w-full resize-none rounded-xl border border-border bg-background px-3.5 py-2.5 text-[13.5px] outline-none placeholder:text-muted-foreground/60"
      />
      <textarea
        value={notes}
        onChange={(e) => setNotes(e.target.value)}
        placeholder="Other notes — timelines, usage rights…"
        rows={2}
        className="mt-2 w-full resize-none rounded-xl border border-border bg-background px-3.5 py-2.5 text-[13.5px] outline-none placeholder:text-muted-foreground/60"
      />
      <div className="mt-2 flex flex-wrap items-center gap-2">
        <button
          onClick={() => setExclusive((v) => !v)}
          className={cn(
            "rounded-full border px-3 py-1.5 text-[12px] font-bold transition-colors",
            exclusive
              ? "border-indigo-500/50 bg-indigo-500/10 text-indigo-500"
              : "border-border text-muted-foreground"
          )}
        >
          {exclusive ? "✓ " : ""}Exclusivity clause
        </button>
      </div>

      <div className="mt-3 grid grid-cols-3 gap-1.5">
        <button
          onClick={() => act("accept")}
          disabled={acting !== null}
          className="flex items-center justify-center gap-1 rounded-full bg-emerald-600 py-2.5 text-[12.5px] font-bold text-white transition-transform active:scale-[0.97] disabled:opacity-40"
        >
          {acting === "accept" ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <CheckCircle2 className="h-3.5 w-3.5" />
          )}
          Accept
        </button>
        <button
          onClick={() => act("counter")}
          disabled={acting !== null}
          className="flex items-center justify-center gap-1 rounded-full bg-indigo-500 py-2.5 text-[12.5px] font-bold text-white transition-transform active:scale-[0.97] disabled:opacity-40"
        >
          {acting === "counter" ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <Undo2 className="h-3.5 w-3.5" />
          )}
          Counter
        </button>
        <button
          onClick={() => act("deny")}
          disabled={acting !== null}
          className="flex items-center justify-center gap-1 rounded-full bg-red-500/10 py-2.5 text-[12.5px] font-bold text-red-500 transition-transform active:scale-[0.97] disabled:opacity-40"
        >
          {acting === "deny" ? (
            <Loader2 className="h-3.5 w-3.5 animate-spin" />
          ) : (
            <ShieldX className="h-3.5 w-3.5" />
          )}
          Deny
        </button>
      </div>
      {app.status === "denied" && (
        <p className="mt-2 text-[11px] text-muted-foreground">
          In production: denying also DM-blocks this creator from your brand.
        </p>
      )}
    </div>
  );
}

/** Real DealCard layout from BrandDashboard — escrow funding + tracked posts. */
function BrandDealCard({
  deal,
  payments,
  posts,
  funding,
  onFund,
}: {
  deal: typeof SAMPLE_BRAND_DEALS[number];
  payments: typeof SAMPLE_BRAND_PAYMENTS;
  posts: typeof SAMPLE_BRAND_POSTS;
  funding: boolean;
  onFund: () => void;
}) {
  const pending = payments.filter((p) => p.status === "pending");
  const released = payments.filter((p) => p.status === "released");
  const totalLikes = posts.reduce((s, p) => s + (p.likes_count ?? 0), 0);
  const totalComments = posts.reduce((s, p) => s + (p.comments_count ?? 0), 0);
  const fmt = (c: number) => formatUsd(c);

  return (
    <div className="rounded-[20px] border border-border bg-card p-4">
      <div className="flex items-start justify-between gap-2">
        <div>
          <p className="text-[15px] font-extrabold">@{deal.creator_username ?? "creator"}</p>
          <p className="text-[13px] font-bold text-indigo-500">
            {formatSponsorAmount(deal.amount_cents, deal.basis)}
          </p>
        </div>
        <StatusPill status={deal.status} />
      </div>

      <div className="mt-3 grid grid-cols-3 gap-2 text-center">
        <div className="rounded-xl bg-secondary/60 py-2">
          <p className="text-[15px] font-black text-amber-600">{pending.length}</p>
          <p className="text-[11px] text-muted-foreground">In escrow</p>
        </div>
        <div className="rounded-xl bg-secondary/60 py-2">
          <p className="text-[15px] font-black text-emerald-600">{released.length}</p>
          <p className="text-[11px] text-muted-foreground">Released</p>
        </div>
        <div className="rounded-xl bg-secondary/60 py-2">
          <p className="text-[15px] font-black">{posts.length}</p>
          <p className="text-[11px] text-muted-foreground">Posts live</p>
        </div>
      </div>

      {(deal.deliverables || deal.exclusive) && (
        <div className="mt-2.5 rounded-xl bg-secondary/60 p-3">
          {deal.exclusive && (
            <p className="text-[11.5px] font-bold text-indigo-500">Exclusive partnership</p>
          )}
          {deal.deliverables && (
            <p className="text-[12px] leading-snug text-muted-foreground">
              <span className="font-bold text-foreground">Deliverables:</span>{" "}
              {deal.deliverables}
            </p>
          )}
        </div>
      )}

      {posts.length > 0 && (
        <div className="mt-2.5 flex items-center gap-3 rounded-xl bg-secondary/60 px-3 py-2">
          <p className="text-[11.5px] font-bold">Verified reach</p>
          <span className="inline-flex items-center gap-1 text-[11.5px] text-muted-foreground">
            <Heart className="h-3 w-3 text-red-500" /> {totalLikes.toLocaleString()}
          </span>
          <span className="inline-flex items-center gap-1 text-[11.5px] text-muted-foreground">
            <MessageCircle className="h-3 w-3 text-indigo-500" />{" "}
            {totalComments.toLocaleString()}
          </span>
        </div>
      )}

      {pending.length > 0 && (
        <div className="mt-2.5 space-y-1.5">
          {pending.map((p) => (
            <div
              key={p.id}
              className="flex items-center justify-between rounded-xl border border-amber-500/25 bg-amber-500/5 px-3 py-2"
            >
              <p className="text-[12px] font-bold text-amber-600">
                {fmt(p.gross_cents)} in escrow
                {p.requires_post ? " · awaiting post" : ""}
              </p>
              <span className="inline-flex items-center gap-1 rounded-full bg-red-500/10 px-2.5 py-1 text-[11px] font-bold text-red-500">
                <ShieldAlert className="h-3 w-3" /> Dispute & refund
              </span>
            </div>
          ))}
        </div>
      )}

      <p className="mt-2.5 text-[11.5px] leading-snug text-muted-foreground">
        {deal.basis === "per_post"
          ? "Funds are held by Whisper and release to the creator as each sponsored post goes live."
          : "Funds are held by Whisper and release at the end of the week once the creator's posts are verified."}
      </p>

      {deal.status === "active" && (
        <button
          onClick={onFund}
          disabled={funding}
          className="mt-3 flex w-full items-center justify-center gap-2 rounded-full bg-emerald-600 py-2.5 text-[13px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-40"
        >
          {funding ? (
            <Loader2 className="h-4 w-4 animate-spin" />
          ) : (
            <Lock className="h-3.5 w-3.5" />
          )}
          {funding
            ? "Opening Stripe Checkout…"
            : `Fund ${formatSponsorAmount(deal.amount_cents, deal.basis).split(" ")[0]} into escrow`}
        </button>
      )}
    </div>
  );
}

/** Compact "how brands see it" teaser row for the brands deck intro. */
export function BrandDirectoryTeaser({ brand }: { brand: SampleBrand }) {
  const photo = SAMPLE_BRAND_PHOTOS[brand.user_id];
  return (
    <div className="flex items-center gap-3 rounded-[20px] border border-border bg-card p-4 shadow-sm">
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
          <p className="truncate text-[15px] font-extrabold">{brand.company_name}</p>
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
          <p className="truncate text-[12.5px] text-muted-foreground">{brand.industry}</p>
        )}
      </div>
      <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />
    </div>
  );
}

/** The "post your sponsorship" CTA card shown at the top of the brands deck. */
export function BrandSignupTeaser() {
  return (
    <div className="rounded-[20px] border border-indigo-500/25 bg-indigo-500/5 p-4">
      <p className="text-[14px] font-extrabold">Are you a company?</p>
      <p className="mt-1 text-[12.5px] leading-snug text-muted-foreground">
        Create a brand profile, set your sponsorship requirements, and let
        eligible creators apply — payments stay in escrow until posts go live.
      </p>
      <div className="mt-3 flex gap-2">
        <span className="inline-flex items-center gap-1.5 rounded-full bg-indigo-500 px-4 py-2 text-[13px] font-bold text-white">
          <Briefcase className="h-3.5 w-3.5" /> Create brand profile
        </span>
        <span className="inline-flex items-center rounded-full border border-border bg-card px-4 py-2 text-[13px] font-bold">
          Brand dashboard
        </span>
      </div>
    </div>
  );
}

/** The "no brands yet" empty state shown in the brands deck intro. */
export function BrandsEmptyTeaser() {
  return (
    <div className="py-12 text-center">
      <Handshake className="mx-auto h-8 w-8 text-muted-foreground" />
      <p className="mt-3 text-[15px] font-bold">No brands yet</p>
      <p className="mx-auto mt-1 max-w-xs text-[13px] text-muted-foreground">
        Brands that join Whisper appear here with their requirements and
        typical pay — so you always know what a partnership is worth before you
        apply.
      </p>
    </div>
  );
}

/** The Ember brand-check explainer card for the brands deck. */
export function EmberBrandCheckTeaser() {
  return (
    <div className="rounded-[20px] border border-orange-500/25 bg-orange-500/5 p-4">
      <div className="flex items-center gap-1.5">
        <Flame className="h-4 w-4 text-orange-500" />
        <p className="text-[13.5px] font-extrabold">Jasper brand check</p>
      </div>
      <p className="mt-1.5 text-[12.5px] leading-snug text-muted-foreground">
        Every brand on Whisper is Jasper-checked: we verify the company, the
        product line, and their payout history before they can sponsor anyone.
        A score out of 100 shows up on their profile so creators know who they're
        dealing with before they apply.
      </p>
      <p className="mt-2 flex items-center gap-1.5 text-[11.5px] font-bold text-orange-500">
        <ShieldCheck className="h-3.5 w-3.5" /> Creators never chase an invoice
      </p>
    </div>
  );
}

/** A small "back" affordance re-used by the brands deck's section headers. */
export function PitchBackButton({ onClick }: { onClick: () => void }) {
  return (
    <button
      onClick={onClick}
      aria-label="Back"
      className="flex h-9 w-9 items-center justify-center rounded-full bg-secondary transition-transform active:scale-90"
    >
      <ArrowLeft className="h-5 w-5" />
    </button>
  );
}
