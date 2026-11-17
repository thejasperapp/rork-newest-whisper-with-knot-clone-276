import { useRef, useState } from "react";
import { BookOpen, Copy, Mail, MessageSquareQuote, Pin, RotateCcw, Save, X } from "lucide-react";

import { usePitch } from "@/components/pitch/PitchContext";
import { cn } from "@/lib/utils";

export interface PitchSpeakerNotesItem {
  section: string;
  bullets: string[];
}

export interface PitchFaqItem {
  question: string;
  answer: string;
}

const CLIENT_NOTES_KEY = "__client";

function defaultText(bullets: string[]): string {
  return bullets.map((b) => `• ${b}`).join("\n");
}

function formatSavedAt(timestamp: number | null): string {
  if (!timestamp) return "Never saved";
  const d = new Date(timestamp);
  return d.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit", second: "2-digit" });
}

function findObjectionForSection(
  activeSectionId: string,
  notes: PitchSpeakerNotesItem[],
  faqs: PitchFaqItem[]
): PitchFaqItem | null {
  // Each deck puts its FAQ under a section id ending in "-faq". Find the
  // talking-points section whose id most closely matches the active section,
  // then surface the FAQ question that best matches its first bullet's keywords.
  if (!faqs.length) return null;
  const active = notes.find((n) => n.section.toLowerCase().replace(/\s+/g, "-") === activeSectionId);
  if (!active) return faqs[0];
  const keywords = active.bullets[0]?.toLowerCase().split(/\s+/).slice(0, 3) ?? [];
  const match = faqs.find((f) => keywords.some((k) => f.question.toLowerCase().includes(k)));
  return match ?? faqs[0];
}

function NotebookEditor({
  notes,
  faqs,
  onClose,
}: {
  notes: PitchSpeakerNotesItem[];
  faqs?: PitchFaqItem[];
  onClose?: () => void;
}) {
  const {
    notes: savedNotes,
    setNote,
    resetNotes,
    notesSavedAt,
    emailNotes,
    activeSectionId,
  } = usePitch();
  const [copied, setCopied] = useState(false);
  const [emailed, setEmailed] = useState(false);
  const clientRef = useRef<HTMLTextAreaElement>(null);

  const copyAll = async () => {
    const lines: string[] = [];
    const client = savedNotes[CLIENT_NOTES_KEY]?.trim();
    if (client) lines.push("Client notes", client, "");
    notes.forEach((note) => {
      const value = savedNotes[note.section]?.trim() || defaultText(note.bullets);
      if (value) {
        lines.push(note.section, value, "");
      }
    });
    try {
      await navigator.clipboard.writeText(lines.join("\n").trim());
      setCopied(true);
      setTimeout(() => setCopied(false), 2000);
    } catch (err) {
      console.error("Failed to copy notes", err);
    }
  };

  const sendEmail = () => {
    emailNotes();
    setEmailed(true);
    setTimeout(() => setEmailed(false), 2500);
  };

  // The objection pinned to the top of the notebook, derived from the
  // currently-visible deck section. Falls back to the first FAQ when no
  // section matches (e.g. hero or follow-up).
  const pinnedObjection = faqs && faqs.length > 0
    ? findObjectionForSection(activeSectionId, notes, faqs)
    : null;
  const activeNote = notes.find((n) => n.section.toLowerCase().replace(/\s+/g, "-") === activeSectionId);

  return (
    <div className="flex h-full flex-col">
      <div className="flex items-center justify-between border-b border-dashed border-border pb-3">
        <p className="flex items-center gap-2 text-[13px] font-bold">
          <BookOpen className="h-4 w-4" /> Speaker notebook
        </p>
        <div className="flex items-center gap-1">
          <button
            onClick={copyAll}
            className={cn(
              "flex h-7 items-center gap-1 rounded-full px-2 text-[10px] font-bold transition-colors",
              copied
                ? "bg-emerald-500/15 text-emerald-600"
                : "text-muted-foreground hover:bg-secondary hover:text-foreground"
            )}
            title="Copy all notes"
          >
            <Copy className="h-3 w-3" /> {copied ? "Copied" : "Copy"}
          </button>
          <button
            onClick={sendEmail}
            className={cn(
              "flex h-7 items-center gap-1 rounded-full px-2 text-[10px] font-bold transition-colors",
              emailed
                ? "bg-emerald-500/15 text-emerald-600"
                : "text-muted-foreground hover:bg-secondary hover:text-foreground"
            )}
            title="Email all notes to yourself"
          >
            <Mail className="h-3 w-3" /> {emailed ? "Opening…" : "Email"}
          </button>
          <button
            onClick={resetNotes}
            className="flex h-7 items-center gap-1 rounded-full px-2 text-[10px] font-bold text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
            title="Reset notes to defaults"
          >
            <RotateCcw className="h-3 w-3" /> Reset
          </button>
          {onClose && (
            <button
              onClick={onClose}
              className="flex h-7 w-7 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
              aria-label="Close notes"
            >
              <X className="h-3.5 w-3.5" />
            </button>
          )}
        </div>
      </div>

      <div className="mt-3 flex-1 space-y-4 overflow-y-auto pr-1">
        {/* Pinned objection — updates with the section the mod is presenting */}
        {pinnedObjection && (
          <div className="rounded-[16px] border border-foreground/15 bg-foreground/[0.04] p-3">
            <p className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-foreground/80">
              <Pin className="h-3 w-3" /> In the room now
              {activeNote && (
                <span className="ml-1 rounded-full bg-foreground/10 px-1.5 py-0.5 text-[9px] font-bold normal-case tracking-normal text-foreground/70">
                  {activeNote.section}
                </span>
              )}
            </p>
            <p className="mt-1.5 text-[12px] font-bold leading-snug">
              {pinnedObjection.question}
            </p>
            <p className="mt-1 text-[11px] leading-snug text-muted-foreground">
              {pinnedObjection.answer}
            </p>
          </div>
        )}

        {/* Live client notes — free-form, always on top */}
        <div className="rounded-[16px] border border-foreground/10 bg-background/60 p-3">
          <p className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
            <MessageSquareQuote className="h-3 w-3" /> Live client notes
          </p>
          <p className="mt-1 text-[11px] leading-snug text-muted-foreground">
            Type anything the prospect says or asks during the pitch. Saved
            automatically.
          </p>
          <textarea
            ref={clientRef}
            value={savedNotes[CLIENT_NOTES_KEY] ?? ""}
            onChange={(e) => setNote(CLIENT_NOTES_KEY, e.target.value)}
            rows={5}
            placeholder="Prospect questions, objections, next steps…"
            className="mt-2 w-full resize-none rounded-lg border border-border/60 bg-background p-2.5 text-[12px] leading-snug text-foreground/90 outline-none focus:border-foreground/40"
          />
        </div>

        {/* Per-section talking points */}
        {notes.map((note) => {
          const value = savedNotes[note.section] ?? defaultText(note.bullets);
          const isActive = note.section.toLowerCase().replace(/\s+/g, "-") === activeSectionId;
          return (
            <div
              key={note.section}
              className={cn(
                "rounded-[16px] border bg-background/60 p-3 transition-colors",
                isActive ? "border-foreground/40 bg-foreground/[0.03]" : "border-border"
              )}
            >
              <p className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-wider text-muted-foreground">
                {isActive && <Pin className="h-3 w-3" />}
                {note.section}
              </p>
              <textarea
                value={value}
                onChange={(e) => setNote(note.section, e.target.value)}
                rows={Math.max(4, value.split("\n").length + 1)}
                className="mt-2 w-full resize-none rounded-lg border border-border/60 bg-background p-2.5 text-[12px] leading-snug text-foreground/90 outline-none focus:border-foreground/40"
                placeholder={`Notes for ${note.section.toLowerCase()}…`}
              />
            </div>
          );
        })}
      </div>

      <div className="mt-3 flex items-center justify-between border-t border-dashed border-border pt-3">
        <p className="flex items-center gap-1 text-[10px] text-muted-foreground">
          <Save className="h-3 w-3" /> Saved internally
        </p>
        <p className="text-[10px] text-muted-foreground">{formatSavedAt(notesSavedAt)}</p>
      </div>
    </div>
  );
}

export function PitchSpeakerNotes({
  notes,
  faqs,
}: {
  notes: PitchSpeakerNotesItem[];
  faqs?: PitchFaqItem[];
}) {
  const { speakerNotes, setSpeakerNotes } = usePitch();
  if (!speakerNotes) return null;

  return (
    <div className="fixed right-4 top-20 z-[70] hidden h-[calc(100vh-9rem)] w-80 flex-col rounded-[24px] border border-border bg-card p-4 shadow-2xl backdrop-blur-md lg:flex">
      <NotebookEditor notes={notes} faqs={faqs} onClose={() => setSpeakerNotes(false)} />
    </div>
  );
}

export function PitchSpeakerNotesMobile({
  notes,
  faqs,
}: {
  notes: PitchSpeakerNotesItem[];
  faqs?: PitchFaqItem[];
}) {
  const { speakerNotes, setSpeakerNotes } = usePitch();
  if (!speakerNotes) return null;

  return (
    <div className="fixed inset-0 z-[70] flex items-end justify-center bg-black/40 p-4 lg:hidden">
      <div className={cn(
        "flex h-[85vh] w-full max-w-md flex-col rounded-t-[24px] border border-border bg-card p-4 shadow-2xl",
        "animate-in slide-in-from-bottom-full duration-300"
      )}>
        <NotebookEditor notes={notes} faqs={faqs} onClose={() => setSpeakerNotes(false)} />
      </div>
    </div>
  );
}

export function PitchNotesReset({ notes }: { notes: PitchSpeakerNotesItem[] }) {
  const { resetNotes } = usePitch();

  return (
    <button
      onClick={resetNotes}
      className="flex items-center gap-1.5 text-[10px] font-bold text-muted-foreground transition-colors hover:text-foreground"
    >
      <RotateCcw className="h-3 w-3" /> Reset notes
    </button>
  );
}
