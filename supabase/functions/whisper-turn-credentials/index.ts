// Whisper TURN credentials Edge Function
//
// Mints short-lived TURN credentials from Twilio's Network Traversal Service
// and returns them as a list of ICE servers the iOS WebRTC client can use
// directly. Twilio NTS tokens expire every 24h, so the client calls this
// endpoint right before every call to get a fresh set.
//
// Environment variables (set with `supabase secrets set ...`):
//   TWILIO_ACCOUNT_SID    starts with AC...
//   TWILIO_AUTH_TOKEN     the Twilio auth token (rotate if leaked)
//
// Response shape:
//   {
//     "iceServers": [
//       { "urls": ["stun:..."] },
//       { "urls": ["turn:..."], "username": "...", "credential": "..." }
//     ],
//     "ttl": 86400
//   }

const TWILIO_ACCOUNT_SID = Deno.env.get("TWILIO_ACCOUNT_SID") ?? "";
const TWILIO_AUTH_TOKEN = Deno.env.get("TWILIO_AUTH_TOKEN") ?? "";

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

interface TwilioIceServer {
  url?: string;
  urls?: string;
  username?: string;
  credential?: string;
}

interface TwilioTokenResponse {
  username: string;
  password: string;
  ttl: string;
  ice_servers: TwilioIceServer[];
}

/** Always-available STUN fallback so the client can still try to connect
 * even if Twilio is unreachable or unconfigured. */
const STUN_FALLBACK = {
  iceServers: [
    {
      urls: [
        "stun:stun.l.google.com:19302",
        "stun:stun1.l.google.com:19302",
        "stun:stun2.l.google.com:19302",
      ],
    },
  ],
  ttl: 0,
  source: "stun-fallback" as const,
};

async function mintTwilioToken(): Promise<Response> {
  if (!TWILIO_ACCOUNT_SID || !TWILIO_AUTH_TOKEN) {
    return new Response(
      JSON.stringify({
        ...STUN_FALLBACK,
        warning:
          "TWILIO_ACCOUNT_SID / TWILIO_AUTH_TOKEN not set on this function. " +
          "Falling back to STUN-only; cellular & strict-NAT calls will fail.",
      }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  const url = `https://api.twilio.com/2010-04-01/Accounts/${TWILIO_ACCOUNT_SID}/Tokens.json`;
  const basic = btoa(`${TWILIO_ACCOUNT_SID}:${TWILIO_AUTH_TOKEN}`);

  let resp: Response;
  try {
    resp = await fetch(url, {
      method: "POST",
      headers: {
        Authorization: `Basic ${basic}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      // Twilio Ttl param max is 86400 (24h). Omit to use Twilio default.
      body: "Ttl=3600",
    });
  } catch (err) {
    return new Response(
      JSON.stringify({
        ...STUN_FALLBACK,
        warning: `Twilio request failed: ${(err as Error).message}`,
      }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  if (!resp.ok) {
    const text = await resp.text().catch(() => "");
    return new Response(
      JSON.stringify({
        ...STUN_FALLBACK,
        warning: `Twilio returned ${resp.status}: ${text.slice(0, 200)}`,
      }),
      { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
    );
  }

  const json = (await resp.json()) as TwilioTokenResponse;

  // Normalize: Twilio returns ice_servers with either `url` (deprecated) or `urls`.
  // Group URLs by username/credential so we return a clean array.
  const stunUrls: string[] = [
    "stun:stun.l.google.com:19302",
    "stun:stun1.l.google.com:19302",
  ];
  const turnUrls: string[] = [];

  for (const s of json.ice_servers ?? []) {
    const u = s.urls ?? s.url ?? "";
    if (!u) continue;
    if (u.startsWith("stun:")) {
      if (!stunUrls.includes(u)) stunUrls.push(u);
    } else if (u.startsWith("turn:") || u.startsWith("turns:")) {
      turnUrls.push(u);
    }
  }

  const iceServers: Array<{ urls: string[]; username?: string; credential?: string }> = [
    { urls: stunUrls },
  ];
  if (turnUrls.length > 0) {
    iceServers.push({
      urls: turnUrls,
      username: json.username,
      credential: json.password,
    });
  }

  const ttl = Number.parseInt(json.ttl, 10) || 3600;

  return new Response(
    JSON.stringify({
      iceServers,
      ttl,
      source: "twilio",
    }),
    { status: 200, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } },
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "GET" && req.method !== "POST") {
    return new Response("Method Not Allowed", {
      status: 405,
      headers: CORS_HEADERS,
    });
  }
  return await mintTwilioToken();
});
