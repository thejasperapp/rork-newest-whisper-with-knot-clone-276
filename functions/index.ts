
// functions/index.ts — Whisper billing backend (Stripe + Supabase + Resend + LiveKit).
//
// Routes:
//   POST /stripe/checkout   — create a Stripe Checkout Session for Whisper One
//   GET  /stripe/session    — verify a Checkout Session (success page)
//   POST /webhooks/stripe   — Stripe webhook: verifies signature, updates the
//                             member's account status in Supabase, and sends
//                             branded transactional emails via Resend
//   POST /admin/broadcast   — send a branded email to ALL Supabase users
//                             (preview / test / send modes, gated by
//                             BROADCAST_SECRET)
//
// Secrets (set in the project envs UI, never hardcoded):
//   STRIPE_SECRET_KEY          sk_live_... / sk_test_...
//   STRIPE_WEBHOOK_SECRET      whsec_...
//   SUPABASE_SERVICE_ROLE_KEY  service_role key (Supabase → Settings → API)
//   RESEND_API_KEY             re_... (resend.com → API Keys)
//   RESEND_FROM                e.g. "Whisper <hello@mydailywhisper.com>" (optional)
//   RESEND_AUDIENCE_ID         Resend audience for marketing contacts (optional)
//   BROADCAST_SECRET           shared secret that unlocks /admin/broadcast
//   LIVEKIT_API_KEY            LiveKit API key (for /livekit/token)
//   LIVEKIT_API_SECRET         LiveKit API secret (for /livekit/token)
//   LIVEKIT_URL                LiveKit server URL (for /livekit/token)

import { tracedKnotRequest } from './knot-request-trace';
import { receiveTeamsEvent, teamsEventPath, type TeamsReceiverEnv } from './teams-invitations';
import { passwordLogin } from './password-login';
import { inspectKnotTextTransport, inspectKnotToolSelection, knotLive } from './knot-live';
import { knotAITransport } from './knot-ai-transport';
import { inspectKnotKeyBinding } from './knot-key-binding';
import { inspectKnotDocumentTransport } from './knot-document-transport-check';
import { dispatchKnotActor, knotShellRoute, type KnotShellEnv } from './knot-shell';
import { knotBrowserRoute } from './knot-browser';
import { knotArtifactSharingRoute } from './knot-artifact-sharing';
export { KnotShellConversation } from './knot-shell';
import { knotBackgroundRoute } from './knot-background';
import { knotOwnedTurnsRoute } from './knot-owned-turns';
import { knotConversationsRoute } from './knot-conversations';
export { KnotConversationAccount } from './knot-conversations';
import { knotContactClaimRoute } from './knot-contact';
export { KnotBackgroundAccount } from './knot-background';
import { inspectKnotVoicePolicy, knotVoiceToken, type KnotVoiceEnv } from './knot-voice';
import { knotVoiceCompletions, knotVoiceEnd } from './knot-voice-bridge';
export { KnotResponseLimiter } from './knot-response-limiter';
export { WhisperLoginLimiter } from './login-limiter';
import { notebookTranscription } from "./notebook-transcription";
import { isMeetingIdentity, meetingInvitationLink, parseMeetingInvitation } from "./meeting-links";
import { routeJasperMeetings, type JasperEnv } from "./jasper-meetings";
import { googlePublicRoute } from "./jasper-google-calendar";
export { JasperMeetingAccount } from "./jasper-meetings";

type Env = JasperEnv & TeamsReceiverEnv & KnotVoiceEnv & KnotShellEnv & {
  EXPO_PUBLIC_SUPABASE_ANON_KEY?: string;
  STRIPE_SECRET_KEY?: string;
  STRIPE_PUBLISHABLE_KEY?: string;
  STRIPE_WEBHOOK_SECRET?: string;
  SUPABASE_SERVICE_ROLE_KEY?: string;
  RESEND_API_KEY?: string;
  RESEND_FROM?: string;
  RESEND_AUDIENCE_ID?: string;
  BROADCAST_SECRET?: string;
  LIVEKIT_API_KEY?: string;
  LIVEKIT_API_SECRET?: string;
  LIVEKIT_URL?: string;
  /** Server-side OpenAI key powering the /ai/chat proxy (Ember + notes). */
  OPENAI_API_KEY?: string;
  /** Rork toolkit credentials for the /webrtc/ice-servers proxy (TURN). */
  EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY?: string;
  RORK_TOOLKIT_SECRET_KEY?: string;
  EXPO_PUBLIC_TOOLKIT_URL?: string;
};

// ---------------------------------------------------------------------------
// Stripe env self-healing — saved dashboard values routinely arrive with
// paste artifacts (wrapping quotes, labels like "Secret key sk_live_…",
// zero-width characters) or land in the wrong slot entirely (secret and
// publishable swapped). Rather than fail as unknown_format, every request
// normalizes the three values: recognizable Stripe tokens are extracted
// from ANY of the three slots and routed to the slot they belong to.
// /ping reports safe metadata (prefix + length only — never key material)
// so misconfigurations stay diagnosable without exposing secrets.

const STRIPE_TOKEN_RE =
  /(?:sk|pk|rk)_(?:live|test)_[A-Za-z0-9]{8,}|whsec_[A-Za-z0-9]{8,}/g;

type StripeEnvFieldDiag = {
  set: boolean;
  detectedPrefix: string;
  length: number;
  repaired: boolean;
};

type StripeEnvDiag = {
  secretKey: StripeEnvFieldDiag;
  publishableKey: StripeEnvFieldDiag;
  webhookSecret: StripeEnvFieldDiag;
};

/** Most recent normalization result, surfaced by /ping for diagnostics. */
let stripeEnvDiag: StripeEnvDiag | null = null;

function detectStripePrefix(value: string): string {
  const known = [
    "sk_live_",
    "sk_test_",
    "rk_live_",
    "rk_test_",
    "pk_live_",
    "pk_test_",
    "whsec_",
  ];
  for (const prefix of known) {
    if (value.startsWith(prefix)) return prefix;
  }
  return value ? "unrecognized" : "empty";
}

function stripPasteArtifacts(raw: string | undefined): string {
  return (raw ?? "").replace(/[\u200b\u200c\u200d\ufeff]/g, "").trim();
}

/**
 * Returns a copy of the env with the Stripe values repaired: paste
 * artifacts stripped and each recognizable token routed to its proper
 * slot, so a swapped or label-wrapped paste can never break payments.
 */
function normalizeStripeEnv(base: Env): Env {
  const rawSecret = stripPasteArtifacts(base.STRIPE_SECRET_KEY);
  const rawPublishable = stripPasteArtifacts(base.STRIPE_PUBLISHABLE_KEY);
  const rawWebhook = stripPasteArtifacts(base.STRIPE_WEBHOOK_SECRET);

  const pool: string[] = [rawSecret, rawPublishable, rawWebhook].flatMap(
    (value) => value.match(STRIPE_TOKEN_RE) ?? []
  );
  const resolve = (
    current: string,
    matches: (token: string) => boolean
  ): string => {
    if (matches(current)) return current;
    return pool.find(matches) ?? current;
  };

  const secretKey = resolve(
    rawSecret,
    (t) => t.startsWith("sk_") || t.startsWith("rk_")
  );
  const publishableKey = resolve(rawPublishable, (t) => t.startsWith("pk_"));
  const webhookSecret = resolve(rawWebhook, (t) => t.startsWith("whsec_"));

  stripeEnvDiag = {
    secretKey: {
      set: rawSecret.length > 0,
      detectedPrefix: detectStripePrefix(secretKey),
      length: secretKey.length,
      repaired: secretKey !== (base.STRIPE_SECRET_KEY ?? ""),
    },
    publishableKey: {
      set: rawPublishable.length > 0,
      detectedPrefix: detectStripePrefix(publishableKey),
      length: publishableKey.length,
      repaired: publishableKey !== (base.STRIPE_PUBLISHABLE_KEY ?? ""),
    },
    webhookSecret: {
      set: rawWebhook.length > 0,
      detectedPrefix: detectStripePrefix(webhookSecret),
      length: webhookSecret.length,
      repaired: webhookSecret !== (base.STRIPE_WEBHOOK_SECRET ?? ""),
    },
  };

  return {
    ...base,
    STRIPE_SECRET_KEY: secretKey || undefined,
    STRIPE_PUBLISHABLE_KEY: publishableKey || undefined,
    STRIPE_WEBHOOK_SECRET: webhookSecret || undefined,
  };
}

const SUPABASE_URL = "https://uryyyegnbtlmyhqlgndy.supabase.co";
const SITE_URL = "https://mydailywhisper.com";
const DEFAULT_FROM = "Whisper <onboarding@resend.dev>";

type BadgeRole = "coach" | "athlete" | "verified";

interface Plan {
  name: string;
  unitAmount: number;
  interval: "month" | "year";
  /** Set for verified-badge plans; checkout requires an approved application. */
  badgeRole?: BadgeRole;
  /** Whisper Business+ — fulfills into whisper_business_plus (open signup). */
  businessPlus?: boolean;
}

/** Whisper plans — single source of truth for what checkout charges. */
const PLANS: Record<string, Plan> = {
  "one-monthly": {
    name: "Whisper One",
    unitAmount: 1499,
    interval: "month",
  },
  "one-annual": {
    name: "Whisper One (Annual)",
    unitAmount: 11999,
    interval: "year",
  },
  // Verified badges: charged once per year, only purchasable after a human
  // approves the application. Prices are in cents — edit here to change.
  "coach-annual": {
    name: "Whisper Verified Coach (Annual)",
    unitAmount: 24999,
    interval: "year",
    badgeRole: "coach",
  },
  "athlete-annual": {
    name: "Whisper Verified Athlete (Annual)",
    unitAmount: 9999,
    interval: "year",
    badgeRole: "athlete",
  },
  "verified-annual": {
    name: "Whisper Verified (Annual)",
    unitAmount: 9999,
    interval: "year",
    badgeRole: "verified",
  },
  // Whisper Business+ — the business workspace plan: custom hiring
  // questionnaires with auto-matching, team roles, the private HQ group,
  // team chat, the internal calendar, and meeting presentation tools.
  "business-plus-monthly": {
    name: "Whisper Business+",
    unitAmount: 10000,
    interval: "month",
    businessPlus: true,
  },
  "business-plus-annual": {
    name: "Whisper Business+ (Annual)",
    unitAmount: 99999,
    interval: "year",
    businessPlus: true,
  },
};

const BADGE_APPLICATION_TABLE: Record<BadgeRole, string> = {
  coach: "whisper_coach_applications",
  athlete: "whisper_athlete_applications",
  verified: "whisper_verification_requests",
};

const BADGE_PROFILE_FLAG: Record<BadgeRole, string> = {
  coach: "is_coach",
  athlete: "is_athlete",
  verified: "is_verified",
};

const BADGE_LABEL: Record<BadgeRole, string> = {
  coach: "Verified Coach",
  athlete: "Verified Athlete",
  verified: "Verified",
};

const BADGE_GREETING: Record<BadgeRole, string> = {
  coach: "Coach",
  athlete: "Athlete",
  verified: "you're Verified",
};

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, DELETE, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, Authorization, X-Whisper-Authorization",
};

// ---------------------------------------------------------------------------
// Link previews — GET /link/preview?url=… unfurls a public page's Open Graph /
// Twitter-card metadata (title · description · image · site name) so chat
// links render as cards on web (browsers can't read a third-party page's
// tags cross-origin). http(s) only, private/loopback hosts refused, 6s
// timeout, first 256 KB of HTML only, cached at the edge for a day.
// ---------------------------------------------------------------------------

const LINK_PREVIEW_MAX_BYTES = 256 * 1024;

function isPrivateHost(host: string): boolean {
  const h = host.toLowerCase();
  if (h === "localhost" || h.endsWith(".localhost") || h.endsWith(".local") || h.endsWith(".internal")) {
    return true;
  }
  const v4 = h.match(/^(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})$/);
  if (v4) {
    const a = Number(v4[1]);
    const b = Number(v4[2]);
    if (a === 10 || a === 127 || a === 0) return true;
    if (a === 169 && b === 254) return true;
    if (a === 172 && b >= 16 && b <= 31) return true;
    if (a === 192 && b === 168) return true;
    return false;
  }
  if (h.includes(":")) {
    // IPv6 literal — refuse loopback / link-local / unique-local outright.
    return h === "::1" || h.startsWith("fe80") || h.startsWith("fc") || h.startsWith("fd");
  }
  return false;
}

function decodeHtmlEntities(s: string): string {
  return s
    .replace(/&amp;/g, "&")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&nbsp;/g, " ")
    .replace(/&#(\d+);/g, (_m, n: string) => {
      const code = Number(n);
      return Number.isFinite(code) && code > 0 && code < 0x110000 ? String.fromCodePoint(code) : "";
    })
    .trim();
}

/** Reads `<meta property|name="key" content="…">` in either attribute order. */
function readMeta(html: string, key: string): string | null {
  const escaped = key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const patterns = [
    new RegExp(`<meta[^>]+(?:property|name)=["']${escaped}["'][^>]*content=["']([^"']*)["']`, "i"),
    new RegExp(`<meta[^>]+content=["']([^"']*)["'][^>]*(?:property|name)=["']${escaped}["']`, "i"),
  ];
  for (const re of patterns) {
    const m = html.match(re);
    if (m?.[1]) {
      const v = decodeHtmlEntities(m[1]);
      if (v) return v;
    }
  }
  return null;
}

async function handleLinkPreview(raw: string): Promise<Response> {
  let target: URL;
  try {
    target = new URL(raw);
  } catch {
    return json({ error: "invalid_url" }, 400);
  }
  if (target.protocol !== "http:" && target.protocol !== "https:") {
    return json({ error: "unsupported_scheme" }, 400);
  }
  if (isPrivateHost(target.hostname)) {
    return json({ error: "refused" }, 400);
  }

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 6000);
  try {
    const res = await fetch(target.toString(), {
      redirect: "follow",
      signal: controller.signal,
      headers: {
        // A browser-ish UA + the Facebook crawler token so sites serve their
        // share metadata instead of a JS shell or a bot wall.
        "User-Agent":
          "Mozilla/5.0 (compatible; WhisperBot/1.0; +https://mydailywhisper.com) facebookexternalhit/1.1",
        Accept: "text/html,application/xhtml+xml;q=0.9,*/*;q=0.5",
        "Accept-Language": "en-US,en;q=0.8",
      },
    });
    const finalUrl = res.url || target.toString();
    const type = (res.headers.get("content-type") ?? "").toLowerCase();
    if (type.startsWith("image/")) {
      return new Response(
        JSON.stringify({ url: finalUrl, kind: "image", image: finalUrl, siteName: target.hostname }),
        { headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=86400", ...CORS_HEADERS } }
      );
    }
    if (!res.ok || !type.includes("html")) {
      return json({ url: finalUrl, kind: "link", title: null, siteName: target.hostname }, 200);
    }

    // Read at most the first 256 KB — metadata lives in <head>.
    let html = "";
    const reader = res.body?.getReader();
    if (reader) {
      const decoder = new TextDecoder();
      let received = 0;
      while (received < LINK_PREVIEW_MAX_BYTES) {
        const { value, done } = await reader.read();
        if (done) break;
        received += value.byteLength;
        html += decoder.decode(value, { stream: true });
        if (/<\/head>/i.test(html)) break;
      }
      try {
        await reader.cancel();
      } catch {
        /* stream already closed */
      }
    } else {
      html = (await res.text()).slice(0, LINK_PREVIEW_MAX_BYTES);
    }

    const titleTag = html.match(/<title[^>]*>([^<]*)<\/title>/i)?.[1];
    const title =
      readMeta(html, "og:title") ?? readMeta(html, "twitter:title") ?? (titleTag ? decodeHtmlEntities(titleTag) : null);
    const description =
      readMeta(html, "og:description") ?? readMeta(html, "twitter:description") ?? readMeta(html, "description");
    let image = readMeta(html, "og:image") ?? readMeta(html, "og:image:url") ?? readMeta(html, "twitter:image");
    if (image) {
      try {
        image = new URL(image, finalUrl).toString();
        if (!image.startsWith("http")) image = null;
      } catch {
        image = null;
      }
    }
    const siteName = readMeta(html, "og:site_name") ?? target.hostname.replace(/^www\./, "");

    return new Response(
      JSON.stringify({
        url: finalUrl,
        kind: "link",
        title: title ? title.slice(0, 200) : null,
        description: description ? description.slice(0, 300) : null,
        image,
        siteName,
      }),
      { headers: { "Content-Type": "application/json", "Cache-Control": "public, max-age=86400", ...CORS_HEADERS } }
    );
  } catch {
    return json({ url: target.toString(), kind: "link", title: null, siteName: target.hostname }, 200);
  } finally {
    clearTimeout(timer);
  }
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

async function stripeRequest(
  env: Env,
  path: string,
  params?: URLSearchParams,
  /** When set, the call runs on this connected (Stripe Connect) account. */
  stripeAccount?: string
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    method: params ? "POST" : "GET",
    headers: {
      Authorization: `Bearer ${env.STRIPE_SECRET_KEY}`,
      ...(stripeAccount ? { "Stripe-Account": stripeAccount } : {}),
      ...(params
        ? { "Content-Type": "application/x-www-form-urlencoded" }
        : {}),
    },
    body: params ? params.toString() : undefined,
  });
  const data = (await res.json()) as Record<string, unknown>;
  return { ok: res.ok, status: res.status, data };
}

/** Service-role Supabase RPC call — returns parsed JSON or null on error. */
async function supabaseRpc<T>(
  env: Env,
  fn: string,
  args: Record<string, unknown>
): Promise<T | null> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1/rpc/${fn}`, {
      method: "POST",
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(args),
    });
    if (!res.ok) return null;
    return (await res.json().catch(() => null)) as T | null;
  } catch {
    return null;
  }
}

/** DELETE a Stripe resource (immediate subscription cancellation on refunds). */
async function stripeDelete(
  env: Env,
  path: string
): Promise<{ ok: boolean; status: number; data: Record<string, unknown> }> {
  const res = await fetch(`https://api.stripe.com/v1${path}`, {
    method: "DELETE",
    headers: { Authorization: `Bearer ${env.STRIPE_SECRET_KEY}` },
  });
  const data = (await res.json()) as Record<string, unknown>;
  return { ok: res.ok, status: res.status, data };
}

// ---------------------------------------------------------------------------
// Supabase admin helpers (service role — server-side only)
// ---------------------------------------------------------------------------

async function supabaseAdmin(
  env: Env,
  path: string,
  init: { method: string; body?: unknown; prefer?: string }
): Promise<{ ok: boolean; status: number }> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) {
    console.error("SUPABASE_SERVICE_ROLE_KEY not set — skipping DB update");
    return { ok: false, status: 0 };
  }
  const res = await fetch(`${SUPABASE_URL}/rest/v1${path}`, {
    method: init.method,
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
      ...(init.prefer ? { Prefer: init.prefer } : {}),
    },
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  });
  if (!res.ok) {
    const text = await res.text();
    console.error("Supabase admin call failed", {
      path,
      status: res.status,
      body: text.slice(0, 300),
    });
  }
  return { ok: res.ok, status: res.status };
}

/** Count rows with the service role key (HEAD + count=exact). */
async function supabaseCount(env: Env, path: string): Promise<number> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return 0;
  const res = await fetch(`${SUPABASE_URL}/rest/v1${path}`, {
    method: "HEAD",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      Prefer: "count=exact",
    },
  });
  if (!res.ok) return 0;
  const range = res.headers.get("content-range") ?? "";
  const total = Number(range.split("/")[1] ?? "0");
  return Number.isFinite(total) ? total : 0;
}

/**
 * Probe that a table (and optionally specific columns) exists — used by
 * /ping?db=1 to verify SQL migrations landed. Returns "ok", "missing_<status>"
 * (404 = table absent, 400 = column absent), or an availability marker.
 * Never returns row data.
 */
async function dbProbe(env: Env, path: string): Promise<string> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return "no_service_key";
  try {
    const res = await fetch(`${SUPABASE_URL}/rest/v1${path}`, {
      method: "HEAD",
      headers: { apikey: key, Authorization: `Bearer ${key}` },
    });
    return res.ok ? "ok" : `missing_${res.status}`;
  } catch {
    return "unreachable";
  }
}

/** Read rows with the service role key. Returns null on any failure. */
async function supabaseSelect(
  env: Env,
  path: string
): Promise<unknown[] | null> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  const res = await fetch(`${SUPABASE_URL}/rest/v1${path}`, {
    headers: { apikey: key, Authorization: `Bearer ${key}` },
  });
  if (!res.ok) return null;
  const data = (await res.json()) as unknown;
  return Array.isArray(data) ? data : null;
}

/** True when this subscription was already recorded (webhook or fallback ran). */
async function membershipExists(
  env: Env,
  subscriptionId: string,
  table: "whisper_one_members" | "whisper_badge_members" = "whisper_one_members"
): Promise<boolean> {
  const rows = await supabaseSelect(
    env,
    `/${table}?stripe_subscription_id=eq.${encodeURIComponent(
      subscriptionId
    )}&select=stripe_subscription_id&limit=1`
  );
  return Array.isArray(rows) && rows.length > 0;
}

/** True when this user has an approved application for the given badge role. */
async function hasApprovedApplication(
  env: Env,
  userId: string,
  role: BadgeRole
): Promise<boolean> {
  const rows = await supabaseSelect(
    env,
    `/${BADGE_APPLICATION_TABLE[role]}?user_id=eq.${encodeURIComponent(
      userId
    )}&status=eq.approved&select=id&limit=1`
  );
  return Array.isArray(rows) && rows.length > 0;
}

interface MembershipRecord {
  userId: string | null;
  email: string | null;
  plan: string;
  status: "active" | "past_due" | "cancelled";
  stripeCustomerId: string | null;
  stripeSubscriptionId: string | null;
}

/**
 * Persist a membership change: upsert the whisper_one_members ledger row and,
 * when we know the Whisper user id, flip the is_one flag on their profile.
 */
async function applyMembership(
  env: Env,
  record: MembershipRecord
): Promise<void> {
  await supabaseAdmin(env, "/whisper_one_members?on_conflict=stripe_subscription_id", {
    method: "POST",
    prefer: "resolution=merge-duplicates",
    body: {
      user_id: record.userId,
      email: record.email,
      plan: record.plan,
      status: record.status,
      stripe_customer_id: record.stripeCustomerId,
      stripe_subscription_id: record.stripeSubscriptionId,
      updated_at: new Date().toISOString(),
    },
  });

  if (record.userId) {
    await supabaseAdmin(
      env,
      `/whisper_profiles?user_id=eq.${encodeURIComponent(record.userId)}`,
      {
        method: "PATCH",
        body: {
          is_one: record.status === "active",
          one_plan: record.status === "active" ? record.plan : null,
        },
      }
    );
  }
}

/**
 * Persist a verified-badge purchase: upsert the whisper_badge_members ledger
 * row and flip the role flag (is_coach / is_athlete) on BOTH profile tables —
 * mirrors what the iOS moderation dashboard used to do at approval time.
 */
async function applyBadgeMembership(
  env: Env,
  record: MembershipRecord & { role: BadgeRole }
): Promise<void> {
  await supabaseAdmin(
    env,
    "/whisper_badge_members?on_conflict=stripe_subscription_id",
    {
      method: "POST",
      prefer: "resolution=merge-duplicates",
      body: {
        user_id: record.userId,
        email: record.email,
        role: record.role,
        plan: record.plan,
        status: record.status,
        stripe_customer_id: record.stripeCustomerId,
        stripe_subscription_id: record.stripeSubscriptionId,
        updated_at: new Date().toISOString(),
      },
    }
  );

  if (record.userId) {
    const active = record.status === "active";
    const flag = BADGE_PROFILE_FLAG[record.role];
    const uid = encodeURIComponent(record.userId);
    // The blue check only exists on `profiles`; coach/athlete flags live on
    // both profile tables.
    if (record.role !== "verified") {
      await supabaseAdmin(env, `/whisper_profiles?user_id=eq.${uid}`, {
        method: "PATCH",
        body: { [flag]: active },
      });
    }
    await supabaseAdmin(env, `/profiles?id=eq.${uid}`, {
      method: "PATCH",
      body: { [flag]: active },
    });
  }
}

/**
 * Persist a Business+ purchase: upsert the whisper_business_plus ledger row.
 * The row IS the entitlement — the suite, meeting tools, and hiring surfaces
 * all check for an active row owned by (or shared with) the caller.
 */
async function applyBusinessPlusMembership(
  env: Env,
  record: MembershipRecord
): Promise<void> {
  await supabaseAdmin(
    env,
    "/whisper_business_plus?on_conflict=stripe_subscription_id",
    {
      method: "POST",
      prefer: "resolution=merge-duplicates",
      body: {
        user_id: record.userId,
        email: record.email,
        plan: record.plan,
        status: record.status,
        stripe_customer_id: record.stripeCustomerId,
        stripe_subscription_id: record.stripeSubscriptionId,
        updated_at: new Date().toISOString(),
      },
    }
  );
}

// ---------------------------------------------------------------------------
// Resend email helpers
// ---------------------------------------------------------------------------

function emailShell(title: string, bodyHtml: string): string {
  return `<!doctype html>
<html>
  <body style="margin:0;padding:0;background:#f5f5f4;font-family:-apple-system,'Segoe UI',Helvetica,Arial,sans-serif;">
    <div style="max-width:480px;margin:0 auto;padding:32px 16px;">
      <div style="text-align:center;padding-bottom:20px;">
        <img src="${SITE_URL}/whisper-logo.png" width="32" height="32" alt="" style="vertical-align:middle;border-radius:8px;margin-right:8px;"/><span style="font-size:22px;font-weight:800;letter-spacing:-0.5px;color:#111;vertical-align:middle;">whisper</span>
      </div>
      <div style="background:#ffffff;border:1px solid #e7e5e4;border-radius:20px;padding:32px 28px;">
        <h1 style="margin:0 0 14px;font-size:21px;font-weight:800;color:#111;">${title}</h1>
        ${bodyHtml}
      </div>
      <p style="text-align:center;color:#a8a29e;font-size:12px;line-height:1.6;margin-top:20px;">
        Whisper · <a href="${SITE_URL}" style="color:#a8a29e;">mydailywhisper.com</a><br/>
        You received this email because of activity on your Whisper account.
      </p>
    </div>
  </body>
</html>`;
}

const EMAIL_P =
  'style="margin:0 0 14px;font-size:15px;line-height:1.65;color:#44403c;"';
const EMAIL_BTN =
  'style="display:inline-block;background:#111;color:#fff;text-decoration:none;font-weight:700;font-size:15px;padding:13px 28px;border-radius:999px;margin-top:6px;"';

/** Sends one branded email via Resend. Returns true only when Resend
 *  actually accepted the message, so callers can report truthful counts
 *  instead of claiming success for silently dropped sends. */
async function sendEmail(
  env: Env,
  to: string,
  subject: string,
  html: string,
  attachments?: { filename: string; content: string }[]
): Promise<boolean> {
  if (!env.RESEND_API_KEY) {
    console.log("RESEND_API_KEY not set — skipping email", { subject });
    return false;
  }
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: env.RESEND_FROM || DEFAULT_FROM,
      to: [to],
      subject,
      html,
      ...(attachments && attachments.length > 0 ? { attachments } : {}),
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    console.error("Resend send failed", {
      status: res.status,
      body: text.slice(0, 300),
    });
    return false;
  }
  return true;
}

/** Branded password-reset email — mirrors every other Whisper transactional email. */
function passwordResetEmail(link: string): { subject: string; html: string } {
  return {
    subject: "Reset your Whisper password",
    html: emailShell(
      "Reset your password",
      `<p ${EMAIL_P}>Someone (hopefully you) asked to reset the password for this Whisper account. Tap the button below to choose a new one.</p>
       <p ${EMAIL_P}>This link expires after one hour. If you didn't ask for a reset, you can safely ignore this email — your password stays exactly as it is.</p>
       <a href="${link}" ${EMAIL_BTN}>Reset password</a>`
    ),
  };
}

/**
 * POST /auth/password-reset — send a BRANDED password-reset email via Resend
 * instead of Supabase's default template. Uses the admin generate_link API to
 * mint the recovery link, then wraps it in the standard Whisper email shell.
 * Always answers { ok: true } so the endpoint never leaks whether an account
 * exists for a given address.
 */
async function handleAuthPasswordReset(
  request: Request,
  env: Env
): Promise<Response> {
  let body: { email?: string };
  try {
    body = (await request.json()) as { email?: string };
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const email = (body.email ?? "").trim().toLowerCase();
  if (!email || !email.includes("@") || email.length > 320) {
    return json({ error: "invalid_email" }, 400);
  }
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key || !env.RESEND_API_KEY) {
    // Signal the caller to fall back to Supabase's built-in reset email.
    return json({ error: "not_configured" }, 503);
  }
  const res = await fetch(`${SUPABASE_URL}/auth/v1/admin/generate_link`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      type: "recovery",
      email,
      options: { redirect_to: `${SITE_URL}/reset-password` },
    }),
  });
  if (!res.ok) {
    // Unknown account or transient error — report success either way so the
    // response can't be used to enumerate registered emails.
    console.log("password-reset generate_link non-ok", { status: res.status });
    return json({ ok: true });
  }
  const data = (await res.json()) as {
    action_link?: string;
    hashed_token?: string;
  };
  // IMPORTANT: link straight to our own domain with the token_hash instead
  // of using Supabase's action_link. The action_link bounces through
  // Supabase's /auth/v1/verify endpoint, which ignores non-allowlisted
  // redirect URLs and falls back to the project's default Site URL
  // (localhost) — that's the "localhost refused to connect" error users
  // saw. A token_hash link lands on mydailywhisper.com directly and the
  // reset page exchanges it via verifyOtp.
  const link = data.hashed_token
    ? `${SITE_URL}/reset-password?token_hash=${encodeURIComponent(data.hashed_token)}&type=recovery`
    : data.action_link;
  if (link) {
    const mail = passwordResetEmail(link);
    await sendEmail(env, email, mail.subject, mail.html);
  }
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// Creator referral codes
// ---------------------------------------------------------------------------

/**
 * Redeem a creator/invite code for a freshly signed-up user. Uses the
 * service role so RLS on `whisper_referral_codes` (owner-only updates)
 * doesn't block the counter increment. Idempotent per new user: a second
 * redeem for the same user is ignored.
 */
async function handleReferralRedeem(
  request: Request,
  env: Env
): Promise<Response> {
  // The redemption is attributed to the SIGNED-IN caller — a body-supplied
  // user id would let anyone redeem as anyone (and inflate recruiter stats).
  const caller = await requireUser(request, env);
  if (caller instanceof Response) return caller;

  let body: { code?: string };
  try {
    body = (await request.json()) as { code?: string };
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const code = (body.code ?? "").trim().toUpperCase();
  const userId = caller.userId;
  if (!code || code.length > 32) {
    return json({ error: "invalid_input" }, 400);
  }
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return json({ error: "not_configured" }, 503);
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
  };

  // 1. Find the code (case-insensitive — codes are stored uppercase).
  const lookup = await fetch(
    `${SUPABASE_URL}/rest/v1/whisper_referral_codes?code=ilike.${encodeURIComponent(code)}&select=id,recruiter_id,code,uses&limit=1`,
    { headers }
  );
  if (!lookup.ok) return json({ error: "lookup_failed" }, 502);
  const rows = (await lookup.json()) as Array<{
    id: string;
    recruiter_id: string;
    code: string;
    uses: number;
  }>;
  const row = rows[0];
  if (!row) return json({ error: "code_not_found" }, 404);
  if (row.recruiter_id === userId) {
    return json({ error: "own_code" }, 400);
  }

  // 2. Record the signup (unique per new user — makes redeem idempotent).
  const insert = await fetch(
    `${SUPABASE_URL}/rest/v1/whisper_referral_signups`,
    {
      method: "POST",
      headers: { ...headers, Prefer: "return=minimal" },
      body: JSON.stringify({
        code_id: row.id,
        recruiter_id: row.recruiter_id,
        new_user_id: userId,
      }),
    }
  );
  if (!insert.ok) {
    const text = await insert.text();
    // 409 / duplicate key — user already redeemed a code. Not an error the
    // client needs to fail signup over.
    if (insert.status === 409 || text.includes("duplicate")) {
      return json({ ok: true, alreadyRedeemed: true });
    }
    console.log("referral signup insert failed", { status: insert.status });
    return json({ error: "redeem_failed" }, 502);
  }

  // 3. Bump the counter (best-effort — the signups table is authoritative).
  await fetch(
    `${SUPABASE_URL}/rest/v1/whisper_referral_codes?id=eq.${row.id}`,
    {
      method: "PATCH",
      headers: { ...headers, Prefer: "return=minimal" },
      body: JSON.stringify({ uses: row.uses + 1 }),
    }
  );

  return json({ ok: true, recruiterId: row.recruiter_id });
}

/** Signup credits earned by a creator: total + recent signups. */
async function handleReferralStats(
  request: Request,
  env: Env
): Promise<Response> {
  const url = new URL(request.url);
  const userId = (url.searchParams.get("userId") ?? "").trim();
  if (!userId) return json({ error: "missing_userId" }, 400);
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return json({ error: "not_configured" }, 503);
  const headers = { apikey: key, Authorization: `Bearer ${key}` };
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/whisper_referral_signups?recruiter_id=eq.${encodeURIComponent(userId)}&select=new_user_id,created_at&order=created_at.desc&limit=50`,
    { headers }
  );
  if (!res.ok) return json({ signups: [], total: 0 });
  const rows = (await res.json()) as Array<{
    new_user_id: string;
    created_at: string;
  }>;
  return json({ signups: rows, total: rows.length });
}

/**
 * POST /recruiter/reviews — a user who signed up via a recruiter's code
 * submits a 1–5 star rating + optional review. One review per
 * (recruiter, reviewer); re-submitting upserts. The reviewer must be signed
 * in; their user id must match a `whisper_referral_signups` row crediting
 * the recruiter so only real referrals can rate the recruiter who brought
 * them in.
 */
async function handleRecruiterReviewSubmit(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: { recruiterId?: string; rating?: number; review?: string };
  try {
    body = (await request.json()) as {
      recruiterId?: string;
      rating?: number;
      review?: string;
    };
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const recruiterId = (body.recruiterId ?? "").trim();
  const rating = Math.round(body.rating ?? 0);
  const review = (body.review ?? "").trim().slice(0, 1000);
  if (!recruiterId) return json({ error: "missing_recruiterId" }, 400);
  if (rating < 1 || rating > 5) return json({ error: "invalid_rating" }, 400);
  if (recruiterId === user.userId) {
    return json({ error: "cannot_review_self" }, 400);
  }

  // Verify the reviewer actually signed up via this recruiter's code so only
  // real referrals can rate the recruiter who brought them in.
  const signupRes = await supabaseSelect(
    env,
    `/whisper_referral_signups?recruiter_id=eq.${encodeURIComponent(
      recruiterId
    )}&new_user_id=eq.${encodeURIComponent(user.userId)}&select=id&limit=1`
  );
  if (!signupRes || signupRes.length === 0) {
    return json({ error: "not_referred_by" }, 403);
  }

  const upserted = await supabaseAdmin(
    env,
    "/whisper_recruiter_reviews?on_conflict=recruiter_id,reviewer_id",
    {
      method: "POST",
      prefer: "resolution=merge-duplicates",
      body: {
        recruiter_id: recruiterId,
        reviewer_id: user.userId,
        rating,
        review: review || null,
      },
    }
  );
  if (!upserted.ok) return json({ error: "submit_failed" }, 502);
  return json({ ok: true });
}

/**
 * GET /recruiter/reviews?recruiterId=... — list reviews + aggregate rating.
 * Anyone can read a recruiter's reviews (they're public reputation). Admins
 * get the same payload; the service role is used only for the aggregate view.
 */
async function handleRecruiterReviewsList(
  request: Request,
  env: Env
): Promise<Response> {
  const url = new URL(request.url);
  const recruiterId = (url.searchParams.get("recruiterId") ?? "").trim();
  if (!recruiterId) return json({ error: "missing_recruiterId" }, 400);
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return json({ error: "not_configured" }, 503);
  const headers = { apikey: key, Authorization: `Bearer ${key}` };

  const [reviewsRes, summaryRes] = await Promise.all([
    fetch(
      `${SUPABASE_URL}/rest/v1/whisper_recruiter_reviews?recruiter_id=eq.${encodeURIComponent(
        recruiterId
      )}&select=reviewer_id,rating,review,created_at&order=created_at.desc&limit=200`,
      { headers }
    ),
    fetch(
      `${SUPABASE_URL}/rest/v1/whisper_recruiter_rating_summary?recruiter_id=eq.${encodeURIComponent(
        recruiterId
      )}&select=review_count,average_rating,positive_count,negative_count&limit=1`,
      { headers }
    ),
  ]);

  const reviews = reviewsRes.ok
    ? ((await reviewsRes.json()) as Array<{
        reviewer_id: string;
        rating: number;
        review: string | null;
        created_at: string;
      }>)
    : [];
  const summary = summaryRes.ok
    ? ((await summaryRes.json()) as Array<{
        review_count: number;
        average_rating: number | null;
        positive_count: number;
        negative_count: number;
      }>)[0] ?? null
    : null;

  return json({
    reviews,
    reviewCount: summary?.review_count ?? reviews.length,
    averageRating: summary?.average_rating ?? null,
    positiveCount: summary?.positive_count ?? 0,
    negativeCount: summary?.negative_count ?? 0,
  });
}

interface RecruiterRow {
  user_id: string;
  username: string | null;
  display_name: string | null;
  profile_image_url: string | null;
}

interface RatingSummary {
  recruiter_id: string;
  review_count: number;
  average_rating: number | null;
  positive_count: number;
  negative_count: number;
}

interface ReferralStat {
  recruiter_id: string;
  signup_count: number;
}

/**
 * GET /admin/recruiters — list every recruiter with their aggregate rating
 * + referral signup count so the founder can see which recruiters are
 * performing well and which aren't. Admins/owner only.
 */
async function handleAdminRecruitersList(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return json({ error: "not_configured" }, 503);
  const headers = { apikey: key, Authorization: `Bearer ${key}` };

  // Pull recruiters, their rating summaries, and their referral counts in
  // parallel so the page loads in one round trip.
  const [recruitersRes, summaryRes, referralRes] = await Promise.all([
    fetch(
      `${SUPABASE_URL}/rest/v1/whisper_profiles?is_recruiter=eq.true&select=user_id,username,display_name,profile_image_url&order=username.asc&limit=200`,
      { headers }
    ),
    fetch(
      `${SUPABASE_URL}/rest/v1/whisper_recruiter_rating_summary?select=recruiter_id,review_count,average_rating,positive_count,negative_count`,
      { headers }
    ),
    fetch(
      `${SUPABASE_URL}/rest/v1/rpc/get_recruiter_referral_counts`,
      { headers, method: "POST", body: JSON.stringify({}) }
    ).catch(() => null),
  ]);

  const recruiters: RecruiterRow[] = recruitersRes.ok
    ? ((await recruitersRes.json()) as RecruiterRow[])
    : [];
  const summaries: RatingSummary[] = summaryRes.ok
    ? ((await summaryRes.json()) as RatingSummary[])
    : [];
  // The RPC may not exist yet — fall back to counting signups per recruiter
  // from the signups table directly if the RPC isn't deployed.
  let referralStats: ReferralStat[] = [];
  if (referralRes && referralRes.ok) {
    referralStats = ((await referralRes.json()) as ReferralStat[]) ?? [];
  } else {
    const signupsRes = await fetch(
      `${SUPABASE_URL}/rest/v1/whisper_referral_signups?select=recruiter_id&limit=1000`,
      { headers }
    );
    if (signupsRes.ok) {
      const rows = (await signupsRes.json()) as { recruiter_id: string }[];
      const counts = new Map<string, number>();
      for (const r of rows) {
        counts.set(r.recruiter_id, (counts.get(r.recruiter_id) ?? 0) + 1);
      }
      referralStats = Array.from(counts.entries()).map(([recruiter_id, n]) => ({
        recruiter_id,
        signup_count: n,
      }));
    }
  }

  const summaryMap = new Map(summaries.map((s) => [s.recruiter_id, s]));
  const referralMap = new Map(referralStats.map((r) => [r.recruiter_id, r.signup_count]));

  const rows = recruiters.map((r) => {
    const s = summaryMap.get(r.user_id);
    return {
      userId: r.user_id,
      username: r.username,
      displayName: r.display_name,
      profileImageUrl: r.profile_image_url,
      signupCount: referralMap.get(r.user_id) ?? 0,
      reviewCount: s?.review_count ?? 0,
      averageRating: s?.average_rating ?? null,
      positiveCount: s?.positive_count ?? 0,
      negativeCount: s?.negative_count ?? 0,
    };
  });

  // Sort by signup count desc so the most active recruiters surface first.
  rows.sort((a, b) => b.signupCount - a.signupCount);
  return json({ recruiters: rows });
}

/** Add the buyer to the marketing audience so future campaigns reach them. */
async function addMarketingContact(env: Env, email: string): Promise<void> {
  if (!env.RESEND_API_KEY || !env.RESEND_AUDIENCE_ID) return;
  const res = await fetch(
    `https://api.resend.com/audiences/${env.RESEND_AUDIENCE_ID}/contacts`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({ email, unsubscribed: false }),
    }
  );
  if (!res.ok) {
    console.error("Resend audience add failed", { status: res.status });
  }
}

function welcomeEmail(plan: string): { subject: string; html: string } {
  const planLabel =
    plan === "one-annual" ? "Whisper One · Annual" : "Whisper One · Monthly";
  return {
    subject: "Welcome to Whisper One",
    html: emailShell(
      "Welcome to Whisper One",
      `<p ${EMAIL_P}>Your <strong>${planLabel}</strong> membership is now active. Here's what just unlocked:</p>
       <p ${EMAIL_P}>• Membership tools without a public membership marker<br/>
       • 3 client slots for coaching<br/>
       • Creator Studio Lite<br/>
       • Stat sharing</p>
       <p ${EMAIL_P}>Open the app and your perks will be waiting. Your Stripe receipt arrives separately.</p>
       <a href="${SITE_URL}" ${EMAIL_BTN}>Open Whisper</a>`
    ),
  };
}

function cancelledEmail(): { subject: string; html: string } {
  return {
    subject: "Your Whisper One membership has ended",
    html: emailShell(
      "Your membership has ended",
      `<p ${EMAIL_P}>Your Whisper One subscription has been cancelled and your perks have been switched off. Your account, posts, and messages are untouched.</p>
       <p ${EMAIL_P}>Changed your mind? You can rejoin any time and everything picks up where it left off.</p>
       <a href="${SITE_URL}/one" ${EMAIL_BTN}>Rejoin Whisper One</a>`
    ),
  };
}

function badgeWelcomeEmail(role: BadgeRole): { subject: string; html: string } {
  const label = BADGE_LABEL[role];
  return {
    subject: `Your ${label} tools are live`,
    html: emailShell(
      `You're officially a ${label}`,
      `<p ${EMAIL_P}>Your payment went through and your approved <strong>${label}</strong> tools are now active. Professional roles appear as plain profile details, not decorative seals.</p>
       <p ${EMAIL_P}>The subscription renews once a year — we'll email you before each renewal. Your Stripe receipt arrives separately.</p>
       <a href="${SITE_URL}" ${EMAIL_BTN}>Open Whisper</a>`
    ),
  };
}

function badgeEndedEmail(role: BadgeRole): { subject: string; html: string } {
  const label = BADGE_LABEL[role];
  return {
    subject: `Your ${label} subscription has ended`,
    html: emailShell(
      `Your ${label} subscription has ended`,
      `<p ${EMAIL_P}>Your annual ${label} subscription has ended, so its paid tool access has ended. Your account, posts, and messages are untouched.</p>
       <p ${EMAIL_P}>Your application approval still stands — reactivate any time to restore eligible tools.</p>
       <a href="${SITE_URL}/badge/activate?role=${role}" ${EMAIL_BTN}>Reactivate your tools</a>`
    ),
  };
}

function badgeApprovedEmail(role: BadgeRole): { subject: string; html: string } {
  const label = BADGE_LABEL[role];
  return {
    subject: `You've been approved as a Whisper ${label}`,
    html: emailShell(
      `You're approved, ${BADGE_GREETING[role]}!`,
      `<p ${EMAIL_P}>A real person reviewed your application and approved you as a <strong>${label}</strong>. One step left: activate your approved tools.</p>
       <p ${EMAIL_P}>The ${label} subscription is <strong>billed once per year</strong>. Payment activates the same approved role tools. Your professional role is shown as plain profile text; identity indicators are separate and are not safety guarantees.</p>
       <a href="${SITE_URL}/badge/activate?role=${role}" ${EMAIL_BTN}>Activate your ${label} tools</a>`
    ),
  };
}

function paymentFailedEmail(): { subject: string; html: string } {
  return {
    subject: "Action needed: your Whisper One payment failed",
    html: emailShell(
      "Your payment didn't go through",
      `<p ${EMAIL_P}>We couldn't charge your card for Whisper One. Stripe will retry automatically over the next few days, but if it keeps failing your membership will pause.</p>
       <p ${EMAIL_P}>To keep your perks, update your payment method:</p>
       <a href="${SITE_URL}/one" ${EMAIL_BTN}>Update payment</a>`
    ),
  };
}

// ---------------------------------------------------------------------------
// Broadcast — branded email to every Supabase user
// ---------------------------------------------------------------------------

/** Escape user-provided text before interpolating it into email HTML. */
function escapeHtml(text: string): string {
  return text
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

interface BroadcastAttachment {
  /** Original file name, shown to the recipient. */
  filename: string;
  /** Base64-encoded file content. */
  content: string;
  /** MIME type; set for images so clients render them. */
  content_type?: string;
  /** CID reference — set for images so they render inline in the body. */
  content_id?: string;
}

/** MIME type for common image extensions, or null for non-images. */
function imageContentType(filename: string): string | null {
  const ext = filename.toLowerCase().split(".").pop() ?? "";
  const map: Record<string, string> = {
    png: "image/png",
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    gif: "image/gif",
    webp: "image/webp",
    bmp: "image/bmp",
    svg: "image/svg+xml",
  };
  return map[ext] ?? null;
}

interface BroadcastBody {
  mode?: "preview" | "test" | "send";
  subject?: string;
  headline?: string;
  /** Plain text; blank lines split paragraphs. */
  message?: string;
  buttonLabel?: string;
  buttonUrl?: string;
  /** Files attached to the email (base64). */
  attachments?: BroadcastAttachment[];
  /** Required for mode:"test". */
  testEmail?: string;
}

/** Validate + sanitize incoming attachments; cap count and total size. */
function sanitizeAttachments(
  raw: BroadcastAttachment[] | undefined
): BroadcastAttachment[] {
  if (!raw || !Array.isArray(raw)) return [];
  const out: BroadcastAttachment[] = [];
  let totalBase64 = 0;
  for (const item of raw.slice(0, 5)) {
    if (!item || typeof item.filename !== "string") continue;
    if (typeof item.content !== "string" || item.content.length === 0) continue;
    totalBase64 += item.content.length;
    // ~15MB of real bytes ≈ 20M base64 chars — Resend's limit is 40MB total.
    if (totalBase64 > 20_000_000) break;
    const filename = item.filename.replace(/[\\/:*?"<>|]/g, "_").slice(0, 120);
    out.push({ filename: filename || "attachment", content: item.content });
  }
  return out;
}

/** Render the user's plain-text message into the branded Whisper shell. */
function broadcastHtml(
  body: BroadcastBody,
  inlineImages: { src: string; name: string }[] = []
): string {
  const paragraphs = (body.message ?? "")
    .split(/\n\s*\n/)
    .map((p) => p.trim())
    .filter((p) => p.length > 0)
    .map(
      (p) => `<p ${EMAIL_P}>${escapeHtml(p).replace(/\n/g, "<br/>")}</p>`
    )
    .join("\n");

  let button = "";
  const label = (body.buttonLabel ?? "").trim();
  let rawUrl = (body.buttonUrl ?? "").trim();
  if (label && rawUrl) {
    // People type "mydailywhisper.com" — add the protocol instead of
    // silently dropping the button.
    if (!/^https?:\/\//i.test(rawUrl)) rawUrl = `https://${rawUrl}`;
    try {
      const url = new URL(rawUrl);
      if (url.protocol === "https:" || url.protocol === "http:") {
        button = `<a href="${escapeHtml(url.toString())}" ${EMAIL_BTN}>${escapeHtml(label)}</a>`;
      }
    } catch {
      // invalid URL — omit the button rather than break the email
    }
  }

  const images = inlineImages
    .map(
      (img) =>
        `<img src="${img.src}" alt="${escapeHtml(img.name)}" style="display:block;max-width:100%;height:auto;border-radius:14px;margin:6px 0 14px;"/>`
    )
    .join("\n");

  return emailShell(
    escapeHtml(body.headline || body.subject || "A note from Whisper"),
    `${paragraphs}\n${images}\n${button}`
  );
}

/** Page through Supabase Auth admin API and collect every user's email. */
async function listAllUserEmails(env: Env): Promise<string[] | null> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;

  const emails = new Set<string>();
  const perPage = 1000;
  for (let page = 1; page <= 50; page++) {
    const res = await fetch(
      `${SUPABASE_URL}/auth/v1/admin/users?page=${page}&per_page=${perPage}`,
      { headers: { apikey: key, Authorization: `Bearer ${key}` } }
    );
    if (!res.ok) {
      console.error("Supabase admin user list failed", {
        page,
        status: res.status,
      });
      return null;
    }
    const data = (await res.json()) as {
      users?: { email?: string | null; banned_until?: string | null }[];
    };
    const users = data.users ?? [];
    for (const user of users) {
      if (user.email) emails.add(user.email.toLowerCase());
    }
    if (users.length < perPage) break;
  }
  return Array.from(emails);
}

/**
 * Send one branded email to many recipients. Uses Resend's batch API when
 * there are no attachments; falls back to individual sends otherwise
 * (Resend's batch endpoint does not support attachments).
 */
async function sendBroadcastBatch(
  env: Env,
  recipients: string[],
  subject: string,
  html: string,
  attachments: { filename: string; content: string }[] = []
): Promise<{ sent: number; failed: number }> {
  const from = env.RESEND_FROM || DEFAULT_FROM;
  let sent = 0;
  let failed = 0;

  if (attachments.length > 0) {
    for (const to of recipients) {
      const res = await fetch("https://api.resend.com/emails", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.RESEND_API_KEY}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ from, to: [to], subject, html, attachments }),
      });
      if (res.ok) {
        sent += 1;
      } else {
        failed += 1;
        const text = await res.text();
        console.error("Resend attachment send failed", {
          status: res.status,
          body: text.slice(0, 300),
        });
      }
    }
    return { sent, failed };
  }

  // Resend's batch endpoint accepts up to 100 emails per call.
  for (let i = 0; i < recipients.length; i += 100) {
    const chunk = recipients.slice(i, i + 100);
    const res = await fetch("https://api.resend.com/emails/batch", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.RESEND_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(
        chunk.map((to) => ({ from, to: [to], subject, html }))
      ),
    });
    if (res.ok) {
      sent += chunk.length;
    } else {
      failed += chunk.length;
      const text = await res.text();
      console.error("Resend batch send failed", {
        status: res.status,
        body: text.slice(0, 300),
      });
    }
  }
  return { sent, failed };
}

// ---------------------------------------------------------------------------
// Badge approval hook — called by a Supabase trigger (or manually) whenever an
// application flips to "approved". Sends the "activate your badge" email.
// ---------------------------------------------------------------------------

interface ApprovedHookBody {
  userId?: string;
  email?: string;
  role?: string;
}

/** Look up a Supabase auth user's email by id (service role). */
async function authUserEmail(env: Env, userId: string): Promise<string | null> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  const res = await fetch(
    `${SUPABASE_URL}/auth/v1/admin/users/${encodeURIComponent(userId)}`,
    { headers: { apikey: key, Authorization: `Bearer ${key}` } }
  );
  if (!res.ok) return null;
  const data = (await res.json()) as { email?: string | null };
  return data.email ?? null;
}

async function handleBadgeApprovedHook(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.BROADCAST_SECRET) {
    return json({ error: "hook_not_configured" }, 503);
  }
  const auth = request.headers.get("Authorization") ?? "";
  const provided = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!provided || provided !== env.BROADCAST_SECRET) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: ApprovedHookBody;
  try {
    body = (await request.json()) as ApprovedHookBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const role =
    body.role === "coach" || body.role === "athlete" || body.role === "verified"
      ? body.role
      : null;
  if (!role) return json({ error: "invalid_role" }, 400);

  let email = (body.email ?? "").trim();
  if (!email.includes("@") && body.userId) {
    email = (await authUserEmail(env, body.userId)) ?? "";
  }
  if (!email.includes("@")) {
    return json({ error: "email_not_found" }, 404);
  }

  console.log("Sending badge approval email", { role });
  const mail = badgeApprovedEmail(role);
  await sendEmail(env, email, mail.subject, mail.html);
  return json({ ok: true, sent: 1 });
}

/**
 * GET /admin/diagnostics — broadcast-key-protected snapshot of the review
 * tables so we can debug "applications not showing" without dashboard access.
 * Returns per-table existence, total rows, and a status breakdown.
 */
async function handleAdminDiagnostics(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.BROADCAST_SECRET) return json({ error: "not_configured" }, 503);
  const auth = request.headers.get("Authorization") ?? "";
  const provided = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!provided || provided !== env.BROADCAST_SECRET) {
    return json({ error: "unauthorized" }, 401);
  }
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return json({ error: "server_not_configured" }, 503);

  const tables = [
    "whisper_coach_applications",
    "whisper_athlete_applications",
    "whisper_verification_requests",
    "whisper_admins",
  ];
  const out: Record<string, unknown> = {};

  // Stripe Connect readiness — coach payouts need Connect enabled on the
  // platform Stripe account. Listing connected accounts fails with a clear
  // message when Connect hasn't been activated in the Stripe dashboard.
  if (env.STRIPE_SECRET_KEY) {
    // Do exactly what "Link bank account" does: create an Express account
    // with the same capabilities, then delete it immediately. Surfaces the
    // exact Stripe error coaches would hit.
    const params = new URLSearchParams();
    params.set("type", "express");
    params.set("capabilities[transfers][requested]", "true");
    params.set("capabilities[card_payments][requested]", "true");
    params.set("business_type", "individual");
    params.set("business_profile[url]", SITE_URL);
    params.set("business_profile[mcc]", "7298");
    params.set(
      "business_profile[product_description]",
      "Personal fitness coaching on Whisper"
    );
    params.set("settings[payouts][schedule][interval]", "manual");
    params.set("metadata[diagnosticProbe]", "true");
    const probe = await stripeRequest(env, "/accounts", params);
    if (probe.ok && typeof probe.data.id === "string") {
      const accountId = probe.data.id;
      out.stripeConnect = { enabled: true };

      // Second half of the flow: the embedded onboarding Account Session
      // (what BankLinkSheet renders). Surfaces the exact Stripe error.
      const sessionParams = new URLSearchParams();
      sessionParams.set("account", accountId);
      sessionParams.set("components[account_onboarding][enabled]", "true");
      sessionParams.set(
        "components[account_onboarding][features][external_account_collection]",
        "true"
      );
      const session = await stripeRequest(
        env,
        "/account_sessions",
        sessionParams
      );
      if (session.ok && typeof session.data.client_secret === "string") {
        out.embeddedOnboarding = {
          ok: true,
          publishableKeySet: Boolean(env.STRIPE_PUBLISHABLE_KEY),
          publishableKeyMode: (env.STRIPE_PUBLISHABLE_KEY ?? "").startsWith(
            "pk_test_"
          )
            ? "test"
            : (env.STRIPE_PUBLISHABLE_KEY ?? "").startsWith("pk_live_")
              ? "live"
              : env.STRIPE_PUBLISHABLE_KEY
                ? "unknown_format"
                : "missing",
        };
      } else {
        const sessionErr = session.data.error as
          | { message?: string; code?: string }
          | undefined;
        out.embeddedOnboarding = {
          ok: false,
          status: session.status,
          code: sessionErr?.code ?? null,
          message: sessionErr?.message ?? null,
          publishableKeySet: Boolean(env.STRIPE_PUBLISHABLE_KEY),
        };
      }

      await stripeRequest(
        env,
        `/accounts/${encodeURIComponent(accountId)}`,
        new URLSearchParams(),
        { method: "DELETE" }
      ).catch(() => null);
    } else {
      const err = probe.data.error as { message?: string } | undefined;
      out.stripeConnect = {
        enabled: false,
        status: probe.status,
        message: err?.message ?? null,
      };
    }
  } else {
    out.stripeConnect = { enabled: false, message: "STRIPE_SECRET_KEY not set" };
  }

  await Promise.all(
    tables.map(async (table) => {
      // whisper_admins has a `role` column instead of `status`.
      const facet = table === "whisper_admins" ? "role" : "status";
      const res = await fetch(
        `${SUPABASE_URL}/rest/v1/${table}?select=id,${facet},created_at&order=created_at.desc&limit=200`,
        {
          headers: {
            apikey: key,
            Authorization: `Bearer ${key}`,
            Prefer: "count=exact",
          },
        }
      );
      if (!res.ok) {
        const text = await res.text();
        out[table] = { ok: false, status: res.status, error: text.slice(0, 200) };
        return;
      }
      const rows = (await res.json()) as Record<string, unknown>[];
      const byStatus: Record<string, number> = {};
      for (const r of rows) {
        const s = String(r[facet] ?? "null");
        byStatus[s] = (byStatus[s] ?? 0) + 1;
      }
      out[table] = {
        ok: true,
        total: res.headers.get("content-range"),
        byStatus,
      };
    })
  );
  return json(out);
}

// ---------------------------------------------------------------------------
// Admin application review — powers mydailywhisper.com/admin/applications.
// The caller is a signed-in Supabase user; we verify their JWT server-side and
// require an admin/moderator/owner flag on their profile. Decisions are
// written with the service role, and approval emails are sent directly from
// here (no dependency on the Supabase pg_net trigger).
// ---------------------------------------------------------------------------

type AdminRole = "owner" | "admin" | "moderator";

/**
 * Resolve + authorize the calling admin from their Supabase access token.
 * Role is resolved with **highest-rank-wins** across both the
 * `whisper_admins` table and the legacy `profiles` flags
 * (is_admin / is_moderator / is_owner). This matches the badge resolution
 * the web + iOS apps use (`rowToBadge`), so a caller whose `whisper_admins`
 * row says `moderator` but whose `profiles.is_admin` flag is `true` still
 * resolves as `admin` — preventing the "promoted then suddenly can't
 * promote anyone" regression that happened when the primary source
 * silently downgraded a legacy admin.
 */
async function requireAdmin(
  request: Request,
  env: Env
): Promise<{ userId: string; role: AdminRole } | Response> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return json({ error: "server_not_configured" }, 503);

  const auth = request.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) return json({ error: "unauthorized" }, 401);

  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: key, Authorization: `Bearer ${token}` },
  });
  if (!res.ok) return json({ error: "unauthorized" }, 401);
  const user = (await res.json()) as { id?: string };
  if (!user.id) return json({ error: "unauthorized" }, 401);
  const uid = encodeURIComponent(user.id);

  // Pull both sources in parallel so latency stays flat.
  const [adminRows, profileRows] = await Promise.all([
    supabaseSelect(env, `/whisper_admins?user_id=eq.${uid}&select=role&limit=1`),
    supabaseSelect(
      env,
      `/profiles?id=eq.${uid}&select=is_admin,is_moderator,is_owner&limit=1`
    ),
  ]);

  const adminRole = (adminRows?.[0] as { role?: string } | undefined)?.role;
  const profile = (profileRows?.[0] ?? null) as {
    is_admin?: boolean | null;
    is_moderator?: boolean | null;
    is_owner?: boolean | null;
  } | null;

  // Highest rank wins across both sources (owner > admin > moderator).
  let best: AdminRole | null = null;
  const consider = (r: AdminRole | null | undefined): void => {
    if (!r) return;
    if (r === "owner") best = "owner";
    else if (r === "admin" && best !== "owner") best = "admin";
    else if (r === "moderator" && best !== "owner" && best !== "admin")
      best = "moderator";
  };
  if (
    adminRole === "owner" ||
    adminRole === "admin" ||
    adminRole === "moderator"
  ) {
    consider(adminRole as AdminRole);
  }
  if (profile?.is_owner) consider("owner");
  if (profile?.is_admin) consider("admin");
  if (profile?.is_moderator) consider("moderator");

  if (best) return { userId: user.id, role: best };
  return json({ error: "forbidden" }, 403);
}

/**
 * Resolve the calling signed-in user from their Supabase access token.
 * Used by the coach-payments endpoints where any authenticated user (not
 * just admins) acts on their own account.
 */
async function requireUser(
  request: Request,
  env: Env,
  signal?: AbortSignal
): Promise<{ userId: string; email: string | null; emailVerified: boolean } | Response> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return json({ error: "server_not_configured" }, 503);

  const auth = request.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!token) return json({ error: "sign_in_required" }, 401);

  const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: { apikey: key, Authorization: `Bearer ${token}` },
    ...(signal ? { signal } : {}),
  });
  if (!res.ok) return json({ error: "sign_in_required" }, 401);
  const user = (await res.json()) as { id?: string; email?: string; email_confirmed_at?: string | null };
  if (!user.id) return json({ error: "sign_in_required" }, 401);
  return { userId: user.id, email: user.email ?? null, emailVerified: !!user.email_confirmed_at };
}

/** Voice-only transient identity recovery. No token issuance/call mutation is
 * retried. Supabase remains the authority; a rejected credential fails closed. */
async function requireKnotVoiceUser(
  request: Request, env: Env, signal: AbortSignal
): Promise<{ userId: string; email: string | null; emailVerified: boolean } | Response> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return json({ error: 'server_not_configured' }, 503);
  const auth = request.headers.get('Authorization') ?? '';
  if (!auth.startsWith('Bearer ') || !auth.slice(7).trim()) return json({ error: 'sign_in_required' }, 401);
  for (let attempt = 0; attempt < 2; attempt++) {
    if (signal.aborted) throw new Error('voice_auth_unavailable');
    try {
      const response = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
        headers: { apikey: key, Authorization: auth },
        signal: AbortSignal.any([signal, AbortSignal.timeout(attempt === 0 ? 4500 : 5500)]),
      });
      if (response.status === 401 || response.status === 403) {
        await response.body?.cancel();
        return json({ error: 'sign_in_required' }, 401);
      }
      if (!response.ok) {
        const transient = response.status === 408 || response.status === 429 || response.status >= 500;
        await response.body?.cancel();
        if (!transient) throw new Error('voice_auth_rejected');
        console.warn('knot_voice_auth_read', { attempt: attempt + 1, outcome: 'transient_http', status: response.status });
      } else {
        const user = await response.json() as { id?: unknown; email?: unknown; email_confirmed_at?: unknown };
        if (typeof user.id !== 'string' || !/^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i.test(user.id)) return json({ error: 'sign_in_required' }, 401);
        if (signal.aborted) throw new Error('voice_auth_unavailable');
        return { userId: user.id, email: typeof user.email === 'string' ? user.email : null, emailVerified: typeof user.email_confirmed_at === 'string' && !!user.email_confirmed_at };
      }
    } catch (error) {
      if (signal.aborted || error instanceof Error && error.message === 'voice_auth_rejected') throw new Error('voice_auth_unavailable');
      console.warn('knot_voice_auth_read', { attempt: attempt + 1, outcome: 'transport_unavailable' });
    }
  }
  throw new Error('voice_auth_unavailable');
}

// ---------------------------------------------------------------------------
// Coach access — one-tap authorize (no codes)
//
// The client taps Authorize in Whisper's Coach access sheet. We verify their
// session, confirm the target is genuinely their accepted coach
// (whisper_coach_requests.status = 'accepted'), then write the coach_grants
// row with the service role — producing exactly what redeem_coach_grant_code
// used to, so my_coaches / my_clients / revoke_coach_grant and the Jasper
// Connect coach-token mint (authorize + p_client) keep working unchanged.
// The same endpoint also switches scope on an existing grant (view-only ⇄
// view & edit) and re-activates a previously revoked pair.
// ---------------------------------------------------------------------------

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// ---------------------------------------------------------------------------
// Legacy Jasper push is retired: its deterministic shared topics did not
// enforce holder ownership or revocation. Do not issue descriptors or forward
// even previously registered deliveries. Native dashboards retain polling.
// ---------------------------------------------------------------------------

function retiredJasperHook(): Response {
  return json({ error: "push_disabled", message: "Use authenticated Jasper reads to refresh." }, 410);
}

async function handleCoachAccessGrant(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: { coachId?: string; scope?: string };
  try {
    body = (await request.json()) as { coachId?: string; scope?: string };
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const coachId = (body.coachId ?? "").trim().toLowerCase();
  const scope =
    body.scope === "read"
      ? "read"
      : body.scope === "read_write"
        ? "read_write"
        : null;
  if (!UUID_RE.test(coachId)) return json({ error: "invalid_coachId" }, 400);
  if (!scope) return json({ error: "invalid_scope" }, 400);
  if (coachId === user.userId.toLowerCase()) {
    return json({ error: "cannot_authorize_self" }, 400);
  }

  // Only an accepted coach can be authorized — the one-tap button never
  // grants data access to someone the user hasn't hired as a coach.
  const rel = await supabaseSelect(
    env,
    `/whisper_coach_requests?client_user_id=eq.${encodeURIComponent(
      user.userId
    )}&coach_user_id=eq.${encodeURIComponent(
      coachId
    )}&status=eq.accepted&select=id&limit=1`
  );
  if (!rel || rel.length === 0) return json({ error: "not_your_coach" }, 403);

  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return json({ error: "server_not_configured" }, 503);
  const headers = {
    apikey: key,
    Authorization: `Bearer ${key}`,
    "Content-Type": "application/json",
    Prefer: "return=representation",
  };

  // Update-then-insert instead of a bare upsert: it needs no knowledge of how
  // pair uniqueness is declared on coach_grants and re-activates revoked rows.
  const pairFilter = `client_uid=eq.${encodeURIComponent(
    user.userId
  )}&coach_uid=eq.${encodeURIComponent(coachId)}`;
  const stamp = new Date().toISOString();
  const patchRes = await fetch(
    `${SUPABASE_URL}/rest/v1/coach_grants?${pairFilter}`,
    {
      method: "PATCH",
      headers,
      body: JSON.stringify({ scope, status: "active", granted_at: stamp }),
    }
  );
  if (patchRes.ok) {
    const rows = (await patchRes.json()) as unknown[];
    if (Array.isArray(rows) && rows.length > 0) {
      return json({ ok: true, scope, updated: true });
    }
  }

  const postRes = await fetch(`${SUPABASE_URL}/rest/v1/coach_grants`, {
    method: "POST",
    headers,
    body: JSON.stringify({
      client_uid: user.userId,
      coach_uid: coachId,
      scope,
      status: "active",
      granted_at: stamp,
    }),
  });
  if (!postRes.ok) {
    const text = await postRes.text();
    console.error("coach-access grant insert failed", {
      status: postRes.status,
      body: text.slice(0, 300),
    });
    return json({ error: "grant_failed" }, 502);
  }
  return json({ ok: true, scope, updated: false });
}

// ---------------------------------------------------------------------------
// Coach payments — Stripe Connect Express
//
// Approved coaches set a monthly rate, link a bank account through Stripe's
// hosted onboarding, and cash out their available balance. Clients pay via
// a destination-charge subscription; Whisper keeps a platform fee.
// ---------------------------------------------------------------------------

const COACH_PLATFORM_FEE_PERCENT = 10;
const COACH_PRICE_MIN_CENTS = 500; // $5
const COACH_PRICE_MAX_CENTS = 200000; // $2,000

interface ConnectRow {
  user_id: string;
  stripe_account_id: string;
  charges_enabled: boolean;
  payouts_enabled: boolean;
  details_submitted: boolean;
}

async function getConnectRow(
  env: Env,
  userId: string
): Promise<ConnectRow | null> {
  const rows = await supabaseSelect(
    env,
    `/whisper_coach_connect?user_id=eq.${encodeURIComponent(userId)}&select=user_id,stripe_account_id,charges_enabled,payouts_enabled,details_submitted&limit=1`
  );
  return (rows?.[0] as ConnectRow | undefined) ?? null;
}

/**
 * Connect row with self-healing readiness: when the stored snapshot says
 * the account can't take payments yet, re-check Stripe LIVE and persist.
 * A coach who just finished onboarding becomes hireable immediately —
 * their public rate card no longer waits for their next Studio visit.
 */
async function getFreshConnectRow(
  env: Env,
  userId: string
): Promise<ConnectRow | null> {
  const row = await getConnectRow(env, userId);
  if (!row) return null;
  if (row.payouts_enabled || row.charges_enabled) return row;
  if (!env.STRIPE_SECRET_KEY) return row;
  const status = await refreshConnectStatus(env, userId, row.stripe_account_id);
  if (status.accountMissing) return null;
  return {
    ...row,
    charges_enabled: status.chargesEnabled,
    payouts_enabled: status.payoutsEnabled,
    details_submitted: status.detailsSubmitted,
  };
}

/**
 * True when Stripe says a referenced account no longer exists — the classic
 * symptom of a Connect payout account minted under TEST keys being used
 * after the platform switched to LIVE keys (test accounts don't exist in
 * live mode). Covers both direct lookups (resource_missing / "No such
 * account"), checkout destinations ("No such destination"), and calls made
 * on behalf of the account (account_invalid).
 */
function isMissingAccountError(result: {
  ok: boolean;
  status: number;
  data: Record<string, unknown>;
}): boolean {
  if (result.ok) return false;
  const err = result.data.error as
    | { code?: string; message?: string; param?: string }
    | undefined;
  if (!err) return false;
  if (err.code === "account_invalid") return true;
  const message = err.message ?? "";
  if (/no such (destination|account)/i.test(message)) return true;
  return (
    err.code === "resource_missing" &&
    /account|destination/i.test(`${err.param ?? ""} ${message}`)
  );
}

/**
 * Drop a payout-account row whose Stripe account no longer exists in the
 * current key mode, so the owner sees "Connect payouts" again and the next
 * connect mints a FRESH account in the right mode. Guarded by account id
 * so a racing reconnect can't be wiped.
 */
async function clearStaleConnect(
  env: Env,
  userId: string,
  accountId: string
): Promise<void> {
  console.error("Clearing stale Connect payout account (missing in current key mode)", {
    userId,
  });
  await supabaseAdmin(
    env,
    `/whisper_coach_connect?user_id=eq.${encodeURIComponent(userId)}&stripe_account_id=eq.${encodeURIComponent(accountId)}`,
    { method: "DELETE" }
  );
}

/** Clamp an integer to [min, max] with a fallback when invalid. */
function clampInt(v: unknown, min: number, max: number, fallback: number): number {
  const n = Math.round(Number(v));
  return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : fallback;
}

/** Read a boolean flag from the caller's `whisper_profiles` row. */
async function userFlag(env: Env, userId: string, column: string): Promise<boolean> {
  const uid = encodeURIComponent(userId);
  const rows = await supabaseSelect(
    env,
    `/whisper_profiles?user_id=eq.${uid}&select=${column}&limit=1`
  );
  return !!(rows?.[0] as Record<string, boolean | null> | undefined)?.[column];
}

/** Resolve a user's verification badge (owner > admin > moderator > verified > none). */
async function resolveUserBadge(env: Env, userId: string): Promise<"owner" | "admin" | "moderator" | "verified" | "none"> {
  const uid = encodeURIComponent(userId);
  const [adminRows, profileRows] = await Promise.all([
    supabaseSelect(env, `/whisper_admins?user_id=eq.${uid}&select=role&limit=1`),
    supabaseSelect(env, `/profiles?id=eq.${uid}&select=is_admin,is_moderator,is_owner,is_verified&limit=1`),
  ]);
  const adminRole = (adminRows?.[0] as { role?: string } | undefined)?.role;
  const p = (profileRows?.[0] ?? null) as {
    is_admin?: boolean | null;
    is_moderator?: boolean | null;
    is_owner?: boolean | null;
    is_verified?: boolean | null;
  } | null;
  if (adminRole === "owner" || p?.is_owner) return "owner";
  if (adminRole === "admin" || p?.is_admin) return "admin";
  if (adminRole === "moderator" || p?.is_moderator) return "moderator";
  if (p?.is_verified) return "verified";
  return "none";
}

/** True when the user is an approved (or already active) coach. */
async function isCoach(env: Env, userId: string): Promise<boolean> {
  if (await hasApprovedApplication(env, userId, "coach")) return true;
  const rows = await supabaseSelect(
    env,
    `/whisper_profiles?user_id=eq.${encodeURIComponent(userId)}&select=is_coach&limit=1`
  );
  return !!(rows?.[0] as { is_coach?: boolean } | undefined)?.is_coach;
}

/**
 * True when the user may link a bank account for payouts. Coaches always
 * qualify; verified athletes and creators qualify (they receive sponsorship
 * payouts); anyone with a sponsorship deal also qualifies so pending
 * payments can be released.
 */
async function canReceivePayouts(env: Env, userId: string): Promise<boolean> {
  if (await isCoach(env, userId)) return true;
  const uid = encodeURIComponent(userId);
  const rows = await supabaseSelect(
    env,
    `/whisper_profiles?user_id=eq.${uid}&select=is_athlete,is_verified&limit=1`
  );
  const p = rows?.[0] as
    | { is_athlete?: boolean; is_verified?: boolean }
    | undefined;
  if (p?.is_athlete || p?.is_verified) return true;
  if (await hasApprovedApplication(env, userId, "athlete")) return true;
  if (await hasApprovedApplication(env, userId, "verified")) return true;
  const deals = await supabaseSelect(
    env,
    `/whisper_sponsorship_deals?creator_user_id=eq.${uid}&select=id&limit=1`
  );
  return Array.isArray(deals) && deals.length > 0;
}

/** Fetch + persist the latest onboarding state of a connected account. */
async function refreshConnectStatus(
  env: Env,
  userId: string,
  accountId: string
): Promise<{
  chargesEnabled: boolean;
  payoutsEnabled: boolean;
  detailsSubmitted: boolean;
  accountMissing?: boolean;
}> {
  const account = await stripeRequest(
    env,
    `/accounts/${encodeURIComponent(accountId)}`
  );
  if (!account.ok && isMissingAccountError(account)) {
    await clearStaleConnect(env, userId, accountId);
    return {
      chargesEnabled: false,
      payoutsEnabled: false,
      detailsSubmitted: false,
      accountMissing: true,
    };
  }
  const chargesEnabled = account.data.charges_enabled === true;
  const payoutsEnabled = account.data.payouts_enabled === true;
  const detailsSubmitted = account.data.details_submitted === true;
  await supabaseAdmin(env, "/whisper_coach_connect?on_conflict=user_id", {
    method: "POST",
    prefer: "resolution=merge-duplicates",
    body: {
      user_id: userId,
      stripe_account_id: accountId,
      charges_enabled: chargesEnabled,
      payouts_enabled: payoutsEnabled,
      details_submitted: detailsSubmitted,
      updated_at: new Date().toISOString(),
    },
  });
  return { chargesEnabled, payoutsEnabled, detailsSubmitted };
}

/**
 * Create (or reuse) the coach's Stripe payout account.
 *
 * Minimal-question setup, DoorDash/Cash App style: individuals only, with
 * the `card_payments` + `transfers` capability pair. Transfers-only would be
 * leaner, but Stripe gates that combo behind manual platform approval
 * ("Your platform needs approval for accounts to have requested the
 * transfers capability without the card_payments capability") — the pair is
 * granted automatically, no Stripe contact needed. Clients still pay
 * Whisper's platform account directly; the coach's card_payments capability
 * simply sits unused. We prefill everything we already know so onboarding
 * stays short.
 */
async function ensureConnectAccount(
  env: Env,
  user: { userId: string; email?: string | null }
): Promise<ConnectRow | Response> {
  let row = await getConnectRow(env, user.userId);
  if (row) {
    // A payout account minted under TEST keys stops existing once the
    // platform switches to LIVE keys. Verify before reusing — when Stripe
    // no longer recognises the stored account, drop it and mint a fresh
    // one in the current mode instead of failing every downstream call.
    const existing = await stripeRequest(
      env,
      `/accounts/${encodeURIComponent(row.stripe_account_id)}`
    );
    if (existing.ok) {
      // Accounts minted before the capability fix requested `transfers`
      // alone, which Stripe gates behind manual platform approval. Upgrade
      // them in place to the auto-approved card_payments + transfers pair
      // so onboarding can finish without ever contacting Stripe.
      const caps = existing.data.capabilities as
        | Record<string, unknown>
        | null
        | undefined;
      if (!caps || !("card_payments" in caps)) {
        const upgrade = new URLSearchParams();
        upgrade.set("capabilities[card_payments][requested]", "true");
        upgrade.set("capabilities[transfers][requested]", "true");
        await stripeRequest(
          env,
          `/accounts/${encodeURIComponent(row.stripe_account_id)}`,
          upgrade
        );
      }
      return row;
    }
    if (!isMissingAccountError(existing)) return row;
    await clearStaleConnect(env, user.userId, row.stripe_account_id);
    row = null;
  }

  const params = new URLSearchParams();
  params.set("type", "express");
  if (user.email) params.set("email", user.email);
  params.set("capabilities[transfers][requested]", "true");
  params.set("capabilities[card_payments][requested]", "true");
  params.set("business_type", "individual");
  params.set("business_profile[url]", SITE_URL);
  params.set("business_profile[mcc]", "7298"); // health & fitness services
  params.set(
    "business_profile[product_description]",
    "Personal fitness coaching on Whisper"
  );
  if (user.email) params.set("individual[email]", user.email);
  params.set("settings[payouts][schedule][interval]", "manual");
  params.set("metadata[whisperUserId]", user.userId);
  const account = await stripeRequest(env, "/accounts", params);
  if (!account.ok || typeof account.data.id !== "string") {
    const err = account.data.error as { message?: string } | undefined;
    console.error("Connect account creation failed", {
      status: account.status,
      error: err?.message,
    });
    // Stripe Connect hasn't been activated on the platform account yet.
    if (err?.message?.includes("signed up for Connect")) {
      return json({ error: "connect_not_enabled" }, 503);
    }
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  await supabaseAdmin(env, "/whisper_coach_connect?on_conflict=user_id", {
    method: "POST",
    prefer: "resolution=merge-duplicates",
    body: {
      user_id: user.userId,
      stripe_account_id: account.data.id,
      charges_enabled: false,
      payouts_enabled: false,
      details_submitted: false,
      updated_at: new Date().toISOString(),
    },
  });
  row = {
    user_id: user.userId,
    stripe_account_id: account.data.id,
    charges_enabled: false,
    payouts_enabled: false,
    details_submitted: false,
  };
  return row;
}

/**
 * POST /coach/connect/session — embedded onboarding (stays in our app).
 * Creates an Account Session so the web app can render Stripe's embedded
 * onboarding component inline, exactly like Cash App / DoorDash do.
 */
async function handleConnectSession(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) {
    return json({ error: "billing_not_configured" }, 503);
  }
  if (!env.STRIPE_PUBLISHABLE_KEY) {
    // Frontend falls back to the hosted onboarding redirect.
    return json({ error: "embedded_not_configured" }, 503);
  }
  // Stripe rejects an embedded session whose client secret was minted in a
  // different mode (test vs live) than the publishable key. Fall back to the
  // hosted redirect (which only needs the secret key) instead of erroring.
  const secretIsTest = env.STRIPE_SECRET_KEY.startsWith("sk_test_");
  const publishableIsTest = env.STRIPE_PUBLISHABLE_KEY.startsWith("pk_test_");
  if (secretIsTest !== publishableIsTest) {
    console.error("Stripe key mode mismatch", {
      secretMode: secretIsTest ? "test" : "live",
      publishableMode: publishableIsTest ? "test" : "live",
    });
    return json({ error: "embedded_not_configured" }, 503);
  }
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  if (!(await canReceivePayouts(env, user.userId))) {
    return json({ error: "not_payout_eligible" }, 403);
  }

  const row = await ensureConnectAccount(env, user);
  if (row instanceof Response) return row;

  const params = new URLSearchParams();
  params.set("account", row.stripe_account_id);
  params.set("components[account_onboarding][enabled]", "true");
  params.set(
    "components[account_onboarding][features][external_account_collection]",
    "true"
  );
  const session = await stripeRequest(env, "/account_sessions", params);
  if (!session.ok || typeof session.data.client_secret !== "string") {
    const err = session.data.error as { message?: string } | undefined;
    console.error("Account session failed", {
      status: session.status,
      error: err?.message,
    });
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  return json({
    clientSecret: session.data.client_secret,
    publishableKey: env.STRIPE_PUBLISHABLE_KEY,
  });
}

/** POST /coach/connect/onboard — hosted onboarding link (fallback). */
async function handleConnectOnboard(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) return json({ error: "billing_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  if (!(await canReceivePayouts(env, user.userId))) {
    return json({ error: "not_payout_eligible" }, 403);
  }

  let body: { origin?: string };
  try {
    body = (await request.json()) as { origin?: string };
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  let origin: URL;
  try {
    origin = new URL(body.origin ?? "");
  } catch {
    origin = new URL(SITE_URL);
  }

  const row = await ensureConnectAccount(env, user);
  if (row instanceof Response) return row;

  const linkParams = new URLSearchParams();
  linkParams.set("account", row.stripe_account_id);
  linkParams.set("refresh_url", `${origin.origin}/coach/earnings`);
  linkParams.set("return_url", `${origin.origin}/coach/earnings?onboarded=1`);
  linkParams.set("type", "account_onboarding");
  const link = await stripeRequest(env, "/account_links", linkParams);
  if (!link.ok || typeof link.data.url !== "string") {
    const err = link.data.error as { message?: string } | undefined;
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  return json({ url: link.data.url });
}

/** GET /coach/connect/status — onboarding + payout readiness. */
async function handleConnectStatus(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const row = await getConnectRow(env, user.userId);
  if (!row) return json({ connected: false });
  if (!env.STRIPE_SECRET_KEY) return json({ connected: false });
  const status = await refreshConnectStatus(
    env,
    user.userId,
    row.stripe_account_id
  );
  if (status.accountMissing) {
    // Test-mode account read with live keys — the row was cleared so the
    // owner can reconnect and mint a live-mode account.
    return json({ connected: false, reset: true });
  }
  return json({ connected: true, ...status });
}

/** POST /coach/connect/dashboard — Stripe Express dashboard login link. */
async function handleConnectDashboard(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) return json({ error: "billing_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const row = await getConnectRow(env, user.userId);
  if (!row) return json({ error: "not_connected" }, 404);
  const link = await stripeRequest(
    env,
    `/accounts/${encodeURIComponent(row.stripe_account_id)}/login_links`,
    new URLSearchParams()
  );
  if (!link.ok || typeof link.data.url !== "string") {
    if (isMissingAccountError(link)) {
      await clearStaleConnect(env, user.userId, row.stripe_account_id);
      return json({ error: "not_connected" }, 404);
    }
    return json({ error: "stripe_error" }, 502);
  }
  return json({ url: link.data.url });
}

/**
 * GET /coach/stripe/overview — the user's FULL Stripe standing rendered
 * inside Whisper (no Express-dashboard hop): account status + requirements,
 * live balance, bank on file, payout schedule, recent payouts, and recent
 * incoming transfers. Everything sanitized — no account ids or raw keys.
 */
async function handleStripeOverview(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  if (!env.STRIPE_SECRET_KEY) return json({ connected: false });
  const row = await getFreshConnectRow(env, user.userId);
  if (!row) return json({ connected: false });
  const acct = row.stripe_account_id;
  const [account, balance, payouts, transfers] = await Promise.all([
    stripeRequest(env, `/accounts/${encodeURIComponent(acct)}`),
    stripeRequest(env, "/balance", undefined, acct),
    stripeRequest(env, "/payouts?limit=15", undefined, acct),
    stripeRequest(
      env,
      `/transfers?destination=${encodeURIComponent(acct)}&limit=15`
    ),
  ]);
  if (!account.ok) {
    if (isMissingAccountError(account)) {
      await clearStaleConnect(env, user.userId, acct);
      return json({ connected: false, reset: true });
    }
    return json({ error: "stripe_error" }, 502);
  }

  const acc = account.data as Record<string, unknown>;
  const req = (acc.requirements ?? {}) as {
    currently_due?: string[];
    past_due?: string[];
    disabled_reason?: string | null;
  };
  const prettify = (key: string): string =>
    key
      .replace(/^individual\./, "")
      .replace(/^company\./, "")
      .replace(/[._]/g, " ")
      .replace(/\b\w/g, (c) => c.toUpperCase());
  const due = Array.from(
    new Set([...(req.currently_due ?? []), ...(req.past_due ?? [])])
  ).map(prettify);

  // Bank on file — name + last4 only.
  const extAccounts = (acc.external_accounts ?? {}) as {
    data?: Record<string, unknown>[];
  };
  const bankRow = (extAccounts.data ?? []).find(
    (b) => b.object === "bank_account" || b.object === "card"
  );
  const bank = bankRow
    ? {
        bankName: String(bankRow.bank_name ?? bankRow.brand ?? "Bank"),
        last4: String(bankRow.last4 ?? "••••"),
        currency: String(bankRow.currency ?? "usd").toUpperCase(),
      }
    : null;

  const settings = (acc.settings ?? {}) as {
    payouts?: { schedule?: { interval?: string; delay_days?: number } };
  };
  const schedule = settings.payouts?.schedule ?? {};

  const sumBalance = (
    rows: { amount?: number; currency?: string }[] | undefined
  ): number =>
    (rows ?? [])
      .filter((b) => (b.currency ?? "usd") === "usd")
      .reduce((s, b) => s + (b.amount ?? 0), 0);
  const bal = balance.ok
    ? (balance.data as {
        available?: { amount?: number; currency?: string }[];
        pending?: { amount?: number; currency?: string }[];
      })
    : {};

  const payoutRows = payouts.ok
    ? ((payouts.data.data ?? []) as Record<string, unknown>[]).map((p) => ({
        amountCents: typeof p.amount === "number" ? p.amount : 0,
        status: String(p.status ?? ""),
        arrivalDate:
          typeof p.arrival_date === "number"
            ? new Date(p.arrival_date * 1000).toISOString()
            : null,
        createdAt:
          typeof p.created === "number"
            ? new Date(p.created * 1000).toISOString()
            : null,
      }))
    : [];
  const transferRows = transfers.ok
    ? ((transfers.data.data ?? []) as Record<string, unknown>[]).map((t) => ({
        amountCents: typeof t.amount === "number" ? t.amount : 0,
        description: String(t.description ?? "Earnings transfer"),
        createdAt:
          typeof t.created === "number"
            ? new Date(t.created * 1000).toISOString()
            : null,
      }))
    : [];

  return json({
    connected: true,
    chargesEnabled: acc.charges_enabled === true,
    payoutsEnabled: acc.payouts_enabled === true,
    detailsSubmitted: acc.details_submitted === true,
    requirementsDue: due.slice(0, 8),
    disabledReason: req.disabled_reason ?? null,
    balance: {
      availableCents: sumBalance(bal.available),
      pendingCents: sumBalance(bal.pending),
    },
    bank,
    payoutSchedule: {
      interval: String(schedule.interval ?? "daily"),
      delayDays: typeof schedule.delay_days === "number" ? schedule.delay_days : 2,
    },
    payouts: payoutRows,
    transfers: transferRows,
  });
}

/** POST /coach/pricing — the coach sets their own monthly rate. */
async function handleCoachPricingSet(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  if (!(await isCoach(env, user.userId))) {
    return json({ error: "not_a_coach" }, 403);
  }

  let body: { monthlyPriceCents?: number; active?: boolean };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const cents = Math.round(Number(body.monthlyPriceCents));
  if (
    !Number.isFinite(cents) ||
    cents < COACH_PRICE_MIN_CENTS ||
    cents > COACH_PRICE_MAX_CENTS
  ) {
    return json({ error: "invalid_price" }, 400);
  }

  const ok = await supabaseAdmin(
    env,
    "/whisper_coach_pricing?on_conflict=user_id",
    {
      method: "POST",
      prefer: "resolution=merge-duplicates",
      body: {
        user_id: user.userId,
        monthly_price_cents: cents,
        active: body.active !== false,
        updated_at: new Date().toISOString(),
      },
    }
  );
  if (!ok.ok) return json({ error: "db_error" }, 500);
  return json({ ok: true, monthlyPriceCents: cents, active: body.active !== false });
}

/** GET /coach/pricing?userId=… — public rate card for the hire page. */
async function handleCoachPricingGet(
  request: Request,
  env: Env
): Promise<Response> {
  const userId = new URL(request.url).searchParams.get("userId") ?? "";
  if (!userId) return json({ error: "missing_user" }, 400);
  const uid = encodeURIComponent(userId);
  const [pricingRows, connectRow, profileRows, tierRows] = await Promise.all([
    supabaseSelect(
      env,
      `/whisper_coach_pricing?user_id=eq.${uid}&select=monthly_price_cents,active&limit=1`
    ),
    getFreshConnectRow(env, userId),
    supabaseSelect(
      env,
      `/whisper_profiles?user_id=eq.${uid}&select=username,display_name&limit=1`
    ),
    supabaseSelect(
      env,
      `/whisper_coach_plans?coach_user_id=eq.${uid}&active=eq.true&select=id,name,tagline,monthly_price_cents,perks,max_clients,sort&order=sort.asc,monthly_price_cents.asc&limit=6`
    ),
  ]);
  const pricing = pricingRows?.[0] as
    | { monthly_price_cents?: number; active?: boolean }
    | undefined;
  const profile = profileRows?.[0] as
    | { username?: string; display_name?: string }
    | undefined;
  return json({
    monthlyPriceCents: pricing?.monthly_price_cents ?? null,
    active: pricing?.active === true,
    acceptingPayments:
      connectRow?.payouts_enabled === true ||
      connectRow?.charges_enabled === true,
    username: profile?.username ?? null,
    displayName: profile?.display_name ?? null,
    tiers: normalizeTierRows(tierRows),
  });
}

// ---------------------------------------------------------------------------
// Coach plan tiers — coaches define up to 3 plans (e.g. Check-ins / Full
// coaching / Elite 1-on-1), each with its own monthly price and perk list.
// Clients pick a tier on the hire page; the legacy single monthly rate stays
// as the fallback when a coach hasn't created tiers.
// ---------------------------------------------------------------------------

interface CoachTierRow {
  id: string;
  name?: string | null;
  tagline?: string | null;
  monthly_price_cents?: number | null;
  perks?: unknown;
  max_clients?: number | null;
  sort?: number | null;
}

interface CoachTierWire {
  id: string;
  name: string;
  tagline: string | null;
  monthlyPriceCents: number;
  perks: string[];
  maxClients: number | null;
  sort: number;
}

/** Map DB tier rows to the camelCase wire shape both clients render. */
function normalizeTierRows(rows: unknown[] | null): CoachTierWire[] {
  const out: CoachTierWire[] = [];
  for (const raw of rows ?? []) {
    const r = raw as CoachTierRow;
    const price = Math.round(Number(r.monthly_price_cents));
    if (!r.id || !Number.isFinite(price) || price <= 0) continue;
    const perks = Array.isArray(r.perks)
      ? (r.perks as unknown[])
          .map((p) => String(p ?? "").trim())
          .filter((p) => p.length > 0)
          .slice(0, 6)
      : [];
    out.push({
      id: r.id,
      name: (r.name ?? "").trim() || "Plan",
      tagline: (r.tagline ?? "").toString().trim() || null,
      monthlyPriceCents: price,
      perks,
      maxClients: typeof r.max_clients === "number" ? r.max_clients : null,
      sort: typeof r.sort === "number" ? r.sort : 0,
    });
  }
  return out;
}

/**
 * POST /coach/tiers — replace the signed-in coach's plan tiers (max 3).
 * Ids are preserved when provided so existing subscriptions' metadata keeps
 * pointing at a real tier; omitted tiers are deleted.
 */
async function handleCoachTiersSet(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  if (!(await isCoach(env, user.userId))) {
    return json({ error: "not_a_coach" }, 403);
  }

  let body: { tiers?: Array<Record<string, unknown>> };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const input = Array.isArray(body.tiers) ? body.tiers.slice(0, 3) : [];

  const now = new Date().toISOString();
  const rows: Array<Record<string, unknown>> = [];
  for (let i = 0; i < input.length; i++) {
    const t = input[i] ?? {};
    const name = String(t.name ?? "").trim().slice(0, 40);
    if (name.length < 2) return json({ error: "invalid_tier_name" }, 400);
    const price = Math.round(Number(t.priceCents));
    if (
      !Number.isFinite(price) ||
      price < COACH_PRICE_MIN_CENTS ||
      price > COACH_PRICE_MAX_CENTS
    ) {
      return json({ error: "invalid_tier_price" }, 400);
    }
    const perks = Array.isArray(t.perks)
      ? (t.perks as unknown[])
          .map((p) => String(p ?? "").trim().slice(0, 90))
          .filter((p) => p.length > 0)
          .slice(0, 6)
      : [];
    const maxRaw = Math.round(Number(t.maxClients));
    rows.push({
      id:
        typeof t.id === "string" && UUID_RE.test(t.id)
          ? t.id
          : crypto.randomUUID(),
      coach_user_id: user.userId,
      name,
      tagline: String(t.tagline ?? "").trim().slice(0, 80) || null,
      monthly_price_cents: price,
      perks,
      max_clients:
        Number.isFinite(maxRaw) && maxRaw > 0 ? Math.min(maxRaw, 500) : null,
      active: t.active !== false,
      sort: i,
      updated_at: now,
    });
  }

  // Replace-all: drop tiers not in the submitted set, then upsert the rest.
  const uid = encodeURIComponent(user.userId);
  const keep = rows.map((r) => String(r.id));
  const delPath =
    keep.length > 0
      ? `/whisper_coach_plans?coach_user_id=eq.${uid}&id=not.in.(${keep
          .map(encodeURIComponent)
          .join(",")})`
      : `/whisper_coach_plans?coach_user_id=eq.${uid}`;
  const del = await supabaseAdmin(env, delPath, { method: "DELETE" });
  if (!del.ok) return json({ error: "db_error" }, 500);
  if (rows.length > 0) {
    const up = await supabaseAdmin(env, "/whisper_coach_plans?on_conflict=id", {
      method: "POST",
      prefer: "resolution=merge-duplicates",
      body: rows,
    });
    if (!up.ok) return json({ error: "db_error" }, 500);
  }
  console.log("Coach tiers saved", { coach: user.userId, count: rows.length });
  return json({ ok: true, count: rows.length });
}

/** GET /coach/tiers?coachUserId=… — public: a coach's active tiers. */
async function handleCoachTiersGet(
  request: Request,
  env: Env
): Promise<Response> {
  const coachUserId =
    new URL(request.url).searchParams.get("coachUserId") ?? "";
  if (!coachUserId) return json({ error: "missing_coach" }, 400);
  const rows = await supabaseSelect(
    env,
    `/whisper_coach_plans?coach_user_id=eq.${encodeURIComponent(
      coachUserId
    )}&active=eq.true&select=id,name,tagline,monthly_price_cents,perks,max_clients,sort&order=sort.asc,monthly_price_cents.asc&limit=6`
  );
  return json({ tiers: normalizeTierRows(rows) });
}

/** GET /coach/earnings — ledger history + live Stripe balance. */
async function handleCoachEarnings(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  const uid = encodeURIComponent(user.userId);
  const [ledger, row] = await Promise.all([
    supabaseSelect(
      env,
      `/whisper_coach_earnings?coach_user_id=eq.${uid}&select=gross_cents,fee_cents,net_cents,client_email,description,created_at&order=created_at.desc&limit=100`
    ),
    getFreshConnectRow(env, user.userId),
  ]);

  const payments = (ledger ?? []) as {
    gross_cents: number;
    fee_cents: number;
    net_cents: number;
    client_email: string | null;
    description: string | null;
    created_at: string;
  }[];
  const totalEarnedCents = payments.reduce(
    (sum, p) => sum + (p.net_cents ?? 0),
    0
  );

  let availableCents = 0;
  let pendingCents = 0;
  let connected = !!row;
  let payoutsEnabled = row?.payouts_enabled === true;
  let chargesEnabled = row?.charges_enabled === true;
  if (row && env.STRIPE_SECRET_KEY) {
    const balance = await stripeRequest(
      env,
      "/balance",
      undefined,
      row.stripe_account_id
    );
    if (!balance.ok && isMissingAccountError(balance)) {
      // Test-mode payout account read with live keys — reset it so the
      // coach can reconnect and mint a live-mode account.
      await clearStaleConnect(env, user.userId, row.stripe_account_id);
      connected = false;
      payoutsEnabled = false;
      chargesEnabled = false;
    }
    const sumUsd = (list: unknown): number =>
      Array.isArray(list)
        ? list
            .filter(
              (b): b is { amount: number; currency: string } =>
                typeof (b as { amount?: unknown }).amount === "number" &&
                (b as { currency?: string }).currency === "usd"
            )
            .reduce((s, b) => s + b.amount, 0)
        : 0;
    availableCents = sumUsd(balance.data.available);
    pendingCents = sumUsd(balance.data.pending);
  }

  return json({
    connected,
    payoutsEnabled,
    chargesEnabled,
    totalEarnedCents,
    availableCents,
    pendingCents,
    payments: payments.slice(0, 25),
  });
}

/** POST /coach/payout — cash out the full available balance. */
async function handleCoachPayout(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) return json({ error: "billing_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const row = await getConnectRow(env, user.userId);
  if (!row) return json({ error: "not_connected" }, 404);

  const balance = await stripeRequest(
    env,
    "/balance",
    undefined,
    row.stripe_account_id
  );
  if (!balance.ok && isMissingAccountError(balance)) {
    await clearStaleConnect(env, user.userId, row.stripe_account_id);
    return json({ error: "not_connected" }, 404);
  }
  const available = Array.isArray(balance.data.available)
    ? (balance.data.available as { amount: number; currency: string }[])
        .filter((b) => b.currency === "usd")
        .reduce((s, b) => s + b.amount, 0)
    : 0;
  if (available < 100) {
    return json({ error: "insufficient_balance", availableCents: available }, 400);
  }

  const params = new URLSearchParams();
  params.set("amount", String(available));
  params.set("currency", "usd");
  const payout = await stripeRequest(
    env,
    "/payouts",
    params,
    row.stripe_account_id
  );
  if (!payout.ok) {
    const err = payout.data.error as { message?: string } | undefined;
    console.error("Coach payout failed", { error: err?.message });
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  return json({ ok: true, amountCents: available });
}

/** POST /coach/hire-checkout — a client subscribes to a coach's rate. */
async function handleCoachHireCheckout(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) return json({ error: "billing_not_configured" }, 503);

  let body: {
    coachUserId?: string;
    tierId?: string;
    userId?: string;
    email?: string;
    origin?: string;
    cancelPath?: string;
    mode?: string;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  // The paying client is the SIGNED-IN caller (live-mode hardening).
  const caller = await requireUser(request, env);
  if (caller instanceof Response) return caller;
  body.userId = caller.userId;
  if (!body.email && caller.email) body.email = caller.email;
  if (!body.coachUserId) return json({ error: "missing_coach" }, 400);
  if (body.coachUserId === body.userId) {
    return json({ error: "cannot_hire_self" }, 400);
  }
  const embedded = body.mode === "embedded";

  let origin: URL;
  try {
    origin = new URL(body.origin ?? "");
  } catch {
    return json({ error: "invalid_origin" }, 400);
  }

  const uid = encodeURIComponent(body.coachUserId);
  const [pricingRows, connectRow, profileRows] = await Promise.all([
    supabaseSelect(
      env,
      `/whisper_coach_pricing?user_id=eq.${uid}&active=eq.true&select=monthly_price_cents&limit=1`
    ),
    getFreshConnectRow(env, body.coachUserId),
    supabaseSelect(
      env,
      `/whisper_profiles?user_id=eq.${uid}&select=username&limit=1`
    ),
  ]);
  let priceCents = (
    pricingRows?.[0] as { monthly_price_cents?: number } | undefined
  )?.monthly_price_cents;
  // Tiered pricing: when the client picked one of the coach's plans, charge
  // that tier's price and stamp its name through checkout + metadata.
  let tierName: string | null = null;
  const tierId = (body.tierId ?? "").trim();
  if (tierId) {
    if (!UUID_RE.test(tierId)) return json({ error: "tier_not_found" }, 404);
    const tierRows = await supabaseSelect(
      env,
      `/whisper_coach_plans?id=eq.${encodeURIComponent(tierId)}&coach_user_id=eq.${uid}&active=eq.true&select=id,name,monthly_price_cents&limit=1`
    );
    const tier = tierRows?.[0] as
      | { id: string; name?: string; monthly_price_cents?: number }
      | undefined;
    if (!tier) return json({ error: "tier_not_found" }, 404);
    const tierPrice = Math.round(Number(tier.monthly_price_cents));
    if (
      !Number.isFinite(tierPrice) ||
      tierPrice < COACH_PRICE_MIN_CENTS ||
      tierPrice > COACH_PRICE_MAX_CENTS
    ) {
      return json({ error: "tier_not_priced" }, 400);
    }
    priceCents = tierPrice;
    tierName = (tier.name ?? "").trim().slice(0, 60) || null;
  }
  if (!priceCents || priceCents < COACH_PRICE_MIN_CENTS) {
    return json({ error: "coach_not_priced" }, 400);
  }
  // Ready once payouts (or charges) are enabled — clients pay Whisper's
  // platform account directly; the coach account only receives transfers.
  if (!connectRow?.payouts_enabled && !connectRow?.charges_enabled) {
    return json({ error: "coach_not_ready" }, 400);
  }
  const username =
    (profileRows?.[0] as { username?: string } | undefined)?.username ??
    "your coach";

  const cancelUrl = `${origin.origin}${body.cancelPath && body.cancelPath.startsWith("/") ? body.cancelPath : "/"}`;
  const params = new URLSearchParams();
  params.set("mode", "subscription");
  if (embedded) {
    // Stripe renamed this value on newer API versions — accounts pinned to
    // 2025+ reject "embedded" with "use embedded_page instead".
    params.set("ui_mode", "embedded_page");
    params.set("return_url", `${origin.origin}/billing/success?embedded=1&session_id={CHECKOUT_SESSION_ID}`);
  }
  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", "usd");
  params.set("line_items[0][price_data][unit_amount]", String(priceCents));
  params.set("line_items[0][price_data][recurring][interval]", "month");
  params.set(
    "line_items[0][price_data][product_data][name]",
    tierName ? `Coaching with @${username} — ${tierName}` : `Coaching with @${username}`
  );
  params.set(
    "subscription_data[application_fee_percent]",
    String(COACH_PLATFORM_FEE_PERCENT)
  );
  params.set(
    "subscription_data[transfer_data][destination]",
    connectRow.stripe_account_id
  );
  if (!embedded) {
    params.set(
      "success_url",
      `${origin.origin}/billing/success?session_id={CHECKOUT_SESSION_ID}`
    );
    params.set("cancel_url", cancelUrl);
  }
  params.set("metadata[kind]", "coach-hire");
  params.set("metadata[coachUserId]", body.coachUserId);
  params.set("metadata[whisperUserId]", body.userId);
  params.set("subscription_data[metadata][kind]", "coach-hire");
  params.set("subscription_data[metadata][coachUserId]", body.coachUserId);
  params.set("subscription_data[metadata][whisperUserId]", body.userId);
  if (tierId && tierName) {
    params.set("metadata[tierId]", tierId);
    params.set("metadata[tierName]", tierName);
    params.set("subscription_data[metadata][tierId]", tierId);
    params.set("subscription_data[metadata][tierName]", tierName);
  }
  if (body.email) params.set("customer_email", body.email);

  const session = await stripeRequest(env, "/checkout/sessions", params);
  if (!session.ok && isMissingAccountError(session)) {
    // The coach's payout account was minted under TEST keys and doesn't
    // exist on live payments. Reset it so Coach Studio shows "Connect
    // payouts" again, and tell the buyer what's actually going on.
    await clearStaleConnect(
      env,
      body.coachUserId,
      connectRow.stripe_account_id
    );
    console.error("Coach hire blocked — stale payout account reset", {
      coachUserId: body.coachUserId,
    });
    return json(
      {
        error: "coach_not_ready",
        stripeMessage: `@${username}'s payout account needs to be reconnected for live payments (it was set up in test mode). It's been reset — once they reconnect payouts in Coach Studio, hiring will work.`,
      },
      409
    );
  }
  if (embedded) {
    if (!session.ok || typeof session.data.client_secret !== "string") {
      const err = session.data.error as { message?: string } | undefined;
      console.error("Coach hire embedded checkout failed", {
        status: session.status,
        error: err?.message,
      });
      return json(
        { error: "stripe_error", stripeMessage: err?.message ?? null },
        502
      );
    }
    return json({
      clientSecret: session.data.client_secret,
      publishableKey: env.STRIPE_PUBLISHABLE_KEY ?? null,
    });
  }
  if (!session.ok || typeof session.data.url !== "string") {
    const err = session.data.error as { message?: string } | undefined;
    console.error("Coach hire checkout failed", {
      status: session.status,
      error: err?.message,
    });
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  return json({ url: session.data.url });
}

/**
 * GET /coach/my-hires — the signed-in client's active coaching
 * subscriptions (searched by Stripe metadata), so they can review and
 * cancel from Settings. Cancelling stops future renewals; access runs to
 * the end of the paid month.
 */
async function handleMyCoachSubscriptions(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  if (!env.STRIPE_SECRET_KEY) return json({ subscriptions: [] });

  const query = `metadata['kind']:'coach-hire' AND metadata['whisperUserId']:'${user.userId}'`;
  const search = await stripeRequest(
    env,
    `/subscriptions/search?query=${encodeURIComponent(query)}&limit=20`
  );
  if (!search.ok) {
    console.error("Coach subscription search failed", { status: search.status });
    return json({ error: "stripe_error" }, 502);
  }

  const rows = Array.isArray(search.data.data)
    ? (search.data.data as Record<string, unknown>[])
    : [];
  const active = rows.filter((s) =>
    ["active", "trialing", "past_due"].includes(String(s.status ?? ""))
  );

  // Resolve coach usernames for display.
  const coachIds = Array.from(
    new Set(
      active
        .map(
          (s) =>
            ((s.metadata ?? {}) as Record<string, string>).coachUserId ?? ""
        )
        .filter(Boolean)
    )
  );
  const nameById = new Map<string, string>();
  if (coachIds.length > 0) {
    const profs = await supabaseSelect(
      env,
      `/whisper_profiles?user_id=in.(${coachIds
        .map((id) => encodeURIComponent(id))
        .join(",")})&select=user_id,username&limit=20`
    );
    for (const p of (profs ?? []) as { user_id?: string; username?: string }[]) {
      if (p.user_id && p.username) nameById.set(p.user_id, p.username);
    }
  }

  const subscriptions = active.map((s) => {
    const meta = (s.metadata ?? {}) as Record<string, string>;
    const items = (s.items as { data?: { price?: { unit_amount?: number } }[] })
      ?.data;
    const periodEnd =
      typeof s.current_period_end === "number" ? s.current_period_end : null;
    return {
      id: String(s.id ?? ""),
      coachUserId: meta.coachUserId ?? null,
      coachUsername: nameById.get(meta.coachUserId ?? "") ?? null,
      priceCents: items?.[0]?.price?.unit_amount ?? null,
      status: String(s.status ?? ""),
      cancelAtPeriodEnd: Boolean(s.cancel_at_period_end),
      currentPeriodEnd: periodEnd ? new Date(periodEnd * 1000).toISOString() : null,
    };
  });

  return json({ subscriptions });
}

/**
 * POST /coach/hire-cancel — stop a coaching subscription at the end of the
 * current paid month. Ownership is verified against the subscription's
 * Stripe metadata so users can only cancel their own.
 */
async function handleCoachHireCancel(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  if (!env.STRIPE_SECRET_KEY) return json({ error: "billing_not_configured" }, 503);

  let body: { subscriptionId?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const subId = (body.subscriptionId ?? "").trim();
  if (!subId.startsWith("sub_")) return json({ error: "invalid_body" }, 400);

  const sub = await stripeRequest(env, `/subscriptions/${encodeURIComponent(subId)}`);
  if (!sub.ok) return json({ error: "not_found" }, 404);
  const meta = (sub.data.metadata ?? {}) as Record<string, string>;
  if (meta.kind !== "coach-hire" || meta.whisperUserId !== user.userId) {
    return json({ error: "forbidden" }, 403);
  }

  const params = new URLSearchParams();
  params.set("cancel_at_period_end", "true");
  const updated = await stripeRequest(
    env,
    `/subscriptions/${encodeURIComponent(subId)}`,
    params
  );
  if (!updated.ok) return json({ error: "stripe_error" }, 502);

  console.log("Coach hire cancel scheduled", { sub: subId });
  return json({ ok: true, cancelAtPeriodEnd: true });
}

/**
 * GET /coach/hire-status?coachUserId=... — the signed-in client's payment
 * standing with a coach. `requiresPayment` is true when the coach has an
 * active rate and a payout-ready bank account; `paid` is true when the
 * client has a coach-hire payment in the earnings ledger within the last
 * 40 days (covers a monthly cycle plus grace).
 */
async function handleCoachHireStatus(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  const url = new URL(request.url);
  const coachUserId = url.searchParams.get("coachUserId") ?? "";
  if (!coachUserId) return json({ error: "missing_coach" }, 400);
  const uid = encodeURIComponent(coachUserId);

  const since = new Date(Date.now() - 40 * 86_400_000).toISOString();
  const paidQueryBase = `/whisper_coach_earnings?coach_user_id=eq.${uid}&client_user_id=eq.${encodeURIComponent(
    user.userId
  )}&created_at=gte.${encodeURIComponent(since)}&select=id,created_at&limit=1`;
  const [pricingRows, connectRow, paymentRowsFiltered] = await Promise.all([
    supabaseSelect(
      env,
      `/whisper_coach_pricing?user_id=eq.${uid}&active=eq.true&select=monthly_price_cents&limit=1`
    ),
    getFreshConnectRow(env, coachUserId),
    // Exclude refunded charges; falls back below when the `refunded`
    // column migration hasn't been run yet (query would 400 → null).
    supabaseSelect(env, `${paidQueryBase}&refunded=not.is.true`),
  ]);
  const paymentRows =
    paymentRowsFiltered ?? (await supabaseSelect(env, paidQueryBase));

  const priceCents =
    (pricingRows?.[0] as { monthly_price_cents?: number } | undefined)
      ?.monthly_price_cents ?? null;
  const coachReady = Boolean(
    connectRow?.payouts_enabled || connectRow?.charges_enabled
  );
  const paid = Array.isArray(paymentRows) && paymentRows.length > 0;

  return json({
    requiresPayment: Boolean(priceCents) && coachReady,
    priceCents,
    paid,
  });
}

// ---------------------------------------------------------------------------
// Program purchases — one-time destination charges
//
// Coaches can price individual training programs (price lives in the
// program's JSON payload as `priceCents`). Clients buy them once; the sale
// lands in the same earnings ledger tagged with a `[program:{id}]` marker so
// entitlement checks and payout math need no new tables.
// ---------------------------------------------------------------------------

interface ProgramRow {
  id: string;
  coach_user_id: string;
  coach_username: string | null;
  title: string | null;
  payload: Record<string, unknown> | null;
}

async function getProgramRow(
  env: Env,
  programId: string
): Promise<ProgramRow | null> {
  const rows = await supabaseSelect(
    env,
    `/whisper_coach_programs?id=eq.${encodeURIComponent(programId)}&select=id,coach_user_id,coach_username,title,payload&limit=1`
  );
  return (rows?.[0] as ProgramRow | undefined) ?? null;
}

/** Read the one-time price (cents) from a program's JSON payload. */
function programPriceCents(program: ProgramRow): number {
  const raw = (program.payload as { priceCents?: unknown } | null)?.priceCents;
  const n = Math.round(Number(raw));
  if (!Number.isFinite(n) || n <= 0) return 0;
  return Math.min(COACH_PRICE_MAX_CENTS, Math.max(COACH_PRICE_MIN_CENTS, n));
}

/** True when this client already owns the program (earnings marker row). */
async function hasProgramPurchase(
  env: Env,
  programId: string,
  clientUserId: string
): Promise<boolean> {
  const marker = encodeURIComponent(`*[program:${programId}]*`);
  const base = `/whisper_coach_earnings?client_user_id=eq.${encodeURIComponent(
    clientUserId
  )}&description=like.${marker}&select=id&limit=1`;
  // Refunded purchases lose access; fall back to the unfiltered query when
  // the `refunded` column migration hasn't been run yet.
  const rows =
    (await supabaseSelect(env, `${base}&refunded=not.is.true`)) ??
    (await supabaseSelect(env, base));
  return Array.isArray(rows) && rows.length > 0;
}

/** POST /coach/program-checkout — buy a single training program. */
async function handleProgramCheckout(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) return json({ error: "billing_not_configured" }, 503);

  let body: {
    programId?: string;
    userId?: string;
    email?: string;
    origin?: string;
    cancelPath?: string;
    mode?: string;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  // The buyer is the SIGNED-IN caller (live-mode hardening).
  const caller = await requireUser(request, env);
  if (caller instanceof Response) return caller;
  body.userId = caller.userId;
  if (!body.email && caller.email) body.email = caller.email;
  if (!body.programId) return json({ error: "missing_program" }, 400);
  const embedded = body.mode === "embedded";

  let origin: URL;
  try {
    origin = new URL(body.origin ?? "");
  } catch {
    return json({ error: "invalid_origin" }, 400);
  }

  const program = await getProgramRow(env, body.programId);
  if (!program) return json({ error: "program_not_found" }, 404);
  if (program.coach_user_id === body.userId) {
    return json({ error: "cannot_buy_own_program" }, 400);
  }
  const priceCents = programPriceCents(program);
  if (!priceCents) return json({ error: "program_not_priced" }, 400);

  const connectRow = await getFreshConnectRow(env, program.coach_user_id);
  if (!connectRow?.payouts_enabled && !connectRow?.charges_enabled) {
    return json({ error: "coach_not_ready" }, 400);
  }

  if (await hasProgramPurchase(env, program.id, body.userId)) {
    return json({ alreadyPurchased: true });
  }

  const title = program.title?.trim() || "Training program";
  const feeCents = Math.round((priceCents * COACH_PLATFORM_FEE_PERCENT) / 100);
  const cancelUrl = `${origin.origin}${body.cancelPath && body.cancelPath.startsWith("/") ? body.cancelPath : "/"}`;

  const params = new URLSearchParams();
  params.set("mode", "payment");
  if (embedded) {
    // Stripe renamed this value on newer API versions — accounts pinned to
    // 2025+ reject "embedded" with "use embedded_page instead".
    params.set("ui_mode", "embedded_page");
    params.set(
      "return_url",
      `${origin.origin}/billing/success?embedded=1&session_id={CHECKOUT_SESSION_ID}`
    );
  } else {
    params.set(
      "success_url",
      `${origin.origin}/billing/success?session_id={CHECKOUT_SESSION_ID}`
    );
    params.set("cancel_url", cancelUrl);
  }
  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", "usd");
  params.set("line_items[0][price_data][unit_amount]", String(priceCents));
  params.set(
    "line_items[0][price_data][product_data][name]",
    `${title} — program by @${program.coach_username ?? "coach"}`
  );
  params.set("payment_intent_data[application_fee_amount]", String(feeCents));
  params.set(
    "payment_intent_data[transfer_data][destination]",
    connectRow.stripe_account_id
  );
  params.set("payment_intent_data[description]", `Whisper program: ${title}`);
  params.set("metadata[kind]", "program-purchase");
  params.set("metadata[programId]", program.id);
  params.set("metadata[programTitle]", title.slice(0, 120));
  params.set("metadata[coachUserId]", program.coach_user_id);
  params.set("metadata[whisperUserId]", body.userId);
  if (body.email) params.set("customer_email", body.email);

  const session = await stripeRequest(env, "/checkout/sessions", params);
  if (!session.ok && isMissingAccountError(session)) {
    await clearStaleConnect(
      env,
      program.coach_user_id,
      connectRow.stripe_account_id
    );
    console.error("Program purchase blocked — stale payout account reset", {
      coachUserId: program.coach_user_id,
    });
    return json(
      {
        error: "coach_not_ready",
        stripeMessage: `@${program.coach_username ?? "the coach"}'s payout account needs to be reconnected for live payments (it was set up in test mode). It's been reset — once they reconnect payouts in Coach Studio, purchases will work.`,
      },
      409
    );
  }
  if (embedded) {
    if (!session.ok || typeof session.data.client_secret !== "string") {
      const err = session.data.error as { message?: string } | undefined;
      console.error("Program embedded checkout failed", {
        status: session.status,
        error: err?.message,
      });
      return json(
        { error: "stripe_error", stripeMessage: err?.message ?? null },
        502
      );
    }
    return json({
      clientSecret: session.data.client_secret,
      publishableKey: env.STRIPE_PUBLISHABLE_KEY ?? null,
    });
  }
  if (!session.ok || typeof session.data.url !== "string") {
    const err = session.data.error as { message?: string } | undefined;
    console.error("Program checkout failed", {
      status: session.status,
      error: err?.message,
    });
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  return json({ url: session.data.url });
}

/**
 * GET /coach/program-access?programId=... — whether the signed-in user can
 * open the full program. Owners (the coach) always can; clients can after a
 * one-time purchase. Also returns the price so lock screens can render it.
 */
async function handleProgramAccess(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  const url = new URL(request.url);
  const programId = url.searchParams.get("programId") ?? "";
  if (!programId) return json({ error: "missing_program" }, 400);

  const program = await getProgramRow(env, programId);
  if (!program) return json({ error: "program_not_found" }, 404);

  const priceCents = programPriceCents(program);
  if (program.coach_user_id === user.userId) {
    return json({ purchased: true, owner: true, priceCents: priceCents || null });
  }
  if (!priceCents) {
    // Free program — everyone the coach shares it with can open it.
    return json({ purchased: true, owner: false, priceCents: null });
  }
  const connectRow = await getFreshConnectRow(env, program.coach_user_id);
  const coachReady = Boolean(
    connectRow?.payouts_enabled || connectRow?.charges_enabled
  );
  if (!coachReady) {
    // Priced but the coach can't take payments yet — don't wall content.
    return json({ purchased: true, owner: false, priceCents, coachReady: false });
  }
  const purchased = await hasProgramPurchase(env, programId, user.userId);
  return json({ purchased, owner: false, priceCents, coachReady: true });
}

// ---------------------------------------------------------------------------
// WPP — Whisper Paid Partners: the ad-revenue share that pays creators.
// Ad impressions fund the pool; creators earn per 1k qualified views at
// their tier's RPM and cash out through the SAME Stripe payout rail as
// coaches. Qualified views land in whisper_wpp_views via the
// wpp_track_views RPC (deduped per viewer/post/day); this code only READS
// counts and moves money.
// ---------------------------------------------------------------------------

const WPP_RATE_TIERS = [
  { id: "elite", label: "Elite", minFollowers: 100_000, rpmCents: 220 },
  { id: "partner-plus", label: "Partner+", minFollowers: 10_000, rpmCents: 140 },
  { id: "partner", label: "Partner", minFollowers: 1_000, rpmCents: 90 },
] as const;

function wppTierFor(followers: number) {
  return WPP_RATE_TIERS.find((t) => followers >= t.minFollowers) ?? null;
}

/**
 * Manual WPP access — founder-granted testing/partner slots. Consulted only
 * when the follower count doesn't qualify on its own: first the
 * whisper_wpp_overrides table (durable, run supabase/wpp-overrides.sql),
 * then a baked-in founder allowlist so a grant works even before the
 * migration runs. Overrides give the TIER; views/pool math stays identical.
 */
const WPP_FOUNDER_OVERRIDES: Record<string, string> = {
  dyl: "partner",
};

async function wppOverrideTier(
  env: Env,
  userId: string
): Promise<(typeof WPP_RATE_TIERS)[number] | null> {
  const uid = encodeURIComponent(userId);
  const rows = await supabaseSelect(
    env,
    `/whisper_wpp_overrides?user_id=eq.${uid}&select=tier_id&limit=1`
  );
  const tierId = (rows?.[0] as { tier_id?: string } | undefined)?.tier_id;
  if (tierId) {
    const fromTable = WPP_RATE_TIERS.find((t) => t.id === tierId);
    if (fromTable) return fromTable;
  }
  const prof = await supabaseSelect(
    env,
    `/whisper_profiles?user_id=eq.${uid}&select=username&limit=1`
  );
  const username = (
    (prof?.[0] as { username?: string } | undefined)?.username ?? ""
  ).toLowerCase();
  const allowTier = WPP_FOUNDER_OVERRIDES[username];
  if (!allowTier) return null;
  return WPP_RATE_TIERS.find((t) => t.id === allowTier) ?? null;
}

/**
 * The creator pool's share of real ad revenue — the YouTube/TikTok model:
 * every month, 50% of actual ad spend (impressions × CPM) becomes the
 * creator pool. A creator's month = min(their views × tier RPM, their
 * view-share of the pool) — so payouts can NEVER exceed collected ad
 * revenue, and tier RPMs act as per-creator caps. Months finalize on the
 * 1st (UTC); only closed months are cashable.
 */
const WPP_POOL_SHARE = 0.5;

interface WppMonthRow {
  month: string;
  my_views: number;
  total_views: number;
  revenue_cents: number;
}

/** Shared ledger math for summary + cashout — revenue-pool based. */
async function wppLedger(env: Env, userId: string) {
  const uid = encodeURIComponent(userId);
  const [followers, monthRows, cashoutRows] = await Promise.all([
    supabaseCount(
      env,
      `/whisper_follows?followee_id=eq.${uid}&select=follower_id`
    ),
    supabaseRpc<WppMonthRow[]>(env, "wpp_creator_months", { p_user: userId }),
    supabaseSelect(
      env,
      `/whisper_wpp_cashouts?user_id=eq.${uid}&select=amount_cents,created_at&order=created_at.desc&limit=50`
    ),
  ]);
  const tier =
    wppTierFor(followers) ?? (await wppOverrideTier(env, userId));
  const rpmCents = tier?.rpmCents ?? 0;
  const rows = Array.isArray(monthRows) ? monthRows : [];
  const monthStart = new Date();
  monthStart.setUTCDate(1);
  monthStart.setUTCHours(0, 0, 0, 0);

  let closedEarnedCents = 0;
  let monthEstimatedCents = 0;
  let monthViews = 0;
  let allViews = 0;
  let poolMonthCents = 0;
  let monthRevenueCents = 0;
  for (const r of rows) {
    const myViews = Math.max(0, Number(r.my_views ?? 0));
    const totalViews = Math.max(0, Number(r.total_views ?? 0));
    const revenue = Math.max(0, Number(r.revenue_cents ?? 0));
    allViews += myViews;
    const pool = Math.floor(revenue * WPP_POOL_SHARE);
    const byRpm = Math.floor((myViews * rpmCents) / 1000);
    const byShare =
      totalViews > 0 ? Math.floor((pool * myViews) / totalViews) : 0;
    const earned = Math.min(byRpm, byShare);
    const rowMonth = new Date(r.month).getTime();
    if (Number.isFinite(rowMonth) && rowMonth >= monthStart.getTime()) {
      monthEstimatedCents = earned;
      monthViews = myViews;
      poolMonthCents = pool;
      monthRevenueCents = revenue;
    } else {
      closedEarnedCents += earned;
    }
  }

  const cashouts = (cashoutRows ?? []) as {
    amount_cents?: number;
    created_at?: string;
  }[];
  const cashedOutCents = cashouts.reduce(
    (s, r) => s + (r.amount_cents ?? 0),
    0
  );
  return {
    followers,
    monthViews,
    allViews,
    tier,
    rpmCents,
    // "Earned" = every closed month + the live month's running estimate.
    accruedCents: closedEarnedCents + monthEstimatedCents,
    monthEstimatedCents,
    poolMonthCents,
    monthRevenueCents,
    cashedOutCents,
    // Cashable = FINALIZED months only — protects the pool math.
    availableCents: Math.max(0, closedEarnedCents - cashedOutCents),
    cashouts,
  };
}

/** GET /wpp/summary — the signed-in creator's WPP standing. */
async function handleWppSummary(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const ledger = await wppLedger(env, user.userId);
  const row = await getFreshConnectRow(env, user.userId);
  // The next tier up (for the "X followers to go" motivator).
  const next = [...WPP_RATE_TIERS]
    .reverse()
    .find((t) => ledger.followers < t.minFollowers);
  return json({
    eligible: ledger.tier !== null,
    tierId: ledger.tier?.id ?? null,
    tierLabel: ledger.tier?.label ?? null,
    rpmCents: ledger.rpmCents,
    followers: ledger.followers,
    monthViews: ledger.monthViews,
    allTimeViews: ledger.allViews,
    accruedCents: ledger.accruedCents,
    monthEstimatedCents: ledger.monthEstimatedCents,
    poolMonthCents: ledger.poolMonthCents,
    monthRevenueCents: ledger.monthRevenueCents,
    cashedOutCents: ledger.cashedOutCents,
    availableCents: ledger.availableCents,
    connected: !!row,
    payoutsReady: row?.payouts_enabled === true,
    nextTierLabel: next?.label ?? null,
    nextTierFollowers: next?.minFollowers ?? null,
    cashouts: ledger.cashouts.slice(0, 12),
  });
}

/** POST /wpp/cashout — transfer the available WPP balance to the creator. */
async function handleWppCashout(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) {
    return json({ error: "billing_not_configured" }, 503);
  }
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const ledger = await wppLedger(env, user.userId);
  if (!ledger.tier) return json({ error: "not_eligible" }, 403);
  if (ledger.availableCents < 1000) {
    return json(
      { error: "below_minimum", availableCents: ledger.availableCents },
      400
    );
  }
  const row = await getFreshConnectRow(env, user.userId);
  if (!row) return json({ error: "not_connected" }, 404);
  if (!row.payouts_enabled) return json({ error: "payouts_not_ready" }, 400);

  const amount = ledger.availableCents;
  const params = new URLSearchParams();
  params.set("amount", String(amount));
  params.set("currency", "usd");
  params.set("destination", row.stripe_account_id);
  params.set("description", "WPP creator payout — Whisper Paid Partners");
  params.set("metadata[kind]", "wpp-payout");
  params.set("metadata[whisperUserId]", user.userId);
  const transfer = await stripeRequest(env, "/transfers", params);
  if (!transfer.ok) {
    if (isMissingAccountError(transfer)) {
      await clearStaleConnect(env, user.userId, row.stripe_account_id);
      return json({ error: "not_connected" }, 404);
    }
    const err = transfer.data.error as { message?: string } | undefined;
    console.error("WPP transfer failed", { error: err?.message });
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  const ins = await supabaseAdmin(env, "/whisper_wpp_cashouts", {
    method: "POST",
    body: {
      user_id: user.userId,
      amount_cents: amount,
      views_counted: ledger.allViews,
      rpm_cents: ledger.rpmCents,
    },
  });
  if (!ins.ok) console.error("WPP cashout ledger write failed");
  // Best-effort: push the funds onward to their bank right away.
  const payoutParams = new URLSearchParams();
  payoutParams.set("amount", String(amount));
  payoutParams.set("currency", "usd");
  const payout = await stripeRequest(
    env,
    "/payouts",
    payoutParams,
    row.stripe_account_id
  );
  return json({ ok: true, amountCents: amount, sentToBank: payout.ok });
}

// ---------------------------------------------------------------------------
// Live gifts — viewers buy prepaid gift credits and send gifts in live
// rooms; hosts keep 70% and cash out on the same Stripe rail as WPP and
// coach payouts. Wallet writes are service-role only, and every balance
// change is a compare-and-swap so concurrent spends can never double-
// deduct or go negative.
// ---------------------------------------------------------------------------

const LIVE_GIFT_CATALOG = [
  { id: "spark", label: "Spark", emoji: "✨", cents: 99 },
  { id: "rose", label: "Rose", emoji: "🌹", cents: 199 },
  { id: "flame", label: "Flame", emoji: "🔥", cents: 499 },
  { id: "ghost", label: "Ghost", emoji: "👻", cents: 999 },
  { id: "crown", label: "Crown", emoji: "👑", cents: 2499 },
  { id: "meteor", label: "Meteor", emoji: "☄️", cents: 9999 },
] as const;
const GIFT_HOST_SHARE_PERCENT = 70;
const GIFT_TOPUP_MIN_CENTS = 500; // $5
const GIFT_TOPUP_MAX_CENTS = 20_000; // $200 per top-up
const GIFT_CASHOUT_MIN_CENTS = 1_000; // $10 — same floor as WPP

/** Read a gift wallet balance. `null` = table missing (migration not run). */
async function giftWalletBalance(
  env: Env,
  userId: string
): Promise<number | null> {
  const rows = await supabaseSelect(
    env,
    `/whisper_gift_wallets?user_id=eq.${encodeURIComponent(
      userId
    )}&select=balance_cents&limit=1`
  );
  if (rows === null) return null;
  const row = rows[0] as { balance_cents?: number } | undefined;
  return typeof row?.balance_cents === "number" ? row.balance_cents : 0;
}

/** Ensure the wallet row exists (idempotent). */
async function ensureGiftWallet(env: Env, userId: string): Promise<void> {
  await supabaseAdmin(env, "/whisper_gift_wallets?on_conflict=user_id", {
    method: "POST",
    prefer: "resolution=ignore-duplicates",
    body: { user_id: userId, balance_cents: 0 },
  });
}

/**
 * Compare-and-swap a wallet balance. Returns true only when THIS update
 * applied (the row still held `fromCents`) — a concurrent spender's filter
 * matches zero rows, so a balance can never be deducted twice.
 */
async function giftWalletCas(
  env: Env,
  userId: string,
  fromCents: number,
  toCents: number
): Promise<boolean> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return false;
  const res = await fetch(
    `${SUPABASE_URL}/rest/v1/whisper_gift_wallets?user_id=eq.${encodeURIComponent(
      userId
    )}&balance_cents=eq.${fromCents}`,
    {
      method: "PATCH",
      headers: {
        apikey: key,
        Authorization: `Bearer ${key}`,
        "Content-Type": "application/json",
        Prefer: "return=representation",
      },
      body: JSON.stringify({
        balance_cents: toCents,
        updated_at: new Date().toISOString(),
      }),
    }
  );
  if (!res.ok) return false;
  const rows = (await res.json().catch(() => [])) as unknown[];
  return rows.length === 1;
}

/** Credit a wallet with CAS retries (webhook fulfillment). */
async function giftWalletCredit(
  env: Env,
  userId: string,
  amountCents: number
): Promise<boolean> {
  await ensureGiftWallet(env, userId);
  for (let attempt = 0; attempt < 5; attempt++) {
    const balance = await giftWalletBalance(env, userId);
    if (balance === null) return false;
    if (await giftWalletCas(env, userId, balance, balance + amountCents)) {
      return true;
    }
  }
  return false;
}

/** GET /gifts/wallet — balance + the server-truth catalog. */
async function handleGiftWallet(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const balance = await giftWalletBalance(env, user.userId);
  return json({
    ready: balance !== null,
    balanceCents: balance ?? 0,
    hostSharePercent: GIFT_HOST_SHARE_PERCENT,
    catalog: LIVE_GIFT_CATALOG,
  });
}

/** POST /gifts/topup — embedded checkout session for gift credits. */
async function handleGiftTopup(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY || !env.STRIPE_PUBLISHABLE_KEY) {
    return json({ error: "billing_not_configured" }, 503);
  }
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: { amountCents?: number; origin?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const amount = Math.round(Number(body.amountCents));
  if (
    !Number.isFinite(amount) ||
    amount < GIFT_TOPUP_MIN_CENTS ||
    amount > GIFT_TOPUP_MAX_CENTS
  ) {
    return json({ error: "invalid_amount" }, 400);
  }
  let origin: URL;
  try {
    origin = new URL(String(body.origin ?? "https://mydailywhisper.com"));
  } catch {
    origin = new URL("https://mydailywhisper.com");
  }
  const params = new URLSearchParams();
  params.set("mode", "payment");
  params.set("ui_mode", "embedded_page");
  params.set(
    "return_url",
    `${origin.origin}/billing/success?embedded=1&session_id={CHECKOUT_SESSION_ID}`
  );
  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", "usd");
  params.set("line_items[0][price_data][unit_amount]", String(amount));
  params.set(
    "line_items[0][price_data][product_data][name]",
    "Whisper gift credits"
  );
  params.set("metadata[kind]", "gift-credits");
  params.set("metadata[whisperUserId]", user.userId);
  const session = await stripeRequest(env, "/checkout/sessions", params);
  if (!session.ok || typeof session.data.client_secret !== "string") {
    const err = session.data.error as { message?: string } | undefined;
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  return json({
    clientSecret: session.data.client_secret,
    publishableKey: env.STRIPE_PUBLISHABLE_KEY,
  });
}

/** POST /gifts/send — spend prepaid credits on a live gift. */
async function handleGiftSend(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: { roomId?: string; giftId?: string; qty?: number };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const roomId = String(body.roomId ?? "");
  if (!/^[0-9a-f-]{36}$/i.test(roomId)) {
    return json({ error: "room_not_found" }, 404);
  }
  const gift = LIVE_GIFT_CATALOG.find((g) => g.id === body.giftId);
  if (!gift) return json({ error: "gift_not_found" }, 404);
  const qty = Math.round(Number(body.qty ?? 1));
  if (!Number.isFinite(qty) || qty < 1 || qty > 20) {
    return json({ error: "invalid_qty" }, 400);
  }

  const rooms = await supabaseSelect(
    env,
    `/whisper_live_rooms?id=eq.${encodeURIComponent(
      roomId
    )}&select=host_id,is_live&limit=1`
  );
  const room = rooms?.[0] as
    | { host_id?: string; is_live?: boolean }
    | undefined;
  if (!room?.host_id) return json({ error: "room_not_found" }, 404);
  if (room.is_live !== true) return json({ error: "room_not_live" }, 400);
  if (room.host_id.toLowerCase() === user.userId.toLowerCase()) {
    return json({ error: "cant_gift_yourself" }, 400);
  }

  const total = gift.cents * qty;
  await ensureGiftWallet(env, user.userId);
  let newBalance = -1;
  for (let attempt = 0; attempt < 3; attempt++) {
    const balance = await giftWalletBalance(env, user.userId);
    if (balance === null) return json({ error: "gifts_not_ready" }, 503);
    if (balance < total) {
      return json(
        { error: "insufficient_gift_balance", balanceCents: balance },
        400
      );
    }
    if (await giftWalletCas(env, user.userId, balance, balance - total)) {
      newBalance = balance - total;
      break;
    }
  }
  if (newBalance < 0) return json({ error: "wallet_conflict" }, 409);

  const profileRows = await supabaseSelect(
    env,
    `/whisper_profiles?user_id=eq.${encodeURIComponent(
      user.userId
    )}&select=username&limit=1`
  );
  const senderUsername =
    (profileRows?.[0] as { username?: string } | undefined)?.username ?? null;

  const net = Math.floor((total * GIFT_HOST_SHARE_PERCENT) / 100);
  const ins = await supabaseAdmin(env, "/whisper_live_gifts", {
    method: "POST",
    body: {
      room_id: roomId,
      host_id: room.host_id,
      sender_id: user.userId,
      sender_username: senderUsername,
      gift_id: gift.id,
      gift_label: gift.label,
      gift_emoji: gift.emoji,
      qty,
      amount_cents: total,
      net_cents: net,
    },
  });
  if (!ins.ok) {
    // Refund the deduction — the gift never landed.
    await giftWalletCredit(env, user.userId, total);
    return json({ error: "gifts_not_ready" }, 503);
  }
  return json({ ok: true, balanceCents: newBalance, netCents: net });
}

/** Shared host gift-earnings math for the earnings + cashout endpoints. */
async function giftEarningsLedger(env: Env, userId: string) {
  const uid = encodeURIComponent(userId);
  const [giftRows, cashoutRows] = await Promise.all([
    supabaseSelect(
      env,
      `/whisper_live_gifts?host_id=eq.${uid}&select=net_cents,amount_cents,gift_emoji,gift_label,qty,sender_username,created_at&order=created_at.desc&limit=1000`
    ),
    supabaseSelect(
      env,
      `/whisper_gift_cashouts?user_id=eq.${uid}&select=amount_cents&limit=200`
    ),
  ]);
  const gifts = (giftRows ?? []) as {
    net_cents: number;
    amount_cents: number;
    gift_emoji: string;
    gift_label: string;
    qty: number;
    sender_username: string | null;
    created_at: string;
  }[];
  const allTimeCents = gifts.reduce((s, g) => s + (g.net_cents ?? 0), 0);
  const cashedOutCents = ((cashoutRows ?? []) as { amount_cents: number }[])
    .reduce((s, c) => s + (c.amount_cents ?? 0), 0);
  return {
    ready: giftRows !== null,
    allTimeCents,
    cashedOutCents,
    availableCents: Math.max(0, allTimeCents - cashedOutCents),
    recent: gifts.slice(0, 12),
  };
}

/** GET /gifts/earnings — host totals + recent gifts. */
async function handleGiftEarnings(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const ledger = await giftEarningsLedger(env, user.userId);
  return json(ledger);
}

/** POST /gifts/cashout — transfer the available gift balance to the host. */
async function handleGiftCashout(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) {
    return json({ error: "billing_not_configured" }, 503);
  }
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const ledger = await giftEarningsLedger(env, user.userId);
  if (!ledger.ready) return json({ error: "gifts_not_ready" }, 503);
  if (ledger.availableCents < GIFT_CASHOUT_MIN_CENTS) {
    return json(
      { error: "below_minimum", availableCents: ledger.availableCents },
      400
    );
  }
  const row = await getFreshConnectRow(env, user.userId);
  if (!row) return json({ error: "not_connected" }, 404);
  if (!row.payouts_enabled) return json({ error: "payouts_not_ready" }, 400);

  const amount = ledger.availableCents;
  const params = new URLSearchParams();
  params.set("amount", String(amount));
  params.set("currency", "usd");
  params.set("destination", row.stripe_account_id);
  params.set("description", "Live gifts payout — Whisper");
  params.set("metadata[kind]", "gift-payout");
  params.set("metadata[whisperUserId]", user.userId);
  const transfer = await stripeRequest(env, "/transfers", params);
  if (!transfer.ok) {
    if (isMissingAccountError(transfer)) {
      await clearStaleConnect(env, user.userId, row.stripe_account_id);
      return json({ error: "not_connected" }, 404);
    }
    const err = transfer.data.error as { message?: string } | undefined;
    console.error("Gift transfer failed", { error: err?.message });
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  const ins = await supabaseAdmin(env, "/whisper_gift_cashouts", {
    method: "POST",
    body: { user_id: user.userId, amount_cents: amount },
  });
  if (!ins.ok) console.error("Gift cashout ledger write failed");
  // Best-effort: push the funds onward to their bank right away.
  const payoutParams = new URLSearchParams();
  payoutParams.set("amount", String(amount));
  payoutParams.set("currency", "usd");
  const payout = await stripeRequest(
    env,
    "/payouts",
    payoutParams,
    row.stripe_account_id
  );
  return json({ ok: true, amountCents: amount, sentToBank: payout.ok });
}

// ---------------------------------------------------------------------------
// Whisper Ads credits — businesses prepay ad delivery; impressions bill at
// the campaign's CPM and serving stops when the wallet is empty. Ad spend is
// the revenue that funds WPP creator payouts (50% pool share).
// ---------------------------------------------------------------------------

const AD_TOPUP_MIN_CENTS = 1_000; // $10
const AD_TOPUP_MAX_CENTS = 100_000; // $1,000 per top-up

/** POST /business/ads/topup — embedded checkout session for ad credits. */
async function handleAdsTopup(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY || !env.STRIPE_PUBLISHABLE_KEY) {
    return json({ error: "billing_not_configured" }, 503);
  }
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: { amountCents?: number; origin?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const amount = Math.round(Number(body.amountCents));
  if (
    !Number.isFinite(amount) ||
    amount < AD_TOPUP_MIN_CENTS ||
    amount > AD_TOPUP_MAX_CENTS
  ) {
    return json({ error: "invalid_amount" }, 400);
  }
  let origin: URL;
  try {
    origin = new URL(String(body.origin ?? "https://mydailywhisper.com"));
  } catch {
    origin = new URL("https://mydailywhisper.com");
  }
  const params = new URLSearchParams();
  params.set("mode", "payment");
  params.set("ui_mode", "embedded_page");
  params.set(
    "return_url",
    `${origin.origin}/billing/success?embedded=1&session_id={CHECKOUT_SESSION_ID}`
  );
  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", "usd");
  params.set("line_items[0][price_data][unit_amount]", String(amount));
  params.set(
    "line_items[0][price_data][product_data][name]",
    "Whisper Ads credit"
  );
  params.set("metadata[kind]", "ad-credits");
  params.set("metadata[whisperUserId]", user.userId);
  const session = await stripeRequest(env, "/checkout/sessions", params);
  if (!session.ok || typeof session.data.client_secret !== "string") {
    const err = session.data.error as { message?: string } | undefined;
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  return json({
    clientSecret: session.data.client_secret,
    publishableKey: env.STRIPE_PUBLISHABLE_KEY,
  });
}

// ---------------------------------------------------------------------------
// Ads auto-recharge — an optional saved card tops the wallet up whenever it
// dips under a threshold. Settings live in whisper_ad_autorecharge (service
// role writes only; owners read their own row). Charges are off-session
// PaymentIntents deduped into whisper_ad_topups by payment-intent id, with
// a 6-hour cooldown so a burst of checks can never double-charge.
// ---------------------------------------------------------------------------

const AR_THRESHOLD_MIN_CENTS = 100; // $1
const AR_THRESHOLD_MAX_CENTS = 10_000; // $100
const AR_AMOUNT_MIN_CENTS = 1_000; // $10
const AR_AMOUNT_MAX_CENTS = 100_000; // $1,000
const AR_COOLDOWN_MS = 6 * 60 * 60 * 1000;

interface AutoRechargeRow {
  user_id: string;
  enabled: boolean;
  threshold_cents: number;
  amount_cents: number;
  stripe_customer_id: string | null;
  stripe_pm_id: string | null;
  pm_brand: string | null;
  pm_last4: string | null;
  pending_session_id: string | null;
  last_charged_at: string | null;
}

async function getAutoRechargeRow(
  env: Env,
  userId: string
): Promise<AutoRechargeRow | null> {
  const rows = await supabaseSelect(
    env,
    `/whisper_ad_autorecharge?user_id=eq.${encodeURIComponent(userId)}&select=*&limit=1`
  );
  return ((rows ?? [])[0] as AutoRechargeRow | undefined) ?? null;
}

function autoRechargeSettings(row: AutoRechargeRow | null): unknown {
  if (!row) return null;
  return {
    enabled: !!row.enabled,
    thresholdCents: row.threshold_cents,
    amountCents: row.amount_cents,
    cardBrand: row.pm_brand,
    cardLast4: row.pm_last4,
    hasCard: !!row.stripe_pm_id,
    lastChargedAt: row.last_charged_at,
  };
}

/** GET /business/wallet/autorecharge — the caller's sanitized settings. */
async function handleAutoRechargeGet(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const row = await getAutoRechargeRow(env, user.userId);
  return json({ settings: autoRechargeSettings(row) });
}

/** POST /business/wallet/autorecharge/start — embedded setup-mode checkout
 * to save a card. The session id is remembered server-side so enabling
 * after completion never needs the client to know it. */
async function handleAutoRechargeStart(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY || !env.STRIPE_PUBLISHABLE_KEY) {
    return json({ error: "billing_not_configured" }, 503);
  }
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: { origin?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    body = {};
  }
  let origin: URL;
  try {
    origin = new URL(String(body.origin ?? SITE_URL));
  } catch {
    origin = new URL(SITE_URL);
  }

  const existing = await getAutoRechargeRow(env, user.userId);
  let customerId = existing?.stripe_customer_id ?? null;
  if (!customerId) {
    const customerParams = new URLSearchParams();
    if (user.email) customerParams.set("email", user.email);
    customerParams.set("metadata[whisperUserId]", user.userId);
    const customer = await stripeRequest(env, "/customers", customerParams);
    if (!customer.ok || typeof customer.data.id !== "string") {
      const err = customer.data.error as { message?: string } | undefined;
      return json(
        { error: "stripe_error", stripeMessage: err?.message ?? null },
        502
      );
    }
    customerId = customer.data.id;
  }

  const params = new URLSearchParams();
  params.set("mode", "setup");
  params.set("ui_mode", "embedded_page");
  params.set("customer", customerId);
  params.set(
    "return_url",
    `${origin.origin}/billing/success?embedded=1&session_id={CHECKOUT_SESSION_ID}`
  );
  params.set("metadata[kind]", "ad-autorecharge-setup");
  params.set("metadata[whisperUserId]", user.userId);
  const session = await stripeRequest(env, "/checkout/sessions", params);
  if (
    !session.ok ||
    typeof session.data.client_secret !== "string" ||
    typeof session.data.id !== "string"
  ) {
    const err = session.data.error as { message?: string } | undefined;
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }

  await supabaseAdmin(env, "/whisper_ad_autorecharge?on_conflict=user_id", {
    method: "POST",
    prefer: "resolution=merge-duplicates",
    body: {
      user_id: user.userId,
      stripe_customer_id: customerId,
      pending_session_id: session.data.id,
      updated_at: new Date().toISOString(),
    },
  });

  return json({
    clientSecret: session.data.client_secret,
    publishableKey: env.STRIPE_PUBLISHABLE_KEY,
  });
}

/** POST /business/wallet/autorecharge/enable — resolve the saved card from
 * the pending setup session (when present) and switch auto-recharge on. */
async function handleAutoRechargeEnable(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) {
    return json({ error: "billing_not_configured" }, 503);
  }
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: { thresholdCents?: number; amountCents?: number };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    body = {};
  }
  const threshold = Math.min(
    AR_THRESHOLD_MAX_CENTS,
    Math.max(AR_THRESHOLD_MIN_CENTS, Math.round(Number(body.thresholdCents) || 500))
  );
  const amount = Math.min(
    AR_AMOUNT_MAX_CENTS,
    Math.max(AR_AMOUNT_MIN_CENTS, Math.round(Number(body.amountCents) || 2500))
  );

  const row = await getAutoRechargeRow(env, user.userId);
  let pmId = row?.stripe_pm_id ?? null;
  let pmBrand = row?.pm_brand ?? null;
  let pmLast4 = row?.pm_last4 ?? null;

  if (row?.pending_session_id) {
    const session = await stripeRequest(
      env,
      `/checkout/sessions/${encodeURIComponent(row.pending_session_id)}?expand[]=setup_intent`
    );
    if (session.ok) {
      const si = session.data.setup_intent as
        | { payment_method?: string | null; status?: string }
        | string
        | null;
      const pmFromSession =
        si && typeof si === "object" && typeof si.payment_method === "string"
          ? si.payment_method
          : null;
      if (pmFromSession) {
        pmId = pmFromSession;
        const pm = await stripeRequest(
          env,
          `/payment_methods/${encodeURIComponent(pmFromSession)}`
        );
        if (pm.ok) {
          const card = pm.data.card as
            | { brand?: string; last4?: string }
            | undefined;
          pmBrand = card?.brand ?? null;
          pmLast4 = card?.last4 ?? null;
        }
      }
    }
  }

  if (!pmId) return json({ error: "no_card" }, 400);

  await supabaseAdmin(env, "/whisper_ad_autorecharge?on_conflict=user_id", {
    method: "POST",
    prefer: "resolution=merge-duplicates",
    body: {
      user_id: user.userId,
      enabled: true,
      threshold_cents: threshold,
      amount_cents: amount,
      stripe_pm_id: pmId,
      pm_brand: pmBrand,
      pm_last4: pmLast4,
      pending_session_id: null,
      updated_at: new Date().toISOString(),
    },
  });
  return json({ ok: true });
}

/** POST /business/wallet/autorecharge/disable */
async function handleAutoRechargeDisable(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  await supabaseAdmin(
    env,
    `/whisper_ad_autorecharge?user_id=eq.${encodeURIComponent(user.userId)}`,
    {
      method: "PATCH",
      body: { enabled: false, updated_at: new Date().toISOString() },
    }
  );
  return json({ ok: true });
}

/** POST /business/wallet/autorecharge/check — charge the saved card
 * off-session when the wallet sits under the threshold (6h cooldown,
 * deduped by payment-intent id). Called whenever the suite opens. */
async function handleAutoRechargeCheck(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) {
    return json({ charged: false, reason: "billing_not_configured" });
  }
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const row = await getAutoRechargeRow(env, user.userId);
  if (!row?.enabled || !row.stripe_pm_id || !row.stripe_customer_id) {
    return json({ charged: false, reason: "disabled" });
  }
  if (
    row.last_charged_at &&
    Date.now() - new Date(row.last_charged_at).getTime() < AR_COOLDOWN_MS
  ) {
    return json({ charged: false, reason: "cooldown" });
  }
  const balance = await supabaseRpc<number>(
    env,
    "business_wallet_balance_cents",
    { p_user: user.userId }
  );
  if (typeof balance !== "number") {
    return json({ charged: false, reason: "balance_unavailable" });
  }
  if (balance >= row.threshold_cents) {
    return json({ charged: false, reason: "above_threshold" });
  }

  const params = new URLSearchParams();
  params.set("amount", String(row.amount_cents));
  params.set("currency", "usd");
  params.set("customer", row.stripe_customer_id);
  params.set("payment_method", row.stripe_pm_id);
  params.set("off_session", "true");
  params.set("confirm", "true");
  params.set("description", "Whisper Ads auto-recharge");
  params.set("metadata[kind]", "ad-credits-auto");
  params.set("metadata[whisperUserId]", user.userId);
  const pi = await stripeRequest(env, "/payment_intents", params);
  if (!pi.ok || pi.data.status !== "succeeded" || typeof pi.data.id !== "string") {
    const err = pi.data.error as { message?: string } | undefined;
    console.error("Auto-recharge charge failed", { error: err?.message });
    return json({
      charged: false,
      reason: "charge_failed",
      stripeMessage: err?.message ?? null,
    });
  }

  await supabaseAdmin(env, "/whisper_ad_topups?on_conflict=stripe_session_id", {
    method: "POST",
    prefer: "resolution=ignore-duplicates",
    body: {
      user_id: user.userId,
      amount_cents: row.amount_cents,
      source: "purchase",
      stripe_session_id: pi.data.id,
      created_at: new Date().toISOString(),
    },
  });
  await supabaseAdmin(
    env,
    `/whisper_ad_autorecharge?user_id=eq.${encodeURIComponent(user.userId)}`,
    {
      method: "PATCH",
      body: {
        last_charged_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
    }
  );
  await recordReceipt(env, {
    userId: user.userId,
    email: user.email,
    kind: "ad-credits",
    description: "Whisper Ads auto-recharge — wallet top-up",
    amountCents: row.amount_cents,
    sessionId: pi.data.id,
    paymentIntent: pi.data.id,
  });
  console.log("Auto-recharge charged", { amount: row.amount_cents });
  return json({ charged: true, amountCents: row.amount_cents });
}

/** GET /admin/applications — pending + recent rows for all three queues. */
async function handleAdminApplicationsList(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  const roles: BadgeRole[] = ["coach", "athlete", "verified"];
  const out: Record<string, { pending: unknown[]; recent: unknown[] }> = {};
  await Promise.all(
    roles.map(async (role) => {
      const table = BADGE_APPLICATION_TABLE[role];
      const [pending, recent] = await Promise.all([
        supabaseSelect(
          env,
          `/${table}?status=eq.pending&select=*&order=created_at.desc&limit=100`
        ),
        supabaseSelect(
          env,
          `/${table}?status=in.(approved,denied)&select=*&order=created_at.desc&limit=20`
        ),
      ]);
      out[role] = { pending: pending ?? [], recent: recent ?? [] };
    })
  );
  return json(out);
}

interface DecideBody {
  role?: string;
  id?: string;
  decision?: string;
}

/**
 * POST /admin/applications/decide — approve or deny one application.
 * Approving ONLY stamps the row and emails the activation/payment link;
 * the role perks stay off until the Stripe payment confirms (webhook or
 * success-page fulfillment flips the flag). Denying stamps the row and
 * force-clears any lingering perk flags.
 */
async function handleAdminApplicationDecide(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  let body: DecideBody;
  try {
    body = (await request.json()) as DecideBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const role =
    body.role === "coach" || body.role === "athlete" || body.role === "verified"
      ? body.role
      : null;
  const decision =
    body.decision === "approved" || body.decision === "denied"
      ? body.decision
      : null;
  const id = (body.id ?? "").trim();
  if (!role || !decision || !id) return json({ error: "invalid_body" }, 400);

  const table = BADGE_APPLICATION_TABLE[role];
  const rows = await supabaseSelect(
    env,
    `/${table}?id=eq.${encodeURIComponent(id)}&select=id,user_id,email&limit=1`
  );
  const row = (rows?.[0] ?? null) as {
    id?: string;
    user_id?: string | null;
    email?: string | null;
  } | null;
  if (!row?.id) return json({ error: "application_not_found" }, 404);

  const updated = await supabaseAdmin(
    env,
    `/${table}?id=eq.${encodeURIComponent(id)}`,
    { method: "PATCH", body: { status: decision } }
  );
  if (!updated.ok) return json({ error: "update_failed" }, 502);

  if (decision === "denied" && row.user_id) {
    // Perks must never linger on a denied account.
    const flag = BADGE_PROFILE_FLAG[role];
    const uid = encodeURIComponent(row.user_id);
    await supabaseAdmin(env, `/profiles?id=eq.${uid}`, {
      method: "PATCH",
      body: { [flag]: false },
    });
    if (role !== "verified") {
      await supabaseAdmin(env, `/whisper_profiles?user_id=eq.${uid}`, {
        method: "PATCH",
        body: { [flag]: false },
      });
    }
  }

  let emailSent = false;
  if (decision === "approved") {
    let email = (row.email ?? "").trim();
    if (!email.includes("@") && row.user_id) {
      email = (await authUserEmail(env, row.user_id)) ?? "";
    }
    if (email.includes("@")) {
      console.log("Sending badge approval email (admin decide)", { role });
      const mail = badgeApprovedEmail(role);
      await sendEmail(env, email, mail.subject, mail.html);
      emailSent = true;
    } else {
      console.error("Approved application has no reachable email", { role, id });
    }
  }

  return json({ ok: true, decision, emailSent });
}

// ---------------------------------------------------------------------------
// Admin team management — powers the "Team" tab on /admin/applications.
// Moderators can view the roster; only admins and the owner can change it.
// Writes go to whisper_admins (a DB trigger mirrors the profiles flags), and
// the backend also patches profiles directly as a belt-and-suspenders sync.
// ---------------------------------------------------------------------------

interface TeamMemberRow {
  id?: string;
  user_id?: string;
  username?: string | null;
  email?: string | null;
  role?: string;
  created_at?: string | null;
}

/**
 * Mirror a whisper_admins role (or removal) onto the profiles flags.
 * Returns true on success, false on failure so callers can surface a real
 * error instead of silently reporting success when the flags never flipped.
 */
async function syncAdminProfileFlags(
  env: Env,
  userId: string,
  role: AdminRole | null
): Promise<boolean> {
  const res = await supabaseAdmin(
    env,
    `/profiles?id=eq.${encodeURIComponent(userId)}`,
    {
      method: "PATCH",
      body: {
        is_owner: role === "owner",
        is_admin: role === "admin",
        is_moderator: role === "moderator",
      },
    }
  );
  return res.ok;
}

/** Find a Supabase auth user id by email (pages through the admin API). */
async function findAuthUserByEmail(
  env: Env,
  email: string
): Promise<{ id: string; email: string } | null> {
  const key = env.SUPABASE_SERVICE_ROLE_KEY;
  if (!key) return null;
  const target = email.toLowerCase();
  const perPage = 200;
  for (let page = 1; page <= 50; page++) {
    const res = await fetch(
      `${SUPABASE_URL}/auth/v1/admin/users?page=${page}&per_page=${perPage}`,
      { headers: { apikey: key, Authorization: `Bearer ${key}` } }
    );
    if (!res.ok) return null;
    const data = (await res.json()) as {
      users?: { id?: string; email?: string }[];
    };
    const users = data.users ?? [];
    const hit = users.find((u) => (u.email ?? "").toLowerCase() === target);
    if (hit?.id) return { id: hit.id, email: hit.email ?? email };
    if (users.length < perPage) break;
  }
  return null;
}

/** GET /admin/team — the roster plus the caller's own role. */
async function handleAdminTeamList(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  const rows = await supabaseSelect(
    env,
    "/whisper_admins?select=id,user_id,username,email,role,created_at&order=created_at.asc&limit=200"
  );
  return json({
    members: (rows ?? []) as TeamMemberRow[],
    callerRole: admin.role,
    callerUserId: admin.userId,
  });
}

interface TeamUpsertBody {
  identifier?: string;
  role?: string;
}

/**
 * POST /admin/team/upsert — add or re-role a team member by @username or
 * email. Only owner/admin may call; only the owner can grant/change owner.
 */
async function handleAdminTeamUpsert(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  if (admin.role === "moderator") return json({ error: "forbidden" }, 403);

  let body: TeamUpsertBody;
  try {
    body = (await request.json()) as TeamUpsertBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const role =
    body.role === "owner" || body.role === "admin" || body.role === "moderator"
      ? body.role
      : null;
  const identifier = (body.identifier ?? "").trim().replace(/^@/, "");
  if (!role || !identifier) return json({ error: "invalid_body" }, 400);
  if (role === "owner" && admin.role !== "owner") {
    return json({ error: "owner_only" }, 403);
  }

  // Resolve the target user: email first, then profiles username.
  let userId: string | null = null;
  let username: string | null = null;
  let email: string | null = null;
  if (identifier.includes("@")) {
    const hit = await findAuthUserByEmail(env, identifier);
    if (hit) {
      userId = hit.id;
      email = hit.email;
    }
  } else {
    const rows = await supabaseSelect(
      env,
      `/profiles?username=ilike.${encodeURIComponent(
        identifier
      )}&select=id,username&limit=1`
    );
    const p = rows?.[0] as { id?: string; username?: string } | undefined;
    if (p?.id) {
      userId = p.id;
      username = p.username ?? identifier;
    }
  }
  if (!userId) return json({ error: "user_not_found" }, 404);

  const upserted = await supabaseAdmin(
    env,
    "/whisper_admins?on_conflict=user_id",
    {
      method: "POST",
      prefer: "resolution=merge-duplicates",
      body: { user_id: userId, username, email, role },
    }
  );
  if (!upserted.ok) return json({ error: "update_failed" }, 502);

  // Mirror the role onto the profiles flags. If the promotee has no
  // `profiles` row yet (auth user exists but the row wasn't seeded) the
  // PATCH silently affects 0 rows — surface that as a real error so the
  // caller knows the promotion didn't fully take, instead of returning
  // `{ ok: true }` while `profiles.is_moderator` stays false.
  const synced = await syncAdminProfileFlags(env, userId, role);
  if (!synced) {
    console.log("Admin team upsert — profile sync failed", {
      role,
      by: admin.role,
      userId,
    });
    return json({ error: "sync_failed" }, 502);
  }
  console.log("Admin team upsert", { role, by: admin.role });
  return json({ ok: true, userId, role });
}

interface TeamRemoveBody {
  userId?: string;
}

/** POST /admin/team/remove — revoke a member. Owners can't be removed here. */
async function handleAdminTeamRemove(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  if (admin.role === "moderator") return json({ error: "forbidden" }, 403);

  let body: TeamRemoveBody;
  try {
    body = (await request.json()) as TeamRemoveBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const target = (body.userId ?? "").trim();
  if (!target) return json({ error: "invalid_body" }, 400);
  if (target === admin.userId) return json({ error: "cannot_remove_self" }, 400);

  const rows = await supabaseSelect(
    env,
    `/whisper_admins?user_id=eq.${encodeURIComponent(target)}&select=role&limit=1`
  );
  const targetRole = (rows?.[0] as { role?: string } | undefined)?.role;
  if (targetRole === "owner" && admin.role !== "owner") {
    return json({ error: "owner_only" }, 403);
  }

  const removed = await supabaseAdmin(
    env,
    `/whisper_admins?user_id=eq.${encodeURIComponent(target)}`,
    { method: "DELETE" }
  );
  if (!removed.ok) return json({ error: "update_failed" }, 502);

  await syncAdminProfileFlags(env, target, null);
  console.log("Admin team member removed", { by: admin.role });
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// Featured profiles — admin-curated spotlight cards (the "Hudson" template)
// shown on the public Coaches page and the Athlete/Creator role pages.
// Public pages read published rows directly from Supabase with the anon key;
// these endpoints handle the admin side (full list + writes).
// ---------------------------------------------------------------------------

type FeaturedKind = "coach" | "athlete" | "creator" | "recruiter";

interface FeaturedTestimonial {
  quote?: string;
  name?: string;
  result?: string;
}

interface FeaturedUpsertBody {
  id?: string;
  kind?: string;
  name?: string;
  username?: string | null;
  user_id?: string | null;
  photo_url?: string;
  tier?: number | null;
  discipline?: string | null;
  age?: string | null;
  chips?: string[];
  paragraphs?: string[];
  highlights?: string[];
  testimonials?: FeaturedTestimonial[];
  cta_label?: string | null;
  cta_url?: string | null;
  action_buttons?: FeaturedActionButtonInput[];
  sort_order?: number;
  published?: boolean;
}

interface FeaturedActionButtonInput {
  label?: string;
  type?: string;
  href?: string;
}

const FEATURED_COLUMNS =
  "id,kind,name,username,user_id,photo_url,tier,discipline,age,chips,paragraphs,highlights,testimonials,cta_label,cta_url,action_buttons,sort_order,published,created_at,updated_at";

/** GET /admin/featured — every row (drafts included) for the admin editor. */
async function handleAdminFeaturedList(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  const rows = await supabaseSelect(
    env,
    `/whisper_featured_profiles?select=${FEATURED_COLUMNS}&order=kind.asc,sort_order.asc,created_at.asc&limit=200`
  );
  if (rows === null) return json({ error: "load_failed" }, 502);
  return json({ profiles: rows });
}

const cleanStrings = (values: unknown): string[] =>
  Array.isArray(values)
    ? values
        .map((v) => String(v ?? "").trim())
        .filter((v) => v.length > 0)
        .slice(0, 12)
    : [];

/** POST /admin/featured/upsert — create or update one featured profile. */
async function handleAdminFeaturedUpsert(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  let body: FeaturedUpsertBody;
  try {
    body = (await request.json()) as FeaturedUpsertBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const kind: FeaturedKind | null =
    body.kind === "coach" ||
    body.kind === "athlete" ||
    body.kind === "creator" ||
    body.kind === "recruiter"
      ? body.kind
      : null;
  const name = (body.name ?? "").trim();
  if (!kind || !name) return json({ error: "invalid_body" }, 400);

  // Resolve the linked account by username (optional).
  const username = (body.username ?? "").trim().replace(/^@/, "") || null;
  let linkedUserId: string | null = null;
  if (username) {
    const rows = await supabaseSelect(
      env,
      `/profiles?username=ilike.${encodeURIComponent(username)}&select=id,username&limit=1`
    );
    const p = rows?.[0] as { id?: string } | undefined;
    linkedUserId = p?.id ?? null;
  }

  const tier =
    typeof body.tier === "number" && body.tier >= 1 && body.tier <= 3
      ? Math.round(body.tier)
      : null;

  const testimonials = Array.isArray(body.testimonials)
    ? body.testimonials
        .map((t) => ({
          quote: String(t?.quote ?? "").trim(),
          name: String(t?.name ?? "").trim(),
          result: String(t?.result ?? "").trim(),
        }))
        .filter((t) => t.quote.length > 0)
        .slice(0, 6)
    : [];

  // Typed CTA buttons — up to 3, validated against the allowed types so a
  // bad payload can't smuggle arbitrary mailto/external schemes through.
  const validActionTypes = new Set(["profile", "link", "email", "calendar"]);
  const actionButtons = Array.isArray(body.action_buttons)
    ? body.action_buttons
        .map((b) => ({
          label: String(b?.label ?? "").trim(),
          type: validActionTypes.has(String(b?.type))
            ? String(b?.type)
            : "profile",
          href: String(b?.href ?? "").trim(),
        }))
        .filter((b) => b.label.length > 0)
        .slice(0, 3)
    : [];

  // Legacy cta_label/cta_url still drive the button label fallback in the
  // public normalizer when action_buttons is empty, so keep them in sync.
  const ctaLabel = (body.cta_label ?? "").trim() || null;
  const ctaUrl = (body.cta_url ?? "").trim() || null;

  const id =
    (body.id ?? "").trim() ||
    (globalThis.crypto?.randomUUID ? crypto.randomUUID() : `${Date.now()}`);

  const row = {
    id,
    kind,
    name,
    username,
    user_id: linkedUserId,
    photo_url: (body.photo_url ?? "").trim(),
    tier,
    discipline: (body.discipline ?? "").trim() || null,
    age: (body.age ?? "").trim() || null,
    chips: cleanStrings(body.chips),
    paragraphs: cleanStrings(body.paragraphs),
    highlights: cleanStrings(body.highlights),
    testimonials,
    cta_label: ctaLabel,
    cta_url: ctaUrl,
    action_buttons: actionButtons,
    sort_order:
      typeof body.sort_order === "number" ? Math.round(body.sort_order) : 0,
    published: body.published !== false,
    updated_at: new Date().toISOString(),
  };

  const upserted = await supabaseAdmin(
    env,
    "/whisper_featured_profiles?on_conflict=id",
    {
      method: "POST",
      prefer: "resolution=merge-duplicates",
      body: row,
    }
  );
  if (!upserted.ok) return json({ error: "save_failed" }, 502);

  console.log("Featured profile saved", { kind, by: admin.role });
  return json({ ok: true, id, username, userId: linkedUserId });
}

interface FeaturedDeleteBody {
  id?: string;
}

/** POST /admin/featured/delete — remove one featured profile. */
async function handleAdminFeaturedDelete(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  let body: FeaturedDeleteBody;
  try {
    body = (await request.json()) as FeaturedDeleteBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const id = (body.id ?? "").trim();
  if (!id) return json({ error: "invalid_body" }, 400);

  const removed = await supabaseAdmin(
    env,
    `/whisper_featured_profiles?id=eq.${encodeURIComponent(id)}`,
    { method: "DELETE" }
  );
  if (!removed.ok) return json({ error: "delete_failed" }, 502);

  console.log("Featured profile deleted", { by: admin.role });
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// Articles — admin-written posts rendered on the public site. Reads happen
// straight from Supabase with the anon key (RLS: published only); writes go
// through here with the service role.
// ---------------------------------------------------------------------------

interface ArticleUpsertBody {
  id?: string;
  slug?: string;
  title?: string;
  excerpt?: string;
  cover_url?: string;
  category?: string;
  author_name?: string;
  paragraphs?: string[];
  published?: boolean;
  published_at?: string;
  /** Optional link to a Featured Film — the article renders the film's trailer (or clipped section). */
  film_id?: string;
  /** For clipped articles: the spot in the film the article is about. */
  clip_time_seconds?: number;
}

const ARTICLE_COLUMNS =
  "id,slug,title,excerpt,cover_url,category,author_name,author_username,author_user_id,paragraphs,published,published_at,created_at,updated_at,film_id,clip_time_seconds";

const slugify = (value: string): string =>
  value
    .toLowerCase()
    .replace(/[^a-z0-9\s-]/g, "")
    .trim()
    .replace(/[\s-]+/g, "-")
    .slice(0, 80);

/** GET /admin/articles — every article including drafts. */
async function handleAdminArticlesList(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  const rows = await supabaseSelect(
    env,
    `/whisper_articles?select=${ARTICLE_COLUMNS}&order=published_at.desc&limit=200`
  );
  if (rows === null) return json({ error: "load_failed" }, 502);
  return json({ articles: rows });
}

/** POST /admin/articles/upsert — create or update one article. */
async function handleAdminArticleUpsert(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  let body: ArticleUpsertBody;
  try {
    body = (await request.json()) as ArticleUpsertBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const title = (body.title ?? "").trim();
  if (!title) return json({ error: "invalid_body" }, 400);

  const slug = slugify((body.slug ?? "").trim() || title);
  if (!slug) return json({ error: "invalid_body" }, 400);

  const paragraphs = Array.isArray(body.paragraphs)
    ? body.paragraphs
        .map((p) => String(p ?? "").trim())
        .filter((p) => p.length > 0)
        .slice(0, 60)
    : [];

  const id =
    (body.id ?? "").trim() ||
    (globalThis.crypto?.randomUUID ? crypto.randomUUID() : `${Date.now()}`);

  const filmId = (body.film_id ?? "").trim();
  const clipTime =
    typeof body.clip_time_seconds === "number"
      ? clampInt(body.clip_time_seconds, 0, 86400, null)
      : null;

  const row = {
    id,
    slug,
    title,
    excerpt: (body.excerpt ?? "").trim().slice(0, 400),
    cover_url: (body.cover_url ?? "").trim(),
    category: (body.category ?? "").trim() || "Training",
    author_name: (body.author_name ?? "").trim() || "Whisper Team",
    paragraphs,
    published: body.published !== false,
    published_at: body.published_at || new Date().toISOString(),
    updated_at: new Date().toISOString(),
    film_id: filmId || null,
    clip_time_seconds: clipTime,
  };

  const upserted = await supabaseAdmin(env, "/whisper_articles?on_conflict=id", {
    method: "POST",
    prefer: "resolution=merge-duplicates",
    body: row,
  });
  if (!upserted.ok) return json({ error: "save_failed" }, 502);

  console.log("Article saved", { slug, by: admin.role });
  return json({ ok: true, id, slug });
}

/**
 * Resolve a signed-in badge holder (coach, athlete, verified creator,
 * director, or blogger) who is allowed to write articles. Returns their
 * profile info for the byline, or a 403 for regular accounts.
 *
 * Resilient to missing columns: the core flags (is_coach, is_athlete,
 * is_verified) and byline (username, display_name) are fetched in one query
 * using only columns that always exist. The newer optional flags
 * (is_director, is_blogger) are read via separate single-column `userFlag`
 * calls so a missing column never breaks the whole gate (PostgREST rejects
 * the entire select if any requested column is absent).
 */
async function requireBadgeAuthor(
  request: Request,
  env: Env
): Promise<
  { userId: string; username: string; displayName: string } | Response
> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  // Core profile + always-present flags in one query.
  const rows = await supabaseSelect(
    env,
    `/whisper_profiles?user_id=eq.${encodeURIComponent(
      user.userId
    )}&select=username,display_name,is_coach,is_athlete,is_verified&limit=1`
  );
  const p = rows?.[0] as
    | {
        username?: string;
        display_name?: string | null;
        is_coach?: boolean | null;
        is_athlete?: boolean | null;
        is_verified?: boolean | null;
      }
    | undefined;

  // Optional flags via resilient single-column reads (false if column
  // missing or row absent — never throws).
  const isDirector = await userFlag(env, user.userId, "is_director");
  const isBlogger = await userFlag(env, user.userId, "is_blogger");

  const hasCoreFlag = !!(
    p && (p.is_coach || p.is_athlete || p.is_verified)
  );
  const badge = await resolveUserBadge(env, user.userId);
  const isModOrHigher =
    badge === "moderator" || badge === "admin" || badge === "owner";

  if (!hasCoreFlag && !isDirector && !isBlogger && !isModOrHigher) {
    return json({ error: "forbidden" }, 403);
  }
  return {
    userId: user.userId,
    username: p?.username ?? "member",
    displayName: (p?.display_name ?? "").trim() || p?.username || "Member",
  };
}

/** GET /author/articles — the signed-in badge holder's own articles. */
async function handleAuthorArticlesList(
  request: Request,
  env: Env
): Promise<Response> {
  const author = await requireBadgeAuthor(request, env);
  if (author instanceof Response) return author;

  const rows = await supabaseSelect(
    env,
    `/whisper_articles?author_user_id=eq.${encodeURIComponent(
      author.userId
    )}&select=${ARTICLE_COLUMNS}&order=published_at.desc&limit=100`
  );
  if (rows === null) return json({ error: "load_failed" }, 502);
  return json({ articles: rows });
}

/**
 * POST /author/articles/upsert — a badge holder creates or updates one of
 * THEIR OWN articles. The byline is locked to their profile and ownership
 * is enforced on edits.
 */
async function handleAuthorArticleUpsert(
  request: Request,
  env: Env
): Promise<Response> {
  const author = await requireBadgeAuthor(request, env);
  if (author instanceof Response) return author;

  let body: ArticleUpsertBody;
  try {
    body = (await request.json()) as ArticleUpsertBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const title = (body.title ?? "").trim();
  if (!title) return json({ error: "invalid_body" }, 400);
  const slug = slugify((body.slug ?? "").trim() || title);
  if (!slug) return json({ error: "invalid_body" }, 400);

  const existingId = (body.id ?? "").trim();
  if (existingId) {
    const owned = await supabaseSelect(
      env,
      `/whisper_articles?id=eq.${encodeURIComponent(
        existingId
      )}&select=author_user_id&limit=1`
    );
    const ownerId = (owned?.[0] as { author_user_id?: string | null } | undefined)
      ?.author_user_id;
    if (!ownerId || ownerId !== author.userId) {
      return json({ error: "forbidden" }, 403);
    }
  }

  const paragraphs = Array.isArray(body.paragraphs)
    ? body.paragraphs
        .map((p) => String(p ?? "").trim())
        .filter((p) => p.length > 0)
        .slice(0, 60)
    : [];

  const id =
    existingId ||
    (globalThis.crypto?.randomUUID ? crypto.randomUUID() : `${Date.now()}`);

  const filmId = (body.film_id ?? "").trim();
  const clipTime =
    typeof body.clip_time_seconds === "number"
      ? clampInt(body.clip_time_seconds, 0, 86400, null)
      : null;

  const row = {
    id,
    slug,
    title,
    excerpt: (body.excerpt ?? "").trim().slice(0, 400),
    cover_url: (body.cover_url ?? "").trim(),
    category: (body.category ?? "").trim() || "Training",
    author_name: author.displayName,
    author_username: author.username,
    author_user_id: author.userId,
    paragraphs,
    published: body.published !== false,
    published_at: body.published_at || new Date().toISOString(),
    updated_at: new Date().toISOString(),
    film_id: filmId || null,
    clip_time_seconds: clipTime,
  };

  const upserted = await supabaseAdmin(env, "/whisper_articles?on_conflict=id", {
    method: "POST",
    prefer: "resolution=merge-duplicates",
    body: row,
  });
  if (!upserted.ok) return json({ error: "save_failed" }, 502);

  console.log("Author article saved", { slug, by: author.username });
  return json({ ok: true, id, slug });
}

/** POST /author/articles/delete — a badge holder removes their own article. */
async function handleAuthorArticleDelete(
  request: Request,
  env: Env
): Promise<Response> {
  const author = await requireBadgeAuthor(request, env);
  if (author instanceof Response) return author;

  let body: { id?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const id = (body.id ?? "").trim();
  if (!id) return json({ error: "invalid_body" }, 400);

  const owned = await supabaseSelect(
    env,
    `/whisper_articles?id=eq.${encodeURIComponent(id)}&select=author_user_id&limit=1`
  );
  const ownerId = (owned?.[0] as { author_user_id?: string | null } | undefined)
    ?.author_user_id;
  if (!ownerId || ownerId !== author.userId) {
    return json({ error: "forbidden" }, 403);
  }

  const res = await supabaseAdmin(
    env,
    `/whisper_articles?id=eq.${encodeURIComponent(id)}`,
    { method: "DELETE" }
  );
  if (!res.ok) return json({ error: "delete_failed" }, 502);
  return json({ ok: true });
}

/**
 * Starter articles written by the Whisper team — seeded on demand from the
 * admin panel so the public Articles page never launches empty. Cover URLs
 * point at generated brand imagery hosted on Rork's CDN.
 */
const STARTER_ARTICLES: {
  slug: string;
  title: string;
  category: string;
  excerpt: string;
  cover_url: string;
  paragraphs: string[];
}[] = [
  {
    slug: "welcome-to-whisper",
    title: "Welcome to Whisper: the fitness network built on proof",
    category: "News",
    excerpt:
      "Why we built a social platform where your training log matters more than your follower count.",
    cover_url: "https://rork.app/pa/339ewll6y549xwakbhd4s/smartphone_gym_bench_feed",
    paragraphs: [
      "Most social platforms reward whoever shouts the loudest. Whisper was built on a different bet: that people in fitness actually want the opposite — a place where the work you put in is the content, and where the people giving advice have been verified by a real human, not an algorithm.",
      "Whisper is the social side of Jasper, the fitness app. Your workouts, nutrition, sleep, and progress photos live in Jasper; Whisper is where you share the journey, find a coach, follow athletes who inspire you, and keep yourself honest in front of people on the same road.",
      "Three verified roles anchor the community. Athletes apply with their sport history. Creators apply with their content. Coaches go through the strictest review of all — credentials, client history, and a human decision — because coaching advice is the one thing we refuse to leave unverified.",
      "Verification here is not a paid checkmark. You apply for free, a real person reviews your submission, and only approved members activate their badge. That order matters: review first, badge second. It keeps the seal meaningful for everyone who carries it.",
      "For coaches, Whisper is also a storefront. Approved coaches set their own monthly rate, link a bank account, and get paid directly by their clients — programs, check-ins, and DM access all in one place, with payments handled securely through Stripe.",
      "This articles section is where we publish training guides, nutrition breakdowns, athlete stories, and product news. New pieces land regularly — follow along, and if there is a topic you want covered, tell us through the Support page. Welcome in.",
    ],
  },
  {
    slug: "progressive-overload-explained",
    title: "Progressive overload, explained simply",
    category: "Training",
    excerpt:
      "The single principle behind every effective training program — and the three ways to apply it without wrecking your joints.",
    cover_url: "https://rork.app/pa/339ewll6y549xwakbhd4s/barbell_progressive_overload",
    paragraphs: [
      "Strip away the influencer noise and almost every effective training program rests on one principle: progressive overload. Your body adapts to the demands you place on it, so to keep adapting — more muscle, more strength, better conditioning — the demand has to keep rising over time.",
      "The mistake most lifters make is thinking overload only means adding weight to the bar. Load is one lever, but it is the bluntest one. Chase it exclusively and you will stall within months, usually with cranky shoulders or a tweaked lower back to show for it.",
      "There are three levers worth managing. First, load: add small amounts of weight when your top sets feel controlled. Second, volume: add a rep or a set at the same weight — going from 3x8 to 3x10 on the same dumbbells is real progress. Third, execution: slower eccentrics, deeper range of motion, shorter rest. Same weight, harder stimulus.",
      "A simple rule that works for years, not weeks: earn your reps before you add load. Pick a rep range — say 8 to 12. Start at the bottom with a weight you own. Each session, push toward the top of the range with clean form. When you hit the ceiling on every set, add the smallest increment available and drop back to the bottom.",
      "Track it, or it did not happen. Overload only works when you know exactly what you did last time. Log every working set — the lifters who progress fastest are almost never the ones training hardest, they are the ones tracking most honestly.",
      "Finally, remember that adaptation happens between sessions, not during them. Sleep, protein, and managing stress are part of the overload equation. Push the numbers up in the gym, and give your body the raw material to cash the check.",
    ],
  },
  {
    slug: "protein-targets-that-fit-your-life",
    title: "Protein targets that actually fit your life",
    category: "Nutrition",
    excerpt:
      "Forget the bro-science extremes. Here's how to set a protein number you can hit every day — and why consistency beats precision.",
    cover_url: "https://rork.app/pa/339ewll6y549xwakbhd4s/protein_meal_prep_flatlay",
    paragraphs: [
      "Ask five fitness people about protein and you will get five confident, contradictory answers. The research is actually pretty settled: for people who train, somewhere between 0.7 and 1 gram per pound of goal body weight per day covers nearly everyone. More than that is not harmful for healthy people — it is just usually unnecessary.",
      "Notice the phrase goal body weight. If you weigh 240 pounds and your target is 190, anchoring protein to 190 keeps the number realistic and supports the body you are building rather than the one you are leaving behind.",
      "The daily total matters far more than timing. The anabolic window is wider than a garage door — hitting your number across three or four meals beats obsessing over a post-workout shake. A practical pattern: 30 to 50 grams per meal, plus one flexible snack, and the math takes care of itself.",
      "Where people actually fail is not knowledge, it is logistics. Protein takes preparation in a way carbs and fat never do. The fix is boring: keep two or three zero-thought options always available — Greek yogurt, cottage cheese, rotisserie chicken, a quality protein powder, canned fish, eggs. When the fridge is stocked, the target hits itself.",
      "If you are in a fat-loss phase, protein becomes even more important, not less. It preserves muscle while you drop weight, it is the most satiating macronutrient, and it costs the most calories to digest. A cut without adequate protein is how you end up lighter but softer.",
      "Log your food for two ordinary weeks in Jasper before changing anything. Most people discover they are 40 to 60 grams short of their target on normal days — and that one insight, fixed with one extra protein-forward meal, outperforms every supplement on the shelf.",
    ],
  },
  {
    slug: "what-a-verified-coach-actually-does",
    title: "What a verified Whisper coach actually does for you",
    category: "Coaching",
    excerpt:
      "Programs are the least of it. The real value of a coach is accountability, auditing, and course-correction — here's what to expect.",
    cover_url: "https://rork.app/pa/339ewll6y549xwakbhd4s/fitness_coach_phone_squat",
    paragraphs: [
      "A training program is a commodity. You can find a thousand decent ones for free tonight. What you cannot download is someone who watches your actual data week after week and adjusts the plan to the life you are actually living. That is the job of a coach, and it is why we verify ours.",
      "Every coach on Whisper with the orange seal went through a human review — credentials, client history, and experience. That does not guarantee chemistry with every client, but it does guarantee you are not taking programming advice from someone who bought a checkmark.",
      "Here is what working with a coach on Whisper looks like in practice. Your coach builds structured, multi-week programs and sends them straight into your DM thread, where they apply with one tap. They see your training, nutrition, sleep, and progress snapshots — the real numbers, not your highlight reel — and they propose adjustments you accept or decline.",
      "The accountability loop is the product. Knowing a real person will see this week's log changes behavior more reliably than any streak badge ever will. Most clients do not need a smarter program; they need to execute an ordinary program for an extraordinary number of consecutive weeks.",
      "Payment is simple and protected. Coaches set their own monthly rate, you subscribe through Stripe, and you can cancel anytime. Money only changes hands when a coach has accepted you as a client — and the relationship, the programs, and the check-ins all live in one thread.",
      "How to choose: look at their profile, their content, and their specialties. Send a request with a sentence about your goal. A good coach will ask you questions before they promise you results — that is usually the clearest signal you have found the right one.",
    ],
  },
  {
    slug: "building-an-athletic-resume",
    title: "Your profile is your athletic resume. Build it like one.",
    category: "Athletes",
    excerpt:
      "For student athletes and competitors, a feed can be more than highlights — it can be the living record recruiters and sponsors actually check.",
    cover_url: "https://rork.app/pa/339ewll6y549xwakbhd4s/sprinter_starting_blocks",
    paragraphs: [
      "Recruiters, sponsors, and team managers all do the same thing before they reply to your email: they look you up. What they find is either a scattered highlight reel across three platforms — or a single, dated, verifiable record of your athletic life. The second one wins.",
      "The verified Athlete badge on Whisper exists for exactly this. You apply with your sport history, a real person reviews it, and once approved your profile stops being just a feed and becomes a living athletic resume — competition results, training blocks, physical development over time, all timestamped.",
      "Post the process, not just the podium. A season of consistent training logs tells a scout more about your character than one viral clip. Coaches at the next level are betting on trajectory — show them the slope, not just the peak.",
      "Dates matter more than production value. A shaky phone video of a verified PR, posted the day it happened, is worth more than a polished montage assembled months later. Chronology is credibility.",
      "Use the pinned posts on your profile like the top of a resume: current stats, best verified results, and one clip that shows how you move. Assume every viewer gives you thirty seconds — make the first screen count.",
      "And compete with your circle, not against it. Follow athletes one level above you. Their standards recalibrate yours, and on a platform built around real logs rather than filtered highlights, proximity to better athletes makes you better. That is the whole point of putting your career on the record.",
    ],
  },
  {
    slug: "consistency-beats-intensity",
    title: "Consistency beats intensity — and your feed can prove it",
    category: "Community",
    excerpt:
      "The uncomfortable math of showing up: why the 80% effort you repeat forever beats the 100% effort you abandon in March.",
    cover_url: "https://rork.app/pa/339ewll6y549xwakbhd4s/lifters_fist_bump_gym",
    paragraphs: [
      "Every January the gym fills with people training at an intensity they cannot sustain, and every March it empties again. The math is brutal and simple: three moderate sessions a week for a year is 156 workouts. An all-out six-day program abandoned after eight weeks is 48. The moderate plan wins by a factor of three — before you even account for injuries.",
      "Intensity is emotional; consistency is structural. Motivation is a feeling and feelings are weather. The people still training in November built systems instead: fixed training days, a bag packed the night before, a minimum viable workout for the days when life goes sideways.",
      "The minimum viable workout deserves its own paragraph. Decide in advance what counts on a terrible day — twenty minutes, three exercises, done. The goal is not the stimulus; it is protecting the identity of someone who trains. Zeroes are what kill progress, because they cluster. One skipped day becomes a skipped week.",
      "This is where a community changes the equation. Posting your sessions on Whisper — even the ugly, abbreviated ones — creates a public record that quietly pressures you to keep it alive. Not for likes. Because the version of you that people follow is the version that shows up.",
      "Follow people at your level who post their real logs, not just their PRs. Watching an ordinary person string together ordinary weeks is more motivating than any transformation photo, because it looks achievable — and it is.",
      "Zoom out far enough and intensity barely registers; the graph of anyone's progress is just a record of how often they showed up. Make showing up the metric. Everything else compounds from there.",
    ],
  },
];

/**
 * POST /admin/articles/seed — insert the starter articles, skipping any slug
 * that already exists so it is safe to press twice.
 */
async function handleAdminArticlesSeed(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  const existing = await supabaseSelect(
    env,
    "/whisper_articles?select=slug&limit=500"
  );
  if (existing === null) return json({ error: "load_failed" }, 502);
  const have = new Set(
    existing.map((r) => String((r as { slug?: string }).slug ?? ""))
  );

  let inserted = 0;
  const now = Date.now();
  for (const [i, a] of STARTER_ARTICLES.entries()) {
    if (have.has(a.slug)) continue;
    const res = await supabaseAdmin(env, "/whisper_articles?on_conflict=slug", {
      method: "POST",
      prefer: "resolution=ignore-duplicates",
      body: {
        slug: a.slug,
        title: a.title,
        excerpt: a.excerpt,
        cover_url: a.cover_url,
        category: a.category,
        author_name: "Whisper Team",
        paragraphs: a.paragraphs,
        published: true,
        // Stagger publish dates so the list reads naturally, newest first.
        published_at: new Date(now - i * 86_400_000).toISOString(),
      },
    });
    if (res.ok) inserted += 1;
  }

  console.log("Starter articles seeded", { inserted, by: admin.role });
  return json({ ok: true, inserted, skipped: STARTER_ARTICLES.length - inserted });
}

/** POST /admin/articles/delete — remove one article. */
async function handleAdminArticleDelete(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;

  let body: { id?: string };
  try {
    body = (await request.json()) as { id?: string };
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const id = (body.id ?? "").trim();
  if (!id) return json({ error: "invalid_body" }, 400);

  const removed = await supabaseAdmin(
    env,
    `/whisper_articles?id=eq.${encodeURIComponent(id)}`,
    { method: "DELETE" }
  );
  if (!removed.ok) return json({ error: "delete_failed" }, 502);

  console.log("Article deleted", { by: admin.role });
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// Collab Projects — moderator-created, invite-only activity spaces. The
// backend is the authority: a member can participate only after an elevated
// Whisper team member has invited them, and only elevated members can invite.
// ---------------------------------------------------------------------------

type CollabFormat =
  | "content_sprint"
  | "community_challenge"
  | "feedback_swap"
  | "brand_campaign"
  | "scouting_room"
  | "custom";
type CollabActivityKind = "task" | "post" | "review" | "meeting" | "challenge";
type CollabActivityStatus = "open" | "doing" | "done";

async function collabAdminRole(
  env: Env,
  userId: string
): Promise<AdminRole | null> {
  const uid = encodeURIComponent(userId);
  const rows = await supabaseSelect(
    env,
    `/whisper_admins?user_id=eq.${uid}&select=role&limit=1`
  );
  const role = (rows?.[0] as { role?: string } | undefined)?.role;
  if (role === "owner" || role === "admin" || role === "moderator") return role;
  const profiles = await supabaseSelect(
    env,
    `/profiles?id=eq.${uid}&select=is_owner,is_admin,is_moderator&limit=1`
  );
  const p = (profiles?.[0] ?? null) as {
    is_owner?: boolean;
    is_admin?: boolean;
    is_moderator?: boolean;
  } | null;
  if (p?.is_owner) return "owner";
  if (p?.is_admin) return "admin";
  if (p?.is_moderator) return "moderator";
  return null;
}

async function collabCanAccess(
  env: Env,
  userId: string,
  projectId: string
): Promise<boolean> {
  if (await collabAdminRole(env, userId)) return true;
  const rows = await supabaseSelect(
    env,
    `/whisper_collab_members?project_id=eq.${encodeURIComponent(projectId)}&user_id=eq.${encodeURIComponent(userId)}&status=eq.active&select=user_id&limit=1`
  );
  return (rows?.length ?? 0) > 0;
}

async function collabUsername(env: Env, userId: string): Promise<string> {
  const rows = await supabaseSelect(
    env,
    `/whisper_profiles?user_id=eq.${encodeURIComponent(userId)}&select=username&limit=1`
  );
  return String((rows?.[0] as { username?: string } | undefined)?.username ?? "");
}

async function handleCollabList(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const role = await collabAdminRole(env, user.userId);
  let projects: unknown[] | null = null;
  if (role) {
    projects = await supabaseSelect(
      env,
      "/whisper_collab_projects?select=*&order=updated_at.desc&limit=100"
    );
  } else {
    const membership = await supabaseSelect(
      env,
      `/whisper_collab_members?user_id=eq.${encodeURIComponent(user.userId)}&status=eq.active&select=project_id`
    );
    const ids = (membership ?? [])
      .map((row) => String((row as { project_id?: string }).project_id ?? ""))
      .filter(Boolean);
    if (ids.length === 0) return json({ projects: [], canManage: false });
    projects = await supabaseSelect(
      env,
      `/whisper_collab_projects?id=in.(${ids.map(encodeURIComponent).join(",")})&select=*&order=updated_at.desc&limit=100`
    );
  }
  if (projects === null) return json({ error: "load_failed" }, 502);
  return json({ projects, canManage: Boolean(role) });
}

async function handleCollabDetail(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const projectId = (new URL(request.url).searchParams.get("projectId") ?? "").trim();
  if (!projectId || !(await collabCanAccess(env, user.userId, projectId))) {
    return json({ error: "forbidden" }, 403);
  }
  const [projects, members, activities] = await Promise.all([
    supabaseSelect(env, `/whisper_collab_projects?id=eq.${encodeURIComponent(projectId)}&select=*&limit=1`),
    supabaseSelect(env, `/whisper_collab_members?project_id=eq.${encodeURIComponent(projectId)}&select=*&order=created_at.asc`),
    supabaseSelect(env, `/whisper_collab_activities?project_id=eq.${encodeURIComponent(projectId)}&select=*&order=created_at.asc`),
  ]);
  if (!projects?.[0]) return json({ error: "not_found" }, 404);
  return json({ project: projects[0], members: members ?? [], activities: activities ?? [] });
}

async function handleCollabCreate(request: Request, env: Env): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  let body: { title?: string; summary?: string; format?: CollabFormat };
  try { body = (await request.json()) as { title?: string; summary?: string; format?: CollabFormat }; }
  catch { return json({ error: "invalid_body" }, 400); }
  const title = (body.title ?? "").trim().slice(0, 100);
  const summary = (body.summary ?? "").trim().slice(0, 600);
  const formats: CollabFormat[] = ["content_sprint", "community_challenge", "feedback_swap", "brand_campaign", "scouting_room", "custom"];
  const format = formats.includes(body.format ?? "custom") ? body.format ?? "custom" : "custom";
  if (title.length < 2) return json({ error: "invalid_body" }, 400);
  const ok = await supabaseAdmin(env, "/whisper_collab_projects", {
    method: "POST",
    body: { title, summary, format, created_by: admin.userId, created_by_username: await collabUsername(env, admin.userId) },
  });
  if (!ok.ok) return json({ error: "save_failed" }, 502);
  return json({ ok: true });
}

async function handleCollabInvite(request: Request, env: Env): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  let body: { projectId?: string; username?: string };
  try { body = (await request.json()) as { projectId?: string; username?: string }; }
  catch { return json({ error: "invalid_body" }, 400); }
  const projectId = (body.projectId ?? "").trim();
  const username = (body.username ?? "").trim().replace(/^@/, "").slice(0, 40);
  if (!projectId || !username) return json({ error: "invalid_body" }, 400);
  const target = await supabaseSelect(
    env,
    `/whisper_profiles?username=ilike.${encodeURIComponent(username)}&select=user_id,username&limit=1`
  );
  const member = target?.[0] as { user_id?: string; username?: string } | undefined;
  if (!member?.user_id) return json({ error: "member_not_found" }, 404);
  const ok = await supabaseAdmin(env, "/whisper_collab_members?on_conflict=project_id,user_id", {
    method: "POST",
    prefer: "resolution=merge-duplicates",
    body: { project_id: projectId, user_id: member.user_id, username: member.username ?? username, invited_by: admin.userId, role: "collaborator", status: "active" },
  });
  if (!ok.ok) return json({ error: "invite_failed" }, 502);
  return json({ ok: true });
}

async function handleCollabActivityCreate(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: { projectId?: string; title?: string; detail?: string; kind?: CollabActivityKind; dueOn?: string | null };
  try { body = (await request.json()) as { projectId?: string; title?: string; detail?: string; kind?: CollabActivityKind; dueOn?: string | null }; }
  catch { return json({ error: "invalid_body" }, 400); }
  const projectId = (body.projectId ?? "").trim();
  const title = (body.title ?? "").trim().slice(0, 160);
  const detail = (body.detail ?? "").trim().slice(0, 1000);
  const kinds: CollabActivityKind[] = ["task", "post", "review", "meeting", "challenge"];
  const kind = kinds.includes(body.kind ?? "task") ? body.kind ?? "task" : "task";
  if (!projectId || title.length < 2 || !(await collabCanAccess(env, user.userId, projectId))) return json({ error: "forbidden" }, 403);
  const ok = await supabaseAdmin(env, "/whisper_collab_activities", {
    method: "POST",
    body: { project_id: projectId, title, detail, kind, due_on: body.dueOn ?? null, created_by: user.userId, created_by_username: await collabUsername(env, user.userId) },
  });
  if (!ok.ok) return json({ error: "save_failed" }, 502);
  return json({ ok: true });
}

async function handleCollabActivityStatus(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: { projectId?: string; activityId?: string; status?: CollabActivityStatus };
  try { body = (await request.json()) as { projectId?: string; activityId?: string; status?: CollabActivityStatus }; }
  catch { return json({ error: "invalid_body" }, 400); }
  const statuses: CollabActivityStatus[] = ["open", "doing", "done"];
  if (!body.projectId || !body.activityId || !statuses.includes(body.status ?? "open") || !(await collabCanAccess(env, user.userId, body.projectId))) {
    return json({ error: "forbidden" }, 403);
  }
  const ok = await supabaseAdmin(env, `/whisper_collab_activities?id=eq.${encodeURIComponent(body.activityId)}&project_id=eq.${encodeURIComponent(body.projectId)}`, {
    method: "PATCH",
    body: { status: body.status, updated_at: new Date().toISOString() },
  });
  if (!ok.ok) return json({ error: "save_failed" }, 502);
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// Public read-only profile — powers mydailywhisper.com/p/:username so
// featured members can be viewed before signing up. Only safe, public fields
// are ever returned, and private accounts stay hidden.
// ---------------------------------------------------------------------------

/** GET /public/profile?username=… — safe public subset of one profile. */
async function handlePublicProfile(
  request: Request,
  env: Env
): Promise<Response> {
  const url = new URL(request.url);
  const username = (url.searchParams.get("username") ?? "")
    .trim()
    .replace(/^@/, "");
  if (!username || username.length > 40) {
    return json({ error: "invalid_username" }, 400);
  }

  const rows = await supabaseSelect(
    env,
    `/profiles?username=ilike.${encodeURIComponent(username)}&select=*&limit=1`
  );
  if (rows === null) return json({ error: "load_failed" }, 502);
  const p = rows[0] as Record<string, unknown> | undefined;
  if (!p) return json({ error: "not_found" }, 404);
  if (p.is_private === true) return json({ error: "not_found" }, 404);

  // Whitelist — never expose emails, flags, or internal columns.
  return json({
    profile: {
      username: String(p.username ?? username),
      display_name: (p.display_name as string | null) ?? null,
      bio: (p.bio as string | null) ?? null,
      profile_image_url: (p.profile_image_url as string | null) ?? null,
      interests: Array.isArray(p.interests)
        ? (p.interests as string[]).slice(0, 8)
        : [],
      is_coach: p.is_coach === true,
      is_athlete: p.is_athlete === true,
      is_verified: p.is_verified === true,
    },
  });
}

// ---------------------------------------------------------------------------
// Featured Film Friday — short films produced by the Whisper media team
// (Directors). Films are published by directors/mods/admins/owners; users
// with blogging permissions (coaches/athletes/verified creators) can
// timestamp moments and generate clip placeholders for articles.
// ---------------------------------------------------------------------------

/** POST /films/create — directors/mods/admins/owners publish a film. */
async function handleFilmCreate(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  // Directors, mods, admins, and owners can publish films.
  const isDirector = await userFlag(env, user.userId, "is_director");
  const badge = await resolveUserBadge(env, user.userId);
  const canManage = isDirector || badge === "moderator" || badge === "admin" || badge === "owner";
  if (!canManage) return json({ error: "forbidden" }, 403);

  let body: Record<string, unknown>;
  try { body = (await request.json()) as Record<string, unknown>; } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const title = String(body.title ?? "").trim().slice(0, 200);
  const videoUrl = String(body.videoUrl ?? "").trim().slice(0, 1000);
  if (!title) return json({ error: "title_required" }, 400);
  if (!videoUrl) return json({ error: "video_url_required" }, 400);

  const row: Record<string, unknown> = {
    director_id: user.userId,
    title,
    synopsis: String(body.synopsis ?? "").trim().slice(0, 5000) || null,
    video_url: videoUrl,
    trailer_url: String(body.trailerUrl ?? "").trim().slice(0, 1000) || null,
    poster_url: String(body.posterUrl ?? "").trim().slice(0, 1000) || null,
    duration_seconds: clampInt(body.durationSeconds, 0, 86400, null),
    featured_date: String(body.featuredDate ?? "").trim().slice(0, 20) || null,
    published: body.published !== false,
  };
  const ok = await supabaseAdmin(env, "/whisper_films", { method: "POST", body: row });
  if (!ok.ok) return json({ error: "save_failed" }, 502);
  return json({ ok: true });
}

/** POST /films/timestamps — a blogger marks a moment in a film. */
async function handleFilmTimestampCreate(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: Record<string, unknown>;
  try { body = (await request.json()) as Record<string, unknown>; } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const filmId = String(body.filmId ?? "").trim();
  const label = String(body.label ?? "").trim().slice(0, 500);
  const timeSeconds = clampInt(body.timeSeconds, 0, 86400, -1);
  if (!filmId || !label || timeSeconds < 0) {
    return json({ error: "invalid_input" }, 400);
  }

  // Blogging permission: coaches, athletes, verified creators, directors,
  // bloggers, mods, admins, owners.
  const isCoach = await userFlag(env, user.userId, "is_coach");
  const isAthlete = await userFlag(env, user.userId, "is_athlete");
  const isVerified = await userFlag(env, user.userId, "is_verified");
  const isDirector = await userFlag(env, user.userId, "is_director");
  const isBlogger = await userFlag(env, user.userId, "is_blogger");
  const badge = await resolveUserBadge(env, user.userId);
  const canTimestamp = isCoach || isAthlete || isVerified || isDirector ||
    isBlogger || badge === "moderator" || badge === "admin" || badge === "owner";
  if (!canTimestamp) return json({ error: "forbidden" }, 403);

  // The poster placeholder is the video URL + timecode — the article
  // renderer uses this to show a frame placeholder where the cover image
  // normally goes.
  const posterUrl = `film-frame:${filmId}:${timeSeconds}`;

  const row: Record<string, unknown> = {
    film_id: filmId,
    user_id: user.userId,
    label,
    time_seconds: timeSeconds,
    poster_url: posterUrl,
  };
  const ok = await supabaseAdmin(env, "/whisper_film_timestamps", { method: "POST", body: row });
  if (!ok.ok) return json({ error: "save_failed" }, 502);
  const created = (await ok.json()) as Record<string, unknown>;
  const timestamp = (created as { id?: string; film_id?: string; user_id?: string; label?: string; time_seconds?: number; poster_url?: string | null; created_at?: string });
  return json({ ok: true, timestamp });
}

/** DELETE /films/timestamps — author deletes their own timestamp. */
async function handleFilmTimestampDelete(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: Record<string, unknown>;
  try { body = (await request.json()) as Record<string, unknown>; } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const id = String(body.id ?? "").trim();
  if (!id) return json({ error: "invalid_input" }, 400);

  // RLS allows the author to delete; the backend double-checks ownership.
  const ok = await supabaseAdmin(env, `/whisper_film_timestamps?id=eq.${encodeURIComponent(id)}&user_id=eq.${encodeURIComponent(user.userId)}`, { method: "DELETE" });
  if (!ok.ok) return json({ error: "delete_failed" }, 502);
  return json({ ok: true });
}

/** GET /films — public list of published films, with the director's profile
 *  joined so the credit can link to the real director's profile page. */
async function handleFilmsList(_request: Request, env: Env): Promise<Response> {
  const rows = await supabaseSelect(
    env,
    `/whisper_films?select=id,director_id,title,synopsis,video_url,trailer_url,poster_url,duration_seconds,featured_date,published,created_at,updated_at&published=eq.true&order=featured_date.desc.nullslast,created_at.desc&limit=30`
  );
  if (rows === null) return json({ films: [] });
  const films = rows as Array<Record<string, unknown>>;
  if (films.length === 0) return json({ films: [] });

  // Resolve director profiles in one batched query.
  const directorIds = Array.from(
    new Set(films.map((f) => String(f.director_id ?? "")).filter(Boolean))
  );
  const directorById = new Map<string, { username: string | null; display_name: string | null }>();
  if (directorIds.length > 0) {
    const idFilter = directorIds.map((id) => `user_id=eq.${encodeURIComponent(id)}`).join(",");
    const profileRows = await supabaseSelect(
      env,
      `/whisper_profiles?select=user_id,username,display_name&or=(${idFilter})&limit=${directorIds.length * 2}`
    );
    if (profileRows) {
      for (const p of profileRows as Array<Record<string, unknown>>) {
        const uid = String(p.user_id ?? "");
        if (uid) {
          directorById.set(uid, {
            username: (p.username as string | null) ?? null,
            display_name: (p.display_name as string | null) ?? null,
          });
        }
      }
    }
  }

  const withCredit = films.map((f) => {
    const directorId = String(f.director_id ?? "");
    const profile = directorById.get(directorId);
    return {
      ...f,
      director_name: profile?.display_name ?? null,
      director_username: profile?.username ?? null,
    };
  });
  return json({ films: withCredit });
}

/** GET /films/:id — one published film, with the director's profile joined. */
async function handleFilmGet(request: Request, env: Env): Promise<Response> {
  const url = new URL(request.url);
  const id = url.searchParams.get("id") ?? "";
  if (!id) return json({ error: "invalid_input" }, 400);
  const rows = await supabaseSelect(
    env,
    `/whisper_films?select=id,director_id,title,synopsis,video_url,trailer_url,poster_url,duration_seconds,featured_date,published,created_at,updated_at&id=eq.${encodeURIComponent(id)}&published=eq.true&limit=1`
  );
  if (rows === null || rows.length === 0) return json({ error: "not_found" }, 404);
  const film = rows[0] as Record<string, unknown>;
  const directorId = String(film.director_id ?? "");
  if (directorId) {
    const profileRows = await supabaseSelect(
      env,
      `/whisper_profiles?select=user_id,username,display_name&user_id=eq.${encodeURIComponent(directorId)}&limit=1`
    );
    const profile = (profileRows?.[0] as Record<string, unknown> | undefined);
    film.director_name = profile?.display_name ?? null;
    film.director_username = profile?.username ?? null;
  }
  return json({ film });
}

// ---------------------------------------------------------------------------
// Support / contact form — relays the message to the Whisper inbox via
// Resend with reply-to set to the visitor, so replying just works.
// ---------------------------------------------------------------------------

interface SupportBody {
  name?: string;
  email?: string;
  topic?: string;
  message?: string;
}

/** Extract the bare address out of `Name <addr@x.com>` or a plain address. */
function fromAddress(env: Env): string {
  const raw = env.RESEND_FROM || DEFAULT_FROM;
  const match = raw.match(/<([^>]+)>/);
  return (match ? match[1] : raw).trim();
}

/** POST /support/contact — visitor support form. */
async function handleSupportContact(
  request: Request,
  env: Env
): Promise<Response> {
  let body: SupportBody;
  try {
    body = (await request.json()) as SupportBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const name = (body.name ?? "").trim().slice(0, 80);
  const email = (body.email ?? "").trim().slice(0, 120);
  const topic = (body.topic ?? "General").trim().slice(0, 60);
  const message = (body.message ?? "").trim().slice(0, 4000);

  if (!name || !message || !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) {
    return json({ error: "invalid_body" }, 400);
  }
  if (!env.RESEND_API_KEY) return json({ error: "not_configured" }, 503);

  const escapeHtml = (s: string): string =>
    s
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;");

  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.RESEND_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from: env.RESEND_FROM || DEFAULT_FROM,
      to: [fromAddress(env)],
      reply_to: email,
      subject: `[Support · ${topic}] from ${name}`,
      html: emailShell(
        "New support message",
        `<p ${EMAIL_P}><strong>From:</strong> ${escapeHtml(name)} &lt;${escapeHtml(email)}&gt;</p>
         <p ${EMAIL_P}><strong>Topic:</strong> ${escapeHtml(topic)}</p>
         <p ${EMAIL_P}>${escapeHtml(message).replace(/\n/g, "<br/>")}</p>`
      ),
    }),
  });
  if (!res.ok) {
    console.error("Support relay failed", { status: res.status });
    return json({ error: "send_failed" }, 502);
  }

  console.log("Support message relayed", { topic });
  return json({ ok: true });
}

async function handleBroadcast(request: Request, env: Env): Promise<Response> {
  if (!env.BROADCAST_SECRET) {
    console.error("BROADCAST_SECRET is not set in project envs");
    return json({ error: "broadcast_not_configured" }, 503);
  }
  const auth = request.headers.get("Authorization") ?? "";
  const provided = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (!provided || provided !== env.BROADCAST_SECRET) {
    return json({ error: "unauthorized" }, 401);
  }

  let body: BroadcastBody;
  try {
    body = (await request.json()) as BroadcastBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const subject = (body.subject ?? "").trim();
  const message = (body.message ?? "").trim();
  const mode = body.mode ?? "preview";

  if (mode !== "preview" && (!subject || !message)) {
    return json({ error: "subject_and_message_required" }, 400);
  }

  // Split attachments: images get embedded inline in the email body (CID),
  // everything else stays a regular downloadable attachment. Without a CID
  // reference in the HTML, most mail clients (Gmail especially) hide image
  // attachments entirely.
  const attachments = sanitizeAttachments(body.attachments);
  const inline: BroadcastAttachment[] = [];
  const regular: BroadcastAttachment[] = [];
  attachments.forEach((att, i) => {
    const mime = imageContentType(att.filename);
    if (mime) {
      inline.push({
        ...att,
        content_type: mime,
        content_id: `inline-img-${i}`,
      });
    } else {
      regular.push(att);
    }
  });

  if (mode === "preview") {
    // Preview renders images as data URIs so they show in the browser iframe.
    const html = broadcastHtml(
      body,
      inline.map((att) => ({
        src: `data:${att.content_type};base64,${att.content}`,
        name: att.filename,
      }))
    );
    const emails = await listAllUserEmails(env);
    return json({
      html,
      recipientCount: emails ? emails.length : null,
    });
  }

  if (!env.RESEND_API_KEY) {
    return json({ error: "resend_not_configured" }, 503);
  }

  const html = broadcastHtml(
    body,
    inline.map((att) => ({
      src: `cid:${att.content_id}`,
      name: att.filename,
    }))
  );
  const allAttachments: BroadcastAttachment[] = [...inline, ...regular];

  if (mode === "test") {
    const testEmail = (body.testEmail ?? "").trim();
    if (!testEmail.includes("@")) {
      return json({ error: "test_email_required" }, 400);
    }
    await sendEmail(env, testEmail, `[TEST] ${subject}`, html, allAttachments);
    return json({ ok: true, mode: "test", sent: 1 });
  }

  const emails = await listAllUserEmails(env);
  if (!emails) {
    return json({ error: "user_list_failed" }, 502);
  }
  if (emails.length === 0) {
    return json({ ok: true, mode: "send", sent: 0, failed: 0 });
  }

  console.log("Broadcasting branded email", {
    recipients: emails.length,
    subject,
    attachments: allAttachments.length,
    inlineImages: inline.length,
  });
  const result = await sendBroadcastBatch(env, emails, subject, html, allAttachments);
  return json({ ok: true, mode: "send", ...result });
}

// ---------------------------------------------------------------------------
// Brand accounts + creator sponsorships
//
// Brands sign up with a company profile that includes sponsorship
// requirements (min followers / age / posts) and transparent typical pay.
// Eligible creators apply with their desired rate; brands accept, deny, or
// counter with editable terms. Denied brands are DM-blocked from the
// creator. Accepted deals are funded through Stripe and held as PENDING
// payments until the creator's tracked posts (per-post deals) land or the
// weekly hold passes — then the net amount transfers to the creator's
// linked bank via Stripe Connect.
// ---------------------------------------------------------------------------

const SPONSOR_PLATFORM_FEE_PERCENT = 10;
const SPONSOR_BASES = ["per_post", "per_month", "per_year"] as const;
type SponsorBasis = (typeof SPONSOR_BASES)[number];

const BRAND_COLUMNS =
  "user_id,company_name,username,website,industry,about,logo_url,cover_url,media_urls,video_url,instagram,ember_verified,ember_score,ember_summary,ember_checked_at,amenities,min_followers,min_age,min_posts,pay_basis,typical_pay_min_cents,typical_pay_max_cents,payment_terms,published,created_at,updated_at";

interface BrandRow {
  user_id: string;
  company_name: string;
  username: string | null;
  instagram: string | null;
  min_followers: number;
  min_age: number;
  min_posts: number;
  pay_basis: string;
  published: boolean;
}

/** Normalize an Instagram handle: strips @, URLs, and trailing slashes. */
function cleanInstagramHandle(raw: unknown): string | null {
  const handle = String(raw ?? "")
    .trim()
    .replace(/^https?:\/\/(www\.)?instagram\.com\//i, "")
    .replace(/^@+/, "")
    .replace(/[/?#].*$/, "")
    .slice(0, 60);
  return /^[a-zA-Z0-9._]+$/.test(handle) ? handle : null;
}

async function getBrandRow(
  env: Env,
  userId: string
): Promise<Record<string, unknown> | null> {
  const rows = await supabaseSelect(
    env,
    `/whisper_brand_profiles?user_id=eq.${encodeURIComponent(userId)}&select=${BRAND_COLUMNS}&limit=1`
  );
  return (rows?.[0] as Record<string, unknown> | undefined) ?? null;
}

function parseBasis(raw: unknown): SponsorBasis | null {
  return SPONSOR_BASES.includes(raw as SponsorBasis)
    ? (raw as SponsorBasis)
    : null;
}

/** POST /brand/profile — create or update the caller's brand profile. */
async function handleBrandUpsert(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: Record<string, unknown>;
  try {
    body = (await request.json()) as Record<string, unknown>;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const companyName = String(body.companyName ?? "").trim().slice(0, 80);
  if (!companyName) return json({ error: "company_name_required" }, 400);

  const clampInt = (v: unknown, min: number, max: number, fallback: number) => {
    const n = Math.round(Number(v));
    return Number.isFinite(n) ? Math.min(max, Math.max(min, n)) : fallback;
  };
  const optCents = (v: unknown): number | null => {
    const n = Math.round(Number(v));
    return Number.isFinite(n) && n > 0 ? Math.min(n, 100_000_000) : null;
  };

  // Resolve the account username for display.
  const profRows = await supabaseSelect(
    env,
    `/whisper_profiles?user_id=eq.${encodeURIComponent(user.userId)}&select=username&limit=1`
  );
  const username =
    (profRows?.[0] as { username?: string } | undefined)?.username ?? null;

  // Changing the Instagram handle invalidates any previous Ember check.
  const instagram = cleanInstagramHandle(body.instagram);
  const existingBrand = (await getBrandRow(env, user.userId)) as
    | (BrandRow & { instagram?: string | null })
    | null;
  const instagramChanged = (existingBrand?.instagram ?? null) !== instagram;

  const row: Record<string, unknown> = {
    user_id: user.userId,
    company_name: companyName,
    username,
    website: String(body.website ?? "").trim().slice(0, 200) || null,
    industry: String(body.industry ?? "").trim().slice(0, 80) || null,
    about: String(body.about ?? "").trim().slice(0, 2000) || null,
    logo_url: String(body.logoUrl ?? "").trim().slice(0, 500) || null,
    cover_url: String(body.coverUrl ?? "").trim().slice(0, 500) || null,
    video_url: String(body.videoUrl ?? "").trim().slice(0, 500) || null,
    media_urls: cleanStrings(body.mediaUrls).slice(0, 12),
    instagram,
    ...(instagramChanged
      ? {
          ember_verified: false,
          ember_score: null,
          ember_summary: null,
          ember_checked_at: null,
        }
      : {}),
    amenities: cleanStrings(body.amenities),
    min_followers: clampInt(body.minFollowers, 0, 100_000_000, 0),
    min_age: clampInt(body.minAge, 13, 99, 18),
    min_posts: clampInt(body.minPosts, 0, 100_000, 0),
    pay_basis: parseBasis(body.payBasis) ?? "per_post",
    typical_pay_min_cents: optCents(body.typicalPayMinCents),
    typical_pay_max_cents: optCents(body.typicalPayMaxCents),
    payment_terms: String(body.paymentTerms ?? "").trim().slice(0, 2000) || null,
    published: body.published !== false,
    updated_at: new Date().toISOString(),
  };

  const upsertPath = "/whisper_brand_profiles?on_conflict=user_id";
  const upsertInit = {
    method: "POST",
    prefer: "resolution=merge-duplicates",
    body: row,
  } as const;

  let upserted = await supabaseAdmin(env, upsertPath, upsertInit);

  // If the full payload fails, the live DB may be missing the v3 media columns
  // (cover_url / media_urls / video_url) — the migration hasn't been applied
  // yet. Retry with a stripped payload so the rest of the profile (company,
  // requirements, pay, amenities) still saves instead of failing entirely.
  // The media fields persist as soon as `supabase/brand-media-columns.sql` is
  // run in the Supabase dashboard.
  if (!upserted.ok) {
    const stripped: Record<string, unknown> = { ...row };
    delete stripped.cover_url;
    delete stripped.media_urls;
    delete stripped.video_url;
    upserted = await supabaseAdmin(env, upsertPath, {
      method: "POST",
      prefer: "resolution=merge-duplicates",
      body: stripped,
    });
    if (!upserted.ok) {
      console.error("Brand profile save failed even without media columns", {
        company: companyName,
      });
      return json({ error: "save_failed" }, 502);
    }
    console.warn(
      "Brand profile saved without media columns — run supabase/brand-media-columns.sql to enable cover/gallery/video uploads.",
      { company: companyName }
    );
    return json({ ok: true, userId: user.userId, mediaPending: true });
  }

  console.log("Brand profile saved", { company: companyName });
  return json({ ok: true, userId: user.userId });
}

/**
 * POST /brand/verify — store the Ember Instagram verification result for the
 * caller's own brand. The AI check itself runs on the client (same toolkit
 * proxy every other Ember feature uses); this endpoint persists the verdict.
 */
async function handleBrandVerifySave(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: {
    instagram?: string;
    verified?: boolean;
    score?: number;
    summary?: string;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const brand = await getBrandRow(env, user.userId);
  if (!brand) return json({ error: "brand_not_found" }, 404);

  const instagram = cleanInstagramHandle(body.instagram);
  if (!instagram) return json({ error: "invalid_instagram" }, 400);

  const rawScore = Math.round(Number(body.score));
  const score = Number.isFinite(rawScore)
    ? Math.min(100, Math.max(0, rawScore))
    : 0;

  const updated = await supabaseAdmin(
    env,
    `/whisper_brand_profiles?user_id=eq.${encodeURIComponent(user.userId)}`,
    {
      method: "PATCH",
      body: {
        instagram,
        ember_verified: body.verified === true,
        ember_score: score,
        ember_summary:
          String(body.summary ?? "").trim().slice(0, 1200) || null,
        ember_checked_at: new Date().toISOString(),
        updated_at: new Date().toISOString(),
      },
    }
  );
  if (!updated.ok) return json({ error: "save_failed" }, 502);

  console.log("Brand Ember verification saved", {
    instagram,
    verified: body.verified === true,
    score,
  });
  return json({ ok: true, verified: body.verified === true, score });
}

/** GET /brands — public directory of published brands. */
async function handleBrandsList(_request: Request, env: Env): Promise<Response> {
  const rows = await supabaseSelect(
    env,
    `/whisper_brand_profiles?published=eq.true&select=${BRAND_COLUMNS}&order=created_at.desc&limit=100`
  );
  if (rows === null) return json({ error: "load_failed" }, 502);
  return json({ brands: rows });
}

/**
 * GET /brand/profile?userId=… — one brand profile. Unpublished profiles are
 * only visible to their owner (when an auth token is provided).
 */
async function handleBrandGet(request: Request, env: Env): Promise<Response> {
  const userId = new URL(request.url).searchParams.get("userId") ?? "";
  if (!userId) return json({ error: "missing_user" }, 400);

  const row = await getBrandRow(env, userId);
  if (!row) return json({ brand: null });

  if (row.published !== true) {
    const user = await requireUser(request, env);
    if (user instanceof Response || user.userId !== userId) {
      return json({ brand: null });
    }
  }
  return json({ brand: row });
}

interface EligibilityResult {
  eligible: boolean;
  blocked: boolean;
  followers: number;
  posts: number;
  minFollowers: number;
  minAge: number;
  minPosts: number;
  reasons: string[];
}

async function computeEligibility(
  env: Env,
  brand: BrandRow,
  creatorUserId: string
): Promise<EligibilityResult> {
  const uid = encodeURIComponent(creatorUserId);
  const bid = encodeURIComponent(brand.user_id);
  const [followers, posts, deniedRows, blockRows] = await Promise.all([
    supabaseCount(env, `/whisper_follows?followee_id=eq.${uid}&select=follower_id`),
    supabaseCount(env, `/whisper_posts?user_id=eq.${uid}&select=id`),
    supabaseSelect(
      env,
      `/whisper_sponsorship_applications?brand_user_id=eq.${bid}&creator_user_id=eq.${uid}&status=eq.denied&select=id&limit=1`
    ),
    supabaseSelect(
      env,
      `/whisper_dm_blocks?blocked_sender_id=eq.${bid}&protected_user_id=eq.${uid}&select=id&limit=1`
    ),
  ]);

  const blocked =
    (Array.isArray(deniedRows) && deniedRows.length > 0) ||
    (Array.isArray(blockRows) && blockRows.length > 0);

  const reasons: string[] = [];
  if (followers < brand.min_followers) {
    reasons.push(
      `You need at least ${brand.min_followers.toLocaleString()} followers (you have ${followers.toLocaleString()}).`
    );
  }
  if (posts < brand.min_posts) {
    reasons.push(
      `You need at least ${brand.min_posts} posts (you have ${posts}).`
    );
  }
  if (blocked) {
    reasons.push("This brand has already reviewed and declined an application from you.");
  }

  return {
    eligible: reasons.length === 0,
    blocked,
    followers,
    posts,
    minFollowers: brand.min_followers,
    minAge: brand.min_age,
    minPosts: brand.min_posts,
    reasons,
  };
}

/** GET /brand/eligibility?brandUserId=… — can the caller apply? */
async function handleBrandEligibility(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  const brandUserId =
    new URL(request.url).searchParams.get("brandUserId") ?? "";
  if (!brandUserId) return json({ error: "missing_brand" }, 400);
  const brand = (await getBrandRow(env, brandUserId)) as BrandRow | null;
  if (!brand || brand.published !== true) {
    return json({ error: "brand_not_found" }, 404);
  }
  if (brandUserId === user.userId) {
    return json({ error: "cannot_apply_to_self" }, 400);
  }

  const result = await computeEligibility(env, brand, user.userId);
  return json(result);
}

/** POST /brand/apply — a creator applies for sponsorship. */
async function handleBrandApply(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: {
    brandUserId?: string;
    basis?: string;
    amountCents?: number;
    message?: string;
    age?: number;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const brandUserId = (body.brandUserId ?? "").trim();
  const basis = parseBasis(body.basis);
  const amountCents = Math.round(Number(body.amountCents));
  const age = Math.round(Number(body.age));
  if (!brandUserId || !basis) return json({ error: "invalid_body" }, 400);
  if (!Number.isFinite(amountCents) || amountCents < 100 || amountCents > 100_000_000) {
    return json({ error: "invalid_amount" }, 400);
  }
  if (brandUserId === user.userId) {
    return json({ error: "cannot_apply_to_self" }, 400);
  }

  const brand = (await getBrandRow(env, brandUserId)) as BrandRow | null;
  if (!brand || brand.published !== true) {
    return json({ error: "brand_not_found" }, 404);
  }

  if (!Number.isFinite(age) || age < brand.min_age) {
    return json({ error: "age_requirement", minAge: brand.min_age }, 400);
  }

  const eligibility = await computeEligibility(env, brand, user.userId);
  if (!eligibility.eligible) {
    return json({ error: "not_eligible", reasons: eligibility.reasons }, 403);
  }

  // One live application per brand/creator pair.
  const existing = await supabaseSelect(
    env,
    `/whisper_sponsorship_applications?brand_user_id=eq.${encodeURIComponent(
      brandUserId
    )}&creator_user_id=eq.${encodeURIComponent(
      user.userId
    )}&status=in.(pending,countered,accepted)&select=id&limit=1`
  );
  if (Array.isArray(existing) && existing.length > 0) {
    return json({ error: "already_applied" }, 409);
  }

  const profRows = await supabaseSelect(
    env,
    `/whisper_profiles?user_id=eq.${encodeURIComponent(user.userId)}&select=username&limit=1`
  );
  const creatorUsername =
    (profRows?.[0] as { username?: string } | undefined)?.username ?? null;

  const id = crypto.randomUUID();
  const inserted = await supabaseAdmin(env, "/whisper_sponsorship_applications", {
    method: "POST",
    body: {
      id,
      brand_user_id: brandUserId,
      brand_company: brand.company_name,
      creator_user_id: user.userId,
      creator_username: creatorUsername,
      creator_age: age,
      creator_followers: eligibility.followers,
      desired_basis: basis,
      desired_amount_cents: amountCents,
      message: String(body.message ?? "").trim().slice(0, 2000) || null,
      terms_basis: basis,
      terms_amount_cents: amountCents,
      status: "pending",
    },
  });
  if (!inserted.ok) return json({ error: "save_failed" }, 502);

  console.log("Sponsorship application created", { brand: brand.company_name });
  return json({ ok: true, id });
}

const SPONSOR_APP_COLUMNS =
  "id,brand_user_id,brand_company,creator_user_id,creator_username,creator_age,creator_followers,desired_basis,desired_amount_cents,message,terms_basis,terms_amount_cents,terms_notes,terms_deliverables,terms_exclusive,terms_expires_at,status,created_at,updated_at";

/** GET /sponsorship/applications — caller's applications, both roles. */
async function handleSponsorshipApplications(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const uid = encodeURIComponent(user.userId);

  const [asBrand, asCreator] = await Promise.all([
    supabaseSelect(
      env,
      `/whisper_sponsorship_applications?brand_user_id=eq.${uid}&select=${SPONSOR_APP_COLUMNS}&order=created_at.desc&limit=100`
    ),
    supabaseSelect(
      env,
      `/whisper_sponsorship_applications?creator_user_id=eq.${uid}&select=${SPONSOR_APP_COLUMNS}&order=created_at.desc&limit=100`
    ),
  ]);
  return json({ asBrand: asBrand ?? [], asCreator: asCreator ?? [] });
}

interface SponsorAppRow {
  id: string;
  brand_user_id: string;
  brand_company: string | null;
  creator_user_id: string;
  creator_username: string | null;
  desired_basis: string;
  desired_amount_cents: number;
  terms_basis: string | null;
  terms_amount_cents: number | null;
  terms_notes: string | null;
  terms_deliverables: string | null;
  terms_exclusive: boolean | null;
  terms_expires_at: string | null;
  status: string;
}

async function getSponsorApp(
  env: Env,
  id: string
): Promise<SponsorAppRow | null> {
  const rows = await supabaseSelect(
    env,
    `/whisper_sponsorship_applications?id=eq.${encodeURIComponent(id)}&select=${SPONSOR_APP_COLUMNS}&limit=1`
  );
  return (rows?.[0] as SponsorAppRow | undefined) ?? null;
}

/** Create a deal from an accepted application. Returns the deal id. */
async function createDealFromApp(
  env: Env,
  app: SponsorAppRow,
  basis: SponsorBasis,
  amountCents: number,
  notes: string | null,
  deliverables: string | null,
  exclusive: boolean
): Promise<string | null> {
  const dealId = crypto.randomUUID();
  const inserted = await supabaseAdmin(env, "/whisper_sponsorship_deals", {
    method: "POST",
    body: {
      id: dealId,
      application_id: app.id,
      brand_user_id: app.brand_user_id,
      brand_company: app.brand_company,
      creator_user_id: app.creator_user_id,
      creator_username: app.creator_username,
      basis,
      amount_cents: amountCents,
      notes,
      deliverables,
      exclusive,
      status: "active",
    },
  });
  return inserted.ok ? dealId : null;
}

/**
 * POST /sponsorship/respond — the BRAND accepts, denies, or counters an
 * application. Countering updates the standing terms (editable form).
 * Denying also DM-blocks the brand from messaging the creator.
 */
async function handleSponsorshipRespond(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: {
    id?: string;
    action?: string;
    termsBasis?: string;
    termsAmountCents?: number;
    termsNotes?: string;
    termsDeliverables?: string;
    termsExclusive?: boolean;
    expiresInDays?: number;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const id = (body.id ?? "").trim();
  const action = body.action;
  if (!id || !action || !["accept", "deny", "counter"].includes(action)) {
    return json({ error: "invalid_body" }, 400);
  }

  const app = await getSponsorApp(env, id);
  if (!app) return json({ error: "not_found" }, 404);
  if (app.brand_user_id !== user.userId) return json({ error: "forbidden" }, 403);
  if (!["pending", "countered"].includes(app.status)) {
    return json({ error: "already_decided" }, 409);
  }

  const patch = (fields: Record<string, unknown>) =>
    supabaseAdmin(
      env,
      `/whisper_sponsorship_applications?id=eq.${encodeURIComponent(id)}`,
      {
        method: "PATCH",
        body: { ...fields, updated_at: new Date().toISOString() },
      }
    );

  if (action === "deny") {
    const updated = await patch({ status: "denied" });
    if (!updated.ok) return json({ error: "update_failed" }, 502);
    // Scam protection: the denying brand can no longer DM this creator.
    await supabaseAdmin(
      env,
      "/whisper_dm_blocks?on_conflict=blocked_sender_id,protected_user_id",
      {
        method: "POST",
        prefer: "resolution=ignore-duplicates",
        body: {
          blocked_sender_id: app.brand_user_id,
          protected_user_id: app.creator_user_id,
          reason: "sponsorship_denied",
        },
      }
    );
    console.log("Sponsorship denied + DM block added");
    return json({ ok: true, status: "denied" });
  }

  const basis =
    parseBasis(body.termsBasis) ??
    parseBasis(app.terms_basis) ??
    parseBasis(app.desired_basis) ??
    "per_post";
  const rawAmount = Math.round(Number(body.termsAmountCents));
  const amountCents =
    Number.isFinite(rawAmount) && rawAmount >= 100 && rawAmount <= 100_000_000
      ? rawAmount
      : app.terms_amount_cents ?? app.desired_amount_cents;
  const notes = String(body.termsNotes ?? app.terms_notes ?? "").trim().slice(0, 2000) || null;
  const deliverables =
    String(body.termsDeliverables ?? app.terms_deliverables ?? "")
      .trim()
      .slice(0, 2000) || null;
  const exclusive =
    typeof body.termsExclusive === "boolean"
      ? body.termsExclusive
      : app.terms_exclusive === true;
  const expiresDays = Math.round(Number(body.expiresInDays));
  const expiresAt =
    Number.isFinite(expiresDays) && expiresDays > 0 && expiresDays <= 90
      ? new Date(Date.now() + expiresDays * 86_400_000).toISOString()
      : null;

  if (action === "counter") {
    const updated = await patch({
      status: "countered",
      terms_basis: basis,
      terms_amount_cents: amountCents,
      terms_notes: notes,
      terms_deliverables: deliverables,
      terms_exclusive: exclusive,
      terms_expires_at: expiresAt,
    });
    if (!updated.ok) return json({ error: "update_failed" }, 502);
    return json({ ok: true, status: "countered" });
  }

  // Accept.
  const dealId = await createDealFromApp(
    env,
    app,
    basis,
    amountCents,
    notes,
    deliverables,
    exclusive
  );
  if (!dealId) return json({ error: "save_failed" }, 502);
  const updated = await patch({
    status: "accepted",
    terms_basis: basis,
    terms_amount_cents: amountCents,
    terms_notes: notes,
    terms_deliverables: deliverables,
    terms_exclusive: exclusive,
  });
  if (!updated.ok) return json({ error: "update_failed" }, 502);
  console.log("Sponsorship accepted", { dealId });
  return json({ ok: true, status: "accepted", dealId });
}

/**
 * POST /sponsorship/creator-respond — the CREATOR accepts a counter-offer
 * (creating the deal) or withdraws their application.
 */
async function handleSponsorshipCreatorRespond(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: { id?: string; action?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const id = (body.id ?? "").trim();
  const action = body.action;
  if (!id || !action || !["accept", "withdraw"].includes(action)) {
    return json({ error: "invalid_body" }, 400);
  }

  const app = await getSponsorApp(env, id);
  if (!app) return json({ error: "not_found" }, 404);
  if (app.creator_user_id !== user.userId) return json({ error: "forbidden" }, 403);

  const patch = (fields: Record<string, unknown>) =>
    supabaseAdmin(
      env,
      `/whisper_sponsorship_applications?id=eq.${encodeURIComponent(id)}`,
      {
        method: "PATCH",
        body: { ...fields, updated_at: new Date().toISOString() },
      }
    );

  if (action === "withdraw") {
    if (!["pending", "countered"].includes(app.status)) {
      return json({ error: "already_decided" }, 409);
    }
    const updated = await patch({ status: "withdrawn" });
    if (!updated.ok) return json({ error: "update_failed" }, 502);
    return json({ ok: true, status: "withdrawn" });
  }

  // Accept — only valid for a brand counter-offer that hasn't expired.
  if (app.status !== "countered") {
    return json({ error: "nothing_to_accept" }, 409);
  }
  if (
    app.terms_expires_at &&
    Date.parse(app.terms_expires_at) < Date.now()
  ) {
    return json({ error: "offer_expired" }, 409);
  }
  const basis = parseBasis(app.terms_basis) ?? "per_post";
  const amountCents = app.terms_amount_cents ?? app.desired_amount_cents;
  const dealId = await createDealFromApp(
    env,
    app,
    basis,
    amountCents,
    app.terms_notes,
    app.terms_deliverables,
    app.terms_exclusive === true
  );
  if (!dealId) return json({ error: "save_failed" }, 502);
  const updated = await patch({ status: "accepted" });
  if (!updated.ok) return json({ error: "update_failed" }, 502);
  return json({ ok: true, status: "accepted", dealId });
}

interface SponsorPaymentRow {
  id: string;
  deal_id: string;
  creator_user_id: string | null;
  net_cents: number;
  status: string;
  requires_post: boolean;
  hold_until: string | null;
  created_at: string;
}

/**
 * Transfer a pending payment's net amount to the creator's linked bank
 * (Stripe Connect). Silently stays pending when the creator hasn't linked
 * a payout account yet.
 */
async function releaseSponsorPayment(
  env: Env,
  payment: SponsorPaymentRow
): Promise<boolean> {
  if (!env.STRIPE_SECRET_KEY || !payment.creator_user_id) return false;
  const connect = await getConnectRow(env, payment.creator_user_id);
  if (!connect?.payouts_enabled) return false;

  const params = new URLSearchParams();
  params.set("amount", String(payment.net_cents));
  params.set("currency", "usd");
  params.set("destination", connect.stripe_account_id);
  params.set("metadata[kind]", "sponsorship");
  params.set("metadata[paymentId]", payment.id);
  const transfer = await stripeRequest(env, "/transfers", params);
  if (!transfer.ok || typeof transfer.data.id !== "string") {
    const err = transfer.data.error as { message?: string } | undefined;
    console.error("Sponsorship transfer failed", { error: err?.message });
    if (isMissingAccountError(transfer)) {
      // Stale test-mode payout account — reset it so the creator can
      // reconnect; the payment stays pending and releases after that.
      await clearStaleConnect(
        env,
        payment.creator_user_id,
        connect.stripe_account_id
      );
    }
    return false;
  }

  await supabaseAdmin(
    env,
    `/whisper_sponsorship_payments?id=eq.${encodeURIComponent(payment.id)}`,
    {
      method: "PATCH",
      body: {
        status: "released",
        stripe_transfer_id: transfer.data.id,
        released_at: new Date().toISOString(),
      },
    }
  );
  console.log("Sponsorship payment released", { net: payment.net_cents });
  return true;
}

/**
 * Lazy escrow sweep for a set of deals: releases time-based payments whose
 * hold has passed, and per-post payments backed by enough tracked posts.
 */
async function releaseDuePayments(
  env: Env,
  dealIds: string[]
): Promise<void> {
  if (dealIds.length === 0) return;
  const idList = dealIds.map((d) => encodeURIComponent(d)).join(",");
  const [paymentsRaw, postsRaw] = await Promise.all([
    supabaseSelect(
      env,
      `/whisper_sponsorship_payments?deal_id=in.(${idList})&select=id,deal_id,creator_user_id,net_cents,status,requires_post,hold_until,created_at&order=created_at.asc&limit=500`
    ),
    supabaseSelect(
      env,
      `/whisper_sponsorship_posts?deal_id=in.(${idList})&select=deal_id&limit=1000`
    ),
  ]);
  const payments = (paymentsRaw ?? []) as SponsorPaymentRow[];
  const postCountByDeal = new Map<string, number>();
  for (const p of (postsRaw ?? []) as { deal_id?: string }[]) {
    if (!p.deal_id) continue;
    postCountByDeal.set(p.deal_id, (postCountByDeal.get(p.deal_id) ?? 0) + 1);
  }

  const now = Date.now();
  // Per-post budgeting: each tracked post releases one payment (oldest first).
  const consumedByDeal = new Map<string, number>();
  for (const payment of payments) {
    if (payment.status !== "pending") {
      if (payment.requires_post && payment.status === "released") {
        consumedByDeal.set(
          payment.deal_id,
          (consumedByDeal.get(payment.deal_id) ?? 0) + 1
        );
      }
      continue;
    }
    if (payment.requires_post) {
      const available =
        (postCountByDeal.get(payment.deal_id) ?? 0) -
        (consumedByDeal.get(payment.deal_id) ?? 0);
      if (available > 0) {
        const ok = await releaseSponsorPayment(env, payment);
        if (ok) {
          consumedByDeal.set(
            payment.deal_id,
            (consumedByDeal.get(payment.deal_id) ?? 0) + 1
          );
        }
      }
    } else if (payment.hold_until && Date.parse(payment.hold_until) <= now) {
      await releaseSponsorPayment(env, payment);
    }
  }
}

/** GET /sponsorship/deals — caller's deals with posts + payment ledger. */
async function handleSponsorshipDeals(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const uid = encodeURIComponent(user.userId);

  const dealsRaw = await supabaseSelect(
    env,
    `/whisper_sponsorship_deals?or=(brand_user_id.eq.${uid},creator_user_id.eq.${uid})&select=id,application_id,brand_user_id,brand_company,creator_user_id,creator_username,basis,amount_cents,notes,deliverables,exclusive,status,created_at&order=created_at.desc&limit=100`
  );
  const deals = (dealsRaw ?? []) as { id: string }[];
  const dealIds = deals.map((d) => d.id);

  // Escrow sweep before reporting balances so the ledger is fresh.
  await releaseDuePayments(env, dealIds);

  let payments: unknown[] = [];
  let posts: unknown[] = [];
  if (dealIds.length > 0) {
    const idList = dealIds.map((d) => encodeURIComponent(d)).join(",");
    const [paymentsRaw, postsRaw] = await Promise.all([
      supabaseSelect(
        env,
        `/whisper_sponsorship_payments?deal_id=in.(${idList})&select=id,deal_id,gross_cents,fee_cents,net_cents,status,requires_post,hold_until,released_at,created_at&order=created_at.desc&limit=300`
      ),
      supabaseSelect(
        env,
        `/whisper_sponsorship_posts?deal_id=in.(${idList})&select=id,deal_id,post_id,likes_count,comments_count,created_at&order=created_at.desc&limit=300`
      ),
    ]);
    payments = paymentsRaw ?? [];
    posts = postsRaw ?? [];
  }

  return json({ deals: dealsRaw ?? [], payments, posts });
}

/**
 * POST /sponsorship/fund — the brand funds the next payment for a deal via
 * Stripe Checkout. The money lands on the platform account and is recorded
 * as a PENDING payment that only releases to the creator once obligations
 * are met (tracked post for per-post deals, end-of-week hold otherwise).
 */
async function handleSponsorshipFund(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) return json({ error: "billing_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: { dealId?: string; origin?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const dealId = (body.dealId ?? "").trim();
  if (!dealId) return json({ error: "invalid_body" }, 400);

  const rows = await supabaseSelect(
    env,
    `/whisper_sponsorship_deals?id=eq.${encodeURIComponent(dealId)}&select=id,brand_user_id,creator_user_id,creator_username,basis,amount_cents,status&limit=1`
  );
  const deal = rows?.[0] as
    | {
        id: string;
        brand_user_id: string;
        creator_user_id: string;
        creator_username: string | null;
        basis: string;
        amount_cents: number;
        status: string;
      }
    | undefined;
  if (!deal) return json({ error: "not_found" }, 404);
  if (deal.brand_user_id !== user.userId) return json({ error: "forbidden" }, 403);
  if (deal.status !== "active") return json({ error: "deal_not_active" }, 409);

  let origin: URL;
  try {
    origin = new URL(body.origin ?? "");
  } catch {
    origin = new URL(SITE_URL);
  }

  const basisLabel =
    deal.basis === "per_post"
      ? "per post"
      : deal.basis === "per_month"
        ? "monthly"
        : "yearly";
  const params = new URLSearchParams();
  params.set("mode", "payment");
  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", "usd");
  params.set("line_items[0][price_data][unit_amount]", String(deal.amount_cents));
  params.set(
    "line_items[0][price_data][product_data][name]",
    `Sponsorship — @${deal.creator_username ?? "creator"} (${basisLabel})`
  );
  params.set("success_url", `${origin.origin}/brand/dashboard?funded=1`);
  params.set("cancel_url", `${origin.origin}/brand/dashboard`);
  params.set("metadata[kind]", "sponsorship");
  params.set("metadata[dealId]", deal.id);
  params.set("metadata[basis]", deal.basis);
  params.set("metadata[brandUserId]", deal.brand_user_id);
  params.set("metadata[creatorUserId]", deal.creator_user_id);
  if (user.email) params.set("customer_email", user.email);

  const session = await stripeRequest(env, "/checkout/sessions", params);
  if (!session.ok || typeof session.data.url !== "string") {
    const err = session.data.error as { message?: string } | undefined;
    console.error("Sponsorship fund checkout failed", { error: err?.message });
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  return json({ url: session.data.url });
}

/**
 * POST /sponsorship/track-post — the creator links one of their posts to a
 * deal (fulfilling their obligation). Per-post deals release a pending
 * payment immediately.
 */
async function handleSponsorshipTrackPost(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: { dealId?: string; postId?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const dealId = (body.dealId ?? "").trim();
  const postId = (body.postId ?? "").trim();
  if (!dealId || !postId) return json({ error: "invalid_body" }, 400);

  const rows = await supabaseSelect(
    env,
    `/whisper_sponsorship_deals?id=eq.${encodeURIComponent(dealId)}&select=id,brand_user_id,creator_user_id,basis,status&limit=1`
  );
  const deal = rows?.[0] as
    | { id: string; brand_user_id: string; creator_user_id: string; basis: string; status: string }
    | undefined;
  if (!deal) return json({ error: "not_found" }, 404);
  if (deal.creator_user_id !== user.userId) return json({ error: "forbidden" }, 403);
  if (deal.status !== "active") return json({ error: "deal_not_active" }, 409);

  // The post must belong to the creator.
  const postRows = await supabaseSelect(
    env,
    `/whisper_posts?id=eq.${encodeURIComponent(postId)}&select=id,user_id&limit=1`
  );
  const post = postRows?.[0] as { user_id?: string } | undefined;
  if (!post || post.user_id !== user.userId) {
    return json({ error: "post_not_found" }, 404);
  }

  // Snapshot verified reach metrics so the brand sees real engagement.
  const pid = encodeURIComponent(postId);
  const [likesCount, commentsCount] = await Promise.all([
    supabaseCount(env, `/whisper_post_likes?post_id=eq.${pid}&select=post_id`),
    supabaseCount(
      env,
      `/whisper_post_comments?post_id=eq.${pid}&select=post_id`
    ),
  ]);

  const inserted = await supabaseAdmin(
    env,
    "/whisper_sponsorship_posts?on_conflict=deal_id,post_id",
    {
      method: "POST",
      prefer: "resolution=ignore-duplicates",
      body: {
        deal_id: dealId,
        post_id: postId,
        creator_user_id: deal.creator_user_id,
        brand_user_id: deal.brand_user_id,
        likes_count: likesCount,
        comments_count: commentsCount,
      },
    }
  );
  if (!inserted.ok) return json({ error: "save_failed" }, 502);

  // Per-post deals: try to release a payment right away.
  await releaseDuePayments(env, [dealId]);

  console.log("Sponsorship post tracked", { deal: dealId });
  return json({ ok: true });
}

/**
 * POST /sponsorship/dispute — the BRAND disputes a still-pending escrow
 * payment (creator didn't deliver). Refunds the Stripe charge and marks the
 * ledger entry refunded so the money never reaches the creator.
 */
async function handleSponsorshipDispute(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: { paymentId?: string; reason?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const paymentId = (body.paymentId ?? "").trim();
  if (!paymentId) return json({ error: "invalid_body" }, 400);

  const rows = await supabaseSelect(
    env,
    `/whisper_sponsorship_payments?id=eq.${encodeURIComponent(paymentId)}&select=id,deal_id,brand_user_id,status,stripe_session_id,stripe_payment_intent&limit=1`
  );
  const payment = rows?.[0] as
    | {
        id: string;
        deal_id: string;
        brand_user_id: string | null;
        status: string;
        stripe_session_id: string | null;
        stripe_payment_intent: string | null;
      }
    | undefined;
  if (!payment) return json({ error: "not_found" }, 404);
  if (payment.brand_user_id !== user.userId) {
    return json({ error: "forbidden" }, 403);
  }
  if (payment.status !== "pending") {
    return json({ error: "already_released" }, 409);
  }

  // Resolve the payment intent (older rows only stored the session id).
  let paymentIntent = payment.stripe_payment_intent;
  if (!paymentIntent && payment.stripe_session_id && env.STRIPE_SECRET_KEY) {
    const session = await stripeRequest(
      env,
      `/checkout/sessions/${encodeURIComponent(payment.stripe_session_id)}`
    );
    if (session.ok && typeof session.data.payment_intent === "string") {
      paymentIntent = session.data.payment_intent;
    }
  }

  let refundId: string | null = null;
  if (paymentIntent && env.STRIPE_SECRET_KEY) {
    const params = new URLSearchParams();
    params.set("payment_intent", paymentIntent);
    params.set("metadata[kind]", "sponsorship-dispute");
    params.set("metadata[paymentId]", payment.id);
    const refund = await stripeRequest(env, "/refunds", params);
    if (!refund.ok || typeof refund.data.id !== "string") {
      const err = refund.data.error as { message?: string } | undefined;
      console.error("Sponsorship refund failed", { error: err?.message });
      return json(
        { error: "stripe_error", stripeMessage: err?.message ?? null },
        502
      );
    }
    refundId = refund.data.id;
  }

  const updated = await supabaseAdmin(
    env,
    `/whisper_sponsorship_payments?id=eq.${encodeURIComponent(payment.id)}`,
    {
      method: "PATCH",
      body: {
        status: "refunded",
        dispute_reason:
          String(body.reason ?? "").trim().slice(0, 1000) || null,
        refunded_at: new Date().toISOString(),
        stripe_refund_id: refundId,
      },
    }
  );
  if (!updated.ok) return json({ error: "update_failed" }, 502);

  console.log("Sponsorship payment disputed + refunded", {
    payment: payment.id,
  });
  return json({ ok: true, refunded: refundId !== null });
}

/**
 * GET /creator/earnings — the creator/athlete payment gateway: escrow
 * totals (pending / released / refunded), the full ledger, and payout
 * account status. Mirrors what coaches get from /coach/earnings.
 */
async function handleCreatorEarnings(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const uid = encodeURIComponent(user.userId);

  const dealsRaw = await supabaseSelect(
    env,
    `/whisper_sponsorship_deals?creator_user_id=eq.${uid}&select=id,brand_company,basis,amount_cents,status,created_at&order=created_at.desc&limit=100`
  );
  const deals = (dealsRaw ?? []) as { id: string }[];

  // Sweep escrow before reporting so due money shows as released.
  await releaseDuePayments(
    env,
    deals.map((d) => d.id)
  );

  const [paymentsRaw, connect] = await Promise.all([
    supabaseSelect(
      env,
      `/whisper_sponsorship_payments?creator_user_id=eq.${uid}&select=id,deal_id,gross_cents,fee_cents,net_cents,status,requires_post,hold_until,released_at,created_at&order=created_at.desc&limit=200`
    ),
    getConnectRow(env, user.userId),
  ]);
  const payments = (paymentsRaw ?? []) as {
    net_cents: number;
    status: string;
  }[];

  const sum = (status: string) =>
    payments
      .filter((p) => p.status === status)
      .reduce((s, p) => s + (p.net_cents || 0), 0);

  return json({
    pendingCents: sum("pending"),
    releasedCents: sum("released"),
    refundedCents: sum("refunded"),
    payoutsEnabled: connect?.payouts_enabled === true,
    payments: paymentsRaw ?? [],
    deals: dealsRaw ?? [],
  });
}

// ---------------------------------------------------------------------------
// Checkout
// ---------------------------------------------------------------------------

/**
 * Fulfill a completed Checkout Session: record the membership, flip the
 * profile flag, and send the welcome email. Idempotent — the email only goes
 * out the first time we see this subscription, so it's safe to call from
 * both the webhook AND the success-page verification (the fallback path that
 * covers a missing/misconfigured Stripe webhook).
 */
// ---------------------------------------------------------------------------
// Receipts — one ledger row per successful charge (whisper_receipts).
//
// Written by the Stripe webhook on checkout completion AND on every renewal
// invoice, marked refunded by both refund paths, listed by
// GET /billing/receipts (user) and GET /admin/receipts (console), and
// refundable directly via POST /admin/refunds/direct. Buyers also get a
// branded receipt email. Migration: supabase/receipts.sql (safe to re-run).
// ---------------------------------------------------------------------------

interface ReceiptInput {
  userId: string | null;
  email: string | null;
  /** one | badge | coach-hire | program | sponsorship */
  kind: string;
  description: string;
  amountCents: number;
  sessionId?: string | null;
  invoiceId?: string | null;
  paymentIntent?: string | null;
  subscriptionId?: string | null;
  coachUserId?: string | null;
}

const RECEIPT_KIND_LABELS: Record<string, string> = {
  one: "Whisper One",
  badge: "Verified badge",
  "coach-hire": "Coaching",
  program: "Training program",
  sponsorship: "Sponsorship escrow",
  "ad-credits": "Whisper Ads credit",
  "gift-credits": "Live gift credits",
};

function receiptNumber(): string {
  const rand = crypto.randomUUID().replace(/-/g, "").slice(0, 8).toUpperCase();
  return `WSP-${new Date().getFullYear()}-${rand}`;
}

function receiptEscape(value: string): string {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

function receiptEmail(
  receiptNo: string,
  input: ReceiptInput
): { subject: string; html: string } {
  const amount = `$${(input.amountCents / 100).toFixed(2)}`;
  const label = RECEIPT_KIND_LABELS[input.kind] ?? "Purchase";
  const dateLine = new Date().toLocaleDateString("en-US", {
    month: "long",
    day: "numeric",
    year: "numeric",
  });
  const subject = `Your Whisper receipt — ${amount}`;
  const html = `
  <div style="font-family:-apple-system,'Segoe UI',Roboto,sans-serif;background:#F5F4F0;padding:32px 16px;">
    <div style="max-width:480px;margin:0 auto;background:#ffffff;border-radius:20px;padding:28px;border:1px solid #E8E6E0;">
      <p style="margin:0;font-size:12px;letter-spacing:2px;color:#8A877E;font-weight:700;">WHISPER · RECEIPT</p>
      <h1 style="margin:10px 0 2px;font-size:28px;color:#111111;">${amount}</h1>
      <p style="margin:0;color:#6B6960;font-size:14px;">Paid · ${dateLine}</p>
      <div style="margin:20px 0;padding:14px 16px;background:#FAF9F6;border-radius:14px;border:1px solid #EFEDE7;">
        <p style="margin:0;font-weight:700;color:#111111;font-size:15px;">${receiptEscape(label)}</p>
        <p style="margin:4px 0 0;color:#6B6960;font-size:13.5px;">${receiptEscape(input.description)}</p>
      </div>
      <p style="margin:0 0 14px;color:#8A877E;font-size:12.5px;">Receipt ${receiptNo}. Track purchases or request a refund any time in Settings → Billing &amp; refunds.</p>
      <a href="https://mydailywhisper.com/settings" ${BUTTON_STYLE}>Open billing</a>
      <p style="margin:18px 0 0;color:#B5B2A8;font-size:11.5px;">Refund windows: Whisper One &amp; badges 14 days · coaching 7 days · programs 14 days — mydailywhisper.com/policies</p>
    </div>
  </div>`;
  return { subject, html };
}

/**
 * Insert one receipts-ledger row (idempotent across webhook retries) and
 * email the buyer. Never throws — a missing table or Resend hiccup can't
 * break fulfillment.
 */
async function recordReceipt(env: Env, input: ReceiptInput): Promise<void> {
  try {
    const key = env.SUPABASE_SERVICE_ROLE_KEY;
    if (!key || input.amountCents <= 0) return;
    const receiptNo = receiptNumber();
    const conflict = input.invoiceId
      ? "stripe_invoice_id"
      : "stripe_session_id";
    const res = await fetch(
      `${SUPABASE_URL}/rest/v1/whisper_receipts?on_conflict=${conflict}`,
      {
        method: "POST",
        headers: {
          apikey: key,
          Authorization: `Bearer ${key}`,
          "Content-Type": "application/json",
          Prefer: "resolution=ignore-duplicates,return=representation",
        },
        body: JSON.stringify({
          receipt_no: receiptNo,
          user_id: input.userId,
          email: input.email,
          kind: input.kind,
          description: input.description.slice(0, 300),
          amount_cents: Math.round(input.amountCents),
          currency: "usd",
          status: "paid",
          stripe_session_id: input.sessionId ?? null,
          stripe_invoice_id: input.invoiceId ?? null,
          stripe_payment_intent: input.paymentIntent ?? null,
          stripe_subscription_id: input.subscriptionId ?? null,
          coach_user_id: input.coachUserId ?? null,
          created_at: new Date().toISOString(),
        }),
      }
    );
    if (!res.ok) {
      console.error("Receipt insert failed", {
        status: res.status,
        body: (await res.text()).slice(0, 200),
      });
      return;
    }
    const rows = (await res.json().catch(() => [])) as unknown[];
    // Empty array = duplicate webhook delivery; the email already went out.
    if (!Array.isArray(rows) || rows.length === 0) return;
    if (input.email) {
      const mail = receiptEmail(receiptNo, input);
      await sendEmail(env, input.email, mail.subject, mail.html);
    }
  } catch (err) {
    console.error("Receipt record failed", String(err));
  }
}

async function fulfillCheckoutSession(
  env: Env,
  obj: Record<string, unknown>
): Promise<void> {
  const metadata = (obj.metadata ?? {}) as Record<string, string>;
  const details = (obj.customer_details ?? {}) as { email?: string | null };
  const email = details.email ?? null;
  const plan = metadata.plan || "one-monthly";
  const userId = metadata.whisperUserId || null;
  const subscriptionId =
    typeof obj.subscription === "string" ? obj.subscription : null;
  const stripeCustomerId =
    typeof obj.customer === "string" ? obj.customer : null;

  // Sponsorship escrow: record the brand's payment as PENDING. It only
  // releases to the creator after obligations are met (tracked post for
  // per-post deals, end-of-week hold otherwise).
  if (metadata.kind === "sponsorship" && metadata.dealId) {
    const gross = typeof obj.amount_total === "number" ? obj.amount_total : 0;
    if (gross <= 0) return;
    const fee = Math.round((gross * SPONSOR_PLATFORM_FEE_PERCENT) / 100);
    const requiresPost = metadata.basis === "per_post";
    await supabaseAdmin(
      env,
      "/whisper_sponsorship_payments?on_conflict=stripe_session_id",
      {
        method: "POST",
        prefer: "resolution=ignore-duplicates",
        body: {
          deal_id: metadata.dealId,
          brand_user_id: metadata.brandUserId ?? null,
          creator_user_id: metadata.creatorUserId ?? null,
          gross_cents: gross,
          fee_cents: fee,
          net_cents: gross - fee,
          status: "pending",
          requires_post: requiresPost,
          hold_until: requiresPost
            ? null
            : new Date(Date.now() + 7 * 86_400_000).toISOString(),
          stripe_session_id: typeof obj.id === "string" ? obj.id : null,
          stripe_payment_intent:
            typeof obj.payment_intent === "string" ? obj.payment_intent : null,
          created_at: new Date().toISOString(),
        },
      }
    );
    console.log("Sponsorship payment recorded (pending)", {
      deal: metadata.dealId,
      gross,
    });
    await recordReceipt(env, {
      userId: metadata.brandUserId ?? null,
      email,
      kind: "sponsorship",
      description: "Sponsorship — creator deal (held in escrow)",
      amountCents: gross,
      sessionId: typeof obj.id === "string" ? obj.id : null,
      paymentIntent:
        typeof obj.payment_intent === "string" ? obj.payment_intent : null,
    });
    return;
  }

  // Ad credits: fund the business's ad wallet — the revenue that pays
  // creators through WPP. Deduped on the session id across webhook retries.
  if (metadata.kind === "ad-credits") {
    const gross = typeof obj.amount_total === "number" ? obj.amount_total : 0;
    if (gross <= 0 || !userId) return;
    await supabaseAdmin(
      env,
      "/whisper_ad_topups?on_conflict=stripe_session_id",
      {
        method: "POST",
        prefer: "resolution=ignore-duplicates",
        body: {
          user_id: userId,
          amount_cents: gross,
          source: "purchase",
          stripe_session_id: typeof obj.id === "string" ? obj.id : null,
          created_at: new Date().toISOString(),
        },
      }
    );
    await recordReceipt(env, {
      userId,
      email,
      kind: "ad-credits",
      description: "Whisper Ads credit — funds ad delivery & the creator pool",
      amountCents: gross,
      sessionId: typeof obj.id === "string" ? obj.id : null,
      paymentIntent:
        typeof obj.payment_intent === "string" ? obj.payment_intent : null,
    });
    console.log("Ad credits funded", { gross });
    return;
  }

  // Gift credits: prepaid balance for live-room gifts. The topup INSERT is
  // strict (unique session id) — only the FIRST webhook delivery credits
  // the wallet, so retries can never double-credit.
  if (metadata.kind === "gift-credits") {
    const gross = typeof obj.amount_total === "number" ? obj.amount_total : 0;
    if (gross <= 0 || !userId) return;
    const ins = await supabaseAdmin(env, "/whisper_gift_topups", {
      method: "POST",
      body: {
        user_id: userId,
        amount_cents: gross,
        stripe_session_id: typeof obj.id === "string" ? obj.id : null,
      },
    });
    if (ins.ok) {
      const credited = await giftWalletCredit(env, userId, gross);
      if (!credited) console.error("Gift wallet credit failed", { gross });
      await recordReceipt(env, {
        userId,
        email,
        kind: "gift-credits",
        description: "Whisper gift credits — cheer creators in live rooms",
        amountCents: gross,
        sessionId: typeof obj.id === "string" ? obj.id : null,
        paymentIntent:
          typeof obj.payment_intent === "string" ? obj.payment_intent : null,
      });
      console.log("Gift credits funded", { gross });
    }
    return;
  }

  // Coach-hire payments: record the sale in the coach's earnings ledger
  // instead of the membership tables.
  if (metadata.kind === "coach-hire" && metadata.coachUserId) {
    const gross =
      typeof obj.amount_total === "number" ? obj.amount_total : 0;
    const fee = Math.round((gross * COACH_PLATFORM_FEE_PERCENT) / 100);
    await supabaseAdmin(
      env,
      "/whisper_coach_earnings?on_conflict=stripe_session_id",
      {
        method: "POST",
        prefer: "resolution=ignore-duplicates",
        body: {
          coach_user_id: metadata.coachUserId,
          client_user_id: userId,
          client_email: email,
          gross_cents: gross,
          fee_cents: fee,
          net_cents: gross - fee,
          description: metadata.tierName
            ? `Monthly coaching subscription — ${metadata.tierName}`
            : "Monthly coaching subscription",
          stripe_session_id: typeof obj.id === "string" ? obj.id : null,
          created_at: new Date().toISOString(),
        },
      }
    );
    console.log("Coach hire recorded", {
      coach: metadata.coachUserId,
      gross,
    });
    await recordReceipt(env, {
      userId,
      email,
      kind: "coach-hire",
      description: metadata.tierName
        ? `Coaching — ${metadata.tierName} (monthly)`
        : "Coaching — monthly subscription",
      amountCents: gross,
      sessionId: typeof obj.id === "string" ? obj.id : null,
      subscriptionId,
      coachUserId: metadata.coachUserId,
    });

    // Paying activates the coaching relationship: upsert the request row to
    // accepted so the pair shows up in Coach Studio / My coaches even when
    // the client paid through a shared hire link without a prior request.
    if (userId) {
      const [clientRows, coachRows] = await Promise.all([
        supabaseSelect(
          env,
          `/whisper_profiles?user_id=eq.${encodeURIComponent(userId)}&select=username&limit=1`
        ),
        supabaseSelect(
          env,
          `/whisper_profiles?user_id=eq.${encodeURIComponent(
            metadata.coachUserId
          )}&select=username&limit=1`
        ),
      ]);
      const clientUsername =
        (clientRows?.[0] as { username?: string } | undefined)?.username ??
        "client";
      const coachUsername =
        (coachRows?.[0] as { username?: string } | undefined)?.username ??
        "coach";
      await supabaseAdmin(
        env,
        "/whisper_coach_requests?on_conflict=client_user_id,coach_user_id",
        {
          method: "POST",
          prefer: "resolution=merge-duplicates",
          body: {
            client_user_id: userId,
            client_username: clientUsername,
            coach_user_id: metadata.coachUserId,
            coach_username: coachUsername,
            status: "accepted",
            updated_at: new Date().toISOString(),
          },
        }
      );
    }
    return;
  }

  // One-time program purchases: earnings ledger row with a program marker so
  // /coach/program-access can grant the buyer permanent access.
  if (metadata.kind === "program-purchase" && metadata.coachUserId) {
    const gross =
      typeof obj.amount_total === "number" ? obj.amount_total : 0;
    const fee = Math.round((gross * COACH_PLATFORM_FEE_PERCENT) / 100);
    const title = metadata.programTitle || "Training program";
    await supabaseAdmin(
      env,
      "/whisper_coach_earnings?on_conflict=stripe_session_id",
      {
        method: "POST",
        prefer: "resolution=ignore-duplicates",
        body: {
          coach_user_id: metadata.coachUserId,
          client_user_id: userId,
          client_email: email,
          gross_cents: gross,
          fee_cents: fee,
          net_cents: gross - fee,
          description: `Program: ${title} [program:${metadata.programId ?? ""}]`,
          stripe_session_id: typeof obj.id === "string" ? obj.id : null,
          created_at: new Date().toISOString(),
        },
      }
    );
    console.log("Program purchase recorded", {
      program: metadata.programId,
      coach: metadata.coachUserId,
      gross,
    });
    await recordReceipt(env, {
      userId,
      email,
      kind: "program",
      description: `Program — ${title}`,
      amountCents: gross,
      sessionId: typeof obj.id === "string" ? obj.id : null,
      paymentIntent:
        typeof obj.payment_intent === "string" ? obj.payment_intent : null,
      coachUserId: metadata.coachUserId,
    });
    return;
  }

  if (PLANS[plan]?.businessPlus) {
    const alreadyFulfilled = subscriptionId
      ? await membershipExists(env, subscriptionId, "whisper_business_plus")
      : false;

    await applyBusinessPlusMembership(env, {
      userId,
      email,
      plan,
      status: "active",
      stripeCustomerId,
      stripeSubscriptionId: subscriptionId,
    });

    await recordReceipt(env, {
      userId,
      email,
      kind: "business-plus",
      description: `Whisper Business+ — ${
        plan === "business-plus-annual" ? "annual" : "monthly"
      } plan`,
      amountCents: typeof obj.amount_total === "number" ? obj.amount_total : 0,
      sessionId: typeof obj.id === "string" ? obj.id : null,
      subscriptionId,
    });

    if (!alreadyFulfilled && email) {
      console.log("Sending Business+ welcome email", { plan });
      const html = emailShell(
        "Business+ is live on your account",
        `<p>Welcome to <strong>Whisper Business+</strong> — your team's workspace is unlocked.</p>
         <p>Open the Business Suite → Business+ to:</p>
         <ul>
           <li>Add your team and give everyone their role</li>
           <li>Publish open positions with your own application questions — Whisper auto-matches applicants to them</li>
           <li>Spin up your private HQ group and the team chat</li>
           <li>Run your internal team calendar</li>
           <li>Present your company card live inside Whisper meetings</li>
         </ul>
         <p>Refund window: 14 days. Manage or cancel anytime from Settings → Billing.</p>`
      );
      await sendEmail(env, email, "Welcome to Whisper Business+ 💼", html);
      await addMarketingContact(env, email);
    }
    return;
  }

  const badgeRole = PLANS[plan]?.badgeRole;

  if (badgeRole) {
    const alreadyFulfilled = subscriptionId
      ? await membershipExists(env, subscriptionId, "whisper_badge_members")
      : false;

    await applyBadgeMembership(env, {
      userId,
      email,
      plan,
      role: badgeRole,
      status: "active",
      stripeCustomerId,
      stripeSubscriptionId: subscriptionId,
    });

    await recordReceipt(env, {
      userId,
      email,
      kind: "badge",
      description: `Approved ${badgeRole} tools — annual`,
      amountCents: typeof obj.amount_total === "number" ? obj.amount_total : 0,
      sessionId: typeof obj.id === "string" ? obj.id : null,
      subscriptionId,
    });

    if (!alreadyFulfilled && email) {
      console.log("Sending badge welcome email", { plan, role: badgeRole });
      const mail = badgeWelcomeEmail(badgeRole);
      await sendEmail(env, email, mail.subject, mail.html);
      await addMarketingContact(env, email);
    }
    return;
  }

  const alreadyFulfilled = subscriptionId
    ? await membershipExists(env, subscriptionId)
    : false;

  await applyMembership(env, {
    userId,
    email,
    plan,
    status: "active",
    stripeCustomerId,
    stripeSubscriptionId: subscriptionId,
  });

  await recordReceipt(env, {
    userId,
    email,
    kind: "one",
    description: `Whisper One — ${
      plan === "one-annual" ? "annual" : "monthly"
    } membership`,
    amountCents: typeof obj.amount_total === "number" ? obj.amount_total : 0,
    sessionId: typeof obj.id === "string" ? obj.id : null,
    subscriptionId,
  });

  if (!alreadyFulfilled && email) {
    console.log("Sending Whisper One welcome email", { plan });
    const mail = welcomeEmail(plan);
    await sendEmail(env, email, mail.subject, mail.html);
    await addMarketingContact(env, email);
  }
}

interface CheckoutBody {
  plan?: string;
  origin?: string;
  userId?: string;
  email?: string;
  /** "embedded" returns a clientSecret; omit for hosted redirect. */
  mode?: string;
}

async function handleCheckout(request: Request, env: Env): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) {
    console.error("STRIPE_SECRET_KEY is not set in project envs");
    return json({ error: "billing_not_configured" }, 503);
  }

  let body: CheckoutBody;
  try {
    body = (await request.json()) as CheckoutBody;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }

  const plan = PLANS[body.plan ?? ""];
  if (!plan) return json({ error: "unknown_plan" }, 400);

  // Every subscription must belong to the SIGNED-IN caller — verified from
  // the Supabase token so a payer can't attribute entitlements to someone
  // else's account (live-mode hardening).
  const caller = await requireUser(request, env);
  if (caller instanceof Response) return caller;
  body.userId = caller.userId;
  if (!body.email && caller.email) body.email = caller.email;

  // Verified badges are only purchasable AFTER a human approved the
  // application — enforce server-side so the checkout URL can't be shared.
  if (plan.badgeRole) {
    const approved = await hasApprovedApplication(
      env,
      body.userId,
      plan.badgeRole
    );
    if (!approved) {
      return json({ error: "not_approved" }, 403);
    }
  }

  let origin: URL;
  try {
    origin = new URL(body.origin ?? "");
    if (origin.protocol !== "https:" && origin.protocol !== "http:") {
      throw new Error("bad protocol");
    }
  } catch {
    return json({ error: "invalid_origin" }, 400);
  }

  const embedded = body.mode === "embedded";
  const params = new URLSearchParams();
  params.set("mode", "subscription");
  // ui_mode=embedded returns a clientSecret so the web app can render
  // Stripe's checkout form inline (no redirect). The hosted redirect
  // stays as the fallback when embedded isn't requested.
  if (embedded) {
    // Stripe renamed this value on newer API versions — accounts pinned to
    // 2025+ reject "embedded" with "use embedded_page instead".
    params.set("ui_mode", "embedded_page");
    params.set("return_url", `${origin.origin}/billing/success?embedded=1&session_id={CHECKOUT_SESSION_ID}`);
  }
  params.set("line_items[0][quantity]", "1");
  params.set("line_items[0][price_data][currency]", "usd");
  params.set(
    "line_items[0][price_data][unit_amount]",
    String(plan.unitAmount)
  );
  params.set("line_items[0][price_data][recurring][interval]", plan.interval);
  params.set("line_items[0][price_data][product_data][name]", plan.name);
  if (!embedded) {
    params.set(
      "success_url",
      `${origin.origin}/billing/success?session_id={CHECKOUT_SESSION_ID}`
    );
    params.set(
      "cancel_url",
      plan.badgeRole
        ? `${origin.origin}/badge/activate?role=${plan.badgeRole}`
        : plan.businessPlus
          ? `${origin.origin}/business`
          : `${origin.origin}/one`
    );
  }
  params.set("allow_promotion_codes", "true");
  params.set("metadata[plan]", body.plan ?? "");
  if (body.userId) {
    params.set("metadata[whisperUserId]", body.userId);
    params.set("subscription_data[metadata][whisperUserId]", body.userId);
    params.set("subscription_data[metadata][plan]", body.plan ?? "");
  }
  if (body.email) params.set("customer_email", body.email);

  const session = await stripeRequest(env, "/checkout/sessions", params);
  if (embedded) {
    if (!session.ok || typeof session.data.client_secret !== "string") {
      const stripeError = session.data.error as
        | { message?: string; type?: string; code?: string }
        | undefined;
      console.error("Stripe embedded checkout session creation failed", {
        status: session.status,
        error: stripeError?.message,
      });
      return json(
        {
          error: "stripe_error",
          stripeStatus: session.status,
          stripeType: stripeError?.type ?? null,
          stripeCode: stripeError?.code ?? null,
          stripeMessage: stripeError?.message ?? null,
        },
        502
      );
    }
    return json({
      clientSecret: session.data.client_secret,
      publishableKey: env.STRIPE_PUBLISHABLE_KEY ?? null,
    });
  }
  if (!session.ok || typeof session.data.url !== "string") {
    const stripeError = session.data.error as
      | { message?: string; type?: string; code?: string }
      | undefined;
    console.error("Stripe checkout session creation failed", {
      status: session.status,
      error: stripeError?.message,
    });
    return json(
      {
        error: "stripe_error",
        stripeStatus: session.status,
        stripeType: stripeError?.type ?? null,
        stripeCode: stripeError?.code ?? null,
        stripeMessage: stripeError?.message ?? null,
      },
      502
    );
  }

  return json({ url: session.data.url });
}

async function handleSessionLookup(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.STRIPE_SECRET_KEY) {
    return json({ error: "billing_not_configured" }, 503);
  }
  const id = new URL(request.url).searchParams.get("id") ?? "";
  if (!/^cs_[a-zA-Z0-9_]+$/.test(id)) {
    return json({ error: "invalid_session_id" }, 400);
  }

  const session = await stripeRequest(
    env,
    `/checkout/sessions/${encodeURIComponent(id)}`
  );
  if (!session.ok) {
    return json({ error: "session_not_found" }, 404);
  }

  const metadata = (session.data.metadata ?? {}) as Record<string, string>;
  const details = (session.data.customer_details ?? {}) as {
    email?: string | null;
  };

  // Fallback fulfillment: if the buyer landed on the success page but the
  // Stripe webhook never reached us, activate the membership and send the
  // welcome email right here (idempotent, so no double-sends).
  const isComplete =
    session.data.status === "complete" ||
    session.data.payment_status === "paid";
  if (isComplete) {
    await fulfillCheckoutSession(env, session.data);
  }

  return json({
    status: String(session.data.status ?? ""),
    paymentStatus: String(session.data.payment_status ?? ""),
    customerEmail: details.email ?? null,
    plan: metadata.plan ?? null,
  });
}

// ---------------------------------------------------------------------------
// Refunds — self-serve requests, admin review, Stripe execution
//
// Policy windows (published on /policies): Whisper One + badge fees are
// refundable within 14 days of the charge; coaching within 7 days of the
// billing cycle start; program purchases within 14 days. Requests land in
// whisper_refund_requests (owner-readable via RLS, service-role writes
// only); admins decide in the web admin console. Approval refunds the
// payment intent — reversing the coach transfer + platform fee for
// destination charges — and immediately ends the underlying subscription.
// ---------------------------------------------------------------------------

type RefundKind = "one" | "badge" | "coach-hire" | "program" | "business-plus";

const REFUND_WINDOW_DAYS: Record<RefundKind, number> = {
  one: 14,
  badge: 14,
  "coach-hire": 7,
  program: 14,
  "business-plus": 14,
};

const formatUsd = (cents: number): string => `$${(cents / 100).toFixed(2)}`;

function refundReceivedEmail(kind: RefundKind): {
  subject: string;
  html: string;
} {
  const label =
    kind === "one"
      ? "Whisper One"
      : kind === "badge"
        ? "verified badge"
        : kind === "coach-hire"
          ? "coaching subscription"
          : kind === "business-plus"
            ? "Business+ plan"
            : "program purchase";
  return {
    subject: "We got your refund request",
    html: emailShell(
      "Refund request received",
      `<p style="margin:0 0 12px;color:#444;font-size:15px;line-height:1.6;">Your ${label} refund request is in the review queue. A human looks at every request — most decisions land within 2 business days, and you'll get an email either way.</p><p style="margin:0;color:#444;font-size:15px;line-height:1.6;">You can check the status anytime in Settings → Billing.</p>`
    ),
  };
}

function refundDecisionEmail(
  approved: boolean,
  amountCents: number | null,
  note: string | null
): { subject: string; html: string } {
  if (approved) {
    const amount = amountCents ? formatUsd(amountCents) : "Your payment";
    return {
      subject: "Your refund is on the way",
      html: emailShell(
        "Refund approved",
        `<p style="margin:0 0 12px;color:#444;font-size:15px;line-height:1.6;">${amount} is being returned to your original payment method. Banks typically post refunds within 5–10 business days.</p>${
          note
            ? `<p style="margin:0;color:#444;font-size:15px;line-height:1.6;">Note from the team: ${note}</p>`
            : ""
        }`
      ),
    };
  }
  return {
    subject: "About your refund request",
    html: emailShell(
      "Refund request reviewed",
      `<p style="margin:0 0 12px;color:#444;font-size:15px;line-height:1.6;">We reviewed your request and couldn't approve it this time${
        note ? `: ${note}` : " — it fell outside the refund window in our billing policy"
      }.</p><p style="margin:0;color:#444;font-size:15px;line-height:1.6;">If you think we got this wrong, reply to this email or reach support@mydailywhisper.com and a human will take a second look.</p>`
    ),
  };
}

/** POST /refunds/request — a signed-in user asks for a refund. */
async function handleRefundRequest(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  if (!env.STRIPE_SECRET_KEY) return json({ error: "billing_not_configured" }, 503);

  let body: {
    kind?: string;
    subscriptionId?: string;
    programId?: string;
    reason?: string;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const kind = body.kind as RefundKind;
  if (!REFUND_WINDOW_DAYS[kind]) return json({ error: "invalid_kind" }, 400);
  const reason = String(body.reason ?? "").trim().slice(0, 600);
  if (reason.length < 5) return json({ error: "reason_required" }, 400);

  const uid = encodeURIComponent(user.userId);
  let reference: string | null = null;
  let coachUserId: string | null = null;
  let amountCents: number | null = null;
  let purchasedAtMs: number | null = null;

  if (kind === "one" || kind === "badge" || kind === "business-plus") {
    const table =
      kind === "one"
        ? "whisper_one_members"
        : kind === "badge"
          ? "whisper_badge_members"
          : "whisper_business_plus";
    const rows = await supabaseSelect(
      env,
      `/${table}?user_id=eq.${uid}&status=in.(active,past_due)&select=stripe_subscription_id,plan&order=updated_at.desc&limit=1`
    );
    const row = rows?.[0] as
      | { stripe_subscription_id?: string; plan?: string }
      | undefined;
    if (!row?.stripe_subscription_id) {
      return json({ error: "no_active_membership" }, 404);
    }
    reference = row.stripe_subscription_id;
    amountCents = PLANS[row.plan ?? ""]?.unitAmount ?? null;
    const sub = await stripeRequest(
      env,
      `/subscriptions/${encodeURIComponent(reference)}`
    );
    if (sub.ok) {
      const start =
        typeof sub.data.current_period_start === "number"
          ? sub.data.current_period_start
          : null;
      if (start) purchasedAtMs = start * 1000;
      const items = (
        sub.data.items as { data?: { price?: { unit_amount?: number } }[] }
      )?.data;
      const unit = items?.[0]?.price?.unit_amount;
      if (typeof unit === "number") amountCents = unit;
    }
  } else if (kind === "coach-hire") {
    const subId = (body.subscriptionId ?? "").trim();
    if (!subId.startsWith("sub_")) {
      return json({ error: "missing_subscription" }, 400);
    }
    const sub = await stripeRequest(
      env,
      `/subscriptions/${encodeURIComponent(subId)}`
    );
    if (!sub.ok) return json({ error: "subscription_not_found" }, 404);
    const meta = (sub.data.metadata ?? {}) as Record<string, string>;
    if (meta.kind !== "coach-hire" || meta.whisperUserId !== user.userId) {
      return json({ error: "forbidden" }, 403);
    }
    reference = subId;
    coachUserId = meta.coachUserId ?? null;
    const start =
      typeof sub.data.current_period_start === "number"
        ? sub.data.current_period_start
        : null;
    if (start) purchasedAtMs = start * 1000;
    const items = (
      sub.data.items as { data?: { price?: { unit_amount?: number } }[] }
    )?.data;
    amountCents = items?.[0]?.price?.unit_amount ?? null;
  } else {
    const programId = (body.programId ?? "").trim();
    if (!programId) return json({ error: "missing_program" }, 400);
    const marker = encodeURIComponent(`*[program:${programId}]*`);
    const rows = await supabaseSelect(
      env,
      `/whisper_coach_earnings?client_user_id=eq.${uid}&description=like.${marker}&select=stripe_session_id,coach_user_id,gross_cents,created_at&order=created_at.desc&limit=1`
    );
    const row = rows?.[0] as
      | {
          stripe_session_id?: string;
          coach_user_id?: string;
          gross_cents?: number;
          created_at?: string;
        }
      | undefined;
    if (!row?.stripe_session_id) {
      return json({ error: "purchase_not_found" }, 404);
    }
    reference = row.stripe_session_id;
    coachUserId = row.coach_user_id ?? null;
    amountCents = row.gross_cents ?? null;
    if (row.created_at) purchasedAtMs = Date.parse(row.created_at);
  }

  const windowMs = REFUND_WINDOW_DAYS[kind] * 86_400_000;
  const eligibleAuto =
    purchasedAtMs != null && Date.now() - purchasedAtMs <= windowMs;

  // One pending request per purchase.
  const dupes = await supabaseSelect(
    env,
    `/whisper_refund_requests?user_id=eq.${uid}&status=eq.pending&reference=eq.${encodeURIComponent(
      reference ?? ""
    )}&select=id&limit=1`
  );
  if (Array.isArray(dupes) && dupes.length > 0) {
    return json({ ok: true, duplicate: true });
  }

  const ins = await supabaseAdmin(env, "/whisper_refund_requests", {
    method: "POST",
    body: {
      user_id: user.userId,
      email: user.email,
      kind,
      reference,
      coach_user_id: coachUserId,
      amount_cents: amountCents,
      reason,
      status: "pending",
      eligible_auto: eligibleAuto,
      created_at: new Date().toISOString(),
    },
  });
  if (!ins.ok) return json({ error: "db_error" }, 500);
  if (user.email) {
    const mail = refundReceivedEmail(kind);
    await sendEmail(env, user.email, mail.subject, mail.html);
  }
  console.log("Refund requested", { kind, eligibleAuto });
  return json({ ok: true, eligibleAuto });
}

/** GET /refunds/mine — the signed-in user's refund requests. */
async function handleMyRefunds(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const rows = await supabaseSelect(
    env,
    `/whisper_refund_requests?user_id=eq.${encodeURIComponent(
      user.userId
    )}&select=id,kind,reference,amount_cents,reason,status,eligible_auto,admin_note,created_at,decided_at&order=created_at.desc&limit=20`
  );
  const requests = ((rows ?? []) as Record<string, unknown>[]).map((r) => ({
    id: r.id,
    kind: r.kind,
    reference: r.reference ?? null,
    amountCents: r.amount_cents ?? null,
    reason: r.reason ?? null,
    status: r.status,
    eligibleAuto: r.eligible_auto === true,
    adminNote: r.admin_note ?? null,
    createdAt: r.created_at,
    decidedAt: r.decided_at ?? null,
  }));
  return json({ requests });
}

/** GET /admin/refunds?status=pending — the review queue. */
async function handleAdminRefundsList(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  const status = new URL(request.url).searchParams.get("status") ?? "";
  const filter = ["pending", "processed", "denied", "failed"].includes(status)
    ? `&status=eq.${status}`
    : "";
  const rows = await supabaseSelect(
    env,
    `/whisper_refund_requests?select=*${filter}&order=created_at.desc&limit=100`
  );
  const list = (rows ?? []) as Record<string, unknown>[];
  const userIds = Array.from(
    new Set(list.map((r) => String(r.user_id ?? "")).filter(Boolean))
  );
  const nameById = new Map<string, string>();
  if (userIds.length > 0) {
    const profs = await supabaseSelect(
      env,
      `/whisper_profiles?user_id=in.(${userIds
        .map(encodeURIComponent)
        .join(",")})&select=user_id,username&limit=100`
    );
    for (const p of (profs ?? []) as {
      user_id?: string;
      username?: string;
    }[]) {
      if (p.user_id && p.username) nameById.set(p.user_id, p.username);
    }
  }
  return json({
    requests: list.map((r) => ({
      id: r.id,
      userId: r.user_id,
      username: nameById.get(String(r.user_id ?? "")) ?? null,
      email: r.email ?? null,
      kind: r.kind,
      reference: r.reference ?? null,
      coachUserId: r.coach_user_id ?? null,
      amountCents: r.amount_cents ?? null,
      reason: r.reason ?? null,
      status: r.status,
      eligibleAuto: r.eligible_auto === true,
      adminNote: r.admin_note ?? null,
      createdAt: r.created_at,
      decidedAt: r.decided_at ?? null,
    })),
  });
}

/**
 * POST /admin/refunds/decide — approve (executes the Stripe refund, ends the
 * subscription, flips entitlements) or deny (with a note). Admin/owner only.
 */
async function handleAdminRefundDecide(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  if (admin.role === "moderator") return json({ error: "forbidden" }, 403);
  if (!env.STRIPE_SECRET_KEY) return json({ error: "billing_not_configured" }, 503);

  let body: { id?: string; action?: string; note?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const id = (body.id ?? "").trim();
  if (!UUID_RE.test(id)) return json({ error: "invalid_id" }, 400);
  const action =
    body.action === "approve" ? "approve" : body.action === "deny" ? "deny" : null;
  if (!action) return json({ error: "invalid_action" }, 400);
  const note = String(body.note ?? "").trim().slice(0, 500) || null;

  const rows = await supabaseSelect(
    env,
    `/whisper_refund_requests?id=eq.${encodeURIComponent(id)}&select=*&limit=1`
  );
  const row = rows?.[0] as
    | {
        id: string;
        user_id: string;
        email: string | null;
        kind: RefundKind;
        reference: string | null;
        coach_user_id: string | null;
        amount_cents: number | null;
        status: string;
      }
    | undefined;
  if (!row) return json({ error: "not_found" }, 404);
  if (row.status !== "pending") return json({ error: "already_decided" }, 409);

  const idPath = `/whisper_refund_requests?id=eq.${encodeURIComponent(id)}`;
  const decidedPatch = {
    decided_by: admin.userId,
    decided_at: new Date().toISOString(),
    admin_note: note,
    updated_at: new Date().toISOString(),
  };

  if (action === "deny") {
    const ok = await supabaseAdmin(env, idPath, {
      method: "PATCH",
      body: { ...decidedPatch, status: "denied" },
    });
    if (!ok.ok) return json({ error: "db_error" }, 500);
    if (row.email) {
      const mail = refundDecisionEmail(false, row.amount_cents, note);
      await sendEmail(env, row.email, mail.subject, mail.html);
    }
    return json({ ok: true, status: "denied" });
  }

  // Approve — resolve the payment intent behind the purchase.
  const ref = row.reference ?? "";
  let paymentIntent: string | null = null;
  if (row.kind === "program") {
    if (!ref.startsWith("cs_")) return json({ error: "missing_reference" }, 422);
    const session = await stripeRequest(
      env,
      `/checkout/sessions/${encodeURIComponent(ref)}`
    );
    if (session.ok && typeof session.data.payment_intent === "string") {
      paymentIntent = session.data.payment_intent;
    }
  } else {
    if (!ref.startsWith("sub_")) return json({ error: "missing_reference" }, 422);
    const sub = await stripeRequest(
      env,
      `/subscriptions/${encodeURIComponent(ref)}?expand[]=latest_invoice`
    );
    if (sub.ok) {
      const inv = sub.data.latest_invoice as
        | Record<string, unknown>
        | string
        | null;
      if (inv && typeof inv === "object") {
        if (typeof inv.payment_intent === "string") {
          paymentIntent = inv.payment_intent;
        } else if (typeof inv.charge === "string") {
          const ch = await stripeRequest(
            env,
            `/charges/${encodeURIComponent(inv.charge)}`
          );
          if (ch.ok && typeof ch.data.payment_intent === "string") {
            paymentIntent = ch.data.payment_intent;
          }
        }
      }
    }
  }
  if (!paymentIntent) {
    await supabaseAdmin(env, idPath, {
      method: "PATCH",
      body: {
        ...decidedPatch,
        status: "failed",
        admin_note: [note, "payment intent not found"]
          .filter(Boolean)
          .join(" · "),
      },
    });
    return json({ error: "payment_not_found" }, 422);
  }

  const params = new URLSearchParams();
  params.set("payment_intent", paymentIntent);
  params.set("metadata[whisperRefundId]", row.id);
  if (row.kind === "coach-hire" || row.kind === "program") {
    // Destination charges: pull the transfer back from the coach and return
    // Whisper's platform fee so the client is made 100% whole.
    params.set("reverse_transfer", "true");
    params.set("refund_application_fee", "true");
  }
  const refund = await stripeRequest(env, "/refunds", params);
  if (!refund.ok) {
    const err = refund.data.error as { message?: string } | undefined;
    await supabaseAdmin(env, idPath, {
      method: "PATCH",
      body: {
        ...decidedPatch,
        status: "failed",
        admin_note: [note, err?.message].filter(Boolean).join(" · ").slice(0, 500),
      },
    });
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  const refundId = typeof refund.data.id === "string" ? refund.data.id : null;
  const refundedCents =
    typeof refund.data.amount === "number" ? refund.data.amount : row.amount_cents;

  // Post-refund cleanup: end subscriptions + flip entitlements immediately.
  const uid = encodeURIComponent(row.user_id);
  if (row.kind === "business-plus") {
    // Business+ refund: cancel the subscription and flip the plan ledger —
    // entitlement (suite tabs, team, presenting) reads status=active.
    await stripeDelete(env, `/subscriptions/${encodeURIComponent(ref)}`);
    await supabaseAdmin(
      env,
      `/whisper_business_plus?stripe_subscription_id=eq.${encodeURIComponent(ref)}`,
      {
        method: "PATCH",
        body: { status: "cancelled", updated_at: new Date().toISOString() },
      }
    );
  } else if (row.kind === "one" || row.kind === "badge") {
    await stripeDelete(env, `/subscriptions/${encodeURIComponent(ref)}`);
    const table =
      row.kind === "one" ? "whisper_one_members" : "whisper_badge_members";
    await supabaseAdmin(
      env,
      `/${table}?stripe_subscription_id=eq.${encodeURIComponent(ref)}`,
      {
        method: "PATCH",
        body: { status: "cancelled", updated_at: new Date().toISOString() },
      }
    );
    if (row.kind === "one") {
      await supabaseAdmin(env, `/whisper_profiles?user_id=eq.${uid}`, {
        method: "PATCH",
        body: { is_one: false, one_plan: null },
      });
    } else {
      const memberRows = await supabaseSelect(
        env,
        `/whisper_badge_members?stripe_subscription_id=eq.${encodeURIComponent(
          ref
        )}&select=role&limit=1`
      );
      const role = (memberRows?.[0] as { role?: BadgeRole } | undefined)?.role;
      if (role) {
        const flag = BADGE_PROFILE_FLAG[role];
        if (role !== "verified") {
          await supabaseAdmin(env, `/whisper_profiles?user_id=eq.${uid}`, {
            method: "PATCH",
            body: { [flag]: false },
          });
        }
        await supabaseAdmin(env, `/profiles?id=eq.${uid}`, {
          method: "PATCH",
          body: { [flag]: false },
        });
      }
    }
  } else if (row.kind === "coach-hire") {
    await stripeDelete(env, `/subscriptions/${encodeURIComponent(ref)}`);
    if (row.coach_user_id) {
      const since = new Date(Date.now() - 45 * 86_400_000).toISOString();
      await supabaseAdmin(
        env,
        `/whisper_coach_earnings?coach_user_id=eq.${encodeURIComponent(
          row.coach_user_id
        )}&client_user_id=eq.${uid}&created_at=gte.${encodeURIComponent(since)}`,
        { method: "PATCH", body: { refunded: true } }
      );
    }
  } else {
    await supabaseAdmin(
      env,
      `/whisper_coach_earnings?stripe_session_id=eq.${encodeURIComponent(ref)}`,
      { method: "PATCH", body: { refunded: true } }
    );
  }

  // Mirror the refund into the receipts ledger so Settings → Billing and
  // the admin console read truthfully.
  const receiptRefundPatch = {
    method: "PATCH" as const,
    body: {
      status: "refunded",
      refunded_at: new Date().toISOString(),
      refund_note: note ?? "Refund approved",
    },
  };
  await supabaseAdmin(
    env,
    `/whisper_receipts?stripe_payment_intent=eq.${encodeURIComponent(
      paymentIntent
    )}&status=eq.paid`,
    receiptRefundPatch
  );
  await supabaseAdmin(
    env,
    ref.startsWith("sub_")
      ? `/whisper_receipts?stripe_subscription_id=eq.${encodeURIComponent(
          ref
        )}&status=eq.paid`
      : `/whisper_receipts?stripe_session_id=eq.${encodeURIComponent(
          ref
        )}&status=eq.paid`,
    receiptRefundPatch
  );

  const done = await supabaseAdmin(env, idPath, {
    method: "PATCH",
    body: {
      ...decidedPatch,
      status: "processed",
      stripe_refund_id: refundId,
      amount_cents: refundedCents,
    },
  });
  if (!done.ok) console.error("Refund row final PATCH failed", { id });
  if (row.email) {
    const mail = refundDecisionEmail(true, refundedCents ?? null, note);
    await sendEmail(env, row.email, mail.subject, mail.html);
  }
  console.log("Refund processed", { id, kind: row.kind, refundId });
  return json({ ok: true, status: "processed", stripeRefundId: refundId });
}

// ---------------------------------------------------------------------------
// Receipts endpoints — user history, the admin money ledger, direct refunds
// ---------------------------------------------------------------------------

/** GET /billing/receipts — the signed-in user's purchase history. */
async function handleMyReceipts(
  request: Request,
  env: Env
): Promise<Response> {
  const caller = await requireUser(request, env);
  if (caller instanceof Response) return caller;
  const rows = await supabaseSelect(
    env,
    `/whisper_receipts?user_id=eq.${encodeURIComponent(
      caller.userId
    )}&select=id,receipt_no,kind,description,amount_cents,status,stripe_subscription_id,created_at,refunded_at&order=created_at.desc&limit=100`
  );
  const receipts = (rows ?? []).map((raw) => {
    const row = raw as Record<string, unknown>;
    return {
      id: row.id,
      receiptNo: row.receipt_no,
      kind: row.kind,
      description: row.description,
      amountCents: row.amount_cents,
      status: row.status,
      subscriptionId: row.stripe_subscription_id,
      createdAt: row.created_at,
      refundedAt: row.refunded_at,
    };
  });
  return json({ receipts });
}

/** GET /admin/receipts?query= — the searchable money ledger. */
async function handleAdminReceipts(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  const url = new URL(request.url);
  const query = (url.searchParams.get("query") ?? "").trim().slice(0, 80);
  let path = `/whisper_receipts?select=*&order=created_at.desc&limit=150`;
  if (query) {
    const term = encodeURIComponent(`*${query}*`);
    path += `&or=(email.ilike.${term},description.ilike.${term},receipt_no.ilike.${term})`;
  }
  const rows = await supabaseSelect(env, path);
  return json({ receipts: rows ?? [] });
}

/**
 * POST /admin/refunds/direct — refund straight from a receipt (no user
 * request needed). Executes the Stripe refund (reversing transfers and
 * returning the platform fee on coach/program/sponsorship charges), ends
 * subscriptions, flips entitlements, marks the receipt, writes an audit row
 * into the refunds queue, and emails the buyer.
 */
async function handleAdminDirectRefund(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  if (admin.role === "moderator") return json({ error: "forbidden" }, 403);
  if (!env.STRIPE_SECRET_KEY)
    return json({ error: "billing_not_configured" }, 503);

  let body: { receiptId?: string; note?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const id = (body.receiptId ?? "").trim();
  if (!UUID_RE.test(id)) return json({ error: "invalid_id" }, 400);
  const note =
    String(body.note ?? "").trim().slice(0, 300) ||
    "Refunded by Whisper support";

  const rows = await supabaseSelect(
    env,
    `/whisper_receipts?id=eq.${encodeURIComponent(id)}&select=*&limit=1`
  );
  const row = rows?.[0] as
    | {
        id: string;
        user_id: string | null;
        email: string | null;
        kind: string;
        amount_cents: number;
        status: string;
        stripe_session_id: string | null;
        stripe_invoice_id: string | null;
        stripe_payment_intent: string | null;
        stripe_subscription_id: string | null;
        coach_user_id: string | null;
      }
    | undefined;
  if (!row) return json({ error: "not_found" }, 404);
  if (row.status !== "paid") return json({ error: "already_refunded" }, 409);

  // Resolve the payment intent behind this receipt (stored → invoice →
  // session → subscription's latest invoice).
  let paymentIntent = row.stripe_payment_intent;
  if (!paymentIntent && row.stripe_invoice_id) {
    const inv = await stripeRequest(
      env,
      `/invoices/${encodeURIComponent(row.stripe_invoice_id)}`
    );
    if (inv.ok) {
      if (typeof inv.data.payment_intent === "string") {
        paymentIntent = inv.data.payment_intent;
      } else if (typeof inv.data.charge === "string") {
        const ch = await stripeRequest(
          env,
          `/charges/${encodeURIComponent(inv.data.charge)}`
        );
        if (ch.ok && typeof ch.data.payment_intent === "string") {
          paymentIntent = ch.data.payment_intent;
        }
      }
    }
  }
  if (!paymentIntent && row.stripe_session_id) {
    const session = await stripeRequest(
      env,
      `/checkout/sessions/${encodeURIComponent(row.stripe_session_id)}`
    );
    if (session.ok && typeof session.data.payment_intent === "string") {
      paymentIntent = session.data.payment_intent;
    }
  }
  if (!paymentIntent && row.stripe_subscription_id) {
    const sub = await stripeRequest(
      env,
      `/subscriptions/${encodeURIComponent(
        row.stripe_subscription_id
      )}?expand[]=latest_invoice`
    );
    if (sub.ok) {
      const inv = sub.data.latest_invoice as
        | Record<string, unknown>
        | string
        | null;
      if (inv && typeof inv === "object") {
        if (typeof inv.payment_intent === "string") {
          paymentIntent = inv.payment_intent;
        } else if (typeof inv.charge === "string") {
          const ch = await stripeRequest(
            env,
            `/charges/${encodeURIComponent(inv.charge)}`
          );
          if (ch.ok && typeof ch.data.payment_intent === "string") {
            paymentIntent = ch.data.payment_intent;
          }
        }
      }
    }
  }
  if (!paymentIntent) return json({ error: "payment_not_found" }, 422);

  const params = new URLSearchParams();
  params.set("payment_intent", paymentIntent);
  params.set("metadata[whisperReceiptId]", row.id);
  if (
    row.kind === "coach-hire" ||
    row.kind === "program" ||
    row.kind === "sponsorship"
  ) {
    // Destination charges: pull the transfer back and return Whisper's fee
    // so the buyer is made 100% whole.
    params.set("reverse_transfer", "true");
    params.set("refund_application_fee", "true");
  }
  const refund = await stripeRequest(env, "/refunds", params);
  if (!refund.ok) {
    const err = refund.data.error as { message?: string } | undefined;
    return json(
      { error: "stripe_error", stripeMessage: err?.message ?? null },
      502
    );
  }
  const refundId = typeof refund.data.id === "string" ? refund.data.id : null;

  // End subscriptions + flip entitlements, mirroring the queue's approve path.
  const subId = row.stripe_subscription_id;
  if (
    subId &&
    (row.kind === "one" || row.kind === "badge" || row.kind === "coach-hire")
  ) {
    await stripeDelete(env, `/subscriptions/${encodeURIComponent(subId)}`);
    const subFilter = `stripe_subscription_id=eq.${encodeURIComponent(subId)}`;
    if (row.kind === "one") {
      await supabaseAdmin(env, `/whisper_one_members?${subFilter}`, {
        method: "PATCH",
        body: { status: "cancelled", updated_at: new Date().toISOString() },
      });
      if (row.user_id) {
        await supabaseAdmin(
          env,
          `/whisper_profiles?user_id=eq.${encodeURIComponent(row.user_id)}`,
          { method: "PATCH", body: { is_one: false, one_plan: null } }
        );
      }
    } else if (row.kind === "badge") {
      await supabaseAdmin(env, `/whisper_badge_members?${subFilter}`, {
        method: "PATCH",
        body: { status: "cancelled", updated_at: new Date().toISOString() },
      });
      const memberRows = await supabaseSelect(
        env,
        `/whisper_badge_members?${subFilter}&select=role&limit=1`
      );
      const role = (memberRows?.[0] as { role?: BadgeRole } | undefined)?.role;
      if (role && row.user_id) {
        const flag = BADGE_PROFILE_FLAG[role];
        const uid = encodeURIComponent(row.user_id);
        if (role !== "verified") {
          await supabaseAdmin(env, `/whisper_profiles?user_id=eq.${uid}`, {
            method: "PATCH",
            body: { [flag]: false },
          });
        }
        await supabaseAdmin(env, `/profiles?id=eq.${uid}`, {
          method: "PATCH",
          body: { [flag]: false },
        });
      }
    } else if (row.kind === "business-plus") {
      await supabaseAdmin(env, `/whisper_business_plus?${subFilter}`, {
        method: "PATCH",
        body: { status: "cancelled", updated_at: new Date().toISOString() },
      });
    } else if (row.kind === "coach-hire" && row.coach_user_id && row.user_id) {
      const since = new Date(Date.now() - 45 * 86_400_000).toISOString();
      await supabaseAdmin(
        env,
        `/whisper_coach_earnings?coach_user_id=eq.${encodeURIComponent(
          row.coach_user_id
        )}&client_user_id=eq.${encodeURIComponent(
          row.user_id
        )}&created_at=gte.${encodeURIComponent(since)}`,
        { method: "PATCH", body: { refunded: true } }
      );
    }
  } else if (row.kind === "program" && row.stripe_session_id) {
    await supabaseAdmin(
      env,
      `/whisper_coach_earnings?stripe_session_id=eq.${encodeURIComponent(
        row.stripe_session_id
      )}`,
      { method: "PATCH", body: { refunded: true } }
    );
  }

  await supabaseAdmin(env, `/whisper_receipts?id=eq.${encodeURIComponent(row.id)}`, {
    method: "PATCH",
    body: {
      status: "refunded",
      refunded_at: new Date().toISOString(),
      refund_note: note,
    },
  });

  // Audit trail in the refunds queue so direct refunds show up in history.
  if (row.user_id) {
    await supabaseAdmin(env, "/whisper_refund_requests", {
      method: "POST",
      body: {
        user_id: row.user_id,
        email: row.email,
        kind: row.kind,
        reference: subId ?? row.stripe_session_id,
        amount_cents: row.amount_cents,
        reason: "Issued directly from the receipts ledger",
        status: "processed",
        admin_note: note,
        decided_by: admin.userId,
        decided_at: new Date().toISOString(),
        stripe_refund_id: refundId,
      },
    });
  }
  if (row.email) {
    const mail = refundDecisionEmail(true, row.amount_cents, note);
    await sendEmail(env, row.email, mail.subject, mail.html);
  }
  console.log("Direct refund processed", {
    receipt: row.id,
    kind: row.kind,
    refundId,
  });
  return json({ ok: true, stripeRefundId: refundId });
}

// ---------------------------------------------------------------------------
// Admin badge grants — director / blogger / recruiter / trusted are EARNED
// roles granted from the admin console (no payment path). Coach, athlete,
// and verified stay on the application + annual-fee path.
// ---------------------------------------------------------------------------

const GRANTABLE_BADGES: Record<
  string,
  { table: string; keyCol: string; flag: string }
> = {
  director: { table: "whisper_profiles", keyCol: "user_id", flag: "is_director" },
  blogger: { table: "whisper_profiles", keyCol: "user_id", flag: "is_blogger" },
  recruiter: {
    table: "whisper_profiles",
    keyCol: "user_id",
    flag: "is_recruiter",
  },
  trusted: { table: "profiles", keyCol: "id", flag: "is_trusted_member" },
};

/** POST /admin/badges/grant — { username | userId, badge, grant } */
async function handleAdminBadgeGrant(
  request: Request,
  env: Env
): Promise<Response> {
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  if (admin.role === "moderator") return json({ error: "forbidden" }, 403);

  let body: {
    userId?: string;
    username?: string;
    badge?: string;
    grant?: boolean;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const spec = GRANTABLE_BADGES[body.badge ?? ""];
  if (!spec) return json({ error: "invalid_badge" }, 400);

  let targetId = (body.userId ?? "").trim();
  const username = (body.username ?? "").trim().replace(/^@/, "");
  let resolvedName: string | null = null;
  if (!targetId && username) {
    const rows = await supabaseSelect(
      env,
      `/whisper_profiles?username=ilike.${encodeURIComponent(
        username
      )}&select=user_id,username&limit=1`
    );
    const hit = rows?.[0] as
      | { user_id?: string; username?: string }
      | undefined;
    targetId = hit?.user_id ?? "";
    resolvedName = hit?.username ?? null;
  }
  if (!targetId || !UUID_RE.test(targetId)) {
    return json({ error: "user_not_found" }, 404);
  }

  const grant = body.grant !== false;
  const res = await supabaseAdmin(
    env,
    `/${spec.table}?${spec.keyCol}=eq.${encodeURIComponent(targetId)}`,
    { method: "PATCH", body: { [spec.flag]: grant } }
  );
  if (!res.ok) return json({ error: "db_error" }, 500);
  console.log("Admin badge grant", {
    badge: body.badge,
    grant,
    by: admin.userId,
  });
  return json({
    ok: true,
    userId: targetId,
    username: resolvedName,
    badge: body.badge,
    granted: grant,
  });
}

// ---------------------------------------------------------------------------
// Webhook
// ---------------------------------------------------------------------------

// Stripe webhooks must be verified within 5 minutes of the timestamp to
// prevent replay attacks. During secret rotation Stripe sends multiple v1
// signatures — one per active secret — so accept any match.
const STRIPE_TIMESTAMP_TOLERANCE_SEC = 300;

async function verifyStripeSignature(
  payload: string,
  header: string,
  secret: string
): Promise<boolean> {
  const entries = header.split(",").map((kv) => {
    const [k, ...rest] = kv.split("=");
    return [k, rest.join("=")] as const;
  });
  const timestamp = entries.find(([k]) => k === "t")?.[1];
  const signatures = entries
    .filter(([k, v]) => k === "v1" && v)
    .map(([, v]) => v);
  if (!timestamp || signatures.length === 0) return false;

  const ageSec = Math.floor(Date.now() / 1000) - Number(timestamp);
  if (!Number.isFinite(ageSec) || Math.abs(ageSec) > STRIPE_TIMESTAMP_TOLERANCE_SEC) {
    return false;
  }

  const signedPayload = `${timestamp}.${payload}`;
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const sig = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(signedPayload)
  );
  const computed = Array.from(new Uint8Array(sig))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");

  return signatures.some((candidate) => {
    if (computed.length !== candidate.length) return false;
    let mismatch = 0;
    for (let i = 0; i < computed.length; i++) {
      mismatch |= computed.charCodeAt(i) ^ candidate.charCodeAt(i);
    }
    return mismatch === 0;
  });
}

/** Look up a Stripe customer's email (for events that don't include one). */
async function customerEmail(
  env: Env,
  customerId: string | null
): Promise<string | null> {
  if (!customerId) return null;
  const res = await stripeRequest(
    env,
    `/customers/${encodeURIComponent(customerId)}`
  );
  if (!res.ok) return null;
  const email = res.data.email;
  return typeof email === "string" ? email : null;
}

async function handleWebhook(request: Request, env: Env): Promise<Response> {
  const signature = request.headers.get("Stripe-Signature");
  if (!signature) return new Response("missing signature", { status: 400 });

  const secret = env.STRIPE_WEBHOOK_SECRET;
  if (!secret) {
    console.error("STRIPE_WEBHOOK_SECRET is not set in project envs");
    return new Response("server misconfigured", { status: 500 });
  }

  const payload = await request.text();
  const ok = await verifyStripeSignature(payload, signature, secret);
  if (!ok) return new Response("invalid signature", { status: 400 });

  let event: { type: string; data: { object: Record<string, unknown> } };
  try {
    event = JSON.parse(payload) as typeof event;
  } catch {
    return new Response("invalid json payload", { status: 400 });
  }

  const obj = event.data.object;
  const metadata = (obj.metadata ?? {}) as Record<string, string>;

  switch (event.type) {
    case "checkout.session.completed": {
      console.log("Whisper One checkout completed", {
        plan: metadata.plan || "one-monthly",
        whisperUserId: metadata.whisperUserId || "guest",
      });
      await fulfillCheckoutSession(env, obj);
      break;
    }

    case "customer.subscription.deleted": {
      const userId = metadata.whisperUserId || null;
      const custId = typeof obj.customer === "string" ? obj.customer : null;
      const plan = metadata.plan || "one-monthly";
      const badgeRole = PLANS[plan]?.badgeRole;
      console.log("Subscription cancelled", {
        plan,
        whisperUserId: userId ?? "unknown",
      });

      if (badgeRole) {
        await applyBadgeMembership(env, {
          userId,
          email: null,
          plan,
          role: badgeRole,
          status: "cancelled",
          stripeCustomerId: custId,
          stripeSubscriptionId: typeof obj.id === "string" ? obj.id : null,
        });
        const email = await customerEmail(env, custId);
        if (email) {
          const mail = badgeEndedEmail(badgeRole);
          await sendEmail(env, email, mail.subject, mail.html);
        }
        break;
      }

      if (PLANS[plan]?.businessPlus) {
        await applyBusinessPlusMembership(env, {
          userId,
          email: null,
          plan,
          status: "cancelled",
          stripeCustomerId: custId,
          stripeSubscriptionId: typeof obj.id === "string" ? obj.id : null,
        });
        const email = await customerEmail(env, custId);
        if (email) {
          const html = emailShell(
            "Business+ has ended",
            `<p>Your Whisper Business+ plan is cancelled. Your team, positions, and groups are kept safe — resubscribe anytime to pick up right where you left off.</p>`
          );
          await sendEmail(env, email, "Your Business+ plan has ended", html);
        }
        break;
      }

      await applyMembership(env, {
        userId,
        email: null,
        plan,
        status: "cancelled",
        stripeCustomerId: custId,
        stripeSubscriptionId: typeof obj.id === "string" ? obj.id : null,
      });

      const email = await customerEmail(env, custId);
      if (email) {
        const mail = cancelledEmail();
        await sendEmail(env, email, mail.subject, mail.html);
      }
      break;
    }

    case "invoice.paid":
    case "invoice.payment_succeeded": {
      // Coach-hire renewals: each monthly invoice adds an earnings row so
      // the client's paid window stays fresh and the coach's ledger grows.
      // The FIRST payment is recorded by checkout.session.completed, so we
      // skip subscription_create invoices to avoid double counting.
      const billingReason = String(obj.billing_reason ?? "");
      if (billingReason === "subscription_create") break;
      const invoiceSubId =
        typeof obj.subscription === "string"
          ? obj.subscription
          : ((obj.parent as Record<string, unknown> | undefined)
              ?.subscription_details as { subscription?: string } | undefined)
              ?.subscription ?? null;
      if (!invoiceSubId) break;

      const sub = await stripeRequest(
        env,
        `/subscriptions/${encodeURIComponent(invoiceSubId)}`
      );
      if (!sub.ok) break;
      const subMeta = (sub.data.metadata ?? {}) as Record<string, string>;
      const gross = typeof obj.amount_paid === "number" ? obj.amount_paid : 0;
      if (gross <= 0) break;
      const renewalEmail =
        typeof obj.customer_email === "string" ? obj.customer_email : null;
      const renewalInvoiceId = typeof obj.id === "string" ? obj.id : null;

      if (subMeta.kind === "coach-hire" && subMeta.coachUserId) {
        const fee = Math.round((gross * COACH_PLATFORM_FEE_PERCENT) / 100);
        await supabaseAdmin(
          env,
          "/whisper_coach_earnings?on_conflict=stripe_session_id",
          {
            method: "POST",
            prefer: "resolution=ignore-duplicates",
            body: {
              coach_user_id: subMeta.coachUserId,
              client_user_id: subMeta.whisperUserId ?? null,
              client_email: renewalEmail,
              gross_cents: gross,
              fee_cents: fee,
              net_cents: gross - fee,
              description: subMeta.tierName
                ? `Monthly coaching renewal — ${subMeta.tierName}`
                : "Monthly coaching renewal",
              stripe_session_id: renewalInvoiceId,
              created_at: new Date().toISOString(),
            },
          }
        );
        await recordReceipt(env, {
          userId: subMeta.whisperUserId ?? null,
          email: renewalEmail,
          kind: "coach-hire",
          description: subMeta.tierName
            ? `Coaching renewal — ${subMeta.tierName}`
            : "Coaching renewal — monthly",
          amountCents: gross,
          invoiceId: renewalInvoiceId,
          subscriptionId: invoiceSubId,
          coachUserId: subMeta.coachUserId,
        });
        console.log("Coach hire renewal recorded", {
          coach: subMeta.coachUserId,
          gross,
        });
        break;
      }

      // Whisper One / badge renewals — receipt + email only (entitlements
      // were set at first fulfillment and stay active).
      const renewalPlan = subMeta.plan || "one-monthly";
      const renewalRole = PLANS[renewalPlan]?.badgeRole;
      await recordReceipt(env, {
        userId: subMeta.whisperUserId ?? null,
        email: renewalEmail,
        kind: renewalRole ? "badge" : "one",
        description: renewalRole
          ? `Approved ${renewalRole} tools — annual renewal`
          : `Whisper One renewal — ${
              renewalPlan === "one-annual" ? "annual" : "monthly"
            }`,
        amountCents: gross,
        invoiceId: renewalInvoiceId,
        subscriptionId: invoiceSubId,
      });
      break;
    }

    case "invoice.payment_failed": {
      // Mark the membership past_due (perks stay until Stripe actually
      // deletes the subscription — this is the grace period) so Settings
      // and the admin console can surface the failing card.
      const failedSubId =
        typeof obj.subscription === "string"
          ? obj.subscription
          : ((obj.parent as Record<string, unknown> | undefined)
              ?.subscription_details as { subscription?: string } | undefined)
              ?.subscription ?? null;
      if (failedSubId) {
        const sid = encodeURIComponent(failedSubId);
        await Promise.all([
          supabaseAdmin(
            env,
            `/whisper_one_members?stripe_subscription_id=eq.${sid}`,
            {
              method: "PATCH",
              body: { status: "past_due", updated_at: new Date().toISOString() },
            }
          ),
          supabaseAdmin(
            env,
            `/whisper_badge_members?stripe_subscription_id=eq.${sid}`,
            {
              method: "PATCH",
              body: { status: "past_due", updated_at: new Date().toISOString() },
            }
          ),
        ]);
      }
      const invoiceEmail =
        typeof obj.customer_email === "string" ? obj.customer_email : null;
      const email =
        invoiceEmail ??
        (await customerEmail(
          env,
          typeof obj.customer === "string" ? obj.customer : null
        ));
      console.log("Whisper One payment failed");
      if (email) {
        const mail = paymentFailedEmail();
        await sendEmail(env, email, mail.subject, mail.html);
      }
      break;
    }
  }

  return new Response(null, { status: 200 });
}

// ---------------------------------------------------------------------------
// Meeting requests — a visitor or member asks a recruiter for a call via the
// "Schedule a call" button on a featured profile card. The recruiter sees the
// request in their dashboard and approves or denies it. On approval, a
// Whisper-branded email with the Google Meet link is sent to the requester.
// ---------------------------------------------------------------------------

interface MeetingRequestBody {
  recruiterId?: string;
  recruiterUsername?: string;
  featuredId?: string;
  requesterName?: string;
  requesterEmail?: string;
  requestedTime?: string;
  requesterTimezone?: string;
  message?: string;
}

function isValidEmail(s: string): boolean {
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(s) && s.length <= 320;
}

/** Normalize a free-form preferred time to an ISO string if possible. */
function normalizeTime(raw: string): string | null {
  const t = raw.trim();
  if (!t) return null;
  const d = new Date(t);
  return Number.isNaN(d.getTime()) ? t : d.toISOString();
}

function recruiterMeetingInviteEmail(input: {
  requesterName: string;
  recruiterUsername: string;
  requestedTime: string;
  requesterTimezone: string | null;
  message: string | null;
  meetingLink: string;
  recruiterNote: string | null;
}): { subject: string; html: string } {
  const when = (() => {
    try {
      return new Date(input.requestedTime).toLocaleString("en-US", {
        dateStyle: "full",
        timeStyle: "short",
      });
    } catch {
      return input.requestedTime;
    }
  })();
  const noteBlock = input.recruiterNote
    ? `<p ${EMAIL_P}><strong>A note from ${input.recruiterUsername}:</strong></p><p ${EMAIL_P}>${escapeHtml(input.recruiterNote)}</p>`
    : "";
  return {
    subject: `Meeting confirmed with @${input.recruiterUsername} on Whisper`,
    html: emailShell(
      "Your meeting is confirmed",
      `<p ${EMAIL_P}>Hi ${escapeHtml(input.requesterName || "there")},</p>
       <p ${EMAIL_P}>@${escapeHtml(input.recruiterUsername)} approved your meeting request on Whisper. Here are the details:</p>
       <p ${EMAIL_P}><strong>When:</strong> ${escapeHtml(when)}${input.requesterTimezone ? ` (${escapeHtml(input.requesterTimezone)})` : ""}</p>
       <p ${EMAIL_P}><strong>Where:</strong> Google Meet</p>
       <a href="${escapeHtml(input.meetingLink)}" ${EMAIL_BTN}>Join the meeting</a>
       ${noteBlock}
       <p ${EMAIL_P}>Your original message:</p>
       <p ${EMAIL_P}><em>"${escapeHtml(input.message ?? "")}"</em></p>
       <p ${EMAIL_P}>We'll see you there. — The Whisper team</p>`
    ),
  };
}

function meetingDeclinedEmail(input: {
  requesterName: string;
  recruiterUsername: string;
  recruiterNote: string | null;
}): { subject: string; html: string } {
  const noteBlock = input.recruiterNote
    ? `<p ${EMAIL_P}><strong>A note from ${input.recruiterUsername}:</strong></p><p ${EMAIL_P}>${escapeHtml(input.recruiterNote)}</p>`
    : "";
  return {
    subject: `Update on your meeting request to @${input.recruiterUsername}`,
    html: emailShell(
      "Meeting request update",
      `<p ${EMAIL_P}>Hi ${escapeHtml(input.requesterName || "there")},</p>
       <p ${EMAIL_P}>@${escapeHtml(input.recruiterUsername)} wasn't able to take this meeting right now. You're welcome to submit a new request with a different time.</p>
       ${noteBlock}
       <p ${EMAIL_P}>— The Whisper team</p>`
    ),
  };
}

/** POST /meetings/request — public; creates a pending meeting request. */
async function handleMeetingRequest(
  request: Request,
  env: Env
): Promise<Response> {
  let body: MeetingRequestBody;
  try {
    body = (await request.json()) as MeetingRequestBody;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const recruiterId = (body.recruiterId ?? "").trim();
  const recruiterUsername = (body.recruiterUsername ?? "").trim().replace(/^@/, "");
  const featuredId = (body.featuredId ?? "").trim() || null;
  if (!recruiterId || !recruiterUsername) {
    return json({ error: "missing_recruiter" }, 400);
  }
  const name = (body.requesterName ?? "").trim().slice(0, 80);
  const email = (body.requesterEmail ?? "").trim().toLowerCase();
  if (!isValidEmail(email)) return json({ error: "invalid_email" }, 400);
  const requestedTime = normalizeTime(body.requestedTime ?? "");
  if (!requestedTime) return json({ error: "missing_time" }, 400);
  const tz = (body.requesterTimezone ?? "").trim().slice(0, 80) || null;
  const message = (body.message ?? "").trim().slice(0, 2000) || null;

  // Optionally resolve the signed-in requester (so they can track their own
  // requests later). Not required — the call to action is on a public page.
  let requesterUserId: string | null = null;
  const auth = request.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (token) {
    try {
      const res = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
        headers: { apikey: env.SUPABASE_SERVICE_ROLE_KEY ?? "", Authorization: `Bearer ${token}` },
      });
      if (res.ok) {
        const u = (await res.json()) as { id?: string };
        if (u.id) requesterUserId = u.id;
      }
    } catch {
      // ignore — anonymous request is fine
    }
  }

  const row = {
    recruiter_id: recruiterId,
    recruiter_username: recruiterUsername,
    featured_id: featuredId,
    requester_user_id: requesterUserId,
    requester_name: name,
    requester_email: email,
    requested_time: requestedTime,
    requester_timezone: tz,
    message,
    status: "pending",
  };
  const inserted = await supabaseAdmin(
    env,
    "/whisper_meeting_requests",
    { method: "POST", prefer: "return=representation", body: row }
  );
  if (!inserted.ok) return json({ error: "insert_failed" }, 502);
  return json({ ok: true });
}

/** POST /meetings/invite — send branded Whisper email invites for a scheduled
 *  meeting. The host provides a meeting id, title, scheduled time, and a list
 *  of email addresses. Each recipient gets a branded email with a link to
 *  /meet/{id} — they can join as a guest or sign up first. */
interface MeetingInviteBody {
  meetingId?: string;
  title?: string;
  scheduledAt?: string;
  hostUsername?: string;
  emails?: string[];
}

/** Branded email for a scheduled Whisper Meeting invite. */
function whisperMeetingInviteEmail(input: {
  hostUsername: string;
  title: string;
  scheduledAt: string;
  meetingLink: string;
}): { subject: string; html: string } {
  const when = (() => {
    try {
      return new Date(input.scheduledAt).toLocaleString("en-US", {
        dateStyle: "full",
        timeStyle: "short",
      });
    } catch {
      return input.scheduledAt;
    }
  })();
  return {
    subject: `You're invited: ${input.title} on Whisper`,
    html: emailShell(
      "You're invited to a Whisper Meeting",
      `<p ${EMAIL_P}>@${escapeHtml(input.hostUsername)} invited you to a meeting on Whisper.</p>
       <p ${EMAIL_P}><strong>What:</strong> ${escapeHtml(input.title)}</p>
       <p ${EMAIL_P}><strong>When:</strong> ${escapeHtml(when)}</p>
       <p ${EMAIL_P}>Whisper Meetings include live video, screen sharing, and AI-generated notes after the call — key points, decisions, and action items.</p>
       <a href="${escapeHtml(input.meetingLink)}" ${EMAIL_BTN}>Join the meeting</a>
       <p ${EMAIL_P}>Open Whisper Meet to sign in, confirm your account, and choose when to join. Opening this invitation does not start your camera or microphone.</p>
       <p ${EMAIL_P}>— The Whisper team</p>`
    ),
  };
}

async function handleMeetingInvite(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: MeetingInviteBody;
  try {
    body = (await request.json()) as MeetingInviteBody;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const meetingId = (body.meetingId ?? "").trim();
  if (!meetingId) return json({ error: "missing_meeting_id" }, 400);
  const title = (body.title ?? "").trim().slice(0, 200) || "Meeting";
  const hostUsername = (body.hostUsername ?? "").trim().replace(/^@/, "") || "host";
  const scheduledAt = (body.scheduledAt ?? "").trim();
  const emailList = (body.emails ?? [])
    .map((e) => e.trim().toLowerCase())
    .filter((e) => e && isValidEmail(e))
    .slice(0, 50);
  if (emailList.length === 0) return json({ error: "no_valid_emails" }, 400);
  if (!env.RESEND_API_KEY) {
    return json({ error: "not_configured" }, 503);
  }
  if (!isMeetingIdentity(meetingId)) return json({ error: "invalid_meeting_id" }, 400);
  const link = meetingInvitationLink(meetingId);
  const mail = whisperMeetingInviteEmail({
    hostUsername,
    title,
    scheduledAt,
    meetingLink: link,
  });
  let sent = 0;
  for (const email of emailList) {
    try {
      if (await sendEmail(env, email, mail.subject, mail.html)) sent++;
    } catch {
      // continue sending the rest
    }
  }
  if (sent === 0) return json({ error: "send_failed" }, 502);
  return json({ ok: true, sent });
}

/** POST /meetings/notes-email — send a finished meeting's AI notes as a
 *  branded, formatted Whisper email (instead of a bare mailto dump). */
interface MeetingNotesEmailBody {
  meetingId?: string;
  link?: string;
  title?: string;
  hostUsername?: string;
  notes?: string;
  emails?: string[];
  /** The FULL transcript ("Speaker: line" per row) — always rides along. */
  transcript?: string;
}

/** The full transcript as a quiet ruled block under the notes. */
function meetingTranscriptHtml(transcript: string): string {
  const lines = transcript
    .split(/\r?\n/)
    .map((l) => l.trim())
    .filter(Boolean);
  if (lines.length === 0) return "";
  const rows = lines
    .map((line) => {
      const m = /^([^:]{1,48}):\s*(.*)$/.exec(line);
      if (m) {
        return `<p style="margin:0 0 7px;font-size:13px;line-height:1.55;color:#44403c"><strong style="color:#111">${escapeHtml(m[1])}</strong> ${escapeHtml(m[2])}</p>`;
      }
      return `<p style="margin:0 0 7px;font-size:13px;line-height:1.55;color:#44403c">${escapeHtml(line)}</p>`;
    })
    .join("");
  return `<h3 style="margin:26px 0 8px;font-size:15px;line-height:1.3;color:#111111;letter-spacing:0.01em">Full transcript</h3>
    <p style="margin:0 0 10px;font-size:12px;color:#78716c">${lines.length} line${lines.length === 1 ? "" : "s"} — everything Jasper heard, in order.</p>
    <div style="border:1px solid #e7e5e4;border-radius:14px;padding:14px 16px;background:#fafaf9">${rows}</div>`;
}

/** Convert the AI notes (markdown-ish: **Sections** + "- " bullets) into
 *  clean inline-styled HTML for the branded email shell. */
function meetingNotesHtml(notes: string): string {
  const lines = notes.split(/\r?\n/);
  let html = "";
  let inList = false;
  const closeList = (): void => {
    if (inList) {
      html += "</ul>";
      inList = false;
    }
  };
  const inline = (text: string): string =>
    escapeHtml(text).replace(/\*\*(.+?)\*\*/g, "<strong>$1</strong>");
  for (const raw of lines) {
    const line = raw.trim();
    if (!line) {
      closeList();
      continue;
    }
    const bulletMatch = /^[-•*]\s+(.*)$/.exec(line);
    const headerMatch = /^(?:#{1,4}\s+(.+)|\*\*(.+?)\*\*:?)$/.exec(line);
    if (headerMatch && !bulletMatch) {
      closeList();
      const title = (headerMatch[1] ?? headerMatch[2] ?? "").replace(/:$/, "");
      html += `<h3 style="margin:20px 0 8px;font-size:15px;line-height:1.3;color:#111111;letter-spacing:0.01em">${escapeHtml(title)}</h3>`;
    } else if (bulletMatch) {
      if (!inList) {
        html += `<ul style="margin:6px 0 12px;padding-left:20px">`;
        inList = true;
      }
      html += `<li style="margin:4px 0;font-size:14px;line-height:1.55;color:#333333">${inline(bulletMatch[1] ?? "")}</li>`;
    } else {
      closeList();
      html += `<p style="margin:8px 0;font-size:14px;line-height:1.6;color:#333333">${inline(line)}</p>`;
    }
  }
  closeList();
  return html;
}

function meetingNotesEmail(input: {
  hostUsername: string;
  title: string;
  notes: string;
  meetingLink: string;
  transcript?: string;
}): { subject: string; html: string } {
  return {
    subject: `Meeting notes — ${input.title}`,
    html: emailShell(
      `Notes from “${escapeHtml(input.title)}”`,
      `<p ${EMAIL_P}>@${escapeHtml(input.hostUsername)} shared the AI-generated notes from a Whisper Meeting with you.</p>
       ${meetingNotesHtml(input.notes)}
       ${input.transcript ? meetingTranscriptHtml(input.transcript) : ""}
       <a href="${escapeHtml(input.meetingLink)}" ${EMAIL_BTN}>Open the meeting on Whisper</a>
       <p ${EMAIL_P}>Whisper Meetings include live video, captions, and AI notes — key points, decisions, and action items after every call.</p>
       <p ${EMAIL_P}>— The Whisper team</p>`
    ),
  };
}

async function handleMeetingNotesEmail(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: MeetingNotesEmailBody;
  try {
    body = (await request.json()) as MeetingNotesEmailBody;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const meetingId = (body.meetingId ?? "").trim();
  if (!meetingId) return json({ error: "missing_meeting_id" }, 400);
  const publicLink = body.link ? parseMeetingInvitation(body.link)?.href : meetingInvitationLink(meetingId);
  if (!publicLink) return json({ error: "invalid_link" }, 400);
  const notes = (body.notes ?? "").trim().slice(0, 16000);
  if (!notes) return json({ error: "missing_notes" }, 400);
  const title = (body.title ?? "").trim().slice(0, 200) || "Meeting";
  const hostUsername =
    (body.hostUsername ?? "").trim().replace(/^@/, "").slice(0, 40) || "host";
  const emailList = (body.emails ?? [])
    .map((e) => e.trim().toLowerCase())
    .filter((e) => e && isValidEmail(e))
    .slice(0, 20);
  if (emailList.length === 0) return json({ error: "no_valid_emails" }, 400);
  if (!env.RESEND_API_KEY) return json({ error: "not_configured" }, 503);
  // The full transcript always rides along (capped so the email stays
  // deliverable — the last lines are dropped, never the notes).
  const transcript = (body.transcript ?? "").trim().slice(0, 60_000);
  const mail = meetingNotesEmail({
    hostUsername,
    title,
    notes,
    meetingLink: publicLink,
    transcript: transcript || undefined,
  });
  let sent = 0;
  for (const email of emailList) {
    try {
      if (await sendEmail(env, email, mail.subject, mail.html)) sent++;
    } catch {
      // keep sending the rest
    }
  }
  if (sent === 0) return json({ error: "send_failed" }, 502);
  return json({ ok: true, sent });
}

// ---------------------------------------------------------------------------
// Whisper Meet — email invitations (the Google-Calendar-grade invite)
//
// POST /meetings/invite-email — a branded email with the when/where block,
// a Join button, the joining info, an Add-to-Google-Calendar link, and a
// real .ics attachment so it lands on any calendar app. Signed-in callers
// only; never a bare mailto.
// ---------------------------------------------------------------------------

interface MeetingInviteEmailBody {
  emails?: string[];
  title?: string;
  link?: string;
  hostUsername?: string;
  startsAt?: string | null;
  endsAt?: string | null;
  description?: string | null;
  code?: string | null;
  recurrence?: string | null;
  recurrenceLabel?: string | null;
  note?: string | null;
  timeZone?: string | null;
}

/** RFC 5545 text escaping. */
function icsText(value: string): string {
  return value
    .replace(/\\/g, "\\\\")
    .replace(/;/g, "\\;")
    .replace(/,/g, "\\,")
    .replace(/\r?\n/g, "\\n");
}

/** Fold a content line at 75 octets (RFC 5545 §3.1). */
function icsFold(line: string): string {
  const out: string[] = [];
  let rest = line;
  while (rest.length > 73) {
    out.push(rest.slice(0, 73));
    rest = ` ${rest.slice(73)}`;
  }
  out.push(rest);
  return out.join("\r\n");
}

/** 20260905T190000Z */
function icsUtc(d: Date): string {
  return d.toISOString().replace(/[-:]/g, "").replace(/\.\d{3}Z$/, "Z");
}

function toBase64Utf8(text: string): string {
  const bytes = new TextEncoder().encode(text);
  let bin = "";
  for (let i = 0; i < bytes.length; i += 1) bin += String.fromCharCode(bytes[i]);
  return btoa(bin);
}

function buildInviteIcs(input: {
  uid: string;
  title: string;
  link: string;
  hostUsername: string;
  start: Date;
  end: Date;
  description: string;
  recurrence: string | null;
  attendee: string;
}): string {
  const rrule =
    input.recurrence === "weekly"
      ? "RRULE:FREQ=WEEKLY;COUNT=8"
      : input.recurrence === "biweekly"
        ? "RRULE:FREQ=WEEKLY;INTERVAL=2;COUNT=8"
        : input.recurrence === "monthly"
          ? "RRULE:FREQ=MONTHLY;COUNT=8"
          : null;
  const lines = [
    "BEGIN:VCALENDAR",
    "VERSION:2.0",
    "PRODID:-//Whisper//Whisper Meet//EN",
    "CALSCALE:GREGORIAN",
    "METHOD:REQUEST",
    "BEGIN:VEVENT",
    `UID:${input.uid}`,
    `DTSTAMP:${icsUtc(new Date())}`,
    `DTSTART:${icsUtc(input.start)}`,
    `DTEND:${icsUtc(input.end)}`,
    `SUMMARY:${icsText(input.title)}`,
    `DESCRIPTION:${icsText(`Join with Whisper Meet: ${input.link}${input.description ? `\n\n${input.description}` : ""}`)}`,
    `LOCATION:${icsText(input.link)}`,
    `URL:${input.link}`,
    `ORGANIZER;CN=${icsText(`@${input.hostUsername} on Whisper`)}:mailto:meet@mydailywhisper.com`,
    `ATTENDEE;CUTYPE=INDIVIDUAL;ROLE=REQ-PARTICIPANT;PARTSTAT=NEEDS-ACTION;RSVP=TRUE:mailto:${input.attendee}`,
    ...(rrule ? [rrule] : []),
    "STATUS:CONFIRMED",
    "SEQUENCE:0",
    "TRANSP:OPAQUE",
    "BEGIN:VALARM",
    "TRIGGER:-PT10M",
    "ACTION:DISPLAY",
    `DESCRIPTION:${icsText(input.title)} starts in 10 minutes`,
    "END:VALARM",
    "END:VEVENT",
    "END:VCALENDAR",
  ];
  return lines.map(icsFold).join("\r\n") + "\r\n";
}

function googleCalendarLink(input: {
  title: string;
  start: Date;
  end: Date;
  link: string;
  description: string;
}): string {
  const params = new URLSearchParams({
    action: "TEMPLATE",
    text: input.title,
    dates: `${icsUtc(input.start)}/${icsUtc(input.end)}`,
    details: `Join with Whisper Meet: ${input.link}${input.description ? `\n\n${input.description}` : ""}`,
    location: input.link,
  });
  return `https://calendar.google.com/calendar/render?${params.toString()}`;
}

/** "Friday, September 5" + "7:00 – 7:30 PM" + short zone, in the guest's zone. */
function formatInviteWhen(
  start: Date,
  end: Date,
  timeZone: string
): { dayLine: string; timeLine: string; monthShort: string; dayNumber: string; shortWhen: string } {
  let tz = timeZone;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: tz });
  } catch {
    tz = "UTC";
  }
  const dayLine = new Intl.DateTimeFormat("en-US", {
    timeZone: tz,
    weekday: "long",
    month: "long",
    day: "numeric",
    year: "numeric",
  }).format(start);
  const timeFmt = new Intl.DateTimeFormat("en-US", { timeZone: tz, hour: "numeric", minute: "2-digit" });
  const zone =
    new Intl.DateTimeFormat("en-US", { timeZone: tz, timeZoneName: "short" })
      .formatToParts(start)
      .find((p) => p.type === "timeZoneName")?.value ?? tz;
  const timeLine = `${timeFmt.format(start)} – ${timeFmt.format(end)} ${zone}`;
  const monthShort = new Intl.DateTimeFormat("en-US", { timeZone: tz, month: "short" }).format(start).toUpperCase();
  const dayNumber = new Intl.DateTimeFormat("en-US", { timeZone: tz, day: "numeric" }).format(start);
  const shortWhen = `${new Intl.DateTimeFormat("en-US", { timeZone: tz, weekday: "short", month: "short", day: "numeric" }).format(start)} · ${timeFmt.format(start)} ${zone}`;
  return { dayLine, timeLine, monthShort, dayNumber, shortWhen };
}

function meetingInviteEmail(input: {
  title: string;
  link: string;
  hostUsername: string;
  start: Date | null;
  end: Date | null;
  description: string;
  code: string | null;
  recurrenceLabel: string | null;
  note: string | null;
  timeZone: string;
}): { subject: string; html: string } {
  const when = input.start && input.end ? formatInviteWhen(input.start, input.end, input.timeZone) : null;
  const gcal =
    input.start && input.end
      ? googleCalendarLink({
          title: input.title,
          start: input.start,
          end: input.end,
          link: input.link,
          description: input.description,
        })
      : null;
  const subject = when
    ? `Invitation: ${input.title} @ ${when.shortWhen}`
    : `Join now: ${input.title} — @${input.hostUsername} is inviting you`;
  const whenBlock = when
    ? `<table role="presentation" cellspacing="0" cellpadding="0" style="width:100%;border:1px solid #e7e5e4;border-radius:16px;margin:6px 0 18px;background:#fafaf9">
         <tr>
           <td style="width:64px;padding:14px 0 14px 16px;vertical-align:middle">
             <div style="width:56px;border-radius:12px;background:#111;color:#fff;text-align:center;padding:8px 0 9px">
               <div style="font-size:10px;font-weight:800;letter-spacing:0.14em">${escapeHtml(when.monthShort)}</div>
               <div style="font-size:22px;font-weight:800;line-height:1.1">${escapeHtml(when.dayNumber)}</div>
             </div>
           </td>
           <td style="padding:14px 16px;vertical-align:middle">
             <div style="font-size:15px;font-weight:700;color:#111">${escapeHtml(when.dayLine)}</div>
             <div style="font-size:14px;color:#44403c;margin-top:2px">${escapeHtml(when.timeLine)}</div>
             ${input.recurrenceLabel ? `<div style="font-size:12px;color:#78716c;margin-top:4px">Repeats · ${escapeHtml(input.recurrenceLabel)}</div>` : ""}
           </td>
         </tr>
       </table>`
    : `<div style="border:1px solid #fecaca;border-radius:16px;margin:6px 0 18px;background:#fff1f2;padding:14px 16px">
         <div style="font-size:13px;font-weight:800;letter-spacing:0.12em;color:#be123c">HAPPENING NOW</div>
         <div style="font-size:14px;color:#44403c;margin-top:2px">The room is open — join whenever you're ready.</div>
       </div>`;
  return {
    subject,
    html: emailShell(
      escapeHtml(input.title),
      `${input.note ? `<p ${EMAIL_P}>${escapeHtml(input.note)}</p>` : `<p ${EMAIL_P}>@${escapeHtml(input.hostUsername)} invited you to a Whisper Meet.</p>`}
       ${whenBlock}
       <a href="${escapeHtml(input.link)}" ${EMAIL_BTN}>Join with Whisper Meet</a>
       <div style="margin:22px 0 0;padding-top:18px;border-top:1px solid #e7e5e4">
         <div style="font-size:11px;font-weight:800;letter-spacing:0.14em;color:#78716c">JOINING INFO</div>
         <p style="margin:8px 0 0;font-size:14px;line-height:1.6;color:#111;word-break:break-all"><a href="${escapeHtml(input.link)}" style="color:#111">${escapeHtml(input.link)}</a></p>
         ${input.code ? `<p style="margin:4px 0 0;font-size:13px;color:#44403c">Meeting code: <strong>${escapeHtml(input.code)}</strong></p>` : ""}
         <p style="margin:10px 0 0;font-size:13px;line-height:1.6;color:#44403c">Open it in a browser or the Whisper app — no account needed to join as a guest.</p>
       </div>
       ${
         gcal
           ? `<div style="margin:18px 0 0;padding-top:16px;border-top:1px solid #e7e5e4">
                <p style="margin:0;font-size:13px;line-height:1.7;color:#44403c">
                  <a href="${escapeHtml(gcal)}" style="color:#111;font-weight:700">Add to Google Calendar</a>
                  &nbsp;·&nbsp; A calendar file (.ics) is attached for Apple Calendar, Outlook, and everything else.
                </p>
              </div>`
           : ""
       }
       ${
         input.description
           ? `<div style="margin:18px 0 0;padding-top:16px;border-top:1px solid #e7e5e4">
                <div style="font-size:11px;font-weight:800;letter-spacing:0.14em;color:#78716c">ABOUT</div>
                <p style="margin:8px 0 0;font-size:14px;line-height:1.65;color:#44403c;white-space:pre-wrap">${escapeHtml(input.description)}</p>
              </div>`
           : ""
       }
       <p style="margin:22px 0 0;font-size:12.5px;line-height:1.6;color:#78716c">Hosted by @${escapeHtml(input.hostUsername)} on Whisper. Whisper Meet has live video, captions, and Jasper's AI notes after every call.</p>`
    ),
  };
}

async function handleMeetingInviteEmail(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: MeetingInviteEmailBody;
  try {
    body = (await request.json()) as MeetingInviteEmailBody;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const title = (body.title ?? "").trim().slice(0, 200) || "Meeting";
  const invitation = parseMeetingInvitation((body.link ?? "").trim());
  if (!invitation) return json({ error: "invalid_link" }, 400);
  const link = invitation.href;
  const hostUsername = (body.hostUsername ?? "").trim().replace(/^@/, "").slice(0, 40) || "host";
  const emailList = (body.emails ?? [])
    .map((e) => e.trim().toLowerCase())
    .filter((e) => e && isValidEmail(e))
    .slice(0, 30);
  if (emailList.length === 0) return json({ error: "no_valid_emails" }, 400);
  if (!env.RESEND_API_KEY) return json({ error: "not_configured" }, 503);

  const start = body.startsAt ? new Date(body.startsAt) : null;
  const validStart = start && !Number.isNaN(start.getTime()) ? start : null;
  let end: Date | null = body.endsAt ? new Date(body.endsAt) : null;
  if (!end || Number.isNaN(end.getTime()) || (validStart && end.getTime() <= validStart.getTime())) {
    end = validStart ? new Date(validStart.getTime() + 30 * 60_000) : null;
  }
  const description = (body.description ?? "").trim().slice(0, 2000);
  const code = /^wsp-/i.test(invitation.idOrCode) ? invitation.idOrCode : null;
  const recurrence = (body.recurrence ?? "").trim().toLowerCase() || null;
  const recurrenceLabel = (body.recurrenceLabel ?? "").trim().slice(0, 60) || null;
  const note = (body.note ?? "").trim().slice(0, 300) || null;
  const timeZone = (body.timeZone ?? "").trim().slice(0, 64) || "UTC";

  const mail = meetingInviteEmail({
    title,
    link,
    hostUsername,
    start: validStart,
    end: validStart ? end : null,
    description,
    code,
    recurrenceLabel,
    note,
    timeZone,
  });
  const uid = `${code ?? link.split("/").filter(Boolean).pop() ?? crypto.randomUUID()}@mydailywhisper.com`;

  let sent = 0;
  for (const email of emailList) {
    try {
      const attachments =
        validStart && end
          ? [
              {
                filename: "whisper-meet-invite.ics",
                content: toBase64Utf8(
                  buildInviteIcs({
                    uid,
                    title,
                    link,
                    hostUsername,
                    start: validStart,
                    end,
                    description,
                    recurrence,
                    attendee: email,
                  })
                ),
              },
            ]
          : undefined;
      if (await sendEmail(env, email, mail.subject, mail.html, attachments)) sent++;
    } catch {
      // keep sending the rest
    }
  }
  if (sent === 0) return json({ error: "send_failed" }, 502);
  return json({ ok: true, sent });
}

// ---------------------------------------------------------------------------
// Ember deck-walkthrough narration audio
//
// When the walkthrough driver is on iOS, their device cannot mix Ember's
// voice into the outgoing call audio (native WebRTC has no aux-mix path), so
// every participant's device plays the same fixed script line locally
// instead. This endpoint turns one script line into Ember-voiced MP3.
// ---------------------------------------------------------------------------

/** The walkthrough narration script, indexed [slide][segment]. Mirrored from
 *  the web + iOS clients (lib/emberDeckTour.ts) — the endpoint only ever
 *  speaks these fixed lines, never client-supplied text, so it stays safe to
 *  serve without auth (guest viewers must hear the tour too). */
const TOUR_NARRATION: string[][] = [
  [
    "Hey everyone — I'm Jasper, Whisper's built-in intelligence, and I'll walk you through the deck. Whisper is a social platform with a real creator economy built in. Not promised — built and running.",
    "Creators, athletes, coaches, recruiters, and brands all earn in one place — posting, sponsorships, coaching, and recruiting share the same profile and the same wallet.",
    "And everything I'm about to show you is the live product with clearly marked sample data — the sliders slide and the cards open, so feel free to touch things as we go.",
  ],
  [
    "First, the money most people ask about: W-P-P, Whisper Paid Partners. You post Reels and threads like you already do, and you earn a share of ad revenue, paid out monthly through Stripe.",
    "There are three tiers. Partner opens at 1,000 followers and pays about $0.90 per thousand qualified views. Partner+ pays $1.40, and Elite pays $2.20 per thousand.",
    "Quick example — two hundred and fifty thousand monthly views at the Partner+ tier is about $350 every single month, on top of sponsorships and coaching.",
    "The calculator on this slide is the real one from our pitch deck — drag the followers and views sliders and watch the payout move. Go ahead, play with it while we talk.",
  ],
  [
    "Next, sponsorships. Brands post real offers in the marketplace, creators apply or get scouted, both sides can counter, and every deal is tracked automatically.",
    "Here's the trust piece: the brand's money goes into escrow up front, and it's released the moment the tracked post goes live. Nobody chases invoices, and Whisper keeps a flat 10 percent.",
    "On this slide are three sample brands — Apex Nutrition, Stride Athletics, and Forge Recovery Lab — with typical deals from a hundred and fifty dollars a post up to nine thousand a year.",
    "These are the actual brand card modals from the deck — tap one open and you'll see the requirements, the typical pay range, and the real apply flow, right here in the meeting.",
  ],
  [
    "For coaches, the business side is already wired. You set any monthly rate from 5 to 2,000 dollars, and clients subscribe directly on your profile — no invoices, no spreadsheets.",
    "Stripe handles the payouts automatically every month, and Whisper keeps just 10 percent — the rest lands in the coach's account.",
    "So a coach with just twelve clients at fifty dollars a month takes home five hundred and forty dollars, recurring, from day one. That's a real business, not a side hustle.",
  ],
  [
    "Behind all of this is a recruiting engine — scouts track talent in a live pipeline, run meetings exactly like this one, and every conversation files itself to the right prospect.",
    "And yes — this very call is getting live captions and AI notes. When we hang up, the key points and action items write themselves.",
    "That's the tour. I'm here the whole meeting — ask me anything out loud, or open the full interactive deck from the menu. Thanks for listening, everyone.",
  ],
];

/** GET /meetings/tour-audio?slide=&segment= — one narration line as MP3 in
 *  Ember's presenter voice. Cache-friendly: the script is fixed, so edges
 *  and devices can reuse the audio for a day. */
async function handleMeetingTourAudio(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.OPENAI_API_KEY) return json({ error: "ai_not_configured" }, 503);
  const url = new URL(request.url);
  const slide = Number.parseInt(url.searchParams.get("slide") ?? "", 10);
  const segment = Number.parseInt(url.searchParams.get("segment") ?? "", 10);
  const line =
    Number.isInteger(slide) && Number.isInteger(segment) && slide >= 0 && segment >= 0
      ? TOUR_NARRATION[slide]?.[segment]
      : undefined;
  if (!line) return json({ error: "unknown_segment" }, 404);
  const res = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini-tts",
      voice: "echo",
      input: line,
      instructions:
        "You are Jasper, a warm, confident presenter walking a live meeting through a pitch deck. Sound natural and human — friendly energy, clear pacing, never robotic.",
      response_format: "mp3",
    }),
  });
  if (!res.ok) {
    const text = await res.text();
    console.error("tour-audio TTS failed", {
      status: res.status,
      body: text.slice(0, 200),
    });
    return json({ error: "tts_failed" }, 502);
  }
  const audio = await res.arrayBuffer();
  return new Response(audio, {
    headers: {
      "Content-Type": "audio/mpeg",
      "Cache-Control": "public, max-age=86400",
      "Access-Control-Allow-Origin": "*",
    },
  });
}

/** GET /meetings/mine — signed-in user sees requests they submitted. */
async function handleMeetingListMine(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const uid = encodeURIComponent(user.userId);
  const rows = await supabaseSelect(
    env,
    `/whisper_meeting_requests?requester_user_id=eq.${uid}&order=created_at.desc&limit=100`
  );
  return json({ requests: rows ?? [] });
}

/** GET /meetings/recruiter — recruiter sees requests assigned to them. */
async function handleMeetingListRecruiter(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  const uid = encodeURIComponent(user.userId);
  const rows = await supabaseSelect(
    env,
    `/whisper_meeting_requests?recruiter_id=eq.${uid}&order=created_at.desc&limit=100`
  );
  return json({ requests: rows ?? [] });
}

interface MeetingDecideBody {
  id?: string;
  decision?: "approved" | "denied";
  meetingLink?: string;
  recruiterNote?: string;
}

/** POST /meetings/decide — recruiter approves or denies a request. */
async function handleMeetingDecide(
  request: Request,
  env: Env
): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;
  let body: MeetingDecideBody;
  try {
    body = (await request.json()) as MeetingDecideBody;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const id = (body.id ?? "").trim();
  if (!id) return json({ error: "missing_id" }, 400);
  const decision = body.decision === "approved" || body.decision === "denied"
    ? body.decision
    : null;
  if (!decision) return json({ error: "invalid_decision" }, 400);

  const suppliedLink = decision === "approved" ? (body.meetingLink ?? "").trim() : "";
  const meetingLink = parseMeetingInvitation(suppliedLink)?.href ?? suppliedLink;
  if (decision === "approved" && !/^https?:\/\//i.test(meetingLink)) {
    return json({ error: "invalid_meeting_link" }, 400);
  }
  const note = (body.recruiterNote ?? "").trim().slice(0, 2000) || null;

  const uid = encodeURIComponent(user.userId);
  const updated = await supabaseAdmin(
    env,
    `/whisper_meeting_requests?id=eq.${encodeURIComponent(id)}&recruiter_id=eq.${uid}`,
    {
      method: "PATCH",
      prefer: "return=representation",
      body: {
        status: decision,
        meeting_link: decision === "approved" ? meetingLink : null,
        recruiter_note: note,
        decided_at: new Date().toISOString(),
      },
    }
  );
  if (!updated.ok) return json({ error: "update_failed" }, 502);

  // Fetch the row to email the requester.
  const rows = await supabaseSelect(
    env,
    `/whisper_meeting_requests?id=eq.${encodeURIComponent(id)}&select=*`
  );
  const row = (rows?.[0] ?? null) as {
    requester_name: string;
    requester_email: string;
    requested_time: string;
    requester_timezone: string | null;
    message: string | null;
    recruiter_username: string | null;
    meeting_link: string | null;
    recruiter_note: string | null;
  } | null;
  if (row?.requester_email) {
    if (decision === "approved" && row.meeting_link) {
      const mail = recruiterMeetingInviteEmail({
        requesterName: row.requester_name,
        recruiterUsername: row.recruiter_username ?? "recruiter",
        requestedTime: row.requested_time,
        requesterTimezone: row.requester_timezone,
        message: row.message,
        meetingLink: row.meeting_link,
        recruiterNote: row.recruiter_note,
      });
      await sendEmail(env, row.requester_email, mail.subject, mail.html);
    } else if (decision === "denied") {
      const mail = meetingDeclinedEmail({
        requesterName: row.requester_name,
        recruiterUsername: row.recruiter_username ?? "recruiter",
        recruiterNote: row.recruiter_note,
      });
      await sendEmail(env, row.requester_email, mail.subject, mail.html);
    }
  }
  return json({ ok: true });
}

// ─────────────────────────────────────────────────────────────────────────────
// LiveKit token minting (inlined so the single-file deploy never loses the
// handler if a separate module fails to bundle on Cloudflare Workers).
// ─────────────────────────────────────────────────────────────────────────────
const livekitEnc = new TextEncoder();

function livekitBase64UrlEncode(data: ArrayBuffer | Uint8Array): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function livekitBase64UrlEncodeString(str: string): string {
  return livekitBase64UrlEncode(livekitEnc.encode(str));
}

async function livekitHmacSha256(key: string, message: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    livekitEnc.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  return crypto.subtle.sign("HMAC", cryptoKey, livekitEnc.encode(message));
}

async function mintLiveKitToken(
  apiKey: string,
  apiSecret: string,
  room: string,
  identity: string,
  name?: string
): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "HS256", typ: "JWT", kid: apiKey };
  const payload = {
    iss: apiKey,
    sub: identity,
    aud: "",
    nbf: now,
    exp: now + 3600,
    video: {
      roomJoin: true,
      room,
      canPublish: true,
      canSubscribe: true,
      canPublishData: true,
      hidden: false,
    },
    sid: crypto.randomUUID(),
    name: name ?? identity,
  };

  const headerB64 = livekitBase64UrlEncodeString(JSON.stringify(header));
  const payloadB64 = livekitBase64UrlEncodeString(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const sig = await livekitHmacSha256(apiSecret, signingInput);
  const sigB64 = livekitBase64UrlEncode(sig);

  return `${headerB64}.${payloadB64}.${sigB64}`;
}

async function handleLiveKitToken(request: Request, env: Env): Promise<Response> {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const apiKey = env.LIVEKIT_API_KEY;
  const apiSecret = env.LIVEKIT_API_SECRET;
  const livekitUrl = env.LIVEKIT_URL ?? "";

  if (!apiKey || !apiSecret) {
    return json({ error: "LiveKit credentials not configured" }, 500);
  }

  // Security sweep (Aug 2026): minting was unauthenticated — anyone could
  // forge a publish-capable token for ANY room under ANY identity. Every
  // real consumer is a signed-in app (iOS attaches the Supabase session;
  // meetings ride the Supabase mesh, not LiveKit), so a valid Whisper
  // session is now required. Identities prefixed "guest" stay reserved
  // for a future guest flow but still need a signed-in minter.
  const caller = await requireUser(request, env);
  if (caller instanceof Response) return caller;

  let body: { room?: string; identity?: string; name?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "Invalid JSON" }, 400);
  }

  const room = body.room?.trim();
  const identity = body.identity?.trim();
  if (!room || !identity) {
    return json({ error: "room and identity are required" }, 400);
  }
  if (room.length > 120 || identity.length > 120) {
    return json({ error: "room or identity too long" }, 400);
  }
  // A signed-in member may mint for their own id or a guest-prefixed
  // identity — never for another member's id (impersonation guard).
  const isSelf = identity.toLowerCase() === caller.userId.toLowerCase();
  const isGuest = /^guest[-_]/i.test(identity);
  if (!isSelf && !isGuest) {
    return json({ error: "identity_not_allowed" }, 403);
  }
  const name = (body.name ?? "").toString().slice(0, 80) || undefined;

  try {
    const token = await mintLiveKitToken(apiKey, apiSecret, room, identity, name);
    return json({ token, url: livekitUrl });
  } catch (err) {
    return json({ error: "Failed to mint token" }, 500);
  }
}

// ---------------------------------------------------------------------------
// Bot system — a crew of registered bot accounts (public.whisper_bots) that
// post real fitness/sports news, training tips, and motivation, and engage
// with real users' posts (likes + natural comments). Waves are triggered by
// POST /bots/run — call it from an external scheduler (e.g. cron-job.org
// every 2-3 hours) with the BROADCAST_SECRET bearer, or from the admin panel.
// ---------------------------------------------------------------------------

interface BotRow {
  user_id: string;
  username: string;
  persona: string;
}

interface BotConfigRow {
  paused: boolean;
  intensity: "calm" | "normal" | "lively";
  last_run_at: string | null;
}

const BOT_TIPS: Record<string, string[]> = {
  runner: [
    "Easy days easy, hard days hard. Most of your weekly miles should feel almost too slow \u2014 that's where the aerobic engine gets built.",
    "Cadence check: if your knees complain on downhills, try shorter, quicker steps. Same speed, way less impact.",
    "Long run fueling rule of thumb: anything over 75 minutes, bring carbs. Your future self at mile 10 says thanks.",
    "The 10 percent rule is a guideline, not a law \u2014 but jumping weekly mileage 40 percent is how calves file complaints.",
  ],
  lifter: [
    "Progressive overload is boring on purpose. Add a rep or 5 lbs each week and let a year do the heavy lifting.",
    "Your last warmup set should feel crisp, not tiring. If warmups are wearing you out, cut the volume, not the weight.",
    "Tempo is free gains: 3 seconds down on RDLs and you'll feel hamstrings you forgot existed.",
    "Log your lifts. The notebook doesn't lie, and 'I think I did 185 last week' is how plateaus are born.",
  ],
  yoga: [
    "Two minutes of box breathing before bed does more for recovery than an hour of scrolling recovery content.",
    "Tight hips after leg day? 90/90 switches, 2 minutes a side. Slow is the whole point.",
    "Mobility isn't a warmup chore \u2014 it's strength at end range. Own the position, don't just visit it.",
    "Your breath is the rep counter. If you can't breathe smoothly in a pose, you've gone deeper than today's body wants.",
  ],
  sportsfan: [
    "Watching film of your own rec-league games feels ridiculous until you spot the same mistake three games in a row.",
    "Hot take: conditioning wins more pickup games than talent. The best player in the fourth quarter is whoever can still run.",
    "Practice free throws tired. Nobody shoots them fresh in a real game.",
  ],
  crosstrain: [
    "Mix one strength day, one intervals day, and one long easy session a week and you're fitter than 90 percent of people. Consistency does the rest.",
    "Kettlebell swings: hinge, don't squat. The bell floats because your hips said so.",
    "Skipping rope 5 minutes a day quietly fixes your footwork, calves, and conditioning at once.",
  ],
  swimmer: [
    "Swim slower to swim faster: most stroke flaws show up when you rush. Count your strokes per lap and try to lower it.",
    "Kick from the hips, not the knees. Your quads aren't the motor, your core is.",
    "Open water tip: sight every 6-8 strokes, breathe away from the chop, and trust the line.",
  ],
  nutrition: [
    "Protein at breakfast is the easiest habit upgrade: 30g before noon and the afternoon snack goblin mostly disappears.",
    "Meal prep hack: cook proteins and grains in bulk, keep sauces separate. Same food, five different meals.",
    "Hydration check: if you only drink when thirsty during training, you're already behind. Sip early, sip often.",
    "Fiber is the most underrated 'supplement' in fitness. Beans are basically legal performance enhancement.",
  ],
  cyclist: [
    "Zone 2 is humbling: if you can't hold a conversation, you're not in it. Slow down and let the base build.",
    "Bike fit beats new wheels. A 30 dollar fit adjustment can buy you more watts than a 3000 dollar upgrade.",
    "Cadence drills once a week \u2014 spin at 100+ rpm for a few minutes \u2014 and grinding big gears stops feeling like the only option.",
  ],
};

const BOT_MOTIVATION: string[] = [
  "Nobody is coming to do the workout for you. Two years from now you'll be glad it was you.",
  "The session you don't want to do is usually the one that changes the week.",
  "Small brag: showed up today when the couch made a very compelling argument.",
  "Discipline is just remembering what you want most instead of what you want now.",
  "Rest days are training days for patience.",
  "You don't need a perfect plan. You need a repeatable Tuesday.",
  "Progress photos lie week to week and tell the truth year to year. Zoom out.",
  "The gym doesn't care about your mood, and honestly that's the best part.",
];

const BOT_COMMENTS: string[] = [
  "This is the kind of consistency that pays off. Keep going.",
  "Love to see it. What's the next goal?",
  "Strong work. The discipline shows.",
  "Saving this for motivation later.",
  "This showed up on my feed at exactly the right time.",
  "Respect. Most people never even start.",
  "Okay this is seriously impressive.",
  "The grind is quiet but the results are loud.",
  "More of this energy on my feed please.",
  "Adding this to my routine this week.",
];

/** Pull up to `limit` items from a sports RSS feed (title + link). */
async function fetchSportsHeadlines(
  limit = 6
): Promise<{ title: string; link: string }[]> {
  const feeds = [
    "https://www.espn.com/espn/rss/news",
    "https://feeds.bbci.co.uk/sport/rss.xml",
  ];
  const feed = feeds[Math.floor(Math.random() * feeds.length)];
  try {
    const res = await fetch(feed, {
      headers: { "User-Agent": "WhisperBot/1.0" },
    });
    if (!res.ok) return [];
    const xml = await res.text();
    const items: { title: string; link: string }[] = [];
    const itemRe = /<item>([\s\S]*?)<\/item>/g;
    let m: RegExpExecArray | null;
    while ((m = itemRe.exec(xml)) !== null && items.length < limit) {
      const block = m[1];
      const title = (
        /<title>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/title>/.exec(block)?.[1] ?? ""
      ).trim();
      const link = (
        /<link>(?:<!\[CDATA\[)?([\s\S]*?)(?:\]\]>)?<\/link>/.exec(block)?.[1] ?? ""
      ).trim();
      if (title && link && !title.includes("<")) {
        items.push({ title, link });
      }
    }
    return items;
  } catch {
    return [];
  }
}

function pick<T>(arr: T[]): T {
  return arr[Math.floor(Math.random() * arr.length)];
}

/** Run one bot activity wave: some bots post, most engage. */
async function runBotWave(env: Env): Promise<Record<string, unknown>> {
  const [botsRaw, configRaw] = await Promise.all([
    supabaseSelect(env, "/whisper_bots?select=user_id,username,persona&limit=50"),
    supabaseSelect(env, "/whisper_bot_config?id=eq.1&select=paused,intensity,last_run_at&limit=1"),
  ]);
  const bots = (botsRaw ?? []) as BotRow[];
  const config = ((configRaw ?? [])[0] ?? null) as BotConfigRow | null;
  if (bots.length === 0) return { ok: false, error: "no_bots_seeded" };
  if (config?.paused) return { ok: true, skipped: "paused" };

  const intensity = config?.intensity ?? "normal";
  const posterCount = intensity === "calm" ? 1 : intensity === "lively" ? 4 : 2;
  const engagerCount = intensity === "calm" ? 3 : intensity === "lively" ? 10 : 6;

  const shuffled = [...bots].sort(() => Math.random() - 0.5);
  const posters = shuffled.slice(0, posterCount);
  const engagers = shuffled.slice(posterCount, posterCount + engagerCount);

  let postsCreated = 0;
  let likesGiven = 0;
  let commentsGiven = 0;

  // — Posts — news (with real linked source), tips, or motivation.
  const headlines = await fetchSportsHeadlines();
  for (const bot of posters) {
    const roll = Math.random();
    let caption = "";
    if (roll < 0.4 && headlines.length > 0) {
      const item = headlines.splice(
        Math.floor(Math.random() * headlines.length),
        1
      )[0];
      const reactions = [
        "Seeing this everywhere today.",
        "Big if true.",
        "This one's worth a read.",
        "Sports never has a quiet week.",
        "Couldn't scroll past this one.",
      ];
      caption = `${pick(reactions)} ${item.title}\n\n${item.link}`;
    } else if (roll < 0.8) {
      const pool = BOT_TIPS[bot.persona] ?? BOT_MOTIVATION;
      caption = pick(pool);
    } else {
      caption = pick(BOT_MOTIVATION);
    }
    const created = await supabaseAdmin(env, "/whisper_posts", {
      method: "POST",
      prefer: "return=minimal",
      body: {
        user_id: bot.user_id,
        kind: "text",
        caption,
        media_urls: [],
        media_count: 0,
        media_kind: "text",
        is_ghost: false,
        is_reel: false,
      },
    });
    if (created.ok) postsCreated += 1;
  }

  // — Engagement — like + comment on recent posts (not their own).
  const since = new Date(Date.now() - 48 * 3600_000).toISOString();
  const recentRaw = await supabaseSelect(
    env,
    `/whisper_posts?created_at=gte.${encodeURIComponent(since)}&select=id,user_id&order=created_at.desc&limit=50`
  );
  const botIds = new Set(bots.map((b) => b.user_id));
  const recent = ((recentRaw ?? []) as { id: string; user_id: string }[]);

  for (const bot of engagers) {
    const candidates = recent.filter((p) => p.user_id !== bot.user_id);
    if (candidates.length === 0) continue;
    // Prefer real users' posts 2:1 over other bots'.
    const weighted = candidates.filter(
      (p) => !botIds.has(p.user_id) || Math.random() < 0.35
    );
    const pool = weighted.length > 0 ? weighted : candidates;

    // 1-3 likes per engager.
    const likeCount = 1 + Math.floor(Math.random() * 3);
    const liked = [...pool].sort(() => Math.random() - 0.5).slice(0, likeCount);
    for (const post of liked) {
      const res = await supabaseAdmin(
        env,
        "/whisper_post_likes?on_conflict=post_id,user_id",
        {
          method: "POST",
          prefer: "resolution=ignore-duplicates,return=minimal",
          body: { post_id: post.id, user_id: bot.user_id },
        }
      );
      if (res.ok) likesGiven += 1;
    }

    // ~40% of engagers leave one comment.
    if (Math.random() < 0.4 && liked.length > 0) {
      const target = liked[0];
      const res = await supabaseAdmin(env, "/whisper_post_comments", {
        method: "POST",
        prefer: "return=minimal",
        body: {
          post_id: target.id,
          user_id: bot.user_id,
          username: bot.username,
          body: pick(BOT_COMMENTS),
        },
      });
      if (res.ok) commentsGiven += 1;
    }
  }

  await supabaseAdmin(env, "/whisper_bot_config?id=eq.1", {
    method: "PATCH",
    body: { last_run_at: new Date().toISOString(), updated_at: new Date().toISOString() },
  });

  return {
    ok: true,
    intensity,
    postsCreated,
    likesGiven,
    commentsGiven,
    posters: posters.map((b) => b.username),
  };
}

/** Bearer check: BROADCAST_SECRET (scheduler) or a signed-in admin. */
async function requireBotAccess(
  request: Request,
  env: Env
): Promise<true | Response> {
  const auth = request.headers.get("Authorization") ?? "";
  const token = auth.startsWith("Bearer ") ? auth.slice(7) : "";
  if (env.BROADCAST_SECRET && token === env.BROADCAST_SECRET) return true;
  const admin = await requireAdmin(request, env);
  if (admin instanceof Response) return admin;
  return true;
}

async function handleBotsRun(request: Request, env: Env): Promise<Response> {
  const access = await requireBotAccess(request, env);
  if (access !== true) return access;
  const result = await runBotWave(env);
  return json(result);
}

async function handleBotsStatus(request: Request, env: Env): Promise<Response> {
  const access = await requireBotAccess(request, env);
  if (access !== true) return access;
  const [configRaw, botsRaw] = await Promise.all([
    supabaseSelect(env, "/whisper_bot_config?id=eq.1&select=paused,intensity,last_run_at&limit=1"),
    supabaseSelect(env, "/whisper_bots?select=username,persona&limit=50"),
  ]);
  return json({
    config: (configRaw ?? [])[0] ?? null,
    bots: botsRaw ?? [],
  });
}

async function handleBotsConfig(request: Request, env: Env): Promise<Response> {
  const access = await requireBotAccess(request, env);
  if (access !== true) return access;
  let body: { paused?: boolean; intensity?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_body" }, 400);
  }
  const patch: Record<string, unknown> = { updated_at: new Date().toISOString() };
  if (typeof body.paused === "boolean") patch.paused = body.paused;
  if (
    body.intensity === "calm" ||
    body.intensity === "normal" ||
    body.intensity === "lively"
  ) {
    patch.intensity = body.intensity;
  }
  const res = await supabaseAdmin(env, "/whisper_bot_config?id=eq.1", {
    method: "PATCH",
    body: patch,
  });
  if (!res.ok) return json({ error: "update_failed" }, 502);
  return json({ ok: true });
}

// ---------------------------------------------------------------------------
// Ember AI proxy — server-side OpenAI chat completions for signed-in users.
// Production web builds on the custom domain ship no client AI credentials,
// so Ember, meeting notes, and every AI feature route through here. The
// OpenAI key never leaves the server.
// ---------------------------------------------------------------------------

interface AiChatBody {
  messages?: { role?: string; content?: unknown }[];
  maxTokens?: number;
  max_tokens?: number;
}

async function handleAiChat(request: Request, env: Env): Promise<Response> {
  if (!env.OPENAI_API_KEY) return json({ error: "ai_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: AiChatBody;
  try {
    body = (await request.json()) as AiChatBody;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const messages = Array.isArray(body.messages) ? body.messages : [];
  if (messages.length === 0 || messages.length > 40) {
    return json({ error: "invalid_messages" }, 400);
  }
  // Text plus optional image parts — hard-capped so nobody can relay huge blobs.
  if (JSON.stringify(messages).length > 600_000) {
    return json({ error: "payload_too_large" }, 413);
  }
  const maxTokens = clampInt(body.max_tokens ?? body.maxTokens, 16, 1600, 700);

  const upstream = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model: "gpt-4o", max_tokens: maxTokens, messages }),
  });
  if (!upstream.ok) {
    const text = await upstream.text();
    console.error("AI chat upstream failed", {
      status: upstream.status,
      body: text.slice(0, 200),
    });
    return json({ error: "upstream_failed" }, 502);
  }
  const data = (await upstream.json()) as {
    choices?: { message?: { content?: string } }[];
  };
  const content = data.choices?.[0]?.message?.content ?? "";
  if (!content) return json({ error: "empty_reply" }, 502);
  // OpenAI-shaped body so every client transport parses identically.
  return json({ choices: [{ message: { content } }] });
}

interface AiWebSearchBody {
  query?: string;
  maxTokens?: number;
}

/**
 * REAL web search for Jasper — OpenAI's Responses API with the hosted
 * web_search tool. The model genuinely searches and crawls the live web,
 * and citations come back as url annotations, so the answer ships with
 * real sources instead of prompted guesses. Used by Jasper chat + meetings
 * on both apps.
 */
async function handleAiWebSearch(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.OPENAI_API_KEY) return json({ error: "ai_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: AiWebSearchBody;
  try {
    body = (await request.json()) as AiWebSearchBody;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const query =
    typeof body.query === "string" ? body.query.trim().slice(0, 2000) : "";
  if (!query) return json({ error: "missing_query" }, 400);
  const maxTokens = clampInt(body.maxTokens, 200, 1600, 900);

  const call = (toolType: string): Promise<Response> =>
    fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        tools: [{ type: toolType }],
        input: [
          {
            role: "system",
            content:
              "You are a research assistant. Search the web for current, factual information before answering. Answer plainly and concisely (2-6 short paragraphs max, no markdown headings). Cite what you found.",
          },
          { role: "user", content: query },
        ],
        max_output_tokens: maxTokens,
      }),
    });

  // Tool naming differs across API generations — try the GA name, fall back
  // to the preview name so the route survives OpenAI's rename.
  let upstream = await call("web_search");
  if (!upstream.ok && (upstream.status === 400 || upstream.status === 404)) {
    upstream = await call("web_search_preview");
  }
  if (!upstream.ok) {
    const text = await upstream.text();
    console.error("AI websearch upstream failed", {
      status: upstream.status,
      body: text.slice(0, 200),
    });
    return json({ error: "upstream_failed" }, 502);
  }

  const data2 = (await upstream.json()) as {
    output?: {
      type?: string;
      content?: {
        type?: string;
        text?: string;
        annotations?: { type?: string; url?: string; title?: string }[];
      }[];
    }[];
  };

  let answer = "";
  const sources: { title: string; url: string }[] = [];
  const seen = new Set<string>();
  for (const item of data2.output ?? []) {
    if (item.type !== "message") continue;
    for (const part of item.content ?? []) {
      if (typeof part.text === "string" && part.text.trim()) {
        answer += (answer ? "\n\n" : "") + part.text.trim();
      }
      for (const a of part.annotations ?? []) {
        if (
          a.type === "url_citation" &&
          typeof a.url === "string" &&
          /^https?:\/\//.test(a.url) &&
          !seen.has(a.url)
        ) {
          seen.add(a.url);
          sources.push({
            title: (a.title ?? "").trim().slice(0, 140) || a.url,
            url: a.url,
          });
        }
      }
    }
  }
  answer = answer.trim();
  if (!answer) return json({ error: "empty_reply" }, 502);
  return json({ answer, sources: sources.slice(0, 8) });
}

interface AiTranscribeBody {
  audio?: string;
  mediaType?: string;
}

/**
 * Server-side speech-to-text proxy. The meeting caption recorder fallback
 * posts base64 audio chunks here when the browser has no native Web Speech
 * support and the build ships no gateway credentials — exactly the
 * production mydailywhisper.com case. Without this route those hosts saw
 * "transcription unavailable" and ended calls with zero transcript, which
 * silently killed AI notes.
 */
async function handleAiTranscribe(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.OPENAI_API_KEY) return json({ error: "ai_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: AiTranscribeBody;
  try {
    body = (await request.json()) as AiTranscribeBody;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const audio = typeof body.audio === "string" ? body.audio : "";
  if (!audio) return json({ error: "missing_audio" }, 400);
  // ~9 MB of base64 ≈ 6.75 MB of audio — far beyond a 15s caption chunk.
  if (audio.length > 9_000_000) return json({ error: "payload_too_large" }, 413);

  let bytes: Uint8Array;
  try {
    const binary = atob(audio);
    bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  } catch {
    return json({ error: "invalid_base64" }, 400);
  }

  const mediaType =
    typeof body.mediaType === "string" && body.mediaType
      ? body.mediaType
      : "audio/webm";
  const { meetingAudioFile, transcribeMeetingAudio } = await import('./meeting-audio');
  try { return await transcribeMeetingAudio(meetingAudioFile(bytes, mediaType), env.OPENAI_API_KEY, false); }
  catch { return json({ error: 'invalid_audio', retryable: false }, 422); }
}

// ---------------------------------------------------------------------------
// Instagram profile photos — recruiter prospect cards
// ---------------------------------------------------------------------------

interface IgWebProfile {
  data?: {
    user?: {
      full_name?: string;
      profile_pic_url?: string;
      profile_pic_url_hd?: string;
      edge_followed_by?: { count?: number };
      edge_owner_to_timeline_media?: {
        edges?: {
          node?: {
            display_url?: string;
            thumbnail_src?: string;
            is_video?: boolean;
          };
        }[];
      };
    };
  };
}

/**
 * Best-effort public Instagram gallery for a prospect handle — profile
 * photo + recent grid thumbnails — so recruiters can show the team what a
 * prospect looks like while presenting. Instagram aggressively blocks
 * datacenter scraping, so this degrades gracefully to `{ok:false}` and the
 * client falls back to the unavatar profile picture. Results are cached at
 * the edge (6h success / 10min failure) to stay polite.
 */
async function handleIgPhotos(request: Request, env: Env): Promise<Response> {
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  const url = new URL(request.url);
  const raw = (url.searchParams.get("handle") ?? "")
    .trim()
    .replace(/^@/, "")
    .replace(/^https?:\/\/(www\.)?instagram\.com\//i, "")
    .replace(/[/?#].*$/, "")
    .toLowerCase();
  if (!raw || !/^[a-z0-9._]{1,30}$/.test(raw)) {
    return json({ ok: false, error: "invalid_handle" }, 400);
  }

  const cache = (caches as unknown as { default: Cache }).default;
  const cacheKey = new Request(`https://ig-photos.internal/${raw}`);
  const cached = await cache.match(cacheKey).catch(() => undefined);
  if (cached) {
    const cachedBody = await cached.text();
    return new Response(cachedBody, {
      status: 200,
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    });
  }

  let payload: Record<string, unknown> = { ok: false, handle: raw, photos: [] };
  let ttl = 600;
  try {
    const upstream = await fetch(
      `https://i.instagram.com/api/v1/users/web_profile_info/?username=${encodeURIComponent(raw)}`,
      {
        headers: {
          "User-Agent":
            "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
          "x-ig-app-id": "936619743392459",
          Accept: "application/json",
        },
      }
    );
    if (upstream.ok) {
      const parsed = (await upstream.json()) as IgWebProfile;
      const igUser = parsed.data?.user;
      if (igUser) {
        const photos = (igUser.edge_owner_to_timeline_media?.edges ?? [])
          .map((e) => e.node?.thumbnail_src || e.node?.display_url || "")
          .filter((u) => !!u)
          .slice(0, 12);
        payload = {
          ok: true,
          handle: raw,
          fullName: igUser.full_name ?? null,
          profilePic:
            igUser.profile_pic_url_hd ?? igUser.profile_pic_url ?? null,
          followers: igUser.edge_followed_by?.count ?? null,
          photos,
        };
        ttl = 21600;
      }
    }
  } catch {
    /* blocked or offline — the graceful fallback below applies */
  }

  const responseBody = JSON.stringify(payload);
  await cache
    .put(
      cacheKey,
      new Response(responseBody, {
        headers: {
          "Content-Type": "application/json",
          "Cache-Control": `public, max-age=${ttl}`,
        },
      })
    )
    .catch(() => undefined);
  return new Response(responseBody, {
    status: 200,
    headers: { "Content-Type": "application/json", ...CORS_HEADERS },
  });
}

/**
 * Mints a short-lived OpenAI Realtime client secret so signed-in users can
 * open unrelated Jasper/Meet speech sessions without a client-side API key.
 * Knot calls must use the separate shared-Rork voice route, never this one.
 */
async function handleAiRealtimeToken(
  request: Request,
  env: Env
): Promise<Response> {
  if (!env.OPENAI_API_KEY) return json({ error: "ai_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  // Legacy welcome bodies are deliberately rejected, not claimed or migrated.
  // Ordinary Jasper/Meet callers use a bodyless request and retain their route.
  if (request.body !== null) return json({ error: 'use_knot_voice_route' }, 400);
  const signal = AbortSignal.any([request.signal, AbortSignal.timeout(14000)]);
  const upstream = await fetch(
    "https://api.openai.com/v1/realtime/client_secrets",
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      signal,
      body: JSON.stringify({
        expires_after: { anchor: "created_at", seconds: 600 },
        session: {
          type: "realtime",
          model: "gpt-realtime",
          audio: { output: { voice: "echo" } },
        },
      }),
    }
  );
  if (!upstream.ok) {
    await upstream.body?.cancel();
    // Log status only, never credentials, instructions or a provider body.
    console.error("Realtime token upstream failed", { status: upstream.status });
    return json({ error: "upstream_failed" }, 502);
  }
  const data = (await upstream.json()) as {
    value?: string;
    expires_at?: number;
  };
  if (!data.value) return json({ error: "empty_token" }, 502);
  return json({
    value: data.value,
    expiresAt: data.expires_at ?? null,
    model: "gpt-realtime",
  });
}

// ---------------------------------------------------------------------------
// AI speech + image proxies — server-side OpenAI so no client ever ships the
// key. /ai/speech streams TTS audio (Jasper voice features); /ai/image
// powers Jasper Imagine. Both require a signed-in user.
// ---------------------------------------------------------------------------

const AI_SPEECH_VOICES = new Set([
  "alloy",
  "ash",
  "ballad",
  "coral",
  "echo",
  "fable",
  "onyx",
  "nova",
  "sage",
  "shimmer",
  "verse",
]);
const AI_SPEECH_MODELS = new Set(["gpt-4o-mini-tts", "tts-1", "tts-1-hd"]);

async function handleAiSpeech(request: Request, env: Env): Promise<Response> {
  if (!env.OPENAI_API_KEY) return json({ error: "ai_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: {
    text?: string;
    voice?: string;
    model?: string;
    format?: string;
    speed?: number;
    instructions?: string;
  };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const text = String(body.text ?? "").trim();
  if (!text) return json({ error: "missing_text" }, 400);
  if (text.length > 4000) return json({ error: "payload_too_large" }, 413);
  const voice = AI_SPEECH_VOICES.has(body.voice ?? "")
    ? (body.voice as string)
    : "echo";
  const model = AI_SPEECH_MODELS.has(body.model ?? "")
    ? (body.model as string)
    : "gpt-4o-mini-tts";
  const format = body.format === "wav" ? "wav" : "mp3";
  const payload: Record<string, unknown> = {
    model,
    voice,
    input: text,
    response_format: format,
  };
  if (typeof body.speed === "number" && Number.isFinite(body.speed)) {
    payload.speed = Math.min(2, Math.max(0.5, body.speed));
  }
  if (
    typeof body.instructions === "string" &&
    body.instructions.trim() &&
    model === "gpt-4o-mini-tts"
  ) {
    payload.instructions = body.instructions.trim().slice(0, 500);
  }

  const upstream = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(payload),
  });
  if (!upstream.ok || !upstream.body) {
    const t = await upstream.text();
    console.error("AI speech upstream failed", {
      status: upstream.status,
      body: t.slice(0, 200),
    });
    return json({ error: "upstream_failed" }, 502);
  }
  return new Response(upstream.body, {
    status: 200,
    headers: {
      "Content-Type": format === "wav" ? "audio/wav" : "audio/mpeg",
      "Cache-Control": "no-store",
      ...CORS_HEADERS,
    },
  });
}

async function handleAiImage(request: Request, env: Env): Promise<Response> {
  if (!env.OPENAI_API_KEY) return json({ error: "ai_not_configured" }, 503);
  const user = await requireUser(request, env);
  if (user instanceof Response) return user;

  let body: { prompt?: string; size?: string };
  try {
    body = (await request.json()) as typeof body;
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  const prompt = String(body.prompt ?? "").trim();
  if (!prompt) return json({ error: "missing_prompt" }, 400);
  if (prompt.length > 4000) return json({ error: "payload_too_large" }, 413);
  const size = ["1024x1024", "1024x1536", "1536x1024", "1024x1792", "1792x1024"].includes(
    body.size ?? ""
  )
    ? (body.size as string)
    : "1024x1024";

  const call = (payload: Record<string, unknown>) =>
    fetch("https://api.openai.com/v1/images/generations", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.OPENAI_API_KEY}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(payload),
    });

  // gpt-image-1 first; fall back to dall-e-3 when the account lacks access.
  let upstream = await call({
    model: "gpt-image-1",
    prompt,
    size: ["1024x1024", "1024x1536", "1536x1024"].includes(size)
      ? size
      : "1024x1024",
    n: 1,
  });
  if (!upstream.ok) {
    upstream = await call({
      model: "dall-e-3",
      prompt,
      size: ["1024x1024", "1792x1024", "1024x1792"].includes(size)
        ? size
        : "1024x1024",
      n: 1,
      response_format: "b64_json",
    });
  }
  if (!upstream.ok) {
    const t = await upstream.text();
    console.error("AI image upstream failed", {
      status: upstream.status,
      body: t.slice(0, 200),
    });
    return json({ error: "upstream_failed" }, 502);
  }
  const data = (await upstream.json()) as {
    data?: { b64_json?: string; url?: string }[];
  };
  const first = data.data?.[0];
  if (!first?.b64_json && !first?.url) return json({ error: "empty_image" }, 502);
  return json({ b64: first.b64_json ?? null, url: first.url ?? null });
}

// ─── WebRTC ICE servers proxy ────────────────────────────────────────────────
// Meetings/live rooms need TURN credentials from the Rork toolkit. Rork-built
// clients carry the toolkit key at build time, but deploys through third-party
// hosts (the Vercel production site) can ship WITHOUT it — those clients used
// to fall back to STUN-only silently, and anyone behind a strict NAT sent no
// audio/video. This proxy serves fresh ICE servers using the server-side key.
// Cached in-memory for a fraction of the credential TTL so a whole meeting
// joining at once stays well inside the toolkit's per-project rate limit.

let iceServersCache: { body: string; expiresAt: number } | null = null;

async function handleIceServers(env: Env): Promise<Response> {
  const secret =
    env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY ?? env.RORK_TOOLKIT_SECRET_KEY;
  if (!secret) return json({ error: "ice_not_configured" }, 503);
  const base = (env.EXPO_PUBLIC_TOOLKIT_URL ?? "https://toolkit.rork.com").replace(
    /\/+$/,
    ""
  );
  const now = Date.now();
  if (iceServersCache && iceServersCache.expiresAt > now) {
    return new Response(iceServersCache.body, {
      status: 200,
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    });
  }
  try {
    const upstream = await fetch(`${base}/v2/webrtc/ice-servers`, {
      headers: { Authorization: `Bearer ${secret}` },
    });
    if (!upstream.ok) return json({ error: "ice_upstream_failed" }, 502);
    const data = (await upstream.json()) as {
      iceServers?: unknown[];
      ttlSeconds?: number;
    };
    if (!Array.isArray(data.iceServers) || data.iceServers.length === 0) {
      return json({ error: "ice_empty" }, 502);
    }
    const ttlSeconds =
      typeof data.ttlSeconds === "number" && data.ttlSeconds > 0
        ? data.ttlSeconds
        : 300;
    const body = JSON.stringify({ iceServers: data.iceServers, ttlSeconds });
    // Serve the cached list for at most a quarter of its lifetime (cap 10m)
    // so every client still receives plenty of remaining validity.
    iceServersCache = {
      body,
      expiresAt: now + Math.min(ttlSeconds * 250, 10 * 60_000),
    };
    return new Response(body, {
      status: 200,
      headers: { "Content-Type": "application/json", ...CORS_HEADERS },
    });
  } catch {
    return json({ error: "ice_unreachable" }, 502);
  }
}

export default {
  async fetch(request: Request, rawEnv: Env, execution?: ExecutionContext): Promise<Response> {
    return tracedKnotRequest(request, false, owned => serveRequest(owned, rawEnv, execution));
  },
};
async function serveRequest(request: Request, rawEnv: Env, execution?: ExecutionContext): Promise<Response> {
    const env = normalizeStripeEnv(rawEnv);
    const url = new URL(request.url);
    if (url.pathname === teamsEventPath) return receiveTeamsEvent(request, env);
    // Keep the Supabase session distinct from hosting-layer Authorization handling.
    // It is still verified by requireUser; this header is never trusted as an identity.
    if ((url.pathname.startsWith('/jasper-meetings/') || url.pathname.startsWith('/knot/background') || url.pathname === '/knot/turns' || url.pathname.startsWith('/knot/turns/') || url.pathname.startsWith('/knot/conversations') || url.pathname === '/knot/documents' || url.pathname.startsWith('/knot/artifacts/') || url.pathname.startsWith('/knot/shell/') || url.pathname.startsWith('/knot/persona/') || url.pathname.startsWith('/knot/browser/') || ['/notebook/transcribe', '/ai/transcribe', '/knot/chat/stream', '/knot/voice/token', '/knot/voice/end'].includes(url.pathname)) && request.headers.has('X-Whisper-Authorization')) {
      const headers = new Headers(request.headers);
      headers.set('Authorization', headers.get('X-Whisper-Authorization') ?? '');
      request = new Request(request, { headers });
    }

    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS_HEADERS });
    }

    if (url.pathname.startsWith("/jasper-meetings/")) {
      if (request.method === "GET" && ["/jasper-meetings/google/start", "/jasper-meetings/google/callback"].includes(url.pathname)) return googlePublicRoute(request, env);
      const identity = await requireUser(request, env);
      if (identity instanceof Response) return identity;
      return routeJasperMeetings(request, env, identity.userId, identity.emailVerified ? identity.email : null);
    }

    if (url.pathname === "/webrtc/ice-servers" && request.method === "GET") {
      return handleIceServers(env);
    }

    if (url.pathname === "/link/preview" && request.method === "GET") {
      return handleLinkPreview(url.searchParams.get("url") ?? "");
    }

    if (url.pathname === "/ping") {
      const key = env.STRIPE_SECRET_KEY ?? "";
      const keyMode = key.startsWith("sk_test_")
        ? "test"
        : key.startsWith("sk_live_")
          ? "live"
          : key.startsWith("pk_")
            ? "publishable_key_misplaced"
            : key.startsWith("rk_")
              ? "restricted"
              : key
                ? "unknown_format"
                : "missing";
      // Optional migration check: /ping?db=1 probes the money-path tables
      // so we can confirm SQL migrations without dashboard access.
      let db: Record<string, string> | undefined;
      if (url.searchParams.get("db") === "1") {
        const [receipts, refunds, coachPlans, businessAdsV3] =
          await Promise.all([
            dbProbe(env, "/whisper_receipts?select=id&limit=1"),
            dbProbe(env, "/whisper_refund_requests?select=id&limit=1"),
            dbProbe(env, "/whisper_coach_plans?select=id&limit=1"),
            dbProbe(
              env,
              "/business_ads?select=target_roles,daily_impression_cap&limit=1"
            ),
          ]);
        db = { receipts, refunds, coachPlans, businessAdsV3 };
      }
      // Optional Stripe diagnostic: /ping?stripe=1 dry-runs the EXACT
      // embedded checkout call the apps make (created, then immediately
      // expired — nobody is charged, nothing fulfills) and reads the
      // account's charge capability. Sanitized error text only — never
      // key material.
      let stripeDiag: Record<string, unknown> | undefined;
      if (url.searchParams.get("stripe") === "1") {
        if (!env.STRIPE_SECRET_KEY) {
          stripeDiag = { accountOk: false, accountError: "no_secret_key" };
        } else {
          const account = await stripeRequest(env, "/account");
          const acct = account.data as {
            charges_enabled?: boolean;
            details_submitted?: boolean;
            payouts_enabled?: boolean;
            error?: { message?: string };
          };
          const dry = new URLSearchParams();
          dry.set("mode", "subscription");
          dry.set("ui_mode", "embedded_page");
          dry.set(
            "return_url",
            "https://mydailywhisper.com/billing/success?embedded=1&session_id={CHECKOUT_SESSION_ID}"
          );
          dry.set("line_items[0][quantity]", "1");
          dry.set("line_items[0][price_data][currency]", "usd");
          dry.set("line_items[0][price_data][unit_amount]", "1499");
          dry.set("line_items[0][price_data][recurring][interval]", "month");
          dry.set(
            "line_items[0][price_data][product_data][name]",
            "Whisper One (diagnostic)"
          );
          dry.set("allow_promotion_codes", "true");
          dry.set("metadata[diagnostic]", "1");
          const dryRun = await stripeRequest(env, "/checkout/sessions", dry);
          const dryErr = dryRun.data.error as
            | { message?: string; type?: string; code?: string }
            | undefined;
          const dryId =
            typeof dryRun.data.id === "string" ? dryRun.data.id : null;
          if (dryRun.ok && dryId) {
            await stripeRequest(
              env,
              `/checkout/sessions/${dryId}/expire`,
              new URLSearchParams()
            );
          }
          stripeDiag = {
            accountOk: account.ok,
            chargesEnabled: acct.charges_enabled ?? null,
            detailsSubmitted: acct.details_submitted ?? null,
            payoutsEnabled: acct.payouts_enabled ?? null,
            accountError: account.ok ? null : (acct.error?.message ?? null),
            checkoutDryRun: dryRun.ok ? "ok" : "failed",
            checkoutStatus: dryRun.status,
            checkoutErrorType: dryErr?.type ?? null,
            checkoutErrorCode: dryErr?.code ?? null,
            checkoutErrorMessage: dryErr?.message ?? null,
          };
        }
      }
      // Optional payout-account sweep: /ping?connect=1 verifies every
      // stored Connect payout account against the CURRENT key mode and
      // clears the ones Stripe no longer recognises (test-mode accounts
      // being read with live keys). Reports counts only — never ids.
      let connectDiag: Record<string, number | string> | undefined;
      if (url.searchParams.get("connect") === "1" && env.STRIPE_SECRET_KEY) {
        const rows = await supabaseSelect(
          env,
          "/whisper_coach_connect?select=user_id,stripe_account_id&limit=40"
        );
        let checked = 0;
        let cleared = 0;
        for (const raw of rows ?? []) {
          const row = raw as {
            user_id?: string;
            stripe_account_id?: string;
          };
          if (!row.user_id || !row.stripe_account_id) continue;
          checked += 1;
          const account = await stripeRequest(
            env,
            `/accounts/${encodeURIComponent(row.stripe_account_id)}`
          );
          if (!account.ok && isMissingAccountError(account)) {
            await clearStaleConnect(env, row.user_id, row.stripe_account_id);
            cleared += 1;
          }
        }
        // Creation dry-run: mint a live Express account with the EXACT
        // params "Link bank account" uses (card_payments + transfers pair,
        // the combo Stripe auto-approves), then delete it immediately.
        // Status only — never ids.
        let creation = "skipped";
        const probeParams = new URLSearchParams();
        probeParams.set("type", "express");
        probeParams.set("capabilities[transfers][requested]", "true");
        probeParams.set("capabilities[card_payments][requested]", "true");
        probeParams.set("business_type", "individual");
        probeParams.set("business_profile[url]", SITE_URL);
        probeParams.set("business_profile[mcc]", "7298");
        probeParams.set(
          "business_profile[product_description]",
          "Personal fitness coaching on Whisper"
        );
        probeParams.set("settings[payouts][schedule][interval]", "manual");
        probeParams.set("metadata[diagnosticProbe]", "true");
        const probe = await stripeRequest(env, "/accounts", probeParams);
        let embeddedOnboarding = "skipped";
        if (probe.ok && typeof probe.data.id === "string") {
          creation = "ok";
          // Also dry-run the EMBEDDED onboarding session (the in-app bank
          // sheet) against the probe account before deleting it, so the
          // in-app flow is provably working — or the exact error is logged.
          if (env.STRIPE_PUBLISHABLE_KEY) {
            const sess = new URLSearchParams();
            sess.set("account", probe.data.id);
            sess.set("components[account_onboarding][enabled]", "true");
            sess.set(
              "components[account_onboarding][features][external_account_collection]",
              "true"
            );
            const s = await stripeRequest(env, "/account_sessions", sess);
            embeddedOnboarding =
              s.ok && typeof s.data.client_secret === "string"
                ? "ok"
                : `error: ${(
                    (s.data.error as { message?: string } | undefined)
                      ?.message ?? "unknown"
                  ).slice(0, 140)}`;
          }
          await stripeDelete(
            env,
            `/accounts/${encodeURIComponent(probe.data.id)}`
          );
        } else {
          const err = probe.data.error as { message?: string } | undefined;
          creation = `error: ${(err?.message ?? "unknown").slice(0, 140)}`;
        }
        connectDiag = { checked, cleared, creation, embeddedOnboarding };
      }
      return json({
        ok: true,
        now: new Date().toISOString(),
        stripeKeyMode: keyMode,
        stripePublishableKeyMode: (env.STRIPE_PUBLISHABLE_KEY ?? "").startsWith(
          "pk_test_"
        )
          ? "test"
          : (env.STRIPE_PUBLISHABLE_KEY ?? "").startsWith("pk_live_")
            ? "live"
            : env.STRIPE_PUBLISHABLE_KEY
              ? "unknown_format"
              : "missing",
        webhookSecretSet: Boolean(env.STRIPE_WEBHOOK_SECRET),
        supabaseAdminSet: Boolean(env.SUPABASE_SERVICE_ROLE_KEY),
        resendSet: Boolean(env.RESEND_API_KEY),
        resendFrom: env.RESEND_FROM || DEFAULT_FROM,
        broadcastSet: Boolean(env.BROADCAST_SECRET),
        stripeEnvDiag,
        ...(db ? { db } : {}),
        ...(stripeDiag ? { stripeDiag } : {}),
        ...(connectDiag ? { connect: connectDiag } : {}),
        version: "r64",
      });
    }

    if (url.pathname === "/admin/diagnostics" && request.method === "GET") {
      return handleAdminDiagnostics(request, env);
    }

    if (url.pathname === "/bots/run" && request.method === "POST") {
      return handleBotsRun(request, env);
    }

    if (url.pathname === "/bots/status" && request.method === "GET") {
      return handleBotsStatus(request, env);
    }

    if (url.pathname === "/bots/config" && request.method === "POST") {
      return handleBotsConfig(request, env);
    }

    if (url.pathname === "/stripe/checkout" && request.method === "POST") {
      return handleCheckout(request, env);
    }

    if (url.pathname === "/stripe/session" && request.method === "GET") {
      return handleSessionLookup(request, env);
    }

    if (url.pathname === "/refunds/request" && request.method === "POST") {
      return handleRefundRequest(request, env);
    }

    if (url.pathname === "/refunds/mine" && request.method === "GET") {
      return handleMyRefunds(request, env);
    }

    if (url.pathname === "/admin/refunds" && request.method === "GET") {
      return handleAdminRefundsList(request, env);
    }

    if (url.pathname === "/admin/refunds/decide" && request.method === "POST") {
      return handleAdminRefundDecide(request, env);
    }

    if (url.pathname === "/billing/receipts" && request.method === "GET") {
      return handleMyReceipts(request, env);
    }

    if (url.pathname === "/admin/receipts" && request.method === "GET") {
      return handleAdminReceipts(request, env);
    }

    if (url.pathname === "/admin/refunds/direct" && request.method === "POST") {
      return handleAdminDirectRefund(request, env);
    }

    if (url.pathname === "/webhooks/stripe" && request.method === "POST") {
      return handleWebhook(request, env);
    }

    if (url.pathname === "/admin/broadcast" && request.method === "POST") {
      return handleBroadcast(request, env);
    }

    if (url.pathname === "/badges/approved-hook" && request.method === "POST") {
      return handleBadgeApprovedHook(request, env);
    }

    if (url.pathname === "/admin/applications" && request.method === "GET") {
      return handleAdminApplicationsList(request, env);
    }

    if (
      url.pathname === "/admin/applications/decide" &&
      request.method === "POST"
    ) {
      return handleAdminApplicationDecide(request, env);
    }

    if (url.pathname === "/admin/badges/grant" && request.method === "POST") {
      return handleAdminBadgeGrant(request, env);
    }

    if (url.pathname === "/coach-access/grant" && request.method === "POST") {
      return handleCoachAccessGrant(request, env);
    }

    if (
      url.pathname === "/jasper/hook/descriptor" &&
      request.method === "POST"
    ) {
      return retiredJasperHook();
    }

    if (url.pathname.startsWith("/jasper/hook/") && request.method === "POST") {
      const parts = url.pathname.split("/").filter(Boolean);
      if (parts.length === 4) {
        return retiredJasperHook();
      }
      return json({ error: "not_found" }, 404);
    }

    if (url.pathname === "/coach/connect/onboard" && request.method === "POST") {
      return handleConnectOnboard(request, env);
    }

    if (url.pathname === "/coach/connect/session" && request.method === "POST") {
      return handleConnectSession(request, env);
    }

    if (url.pathname === "/coach/connect/status" && request.method === "GET") {
      return handleConnectStatus(request, env);
    }

    if (
      url.pathname === "/coach/connect/dashboard" &&
      request.method === "POST"
    ) {
      return handleConnectDashboard(request, env);
    }

    if (url.pathname === "/coach/pricing" && request.method === "POST") {
      return handleCoachPricingSet(request, env);
    }

    if (url.pathname === "/coach/pricing" && request.method === "GET") {
      return handleCoachPricingGet(request, env);
    }

    if (url.pathname === "/coach/tiers" && request.method === "POST") {
      return handleCoachTiersSet(request, env);
    }

    if (url.pathname === "/coach/tiers" && request.method === "GET") {
      return handleCoachTiersGet(request, env);
    }

    if (url.pathname === "/coach/earnings" && request.method === "GET") {
      return handleCoachEarnings(request, env);
    }

    if (url.pathname === "/coach/payout" && request.method === "POST") {
      return handleCoachPayout(request, env);
    }

    if (url.pathname === "/wpp/summary" && request.method === "GET") {
      return handleWppSummary(request, env);
    }

    if (url.pathname === "/wpp/cashout" && request.method === "POST") {
      return handleWppCashout(request, env);
    }

    if (url.pathname === "/gifts/wallet" && request.method === "GET") {
      return handleGiftWallet(request, env);
    }

    if (url.pathname === "/gifts/topup" && request.method === "POST") {
      return handleGiftTopup(request, env);
    }

    if (url.pathname === "/gifts/send" && request.method === "POST") {
      return handleGiftSend(request, env);
    }

    if (url.pathname === "/gifts/earnings" && request.method === "GET") {
      return handleGiftEarnings(request, env);
    }

    if (url.pathname === "/gifts/cashout" && request.method === "POST") {
      return handleGiftCashout(request, env);
    }

    if (
      url.pathname === "/coach/stripe/overview" &&
      request.method === "GET"
    ) {
      return handleStripeOverview(request, env);
    }

    if (url.pathname === "/business/ads/topup" && request.method === "POST") {
      return handleAdsTopup(request, env);
    }

    if (
      url.pathname === "/business/wallet/autorecharge" &&
      request.method === "GET"
    ) {
      return handleAutoRechargeGet(request, env);
    }
    if (
      url.pathname === "/business/wallet/autorecharge/start" &&
      request.method === "POST"
    ) {
      return handleAutoRechargeStart(request, env);
    }
    if (
      url.pathname === "/business/wallet/autorecharge/enable" &&
      request.method === "POST"
    ) {
      return handleAutoRechargeEnable(request, env);
    }
    if (
      url.pathname === "/business/wallet/autorecharge/disable" &&
      request.method === "POST"
    ) {
      return handleAutoRechargeDisable(request, env);
    }
    if (
      url.pathname === "/business/wallet/autorecharge/check" &&
      request.method === "POST"
    ) {
      return handleAutoRechargeCheck(request, env);
    }

    if (url.pathname === "/coach/hire-checkout" && request.method === "POST") {
      return handleCoachHireCheckout(request, env);
    }

    if (url.pathname === "/admin/team" && request.method === "GET") {
      return handleAdminTeamList(request, env);
    }

    if (url.pathname === "/admin/team/upsert" && request.method === "POST") {
      return handleAdminTeamUpsert(request, env);
    }

    if (url.pathname === "/admin/team/remove" && request.method === "POST") {
      return handleAdminTeamRemove(request, env);
    }

    if (url.pathname === "/admin/featured" && request.method === "GET") {
      return handleAdminFeaturedList(request, env);
    }

    if (url.pathname === "/admin/featured/upsert" && request.method === "POST") {
      return handleAdminFeaturedUpsert(request, env);
    }

    if (url.pathname === "/admin/featured/delete" && request.method === "POST") {
      return handleAdminFeaturedDelete(request, env);
    }

    if (url.pathname === "/admin/articles" && request.method === "GET") {
      return handleAdminArticlesList(request, env);
    }

    if (url.pathname === "/admin/articles/upsert" && request.method === "POST") {
      return handleAdminArticleUpsert(request, env);
    }

    if (url.pathname === "/admin/articles/delete" && request.method === "POST") {
      return handleAdminArticleDelete(request, env);
    }

    if (url.pathname === "/admin/articles/seed" && request.method === "POST") {
      return handleAdminArticlesSeed(request, env);
    }

    if (url.pathname === "/coach/hire-status" && request.method === "GET") {
      return handleCoachHireStatus(request, env);
    }

    if (url.pathname === "/coach/my-hires" && request.method === "GET") {
      return handleMyCoachSubscriptions(request, env);
    }

    if (url.pathname === "/coach/hire-cancel" && request.method === "POST") {
      return handleCoachHireCancel(request, env);
    }

    if (url.pathname === "/coach/program-checkout" && request.method === "POST") {
      return handleProgramCheckout(request, env);
    }

    if (url.pathname === "/coach/program-access" && request.method === "GET") {
      return handleProgramAccess(request, env);
    }

    if (url.pathname === "/author/articles" && request.method === "GET") {
      return handleAuthorArticlesList(request, env);
    }

    if (url.pathname === "/author/articles/upsert" && request.method === "POST") {
      return handleAuthorArticleUpsert(request, env);
    }

    if (url.pathname === "/author/articles/delete" && request.method === "POST") {
      return handleAuthorArticleDelete(request, env);
    }

    if (url.pathname === "/collabs" && request.method === "GET") {
      return handleCollabList(request, env);
    }
    if (url.pathname === "/collabs/detail" && request.method === "GET") {
      return handleCollabDetail(request, env);
    }
    if (url.pathname === "/collabs/create" && request.method === "POST") {
      return handleCollabCreate(request, env);
    }
    if (url.pathname === "/collabs/invite" && request.method === "POST") {
      return handleCollabInvite(request, env);
    }
    if (url.pathname === "/collabs/activity" && request.method === "POST") {
      return handleCollabActivityCreate(request, env);
    }
    if (url.pathname === "/collabs/activity/status" && request.method === "POST") {
      return handleCollabActivityStatus(request, env);
    }

    if (url.pathname === "/films" && request.method === "GET") {
      return handleFilmsList(request, env);
    }
    if (url.pathname === "/films/get" && request.method === "GET") {
      return handleFilmGet(request, env);
    }
    if (url.pathname === "/films/create" && request.method === "POST") {
      return handleFilmCreate(request, env);
    }
    if (url.pathname === "/films/timestamps" && request.method === "POST") {
      return handleFilmTimestampCreate(request, env);
    }
    if (url.pathname === "/films/timestamps" && request.method === "DELETE") {
      return handleFilmTimestampDelete(request, env);
    }

    if (url.pathname === "/public/profile" && request.method === "GET") {
      return handlePublicProfile(request, env);
    }

    if (url.pathname === "/brands" && request.method === "GET") {
      return handleBrandsList(request, env);
    }

    if (url.pathname === "/brand/profile" && request.method === "POST") {
      return handleBrandUpsert(request, env);
    }

    if (url.pathname === "/brand/profile" && request.method === "GET") {
      return handleBrandGet(request, env);
    }

    if (url.pathname === "/brand/verify" && request.method === "POST") {
      return handleBrandVerifySave(request, env);
    }

    if (url.pathname === "/brand/eligibility" && request.method === "GET") {
      return handleBrandEligibility(request, env);
    }

    if (url.pathname === "/brand/apply" && request.method === "POST") {
      return handleBrandApply(request, env);
    }

    if (
      url.pathname === "/sponsorship/applications" &&
      request.method === "GET"
    ) {
      return handleSponsorshipApplications(request, env);
    }

    if (url.pathname === "/sponsorship/respond" && request.method === "POST") {
      return handleSponsorshipRespond(request, env);
    }

    if (
      url.pathname === "/sponsorship/creator-respond" &&
      request.method === "POST"
    ) {
      return handleSponsorshipCreatorRespond(request, env);
    }

    if (url.pathname === "/sponsorship/deals" && request.method === "GET") {
      return handleSponsorshipDeals(request, env);
    }

    if (url.pathname === "/sponsorship/fund" && request.method === "POST") {
      return handleSponsorshipFund(request, env);
    }

    if (url.pathname === "/sponsorship/dispute" && request.method === "POST") {
      return handleSponsorshipDispute(request, env);
    }

    if (url.pathname === "/creator/earnings" && request.method === "GET") {
      return handleCreatorEarnings(request, env);
    }

    if (
      url.pathname === "/sponsorship/track-post" &&
      request.method === "POST"
    ) {
      return handleSponsorshipTrackPost(request, env);
    }

    if (url.pathname === "/support/contact" && request.method === "POST") {
      return handleSupportContact(request, env);
    }

    if (url.pathname === "/auth/password-login") {
      return passwordLogin(request, env);
    }

    if (
      url.pathname === "/auth/password-reset" &&
      request.method === "POST"
    ) {
      return handleAuthPasswordReset(request, env);
    }

    if (url.pathname === "/referrals/redeem" && request.method === "POST") {
      return handleReferralRedeem(request, env);
    }

    if (url.pathname === "/referrals/stats" && request.method === "GET") {
      return handleReferralStats(request, env);
    }

    // Recruiter reviews — a user who signed up via a recruiter's code can rate
    // the recruiter 1–5 stars + leave a review. Admins/owner see all reviews.
    if (url.pathname === "/recruiter/reviews" && request.method === "POST") {
      return handleRecruiterReviewSubmit(request, env);
    }
    if (url.pathname === "/recruiter/reviews" && request.method === "GET") {
      return handleRecruiterReviewsList(request, env);
    }
    // Admin: list all recruiters with their aggregate ratings so the founder
    // can see which recruiters are performing well and which aren't.
    if (url.pathname === "/admin/recruiters" && request.method === "GET") {
      return handleAdminRecruitersList(request, env);
    }

    // Meeting requests — a visitor/member asks a recruiter for a call; the
    // recruiter approves/denies; approval emails the Google Meet link.
    if (url.pathname === "/meetings/request" && request.method === "POST") {
      return handleMeetingRequest(request, env);
    }
    if (url.pathname === "/meetings/mine" && request.method === "GET") {
      return handleMeetingListMine(request, env);
    }
    if (url.pathname === "/meetings/recruiter" && request.method === "GET") {
      return handleMeetingListRecruiter(request, env);
    }
    if (url.pathname === "/livekit/token" && request.method === "POST") {
      return handleLiveKitToken(request, env);
    }

    if (url.pathname === "/notebook/transcribe" && request.method === "POST") {
      const caller = await requireUser(request, env);
      if (caller instanceof Response) return caller;
      return notebookTranscription(request, env);
    }

    if (url.pathname.startsWith('/knot/browser/')) {
      try {
        const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
        if (identity instanceof Response) return identity;
        return await knotBrowserRoute(request, env, identity.userId);
      } catch { return json({ error: 'browser_unavailable' }, 503); }
    }

    if (url.pathname.startsWith('/knot/artifacts/')) {
      try {
        const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
        if (identity instanceof Response) return identity;
        return await knotArtifactSharingRoute(request, env, identity.userId.toLowerCase());
      } catch { return json({ error: 'sharing_unavailable' }, 503); }
    }

    if (url.pathname === '/knot/documents' && request.method === 'DELETE') {
      try {
        const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
        if (identity instanceof Response) return identity;
        return await dispatchKnotActor(env, identity.userId, 'documents/erase-all', {});
      } catch { return json({ error: 'document_deletion_unavailable' }, 503); }
    }

    if (url.pathname.startsWith('/knot/persona/')) {
      if (request.method !== 'POST') return json({ error: 'method_not_allowed' }, 405);
      if (!/^\/knot\/persona\/(read|name|vibe|consent|models|candidates|pick|revert|approve|generate|media)$/.test(url.pathname)) return json({ error: 'not_found' }, 404);
      try {
        const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
        if (identity instanceof Response) return identity;
        // Stream the bounded JSON through to the account actor; never trust owner IDs.
        const reader = request.body?.getReader(); let size = 0, text = ''; const decoder = new TextDecoder();
        if (reader) { try { for (;;) { const next = await reader.read(); if (next.done) break; size += next.value.byteLength; if (size > 16000) return json({ error: 'request_too_large' }, 413); text += decoder.decode(next.value, { stream: true }); } } finally { await reader.cancel().catch(() => {}); reader.releaseLock(); } }
        const body: unknown = JSON.parse(text + decoder.decode());
        if (!body || typeof body !== 'object' || Array.isArray(body)) return json({ error: 'invalid_request' }, 400);
        return await dispatchKnotActor(env, identity.userId.toLowerCase(), url.pathname.slice('/knot/'.length), body, request.signal);
      } catch { return json({ error: 'persona_unavailable' }, 503); }
    }

    if (url.pathname.startsWith('/knot/shell/')) {
      try {
        const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
        if (identity instanceof Response) {
          console.warn('knot_shell_boundary', JSON.stringify({ stage: 'authentication', status: identity.status, dispatchAccepted: false }));
          return identity;
        }
        console.info('knot_shell_boundary', JSON.stringify({ stage: 'authenticated' }));
        return await knotShellRoute(request, env, identity.userId);
      } catch {
        console.warn('knot_shell_boundary', JSON.stringify({ stage: 'authentication_or_route', outcome: 'unavailable' }));
        return json({ error: 'shell_unavailable' }, 503);
      }
    }

    if (url.pathname === '/knot/conversations' || url.pathname.startsWith('/knot/conversations/')) {
      try {
        const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
        if (identity instanceof Response) return identity;
        return await knotConversationsRoute(request, env, identity.userId);
      } catch { return json({ error: 'history_unavailable' }, 503); }
    }

    if (url.pathname === '/internal/knot/contact-claim' && request.method === 'POST') return knotContactClaimRoute(request, env);

    if (url.pathname === '/knot/turns' || url.pathname.startsWith('/knot/turns/')) {
      try {
        const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
        if (identity instanceof Response) return identity;
        return await knotOwnedTurnsRoute(request, env, identity.userId);
      } catch { return json({ error: 'task_unavailable' }, 503); }
    }

    if (url.pathname === '/knot/background' || url.pathname.startsWith('/knot/background/')) {
      try {
        const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
        if (identity instanceof Response) return identity;
        return await knotBackgroundRoute(request, env, identity.userId);
      } catch { return json({ error: 'background_unavailable' }, 503); }
    }

    if (url.pathname === '/admin/knot-text-transport' && request.method === 'POST') {
      if (!env.BROADCAST_SECRET || request.headers.get('X-Whisper-Operator') !== env.BROADCAST_SECRET) return json({ error: 'forbidden' }, 403);
      const check = url.searchParams.get('check');
      const result = await (check === 'authoring-chat' || check === 'authoring-messages' || check === 'authoring-bound' || check === 'authoring-beta' || check === 'authoring-beta-bound' ? inspectKnotDocumentTransport(env, check) : check === 'browser-tools' || check === 'forced-shell' ? inspectKnotToolSelection(env, check === 'forced-shell') : inspectKnotTextTransport(env));
      return json({ ...result, provider: knotAITransport(env)?.provider ?? 'unavailable', observedAt: new Date().toISOString() });
    }

    if (url.pathname === '/admin/knot-key-binding' && request.method === 'GET') {
      if (!env.BROADCAST_SECRET || request.headers.get('X-Whisper-Operator') !== env.BROADCAST_SECRET) return json({ error: 'forbidden' }, 403);
      return inspectKnotKeyBinding(request, env);
    }

    if (url.pathname === '/admin/knot-text-policy' && request.method === 'GET') {
      if (!env.BROADCAST_SECRET || request.headers.get('X-Whisper-Operator') !== env.BROADCAST_SECRET) return json({ error: 'forbidden' }, 403);
      // Presence/routing only; never credentials or member state.
      const transport = knotAITransport(env);
      return json({ tokenPresent: !!transport, gatewayValid: !!transport, provider: transport?.provider ?? 'unavailable', routingPolicy: 'rork_cloud_only_v1', credentialSource: env.EXPO_PUBLIC_RORK_TOOLKIT_SECRET_KEY ? 'managed' : 'missing', addressOverridePresent: !!env.EXPO_PUBLIC_TOOLKIT_URL?.trim(), signingKeyPresent: !!env.SUPABASE_SERVICE_ROLE_KEY, admissionPresent: !!env.DO });
    }

    if (url.pathname === '/admin/knot-voice-policy' && request.method === 'GET') {
      if (!env.BROADCAST_SECRET || request.headers.get('X-Whisper-Operator') !== env.BROADCAST_SECRET) return json({ error: 'forbidden' }, 403);
      return inspectKnotVoicePolicy(env);
    }

    if (url.pathname === '/knot/voice/completions' && request.method === 'POST') {
      return knotVoiceCompletions(request, env);
    }
    if (url.pathname === '/knot/voice/end' && request.method === 'POST') {
      const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
      if (identity instanceof Response) return identity;
      return knotVoiceEnd(request, env, identity.userId);
    }
    if (url.pathname === "/knot/voice/token" && request.method === "POST") {
      const signal = AbortSignal.any([request.signal, AbortSignal.timeout(26000)]);
      let stage = 'voice_auth_unavailable';
      try {
        // Retry only the idempotent identity GET, never admission, provider token
        // issuance, invitation claims or call creation. Invalid sessions fail closed.
        const identity = await requireKnotVoiceUser(request, env, signal);
        if (identity instanceof Response) return identity;
        stage = 'voice_unavailable';
        return await knotVoiceToken(new Request(request, { signal }), env, identity.userId);
      } catch {
        const error = signal.aborted ? 'voice_connection_timeout' : stage;
        console.warn('knot_voice_failure', JSON.stringify({ stage: error, status: 503 }));
        return json({ error }, 503);
      }
    }

    // Additive Knot transport. Identity is always verified against the existing Supabase account.
    if (url.pathname === "/knot/chat/stream" && request.method === "POST") {
      let stage = 'authentication';
      try {
        const identity = await requireUser(request, env, AbortSignal.any([request.signal, AbortSignal.timeout(5000)]));
        if (identity instanceof Response) {
          console.warn('knot_live_failure', JSON.stringify({ stage, status: identity.status }));
          return identity;
        }
        stage = 'live_request';
        return await knotLive(request, env, identity.userId, execution);
      } catch {
        console.warn('knot_live_failure', JSON.stringify({ stage, outcome: 'unavailable' }));
        return json({ error: "live_unavailable" }, 503);
      }
    }

    // Ember AI proxy — signed-in users only; used by web builds that ship
    // no client-side AI credentials (the production custom domain).
    if (url.pathname === "/ai/chat" && request.method === "POST") {
      return handleAiChat(request, env);
    }
    // Ember live voice — ephemeral OpenAI Realtime credentials (echo voice).
    if (url.pathname === "/ai/realtime-token" && request.method === "POST") {
      return handleAiRealtimeToken(request, env);
    }
    // Meeting captions fallback — server-side speech-to-text for browsers
    // without Web Speech (keeps host transcription + AI notes working).
    if (url.pathname === "/ai/transcribe" && request.method === "POST") {
      return handleAiTranscribe(request, env);
    }
    // Jasper voice — server-side TTS (no client ever ships the OpenAI key).
    if (url.pathname === "/ai/speech" && request.method === "POST") {
      return handleAiSpeech(request, env);
    }
    // Jasper Imagine — server-side image generation.
    if (url.pathname === "/ai/image" && request.method === "POST") {
      return handleAiImage(request, env);
    }
    // Jasper web search — REAL search + crawl with cited sources (chat + meetings).
    if (url.pathname === "/ai/websearch" && request.method === "POST") {
      return handleAiWebSearch(request, env);
    }
    // Prospect Instagram gallery — photos for recruiter presenting cards.
    if (url.pathname === "/ig/photos" && request.method === "GET") {
      return handleIgPhotos(request, env);
    }

    if (url.pathname === "/meetings/decide" && request.method === "POST") {
      return handleMeetingDecide(request, env);
    }

    if (url.pathname === "/meetings/invite" && request.method === "POST") {
      return handleMeetingInvite(request, env);
    }

    if (url.pathname === "/meetings/notes-email" && request.method === "POST") {
      return handleMeetingNotesEmail(request, env);
    }

    if (url.pathname === "/meetings/invite-email" && request.method === "POST") {
      return handleMeetingInviteEmail(request, env);
    }

    // Ember deck-walkthrough narration line (device-voiced tours from iOS).
    if (url.pathname === "/meetings/tour-audio" && request.method === "GET") {
      return handleMeetingTourAudio(request, env);
    }

    return json({ error: "not_found" }, 404);
}

