import { useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Star, X, Loader2, Check } from "lucide-react";
import { toast } from "sonner";

import {
  submitRecruiterReview,
  fetchMyReview,
} from "@/lib/recruiterReviews";
import { cn } from "@/lib/utils";

/**
 * A sheet that lets a user who signed up via a recruiter's referral code rate
 * that recruiter 1–5 stars and leave a short review. The founder uses these
 * ratings to see which recruiters are performing well.
 *
 * Shown from Settings (for referred users) and after onboarding when the user
 * arrived via a recruiter's link. One review per (recruiter, reviewer);
 * re-submitting updates the existing review.
 */
export function RecruiterReviewSheet({
  recruiterId,
  recruiterUsername,
  onClose,
}: {
  recruiterId: string;
  recruiterUsername: string | null;
  onClose: () => void;
}) {
  const queryClient = useQueryClient();
  const [rating, setRating] = useState<number>(0);
  const [review, setReview] = useState<string>("");
  const [hoverRating, setHoverRating] = useState<number>(0);

  // Pre-fill if the user already reviewed this recruiter.
  const existing = useQuery({
    queryKey: ["my-recruiter-review", recruiterId],
    queryFn: () => fetchMyReview(recruiterId),
    enabled: !!recruiterId,
  });
  // Apply existing values once loaded.
  if (existing.data && rating === 0 && !review) {
    setRating(existing.data.rating);
    if (existing.data.review) setReview(existing.data.review);
  }

  const submit = useMutation({
    mutationFn: () =>
      submitRecruiterReview({ recruiterId, rating, review }),
    onSuccess: () => {
      toast.success("Thanks for rating your recruiter!");
      void queryClient.invalidateQueries({
        queryKey: ["my-recruiter-review", recruiterId],
      });
      void queryClient.invalidateQueries({
        queryKey: ["recruiter-reviews", recruiterId],
      });
      onClose();
    },
    onError: (err) => {
      toast.error(
        err instanceof Error ? err.message : "Couldn't submit your review."
      );
    },
  });

  const displayStars = hoverRating || rating;

  return (
    <div className="fixed inset-0 z-50 flex flex-col bg-background md:items-center md:justify-center md:bg-black/50 md:p-6">
      <div className="flex h-full w-full flex-col bg-background md:max-w-md md:rounded-[26px] md:border md:border-border md:shadow-2xl md:h-auto md:max-h-[88vh]">
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border px-4 py-3.5">
          <button
            onClick={onClose}
            className="flex h-8 w-8 items-center justify-center rounded-full transition-colors hover:bg-secondary"
            aria-label="Close"
          >
            <X className="h-5 w-5" />
          </button>
          <h2 className="font-display text-[17px] font-bold">Rate your recruiter</h2>
          <span className="w-8" />
        </div>

        {/* Body */}
        <div className="min-h-0 flex-1 space-y-5 overflow-y-auto px-4 py-5">
          <div className="text-center">
            <p className="text-sm text-muted-foreground">
              How was your experience with
            </p>
            <p className="mt-0.5 font-display text-lg font-bold">
              @{recruiterUsername ?? "your recruiter"}
            </p>
            <p className="mt-2 text-[13px] text-muted-foreground">
              Your rating helps us know which recruiters are performing well.
              It's visible to the Whisper team.
            </p>
          </div>

          {/* Star rating */}
          <div className="flex flex-col items-center gap-2 py-2">
            <div className="flex items-center gap-1.5">
              {[1, 2, 3, 4, 5].map((star) => (
                <button
                  key={star}
                  onClick={() => setRating(star === rating ? 0 : star)}
                  onMouseEnter={() => setHoverRating(star)}
                  onMouseLeave={() => setHoverRating(0)}
                  className="transition-transform active:scale-90"
                  aria-label={`${star} star${star > 1 ? "s" : ""}`}
                >
                  <Star
                    className={cn(
                      "h-9 w-9 transition-colors",
                      star <= displayStars
                        ? "fill-amber-400 text-amber-400"
                        : "text-muted-foreground/30"
                    )}
                  />
                </button>
              ))}
            </div>
            {rating > 0 && (
              <p className="text-sm font-bold text-muted-foreground">
                {["", "Poor", "Fair", "Good", "Great", "Excellent"][rating]} · {rating}/5
              </p>
            )}
          </div>

          {/* Review text */}
          <div>
            <label className="mb-1.5 block text-xs font-semibold text-muted-foreground">
              Review (optional)
            </label>
            <textarea
              value={review}
              onChange={(e) => setReview(e.target.value.slice(0, 1000))}
              placeholder="Share how the recruitment process went — communication, follow-through, anything that stood out."
              rows={4}
              maxLength={1000}
              className="w-full resize-none rounded-2xl border border-border bg-card px-4 py-3 text-[15px] outline-none ring-primary/50 focus:ring-2"
            />
            <p className="mt-1 text-right text-xs text-muted-foreground">
              {review.length}/1000
            </p>
          </div>
        </div>

        {/* Footer */}
        <div className="border-t border-border px-4 py-3 pb-[max(0.75rem,env(safe-area-inset-bottom))]">
          <button
            onClick={() => submit.mutate()}
            disabled={rating === 0 || submit.isPending}
            className="flex w-full items-center justify-center gap-2 rounded-xl bg-primary py-3.5 text-[15px] font-bold text-primary-foreground transition-transform active:scale-[0.98] disabled:opacity-50"
          >
            {submit.isPending ? (
              <>
                <Loader2 className="h-4 w-4 animate-spin" /> Submitting…
              </>
            ) : (
              <>
                <Check className="h-4 w-4" /> Submit rating
              </>
            )}
          </button>
        </div>
      </div>
    </div>
  );
}

export default RecruiterReviewSheet;
