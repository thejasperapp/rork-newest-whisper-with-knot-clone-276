/** Social's server-to-server boundary. Teams remains the invitation/roster authority. */
export interface TeamsReceiverEnv {
  WHISPER_TEAMS_RECEIVER_ENABLED?: string;
  WHISPER_TEAMS_SIGNING_KEYS?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
}
export const teamsEventPath = "/social/teams/v1/events";
const databaseOrigin = "https://uryyyegnbtlmyhqlgndy.supabase.co";
const uuid = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/;
const statuses = ["pending", "accepted", "declined", "revoked", "expired"] as const;
export interface TeamsInvitationEvent {
  schemaVersion: 1;
  source: "whisper-teams";
  eventId: string;
  invitationId: string;
  invitationVersion: string;
  teamId: string;
  teamName: string;
  inviterId: string;
  recipientId: string;
  status: typeof statuses[number];
  occurredAt: number;
  expiresAt: number;
}
const fields = ["schemaVersion", "source", "eventId", "invitationId", "invitationVersion", "teamId", "teamName", "inviterId", "recipientId", "status", "occurredAt", "expiresAt"];
/** Strict full-state event; no caller-chosen message IDs, privileges, URLs or notification copy. */
export function parseTeamsEvent(value: unknown, now = Date.now()): TeamsInvitationEvent | null {
  if (!value || typeof value !== "object" || Array.isArray(value)) return null;
  const v = value as Record<string, unknown>;
  if (Object.keys(v).length !== fields.length || !fields.every(k => Object.hasOwn(v, k))) return null;
  if (v.schemaVersion !== 1 || v.source !== "whisper-teams") return null;
  if (![v.eventId, v.invitationId, v.teamId, v.inviterId, v.recipientId].every(id => typeof id === "string" && uuid.test(id))) return null;
  if (v.inviterId === v.recipientId || typeof v.invitationVersion !== "string" || !/^[1-9][0-9]{0,18}$/.test(v.invitationVersion) || BigInt(v.invitationVersion) > 9223372036854775807n) return null;
  if (typeof v.teamName !== "string" || !v.teamName.trim() || v.teamName.length > 120 || /[\p{Cc}\p{Cf}\p{Zl}\p{Zp}<>]/u.test(v.teamName)) return null;
  if (!statuses.includes(v.status as typeof statuses[number])) return null;
  if (![v.occurredAt, v.expiresAt].every(t => typeof t === "number" && Number.isSafeInteger(t) && t > 0 && t < 8_640_000_000_000_000)) return null;
  if ((v.occurredAt as number) > now + 60_000 || (v.status === "pending" && (v.expiresAt as number) <= (v.occurredAt as number))) return null;
  return v as unknown as TeamsInvitationEvent;
}
const encode = (value: string): Uint8Array<ArrayBuffer> => new TextEncoder().encode(value);
const hex = (value: ArrayBuffer): string => Array.from(new Uint8Array(value), b => b.toString(16).padStart(2, "0")).join("");
/** Domain-separated signature input; transport timestamp changes on retry, event bytes do not. */
export async function teamsSigningInput(raw: string, timestamp: string, keyId: string): Promise<string> {
  const digest = hex(await crypto.subtle.digest("SHA-256", encode(raw)));
  return ["whisper-social-teams-v1", "POST", teamsEventPath, keyId, timestamp, digest].join("\n");
}
async function authentic(req: Request, raw: string, keys: Record<string, unknown>, now: number): Promise<boolean> {
  const id = req.headers.get("X-Whisper-Teams-Key-Id") ?? "";
  const timestamp = req.headers.get("X-Whisper-Teams-Timestamp") ?? "";
  const signature = req.headers.get("X-Whisper-Teams-Signature") ?? "";
  if (!/^[a-zA-Z0-9_-]{1,64}$/.test(id) || !/^[0-9]{10}$/.test(timestamp) || Math.abs(now - Number(timestamp) * 1000) > 300_000 || !/^v1=[0-9a-f]{64}$/.test(signature)) return false;
  const secret = Object.hasOwn(keys, id) ? keys[id] : undefined;
  if (typeof secret !== "string" || !/^[0-9a-f]{64}$/.test(secret)) return false;
  const bytes = Uint8Array.from(secret.match(/../g) ?? [], b => parseInt(b, 16));
  const key = await crypto.subtle.importKey("raw", bytes, { name: "HMAC", hash: "SHA-256" }, false, ["verify"]);
  const supplied = Uint8Array.from(signature.slice(3).match(/../g) ?? [], b => parseInt(b, 16));
  return crypto.subtle.verify("HMAC", key, supplied, encode(await teamsSigningInput(raw, timestamp, id)));
}
function reply(value: unknown, status = 200): Response {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store", ...(status === 503 ? { "Retry-After": "60" } : {}) } });
}
async function boundedBody(req: Request): Promise<string> {
  const reader = req.body?.getReader();
  if (!reader) throw new Error("body");
  let length = 0;
  const chunks: Uint8Array[] = [];
  try {
    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      length += value.byteLength;
      if (length > 8192) { void reader.cancel(); throw new Error("size"); }
      chunks.push(value);
    }
    const bytes = new Uint8Array(length); let offset = 0;
    for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
    return new TextDecoder("utf-8", { fatal: true }).decode(bytes);
  } finally { reader.releaseLock(); }
}
/** No user JWT is accepted as delivery authority. DB commit precedes acknowledgment. */
export async function receiveTeamsEvent(request: Request, env: TeamsReceiverEnv, transport: typeof fetch = fetch, now = Date.now()): Promise<Response> {
  if (request.method !== "POST") return reply({ error: "method_not_allowed" }, 405);
  if (new URL(request.url).search) return reply({ error: "invalid_request" }, 400);
  if (env.WHISPER_TEAMS_RECEIVER_ENABLED !== "true" || !env.SUPABASE_SERVICE_ROLE_KEY || !env.WHISPER_TEAMS_SIGNING_KEYS) return reply({ error: "receiver_not_ready" }, 503);
  let keys: Record<string, unknown>;
  try { keys = JSON.parse(env.WHISPER_TEAMS_SIGNING_KEYS); if (!keys || typeof keys !== "object" || Array.isArray(keys)) throw new Error(); }
  catch { return reply({ error: "receiver_not_ready" }, 503); }
  if (request.headers.get("content-type")?.split(";")[0].trim().toLowerCase() !== "application/json") return reply({ error: "json_required" }, 415);
  let raw: string;
  try { raw = await boundedBody(request); } catch { return reply({ error: "invalid_or_oversized_body" }, 413); }
  if (!await authentic(request, raw, keys, now)) return reply({ error: "invalid_server_signature" }, 401);
  let event: TeamsInvitationEvent | null;
  try { event = parseTeamsEvent(JSON.parse(raw), now); } catch { event = null; }
  if (!event) return reply({ error: "invalid_event" }, 422);
  try {
    const response = await transport(`${databaseOrigin}/rest/v1/rpc/whisper_social_teams_receive`, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(15_000),
      headers: { "Content-Type": "application/json", apikey: env.SUPABASE_SERVICE_ROLE_KEY, Authorization: `Bearer ${env.SUPABASE_SERVICE_ROLE_KEY}` },
      body: JSON.stringify({ p_event: event }),
    });
    if (!response.ok) {
      const failure = await response.json().catch(() => ({})) as { code?: string };
      if (failure.code === "23505" || failure.code === "PT409") return reply({ error: "event_conflict" }, 409);
      if (failure.code === "22023") return reply({ error: "invalid_event" }, 422);
      return reply({ error: "receiver_unavailable" }, 503);
    }
    const result = await response.json() as { eventId?: unknown; result?: unknown };
    if (result?.eventId !== event.eventId || !["applied", "duplicate", "stale", "suppressed"].includes(String(result.result))) return reply({ error: "receiver_unavailable" }, 503);
    // Don't expose Social message/read IDs, block reasons, preferences or notification outcomes to the inviter.
    return reply({ eventId: event.eventId, acknowledged: true, result: result.result });
  } catch { return reply({ error: "receiver_unavailable" }, 503); }
}
