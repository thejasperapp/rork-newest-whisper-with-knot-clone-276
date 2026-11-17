import { memo, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import {
  ResponsiveContainer,
  ComposedChart,
  Line,
  Bar,
  Area,
  Scatter,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ReferenceLine,
} from "recharts";
import {
  LineChart as LineChartIcon,
  Target,
  Calendar,
  Check,
  ChevronLeft,
  ChevronRight,
  Clock,
  Copy,
  Heart,
  ImagePlus,
  MessageCircle,
  Plus,
  Presentation,
  Repeat,
  Repeat2,
  Send,
  SlidersHorizontal,
  Sparkles,
  SquarePen,
  Flag,
  UserRound,
} from "lucide-react";
import { toast } from "sonner";

import { Avatar } from "@/components/Avatar";
import { EmberJasperLookCard } from "@/components/JasperDataCards";
import { useAuth } from "@/hooks/useAuth";
import { setComposerPrefill } from "@/lib/composerDraft";
import type {
  EmberBlock,
  EmberChart,
  EmberDeck,
  EmberGoalPlan,
  EmberPostDraft,
  EmberProfileCard,
  EmberSchedule,
} from "@/lib/emberBrain";
import { chartRenderSeries } from "@/lib/emberBrain";

/**
 * Web port of the iOS `WhisperEmberBlockCard` — renders the fenced
 * chart/goalplan/schedule blocks the shared brain appends to replies as
 * native cards in Whisper's black & white styling.
 */

function formatted(v: number): string {
  if (v >= 1000) return `${(v / 1000).toFixed(1)}k`;
  if (Number.isInteger(v)) return String(v);
  return v.toFixed(1);
}

/** Ink opacities per series — Whisper plots in pure ink, not hues. */
const SERIES_OPACITIES = [1.0, 0.55, 0.32, 0.78, 0.42];

function EmberChartCard({ chart }: { chart: EmberChart }) {
  const series = chartRenderSeries(chart);

  /** Merge all series into recharts row shape keyed by x. */
  const rows = useMemo(() => {
    const byX = new Map<string, Record<string, string | number>>();
    const order: string[] = [];
    series.forEach((s, idx) => {
      const key = `s${idx}`;
      for (const p of s.points) {
        let row = byX.get(p.x);
        if (!row) {
          row = { x: p.x };
          byX.set(p.x, row);
          order.push(p.x);
        }
        row[key] = p.y;
      }
    });
    return order.map((x) => byX.get(x)!);
  }, [series]);

  const type = chart.type.toLowerCase();

  return (
    <div className="rounded-2xl border border-border bg-card p-3.5">
      <div className="mb-2 flex items-center gap-2">
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-foreground text-background">
          <LineChartIcon className="h-3.5 w-3.5" />
        </span>
        <div className="min-w-0">
          <p className="text-[10px] font-extrabold uppercase tracking-widest opacity-70">
            {chart.title ?? "Chart"}
          </p>
          {chart.unit && (
            <p className="text-[10px] text-muted-foreground">{chart.unit}</p>
          )}
        </div>
      </div>
      <div className="h-[170px] w-full">
        <ResponsiveContainer width="100%" height="100%">
          <ComposedChart data={rows} margin={{ top: 8, right: 8, bottom: 0, left: -18 }}>
            <CartesianGrid strokeDasharray="3 3" stroke="hsl(var(--border))" vertical={false} />
            <XAxis dataKey="x" tick={{ fontSize: 10 }} tickLine={false} axisLine={false} />
            <YAxis tick={{ fontSize: 10 }} tickLine={false} axisLine={false} width={46} />
            <Tooltip
              contentStyle={{
                borderRadius: 12,
                border: "1px solid hsl(var(--border))",
                background: "hsl(var(--card))",
                fontSize: 12,
              }}
              formatter={(value: number, name: string) => {
                const idx = Number(name.replace("s", ""));
                return [formatted(value), series[idx]?.name ?? chart.title ?? "value"];
              }}
            />
            {chart.goal != null && (
              <ReferenceLine
                y={chart.goal}
                stroke="hsl(var(--muted-foreground))"
                strokeDasharray="4 4"
                label={{
                  value: `goal ${formatted(chart.goal)}`,
                  fontSize: 10,
                  position: "insideTopRight",
                  fill: "hsl(var(--muted-foreground))",
                }}
              />
            )}
            {series.map((s, idx) => {
              const key = `s${idx}`;
              const color = `hsl(var(--foreground) / ${SERIES_OPACITIES[idx % SERIES_OPACITIES.length]})`;
              if (type === "bar") {
                return <Bar key={key} dataKey={key} fill={color} radius={[4, 4, 0, 0]} />;
              }
              if (type === "area") {
                return (
                  <Area
                    key={key}
                    dataKey={key}
                    stroke={color}
                    fill={color}
                    fillOpacity={0.18}
                    strokeWidth={2}
                  />
                );
              }
              if (type === "point") {
                return <Scatter key={key} dataKey={key} fill={color} />;
              }
              return (
                <Line
                  key={key}
                  dataKey={key}
                  stroke={color}
                  strokeWidth={2}
                  dot={{ r: 2.5, fill: color, strokeWidth: 0 }}
                  type="monotone"
                />
              );
            })}
          </ComposedChart>
        </ResponsiveContainer>
      </div>
      {series.length > 1 && (
        <div className="mt-1.5 flex flex-wrap items-center gap-3">
          {series.map((s, idx) =>
            s.name ? (
              <span key={idx} className="flex items-center gap-1.5 text-[10px] font-semibold">
                <span
                  className="h-2 w-2 rounded-full"
                  style={{
                    background: `hsl(var(--foreground) / ${SERIES_OPACITIES[idx % SERIES_OPACITIES.length]})`,
                  }}
                />
                {s.name}
              </span>
            ) : null
          )}
        </div>
      )}
    </div>
  );
}

const GOAL_STORE_KEY = "whisper_ember_saved_goals_v1";

function persistSaved(kind: "goal" | "schedule", payload: unknown): void {
  try {
    const raw = localStorage.getItem(GOAL_STORE_KEY);
    const list = raw ? (JSON.parse(raw) as unknown[]) : [];
    list.unshift({ kind, payload, savedAt: Date.now() });
    localStorage.setItem(GOAL_STORE_KEY, JSON.stringify(list.slice(0, 50)));
  } catch {
    /* storage unavailable */
  }
}

function milestoneLabel(m: { label?: string | null; date?: string | null; value?: number | null }): string {
  const parts: string[] = [];
  if (m.label) parts.push(m.label);
  if (m.value != null) parts.push(formatted(m.value));
  if (m.date) parts.push(`· ${m.date}`);
  return parts.length > 0 ? parts.join(" ") : "Milestone";
}

function EmberGoalPlanCard({ plan }: { plan: EmberGoalPlan }) {
  const [saved, setSaved] = useState<boolean>(false);

  return (
    <div className="rounded-2xl border border-border bg-card p-3.5">
      <div className="mb-2 flex items-center gap-2">
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-green-600 text-white">
          <Target className="h-3.5 w-3.5" />
        </span>
        <div className="min-w-0 flex-1">
          <p className="text-[10px] font-extrabold uppercase tracking-widest opacity-70">Goal plan</p>
          {plan.category && (
            <p className="text-[10px] text-muted-foreground">{plan.category}</p>
          )}
        </div>
        {plan.targetDate && (
          <span className="rounded-full bg-secondary px-2 py-0.5 text-[10px] font-semibold">
            {plan.targetDate}
          </span>
        )}
      </div>

      {plan.title && <p className="text-[15px] font-bold">{plan.title}</p>}
      {plan.summary && (
        <p className="mt-1 whitespace-pre-wrap text-sm leading-relaxed">{plan.summary}</p>
      )}

      {plan.startValue != null && plan.targetValue != null && (
        <div className="mt-3">
          <div className="mb-1 flex justify-between text-[11px] font-semibold text-muted-foreground">
            <span>
              {formatted(plan.startValue)} {plan.metricLabel ?? ""}
            </span>
            <span>
              {formatted(plan.targetValue)} {plan.metricLabel ?? ""}
            </span>
          </div>
          <div className="h-2 overflow-hidden rounded-full bg-secondary">
            <div className="h-full w-4 rounded-full bg-green-600" />
          </div>
        </div>
      )}

      {plan.weeklyFocus && plan.weeklyFocus.length > 0 && (
        <div className="mt-3">
          <p className="text-[11px] font-extrabold uppercase opacity-70">Weekly focus</p>
          <ul className="mt-1 space-y-1">
            {plan.weeklyFocus.slice(0, 6).map((f, i) => (
              <li key={i} className="flex items-start gap-1.5 text-xs">
                <Check className="mt-0.5 h-3 w-3 shrink-0 text-muted-foreground" />
                {f}
              </li>
            ))}
          </ul>
        </div>
      )}

      {plan.milestones && plan.milestones.length > 0 && (
        <div className="mt-3">
          <p className="text-[11px] font-extrabold uppercase opacity-70">Milestones</p>
          <ul className="mt-1 space-y-1">
            {plan.milestones.map((m, i) => (
              <li key={i} className="flex items-start gap-1.5 text-xs">
                <Flag className="mt-0.5 h-3 w-3 shrink-0 text-green-600" />
                {milestoneLabel(m)}
              </li>
            ))}
          </ul>
        </div>
      )}

      <button
        type="button"
        disabled={saved}
        onClick={() => {
          persistSaved("goal", plan);
          setSaved(true);
        }}
        className={
          saved
            ? "mt-3 flex w-full items-center justify-center gap-1.5 rounded-full bg-green-600/15 py-2.5 text-sm font-bold text-green-600"
            : "mt-3 flex w-full items-center justify-center gap-1.5 rounded-full bg-green-600 py-2.5 text-sm font-bold text-white transition-transform active:scale-[0.98]"
        }
      >
        {saved ? <Check className="h-3.5 w-3.5" /> : <Plus className="h-3.5 w-3.5" />}
        {saved ? "Saved to your goals" : "Track this goal"}
      </button>
    </div>
  );
}

function EmberScheduleCard({ schedule }: { schedule: EmberSchedule }) {
  const [saved, setSaved] = useState<boolean>(false);

  const section = (title: string, Icon: typeof Repeat, items: string[]): JSX.Element => (
    <div className="mt-2">
      <p className="text-[11px] font-extrabold uppercase opacity-70">{title}</p>
      <ul className="mt-1 space-y-1">
        {items
          .filter((s) => s.length > 0)
          .map((item, i) => (
            <li key={i} className="flex items-start gap-1.5 text-xs">
              <Icon className="mt-0.5 h-3 w-3 shrink-0 text-muted-foreground" />
              {item}
            </li>
          ))}
      </ul>
    </div>
  );

  return (
    <div className="rounded-2xl border border-border bg-card p-3.5">
      <div className="flex items-center gap-2">
        <span className="flex h-7 w-7 items-center justify-center rounded-full bg-indigo-600 text-white">
          <Calendar className="h-3.5 w-3.5" />
        </span>
        <p className="text-[10px] font-extrabold uppercase tracking-widest opacity-70">Schedule</p>
      </div>
      {schedule.rules && schedule.rules.length > 0 && section("Rules", Repeat, schedule.rules)}
      {schedule.conditions &&
        schedule.conditions.length > 0 &&
        section("Conditions", SlidersHorizontal, schedule.conditions)}
      <button
        type="button"
        disabled={saved}
        onClick={() => {
          persistSaved("schedule", schedule);
          setSaved(true);
        }}
        className={
          saved
            ? "mt-3 flex w-full items-center justify-center gap-1.5 rounded-full bg-indigo-600/15 py-2.5 text-sm font-bold text-indigo-600"
            : "mt-3 flex w-full items-center justify-center gap-1.5 rounded-full bg-indigo-600 py-2.5 text-sm font-bold text-white transition-transform active:scale-[0.98]"
        }
      >
        {saved ? <Check className="h-3.5 w-3.5" /> : <Plus className="h-3.5 w-3.5" />}
        {saved ? "Schedule saved" : "Save schedule"}
      </button>
    </div>
  );
}

/**
 * A post Ember drafted, rendered through the REAL post UX — the user's own
 * avatar and handle, the thread-card layout, and the live action row — so
 * what they see is exactly what the feed will show. One tap opens the
 * composer with everything pre-filled.
 */
function EmberPostDraftCard({ draft }: { draft: EmberPostDraft }) {
  const { profile } = useAuth();
  const navigate = useNavigate();
  const username = profile?.username ?? "you";

  const fullCaption = useMemo(() => {
    const tags = (draft.hashtags ?? [])
      .map((h) => `#${h}`)
      .filter((t) => !(draft.caption ?? "").toLowerCase().includes(t.toLowerCase()));
    return [draft.caption?.trim() ?? "", tags.join(" ")].filter(Boolean).join("\n\n");
  }, [draft]);

  const openInComposer = (): void => {
    setComposerPrefill({
      caption: fullCaption,
      topic: draft.community?.toLowerCase().replace(/^#/, "") ?? null,
    });
    toast("Draft loaded — finish it in the composer");
    navigate("/compose");
  };

  return (
    <div className="overflow-hidden rounded-2xl border border-border bg-card">
      <div className="flex items-center gap-2 border-b border-border px-3.5 py-2">
        <span className="flex h-6 w-6 items-center justify-center rounded-full bg-foreground text-background">
          <SquarePen className="h-3 w-3" />
        </span>
        <p className="text-[10px] font-extrabold uppercase tracking-widest opacity-70">
          Post draft · preview
        </p>
        {draft.bestTime && (
          <span className="ml-auto flex items-center gap-1 rounded-full bg-secondary px-2 py-0.5 text-[10px] font-semibold text-muted-foreground">
            <Clock className="h-3 w-3" />
            {draft.bestTime}
          </span>
        )}
      </div>

      {/* Real thread-card layout */}
      <div className="flex gap-3 px-3.5 pt-3">
        <div className="flex w-9 flex-col items-center">
          <Avatar url={profile?.profile_image_url} name={username} size={36} />
          <div className="mt-1 w-0.5 flex-1 rounded-full bg-foreground/10" />
        </div>
        <div className="min-w-0 flex-1 pb-3">
          <div className="flex items-center gap-1.5 text-[14px]">
            <span className="font-bold">{username}</span>
            {draft.community && (
              <>
                <span className="text-muted-foreground">›</span>
                <span className="truncate font-semibold">#{draft.community.replace(/^#/, "")}</span>
              </>
            )}
            <span className="text-[12px] text-muted-foreground">now</span>
          </div>
          <p className="mt-0.5 whitespace-pre-wrap text-[14.5px] leading-snug">
            {fullCaption || "…"}
          </p>
          {draft.mediaIdea && (
            <div className="mt-2 flex items-center gap-2 rounded-xl border border-dashed border-border bg-secondary/40 px-2.5 py-2 text-[12px] text-muted-foreground">
              <ImagePlus className="h-3.5 w-3.5 shrink-0" />
              <span className="leading-snug">{draft.mediaIdea}</span>
            </div>
          )}
          <div className="mt-2 flex items-center gap-4 text-foreground/80">
            <Heart className="h-[17px] w-[17px]" />
            <MessageCircle className="h-[17px] w-[17px]" />
            <Repeat2 className="h-[17px] w-[17px]" />
            <Send className="h-[15px] w-[15px]" />
          </div>
        </div>
      </div>

      <div className="flex gap-2 border-t border-border p-2.5">
        <button
          type="button"
          onClick={openInComposer}
          className="flex flex-1 items-center justify-center gap-1.5 rounded-full bg-foreground py-2.5 text-sm font-bold text-background transition-transform active:scale-[0.98]"
        >
          <SquarePen className="h-3.5 w-3.5" />
          Open in composer
        </button>
        <button
          type="button"
          onClick={() => {
            void navigator.clipboard?.writeText(fullCaption);
            toast("Caption copied");
          }}
          aria-label="Copy caption"
          className="flex h-10 w-10 items-center justify-center rounded-full border border-border bg-card text-foreground transition-colors hover:bg-secondary"
        >
          <Copy className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}

/**
 * Profile makeover card — shows the rewritten bio inside a real profile
 * header preview (avatar, name, bio) plus Ember's tips, with one-tap copy.
 */
function EmberProfileCardView({ card }: { card: EmberProfileCard }) {
  const { profile } = useAuth();
  const username = profile?.username ?? "you";

  return (
    <div className="overflow-hidden rounded-2xl border border-border bg-card">
      <div className="flex items-center gap-2 border-b border-border px-3.5 py-2">
        <span className="flex h-6 w-6 items-center justify-center rounded-full bg-foreground text-background">
          <UserRound className="h-3 w-3" />
        </span>
        <p className="text-[10px] font-extrabold uppercase tracking-widest opacity-70">
          {card.title ?? "Profile upgrade"}
        </p>
      </div>

      {card.bio && (
        <div className="px-3.5 pt-3">
          {/* Real profile-header preview */}
          <div className="flex items-start gap-3">
            <Avatar url={profile?.profile_image_url} name={username} size={46} />
            <div className="min-w-0 flex-1">
              <p className="text-[15px] font-bold leading-tight">
                {profile?.display_name || username}
              </p>
              <p className="text-[12.5px] text-muted-foreground">@{username}</p>
              <p className="mt-1.5 whitespace-pre-wrap text-[13.5px] leading-snug">
                {card.bio}
              </p>
            </div>
          </div>
          <button
            type="button"
            onClick={() => {
              void navigator.clipboard?.writeText(card.bio ?? "");
              toast("Bio copied — paste it in Edit profile");
            }}
            className="mt-3 flex w-full items-center justify-center gap-1.5 rounded-full bg-foreground py-2.5 text-sm font-bold text-background transition-transform active:scale-[0.98]"
          >
            <Copy className="h-3.5 w-3.5" />
            Copy new bio
          </button>
        </div>
      )}

      {card.pinnedIdea && (
        <div className="mx-3.5 mt-3 flex items-start gap-2 rounded-xl bg-secondary/50 px-2.5 py-2">
          <Sparkles className="mt-0.5 h-3.5 w-3.5 shrink-0 text-muted-foreground" />
          <p className="text-[12.5px] leading-snug">
            <span className="font-bold">Pin this: </span>
            {card.pinnedIdea}
          </p>
        </div>
      )}

      {card.tips && card.tips.length > 0 && (
        <div className="px-3.5 py-3">
          <p className="text-[11px] font-extrabold uppercase opacity-70">Tips</p>
          <ul className="mt-1 space-y-1">
            {card.tips.slice(0, 6).map((t, i) => (
              <li key={i} className="flex items-start gap-1.5 text-xs">
                <Check className="mt-0.5 h-3 w-3 shrink-0 text-muted-foreground" />
                {t}
              </li>
            ))}
          </ul>
        </div>
      )}
      {!card.tips?.length && !card.pinnedIdea && <div className="pb-3" />}
    </div>
  );
}

/**
 * A swipeable mini pitch deck — Ember walks the room through Whisper slide by
 * slide. Arrow keys / buttons page through; dots show progress. Slides carry
 * an optional hero stat so numbers land with weight.
 */
function EmberDeckCard({ deck }: { deck: EmberDeck }) {
  const [index, setIndex] = useState<number>(0);
  const slides = deck.slides;
  const slide = slides[Math.min(index, slides.length - 1)];
  if (!slide) return null;

  const go = (dir: 1 | -1): void => {
    setIndex((current) => Math.max(0, Math.min(slides.length - 1, current + dir)));
  };

  return (
    <div className="overflow-hidden rounded-2xl border border-border bg-card">
      <div className="flex items-center gap-2 border-b border-border px-3.5 py-2">
        <span className="flex h-6 w-6 items-center justify-center rounded-full bg-foreground text-background">
          <Presentation className="h-3 w-3" />
        </span>
        <p className="min-w-0 flex-1 truncate text-[10px] font-extrabold uppercase tracking-widest opacity-70">
          {deck.title ?? "Whisper walkthrough"}
        </p>
        <span className="shrink-0 text-[10px] font-bold tabular-nums text-muted-foreground">
          {index + 1}/{slides.length}
        </span>
      </div>

      {/* Keyed so each slide pops in with the cinematic spring. */}
      <div key={index} className="min-h-[132px] px-4 py-3.5" style={{ animation: "ember-pop-in 300ms cubic-bezier(0.34, 1.4, 0.64, 1) both" }}>
        {slide.stat && (
          <div className="mb-1.5 flex items-baseline gap-2">
            <p className="text-[30px] font-black leading-none tracking-tight">{slide.stat}</p>
            {slide.statLabel && (
              <p className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                {slide.statLabel}
              </p>
            )}
          </div>
        )}
        {slide.title && <p className="text-[15px] font-extrabold leading-tight">{slide.title}</p>}
        {slide.body && (
          <p className="mt-1 text-[12.5px] leading-relaxed text-muted-foreground">{slide.body}</p>
        )}
        {slide.bullets && slide.bullets.length > 0 && (
          <ul className="mt-2 space-y-1">
            {slide.bullets.slice(0, 5).map((b, i) => (
              <li key={i} className="flex items-start gap-1.5 text-[12px] leading-snug">
                <Check className="mt-0.5 h-3 w-3 shrink-0 text-muted-foreground" />
                {b}
              </li>
            ))}
          </ul>
        )}
      </div>

      <div className="flex items-center justify-between border-t border-border px-2.5 py-2">
        <button
          type="button"
          onClick={() => go(-1)}
          disabled={index === 0}
          aria-label="Previous slide"
          className="flex h-8 w-8 items-center justify-center rounded-full border border-border transition-colors hover:bg-secondary disabled:opacity-30"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>
        <div className="flex items-center gap-1.5">
          {slides.map((_, i) => (
            <button
              key={i}
              type="button"
              aria-label={`Go to slide ${i + 1}`}
              onClick={() => setIndex(i)}
              className="rounded-full transition-all"
              style={{
                width: i === index ? 16 : 6,
                height: 6,
                background:
                  i === index ? "hsl(var(--foreground))" : "hsl(var(--foreground) / 0.22)",
              }}
            />
          ))}
        </div>
        <button
          type="button"
          onClick={() => go(1)}
          disabled={index === slides.length - 1}
          aria-label="Next slide"
          className="flex h-8 w-8 items-center justify-center rounded-full border border-border transition-colors hover:bg-secondary disabled:opacity-30"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}

function EmberBlockCardBase({ block }: { block: EmberBlock }) {
  if (block.kind === "chart") return <EmberChartCard chart={block.chart} />;
  if (block.kind === "goalplan") return <EmberGoalPlanCard plan={block.plan} />;
  if (block.kind === "postdraft") return <EmberPostDraftCard draft={block.draft} />;
  if (block.kind === "profilecard") return <EmberProfileCardView card={block.card} />;
  if (block.kind === "deck") return <EmberDeckCard deck={block.deck} />;
  if (block.kind === "jasper") return <EmberJasperLookCard look={block.jasper} />;
  return <EmberScheduleCard schedule={block.schedule} />;
}

export const EmberBlockCard = memo(EmberBlockCardBase);
