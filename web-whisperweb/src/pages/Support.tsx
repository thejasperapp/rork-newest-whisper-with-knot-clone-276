import { useState } from "react";
import { Link } from "react-router-dom";
import { useMutation } from "@tanstack/react-query";
import { CheckCircle2, LifeBuoy, Loader2, Send } from "lucide-react";
import { toast } from "sonner";

import PublicNav from "@/components/PublicNav";
import PublicFooter from "@/components/PublicFooter";
import { Reveal } from "@/components/Reveal";
import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { usePageMeta } from "@/hooks/usePageMeta";
import { BACKEND_URL } from "@/lib/billing";

const TOPICS = [
  "General",
  "Billing & refunds",
  "Coach applications",
  "Coaching payments",
  "Account & privacy",
  "Bug report",
];

const inputClass =
  "h-11 w-full rounded-full border border-border bg-background px-4 text-[14.5px] outline-none focus:border-foreground";
const labelClass =
  "mb-1.5 block text-[12px] font-extrabold uppercase tracking-wider text-muted-foreground";

interface SupportForm {
  name: string;
  email: string;
  topic: string;
  message: string;
}

async function sendSupport(form: SupportForm): Promise<void> {
  const res = await fetch(`${BACKEND_URL}/support/contact`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(form),
  });
  const data = (await res.json()) as { ok?: boolean; error?: string };
  if (!res.ok || !data.ok) {
    throw new Error(
      data.error === "invalid_body"
        ? "Please fill in your name, a valid email, and a message."
        : "Couldn't send your message. Try again in a minute."
    );
  }
}

/** Public support/contact page — messages land straight in the Whisper inbox. */
export default function Support() {
  usePageMeta(
    "Support",
    "Questions about billing, coaching, or your account? Message the Whisper team directly."
  );

  const { profile, user } = useAuth();
  const [name, setName] = useState<string>(profile?.display_name ?? "");
  const [email, setEmail] = useState<string>(user?.email ?? "");
  const [topic, setTopic] = useState<string>(TOPICS[0]);
  const [message, setMessage] = useState<string>("");
  const [sent, setSent] = useState<boolean>(false);

  const send = useMutation({
    mutationFn: sendSupport,
    onSuccess: () => setSent(true),
    onError: (err) => {
      toast.error(err instanceof Error ? err.message : "Something went wrong.");
    },
  });

  return (
    <div className="flex min-h-screen flex-col bg-background">
      <PublicNav />

      <main className="flex-1">
        <section className="px-4 pb-8 pt-32 sm:px-6 lg:px-8 lg:pt-40">
          <div className="mx-auto max-w-3xl text-center">
            <div className="inline-flex items-center gap-2 rounded-full border border-border bg-card px-4 py-1.5 text-[13px] font-medium text-muted-foreground">
              <LifeBuoy className="h-4 w-4" />
              We answer every message
            </div>
            <h1 className="mt-6 font-display text-[36px] font-extrabold leading-[1.1] tracking-tight sm:text-[48px]">
              How can we help?
            </h1>
            <p className="mx-auto mt-5 max-w-xl text-[16.5px] leading-relaxed text-muted-foreground">
              Billing questions, coaching issues, bug reports — send it here
              and a real person replies to your email.
            </p>
          </div>
        </section>

        <section className="px-4 pb-20 sm:px-6 lg:px-8">
          <div className="mx-auto max-w-xl">
            {sent ? (
              <Reveal variant="scale" className="rounded-[28px] border border-border bg-card p-10 text-center">
                <CheckCircle2 className="mx-auto h-12 w-12 text-green-500" />
                <h2 className="mt-4 font-display text-[22px] font-extrabold">
                  Message sent.
                </h2>
                <p className="mx-auto mt-2 max-w-sm text-[14.5px] leading-relaxed text-muted-foreground">
                  We'll reply to <span className="font-semibold text-foreground">{email}</span>{" "}
                  — usually within a day.
                </p>
                <Button
                  variant="outline"
                  className="mt-6 rounded-full"
                  onClick={() => {
                    setSent(false);
                    setMessage("");
                  }}
                >
                  Send another message
                </Button>
              </Reveal>
            ) : (
              <Reveal className="rounded-[28px] border border-border bg-card p-6 sm:p-8">
                <div className="grid gap-4 sm:grid-cols-2">
                  <div>
                    <span className={labelClass}>Your name</span>
                    <input
                      value={name}
                      onChange={(e) => setName(e.target.value)}
                      placeholder="Alex"
                      className={inputClass}
                    />
                  </div>
                  <div>
                    <span className={labelClass}>Email</span>
                    <input
                      value={email}
                      onChange={(e) => setEmail(e.target.value)}
                      type="email"
                      placeholder="you@example.com"
                      className={inputClass}
                    />
                  </div>
                </div>

                <div className="mt-4">
                  <span className={labelClass}>Topic</span>
                  <select
                    value={topic}
                    onChange={(e) => setTopic(e.target.value)}
                    className={inputClass}
                  >
                    {TOPICS.map((t) => (
                      <option key={t} value={t}>
                        {t}
                      </option>
                    ))}
                  </select>
                </div>

                <div className="mt-4">
                  <span className={labelClass}>Message</span>
                  <textarea
                    value={message}
                    onChange={(e) => setMessage(e.target.value)}
                    rows={6}
                    placeholder="Tell us what's going on…"
                    className="w-full rounded-2xl border border-border bg-background px-4 py-3 text-[14.5px] leading-relaxed outline-none focus:border-foreground"
                  />
                </div>

                <Button
                  className="mt-5 h-12 w-full rounded-full text-[15px] font-bold"
                  disabled={
                    send.isPending ||
                    !name.trim() ||
                    !email.trim() ||
                    !message.trim()
                  }
                  onClick={() =>
                    send.mutate({
                      name: name.trim(),
                      email: email.trim(),
                      topic,
                      message: message.trim(),
                    })
                  }
                >
                  {send.isPending ? (
                    <Loader2 className="h-4 w-4 animate-spin" />
                  ) : (
                    <>
                      <Send className="mr-1.5 h-4 w-4" />
                      Send message
                    </>
                  )}
                </Button>

                <p className="mt-4 text-center text-[13px] text-muted-foreground">
                  Billing questions? The{" "}
                  <Link
                    to="/terms"
                    className="font-semibold text-foreground underline-offset-4 hover:underline"
                  >
                    refund policy
                  </Link>{" "}
                  covers the common cases.
                </p>
              </Reveal>
            )}
          </div>
        </section>
      </main>

      <PublicFooter />
    </div>
  );
}
