import { memo, useState } from "react";
import { useQuery } from "@tanstack/react-query";
import {
  ChevronDown,
  ChevronRight,
  ExternalLink,
  MapPin,
  CheckCircle2,
  ShieldCheck,
  AlertTriangle,
  XCircle,
  HelpCircle,
  Utensils,
  Plus,
  Check,
  Loader2,
} from "lucide-react";
import { toast } from "sonner";

import { KnotPortrait } from "@/components/Knot";
import { JasperSpark } from "@/components/JasperSpark";
import { NearbyMap } from "@/components/NearbyMap";
import { cn } from "@/lib/utils";
import {
  decodeEmberAnswer,
  decodeFactCheck,
  decodeMap,
  type FactCheckPayload,
  type MapPlace,
} from "@/lib/dmEmber";
import type { Verdict } from "@/lib/ember";
import { useAuth } from "@/hooks/useAuth";
import {
  resolveMenu,
  rankMenu,
  fetchRemainingMacros,
  logMenuItem,
  MENU_FILTERS,
  MEAL_SLOTS,
  type MenuFilter,
  type MenuEntry,
  type MealSlot,
} from "@/lib/emberMenu";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";

/**
 * Renders the Ember-produced DM embeds (chat answer, fact-check verdict,
 * nearby-restaurants map) instead of leaking the raw `::whisper-…::{json}`
 * payload. Returns null when the body isn't a recognised Ember embed so the
 * caller falls back to the next renderer.
 */
function EmberDmCardBase({
  body,
  mine,
}: {
  body: string | null | undefined;
  mine: boolean;
}) {
  const answer = decodeEmberAnswer(body);
  const fact = decodeFactCheck(body);
  const map = decodeMap(body);

  const shell = cn(
    "w-[min(290px,82vw)] overflow-hidden rounded-[20px] border text-left",
    mine ? "border-primary/30 bg-primary/5" : "border-border bg-card"
  );

  if (answer) return <AnswerCard payload={answer} shell={shell} />;
  if (fact) return <FactCard payload={fact} shell={shell} />;
  if (map) return <MapCard payload={map} shell={shell} />;
  return null;
}

function AnswerCard({
  payload,
  shell,
}: {
  payload: NonNullable<ReturnType<typeof decodeEmberAnswer>>;
  shell: string;
}) {
  const [expanded, setExpanded] = useState<boolean>(false);
  const isLong = payload.answer.length > 280;
  const preview = isLong ? payload.answer.slice(0, 220).trim() + "…" : payload.answer;
  return (
    <div className={cn(shell, "p-3.5")}>
      <div className="mb-2 flex items-center gap-2">
        <KnotPortrait size={32} />
        <span className="text-sm font-semibold">Knot<span className="ml-2 text-[11px] font-normal text-muted-foreground">AI assistant</span></span>
      </div>
      {payload.question && (
        <p className="mb-1.5 line-clamp-2 text-xs font-semibold opacity-70">
          {payload.question}
        </p>
      )}
      <p className="whitespace-pre-wrap text-sm leading-relaxed">
        {expanded ? payload.answer : preview}
      </p>
      {isLong && !expanded && (
        <button
          onClick={() => setExpanded(true)}
          className="mt-2 rounded-full bg-secondary px-3 py-1 text-xs font-bold text-foreground transition-colors hover:bg-secondary/70"
        >
          Tell me more
        </button>
      )}
      {payload.sources.length > 0 && (
        <div className="mt-2.5 space-y-1 border-t border-border/60 pt-2.5">
          {payload.sources.slice(0, 3).map((s) => (
            <SourceLink key={s} url={s} />
          ))}
        </div>
      )}
    </div>
  );
}

const VERDICT_META: Record<
  Verdict,
  { label: string; icon: React.ReactNode; color: string; bg: string }
> = {
  true: {
    label: "True",
    icon: <CheckCircle2 className="h-4 w-4" />,
    color: "#22c55e",
    bg: "rgba(34,197,94,0.14)",
  },
  mostly_true: {
    label: "Mostly true",
    icon: <ShieldCheck className="h-4 w-4" />,
    color: "#10b981",
    bg: "rgba(16,185,129,0.14)",
  },
  misleading: {
    label: "Misleading",
    icon: <AlertTriangle className="h-4 w-4" />,
    color: "#f59e0b",
    bg: "rgba(245,158,11,0.14)",
  },
  false: {
    label: "False",
    icon: <XCircle className="h-4 w-4" />,
    color: "#ef4444",
    bg: "rgba(239,68,68,0.14)",
  },
  unverified: {
    label: "Unverified",
    icon: <HelpCircle className="h-4 w-4" />,
    color: "#94a3b8",
    bg: "rgba(148,163,184,0.16)",
  },
};

function FactCard({ payload, shell }: { payload: FactCheckPayload; shell: string }) {
  const [expanded, setExpanded] = useState<boolean>(false);
  const meta = VERDICT_META[payload.verdictRaw] ?? VERDICT_META.unverified;
  return (
    <div className={cn(shell, "p-3.5")}>
      <div className="mb-2 flex items-center gap-2">
        <JasperSpark size={14} breathing={false} />
        <span className="text-[10px] font-extrabold uppercase tracking-wide opacity-60">
          Fact check
        </span>
        <span
          className="ml-auto flex items-center gap-1 rounded-full px-2.5 py-1 text-[11px] font-bold"
          style={{ color: meta.color, background: meta.bg }}
        >
          {meta.icon}
          {meta.label}
        </span>
      </div>
      <p className="mb-1.5 line-clamp-2 text-xs font-semibold opacity-70">
        “{payload.claim}”
      </p>
      {payload.summary && (
        <p className="text-sm font-semibold leading-snug">{payload.summary}</p>
      )}
      {payload.explanation && (
        <>
          {expanded && (
            <p className="mt-1.5 text-sm leading-relaxed opacity-90">
              {payload.explanation}
            </p>
          )}
          {!expanded && (
            <button
              onClick={() => setExpanded(true)}
              className="mt-2 flex items-center gap-1 text-xs font-bold text-foreground"
            >
              Show more <ChevronDown className="h-3.5 w-3.5" />
            </button>
          )}
        </>
      )}
      {payload.sources.length > 0 && (
        <div className="mt-2.5 space-y-1 border-t border-border/60 pt-2.5">
          {payload.sources.slice(0, 3).map((s) => (
            <SourceLink key={s} url={s} />
          ))}
        </div>
      )}
    </div>
  );
}

function MapCard({
  payload,
  shell,
}: {
  payload: NonNullable<ReturnType<typeof decodeMap>>;
  shell: string;
}) {
  const { user } = useAuth();
  const [expanded, setExpanded] = useState<string | null>(null);
  const [filter, setFilter] = useState<MenuFilter>("all");

  const remainingQuery = useQuery({
    queryKey: ["ember-remaining-macros", user?.id],
    queryFn: () => fetchRemainingMacros(user!.id),
    enabled: !!user,
    staleTime: 60_000,
  });
  const remaining = remainingQuery.data ?? {
    calories: 2000,
    protein: 150,
    carbs: 200,
    fat: 65,
  };

  return (
    <div className={cn(shell, "overflow-hidden")}>
      <div className="relative h-[150px] w-full bg-secondary">
        <NearbyMap
          lat={payload.lat}
          lon={payload.lon}
          places={payload.places}
          height={150}
        />
        <div className="pointer-events-none absolute inset-x-0 bottom-0 flex items-center gap-1.5 bg-gradient-to-t from-black/70 to-transparent p-3 text-white">
          <MapPin className="h-4 w-4" />
          <span className="text-sm font-bold">{payload.title}</span>
        </div>
      </div>

      {/* Ember macro summary — what's left today, ranked into the picks below. */}
      <div className="flex items-center gap-2 border-b border-border/60 px-3.5 py-2">
        <JasperSpark size={13} breathing={false} />
        <span className="text-[11px] font-semibold text-muted-foreground">
          {Math.round(remaining.calories)} cal · {Math.round(remaining.protein)}p ·{" "}
          {Math.round(remaining.carbs)}c · {Math.round(remaining.fat)}f left today
        </span>
      </div>

      {/* Filter chips */}
      <div className="no-scrollbar flex gap-1.5 overflow-x-auto px-3.5 py-2">
        {MENU_FILTERS.map((f) => (
          <button
            key={f.id}
            onClick={() => setFilter(f.id)}
            className={cn(
              "shrink-0 rounded-full px-2.5 py-1 text-[11px] font-bold transition-colors",
              filter === f.id
                ? "bg-foreground text-background"
                : "bg-secondary text-muted-foreground"
            )}
          >
            {f.label}
          </button>
        ))}
      </div>

      <div className="divide-y divide-border/60">
        {payload.places.slice(0, 6).map((p) => (
          <PlaceRow
            key={p.id}
            place={p}
            city={payload.city}
            filter={filter}
            remaining={remaining}
            expanded={expanded === p.id}
            onToggle={() =>
              setExpanded((cur) => (cur === p.id ? null : p.id))
            }
            userId={user?.id ?? null}
          />
        ))}
      </div>
    </div>
  );
}

function PlaceRow({
  place,
  city,
  filter,
  remaining,
  expanded,
  onToggle,
  userId,
}: {
  place: MapPlace;
  city: string | null;
  filter: MenuFilter;
  remaining: { calories: number; protein: number; carbs: number; fat: number };
  expanded: boolean;
  onToggle: () => void;
  userId: string | null;
}) {
  const [logged, setLogged] = useState<Set<string>>(new Set());

  const menuQuery = useQuery({
    queryKey: ["ember-menu", place.name, city],
    queryFn: () => resolveMenu(place.name, place.category, city),
    enabled: expanded,
    staleTime: 5 * 60 * 1000,
  });

  const ranked = menuQuery.data
    ? rankMenu(menuQuery.data, filter, remaining)
    : [];

  const handleLog = async (item: MenuEntry, slot: MealSlot): Promise<void> => {
    setLogged((s) => new Set(s).add(item.id));
    const slotLabel =
      MEAL_SLOTS.find((s) => s.id === slot)?.label ?? "Snack";
    if (userId) {
      const ok = await logMenuItem(userId, item, place.name, place.id, slot);
      toast(
        ok
          ? `Logged ${item.name} · ${slotLabel}`
          : `Saved ${item.name} locally`
      );
    } else {
      toast(`Logged ${item.name} · ${slotLabel}`);
    }
  };

  return (
    <div>
      <button
        onClick={onToggle}
        className="flex w-full items-center gap-3 px-3.5 py-2.5 text-left transition-colors hover:bg-secondary/50"
      >
        <span className="flex h-8 w-8 shrink-0 items-center justify-center rounded-xl bg-[#FF7340]/12 text-[#FF7340]">
          <Utensils className="h-4 w-4" />
        </span>
        <div className="min-w-0 flex-1">
          <p className="truncate text-sm font-semibold">{place.name}</p>
          {place.category && (
            <p className="truncate text-xs capitalize text-muted-foreground">
              {place.category}
            </p>
          )}
        </div>
        <ChevronRight
          className={cn(
            "h-4 w-4 shrink-0 text-muted-foreground transition-transform",
            expanded && "rotate-90"
          )}
        />
      </button>

      {expanded && (
        <div className="bg-secondary/30 px-3.5 pb-3">
          {menuQuery.isLoading ? (
            <div className="flex items-center gap-2 py-3 text-xs text-muted-foreground">
              <Loader2 className="h-3.5 w-3.5 animate-spin" />
              Jasper is reading the menu…
            </div>
          ) : ranked.length === 0 ? (
            <p className="py-3 text-xs text-muted-foreground">
              No items match this filter.
            </p>
          ) : (
            <div className="space-y-1.5 pt-1">
              {ranked.map((item) => {
                const isLogged = logged.has(item.id);
                return (
                  <div
                    key={item.id}
                    className="flex items-center gap-2 rounded-xl bg-background px-3 py-2"
                  >
                    <div className="min-w-0 flex-1">
                      <div className="flex items-center gap-1.5">
                        <span className="truncate text-[13px] font-semibold">
                          {item.name}
                        </span>
                        {item.tag && (
                          <span className="shrink-0 rounded-full bg-secondary px-1.5 py-0.5 text-[9px] font-bold uppercase text-muted-foreground">
                            {item.tag}
                          </span>
                        )}
                      </div>
                      <p className="text-[11px] text-muted-foreground">
                        {item.calories} cal · {Math.round(item.protein)}p ·{" "}
                        {Math.round(item.carbs)}c · {Math.round(item.fat)}f
                      </p>
                    </div>
                    {isLogged ? (
                      <span className="flex shrink-0 items-center gap-1 rounded-full bg-green-500/15 px-2.5 py-1 text-[11px] font-bold text-green-600">
                        <Check className="h-3 w-3" />
                        Logged
                      </span>
                    ) : (
                      <DropdownMenu>
                        <DropdownMenuTrigger asChild>
                          <button
                            className="flex shrink-0 items-center gap-1 rounded-full bg-foreground px-2.5 py-1 text-[11px] font-bold text-background transition-colors"
                          >
                            <Plus className="h-3 w-3" />
                            Log
                          </button>
                        </DropdownMenuTrigger>
                        <DropdownMenuContent align="end">
                          {MEAL_SLOTS.map((slot) => (
                            <DropdownMenuItem
                              key={slot.id}
                              onSelect={() => void handleLog(item, slot.id)}
                            >
                              {slot.label}
                            </DropdownMenuItem>
                          ))}
                        </DropdownMenuContent>
                      </DropdownMenu>
                    )}
                  </div>
                );
              })}
            </div>
          )}
        </div>
      )}
    </div>
  );
}

function SourceLink({ url }: { url: string }) {
  let host = url;
  try {
    host = new URL(url).hostname.replace(/^www\./, "");
  } catch {
    /* keep raw */
  }
  return (
    <a
      href={url}
      target="_blank"
      rel="noreferrer"
      className="flex items-center gap-1.5 text-xs font-medium text-[#FF7340] hover:underline"
    >
      <ExternalLink className="h-3 w-3 shrink-0" />
      <span className="truncate">{host}</span>
    </a>
  );
}

export const EmberDmCard = memo(EmberDmCardBase);
