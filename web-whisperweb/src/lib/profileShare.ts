/**
 * Web port of the iOS `WhisperProfileShareEmbed`. Encodes a profile into a DM
 * body so the recipient sees a rich profile preview card instead of a bare
 * text link. Wire-compatible with the iOS `::whisper-sharedprofile-v1::` format.
 */
const PREFIX = "::whisper-sharedprofile-v1::";

export interface SharedProfilePayload {
  username: string;
  displayName: string | null;
  bio: string | null;
  avatarUrl: string | null;
  isVerified: boolean;
  isCoach: boolean;
  isAthlete: boolean;
  isRecruiter: boolean;
}

export function encodeSharedProfile(p: SharedProfilePayload): string {
  return PREFIX + JSON.stringify(p);
}

export function decodeSharedProfile(
  body: string | null | undefined
): SharedProfilePayload | null {
  const t = body ?? "";
  if (!t.startsWith(PREFIX)) return null;
  try {
    const json = t.slice(PREFIX.length);
    const p = JSON.parse(json) as SharedProfilePayload;
    if (!p.username) return null;
    return p;
  } catch {
    return null;
  }
}

export function isSharedProfile(body: string | null | undefined): boolean {
  return !!body && body.startsWith(PREFIX);
}
