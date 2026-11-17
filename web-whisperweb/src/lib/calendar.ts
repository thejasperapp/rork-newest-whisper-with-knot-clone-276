import { supabase } from "@/lib/supabase";
import type { WhisperProfile } from "@/lib/types";
import { fetchProfilesByIds, sendMessage } from "@/lib/api";

export type CalendarEventType =
  | "meet"
  | "content_collab"
  | "training"
  | "event"
  | "deadline"
  | "other";

export interface CalendarEvent {
  id: string;
  created_by: string;
  created_by_username: string | null;
  title: string;
  description: string | null;
  event_type: CalendarEventType;
  start_time: string;
  end_time: string | null;
  location: string | null;
  meeting_link: string | null;
  tagged_user_ids: string[];
  tagged_usernames: string[];
  recurrence?: CalendarRecurrence | null;
  recurrence_group?: string | null;
  created_at: string | null;
}

export type CalendarRecurrence = "none" | "weekly" | "biweekly" | "monthly";

export const RECURRENCE_LABELS: Record<CalendarRecurrence, string> = {
  none: "Doesn't repeat",
  weekly: "Every week",
  biweekly: "Every 2 weeks",
  monthly: "Every month",
};

/** Number of materialized occurrences created for a recurring event. */
const RECURRENCE_INSTANCES = 8;

export interface CalendarRSVP {
  id: string;
  event_id: string;
  user_id: string;
  username: string | null;
  status: "going" | "maybe" | "declined";
  created_at: string | null;
}

export interface CalendarNote {
  id: string;
  event_id: string;
  user_id: string;
  username: string | null;
  body: string;
  created_at: string | null;
}

export const EVENT_TYPE_LABELS: Record<CalendarEventType, string> = {
  meet: "Meet up",
  content_collab: "Content collab",
  training: "Training",
  event: "Event",
  deadline: "Deadline",
  other: "Other",
};

export const EVENT_TYPE_COLORS: Record<CalendarEventType, string> = {
  meet: "#3b82f6",
  content_collab: "#a855f7",
  training: "#22c55e",
  event: "#f59e0b",
  deadline: "#ef4444",
  other: "#6b7280",
};

/** Fetch all calendar events, optionally filtered by month. */
export async function fetchCalendarEvents(
  monthStart?: string,
  monthEnd?: string
): Promise<CalendarEvent[]> {
  let query = supabase
    .from("whisper_calendar_events")
    .select("*")
    .order("start_time", { ascending: true });
  if (monthStart && monthEnd) {
    query = query
      .gte("start_time", monthStart)
      .lt("start_time", monthEnd);
  }
  const { data } = await query;
  return (data as CalendarEvent[] | null) ?? [];
}

/** Advance a date by one recurrence step. */
function nextOccurrence(date: Date, recurrence: CalendarRecurrence): Date {
  const d = new Date(date);
  if (recurrence === "weekly") d.setDate(d.getDate() + 7);
  else if (recurrence === "biweekly") d.setDate(d.getDate() + 14);
  else if (recurrence === "monthly") d.setMonth(d.getMonth() + 1);
  return d;
}

/**
 * Create a new calendar event. Recurring events are materialized as real
 * rows (up to 8 occurrences) sharing a recurrence_group so every client
 * sees them without expansion logic. Returns the first created event.
 */
export async function createCalendarEvent(input: {
  createdBy: string;
  createdByUsername: string;
  title: string;
  description?: string;
  eventType: CalendarEventType;
  startTime: string;
  endTime?: string;
  location?: string;
  meetingLink?: string;
  taggedUserIds?: string[];
  taggedUsernames?: string[];
  recurrence?: CalendarRecurrence;
}): Promise<CalendarEvent | null> {
  const recurrence: CalendarRecurrence = input.recurrence ?? "none";
  const group = recurrence !== "none" ? crypto.randomUUID() : null;
  const count = recurrence !== "none" ? RECURRENCE_INSTANCES : 1;

  let start = new Date(input.startTime);
  let firstCreated: CalendarEvent | null = null;
  let includeRecurrence = recurrence !== "none";

  for (let i = 0; i < count; i++) {
    const payload: Record<string, unknown> = {
      created_by: input.createdBy,
      created_by_username: input.createdByUsername,
      title: input.title,
      description: input.description ?? null,
      event_type: input.eventType,
      start_time: start.toISOString(),
      end_time: input.endTime ?? null,
      location: input.location ?? null,
      tagged_user_ids: input.taggedUserIds ?? [],
      tagged_usernames: input.taggedUsernames ?? [],
    };
    // Only include optional columns when set — they may not exist yet if
    // the migration hasn't been run.
    if (input.meetingLink) {
      payload.meeting_link = input.meetingLink;
    }
    if (includeRecurrence) {
      payload.recurrence = recurrence;
      payload.recurrence_group = group;
    }
    let { data, error } = await supabase
      .from("whisper_calendar_events")
      .insert(payload)
      .select("*")
      .maybeSingle();
    // Older schema without recurrence columns: retry without them and stop
    // materializing extra occurrences.
    if (error && /recurrence/i.test(error.message)) {
      delete payload.recurrence;
      delete payload.recurrence_group;
      includeRecurrence = false;
      ({ data, error } = await supabase
        .from("whisper_calendar_events")
        .insert(payload)
        .select("*")
        .maybeSingle());
    }
    if (error) {
      if (firstCreated) return firstCreated; // partial series is fine
      throw error;
    }
    if (!firstCreated) firstCreated = (data as CalendarEvent | null) ?? null;
    if (!includeRecurrence && recurrence !== "none") break;
    start = nextOccurrence(start, recurrence);
  }
  return firstCreated;
}

// ---------------------------------------------------------------------------
// Team-message DMs — invite / update / cancel notices from the organizer
// ---------------------------------------------------------------------------

/** Wire prefix shared with the iOS `WhisperCalendarEmbed`. */
export const CALENDAR_EMBED_PREFIX = "::whisper-calendar-v1::";

export interface CalendarEmbedPayload {
  id: string;
  eventID: string;
  title: string;
  eventType: string;
  startTime: string;
  location?: string | null;
  meetingLink?: string | null;
  createdByUsername: string;
  taggedUsernames: string[];
  /** "invite" | "update" | "cancelled" — optional so old clients still decode */
  kind?: string;
}

export function encodeCalendarEmbed(p: CalendarEmbedPayload): string {
  return CALENDAR_EMBED_PREFIX + JSON.stringify(p);
}

export function decodeCalendarEmbed(
  body: string | null | undefined
): CalendarEmbedPayload | null {
  const t = (body ?? "").trim();
  if (!t.startsWith(CALENDAR_EMBED_PREFIX)) return null;
  try {
    if (t.length > 32_768) return null;
    const p: unknown = JSON.parse(t.slice(CALENDAR_EMBED_PREFIX.length));
    if (!p || typeof p !== "object" || Array.isArray(p)) return null;
    const value = p as Record<string, unknown>;
    if (typeof value.eventID !== "string" || !/^[a-f0-9]{8}(-[a-f0-9]{4}){3}-[a-f0-9]{12}$/i.test(value.eventID)) return null;
    if (value.kind !== "chat-meet" && typeof value.title !== "string") return null;
    return {
      id: typeof value.id === "string" ? value.id : value.eventID,
      eventID: value.eventID,
      title: typeof value.title === "string" ? value.title : "Meet invitation",
      eventType: typeof value.eventType === "string" ? value.eventType : "meeting",
      startTime: typeof value.startTime === "string" ? value.startTime : "",
      createdByUsername: typeof value.createdByUsername === "string" ? value.createdByUsername : "organizer",
      taggedUsernames: Array.isArray(value.taggedUsernames) ? value.taggedUsernames.filter((name): name is string => typeof name === "string") : [],
      location: typeof value.location === "string" ? value.location : null,
      meetingLink: typeof value.meetingLink === "string" ? value.meetingLink : null,
      kind: typeof value.kind === "string" ? value.kind : undefined,
    };
  } catch {
    return null;
  }
}

/**
 * DM every tagged user a team-message calendar card from the organizer.
 * Used on create ("invite"), edit ("update"), and delete ("cancelled").
 */
export async function sendCalendarTeamDMs(
  event: CalendarEvent,
  organizer: { id: string; username: string },
  kind: "invite" | "update" | "cancelled"
): Promise<void> {
  const payload: CalendarEmbedPayload = {
    id: crypto.randomUUID(),
    eventID: event.id,
    title: event.title,
    eventType: event.event_type,
    startTime: event.start_time,
    location: event.location,
    meetingLink: event.meeting_link,
    createdByUsername: organizer.username,
    taggedUsernames: event.tagged_usernames ?? [],
    kind,
  };
  const body = encodeCalendarEmbed(payload);
  const ids = event.tagged_user_ids ?? [];
  const names = event.tagged_usernames ?? [];
  await Promise.all(
    ids.map((uid, i) => {
      if (uid.toLowerCase() === organizer.id.toLowerCase()) return Promise.resolve();
      return sendMessage(
        organizer.id,
        organizer.username,
        uid,
        names[i] ?? "user",
        body
      ).catch((e) => console.error("calendar team DM failed:", e));
    })
  );
}

/** Update an existing event. */
export async function updateCalendarEvent(
  eventId: string,
  updates: Partial<Pick<CalendarEvent, "title" | "description" | "event_type" | "start_time" | "end_time" | "location" | "meeting_link" | "tagged_user_ids" | "tagged_usernames">>
): Promise<void> {
  // Strip meeting_link from the update if it's null/undefined and the
  // column may not exist yet — only send it when there's a real value.
  const safeUpdates: Record<string, unknown> = { ...updates };
  if ("meeting_link" in safeUpdates && !safeUpdates.meeting_link) {
    delete safeUpdates.meeting_link;
  }
  const { error } = await supabase
    .from("whisper_calendar_events")
    .update(safeUpdates)
    .eq("id", eventId);
  if (error) throw error;
}

/** Delete an event. */
export async function deleteCalendarEvent(eventId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_calendar_events")
    .delete()
    .eq("id", eventId);
  if (error) throw error;
}

// ---------------------------------------------------------------------------
// Conflict detection — same person tagged on two overlapping events
// ---------------------------------------------------------------------------

/** Assumed duration when an event has no end time. */
const DEFAULT_DURATION_MS = 60 * 60 * 1000;

function eventWindow(e: CalendarEvent): { start: number; end: number } {
  const start = new Date(e.start_time).getTime();
  const end = e.end_time ? new Date(e.end_time).getTime() : start + DEFAULT_DURATION_MS;
  return { start, end };
}

function eventPeople(e: CalendarEvent): Set<string> {
  const s = new Set<string>([e.created_by]);
  for (const uid of e.tagged_user_ids ?? []) s.add(uid);
  return s;
}

/** Local calendar-day key (year-month-day, month 0-based) — the page grids' key. */
export function dayKey(d: Date): string {
  return `${d.getFullYear()}-${d.getMonth()}-${d.getDate()}`;
}

/**
 * Every local day an event touches, start → end (inclusive). A single-day
 * event yields one key; a MULTI-DAY event (end_time on a later day) yields
 * one per day so it lands on every day it covers. An end exactly at
 * midnight belongs to the previous day. Capped at 60 days as a sanity guard.
 */
export function eventDayKeys(e: CalendarEvent): string[] {
  const start = new Date(e.start_time);
  if (Number.isNaN(start.getTime())) return [];
  const keys: string[] = [dayKey(start)];
  const end = e.end_time ? new Date(e.end_time) : null;
  if (!end || Number.isNaN(end.getTime()) || end <= start) return keys;
  const cursor = new Date(start.getFullYear(), start.getMonth(), start.getDate());
  const last = new Date(end.getFullYear(), end.getMonth(), end.getDate());
  if (end.getHours() === 0 && end.getMinutes() === 0 && last > cursor) {
    last.setDate(last.getDate() - 1);
  }
  let guard = 0;
  while (cursor < last && guard++ < 60) {
    cursor.setDate(cursor.getDate() + 1);
    keys.push(dayKey(cursor));
  }
  return keys;
}

/** True when the event spans more than one local day. */
export function isMultiDay(e: CalendarEvent): boolean {
  return eventDayKeys(e).length > 1;
}

/** "Day 2 of 3" for a multi-day event viewed on `date`; null otherwise. */
export function multiDayLabel(e: CalendarEvent, date: Date): string | null {
  const keys = eventDayKeys(e);
  if (keys.length <= 1) return null;
  const idx = keys.indexOf(dayKey(date));
  if (idx < 0) return null;
  return `Day ${idx + 1} of ${keys.length}`;
}

/**
 * Returns the set of event IDs that conflict — two events overlap in time
 * AND share at least one participant (organizer or tagged user).
 */
export function detectConflicts(events: CalendarEvent[]): Set<string> {
  const conflicts = new Set<string>();
  for (let i = 0; i < events.length; i++) {
    const a = events[i];
    const wa = eventWindow(a);
    const pa = eventPeople(a);
    for (let j = i + 1; j < events.length; j++) {
      const b = events[j];
      const wb = eventWindow(b);
      if (wa.start >= wb.end || wb.start >= wa.end) continue;
      const pb = eventPeople(b);
      let shared = false;
      for (const uid of pa) {
        if (pb.has(uid)) {
          shared = true;
          break;
        }
      }
      if (shared) {
        conflicts.add(a.id);
        conflicts.add(b.id);
      }
    }
  }
  return conflicts;
}

// ---------------------------------------------------------------------------
// .ics export — download the team calendar for Google / Apple Calendar
// ---------------------------------------------------------------------------

function icsDate(iso: string): string {
  return new Date(iso).toISOString().replace(/[-:]/g, "").replace(/\.\d{3}/, "");
}

function icsEscape(s: string): string {
  return s.replace(/\\/g, "\\\\").replace(/;/g, "\\;").replace(/,/g, "\\,").replace(/\n/g, "\\n");
}

/** Build an RFC 5545 .ics document from a set of events. */
export function buildICS(events: CalendarEvent[]): string {
  const lines: string[] = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Whisper//Team Calendar//EN",
    "CALSCALE:GREGORIAN",
    "X-WR-CALNAME:Whisper Team Calendar",
  ];
  for (const e of events) {
    const start = icsDate(e.start_time);
    const end = e.end_time
      ? icsDate(e.end_time)
      : icsDate(new Date(new Date(e.start_time).getTime() + DEFAULT_DURATION_MS).toISOString());
    lines.push("BEGIN:VEVENT");
    lines.push(`UID:${e.id}@whisper`);
    lines.push(`DTSTAMP:${icsDate(e.created_at ?? e.start_time)}`);
    lines.push(`DTSTART:${start}`);
    lines.push(`DTEND:${end}`);
    lines.push(`SUMMARY:${icsEscape(e.title)}`);
    const descParts: string[] = [];
    if (e.description) descParts.push(e.description);
    if (e.meeting_link) descParts.push(`Join: ${e.meeting_link}`);
    descParts.push(`Organized by @${e.created_by_username ?? "user"} on Whisper`);
    lines.push(`DESCRIPTION:${icsEscape(descParts.join("\n"))}`);
    if (e.location) lines.push(`LOCATION:${icsEscape(e.location)}`);
    if (e.meeting_link) lines.push(`URL:${e.meeting_link}`);
    lines.push("END:VEVENT");
  }
  lines.push("END:VCALENDAR");
  return lines.join("\r\n");
}

/**
 * Google Calendar "add event" template URL — opens a pre-filled event
 * creation screen so the user can save one event without importing an .ics.
 */
export function googleCalendarUrl(e: CalendarEvent): string {
  const start = icsDate(e.start_time);
  const end = e.end_time
    ? icsDate(e.end_time)
    : icsDate(new Date(new Date(e.start_time).getTime() + DEFAULT_DURATION_MS).toISOString());
  const details: string[] = [];
  if (e.description) details.push(e.description);
  if (e.meeting_link) details.push(`Join: ${e.meeting_link}`);
  details.push(`Organized by @${e.created_by_username ?? "user"} on Whisper`);
  const params = new URLSearchParams({
    action: "TEMPLATE",
    text: e.title,
    dates: `${start}/${end}`,
    details: details.join("\n"),
  });
  if (e.location) params.set("location", e.location);
  return `https://calendar.google.com/calendar/render?${params.toString()}`;
}

/** Trigger a browser download of the calendar as an .ics file. */
export function downloadICS(events: CalendarEvent[]): void {
  const blob = new Blob([buildICS(events)], { type: "text/calendar" });
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = "whisper-team-calendar.ics";
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

// ---------------------------------------------------------------------------
// Post-event recap — lightweight content log stored as marked notes
// ---------------------------------------------------------------------------

/** Marker prefix identifying a recap note in the shared notes table. */
export const RECAP_PREFIX = "📸 Recap — ";

export function isRecapNote(note: CalendarNote): boolean {
  return note.body.startsWith(RECAP_PREFIX);
}

export function recapBody(note: CalendarNote): string {
  return note.body.slice(RECAP_PREFIX.length);
}

/** True once the event has finished (start + duration in the past). */
export function eventHasEnded(e: CalendarEvent): boolean {
  return eventWindow(e).end < Date.now();
}

/** Add a post-event recap entry. */
export async function addRecap(
  eventId: string,
  userId: string,
  username: string,
  body: string
): Promise<void> {
  await addNote(eventId, userId, username, RECAP_PREFIX + body);
}

/** Fetch RSVPs for a set of events. */
export async function fetchRSVPs(
  eventIds: string[]
): Promise<Record<string, CalendarRSVP[]>> {
  if (eventIds.length === 0) return {};
  const { data } = await supabase
    .from("whisper_calendar_rsvps")
    .select("*")
    .in("event_id", eventIds);
  const map: Record<string, CalendarRSVP[]> = {};
  for (const r of (data as CalendarRSVP[] | null) ?? []) {
    if (!map[r.event_id]) map[r.event_id] = [];
    map[r.event_id].push(r);
  }
  return map;
}

/** Set or update an RSVP for an event. */
export async function setRSVP(
  eventId: string,
  userId: string,
  username: string,
  status: "going" | "maybe" | "declined"
): Promise<void> {
  const { error } = await supabase
    .from("whisper_calendar_rsvps")
    .upsert(
      {
        event_id: eventId,
        user_id: userId,
        username,
        status,
      },
      { onConflict: "event_id,user_id" }
    );
  if (error) throw error;
}

/** Fetch notes for a set of events, returned as a map keyed by event_id. */
export async function fetchNotes(
  eventIds: string[]
): Promise<Record<string, CalendarNote[]>> {
  if (eventIds.length === 0) return {};
  const { data } = await supabase
    .from("whisper_calendar_notes")
    .select("*")
    .in("event_id", eventIds)
    .order("created_at", { ascending: true });
  const map: Record<string, CalendarNote[]> = {};
  for (const n of (data as CalendarNote[] | null) ?? []) {
    if (!map[n.event_id]) map[n.event_id] = [];
    map[n.event_id].push(n);
  }
  return map;
}

/** Add a mini note to a calendar event. */
export async function addNote(
  eventId: string,
  userId: string,
  username: string,
  body: string
): Promise<void> {
  const { error } = await supabase
    .from("whisper_calendar_notes")
    .insert({
      event_id: eventId,
      user_id: userId,
      username,
      body,
    });
  if (error) throw error;
}

/** Delete a mini note. */
export async function deleteNote(noteId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_calendar_notes")
    .delete()
    .eq("id", noteId);
  if (error) throw error;
}

/** Resolve profiles for all RSVP'd + tagged users of a set of events. */
export async function fetchEventParticipantProfiles(
  events: CalendarEvent[],
  rsvps: Record<string, CalendarRSVP[]>
): Promise<Record<string, WhisperProfile>> {
  const ids = new Set<string>();
  for (const e of events) {
    if (e.created_by) ids.add(e.created_by);
    for (const uid of e.tagged_user_ids) ids.add(uid);
    for (const r of rsvps[e.id] ?? []) ids.add(r.user_id);
  }
  return fetchProfilesByIds(Array.from(ids));
}

/** Derive a user's role label from their profile. */
export function roleLabelFor(
  profile: WhisperProfile | null | undefined
): string | null {
  if (!profile) return null;
  if (profile.is_coach) return "Coach";
  if (profile.is_athlete) return "Athlete";
  if (profile.is_verified) return "Creator";
  if (profile.is_recruiter) return "Recruiter";
  return null;
}
