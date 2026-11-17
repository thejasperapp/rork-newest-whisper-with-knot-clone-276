import { useState } from "react";
import {
  ChevronLeft,
  ChevronRight,
  Flame,
  MessageCircleQuestion,
  Plus,
  Quote,
  RotateCw,
  X,
} from "lucide-react";

import { EmberMascot } from "@/components/EmberMascot";
import {
  JasperKitKeyframes,
  JasperMintPill,
  jasperBoxStyle,
} from "@/components/JasperIntelKit";
import { jasperPillPalette } from "@/lib/jasperIntel";
import { coachModeInfo, loadCoachMode } from "@/lib/emberBrain";
import {
  dailyStorySpark,
  fileToDataUrl,
  storySparks,
  type StorySparks,
} from "@/lib/storyJasper";

type Panel = "menu" | "spark" | "captions" | "questions";

const PANEL_TITLES: Record<Panel, string> = {
  menu: "Story studio",
  spark: "Today's spark",
  captions: "Caption ideas",
  questions: "Ask your viewers",
};

/**
 * Jasper in the story editor — the SAME meeting-style pill language as the
 * analysis docks: the living mascot peeks from behind the mint pill floating
 * over the canvas; tapping opens the dark glass box with a menu of what he
 * can do (Today's spark · Caption ideas · Ask your viewers). Every pick
 * lands on the canvas as a real draggable sticker.
 */
export function StoryJasperDock({
  file,
  onCaption,
  onQuestion,
}: {
  file: File;
  onCaption: (text: string) => void;
  onQuestion: (text: string) => void;
}) {
  const [open, setOpen] = useState<boolean>(false);
  const [panel, setPanel] = useState<Panel>("menu");
  const [spark, setSpark] = useState<string | null>(null);
  const [sparks, setSparks] = useState<StorySparks | null>(null);
  const [loading, setLoading] = useState<boolean>(false);
  const [failed, setFailed] = useState<boolean>(false);
  const mode = loadCoachMode();
  const info = coachModeInfo(mode);
  const palette = jasperPillPalette(mode);

  const warmSpark = (): void => {
    if (!spark) void dailyStorySpark().then(setSpark);
  };

  const ensureSparks = (force = false): void => {
    if ((sparks && !force) || loading) return;
    setLoading(true);
    setFailed(false);
    void (async () => {
      try {
        const dataUrl = await fileToDataUrl(file);
        const result = await storySparks(dataUrl);
        if (result) setSparks(result);
        else setFailed(true);
      } catch {
        setFailed(true);
      } finally {
        setLoading(false);
      }
    })();
  };

  const closeDock = (): void => {
    setOpen(false);
    setPanel("menu");
  };

  const applyCaption = (text: string): void => {
    onCaption(text);
    closeDock();
  };

  const applyQuestion = (text: string): void => {
    onQuestion(text);
    closeDock();
  };

  const mascot = (
    <span
      className="pointer-events-none absolute left-1/2 z-0 -translate-x-1/2"
      style={{
        top: -26,
        animation: loading ? undefined : "jasper-mascot-bob 1.7s ease-in-out infinite",
      }}
    >
      {loading && (
        <span
          className="absolute left-1/2 top-1/2 h-11 w-11 -translate-x-1/2 -translate-y-1/2 rounded-full"
          style={{
            background: info.accent,
            filter: "blur(14px)",
            animation: "jasper-glow-pulse 0.9s ease-in-out infinite",
          }}
        />
      )}
      <EmberMascot
        size={50}
        coachMode={mode}
        isActive={loading}
        expression={loading ? "thinking" : info.signatureExpression}
        cyclesExpressions={!loading}
      />
    </span>
  );

  const menuRow = (
    icon: React.ReactNode,
    title: string,
    subtitle: string,
    onClick: () => void
  ) => (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-[14px] border border-white/[0.08] bg-white/[0.05] px-2.5 py-2.5 text-left transition-colors hover:bg-white/10"
    >
      <span
        className="flex h-9 w-9 shrink-0 items-center justify-center rounded-[10px]"
        style={{ background: `${info.accent}2E`, color: info.softAccent }}
      >
        {icon}
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[13.5px] font-bold text-white">{title}</span>
        <span className="block truncate text-[11px] text-white/55">{subtitle}</span>
      </span>
      <ChevronRight className="h-3.5 w-3.5 shrink-0 text-white/40" />
    </button>
  );

  const ideaRows = (items: string[], apply: (t: string) => void) => (
    <div className="space-y-1.5">
      {items.map((item) => (
        <button
          key={item}
          type="button"
          onClick={() => apply(item)}
          className="flex w-full items-center gap-2.5 rounded-xl border border-white/[0.08] bg-white/[0.05] px-3 py-2.5 text-left transition-colors hover:bg-white/10"
        >
          <span className="min-w-0 flex-1 text-[13.5px] font-semibold leading-snug text-white">
            {item}
          </span>
          <Plus
            className="h-4 w-4 shrink-0"
            style={{ color: info.softAccent }}
            strokeWidth={3}
          />
        </button>
      ))}
      <button
        type="button"
        onClick={() => {
          setSparks(null);
          ensureSparks(true);
        }}
        disabled={loading}
        className="flex items-center gap-1.5 rounded-full border border-white/[0.12] bg-white/[0.08] px-3 py-[7px] text-[12px] font-bold text-white/85 transition-colors hover:bg-white/15 disabled:opacity-50"
      >
        <RotateCw className={loading ? "h-2.5 w-2.5 animate-spin" : "h-2.5 w-2.5"} strokeWidth={3} />
        {loading ? "Reading…" : "New ideas"}
      </button>
    </div>
  );

  const loadingRows = (
    <div className="space-y-1.5">
      {[0, 1, 2].map((i) => (
        <div key={i} className="h-11 animate-pulse rounded-xl bg-white/[0.06]" />
      ))}
      <p className="text-[11px] text-white/50">Jasper is reading your photo…</p>
    </div>
  );

  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-3 z-30 flex justify-center px-4">
      <JasperKitKeyframes />
      {open ? (
        <div
          className="pointer-events-auto w-[min(340px,calc(100vw-40px))]"
          style={{
            animation: "jasper-dock-open 450ms cubic-bezier(0.34, 1.3, 0.5, 1) both",
            transformOrigin: "bottom center",
          }}
        >
          <div className="relative overflow-visible pb-2.5" style={jasperBoxStyle(mode)}>
            <span className="absolute -top-6 left-1/2 z-0 -translate-x-1/2">{mascot}</span>
            <div className="relative z-10 mx-2.5 mt-2.5">
              <JasperMintPill
                mode={mode}
                className="h-9 w-full justify-between pl-2.5 pr-[7px]"
              >
                <span className="flex min-w-0 items-center gap-1.5">
                  {panel !== "menu" && (
                    <button
                      type="button"
                      aria-label="Back"
                      onClick={() => setPanel("menu")}
                      className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full"
                      style={{ background: `${palette.ink}14`, color: `${palette.ink}B3` }}
                    >
                      <ChevronLeft className="h-3 w-3" strokeWidth={3.2} />
                    </button>
                  )}
                  <span
                    className="truncate pl-1 text-[14px] font-black"
                    style={{ color: palette.ink }}
                  >
                    {PANEL_TITLES[panel]}
                  </span>
                </span>
                <button
                  type="button"
                  aria-label="Close Jasper"
                  onClick={closeDock}
                  className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full"
                  style={{ background: `${palette.ink}14`, color: `${palette.ink}8C` }}
                >
                  <X className="h-2.5 w-2.5" strokeWidth={3.2} />
                </button>
              </JasperMintPill>
            </div>

            <div className="max-h-[300px] overflow-y-auto px-3 py-3">
              {panel === "menu" && (
                <div className="space-y-1.5">
                  {menuRow(
                    <Flame className="h-4 w-4" />,
                    "Today's spark",
                    spark ?? "One prompt a day — warming it up…",
                    () => {
                      setPanel("spark");
                      warmSpark();
                    }
                  )}
                  {menuRow(
                    <Quote className="h-4 w-4" />,
                    "Caption ideas",
                    "Jasper reads this exact photo — 3 vibes",
                    () => {
                      setPanel("captions");
                      ensureSparks();
                    }
                  )}
                  {menuRow(
                    <MessageCircleQuestion className="h-4 w-4" />,
                    "Ask your viewers",
                    "Question stickers people actually answer",
                    () => {
                      setPanel("questions");
                      ensureSparks();
                    }
                  )}
                </div>
              )}

              {panel === "spark" && (
                <div
                  className="rounded-[14px] border bg-white/[0.05] p-3"
                  style={{ borderColor: `${info.accent}4D` }}
                >
                  <p
                    className="flex items-center gap-1 text-[9px] font-black tracking-[0.14em]"
                    style={{ color: info.softAccent }}
                  >
                    <Flame className="h-2.5 w-2.5" /> TODAY'S SPARK
                  </p>
                  <p className="mt-1.5 text-[17px] font-bold leading-snug text-white">
                    {spark ?? "Warming one up…"}
                  </p>
                  <button
                    type="button"
                    disabled={!spark}
                    onClick={() => spark && applyCaption(spark)}
                    className="mt-2.5 inline-flex items-center gap-1.5 rounded-full bg-white px-3.5 py-1.5 text-[12.5px] font-bold text-black disabled:opacity-40"
                  >
                    <Plus className="h-3 w-3" strokeWidth={3.4} /> Add to story
                  </button>
                  <p className="mt-2 text-[10.5px] text-white/45">
                    One spark a day — a fresh one lands tomorrow.
                  </p>
                </div>
              )}

              {panel === "captions" &&
                (sparks?.captions.length
                  ? ideaRows(sparks.captions, applyCaption)
                  : loading
                    ? loadingRows
                    : (
                      <div className="space-y-2">
                        <p className="text-[12.5px] text-white/60">
                          {failed ? "Couldn't read the photo right now." : "No ideas yet."}
                        </p>
                        {ideaRows([], applyCaption)}
                      </div>
                    ))}

              {panel === "questions" &&
                (sparks?.questions.length
                  ? ideaRows(sparks.questions, applyQuestion)
                  : loading
                    ? loadingRows
                    : (
                      <div className="space-y-2">
                        <p className="text-[12.5px] text-white/60">
                          {failed ? "Couldn't read the photo right now." : "No ideas yet."}
                        </p>
                        {ideaRows([], applyQuestion)}
                      </div>
                    ))}
            </div>
          </div>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => {
            setOpen(true);
            warmSpark();
          }}
          className="group pointer-events-auto relative mt-7 transition-transform hover:scale-[1.03] active:scale-95"
          style={{
            animation: "jasper-peek-in 750ms cubic-bezier(0.34, 1.45, 0.64, 1) 500ms both",
          }}
          aria-label="Open Jasper story tools"
        >
          {mascot}
          <JasperMintPill mode={mode} className="relative z-10 h-[34px] px-5">
            <span className="text-[14px] font-black" style={{ color: palette.ink }}>
              Jasper
            </span>
          </JasperMintPill>
        </button>
      )}
    </div>
  );
}
