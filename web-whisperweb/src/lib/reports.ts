import { supabase } from "@/lib/supabase";
import { assertReceipt, safetyRequest } from "@/lib/safetyReview";

/** Where a bug report was filed from — rides along as context for triage. */
export interface BugReportContext {
  surface: string;
  meetingId?: string | null;
  path?: string;
  [key: string]: string | number | boolean | null | undefined;
}

export type BugCategory = "meetings" | "calendar" | "audio-video" | "messages" | "account" | "other";

export const BUG_CATEGORIES: { id: BugCategory; label: string; hint: string }[] = [
  { id: "meetings", label: "Meetings", hint: "Joining, links, the room" },
  { id: "audio-video", label: "Audio & video", hint: "Mic, camera, sharing" },
  { id: "calendar", label: "Calendar", hint: "Scheduling, invites" },
  { id: "messages", label: "Messages", hint: "DMs, groups, notes" },
  { id: "account", label: "Account", hint: "Sign-in, billing, profile" },
  { id: "other", label: "Something else", hint: "Anything at all" },
];

const SUPPORT_EMAIL = "support@mydailywhisper.com";

/** Browser + page facts a bug report can carry — never anything personal. */
export function environmentSummary(): Record<string, string> {
  if (typeof navigator === "undefined") return {};
  return {
    userAgent: navigator.userAgent.slice(0, 240),
    language: navigator.language,
    viewport: typeof window !== "undefined" ? `${window.innerWidth}×${window.innerHeight}` : "",
    online: typeof navigator.onLine === "boolean" ? String(navigator.onLine) : "",
    url: typeof window !== "undefined" ? window.location.href.slice(0, 300) : "",
  };
}

/**
 * Files a bug report through the in-app report rail (`whisper_submit_report`,
 * see supabase/reports.sql). Returns "filed" on success, "mailto" when the
 * rail isn't available (signed out, or the migration hasn't landed) — the
 * caller then falls back to the prepared support email.
 */
export async function submitBugReport(input: {
  category: BugCategory;
  details: string;
  includeEnvironment: boolean;
  context: BugReportContext;
}): Promise<"filed" | "mailto"> {
  const { data: sessionData } = await supabase.auth.getSession();
  if (!sessionData.session) return "mailto";
  const context: Record<string, unknown> = {
    ...input.context,
    category: input.category,
    ...(input.includeEnvironment ? { environment: environmentSummary() } : {}),
  };
  try {
  const receipt = await safetyRequest(sessionData.session.user.id, "rpc/whisper_submit_report", {
    p_kind: "bug",
    p_reason: input.category,
    p_details: input.details.trim().slice(0, 4000),
    p_target_username: null,
    p_target_id: input.context.meetingId ?? input.context.adId ?? null,
    p_context: context,
  });
  assertReceipt(receipt);
  return "filed";
  } catch {
    // Preparing an email is not confirmation of an in-app report or email delivery.
    return "mailto";
  }
}

/** A ready-to-send support email carrying the same report. */
export function bugReportMailto(input: {
  category: BugCategory;
  details: string;
  includeEnvironment: boolean;
  context: BugReportContext;
}): string {
  const label = BUG_CATEGORIES.find((c) => c.id === input.category)?.label ?? "Bug";
  const lines: string[] = [
    input.details.trim(),
    "",
    `Area: ${label}`,
    `From: ${input.context.surface}${input.context.meetingId ? ` · meeting ${input.context.meetingId}` : ""}`,
  ];
  if (input.includeEnvironment) {
    for (const [key, value] of Object.entries(environmentSummary())) {
      if (value) lines.push(`${key}: ${value}`);
    }
  }
  const subject = encodeURIComponent(`Whisper bug report — ${label}`);
  const body = encodeURIComponent(lines.join("\n"));
  return `mailto:${SUPPORT_EMAIL}?subject=${subject}&body=${body}`;
}
