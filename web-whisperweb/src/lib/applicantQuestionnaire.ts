/**
 * Applicant questionnaire + recruiter QR system — API functions.
 *
 * Leads scan a recruiter's QR code → land on mydailywhisper.com/auth?mode=signup&code=RECRUITER_CODE
 * → after signup (or as a guest) they fill the applicant questionnaire →
 * responses are stored with the recruiter's ID → recruiter sees them in
 * real-time with position matching scores.
 */

import { supabase } from "@/lib/supabase";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ApplicantQuestion {
  id: string;
  question: string;
  question_type: "text" | "textarea" | "select" | "number" | "rating";
  options: string[] | null;
  required: boolean;
  display_order: number;
  is_active: boolean;
}

export interface ApplicantResponse {
  id: string;
  recruiter_id: string;
  recruiter_code: string | null;
  applicant_email: string | null;
  applicant_name: string | null;
  applicant_user_id: string | null;
  answers: Record<string, { question: string; answer: string }>;
  best_position: string | null;
  position_scores: Record<string, number> | null;
  potential_score: number | null;
  confidence_score: number | null;
  status: string;
  created_at: string;
  updated_at: string;
}

// ---------------------------------------------------------------------------
// Questions — fetched by applicants, managed by admins
// ---------------------------------------------------------------------------

/** Fetch all active questions, ordered by display_order. */
export async function fetchActiveQuestions(): Promise<ApplicantQuestion[]> {
  const { data } = await supabase
    .from("whisper_applicant_questions")
    .select("*")
    .eq("is_active", true)
    .order("display_order", { ascending: true });
  return (data as ApplicantQuestion[] | null) ?? [];
}

/** Fetch ALL questions (including inactive) for admin management. */
export async function fetchAllQuestions(): Promise<ApplicantQuestion[]> {
  const { data } = await supabase
    .from("whisper_applicant_questions")
    .select("*")
    .order("display_order", { ascending: true });
  return (data as ApplicantQuestion[] | null) ?? [];
}

/** Create a new question. */
export async function createQuestion(input: {
  question: string;
  question_type?: string;
  options?: string[] | null;
  required?: boolean;
  display_order?: number;
}): Promise<void> {
  const { error } = await supabase.from("whisper_applicant_questions").insert({
    question: input.question.trim(),
    question_type: input.question_type ?? "text",
    options: input.options ?? null,
    required: input.required ?? true,
    display_order: input.display_order ?? 0,
    is_active: true,
  });
  if (error) throw error;
}

/** Update a question. */
export async function updateQuestion(
  id: string,
  updates: Partial<Pick<ApplicantQuestion, "question" | "question_type" | "options" | "required" | "display_order" | "is_active">>
): Promise<void> {
  const { error } = await supabase
    .from("whisper_applicant_questions")
    .update({ ...updates, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw error;
}

/** Delete a question. */
export async function deleteQuestion(id: string): Promise<void> {
  const { error } = await supabase
    .from("whisper_applicant_questions")
    .delete()
    .eq("id", id);
  if (error) throw error;
}

// ---------------------------------------------------------------------------
// Responses — submitted by leads, viewed by recruiters + admins
// ---------------------------------------------------------------------------

/**
 * Submit an applicant response. The recruiter is identified by their referral
 * code, which is looked up in `whisper_referral_codes`.
 */
export async function submitApplicantResponse(input: {
  recruiterCode: string;
  applicantEmail?: string;
  applicantName?: string;
  applicantUserId?: string;
  answers: Record<string, { question: string; answer: string }>;
}): Promise<{ response_id: string }> {
  // Look up the recruiter from the referral code
  const { data: codeRow } = await supabase
    .from("whisper_referral_codes")
    .select("recruiter_id")
    .eq("code", input.recruiterCode.toUpperCase())
    .maybeSingle();

  if (!codeRow) throw new Error("Invalid recruiter code");

  const recruiterId = (codeRow as { recruiter_id: string }).recruiter_id;

  // Compute position match scores from the answers
  const match = computePositionMatch(input.answers);

  // Application answers must land reliably — retry transient failures
  // (flaky venue wi-fi during live meetings) before surfacing an error.
  let lastError: unknown = null;
  for (let attempt = 0; attempt < 3; attempt++) {
    const { data, error } = await supabase
      .from("whisper_applicant_responses")
      .insert({
        recruiter_id: recruiterId,
        recruiter_code: input.recruiterCode.toUpperCase(),
        applicant_email: input.applicantEmail ?? null,
        applicant_name: input.applicantName ?? null,
        applicant_user_id: input.applicantUserId ?? null,
        answers: input.answers,
        best_position: match.bestPosition,
        position_scores: match.positionScores,
        potential_score: match.potentialScore,
        confidence_score: match.confidenceScore,
        status: "submitted",
      })
      .select("id")
      .single();
    if (!error && data) {
      return { response_id: (data as { id: string }).id };
    }
    lastError = error;
    // Unique/constraint violations won't heal — don't hammer the table.
    if (error && typeof error.code === "string" && error.code.startsWith("23")) break;
    if (attempt < 2) {
      await new Promise((resolve) => setTimeout(resolve, 600 * (attempt + 1)));
    }
  }
  throw lastError instanceof Error ? lastError : new Error("Couldn't save the application");
}

/** Fetch all responses for a recruiter (real-time via Supabase subscriptions). */
export async function fetchRecruiterResponses(
  recruiterId: string
): Promise<ApplicantResponse[]> {
  const { data } = await supabase
    .from("whisper_applicant_responses")
    .select("*")
    .eq("recruiter_id", recruiterId)
    .order("created_at", { ascending: false });
  return (data as ApplicantResponse[] | null) ?? [];
}

/** Fetch all responses (admin view) — optionally filtered by recruiter. */
export async function fetchAllResponses(
  recruiterId?: string
): Promise<ApplicantResponse[]> {
  let query = supabase
    .from("whisper_applicant_responses")
    .select("*")
    .order("created_at", { ascending: false });
  if (recruiterId) query = query.eq("recruiter_id", recruiterId);
  const { data } = await query;
  return (data as ApplicantResponse[] | null) ?? [];
}

/** Update response status (accept/reject/review). */
export async function updateResponseStatus(
  id: string,
  status: "reviewed" | "accepted" | "rejected"
): Promise<void> {
  const { error } = await supabase
    .from("whisper_applicant_responses")
    .update({ status, updated_at: new Date().toISOString() })
    .eq("id", id);
  if (error) throw error;
}

// ---------------------------------------------------------------------------
// Position matching engine
// ---------------------------------------------------------------------------

interface PositionMatch {
  bestPosition: string;
  positionScores: Record<string, number>;
  potentialScore: number;
  confidenceScore: number;
}

/**
 * Heuristic scoring engine that matches an applicant's questionnaire answers
 * to the three promotable roles (coach, athlete, creator) and computes a
 * potential score and confidence score.
 *
 * The scoring uses keyword matching on the answers — each answer is scanned
 * for role-relevant signals (e.g. "coach", "train", "teach" → coach; "compete",
 * "sport", "elite" → athlete; "content", "social", "create" → creator).
 * Scores are normalized to 0-100.
 */
export function computePositionMatch(
  answers: Record<string, { question: string; answer: string }>
): PositionMatch {
  const allText = Object.values(answers)
    .map((a) => `${a.question} ${a.answer}`.toLowerCase())
    .join(" ");

  const scores: Record<string, number> = { coach: 0, athlete: 0, creator: 0 };

  // Coach signals
  const coachKeywords = ["coach", "train", "teach", "instruct", "certified", "client", "program", "guide", "mentor", "help other"];
  let coachHits = 0;
  for (const kw of coachKeywords) if (allText.includes(kw)) coachHits++;
  scores.coach = Math.min(100, 30 + coachHits * 14);

  // Athlete signals
  const athleteKeywords = ["compete", "competition", "sport", "elite", "athlete", "performance", "pr", "personal record", "meet", "race", "championship", "college", "scholarship"];
  let athleteHits = 0;
  for (const kw of athleteKeywords) if (allText.includes(kw)) athleteHits++;
  scores.athlete = Math.min(100, 25 + athleteHits * 12);

  // Creator signals
  const creatorKeywords = ["content", "social", "create", "video", "post", "instagram", "tiktok", "youtube", "blog", "photography", "edit", "audience", "follower", "brand"];
  let creatorHits = 0;
  for (const kw of creatorKeywords) if (allText.includes(kw)) creatorHits++;
  scores.creator = Math.min(100, 28 + creatorHits * 12);

  // Direct role selection boost
  for (const a of Object.values(answers)) {
    const ans = a.answer.toLowerCase();
    if (ans.includes("coach")) scores.coach += 20;
    if (ans.includes("athlete")) scores.athlete += 20;
    if (ans.includes("creator")) scores.creator += 20;
  }
  for (const k of Object.keys(scores)) scores[k] = Math.min(100, scores[k]);

  // Best position
  const bestPosition = Object.entries(scores).sort((a, b) => b[1] - a[1])[0]![0];

  // Potential score: weighted average of top-2 scores
  const sortedScores = Object.values(scores).sort((a, b) => b - a);
  const potentialScore = Math.round(sortedScores[0]! * 0.65 + sortedScores[1]! * 0.35);

  // Confidence score: based on how decisive the top score is vs the others
  const gap = sortedScores[0]! - sortedScores[1]!;
  const confidenceScore = Math.min(100, Math.round(40 + gap * 1.2));

  return {
    bestPosition,
    positionScores: scores,
    potentialScore,
    confidenceScore,
  };
}

export interface ApplicantNote {
  id: string;
  response_id: string;
  question_id: string;
  recruiter_id: string;
  note: string;
  created_at: string;
  updated_at: string;
}

/** Fetch all notes for a response. */
export async function fetchNotesForResponse(responseId: string): Promise<ApplicantNote[]> {
  const { data, error } = await supabase
    .from("whisper_applicant_notes")
    .select("*")
    .eq("response_id", responseId)
    .order("created_at", { ascending: true });
  if (error) throw error;
  return (data as ApplicantNote[] | null) ?? [];
}

/** Save a recruiter note on a specific answer. */
export async function saveQuestionNote(input: {
  responseId: string;
  questionId: string;
  recruiterId: string;
  note: string;
}): Promise<void> {
  const { error } = await supabase.from("whisper_applicant_notes").upsert(
    {
      response_id: input.responseId,
      question_id: input.questionId,
      recruiter_id: input.recruiterId,
      note: input.note.trim(),
      updated_at: new Date().toISOString(),
    },
    { onConflict: "response_id,question_id,recruiter_id" }
  );
  if (error) throw error;
}

/** Subscribe to all changes on the recruiter's responses (new, updated, deleted). */
export function subscribeToResponses(
  recruiterId: string,
  callback: (payload: { event: "INSERT" | "UPDATE" | "DELETE"; response: ApplicantResponse }) => void
): () => void {
  const channel = supabase
    .channel(`applicant-responses:${recruiterId}`)
    .on(
      "postgres_changes",
      {
        event: "*",
        schema: "public",
        table: "whisper_applicant_responses",
        filter: `recruiter_id=eq.${recruiterId}`,
      },
      (payload) => callback({ event: payload.eventType as "INSERT" | "UPDATE" | "DELETE", response: payload.new as ApplicantResponse })
    )
    .subscribe();
  return () => {
    void supabase.removeChannel(channel);
  };
}

/** Subscribe to notes for a response. */
export function subscribeToResponseNotes(
  responseId: string,
  callback: (note: ApplicantNote) => void
): () => void {
  const channel = supabase
    .channel(`applicant-notes:${responseId}`)
    .on(
      "postgres_changes",
      { event: "*", schema: "public", table: "whisper_applicant_notes", filter: `response_id=eq.${responseId}` },
      (payload) => callback(payload.new as ApplicantNote)
    )
    .subscribe();
  return () => {
    void supabase.removeChannel(channel);
  };
}
