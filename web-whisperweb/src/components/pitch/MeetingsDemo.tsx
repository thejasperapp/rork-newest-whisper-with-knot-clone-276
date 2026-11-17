import { useState } from "react";
import { usePitchReset, usePitchToast } from "@/components/pitch/PitchContext";
import {
  CalendarCheck2,
  Check,
  Mail,
  Video,
  X,
} from "lucide-react";

import { cn } from "@/lib/utils";
import { SAMPLE_MEETINGS, type SampleMeeting } from "@/lib/pitch";

function formatWhen(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleString("en-US", {
    weekday: "short",
    month: "short",
    day: "numeric",
    hour: "numeric",
    minute: "2-digit",
  });
}

/**
 * Standalone meeting-requests demo for the recruiter deck (kept separate from
 * PipelineDemo's embedded meetings list so the recruiter deck can show it as
 * its own section). Mirrors the real MeetingRequestsSection layout exactly.
 */
export function MeetingsDemo() {
  const [meetings, setMeetings] = useState<SampleMeeting[]>(SAMPLE_MEETINGS);
  const [approvingId, setApprovingId] = useState<string | null>(null);
  const showToast = usePitchToast();
  usePitchReset(() => {
    setMeetings(SAMPLE_MEETINGS);
    setApprovingId(null);
    setDenyingId(null);
    setLink("https://meet.google.com/abc-defg-hij");
    setDenyNote("");
  });
  const [link, setLink] = useState<string>("https://meet.google.com/abc-defg-hij");
  const [denyNote, setDenyNote] = useState<string>("");
  const [denyingId, setDenyingId] = useState<string | null>(null);

  const decide = (id: string, status: "approved" | "denied"): void => {
    setMeetings((prev) => prev.map((m) => (m.id === id ? { ...m, status } : m)));
    const m = meetings.find((x) => x.id === id);
    showToast(`${m?.requester_name ?? "Request"} ${status}${status === "approved" ? " — invite email sent" : ""}`, "success");
    setApprovingId(null);
    setDenyingId(null);
    setLink("https://meet.google.com/abc-defg-hij");
    setDenyNote("");
  };

  return (
    <div className="space-y-3">
      {meetings.map((m) => {
        const isApproving = approvingId === m.id;
        const isDenying = denyingId === m.id;
        const statusStyle =
          m.status === "pending"
            ? "bg-amber-500/15 text-amber-600"
            : m.status === "approved"
              ? "bg-emerald-500/15 text-emerald-600"
              : "bg-rose-500/15 text-rose-600";
        return (
          <div key={m.id} className="rounded-2xl border border-border bg-card p-4">
            <div className="flex items-start justify-between gap-3">
              <div className="min-w-0">
                <p className="text-[15px] font-extrabold">{m.requester_name}</p>
                <a
                  href={`mailto:${m.requester_email}`}
                  className="text-[12.5px] text-muted-foreground hover:underline"
                >
                  {m.requester_email}
                </a>
              </div>
              <span
                className={cn(
                  "shrink-0 rounded-full px-2.5 py-1 text-[11px] font-bold capitalize",
                  statusStyle
                )}
              >
                {m.status}
              </span>
            </div>

            <p className="mt-3 flex items-center gap-2 text-[13px] text-foreground/80">
              <CalendarCheck2 className="h-4 w-4 text-muted-foreground" />
              <span>{formatWhen(m.requested_time)}</span>
              <span className="text-muted-foreground">· {m.requester_timezone}</span>
            </p>
            <p className="mt-3 rounded-xl bg-secondary p-3 text-[13.5px] leading-relaxed text-foreground/90">
              "{m.message}"
            </p>

            {m.status === "approved" && (
              <p className="mt-3 text-[12.5px] text-muted-foreground">
                In production: {m.requester_name.split(" ")[0]} receives a
                Whisper-branded email with the Meet link — they never see your
                calendar.
              </p>
            )}
            {m.status === "denied" && (
              <p className="mt-3 text-[12.5px] text-muted-foreground">
                In production: the requester is notified by email with your note.
              </p>
            )}

            {m.status === "pending" && isApproving && (
              <div className="mt-4 space-y-3 rounded-xl border border-border bg-background p-3">
                <p className="text-[12.5px] font-bold">
                  Paste the Google Meet link for the invite email:
                </p>
                <input
                  value={link}
                  onChange={(e) => setLink(e.target.value)}
                  placeholder="https://meet.google.com/xxx-xxxx-xxx"
                  className="h-11 w-full rounded-xl border border-border bg-card px-3 text-[14px] outline-none focus:border-foreground"
                />
                <div className="flex gap-2">
                  <button
                    onClick={() => decide(m.id, "approved")}
                    disabled={!link.trim()}
                    className="flex-1 rounded-xl bg-foreground py-2.5 text-[13px] font-bold text-background disabled:opacity-50"
                  >
                    Approve & send invite
                  </button>
                  <button
                    onClick={() => {
                      setApprovingId(null);
                      setLink("https://meet.google.com/abc-defg-hij");
                    }}
                    className="rounded-xl px-3 py-2.5 text-[13px] font-bold text-muted-foreground"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            )}

            {m.status === "pending" && isDenying && (
              <div className="mt-4 space-y-3 rounded-xl border border-border bg-background p-3">
                <textarea
                  value={denyNote}
                  onChange={(e) => setDenyNote(e.target.value)}
                  placeholder="Optional note for the requester"
                  rows={2}
                  className="w-full rounded-xl border border-border bg-card p-3 text-[14px] outline-none focus:border-foreground"
                />
                <div className="flex gap-2">
                  <button
                    onClick={() => decide(m.id, "denied")}
                    className="flex-1 rounded-xl bg-rose-600 py-2.5 text-[13px] font-bold text-white"
                  >
                    Decline & notify
                  </button>
                  <button
                    onClick={() => {
                      setDenyingId(null);
                      setDenyNote("");
                    }}
                    className="rounded-xl px-3 py-2.5 text-[13px] font-bold text-muted-foreground"
                  >
                    Cancel
                  </button>
                </div>
              </div>
            )}

            {m.status === "pending" && !isApproving && !isDenying && (
              <div className="mt-4 flex gap-2">
                <button
                  onClick={() => setApprovingId(m.id)}
                  className="flex-1 rounded-xl bg-foreground py-2.5 text-[13px] font-bold text-background"
                >
                  <span className="inline-flex items-center gap-1.5">
                    <Check className="h-3.5 w-3.5" /> Approve
                  </span>
                </button>
                <button
                  onClick={() => setDenyingId(m.id)}
                  className="flex-1 rounded-xl border border-border bg-card py-2.5 text-[13px] font-bold text-foreground"
                >
                  <span className="inline-flex items-center gap-1.5">
                    <X className="h-3.5 w-3.5" /> Decline
                  </span>
                </button>
              </div>
            )}
          </div>
        );
      })}

      <p className="text-center text-[11px] text-muted-foreground">
        Sample requests for presentation · your calendar stays private — only
        the Meet link you approve is shared
      </p>
    </div>
  );
}

/** Re-export the icon for the recruiter deck's "approve" CTA. */
export const ApproveIcon = Video;
export const MailIcon = Mail;
