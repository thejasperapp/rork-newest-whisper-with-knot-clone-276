import { BACKEND_URL } from "@/lib/billing";
import { supabase } from "@/lib/supabase";

/**
 * Recruiter reviews — users who signed up via a recruiter's referral code can
 * rate the recruiter 1–5 stars and leave a short review. The founder/admin
 * sees aggregate ratings so they know which recruiters are performing well.
 */

export interface RecruiterReview {
  reviewer_id: string;
  rating: number;
  review: string | null;
  created_at: string;
}

export interface RecruiterReviewSummary {
  reviews: RecruiterReview[];
  reviewCount: number;
  averageRating: number | null;
  positiveCount: number;
  negativeCount: number;
}

/** Submit (or update) a review for a recruiter. */
export async function submitRecruiterReview(input: {
  recruiterId: string;
  rating: number;
  review?: string;
}): Promise<void> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("sign_in_required");
  const res = await fetch(`${BACKEND_URL}/recruiter/reviews`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${token}`,
    },
    body: JSON.stringify({
      recruiterId: input.recruiterId,
      rating: input.rating,
      review: input.review?.trim() || undefined,
    }),
  });
  const body = (await res.json()) as { ok?: boolean; error?: string };
  if (!res.ok || !body.ok) {
    const msg =
      body.error === "not_referred_by"
        ? "You can only review a recruiter you signed up with."
        : body.error === "cannot_review_self"
          ? "You can't review yourself."
          : body.error === "invalid_rating"
            ? "Pick a rating from 1 to 5 stars."
            : "Couldn't submit your review. Try again.";
    throw new Error(msg);
  }
}

/** Fetch a recruiter's reviews + aggregate rating (public reputation). */
export async function fetchRecruiterReviews(
  recruiterId: string
): Promise<RecruiterReviewSummary> {
  const res = await fetch(
    `${BACKEND_URL}/recruiter/reviews?recruiterId=${encodeURIComponent(recruiterId)}`
  );
  if (!res.ok) {
    return {
      reviews: [],
      reviewCount: 0,
      averageRating: null,
      positiveCount: 0,
      negativeCount: 0,
    };
  }
  return (await res.json()) as RecruiterReviewSummary;
}

/**
 * Find the recruiter who referred the signed-in user (if any), so we can show
 * them a "rate your recruiter" prompt. Returns the recruiter's user id +
 * username, or null if the user wasn't referred.
 */
export async function fetchMyRecruiter(): Promise<{
  recruiterId: string;
  username: string | null;
} | null> {
  const { data: sessionData } = await supabase.auth.getSession();
  const userId = sessionData.session?.user?.id;
  if (!userId) return null;
  // whisper_referral_signups has RLS: the new_user_id can read their own row.
  const { data: signupData } = await supabase
    .from("whisper_referral_signups")
    .select("recruiter_id")
    .eq("new_user_id", userId)
    .limit(1)
    .maybeSingle();
  const recruiterId = (signupData as { recruiter_id?: string } | null)?.recruiter_id;
  if (!recruiterId) return null;
  // Look up the recruiter's username from whisper_profiles.
  const { data: profileData } = await supabase
    .from("whisper_profiles")
    .select("username")
    .eq("user_id", recruiterId)
    .limit(1)
    .maybeSingle();
  return {
    recruiterId,
    username: (profileData as { username?: string } | null)?.username ?? null,
  };
}

/** Check whether the signed-in user has already reviewed their recruiter. */
export async function fetchMyReview(
  recruiterId: string
): Promise<RecruiterReview | null> {
  const { data: sessionData } = await supabase.auth.getSession();
  const userId = sessionData.session?.user?.id;
  if (!userId) return null;
  const { data: reviewData } = await supabase
    .from("whisper_recruiter_reviews")
    .select("reviewer_id,rating,review,created_at")
    .eq("recruiter_id", recruiterId)
    .eq("reviewer_id", userId)
    .limit(1)
    .maybeSingle();
  return (reviewData as RecruiterReview | null) ?? null;
}
