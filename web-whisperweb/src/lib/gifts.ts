import { supabase } from "@/lib/supabase";
import { backendFetch } from "@/lib/billing";

/**
 * Live gifts client — prepaid gift credits spent in live rooms. Viewers
 * top up through the embedded Stripe checkout (same rail as every other
 * Whisper payment); hosts keep 70% and cash out on the coach/WPP rail.
 */

export interface GiftCatalogItem {
  id: string;
  label: string;
  emoji: string;
  cents: number;
}

export interface GiftWallet {
  ready: boolean;
  balanceCents: number;
  hostSharePercent: number;
  catalog: GiftCatalogItem[];
}

export interface GiftEarningRow {
  net_cents: number;
  amount_cents: number;
  gift_emoji: string;
  gift_label: string;
  qty: number;
  sender_username: string | null;
  created_at: string;
}

export interface GiftEarnings {
  ready: boolean;
  allTimeCents: number;
  cashedOutCents: number;
  availableCents: number;
  recent: GiftEarningRow[];
}

/** The credit packs offered in the gift sheet. */
export const GIFT_PACK_CENTS: number[] = [500, 1000, 2500];

async function accessToken(): Promise<string> {
  const { data } = await supabase.auth.getSession();
  const token = data.session?.access_token;
  if (!token) throw new Error("Please sign in first.");
  return token;
}

async function authedFetch(
  path: string,
  init: { method?: string; body?: unknown } = {}
): Promise<Record<string, unknown>> {
  const token = await accessToken();
  const res = await backendFetch(path, {
    method: init.method ?? "GET",
    headers: {
      Authorization: `Bearer ${token}`,
      ...(init.body !== undefined ? { "Content-Type": "application/json" } : {}),
    },
    body: init.body !== undefined ? JSON.stringify(init.body) : undefined,
  });
  const data = (await res.json().catch(() => ({}))) as Record<string, unknown>;
  if (!res.ok) {
    const code = typeof data.error === "string" ? data.error : "";
    const messages: Record<string, string> = {
      sign_in_required: "Please sign in first.",
      insufficient_gift_balance: "Not enough gift credits — add funds below.",
      gifts_not_ready:
        "Gifts aren't switched on yet — one-time setup pending (supabase/live-gifts.sql).",
      room_not_found: "This live room doesn't exist anymore.",
      room_not_live: "This live has ended.",
      cant_gift_yourself: "You can't send gifts to your own stream.",
      gift_not_found: "That gift isn't available.",
      invalid_qty: "Pick between 1 and 20 of a gift.",
      wallet_conflict: "Your wallet was busy — try that again.",
      below_minimum: "You need at least $10.00 in gifts to cash out.",
      not_connected: "Link your bank account first — open Earnings & payouts.",
      payouts_not_ready:
        "Your bank setup isn't finished yet — open Earnings & payouts to complete it.",
      invalid_amount: "Pick a valid amount.",
      billing_not_configured: "Payments aren't configured yet.",
    };
    throw new Error(
      messages[code] ??
        (typeof data.stripeMessage === "string" && data.stripeMessage
          ? data.stripeMessage
          : "Something went wrong. Please try again.")
    );
  }
  return data;
}

export async function fetchGiftWallet(): Promise<GiftWallet> {
  const data = await authedFetch("/gifts/wallet");
  return {
    ready: data.ready === true,
    balanceCents: typeof data.balanceCents === "number" ? data.balanceCents : 0,
    hostSharePercent:
      typeof data.hostSharePercent === "number" ? data.hostSharePercent : 70,
    catalog: Array.isArray(data.catalog)
      ? (data.catalog as GiftCatalogItem[])
      : [],
  };
}

export async function startGiftTopup(
  amountCents: number
): Promise<{ clientSecret: string; publishableKey: string }> {
  const data = await authedFetch("/gifts/topup", {
    method: "POST",
    body: { amountCents, origin: window.location.origin },
  });
  if (
    typeof data.clientSecret !== "string" ||
    typeof data.publishableKey !== "string"
  ) {
    throw new Error("Couldn't start checkout.");
  }
  return {
    clientSecret: data.clientSecret,
    publishableKey: data.publishableKey,
  };
}

export async function sendLiveGift(opts: {
  roomId: string;
  giftId: string;
  qty: number;
}): Promise<{ balanceCents: number; netCents: number }> {
  const data = await authedFetch("/gifts/send", {
    method: "POST",
    body: opts,
  });
  return {
    balanceCents: typeof data.balanceCents === "number" ? data.balanceCents : 0,
    netCents: typeof data.netCents === "number" ? data.netCents : 0,
  };
}

export async function fetchGiftEarnings(): Promise<GiftEarnings> {
  const data = await authedFetch("/gifts/earnings");
  return {
    ready: data.ready === true,
    allTimeCents: typeof data.allTimeCents === "number" ? data.allTimeCents : 0,
    cashedOutCents:
      typeof data.cashedOutCents === "number" ? data.cashedOutCents : 0,
    availableCents:
      typeof data.availableCents === "number" ? data.availableCents : 0,
    recent: Array.isArray(data.recent) ? (data.recent as GiftEarningRow[]) : [],
  };
}

export async function giftCashOut(): Promise<{
  amountCents: number;
  sentToBank: boolean;
}> {
  const data = await authedFetch("/gifts/cashout", { method: "POST" });
  return {
    amountCents: typeof data.amountCents === "number" ? data.amountCents : 0,
    sentToBank: data.sentToBank === true,
  };
}

export function formatGiftCents(cents: number): string {
  return (cents / 100).toLocaleString("en-US", {
    style: "currency",
    currency: "USD",
  });
}
