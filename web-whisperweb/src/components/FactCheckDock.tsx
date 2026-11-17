import { useCallback, useState } from "react";
import {
  AlertTriangle,
  CheckCircle2,
  ExternalLink,
  HelpCircle,
  RotateCw,
  Sparkles,
  X,
  XCircle,
} from "lucide-react";

import { EmberMascot } from "@/components/EmberMascot";
import {
  JasperKitKeyframes,
  JasperMintPill,
  JasperThinkingRail,
  jasperBoxStyle,
} from "@/components/JasperIntelKit";
import { factCheck, type FactCheck, type Verdict } from "@/lib/ember";
import { jasperPillPalette } from "@/lib/jasperIntel";
import { coachModeInfo, loadCoachMode } from "@/lib/emberBrain";
import { cn } from "@/lib/utils";

const VERDICT_META: Record<Verdict, { label: string; color: string }> = {
  true: { label: "TRUE", color: "#22c55e" },
  mostly_true: { label: "MOSTLY TRUE", color: "#84cc16" },
  misleading: { label: "MISLEADING", color: "#f59e0b" },
  false: { label: "FALSE", color: "#ef4444" },
  unverified: { label: "UNVERIFIED", color: "#94a3b8" },
};

function verdictIcon(v: Verdict) {
  if (v === "true" || v === "mostly_true") return CheckCircle2;
  if (v === "false") return XCircle;
  if (v === "misleading") return AlertTriangle;
  return HelpCircle;
}

/**
 * The article fact-check dock — the SAME meeting-style pill language as the
 * analysis docks (mascot peeking behind the mint pill, pinned right above
 * the mobile nav): tap to run Jasper's research read of the article, cached
 * per claim so reopening never re-bills.
 */
export function FactCheckDock({
  claim,
  className,
}: {
  claim: string;
  className?: string;
}) {
  const [open, setOpen] = useState<boolean>(false);
  const [busy, setBusy] = useState<boolean>(false);
  const [result, setResult] = useState<FactCheck | null>(null);
  const [expanded, setExpanded] = useState<boolean>(false);
  const mode = loadCoachMode();
  const info = coachModeInfo(mode);
  const palette = jasperPillPalette(mode);

  const run = useCallback(async (): Promise<void> => {
    setBusy(true);
    try {
      setResult(await factCheck(claim));
    } finally {
      setBusy(false);
    }
  }, [claim]);

  const mascot = (
    <span
      className="pointer-events-none absolute left-1/2 z-0 -translate-x-1/2"
      style={{
        top: -26,
        animation: busy ? undefined : "jasper-mascot-bob 1.7s ease-in-out infinite",
      }}
    >
      {busy && (
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
        isActive={busy}
        expression={busy ? "thinking" : result ? info.signatureExpression : "calm"}
        cyclesExpressions={!busy && !result}
      />
    </span>
  );

  const meta = result ? VERDICT_META[result.verdict] : null;
  const VerdictIcon = result ? verdictIcon(result.verdict) : HelpCircle;

  return (
    <div
      className={cn(
        "pointer-events-none fixed inset-x-0 bottom-20 z-40 flex justify-center px-4 lg:bottom-6",
        className
      )}
    >
      <JasperKitKeyframes />
      {open ? (
        <div
          className="pointer-events-auto w-[min(380px,calc(100vw-24px))]"
          style={{
            animation: "jasper-dock-open 450ms cubic-bezier(0.34, 1.3, 0.5, 1) both",
            transformOrigin: "bottom center",
          }}
        >
          <div className="relative overflow-visible pb-2.5" style={jasperBoxStyle(mode)}>
            <span className="absolute -top-6 left-1/2 z-0 -translate-x-1/2">{mascot}</span>
            <div className="relative z-10 mx-2.5 mt-2.5">
              <JasperMintPill mode={mode} className="h-9 w-full justify-between pl-4 pr-[7px]">
                <span className="truncate text-[14px] font-black" style={{ color: palette.ink }}>
                  Jasper fact check
                </span>
                <button
                  type="button"
                  aria-label="Close fact check"
                  onClick={() => setOpen(false)}
                  className="flex h-[22px] w-[22px] shrink-0 items-center justify-center rounded-full transition-colors"
                  style={{ background: `${palette.ink}14`, color: `${palette.ink}8C` }}
                >
                  <X className="h-2.5 w-2.5" strokeWidth={3.2} />
                </button>
              </JasperMintPill>
            </div>

            <div className="max-h-[300px] overflow-y-auto px-3.5 py-3">
              {busy ? (
                <JasperThinkingRail mode={mode} analytical />
              ) : result && meta ? (
                <div
                  className="relative rounded-[16px] border bg-white/[0.05] py-3 pl-4 pr-3"
                  style={{ borderColor: `${info.accent}33` }}
                >
                  <span
                    className="absolute bottom-3 left-1.5 top-3 w-[3px] rounded-full"
                    style={{ background: `${meta.color}CC` }}
                  />
                  <div className="flex items-center gap-1.5">
                    <Sparkles className="h-2.5 w-2.5" style={{ color: info.softAccent }} />
                    <span
                      className="text-[9px] font-black tracking-[0.14em]"
                      style={{ color: info.softAccent }}
                    >
                      JASPER
                    </span>
                    <span
                      className="ml-auto inline-flex items-center gap-1 rounded-full px-2.5 py-1 text-[9px] font-black tracking-wider text-white"
                      style={{ background: meta.color }}
                    >
                      <VerdictIcon className="h-2.5 w-2.5" strokeWidth={3} />
                      {meta.label}
                    </span>
                  </div>
                  <p className="mt-2 text-[14px] font-semibold leading-snug text-white/95">
                    {result.summary}
                  </p>
                  {expanded && (
                    <>
                      {result.explanation && result.explanation !== result.summary && (
                        <p className="mt-2 text-[12.5px] leading-relaxed text-white/75">
                          {result.explanation}
                        </p>
                      )}
                      {result.sources.length > 0 && (
                        <div className="mt-2 space-y-1">
                          {result.sources.slice(0, 3).map((s) => {
                            let host = s;
                            try {
                              host = new URL(s).host;
                            } catch {
                              /* keep raw */
                            }
                            return (
                              <a
                                key={s}
                                href={s}
                                target="_blank"
                                rel="noreferrer"
                                className="flex items-center gap-1.5 text-[12px] font-semibold text-sky-400 hover:underline"
                              >
                                <ExternalLink className="h-3 w-3" />
                                <span className="truncate">{host}</span>
                              </a>
                            );
                          })}
                        </div>
                      )}
                    </>
                  )}
                  <button
                    type="button"
                    onClick={() => setExpanded((e) => !e)}
                    className="mt-2 text-[12px] font-bold text-white/70 hover:text-white"
                  >
                    {expanded ? "Show less" : "Why this verdict"}
                  </button>
                  <p className="mt-1.5 text-[10.5px] text-white/45">
                    AI research read — check the sources yourself.
                  </p>
                </div>
              ) : (
                <p className="text-[13px] text-white/65">
                  Couldn't research this one right now — re-run to try again.
                </p>
              )}
            </div>

            <div className="px-3">
              <button
                type="button"
                onClick={() => void run()}
                disabled={busy}
                className="flex items-center gap-1.5 rounded-full border border-white/[0.12] bg-white/[0.08] px-3 py-[7px] text-[12px] font-bold text-white/85 transition-colors hover:bg-white/15 disabled:opacity-50"
              >
                <RotateCw className={cn("h-2.5 w-2.5", busy && "animate-spin")} strokeWidth={3} />
                {busy ? "Checking…" : "Re-run"}
              </button>
            </div>
          </div>
        </div>
      ) : (
        <button
          type="button"
          onClick={() => {
            setOpen(true);
            if (!result && !busy) void run();
          }}
          className="group pointer-events-auto relative mt-7 transition-transform hover:scale-[1.03] active:scale-95"
          style={{
            animation: "jasper-peek-in 750ms cubic-bezier(0.34, 1.45, 0.64, 1) 400ms both",
          }}
          aria-label="Run Jasper fact check"
        >
          {mascot}
          <JasperMintPill mode={mode} className="relative z-10 h-[34px] px-5">
            <span className="text-[14px] font-black" style={{ color: palette.ink }}>
              {busy ? "Checking…" : "Fact check"}
            </span>
          </JasperMintPill>
        </button>
      )}
    </div>
  );
}
