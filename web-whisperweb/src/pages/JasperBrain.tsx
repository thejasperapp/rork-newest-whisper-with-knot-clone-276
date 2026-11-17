import { type ReactNode, useEffect, useMemo, useState } from "react";
import { useNavigate } from "react-router-dom";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowLeft,
  BookOpenText,
  Brain,
  Check,
  Copy,
  FileCode,
  Globe,
  LayoutTemplate,
  Loader2,
  Lock,
  MessageSquareText,
  PenLine,
  RefreshCw,
  Save,
  ScanSearch,
  ShieldCheck,
  Smartphone,
  Sparkles,
} from "lucide-react";
import { toast } from "sonner";

import { Header } from "@/components/Header";
import { useAuth } from "@/hooks/useAuth";
import { useMyBadge } from "@/hooks/useMyBadge";
import { timeAgo } from "@/lib/format";
import {
  JASPER_BRAIN_SECTIONS,
  composeJasperBrainBlock,
  fetchJasperBrain,
  saveJasperBrainSection,
  type JasperBrainRow,
} from "@/lib/jasperBrain";

/**
 * Jasper Brain — the team's spot to shape Jasper's intelligence ONCE for
 * both platforms. Sections written here are folded into every Jasper system
 * prompt on iOS AND web (chat, meetings, helpers) within ~5 minutes.
 * Admin/owner only; empty sections leave Jasper exactly as shipped.
 */

const SECTION_ICONS: Record<string, ReactNode> = {
  voice: <PenLine className="h-4 w-4" />,
  formatting: <MessageSquareText className="h-4 w-4" />,
  knowledge: <BookOpenText className="h-4 w-4" />,
  guardrails: <ShieldCheck className="h-4 w-4" />,
};

const SECTION_TINTS: Record<string, string> = {
  voice: "#F39057",
  formatting: "#409EFF",
  knowledge: "#33D499",
  guardrails: "#FA5973",
};

/**
 * The full real-code blueprint — 7 verbatim production Swift files plus
 * compile stubs, the ghost asset spec, behaviour rules, and a real mount
 * example — served from this site's public root for the Jasper app team.
 */
const BLUEPRINT_PATH = "/jasper-ui-blueprint.md";

export default function JasperBrain() {
  const navigate = useNavigate();
  const { profile } = useAuth();
  const badge = useMyBadge();
  const canEdit = badge === "admin" || badge === "owner";
  const queryClient = useQueryClient();

  const brainQuery = useQuery({
    queryKey: ["jasper-brain"],
    queryFn: fetchJasperBrain,
    enabled: canEdit,
    staleTime: 60_000,
  });

  const rowsBySection = useMemo(() => {
    const map = new Map<string, JasperBrainRow>();
    for (const r of brainQuery.data ?? []) map.set(r.section, r);
    return map;
  }, [brainQuery.data]);

  const [drafts, setDrafts] = useState<Record<string, string> | null>(null);
  useEffect(() => {
    if (drafts === null && brainQuery.data) {
      const next: Record<string, string> = {};
      for (const meta of JASPER_BRAIN_SECTIONS) {
        next[meta.id] = rowsBySection.get(meta.id)?.content ?? "";
      }
      setDrafts(next);
    }
  }, [brainQuery.data, drafts, rowsBySection]);

  const saveMutation = useMutation({
    mutationFn: async (sectionId: string) => {
      const meta = JASPER_BRAIN_SECTIONS.find((m) => m.id === sectionId);
      await saveJasperBrainSection(
        sectionId,
        meta?.title ?? sectionId,
        drafts?.[sectionId] ?? "",
        profile?.username ?? "admin"
      );
      return sectionId;
    },
    onSuccess: () => {
      toast.success("Saved — live on iOS + web within 5 minutes");
      void queryClient.invalidateQueries({ queryKey: ["jasper-brain"] });
    },
    onError: () => {
      toast.error("Couldn't save — check the database update and your access.");
    },
  });

  const preview = useMemo(() => composeJasperBrainBlock(drafts ?? {}), [drafts]);

  const [copiedSpec, setCopiedSpec] = useState<boolean>(false);
  const copySpec = (): void => {
    const url = `${window.location.origin}${BLUEPRINT_PATH}`;
    void navigator.clipboard
      .writeText(url)
      .then(() => {
        setCopiedSpec(true);
        toast.success("Blueprint link copied — send it to the Jasper app's builder");
        window.setTimeout(() => setCopiedSpec(false), 1600);
      })
      .catch(() => toast.error("Couldn't copy — open the file and share its URL."));
  };

  return (
    <div>
      <Header
        title="Jasper Brain"
        left={
          <button
            onClick={() => navigate(-1)}
            aria-label="Back"
            className="glass flex h-10 w-10 items-center justify-center rounded-full border border-border/60 shadow-sm transition-transform active:scale-90"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
        }
        right={<span className="h-10 w-10" />}
      />

      <div className="px-4 pb-24 pt-2">
        <div className="mx-auto max-w-2xl space-y-3.5">
          {/* Hero — one intelligence, two apps */}
          <div
            className="rounded-[22px] p-4 text-white"
            style={{
              background: "linear-gradient(135deg, #24201D 0%, #3A2A1E 55%, #4A2E1A 100%)",
              border: "1px solid rgba(243,144,87,0.35)",
            }}
          >
            <div className="flex items-start gap-3">
              <img
                src="/jasper-ghost.png"
                alt="Jasper"
                className="h-12 w-12 shrink-0 object-contain"
                loading="lazy"
              />
              <div className="min-w-0 flex-1">
                <p className="flex items-center gap-1.5 text-[15px] font-black">
                  <Brain className="h-4 w-4 text-[#F39057]" />
                  One intelligence, two apps
                </p>
                <p className="mt-1 text-[12px] leading-relaxed text-white/70">
                  Whatever you write below is folded into <b>every</b> Jasper answer — chat,
                  meetings, helpers — on both apps. No redeploy, no app update. Empty sections
                  change nothing.
                </p>
                <div className="mt-2.5 flex flex-wrap items-center gap-1.5">
                  <span className="flex items-center gap-1 rounded-full bg-white/10 px-2.5 py-1 text-[10px] font-bold">
                    <Smartphone className="h-3 w-3 text-[#F39057]" />
                    Live on iOS
                  </span>
                  <span className="flex items-center gap-1 rounded-full bg-white/10 px-2.5 py-1 text-[10px] font-bold">
                    <Globe className="h-3 w-3 text-[#33D499]" />
                    Live on web
                  </span>
                  <span className="rounded-full bg-white/10 px-2.5 py-1 text-[10px] font-bold text-white/70">
                    ~5-min cache
                  </span>
                </div>
              </div>
            </div>
          </div>

          {!canEdit ? (
            <div className="rounded-2xl border border-border/60 bg-card p-6 text-center shadow-sm">
              <Lock className="mx-auto h-8 w-8 text-muted-foreground" />
              <p className="mt-2 text-[14px] font-black">Jasper Brain is team-only</p>
              <p className="mx-auto mt-1 max-w-sm text-[12px] leading-relaxed text-muted-foreground">
                Admins and the owner shape Jasper's shared rules here. If you were just granted
                access, refresh in a moment.
              </p>
            </div>
          ) : brainQuery.isLoading ? (
            <div className="flex justify-center py-12">
              <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
            </div>
          ) : brainQuery.isError ? (
            <div className="rounded-2xl border border-border/60 bg-card p-6 text-center shadow-sm">
              <RefreshCw className="mx-auto h-8 w-8 text-muted-foreground" />
              <p className="mt-2 text-[14px] font-black">One-time database update needed</p>
              <p className="mx-auto mt-1 max-w-sm text-[12px] leading-relaxed text-muted-foreground">
                Run <code className="rounded bg-muted px-1 py-0.5">supabase/jasper-brain.sql</code>{" "}
                in the Supabase SQL editor, then try again. Until then Jasper keeps behaving
                exactly as shipped.
              </p>
              <button
                onClick={() => void brainQuery.refetch()}
                className="mt-3 inline-flex h-9 items-center gap-1.5 rounded-full bg-[#E76F3A] px-4 text-[12px] font-bold text-white transition-transform active:scale-95"
              >
                <RefreshCw className="h-3.5 w-3.5" />
                Try again
              </button>
            </div>
          ) : (
            <>
              {JASPER_BRAIN_SECTIONS.map((meta) => {
                const row = rowsBySection.get(meta.id);
                const draft = drafts?.[meta.id] ?? "";
                const saved = row?.content ?? "";
                const dirty = draft !== saved;
                const saving = saveMutation.isPending && saveMutation.variables === meta.id;
                const tint = SECTION_TINTS[meta.id] ?? "#F39057";
                return (
                  <div
                    key={meta.id}
                    className="rounded-2xl border border-border/60 bg-card p-4 shadow-sm"
                  >
                    <div className="flex items-center gap-2.5">
                      <span
                        className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full"
                        style={{ background: `${tint}1f`, color: tint }}
                      >
                        {SECTION_ICONS[meta.id]}
                      </span>
                      <div className="min-w-0 flex-1">
                        <p className="text-[13px] font-black leading-tight">{meta.title}</p>
                        <p className="text-[11px] leading-snug text-muted-foreground">
                          {meta.hint}
                        </p>
                      </div>
                    </div>
                    <textarea
                      value={draft}
                      onChange={(e) =>
                        setDrafts((d) => ({ ...(d ?? {}), [meta.id]: e.target.value }))
                      }
                      placeholder={meta.placeholder}
                      rows={4}
                      className="mt-3 w-full resize-y rounded-xl border border-border/60 bg-background px-3 py-2.5 text-[13px] leading-relaxed outline-none transition-colors focus:border-[#F39057]/60"
                    />
                    <div className="mt-2 flex items-center justify-between gap-2">
                      <p className="min-w-0 truncate text-[10px] font-semibold text-muted-foreground">
                        {row?.updated_by
                          ? `Updated by @${row.updated_by} · ${timeAgo(row.updated_at)}`
                          : "Not written yet"}
                      </p>
                      <button
                        onClick={() => saveMutation.mutate(meta.id)}
                        disabled={!dirty || saving}
                        className="inline-flex h-8 shrink-0 items-center gap-1.5 rounded-full bg-[#E76F3A] px-3.5 text-[11px] font-bold text-white transition-all active:scale-95 disabled:opacity-40"
                      >
                        {saving ? (
                          <Loader2 className="h-3 w-3 animate-spin" />
                        ) : (
                          <Save className="h-3 w-3" />
                        )}
                        {dirty ? "Save" : "Saved"}
                      </button>
                    </div>
                  </div>
                );
              })}

              <details className="rounded-2xl border border-border/60 bg-card p-4 shadow-sm">
                <summary className="cursor-pointer select-none text-[13px] font-black">
                  What Jasper actually reads
                </summary>
                <pre className="mt-3 max-h-72 overflow-y-auto whitespace-pre-wrap rounded-xl bg-muted/60 p-3 font-mono text-[11px] leading-relaxed text-foreground/80">
                  {preview || "(empty — Jasper behaves exactly as shipped)"}
                </pre>
              </details>
            </>
          )}

          {/* UI blueprint — the REAL production code (grammar, modals, mascot,
              dock animations) served as a shareable file for the Jasper app. */}
          <div className="rounded-2xl border border-border/60 bg-card p-4 shadow-sm">
            <div className="flex items-start justify-between gap-2">
              <p className="flex items-center gap-1.5 text-[13px] font-black">
                <LayoutTemplate className="h-4 w-4 text-[#33D499]" />
                Jasper UI blueprint — share with the Jasper app
              </p>
              <div className="flex shrink-0 items-center gap-1.5">
                <a
                  href={BLUEPRINT_PATH}
                  target="_blank"
                  rel="noreferrer"
                  className="inline-flex h-8 items-center gap-1.5 rounded-full border border-border/60 bg-background px-3 text-[11px] font-bold transition-all active:scale-95"
                >
                  <FileCode className="h-3 w-3 text-[#0E9F76]" />
                  Open
                </a>
                <button
                  onClick={copySpec}
                  className="inline-flex h-8 items-center gap-1.5 rounded-full bg-[#0E9F76] px-3.5 text-[11px] font-bold text-white transition-all active:scale-95"
                >
                  {copiedSpec ? (
                    <Check className="h-3 w-3" />
                  ) : (
                    <Copy className="h-3 w-3" />
                  )}
                  {copiedSpec ? "Copied" : "Copy link"}
                </button>
              </div>
            </div>
            <p className="mt-1 text-[11px] leading-snug text-muted-foreground">
              Not a description — the file at{" "}
              <code className="rounded bg-muted px-1 py-0.5">/jasper-ui-blueprint.md</code>{" "}
              carries the REAL production Swift, verbatim: the reply grammar parser, the
              modal shells, the living mascot rig, the analysis dock with its
              matched-geometry morph, the thinking rail, the personality system, and the
              ember glow kit. Send the link to the Jasper app's builder and it can port
              the surfaces one-to-one.
            </p>

            <div className="mt-3 rounded-xl border border-border/50 bg-background/60 p-3">
              <p className="flex items-center gap-1.5 text-[12px] font-black">
                <Brain className="h-3.5 w-3.5 text-[#F39057]" />
                The Jasper Intelligence surface
              </p>
              <ul className="mt-1.5 space-y-1 text-[11.5px] leading-relaxed text-muted-foreground">
                <li>· Mint-shell personality pill with the LIVING mascot peeking from behind its top edge.</li>
                <li>· Personality stage — the ghost lineup under a soft beam; Original / Guardian / Scientist / Drill Sergeant tints.</li>
                <li>· Structured replies render as interactive cards (plan/workout/deck grammar), never raw text.</li>
                <li>· Expanded tools ride dark glass sheets; mint + ember palette.</li>
              </ul>
            </div>

            <div className="mt-2.5 rounded-xl border border-border/50 bg-background/60 p-3">
              <p className="flex items-center gap-1.5 text-[12px] font-black">
                <ScanSearch className="h-3.5 w-3.5 text-[#33D499]" />
                The auto-analysis dock (“Jasper's read”)
              </p>
              <ul className="mt-1.5 space-y-1 text-[11.5px] leading-relaxed text-muted-foreground">
                <li>· Collapsed: a 34pt mint capsule pinned bottom-center, mascot peeking over the top; springs in with a 0.4s delay.</li>
                <li>· Tap → matched-geometry morph into the dark glass assistant box; the analysis runs ONLY then (credit guardrail), cached per lens.</li>
                <li>· Footer chips: lenses re-run the same context through a different instruction; perform chips open host tools.</li>
                <li>· Personality tint follows the saved mode; honest empty state when there's nothing to analyze.</li>
                <li>· Mounted today: profile reads (Icebreaker · Common ground) and the recruiter pipeline (Rank · Outreach · Stale).</li>
                <li>· Jasper app: mount the same dock on workout / nutrition / sleep screens with its own lenses — the full source is in the file.</li>
              </ul>
            </div>

            <div className="mt-2.5 rounded-xl border border-border/50 bg-background/60 p-3">
              <p className="flex items-center gap-1.5 text-[12px] font-black">
                <FileCode className="h-3.5 w-3.5 text-[#409EFF]" />
                Inside the file — 7 production files, verbatim
              </p>
              <ul className="mt-1.5 space-y-1 font-mono text-[10.5px] leading-relaxed text-muted-foreground">
                <li>WhisperEmberCoachMode.swift — personalities, exact accent hexes, MODE grammar</li>
                <li>WhisperEmberPillStyle.swift — the mint shell + the modal/sheet theme (drifting blooms)</li>
                <li>WhisperEmberMascot.swift — the breathing / blinking / acted-expression eye rig</li>
                <li>JasperAnalysisDock.swift — pill → glass-box morph, cached lenses, perform chips</li>
                <li>WhisperEmberThinkingSteps.swift — the scripted analysis loading rail</li>
                <li>WhisperEmberRichText.swift — the reply grammar parser (headings, bullets, dividers)</li>
                <li>JasperGlowKit.swift — brand tokens, glow boxes, confirmation + walkthrough modals</li>
              </ul>
              <p className="mt-2 text-[10.5px] leading-snug text-muted-foreground">
                Plus the tiny stubs to compile standalone, the ghost template asset spec
                (846×839 with exact eye rects), the behaviour rules (tap-to-run, per-lens
                caching), and the recruiter dock mount verbatim.
              </p>
            </div>
          </div>

          {/* Parity map — what's already shared in code */}
          <div className="rounded-2xl border border-border/60 bg-card p-4 shadow-sm">
            <p className="flex items-center gap-1.5 text-[13px] font-black">
              <Sparkles className="h-4 w-4 text-[#F39057]" />
              Already identical by design
            </p>
            <p className="mt-1 text-[11px] leading-snug text-muted-foreground">
              These ship in code on both apps. Your sections above layer on top — same block,
              same order, both platforms.
            </p>
            <ul className="mt-2.5 space-y-1.5 text-[12px] leading-relaxed">
              <li>
                <b>Personality modes</b> — Original / Guardian / Scientist / Drill Sergeant, picked
                per question with the same MODE grammar line.
              </li>
              <li>
                <b>The Jasper UI language</b> — mascot pill → dock → glass sheet, mint/ember
                palette, personality chips.
              </li>
              <li>
                <b>Card grammar</b> — interactive plan/workout cards and deck offers parsed from
                the same reply tokens.
              </li>
              <li>
                <b>Live grounding</b> — viewer macros, coach client snapshots, and creator
                analytics ride along with asks on both apps.
              </li>
              <li>
                <b>Credit guardrails</b> — tap-to-run AI, cached answers, capped context sizes.
              </li>
            </ul>
          </div>
        </div>
      </div>
    </div>
  );
}
