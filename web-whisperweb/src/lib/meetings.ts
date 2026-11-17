import { supabase } from "@/lib/supabase";
import { meetingInvitationLink, meetingInvitationFromText } from "@/lib/meetingInvitation";
import { BACKEND_URL } from "@/lib/billing";
import { emberCompletion } from "@/lib/ember";

/**
 * Whisper Meetings — two related systems in one module:
 *
 * 1. Recruiter meeting REQUESTS ("Schedule a call" on featured cards) —
 *    approve/deny with a Google Meet link, handled by the billing backend.
 * 2. In-app video MEETINGS — private rooms reusing the live-room WebRTC
 *    engine, with per-participant speech transcripts and an AI-generated
 *    summary after the call (key points, decisions, action items).
 *
 * The in-app meeting signaling channel is `live-signal:meeting:{id}` so iOS
 * and web share the exact same room infrastructure as public lives.
 */

// ─── Recruiter meeting requests (backend-managed) ─────────────────────────

export type MeetingStatus = "pending" | "approved" | "denied" | "cancelled";

export interface MeetingRequest {
  id: string;
  recruiter_id: string;
  recruiter_username: string | null;
  featured_id: string | null;
  requester_user_id: string | null;
  requester_name: string;
  requester_email: string;
  requested_time: string;
  requester_timezone: string | null;
  message: string | null;
  status: MeetingStatus;
  meeting_link: string | null;
  recruiter_note: string | null;
  decided_at: string | null;
  created_at: string | null;
}

function normalizeStatus(s: unknown): MeetingStatus {
  return s === "approved" || s === "denied" || s === "cancelled"
    ? s
    : "pending";
}

function normalizeRow(row: Record<string, unknown>): MeetingRequest {
  return {
    id: String(row.id ?? ""),
    recruiter_id: String(row.recruiter_id ?? ""),
    recruiter_username: (row.recruiter_username as string | null) ?? null,
    featured_id: (row.featured_id as string | null) ?? null,
    requester_user_id: (row.requester_user_id as string | null) ?? null,
    requester_name: String(row.requester_name ?? ""),
    requester_email: String(row.requester_email ?? ""),
    requested_time: String(row.requested_time ?? ""),
    requester_timezone: (row.requester_timezone as string | null) ?? null,
    message: (row.message as string | null) ?? null,
    status: normalizeStatus(row.status),
    meeting_link: (row.meeting_link as string | null) ?? null,
    recruiter_note: (row.recruiter_note as string | null) ?? null,
    decided_at: (row.decided_at as string | null) ?? null,
    created_at: (row.created_at as string | null) ?? null,
  };
}

/** Public: submit a meeting request to a recruiter (from a featured card). */
export async function submitMeetingRequest(input: {
  recruiterId: string;
  recruiterUsername: string;
  featuredId?: string;
  requesterName: string;
  requesterEmail: string;
  requestedTime: string;
  requesterTimezone?: string;
  message?: string;
  token?: string | null;
}): Promise<void> {
  const res = await fetch(`${BACKEND_URL}/meetings/request`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(input.token ? { Authorization: `Bearer ${input.token}` } : {}),
    },
    body: JSON.stringify({
      recruiterId: input.recruiterId,
      recruiterUsername: input.recruiterUsername,
      featuredId: input.featuredId ?? null,
      requesterName: input.requesterName,
      requesterEmail: input.requesterEmail,
      requestedTime: input.requestedTime,
      requesterTimezone: input.requesterTimezone ?? null,
      message: input.message ?? null,
    }),
  });
  const data = (await res.json()) as { ok?: boolean; error?: string };
  if (!res.ok || !data.ok) {
    throw new Error(
      data.error === "invalid_email"
        ? "Please enter a valid email address."
        : data.error === "missing_time"
          ? "Please pick a preferred time."
          : data.error === "missing_recruiter"
            ? "This recruiter's profile isn't linked yet."
            : "Couldn't submit your request. Try again."
    );
  }
}

/** Recruiter: list meeting requests assigned to me. */
export async function fetchMyMeetingRequests(
  token: string
): Promise<MeetingRequest[]> {
  const res = await fetch(`${BACKEND_URL}/meetings/recruiter`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error("Couldn't load meeting requests.");
  const data = (await res.json()) as { requests?: Record<string, unknown>[] };
  return (data.requests ?? []).map(normalizeRow);
}

/** Recruiter: approve or deny a meeting request. */
export async function decideMeetingRequest(
  token: string,
  input: {
    id: string;
    decision: "approved" | "denied";
    meetingLink?: string;
    recruiterNote?: string;
  }
): Promise<void> {
  const res = await fetch(`${BACKEND_URL}/meetings/decide`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      id: input.id,
      decision: input.decision,
      meetingLink: input.meetingLink ?? "",
      recruiterNote: input.recruiterNote ?? "",
    }),
  });
  const data = (await res.json()) as { ok?: boolean; error?: string };
  if (!res.ok || !data.ok) {
    throw new Error(
      data.error === "invalid_meeting_link"
        ? "Please paste a valid Google Meet link (https://...)."
        : data.error === "unauthorized"
          ? "You need to be signed in."
          : "Couldn't update this request. Try again."
    );
  }
}

// ─── In-app video meetings with AI notes ─────────────────────────────────

export interface WhisperMeeting {
  id: string;
  host_id: string;
  host_username: string;
  title: string;
  status: "scheduled" | "live" | "ended";
  scheduled_at: string | null;
  started_at: string | null;
  ended_at: string | null;
  summary: string | null;
  summary_generated_at: string | null;
  created_at: string | null;
}

export interface MeetingTranscriptSegment {
  id: string;
  meeting_id: string;
  user_id: string;
  username: string;
  text: string;
  spoken_at: string | null;
}

/**
 * Translate raw Postgres/PostgREST failures into truthful, actionable copy.
 * The recursion case matters most: it means the superseded hardening policies
 * are still installed and the one-time recovery SQL hasn't been applied.
 */
function explainMeetingDbError(error: {
  code?: string;
  message?: string;
}): string {
  const code = error.code ?? "";
  const message = error.message ?? "";
  if (code === "42P17" || /infinite recursion/i.test(message)) {
    return "Meeting access rules in the database need a one-time repair. Run supabase/meetings-recovery.sql in the Supabase SQL editor, then try again.";
  }
  if (code === "42501" || /row-level security/i.test(message)) {
    return "Your account wasn't allowed to do that. Sign out and back in — and if it persists, apply supabase/meetings-recovery.sql in Supabase.";
  }
  if (code === "PGRST301" || /JWT/i.test(message)) {
    return "Your session expired. Sign in again and retry.";
  }
  return message || "Something went wrong talking to the meetings database.";
}

// ─── Meeting codes (wsp-xxxx-xxxx) ──────────────────────────────────────────

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** True when the id is a real database uuid (vs a human meeting code). */
export function isMeetingUuid(id: string): boolean {
  return UUID_RE.test(id.trim());
}

/**
 * Human meeting codes (wsp-5638-745f) map to a DETERMINISTIC uuid — the
 * database id column is a uuid, so the raw code can never be queried
 * directly. Every client hashes the code to the SAME uuid (cyrb128 →
 * RFC-4122 shape), so everyone opening the same link lands in the same
 * room and the first signed-in arriver creates the row under that id.
 */
export function meetingIdFromCode(code: string): string {
  const norm = code.trim().toLowerCase();
  let h1 = 1779033703;
  let h2 = 3144134277;
  let h3 = 1013904242;
  let h4 = 2773480762;
  for (let i = 0; i < norm.length; i++) {
    const k = norm.charCodeAt(i);
    h1 = h2 ^ Math.imul(h1 ^ k, 597399067);
    h2 = h3 ^ Math.imul(h2 ^ k, 2869860233);
    h3 = h4 ^ Math.imul(h3 ^ k, 951274213);
    h4 = h1 ^ Math.imul(h4 ^ k, 2716044179);
  }
  h1 = Math.imul(h3 ^ (h1 >>> 18), 597399067);
  h2 = Math.imul(h4 ^ (h2 >>> 22), 2869860233);
  h3 = Math.imul(h1 ^ (h3 >>> 17), 951274213);
  h4 = Math.imul(h2 ^ (h4 >>> 19), 2716044179);
  const words = [h1 >>> 0, h2 >>> 0, h3 >>> 0, h4 >>> 0];
  const bytes = new Uint8Array(16);
  words.forEach((w, i) => {
    bytes[i * 4] = (w >>> 24) & 0xff;
    bytes[i * 4 + 1] = (w >>> 16) & 0xff;
    bytes[i * 4 + 2] = (w >>> 8) & 0xff;
    bytes[i * 4 + 3] = w & 0xff;
  });
  bytes[6] = (bytes[6] & 0x0f) | 0x50; // version nibble — RFC shaped
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant bits
  const hex = Array.from(bytes, (b) => b.toString(16).padStart(2, "0")).join("");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

/** Route param → database id: uuids pass through, codes derive. */
export function resolveMeetingRoomId(idOrCode: string): string {
  return isMeetingUuid(idOrCode) ? idOrCode : meetingIdFromCode(idOrCode);
}

/**
 * Create the meeting row for a code-based room if nobody has yet — the
 * first signed-in arriver becomes the host. Idempotent and race-safe:
 * ON CONFLICT DO NOTHING, so simultaneous arrivals can't error out.
 */
export async function ensureMeetingRoom(input: {
  id: string;
  hostId: string;
  hostUsername: string;
  title?: string;
}): Promise<void> {
  const { error } = await supabase.from("whisper_meetings").upsert(
    {
      id: input.id,
      host_id: input.hostId,
      host_username: input.hostUsername,
      title: input.title?.trim() || "Meeting",
      status: "live",
      started_at: new Date().toISOString(),
    },
    { onConflict: "id", ignoreDuplicates: true }
  );
  if (error) throw new Error(explainMeetingDbError(error));
}

/** Original host only; compare-and-set protects a newer title from another device. */
export async function renameMeeting(meeting: WhisperMeeting, title: string): Promise<WhisperMeeting> {
  const clean = title.trim();
  if (!clean || clean.length > 160) throw new Error('Use a meeting name between 1 and 160 characters.');
  const { data: auth } = await supabase.auth.getSession();
  if (auth.session?.user.id !== meeting.host_id) throw new Error('Only the original meeting host can rename this meeting.');
  const { data, error } = await supabase.from('whisper_meetings').update({ title: clean }).eq('id', meeting.id).eq('host_id', auth.session.user.id).eq('title', meeting.title).select().maybeSingle();
  if (error || !data) throw new Error('The meeting could not be renamed. Refresh its current name and try again.');
  const current = await supabase.auth.getSession();
  if (current.data.session?.user.id !== meeting.host_id) throw new Error('Your account changed. Reopen the meeting.');
  return data as WhisperMeeting;
}

/** Start an instant meeting (or schedule one). Returns the created row. */
export async function createMeeting(input: {
  hostId: string;
  hostUsername: string;
  title: string;
  /** When set, the meeting is created as scheduled instead of live. */
  scheduledAt?: string;
  /** Pin the row id — pass `meetingIdFromCode(code)` so a scheduled meeting
   *  lives at a pretty wsp-xxxx-xxxx link instead of a raw uuid. */
  id?: string;
}): Promise<WhisperMeeting> {
  const nowIso = new Date().toISOString();
  const row = {
    ...(input.id ? { id: input.id } : {}),
    host_id: input.hostId,
    host_username: input.hostUsername,
    title: input.title.trim() || "Meeting",
    status: input.scheduledAt ? "scheduled" : "live",
    scheduled_at: input.scheduledAt ?? null,
    // Scheduled meetings stay un-started until the host begins them; the
    // recovery SQL guarantees started_at is nullable.
    started_at: input.scheduledAt ? null : nowIso,
  };
  let { data, error } = await supabase
    .from("whisper_meetings")
    .insert(row)
    .select()
    .limit(1);
  if (error?.code === "23502" && input.scheduledAt) {
    // Legacy database where started_at is still NOT NULL — retry with a
    // placeholder creation timestamp so scheduling keeps working.
    ({ data, error } = await supabase
      .from("whisper_meetings")
      .insert({ ...row, started_at: nowIso })
      .select()
      .limit(1));
  }
  if (error) throw new Error(explainMeetingDbError(error));
  const created = (data as WhisperMeeting[] | null)?.[0];
  if (!created) throw new Error("Meeting could not be created");
  return created;
}

/**
 * Host begins a scheduled meeting — flips it live and stamps the real start
 * time. A no-op for meetings that are already live. Host-only via RLS.
 */
export async function startMeeting(meetingId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_meetings")
    .update({ status: "live", started_at: new Date().toISOString() })
    .eq("id", meetingId)
    .eq("status", "scheduled");
  if (error) throw new Error(explainMeetingDbError(error));
}

/**
 * Reopen an ENDED meeting so its link works again — Meet's rule that a code
 * is never dead. Any signed-in member holding the link may reopen through
 * the guarded RPC (supabase/meetings-links.sql); until that migration lands
 * the host can still reopen directly (their own row is updatable), and
 * everyone else gets an honest "ask the host" error.
 */
export async function reopenMeeting(input: {
  meetingId: string;
  userId: string;
  username: string;
}): Promise<void> {
  const { error } = await supabase.rpc("reopen_whisper_meeting", {
    p_meeting_id: input.meetingId,
    p_username: input.username,
  });
  if (!error) return;
  if (error.code !== "PGRST202") {
    if (/meeting_not_found/i.test(error.message)) {
      throw new Error("This link doesn't point at a meeting anymore.");
    }
    throw new Error(explainMeetingDbError(error));
  }
  // Legacy database (no RPC yet): only the host's own row is updatable.
  const { data, error: updateError } = await supabase
    .from("whisper_meetings")
    .update({ status: "live", started_at: new Date().toISOString(), ended_at: null })
    .eq("id", input.meetingId)
    .eq("host_id", input.userId)
    .select("id")
    .limit(1);
  if (updateError) throw new Error(explainMeetingDbError(updateError));
  if (!(data as { id: string }[] | null)?.length) {
    throw new Error("Only the host can start this meeting again right now — ask them to open the link.");
  }
  await joinMeeting({ meetingId: input.meetingId, userId: input.userId, username: input.username }).catch(
    () => undefined,
  );
}

/** Canonical ordinary invitation, retaining the original public UUID/code. */
export function meetingLink(id: string): string {
  return meetingInvitationLink(id);
}

// ─── 1:1 ringing calls (DM video button) ───────────────────────────────

const CALL_PREFIX = "::whisper-call-v1::";

/** The ring payload a DM video call sends — rendered as a call card in the
 *  thread and picked up in realtime by the callee's incoming-call overlay. */
export interface CallInvitePayload {
  meetingId: string;
  fromUserId: string;
  fromUsername: string;
  toUserId: string | null;
  /** Voice-only or video call — drives ring copy and whether the camera is
   *  acquired on join. Older payloads without a mode are treated as video. */
  mode: "audio" | "video";
  /** Epoch ms when the call started ringing — rings expire after ~45s. */
  at: number;
}

export function encodeCallInvite(input: {
  meetingId: string;
  fromUserId: string;
  fromUsername: string;
  toUserId?: string | null;
  mode?: "audio" | "video";
}): string {
  // Superset of both wire shapes: `id`/`kind`/`mode` are what the iOS
  // client's strict decoder requires (so voice calls ring as voice there),
  // the rest is the web ring payload.
  const payload = {
    id: input.meetingId,
    kind: "invite" as const,
    mode: input.mode ?? "video",
    meetingId: input.meetingId,
    fromUserId: input.fromUserId,
    fromUsername: input.fromUsername,
    toUserId: input.toUserId ?? null,
    at: Date.now(),
  };
  return CALL_PREFIX + JSON.stringify(payload);
}

/** True for ANY call-signal body (invite, accept, decline, cancel, end).
 *  Control signals aren't chat content — threads hide them entirely. */
export function isCallSignal(body: string | null | undefined): boolean {
  return !!body && body.startsWith(CALL_PREFIX);
}

export function decodeCallInvite(
  body: string | null | undefined
): CallInvitePayload | null {
  if (!body || !body.startsWith(CALL_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(CALL_PREFIX.length)) as Partial<CallInvitePayload> & {
      kind?: string;
    };
    if (!o.meetingId || !o.fromUserId) return null;
    // iOS also signals accept/decline/cancel/end on this prefix — only
    // invites should ring or render as call cards.
    if (o.kind && o.kind !== "invite") return null;
    return {
      meetingId: o.meetingId,
      fromUserId: o.fromUserId,
      fromUsername: o.fromUsername ?? "someone",
      toUserId: o.toUserId ?? null,
      mode: o.mode === "audio" ? "audio" : "video",
      at: typeof o.at === "number" ? o.at : 0,
    };
  } catch {
    return null;
  }
}

/**
 * Extract a Whisper meeting id from free text (DM bodies, calendar links).
 * Matches mydailywhisper.com/meet/{uuid} and bare /meet/{uuid} paths.
 */
export function meetingIdFromText(text: string | null | undefined): string | null {
  return meetingInvitationFromText(text)?.idOrCode ?? null;
}

/**
 * Latest heart-rate readings for a set of users, pulled from their Jasper
 * client snapshots. Coaches use this to overlay live bpm on meeting tiles.
 * Payload shapes vary across Jasper builds, so parsing is tolerant.
 */
export async function fetchHeartRates(
  userIds: string[]
): Promise<Record<string, number>> {
  if (userIds.length === 0) return {};
  const { data } = await supabase
    .from("whisper_client_snapshots")
    .select("user_id, payload")
    .in("user_id", userIds);
  const out: Record<string, number> = {};
  for (const row of (data as { user_id: string; payload: unknown }[] | null) ?? []) {
    const bpm = extractHeartRate(row.payload, 0);
    if (bpm != null) out[row.user_id] = bpm;
  }
  return out;
}

function extractHeartRate(payload: unknown, depth: number): number | null {
  if (depth > 2 || !payload || typeof payload !== "object") return null;
  const obj = payload as Record<string, unknown>;
  const candidates = [
    "heartRate", "heart_rate", "currentHeartRate", "restingHeartRate",
    "resting_heart_rate", "latestHeartRate", "bpm",
  ];
  for (const key of candidates) {
    const v = obj[key];
    if (typeof v === "number" && v > 20 && v < 250) return Math.round(v);
  }
  for (const v of Object.values(obj)) {
    if (v && typeof v === "object") {
      const nested = extractHeartRate(v, depth + 1);
      if (nested != null) return nested;
    }
  }
  return null;
}

export async function fetchMeeting(id: string): Promise<WhisperMeeting | null> {
  const { data, error } = await supabase
    .from("whisper_meetings")
    .select("*")
    .eq("id", id)
    .limit(1)
    .maybeSingle();
  // Real database failures must not masquerade as "meeting not found".
  if (error) throw new Error(explainMeetingDbError(error));
  return (data as WhisperMeeting | null) ?? null;
}

/** Meetings I hosted or joined, newest first. */
export async function fetchMyMeetings(userId: string): Promise<WhisperMeeting[]> {
  const [hosted, joined] = await Promise.all([
    supabase
      .from("whisper_meetings")
      .select("*")
      .eq("host_id", userId)
      .order("created_at", { ascending: false })
      .limit(30),
    supabase
      .from("whisper_meeting_participants")
      .select("meeting_id")
      .eq("user_id", userId)
      .order("joined_at", { ascending: false })
      .limit(30),
  ]);
  const rows = (hosted.data as WhisperMeeting[] | null) ?? [];
  const joinedIds = ((joined.data as { meeting_id: string }[] | null) ?? [])
    .map((r) => r.meeting_id)
    .filter((id) => !rows.some((m) => m.id === id));
  if (joinedIds.length > 0) {
    const { data } = await supabase
      .from("whisper_meetings")
      .select("*")
      .in("id", joinedIds);
    rows.push(...(((data as WhisperMeeting[] | null) ?? [])));
  }
  // Upcoming first (soonest at the top), then everything else newest-first.
  // Sorting purely by created_at buried tomorrow's scheduled meeting under
  // older ended calls — iOS already splits upcoming from recent; now web
  // surfaces them the same way everywhere fetchMyMeetings feeds.
  const now = Date.now();
  const isUpcoming = (m: WhisperMeeting): boolean =>
    m.status === "scheduled" &&
    !!m.scheduled_at &&
    new Date(m.scheduled_at).getTime() > now - 30 * 60_000;
  const upcoming = rows
    .filter(isUpcoming)
    .sort(
      (a, b) =>
        new Date(a.scheduled_at ?? 0).getTime() -
        new Date(b.scheduled_at ?? 0).getTime()
    );
  const rest = rows
    .filter((m) => !isUpcoming(m))
    .sort(
      (a, b) =>
        new Date(b.created_at ?? 0).getTime() -
        new Date(a.created_at ?? 0).getTime()
    );
  return [...upcoming, ...rest];
}

/** Record that a user joined (idempotent). */
export async function joinMeeting(input: {
  meetingId: string;
  userId: string;
  username: string;
}): Promise<void> {
  const { error } = await supabase.rpc("join_whisper_meeting", {
    p_meeting_id: input.meetingId,
    p_username: input.username,
  });
  if (!error) return;

  // Existing installs keep working until the hardening SQL is applied. The
  // fallback disappears automatically once the guarded RPC exists.
  if (error.code === "PGRST202") {
    const { error: legacyError } = await supabase
      .from("whisper_meeting_participants")
      .upsert(
        {
          meeting_id: input.meetingId,
          user_id: input.userId,
          username: input.username,
        },
        { onConflict: "meeting_id,user_id" },
      );
    if (!legacyError) return;
    throw legacyError;
  }
  throw error;
}

/** Insert one finished utterance of the local user's speech. */
export async function addTranscriptSegment(input: {
  meetingId: string;
  userId: string;
  username: string;
  text: string;
}): Promise<void> {
  const text = input.text.trim();
  if (!text) return;
  const { error } = await supabase.from("whisper_meeting_transcripts").insert({
    meeting_id: input.meetingId,
    user_id: input.userId,
    username: input.username,
    text,
  });
  if (error) throw error;
}

/** One participant row — used for auto-sending the notes DM after a call. */
export interface MeetingParticipant {
  user_id: string;
  username: string;
}

/** Everyone who joined this meeting (host included). */
export async function fetchMeetingParticipants(
  meetingId: string
): Promise<MeetingParticipant[]> {
  const { data } = await supabase
    .from("whisper_meeting_participants")
    .select("user_id, username")
    .eq("meeting_id", meetingId)
    .limit(60);
  return ((data as MeetingParticipant[] | null) ?? []).filter(
    (p) => p.user_id && p.username
  );
}

export async function fetchTranscript(
  meetingId: string
): Promise<MeetingTranscriptSegment[]> {
  const rows: MeetingTranscriptSegment[] = [];
  const boundary = new Date().toISOString();
  for (let page = 0; page < 50; page++) {
    const { data, error } = await supabase.from('whisper_meeting_transcripts').select('*')
      .eq('meeting_id', meetingId).lte('spoken_at', boundary)
      .order('spoken_at', { ascending: true }).order('id', { ascending: true })
      .range(page * 200, page * 200 + 199);
    if (error) throw new Error('Saved transcript could not load. Reconnect and try again.');
    const segments = (data as MeetingTranscriptSegment[] | null) ?? [];
    rows.push(...segments);
    if (segments.length < 200) return rows;
  }
  throw new Error('This transcript exceeds the readable window. It has not been silently shortened.');
}

// ─── Notebook — favorites + renames over meeting notes ───────────────────

export interface NotebookPref {
  meeting_id: string;
  custom_title: string | null;
  is_favorite: boolean;
}

export interface NotebookPrefsResult {
  prefs: Record<string, NotebookPref>;
  /** True when supabase/notebook.sql hasn't been applied yet. */
  missing: boolean;
}

/** The signed-in user's notebook prefs, keyed by meeting id. */
export async function fetchNotebookPrefs(
  userId: string
): Promise<NotebookPrefsResult> {
  const { data, error } = await supabase
    .from("whisper_notebook_prefs")
    .select("meeting_id, custom_title, is_favorite")
    .eq("user_id", userId);
  if (error) {
    return { prefs: {}, missing: error.code === "42P01" };
  }
  const prefs: Record<string, NotebookPref> = {};
  for (const row of (data as NotebookPref[] | null) ?? []) {
    prefs[row.meeting_id] = row;
  }
  return { prefs, missing: false };
}

/** Upsert one notebook pref (favorite toggle and/or rename). */
export async function saveNotebookPref(
  userId: string,
  meetingId: string,
  patch: { customTitle?: string | null; isFavorite?: boolean }
): Promise<void> {
  const { data: existing } = await supabase
    .from("whisper_notebook_prefs")
    .select("custom_title, is_favorite")
    .eq("user_id", userId)
    .eq("meeting_id", meetingId)
    .maybeSingle();
  const current = existing as {
    custom_title: string | null;
    is_favorite: boolean;
  } | null;
  const { error } = await supabase.from("whisper_notebook_prefs").upsert(
    {
      user_id: userId,
      meeting_id: meetingId,
      custom_title:
        patch.customTitle !== undefined
          ? patch.customTitle
          : (current?.custom_title ?? null),
      is_favorite:
        patch.isFavorite !== undefined
          ? patch.isFavorite
          : (current?.is_favorite ?? false),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "user_id,meeting_id" }
  );
  if (error) throw error;
}

/** Mark the meeting ended (host only via RLS). */
export async function endMeeting(meetingId: string): Promise<void> {
  const { data, error } = await supabase
    .from("whisper_meetings")
    .update({ status: "ended", ended_at: new Date().toISOString() })
    .eq("id", meetingId).select("id").single();
  if (error || !data) throw new Error("You left the call, but ending the shared room could not be confirmed.");
}

// ─── AI summary ───────────────────────────────────────────────────────────────

const NOTES_SYSTEM =
  "You are a meeting notes assistant (like Gemini notes for Google Meet). Given a raw speech transcript, produce clean structured notes with these sections: **Summary** (2-3 sentences), **Key points** (bullets), **Decisions** (bullets, or 'None recorded'), **Action items** (bullets with owner names when identifiable, or 'None recorded'). Be concise and factual — never invent content that isn't in the transcript.";

/** Notes ride the shared Ember transport chain (toolkit gateway → project
 *  backend proxy → OpenAI direct), so they work on every deployment,
 *  including the production custom domain. Returns "" if every path fails. */
async function notesCompletion(transcript: string): Promise<string> {
  return emberCompletion(
    [
      { role: "system", content: NOTES_SYSTEM },
      { role: "user", content: transcript },
    ],
    900
  );
}

export interface MeetingNotesResult {
  /** The generated notes, or null when generation wasn't possible. */
  summary: string | null;
  /** How many transcript segments existed — lets the UI tell "no speech was
   *  captured" apart from "the AI call failed" truthfully. */
  segmentCount: number;
}

/**
 * Generate the AI meeting notes from the transcript and persist them on the
 * meeting row. The transcript itself is always preserved regardless of
 * whether note generation succeeds.
 */
export async function generateMeetingNotes(
  meetingId: string
): Promise<MeetingNotesResult> {
  const { data: callRoom, error: roomError } = await supabase.from("whisper_meetings").select("summary").eq("id", meetingId).single();
  if (roomError) throw new Error("Couldn't load this room. Please try again.");
  if (callRoom?.summary?.startsWith("::whisper-group-call-v1::")) return { summary: null, segmentCount: 0 };
  const segments = await fetchTranscript(meetingId);
  if (segments.length === 0) return { summary: null, segmentCount: 0 };

  const transcript = segments
    .map((s) => `${s.username || "Speaker"}: ${s.text}`)
    .join("\n");
  if (transcript.length > 24000) throw new Error('This transcript is too long for one recap. All saved speech is retained; review smaller selections with Jasper instead.');

  const generated = await notesCompletion(transcript);
  const summary = generated ? `${generated}\n\n**Coverage**\nSaved speech snapshot. Pending or later-arriving speech is not included; refresh the transcript and review with Jasper for updates.` : '';
  if (!summary) return { summary: null, segmentCount: segments.length };

  // A recap is reopenable only after the server acknowledges its row.
  const { data, error } = await supabase
    .from("whisper_meetings")
    .update({
      summary,
      summary_generated_at: new Date().toISOString(),
    })
    .eq("id", meetingId).select("id").single();
  if (error || !data) throw new Error("The shared recap could not be saved. Reopen the ended meeting and retry generating notes.");
  return { summary, segmentCount: segments.length };
}
