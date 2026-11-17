/** Pure public-link contract, shared by invitation email handlers and the web client. */
export interface MeetingInvitation {
  idOrCode: string;
  social: boolean;
  href: string;
}

/** Public identity validation only: never hash, lowercase, or replace a UUID/code. */
export function isMeetingIdentity(value: string): boolean {
  return /^(?:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}|wsp-[a-z0-9]{4}-[a-z0-9]{4})$/i.test(value);
}

export function meetingInvitationLink(idOrCode: string): string {
  return isMeetingIdentity(idOrCode) ? `https://meet.mydailywhisper.com/meet/${idOrCode}` : "";
}

/** Accept known legacy hosts; rebuild links to exclude credentials, tokens and auto-join flags. */
export function parseMeetingInvitation(raw: string): MeetingInvitation | null {
  try {
    const url = new URL(raw.startsWith("www.mydailywhisper.com/") ? `https://${raw}` : raw);
    if (url.username || url.password || url.port || !["https:", "http:"].includes(url.protocol)) return null;
    if (!["mydailywhisper.com", "www.mydailywhisper.com", "meet.mydailywhisper.com"].includes(url.hostname)) return null;
    const parts = url.pathname.split("/").filter(Boolean);
    const idOrCode = parts.length === 2 && parts[0] === "meet" ? parts[1]
      : url.hostname === "meet.mydailywhisper.com" && parts.length === 1 ? parts[0] : "";
    if (!isMeetingIdentity(idOrCode)) return null;
    const social = url.searchParams.get("sd") === "1" || url.searchParams.has("call") || url.searchParams.has("groupCall");
    if (!social) return { idOrCode, social, href: meetingInvitationLink(idOrCode) };
    const safe = new URL(`https://www.mydailywhisper.com/meet/${idOrCode}`);
    for (const key of ["sd", "call", "mode", "groupCall"]) {
      const value = url.searchParams.get(key);
      if (value !== null) safe.searchParams.set(key, value);
    }
    return { idOrCode, social, href: safe.href };
  } catch { return null; }
}

/** Structured dating/calendar/call messages are owned by their respective card decoders. */
export function meetingInvitationFromText(text: string | null | undefined): MeetingInvitation | null {
  const raw = text?.trim();
  if (!raw || raw.includes("::whisper-")) return null;
  if (isMeetingIdentity(raw)) return { idOrCode: raw, social: false, href: meetingInvitationLink(raw) };
  for (const word of raw.split(/\s+/)) {
    const candidate = word.replace(/^[<>"'(),.;!]+|[<>"'(),.;!]+$/g, "");
    const invitation = parseMeetingInvitation(candidate);
    if (!invitation) continue;
    if (raw.includes("Started a group")) {
      return { ...invitation, social: true, href: `https://www.mydailywhisper.com/meet/${invitation.idOrCode}?groupCall=1` };
    }
    return invitation;
  }
  return null;
}
