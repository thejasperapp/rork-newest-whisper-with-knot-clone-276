/**
 * LiveKit token minting endpoint for Whisper Live audio rooms.
 *
 * POST /livekit/token
 * Body: { room: string, identity: string, name?: string }
 * Returns: { token: string, url: string }
 *
 * The token is a LiveKit-compatible JWT signed with HS256 using the
 * LIVEKIT_API_KEY and LIVEKIT_API_SECRET env vars. Works in Cloudflare
 * Workers via the WebCrypto API.
 */

const enc = new TextEncoder();

function base64UrlEncode(data: ArrayBuffer | Uint8Array): string {
  const bytes = data instanceof Uint8Array ? data : new Uint8Array(data);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function base64UrlEncodeString(str: string): string {
  return base64UrlEncode(enc.encode(str));
}

async function hmacSha256(key: string, message: string): Promise<ArrayBuffer> {
  const cryptoKey = await crypto.subtle.importKey(
    "raw",
    enc.encode(key),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  return crypto.subtle.sign("HMAC", cryptoKey, enc.encode(message));
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

  const headerB64 = base64UrlEncodeString(JSON.stringify(header));
  const payloadB64 = base64UrlEncodeString(JSON.stringify(payload));
  const signingInput = `${headerB64}.${payloadB64}`;
  const sig = await hmacSha256(apiSecret, signingInput);
  const sigB64 = base64UrlEncode(sig);

  return `${headerB64}.${payloadB64}.${sigB64}`;
}

export async function handleLiveKitToken(
  request: Request,
  env: { LIVEKIT_API_KEY?: string; LIVEKIT_API_SECRET?: string; LIVEKIT_URL?: string }
): Promise<Response> {
  if (request.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  const apiKey = env.LIVEKIT_API_KEY;
  const apiSecret = env.LIVEKIT_API_SECRET;
  const livekitUrl = env.LIVEKIT_URL ?? "";

  if (!apiKey || !apiSecret) {
    return new Response(
      JSON.stringify({ error: "LiveKit credentials not configured" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }

  let body: { room?: string; identity?: string; name?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: "Invalid JSON" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const room = body.room?.trim();
  const identity = body.identity?.trim();
  if (!room || !identity) {
    return new Response(
      JSON.stringify({ error: "room and identity are required" }),
      { status: 400, headers: { "Content-Type": "application/json" } }
    );
  }

  try {
    const token = await mintLiveKitToken(apiKey, apiSecret, room, identity, body.name);
    return new Response(
      JSON.stringify({ token, url: livekitUrl }),
      { status: 200, headers: { "Content-Type": "application/json" } }
    );
  } catch (err) {
    return new Response(
      JSON.stringify({ error: "Failed to mint token" }),
      { status: 500, headers: { "Content-Type": "application/json" } }
    );
  }
}
