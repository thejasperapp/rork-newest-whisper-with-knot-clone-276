import { supabase } from "@/lib/supabase";

/**
 * Web port of the iOS coach back-office services
 * (`WhisperCoachService`, `WhisperCoachRequestService`,
 * `WhisperCoachProgramService`, `WhisperCoachProposalService`).
 * Talks to the same Supabase tables so coaches and clients are in sync
 * across iOS and web.
 */

// MARK: - Requests / relationships

export type CoachRequestStatus =
  | "pending"
  | "accepted"
  | "declined"
  | "cancelled";

export interface CoachRequest {
  id: string;
  client_user_id: string;
  client_username: string;
  coach_user_id: string;
  coach_username: string;
  message: string | null;
  status: CoachRequestStatus;
  created_at: string | null;
  updated_at: string | null;
}

interface CoachRequestBuckets {
  /** Requests the user sent (they want to be coached). */
  outgoing: CoachRequest[];
  /** Requests the user received (people who want them as coach). */
  incoming: CoachRequest[];
  /** Accepted relationships where the user is the client. */
  myCoaches: CoachRequest[];
  /** Accepted relationships where the user is the coach. */
  myClients: CoachRequest[];
}

export async function fetchCoachRequests(
  userId: string
): Promise<CoachRequestBuckets> {
  const [out, inc] = await Promise.all([
    supabase
      .from("whisper_coach_requests")
      .select("*")
      .eq("client_user_id", userId)
      .order("updated_at", { ascending: false }),
    supabase
      .from("whisper_coach_requests")
      .select("*")
      .eq("coach_user_id", userId)
      .order("updated_at", { ascending: false }),
  ]);
  const outgoing = (out.data as CoachRequest[] | null) ?? [];
  const incoming = (inc.data as CoachRequest[] | null) ?? [];
  return {
    outgoing,
    incoming,
    myCoaches: outgoing.filter((r) => r.status === "accepted"),
    myClients: incoming.filter((r) => r.status === "accepted"),
  };
}

/** Client → coach: "please coach me". Upserts so re-requesting is idempotent. */
export async function requestCoach(input: {
  clientUserId: string;
  clientUsername: string;
  coachUserId: string;
  coachUsername: string;
  message: string;
}): Promise<void> {
  const { error } = await supabase.from("whisper_coach_requests").upsert(
    {
      client_user_id: input.clientUserId,
      client_username: input.clientUsername,
      coach_user_id: input.coachUserId,
      coach_username: input.coachUsername,
      message: input.message,
      status: "pending",
    },
    { onConflict: "client_user_id,coach_user_id" }
  );
  if (error) throw error;
}

export async function updateCoachRequestStatus(
  requestId: string,
  status: CoachRequestStatus
): Promise<void> {
  const { error } = await supabase
    .from("whisper_coach_requests")
    .update({ status, updated_at: new Date().toISOString() })
    .eq("id", requestId);
  if (error) throw error;
}

/** Permanently end / withdraw a coaching relationship. */
export async function endCoachRequest(requestId: string): Promise<void> {
  await supabase.from("whisper_coach_requests").delete().eq("id", requestId);
}

/** Live status of a request the user already sent to a given coach. */
export async function outgoingCoachStatus(
  clientUserId: string,
  coachUserId: string
): Promise<CoachRequestStatus | null> {
  const { data } = await supabase
    .from("whisper_coach_requests")
    .select("status")
    .eq("client_user_id", clientUserId)
    .eq("coach_user_id", coachUserId)
    .limit(1)
    .maybeSingle();
  return ((data as { status: CoachRequestStatus } | null)?.status ?? null);
}

/**
 * Client ids that paid this coach within the current monthly cycle.
 * Reads the coach's own earnings ledger (RLS: coach reads own rows), so it
 * only works for the signed-in coach.
 */
export async function fetchPaidClientIds(
  coachUserId: string
): Promise<Set<string>> {
  const since = new Date(Date.now() - 40 * 86_400_000).toISOString();
  const { data } = await supabase
    .from("whisper_coach_earnings")
    .select("client_user_id")
    .eq("coach_user_id", coachUserId)
    .gte("created_at", since)
    .limit(500);
  const ids = new Set<string>();
  for (const row of (data as { client_user_id: string | null }[] | null) ?? []) {
    if (row.client_user_id) ids.add(row.client_user_id);
  }
  return ids;
}

// MARK: - Programs

export interface ProgramExercise {
  id: string;
  name: string;
  sets: number;
  reps: string;
  restSeconds: number;
  note?: string | null;
}

export interface ProgramDay {
  id: string;
  name: string;
  focus: string;
  exercises: ProgramExercise[];
}

export interface CoachProgram {
  id: string;
  coachUserId: string;
  coachUsername: string;
  title: string;
  focus: string;
  weeks: number;
  sessionsPerWeek: number;
  summary: string;
  days: ProgramDay[];
  /** One-time price in cents (0 = free). Stored in the program's JSON
   *  payload so no schema change is needed; the payment backend reads the
   *  same field when creating checkout sessions. */
  priceCents: number;
  createdAt: string | null;
}

interface ProgramRow {
  id: string;
  coach_user_id: string;
  coach_username: string;
  title: string;
  focus: string;
  weeks: number;
  sessions_per_week: number;
  summary: string;
  payload: { days: ProgramDay[]; priceCents?: number } | null;
  is_public: boolean | null;
  created_at: string | null;
}

function rowToProgram(r: ProgramRow): CoachProgram {
  const rawPrice = Number(r.payload?.priceCents ?? 0);
  return {
    id: r.id,
    coachUserId: r.coach_user_id,
    coachUsername: r.coach_username,
    title: r.title,
    focus: r.focus,
    weeks: r.weeks,
    sessionsPerWeek: r.sessions_per_week,
    summary: r.summary,
    days: r.payload?.days ?? [],
    priceCents: Number.isFinite(rawPrice) && rawPrice > 0 ? Math.round(rawPrice) : 0,
    createdAt: r.created_at,
  };
}

export async function fetchMyPrograms(
  coachUserId: string
): Promise<CoachProgram[]> {
  const { data } = await supabase
    .from("whisper_coach_programs")
    .select("*")
    .eq("coach_user_id", coachUserId)
    .order("created_at", { ascending: false });
  return ((data as ProgramRow[] | null) ?? []).map(rowToProgram);
}

export async function saveProgram(program: CoachProgram): Promise<void> {
  const { error } = await supabase.from("whisper_coach_programs").upsert({
    id: program.id,
    coach_user_id: program.coachUserId,
    coach_username: program.coachUsername,
    title: program.title,
    focus: program.focus,
    weeks: program.weeks,
    sessions_per_week: program.sessionsPerWeek,
    summary: program.summary,
    payload: { days: program.days, priceCents: program.priceCents || 0 },
    is_public: false,
  });
  if (error) throw error;
}

export async function deleteProgram(id: string): Promise<void> {
  await supabase.from("whisper_coach_programs").delete().eq("id", id);
}

export function blankProgram(
  coachUserId: string,
  coachUsername: string
): CoachProgram {
  return {
    id: crypto.randomUUID(),
    coachUserId,
    coachUsername,
    title: "New program",
    focus: "Strength",
    weeks: 4,
    sessionsPerWeek: 3,
    summary: "",
    days: [
      {
        id: crypto.randomUUID(),
        name: "Day 1",
        focus: "Upper",
        exercises: [
          {
            id: crypto.randomUUID(),
            name: "Bench press",
            sets: 4,
            reps: "6-8",
            restSeconds: 120,
            note: null,
          },
        ],
      },
    ],
    priceCents: 0,
    createdAt: new Date().toISOString(),
  };
}

/** Encodes a program into a DM body so a client can receive it inline. */
const PROGRAM_PREFIX = "::whisper-program-v1::";

/** Decoded program payload as it travels through a DM. */
export interface ProgramDMPayload {
  id: string;
  coachUsername: string;
  title: string;
  focus: string;
  weeks: number;
  sessionsPerWeek: number;
  summary: string;
  days: ProgramDay[];
  /** One-time price in cents — recipients must buy before the full plan
   *  opens. 0/absent = free (legacy payloads stay fully visible). */
  priceCents: number;
}

export function decodeProgramDM(
  body: string | null | undefined
): ProgramDMPayload | null {
  if (!body || !body.startsWith(PROGRAM_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(PROGRAM_PREFIX.length)) as Partial<ProgramDMPayload>;
    if (typeof o.title !== "string") return null;
    const rawPrice = Number(o.priceCents ?? 0);
    return {
      id: o.id ?? "",
      coachUsername: o.coachUsername ?? "",
      title: o.title,
      focus: o.focus ?? "",
      weeks: o.weeks ?? 0,
      sessionsPerWeek: o.sessionsPerWeek ?? 0,
      summary: o.summary ?? "",
      days: Array.isArray(o.days) ? o.days : [],
      priceCents: Number.isFinite(rawPrice) && rawPrice > 0 ? Math.round(rawPrice) : 0,
    };
  } catch {
    return null;
  }
}

export function encodeProgramForDM(program: CoachProgram): string {
  const payload = {
    id: program.id,
    coachUsername: program.coachUsername,
    title: program.title,
    focus: program.focus,
    weeks: program.weeks,
    sessionsPerWeek: program.sessionsPerWeek,
    summary: program.summary,
    days: program.days,
    priceCents: program.priceCents || 0,
  };
  return PROGRAM_PREFIX + JSON.stringify(payload);
}

// MARK: - Nutrition / daily-target DM embeds (consumed by the iOS client)

/** `::whisper-coach-macros-v1::` — updates the client's nutrition goals. */
export interface CoachMacros {
  calories: number | null;
  protein_g: number | null;
  carbs_g: number | null;
  fat_g: number | null;
  water_cups: number | null;
}

const MACROS_PREFIX = "::whisper-coach-macros-v1::";

export function encodeCoachMacros(
  coachUsername: string,
  m: CoachMacros
): string {
  const payload = {
    id: crypto.randomUUID(),
    coachUsername,
    calories: m.calories,
    protein_g: m.protein_g,
    carbs_g: m.carbs_g,
    fat_g: m.fat_g,
    water_cups: m.water_cups,
  };
  return MACROS_PREFIX + JSON.stringify(payload);
}

export interface CoachMacrosPayload extends CoachMacros {
  coachUsername: string;
}

export function decodeCoachMacros(
  body: string | null | undefined
): CoachMacrosPayload | null {
  if (!body || !body.startsWith(MACROS_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(MACROS_PREFIX.length)) as Partial<CoachMacrosPayload>;
    return {
      coachUsername: o.coachUsername ?? "",
      calories: o.calories ?? null,
      protein_g: o.protein_g ?? null,
      carbs_g: o.carbs_g ?? null,
      fat_g: o.fat_g ?? null,
      water_cups: o.water_cups ?? null,
    };
  } catch {
    return null;
  }
}

/** `::whisper-coach-targets-v1::` — daily activity targets (steps, sleep). */
export interface CoachDailyTargets {
  steps: number | null;
  sleep_hours: number | null;
  note: string | null;
}

const TARGETS_PREFIX = "::whisper-coach-targets-v1::";

export interface CoachTargetsPayload extends CoachDailyTargets {
  coachUsername: string;
}

export function decodeCoachTargets(
  body: string | null | undefined
): CoachTargetsPayload | null {
  if (!body || !body.startsWith(TARGETS_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(TARGETS_PREFIX.length)) as Partial<CoachTargetsPayload>;
    return {
      coachUsername: o.coachUsername ?? "",
      steps: o.steps ?? null,
      sleep_hours: o.sleep_hours ?? null,
      note: o.note ?? null,
    };
  } catch {
    return null;
  }
}

export function encodeCoachTargets(
  coachUsername: string,
  t: CoachDailyTargets
): string {
  const payload = {
    id: crypto.randomUUID(),
    coachUsername,
    steps: t.steps,
    sleep_hours: t.sleep_hours,
    note: t.note,
  };
  return TARGETS_PREFIX + JSON.stringify(payload);
}

/** `::whisper-coach-diet-plan-v1::` — a full macro-target diet plan. */
export interface CoachDietPlanPayload {
  coachUsername: string;
  name: string;
  calories: number | null;
  protein_g: number | null;
  carbs_g: number | null;
  fat_g: number | null;
  dietary_preference: string | null;
  goal: string | null;
  days_count: number | null;
  meals_per_day: number | null;
}

const DIET_PLAN_PREFIX = "::whisper-coach-diet-plan-v1::";

export function decodeCoachDietPlan(
  body: string | null | undefined
): CoachDietPlanPayload | null {
  if (!body || !body.startsWith(DIET_PLAN_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(DIET_PLAN_PREFIX.length)) as Partial<CoachDietPlanPayload>;
    return {
      coachUsername: o.coachUsername ?? "",
      name: o.name ?? "Coach plan",
      calories: o.calories ?? null,
      protein_g: o.protein_g ?? null,
      carbs_g: o.carbs_g ?? null,
      fat_g: o.fat_g ?? null,
      dietary_preference: o.dietary_preference ?? null,
      goal: o.goal ?? null,
      days_count: o.days_count ?? null,
      meals_per_day: o.meals_per_day ?? null,
    };
  } catch {
    return null;
  }
}

/** `::whisper-coach-proposal-v1::` — a coach suggestion the client reviews. */
export interface CoachProposalPayload {
  id: string;
  kind: string;
  coachUsername: string;
  summary: string;
  note: string | null;
}

const PROPOSAL_PREFIX = "::whisper-coach-proposal-v1::";

export function decodeCoachProposal(
  body: string | null | undefined
): CoachProposalPayload | null {
  if (!body || !body.startsWith(PROPOSAL_PREFIX)) return null;
  try {
    const o = JSON.parse(body.slice(PROPOSAL_PREFIX.length)) as Partial<CoachProposalPayload>;
    if (typeof o.id !== "string" || typeof o.kind !== "string") return null;
    return {
      id: o.id,
      kind: o.kind,
      coachUsername: o.coachUsername ?? "your coach",
      summary: o.summary ?? "",
      note: o.note ?? null,
    };
  } catch {
    return null;
  }
}

/** Human title for a proposal kind — mirrors iOS `WhisperCoachProposalEmbed.title`. */
export function coachProposalTitle(kind: string): string {
  switch (kind) {
    case "macros":
      return "Macro update";
    case "diet_plan":
      return "New diet plan";
    case "workout":
      return "Workout tweak";
    case "exercise_swap":
      return "Exercise swap";
    case "note":
      return "Coaching note";
    default:
      return "Coach suggestion";
  }
}

// MARK: - Local saved/applied state for coach cards
//
// iOS keeps per-message "saved" state in memory (`savedCoachMacrosIDs`) and
// per-proposal status in `whisper_proposal_receipts`. On web we persist a
// small id→state map in localStorage so the card keeps its applied/accepted
// look across refreshes, exactly like the grocery checklist.

const CARD_STATE_KEY = "whisper_coach_card_state_v1";

export type CoachCardState = "applied" | "saved" | "accepted" | "declined";

function readCardStates(): Record<string, CoachCardState> {
  try {
    const raw = localStorage.getItem(CARD_STATE_KEY);
    return raw ? (JSON.parse(raw) as Record<string, CoachCardState>) : {};
  } catch {
    return {};
  }
}

export function coachCardState(id: string): CoachCardState | null {
  if (!id) return null;
  return readCardStates()[id] ?? null;
}

export function setCoachCardState(id: string, state: CoachCardState): void {
  if (!id) return;
  try {
    const map = readCardStates();
    map[id] = state;
    localStorage.setItem(CARD_STATE_KEY, JSON.stringify(map));
  } catch {
    /* storage full / unavailable */
  }
}

/**
 * Records the signed-in client's response to a coach proposal and applies it.
 * Mirrors iOS `WhisperCoachProposalReviewService.respond`: on accept of a
 * macros proposal we read the row's `patch`, push it to the user's goals, then
 * flip the proposal status and write a receipt. Never throws — returns true on
 * a clean write so the UI can fall back gracefully.
 */
export async function respondToCoachProposal(input: {
  proposalId: string;
  userId: string;
  status: "accepted" | "declined";
}): Promise<boolean> {
  const { proposalId, userId, status } = input;
  // On accept, apply the patch (macros) to the user's own goals.
  if (status === "accepted") {
    try {
      const { data } = await supabase
        .from("whisper_coach_proposals")
        .select("kind, patch")
        .eq("id", proposalId)
        .limit(1)
        .maybeSingle();
      const row = data as { kind: string; patch: Record<string, number> | null } | null;
      if (row && row.kind === "macros" && row.patch) {
        const { applyMyGoals } = await import("@/lib/jasperData");
        await applyMyGoals(userId, {
          calories: row.patch.calories ?? null,
          protein_g: row.patch.protein_g ?? null,
          carbs_g: row.patch.carbs_g ?? null,
          fat_g: row.patch.fat_g ?? null,
        });
      }
    } catch {
      /* row hidden by RLS — still record the response below */
    }
  }

  const respondedAt = new Date().toISOString();
  let ok = false;
  // Write the receipt (idempotent upsert) — coaches read this for status.
  try {
    const { error } = await supabase.from("whisper_proposal_receipts").upsert(
      {
        proposal_id: proposalId,
        client_user_id: userId,
        status,
        responded_at: respondedAt,
      },
      { onConflict: "proposal_id,client_user_id" }
    );
    ok = !error;
  } catch {
    /* table missing — embed itself is the permanent record */
  }
  // Best-effort status flip on the proposal row (RLS allows the client).
  try {
    await supabase
      .from("whisper_coach_proposals")
      .update({ status, responded_at: respondedAt })
      .eq("id", proposalId);
  } catch {
    /* benign permission error for non-owners */
  }
  return ok;
}

// MARK: - Proposals

export type ProposalKind = "macros" | "diet_plan" | "note";

export interface CoachProposal {
  id: string;
  coach_user_id: string;
  client_user_id: string;
  kind: string;
  note: string | null;
  status: string;
  created_at: string | null;
}

export async function fetchProposalsForClient(
  coachUserId: string,
  clientUserId: string
): Promise<CoachProposal[]> {
  const { data } = await supabase
    .from("whisper_coach_proposals")
    .select("*")
    .eq("coach_user_id", coachUserId)
    .eq("client_user_id", clientUserId)
    .order("created_at", { ascending: false })
    .limit(25);
  return (data as CoachProposal[] | null) ?? [];
}

export async function submitProposal(input: {
  coachUserId: string;
  clientUserId: string;
  kind: ProposalKind;
  patch: Record<string, string | number | boolean | null>;
  note: string | null;
}): Promise<CoachProposal | null> {
  const { data, error } = await supabase
    .from("whisper_coach_proposals")
    .insert({
      coach_user_id: input.coachUserId,
      client_user_id: input.clientUserId,
      kind: input.kind,
      patch: input.patch,
      note: input.note?.trim() ? input.note.trim() : null,
    })
    .select()
    .limit(1);
  if (error) throw error;
  return ((data as CoachProposal[] | null)?.[0]) ?? null;
}

// MARK: - Client health snapshot (whisper_client_snapshots)

/**
 * Aggregated client fitness snapshot — the web port of the iOS
 * `WhisperClientSnapshot`. A client's accepted coaches can read this row to
 * review current nutrition, sleep, steps, weight and progress photos.
 */
export interface ClientSnapshot {
  caloriesToday: number;
  caloriesGoal: number;
  proteinToday: number;
  proteinGoal: number;
  carbsToday: number;
  carbsGoal: number;
  fatToday: number;
  fatGoal: number;
  waterCount: number;
  loggingStreak: number;
  sleepHours: number;
  steps: number;
  activeCalories: number;
  activeMinutes: number;
  restingHeartRate: number;
  bodyMassLbs: number;
  bodyFatPct: number;
  photoSets: number;
  daysSinceFirstPhoto: number;
  recentWorkouts: { type: string; durationMinutes: number; calories: number; date: string }[];
  note: string;
  capturedAt: string;
}

export interface ClientSnapshotRow {
  snapshot: ClientSnapshot | null;
  photoFrontUrl: string | null;
  photoSideUrl: string | null;
  photoBackUrl: string | null;
  updatedAt: string | null;
}

interface SnapshotRowRaw {
  payload: Partial<ClientSnapshot> | null;
  photo_front_url: string | null;
  photo_side_url: string | null;
  photo_back_url: string | null;
  updated_at: string | null;
}

/** Pulls a single client's latest snapshot row (RLS limits this to coaches). */
export async function fetchClientSnapshot(
  clientUserId: string
): Promise<ClientSnapshotRow | null> {
  const { data } = await supabase
    .from("whisper_client_snapshots")
    .select("payload, photo_front_url, photo_side_url, photo_back_url, updated_at")
    .eq("user_id", clientUserId)
    .limit(1)
    .maybeSingle();
  const row = data as SnapshotRowRaw | null;
  if (!row) return null;
  const p = row.payload;
  const snapshot: ClientSnapshot | null = p
    ? {
        caloriesToday: p.caloriesToday ?? 0,
        caloriesGoal: p.caloriesGoal ?? 0,
        proteinToday: p.proteinToday ?? 0,
        proteinGoal: p.proteinGoal ?? 0,
        carbsToday: p.carbsToday ?? 0,
        carbsGoal: p.carbsGoal ?? 0,
        fatToday: p.fatToday ?? 0,
        fatGoal: p.fatGoal ?? 0,
        waterCount: p.waterCount ?? 0,
        loggingStreak: p.loggingStreak ?? 0,
        sleepHours: p.sleepHours ?? 0,
        steps: p.steps ?? 0,
        activeCalories: p.activeCalories ?? 0,
        activeMinutes: p.activeMinutes ?? 0,
        restingHeartRate: p.restingHeartRate ?? 0,
        bodyMassLbs: p.bodyMassLbs ?? 0,
        bodyFatPct: p.bodyFatPct ?? 0,
        photoSets: p.photoSets ?? 0,
        daysSinceFirstPhoto: p.daysSinceFirstPhoto ?? 0,
        recentWorkouts: Array.isArray(p.recentWorkouts) ? p.recentWorkouts : [],
        note: p.note ?? "",
        capturedAt: p.capturedAt ?? "",
      }
    : null;
  return {
    snapshot,
    photoFrontUrl: row.photo_front_url,
    photoSideUrl: row.photo_side_url,
    photoBackUrl: row.photo_back_url,
    updatedAt: row.updated_at,
  };
}

// MARK: - Coach status / application

/** Resolve whether a user id is an approved coach (checks both tables). */
export async function isCoachUser(userId: string): Promise<boolean> {
  const [wp, p] = await Promise.all([
    supabase
      .from("whisper_profiles")
      .select("is_coach")
      .eq("user_id", userId)
      .limit(1)
      .maybeSingle(),
    supabase
      .from("profiles")
      .select("is_coach")
      .eq("id", userId)
      .limit(1)
      .maybeSingle(),
  ]);
  const a = (wp.data as { is_coach: boolean | null } | null)?.is_coach;
  const b = (p.data as { is_coach: boolean | null } | null)?.is_coach;
  return !!a || !!b;
}

export interface CoachApplicationState {
  status: "none" | "pending" | "approved" | "denied";
}

export async function fetchMyCoachApplication(
  userId: string
): Promise<CoachApplicationState> {
  const { data } = await supabase
    .from("whisper_coach_applications")
    .select("status")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  const status = (data as { status: string } | null)?.status;
  if (status === "pending" || status === "approved" || status === "denied")
    return { status };
  return { status: "none" };
}

export async function submitCoachApplication(input: {
  userId: string;
  username: string;
  email: string;
  fullName: string;
  credentials: string;
  specialties: string[];
  experienceYears: number;
  bio: string;
  website: string;
  social: string;
}): Promise<void> {
  const { error } = await supabase.from("whisper_coach_applications").insert({
    user_id: input.userId,
    username: input.username,
    email: input.email || null,
    full_name: input.fullName,
    credentials: input.credentials,
    specialties: input.specialties,
    experience_years: input.experienceYears,
    bio: input.bio,
    website: input.website || null,
    social: input.social || null,
    status: "pending",
  });
  if (error) throw error;
}
