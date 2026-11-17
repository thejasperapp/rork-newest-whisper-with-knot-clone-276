import { useEffect, useState } from "react";
import { CalendarCheck, Loader2, ShieldCheck, X } from "lucide-react";
import { toast } from "sonner";

import { Button } from "@/components/ui/button";
import { useAuth } from "@/hooks/useAuth";
import { supabase } from "@/lib/supabase";
import { submitMeetingRequest } from "@/lib/meetings";
import type { FeaturedProfile } from "@/lib/featured";

interface MeetingRequestModalProps {
  open: boolean;
  profile: FeaturedProfile | null;
  onClose: () => void;
}

/**
 * "Schedule a call" flow — surfaced from a featured recruiter card. The user
 * enters their name + email + a preferred time + an optional note; the request
 * lands in the recruiter's dashboard for approval. On approval, a Whisper-
 * branded email with the Google Meet link is sent to the requester.
 *
 * The calendar itself is never exposed to the requester — they only request a
 * time and wait for confirmation, so the recruiter keeps full control.
 */
export function MeetingRequestModal({
  open,
  profile,
  onClose,
}: MeetingRequestModalProps) {
  const { session, user, profile: myProfile } = useAuth();
  const [name, setName] = useState<string>("");
  const [email, setEmail] = useState<string>("");
  const [requestedTime, setRequestedTime] = useState<string>("");
  const [timezone, setTimezone] = useState<string>("");
  const [message, setMessage] = useState<string>("");
  const [submitting, setSubmitting] = useState<boolean>(false);

  // Pre-fill name/email from the signed-in account when available.
  useEffect(() => {
    if (!open) return;
    const tz =
      typeof Intl !== "undefined" && typeof Intl.DateTimeFormat === "function"
        ? (() => {
            try {
              return Intl.DateTimeFormat().resolvedOptions().timeZone ?? "";
            } catch {
              return "";
            }
          })()
        : "";
    setTimezone(tz);
    if (session) {
      setName(myProfile?.username ?? user?.email?.split("@")[0] ?? "");
      setEmail(user?.email ?? "");
    } else {
      setName("");
      setEmail("");
    }
    setRequestedTime("");
    setMessage("");
  }, [open, session, myProfile, user]);

  if (!open || !profile) return null;

  const recruiterId = profile.user_id;
  const recruiterUsername = profile.username ?? "";

  const handleSubmit = async (): Promise<void> => {
    if (!recruiterId) {
      toast.error("This recruiter's profile isn't linked yet.");
      return;
    }
    if (!name.trim()) {
      toast.error("Please enter your name.");
      return;
    }
    if (!email.trim()) {
      toast.error("Please enter your email so the recruiter can confirm.");
      return;
    }
    if (!requestedTime) {
      toast.error("Please pick a preferred time.");
      return;
    }
    setSubmitting(true);
    try {
      let token: string | null = null;
      if (session) {
        const { data } = await supabase.auth.getSession();
        token = data.session?.access_token ?? null;
      }
      await submitMeetingRequest({
        recruiterId,
        recruiterUsername,
        featuredId: profile.id,
        requesterName: name.trim(),
        requesterEmail: email.trim(),
        requestedTime,
        requesterTimezone: timezone,
        message: message.trim() || undefined,
        token,
      });
      toast.success("Request sent. The recruiter will email you to confirm.");
      onClose();
    } catch (err) {
      toast.error(
        err instanceof Error ? err.message : "Couldn't submit your request."
      );
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <div
      className="fixed inset-0 z-50 flex items-end justify-center bg-black/60 p-0 sm:items-center sm:p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-md overflow-hidden rounded-t-[28px] border border-border bg-card shadow-2xl sm:rounded-[28px]"
        onClick={(e) => e.stopPropagation()}
      >
        {/* Header */}
        <div className="flex items-center justify-between border-b border-border px-5 py-4">
          <div className="flex items-center gap-2">
            <span className="flex h-8 w-8 items-center justify-center rounded-full bg-foreground text-background">
              <CalendarCheck className="h-4 w-4" />
            </span>
            <div>
              <h2 className="text-[15.5px] font-extrabold leading-tight">
                Schedule a call
              </h2>
              <p className="text-[12px] text-muted-foreground">
                with @{recruiterUsername || "recruiter"}
              </p>
            </div>
          </div>
          <button
            onClick={onClose}
            className="rounded-full p-2 text-muted-foreground hover:bg-secondary"
            aria-label="Close"
          >
            <X className="h-4 w-4" />
          </button>
        </div>

        {/* Body */}
        <div className="max-h-[70vh] space-y-4 overflow-y-auto px-5 py-5">
          <p className="text-[13.5px] leading-relaxed text-muted-foreground">
            Share a preferred time and a quick note. The recruiter reviews your
            request and emails you a Google Meet invite once it's approved —
            your email is only used to confirm this meeting.
          </p>

          <div>
            <label className="mb-1.5 block text-[12.5px] font-bold text-foreground">
              Your name
            </label>
            <input
              value={name}
              onChange={(e) => setName(e.target.value)}
              placeholder="Jordan Lee"
              className="h-12 w-full rounded-2xl border border-border bg-background px-4 text-[14.5px] outline-none focus:border-foreground"
            />
          </div>

          <div>
            <label className="mb-1.5 block text-[12.5px] font-bold text-foreground">
              Email <span className="text-muted-foreground">(required)</span>
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="h-12 w-full rounded-2xl border border-border bg-background px-4 text-[14.5px] outline-none focus:border-foreground"
            />
            <p className="mt-1.5 flex items-center gap-1.5 text-[11.5px] text-muted-foreground">
              <ShieldCheck className="h-3.5 w-3.5" />
              The recruiter emails you here with the meeting link.
            </p>
          </div>

          <div>
            <label className="mb-1.5 block text-[12.5px] font-bold text-foreground">
              Preferred time
            </label>
            <input
              type="datetime-local"
              value={requestedTime}
              onChange={(e) => setRequestedTime(e.target.value)}
              className="h-12 w-full rounded-2xl border border-border bg-background px-4 text-[14.5px] outline-none focus:border-foreground"
            />
            {timezone && (
              <p className="mt-1.5 text-[11.5px] text-muted-foreground">
                Your timezone: {timezone}
              </p>
            )}
          </div>

          <div>
            <label className="mb-1.5 block text-[12.5px] font-bold text-foreground">
              Message <span className="text-muted-foreground">(optional)</span>
            </label>
            <textarea
              value={message}
              onChange={(e) => setMessage(e.target.value)}
              placeholder="What would you like to talk about?"
              rows={3}
              className="w-full rounded-2xl border border-border bg-background p-3.5 text-[14.5px] outline-none focus:border-foreground"
            />
          </div>
        </div>

        {/* Footer */}
        <div className="border-t border-border px-5 py-4">
          <Button
            className="h-12 w-full rounded-full text-[15px] font-bold"
            disabled={submitting}
            onClick={handleSubmit}
          >
            {submitting ? (
              <Loader2 className="h-4 w-4 animate-spin" />
            ) : (
              "Request meeting"
            )}
          </Button>
        </div>
      </div>
    </div>
  );
}
