import { COMMUNITIES, type Community } from "@/lib/communities";

/** Identity only, wire-compatible with native messages; never grants access. */
export const SHARED_COMMUNITY_PREFIX = "::whisper-sharedcommunity-v1::";

export function decodeSharedCommunity(body: string | null | undefined): Community | null {
  if (!body?.startsWith(SHARED_COMMUNITY_PREFIX) || new TextEncoder().encode(body).length > 2048) return null;
  try {
    const value: unknown = JSON.parse(body.slice(SHARED_COMMUNITY_PREFIX.length));
    if (!value || typeof value !== "object" || !("communityID" in value) || typeof value.communityID !== "string") return null;
    return COMMUNITIES.find((community) => community.id === value.communityID) ?? null;
  } catch {
    return null;
  }
}
