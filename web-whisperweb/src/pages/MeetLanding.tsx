import { useEffect, useMemo, useRef, useState } from "react";
import { Link, useNavigate, useParams } from "react-router-dom";
import { useQuery, useQueryClient } from "@tanstack/react-query";
import {
  ArrowRight,
  ArrowUpRight,
  BookOpen,
  Bug,
  Calendar as CalendarIcon,
  CalendarPlus,
  ChevronDown,
  ChevronLeft,
  ChevronRight,
  FileText,
  HelpCircle,
  Keyboard,
  Link2,
  Loader2,
  Mail,
  NotebookPen,
  Phone,
  PhoneCall,
  Plus,
  Search,
  Settings,
  Video,
  X,
} from "lucide-react";
import { toast } from "sonner";

import { useAuth } from "@/hooks/useAuth";
import { WhisperLogo } from "@/components/WhisperLogo";
import { Avatar } from "@/components/Avatar";
import { GradientTypeIn } from "@/components/GradientTypeIn";
import { MeetSettingsDialog } from "@/components/MeetSettingsDialog";
import { ReportBugDialog } from "@/components/ReportBugDialog";
import { cn } from "@/lib/utils";
import { WHISPER_BRAND_GRADIENT, WHISPER_BRAND_GRADIENT_DIAGONAL } from "@/lib/brand";
import {
  createMeeting,
  fetchMyMeetings,
  meetingIdFromCode,
  meetingLink,
  type WhisperMeeting,
} from "@/lib/meetings";
import {
  createCalendarEvent,
  fetchCalendarEvents,
  sendCalendarTeamDMs,
  RECURRENCE_LABELS,
  type CalendarEvent,
  type CalendarRecurrence,
} from "@/lib/calendar";
import { isLikelyEmail, parseEmailList, sendMeetingInviteEmails } from "@/lib/meetInvites";
import { searchProfiles } from "@/lib/api";
import type { WhisperProfile } from "@/lib/types";

/** Extract a meeting id from a pasted link or a raw code. */
function parseMeetingCode(raw: string): string | null {
  const trimmed = raw.trim();
  if (!trimmed) return null;
  try {
    const url = new URL(trimmed);
    const segs = url.pathname.split("/").filter(Boolean);
    return segs.length > 0 ? segs[segs.length - 1] : null;
  } catch {
    return trimmed.split("/").filter(Boolean).pop() ?? null;
  }
}

/** Pronounceable meeting code: wsp-xxxx-xxxx. */
function newMeetingId(): string {
  const chunk = (): string =>
    crypto.randomUUID().replace(/-/g, "").slice(0, 4);
  return `wsp-${chunk()}-${chunk()}`;
}

/** App paths that must never be mistaken for a meeting code. */
const RESERVED_CODES = new Set([
  "auth",
  "welcome",
  "reset-password",
  "onboarding",
  "meet",
  "meetings",
  "messages",
  "live",
  "feed",
  "privacy",
  "terms",
  "support",
]);

type Tab = "meetings" | "calls";

const DAY_MS = 86_400_000;

// Whisper's grammar — surface + hairlines, ink pills, THE brand gradient for
// the one primary action. No borrowed palette.
const INK_PILL = "bg-foreground text-background hover:opacity-90 active:scale-[0.98]";
const HAIRLINE_CARD = "rounded-[22px] border border-border bg-card";
const KICKER = "text-[10.5px] font-bold uppercase tracking-[0.16em] text-muted-foreground";
const FIELD =
  "h-11 w-full rounded-2xl border border-border bg-background px-3 text-[14px] text-foreground outline-none transition-colors focus:border-foreground";

function startOfDay(d: Date): Date {
  const c = new Date(d);
  c.setHours(0, 0, 0, 0);
  return c;
}

function sameDay(a: Date, b: Date): boolean {
  return startOfDay(a).getTime() === startOfDay(b).getTime();
}

function fmtTime(iso: string): string {
  return new Date(iso).toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
}

/** "Friday, September 4" — the day header. */
function fmtHeaderDate(d: Date): string {
  return d.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" });
}

function isCallMeeting(m: WhisperMeeting): boolean {
  return /^(audio|video) call with @/i.test(m.title ?? "");
}

/** A datetime-local value for an input. */
function toLocalInput(d: Date): string {
  const pad = (n: number): string => String(n).padStart(2, "0");
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}T${pad(d.getHours())}:${pad(d.getMinutes())}`;
}

/** Workspace doors always open in their own tab. */
function openInNewTab(href: string): void {
  const win = window.open(href, "_blank", "noopener");
  if (!win) window.location.href = href;
}

/** One row of the day agenda — a calendar event, a meeting row, or both merged. */
interface AgendaItem {
  id: string;
  title: string;
  startIso: string;
  endIso: string | null;
  link: string | null;
  /** The meeting row id when one exists (notes + transcript live on it). */
  meetingId: string | null;
  live: boolean;
  ended: boolean;
  notes: string | null;
  hostLabel: string;
  guests: string[];
}

/** Meeting-row timestamp used for "is there something on this day". */
function meetingDayIso(m: WhisperMeeting): string | null {
  return m.status === "scheduled" ? m.scheduled_at : (m.started_at ?? m.created_at);
}

/**
 * "Happening now" means a room that opened in the last day. A live row older
 * than that is a room somebody left open (a host who stepped out before
 * anyone joined keeps the link alive on purpose) — it stays joinable but
 * reads as Earlier, never as a meeting in progress.
 */
function isLiveNow(m: WhisperMeeting | undefined): boolean {
  if (!m || m.status !== "live") return false;
  const opened = new Date(m.started_at ?? m.created_at ?? 0).getTime();
  return Date.now() - opened < 24 * 60 * 60_000;
}

/**
 * Whisper Meet — the front door at meet.mydailywhisper.com in Whisper's own
 * grammar: a start card (the type-in headline, New meeting, join by code,
 * the doors), and beside it the day — a week strip, the live mini calendar,
 * and the day's meetings as hairline cards.
 */
export default function MeetLanding(): JSX.Element {
  const { session, profile, loading, user } = useAuth();
  const navigate = useNavigate();
  const qc = useQueryClient();
  const params = useParams<{ code?: string }>();
  const [code, setCode] = useState<string>("");
  const [tab, setTab] = useState<Tab>("meetings");
  const [settingsOpen, setSettingsOpen] = useState<boolean>(false);
  const [scheduleOpen, setScheduleOpen] = useState<boolean>(false);
  const [miniCalOpen, setMiniCalOpen] = useState<boolean>(false);
  const [bugOpen, setBugOpen] = useState<boolean>(false);
  const [day, setDay] = useState<Date>(() => startOfDay(new Date()));
  const joinedFromUrl = useRef<boolean>(false);

  const myMeetingsQuery = useQuery({
    queryKey: ["my-meetings", user?.id ?? ""],
    enabled: !!user,
    queryFn: () => fetchMyMeetings(user!.id),
  });
  const myMeetings = myMeetingsQuery.data ?? [];

  // The Sunday-start week around the selected day.
  const weekStart = useMemo(() => {
    const d = new Date(day);
    d.setDate(d.getDate() - d.getDay());
    return startOfDay(d);
  }, [day]);
  const weekEnd = useMemo(() => new Date(weekStart.getTime() + 7 * DAY_MS), [weekStart]);

  const calendarQuery = useQuery({
    queryKey: ["meet-calendar", weekStart.toISOString()],
    enabled: !!user,
    queryFn: () => fetchCalendarEvents(weekStart.toISOString(), weekEnd.toISOString()),
  });

  const agenda = useMemo((): AgendaItem[] => {
    const items: AgendaItem[] = [];
    // Meeting rows by their share link — a calendar event pointing at one
    // MERGES with it (live state, notes, the transcript) instead of hiding it.
    const meetingsByLink = new Map<string, WhisperMeeting>();
    for (const m of myMeetings) {
      if (isCallMeeting(m)) continue;
      meetingsByLink.set(meetingLink(m.id), m);
    }
    const usedMeetingIds = new Set<string>();
    for (const e of calendarQuery.data ?? []) {
      const start = new Date(e.start_time);
      if (!sameDay(start, day)) continue;
      const linkedMeeting =
        e.meeting_link
          ? (meetingsByLink.get(e.meeting_link) ??
            (() => {
              const parsed = parseMeetingCode(e.meeting_link);
              if (!parsed) return undefined;
              const id = /^[0-9a-f-]{36}$/i.test(parsed) ? parsed : meetingIdFromCode(parsed);
              return myMeetings.find((m) => m.id === id);
            })())
          : undefined;
      if (linkedMeeting) usedMeetingIds.add(linkedMeeting.id);
      items.push({
        id: `cal-${e.id}`,
        title: e.title,
        startIso: e.start_time,
        endIso: e.end_time,
        link: e.meeting_link,
        meetingId: linkedMeeting?.id ?? null,
        live: isLiveNow(linkedMeeting),
        ended:
          linkedMeeting?.status === "ended" ||
          (linkedMeeting?.status === "live" && !isLiveNow(linkedMeeting)) ||
          (e.end_time ? new Date(e.end_time).getTime() < Date.now() : false),
        notes: (linkedMeeting?.summary ?? "").trim() || null,
        hostLabel: e.created_by_username ? `@${e.created_by_username}` : "Calendar",
        guests: e.tagged_usernames ?? [],
      });
    }
    for (const m of myMeetings) {
      if (isCallMeeting(m) || usedMeetingIds.has(m.id)) continue;
      const iso = meetingDayIso(m);
      if (!iso || !sameDay(new Date(iso), day)) continue;
      items.push({
        id: `mtg-${m.id}`,
        title: m.title || "Meeting",
        startIso: iso,
        endIso: m.ended_at,
        link: meetingLink(m.id),
        meetingId: m.id,
        live: isLiveNow(m),
        ended: m.status === "ended" || (m.status === "live" && !isLiveNow(m)),
        notes: (m.summary ?? "").trim() || null,
        hostLabel: `@${m.host_username}`,
        guests: [],
      });
    }
    return items.sort((a, b) => a.startIso.localeCompare(b.startIso));
  }, [calendarQuery.data, myMeetings, day]);

  const groups = useMemo(() => {
    const live = agenda.filter((a) => a.live);
    const upcoming = agenda.filter((a) => !a.live && !a.ended);
    const past = agenda.filter((a) => !a.live && a.ended);
    return { live, upcoming, past };
  }, [agenda]);

  const onMeetHost = /^meet\./.test(window.location.hostname.toLowerCase());
  const notebookHref = "/notebook?portal=workspace";
  const calendarHref = onMeetHost ? "https://mydailywhisper.com/calendar" : "/calendar";

  useEffect(() => {
    if (!params.code || joinedFromUrl.current) return;
    if (RESERVED_CODES.has(params.code.toLowerCase())) return;
    joinedFromUrl.current = true;
    navigate(`/meet/${encodeURIComponent(params.code)}`, { replace: true });
  }, [params.code, navigate]);

  const copyLater = (): void => {
    const id = newMeetingId();
    const link = meetingLink(id);
    void navigator.clipboard
      .writeText(link)
      .then(() => toast.success("Link copied — start it whenever you're ready."))
      .catch(() => toast.message(link));
  };

  const startInstant = (): void => {
    const id = newMeetingId();
    const link = meetingLink(id);
    void navigator.clipboard.writeText(link).catch(() => undefined);
    navigate(`/meet/${id}`);
  };

  const joinMeeting = (): void => {
    const parsed = parseMeetingCode(code);
    if (!parsed) {
      toast.error("Enter a meeting code or link.");
      return;
    }
    setCode("");
    navigate(`/meet/${encodeURIComponent(parsed)}`);
  };

  const openLink = (link: string): void => {
    const id = parseMeetingCode(link);
    if (id) navigate(`/meet/${encodeURIComponent(id)}`);
  };

  const callHistory = useMemo(
    () => myMeetings.filter(isCallMeeting).slice(0, 30),
    [myMeetings]
  );

  const isToday = sameDay(day, new Date());
  const dayHasItems = (d: Date): boolean =>
    (calendarQuery.data ?? []).some((e) => sameDay(new Date(e.start_time), d)) ||
    myMeetings.some((m) => {
      const iso = meetingDayIso(m);
      return !!iso && !isCallMeeting(m) && sameDay(new Date(iso), d);
    });

  const newMenuItems: NewMenuItem[] = [
    { icon: Plus, label: "Start a meeting now", hint: "Link copied as you go in", onPick: startInstant },
    { icon: Link2, label: "Create a meeting for later", hint: "Copies a link you can send", onPick: copyLater },
    { icon: CalendarPlus, label: "Schedule in Whisper Calendar", hint: "Guests, email invites, repeats", onPick: () => setScheduleOpen(true) },
    { icon: NotebookPen, label: "Browse meeting notes", hint: "Open your Meetings library", onPick: () => openInNewTab(notebookHref) },
  ];

  const codeField = (compact: boolean): JSX.Element => (
    <div
      className={cn(
        "flex min-w-0 flex-1 items-center gap-2 rounded-full border border-border bg-background pl-4 pr-1.5 transition-colors focus-within:border-foreground",
        compact ? "h-11" : "h-12",
      )}
    >
      <Keyboard className="h-4.5 w-4.5 shrink-0 text-muted-foreground" />
      <input
        value={code}
        onChange={(e) => setCode(e.target.value)}
        onKeyDown={(e) => e.key === "Enter" && joinMeeting()}
        placeholder="Enter a code or link"
        className="min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-muted-foreground/70"
        aria-label="Meeting code or link"
      />
      <button
        type="button"
        onClick={joinMeeting}
        disabled={!code.trim()}
        aria-label="Join"
        className={cn(
          "grid shrink-0 place-items-center rounded-full transition-all disabled:opacity-30",
          compact ? "h-8 w-8" : "h-9 w-9",
          INK_PILL,
        )}
      >
        <ArrowRight className="h-4 w-4" />
      </button>
    </div>
  );

  return (
    <div className="relative flex min-h-screen flex-col bg-background text-foreground">
      {/* Top bar — wordmark · MEET kicker | notebook · help · settings · you */}
      <header className="flex h-16 shrink-0 items-center gap-3 border-b border-border/70 px-4 sm:px-6">
        <div className="flex min-w-0 shrink-0 items-center gap-2.5">
          <WhisperLogo size={26} variant="wordmark" />
          <span className="rounded-full border border-border px-2 py-[3px] text-[10px] font-bold uppercase tracking-[0.16em] text-muted-foreground">
            Meet
          </span>
        </div>
        <div className="ml-auto flex shrink-0 items-center gap-1">
          {session && (
            <button
              type="button"
              onClick={() => openInNewTab(notebookHref)}
              className="hidden h-10 items-center gap-2 rounded-full px-3.5 text-[13.5px] font-semibold text-foreground/80 transition-colors hover:bg-secondary hover:text-foreground sm:flex"
            >
              <NotebookPen className="h-4 w-4" />
              Meeting library
              <ArrowUpRight className="h-3.5 w-3.5 text-muted-foreground" />
            </button>
          )}
          {session && <button type="button" aria-label="Search workspace" title="Search workspace · ⌘K" onClick={() => window.dispatchEvent(new Event('whisper-workspace-search'))} className="grid h-11 w-11 place-items-center rounded-full text-muted-foreground hover:bg-secondary"><Search className="h-5 w-5" /></button>}
          <HelpMenu onReportBug={() => setBugOpen(true)} />
          {session && (
            <button
              type="button"
              onClick={() => setSettingsOpen(true)}
              aria-label="Settings"
              className="grid h-10 w-10 place-items-center rounded-full text-muted-foreground transition-colors hover:bg-secondary hover:text-foreground"
            >
              <Settings className="h-5 w-5" />
            </button>
          )}
          {session && profile ? (
            <Link to="/profile" className="ml-1.5 rounded-full" title={`@${profile.username}`} aria-label="Your account">
              <Avatar url={profile.profile_image_url} name={profile.username ?? profile.display_name} size={34} />
            </Link>
          ) : (
            <Link to="/auth" className={cn("ml-1.5 flex h-9 items-center rounded-full px-4 text-[13px] font-bold", INK_PILL)}>
              Sign in
            </Link>
          )}
        </div>
      </header>

      <main className="mx-auto w-full max-w-[1120px] flex-1 px-4 pb-24 pt-5 sm:px-6 lg:pt-8">
        {!session && !loading ? (
          <SignedOut code={code} setCode={setCode} onJoin={joinMeeting} />
        ) : (
          <div className="grid gap-6 lg:grid-cols-[360px_minmax(0,1fr)] lg:gap-10">
            {/* ── The start card ─────────────────────────────────────── */}
            <aside className="lg:sticky lg:top-6 lg:self-start">
              <section className={cn(HAIRLINE_CARD, "relative overflow-hidden rounded-[28px] p-6")}>
                <div
                  aria-hidden
                  className="pointer-events-none absolute -right-16 -top-20 h-56 w-56 rounded-full opacity-[0.13] blur-3xl"
                  style={{ backgroundImage: WHISPER_BRAND_GRADIENT_DIAGONAL }}
                />
                <p className={KICKER}>Whisper Meet</p>
                <GradientTypeIn
                  as="h1"
                  text="Meet, the Whisper way."
                  speed={26}
                  className="mt-2 font-display text-[30px] font-extrabold leading-[1.06] tracking-tight sm:text-[34px]"
                />
                <p className="mt-2.5 text-[14px] leading-relaxed text-muted-foreground">
                  One link, everyone in — Jasper takes the notes.
                </p>

                <div className="mt-5 flex flex-col gap-2.5">
                  <NewMenu items={newMenuItems} />
                  {codeField(false)}
                </div>

                <div className="mt-5 border-t border-border pt-3">
                  <DoorRow icon={CalendarPlus} label="Schedule a meeting" hint="Calendar, guests, email invites" onClick={() => setScheduleOpen(true)} />
                  <DoorRow icon={NotebookPen} label="Meeting library" hint="Folders, original notes, transcripts & recordings" external onClick={() => openInNewTab(notebookHref)} />
                  <DoorRow icon={CalendarIcon} label="Whisper Calendar" hint="The full shared calendar" external onClick={() => openInNewTab(calendarHref)} />
                  <DoorRow icon={Phone} label="Calls" hint="Ring someone by @username" onClick={() => setTab("calls")} />
                </div>
              </section>
            </aside>

            {/* ── The day ───────────────────────────────────────────── */}
            <section className="min-w-0">
              {/* Tabs — text + ink underline (the profile grammar). */}
              <div className="flex items-center gap-6 border-b border-border">
                {(["meetings", "calls"] as Tab[]).map((t) => (
                  <button
                    key={t}
                    type="button"
                    onClick={() => setTab(t)}
                    className={cn(
                      "-mb-px border-b-[1.5px] pb-2.5 text-[14px] font-semibold capitalize transition-colors",
                      tab === t ? "border-foreground text-foreground" : "border-transparent text-muted-foreground hover:text-foreground",
                    )}
                    aria-pressed={tab === t}
                  >
                    {t}
                  </button>
                ))}
              </div>

              {tab === "meetings" ? (
                <>
                  {/* Day header + the live mini calendar */}
                  <div className="mt-5 flex flex-wrap items-start justify-between gap-x-6 gap-y-3">
                    <div className="min-w-0">
                      <p className={KICKER}>{isToday ? "Today" : day.toLocaleDateString(undefined, { year: "numeric" })}</p>
                      <div className="mt-1 flex items-center gap-1.5">
                        <h2 className="truncate text-[24px] font-bold leading-tight tracking-tight sm:text-[26px]">{fmtHeaderDate(day)}</h2>
                        <div className="relative shrink-0" data-meet-minical="">
                          <button
                            type="button"
                            aria-label="Open the mini calendar"
                            aria-expanded={miniCalOpen}
                            onClick={() => setMiniCalOpen((v) => !v)}
                            className={cn(
                              "grid h-9 w-9 place-items-center rounded-full transition-colors",
                              miniCalOpen ? "bg-foreground text-background" : "text-muted-foreground hover:bg-secondary hover:text-foreground",
                            )}
                          >
                            <CalendarIcon className="h-[18px] w-[18px]" />
                          </button>
                          {miniCalOpen && (
                            <MiniCalendar
                              selected={day}
                              meetings={myMeetings}
                              calendarHref={calendarHref}
                              onPick={(d) => {
                                setDay(startOfDay(d));
                                setMiniCalOpen(false);
                              }}
                              onClose={() => setMiniCalOpen(false)}
                            />
                          )}
                        </div>
                        {!isToday && (
                          <button
                            type="button"
                            onClick={() => setDay(startOfDay(new Date()))}
                            className="ml-1 h-8 shrink-0 rounded-full border border-border px-3 text-[12.5px] font-semibold transition-colors hover:bg-secondary"
                          >
                            Today
                          </button>
                        )}
                      </div>
                    </div>
                  </div>

                  {/* The day strip — weeks of days running the full width under
                      faded ends; the picked day glides to the center. */}
                  <DayStrip selected={day} onPick={(d) => setDay(startOfDay(d))} busy={dayHasItems} />

                  {/* The day's meetings */}
                  {calendarQuery.isLoading && myMeetingsQuery.isLoading ? (
                    <div className="mt-6 space-y-3">
                      <div className={cn(HAIRLINE_CARD, "h-[84px] animate-pulse")} />
                      <div className={cn(HAIRLINE_CARD, "h-[84px] animate-pulse opacity-60")} />
                    </div>
                  ) : agenda.length === 0 ? (
                    <div className={cn(HAIRLINE_CARD, "mt-6 flex flex-col items-center px-6 py-12 text-center sm:py-16")}>
                      <LobbyDoodle />
                      <h3 className="mt-5 text-[20px] font-bold tracking-tight">
                        {isToday ? "Nothing on the books today." : `Nothing on ${day.toLocaleDateString(undefined, { month: "short", day: "numeric" })}.`}
                      </h3>
                      <p className="mt-1.5 max-w-[320px] text-[13.5px] leading-relaxed text-muted-foreground">
                        Start a meeting right now, or put one on the calendar and Whisper sends the invites.
                      </p>
                      <div className="mt-5 flex flex-wrap items-center justify-center gap-2">
                        <button
                          type="button"
                          onClick={startInstant}
                          className="flex h-10 items-center gap-2 rounded-full px-4 text-[13.5px] font-bold text-white transition-transform active:scale-[0.98]"
                          style={{ backgroundImage: WHISPER_BRAND_GRADIENT_DIAGONAL }}
                        >
                          <Video className="h-4 w-4" /> Start now
                        </button>
                        <button
                          type="button"
                          onClick={() => setScheduleOpen(true)}
                          className="flex h-10 items-center gap-2 rounded-full border border-border px-4 text-[13.5px] font-semibold transition-colors hover:bg-secondary"
                        >
                          <CalendarPlus className="h-4 w-4" /> Schedule
                        </button>
                      </div>
                    </div>
                  ) : (
                    <div className="mt-6 space-y-7">
                      {groups.live.length > 0 && (
                        <AgendaGroup label="Happening now" items={groups.live} onJoin={openLink} onNotes={(a) => navigate(`/notebook?portal=workspace${a.meetingId ? `&meeting=${encodeURIComponent(a.meetingId)}` : ""}`)} />
                      )}
                      {groups.upcoming.length > 0 && (
                        <AgendaGroup label="Upcoming" items={groups.upcoming} onJoin={openLink} onNotes={(a) => navigate(`/notebook?portal=workspace${a.meetingId ? `&meeting=${encodeURIComponent(a.meetingId)}` : ""}`)} />
                      )}
                      {groups.past.length > 0 && (
                        <AgendaGroup label="Earlier" items={groups.past} onJoin={openLink} onNotes={(a) => navigate(`/notebook?portal=workspace${a.meetingId ? `&meeting=${encodeURIComponent(a.meetingId)}` : ""}`)} />
                      )}
                    </div>
                  )}
                </>
              ) : (
                <CallsTab
                  history={callHistory}
                  meId={user?.id ?? ""}
                  myUsername={profile?.username ?? "you"}
                  onOpen={(id) => navigate(`/meet/${id}`)}
                />
              )}
            </section>
          </div>
        )}
      </main>

      <MeetSettingsDialog open={settingsOpen} onClose={() => setSettingsOpen(false)} context="landing" />
      <ReportBugDialog
        open={bugOpen}
        onOpenChange={setBugOpen}
        defaultCategory="meetings"
        context={{ surface: "meet-landing", path: window.location.pathname }}
      />

      {scheduleOpen && user && (
        <ScheduleDialog
          meId={user.id}
          myUsername={profile?.username ?? "you"}
          defaultDay={day}
          onClose={() => setScheduleOpen(false)}
          onCreated={() => {
            setScheduleOpen(false);
            void qc.invalidateQueries({ queryKey: ["my-meetings"] });
            void qc.invalidateQueries({ queryKey: ["meet-calendar"] });
            void qc.invalidateQueries({ queryKey: ["meet-calendar-month"] });
            void qc.invalidateQueries({ queryKey: ["calendar-events"] });
          }}
        />
      )}


    </div>
  );
}

// ─── The New menu ────────────────────────────────────────────────────────────

interface NewMenuItem {
  icon: typeof Video;
  label: string;
  hint: string;
  onPick: () => void;
}

/**
 * The one primary action — a brand-gradient pill that unfolds the four ways
 * to start. Outside clicks are detected by DOM ancestry (`closest`), never a
 * shared ref, so the menu can render in several places without one copy
 * closing another's menu before its click lands.
 */
function NewMenu({ items }: { items: NewMenuItem[] }): JSX.Element {
  const [open, setOpen] = useState<boolean>(false);

  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent): void => {
      const target = e.target as Element | null;
      if (!target?.closest?.("[data-meet-new-menu]")) setOpen(false);
    };
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") setOpen(false);
    };
    window.addEventListener("mousedown", onDown);
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("mousedown", onDown);
      window.removeEventListener("keydown", onKey);
    };
  }, [open]);

  return (
    <div className="relative" data-meet-new-menu="">
      <button
        type="button"
        onClick={() => setOpen((v) => !v)}
        aria-expanded={open}
        aria-haspopup="menu"
        className="flex h-12 w-full items-center justify-center gap-2 rounded-full text-[14.5px] font-bold text-white shadow-[0_8px_24px_-12px_rgba(242,38,89,0.55)] transition-transform active:scale-[0.98]"
        style={{ backgroundImage: WHISPER_BRAND_GRADIENT_DIAGONAL }}
      >
        <Video className="h-[18px] w-[18px]" />
        New meeting
        <ChevronDown className={cn("h-4 w-4 opacity-90 transition-transform", open && "rotate-180")} />
      </button>
      {open && (
        <div
          role="menu"
          className="absolute left-0 right-0 top-[calc(100%+8px)] z-40 overflow-hidden rounded-[22px] border border-border bg-card p-1.5 shadow-2xl"
        >
          {items.map((item) => (
            <button
              key={item.label}
              type="button"
              role="menuitem"
              onClick={() => {
                setOpen(false);
                item.onPick();
              }}
              className="flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-left transition-colors hover:bg-secondary"
            >
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-secondary text-foreground">
                <item.icon className="h-4 w-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[13.5px] font-semibold leading-tight">{item.label}</span>
                <span className="block truncate text-[11.5px] text-muted-foreground">{item.hint}</span>
              </span>
            </button>
          ))}
        </div>
      )}
    </div>
  );
}

// ─── The live mini calendar ──────────────────────────────────────────────────

function startOfMonth(d: Date): Date {
  return new Date(d.getFullYear(), d.getMonth(), 1);
}

/**
 * A live pocket version of the real Whisper Calendar — the month grid reads
 * the same events (plus your meeting rows) and paints a brand dot on every
 * busy day. Tap a day to jump the agenda; open the full calendar in its tab.
 */
function MiniCalendar({
  selected,
  meetings,
  calendarHref,
  onPick,
  onClose,
}: {
  selected: Date;
  meetings: WhisperMeeting[];
  calendarHref: string;
  onPick: (d: Date) => void;
  onClose: () => void;
}): JSX.Element {
  const [cursor, setCursor] = useState<Date>(() => startOfMonth(selected));
  const gridStart = useMemo(() => {
    const d = new Date(cursor);
    d.setDate(d.getDate() - d.getDay());
    return startOfDay(d);
  }, [cursor]);
  const gridEnd = useMemo(() => new Date(gridStart.getTime() + 42 * DAY_MS), [gridStart]);

  const monthQuery = useQuery({
    queryKey: ["meet-calendar-month", gridStart.toISOString()],
    queryFn: () => fetchCalendarEvents(gridStart.toISOString(), gridEnd.toISOString()),
  });

  useEffect(() => {
    const onDown = (e: MouseEvent): void => {
      const target = e.target as Element | null;
      if (!target?.closest?.("[data-meet-minical]")) onClose();
    };
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") onClose();
    };
    window.addEventListener("mousedown", onDown);
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("mousedown", onDown);
      window.removeEventListener("keydown", onKey);
    };
  }, [onClose]);

  // Day key → { meet: has a Whisper Meet link/room, other: plain events }.
  const busy = useMemo(() => {
    const map = new Map<string, { meet: number; other: number }>();
    const bump = (iso: string, kind: "meet" | "other"): void => {
      const key = startOfDay(new Date(iso)).getTime().toString();
      const cur = map.get(key) ?? { meet: 0, other: 0 };
      cur[kind] += 1;
      map.set(key, cur);
    };
    for (const e of monthQuery.data ?? []) bump(e.start_time, e.meeting_link ? "meet" : "other");
    for (const m of meetings) {
      if (isCallMeeting(m)) continue;
      const iso = meetingDayIso(m);
      if (iso) bump(iso, "meet");
    }
    return map;
  }, [monthQuery.data, meetings]);

  const cells = Array.from({ length: 42 }, (_, i) => new Date(gridStart.getTime() + i * DAY_MS));
  const monthLabel = cursor.toLocaleDateString(undefined, { month: "long", year: "numeric" });
  const today = new Date();

  return (
    <div
      role="dialog"
      aria-label="Mini calendar"
      className="absolute left-0 top-[calc(100%+8px)] z-40 w-[304px] rounded-[22px] border border-border bg-card p-3 shadow-2xl sm:left-auto sm:right-0"
    >
      <div className="flex items-center justify-between px-1">
        <button
          type="button"
          aria-label="Previous month"
          onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() - 1, 1))}
          className="grid h-8 w-8 place-items-center rounded-full text-muted-foreground hover:bg-secondary hover:text-foreground"
        >
          <ChevronLeft className="h-4 w-4" />
        </button>
        <p className="text-[13.5px] font-bold">{monthLabel}</p>
        <button
          type="button"
          aria-label="Next month"
          onClick={() => setCursor(new Date(cursor.getFullYear(), cursor.getMonth() + 1, 1))}
          className="grid h-8 w-8 place-items-center rounded-full text-muted-foreground hover:bg-secondary hover:text-foreground"
        >
          <ChevronRight className="h-4 w-4" />
        </button>
      </div>
      <div className="mt-2 grid grid-cols-7 text-center">
        {["S", "M", "T", "W", "T", "F", "S"].map((w, i) => (
          <span key={`${w}-${i}`} className="py-1 text-[10.5px] font-bold uppercase tracking-wide text-muted-foreground">
            {w}
          </span>
        ))}
      </div>
      <div className="grid grid-cols-7 gap-y-0.5">
        {cells.map((d) => {
          const inMonth = d.getMonth() === cursor.getMonth();
          const active = sameDay(d, selected);
          const isTodayCell = sameDay(d, today);
          const b = busy.get(startOfDay(d).getTime().toString());
          return (
            <button
              key={d.toISOString()}
              type="button"
              onClick={() => onPick(d)}
              aria-label={d.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}
              aria-pressed={active}
              className="flex flex-col items-center gap-0.5 py-0.5"
            >
              <span
                className={cn(
                  "grid h-8 w-8 place-items-center rounded-full text-[13px] tabular-nums transition-colors",
                  active
                    ? "bg-foreground font-bold text-background"
                    : isTodayCell
                      ? "font-bold ring-1 ring-foreground/60 hover:bg-secondary"
                      : inMonth
                        ? "hover:bg-secondary"
                        : "text-muted-foreground/45 hover:bg-secondary",
                )}
              >
                {d.getDate()}
              </span>
              <span className="flex h-1.5 items-center gap-0.5">
                {b && b.meet > 0 && (
                  <span className="h-1 w-1 rounded-full" style={{ backgroundImage: active ? undefined : WHISPER_BRAND_GRADIENT, backgroundColor: active ? "currentColor" : undefined }} />
                )}
                {b && b.other > 0 && <span className="h-1 w-1 rounded-full bg-foreground/45" />}
              </span>
            </button>
          );
        })}
      </div>
      <div className="mt-2 flex items-center justify-between border-t border-border px-1 pt-2.5">
        <button
          type="button"
          onClick={() => {
            setCursor(startOfMonth(today));
            onPick(today);
          }}
          className="h-8 rounded-full px-3 text-[12.5px] font-semibold text-foreground/80 transition-colors hover:bg-secondary"
        >
          Today
        </button>
        <div className="flex items-center gap-1.5">
          {monthQuery.isLoading && <Loader2 className="h-3.5 w-3.5 animate-spin text-muted-foreground" />}
          <button
            type="button"
            onClick={() => openInNewTab(calendarHref)}
            className="flex h-8 items-center gap-1 rounded-full px-3 text-[12.5px] font-semibold transition-colors hover:bg-secondary"
          >
            Open Whisper Calendar <ArrowUpRight className="h-3.5 w-3.5 text-muted-foreground" />
          </button>
        </div>
      </div>
    </div>
  );
}

// ─── Pieces ─────────────────────────────────────────────────────────────────

function DoorRow({
  icon: Icon,
  label,
  hint,
  external,
  onClick,
}: {
  icon: typeof Video;
  label: string;
  hint: string;
  external?: boolean;
  onClick: () => void;
}): JSX.Element {
  return (
    <button
      type="button"
      onClick={onClick}
      className="flex w-full items-center gap-3 rounded-2xl px-2 py-2.5 text-left transition-colors hover:bg-secondary"
    >
      <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full border border-border text-foreground">
        <Icon className="h-4 w-4" />
      </span>
      <span className="min-w-0 flex-1">
        <span className="block text-[13.5px] font-semibold leading-tight">{label}</span>
        <span className="block truncate text-[11.5px] text-muted-foreground">{hint}</span>
      </span>
      {external ? <ArrowUpRight className="h-4 w-4 shrink-0 text-muted-foreground" /> : <ChevronRight className="h-4 w-4 shrink-0 text-muted-foreground" />}
    </button>
  );
}

function AgendaGroup({
  label,
  items,
  onJoin,
  onNotes,
}: {
  label: string;
  items: AgendaItem[];
  onJoin: (link: string) => void;
  onNotes: (item: AgendaItem) => void;
}): JSX.Element {
  return (
    <section>
      <p className={cn(KICKER, "mb-2.5")}>{label}</p>
      <div className="space-y-2.5">
        {items.map((a) => (
          <div key={a.id} className={cn(HAIRLINE_CARD, "flex items-center gap-4 px-4 py-3.5 sm:px-5")}>
            <div className="w-[62px] shrink-0 text-[12.5px] font-semibold leading-tight tabular-nums text-foreground/80 sm:w-[76px]">
              {fmtTime(a.startIso)}
              {a.endIso && <span className="block text-[11px] font-medium text-muted-foreground">to {fmtTime(a.endIso)}</span>}
            </div>
            <div className="min-w-0 flex-1 border-l border-border pl-4">
              <p className="truncate text-[16px] font-semibold leading-tight">{a.title}</p>
              <p className="mt-0.5 flex items-center gap-1.5 truncate text-[12.5px] text-muted-foreground">
                {a.live && (
                  <span className="inline-flex items-center gap-1 font-semibold" style={{ color: "#F22659" }}>
                    <span className="h-1.5 w-1.5 animate-pulse rounded-full bg-current" /> Live
                  </span>
                )}
                <span className="truncate">
                  {a.hostLabel}
                  {a.guests.length > 0 ? ` · ${a.guests.length} guest${a.guests.length === 1 ? "" : "s"}` : ""}
                </span>
              </p>
            </div>
            {a.live && a.link ? (
              <button
                type="button"
                onClick={() => onJoin(a.link!)}
                className="shrink-0 rounded-full px-4 py-2 text-[13px] font-bold text-white transition-transform active:scale-[0.98]"
                style={{ backgroundImage: WHISPER_BRAND_GRADIENT_DIAGONAL }}
              >
                Join now
              </button>
            ) : !a.ended && a.link ? (
              <button type="button" onClick={() => onJoin(a.link!)} className={cn("shrink-0 rounded-full px-4 py-2 text-[13px] font-bold", INK_PILL)}>
                Join
              </button>
            ) : a.meetingId ? (
              <button
                type="button"
                onClick={() => onNotes(a)}
                className="flex shrink-0 items-center gap-1.5 rounded-full border border-border px-3.5 py-2 text-[12.5px] font-semibold transition-colors hover:bg-secondary"
              >
                <FileText className="h-3.5 w-3.5" />
                <span className="hidden sm:inline">Notes by Jasper</span>
                <span className="sm:hidden">Notes</span>
              </button>
            ) : null}
          </div>
        ))}
      </div>
    </section>
  );
}

// ─── Help ─────────────────────────────────────────────────────────────────────────────

/** The `?` — real help: the questions people actually ask, the full FAQ,
 *  and a bug report that lands in Whisper's report rail. */
function HelpMenu({ onReportBug }: { onReportBug: () => void }): JSX.Element {
  const [open, setOpen] = useState<boolean>(false);
  useEffect(() => {
    if (!open) return;
    const onDown = (e: MouseEvent): void => {
      const target = e.target as HTMLElement | null;
      if (!target?.closest?.("[data-meet-help-menu]")) setOpen(false);
    };
    const onKey = (e: KeyboardEvent): void => {
      if (e.key === "Escape") setOpen(false);
    };
    window.addEventListener("mousedown", onDown);
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("mousedown", onDown);
      window.removeEventListener("keydown", onKey);
    };
  }, [open]);

  const questions: { q: string; to: string }[] = [
    { q: "How do I start or join a meeting?", to: "/faq?q=start%20a%20meeting" },
    { q: "Can people without an account join?", to: "/faq?q=guest" },
    { q: "Where do Jasper's notes go?", to: "/faq?q=notes" },
    { q: "Nobody can hear or see me", to: "/faq?q=microphone" },
  ];

  return (
    <div className="relative" data-meet-help-menu="">
      <button
        type="button"
        aria-label="Help"
        aria-expanded={open}
        aria-haspopup="menu"
        onClick={() => setOpen((v) => !v)}
        className={cn(
          "grid h-10 w-10 place-items-center rounded-full transition-colors",
          open ? "bg-foreground text-background" : "text-muted-foreground hover:bg-secondary hover:text-foreground",
        )}
      >
        <HelpCircle className="h-5 w-5" />
      </button>
      {open && (
        <div
          role="menu"
          className="absolute right-0 top-[calc(100%+8px)] z-40 w-[300px] overflow-hidden rounded-[22px] border border-border bg-card p-1.5 shadow-2xl"
        >
          <p className={cn(KICKER, "px-3 pb-1 pt-2")}>Questions</p>
          {questions.map((item) => (
            <Link
              key={item.q}
              to={item.to}
              role="menuitem"
              onClick={() => setOpen(false)}
              className="flex items-center gap-2.5 rounded-2xl px-3 py-2 text-[13.5px] font-medium text-foreground/90 transition-colors hover:bg-secondary"
            >
              <span className="h-1 w-1 shrink-0 rounded-full" style={{ backgroundImage: WHISPER_BRAND_GRADIENT }} />
              <span className="min-w-0 flex-1 truncate">{item.q}</span>
            </Link>
          ))}
          <div className="my-1.5 border-t border-border" />
          <Link
            to="/faq"
            role="menuitem"
            onClick={() => setOpen(false)}
            className="flex items-center gap-3 rounded-2xl px-3 py-2.5 transition-colors hover:bg-secondary"
          >
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-secondary text-foreground">
              <BookOpen className="h-4 w-4" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-[13.5px] font-semibold leading-tight">All questions & answers</span>
              <span className="block truncate text-[11.5px] text-muted-foreground">The full Whisper FAQ</span>
            </span>
          </Link>
          <button
            type="button"
            role="menuitem"
            onClick={() => {
              setOpen(false);
              onReportBug();
            }}
            className="flex w-full items-center gap-3 rounded-2xl px-3 py-2.5 text-left transition-colors hover:bg-secondary"
          >
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-secondary text-foreground">
              <Bug className="h-4 w-4" />
            </span>
            <span className="min-w-0 flex-1">
              <span className="block text-[13.5px] font-semibold leading-tight">Report a bug</span>
              <span className="block truncate text-[11.5px] text-muted-foreground">Tell us what broke — we read every one</span>
            </span>
          </button>
        </div>
      )}
    </div>
  );
}

// ─── The day strip ──────────────────────────────────────────────────────────────────────

/** Width, in px, of the faded zone under each chevron where the ribbon dissolves. */
const STRIP_EDGE = 44;
const STRIP_SLIDE_MS = 360;

function weekStartOf(d: Date): Date {
  const c = startOfDay(d);
  c.setDate(c.getDate() - c.getDay());
  return c;
}

/**
 * One week at a time — Meet's rhythm in Whisper's grammar. The seven days
 * fill the row; the neighbouring days peek in under faded ends beneath two
 * ink-circle chevrons that glide the ribbon a whole week (three weeks sit on
 * a track that translates, then re-centers silently). Picking a peeking day
 * glides to its week; a far pick (mini calendar, Today) jumps.
 */
function DayStrip({
  selected,
  onPick,
  busy,
}: {
  selected: Date;
  onPick: (d: Date) => void;
  busy: (d: Date) => boolean;
}): JSX.Element {
  const [weekStart, setWeekStart] = useState<Date>(() => weekStartOf(selected));
  const [shift, setShift] = useState<-1 | 0 | 1>(0);
  const settling = useRef<number | null>(null);

  const slide = (dir: -1 | 1): void => {
    if (settling.current !== null) return;
    setShift(dir);
    settling.current = window.setTimeout(() => {
      setWeekStart((w) => new Date(w.getTime() + dir * 7 * DAY_MS));
      setShift(0);
      settling.current = null;
    }, STRIP_SLIDE_MS);
  };

  // Follow the pick: an adjacent week glides, anything further jumps.
  useEffect(() => {
    const target = weekStartOf(selected).getTime();
    if (target === weekStart.getTime() || settling.current !== null) return;
    const weeks = Math.round((target - weekStart.getTime()) / (7 * DAY_MS));
    if (Math.abs(weeks) === 1) slide(weeks as -1 | 1);
    else setWeekStart(new Date(target));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [selected]);

  useEffect(
    () => () => {
      if (settling.current !== null) window.clearTimeout(settling.current);
    },
    [],
  );

  const days = useMemo(
    () => Array.from({ length: 21 }, (_, i) => new Date(weekStart.getTime() + (i - 7) * DAY_MS)),
    [weekStart],
  );
  const today = new Date();
  const fade = `linear-gradient(to right, transparent 0, #000 ${STRIP_EDGE + 14}px, #000 calc(100% - ${STRIP_EDGE + 14}px), transparent 100%)`;
  const chevron =
    "absolute top-1/2 grid h-9 w-9 -translate-y-1/2 place-items-center rounded-full bg-foreground text-background shadow-[0_2px_8px_rgba(0,0,0,0.18)] transition-[transform,opacity] hover:opacity-90 active:scale-95";

  return (
    <div className="relative mt-4">
      <div className="overflow-hidden py-1" style={{ maskImage: fade, WebkitMaskImage: fade }}>
        <div
          className="flex will-change-transform"
          style={{
            width: `calc(300% - ${6 * STRIP_EDGE}px)`,
            transform: `translateX(calc(${(-(1 + shift) * 100) / 3}% + ${STRIP_EDGE}px))`,
            transition: shift === 0 ? "none" : `transform ${STRIP_SLIDE_MS}ms cubic-bezier(0.22, 1, 0.36, 1)`,
          }}
        >
          {days.map((d, i) => {
            const active = sameDay(d, selected);
            const isToday = sameDay(d, today);
            const isBusy = busy(d);
            const monthStart = d.getDate() === 1;
            const inWeek = i >= 7 && i < 14;
            return (
              <button
                key={d.toISOString()}
                type="button"
                onClick={() => onPick(d)}
                tabIndex={inWeek ? 0 : -1}
                className="flex shrink-0 flex-col items-center gap-1.5"
                style={{ width: `${100 / 21}%` }}
                aria-pressed={active}
                aria-label={d.toLocaleDateString(undefined, { weekday: "long", month: "long", day: "numeric" })}
              >
                <span
                  className={cn(
                    "text-[10.5px] font-bold uppercase tracking-[0.08em]",
                    active || monthStart ? "text-foreground" : "text-muted-foreground",
                  )}
                >
                  {monthStart
                    ? d.toLocaleDateString(undefined, { month: "short" })
                    : d.toLocaleDateString(undefined, { weekday: "short" })}
                </span>
                <span
                  className={cn(
                    "grid h-9 w-9 place-items-center rounded-full text-[14.5px] font-semibold tabular-nums transition-colors sm:h-10 sm:w-10 sm:text-[15px]",
                    active
                      ? "bg-foreground text-background"
                      : isToday
                        ? "ring-1 ring-foreground/60 hover:bg-secondary"
                        : "hover:bg-secondary",
                  )}
                >
                  {d.getDate()}
                </span>
                <span
                  className={cn("h-1 w-1 rounded-full", isBusy && !active ? "" : "bg-transparent")}
                  style={isBusy && !active ? { backgroundImage: WHISPER_BRAND_GRADIENT } : undefined}
                />
              </button>
            );
          })}
        </div>
      </div>
      <button type="button" aria-label="Previous week" onClick={() => slide(-1)} className={cn(chevron, "left-1")}>
        <ChevronLeft className="h-[18px] w-[18px]" strokeWidth={2.5} />
      </button>
      <button type="button" aria-label="Next week" onClick={() => slide(1)} className={cn(chevron, "right-1")}>
        <ChevronRight className="h-[18px] w-[18px]" strokeWidth={2.5} />
      </button>
    </div>
  );
}

/** The "nothing today" doodle — a mug, a pencil, a video card, in Whisper's palette. */
function LobbyDoodle(): JSX.Element {
  return (
    <svg width="300" height="164" viewBox="0 0 300 164" fill="none" aria-hidden className="max-w-full text-foreground/70">
      <defs>
        <linearGradient id="mugFill" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#FFD79A" />
          <stop offset="1" stopColor="#FF7340" />
        </linearGradient>
        <linearGradient id="blobFill" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#FFC2D1" />
          <stop offset="1" stopColor="#F9A8C0" />
        </linearGradient>
        <linearGradient id="pencilFill" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#FFE38A" />
          <stop offset="1" stopColor="#FFA94D" />
        </linearGradient>
      </defs>
      {/* ground line */}
      <path d="M22 146 H278" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      {/* pink blob */}
      <path d="M44 146 C36 118 48 92 74 88 C96 85 108 106 104 128 C101 142 90 146 78 146 Z" fill="url(#blobFill)" />
      {/* mug */}
      <path d="M112 146 L118 96 H174 L180 146 Z" fill="url(#mugFill)" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
      <path d="M176 106 C196 104 200 130 178 132" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" />
      {/* steam */}
      <path d="M134 84 C128 74 140 68 134 58" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" />
      <path d="M152 84 C146 72 160 66 152 54" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" />
      {/* pencil */}
      <g transform="rotate(-62 200 110)">
        <rect x="192" y="52" width="16" height="96" rx="2" fill="url(#pencilFill)" stroke="currentColor" strokeWidth="1.5" />
        <path d="M192 148 L200 164 L208 148 Z" fill="#FFE9CF" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" />
        <path d="M197 158 L200 164 L203 158 Z" fill="currentColor" />
        <rect x="192" y="52" width="16" height="10" rx="2" fill="#F22659" opacity="0.7" />
      </g>
      {/* video card */}
      <g transform="rotate(-8 236 112)">
        <rect x="204" y="84" width="72" height="56" rx="8" fill="#ffffff" stroke="currentColor" strokeWidth="1.5" />
        <rect x="204" y="84" width="72" height="56" rx="8" fill="url(#blobFill)" opacity="0.28" />
        <rect x="218" y="100" width="28" height="24" rx="5" stroke="currentColor" strokeWidth="1.5" fill="none" />
        <path d="M246 108 L260 100 V124 L246 116 Z" stroke="currentColor" strokeWidth="1.5" strokeLinejoin="round" fill="none" />
      </g>
      {/* sun dot + squiggle */}
      <circle cx="262" cy="30" r="9" fill="#FFE38A" />
      <path d="M186 38 C200 18 224 40 246 22" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" fill="none" />
    </svg>
  );
}

function SignedOut({ code, setCode, onJoin }: { code: string; setCode: (v: string) => void; onJoin: () => void }): JSX.Element {
  return (
    <div className="mx-auto mt-[6vh] max-w-md">
      <p className={KICKER}>Whisper Meet</p>
      <GradientTypeIn
        as="h1"
        text="Meet, the Whisper way."
        speed={26}
        className="mt-2 font-display text-[36px] font-extrabold leading-[1.06] tracking-tight sm:text-[44px]"
      />
      <p className="mt-3 text-[15px] leading-relaxed text-muted-foreground">
        Video meetings on your Whisper account — one link, everyone in, Jasper takes the notes.
      </p>
      <Link to="/auth" className={cn("mt-6 flex h-12 items-center justify-center rounded-full text-[14.5px] font-bold", INK_PILL)}>
        Sign in or create an account
      </Link>
      <div className="mt-4 flex h-12 items-center gap-2 rounded-full border border-border bg-background pl-4 pr-1.5 focus-within:border-foreground">
        <Keyboard className="h-4.5 w-4.5 text-muted-foreground" />
        <input
          value={code}
          onChange={(e) => setCode(e.target.value)}
          onKeyDown={(e) => e.key === "Enter" && onJoin()}
          placeholder="Have a code or link? Join as a guest"
          className="min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-muted-foreground/70"
        />
        <button type="button" onClick={onJoin} disabled={!code.trim()} aria-label="Join" className={cn("grid h-9 w-9 place-items-center rounded-full disabled:opacity-30", INK_PILL)}>
          <ArrowRight className="h-4 w-4" />
        </button>
      </div>
    </div>
  );
}

// ─── Calls tab ──────────────────────────────────────────────────────────────

function CallsTab({ history, meId, myUsername, onOpen }: { history: WhisperMeeting[]; meId: string; myUsername: string; onOpen: (id: string) => void }): JSX.Element {
  const [q, setQ] = useState<string>("");
  const [busy, setBusy] = useState<string | null>(null);
  const searchQuery = useQuery({
    queryKey: ["meet-call-search", q.trim().toLowerCase()],
    enabled: q.trim().length >= 2,
    queryFn: () => searchProfiles(q.trim()),
  });

  const startCall = async (p: WhisperProfile, mode: "audio" | "video"): Promise<void> => {
    if (busy) return;
    setBusy(p.user_id);
    try {
      const meeting = await createMeeting({
        hostId: meId,
        hostUsername: myUsername,
        title: `${mode === "audio" ? "Audio" : "Video"} call with @${p.username ?? "member"}`,
      });
      onOpen(`${meeting.id}?call=${encodeURIComponent(p.username ?? "")}${mode === "audio" ? "&mode=audio" : ""}`);
    } catch {
      toast.error("Couldn't start the call. Try again.");
    } finally {
      setBusy(null);
    }
  };

  return (
    <div className="mt-5">
      <p className={KICKER}>Calls</p>
      <h2 className="mt-1 text-[24px] font-bold tracking-tight">Ring someone.</h2>
      <p className="mt-1 text-[13.5px] text-muted-foreground">They answer from the app or the web — no link to paste.</p>
      <div className="mt-4 flex h-12 items-center gap-2 rounded-full border border-border bg-background pl-4 pr-2 focus-within:border-foreground">
        <Search className="h-4.5 w-4.5 text-muted-foreground" />
        <input value={q} onChange={(e) => setQ(e.target.value)} placeholder="Search by name or @username" className="min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-muted-foreground/70" />
        {q && (
          <button type="button" onClick={() => setQ("")} aria-label="Clear" className="grid h-8 w-8 place-items-center rounded-full hover:bg-secondary"><X className="h-4 w-4" /></button>
        )}
      </div>
      <div className="mt-3 space-y-1">
        {searchQuery.isLoading && <div className="flex items-center gap-2 px-2 py-3 text-[13px] text-muted-foreground"><Loader2 className="h-4 w-4 animate-spin" /> Searching…</div>}
        {(searchQuery.data ?? []).filter((p) => p.user_id !== meId).slice(0, 8).map((p) => (
          <div key={p.user_id} className="flex items-center gap-3 rounded-2xl px-2 py-2 hover:bg-secondary/60">
            <Avatar url={p.profile_image_url} name={p.username ?? p.display_name} size={40} />
            <div className="min-w-0 flex-1">
              <p className="truncate text-[14px] font-bold">{p.display_name || p.username}</p>
              <p className="truncate text-[12px] text-muted-foreground">@{p.username}</p>
            </div>
            <button type="button" disabled={!!busy} onClick={() => void startCall(p, "audio")} aria-label="Audio call" className="grid h-10 w-10 place-items-center rounded-full border border-border transition-colors hover:bg-secondary disabled:opacity-40"><Phone className="h-4 w-4" /></button>
            <button type="button" disabled={!!busy} onClick={() => void startCall(p, "video")} aria-label="Video call" className={cn("grid h-10 w-10 place-items-center rounded-full disabled:opacity-40", INK_PILL)}><Video className="h-4 w-4" /></button>
          </div>
        ))}
      </div>

      <p className={cn(KICKER, "mt-8")}>Call history</p>
      {history.length === 0 ? (
        <div className={cn(HAIRLINE_CARD, "mt-3 px-6 py-10 text-center")}>
          <PhoneCall className="mx-auto h-6 w-6 text-muted-foreground" />
          <p className="mt-2 text-[15px] font-semibold">No calls yet</p>
          <p className="text-[12.5px] text-muted-foreground">Calls you make or answer show up here.</p>
        </div>
      ) : (
        <ul className="mt-3 space-y-2">
          {history.map((m) => {
            const who = (m.title.match(/@([\w.]+)/)?.[1]) ?? m.host_username;
            const iso = m.started_at ?? m.created_at;
            const isVideo = /^video/i.test(m.title);
            return (
              <li key={m.id} className={cn(HAIRLINE_CARD, "flex items-center gap-3 px-4 py-3")}>
                <Avatar name={who} size={40} />
                <div className="min-w-0 flex-1">
                  <p className="truncate text-[14.5px] font-semibold">@{who}</p>
                  <p className="truncate text-[12px] text-muted-foreground">
                    {isVideo ? "Video" : "Audio"} · {m.host_id === meId ? "Outgoing" : "Incoming"}
                    {iso ? ` · ${new Date(iso).toLocaleString(undefined, { month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })}` : ""}
                  </p>
                </div>
                {m.status === "live" && (
                  <button type="button" onClick={() => onOpen(m.id)} className="rounded-full px-4 py-2 text-[13px] font-bold text-white" style={{ backgroundImage: WHISPER_BRAND_GRADIENT_DIAGONAL }}>Rejoin</button>
                )}
              </li>
            );
          })}
        </ul>
      )}
    </div>
  );
}

// ─── Schedule dialog ─────────────────────────────────────────────────────────

function ScheduleDialog({
  meId,
  myUsername,
  defaultDay,
  onClose,
  onCreated,
}: {
  meId: string;
  myUsername: string;
  defaultDay: Date;
  onClose: () => void;
  onCreated: () => void;
}): JSX.Element {
  const [title, setTitle] = useState<string>("");
  const [start, setStart] = useState<string>(() => {
    const base = sameDay(defaultDay, new Date()) ? new Date(Date.now() + 60 * 60 * 1000) : new Date(defaultDay);
    if (!sameDay(defaultDay, new Date())) base.setHours(12, 0, 0, 0);
    else base.setMinutes(0, 0, 0);
    return toLocalInput(base);
  });
  const [duration, setDuration] = useState<number>(30);
  const [recurrence, setRecurrence] = useState<CalendarRecurrence>("none");
  const [description, setDescription] = useState<string>("");
  const [guestQ, setGuestQ] = useState<string>("");
  const [guests, setGuests] = useState<WhisperProfile[]>([]);
  const [emailGuests, setEmailGuests] = useState<string[]>([]);
  const [emailDraft, setEmailDraft] = useState<string>("");
  const [notify, setNotify] = useState<boolean>(true);
  const [saving, setSaving] = useState<boolean>(false);

  const guestSearch = useQuery({
    queryKey: ["meet-guest-search", guestQ.trim().toLowerCase()],
    enabled: guestQ.trim().length >= 2,
    queryFn: () => searchProfiles(guestQ.trim()),
  });

  const commitEmailDraft = (): void => {
    const parsed = parseEmailList(emailDraft);
    if (parsed.length === 0) return;
    setEmailGuests((prev) => Array.from(new Set([...prev, ...parsed])));
    setEmailDraft("");
  };

  const save = async (): Promise<void> => {
    if (saving) return;
    const startDate = new Date(start);
    if (Number.isNaN(startDate.getTime())) {
      toast.error("Pick a start time.");
      return;
    }
    // A draft still sitting in the email field counts.
    const pendingEmails = parseEmailList(emailDraft);
    const allEmails = Array.from(new Set([...emailGuests, ...pendingEmails]));
    setSaving(true);
    try {
      const finalTitle = title.trim() || "Meeting";
      // A pretty wsp- code for the scheduled room (the row lives at the
      // code's deterministic id, so the link opens the same room everywhere).
      const codeId = newMeetingId();
      await createMeeting({
        hostId: meId,
        hostUsername: myUsername,
        title: finalTitle,
        scheduledAt: startDate.toISOString(),
        id: meetingIdFromCode(codeId),
      });
      const link = meetingLink(codeId);
      const endDate = new Date(startDate.getTime() + duration * 60_000);
      const event: CalendarEvent | null = await createCalendarEvent({
        createdBy: meId,
        createdByUsername: myUsername,
        title: finalTitle,
        description: description.trim() || undefined,
        eventType: "meet",
        startTime: startDate.toISOString(),
        endTime: endDate.toISOString(),
        meetingLink: link,
        taggedUserIds: guests.map((g) => g.user_id),
        taggedUsernames: guests.map((g) => g.username ?? ""),
        recurrence,
      });
      if (notify && event && guests.length > 0) {
        await sendCalendarTeamDMs(event, { id: meId, username: myUsername }, "invite").catch(() => undefined);
      }
      let emailed = 0;
      let emailProblem: string | null = null;
      if (allEmails.length > 0) {
        const result = await sendMeetingInviteEmails({
          emails: allEmails,
          title: finalTitle,
          link,
          hostUsername: myUsername,
          startsAt: startDate.toISOString(),
          endsAt: endDate.toISOString(),
          description: description.trim() || null,
          code: codeId,
          recurrenceLabel: recurrence !== "none" ? RECURRENCE_LABELS[recurrence] : null,
        }).catch(() => ({ ok: false, sent: 0, error: "network" }));
        emailed = result.sent;
        if (!result.ok) emailProblem = result.error ?? "send_failed";
      }
      const parts: string[] = ["Scheduled"];
      if (guests.length > 0) parts.push(`${guests.length} invited on Whisper`);
      if (emailed > 0) parts.push(`${emailed} emailed`);
      toast.success(parts.join(" · ") + (parts.length === 1 ? " and added to your calendar." : "."));
      if (emailProblem) {
        toast.error(
          emailProblem === "not_configured"
            ? "Email invites aren't set up on this deployment yet — the link is in your calendar."
            : emailProblem === "sign_in_required"
              ? "Sign in again to send email invites — the link is in your calendar."
              : `The email invites didn't go out (${emailProblem}) — share the link from the calendar instead.`,
        );
      }
      onCreated();
    } catch (err) {
      toast.error(err instanceof Error ? err.message : "Couldn't schedule the meeting.");
    } finally {
      setSaving(false);
    }
  };

  const durationLabel = (m: number): string => (m < 60 ? `${m} min` : `${m / 60} hr${m > 60 ? "s" : ""}`);

  return (
    <div className="fixed inset-0 z-[70] flex items-end justify-center bg-black/50 p-0 sm:items-center sm:p-4" role="dialog" aria-modal="true" aria-label="Schedule a meeting" onClick={onClose}>
      <div
        className="max-h-[92vh] w-full max-w-[560px] overflow-y-auto rounded-t-[28px] bg-card shadow-2xl sm:rounded-[28px] [scrollbar-width:none] [&::-webkit-scrollbar]:hidden"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="sticky top-0 z-10 flex items-start gap-3 border-b border-border bg-card/95 px-5 pb-3 pt-5 backdrop-blur">
          <div className="min-w-0 flex-1">
            <p className={KICKER}>Schedule</p>
            <h2 className="mt-0.5 text-[20px] font-bold tracking-tight">New meeting</h2>
          </div>
          <button type="button" onClick={onClose} aria-label="Close" className="grid h-10 w-10 place-items-center rounded-full hover:bg-secondary"><X className="h-5 w-5" /></button>
        </div>

        <div className="px-5 pb-5">
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Give it a name"
            className="mt-4 w-full border-b border-border bg-transparent pb-2.5 text-[22px] font-bold tracking-tight outline-none transition-colors placeholder:font-semibold placeholder:text-muted-foreground/50 focus:border-foreground"
          />

          <div className="mt-5 grid gap-3 sm:grid-cols-2">
            <label className="text-[11.5px] font-bold uppercase tracking-[0.12em] text-muted-foreground">
              Starts
              <input type="datetime-local" value={start} onChange={(e) => setStart(e.target.value)} className={cn(FIELD, "mt-1.5 font-medium normal-case tracking-normal")} />
            </label>
            <label className="text-[11.5px] font-bold uppercase tracking-[0.12em] text-muted-foreground">
              Duration
              <select value={duration} onChange={(e) => setDuration(Number(e.target.value))} className={cn(FIELD, "mt-1.5 font-medium normal-case tracking-normal")}>
                {[15, 30, 45, 60, 90, 120].map((m) => <option key={m} value={m}>{durationLabel(m)}</option>)}
              </select>
            </label>
            <label className="text-[11.5px] font-bold uppercase tracking-[0.12em] text-muted-foreground sm:col-span-2">
              Repeats
              <select value={recurrence} onChange={(e) => setRecurrence(e.target.value as CalendarRecurrence)} className={cn(FIELD, "mt-1.5 font-medium normal-case tracking-normal")}>
                {(Object.keys(RECURRENCE_LABELS) as CalendarRecurrence[]).map((r) => <option key={r} value={r}>{RECURRENCE_LABELS[r]}</option>)}
              </select>
            </label>
          </div>

          <div className="mt-4 flex items-center gap-3 rounded-2xl border border-border px-3.5 py-3">
            <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full text-white" style={{ backgroundImage: WHISPER_BRAND_GRADIENT_DIAGONAL }}>
              <Video className="h-4 w-4" />
            </span>
            <div className="min-w-0 flex-1">
              <p className="text-[13.5px] font-semibold">Whisper Meet link attached</p>
              <p className="text-[12px] text-muted-foreground">A wsp- code is minted when you save — everyone invited gets it.</p>
            </div>
          </div>

          <div className="mt-5">
            <p className="text-[11.5px] font-bold uppercase tracking-[0.12em] text-muted-foreground">Guests on Whisper</p>
            {guests.length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1.5">
                {guests.map((g) => (
                  <span key={g.user_id} className="flex items-center gap-1.5 rounded-full bg-secondary py-1 pl-1 pr-2 text-[12.5px] font-semibold">
                    <Avatar url={g.profile_image_url} name={g.username} size={20} /> @{g.username}
                    <button type="button" onClick={() => setGuests((prev) => prev.filter((x) => x.user_id !== g.user_id))} aria-label={`Remove ${g.username}`} className="grid h-4 w-4 place-items-center rounded-full hover:bg-black/10"><X className="h-3 w-3" /></button>
                  </span>
                ))}
              </div>
            )}
            <div className={cn(FIELD, "mt-2 flex items-center gap-2 focus-within:border-foreground")}>
              <Search className="h-4 w-4 text-muted-foreground" />
              <input value={guestQ} onChange={(e) => setGuestQ(e.target.value)} placeholder="Add guests by @username" className="min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-muted-foreground/60" />
            </div>
            {guestQ.trim().length >= 2 && (
              <div className="mt-1 max-h-[180px] overflow-y-auto rounded-2xl border border-border bg-card [scrollbar-width:none] [&::-webkit-scrollbar]:hidden">
                {(guestSearch.data ?? []).filter((p) => p.user_id !== meId && !guests.some((g) => g.user_id === p.user_id)).slice(0, 6).map((p) => (
                  <button key={p.user_id} type="button" onClick={() => { setGuests((prev) => [...prev, p]); setGuestQ(""); }} className="flex w-full items-center gap-3 px-3 py-2 text-left hover:bg-secondary">
                    <Avatar url={p.profile_image_url} name={p.username} size={30} />
                    <span className="text-[13.5px] font-semibold">{p.display_name || p.username}</span>
                    <span className="text-[12px] text-muted-foreground">@{p.username}</span>
                  </button>
                ))}
                {guestSearch.data && guestSearch.data.length === 0 && <p className="px-3 py-2 text-[12.5px] text-muted-foreground">No one found.</p>}
              </div>
            )}
          </div>

          <div className="mt-5">
            <p className="text-[11.5px] font-bold uppercase tracking-[0.12em] text-muted-foreground">Invite by email</p>
            {emailGuests.length > 0 && (
              <div className="mt-2 flex flex-wrap gap-1.5">
                {emailGuests.map((e) => (
                  <span key={e} className="flex items-center gap-1.5 rounded-full bg-secondary py-1 pl-2.5 pr-2 text-[12.5px] font-semibold">
                    <Mail className="h-3 w-3 text-muted-foreground" /> {e}
                    <button type="button" onClick={() => setEmailGuests((prev) => prev.filter((x) => x !== e))} aria-label={`Remove ${e}`} className="grid h-4 w-4 place-items-center rounded-full hover:bg-black/10"><X className="h-3 w-3" /></button>
                  </span>
                ))}
              </div>
            )}
            <div className={cn(FIELD, "mt-2 flex items-center gap-2 focus-within:border-foreground")}>
              <Mail className="h-4 w-4 text-muted-foreground" />
              <input
                value={emailDraft}
                onChange={(e) => setEmailDraft(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" || e.key === "," || e.key === " ") {
                    if (isLikelyEmail(emailDraft.trim()) || emailDraft.includes(",")) {
                      e.preventDefault();
                      commitEmailDraft();
                    }
                  } else if (e.key === "Backspace" && !emailDraft && emailGuests.length > 0) {
                    setEmailGuests((prev) => prev.slice(0, -1));
                  }
                }}
                onBlur={commitEmailDraft}
                onPaste={(e) => {
                  const text = e.clipboardData.getData("text");
                  const parsed = parseEmailList(text);
                  if (parsed.length > 1) {
                    e.preventDefault();
                    setEmailGuests((prev) => Array.from(new Set([...prev, ...parsed])));
                  }
                }}
                type="email"
                inputMode="email"
                autoComplete="off"
                placeholder="name@company.com"
                className="min-w-0 flex-1 bg-transparent text-[14px] outline-none placeholder:text-muted-foreground/60"
              />
            </div>
            <p className="mt-1.5 text-[11.5px] leading-relaxed text-muted-foreground">
              They get a formatted invite with the time, a Join button, the joining info, a calendar file, and an add-to-Google-Calendar link.
            </p>
          </div>

          <textarea
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="What's it about? (optional)"
            rows={3}
            className={cn(FIELD, "mt-5 h-auto resize-none py-2.5")}
          />

          <label className="mt-3 flex items-center gap-3 text-[13.5px]">
            <input type="checkbox" checked={notify} onChange={(e) => setNotify(e.target.checked)} className="h-4 w-4 accent-foreground" />
            Send Whisper guests the invite in Messages
          </label>

          <div className="mt-5 flex justify-end gap-2">
            <button type="button" onClick={onClose} className="h-11 rounded-full px-4 text-[13.5px] font-semibold text-muted-foreground transition-colors hover:bg-secondary">Cancel</button>
            <button
              type="button"
              onClick={() => void save()}
              disabled={saving}
              className="flex h-11 items-center gap-2 rounded-full px-5 text-[13.5px] font-bold text-white transition-transform active:scale-[0.98] disabled:opacity-50"
              style={{ backgroundImage: WHISPER_BRAND_GRADIENT_DIAGONAL }}
            >
              {saving && <Loader2 className="h-4 w-4 animate-spin" />} Schedule
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
