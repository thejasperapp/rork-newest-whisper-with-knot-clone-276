import { supabase } from "@/lib/supabase";
import { createGroupThread, fetchMyGroupThreads, type GroupThread, type GroupPerson } from "@/lib/groupChats";

/**
 * Whisper Business+ — the business workspace plan.
 *
 * The Stripe webhook writes the plan ledger (whisper_business_plus); this
 * client reads entitlement, manages the team + roles, custom hiring
 * questionnaires with auto-matching, the private HQ group, the team chat,
 * and the internal calendar. Migration: supabase/business-plus.sql.
 */

export interface BusinessPlusRow {
  id: string;
  user_id: string;
  email: string | null;
  plan: string;
  status: string;
  company_name: string | null;
  created_at: string | null;
}

export interface BusinessTeamRow {
  business_id: string;
  user_id: string;
  username: string;
  role_title: string;
  accent: string;
  added_at: string | null;
}

export interface BusinessPositionRow {
  id: string;
  business_id: string;
  title: string;
  blurb: string;
  keywords: string[];
  is_open: boolean;
  created_at: string | null;
}

export interface BusinessQuestionRow {
  id: string;
  business_id: string;
  prompt: string;
  kind: "text" | "textarea" | "select";
  options: string[];
  display_order: number;
  is_active: boolean;
}

export interface BusinessAnswer {
  prompt: string;
  answer: string;
}

export interface BusinessApplicationRow {
  id: string;
  business_id: string;
  applicant_id: string;
  applicant_username: string;
  answers: BusinessAnswer[];
  best_position: string | null;
  position_scores: Record<string, number>;
  match_score: number;
  status: "new" | "shortlist" | "passed";
  created_at: string | null;
}

/** The caller's Business+ context — owner of a plan, or on someone's team. */
export interface MyBusinessPlus {
  business: BusinessPlusRow;
  isOwner: boolean;
  roleTitle: string;
}

/** Accent choices for team roles — the badge-system palette. */
export const ROLE_ACCENTS: string[] = [
  "#5A5FE8", "#0E9F76", "#E8853D", "#7059E8", "#D5484F", "#218CF5", "#D9408C", "#8C6A3F",
];

export async function fetchMyBusinessPlus(userId: string): Promise<MyBusinessPlus | null> {
  const { data: own, error } = await supabase
    .from("whisper_business_plus")
    .select("*")
    .eq("user_id", userId)
    .eq("status", "active")
    .order("updated_at", { ascending: false })
    .limit(1);
  if (error) throw new Error("Couldn't check your team access. Please try again.");
  const owned = (own as BusinessPlusRow[] | null)?.[0];
  if (owned) return { business: owned, isOwner: true, roleTitle: "Owner" };

  const { data: teamRows, error: teamError } = await supabase
    .from("whisper_business_team")
    .select("*")
    .eq("user_id", userId)
    .limit(500);
  if (teamError) throw new Error("Couldn't check your team membership. Please try again.");
  const seats = (teamRows as BusinessTeamRow[] | null) ?? [];
  if (!seats.length) return null;
  const { data: biz, error: businessError } = await supabase
    .from("whisper_business_plus")
    .select("*")
    .in("user_id", seats.map((seat) => seat.business_id))
    .eq("status", "active")
    .order("updated_at", { ascending: false })
    .limit(1);
  if (businessError) throw new Error("Couldn't load your team's Business+ plan. Please try again.");
  const row = (biz as BusinessPlusRow[] | null)?.[0];
  if (!row) return null;
  return { business: row, isOwner: false, roleTitle: seats.find((seat) => seat.business_id === row.user_id)?.role_title ?? "Team member" };
}

export async function setCompanyName(rowId: string, name: string): Promise<void> {
  const { data, error } = await supabase
    .from("whisper_business_plus")
    .update({ company_name: name.trim() })
    .eq("id", rowId).select("id");
  if (error || !data?.length) throw new Error("Couldn't save the company name. Refresh your team access and try again.");
}

// ─── Team & roles ───────────────────────────────────────────────────────────

export async function fetchTeam(businessId: string): Promise<BusinessTeamRow[]> {
  const { data, error } = await supabase
    .from("whisper_business_team")
    .select("*")
    .eq("business_id", businessId)
    .order("added_at", { ascending: true });
  if (error) throw new Error("Couldn't load the team. Please try again.");
  return (data as BusinessTeamRow[] | null) ?? [];
}

export async function addTeamMember(input: {
  businessId: string;
  username: string;
  roleTitle: string;
  accent: string;
}): Promise<void> {
  const handle = input.username.trim().replace(/^@/, "").toLowerCase();
  if (!handle) throw new Error("Type a @username.");
  const { data, error: lookupError } = await supabase
    .from("whisper_profiles")
    .select("user_id, username")
    .ilike("username", handle.replace(/[\\%_]/g, "\\$&"))
    .limit(1)
    .maybeSingle();
  const person = data as { user_id: string; username: string } | null;
  if (lookupError) throw new Error("Couldn't look up that username. Please try again.");
  if (!person || person.username.toLowerCase() !== handle) throw new Error(`No one named @${handle} on Whisper.`);
  if (person.user_id === input.businessId) throw new Error("That's you — the owner is already in.");
  const { data: saved, error } = await supabase.from("whisper_business_team").upsert(
    {
      business_id: input.businessId,
      user_id: person.user_id,
      username: person.username,
      role_title: input.roleTitle.trim() || "Team member",
      accent: input.accent,
    },
    { onConflict: "business_id,user_id" }
  ).select("user_id");
  if (error || !saved?.some((row) => row.user_id === person.user_id)) {
    throw new Error("Couldn't confirm the team member was saved. Refresh the team before trying again.");
  }
}

export async function updateTeamMember(
  businessId: string,
  userId: string,
  patch: { role_title?: string; accent?: string }
): Promise<void> {
  const { data, error } = await supabase
    .from("whisper_business_team")
    .update(patch)
    .eq("business_id", businessId)
    .eq("user_id", userId).select("user_id");
  if (error || !data?.length) throw new Error("Couldn't update the role. Refresh your team access and try again.");
}

export async function removeTeamMember(businessId: string, userId: string): Promise<void> {
  const { data, error } = await supabase
    .from("whisper_business_team")
    .delete()
    .eq("business_id", businessId)
    .eq("user_id", userId).select("user_id");
  if (error || !data?.length) throw new Error("Couldn't confirm removal. Refresh the team before trying again.");
}

// ─── Positions + custom questions ───────────────────────────────────────────

export async function fetchPositions(businessId: string): Promise<BusinessPositionRow[]> {
  const { data, error } = await supabase
    .from("whisper_business_positions")
    .select("*")
    .eq("business_id", businessId)
    .order("created_at", { ascending: true });
  if (error) return [];
  return (data as BusinessPositionRow[] | null) ?? [];
}

export async function savePosition(input: {
  id?: string;
  businessId: string;
  title: string;
  blurb: string;
  keywords: string[];
  isOpen: boolean;
}): Promise<void> {
  const row = {
    business_id: input.businessId,
    title: input.title.trim(),
    blurb: input.blurb.trim(),
    keywords: input.keywords.map((k) => k.trim().toLowerCase()).filter(Boolean),
    is_open: input.isOpen,
  };
  const { error } = input.id
    ? await supabase.from("whisper_business_positions").update(row).eq("id", input.id)
    : await supabase.from("whisper_business_positions").insert(row);
  if (error) {
    if (error.code === "42P01") throw new Error("Run supabase/business-plus.sql once to unlock hiring.");
    throw new Error("Couldn't save the position.");
  }
}

export async function deletePosition(id: string): Promise<void> {
  await supabase.from("whisper_business_positions").delete().eq("id", id);
}

export async function fetchQuestions(businessId: string): Promise<BusinessQuestionRow[]> {
  const { data, error } = await supabase
    .from("whisper_business_questions")
    .select("*")
    .eq("business_id", businessId)
    .order("display_order", { ascending: true });
  if (error) return [];
  return (data as BusinessQuestionRow[] | null) ?? [];
}

export async function saveQuestion(input: {
  id?: string;
  businessId: string;
  prompt: string;
  kind?: "text" | "textarea" | "select";
  options?: string[];
  displayOrder: number;
  isActive?: boolean;
}): Promise<void> {
  const row = {
    business_id: input.businessId,
    prompt: input.prompt.trim(),
    kind: input.kind ?? "textarea",
    options: input.options ?? [],
    display_order: input.displayOrder,
    is_active: input.isActive ?? true,
  };
  const { error } = input.id
    ? await supabase.from("whisper_business_questions").update(row).eq("id", input.id)
    : await supabase.from("whisper_business_questions").insert(row);
  if (error) {
    if (error.code === "42P01") throw new Error("Run supabase/business-plus.sql once to unlock hiring.");
    throw new Error("Couldn't save the question.");
  }
}

export async function deleteQuestion(id: string): Promise<void> {
  await supabase.from("whisper_business_questions").delete().eq("id", id);
}

/** Starter questions offered when a business hasn't written any yet. */
export const STARTER_QUESTIONS: string[] = [
  "Tell us about yourself — what do you do best?",
  "Why do you want to work with us?",
  "What relevant experience do you have?",
  "When could you start, and what availability do you have?",
];

// ─── Applications + auto-match ──────────────────────────────────────────────

function escapeRegex(s: string): string {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

function keywordHit(needle: string, keyword: string): boolean {
  const k = keyword.trim().toLowerCase();
  if (!k) return false;
  try {
    return new RegExp(`(^|[^a-z0-9])${escapeRegex(k)}[a-z]{0,4}($|[^a-z0-9])`).test(needle);
  } catch {
    return needle.includes(k);
  }
}

/**
 * Auto-match: scores the applicant's combined answers against every OPEN
 * position's keywords (word-boundary hits) with a boost when they name the
 * role outright. Returns per-position scores + the best fit.
 */
export function scoreAgainstPositions(
  answersText: string,
  positions: BusinessPositionRow[]
): { scores: Record<string, number>; best: string | null; matchScore: number } {
  const needle = ` ${answersText.toLowerCase()} `;
  const scores: Record<string, number> = {};
  for (const p of positions.filter((pos) => pos.is_open)) {
    const kws = p.keywords.length > 0 ? p.keywords : p.title.toLowerCase().split(/\s+/).filter(Boolean);
    let hits = 0;
    for (const k of kws) if (keywordHit(needle, k)) hits += 1;
    const base = kws.length > 0 ? Math.round((hits / kws.length) * 70) : 0;
    const titleBoost = needle.includes(p.title.toLowerCase()) ? 30 : 0;
    scores[p.title] = Math.min(100, base + titleBoost);
  }
  const ranked = Object.entries(scores).sort((a, b) => b[1] - a[1]);
  return {
    scores,
    best: ranked[0] && ranked[0][1] > 0 ? ranked[0][0] : (ranked[0]?.[0] ?? null),
    matchScore: ranked[0]?.[1] ?? 0,
  };
}

export async function submitBusinessApplication(input: {
  businessId: string;
  applicant: GroupPerson;
  answers: BusinessAnswer[];
  positions: BusinessPositionRow[];
}): Promise<void> {
  const text = input.answers.map((a) => a.answer).join(" \n ");
  const match = scoreAgainstPositions(text, input.positions);
  const { error } = await supabase.from("whisper_business_applications").insert({
    business_id: input.businessId,
    applicant_id: input.applicant.id,
    applicant_username: input.applicant.username,
    answers: input.answers,
    best_position: match.best,
    position_scores: match.scores,
    match_score: match.matchScore,
    status: "new",
  });
  if (error) {
    if (error.code === "42P01") throw new Error("This team's hiring isn't set up yet — check back soon.");
    throw new Error("Couldn't send your application. Try again.");
  }
}

/** The answer prompt that marks a lead captured live in a Whisper meeting. */
export const MEETING_LEAD_PROMPT = "How we met";

/**
 * Files a meeting hand-raise as a lead in the business's applicant pipeline —
 * one row per person per business. The viewer inserts their own row (RLS:
 * applicants may insert + read their own applications), so a raised hand in
 * a meeting lands in the Business+ hiring tab automatically.
 */
export async function recordMeetingInterest(input: {
  businessId: string;
  person: GroupPerson;
  company: string;
}): Promise<void> {
  const { data } = await supabase
    .from("whisper_business_applications")
    .select("id")
    .eq("business_id", input.businessId)
    .eq("applicant_id", input.person.id)
    .limit(1);
  if ((data as { id: string }[] | null)?.length) return;
  await supabase.from("whisper_business_applications").insert({
    business_id: input.businessId,
    applicant_id: input.person.id,
    applicant_username: input.person.username,
    answers: [
      {
        prompt: MEETING_LEAD_PROMPT,
        answer: `Raised a hand while ${input.company} presented live in a Whisper meeting.`,
      },
    ],
    best_position: null,
    position_scores: {},
    match_score: 0,
    status: "new",
  });
}

export async function fetchApplications(businessId: string): Promise<BusinessApplicationRow[]> {
  const { data, error } = await supabase
    .from("whisper_business_applications")
    .select("*")
    .eq("business_id", businessId)
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) return [];
  return (data as BusinessApplicationRow[] | null) ?? [];
}

export async function setApplicationStatus(
  id: string,
  status: BusinessApplicationRow["status"]
): Promise<void> {
  await supabase.from("whisper_business_applications").update({ status }).eq("id", id);
}

/** Public link applicants use — company name rides as a display hint. */
export function businessApplyUrl(businessId: string, company: string | null): string {
  const base = `https://mydailywhisper.com/work-with/${businessId}`;
  return company ? `${base}?co=${encodeURIComponent(company)}` : base;
}

// ─── The private HQ group + the team chat ──────────────────────────────────

/** Deterministic slug so the HQ group is found again on any device. */
export function hqGroupSlug(businessId: string): string {
  return `hq-${businessId.replace(/-/g, "").slice(0, 10)}`;
}

/**
 * Ensures the business's invite-only HQ group exists (creates it on first
 * tap), keeps the owner a member, and invites every teammate. Returns the
 * group slug for /c/{slug}.
 */
export async function ensureHqGroup(input: {
  business: BusinessPlusRow;
  owner: GroupPerson;
  team: BusinessTeamRow[];
}): Promise<string> {
  const slug = hqGroupSlug(input.business.user_id);
  const name = `${input.business.company_name?.trim() || input.owner.username} HQ`;
  const { data: existing } = await supabase
    .from("whisper_communities")
    .select("slug")
    .eq("slug", slug)
    .limit(1)
    .maybeSingle();
  if (!existing) {
    const { error } = await supabase.from("whisper_communities").insert({
      slug,
      name,
      tagline: "The team's private space — plans, wins, and honest talk.",
      color1: "#5A5FE8",
      color2: "#8B8FF5",
      keywords: [slug],
      creator_id: input.owner.id,
      creator_username: input.owner.username,
      visibility: "private",
    });
    if (error) {
      if (/visibility/.test(error.message ?? "") || error.code === "42P01") {
        throw new Error("Run supabase/community-posts.sql once to unlock private groups.");
      }
      throw new Error("Couldn't create the HQ group.");
    }
  }
  await supabase.from("whisper_community_members").upsert(
    {
      community_slug: slug,
      user_id: input.owner.id,
      username: input.owner.username,
      role: "owner",
      status: "member",
    },
    { onConflict: "community_slug,user_id" }
  );
  for (const member of input.team) {
    await supabase.from("whisper_community_members").upsert(
      {
        community_slug: slug,
        user_id: member.user_id,
        username: member.username,
        role: "member",
        status: "invited",
        invited_by: input.owner.username,
      },
      { onConflict: "community_slug,user_id", ignoreDuplicates: true }
    );
  }
  return slug;
}

/** Ensures the team's group chat exists in DMs; returns the thread. */
export async function ensureTeamChat(input: {
  business: BusinessPlusRow;
  owner: GroupPerson;
  team: BusinessTeamRow[];
}): Promise<GroupThread> {
  const mine = await fetchMyGroupThreads();
  const existing = mine.find((t) => t.business_id === input.business.user_id);
  if (existing) return existing;
  if (input.team.length === 0) {
    throw new Error("Add at least one teammate first — then the chat has someone in it.");
  }
  return createGroupThread({
    name: `${input.business.company_name?.trim() || input.owner.username} team`,
    owner: input.owner,
    members: input.team.map((m) => ({ id: m.user_id, username: m.username })),
    businessId: input.business.user_id,
  });
}

// ─── Internal team calendar ─────────────────────────────────────────────────

export interface BusinessEventRow {
  id: string;
  created_by: string;
  created_by_username: string;
  title: string;
  description: string | null;
  event_type: string;
  start_time: string;
  end_time: string | null;
  location: string | null;
  meeting_link: string | null;
  business_id: string | null;
}

export async function fetchBusinessEvents(businessId: string): Promise<BusinessEventRow[]> {
  const since = new Date(Date.now() - 14 * 86_400_000).toISOString();
  const { data, error } = await supabase
    .from("whisper_calendar_events")
    .select("*")
    .eq("business_id", businessId)
    .gte("start_time", since)
    .order("start_time", { ascending: true })
    .limit(100);
  if (error) return [];
  return (data as BusinessEventRow[] | null) ?? [];
}

export async function createBusinessEvent(input: {
  businessId: string;
  createdBy: GroupPerson;
  title: string;
  eventType: string;
  startISO: string;
  durationMinutes: number;
  description?: string;
  meetingLink?: string;
}): Promise<void> {
  const end = new Date(new Date(input.startISO).getTime() + input.durationMinutes * 60_000);
  const { error } = await supabase.from("whisper_calendar_events").insert({
    created_by: input.createdBy.id,
    created_by_username: input.createdBy.username,
    title: input.title.trim(),
    description: input.description?.trim() || null,
    event_type: input.eventType,
    start_time: input.startISO,
    end_time: end.toISOString(),
    meeting_link: input.meetingLink?.trim() || null,
    business_id: input.businessId,
  });
  if (error) {
    if (/business_id/.test(error.message ?? "")) {
      throw new Error("Run supabase/business-plus.sql once to unlock the team calendar.");
    }
    throw new Error("Couldn't add the event.");
  }
}

export async function deleteBusinessEvent(id: string): Promise<void> {
  await supabase.from("whisper_calendar_events").delete().eq("id", id);
}
