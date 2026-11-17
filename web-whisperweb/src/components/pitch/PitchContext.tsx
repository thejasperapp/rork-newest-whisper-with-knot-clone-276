import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { toast } from "sonner";

const NOTES_STORAGE_KEY = (deckId: string) => `whisper-pitch-notes-${deckId}`;

export interface PitchSectionRef {
  id: string;
  el: HTMLElement | null;
}

type PitchToastType = "success" | "info" | "error";

export interface PitchContextValue {
  /** Ordered list of registered section IDs for keyboard navigation. */
  sections: PitchSectionRef[];
  /** Register a section element for scrolling / keyboard navigation. */
  registerSection: (id: string, el: HTMLElement | null) => void;
  /** Unregister a section. */
  unregisterSection: (id: string) => void;
  /** Scroll to the section at the given index. */
  scrollToSection: (index: number) => void;
  /** Current active section index (best guess from scroll). */
  activeSectionIndex: number;
  /** Go to next / previous section. */
  goToNextSection: () => void;
  goToPrevSection: () => void;
  /** Reset all demo state registered by child components. */
  resetDemo: () => void;
  /** Register a reset callback from a demo component. */
  registerReset: (fn: () => void) => () => void;
  /** Show a demo toast. */
  showToast: (message: string, type?: PitchToastType) => void;
  /** Pitch length toggle — short shows only hero + core demo + FAQ. */
  pitchLength: "short" | "long";
  setPitchLength: (length: "short" | "long") => void;
  /** Mobile preview frame toggle. */
  phoneFrame: boolean;
  setPhoneFrame: (value: boolean) => void;
  /** Speaker notes panel toggle. */
  speakerNotes: boolean;
  setSpeakerNotes: (value: boolean) => void;
  /** Presenter-only secrets panel toggle. */
  secrets: boolean;
  setSecrets: (value: boolean) => void;
  /** Current deck canonical URL for QR / PDF. */
  deckUrl: string;
  deckTitle: string;
  deckId: string;
  /** Speaker notes keyed by section. */
  notes: Record<string, string>;
  setNote: (section: string, value: string) => void;
  resetNotes: () => void;
  notesSavedAt: number | null;
  /** Open the user's email client with all notes for this deck pre-filled. */
  emailNotes: (to?: string) => void;
  /** Current active section id (derived from activeSectionIndex). */
  activeSectionId: string;
}

const PitchContext = createContext<PitchContextValue | null>(null);

export function PitchProvider({
  children,
  deckUrl,
  deckTitle,
  deckId,
}: {
  children: ReactNode;
  deckUrl: string;
  deckTitle: string;
  deckId: string;
}) {
  const [sections, setSections] = useState<PitchSectionRef[]>([]);
  const [activeSectionIndex, setActiveSectionIndex] = useState<number>(0);
  const [pitchLength, setPitchLength] = useState<"short" | "long">("long");
  const [phoneFrame, setPhoneFrame] = useState<boolean>(false);
  const [speakerNotes, setSpeakerNotes] = useState<boolean>(false);
  const [secrets, setSecrets] = useState<boolean>(false);
  const [notes, setNotes] = useState<Record<string, string>>({});
  const [notesSavedAt, setNotesSavedAt] = useState<number | null>(null);
  const resetsRef = useRef<Set<() => void>>(new Set());
  const observerRef = useRef<IntersectionObserver | null>(null);
  const sectionElsRef = useRef<Map<string, HTMLElement>>(new Map());

  const registerSection = useCallback((id: string, el: HTMLElement | null) => {
    if (!el) return;
    sectionElsRef.current.set(id, el);
    setSections((prev) => {
      if (prev.some((s) => s.id === id)) {
        return prev.map((s) => (s.id === id ? { ...s, el } : s));
      }
      return [...prev, { id, el }].sort((a, b) => {
        const aEl = a.el;
        const bEl = b.el;
        if (!aEl || !bEl) return 0;
        return aEl.compareDocumentPosition(bEl) & Node.DOCUMENT_POSITION_FOLLOWING ? -1 : 1;
      });
    });
  }, []);

  const unregisterSection = useCallback((id: string) => {
    sectionElsRef.current.delete(id);
    setSections((prev) => prev.filter((s) => s.id !== id));
  }, []);

  const scrollToSection = useCallback((index: number) => {
    const section = sections[index];
    if (!section?.el) return;
    const top = section.el.getBoundingClientRect().top + window.scrollY - 100;
    window.scrollTo({ top, behavior: "smooth" });
  }, [sections]);

  const goToNextSection = useCallback(() => {
    setActiveSectionIndex((i) => {
      const next = Math.min(i + 1, sections.length - 1);
      scrollToSection(next);
      return next;
    });
  }, [sections.length, scrollToSection]);

  const goToPrevSection = useCallback(() => {
    setActiveSectionIndex((i) => {
      const prev = Math.max(i - 1, 0);
      scrollToSection(prev);
      return prev;
    });
  }, [scrollToSection]);

  const registerReset = useCallback((fn: () => void) => {
    resetsRef.current.add(fn);
    return () => {
      resetsRef.current.delete(fn);
    };
  }, []);

  const resetDemo = useCallback(() => {
    resetsRef.current.forEach((fn) => fn());
    toast.info("Demo reset");
  }, []);

  const showToast = useCallback((message: string, type: PitchToastType = "info") => {
    if (type === "success") toast.success(message);
    else if (type === "error") toast.error(message);
    else toast(message);
  }, []);

  // Load and persist speaker notes per deck (internal to the presenting device).
  useEffect(() => {
    try {
      const raw = localStorage.getItem(NOTES_STORAGE_KEY(deckId));
      if (raw) {
        const parsed = JSON.parse(raw) as Record<string, string>;
        setNotes(parsed);
      }
    } catch (err) {
      console.error("Failed to load pitch notes", err);
    }
  }, [deckId]);

  const saveNotes = useCallback(
    (next: Record<string, string>) => {
      try {
        localStorage.setItem(NOTES_STORAGE_KEY(deckId), JSON.stringify(next));
        setNotesSavedAt(Date.now());
      } catch (err) {
        console.error("Failed to save pitch notes", err);
      }
    },
    [deckId]
  );

  const setNote = useCallback(
    (section: string, value: string) => {
      setNotes((prev) => {
        const next = { ...prev, [section]: value };
        saveNotes(next);
        return next;
      });
    },
    [saveNotes]
  );

  const resetNotes = useCallback(() => {
    try {
      localStorage.removeItem(NOTES_STORAGE_KEY(deckId));
      setNotes({});
      setNotesSavedAt(Date.now());
    } catch (err) {
      console.error("Failed to reset pitch notes", err);
    }
  }, [deckId]);

  // Build a plain-text export of the notes for the email button. Includes
  // the live client notes, per-section talking points, a header with the
  // deck title, and a timestamp so the mod has a record of the call.
  const buildNotesExport = useCallback(() => {
    const lines: string[] = [];
    lines.push(`Whisper Pitch Notes — ${deckTitle}`);
    lines.push(`Deck: ${deckId}`);
    lines.push(`Saved: ${notesSavedAt ? new Date(notesSavedAt).toLocaleString() : new Date().toLocaleString()}`);
    lines.push("".padEnd(40, "-"));
    lines.push("");
    const client = notes["__client"]?.trim();
    if (client) {
      lines.push("LIVE CLIENT NOTES");
      lines.push(client);
      lines.push("");
    }
    Object.entries(notes).forEach(([section, value]) => {
      if (section === "__client") return;
      const trimmed = value.trim();
      if (!trimmed) return;
      lines.push(section.toUpperCase());
      lines.push(trimmed);
      lines.push("");
    });
    return lines.join("\n").trim();
  }, [deckId, deckTitle, notes, notesSavedAt]);

  const emailNotes = useCallback(
    (to?: string) => {
      const subject = encodeURIComponent(`Whisper Pitch Notes — ${deckTitle}`);
      const body = encodeURIComponent(buildNotesExport());
      const recipient = to ? encodeURIComponent(to) : "";
      window.location.href = `mailto:${recipient}?subject=${subject}&body=${body}`;
    },
    [buildNotesExport, deckTitle]
  );

  // IntersectionObserver to track active section.
  useEffect(() => {
    if (observerRef.current) observerRef.current.disconnect();
    observerRef.current = new IntersectionObserver(
      (entries) => {
        const visible = entries
          .filter((e) => e.isIntersecting)
          .map((e) => ({
            id: e.target.getAttribute("data-pitch-section") ?? "",
            ratio: e.intersectionRatio,
          }))
          .sort((a, b) => b.ratio - a.ratio)[0];
        if (!visible) return;
        const index = sections.findIndex((s) => s.id === visible.id);
        if (index >= 0) setActiveSectionIndex(index);
      },
      { threshold: [0, 0.25, 0.5, 0.75, 1], rootMargin: "-100px 0px -50% 0px" }
    );
    sections.forEach((s) => {
      if (s.el) {
        s.el.setAttribute("data-pitch-section", s.id);
        observerRef.current?.observe(s.el);
      }
    });
    return () => observerRef.current?.disconnect();
  }, [sections]);

  // Keyboard shortcuts.
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // Only active when user is not typing in an input/textarea.
      const target = e.target as HTMLElement;
      if (target.tagName === "INPUT" || target.tagName === "TEXTAREA" || target.isContentEditable) return;

      if (e.key === "ArrowRight" || e.key === "ArrowDown" || e.key === "PageDown") {
        e.preventDefault();
        goToNextSection();
      } else if (e.key === "ArrowLeft" || e.key === "ArrowUp" || e.key === "PageUp") {
        e.preventDefault();
        goToPrevSection();
      } else if (e.key.toLowerCase() === "r") {
        e.preventDefault();
        resetDemo();
      } else if (e.key === "Escape") {
        // Close any open modal by clicking the topmost aria-label="Close" button.
        const closeBtn = document.querySelector(
          '[role="dialog"] button[aria-label="Close"], [role="dialog"] button[aria-label="Back"]'
        ) as HTMLElement | null;
        if (closeBtn) closeBtn.click();
      } else if (e.key.toLowerCase() === "n") {
        e.preventDefault();
        setSpeakerNotes((v) => !v);
      } else if (e.key.toLowerCase() === "s") {
        e.preventDefault();
        setSecrets((v) => !v);
      } else if (e.key.toLowerCase() === "f") {
        e.preventDefault();
        setPhoneFrame((v) => !v);
      } else if (e.key.toLowerCase() === "l") {
        e.preventDefault();
        setPitchLength((v) => (v === "short" ? "long" : "short"));
      } else if (e.key === "F11") {
        e.preventDefault();
        void document.documentElement.requestFullscreen().catch(() => null);
      }
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [goToNextSection, goToPrevSection, resetDemo]);

  const activeSectionId = sections[activeSectionIndex]?.id ?? "";

  const value = useMemo<PitchContextValue>(
    () => ({
      sections,
      registerSection,
      unregisterSection,
      scrollToSection,
      activeSectionIndex,
      goToNextSection,
      goToPrevSection,
      resetDemo,
      registerReset,
      showToast,
      pitchLength,
      setPitchLength,
      phoneFrame,
      setPhoneFrame,
      speakerNotes,
      setSpeakerNotes,
      secrets,
      setSecrets,
      deckUrl,
      deckTitle,
      deckId,
      notes,
      setNote,
      resetNotes,
      notesSavedAt,
      emailNotes,
      activeSectionId,
    }),
    [
      sections,
      registerSection,
      unregisterSection,
      scrollToSection,
      activeSectionIndex,
      goToNextSection,
      goToPrevSection,
      resetDemo,
      registerReset,
      showToast,
      pitchLength,
      phoneFrame,
      speakerNotes,
      secrets,
      deckUrl,
      deckTitle,
      deckId,
      notes,
      setNote,
      resetNotes,
      notesSavedAt,
      emailNotes,
      activeSectionId,
    ]
  );

  return <PitchContext.Provider value={value}>{children}</PitchContext.Provider>;
}

export function usePitch(): PitchContextValue {
  const ctx = useContext(PitchContext);
  if (!ctx) throw new Error("usePitch must be used within a PitchProvider");
  return ctx;
}

/** Hook for demo components to register a reset callback. */
export function usePitchReset(reset: () => void) {
  const { registerReset } = usePitch();
  useEffect(() => registerReset(reset), [registerReset, reset]);
}

/** Hook for demo components to emit a toast. */
export function usePitchToast() {
  return usePitch().showToast;
}
