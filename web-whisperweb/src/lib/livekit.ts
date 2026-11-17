/**
 * LiveKit client wrapper for Whisper Live audio rooms.
 * Fetches a token from the backend and connects to a LiveKit room.
 */

import { BACKEND_URL } from "@/lib/billing";
import { supabase } from "@/lib/supabase";

const LIVEKIT_URL = import.meta.env.VITE_LIVEKIT_URL || (import.meta as unknown as { env?: { EXPO_PUBLIC_LIVEKIT_URL?: string } }).env?.EXPO_PUBLIC_LIVEKIT_URL || "wss://whisper-xgk6npj8.livekit.cloud";

export { LIVEKIT_URL };

export async function fetchLiveKitToken(
  room: string,
  identity: string,
  name?: string
): Promise<{ token: string; url: string }> {
  // The mint endpoint requires a signed-in Whisper session (security sweep
  // Aug 2026) — attach the Supabase access token so the backend can verify
  // the caller and block identity spoofing.
  const { data } = await supabase.auth.getSession();
  const accessToken = data.session?.access_token;
  const res = await fetch(`${BACKEND_URL}/livekit/token`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    body: JSON.stringify({ room, identity, name }),
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({ error: "Failed to get token" }));
    throw new Error(err.error ?? "Failed to get token");
  }
  return await res.json();
}
