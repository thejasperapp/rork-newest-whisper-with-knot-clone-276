import { useMemo, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import {
  Plus,
  ChevronLeft,
  ChevronRight,
  MapPin,
  Clock,
  Trash2,
  X,
  Users,
  Check,
  HelpCircle,
  CalendarDays,
  StickyNote,
  Send,
  Video,
  ExternalLink,
  Download,
  Repeat,
  AlertTriangle,
  Camera,
  CalendarPlus,
  Mail,
} from "lucide-react";
import { toast } from "sonner";
import { parseMeetingInvitation } from "@/lib/meetingInvitation";

import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import { searchProfiles } from "@/lib/api";
import { FloatingHeader, FloatingButton } from "@/components/FloatingHeader";
import {
  fetchCalendarEvents,
  createCalendarEvent,
  deleteCalendarEvent,
  fetchRSVPs,
  setRSVP,
  fetchNotes,
  addNote,
  deleteNote,
  fetchEventParticipantProfiles,
  roleLabelFor,
  sendCalendarTeamDMs,
  detectConflicts,
  downloadICS,
  googleCalendarUrl,
  eventHasEnded,
  addRecap,
  isRecapNote,
  recapBody,
  EVENT_TYPE_LABELS,
  EVENT_TYPE_COLORS,
  RECURRENCE_LABELS,
  eventDayKeys,
  multiDayLabel,
  type CalendarEvent,
  type CalendarEventType,
  type CalendarRecurrence,
  type CalendarRSVP,
  type CalendarNote,
} from "@/lib/calendar";
import { cn } from "@/lib/utils";
import { timeAgo } from "@/lib/format";
import { isLikelyEmail, parseEmailList, sendMeetingInviteEmails } from "@/lib/meetInvites";
import type { WhisperProfile } from "@/lib/types";

const MONTH_NAMES = [
  "January", "February", "March", "April", "May", "June",
  "July", "August", "September", "October", "November", "December",
];

const WEEKDAY_LABELS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];

const EVENT_TYPES = Object.keys(EVENT_TYPE_LABELS) as CalendarEventType[];

const ROLE_STYLES: Record<string, string> = {
  Coach: "bg-orange-500/15 text-orange-600",
  Athlete: "bg-red-500/15 text-red-500",
  Creator: "bg-sky-500/15 text-sky-600",
  Recruiter: "bg-violet-500/15 text-violet-600",
};

/** Collect all unique participant user IDs for a day's events (going RSVPs + tagged + creator). */
function dayParticipants(
  dayEvents: CalendarEvent[],
  rsvps: Record<string, CalendarRSVP[]>
): string[] {
  const ids = new Set<string>();
  for (const e of dayEvents) {
    if (e.created_by) ids.add(e.created_by);
    for (const uid of e.tagged_user_ids) ids.add(uid);
    for (const r of rsvps[e.id] ?? []) {
      if (r.status === "going") ids.add(r.user_id);
    }
  }
  return Array.from(ids);
}

export default function CalendarPage() {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [cursor, setCursor] = useState<Date>(new Date());
  const [selectedDate, setSelectedDate] = useState<Date | null>(null);
  const [showCreate, setShowCreate] = useState<boolean>(false);
  // Phones default to the agenda list — month/week cells overflow small
  // screens; desktop keeps the classic month grid.
  const [viewMode, setViewMode] = useState<"month" | "week" | "agenda">(() =>
    typeof window !== "undefined" && window.innerWidth < 640 ? "agenda" : "month"
  );

  const year = cursor.getFullYear();
  const month = cursor.getMonth();
  const monthStart = new Date(year, month, 1).toISOString();
  const monthEnd = new Date(year, month + 1, 1).toISOString();

  const eventsQuery = useQuery({
    queryKey: ["calendar-events", user?.id, monthStart],
    queryFn: () => fetchCalendarEvents(monthStart, monthEnd),
    enabled: !!user,
    staleTime: 30_000,
    gcTime: 10 * 60_000,
  });
  const events = eventsQuery.data ?? [];

  const selectedEvents = useMemo(() => {
    if (!selectedDate) return [];
    const key = `${selectedDate.getFullYear()}-${selectedDate.getMonth()}-${selectedDate.getDate()}`;
    return events.filter(event => eventDayKeys(event).includes(key));
  }, [selectedDate, events]);
  const selectedEventIds = useMemo(() => selectedEvents.map(event => event.id), [selectedEvents]);
  const eventIds = useMemo(() => events.map((e) => e.id), [events]);
  const rsvpsQuery = useQuery({
    queryKey: ["calendar-rsvps", user?.id, eventIds],
    queryFn: () => fetchRSVPs(eventIds),
    enabled: eventIds.length > 0,
  });
  const rsvps = rsvpsQuery.data ?? {};

  // Notes are only rendered for the selected day, not every event in a month.
  const notesQuery = useQuery({
    queryKey: ["calendar-notes", user?.id, selectedEventIds],
    queryFn: () => fetchNotes(selectedEventIds),
    enabled: !!user && selectedEventIds.length > 0,
  });
  const notes = notesQuery.data ?? {};

  // RSVP fingerprint — the profiles fetch closes over `rsvps`, so its key
  // must change when RSVPs do, or a fresh "going" avatar never appears
  // until a full reload / month change.
  const rsvpStamp = useMemo(() => {
    const parts: string[] = [];
    for (const [eventId, list] of Object.entries(rsvps)) {
      for (const r of list) parts.push(`${eventId}:${r.user_id}:${r.status}`);
    }
    return parts.sort().join("|");
  }, [rsvps]);

  // Fetch participant profiles for avatars + roles
  const profilesQuery = useQuery({
    queryKey: ["calendar-participants", user?.id, eventIds, rsvpStamp],
    queryFn: () => fetchEventParticipantProfiles(events, rsvps),
    enabled: events.length > 0 && !!rsvpsQuery.data,
  });
  const profiles = profilesQuery.data ?? {};

  // Group events by day — a multi-day event lands on EVERY day it spans,
  // not just the day it starts (start → end inclusive).
  const eventsByDay = useMemo(() => {
    const map: Record<string, CalendarEvent[]> = {};
    for (const e of events) {
      for (const key of eventDayKeys(e)) {
        if (!map[key]) map[key] = [];
        map[key].push(e);
      }
    }
    return map;
  }, [events]);

  // Build calendar grid
  const firstDay = new Date(year, month, 1).getDay();
  const daysInMonth = new Date(year, month + 1, 0).getDate();
  const today = new Date();
  const isToday = (d: number): boolean =>
    year === today.getFullYear() &&
    month === today.getMonth() &&
    d === today.getDate();

  const rsvpMutation = useMutation({
    mutationFn: ({
      eventId,
      status,
    }: {
      eventId: string;
      status: "going" | "maybe" | "declined";
    }) =>
      setRSVP(eventId, user!.id, profile?.username ?? "you", status),
    onSettled: () =>
      queryClient.invalidateQueries({ queryKey: ["calendar-rsvps"] }),
  });

  const deleteMutation = useMutation({
    mutationFn: async (event: CalendarEvent) => {
      // Tell tagged users the event is cancelled — DM comes from the organizer.
      await sendCalendarTeamDMs(
        event,
        { id: user!.id, username: profile?.username ?? "you" },
        "cancelled"
      );
      await deleteCalendarEvent(event.id);
    },
    onSuccess: () => {
      toast("Event deleted — attendees notified by DM");
      queryClient.invalidateQueries({ queryKey: ["calendar-events"] });
    },
    onError: () => toast("Couldn't delete event"),
  });

  // Conflict detection — same person on two overlapping events
  const conflictIds = useMemo(() => detectConflicts(events), [events]);

  return (
    <div className="min-h-screen bg-muted/30">
      <FloatingHeader
        title="Shared Calendar"
        right={
          <>
            {/* Plain labeled buttons — the glass circles are retired here. */}
            <button
              onClick={() => {
                if (events.length === 0) {
                  toast("No events this month to export");
                  return;
                }
                downloadICS(events);
                toast("Calendar exported — open the file to subscribe in Google/Apple Calendar");
              }}
              className="flex h-9 items-center gap-1.5 rounded-lg border border-border bg-card px-3 text-[13px] font-semibold text-foreground transition-colors hover:bg-secondary"
              aria-label="Export calendar (.ics)"
            >
              <Download className="h-4 w-4" />
              Export
            </button>
            <button
              onClick={() => setShowCreate(true)}
              className="flex h-9 items-center gap-1.5 rounded-lg bg-foreground px-3 text-[13px] font-semibold text-background transition-transform active:scale-95"
              aria-label="New event"
            >
              <Plus className="h-4 w-4" />
              New event
            </button>
          </>
        }
      />

      {/* Wider container for the bigger calendar */}
      <div className="mx-auto max-w-5xl px-4 py-4">
        {/* Navigation + view toggle */}
        <div className="mb-4 flex items-center justify-between gap-2">
          <button
            onClick={() =>
              setCursor(
                viewMode !== "week"
                  ? new Date(year, month - 1, 1)
                  : new Date(year, month, cursor.getDate() - 7)
              )
            }
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          >
            <ChevronLeft className="h-5 w-5" />
          </button>
          <div className="flex min-w-0 flex-col items-center gap-1">
            <h2 className="font-display text-[20px] font-bold">
              {viewMode !== "week"
                ? `${MONTH_NAMES[month]} ${year}`
                : `${MONTH_NAMES[cursor.getMonth()]} ${cursor.getDate()}, ${year}`}
            </h2>
            <div className="flex items-center gap-0.5 rounded-full bg-secondary p-0.5">
              <button
                onClick={() => setViewMode("month")}
                className={cn(
                  "rounded-full px-3 py-0.5 text-[11px] font-bold transition-colors",
                  viewMode === "month" ? "bg-background text-foreground shadow-sm" : "text-muted-foreground"
                )}
              >
                Month
              </button>
              <button
                onClick={() => setViewMode("week")}
                className={cn(
                  "rounded-full px-3 py-0.5 text-[11px] font-bold transition-colors",
                  viewMode === "week" ? "bg-background text-foreground shadow-sm" : "text-muted-foreground"
                )}
              >
                Week
              </button>
              <button
                onClick={() => setViewMode("agenda")}
                className={cn(
                  "rounded-full px-3 py-0.5 text-[11px] font-bold transition-colors",
                  viewMode === "agenda" ? "bg-background text-foreground shadow-sm" : "text-muted-foreground"
                )}
              >
                Agenda
              </button>
            </div>
          </div>
          <button
            onClick={() =>
              setCursor(
                viewMode === "month"
                  ? new Date(year, month + 1, 1)
                  : new Date(year, month, cursor.getDate() + 7)
              )
            }
            className="flex h-9 w-9 shrink-0 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          >
            <ChevronRight className="h-5 w-5" />
          </button>
        </div>

        {/* Calendar grid — month or week view */}
        <div className="rounded-2xl border border-border bg-card overflow-hidden">
          {/* Weekday labels (grid views only) */}
          {viewMode !== "agenda" && (
            <div className="grid grid-cols-7 border-b border-border bg-secondary/30">
              {WEEKDAY_LABELS.map((d) => (
                <div
                  key={d}
                  className="py-2.5 text-center text-[11px] font-bold uppercase tracking-wider text-muted-foreground"
                >
                  {d}
                </div>
              ))}
            </div>
          )}

          {viewMode === "agenda" && (
            /* Agenda — the month as a readable list (phone-first). */
            (() => {
              const agendaDays: { day: number; list: typeof events }[] = [];
              for (let d = 1; d <= daysInMonth; d++) {
                const list = eventsByDay[`${year}-${month}-${d}`] ?? [];
                if (list.length > 0) {
                  agendaDays.push({
                    day: d,
                    list: [...list].sort(
                      (a, b) =>
                        new Date(a.start_time).getTime() - new Date(b.start_time).getTime()
                    ),
                  });
                }
              }
              if (agendaDays.length === 0) {
                return (
                  <div className="flex flex-col items-center gap-2 px-6 py-14 text-center">
                    <CalendarDays className="h-7 w-7 text-muted-foreground/50" />
                    <p className="text-[14px] font-bold">Nothing scheduled this month</p>
                    <p className="max-w-xs text-[12px] leading-relaxed text-muted-foreground">
                      Tap + to add an event — tagged teammates get a DM and it lands on
                      everyone's calendar.
                    </p>
                  </div>
                );
              }
              return (
                <div className="divide-y divide-border/50">
                  {agendaDays.map(({ day, list }) => {
                    const isCurrent = isToday(day);
                    const date = new Date(year, month, day);
                    const weekday = date.toLocaleDateString(undefined, { weekday: "short" });
                    const participants = dayParticipants(list, rsvps);
                    const visiblePics = participants.slice(0, 4);
                    const overflowCount = participants.length - 4;
                    const isSelected =
                      selectedDate?.getFullYear() === year &&
                      selectedDate?.getMonth() === month &&
                      selectedDate?.getDate() === day;
                    return (
                      <button
                        key={day}
                        onClick={() => setSelectedDate(date)}
                        className={cn(
                          "flex w-full items-start gap-3 px-3.5 py-3 text-left transition-colors",
                          isSelected ? "bg-secondary" : "hover:bg-secondary/30"
                        )}
                      >
                        <div className="flex w-11 shrink-0 flex-col items-center pt-0.5">
                          <span className="text-[10px] font-bold uppercase tracking-wide text-muted-foreground">
                            {weekday}
                          </span>
                          <span
                            className={cn(
                              "mt-0.5 flex h-8 w-8 items-center justify-center rounded-full text-[15px] font-extrabold tabular-nums",
                              isCurrent
                                ? "bg-primary text-primary-foreground"
                                : "text-foreground/85"
                            )}
                          >
                            {day}
                          </span>
                        </div>
                        <div className="min-w-0 flex-1 space-y-1.5">
                          {list.map((e) => {
                            const spanLabel = multiDayLabel(e, date);
                            return (
                            <div key={e.id} className="flex items-center gap-2">
                              <span
                                className="h-2 w-2 shrink-0 rounded-full"
                                style={{ backgroundColor: EVENT_TYPE_COLORS[e.event_type] }}
                              />
                              <span className="shrink-0 text-[11px] font-bold tabular-nums text-muted-foreground">
                                {spanLabel && !spanLabel.startsWith("Day 1 ")
                                  ? spanLabel
                                  : new Date(e.start_time).toLocaleTimeString("en-US", {
                                      hour: "numeric",
                                      minute: "2-digit",
                                    })}
                              </span>
                              <span className="truncate text-[13px] font-semibold">{e.title}</span>
                              {conflictIds.has(e.id) && (
                                <AlertTriangle className="h-3 w-3 shrink-0 text-amber-500" />
                              )}
                            </div>
                            );
                          })}
                          {visiblePics.length > 0 && (
                            <div className="flex items-center pt-0.5">
                              <div className="flex -space-x-1.5">
                                {visiblePics.map((uid) => {
                                  const p = profiles[uid];
                                  return (
                                    <div key={uid} className="ring-2 ring-card rounded-full">
                                      <Avatar
                                        url={p?.profile_image_url}
                                        name={p?.username ?? "?"}
                                        size={18}
                                      />
                                    </div>
                                  );
                                })}
                              </div>
                              {overflowCount > 0 && (
                                <span className="ml-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-secondary px-1 text-[10px] font-bold text-muted-foreground">
                                  +{overflowCount}
                                </span>
                              )}
                            </div>
                          )}
                        </div>
                        <ChevronRight className="mt-1 h-4 w-4 shrink-0 text-muted-foreground/50" />
                      </button>
                    );
                  })}
                </div>
              );
            })()
          )}

          {viewMode === "agenda" ? null : viewMode === "month" ? (
            /* Month view — each cell is ~2x taller */
            <div className="grid grid-cols-7">
              {Array.from({ length: firstDay }).map((_, i) => (
                <div
                  key={`empty-${i}`}
                  className="min-h-[130px] border-b border-border/50 max-lg:[&:nth-child(7n)]:border-r-0 lg:[&:nth-child(7n)]:border-r-0"
                />
              ))}
              {Array.from({ length: daysInMonth }).map((_, i) => {
                const day = i + 1;
                const key = `${year}-${month}-${day}`;
                const dayEvents = eventsByDay[key] ?? [];
                const isCurrent = isToday(day);
                const isSelected =
                  selectedDate?.getFullYear() === year &&
                  selectedDate?.getMonth() === month &&
                  selectedDate?.getDate() === day;
                const participants = dayParticipants(dayEvents, rsvps);
                const visiblePics = participants.slice(0, 3);
                const overflowCount = participants.length - 3;
                const colIndex = (firstDay + i) % 7;
                const isLastCol = colIndex === 6;
                const isLastRow = Math.ceil((firstDay + daysInMonth) / 7) * 7 - (firstDay + i) <= 7 - colIndex - 1 && firstDay + i + 1 > Math.ceil((firstDay + daysInMonth) / 7) * 7 - 7;

                return (
                  <button
                    key={day}
                    onClick={() => setSelectedDate(new Date(year, month, day))}
                    className={cn(
                      "flex min-h-[130px] flex-col p-2 text-left transition-colors border-b border-border/50",
                      !isLastCol && "border-r border-border/50",
                      isSelected ? "bg-secondary" : "hover:bg-secondary/30"
                    )}
                  >
                    <span
                      className={cn(
                        "inline-flex h-6 w-6 shrink-0 items-center justify-center text-[13px] font-bold tabular-nums",
                        isCurrent
                          ? "rounded-full bg-primary text-primary-foreground"
                          : "text-foreground/80"
                      )}
                    >
                      {day}
                    </span>
                    {dayEvents.length > 0 && (
                      <div className="mt-1.5 flex flex-wrap items-center gap-1">
                        {dayEvents.slice(0, 4).map((e) => (
                          <span
                            key={e.id}
                            className="h-2 w-2 rounded-full"
                            style={{ backgroundColor: EVENT_TYPE_COLORS[e.event_type] }}
                          />
                        ))}
                        {dayEvents.length > 4 && (
                          <span className="text-[10px] font-bold text-muted-foreground">
                            +{dayEvents.length - 4}
                          </span>
                        )}
                        {dayEvents.some((e) => conflictIds.has(e.id)) && (
                          <AlertTriangle className="h-3 w-3 text-amber-500" />
                        )}
                      </div>
                    )}
                    {/* Spacer pushes avatars to bottom */}
                    <div className="flex-1" />
                    {visiblePics.length > 0 && (
                      <div className="mt-1.5 flex items-center">
                        <div className="flex -space-x-1.5">
                          {visiblePics.map((uid) => {
                            const p = profiles[uid];
                            return (
                              <div
                                key={uid}
                                className="ring-2 ring-card rounded-full"
                              >
                                <Avatar
                                  url={p?.profile_image_url}
                                  name={p?.username ?? "?"}
                                  size={20}
                                />
                              </div>
                            );
                          })}
                        </div>
                        {overflowCount > 0 && (
                          <span className="ml-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-secondary px-1 text-[10px] font-bold text-muted-foreground">
                            +{overflowCount}
                          </span>
                        )}
                      </div>
                    )}
                  </button>
                );
              })}
            </div>
          ) : (
            /* Week view — 7 columns with expanded event details */
            (() => {
              const weekStart = new Date(cursor);
              weekStart.setDate(cursor.getDate() - cursor.getDay());
              const weekDays = Array.from({ length: 7 }).map((_, i) => {
                const d = new Date(weekStart);
                d.setDate(weekStart.getDate() + i);
                return d;
              });
              return (
                <div className="grid grid-cols-7">
                  {weekDays.map((d, i) => {
                    const key = `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
                    const dayEvents = eventsByDay[key] ?? [];
                    const isCurrent =
                      d.getFullYear() === today.getFullYear() &&
                      d.getMonth() === today.getMonth() &&
                      d.getDate() === today.getDate();
                    const isSelected =
                      selectedDate?.getFullYear() === d.getFullYear() &&
                      selectedDate?.getMonth() === d.getMonth() &&
                      selectedDate?.getDate() === d.getDate();
                    const participants = dayParticipants(dayEvents, rsvps);
                    const visiblePics = participants.slice(0, 3);
                    const overflowCount = participants.length - 3;
                    const isLastCol = i === 6;

                    return (
                      <button
                        key={i}
                        onClick={() => setSelectedDate(new Date(d))}
                        className={cn(
                          "flex min-h-[300px] flex-col p-2.5 text-left transition-colors border-b border-border/50",
                          !isLastCol && "border-r border-border/50",
                          isSelected ? "bg-secondary" : "hover:bg-secondary/30"
                        )}
                      >
                        <span
                          className={cn(
                            "inline-flex h-7 w-7 shrink-0 items-center justify-center text-[13px] font-bold tabular-nums",
                            isCurrent
                              ? "rounded-full bg-primary text-primary-foreground"
                              : "text-foreground/80"
                          )}
                        >
                          {d.getDate()}
                        </span>
                        {/* Event details in week view */}
                        <div className="mt-2 space-y-1.5">
                          {dayEvents.slice(0, 4).map((e) => (
                            <div
                              key={e.id}
                              className="truncate rounded-md px-2 py-1 text-[10px] font-bold leading-tight"
                              style={{
                                backgroundColor: `${EVENT_TYPE_COLORS[e.event_type]}18`,
                                color: EVENT_TYPE_COLORS[e.event_type],
                              }}
                            >
                              <span
                                className="mr-1 inline-block h-1.5 w-1.5 shrink-0 rounded-full align-middle"
                                style={{ backgroundColor: EVENT_TYPE_COLORS[e.event_type] }}
                              />
                              {new Date(e.start_time).toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" })} {e.title}
                            </div>
                          ))}
                          {dayEvents.length > 4 && (
                            <span className="text-[10px] font-bold text-muted-foreground">
                              +{dayEvents.length - 4} more
                            </span>
                          )}
                        </div>
                        <div className="flex-1" />
                        {/* Mini profile pics */}
                        {visiblePics.length > 0 && (
                          <div className="mt-2 flex items-center">
                            <div className="flex -space-x-1.5">
                              {visiblePics.map((uid) => {
                                const p = profiles[uid];
                                return (
                                  <div
                                    key={uid}
                                    className="ring-2 ring-card rounded-full"
                                  >
                                    <Avatar
                                      url={p?.profile_image_url}
                                      name={p?.username ?? "?"}
                                      size={20}
                                    />
                                  </div>
                                );
                              })}
                            </div>
                            {overflowCount > 0 && (
                              <span className="ml-1 flex h-5 min-w-5 items-center justify-center rounded-full bg-secondary px-1 text-[10px] font-bold text-muted-foreground">
                                +{overflowCount}
                              </span>
                            )}
                          </div>
                        )}
                      </button>
                    );
                  })}
                </div>
              );
            })()
          )}
        </div>

        {/* Legend */}
        <div className="mt-3 flex flex-wrap items-center gap-3 px-1">
          {EVENT_TYPES.map((t) => (
            <span key={t} className="flex items-center gap-1.5 text-[11px] font-semibold text-muted-foreground">
              <span
                className="h-2 w-2 rounded-full"
                style={{ backgroundColor: EVENT_TYPE_COLORS[t] }}
              />
              {EVENT_TYPE_LABELS[t]}
            </span>
          ))}
        </div>

        {/* Selected date events */}
        {selectedDate && (
          <div className="mt-6 space-y-3">
            <h3 className="text-[14px] font-bold uppercase tracking-wider text-muted-foreground">
              {selectedDate.toLocaleDateString("en-US", {
                weekday: "long",
                month: "long",
                day: "numeric",
              })}
            </h3>
            {selectedEvents.length === 0 ? (
              <div className="rounded-2xl border border-border bg-card px-4 py-10 text-center">
                <p className="text-sm text-muted-foreground">
                  No events on this day.
                </p>
                <button
                  onClick={() => setShowCreate(true)}
                  className="mt-3 text-sm font-bold text-primary"
                >
                  + Add an event
                </button>
              </div>
            ) : (
              selectedEvents.map((event) => (
                <EventCard
                  key={event.id}
                  event={event}
                  dayLabel={selectedDate ? multiDayLabel(event, selectedDate) : null}
                  rsvps={rsvps[event.id] ?? []}
                  notes={notes[event.id] ?? []}
                  profiles={profiles}
                  meId={user?.id ?? ""}
                  meUsername={profile?.username ?? "you"}
                  hasConflict={conflictIds.has(event.id)}
                  onRSVP={(status) => rsvpMutation.mutate({ eventId: event.id, status })}
                  onDelete={
                    event.created_by === user?.id
                      ? () => deleteMutation.mutate(event)
                      : undefined
                  }
                />
              ))
            )}
          </div>
        )}
      </div>

      {showCreate && (
        <CreateEventSheet
          open={showCreate}
          onOpenChange={setShowCreate}
          defaultDate={selectedDate ?? new Date()}
        />
      )}
    </div>
  );
}

/** Get the role badge style for a profile. */
function RoleBadge({ profile }: { profile: WhisperProfile | null | undefined }) {
  const role = roleLabelFor(profile);
  if (!role) return null;
  return (
    <span
      className={cn(
        "rounded-full px-1.5 py-0.5 text-[10px] font-bold",
        ROLE_STYLES[role] ?? "bg-secondary text-muted-foreground"
      )}
    >
      {role}
    </span>
  );
}

function EventCard({
  event,
  dayLabel,
  rsvps,
  notes,
  profiles,
  meId,
  meUsername,
  hasConflict,
  onRSVP,
  onDelete,
}: {
  event: CalendarEvent;
  /** "Day 2 of 3" when a multi-day event is viewed on one of its days. */
  dayLabel?: string | null;
  rsvps: CalendarRSVP[];
  notes: CalendarNote[];
  profiles: Record<string, WhisperProfile>;
  meId: string;
  meUsername: string;
  hasConflict?: boolean;
  onRSVP: (status: "going" | "maybe" | "declined") => void;
  onDelete?: () => void;
}) {
  const [expanded, setExpanded] = useState<boolean>(false);
  const [noteText, setNoteText] = useState<string>("");
  const [recapText, setRecapText] = useState<string>("");
  const queryClient = useQueryClient();
  const myRSVP = rsvps.find((r) => r.user_id === meId);
  const goingCount = rsvps.filter((r) => r.status === "going").length;
  const color = EVENT_TYPE_COLORS[event.event_type];
  const ended = eventHasEnded(event);
  const recaps = notes.filter(isRecapNote);
  const regularNotes = notes.filter((n) => !isRecapNote(n));

  // Collect all participant IDs with their RSVP status for display
  const allParticipants = useMemo(() => {
    const map = new Map<string, { status: string; username: string | null }>();
    // Creator
    if (event.created_by) {
      map.set(event.created_by, { status: "creator", username: event.created_by_username });
    }
    // Tagged users
    for (let i = 0; i < event.tagged_user_ids.length; i++) {
      const uid = event.tagged_user_ids[i];
      if (!map.has(uid)) {
        map.set(uid, { status: "tagged", username: event.tagged_usernames[i] ?? null });
      }
    }
    // RSVP'd users
    for (const r of rsvps) {
      if (!map.has(r.user_id)) {
        map.set(r.user_id, { status: r.status, username: r.username });
      } else {
        // Update status if they RSVP'd
        map.set(r.user_id, { status: r.status, username: r.username ?? map.get(r.user_id)?.username ?? null });
      }
    }
    return Array.from(map.entries()).map(([uid, info]) => ({ uid, ...info }));
  }, [event, rsvps]);

  const addNoteMutation = useMutation({
    mutationFn: (body: string) => addNote(event.id, meId, meUsername, body),
    onSuccess: () => {
      setNoteText("");
      queryClient.invalidateQueries({ queryKey: ["calendar-notes"] });
    },
    onError: () => toast("Couldn't add note"),
  });

  const deleteNoteMutation = useMutation({
    mutationFn: (noteId: string) => deleteNote(noteId),
    onSuccess: () =>
      queryClient.invalidateQueries({ queryKey: ["calendar-notes"] }),
    onError: () => toast("Couldn't delete note"),
  });

  return (
    <div className="overflow-hidden rounded-2xl border border-border bg-card">
      <button
        onClick={() => setExpanded((v) => !v)}
        className="flex w-full items-start gap-3 p-4 text-left"
      >
        {/* Color bar */}
        <span
          className="mt-1 h-12 w-1.5 shrink-0 rounded-full"
          style={{ backgroundColor: color }}
        />
        <div className="min-w-0 flex-1">
          <p className="text-[16px] font-bold leading-tight">{event.title}</p>
          <div className="mt-1.5 flex flex-wrap items-center gap-2 text-[12px] text-muted-foreground">
            <span className="flex items-center gap-1">
              <Clock className="h-3 w-3" />
              {new Date(event.start_time).toLocaleTimeString("en-US", {
                hour: "numeric",
                minute: "2-digit",
              })}
              {event.end_time && eventDayKeys(event).length > 1 && (
                <>
                  {" – "}
                  {new Date(event.end_time).toLocaleDateString("en-US", { month: "short", day: "numeric" })}
                </>
              )}
            </span>
            {dayLabel && (
              <span className="rounded-full bg-foreground px-2 py-0.5 text-[10px] font-bold text-background">
                {dayLabel}
              </span>
            )}
            <span
              className="rounded-full px-2 py-0.5 text-[10px] font-bold"
              style={{ backgroundColor: `${color}22`, color }}
            >
              {EVENT_TYPE_LABELS[event.event_type]}
            </span>
            {event.recurrence && event.recurrence !== "none" && (
              <span className="flex items-center gap-1 rounded-full bg-secondary px-2 py-0.5 text-[10px] font-bold text-muted-foreground">
                <Repeat className="h-2.5 w-2.5" />
                {RECURRENCE_LABELS[event.recurrence]}
              </span>
            )}
            {hasConflict && (
              <span className="flex items-center gap-1 rounded-full bg-amber-500/15 px-2 py-0.5 text-[10px] font-bold text-amber-600">
                <AlertTriangle className="h-2.5 w-2.5" />
                Schedule conflict
              </span>
            )}
            {event.location && (
              <span className="flex items-center gap-1">
                <MapPin className="h-3 w-3" />
                {event.location}
              </span>
            )}
            {event.meeting_link && (
              <span className="flex items-center gap-1 text-primary">
                <Video className="h-3 w-3" />
                <span className="max-w-[120px] truncate">Online</span>
              </span>
            )}
          </div>

          {/* Participant avatars + roles (always visible) */}
          {allParticipants.length > 0 && (
            <div className="mt-2.5 flex items-center gap-2">
              <div className="flex -space-x-2">
                {allParticipants.slice(0, 5).map(({ uid, username }) => {
                  const p = profiles[uid];
                  return (
                    <div key={uid} className="ring-2 ring-card rounded-full">
                      <Avatar
                        url={p?.profile_image_url}
                        name={username ?? "?"}
                        size={26}
                      />
                    </div>
                  );
                })}
              </div>
              {allParticipants.length > 5 && (
                <span className="flex h-6 min-w-6 items-center justify-center rounded-full bg-secondary px-1.5 text-[10px] font-bold text-muted-foreground">
                  +{allParticipants.length - 5}
                </span>
              )}
              {goingCount > 0 && (
                <span className="text-[12px] font-bold text-emerald-600">
                  {goingCount} going
                </span>
              )}
            </div>
          )}
        </div>
        {onDelete && (
          <span
            role="button"
            tabIndex={0}
            onClick={(e) => {
              e.stopPropagation();
              onDelete();
            }}
            className="flex h-8 w-8 shrink-0 items-center justify-center rounded-full text-muted-foreground transition-colors hover:bg-destructive/10 hover:text-destructive"
          >
            <Trash2 className="h-4 w-4" />
          </span>
        )}
      </button>

      {expanded && (
        <div className="border-t border-border px-4 pb-4 pt-3 space-y-4">
          {event.description && (
            <p className="text-[14px] leading-snug text-foreground/90">
              {event.description}
            </p>
          )}
          {event.meeting_link && parseMeetingInvitation(event.meeting_link) ? (
            <a
              href={parseMeetingInvitation(event.meeting_link)?.href ?? event.meeting_link}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-3 rounded-2xl bg-[#c2e7ff] px-3.5 py-3 text-[#001d35] transition-colors hover:bg-[#b3ddf7] dark:bg-[#004a77] dark:text-[#c2e7ff] dark:hover:bg-[#065788]"
            >
              <span className="grid h-9 w-9 shrink-0 place-items-center rounded-full bg-white/70 dark:bg-white/10">
                <Video className="h-4 w-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-[13.5px] font-bold">Join with Whisper Meet</span>
                <span className="block truncate text-[11.5px] opacity-80">
                  {event.meeting_link.split("/").filter(Boolean).pop()}
                </span>
              </span>
              <ExternalLink className="h-3.5 w-3.5 shrink-0 opacity-70" />
            </a>
          ) : event.meeting_link ? (
            <a
              href={parseMeetingInvitation(event.meeting_link)?.href ?? event.meeting_link}
              target="_blank"
              rel="noopener noreferrer"
              className="flex items-center gap-2 rounded-xl border border-border bg-secondary/40 px-3 py-2.5 text-[13px] font-semibold text-primary transition-colors hover:bg-secondary"
            >
              <Video className="h-4 w-4 shrink-0" />
              <span className="min-w-0 flex-1 truncate">{event.meeting_link}</span>
              <ExternalLink className="h-3.5 w-3.5 shrink-0" />
            </a>
          ) : null}
          <a
            href={googleCalendarUrl(event)}
            target="_blank"
            rel="noopener noreferrer"
            className="flex items-center gap-2 rounded-xl border border-border bg-secondary/40 px-3 py-2.5 text-[13px] font-semibold text-foreground transition-colors hover:bg-secondary"
          >
            <CalendarPlus className="h-4 w-4 shrink-0" />
            <span className="min-w-0 flex-1">Add to Google Calendar</span>
            <ExternalLink className="h-3.5 w-3.5 shrink-0" />
          </a>
          <p className="text-[12px] text-muted-foreground">
            Created by @{event.created_by_username ?? "user"} · {timeAgo(event.created_at)}
          </p>

          {/* Participant list with roles */}
          {allParticipants.length > 0 && (
            <div className="space-y-2">
              <p className="text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                Who's involved
              </p>
              {allParticipants.map(({ uid, username, status }) => {
                const p = profiles[uid];
                return (
                  <div key={uid} className="flex items-center gap-2.5">
                    <Avatar
                      url={p?.profile_image_url}
                      name={username ?? "?"}
                      size={28}
                    />
                    <span className="min-w-0 flex-1 truncate text-[13px] font-semibold">
                      @{p?.username ?? username ?? "user"}
                    </span>
                    <RoleBadge profile={p} />
                    {status === "going" && (
                      <span className="rounded-full bg-emerald-500/15 px-1.5 py-0.5 text-[10px] font-bold text-emerald-600">
                        Going
                      </span>
                    )}
                    {status === "maybe" && (
                      <span className="rounded-full bg-amber-500/15 px-1.5 py-0.5 text-[10px] font-bold text-amber-600">
                        Maybe
                      </span>
                    )}
                    {status === "creator" && (
                      <span className="rounded-full bg-primary/10 px-1.5 py-0.5 text-[10px] font-bold text-primary">
                        Host
                      </span>
                    )}
                  </div>
                );
              })}
            </div>
          )}

          {/* RSVP buttons */}
          <div className="flex gap-2">
            {(["going", "maybe", "declined"] as const).map((status) => {
              const Icon = status === "going" ? Check : status === "maybe" ? HelpCircle : X;
              return (
                <button
                  key={status}
                  onClick={() => onRSVP(status)}
                  className={cn(
                    "flex items-center gap-1.5 rounded-xl px-3 py-2 text-[13px] font-semibold capitalize transition-colors",
                    myRSVP?.status === status
                      ? status === "going"
                        ? "bg-emerald-500 text-white"
                        : status === "maybe"
                          ? "bg-amber-500 text-white"
                          : "bg-destructive text-destructive-foreground"
                      : "border border-border hover:bg-secondary"
                  )}
                >
                  <Icon className="h-3.5 w-3.5" />
                  {status}
                </button>
              );
            })}
          </div>

          {/* Post-event recap — lightweight content log */}
          {ended && (
            <div className="space-y-2 rounded-xl border border-dashed border-border bg-secondary/30 p-3">
              <p className="flex items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                <Camera className="h-3.5 w-3.5" />
                Event recap
              </p>
              {recaps.length > 0 && (
                <div className="space-y-1.5">
                  {recaps.map((note) => {
                    const np = profiles[note.user_id];
                    return (
                      <div key={note.id} className="flex items-start gap-2.5">
                        <Avatar
                          url={np?.profile_image_url}
                          name={note.username ?? "?"}
                          size={22}
                        />
                        <div className="min-w-0 flex-1">
                          <span className="text-[12px] font-bold">
                            @{np?.username ?? note.username ?? "user"}
                          </span>
                          <p className="text-[13px] leading-snug text-foreground/90">
                            {recapBody(note)}
                          </p>
                        </div>
                      </div>
                    );
                  })}
                </div>
              )}
              <div className="flex items-center gap-2">
                <input
                  value={recapText}
                  onChange={(e) => setRecapText(e.target.value)}
                  onKeyDown={(e) => {
                    if (e.key === "Enter" && recapText.trim()) {
                      e.preventDefault();
                      void addRecap(event.id, meId, meUsername, recapText.trim()).then(() => {
                        setRecapText("");
                        queryClient.invalidateQueries({ queryKey: ["calendar-notes"] });
                      });
                    }
                  }}
                  placeholder="How did it go? Drop a quick recap…"
                  className="min-w-0 flex-1 rounded-xl border border-border bg-background px-3 py-2 text-[13px] outline-none placeholder:text-muted-foreground/60 focus:border-foreground/40"
                />
                <button
                  onClick={() => {
                    if (!recapText.trim()) return;
                    void addRecap(event.id, meId, meUsername, recapText.trim()).then(() => {
                      setRecapText("");
                      queryClient.invalidateQueries({ queryKey: ["calendar-notes"] });
                    });
                  }}
                  disabled={!recapText.trim()}
                  className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground transition-transform active:scale-90 disabled:opacity-40"
                  aria-label="Post recap"
                >
                  <Send className="h-4 w-4" />
                </button>
              </div>
            </div>
          )}

          {/* Mini notes section */}
          <div className="space-y-2">
            <p className="flex items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
              <StickyNote className="h-3.5 w-3.5" />
              Notes
            </p>
            {regularNotes.length > 0 && (
              <div className="space-y-1.5">
                {regularNotes.map((note) => {
                  const np = profiles[note.user_id];
                  return (
                    <div
                      key={note.id}
                      className="flex items-start gap-2.5 rounded-xl bg-secondary/50 px-3 py-2.5"
                    >
                      <Avatar
                        url={np?.profile_image_url}
                        name={note.username ?? "?"}
                        size={24}
                      />
                      <div className="min-w-0 flex-1">
                        <div className="flex items-center gap-1.5">
                          <span className="truncate text-[12px] font-bold">
                            @{np?.username ?? note.username ?? "user"}
                          </span>
                          <RoleBadge profile={np} />
                        </div>
                        <p className="mt-0.5 text-[13px] leading-snug text-foreground/90">
                          {note.body}
                        </p>
                        <p className="mt-0.5 text-[10px] text-muted-foreground">
                          {timeAgo(note.created_at)}
                        </p>
                      </div>
                      {note.user_id === meId && (
                        <button
                          onClick={() => deleteNoteMutation.mutate(note.id)}
                          className="shrink-0 text-muted-foreground transition-colors hover:text-destructive"
                          aria-label="Delete note"
                        >
                          <Trash2 className="h-3.5 w-3.5" />
                        </button>
                      )}
                    </div>
                  );
                })}
              </div>
            )}
            {/* Add note input */}
            <div className="flex items-center gap-2">
              <input
                value={noteText}
                onChange={(e) => setNoteText(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && noteText.trim()) {
                    e.preventDefault();
                    addNoteMutation.mutate(noteText.trim());
                  }
                }}
                placeholder="Leave a quick note…"
                className="min-w-0 flex-1 rounded-xl border border-border bg-background px-3 py-2 text-[13px] outline-none placeholder:text-muted-foreground/60 focus:border-foreground/40"
              />
              <button
                onClick={() => {
                  if (noteText.trim()) addNoteMutation.mutate(noteText.trim());
                }}
                disabled={!noteText.trim() || addNoteMutation.isPending}
                className="flex h-9 w-9 shrink-0 items-center justify-center rounded-xl bg-primary text-primary-foreground transition-transform active:scale-90 disabled:opacity-40"
                aria-label="Send note"
              >
                <Send className="h-4 w-4" />
              </button>
            </div>
          </div>
        </div>
      )}
    </div>
  );
}

function CreateEventSheet({
  open,
  onOpenChange,
  defaultDate,
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  defaultDate: Date;
}) {
  const { user, profile } = useAuth();
  const queryClient = useQueryClient();
  const [title, setTitle] = useState<string>("");
  const [description, setDescription] = useState<string>("");
  const [eventType, setEventType] = useState<CalendarEventType>("meet");
  const [date, setDate] = useState<string>(
    defaultDate.toISOString().slice(0, 10)
  );
  const [time, setTime] = useState<string>("12:00");
  /** Multi-day events: an end DATE later than the start date. Empty = same day. */
  const [endDate, setEndDate] = useState<string>("");
  const [endTime, setEndTime] = useState<string>("");
  const [location, setLocation] = useState<string>("");
  const [meetingLink, setMeetingLink] = useState<string>("");
  const [generatingMeet, setGeneratingMeet] = useState<boolean>(false);
  const [recurrence, setRecurrence] = useState<CalendarRecurrence>("none");
  /** Email guests — the Calendar-grade invite (Join button, .ics) for Whisper Meet links. */
  const [emailGuests, setEmailGuests] = useState<string[]>([]);
  const [emailDraft, setEmailDraft] = useState<string>("");
  const isWhisperMeetLink = /mydailywhisper\.com\//i.test(meetingLink.trim());
  const commitEmailDraft = (): void => {
    const parsed = parseEmailList(emailDraft);
    if (parsed.length === 0) return;
    setEmailGuests((prev) => Array.from(new Set([...prev, ...parsed])));
    setEmailDraft("");
  };

  /** Creates a scheduled Whisper Meeting and fills the link field with it. */
  const generateWhisperMeeting = async (): Promise<void> => {
    if (!user) return;
    setGeneratingMeet(true);
    try {
      const { createMeeting, meetingLink: linkFor } = await import("@/lib/meetings");
      const scheduledAt = new Date(`${date}T${time}`).toISOString();
      const meeting = await createMeeting({
        hostId: user.id,
        hostUsername: profile?.username ?? "host",
        title: title.trim() || "Meeting",
        scheduledAt,
      });
      setMeetingLink(linkFor(meeting.id));
      toast("Whisper Meeting created — link added");
    } catch (err) {
      console.error("[Calendar] generateWhisperMeeting failed:", err);
      // Supabase errors are plain objects (not Error instances) — extract
      // .message and .code directly instead of String() which gives
      // '[object Object]'.
      const raw = err instanceof Error
        ? err.message
        : (err as { message?: string })?.message ?? JSON.stringify(err);
      const msg = raw.toLowerCase();
      const code = (err as { code?: string })?.code;
      const isMissingTable = code === "42P01" ||
        (/does not exist|relation .* does not exist/.test(msg) && !msg.includes("constraint"));
      toast(
        code === "42501" ||
          msg.includes("policy") ||
          msg.includes("permission") ||
          msg.includes("rls")
          ? "Meeting tables not ready — apply supabase/meetings.sql in the Supabase dashboard."
          : isMissingTable
            ? "Meeting tables are missing — apply supabase/meetings.sql in the Supabase dashboard."
            : msg.includes("jwt") || msg.includes("auth")
              ? "Sign in to create a meeting."
              : `Couldn't create the meeting: ${raw}`
      );
    } finally {
      setGeneratingMeet(false);
    }
  };
  const [tagQuery, setTagQuery] = useState<string>("");
  const [tagged, setTagged] = useState<WhisperProfile[]>([]);

  const tagResults = useQuery({
    queryKey: ["tag-search", tagQuery],
    queryFn: () => searchProfiles(tagQuery),
    enabled: tagQuery.trim().length >= 1,
  });

  /** Default end = one hour after the start time, on the same day. */
  const defaultEndTime = useMemo(() => {
    const [h, m] = time.split(":").map((n) => Number(n));
    if (Number.isNaN(h) || Number.isNaN(m)) return "13:00";
    const t = new Date(2000, 0, 1, h, m);
    t.setHours(t.getHours() + 1);
    return `${String(t.getHours()).padStart(2, "0")}:${String(t.getMinutes()).padStart(2, "0")}`;
  }, [time]);
  const effectiveEndDate = endDate || date;
  const effectiveEndTime = endTime || defaultEndTime;
  const spanDays = useMemo(() => {
    const a = new Date(`${date}T00:00`);
    const b = new Date(`${effectiveEndDate}T00:00`);
    if (Number.isNaN(a.getTime()) || Number.isNaN(b.getTime())) return 1;
    return Math.max(1, Math.round((b.getTime() - a.getTime()) / 86_400_000) + 1);
  }, [date, effectiveEndDate]);
  /** ISO end, or undefined when it doesn't land after the start. */
  const resolvedEndIso = (startIso: string): string | undefined => {
    const end = new Date(`${effectiveEndDate}T${effectiveEndTime}`);
    if (Number.isNaN(end.getTime())) return undefined;
    return end.getTime() > new Date(startIso).getTime() ? end.toISOString() : undefined;
  };

  const createMutation = useMutation({
    mutationFn: async (): Promise<{ emailed: number; emailProblem: string | null }> => {
      const startTime = new Date(`${date}T${time}`).toISOString();
      const endIso = resolvedEndIso(startTime);
      const created = await createCalendarEvent({
        createdBy: user!.id,
        createdByUsername: profile?.username ?? "you",
        title: title.trim(),
        description: description.trim() || undefined,
        eventType,
        startTime,
        endTime: endIso,
        location: location.trim() || undefined,
        meetingLink: parseMeetingInvitation(meetingLink.trim())?.href ?? (meetingLink.trim() || undefined),
        taggedUserIds: tagged.map((t) => t.user_id),
        taggedUsernames: tagged.map((t) => t.username),
        recurrence,
      });
      // DM every tagged user a team-message invite from the organizer.
      if (created && tagged.length > 0) {
        await sendCalendarTeamDMs(
          created,
          { id: user!.id, username: profile?.username ?? "you" },
          "invite"
        );
      }
      // Email guests get the formatted invite with the .ics — Whisper Meet links only.
      const allEmails = Array.from(new Set([...emailGuests, ...parseEmailList(emailDraft)]));
      let emailed = 0;
      let emailProblem: string | null = null;
      if (created && allEmails.length > 0 && isWhisperMeetLink) {
        const start = new Date(startTime);
        const result = await sendMeetingInviteEmails({
          emails: allEmails,
          title: title.trim() || "Meeting",
          link: meetingLink.trim(),
          hostUsername: profile?.username ?? "you",
          startsAt: start.toISOString(),
          endsAt: endIso ?? new Date(start.getTime() + 60 * 60_000).toISOString(),
          description: description.trim() || null,
          recurrenceLabel: recurrence !== "none" ? RECURRENCE_LABELS[recurrence] : null,
        }).catch(() => ({ ok: false, sent: 0, error: "network" }));
        emailed = result.sent;
        if (!result.ok) emailProblem = result.error ?? "send_failed";
      }
      return { emailed, emailProblem };
    },
    onSuccess: ({ emailed, emailProblem }) => {
      const parts: string[] = ["Event created"];
      if (tagged.length > 0) parts.push("invites sent by DM");
      if (emailed > 0) parts.push(`${emailed} emailed`);
      toast(parts.join(" — "));
      if (emailProblem) {
        toast(
          emailProblem === "not_configured"
            ? "Email invites aren't set up on this deployment yet — share the link instead."
            : "The email invites didn't go out — share the link from the event instead."
        );
      }
      queryClient.invalidateQueries({ queryKey: ["calendar-events"] });
      onOpenChange(false);
    },
    onError: (err) =>
      toast(err instanceof Error ? err.message : "Couldn't create event"),
  });

  const addTag = (p: WhisperProfile): void => {
    if (!tagged.some((t) => t.user_id === p.user_id)) {
      setTagged((prev) => [...prev, p]);
    }
    setTagQuery("");
  };

  const removeTag = (id: string): void => {
    setTagged((prev) => prev.filter((t) => t.user_id !== id));
  };

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-background">
      <div className="flex h-full w-full flex-col bg-background">
        {/* Header */}
        <div className="sticky top-0 z-10 flex items-center justify-between border-b border-border bg-background px-4 py-3.5">
          <button
            onClick={() => onOpenChange(false)}
            className="flex h-9 w-9 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          >
            <X className="h-5 w-5" />
          </button>
          <h2 className="font-display text-[17px] font-bold">New event</h2>
          <span className="w-9" />
        </div>

        {/* Body */}
        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto px-5 py-5">
          <input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder="Event title"
            autoFocus
            className="w-full border-b border-border bg-transparent pb-2 text-[20px] font-bold outline-none placeholder:text-muted-foreground"
          />

          <div>
            <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
              Type
            </p>
            <div className="flex flex-wrap gap-2">
              {EVENT_TYPES.map((t) => (
                <button
                  key={t}
                  onClick={() => setEventType(t)}
                  className={cn(
                    "rounded-full px-3.5 py-1.5 text-[13px] font-semibold transition-all active:scale-95",
                    eventType === t
                      ? "text-white"
                      : "border border-border hover:bg-secondary"
                  )}
                  style={eventType === t ? { backgroundColor: EVENT_TYPE_COLORS[t] } : {}}
                >
                  {EVENT_TYPE_LABELS[t]}
                </button>
              ))}
            </div>
          </div>

          <div className="grid grid-cols-2 gap-3">
            <div>
              <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                Date
              </p>
              <input
                type="date"
                value={date}
                onChange={(e) => setDate(e.target.value)}
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
            </div>
            <div>
              <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                Time
              </p>
              <input
                type="time"
                value={time}
                onChange={(e) => setTime(e.target.value)}
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
            </div>
          </div>

          {/* Ends — pick a later date for a multi-day event. */}
          <div>
            <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
              Ends
            </p>
            <div className="grid grid-cols-2 gap-3">
              <input
                type="date"
                value={effectiveEndDate}
                min={date}
                onChange={(e) => setEndDate(e.target.value)}
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
              <input
                type="time"
                value={effectiveEndTime}
                onChange={(e) => setEndTime(e.target.value)}
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
            </div>
            <p className="mt-1.5 text-[12px] text-muted-foreground">
              {spanDays > 1
                ? `Multi-day · ${spanDays} days — it shows on every day it covers.`
                : "Pick a later date to make this a multi-day event."}
            </p>
          </div>

          <div>
            <p className="mb-2 flex items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
              <Repeat className="h-3.5 w-3.5" />
              Repeats
            </p>
            <div className="flex flex-wrap gap-2">
              {(Object.keys(RECURRENCE_LABELS) as CalendarRecurrence[]).map((r) => (
                <button
                  key={r}
                  onClick={() => setRecurrence(r)}
                  className={cn(
                    "rounded-full px-3.5 py-1.5 text-[13px] font-semibold transition-all active:scale-95",
                    recurrence === r
                      ? "bg-foreground text-background"
                      : "border border-border hover:bg-secondary"
                  )}
                >
                  {RECURRENCE_LABELS[r]}
                </button>
              ))}
            </div>
            {recurrence !== "none" && (
              <p className="mt-1.5 text-[11px] text-muted-foreground">
                Creates the next 8 occurrences on the shared calendar.
              </p>
            )}
          </div>

          <div>
            <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
              Location (optional)
            </p>
            <input
              value={location}
              onChange={(e) => setLocation(e.target.value)}
              placeholder="e.g. Gold's Gym, Venice Beach"
              className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
            />
          </div>

          <div>
            <p className="mb-2 flex items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
              <Video className="h-3.5 w-3.5" />
              Meeting link (optional)
            </p>
            <div className="flex gap-2">
              <input
                value={meetingLink}
                onChange={(e) => setMeetingLink(e.target.value)}
                placeholder="https://meet.google.com/…"
                className="min-w-0 flex-1 rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
              <button
                type="button"
                disabled={generatingMeet}
                onClick={() => void generateWhisperMeeting()}
                className="shrink-0 rounded-xl bg-foreground px-3.5 py-2.5 text-[12.5px] font-bold text-background transition-all active:scale-95 disabled:opacity-50"
              >
                {generatingMeet ? "Creating…" : "+ Whisper Meet"}
              </button>
            </div>
            <p className="mt-1 text-[11px] text-muted-foreground">
              “Whisper Meet” creates an in-app video meeting with AI notes —
              everyone tagged can join right inside Whisper.
            </p>
          </div>

          {isWhisperMeetLink && (
            <div>
              <p className="mb-2 flex items-center gap-1.5 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
                <Mail className="h-3.5 w-3.5" />
                Invite by email (optional)
              </p>
              {emailGuests.length > 0 && (
                <div className="mb-2 flex flex-wrap gap-1.5">
                  {emailGuests.map((e) => (
                    <span key={e} className="flex items-center gap-1.5 rounded-full bg-secondary py-1 pl-2.5 pr-2 text-[12.5px] font-semibold">
                      {e}
                      <button
                        type="button"
                        onClick={() => setEmailGuests((prev) => prev.filter((x) => x !== e))}
                        aria-label={`Remove ${e}`}
                        className="grid h-4 w-4 place-items-center rounded-full hover:bg-black/10"
                      >
                        <X className="h-3 w-3" />
                      </button>
                    </span>
                  ))}
                </div>
              )}
              <input
                value={emailDraft}
                onChange={(e) => setEmailDraft(e.target.value)}
                onKeyDown={(e) => {
                  if ((e.key === "Enter" || e.key === "," || e.key === " ") && (isLikelyEmail(emailDraft.trim()) || emailDraft.includes(","))) {
                    e.preventDefault();
                    commitEmailDraft();
                  } else if (e.key === "Backspace" && !emailDraft && emailGuests.length > 0) {
                    setEmailGuests((prev) => prev.slice(0, -1));
                  }
                }}
                onBlur={commitEmailDraft}
                onPaste={(e) => {
                  const parsed = parseEmailList(e.clipboardData.getData("text"));
                  if (parsed.length > 1) {
                    e.preventDefault();
                    setEmailGuests((prev) => Array.from(new Set([...prev, ...parsed])));
                  }
                }}
                type="email"
                inputMode="email"
                autoComplete="off"
                placeholder="name@company.com — press Enter after each"
                className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
              />
              <p className="mt-1 text-[11px] text-muted-foreground">
                A formatted invite with the time, a Join button, the joining info, an
                Add-to-Google-Calendar link, and a calendar file (.ics).
              </p>
            </div>
          )}

          <div>
            <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
              Description (optional)
            </p>
            <textarea
              value={description}
              onChange={(e) => setDescription(e.target.value)}
              rows={3}
              placeholder="What's this about?"
              className="w-full resize-none rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
            />
          </div>

          {/* Tag users */}
          <div>
            <p className="mb-2 text-[12px] font-bold uppercase tracking-wider text-muted-foreground">
              Tag people
            </p>
            {tagged.length > 0 && (
              <div className="mb-2 flex flex-wrap gap-1.5">
                {tagged.map((t) => (
                  <span
                    key={t.user_id}
                    className="flex items-center gap-1.5 rounded-full bg-secondary px-2.5 py-1 text-[13px] font-semibold"
                  >
                    @{t.username}
                    <button
                      onClick={() => removeTag(t.user_id)}
                      className="text-muted-foreground hover:text-foreground"
                    >
                      <X className="h-3 w-3" />
                    </button>
                  </span>
                ))}
              </div>
            )}
            <input
              value={tagQuery}
              onChange={(e) => setTagQuery(e.target.value)}
              placeholder="Search by username…"
              className="w-full rounded-xl border border-border bg-card px-3 py-2.5 text-sm outline-none focus:border-foreground/40"
            />
            {tagResults.data && tagResults.data.length > 0 && (
              <div className="mt-1.5 divide-y divide-border rounded-xl border border-border bg-card overflow-hidden">
                {tagResults.data.slice(0, 5).map((p) => (
                  <button
                    key={p.user_id}
                    onClick={() => addTag(p)}
                    className="flex w-full items-center gap-2.5 px-3 py-2 text-left transition-colors hover:bg-secondary/50"
                  >
                    <Avatar url={p.profile_image_url} name={p.username} size={28} />
                    <span className="truncate text-sm font-semibold">@{p.username}</span>
                  </button>
                ))}
              </div>
            )}
          </div>
        </div>

        {/* Footer */}
        <div className="sticky bottom-0 border-t border-border bg-background px-5 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <button
            onClick={() => createMutation.mutate()}
            disabled={!title.trim() || createMutation.isPending}
            className="w-full rounded-full bg-foreground py-3.5 text-[15px] font-bold text-background transition-all active:scale-[0.98] disabled:opacity-50"
          >
            {createMutation.isPending ? "Creating…" : "Create event"}
          </button>
        </div>
      </div>
    </div>
  );
}
