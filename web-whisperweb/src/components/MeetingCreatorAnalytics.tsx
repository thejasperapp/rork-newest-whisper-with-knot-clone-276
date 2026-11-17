/**
 * Creator analytics in meetings — the visual twin of the iOS creator meeting
 * cards. A compact pinned mini card (animated score ring + momentum) everyone
 * sees while a creator shares, and the expanded modal with the full Creator
 * Studio breakdown: score ring, verdict, stat chips, and the top-performing
 * posts as real rows with a tap-through media lightbox.
 */
import { useEffect, useMemo, useState } from "react";
import {
  BarChart3,
  Film,
  Flame,
  Heart,
  Image as ImageIcon,
  Maximize2,
  MessageCircle,
  TrendingDown,
  TrendingUp,
  Users,
  X,
} from "lucide-react";
import { compactCount, timeAgo } from "@/lib/format";
import type {
  CreatorAnalyticsCardPayload,
  CreatorAnalyticsTopPost,
} from "@/lib/creatorMeetingCard";

/** Animated 0-100 ring in the mint→ember Jasper gradient. */
function ScoreRing({
  value,
  size,
  stroke,
  idSuffix,
}: {
  value: number;
  size: number;
  stroke: number;
  idSuffix: string;
}) {
  const [drawn, setDrawn] = useState<boolean>(false);
  useEffect(() => {
    const t = window.setTimeout(() => setDrawn(true), 80);
    return () => window.clearTimeout(t);
  }, []);
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  const frac = Math.max(0, Math.min(1, value / 100));
  const gradId = `creator-ring-${idSuffix}`;
  return (
    <div className="relative shrink-0" style={{ width: size, height: size }}>
      <svg width={size} height={size} className="-rotate-90">
        <defs>
          <linearGradient id={gradId} x1="0%" y1="0%" x2="100%" y2="100%">
            <stop offset="0%" stopColor="#34d399" />
            <stop offset="100%" stopColor="#F39057" />
          </linearGradient>
        </defs>
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke="rgba(255,255,255,0.12)"
          strokeWidth={stroke}
        />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={`url(#${gradId})`}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={c}
          strokeDashoffset={drawn ? c * (1 - frac) : c}
          style={{ transition: "stroke-dashoffset 900ms cubic-bezier(0.22, 1, 0.36, 1)" }}
        />
      </svg>
      <span
        className="absolute inset-0 flex items-center justify-center font-black tabular-nums text-white"
        style={{ fontSize: Math.max(11, size * 0.3) }}
      >
        {Math.round(value)}
      </span>
    </div>
  );
}

function CreatorAvatar({
  url,
  name,
  size,
}: {
  url: string | null | undefined;
  name: string;
  size: number;
}) {
  if (url) {
    return (
      <img
        src={url}
        alt={name}
        loading="lazy"
        className="shrink-0 rounded-full object-cover"
        style={{ width: size, height: size }}
      />
    );
  }
  return (
    <span
      className="flex shrink-0 items-center justify-center rounded-full bg-gradient-to-br from-emerald-400/70 to-[#F39057]/70 font-black text-white"
      style={{ width: size, height: size, fontSize: size * 0.42 }}
    >
      {(name || "?").slice(0, 1).toUpperCase()}
    </span>
  );
}

/** The compact card pinned above the meeting controls while a creator
 *  shares — tap to expand, presenter gets the stop control. */
export function CreatorAnalyticsMiniCard({
  card,
  mine,
  onExpand,
  onStop,
}: {
  card: CreatorAnalyticsCardPayload;
  mine: boolean;
  onExpand: () => void;
  onStop: (() => void) | null;
}) {
  const delta = Math.round(card.followerDelta ?? 0);
  return (
    <div className="present-card-in relative w-[238px]">
      <button
        type="button"
        onClick={onExpand}
        className="flex w-full items-center gap-2.5 rounded-2xl border border-emerald-300/25 bg-zinc-900/95 p-2.5 pr-3 text-left shadow-2xl backdrop-blur transition-transform hover:scale-[1.02] active:scale-[0.99]"
      >
        <ScoreRing value={card.score ?? 0} size={42} stroke={4} idSuffix={`mini-${card.id}`} />
        <span className="min-w-0 flex-1">
          <span className="flex items-center gap-1.5">
            <BarChart3 className="h-3 w-3 shrink-0 text-emerald-300" />
            <span className="truncate text-[12px] font-extrabold text-white">
              @{card.username ?? card.presenterName}
            </span>
          </span>
          <span className="mt-0.5 block truncate text-[10px] font-semibold text-white/55">
            {compactCount(Math.round(card.followers ?? 0))} followers
            {delta !== 0 ? ` · ${delta > 0 ? "+" : ""}${delta} this wk` : ""}
          </span>
          <span className="mt-0.5 flex items-center gap-1 text-[9px] font-bold uppercase tracking-wide text-emerald-300/90">
            <span className="inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
            {mine ? "Your live analytics" : "Live analytics · tap to expand"}
          </span>
        </span>
        <Maximize2 className="h-3.5 w-3.5 shrink-0 text-white/40" />
      </button>
      {mine && onStop && (
        <button
          type="button"
          onClick={onStop}
          className="absolute -right-2 -top-2 flex h-6 w-6 items-center justify-center rounded-full border border-white/20 bg-zinc-800 text-white/70 shadow-lg transition-colors hover:bg-red-500 hover:text-white"
          aria-label="Stop sharing analytics"
          title="Stop sharing"
        >
          <X className="h-3 w-3" />
        </button>
      )}
    </div>
  );
}

function StatChip({
  label,
  value,
  sub,
  subTone,
}: {
  label: string;
  value: string;
  sub?: string | null;
  subTone?: "up" | "down" | null;
}) {
  return (
    <div className="rounded-xl bg-white/5 p-2.5 text-center">
      <p className="text-[16px] font-black tabular-nums text-white">{value}</p>
      <p className="text-[9px] font-semibold uppercase tracking-wide text-white/50">{label}</p>
      {sub ? (
        <p
          className={`mt-0.5 flex items-center justify-center gap-0.5 text-[10px] font-bold ${
            subTone === "down" ? "text-red-400" : "text-emerald-400"
          }`}
        >
          {subTone === "down" ? (
            <TrendingDown className="h-2.5 w-2.5" />
          ) : (
            <TrendingUp className="h-2.5 w-2.5" />
          )}
          {sub}
        </p>
      ) : null}
    </div>
  );
}

function TopPostRow({
  post,
  rank,
  onOpen,
}: {
  post: CreatorAnalyticsTopPost;
  rank: number;
  onOpen: () => void;
}) {
  const thumb = post.mediaUrls?.[0] ?? null;
  const accent = post.accentHex ?? "#34d399";
  const isReel = post.isReel === true;
  return (
    <button
      type="button"
      onClick={onOpen}
      className="flex w-full items-center gap-3 rounded-xl bg-white/5 p-2.5 text-left transition-colors hover:bg-white/10"
    >
      <span className="relative h-12 w-12 shrink-0 overflow-hidden rounded-lg">
        {thumb ? (
          <img src={thumb} alt="" loading="lazy" className="h-full w-full object-cover" />
        ) : (
          <span
            className="flex h-full w-full items-center justify-center"
            style={{ background: `linear-gradient(135deg, ${accent}66, ${accent}22)` }}
          >
            {isReel ? (
              <Film className="h-5 w-5 text-white/90" />
            ) : (
              <ImageIcon className="h-5 w-5 text-white/90" />
            )}
          </span>
        )}
        {isReel && thumb ? (
          <span className="absolute bottom-0.5 right-0.5 rounded bg-black/70 p-0.5">
            <Film className="h-2.5 w-2.5 text-white" />
          </span>
        ) : null}
        <span className="absolute left-0.5 top-0.5 flex h-4 min-w-4 items-center justify-center rounded bg-black/70 px-1 text-[9px] font-black text-emerald-300">
          #{rank}
        </span>
      </span>
      <span className="min-w-0 flex-1">
        <span className="block truncate text-[12px] font-bold text-white">
          {post.caption?.trim() || "(media post)"}
        </span>
        <span className="mt-0.5 flex items-center gap-2 text-[10px] font-semibold text-white/50">
          <span className="flex items-center gap-0.5">
            <Heart className="h-2.5 w-2.5" />
            {compactCount(Math.round(post.likes ?? 0))}
          </span>
          <span className="flex items-center gap-0.5">
            <MessageCircle className="h-2.5 w-2.5" />
            {compactCount(Math.round(post.comments ?? 0))}
          </span>
          <span>{timeAgo(post.createdAt ?? null)}</span>
        </span>
      </span>
      <span className="flex shrink-0 items-center gap-1 rounded-full bg-[#F39057]/15 px-2 py-1 text-[10px] font-black text-[#F39057]">
        <Flame className="h-3 w-3" />
        {Math.round(post.score ?? 0)}
      </span>
    </button>
  );
}

/** Full-screen breakdown of a shared creator card — everyone in the call
 *  can open it; the presenter can stop sharing from the footer. */
export function CreatorAnalyticsModal({
  card,
  mine,
  onClose,
  onStop,
}: {
  card: CreatorAnalyticsCardPayload;
  mine: boolean;
  onClose: () => void;
  onStop: (() => void) | null;
}) {
  const [openPost, setOpenPost] = useState<CreatorAnalyticsTopPost | null>(null);
  const tops = useMemo(() => card.topPosts ?? [], [card.topPosts]);
  const delta = Math.round(card.followerDelta ?? 0);
  const name = card.username ?? card.presenterName;

  return (
    <div
      className="fixed inset-0 z-[60] flex items-center justify-center bg-black/60 p-4 backdrop-blur-sm"
      onClick={onClose}
    >
      <div
        className="flex max-h-[85vh] w-full max-w-md flex-col overflow-hidden rounded-[24px] border border-white/15 bg-zinc-900 shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center justify-between border-b border-white/10 px-4 py-3">
          <div className="flex min-w-0 items-center gap-2">
            <BarChart3 className="h-4 w-4 shrink-0 text-emerald-300" />
            <p className="truncate text-[15px] font-bold text-white">Creator analytics</p>
            <span className="flex shrink-0 items-center gap-1 rounded-full bg-emerald-400/15 px-2 py-0.5 text-[9px] font-black uppercase tracking-wide text-emerald-300">
              <span className="inline-block h-1.5 w-1.5 animate-pulse rounded-full bg-emerald-400" />
              Live
            </span>
          </div>
          <button
            onClick={onClose}
            className="flex h-7 w-7 items-center justify-center rounded-full text-white/60 transition-colors hover:bg-white/10 hover:text-white"
            aria-label="Close"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        <div className="flex-1 space-y-4 overflow-y-auto p-4">
          <div className="flex items-center gap-3">
            <CreatorAvatar url={card.imageUrl} name={name} size={44} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[15px] font-extrabold text-white">@{name}</p>
              <p className="truncate text-[11px] font-semibold text-white/50">
                {mine ? "Your live Creator Studio card" : `Shared live by ${card.presenterName}`}
              </p>
            </div>
            <ScoreRing
              value={card.score ?? 0}
              size={62}
              stroke={6}
              idSuffix={`modal-${card.id}`}
            />
          </div>

          {card.verdict ? (
            <p className="rounded-xl bg-gradient-to-r from-emerald-400/10 to-[#F39057]/10 px-3 py-2.5 text-[12px] font-bold leading-snug text-white/90">
              {card.verdict}
            </p>
          ) : null}

          <div className="grid grid-cols-3 gap-2">
            <StatChip
              label="Followers"
              value={compactCount(Math.round(card.followers ?? 0))}
              sub={delta !== 0 ? `${delta > 0 ? "+" : ""}${delta} wk` : null}
              subTone={delta < 0 ? "down" : "up"}
            />
            <StatChip
              label="Engagement"
              value={`${(card.engagementPct ?? 0).toFixed(1)}%`}
            />
            <StatChip label="Posts 30d" value={String(Math.round(card.posts30 ?? 0))} />
            <StatChip label="Likes 30d" value={compactCount(Math.round(card.likes30 ?? 0))} />
            <StatChip
              label="Comments 30d"
              value={compactCount(Math.round(card.comments30 ?? 0))}
            />
            <StatChip
              label="Formats"
              value={`${Math.round(card.reels ?? 0)}·${Math.round(card.photos ?? 0)}`}
              sub="reels · posts"
            />
          </div>

          {tops.length > 0 ? (
            <div>
              <p className="mb-2 flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-white/50">
                <Flame className="h-3 w-3 text-[#F39057]" />
                Top performing
              </p>
              <div className="space-y-2">
                {tops.map((t, i) => (
                  <TopPostRow key={t.id} post={t} rank={i + 1} onOpen={() => setOpenPost(t)} />
                ))}
              </div>
            </div>
          ) : null}
        </div>

        <div className="border-t border-white/10 p-3">
          {mine && onStop ? (
            <button
              type="button"
              onClick={onStop}
              className="flex h-10 w-full items-center justify-center gap-2 rounded-full bg-red-500/90 text-[13px] font-bold text-white transition-colors hover:bg-red-500"
            >
              <X className="h-4 w-4" />
              Stop sharing
            </button>
          ) : (
            <p className="flex items-center justify-center gap-1.5 text-center text-[11px] font-semibold text-white/45">
              <Users className="h-3 w-3" />
              Everyone in the call sees this live card
            </p>
          )}
        </div>
      </div>

      {openPost && (
        <div
          className="fixed inset-0 z-[70] flex items-center justify-center bg-black/95 p-4"
          onClick={(e) => {
            e.stopPropagation();
            setOpenPost(null);
          }}
        >
          <div className="w-full max-w-md" onClick={(e) => e.stopPropagation()}>
            {openPost.mediaUrls?.[0] ? (
              <img
                src={openPost.mediaUrls[0]}
                alt=""
                className="max-h-[62vh] w-full rounded-2xl object-contain"
              />
            ) : (
              <div
                className="flex h-56 w-full items-center justify-center rounded-2xl"
                style={{
                  background: `linear-gradient(135deg, ${openPost.accentHex ?? "#34d399"}55, ${openPost.accentHex ?? "#34d399"}18)`,
                }}
              >
                {openPost.isReel ? (
                  <Film className="h-10 w-10 text-white/80" />
                ) : (
                  <ImageIcon className="h-10 w-10 text-white/80" />
                )}
              </div>
            )}
            <div className="mt-3 rounded-2xl border border-white/10 bg-zinc-900/95 p-3">
              <p className="text-[13px] font-bold leading-snug text-white">
                {openPost.caption?.trim() || "(media post)"}
              </p>
              <div className="mt-2 flex items-center gap-3 text-[11px] font-semibold text-white/55">
                <span className="flex items-center gap-1">
                  <Heart className="h-3 w-3 text-red-400" />
                  {compactCount(Math.round(openPost.likes ?? 0))} likes
                </span>
                <span className="flex items-center gap-1">
                  <MessageCircle className="h-3 w-3" />
                  {compactCount(Math.round(openPost.comments ?? 0))} comments
                </span>
                <span>{timeAgo(openPost.createdAt ?? null)}</span>
                <span className="ml-auto flex items-center gap-1 text-[#F39057]">
                  <Flame className="h-3 w-3" />
                  {Math.round(openPost.score ?? 0)}
                </span>
              </div>
            </div>
            <button
              type="button"
              onClick={() => setOpenPost(null)}
              className="mx-auto mt-3 flex h-9 items-center justify-center gap-1.5 rounded-full bg-white/10 px-5 text-[12px] font-bold text-white transition-colors hover:bg-white/20"
            >
              <X className="h-3.5 w-3.5" />
              Close
            </button>
          </div>
        </div>
      )}
    </div>
  );
}
