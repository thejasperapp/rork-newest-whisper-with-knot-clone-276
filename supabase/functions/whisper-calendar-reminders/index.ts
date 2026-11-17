// Whisper calendar reminders Edge Function
//
// Invoked on a schedule (every minute via pg_cron + pg_net, or the Supabase
// dashboard scheduler). Finds calendar events starting within the next
// 10–20 minutes that haven't been reminded yet, and sends a push
// notification to the organizer and every tagged user.
//
// Environment variables (same as whisper-push-fanout):
//   APNS_TEAM_ID, APNS_KEY_ID, APNS_BUNDLE_ID, APNS_PRIVATE_KEY,
//   APNS_USE_SANDBOX, SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY

import { createClient } from "https://esm.sh/@supabase/supabase-js@2.45.4";
import { create, getNumericDate } from "https://deno.land/x/djwt@v3.0.2/mod.ts";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const APNS_TEAM_ID = Deno.env.get("APNS_TEAM_ID") ?? "";
const APNS_KEY_ID = Deno.env.get("APNS_KEY_ID") ?? "";
const APNS_BUNDLE_ID = Deno.env.get("APNS_BUNDLE_ID") ?? "";
const APNS_PRIVATE_KEY =
  Deno.env.get("APNS_PRIVATE_KEY") ?? Deno.env.get("APNS_KEY_P8") ?? "";
const APNS_USE_SANDBOX = (Deno.env.get("APNS_USE_SANDBOX") ?? "true") === "true";

const PROD_HOST = "https://api.push.apple.com";
const SANDBOX_HOST = "https://api.sandbox.push.apple.com";

const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY, {
  auth: { persistSession: false, autoRefreshToken: false },
});

let cachedJWT: { token: string; issuedAt: number } | null = null;

async function importP8(pem: string): Promise<CryptoKey> {
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
  const now = Math.floor(Date.now() / 1000);
  if (cachedJWT && now - cachedJWT.issuedAt < 50 * 60) return cachedJWT.token;
  const key = await importP8(APNS_PRIVATE_KEY);
  const token = await create(
    { alg: "ES256", kid: APNS_KEY_ID, typ: "JWT" },
    { iss: APNS_TEAM_ID, iat: getNumericDate(0) },
    key
  );
  cachedJWT = { token, issuedAt: now };
  return token;
}

interface DeviceTokenRow {
  token: string;
  sandbox: boolean | null;
  bundle_id: string | null;
}

async function sendToUser(userID: string, title: string, body: string, eventID: string) {
  const { data: tokens } = await supabase
    .from("whisper_device_tokens")
    .select("token, sandbox, bundle_id")
    .eq("user_id", userID)
    .eq("active", true);
  if (!tokens || tokens.length === 0) return;
  const jwt = await apnsJWT();
  await Promise.all(
    (tokens as DeviceTokenRow[]).map(async (row) => {
      const host =
        row.sandbox === false
          ? PROD_HOST
          : row.sandbox === true
            ? SANDBOX_HOST
            : APNS_USE_SANDBOX
              ? SANDBOX_HOST
              : PROD_HOST;
      const payload = {
        aps: {
          alert: { title, body },
          sound: "default",
          "thread-id": "calendar-reminder",
          category: "calendar_reminder",
          "mutable-content": 1,
        },
        data: { kind: "calendar_reminder", event_id: eventID },
      };
      try {
        const res = await fetch(`${host}/3/device/${row.token}`, {
          method: "POST",
          headers: {
            authorization: `bearer ${jwt}`,
            "apns-topic": row.bundle_id ?? APNS_BUNDLE_ID,
            "apns-push-type": "alert",
            "apns-priority": "10",
            "apns-collapse-id": `cal-reminder-${eventID}`.slice(0, 64),
            "content-type": "application/json",
          },
          body: JSON.stringify(payload),
        });
        if (res.status === 410 || res.status === 400) {
          await supabase
            .from("whisper_device_tokens")
            .update({ active: false })
            .eq("token", row.token);
        }
      } catch (e) {
        console.error("apns deliver error", e);
      }
    })
  );
}

interface EventRow {
  id: string;
  created_by: string;
  title: string;
  start_time: string;
  location: string | null;
  meeting_link: string | null;
  tagged_user_ids: string[] | null;
}

function formatTime(iso: string): string {
  const d = new Date(iso);
  return d.toLocaleTimeString("en-US", {
    hour: "numeric",
    minute: "2-digit",
    timeZone: "America/New_York",
  });
}

Deno.serve(async (_req) => {
  const now = Date.now();
  const windowStart = new Date(now + 10 * 60 * 1000).toISOString();
  const windowEnd = new Date(now + 20 * 60 * 1000).toISOString();

  const { data: events, error } = await supabase
    .from("whisper_calendar_events")
    .select("id, created_by, title, start_time, location, meeting_link, tagged_user_ids")
    .gte("start_time", windowStart)
    .lt("start_time", windowEnd);

  if (error) {
    console.error("event query error", error);
    return new Response(JSON.stringify({ error: error.message }), { status: 500 });
  }
  if (!events || events.length === 0) {
    return new Response(JSON.stringify({ reminded: 0 }), { status: 200 });
  }

  // Filter out events already reminded
  const ids = (events as EventRow[]).map((e) => e.id);
  const { data: sent } = await supabase
    .from("whisper_calendar_reminders_sent")
    .select("event_id")
    .in("event_id", ids);
  const sentIDs = new Set((sent ?? []).map((r) => r.event_id as string));

  let reminded = 0;
  for (const event of events as EventRow[]) {
    if (sentIDs.has(event.id)) continue;

    // Claim the reminder first so concurrent invocations can't double-send.
    const { error: claimError } = await supabase
      .from("whisper_calendar_reminders_sent")
      .insert({ event_id: event.id });
    if (claimError) continue; // another invocation claimed it

    const recipients = new Set<string>([event.created_by]);
    for (const uid of event.tagged_user_ids ?? []) recipients.add(uid);

    const timeLabel = formatTime(event.start_time);
    const extra = event.meeting_link
      ? " · Online meeting"
      : event.location
        ? ` · ${event.location}`
        : "";
    const body = `Starts at ${timeLabel}${extra}`;

    await Promise.all(
      Array.from(recipients).map((uid) =>
        sendToUser(uid, `⏰ ${event.title} — in 15 minutes`, body, event.id)
      )
    );
    reminded++;
  }

  return new Response(JSON.stringify({ reminded }), { status: 200 });
});
