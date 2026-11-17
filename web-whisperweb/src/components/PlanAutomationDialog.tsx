import { useEffect, useMemo, useRef, useState } from "react";
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query";
import { Check, ClipboardList, Loader2, RefreshCw } from "lucide-react";
import { toast } from "sonner";
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog";
import { Button } from "@/components/ui/button";
import { Avatar } from "@/components/Avatar";
import { useAuth } from "@/hooks/useAuth";
import { useJasperGeneration } from "@/hooks/useJasperGeneration";
import { fetchConversations, sendMessage } from "@/lib/api";
import { assertJasperSession, jasperSession, JASPER_NATIVE_REVIEW_MESSAGE, onJasperInvalidated } from "@/lib/jasperSession";
import { PLAN_QUIZ_DISPLAY_ORDER, decodePlanQuizAnswers, encodePlanQuiz, planQuizLabel, standardPlanQuiz, type PlanQuizAnswersPayload } from "@/lib/contentEmbeds";
import { cn } from "@/lib/utils";

/** A client explicitly selected for a coaching questionnaire. */
export interface AutomationClient { userId: string; username: string }
interface Props { open: boolean; onOpenChange: (open: boolean) => void; clients: AutomationClient[] }
type Step = "ask" | "review" | "next";

/** Keeps existing questionnaire/review workflows without calling paused plan generation. */
export function PlanAutomationDialog(props: Props) {
  const generation = useJasperGeneration();
  const { onOpenChange } = props;
  useEffect(() => onJasperInvalidated(() => onOpenChange(false)), [onOpenChange]);
  return props.open ? <PlanQuestionnaire key={generation} {...props} /> : null;
}

function PlanQuestionnaire({ open, onOpenChange, clients }: Props) {
  const { user, profile } = useAuth();
  const generation = useJasperGeneration();
  const queryClient = useQueryClient();
  const [step, setStep] = useState<Step>("ask");
  const [selected, setSelected] = useState<Set<string>>(new Set());
  const [sent, setSent] = useState<Set<string>>(new Set());
  const [nudged, setNudged] = useState<Set<string>>(new Set());
  const [notice, setNotice] = useState<string | null>(null);
  const alive = useRef<boolean>(true);
  useEffect(() => { alive.current = true; return () => { alive.current = false; }; }, []);
  const username = profile?.username;
  const rows = clients.filter((client) => selected.has(client.userId.toLowerCase()));
  const conversations = useQuery({
    queryKey: ["jasper-plan-questionnaire", user?.id, generation],
    queryFn: async () => {
      const context = await jasperSession();
      if (context.ownerId !== user?.id.toLowerCase()) throw new Error("Account changed");
      const result = await fetchConversations(context.ownerId);
      assertJasperSession(context);
      return result;
    },
    enabled: open && !!user,
    retry: false,
  });
  const answers = useMemo(() => {
    const result: Record<string, PlanQuizAnswersPayload> = {};
    for (const conversation of conversations.data ?? []) {
      for (const message of [...conversation.messages].reverse()) {
        const decoded = decodePlanQuizAnswers(message.body);
        if (decoded) { result[conversation.otherUserId.toLowerCase()] = decoded; break; }
      }
    }
    return result;
  }, [conversations.data]);

  const send = useMutation({
    mutationFn: async (nudgeClient?: AutomationClient) => {
      const context = await jasperSession();
      if (context.ownerId !== user?.id.toLowerCase() || !username) throw new Error("Sign in again before sending.");
      const check = (): void => { assertJasperSession(context); if (!alive.current) throw new Error("Questionnaire closed"); };
      check();
      const recipients = nudgeClient ? [nudgeClient] : rows.filter((client) => !sent.has(client.userId.toLowerCase()));
      let failed = 0;
      let delivered = 0;
      for (const client of recipients) {
        check();
        try {
          await sendMessage(context.ownerId, username, client.userId, client.username,
            nudgeClient ? "When you have time, please answer the questionnaire above so we can review your goals together. Meal-plan generation requires review in Jasper."
              : encodePlanQuiz(standardPlanQuiz(username)));
          check();
          delivered += 1;
          if (nudgeClient) setNudged((previous) => new Set(previous).add(client.userId.toLowerCase()));
          else setSent((previous) => new Set(previous).add(client.userId.toLowerCase()));
        } catch {
          check();
          failed += 1;
        }
      }
      check();
      setNotice(failed ? `${delivered} sent; ${failed} could not be confirmed. Check Messages before retrying.` : null);
      if (!failed) {
        toast(nudgeClient ? "Reminder sent" : `${delivered} questionnaires sent`);
        if (!nudgeClient) setStep("review");
      }
      void queryClient.invalidateQueries({ queryKey: ["conversations"] });
    },
    onError: () => { if (alive.current) setNotice("Sending stopped. Check your account and Messages before retrying."); },
    retry: false,
  });

  return <Dialog open={open} onOpenChange={onOpenChange}>
    <DialogContent className="flex max-h-[86dvh] max-w-xl flex-col overflow-hidden rounded-3xl">
      <DialogHeader>
        <DialogTitle className="flex items-center gap-2"><ClipboardList className="h-5 w-5" />Plan questionnaire</DialogTitle>
        <DialogDescription>Ask about goals and review the answers. Automatic plan delivery is paused.</DialogDescription>
      </DialogHeader>
      <div className="flex gap-2" aria-label="Questionnaire steps">
        {(["ask", "review", "next"] as const).map((item, index) => <Button key={item} variant={step === item ? "default" : "outline"}
          className="min-h-11 flex-1 rounded-full" disabled={send.isPending} onClick={() => setStep(item)}>
          {index + 1} · {item === "next" ? "Next steps" : item === "ask" ? "Ask" : "Review"}
        </Button>)}
      </div>
      <div className="flex-1 space-y-4 overflow-y-auto">
        {notice && <p role="alert" className="rounded-xl border border-border p-3 text-sm">{notice}</p>}
        {step === "ask" && <>
          <p className="text-sm text-muted-foreground">Choose who receives an eight-question card in Messages. Their answers do not authorize generation, sharing or changes to their Jasper account.</p>
          {clients.length === 0 && <p className="py-6 text-center text-sm text-muted-foreground">No active clients yet.</p>}
          {clients.map((client) => {
            const uid = client.userId.toLowerCase();
            const checked = selected.has(uid);
            return <button key={uid} type="button" disabled={send.isPending} aria-pressed={checked}
              className="flex min-h-14 w-full items-center gap-3 rounded-2xl border border-border p-3 text-left"
              onClick={() => setSelected((previous) => { const next = new Set(previous); if (next.has(uid)) next.delete(uid); else next.add(uid); return next; })}>
              <Avatar name={client.username} size={32} /><span className="min-w-0 flex-1 truncate text-sm font-semibold">@{client.username}
                {sent.has(uid) && <span className="block text-xs font-normal text-muted-foreground">Questionnaire sent</span>}</span>
              <span className={cn("flex h-5 w-5 items-center justify-center rounded-full border", checked && "bg-foreground text-background")}>
                {checked && <Check className="h-3 w-3" />}</span>
            </button>;
          })}
          <div className="grid grid-cols-2 gap-2">{standardPlanQuiz(username ?? "coach").questions.map((question) =>
            <p key={question.id} className="rounded-xl bg-secondary p-2 text-xs">{question.q}</p>)}</div>
        </>}
        {step === "review" && <>
          <Button variant="ghost" onClick={() => void conversations.refetch()} disabled={conversations.isFetching} className="min-h-11 gap-2">
            <RefreshCw className={cn("h-4 w-4", conversations.isFetching && "animate-spin")} />Check answers
          </Button>
          {conversations.isError && <p role="alert" className="text-sm">Could not load answers. Try again.</p>}
          {conversations.isPending && <p className="text-sm text-muted-foreground">Loading answers…</p>}
          {rows.length === 0 && <p className="text-sm text-muted-foreground">Choose clients in Ask to review their answers.</p>}
          {rows.map((client) => {
            const uid = client.userId.toLowerCase();
            const reply = answers[uid];
            return <section key={uid} className="space-y-3 rounded-2xl border border-border p-4">
              <h3 className="text-sm font-bold">@{client.username}</h3>
              {reply ? <dl className="grid grid-cols-2 gap-3">{PLAN_QUIZ_DISPLAY_ORDER.filter((key) => reply.answers[key]).map((key) =>
                <div key={key}><dt className="text-xs text-muted-foreground">{planQuizLabel(key)}</dt><dd className="text-sm">{reply.answers[key]}</dd></div>)}</dl>
                : <><p className="text-sm text-muted-foreground">No answers returned in the loaded conversation.</p>
                  <Button variant="outline" disabled={send.isPending || nudged.has(uid)} onClick={() => send.mutate(client)}>
                    {nudged.has(uid) ? "Reminder sent" : "Send reminder"}</Button></>}
            </section>;
          })}
        </>}
        {step === "next" && <section className="space-y-4 rounded-2xl border border-border p-4">
          <h3 className="text-lg font-semibold">Review in Jasper</h3>
          <p className="text-sm leading-relaxed">{JASPER_NATIVE_REVIEW_MESSAGE}</p>
          <p className="text-sm text-muted-foreground">No meal plan or training program is generated, saved or activated by this questionnaire. No “plans are live” message is sent. Saved cloud plans are not proof of native validation or active selection.</p>
          <a className="inline-flex min-h-11 items-center text-sm font-semibold underline" href="https://www.thejasperapp.com/connect" target="_blank" rel="noreferrer">Jasper connection details</a>
        </section>}
      </div>
      <div className="border-t border-border pt-3">
        {step === "ask" ? <Button className="min-h-11 w-full rounded-full" disabled={!username || !rows.length || send.isPending}
          onClick={() => send.mutate(undefined)}>{send.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}Send questionnaire ({rows.filter((client) => !sent.has(client.userId.toLowerCase())).length})</Button>
          : <Button className="min-h-11 w-full rounded-full" disabled={send.isPending} onClick={() => step === "review" ? setStep("next") : onOpenChange(false)}>{step === "review" ? "Next steps" : "Done"}</Button>}
      </div>
    </DialogContent>
  </Dialog>;
}
