import { supabase } from "@/lib/supabase";
import { parseMeetingInvitation } from "@/lib/meetingInvitation";
import { BACKEND_URL, resolveBackend } from "@/lib/billing";

/**
 * Email invitations for Whisper Meet — the Google-Calendar-grade invite:
 * a branded email with the when/where block, a Join button, the joining
 * info, an Add-to-Google-Calendar link, and a real .ics attachment so it
 * lands on any calendar. Sent by the backend (Resend) — never a mailto.
 */

export interface MeetingInviteEmailInput {
  emails: string[];
  title: string;
  /** The Whisper Meet join link. */
  link: string;
  hostUsername: string;
  /** ISO start; omitted for an instant meeting ("happening now"). */
  startsAt?: string | null;
  endsAt?: string | null;
  description?: string | null;
  /** Human meeting code (wsp-xxxx-xxxx) when the room has one. */
  code?: string | null;
  /** "Repeats weekly" etc. — printed on the invite. */
  recurrenceLabel?: string | null;
  /** Personal line from the host, above the details. */
  note?: string | null;
}

export interface MeetingInviteEmailResult {
  ok: boolean;
  sent: number;
  /** "not_configured" when this deployment has no email provider. */
  error?: string;
}

/** Loose but useful — the backend validates again. */
export function isLikelyEmail(value: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/.test(value.trim());
}

/** Split a pasted "a@x.com, b@y.com" line into clean unique addresses. */
export function parseEmailList(raw: string): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const part of raw.split(/[\s,;]+/)) {
    const e = part.trim().toLowerCase();
    if (!e || !isLikelyEmail(e) || seen.has(e)) continue;
    seen.add(e);
    out.push(e);
  }
  return out;
}

/**
 * Send the invite to every address. Resolves to the count actually
 * accepted by the email provider; throws only on a network failure.
 */
export async function sendMeetingInviteEmails(
  input: MeetingInviteEmailInput,
): Promise<MeetingInviteEmailResult> {
  const invitation = parseMeetingInvitation(input.link);
  if (!invitation) return { ok: false, sent: 0, error: "invalid_link" };
  const emails = input.emails.map((e) => e.trim().toLowerCase()).filter(isLikelyEmail);
  if (emails.length === 0) return { ok: false, sent: 0, error: "no_valid_emails" };
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token ?? "";
  if (!token) return { ok: false, sent: 0, error: "sign_in_required" };
  // The invite route ships with the newest deploy — prefer it, fall back to
  // the permanent alias.
  let base = BACKEND_URL;
  try {
    base = await resolveBackend();
  } catch {
    /* alias */
  }
  const body = JSON.stringify({
    emails,
    title: input.title,
    link: invitation.href,
    hostUsername: input.hostUsername,
    startsAt: input.startsAt ?? null,
    endsAt: input.endsAt ?? null,
    description: input.description ?? null,
    code: /^wsp-/i.test(invitation.idOrCode) ? invitation.idOrCode : null,
    recurrenceLabel: input.recurrenceLabel ?? null,
    note: input.note ?? null,
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone,
  });
  const post = async (host: string): Promise<Response> =>
    fetch(`${host}/meetings/invite-email`, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${token}` },
      body,
    });
  let res = await post(base);
  if (res.status === 404 && base !== BACKEND_URL) res = await post(BACKEND_URL);
  const result = (await res.json().catch(() => ({}))) as { ok?: boolean; sent?: number; error?: string };
  if (!res.ok || !result.ok) {
    return { ok: false, sent: result.sent ?? 0, error: result.error ?? `http_${res.status}` };
  }
  return { ok: true, sent: result.sent ?? emails.length };
}
