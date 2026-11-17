import { useCallback, useMemo, useRef, useState } from "react";
import {
  CheckSquare,
  ChevronLeft,
  ChevronRight,
  Flame,
  Sparkles,
  Target,
  TrendingUp,
} from "lucide-react";

import { EmberMascot } from "@/components/EmberMascot";
import { loadCoachMode } from "@/lib/emberBrain";
import type { DeckMomentKind, JasperPitchDeck } from "@/lib/pitchDeck";

/**
 * Jasper's pitch deck, INLINE in the notes — a real notebook you flip through
 * right where the meeting notes live (no separate popup): a small stack of
 * cream ruled pages with Jasper peeking from BEHIND the top edge, a red
 * margin line, serif ink headings, and highlighter sweeps. Swipe, dots, and
 * the edge chevrons all turn pages.
 */

const PAPER = "#FBF7EC";
const PAPER_LINE = "#E9E0C8";
const PAPER_EDGE = "#EFE7D2";
const PAPER_EDGE_2 = "#F5EEDC";
const MARGIN_RED = "#E5A7A0";
const INK = "#20242B";
const INK_SOFT = "#5C5A50";
const MINT_DEEP = "#0E9F76";
const HI_MINT = "#BDF3DC";
const HI_AMBER = "#FBE7AE";
const HI_ROSE = "#F9D3CB";

const paperStyle: React.CSSProperties = {
  background: `repeating-linear-gradient(${PAPER} 0px, ${PAPER} 27px, ${PAPER_LINE} 27px, ${PAPER_LINE} 28px)`,
  backgroundColor: PAPER,
  color: INK,
};

function momentTint(kind: DeckMomentKind): { bg: string; label: string; ink: string } {
  if (kind === "objection") return { bg: HI_AMBER, label: "OBJECTION", ink: "#8A6A12" };
  if (kind === "signal") return { bg: HI_MINT, label: "BUYING SIGNAL", ink: "#0B7A5B" };
  return { bg: HI_ROSE, label: "INTEREST", ink: "#A05246" };
}

/** A highlighter sweep — slightly rotated so it reads hand-marked. */
function Hi({ children, color = HI_MINT }: { children: React.ReactNode; color?: string }) {
  return (
    <span
      className="-mx-0.5 inline px-1.5 py-0.5"
      style={{
        background: `linear-gradient(100deg, transparent 0%, ${color} 3%, ${color} 97%, transparent 100%)`,
        boxDecorationBreak: "clone",
        WebkitBoxDecorationBreak: "clone",
        borderRadius: 3,
      }}
    >
      {children}
    </span>
  );
}

function Kicker({ children }: { children: React.ReactNode }) {
  return (
    <p
      className="text-[10px] font-black uppercase tracking-[0.22em]"
      style={{ color: MINT_DEEP }}
    >
      {children}
    </p>
  );
}

function SerifTitle({ children, size = 24 }: { children: React.ReactNode; size?: number }) {
  return (
    <h2
      className="mt-1.5 font-extrabold leading-[1.12]"
      style={{ fontFamily: 'Georgia, "Times New Roman", serif', fontSize: size, color: INK }}
    >
      {children}
    </h2>
  );
}

export function PitchDeckInline({ deck }: { deck: JasperPitchDeck }) {
  const mode = loadCoachMode();
  const [page, setPage] = useState<number>(0);
  const [dir, setDir] = useState<1 | -1>(1);
  const touchX = useRef<number | null>(null);

  const deckDate = useMemo(
    () =>
      new Date(deck.generatedAt || Date.now()).toLocaleDateString(undefined, {
        month: "long",
        day: "numeric",
        year: "numeric",
      }),
    [deck.generatedAt]
  );

  const laneLabel =
    deck.placement === "coach" ? "Coach lane" : deck.placement === "athlete" ? "Athlete lane" : "Creator lane";

  /** Page builder — sections only render when the deck actually has them. */
  const pages = useMemo(() => {
    const out: { key: string; node: React.ReactNode }[] = [];

    out.push({
      key: "cover",
      node: (
        <div className="flex h-full flex-col">
          <Kicker>Jasper's pitch deck</Kicker>
          <h1
            className="mt-3 font-extrabold leading-[1.04]"
            style={{ fontFamily: 'Georgia, "Times New Roman", serif', fontSize: 34, color: INK }}
          >
            {deck.prospectName}
          </h1>
          <p className="mt-2 text-[12px] font-semibold" style={{ color: INK_SOFT }}>
            {deck.meetingTitle} · {deckDate}
          </p>
          <span
            className="mt-3 inline-flex w-fit items-center gap-1.5 rounded-full px-3 py-1 text-[10.5px] font-black uppercase tracking-wide"
            style={{ background: `${MINT_DEEP}1A`, color: MINT_DEEP, border: `1px solid ${MINT_DEEP}40` }}
          >
            <Target className="h-3 w-3" /> {laneLabel}
          </span>
          <div className="mt-auto pb-2">
            <p className="text-[11px] font-black uppercase tracking-[0.16em]" style={{ color: INK_SOFT }}>
              The angle
            </p>
            <p
              className="mt-2 text-[17.5px] font-bold leading-snug"
              style={{ fontFamily: 'Georgia, "Times New Roman", serif' }}
            >
              <Hi>{deck.headline}</Hi>
            </p>
            <p className="mt-4 text-[11px] leading-relaxed" style={{ color: INK_SOFT }}>
              Drafted by Jasper from what was actually said in the meeting — flip through for the read,
              the plan, and your close odds.
            </p>
          </div>
        </div>
      ),
    });

    if (deck.interests.length > 0) {
      out.push({
        key: "read",
        node: (
          <div>
            <Kicker>The read</Kicker>
            <SerifTitle>What {deck.prospectName.split(" ")[0]} actually cares about</SerifTitle>
            <div className="mt-4 space-y-2.5">
              {deck.interests.map((it, i) => (
                <div key={i} className="flex items-start gap-2.5">
                  <span
                    className="mt-[3px] flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10px] font-black text-white"
                    style={{ background: MINT_DEEP }}
                  >
                    {i + 1}
                  </span>
                  <p className="text-[14px] font-semibold leading-relaxed">
                    <Hi color={i === 0 ? HI_MINT : "transparent"}>{it}</Hi>
                  </p>
                </div>
              ))}
            </div>
            <p className="mt-5 text-[11px] leading-relaxed" style={{ color: INK_SOFT }}>
              Pitch to these — in their words, not yours. The first one is the door.
            </p>
          </div>
        ),
      });
    }

    if (deck.keyMoments.length > 0) {
      out.push({
        key: "moments",
        node: (
          <div>
            <Kicker>Key moments</Kicker>
            <SerifTitle>Highlighted from the call</SerifTitle>
            <div className="mt-4 space-y-4">
              {deck.keyMoments.slice(0, 4).map((m, i) => {
                const tint = momentTint(m.kind);
                return (
                  <div key={i}>
                    <div className="flex items-center gap-1.5">
                      <span
                        className="rounded-[4px] px-1.5 py-0.5 text-[8.5px] font-black tracking-[0.08em]"
                        style={{ background: tint.bg, color: tint.ink }}
                      >
                        {tint.label}
                      </span>
                      <span className="text-[10px] font-bold" style={{ color: INK_SOFT }}>
                        @{m.speaker}
                      </span>
                    </div>
                    <p
                      className="mt-1.5 text-[13.5px] font-semibold leading-snug"
                      style={{ fontFamily: 'Georgia, "Times New Roman", serif' }}
                    >
                      <Hi color={tint.bg}>“{m.quote}”</Hi>
                    </p>
                    {m.note && (
                      <p className="mt-1 text-[11px] italic leading-snug" style={{ color: INK_SOFT }}>
                        ↳ {m.note}
                      </p>
                    )}
                  </div>
                );
              })}
            </div>
          </div>
        ),
      });
    }

    deck.slides.forEach((slide, si) => {
      out.push({
        key: `slide-${si}`,
        node: (
          <div>
            <Kicker>
              The play · {si + 1} of {deck.slides.length}
            </Kicker>
            <SerifTitle>{slide.title}</SerifTitle>
            <div className="mt-4 space-y-3">
              {slide.bullets.map((b, i) => (
                <div key={i} className="flex items-start gap-2.5">
                  <Sparkles className="mt-[3px] h-4 w-4 shrink-0" style={{ color: MINT_DEEP }} />
                  <p className="text-[14px] font-semibold leading-relaxed">{b}</p>
                </div>
              ))}
            </div>
          </div>
        ),
      });
    });

    if (deck.closePlan.length > 0) {
      out.push({
        key: "plan",
        node: (
          <div>
            <Kicker>The close plan</Kicker>
            <SerifTitle>Run it in this order</SerifTitle>
            <div className="mt-4 space-y-3.5">
              {deck.closePlan.map((s, i) => (
                <div key={i} className="flex items-start gap-2.5">
                  <span
                    className="mt-[1px] flex h-6 w-6 shrink-0 items-center justify-center rounded-full text-[11px] font-black text-white"
                    style={{ background: INK }}
                  >
                    {i + 1}
                  </span>
                  <div className="min-w-0">
                    <p className="text-[13.5px] font-extrabold leading-snug">{s.step}</p>
                    {s.detail && (
                      <p className="mt-0.5 text-[11.5px] leading-snug" style={{ color: INK_SOFT }}>
                        {s.detail}
                      </p>
                    )}
                  </div>
                </div>
              ))}
            </div>
          </div>
        ),
      });
    }

    out.push({
      key: "odds",
      node: (
        <div className="flex h-full flex-col">
          <Kicker>Close probability</Kicker>
          <SerifTitle>The honest odds</SerifTitle>
          <div className="mt-5 space-y-5">
            <div>
              <div className="flex items-end justify-between">
                <p className="text-[11px] font-black uppercase tracking-[0.12em]" style={{ color: MINT_DEEP }}>
                  If the plan is followed
                </p>
                <p
                  className="text-[40px] font-black leading-none"
                  style={{ fontFamily: 'Georgia, "Times New Roman", serif', color: MINT_DEEP }}
                >
                  {deck.closeRate.withPlan}
                  <span className="text-[15px]">%</span>
                </p>
              </div>
              <div className="mt-1.5 h-3 overflow-hidden rounded-full" style={{ background: "#E8E0CB" }}>
                <div
                  className="h-full rounded-full transition-[width] duration-700"
                  style={{
                    width: `${Math.max(4, deck.closeRate.withPlan)}%`,
                    background: `linear-gradient(90deg, ${MINT_DEEP}, #35C08F)`,
                  }}
                />
              </div>
            </div>
            <div>
              <div className="flex items-end justify-between">
                <p className="text-[11px] font-black uppercase tracking-[0.12em]" style={{ color: "#B0543F" }}>
                  If it's winged
                </p>
                <p
                  className="text-[30px] font-black leading-none"
                  style={{ fontFamily: 'Georgia, "Times New Roman", serif', color: "#B0543F" }}
                >
                  {deck.closeRate.withoutPlan}
                  <span className="text-[13px]">%</span>
                </p>
              </div>
              <div className="mt-1.5 h-3 overflow-hidden rounded-full" style={{ background: "#E8E0CB" }}>
                <div
                  className="h-full rounded-full transition-[width] duration-700"
                  style={{
                    width: `${Math.max(4, deck.closeRate.withoutPlan)}%`,
                    background: "linear-gradient(90deg, #C96A52, #B0543F)",
                  }}
                />
              </div>
            </div>
            <span
              className="inline-flex w-fit items-center gap-1.5 rounded-full px-3 py-1 text-[11px] font-black"
              style={{ background: `${MINT_DEEP}14`, color: MINT_DEEP, border: `1px solid ${MINT_DEEP}35` }}
            >
              <TrendingUp className="h-3.5 w-3.5" /> +
              {Math.max(0, deck.closeRate.withPlan - deck.closeRate.withoutPlan)} points for running the plan
            </span>
          </div>
          {deck.closeRate.why && (
            <p className="mt-auto pt-4 text-[12px] italic leading-relaxed" style={{ color: INK_SOFT }}>
              “{deck.closeRate.why}”
            </p>
          )}
        </div>
      ),
    });

    if (deck.impactMoments.length > 0) {
      out.push({
        key: "impact",
        node: (
          <div>
            <Kicker>Your highest impact</Kicker>
            <SerifTitle>The moments you landed</SerifTitle>
            <div className="mt-4 space-y-4">
              {deck.impactMoments.slice(0, 3).map((m, i) => (
                <div key={i}>
                  <div className="flex items-center gap-1.5">
                    <Flame className="h-3.5 w-3.5" style={{ color: "#D97B2F" }} />
                    <span
                      className="text-[9px] font-black uppercase tracking-[0.14em]"
                      style={{ color: "#D97B2F" }}
                    >
                      Impact {i + 1}
                    </span>
                  </div>
                  <p
                    className="mt-1.5 text-[13.5px] font-semibold leading-snug"
                    style={{ fontFamily: 'Georgia, "Times New Roman", serif' }}
                  >
                    <Hi>“{m.quote}”</Hi>
                  </p>
                  {m.why && (
                    <p className="mt-1 text-[11px] italic leading-snug" style={{ color: INK_SOFT }}>
                      ↳ {m.why}
                    </p>
                  )}
                </div>
              ))}
            </div>
            <p className="mt-5 text-[11px] leading-relaxed" style={{ color: INK_SOFT }}>
              Say these again in the follow-up — they already worked once.
            </p>
          </div>
        ),
      });
    }

    if (deck.nextSteps.length > 0) {
      out.push({
        key: "next",
        node: (
          <div className="flex h-full flex-col">
            <Kicker>Next steps</Kicker>
            <SerifTitle>Before the trail goes cold</SerifTitle>
            <div className="mt-4 space-y-3">
              {deck.nextSteps.map((s, i) => (
                <div key={i} className="flex items-start gap-2.5">
                  <CheckSquare className="mt-[2px] h-[18px] w-[18px] shrink-0" style={{ color: MINT_DEEP }} />
                  <div className="min-w-0 flex-1">
                    <p className="text-[13.5px] font-bold leading-snug">{s.action}</p>
                  </div>
                  <span
                    className="shrink-0 rounded-full px-2 py-0.5 text-[10px] font-black"
                    style={{ background: `${MINT_DEEP}14`, color: MINT_DEEP }}
                  >
                    {s.when}
                  </span>
                </div>
              ))}
            </div>
            <p className="mt-auto pt-4 text-[10.5px] leading-relaxed" style={{ color: INK_SOFT }}>
              Jasper drafted this from the live conversation — double-check anything before you promise it.
              {deck.sample ? " This one is a sample so you can see the formatting." : ""}
            </p>
          </div>
        ),
      });
    }

    return out;
  }, [deck, deckDate, laneLabel]);

  const clampPage = useCallback(
    (p: number) => Math.max(0, Math.min(pages.length - 1, p)),
    [pages.length]
  );
  const go = useCallback(
    (delta: 1 | -1) => {
      setDir(delta);
      setPage((p) => clampPage(p + delta));
    },
    [clampPage]
  );

  const stamp = deck.sample ? "SAMPLE" : deck.draft ? "DRAFT" : null;

  return (
    <div className="relative w-full pt-[30px]" aria-label="Jasper's pitch deck">
      <style>{`
        @keyframes deck-page-in-r { from { opacity: 0; transform: translateX(26px) rotate(0.3deg); } to { opacity: 1; transform: none; } }
        @keyframes deck-page-in-l { from { opacity: 0; transform: translateX(-26px) rotate(-0.3deg); } to { opacity: 1; transform: none; } }
        @keyframes deck-ghost-in { from { opacity: 0; transform: translateY(12px); } to { opacity: 1; transform: none; } }
      `}</style>

      {/* Jasper peeking from BEHIND the notebook — drawn under the paper,
          so only the top of his head shows over the page edge. */}
      <div
        className="pointer-events-none absolute left-7 top-0 z-0"
        style={{ animation: "deck-ghost-in 420ms cubic-bezier(0.34,1.4,0.64,1) both" }}
      >
        <EmberMascot size={58} coachMode={mode} isActive expression="calm" />
      </div>

      {/* The notebook — a small stack of pages with the ruled sheet on top. */}
      <div
        className="relative z-[1]"
        onTouchStart={(e) => {
          touchX.current = e.touches[0]?.clientX ?? null;
        }}
        onTouchEnd={(e) => {
          const startX = touchX.current;
          touchX.current = null;
          const endX = e.changedTouches[0]?.clientX ?? null;
          if (startX == null || endX == null) return;
          const dx = endX - startX;
          if (Math.abs(dx) > 48) go(dx < 0 ? 1 : -1);
        }}
      >
        {/* Page stack behind the top sheet */}
        <div
          className="pointer-events-none absolute inset-0 rounded-[16px]"
          style={{
            background: PAPER_EDGE,
            border: "1px solid rgba(0,0,0,0.10)",
            transform: "rotate(-1.1deg) translate(-3px, 5px)",
          }}
          aria-hidden
        />
        <div
          className="pointer-events-none absolute inset-0 rounded-[16px]"
          style={{
            background: PAPER_EDGE_2,
            border: "1px solid rgba(0,0,0,0.07)",
            transform: "rotate(0.7deg) translate(4px, 7px)",
          }}
          aria-hidden
        />

        <div
          className="relative overflow-hidden rounded-[16px] shadow-[0_18px_44px_rgba(0,0,0,0.32)]"
          style={{ ...paperStyle, border: "1px solid rgba(0,0,0,0.22)" }}
        >
          {/* Red margin line */}
          <span
            className="pointer-events-none absolute inset-y-0 left-[38px] w-px"
            style={{ background: MARGIN_RED, opacity: 0.75 }}
            aria-hidden
          />
          {/* Draft / sample stamp */}
          {stamp && (
            <span
              className="pointer-events-none absolute right-5 top-5 rotate-[-8deg] rounded-[6px] border-2 px-2 py-0.5 text-[11px] font-black tracking-[0.18em]"
              style={{ borderColor: "#C0392B99", color: "#C0392BCC" }}
            >
              {stamp}
            </span>
          )}

          {/* Page content */}
          <div
            key={page}
            className="h-[min(56vh,470px)] overflow-y-auto py-6 pl-[52px] pr-5"
            style={{
              animation: `${dir === 1 ? "deck-page-in-r" : "deck-page-in-l"} 300ms cubic-bezier(0.3,0.9,0.4,1) both`,
            }}
          >
            {pages[page]?.node}
          </div>

          {/* Folio */}
          <div
            className="pointer-events-none absolute bottom-2.5 right-4 text-[10px] font-bold"
            style={{ color: INK_SOFT }}
          >
            {page + 1} / {pages.length}
          </div>
        </div>
      </div>

      {/* Pager — paper chips so it reads on any backdrop */}
      <div className="relative z-[1] mt-3 flex items-center justify-between">
        <button
          type="button"
          onClick={() => go(-1)}
          disabled={page === 0}
          aria-label="Previous page"
          className="flex h-9 w-9 items-center justify-center rounded-full border transition-transform active:scale-95 disabled:opacity-35"
          style={{
            background: PAPER,
            borderColor: "rgba(32,36,43,0.18)",
            color: INK,
            boxShadow: "0 2px 8px rgba(0,0,0,0.18)",
          }}
        >
          <ChevronLeft className="h-4.5 w-4.5" style={{ width: 18, height: 18 }} />
        </button>
        <div className="flex items-center gap-1.5">
          {pages.map((p, i) => (
            <button
              key={p.key}
              type="button"
              aria-label={`Page ${i + 1}`}
              onClick={() => {
                setDir(i > page ? 1 : -1);
                setPage(i);
              }}
              className="h-2 rounded-full transition-all"
              style={{
                width: i === page ? 18 : 8,
                background: i === page ? MINT_DEEP : "rgba(126,122,108,0.4)",
              }}
            />
          ))}
        </div>
        <button
          type="button"
          onClick={() => go(1)}
          disabled={page === pages.length - 1}
          aria-label="Next page"
          className="flex h-9 w-9 items-center justify-center rounded-full border transition-transform active:scale-95 disabled:opacity-35"
          style={{
            background: PAPER,
            borderColor: "rgba(32,36,43,0.18)",
            color: INK,
            boxShadow: "0 2px 8px rgba(0,0,0,0.18)",
          }}
        >
          <ChevronRight style={{ width: 18, height: 18 }} />
        </button>
      </div>
    </div>
  );
}
