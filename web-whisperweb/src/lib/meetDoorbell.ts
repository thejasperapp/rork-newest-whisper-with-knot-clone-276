import { supabase } from "@/lib/supabase";

/**
 * Meet-style knocking ("Ask to join") for Whisper Meet.
 *
 * The knocker is NOT a participant yet — no media, no peer connections, no
 * presence. It subscribes to the room's signaling topic in "lobby mode" and
 * broadcasts an app-event the in-room clients already route through their
 * `onAppEvent` handler. Hosts answer on the same wire.
 *
 * Wire (shared with iOS — identical names + payloads):
 *   meeting-knock        {knockId, name, userId|null, avatarUrl|null, isGuest, at}
 *   meeting-knock-ack    {knockId, byName}          host reached — "asking to join…"
 *   meeting-admit        {knockId, byName}          let in → the knocker joins
 *   meeting-deny         {knockId, byName}          refused → "You can't join this call"
 *   meeting-knock-cancel {knockId}                  knocker left the door
 */

export interface MeetDoorbellHandlers {
  onAck?: (byName: string) => void;
  onAdmit?: (byName: string) => void;
  onDeny?: (byName: string) => void;
}

export interface MeetDoorbellIdentity {
  knockId: string;
  name: string;
  userId: string | null;
  avatarUrl: string | null;
  isGuest: boolean;
}

export interface MeetDoorbell {
  /** Broadcast (or re-broadcast) the knock. Safe to call repeatedly. */
  knock: () => Promise<void>;
  /** Tell the room the knocker gave up so the host's prompt disappears. */
  cancel: () => Promise<void>;
  /** Tear the lobby channel down (always before the real join). */
  close: () => Promise<void>;
}

interface LobbySignal {
  type?: string;
  from?: string;
  event?: string;
  data?: { knockId?: string; byName?: string } | null;
}

/**
 * Open the doorbell for a room. Resolves once the lobby channel is
 * subscribed (or rejects when signaling is unreachable).
 *
 * `roomId` is the SAME room id the RTC engine joins (`meeting:<uuid>`).
 */
export async function openMeetDoorbell(
  roomId: string,
  identity: MeetDoorbellIdentity,
  handlers: MeetDoorbellHandlers,
): Promise<MeetDoorbell> {
  const topic = `live-signal:${roomId}`;
  const from = `lobby:${identity.knockId}`;

  const channel = supabase.channel(topic, {
    config: { broadcast: { self: false, ack: true } },
  });

  let closed = false;

  channel.on("broadcast", { event: "signal" }, ({ payload }) => {
    const msg = payload as LobbySignal;
    if (!msg || msg.type !== "app-event") return;
    const data = msg.data ?? null;
    if (!data || data.knockId !== identity.knockId) return;
    const byName = (data.byName ?? "").trim() || "The host";
    switch (msg.event) {
      case "meeting-knock-ack":
        handlers.onAck?.(byName);
        break;
      case "meeting-admit":
        handlers.onAdmit?.(byName);
        break;
      case "meeting-deny":
        handlers.onDeny?.(byName);
        break;
      default:
        break;
    }
  });

  await new Promise<void>((resolve, reject) => {
    let settled = false;
    const finish = (error?: Error): void => {
      if (settled) return;
      settled = true;
      window.clearTimeout(timer);
      if (error) reject(error);
      else resolve();
    };
    const timer = window.setTimeout(
      () => finish(new Error("Couldn't reach the meeting")),
      12_000,
    );
    channel.subscribe((status: string) => {
      if (status === "SUBSCRIBED") finish();
      else if (status === "CHANNEL_ERROR" || status === "TIMED_OUT") {
        finish(new Error("Couldn't reach the meeting signaling service"));
      }
    });
  });

  const send = async (event: string, data: unknown): Promise<void> => {
    if (closed) return;
    try {
      await channel.send({
        type: "broadcast",
        event: "signal",
        payload: { type: "app-event", from, event, data },
      });
    } catch {
      // Best-effort — the knock is re-sent on the caller's cadence.
    }
  };

  return {
    knock: () =>
      send("meeting-knock", {
        knockId: identity.knockId,
        name: identity.name,
        userId: identity.userId,
        avatarUrl: identity.avatarUrl,
        isGuest: identity.isGuest,
        at: Date.now(),
      }),
    cancel: () => send("meeting-knock-cancel", { knockId: identity.knockId }),
    close: async () => {
      if (closed) return;
      closed = true;
      try {
        await supabase.removeChannel(channel);
      } catch {
        /* already gone */
      }
    },
  };
}

/** A stable per-tab knock id (survives a refresh inside the same tab). */
export function meetKnockId(): string {
  try {
    const existing = sessionStorage.getItem("whisper_meet_knock_id");
    if (existing) return existing;
    const fresh = `knock_${Math.random().toString(36).slice(2, 10)}`;
    sessionStorage.setItem("whisper_meet_knock_id", fresh);
    return fresh;
  } catch {
    return `knock_${Math.random().toString(36).slice(2, 10)}`;
  }
}
