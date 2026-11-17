import { useMemo, useState } from "react";
import { useParams, useSearchParams, Link } from "react-router-dom";
import { useMutation, useQuery } from "@tanstack/react-query";
import { Briefcase, Check, Loader2, Send, Sparkles } from "lucide-react";
import { toast } from "sonner";

import { Header } from "@/components/Header";
import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import { cn } from "@/lib/utils";
import { supabase } from "@/lib/supabase";
import {
  fetchPositions,
  fetchQuestions,
  submitBusinessApplication,
  type BusinessAnswer,
} from "@/lib/businessPlus";

const INDIGO = "#5A5FE8";

const FALLBACK_PROMPT = "Tell us about yourself — what do you do best?";

/**
 * The public Business+ application page — /work-with/:businessId.
 * Applicants answer the business's OWN questions; Whisper auto-matches the
 * answers to the team's open positions on submit.
 */
export default function BusinessApply() {
  const { businessId = "" } = useParams<{ businessId: string }>();
  const [params] = useSearchParams();
  const { user, profile } = useAuth();

  const ownerQuery = useQuery({
    queryKey: ["bp-owner", businessId],
    queryFn: async () => {
      const { data } = await supabase
        .from("whisper_profiles")
        .select("user_id, username, display_name, profile_image_url")
        .eq("user_id", businessId)
        .limit(1)
        .maybeSingle();
      return (data ?? null) as {
        user_id: string;
        username: string;
        display_name: string | null;
        profile_image_url: string | null;
      } | null;
    },
    enabled: !!businessId,
  });

  const positionsQuery = useQuery({
    queryKey: ["bp-positions", businessId],
    queryFn: () => fetchPositions(businessId),
    enabled: !!businessId,
  });
  const questionsQuery = useQuery({
    queryKey: ["bp-questions", businessId],
    queryFn: () => fetchQuestions(businessId),
    enabled: !!businessId,
  });

  // One row per applicant — surface "already applied" instead of a dupe form.
  const mineQuery = useQuery({
    queryKey: ["bp-my-application", businessId, user?.id],
    queryFn: async () => {
      const { data } = await supabase
        .from("whisper_business_applications")
        .select("id, status, best_position, match_score, created_at")
        .eq("business_id", businessId)
        .eq("applicant_id", user!.id)
        .order("created_at", { ascending: false })
        .limit(1);
      return (data?.[0] ?? null) as {
        id: string;
        status: string;
        best_position: string | null;
        match_score: number;
      } | null;
    },
    enabled: !!businessId && !!user?.id,
  });

  const company =
    params.get("co")?.trim() ||
    ownerQuery.data?.display_name ||
    (ownerQuery.data ? `@${ownerQuery.data.username}` : "This team");

  const openPositions = useMemo(
    () => (positionsQuery.data ?? []).filter((p) => p.is_open),
    [positionsQuery.data]
  );
  const activeQuestions = useMemo(() => {
    const list = (questionsQuery.data ?? []).filter((q) => q.is_active);
    return list.length > 0
      ? list.map((q) => q.prompt)
      : [FALLBACK_PROMPT];
  }, [questionsQuery.data]);

  const [answers, setAnswers] = useState<Record<string, string>>({});
  const [sent, setSent] = useState<boolean>(false);

  const submit = useMutation({
    mutationFn: async (): Promise<void> => {
      if (!user || !profile) throw new Error("Sign in first.");
      const filled: BusinessAnswer[] = activeQuestions.map((prompt) => ({
        prompt,
        answer: (answers[prompt] ?? "").trim(),
      }));
      if (!filled.some((a) => a.answer.length > 0)) {
        throw new Error("Answer at least one question.");
      }
      await submitBusinessApplication({
        businessId,
        applicant: { id: user.id, username: profile.username },
        answers: filled.filter((a) => a.answer.length > 0),
        positions: positionsQuery.data ?? [],
      });
    },
    onSuccess: () => {
      setSent(true);
      toast("Application sent");
    },
    onError: (err: Error) => toast(err.message),
  });

  const loading =
    ownerQuery.isLoading || positionsQuery.isLoading || questionsQuery.isLoading;

  return (
    <div>
      <Header title="Work with us" />
      <div className="mx-auto w-full max-w-xl px-4 pb-24 pt-4">
        {loading ? (
          <div className="flex justify-center py-16">
            <Loader2 className="h-6 w-6 animate-spin text-muted-foreground" />
          </div>
        ) : (
          <>
            {/* Company hero */}
            <div
              className="rounded-[24px] border p-5 text-center"
              style={{
                borderColor: `${INDIGO}40`,
                background: `linear-gradient(160deg, ${INDIGO}14, transparent 60%)`,
              }}
            >
              <div className="mx-auto w-fit">
                <Avatar
                  url={ownerQuery.data?.profile_image_url}
                  name={company}
                  size={64}
                />
              </div>
              <p
                className="mt-3 flex items-center justify-center gap-1.5 text-[10.5px] font-black uppercase tracking-[0.2em]"
                style={{ color: INDIGO }}
              >
                <Sparkles className="h-3.5 w-3.5" />
                Hiring on Whisper
              </p>
              <h1 className="mt-1 font-display text-[24px] font-extrabold leading-tight">
                Join {company}
              </h1>
              {openPositions.length > 0 ? (
                <div className="mt-3 flex flex-wrap justify-center gap-1.5">
                  {openPositions.map((p) => (
                    <span
                      key={p.id}
                      className="flex items-center gap-1 rounded-full bg-card px-3 py-1.5 text-[12px] font-bold shadow-sm"
                    >
                      <Briefcase className="h-3 w-3" style={{ color: INDIGO }} />
                      {p.title}
                    </span>
                  ))}
                </div>
              ) : (
                <p className="mt-2 text-[12.5px] text-muted-foreground">
                  Open application — tell them what you'd bring.
                </p>
              )}
            </div>

            {/* Already applied / success / the form */}
            {sent || mineQuery.data ? (
              <div className="mt-4 rounded-[24px] border border-emerald-500/30 bg-emerald-500/5 p-6 text-center">
                <span className="mx-auto flex h-12 w-12 items-center justify-center rounded-full bg-emerald-500 text-white">
                  <Check className="h-5 w-5" />
                </span>
                <p className="mt-3 text-[16px] font-extrabold">Application in</p>
                <p className="mx-auto mt-1 max-w-xs text-[12.5px] leading-relaxed text-muted-foreground">
                  {company} sees your answers with an automatic match to their
                  open positions{mineQuery.data?.best_position
                    ? ` — you matched ${mineQuery.data.best_position} at ${mineQuery.data.match_score}%`
                    : ""}
                  . They'll reach out on Whisper.
                </p>
                <Link
                  to="/"
                  className="mt-4 inline-flex items-center justify-center rounded-full bg-foreground px-5 py-2.5 text-[13px] font-bold text-background"
                >
                  Back to the feed
                </Link>
              </div>
            ) : (
              <div className="mt-4 space-y-3">
                {activeQuestions.map((prompt, i) => (
                  <div key={prompt} className="rounded-[20px] border border-border bg-card p-4">
                    <p className="flex items-start gap-2 text-[13.5px] font-bold leading-snug">
                      <span
                        className="mt-0.5 flex h-5 w-5 shrink-0 items-center justify-center rounded-full text-[10.5px] font-black text-white"
                        style={{ background: INDIGO }}
                      >
                        {i + 1}
                      </span>
                      {prompt}
                    </p>
                    <textarea
                      value={answers[prompt] ?? ""}
                      onChange={(e) =>
                        setAnswers((a) => ({ ...a, [prompt]: e.target.value }))
                      }
                      rows={3}
                      maxLength={1200}
                      placeholder="Your answer…"
                      className="mt-2.5 w-full resize-none rounded-2xl border border-border bg-background p-3 text-[14px] leading-snug outline-none focus:border-foreground/40"
                    />
                  </div>
                ))}
                <button
                  onClick={() => submit.mutate()}
                  disabled={submit.isPending || !user}
                  className={cn(
                    "flex h-12 w-full items-center justify-center gap-2 rounded-full text-[15px] font-bold text-white transition-transform active:scale-[0.99] disabled:opacity-50"
                  )}
                  style={{ background: `linear-gradient(135deg, ${INDIGO}, #7A7FF0)` }}
                >
                  {submit.isPending ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <Send className="h-4 w-4" />
                  )}
                  Send application
                </button>
                <p className="text-center text-[11.5px] text-muted-foreground">
                  Whisper matches your answers to their open positions
                  automatically — write naturally and mention what you're best at.
                </p>
              </div>
            )}
          </>
        )}
      </div>
    </div>
  );
}
