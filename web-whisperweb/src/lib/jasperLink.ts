import { supabase } from "@/lib/supabase";
import { groupThemeSession } from "@/lib/groupThemeSession";

/**
 * Whisper's side of the "Connect Jasper" account-linking flow.
 *
 * Jasper is the primary fitness identity; Whisper keeps its own auth. Linking is
 * optional — a signed-in Whisper user redeems a one-time code generated in
 * Jasper, after which Whisper can read that user's `jasper_*` bridge tables.
 *
 * The mapping lives server-side in `account_links` (one active link per Whisper
 * account). Jasper owns the schema and RPCs — we only call them. All RPCs stamp
 * `auth.uid()` server-side, so the link can't be forged.
 */

export interface JasperLinkStatus {
  isLinked: boolean;
  jasperUid: string | null;
  linkedAt: string | null;
}

interface AccountLinkRow {
  jasper_uid: string;
  linked_at: string | null;
  revoked_at: string | null;
}

export type RedeemError =
  | "invalid or expired code"
  | "cannot link an account to itself"
  | "not authenticated"
  | "unknown";

export interface RedeemResult {
  ok: boolean;
  jasperUid: string | null;
  error: RedeemError | null;
}

/**
 * Redeems an 8-character link code as the signed-in Whisper user. Trim/upper-
 * casing is handled server-side, so the raw user input can be passed through.
 * Returns the linked `jasper_uid` on success.
 */
export async function redeemJasperLinkCode(code: string): Promise<RedeemResult> {
  const trimmed = code.trim();
  if (!trimmed) {
    return { ok: false, jasperUid: null, error: "invalid or expired code" };
  }
  const { data, error } = await supabase.rpc("redeem_jasper_link_code", {
    p_code: trimmed,
  });
  if (error) {
    const msg = error.message as RedeemError;
    const known: RedeemError[] = [
      "invalid or expired code",
      "cannot link an account to itself",
      "not authenticated",
    ];
    return {
      ok: false,
      jasperUid: null,
      error: known.includes(msg) ? msg : "unknown",
    };
  }
  return { ok: true, jasperUid: (data as string | null) ?? null, error: null };
}

/** Whether the current Whisper user has an active Jasper link. */
export async function fetchJasperLinkStatus(accountID: string): Promise<JasperLinkStatus> {
  const session = await groupThemeSession(accountID);
  try {
    const { data, error } = await supabase
      .from("account_links")
      .select("jasper_uid, linked_at, revoked_at")
      .is("revoked_at", null)
      .abortSignal(session.signal);
    session.check();
    // An unavailable status is not evidence that a durable account link was removed.
    if (error) throw error;
    const rows = (data as AccountLinkRow[] | null) ?? [];
    const active = rows[0];
    return {
      isLinked: rows.length > 0,
      jasperUid: active?.jasper_uid ?? null,
      linkedAt: active?.linked_at ?? null,
    };
  } finally { session.dispose(); }
}

/** Revokes the current Whisper user's Jasper link. Either side may revoke. */
export async function revokeJasperLink(): Promise<boolean> {
  const { error } = await supabase.rpc("revoke_jasper_link");
  return !error;
}

/**
 * Resolves which Jasper id the current user reads as: the linked `jasper_uid`
 * if a link exists, otherwise the caller's own `auth.uid()`. Use this value
 * when querying any `jasper_*` bridge table for the signed-in user's own data —
 * never assume `auth.uid()` equals the Jasper id.
 */
export async function jasperUidForSelf(): Promise<string | null> {
  const { data, error } = await supabase.rpc("jasper_uid_for");
  if (error) return null;
  return (data as string | null) ?? null;
}
