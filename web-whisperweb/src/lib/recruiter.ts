import { supabase } from "@/lib/supabase";
import { BACKEND_URL } from "@/lib/billing";
import type { WhisperProfile } from "@/lib/types";

export type PromotableRole = "coach" | "athlete" | "creator";

export type ProspectStatus =
  | "discovered"
  | "contacted"
  | "interested"
  | "meeting"
  | "ready"
  | "passed";

export interface Prospect {
  /** Private account metadata, not a Supabase column. */
  client?: import('./recruiterClients').RecruiterClient;
  id: string;
  recruiter_id: string;
  prospect_user_id: string | null;
  prospect_username: string | null;
  prospect_display_name: string | null;
  prospect_image_url: string | null;
  source: string | null;
  location: string | null;
  niche: string | null;
  instagram: string | null;
  tiktok: string | null;
  suggested_role: PromotableRole | null;
  status: ProspectStatus;
  notes: string | null;
  rating: number | null;
  contact_log: { date: string; method: string; note: string }[];
  /** v4 — talent-pool tags. */
  tags?: string[] | null;
  /** v4 — the next-action discipline: what's next and when it's due. */
  next_action?: string | null;
  next_action_due?: string | null;
  last_touch_at?: string | null;
  /** v4 — structured scorecard: criterion id → 1–5. */
  scorecard?: Record<string, number> | null;
  created_at: string | null;
  updated_at: string | null;
}

/** v4 — the four researched scorecard criteria (1–5 stars each). */
export const SCORECARD_CRITERIA: { id: string; label: string }[] = [
  { id: "talent", label: "Talent" },
  { id: "drive", label: "Drive" },
  { id: "coachability", label: "Coachability" },
  { id: "audience", label: "Audience" },
];

/** v4 — next-action presets shown in the drawer + Today queue. */
export const NEXT_ACTION_PRESETS: { id: string; label: string; kind: ActivityKind }[] = [
  { id: "dm", label: "Send a DM", kind: "dm" },
  { id: "call", label: "Call them", kind: "call" },
  { id: "meeting", label: "Set a meeting", kind: "meeting" },
  { id: "followup", label: "Follow up", kind: "task" },
];

export type ActivityKind =
  | "note"
  | "call"
  | "dm"
  | "email"
  | "meeting"
  | "stage"
  | "task";

export interface ProspectActivity {
  id: string;
  prospect_id: string;
  recruiter_id: string;
  kind: ActivityKind;
  body: string;
  created_at: string | null;
}

/** Timeline rows for one prospect, newest first. [] when v4 isn't migrated. */
export async function fetchProspectActivities(
  prospectId: string
): Promise<ProspectActivity[]> {
  const { data, error } = await supabase
    .from("whisper_prospect_activities")
    .select("*")
    .eq("prospect_id", prospectId)
    .order("created_at", { ascending: false })
    .limit(100);
  if (error) return [];
  return (data as ProspectActivity[] | null) ?? [];
}

/** Log one touchpoint and stamp last_touch_at. Throws when v4 is missing. */
export async function addProspectActivity(
  recruiterId: string,
  prospectId: string,
  kind: ActivityKind,
  body: string
): Promise<void> {
  const { error } = await supabase.from("whisper_prospect_activities").insert({
    prospect_id: prospectId,
    recruiter_id: recruiterId,
    kind,
    body: body.slice(0, 800),
  });
  if (error) throw error;
  await supabase
    .from("whisper_recruiter_prospects")
    .update({
      last_touch_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    })
    .eq("id", prospectId);
}

/** True when supabase/recruiting-v4.sql hasn't been applied yet. */
export async function probeRecruitingV4(): Promise<boolean> {
  const { error } = await supabase
    .from("whisper_recruiter_prospects")
    .select("tags")
    .limit(1);
  return !error;
}

export const PROSPECT_STATUS_LABELS: Record<ProspectStatus, string> = {
  discovered: "Discovered",
  contacted: "Contacted",
  interested: "Interested",
  meeting: "Meeting",
  ready: "Ready to promote",
  passed: "Passed",
};

export const PROSPECT_STATUS_COLORS: Record<ProspectStatus, string> = {
  discovered: "#6b7280",
  contacted: "#3b82f6",
  interested: "#a855f7",
  meeting: "#f59e0b",
  ready: "#22c55e",
  passed: "#ef4444",
};

export interface ProspectInput {
  prospectUsername?: string;
  prospectDisplayName?: string;
  prospectImageUrl?: string;
  prospectUserId?: string;
  source?: string;
  location?: string;
  niche?: string;
  instagram?: string;
  tiktok?: string;
  suggestedRole?: PromotableRole;
  notes?: string;
  rating?: number;
}

export interface RecruiterPromotion {
  id: string;
  recruiter_id: string;
  recruiter_username: string | null;
  promoted_id: string;
  promoted_username: string;
  role: PromotableRole;
  notes: string | null;
  created_at: string | null;
}

export interface RecruiterApplication {
  id: string;
  user_id: string;
  username: string;
  email: string | null;
  full_name: string;
  region: string | null;
  experience: string | null;
  bio: string | null;
  social: string | null;
  status: "pending" | "approved" | "denied" | "none";
  created_at: string | null;
}

/**
 * Best-effort profile photo for a prospect from their Instagram handle,
 * via the unavatar.io proxy (Instagram blocks direct scraping). Returns
 * null when there's no usable handle; `fallback=false` 404s when the
 * account has no public photo so the UI's monogram shows instead.
 */
export function instagramAvatarUrl(
  handle: string | null | undefined
): string | null {
  const clean = (handle ?? "")
    .trim()
    .replace(/^@/, "")
    .replace(/^https?:\/\/(www\.)?instagram\.com\//i, "")
    .replace(/[/?#].*$/, "");
  if (!clean || !/^[a-zA-Z0-9._]{1,30}$/.test(clean)) return null;
  return `https://unavatar.io/instagram/${encodeURIComponent(clean)}?fallback=false`;
}

/** A prospect's public Instagram gallery, resolved server-side. */
export interface InstagramGallery {
  handle: string;
  fullName: string | null;
  profilePic: string | null;
  followers: number | null;
  photos: string[];
}

const igGalleryCache = new Map<string, InstagramGallery | null>();

/**
 * Recent public photos for a prospect's Instagram handle via the project
 * backend (`/ig/photos`) — so recruiters can show the team what a prospect
 * looks like while presenting. Returns null when the profile is private,
 * blocked, or the handle is unusable; callers fall back to
 * `instagramAvatarUrl`. Results are memoized per session.
 */
export async function fetchInstagramGallery(
  handle: string | null | undefined
): Promise<InstagramGallery | null> {
  const clean = (handle ?? "")
    .trim()
    .replace(/^@/, "")
    .replace(/^https?:\/\/(www\.)?instagram\.com\//i, "")
    .replace(/[/?#].*$/, "")
    .toLowerCase();
  if (!clean || !/^[a-z0-9._]{1,30}$/.test(clean)) return null;
  if (igGalleryCache.has(clean)) return igGalleryCache.get(clean) ?? null;
  try {
    const { data } = await supabase.auth.getSession();
    const token = data.session?.access_token;
    if (!token) return null;
    const res = await fetch(
      `${BACKEND_URL}/ig/photos?handle=${encodeURIComponent(clean)}`,
      { headers: { Authorization: `Bearer ${token}` } }
    );
    if (!res.ok) {
      igGalleryCache.set(clean, null);
      return null;
    }
    const parsed = (await res.json()) as {
      ok?: boolean;
      fullName?: string | null;
      profilePic?: string | null;
      followers?: number | null;
      photos?: string[];
    };
    const gallery: InstagramGallery | null = parsed.ok
      ? {
          handle: clean,
          fullName: parsed.fullName ?? null,
          profilePic: parsed.profilePic ?? null,
          followers: parsed.followers ?? null,
          photos: Array.isArray(parsed.photos) ? parsed.photos.slice(0, 12) : [],
        }
      : null;
    igGalleryCache.set(clean, gallery);
    return gallery;
  } catch {
    return null;
  }
}

/** Check if the signed-in user has the recruiter role. */
export async function isRecruiter(userId: string): Promise<boolean> {
  const { data } = await supabase
    .from("whisper_profiles")
    .select("is_recruiter")
    .eq("user_id", userId)
    .maybeSingle();
  return !!(data as { is_recruiter?: boolean } | null)?.is_recruiter;
}

/** Submit a recruiter application. */
export async function submitRecruiterApplication(input: {
  userId: string;
  username: string;
  email: string;
  fullName: string;
  region: string;
  experience: string;
  bio: string;
  social: string;
}): Promise<void> {
  const { error } = await supabase
    .from("whisper_recruiter_applications")
    .insert({
      user_id: input.userId,
      username: input.username,
      email: input.email || null,
      full_name: input.fullName,
      region: input.region,
      experience: input.experience,
      bio: input.bio,
      social: input.social || null,
      status: "pending",
    });
  if (error) throw error;
}

/** Fetch the signed-in user's recruiter application status. */
export async function fetchRecruiterApplication(
  userId: string
): Promise<RecruiterApplication | null> {
  const { data } = await supabase
    .from("whisper_recruiter_applications")
    .select("*")
    .eq("user_id", userId)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (!data) return null;
  const row = data as Omit<RecruiterApplication, "status"> & {
    status: string;
  };
  return {
    ...row,
    status:
      row.status === "pending" ||
      row.status === "approved" ||
      row.status === "denied"
        ? row.status
        : "none",
  } as RecruiterApplication;
}

/** Fetch all promotions by this recruiter. */
export async function fetchMyPromotions(
  recruiterId: string
): Promise<RecruiterPromotion[]> {
  const { data } = await supabase
    .from("whisper_recruiter_promotions")
    .select("*")
    .eq("recruiter_id", recruiterId)
    .order("created_at", { ascending: false });
  return (data as RecruiterPromotion[] | null) ?? [];
}

/** Promote a user to a role — inserts a promotion record and flips the profile flag. */
export async function promoteUser(input: {
  recruiterId: string;
  recruiterUsername: string;
  promotedId: string;
  promotedUsername: string;
  role: PromotableRole;
  notes?: string;
}): Promise<void> {
  // Insert the promotion record
  const { error: promoError } = await supabase
    .from("whisper_recruiter_promotions")
    .upsert(
      {
        recruiter_id: input.recruiterId,
        recruiter_username: input.recruiterUsername,
        promoted_id: input.promotedId,
        promoted_username: input.promotedUsername,
        role: input.role,
        notes: input.notes ?? null,
      },
      { onConflict: "promoted_id,role" }
    );
  if (promoError) throw promoError;

  // Flip the profile flag
  const flagMap: Record<PromotableRole, string> = {
    coach: "is_coach",
    athlete: "is_athlete",
    creator: "is_verified",
  };
  const { error: flagError } = await supabase
    .from("whisper_profiles")
    .update({ [flagMap[input.role]]: true })
    .eq("user_id", input.promotedId);
  if (flagError) throw flagError;
}

/** Remove a promotion — unsets the profile flag and deletes the record. */
export async function removePromotion(
  recruiterId: string,
  promotionId: string,
  promotedId: string,
  role: PromotableRole
): Promise<void> {
  const { error: deleteError } = await supabase
    .from("whisper_recruiter_promotions")
    .delete()
    .eq("id", promotionId)
    .eq("recruiter_id", recruiterId);
  if (deleteError) throw deleteError;

  // Unset the flag only if no other recruiter also promoted this role
  const { data: remaining } = await supabase
    .from("whisper_recruiter_promotions")
    .select("id")
    .eq("promoted_id", promotedId)
    .eq("role", role)
    .limit(1);
  if (!remaining || remaining.length === 0) {
    const flagMap: Record<PromotableRole, string> = {
      coach: "is_coach",
      athlete: "is_athlete",
      creator: "is_verified",
    };
    await supabase
      .from("whisper_profiles")
      .update({ [flagMap[role]]: false })
      .eq("user_id", promotedId);
  }
}

/** Search profiles for promotion — returns users matching the query. */
export async function searchForPromotion(
  query: string
): Promise<WhisperProfile[]> {
  if (query.trim().length < 1) return [];
  const { data } = await supabase
    .from("whisper_profiles")
    .select("*")
    .ilike("username", `%${query.trim()}%`)
    .limit(20);
  return (data as WhisperProfile[] | null) ?? [];
}

// ---------------------------------------------------------------------------
// Prospect pipeline
// ---------------------------------------------------------------------------

/** Fetch all prospects for a recruiter. Prospects without a stored photo
 *  get their Instagram profile picture filled in automatically. */
export async function fetchProspects(
  recruiterId: string
): Promise<Prospect[]> {
  const { data } = await supabase
    .from("whisper_recruiter_prospects")
    .select("*")
    .eq("recruiter_id", recruiterId)
    .order("updated_at", { ascending: false });
  return ((data as Prospect[] | null) ?? []).map((p) => ({
    ...p,
    prospect_image_url: p.prospect_image_url ?? instagramAvatarUrl(p.instagram),
  }));
}

/** Create a new prospect in the pipeline. */
export async function createProspect(
  recruiterId: string,
  input: ProspectInput
): Promise<void> {
  const { error } = await supabase
    .from("whisper_recruiter_prospects")
    .insert({
      recruiter_id: recruiterId,
      prospect_user_id: input.prospectUserId ?? null,
      prospect_username: input.prospectUsername ?? null,
      prospect_display_name: input.prospectDisplayName ?? null,
      // No photo supplied → pull their Instagram profile picture.
      prospect_image_url:
        input.prospectImageUrl ?? instagramAvatarUrl(input.instagram) ?? null,
      source: input.source ?? null,
      location: input.location ?? null,
      niche: input.niche ?? null,
      instagram: input.instagram ?? null,
      tiktok: input.tiktok ?? null,
      suggested_role: input.suggestedRole ?? null,
      notes: input.notes ?? null,
      rating: input.rating ?? null,
      status: "discovered",
    });
  if (error) throw error;
}

/** Update a prospect's fields. */
export async function updateProspect(
  prospectId: string,
  updates: Partial<
    Pick<
      Prospect,
      | "status"
      | "notes"
      | "rating"
      | "location"
      | "niche"
      | "instagram"
      | "tiktok"
      | "suggested_role"
      | "prospect_display_name"
      | "prospect_image_url"
      | "prospect_user_id"
      | "tags"
      | "next_action"
      | "next_action_due"
      | "last_touch_at"
      | "scorecard"
    >
  >
): Promise<void> {
  const { error } = await supabase
    .from("whisper_recruiter_prospects")
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq("id", prospectId);
  if (error) throw error;
}

/** Delete a prospect from the pipeline. */
export async function deleteProspect(prospectId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_recruiter_prospects")
    .delete()
    .eq("id", prospectId);
  if (error) throw error;
}

/** Add a contact log entry to a prospect. */
export async function addContactLog(
  prospectId: string,
  method: string,
  note: string
): Promise<void> {
  const { data: existing } = await supabase
    .from("whisper_recruiter_prospects")
    .select("contact_log")
    .eq("id", prospectId)
    .maybeSingle();
  const log = (existing as { contact_log?: { date: string; method: string; note: string }[] } | null)?.contact_log ?? [];
  const entry = { date: new Date().toISOString(), method, note };
  const { error } = await supabase
    .from("whisper_recruiter_prospects")
    .update({ contact_log: [...log, entry], updated_at: new Date().toISOString() })
    .eq("id", prospectId);
  if (error) throw error;
}

// ---------------------------------------------------------------------------
// Pipeline auto-linking — applicant questionnaires and meeting notes file
// themselves into the recruiter's prospect pipeline automatically.
// ---------------------------------------------------------------------------

interface ContactLogEntry {
  date: string;
  method: string;
  note: string;
}

/**
 * Find or create the prospect row for a person this recruiter is working —
 * matched by linked account first, then username. Returns the prospect id,
 * or null when the row couldn't be created.
 */
export async function ensureProspect(
  recruiterId: string,
  input: {
    userId?: string | null;
    username?: string | null;
    displayName?: string | null;
    imageUrl?: string | null;
    source?: string;
    status?: ProspectStatus;
    notes?: string;
  }
): Promise<string | null> {
  const username = (input.username ?? "").trim().replace(/^@/, "");

  if (input.userId) {
    const { data } = await supabase
      .from("whisper_recruiter_prospects")
      .select("id")
      .eq("recruiter_id", recruiterId)
      .eq("prospect_user_id", input.userId)
      .limit(1)
      .maybeSingle();
    const found = (data as { id: string } | null)?.id;
    if (found) return found;
  }

  if (username) {
    const { data } = await supabase
      .from("whisper_recruiter_prospects")
      .select("id, prospect_user_id")
      .eq("recruiter_id", recruiterId)
      .ilike("prospect_username", username)
      .limit(1)
      .maybeSingle();
    const row = data as { id: string; prospect_user_id: string | null } | null;
    if (row) {
      // Backfill the account link when the username row wasn't linked yet.
      if (input.userId && !row.prospect_user_id) {
        await supabase
          .from("whisper_recruiter_prospects")
          .update({
            prospect_user_id: input.userId,
            updated_at: new Date().toISOString(),
          })
          .eq("id", row.id);
      }
      return row.id;
    }
  }

  const { data: created, error } = await supabase
    .from("whisper_recruiter_prospects")
    .insert({
      recruiter_id: recruiterId,
      prospect_user_id: input.userId ?? null,
      prospect_username: username || null,
      prospect_display_name: input.displayName ?? (username || null),
      prospect_image_url: input.imageUrl ?? null,
      source: input.source ?? null,
      notes: input.notes ?? null,
      status: input.status ?? "discovered",
    })
    .select("id")
    .single();
  if (error) return null;
  return (created as { id: string }).id;
}

/** Append a contact-log entry once — the marker keeps reruns idempotent. */
export async function addContactLogOnce(
  prospectId: string,
  method: string,
  note: string,
  marker: string
): Promise<boolean> {
  const { data } = await supabase
    .from("whisper_recruiter_prospects")
    .select("contact_log")
    .eq("id", prospectId)
    .maybeSingle();
  const log =
    (data as { contact_log?: ContactLogEntry[] } | null)?.contact_log ?? [];
  if (log.some((e) => (e.note ?? "").includes(marker))) return false;
  const entry: ContactLogEntry = {
    date: new Date().toISOString(),
    method,
    note,
  };
  const { error } = await supabase
    .from("whisper_recruiter_prospects")
    .update({
      contact_log: [...log, entry],
      updated_at: new Date().toISOString(),
    })
    .eq("id", prospectId);
  return !error;
}

/**
 * Link an applicant questionnaire response to this recruiter's pipeline —
 * creates the prospect when they aren't in it yet and files the application
 * as a contact-log entry (idempotent per response).
 */
export async function linkApplicationToProspect(
  recruiterId: string,
  response: {
    id: string;
    applicant_user_id: string | null;
    applicant_name: string | null;
    applicant_email: string | null;
    best_position: string | null;
    potential_score: number | null;
  }
): Promise<boolean> {
  const marker = `[application:${response.id}]`;

  // Resolve the applicant's Whisper profile when they signed up first.
  let username: string | null = null;
  let displayName: string | null =
    (response.applicant_name ?? "").trim() || null;
  let imageUrl: string | null = null;
  if (response.applicant_user_id) {
    const { data } = await supabase
      .from("whisper_profiles")
      .select("username, display_name, profile_image_url")
      .eq("user_id", response.applicant_user_id)
      .maybeSingle();
    const p = data as {
      username?: string;
      display_name?: string | null;
      profile_image_url?: string | null;
    } | null;
    if (p?.username) username = p.username;
    if (p?.display_name) displayName = p.display_name;
    imageUrl = p?.profile_image_url ?? null;
  }
  if (!username && !displayName && !response.applicant_email) return false;

  const fit = response.best_position
    ? `Best fit: ${response.best_position}${
        response.potential_score != null
          ? ` · potential ${Math.round(response.potential_score)}/100`
          : ""
      }.`
    : "";
  const prospectId = await ensureProspect(recruiterId, {
    userId: response.applicant_user_id,
    username,
    displayName,
    imageUrl,
    source: "application",
    status: "interested",
    notes: `Applied via questionnaire. ${fit}`.trim(),
  });
  if (!prospectId) return false;
  return addContactLogOnce(
    prospectId,
    "application",
    `${marker} Submitted the applicant questionnaire${
      response.applicant_email ? ` (${response.applicant_email})` : ""
    }. ${fit}`.trim(),
    marker
  );
}

/**
 * File a finished meeting's AI notes onto every participant's prospect
 * profile — creating pipeline rows for people who aren't prospects yet.
 * Returns how many profiles were updated.
 */
export async function attachMeetingNotesToProspects(
  recruiterId: string,
  participants: { user_id: string; username: string }[],
  meeting: { id: string; title: string },
  notes: string
): Promise<number> {
  const marker = `[meeting:${meeting.id}]`;
  const trimmed = notes.trim().slice(0, 1400);
  if (!trimmed) return 0;
  let attached = 0;
  for (const p of participants.slice(0, 12)) {
    if (!p.user_id || p.user_id === recruiterId) continue;
    try {
      const prospectId = await ensureProspect(recruiterId, {
        userId: p.user_id,
        username: p.username,
        displayName: p.username,
        source: "meeting",
        status: "meeting",
        notes: `Met in "${meeting.title}".`,
      });
      if (!prospectId) continue;
      const added = await addContactLogOnce(
        prospectId,
        "meeting",
        `${marker} Notes from "${meeting.title}":\n${trimmed}`,
        marker
      );
      if (added) attached += 1;
    } catch {
      /* per-participant best effort */
    }
  }
  return attached;
}

// ---------------------------------------------------------------------------
// Recruitment targets — monthly goals per role
// ---------------------------------------------------------------------------

export interface RecruitmentTarget {
  id: string;
  recruiter_id: string;
  period: string;
  target_coach: number;
  target_athlete: number;
  target_creator: number;
  notes: string | null;
  created_at: string | null;
  updated_at: string | null;
}

/** Get the current month period string (e.g. "2026-07"). */
export function currentPeriod(): string {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, "0")}`;
}

/** Fetch a recruiter's target for a given period (defaults to current month). */
export async function fetchTarget(
  recruiterId: string,
  period: string = currentPeriod()
): Promise<RecruitmentTarget | null> {
  const { data } = await supabase
    .from("whisper_recruiter_targets")
    .select("*")
    .eq("recruiter_id", recruiterId)
    .eq("period", period)
    .maybeSingle();
  return (data as RecruitmentTarget | null) ?? null;
}

/** Create or update a recruitment target. */
export async function saveTarget(
  recruiterId: string,
  period: string,
  targets: { coach: number; athlete: number; creator: number },
  notes?: string
): Promise<void> {
  const { error } = await supabase
    .from("whisper_recruiter_targets")
    .upsert(
      {
        recruiter_id: recruiterId,
        period,
        target_coach: targets.coach,
        target_athlete: targets.athlete,
        target_creator: targets.creator,
        notes: notes?.trim() || null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "recruiter_id,period" }
    );
  if (error) throw error;
}

// ---------------------------------------------------------------------------
// Referral codes — shareable signup codes for recruiters
// ---------------------------------------------------------------------------

export interface ReferralCode {
  id: string;
  recruiter_id: string;
  code: string;
  uses: number;
  created_at: string | null;
}

/** Generate a random 6-character alphanumeric code. */
function generateCode(): string {
  const chars = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";
  let code = "";
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

/** Fetch or create a recruiter's referral code. */
export async function fetchOrCreateReferralCode(
  recruiterId: string,
  username: string
): Promise<ReferralCode> {
  const { data: existing } = await supabase
    .from("whisper_referral_codes")
    .select("*")
    .eq("recruiter_id", recruiterId)
    .maybeSingle();
  if (existing) return existing as ReferralCode;

  // Generate a unique code based on username + random suffix
  const prefix = username.replace(/[^a-zA-Z]/g, "").slice(0, 3).toUpperCase() || "WSP";
  const code = `${prefix}${generateCode().slice(0, 3)}`;
  const { data, error } = await supabase
    .from("whisper_referral_codes")
    .insert({
      recruiter_id: recruiterId,
      code,
    })
    .select("*")
    .single();
  if (error) throw error;
  return data as ReferralCode;
}

// ---------------------------------------------------------------------------
// Territories — the regions a recruiter covers, shown on the territory map
// ---------------------------------------------------------------------------

export type TerritoryRegion =
  | "northeast"
  | "southeast"
  | "midwest"
  | "southwest"
  | "west"
  | "northwest"
  | "international"
  | "other";

export const TERRITORY_REGION_LABELS: Record<TerritoryRegion, string> = {
  northeast: "Northeast",
  southeast: "Southeast",
  midwest: "Midwest",
  southwest: "Southwest",
  west: "West Coast",
  northwest: "Northwest",
  international: "International",
  other: "Other",
};

export const TERRITORY_REGION_COLORS: Record<TerritoryRegion, string> = {
  northeast: "#3b82f6",
  southeast: "#f59e0b",
  midwest: "#22c55e",
  southwest: "#ef4444",
  west: "#a855f7",
  northwest: "#06b6d4",
  international: "#ec4899",
  other: "#6b7280",
};

export interface Territory {
  id: string;
  recruiter_id: string;
  name: string;
  region: TerritoryRegion;
  cities: string | null;
  notes: string | null;
  color: string | null;
  created_at: string | null;
}

/** Fetch a recruiter's territories. */
export async function fetchTerritories(
  recruiterId: string
): Promise<Territory[]> {
  const { data } = await supabase
    .from("whisper_recruiter_territories")
    .select("*")
    .eq("recruiter_id", recruiterId)
    .order("created_at", { ascending: true });
  return (data as Territory[] | null) ?? [];
}

/** Claim a new territory. */
export async function createTerritory(
  recruiterId: string,
  input: { name: string; region: TerritoryRegion; cities?: string; notes?: string }
): Promise<void> {
  const { error } = await supabase
    .from("whisper_recruiter_territories")
    .insert({
      recruiter_id: recruiterId,
      name: input.name,
      region: input.region,
      cities: input.cities?.trim() || null,
      notes: input.notes?.trim() || null,
      color: TERRITORY_REGION_COLORS[input.region],
    });
  if (error) throw error;
}

/** Release a territory. */
export async function deleteTerritory(territoryId: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_recruiter_territories")
    .delete()
    .eq("id", territoryId);
  if (error) throw error;
}

/**
 * Count prospects whose location matches a territory (by territory name or
 * one of its listed cities, case-insensitive substring).
 */
export function prospectCountForTerritory(
  territory: Territory,
  prospects: Prospect[]
): number {
  const needles = [territory.name.toLowerCase()];
  for (const c of (territory.cities ?? "").split(",")) {
    const t = c.trim().toLowerCase();
    if (t) needles.push(t);
  }
  return prospects.filter((p) => {
    const loc = (p.location ?? "").toLowerCase();
    if (!loc) return false;
    return needles.some((n) => loc.includes(n) || n.includes(loc));
  }).length;
}

// ---------------------------------------------------------------------------
// Recruiter group identity — name and photo used on the globe pins
// ---------------------------------------------------------------------------

export interface RecruiterGroup {
  id: string;
  recruiter_id: string;
  name: string;
  photo_url: string | null;
}

export async function fetchRecruiterGroup(
  recruiterId: string
): Promise<RecruiterGroup | null> {
  const { data } = await supabase
    .from("whisper_recruiter_groups")
    .select("id, recruiter_id, name, photo_url")
    .eq("recruiter_id", recruiterId)
    .maybeSingle();
  return (data as RecruiterGroup | null) ?? null;
}

export async function upsertRecruiterGroup(
  recruiterId: string,
  input: { name?: string; photo_url?: string | null }
): Promise<void> {
  const { error } = await supabase
    .from("whisper_recruiter_groups")
    .upsert(
      {
        recruiter_id: recruiterId,
        name: input.name?.trim() || "My Recruiting Group",
        photo_url: input.photo_url ?? null,
        updated_at: new Date().toISOString(),
      },
      { onConflict: "recruiter_id" }
    );
  if (error) throw error;
}

// ---------------------------------------------------------------------------
// Pipeline funnel analytics
// ---------------------------------------------------------------------------

export interface PipelineFunnel {
  discovered: number;
  contacted: number;
  interested: number;
  meeting: number;
  ready: number;
  promoted: number;
  passed: number;
}

/** Compute funnel stats from prospects + promotions. */
export function computeFunnel(
  prospects: Prospect[],
  promotions: RecruiterPromotion[]
): PipelineFunnel {
  const funnel: PipelineFunnel = {
    discovered: 0,
    contacted: 0,
    interested: 0,
    meeting: 0,
    ready: 0,
    promoted: promotions.length,
    passed: 0,
  };
  for (const p of prospects) {
    if (p.status === "passed") {
      funnel.passed++;
      continue;
    }
    if (p.status === "discovered") funnel.discovered++;
    else if (p.status === "contacted") funnel.contacted++;
    else if (p.status === "interested") funnel.interested++;
    else if (p.status === "meeting") funnel.meeting++;
    else if (p.status === "ready") funnel.ready++;
  }
  return funnel;
}
