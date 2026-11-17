import { useState, useMemo, useEffect } from "react";
import { useNavigate, useSearchParams, Link } from "react-router-dom";
import { useQuery, useMutation } from "@tanstack/react-query";
import { ArrowLeft, Check, Loader2, UserCircle, Send } from "lucide-react";
import { toast } from "sonner";

import { CircleZoomTransition } from "@/components/CircleZoomTransition";
import {
  fetchActiveQuestions,
  submitApplicantResponse,
  type ApplicantQuestion,
} from "@/lib/applicantQuestionnaire";
import { useAuth } from "@/hooks/useAuth";
import { cn } from "@/lib/utils";

export default function ApplicantQuestionnaire() {
  const navigate = useNavigate();
  const { user, profile, loading: authLoading, session } = useAuth();
  const [searchParams] = useSearchParams();
  const recruiterCode = (searchParams.get("code") ?? "").toUpperCase();
  const [redirected, setRedirected] = useState(false);

  const isAlreadyVerified =
    profile?.is_verified || profile?.is_coach || profile?.is_athlete || profile?.is_recruiter;

  useEffect(() => {
    if (authLoading || redirected) return;
    if (!recruiterCode) return;
    if (!session) {
      // Signed-out user scanned the QR: go to signup, then come back here.
      setRedirected(true);
      const next = encodeURIComponent(`/apply/questionnaire?code=${recruiterCode}`);
      navigate(`/auth?mode=signup&code=${encodeURIComponent(recruiterCode)}&next=${next}`, {
        replace: true,
      });
      return;
    }
    if (isAlreadyVerified) {
      // Already verified/special-role users don't need to apply again.
      setRedirected(true);
      toast("You're already verified on Whisper", { icon: "✅" });
      navigate("/", { replace: true });
    }
  }, [authLoading, session, recruiterCode, isAlreadyVerified, navigate, redirected]);

  const questionsQuery = useQuery({
    queryKey: ["applicant-questions"],
    queryFn: fetchActiveQuestions,
  });

  const questions = questionsQuery.data ?? [];

  // Initialize answers state from questions
  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [step, setStep] = useState(0);
  const [pendingStep, setPendingStep] = useState<number | null>(null);
  const [transitionActive, setTransitionActive] = useState(false);

  const validAnswers = useMemo(() => {
    const valid: Record<string, string> = {};
    for (const q of questions) {
      const a = answers[q.id];
      if (a && a.trim()) valid[q.id] = a.trim();
    }
    return valid;
  }, [answers, questions]);

  const requiredQuestions = questions.filter((q) => q.required);
  const requiredAnswered = requiredQuestions.filter((q) => validAnswers[q.id]).length;
  const allRequiredAnswered = requiredAnswered === requiredQuestions.length;

  const goToStep = (next: number) => {
    setPendingStep(next);
    setTransitionActive(true);
  };

  const onTransitionComplete = () => {
    if (pendingStep !== null) {
      setStep(pendingStep);
      setPendingStep(null);
    }
  };

  const submitMutation = useMutation({
    mutationFn: () => {
      const answerMap: Record<string, { question: string; answer: string }> = {};
      for (const q of questions) {
        const a = validAnswers[q.id];
        if (a) answerMap[q.id] = { question: q.question, answer: a };
      }

      // Extract name/email from answers if present
      let applicantName = profile?.display_name ?? profile?.username ?? "";
      let applicantEmail = user?.email ?? "";
      for (const q of questions) {
        const a = validAnswers[q.id];
        if (!a) continue;
        if (q.question.toLowerCase().includes("full name")) applicantName = a;
        if (q.question.toLowerCase().includes("email")) applicantEmail = a;
      }

      return submitApplicantResponse({
        recruiterCode,
        applicantEmail,
        applicantName,
        applicantUserId: user?.id,
        answers: answerMap,
      });
    },
    onSuccess: () => {
      toast.success("Application submitted! The recruiter will be in touch.");
      navigate("/");
    },
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Could not submit application");
    },
  });

  if (!recruiterCode) {
    return (
      <div className="flex min-h-[100dvh] flex-col items-center justify-center px-4 text-center">
        <p className="text-lg font-bold">No recruiter code provided</p>
        <p className="mt-1 text-sm text-muted-foreground">
          Ask your recruiter for their signup link or QR code.
        </p>
        <Link to="/" className="mt-6 rounded-full bg-foreground px-5 py-2.5 text-sm font-bold text-background">
          Go home
        </Link>
      </div>
    );
  }

  if (questionsQuery.isLoading) {
    return (
      <div className="flex min-h-[100dvh] items-center justify-center">
        <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
      </div>
    );
  }

  if (questions.length === 0) {
    return (
      <div className="flex min-h-[100dvh] flex-col items-center justify-center px-4 text-center">
        <UserCircle className="mb-4 h-12 w-12 text-muted-foreground" />
        <p className="text-lg font-bold">No questions available yet</p>
        <p className="mt-1 text-sm text-muted-foreground">Please check back soon.</p>
      </div>
    );
  }

  const currentQuestion = questions[step];
  const isLastStep = step === questions.length - 1;
  const currentAnswer = answers[currentQuestion?.id] ?? "";

  return (
    <div className="flex min-h-[100dvh] flex-col bg-background">
      <CircleZoomTransition
        active={transitionActive}
        color="hsl(var(--foreground))"
        origin="center"
        mode="content"
        duration={650}
        onComplete={onTransitionComplete}
        onReset={() => setTransitionActive(false)}
      />

      {/* Progress bar */}
      <div className="sticky top-0 z-30 flex h-1.5 bg-secondary">
        {questions.map((q, i) => (
          <div
            key={q.id}
            className="h-full flex-1 transition-all duration-300"
            style={{ backgroundColor: i <= step ? "var(--foreground)" : "transparent" }}
          />
        ))}
      </div>

      <header className="flex h-14 items-center gap-3 rounded-b-[22px] border-b border-border bg-background/95 px-4 backdrop-blur-sm">
        {step > 0 ? (
          <button
            onClick={() => setStep((s) => Math.max(0, s - 1))}
            className="flex h-10 w-10 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          >
            <ArrowLeft className="h-5 w-5" />
          </button>
        ) : (
          <Link
            to="/"
            className="flex h-10 w-10 items-center justify-center rounded-full transition-colors hover:bg-secondary"
          >
            <ArrowLeft className="h-5 w-5" />
          </Link>
        )}
        <h1 className="font-display text-base font-bold">
          Question {step + 1} of {questions.length}
        </h1>
      </header>

      <main className="mx-auto flex w-full max-w-md flex-1 flex-col px-5 py-6">
        {currentQuestion && (
          <div className="flex flex-1 flex-col">
            <div className="mb-2 flex items-center gap-2">
              {currentQuestion.required && (
                <span className="rounded-full bg-foreground px-2 py-0.5 text-[10px] font-bold uppercase text-background">
                  Required
                </span>
              )}
              <span className="text-xs text-muted-foreground">
                Recruiter code: {recruiterCode}
              </span>
            </div>

            <h2 className="font-display text-2xl font-extrabold tracking-tight">
              {currentQuestion.question}
            </h2>

            <div className="mt-6 flex-1">
              <QuestionInput
                question={currentQuestion}
                value={currentAnswer}
                onChange={(v) => setAnswers((prev) => ({ ...prev, [currentQuestion.id]: v }))}
              />
            </div>

            <div className="mt-auto flex flex-col gap-2 pt-6 pb-[max(1rem,env(safe-area-inset-bottom))]">
              <div className="mb-2 flex items-center justify-between text-xs text-muted-foreground">
                <span>
                  {requiredAnswered} of {requiredQuestions.length} required answered
                </span>
                {!currentQuestion.required && (
                  <button
                    onClick={() => {
                      if (isLastStep) {
                        if (allRequiredAnswered) submitMutation.mutate();
                      } else {
                        goToStep(step + 1);
                      }
                    }}
                    className="font-semibold text-foreground"
                  >
                    Skip →
                  </button>
                )}
              </div>

              <button
                onClick={() => {
                  if (isLastStep) {
                    if (allRequiredAnswered) submitMutation.mutate();
                    else toast.error("Please answer all required questions");
                  } else {
                    goToStep(step + 1);
                  }
                }}
                disabled={
                  (currentQuestion.required && !currentAnswer.trim()) ||
                  submitMutation.isPending
                }
                className="flex items-center justify-center gap-2 rounded-2xl bg-foreground py-3.5 text-sm font-bold text-background transition-transform active:scale-[0.98] disabled:opacity-40"
              >
                {submitMutation.isPending ? (
                  <>
                    <Loader2 className="h-4 w-4 animate-spin" /> Submitting…
                  </>
                ) : isLastStep ? (
                  <>
                    <Send className="h-4 w-4" /> Submit application
                  </>
                ) : (
                  <>
                    Next <ArrowLeft className="h-4 w-4 rotate-180" />
                  </>
                )}
              </button>
            </div>
          </div>
        )}
      </main>
    </div>
  );
}

function QuestionInput({
  question,
  value,
  onChange,
}: {
  question: ApplicantQuestion;
  value: string;
  onChange: (v: string) => void;
}) {
  switch (question.question_type) {
    case "textarea":
      return (
        <textarea
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="Type your answer…"
          rows={5}
          autoFocus
          className="w-full resize-none rounded-2xl border border-border bg-card px-4 py-3 text-[15px] outline-none ring-foreground/50 focus:ring-2"
        />
      );
    case "select":
      return (
        <div className="space-y-2">
          {(question.options ?? []).map((opt) => (
            <button
              key={opt}
              onClick={() => onChange(opt)}
              className={cn(
                "flex w-full items-center justify-between rounded-2xl border px-4 py-3.5 text-left text-[15px] font-semibold transition-all active:scale-[0.98]",
                value === opt
                  ? "border-foreground bg-foreground text-background"
                  : "border-border bg-card text-foreground hover:bg-secondary/50"
              )}
            >
              {opt}
              {value === opt && <Check className="h-5 w-5" />}
            </button>
          ))}
        </div>
      );
    case "number":
      return (
        <input
          type="number"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="Enter a number…"
          autoFocus
          className="w-full rounded-2xl border border-border bg-card px-4 py-3 text-[15px] outline-none ring-foreground/50 focus:ring-2"
        />
      );
    case "rating":
      return (
        <div className="flex gap-2">
          {[1, 2, 3, 4, 5].map((n) => (
            <button
              key={n}
              onClick={() => onChange(String(n))}
              className={cn(
                "flex h-12 w-12 items-center justify-center rounded-2xl border text-lg font-bold transition-all active:scale-90",
                value === String(n)
                  ? "border-foreground bg-foreground text-background"
                  : "border-border bg-card text-foreground"
              )}
            >
              {n}
            </button>
          ))}
        </div>
      );
    default:
      return (
        <input
          type="text"
          value={value}
          onChange={(e) => onChange(e.target.value)}
          placeholder="Type your answer…"
          autoFocus
          className="w-full rounded-2xl border border-border bg-card px-4 py-3.5 text-[15px] outline-none ring-foreground/50 focus:ring-2"
        />
      );
  }
}
