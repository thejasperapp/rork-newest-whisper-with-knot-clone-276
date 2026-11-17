import { useMemo, useState, type ReactNode } from "react";
import {
  ArrowRight,
  CheckCircle2,
  ChevronDown,
  Copy,
  FileText,
  ListChecks,
  MessageSquareQuote,
  Share2,
  Sparkles,
  Users,
} from "lucide-react";
import { toast } from "sonner";

import { cn } from "@/lib/utils";
import { useAuth } from "@/hooks/useAuth";

import { useQuery } from "@tanstack/react-query";

import { MeetingSidekick } from "./MeetingSidekick";
import { JasperMeetingSavedContent } from './JasperMeetingSavedContent';
import { NotebookRecordingSources } from "./NotebookRecordingSources";
import { EmberMascot } from "@/components/EmberMascot";
import {
  JasperCanvasBackdrop,
  JasperKitKeyframes,
  useJasperSheetTheme,
} from "@/components/JasperIntelKit";
import { coachModeInfo, loadCoachMode } from "@/lib/emberBrain";
import { jasperBloom } from "@/lib/jasperIntel";
import { fetchTranscript, type MeetingTranscriptSegment } from "@/lib/meetings";

/**
 * The FULL-SCREEN meeting notes experience — the web twin of iOS's
 * WhisperMeetingNotesView. Jasper's adaptive canvas (personality blooms
 * drifting behind the cards), a hero card, formatted section cards
 * (key points, decisions, action items) and share actions.
 *
 * Used from the Meetings list ("Notes ready" rows) AND as the post-meeting
 * ended screen inside the room — the exact same screen in both places.
 */

interface NotesSection {
  title: string;
  paragraphs: string[];
  bullets: string[];
}

/** Splits `**Header**` markdown notes into titled sections with bullets. */
function parseNotesSections(notes: string): NotesSection[] {
  const sections: NotesSection[] = [];
  let current: NotesSection | null = null;
  const headerOnly = /^\*\*(.+?)\*\*:?\s*$/;
  const headerInline = /^\*\*(.+?)\*\*:?\s+(.+)$/;
  for (const rawLine of notes.split("\n")) {
    const line = rawLine.trim();
    if (!line) continue;
    const only = headerOnly.exec(line);
    const inline = only ? null : headerInline.exec(line);
    if (only || inline) {
      if (current) sections.push(current);
      current = {
        title: (only?.[1] ?? inline?.[1] ?? "Notes").replace(/\*\*/g, "").trim(),
        paragraphs: [],
        bullets: [],
      };
      const rest = inline?.[2]?.trim();
      if (rest) current.paragraphs.push(rest.replace(/\*\*/g, ""));
      continue;
    }
    if (!current) current = { title: "Summary", paragraphs: [], bullets: [] };
    if (/^[-•*]\s+/.test(line)) {
      current.bullets.push(line.replace(/^[-•*]\s+/, "").replace(/\*\*/g, ""));
    } else if (/^\d+[.)]\s+/.test(line)) {
      current.bullets.push(line.replace(/^\d+[.)]\s+/, "").replace(/\*\*/g, ""));
    } else {
      current.paragraphs.push(line.replace(/\*\*/g, ""));
    }
  }
  if (current) sections.push(current);
  return sections.filter((s) => s.paragraphs.length > 0 || s.bullets.length > 0);
}

/** Picks a section icon from its title, mirroring the iOS mapping. */
function sectionIcon(title: string) {
  const t = title.toLowerCase();
  if (t.includes("key") || t.includes("summary") || t.includes("overview")) return Sparkles;
  if (t.includes("decision")) return CheckCircle2;
  if (t.includes("action") || t.includes("task") || t.includes("to-do") || t.includes("todo"))
    return ListChecks;
  if (t.includes("next") || t.includes("follow")) return ArrowRight;
  if (t.includes("attendee") || t.includes("participant") || t.includes("people")) return Users;
  return FileText;
}

/**
 * The line that opens the transcript block inside a notes message — the exact
 * marker every client (web + iOS) splits on. Rides after the notes (and the
 * link line) so old clients still read the notes as before.
 */
export const NOTES_TRANSCRIPT_MARKER = "— Transcript —";

/** Safety cap on the transcript block — a multi-hour recording still sends. */
const TRANSCRIPT_WIRE_CAP = 60_000;

/** "speaker: line" transcript text — the same grammar iOS's fetchTranscriptPlain writes. */
export function transcriptPlainText(
  segments: Array<Pick<MeetingTranscriptSegment, "username" | "text">>,
): string {
  return segments
    .map((s) => `${(s.username || "speaker").replace(/^@/, "")}: ${s.text.trim()}`)
    .filter((line) => !/:\s*$/.test(line))
    .join("\n");
}

/** Appends the transcript block (when there is one) to a notes body. */
export function withTranscriptBlock(body: string, transcript?: string | null): string {
  const lines = (transcript ?? "").trim();
  if (!lines) return body;
  const capped = lines.length > TRANSCRIPT_WIRE_CAP ? `${lines.slice(0, TRANSCRIPT_WIRE_CAP)}\n…` : lines;
  return `${body}\n\n${NOTES_TRANSCRIPT_MARKER}\n${capped}`;
}

/** The plain-text notes body shared through DMs, email, and the clipboard —
 *  the FULL transcript rides along when the caller has it. */
export function meetingNotesShareText(title: string, notes: string, transcript?: string | null): string {
  const body = `\u{1F4CB} Meeting notes — ${title}\n\n${notes.trim().slice(0, 6000)}`;
  return withTranscriptBlock(body, transcript);
}

/**
 * The collapsible "who said what" card — the web twin of iOS's transcriptCard:
 * the first six lines visible, expandable to the whole conversation, each
 * line split into a heavy speaker + the words.
 */
export function TranscriptCard({
  transcript,
  style,
  accent,
  ink,
  muted,
}: {
  transcript: string;
  style: React.CSSProperties;
  accent: string;
  ink: string;
  muted: string;
}): JSX.Element | null {
  const [expanded, setExpanded] = useState<boolean>(false);
  const lines = useMemo(
    () => transcript.split("\n").map((l) => l.trim()).filter((l) => l.length > 0),
    [transcript],
  );
  if (lines.length === 0) return null;
  const visible = expanded ? lines : lines.slice(0, 6);
  return (
    <div className="p-3.5" style={style}>
      <button
        type="button"
        onClick={() => setExpanded((v) => !v)}
        className="flex w-full items-center gap-2 text-left"
        aria-expanded={expanded}
      >
        <MessageSquareQuote className="h-3.5 w-3.5 shrink-0" style={{ color: accent }} strokeWidth={2.8} />
        <span className="text-[10px] font-black uppercase tracking-[0.14em]" style={{ color: muted }}>
          Saved transcript
        </span>
        <span className="text-[10px] font-bold" style={{ color: muted, opacity: 0.7 }}>
          {lines.length} line{lines.length === 1 ? "" : "s"}
        </span>
        <ChevronDown
          className={cn("ml-auto h-3.5 w-3.5 shrink-0 transition-transform", expanded && "rotate-180")}
          style={{ color: muted }}
        />
      </button>
      <div className="mt-2.5 space-y-1.5">
        {visible.map((line, i) => {
          const idx = line.indexOf(":");
          const speaker = idx > 0 ? line.slice(0, idx) : null;
          const words = idx > 0 ? line.slice(idx + 1).trim() : line;
          return (
            <p key={`${i}-${line.slice(0, 24)}`} className="text-[12.5px] leading-snug">
              {speaker && (
                <span className="mr-1.5 font-extrabold" style={{ color: ink }}>
                  {speaker.replace(/^@/, "")}
                </span>
              )}
              <span style={{ color: muted }}>{words}</span>
            </p>
          );
        })}
      </div>
      {!expanded && lines.length > visible.length && (
        <button
          type="button"
          onClick={() => setExpanded(true)}
          className="mt-2 text-[11px] font-bold"
          style={{ color: muted }}
        >
          +{lines.length - visible.length} more — tap to expand
        </button>
      )}
    </div>
  );
}

export function MeetingNotesScreen({
  title,
  notes,
  onClose,
  subtitle,
  loading = false,
  actions,
  emptyContent,
  footnote,
  children,
  transcript,
  meetingId,
  embedded = false,
  recordingId,
}: {
  title: string;
  notes: string | null;
  onClose: () => void;
  /** Hero caption — defaults to the iOS line. */
  subtitle?: string;
  loading?: boolean;
  /** Replaces the default Share / Copy row (e.g. DM · Email · Copy). */
  actions?: ReactNode;
  /** Rendered when there are no notes and nothing is loading. */
  emptyContent?: ReactNode;
  footnote?: string;
  /** Extra sections below the notes (prospect eval, transcript…). */
  children?: ReactNode;
  /** "speaker: line" transcript already in hand (a notes DM carries it). */
  transcript?: string | null;
  /** When known and no transcript was handed in, the transcript is fetched
   *  from the meeting so the card is never missing on an older message. */
  meetingId?: string | null;
  /** Notebook recaps expand in place instead of covering the workspace. */
  embedded?: boolean;
  recordingId?: string | null;
}) {
  const { user } = useAuth();
  const [preferFreshTranscript, setPreferFreshTranscript] = useState<boolean>(false);
  const [sidekickOpened, setSidekickOpened] = useState<boolean>(false);
  const [sidekickVisible, setSidekickVisible] = useState<boolean>(false);
  const mode = loadCoachMode();
  const info = coachModeInfo(mode);
  const { theme, dark } = useJasperSheetTheme();
  const bloom = jasperBloom(mode, dark);
  const sections = useMemo(() => (notes ? parseNotesSections(notes) : []), [notes]);

  const inlineTranscript = (transcript ?? "").trim();
  const transcriptQuery = useQuery({
    queryKey: ["meeting-transcript", meetingId ?? ""],
    enabled: !!meetingId && (!inlineTranscript || preferFreshTranscript),
    queryFn: () => fetchTranscript(meetingId!),
    staleTime: 0,
    refetchInterval: 5000,
  });
  const transcriptText = useMemo(() => {
    if (inlineTranscript && !preferFreshTranscript) return inlineTranscript;
    const segments = transcriptQuery.data ?? [];
    return segments.length > 0 ? transcriptPlainText(segments) : "";
  }, [inlineTranscript, preferFreshTranscript, transcriptQuery.data]);
  const showsTranscript = (transcript !== undefined || meetingId != null) && transcriptText.length > 0;

  const copyNotes = (): void => {
    if (!notes) return;
    void navigator.clipboard?.writeText(meetingNotesShareText(title, notes, transcriptText || null));
    toast.success("Notes copied");
  };

  const shareNotes = (): void => {
    if (!notes) return;
    if (navigator.share) {
      void navigator
        .share({ title: `Meeting notes — ${title}`, text: meetingNotesShareText(title, notes, transcriptText || null) })
        .catch(() => undefined);
    } else {
      copyNotes();
    }
  };

  const card = (extra?: React.CSSProperties): React.CSSProperties => ({
    background: theme.card,
    border: `1px solid ${theme.stroke}`,
    borderRadius: 18,
    ...extra,
  });

  return (
    <div
      className={embedded ? "relative flex min-w-0 flex-col overflow-hidden rounded-2xl border border-border" : "fixed inset-0 z-[70] flex flex-col overflow-hidden"}
      style={{ background: theme.canvas, color: theme.ink }}
    >
      <JasperKitKeyframes />
      {!embedded && <JasperCanvasBackdrop bloom={bloom} lavender={theme.lavenderGlow} canvas={theme.canvas} />}

      {/* ── Top bar — centered title, Done trailing (iOS toolbar) ────────── */}
      <div className="relative z-10 flex h-[54px] shrink-0 items-center justify-center px-4 pt-[max(0px,env(safe-area-inset-top))]">
        <p className="text-[15px] font-black tracking-tight">Meeting notes</p>
        <button
          type="button"
          onClick={onClose}
          className="absolute right-4 text-[14px] font-bold transition-opacity hover:opacity-70"
          style={{ color: theme.ink }}
        >
          {embedded ? "Collapse" : "Done"}
        </button>
      </div>

      {/* ── Scroll canvas ─────────────────────────────────────────────────── */}
      <div className="relative z-10 min-h-0 flex-1 overflow-y-auto">
        <div className="mx-auto w-full max-w-2xl space-y-3.5 px-4 pb-[max(2.25rem,env(safe-area-inset-bottom))] pt-1.5">
          {/* Hero — mascot, meeting title, what these notes are. */}
          <div
            className="flex items-center gap-3 p-3.5"
            style={card({
              border: `1px solid ${info.accent}4D`,
              boxShadow: `0 9px 24px ${theme.cardShadow}`,
              animation: "ember-pop-in 340ms cubic-bezier(0.34, 1.3, 0.64, 1) both",
            })}
          >
            <span className="shrink-0">
              <EmberMascot size={40} coachMode={mode} isActive={loading} expression={loading ? "thinking" : "calm"} />
            </span>
            <div className="min-w-0 flex-1">
              <p className="line-clamp-2 text-[15.5px] font-extrabold leading-tight">{title}</p>
              <p className="mt-0.5 text-[12px]" style={{ color: theme.muted }}>
                {subtitle ?? "AI notes by Jasper · key points, decisions, action items"}
              </p>
            </div>
          </div>

          {loading ? (
            <div className="flex items-center gap-2.5 p-4" style={card()}>
              <EmberMascot size={24} coachMode={mode} isActive expression="thinking" />
              <p className="animate-pulse text-[13.5px] font-semibold" style={{ color: theme.muted }}>
                Writing the notes…
              </p>
            </div>
          ) : notes ? (
            <>
              {sections.length === 0 ? (
                <div className="p-3.5" style={card()}>
                  <p className="whitespace-pre-wrap text-[13.5px] leading-relaxed">
                    {notes.replace(/\*\*/g, "")}
                  </p>
                </div>
              ) : (
                sections.map((section, i) => {
                  const Icon = sectionIcon(section.title);
                  return (
                    <div
                      key={`${section.title}-${i}`}
                      className="p-3.5"
                      style={card({
                        animation: `ember-pop-in 360ms cubic-bezier(0.34, 1.3, 0.64, 1) ${80 + i * 70}ms both`,
                      })}
                    >
                      <div className="flex items-center gap-2">
                        <Icon className="h-3.5 w-3.5" style={{ color: info.deepAccent }} strokeWidth={2.8} />
                        <p
                          className="text-[10px] font-black uppercase tracking-[0.14em]"
                          style={{ color: theme.muted }}
                        >
                          {section.title}
                        </p>
                      </div>
                      {section.paragraphs.map((p, j) => (
                        <p key={j} className="mt-2 text-[13.5px] leading-relaxed">
                          {p}
                        </p>
                      ))}
                      {section.bullets.length > 0 && (
                        <div className="mt-2 space-y-1.5">
                          {section.bullets.map((b, j) => (
                            <div key={j} className="flex items-start gap-2">
                              <span
                                className="mt-[7px] h-[5px] w-[5px] shrink-0 rounded-full"
                                style={{ background: info.accent }}
                              />
                              <p className="min-w-0 flex-1 text-[13.5px] leading-relaxed">{b}</p>
                            </div>
                          ))}
                        </div>
                      )}
                    </div>
                  );
                })
              )}


              {/* Share actions — Share + Copy by default, or the caller's row. */}
              {actions ?? (
                <div className="flex gap-2.5 pt-0.5">
                  <button
                    type="button"
                    onClick={shareNotes}
                    className="flex h-11 flex-1 items-center justify-center gap-2 rounded-full text-[13.5px] font-bold transition-transform active:scale-[0.98]"
                    style={{ background: theme.primaryFill, color: theme.primaryInk }}
                  >
                    <Share2 className="h-4 w-4" /> Share
                  </button>
                  <button
                    type="button"
                    onClick={copyNotes}
                    className="flex h-11 flex-1 items-center justify-center gap-2 rounded-full text-[13.5px] font-bold transition-transform active:scale-[0.98]"
                    style={{
                      background: theme.surfaceStrong,
                      color: theme.ink,
                      border: `1px solid ${theme.stroke}`,
                    }}
                  >
                    <Copy className="h-4 w-4" /> Copy
                  </button>
                </div>
              )}
              {footnote && (
                <p className="px-2 text-center text-[10.5px]" style={{ color: theme.muted }}>
                  {footnote}
                </p>
              )}
            </>
          ) : (
            emptyContent ?? (
              <div className="flex flex-col items-center gap-2.5 px-5 py-8 text-center" style={card()}>
                <EmberMascot size={44} coachMode={mode} isActive={false} expression="concerned" />
                <p className="text-[13.5px] font-bold">Notes aren't ready yet</p>
                <p className="max-w-xs text-[12px] leading-relaxed" style={{ color: theme.muted }}>
                  Jasper writes the notes when the meeting ends. Check back in a moment.
                </p>
              </div>
            )
          )}

          {meetingId && <div className="rounded-2xl bg-card p-4 text-foreground"><p className="text-xs leading-5 text-muted-foreground">These notes are a saved snapshot. Speech that finishes saving later may not be reflected above. Jasper can review the latest saved transcript without replacing your original notes.</p><button className="mt-1 min-h-11 text-xs font-semibold" disabled={transcriptQuery.isFetching} onClick={() => { setPreferFreshTranscript(true); void transcriptQuery.refetch(); }}>Refresh saved transcript</button></div>}
          {showsTranscript && <TranscriptCard transcript={transcriptText} style={card()} accent={info.deepAccent} ink={theme.ink} muted={theme.muted} />}
          {!inlineTranscript && transcriptQuery.isFetching && <p role="status" className="py-3 text-sm">Loading transcript…</p>}
          {transcriptQuery.isError && <p role="alert" className="py-3 text-sm">Couldn’t load the transcript. <button className="min-h-11 underline" onClick={() => void transcriptQuery.refetch()}>Retry</button></p>}
          {user && meetingId && <section aria-label="Meeting recording" className="rounded-2xl border border-border bg-card p-4 text-foreground"><h2 className="mb-3 text-sm font-semibold">Recording</h2><NotebookRecordingSources key={`${user.id}:${meetingId}:${recordingId ?? ""}`} note={{ id: meetingId, ownerId: user.id, meetingId, recordingIds: recordingId ? [recordingId] : undefined }} /></section>}
          {user && meetingId && <JasperMeetingSavedContent owner={user.id} meetingID={meetingId} />}
          {children}
          {user && meetingId && <button className="flex min-h-12 w-full items-center justify-center gap-2 rounded-full border border-border bg-card text-sm text-foreground" onClick={() => { setSidekickOpened(true); setSidekickVisible(true); }}><Sparkles className="h-4 w-4" />Ask Jasper about this meeting</button>}
        </div>
      </div>
      {user && meetingId && sidekickOpened && <MeetingSidekick key={`${user.id}:${meetingId}`} owner={user.id} meetingID={meetingId} title={title} visible={sidekickVisible} captureStatus="Saved meeting transcript" interim="" onRetryCapture={() => undefined} onHide={() => setSidekickVisible(false)} archived />}
    </div>
  );
}
