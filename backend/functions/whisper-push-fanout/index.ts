// Whisper push fan-out Edge Function
//
// Triggered by Supabase Database Webhooks on inserts into:
//   - whisper_messages       (DM received)
//   - whisper_follows        (new follower)
//   - whisper_post_likes     (your post got liked)
//   - whisper_post_comments  (your post got a comment)
//   - whisper_mentions       (you were @mentioned)
//   - whisper_story_responses(someone responded to your story)
//   - whisper_thought_replies(someone replied to your "what's on your mind")
//
// For each incoming row we:
//   1. Determine the recipient user_id and a (title, body, category) payload.
//   2. SELECT every active row in `whisper_device_tokens` for that user.
//   3. Sign a JWT with the team's APNs .p8 key and POST to APNs HTTP/2.
//   4. Mark stale tokens (410 Gone) as inactive.
//
// Environment variables (set with `supabase secrets set ...`):
//   APNS_TEAM_ID         e.g. ABCDE12345
//   APNS_KEY_ID          e.g. ABC1234DEF
//   APNS_BUNDLE_ID       com.your.bundle.id  (the Whisper iOS app)
//   APNS_PRIVATE_KEY     the contents of the AuthKey_XXXXX.p8 file
//                        (paste the WHOLE file including BEGIN/END lines)
//   APNS_USE_SANDBOX     "true" for dev / TestFlight sandbox, "false" for prod
//                        (you can also fan out to both — see SANDBOX_HOST below)
//   SUPABASE_URL         injected automatically
//   SUPABASE_SERVICE_ROLE_KEY  injected automatically

import { groupEnvelope, safePreview } from "./preview.ts";
import { callMetadata, callPushKey } from "./call-preview.ts";
import { authenticWebhook, createPushPolicy, eventIdentity, eventKeys, isUUID, storyResponseAction } from "./policy.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
// Pin the existing database webhook credential independently of Supabase's runtime-injected API credential.
const PUSH_WEBHOOK_KEY = Deno.env.get("WHISPER_PUSH_WEBHOOK_KEY") ?? SUPABASE_SERVICE_ROLE_KEY;

const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "";
const APNS_PRIVATE_KEY =
  Deno.env.get("APNS_PRIVATE_KEY") ??
  Deno.env.get("APNS_KEY_P8") ??
  "";
const APNS_USE_SANDBOX = (Deno.env.get("APNS_USE_SANDBOX") ?? "true") === "true";

function assertAPNsConfig(): void {
  const missing: string[] = [];
  if (!APNS_TEAM_ID) missing.push("APNS_TEAM_ID");
  if (!APNS_KEY_ID) missing.push("APNS_KEY_ID");
  if (!APNS_BUNDLE_ID) missing.push("APNS_BUNDLE_ID");
  if (!APNS_PRIVATE_KEY) missing.push("APNS_PRIVATE_KEY");
  if (missing.length) {
    throw new Error(
      `Missing Edge Function secrets: ${missing.join(", ")}. ` +
        `Set them in Supabase Dashboard → Project Settings → Edge Functions → Secrets, ` +
        `then redeploy this function.`
    );
  }
}

const PROD_HOST = "https://api.push.apple.com";
const SANDBOX_HOST = "https://api.sandbox.push.apple.com";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

const policy = createPushPolicy(supabase);

// ------------------------------ APNs JWT --------------------------------

// Cache the signed JWT for ~50 minutes (Apple invalidates after 60).
let cachedJWT: { token: string; issuedAt: number } | null = null;

async function importP8(pem: string): Promise<CryptoKey> {
  if (!pem) {
    throw new Error(
      "APNS_PRIVATE_KEY is empty. Paste the entire contents of your AuthKey_XXXX.p8 " +
        "(including the BEGIN/END lines) as the value of the APNS_PRIVATE_KEY secret."
    );
  }
  const cleaned = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\\n/g, "")
    .replace(/\s+/g, "");
  const der = Uint8Array.from(atob(cleaned), (c) => c.charCodeAt(0));
  return await crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"]
  );
}

async function apnsJWT(): Promise<string> {
  assertAPNsConfig();
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.issuedAt < 50 * 60) {
    return cachedJWT.token;
  }
  const key = await importP8(APNS_PRIVATE_KEY);
  const token = await create(
    { alg: "ES256", kid: APNS_KEY_ID, typ: "JWT" },
    { iss: APNS_TEAM_ID, iat: getNumericDate(0) },
    key
  );
  cachedJWT = { token, issuedAt: now };
  return token;
}

// ------------------------------ Send -------------------------------------

interface DeviceTokenRow {
  token: string;
  sandbox?: boolean | null;
  environment?: string | null;
  bundle_id?: string | null;
}

interface Payload {
  title: string;
  body: string;
  category: string;
  data?: Record<string, unknown>;
  threadID?: string;
  /// APNs `apns-collapse-id`: any pending notification on the device with the
  /// same id is REPLACED in place. We use it to guarantee a call only ever
  /// surfaces as a single banner — even if the Edge instance cold-starts and
  /// the in-memory dedupe misses a retransmit — and to flip the same banner
  /// from "Incoming call" to "Missed call" when the caller cancels.
  collapseID?: string;
  eventID?: string;
}

async function sendToUser(userID: string, payload: Payload) {
  const actor = payload.data?.from_user_id ?? payload.data?.follower_user_id ?? payload.data?.liker_user_id
    ?? payload.data?.commenter_user_id ?? payload.data?.author_user_id ?? payload.data?.responder_user_id
    ?? payload.data?.replier_user_id ?? payload.data?.coach_user_id;
  if (!isUUID(actor) || !await policy.canNotify(userID, actor, payload.category)) return;
  payload.data = { ...payload.data, recipient_user_id: userID };
  // Final guard: never let a raw control-protocol body leak into a user-
  // facing notification. If for any reason an upstream caller passes one in,
  // rewrite to a friendly fallback so the user doesn't see
  // `::whisper-call-v1::{...}` on their lock screen.
  payload = sanitizeUserFacingPayload(payload);
  // select("*") on purpose: the table has drifted between schema versions
  // (sandbox boolean vs environment text, with/without active). Explicit
  // column lists made the ENTIRE lookup fail on older schemas — which
  // silently killed every push.
  let query = supabase
    .from("whisper_device_tokens")
    .select("*")
    .eq("user_id", userID);
  let { data: tokens, error } = await query.eq("active", true);
  if (error?.code === "42703") {
    // Legacy table without the `active` column — retry unfiltered.
    ({ data: tokens, error } = await supabase
      .from("whisper_device_tokens")
      .select("*")
      .eq("user_id", userID));
  }

  if (error) {
    throw new Error("push token lookup failed");
  }
  if (!tokens || tokens.length === 0) return;

  const jwt = await apnsJWT();
  const results = await Promise.allSettled((tokens as DeviceTokenRow[]).map(async token => {
    let key: string | undefined;
    if (payload.eventID) {
      const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(JSON.stringify([payload.eventID, userID, token.token])));
      key = Array.from(new Uint8Array(hash), value => value.toString(16).padStart(2, "0")).join("");
      const claimTable = payload.data?.social_teams === "v1" ? "whisper_social_teams_push_claims" : "whisper_push_receipts";
      const { error: claimError } = await supabase.from(claimTable).insert({ event_key: key });
      if (claimError?.code === "23505") return;
      if (claimError) throw new Error("push deduplication unavailable");
    }
    try {
      await deliver(token, jwt, { ...payload, collapseID: payload.collapseID ?? key });
    } catch {
      // Automatic social alerts keep ambiguous claims to avoid repeated interruptions.
      // This is at-most-once application attempt, not guaranteed APNs delivery.
      if (key && payload.data?.social_teams !== "v1" && payload.data?.story_tag !== "v1" && payload.data?.return_post !== "v1") await supabase.from("whisper_push_receipts").delete().eq("event_key", key);
      throw new Error("push device delivery failed");
    }
  }));
  if (results.some(result => result.status === "rejected")) throw new Error("push delivery incomplete");
}

async function postAPNs(
  sandbox: boolean,
  row: DeviceTokenRow,
  jwt: string,
  payload: Payload
): Promise<{ ok: boolean; status: number; text: string }> {
  const host = sandbox ? SANDBOX_HOST : PROD_HOST;
  const bundleID = row.bundle_id ?? APNS_BUNDLE_ID;
  const body = {
    aps: {
      alert: { title: payload.title, body: payload.body },
      sound: "default",
      "thread-id": payload.threadID ?? payload.category,
      category: payload.category,
      "mutable-content": 1,
    },
    data: payload.data ?? {},
  };
  const headers: Record<string, string> = {
    authorization: `bearer ${jwt}`,
    "apns-topic": bundleID,
    "apns-push-type": "alert",
    "apns-priority": "10",
    "content-type": "application/json",
  };
  if (payload.collapseID) {
    // 64-byte max per APNs spec; we keep ids short ("call-<uuid>").
    headers["apns-collapse-id"] = payload.collapseID.slice(0, 64);
  }
  try {
    const res = await fetch(`${host}/3/device/${row.token}`, {
      method: "POST",
      headers,
      body: JSON.stringify(body),
    });
    const text = res.ok ? "" : await res.text();
    return { ok: res.ok, status: res.status, text };
  } catch (e) {
    return { ok: false, status: 0, text: String(e) };
  }
}

async function deliver(
  row: DeviceTokenRow,
  jwt: string,
  payload: Payload
): Promise<void> {
  const preferSandbox =
    typeof row.sandbox === "boolean"
      ? row.sandbox
      : row.environment
      ? row.environment === "sandbox"
      : APNS_USE_SANDBOX;

  const first = await postAPNs(preferSandbox, row, jwt, payload);
  if (first.ok) return;

  let reason = "";
  try { reason = JSON.parse(first.text).reason ?? ""; } catch { /* Non-JSON APNs error. */ }
  if (first.status === 410 && reason === "Unregistered") {
    await supabase.from("whisper_device_tokens").update({ active: false }).eq("token", row.token);
    return;
  }
  if (first.status === 400 && reason === "BadDeviceToken") {
    // BadDeviceToken usually means an APNs ENVIRONMENT mix-up (a sandbox
    // token pushed at the production host, or vice versa) — not a dead
    // token. Self-heal: try the opposite host once, and if it works,
    // remember which environment this token really lives in.
    const second = await postAPNs(!preferSandbox, row, jwt, payload);
    if (second.ok) {
      await supabase
        .from("whisper_device_tokens")
        .update({ sandbox: !preferSandbox, active: true })
        .eq("token", row.token);
      return;
    }
    // A rejected topic, payload or provider configuration must not retire a valid token.
    if (second.status === 410) {
      let secondReason = "";
      try { secondReason = JSON.parse(second.text).reason ?? ""; } catch { /* Non-JSON response. */ }
      if (secondReason === "Unregistered") {
        await supabase.from("whisper_device_tokens").update({ active: false }).eq("token", row.token);
        return;
      }
    }
  }
  throw new Error("APNs delivery rejected");
}

// ------------------------------ Handlers ---------------------------------

async function usernameFor(userID: string): Promise<string> {
  const { data } = await supabase
    .from("whisper_profiles")
    .select("username")
    .eq("user_id", userID)
    .maybeSingle();
  return (data?.username as string | undefined) ?? "someone";
}

async function senderProfileFor(
  userID: string
): Promise<{ username: string; avatar_url: string | null }> {
  const { data } = await supabase
    .from("whisper_profiles")
    .select("username, profile_image_url")
    .eq("user_id", userID)
    .maybeSingle();
  return {
    username: (data?.username as string | undefined) ?? "someone",
    avatar_url: (data?.profile_image_url as string | null | undefined) ?? null,
  };
}

// Rewrites payloads whose body still carries a Whisper control prefix into
// human-readable fallbacks. Belt-and-suspenders — every code path that
// produces a notification body should already be friendly, but if a new
// handler ever forgets the user must not see raw `::whisper-...::{json}`.
function sanitizeUserFacingPayload(p: Payload): Payload {
  const raw = p.body ?? "";
  if (!raw.startsWith("::whisper-")) return { ...p, title: safePreview(p.title), body: safePreview(raw) };
  let friendly = raw;
  if (raw.startsWith("::whisper-call-v1::")) friendly = "Incoming call";
  else if (raw.startsWith("::whisper-callsummary-v1::")) friendly = "Call ended";
  else if (raw.startsWith("::whisper-program-v1::")) friendly = "Sent you a program";
  else if (raw.startsWith("::whisper-workout-v1::")) friendly = "Sent you a workout";
  else if (raw.startsWith("::whisper-coach-proposal-v1::")) friendly = "New coach suggestion";
  else if (raw.startsWith("::whisper-matchreq-v1::")) friendly = "Wants to match with you 💘";
  else if (raw.startsWith("::whisper-matched-v1::")) friendly = "It's a match! 💘";
  else friendly = "New message";
  return { ...p, body: friendly };
}

// Whisper call signaling rides on whisper_messages bodies prefixed with
// `::whisper-call-v1::` followed by a JSON payload. The DB webhook fires
// for every row, so we must:
//   - For `invite`: send a clean "Incoming call" notification (so tapping
//     opens the app and the realtime channel surfaces the answer/decline
//     sheet via WhisperCallService).
//   - For all other call kinds (accept/decline/cancel/end/ice): swallow —
//     these are protocol chatter, never user-facing.
const CALL_SIGNAL_PREFIX = "::whisper-call-v1::";
const CALL_SUMMARY_PREFIX = "::whisper-callsummary-v1::";

async function handleCallSignal(
  to: string,
  from: string,
  fromName: string,
  avatar: string | null,
  body: string
): Promise<void> {
  const metadata = callMetadata(body, to);
  if (!await policy.canNotify(to, from, "WHISPER_CALL")) return;
  const json = body.slice(CALL_SIGNAL_PREFIX.length);
  let parsed: { id?: string; kind?: string; mode?: string; sdp?: string } = {};
  try {
    parsed = JSON.parse(json);
    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) return;
    if (typeof parsed.id !== "string" || parsed.id.length === 0 || parsed.id.length > 128) return;
  } catch {
    return; // malformed — never show raw payload to the user
  }
  if (metadata.group_id) {
    const group = await policy.groupFor(metadata.group_id, from, to);
    if (!group) return;
    metadata.group_name = safePreview(group.name);
  }
  // Non-invite signals: most are silent protocol chatter. But `cancel`
  // means the caller hung up before the recipient picked up — we want
  // to REPLACE the original "Incoming call" banner with a "Missed call"
  // banner, so the user sees exactly one entry in Notification Center
  // that updates in place (same `apns-collapse-id`).
  if (parsed.kind === "cancel" && parsed.id) {
    // Lean cancel signals do not contain group metadata. Do not invent it or alert for a read/answered invite.
    const { data: invites, error } = await supabase.from("whisper_messages").select("body,read_at")
      .eq("from_user_id", from).eq("to_user_id", to)
      .gte("created_at", new Date(Date.now() - 180_000).toISOString())
      .like("body", "::whisper-call-v1::%").order("created_at", { ascending: false }).limit(100);
    if (error) throw new Error("call invite lookup failed");
    const invite = invites?.find(row => {
      try { const p = JSON.parse(row.body.slice(CALL_SIGNAL_PREFIX.length)); return p.id === parsed.id && p.kind === "invite"; }
      catch { return false; }
    });
    if (!invite || invite.read_at) return;
    Object.assign(metadata, callMetadata(invite.body, to));
    if (metadata.group_id && !await policy.groupFor(metadata.group_id, from, to)) return;
    await sendToUser(to, {
      title: "Missed call",
      body: `from ${fromName.startsWith("@") ? fromName : `@${fromName}`}`,
      category: "WHISPER_CALL_MISSED",
      eventID: `missed:${parsed.id}:${from}`,
      threadID: parsed.id,
      collapseID: `call-${parsed.id}`,
      data: {
        ...metadata,
        kind: "call_missed",
        call_id: parsed.id,
        mode: parsed.mode ?? "audio",
        from_user_id: from,
        from_username: fromName,
        sender_avatar_url: avatar,
      },
    });
    return;
  }
  if (parsed.kind !== "invite") return; // ignore all other non-invite traffic
  // Dedupe retransmits across edge instances. The caller may emit the
  // same `invite` multiple times for delivery reliability, and an in-
  // memory Set only dedupes within ONE warm instance — cold starts and
  // parallel invocations would still produce duplicate pushes (the
  // "7 banners per call" bug). We persist the call_id in a tiny
  // dedupe table; the first INSERT wins, every retry hits the PK
  // conflict and bails out before APNs.
  if (parsed.id) {
    const key = callPushKey(parsed.id, to);
    if (recentInviteIds.has(key)) return;
    recentInviteIds.add(key);
    setTimeout(() => recentInviteIds.delete(key), 120_000);
    const claimed = await claimCallPush(key);
    if (!claimed) return;
  }

  // Prefer VoIP push (wakes the app, CallKit shows the native incoming
  // call UI). If the recipient has no PushKit token registered yet, fall
  // back to a regular alert push so they at least see something. We do
  // NOT send both — the regular alert competes with the CallKit UI and
  // is what produced the "notification fires 100 times" issue.
  const hasVoIP = await recipientHasVoIPToken(to);
  if (hasVoIP) {
    await sendVoIPInvite(to, {
      ...metadata,
      call_id: parsed.id ?? null,
      mode: parsed.mode ?? "audio",
      from_user_id: from,
      from_username: fromName,
      sender_avatar_url: avatar,
    });
  } else {
    await sendToUser(to, {
      title: metadata.group_name ?? "Incoming call",
      body: `from ${fromName.startsWith("@") ? fromName : `@${fromName}`}`,
      category: "WHISPER_CALL",
      threadID: parsed.id ?? `call-${from}`,
      // Same collapse-id as the eventual `missed` banner so APNs replaces
      // (rather than stacks) the entry on the lock screen.
      collapseID: parsed.id ? `call-${parsed.id}` : undefined,
      data: {
        ...metadata,
        kind: "call_invite",
        call_id: parsed.id ?? null,
        mode: parsed.mode ?? "audio",
        from_user_id: from,
        from_username: fromName,
        sender_avatar_url: avatar,
      },
    });
  }
}

// In-memory dedupe of invite call_ids across retransmits (per function
// instance). Edge Functions reuse instances for warm invocations so
// this is effective in practice; cold starts simply re-fanout once.
const recentInviteIds = new Set<string>();

// Persistent cross-instance dedupe of call invite pushes. Returns true
// if THIS invocation claimed the push (i.e. is the first to see this
// call_id), false if another invocation already pushed. Falls open on
// DB error so a transient outage doesn't swallow legitimate calls.
async function claimCallPush(callID: string): Promise<boolean> {
  try {
    const { error } = await supabase
      .from("whisper_call_push_dedupe")
      .insert({ call_id: callID });
    if (error) {
      // Duplicate key (Postgres code 23505) means another instance
      // already pushed for this call_id — skip.
      if ((error as { code?: string }).code === "23505") return false;
      console.error("call push dedupe insert error", error);
      return true; // fall open
    }
    return true;
  } catch (e) {
    console.error("call push dedupe exception", e);
    return true;
  }
}

async function recipientHasVoIPToken(userID: string): Promise<boolean> {
  const { data, error } = await supabase
    .from("whisper_voip_tokens")
    .select("token")
    .eq("user_id", userID)
    .limit(1);
  if (error) {
    console.error("voip token presence check error", error);
    return false;
  }
  return !!(data && data.length > 0);
}

// ------------------------------ VoIP push --------------------------------

interface VoIPTokenRow {
  token: string;
  bundle_id: string | null;
  environment: string | null;
}

async function sendVoIPInvite(
  userID: string,
  data: Record<string, unknown>
): Promise<void> {
  const { data: tokens, error } = await supabase
    .from("whisper_voip_tokens")
    .select("token, bundle_id, environment")
    .eq("user_id", userID);
  if (error) {
    console.error("voip token lookup error", error);
    return;
  }
  if (!tokens || tokens.length === 0) return;
  const jwt = await apnsJWT();
  await Promise.all(
    (tokens as VoIPTokenRow[]).map((row) => deliverVoIP(row, jwt, data))
  );
}

async function deliverVoIP(
  row: VoIPTokenRow,
  jwt: string,
  data: Record<string, unknown>
): Promise<void> {
  const sandbox =
    row.environment === "sandbox" ||
    (row.environment == null && APNS_USE_SANDBOX);
  const host = sandbox ? SANDBOX_HOST : PROD_HOST;
  const bundleID = row.bundle_id ?? APNS_BUNDLE_ID;
  // VoIP push topic is always `<bundleID>.voip`.
  const topic = `${bundleID}.voip`;
  try {
    const res = await fetch(`${host}/3/device/${row.token}`, {
      method: "POST",
      headers: {
        authorization: `bearer ${jwt}`,
        "apns-topic": topic,
        "apns-push-type": "voip",
        "apns-priority": "10",
        "apns-expiration": "0",
        "content-type": "application/json",
      },
      body: JSON.stringify(data),
    });
    if (res.status === 410) {
      const errorBody = await res.json().catch(() => ({}));
      if (errorBody.reason === "Unregistered") {
        await supabase.from("whisper_voip_tokens").delete().eq("token", row.token);
        return;
      }
    }
    if (!res.ok) throw new Error("VoIP delivery rejected");
  } catch {
    throw new Error("VoIP delivery unavailable");
  }
}

async function handleMessage(row: Record<string, any>) {
  const to = row.to_user_id as string | null;
  const from = row.from_user_id as string | null;
  if (!to || !from || to === from || await policy.blocked(to, from)) return;
  // Re-evaluate current consent/age, both block directions, and restrictions before any DM or VoIP fan-out.
  if (!await policy.contactAllowed(from, to)) return;
  const envelope = groupEnvelope(typeof row.body === "string" ? row.body : "");
  const rawBody: string = envelope?.body ?? (typeof row.body === "string" ? row.body : "");
  let groupAvatarPath: string | undefined;
  if (envelope) {
    const group = await policy.groupFor(envelope.id, from, to);
    if (!group) return;
    envelope.name = safePreview(group.name);
    if (typeof group.avatar_path === "string" && new RegExp(`^${envelope.id}/[a-f0-9-]+\\.jpg$`).test(group.avatar_path)) groupAvatarPath = group.avatar_path;
    const mute = await policy.one("whisper_push_group_mutes", { user_id: to, group_id: envelope.id });
    if (mute?.muted) return;
  }
  if (rawBody.startsWith("::whisper-teams-")) {
    if (envelope || rawBody !== `::whisper-teams-v1::${row.id}` || row.read_at) return;
    const { data: allowed, error } = await supabase.rpc("whisper_social_teams_push_allowed", { p_message_id: row.id });
    if (error) throw new Error("Teams notification authorization unavailable");
    if (allowed !== true) return;
    await sendToUser(to, {
      title: "Whisper", body: "You have a team invitation. Open Whisper to review it.", category: "WHISPER_DM",
      eventID: `social-teams:${row.id}`, collapseID: `teams-${row.id}`, threadID: row.thread_id,
      data: { kind: "dm", social_teams: "v1", recipient_user_id: to, message_id: row.id,
        thread_id: row.thread_id, from_user_id: from },
    });
    return;
  }
  if (rawBody.startsWith("::whisper-storytag-v1::")) {
    if (envelope || Deno.env.get("WHISPER_STORY_TAGS_ENABLED") !== "true") return;
    const { data: tag, error } = await supabase.rpc("whisper_story_tag_push", { p_message_id: row.id });
    if (error) throw new Error("Story tag authorization unavailable");
    if (tag?.tagged === true) {
      if (tag.allowed !== true || !await policy.canNotify(to, from, "WHISPER_MENTION")) return;
      const sender = await senderProfileFor(from);
      await sendToUser(to, {
        title: `@${sender.username}`, body: "Tagged you in a story. Open your conversation to view it.",
        category: "WHISPER_DM", eventID: `story-tag:${row.id}`, threadID: row.thread_id,
        data: { kind: "dm", story_tag: "v1", from_user_id: from, from_username: sender.username,
          recipient_user_id: to, message_id: row.id, thread_id: row.thread_id, sender_avatar_url: sender.avatar_url },
      });
    }
    return;
  }
  const profile = await senderProfileFor(from);
  const fromName =
    (row.from_username as string | null) || profile.username;

  // Call control signals — route through dedicated handler / drop chatter.
  if (rawBody.startsWith(CALL_SIGNAL_PREFIX)) {
    if (Date.now() - Date.parse(row.created_at) > 90_000) return;
    await handleCallSignal(to, from, fromName, profile.avatar_url, rawBody);
    return;
  }
  // Post-call summary embed — never push, the in-app bubble is enough.
  if (rawBody.startsWith(CALL_SUMMARY_PREFIX) || row.read_at) return;

  // Embed messages (program/workout) — show a friendly label.
  let body: string = rawBody;
  if (row.embed && typeof row.embed === "object") {
    const kind = row.embed.kind as string | undefined;
    if (kind === "program") body = "Sent you a program";
    else if (kind === "workout") body = "Sent you a workout";
  } else if (body.startsWith("::whisper-program-v1::")) {
    body = "Sent you a program";
  } else if (body.startsWith("::whisper-workout-v1::")) {
    body = "Sent you a workout";
  } else if (body.startsWith("::whisper-coach-proposal-v1::")) {
    body = "New coach suggestion";
  } else if (body.startsWith("::whisper-matchreq-v1::")) {
    body = "Wants to match with you 💘";
  } else if (body.startsWith("::whisper-matched-v1::")) {
    body = "It's a match! 💘";
  }
  if (!body) body = "New message";
  // Short-lived private storage URL only after membership/block/mute/read admission.
  let groupAvatarURL: string | undefined;
  if (groupAvatarPath) {
    const { data } = await supabase.storage.from("whisper-group-avatars").createSignedUrl(groupAvatarPath, 120);
    groupAvatarURL = data?.signedUrl;
  }
  await sendToUser(to, {
    title: envelope ? envelope.name : fromName,
    body: envelope ? `${safePreview(fromName)}: ${safePreview(body)}` : safePreview(body),
    category: "WHISPER_DM",
    eventID: eventIdentity("whisper_messages", row) ?? undefined,
    threadID: envelope ? `group-${envelope.id}` : (row.thread_id as string | null) ?? undefined,
    collapseID: typeof row.id === "string" ? `msg-${row.id}` : undefined,
    data: {
      kind: envelope ? "group" : "dm",
      group_id: envelope?.id,
      group_name: envelope?.name,
      group_avatar_url: groupAvatarURL,
      recipient_user_id: to,
      message_id: row.id,
      thread_id: row.thread_id,
      from_user_id: from,
      from_username: fromName,
      sender_avatar_url: profile.avatar_url,
    },
  });
}

async function handleFollow(row: Record<string, any>) {
  const followee = row.followee_id as string | null;
  const follower = row.follower_id as string | null;
  if (!followee || !follower || followee === follower) return;
  const name =
    (row.follower_username as string | null) || (await usernameFor(follower));
  await sendToUser(followee, {
    title: "New follower",
    body: `@${name} started following you`,
    category: "WHISPER_FOLLOW",
    eventID: eventIdentity("whisper_follows", row) ?? undefined,
    data: { kind: "follow", follower_user_id: follower, follower_username: name },
  });
}

async function handleMessageReaction(row: Record<string, any>) {
  const actor = row.actor_id, recipient = row.recipient_id;
  if (!isUUID(actor) || !isUUID(recipient) || !isUUID(row.message_id)
      || !["❤️", "😂", "😮", "😢", "😡", "👍", "🔥", "🙌", "💯", "🎉", "😍", "🤔", "👀", "🙏", "😭", "🥹", "💀", "👏", "🫶", "😤", "🤝", "✨"].includes(row.emoji)) return;
  const message = await policy.one("whisper_messages", { id: row.message_id });
  if (!message || message.from_user_id !== recipient || message.to_user_id !== actor) return;
  const reaction = await policy.one("whisper_message_reactions", { target_id: row.target_id, actor_id: actor });
  if (!reaction || reaction.operation_id !== row.operation_id || reaction.emoji !== row.emoji) return;
  if (!await policy.canNotify(recipient, actor, "WHISPER_DM")) return;
  const { data: denied, error: deniedError } = await supabase.from("whisper_dm_blocks").select("id")
    .or(`and(protected_user_id.eq.${recipient},blocked_sender_id.eq.${actor}),and(protected_user_id.eq.${actor},blocked_sender_id.eq.${recipient})`).limit(1);
  if (deniedError) throw new Error("reaction privacy lookup failed");
  if (denied?.length) return;
  let group: Record<string, any> | null = null;
  if (row.group_id) {
    group = await policy.groupFor(row.group_id, actor, recipient);
    if (!group || message.logical_group_message_id == null || row.target_id !== `group:${message.logical_group_message_id}`) return;
    const identity = await policy.one("whisper_group_message_identity", { id: message.logical_group_message_id });
    if (!identity || identity.group_id !== row.group_id || identity.sender_id !== recipient) return;
    const preference = await policy.one("whisper_push_group_mutes", { group_id: row.group_id, user_id: recipient });
    if (preference?.muted) return;
  } else if (row.target_id !== `dm:${message.id}` || message.body?.startsWith("::wg-v1::")) return;
  const profile = await senderProfileFor(actor);
  const name = safePreview(profile.username);
  await sendToUser(recipient, {
    title: group ? safePreview(group.name) : name,
    body: `${name.startsWith("@") ? name : `@${name}`} reacted ${row.emoji} to your message`,
    category: "WHISPER_DM",
    eventID: eventIdentity("whisper_message_reaction_events", row) ?? undefined,
    threadID: group ? `group-${row.group_id}` : message.thread_id,
    collapseID: `reaction-${row.id}`,
    data: { kind: group ? "group" : "dm", message_reaction: "v1", reaction_event_id: row.id,
      recipient_user_id: recipient, group_id: row.group_id ?? undefined, group_name: group?.name,
      message_id: message.id, thread_id: message.thread_id, from_user_id: actor,
      from_username: profile.username, sender_avatar_url: profile.avatar_url },
  });
}

async function handleLike(row: Record<string, any>) {
  const liker = row.user_id as string | null;
  const postID = row.post_id as string | null;
  if (!liker || !postID) return;
  const post = await policy.one("whisper_posts", { id: postID });
  if (!post || !await policy.postVisible(post, liker)) return;
  const owner = post?.user_id as string | undefined;
  if (!owner || owner === liker) return;
  const name = await usernameFor(liker);
  await sendToUser(owner, {
    title: "New like",
    body: `@${name} liked your post`,
    category: "WHISPER_LIKE",
    eventID: eventIdentity("whisper_post_likes", row) ?? undefined,
    data: { kind: "like", like_id: `${postID}:${liker}:${row.created_at}`, post_id: postID, liker_user_id: liker, liker_username: name },
  });
}

async function handleProposal(row: Record<string, any>) {
  const client = row.client_user_id as string | null;
  const coach = row.coach_user_id as string | null;
  const id = row.id as string | null;
  const kind = (row.kind as string | null) ?? "note";
  if (!client || !coach || !id || row.status !== "pending") return;
  const relationship = await policy.one("whisper_coach_requests", { client_user_id: client, coach_user_id: coach });
  if (relationship?.status !== "accepted") return;

  // Coach display name: profiles is the normalized source of truth.
  // Fall back to whisper_profiles, then "Your coach".
  let coachName = "Your coach";
  try {
    const { data: p } = await supabase
      .from("profiles")
      .select("display_name, username")
      .eq("id", coach)
      .maybeSingle();
    coachName =
      (p?.display_name as string | undefined) ||
      (p?.username as string | undefined) ||
      coachName;
  } catch {
    // profiles may not be readable with service role policies—ignore.
  }
  if (coachName === "Your coach") {
    const { data: wp } = await supabase
      .from("whisper_profiles")
      .select("username")
      .eq("user_id", coach)
      .maybeSingle();
    if (wp?.username) coachName = wp.username as string;
  }

  const bodyByKind: Record<string, string> = {
    macros: "Suggested macro changes",
    diet_plan: "Suggested a new diet plan",
    workout: "Suggested a workout tweak",
    exercise_swap: "Suggested an exercise swap",
    note: "Sent you a coaching note",
  };
  const body = bodyByKind[kind] ?? "Sent you a suggestion";

  await sendToUser(client, {
    title: coachName,
    body,
    category: "JASPER_COACH_PROPOSAL",
    eventID: eventIdentity("whisper_coach_proposals", row) ?? undefined,
    threadID: `coach-proposal-${coach}`,
    data: {
      kind: "coach_proposal",
      proposal_id: id,
      coach_user_id: coach,
      proposal_kind: kind,
      deep_link: `jasper://coach-proposal/${id}`,
    },
  });
}

async function handleMention(row: Record<string, any>) {
  const recipient = row.mentioned_user_id as string | null;
  const author = row.author_id as string | null;
  if (!recipient || !author || recipient === author) return;
  const name = await usernameFor(author);
  const sourceType = (row.source_type as string | null) ?? "post";
  if (!isUUID(row.source_id)) return;
  // DM mentions already have a recipient-scoped message notification.
  if (sourceType === "dm") return;
  let postID = row.source_id as string;
  if (sourceType === "comment") {
    const comment = await policy.one("whisper_post_comments", { id: row.source_id });
    if (!comment || comment.user_id !== author) return;
    postID = comment.post_id;
  } else if (!["post", "reel"].includes(sourceType)) return;
  const post = await policy.one("whisper_posts", { id: postID });
  if (!post || (sourceType !== "comment" && post.user_id !== author)
      || !await policy.postVisible(post, recipient) || !await policy.postVisible(post, author)) return;
  const body =
    sourceType === "comment"
      ? "mentioned you in a comment"
      : sourceType === "reel"
      ? "mentioned you in a reel"
      : sourceType === "dm"
      ? "mentioned you in a chat"
      : "mentioned you in a post";
  await sendToUser(recipient, {
    title: `@${name}`,
    body,
    category: "WHISPER_MENTION",
    eventID: eventIdentity("whisper_mentions", row) ?? undefined,
    data: {
      kind: "mention",
      source_type: sourceType,
      source_id: row.source_id ?? null,
      author_user_id: author,
      author_username: name,
    },
  });
}

async function handleReturnPost(row: Record<string, any>) {
  if (Deno.env.get("WHISPER_RETURN_POSTS_ENABLED") !== "true" || !isUUID(row.user_id)) return;
  const { data, error } = await supabase.rpc("whisper_return_post_candidates", { p_post: row.id });
  if (error) throw new Error("Return-post audience unavailable");
  if (!Array.isArray(data) || data.length > 100 || !data.every(isUUID)) throw new Error("Invalid return-post audience");
  const author = row.user_id;
  const name = await usernameFor(author);
  for (const recipient of new Set<string>(data)) {
    const prefs = await policy.one("whisper_notification_prefs", { user_id: recipient });
    if (prefs?.new_posts_synced !== true || prefs.new_posts !== true
      || !await policy.one("whisper_follows", { follower_id: recipient, followee_id: author })
      || !await policy.postVisible(row, recipient)) continue;
    await sendToUser(recipient, { title: `@${name} has a new post`, body: "Catch up with someone you follow.",
      category: "WHISPER_NEW_POST", eventID: `return-post:${row.id}:${recipient}`, threadID: `return-post-${author}`,
      data: { kind: "whisper_new_post", return_post: "v1", postID: row.id, post_id: row.id, fromUsername: name, author_user_id: author, recipient_user_id: recipient },
    });
  }
}

async function handleStoryResponse(row: Record<string, any>) {
  const owner = row.story_owner_id as string | null;
  const responder = row.responder_id as string | null;
  if (!owner || !responder || owner === responder) return;
  if (row.read_at || !isUUID(row.story_id)) return;
  const story = await policy.one("whisper_stories", { id: row.story_id });
  if (!story || story.user_id !== owner || story.is_ghost || Date.parse(story.expires_at) <= Date.now()
      || !await policy.profileVisible(owner, responder)) return;
  // Native and web quick reactions already send a DM; keep Activity's row without a second alert.
  if (row.kind === "reaction") return;
  const name = await usernameFor(responder);
  const kind = (row.kind as string | null) ?? "question";
  const response = (row.response as string | null) ?? "";
  const action = storyResponseAction(kind);
  const trimmed = response.length > 80 ? response.slice(0, 77) + "\u2026" : response;
  await sendToUser(owner, {
    title: `@${name} ${action}`,
    body: trimmed.length > 0 ? trimmed : "Tap to view",
    category: "WHISPER_STORY_RESPONSE",
    eventID: eventIdentity("whisper_story_responses", row) ?? undefined,
    data: {
      kind: "story_response",
      story_id: row.story_id ?? null,
      response_id: row.id,
      response_kind: kind,
      responder_user_id: responder,
      responder_username: name,
    },
  });
}

async function handleThoughtReply(row: Record<string, any>) {
  const owner = row.thought_user_id as string | null;
  const replier = row.replier_user_id as string | null;
  if (!owner || !replier || owner === replier || row.read_at) return;
  const name =
    (row.replier_username as string | null) || (await usernameFor(replier));
  const text = (row.body as string | null) ?? "";
  const trimmed = text.length > 140 ? text.slice(0, 137) + "…" : text;
  await sendToUser(owner, {
    title: `@${name} replied to your thought`,
    body: trimmed.length > 0 ? trimmed : "Tap to view",
    category: "WHISPER_THOUGHT_REPLY",
    eventID: eventIdentity("whisper_thought_replies", row) ?? undefined,
    threadID: `thought-reply-${owner}`,
    data: {
      kind: "whisper_thought_reply",
      reply_id: row.id ?? null,
      replier_user_id: replier,
      replier_username: name,
      replier_avatar_url: row.replier_avatar_url ?? null,
    },
  });
}

async function handleComment(row: Record<string, any>) {
  const commenter = row.user_id as string | null;
  const postID = row.post_id as string | null;
  if (!commenter || !postID) return;
  const post = await policy.one("whisper_posts", { id: postID });
  if (!post || !await policy.postVisible(post, commenter)) return;
  const recipients = new Set<string>([post.user_id]);
  const parentID = row.parent_comment_id ?? row.parent_id;
  if (isUUID(parentID)) {
    const parent = await policy.one("whisper_post_comments", { id: parentID });
    if (parent?.post_id === postID) recipients.add(parent.user_id);
  }
  const name =
    (row.username as string | null) || (await usernameFor(commenter));
  const text = (row.body as string | null) ?? "";
  for (const owner of recipients) {
    if (owner === commenter || !await policy.postVisible(post, owner)) continue;
    await sendToUser(owner, {
    title: `@${name} ${owner === post.user_id ? "commented" : "replied to your comment"}`,
    body: text.length > 120 ? text.slice(0, 117) + "…" : text || "New comment",
    category: "WHISPER_COMMENT",
    eventID: eventIdentity("whisper_post_comments", row) ?? undefined,
    data: {
      kind: "comment",
      post_id: postID,
      comment_id: row.id,
      commenter_user_id: commenter,
      commenter_username: name,
    },
    });
  }
}

// ------------------------------ HTTP entry --------------------------------
//
// Supabase Database Webhook payload shape:
//   { type: "INSERT", table: "whisper_messages", record: {...}, schema: "public", ... }

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

export async function handleRequest(req: Request): Promise<Response> {
  if (req.method === "OPTIONS") return new Response(null, { status: 204, headers: corsHeaders });
  const response = await handleWebhook(req);
  for (const [key, value] of Object.entries(corsHeaders)) response.headers.set(key, value);
  return response;
}

async function handleWebhook(req: Request): Promise<Response> {
  if (!await authenticWebhook(req.headers.get("authorization"), PUSH_WEBHOOK_KEY)) {
    return new Response("unauthorized", { status: 401 });
  }
  if (req.method !== "POST") {
    return new Response("method not allowed", { status: 405 });
  }
  let body: any;
  try {
    const text = await req.text();
    if (text.length > 262144) return new Response("payload too large", { status: 413 });
    body = JSON.parse(text);
  } catch {
    return new Response("bad json", { status: 400 });
  }
  const table = body?.table as string | undefined;
  const type = body?.type as string | undefined;
  const incoming = body?.record as Record<string, any> | undefined;
  if (body?.schema !== "public" || !table || !Object.hasOwn(eventKeys, table)) return new Response("ignored");
  if (type !== "INSERT" || !incoming || typeof incoming !== "object" || Array.isArray(incoming)) {
    return new Response("ok", { status: 200 });
  }
  try {
    const record = await policy.canonicalRecord(table, incoming);
    if (!record) return new Response("ignored");
    switch (table) {
      case "whisper_posts":
        await handleReturnPost(record);
        break;
      case "whisper_messages":
        await handleMessage(record);
        break;
      case "whisper_message_reaction_events":
        await handleMessageReaction(record);
        break;
      case "whisper_follows":
        await handleFollow(record);
        break;
      case "whisper_post_likes":
        await handleLike(record);
        break;
      case "whisper_post_comments":
        await handleComment(record);
        break;
      case "whisper_mentions":
        await handleMention(record);
        break;
      case "whisper_story_responses":
        await handleStoryResponse(record);
        break;
      case "whisper_coach_proposals":
        await handleProposal(record);
        break;
      case "whisper_thought_replies":
        await handleThoughtReply(record);
        break;
      default:
        break;
    }
  } catch {
    console.error("push fanout failed", { table });
    return new Response("delivery unavailable", { status: 503 });
  }
  return new Response("ok", { status: 200 });
}

if (import.meta.main) Deno.serve(handleRequest);
