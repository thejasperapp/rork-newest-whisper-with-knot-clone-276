import type { Session } from "@supabase/supabase-js";
import { useEffect, useState } from "react";

import { sharedAuthStorage } from "@/lib/authStorage";
import { AUTH_STORAGE_KEY, supabase } from "@/lib/supabase";
import type { WhisperProfile } from "@/lib/types";

/**
 * MULTI-ACCOUNT — Instagram's "tap your username → switch account" grammar,
 * mirroring iOS `WhisperAccountSwitcher`. Every completed sign-in remembers
 * its session pair here; switching adopts a saved session in place (no
 * password), "Add account" parks the current session and opens sign-in, and
 * removal forgets the tokens. Capped at 5 accounts per browser.
 *
 * The one rule that makes this work: a parked login is NEVER signed out
 * server-side. Supabase's `signOut({ scope: "local" })` still ends the
 * session and revokes its refresh token — which is exactly what made every
 * switch-back fail with "login expired" and then delete the account.
 */
export interface SwitchableAccount {
  userId: string;
  username: string;
  displayName?: string | null;
  avatarUrl?: string | null;
  email?: string | null;
  accessToken: string;
  refreshToken: string;
  lastActiveAt: number;
}

const STORAGE_KEY = "whisper.accounts.v1";
/** Set while the user is adding a second account (the auth page is up on purpose). */
const ADDING_KEY = "whisper.accounts.adding";
const REAUTH_EMAIL_KEY = "whisper.accounts.reauth-email";
const CHANGE_EVENT = "whisper-accounts-changed";
export const MAX_ACCOUNTS = 5;

function read(): SwitchableAccount[] {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as unknown;
    if (!Array.isArray(parsed)) return [];
    return parsed.filter(
      (a): a is SwitchableAccount =>
        typeof a === "object" &&
        a !== null &&
        typeof (a as SwitchableAccount).userId === "string" &&
        typeof (a as SwitchableAccount).refreshToken === "string"
    );
  } catch {
    return [];
  }
}

function write(list: SwitchableAccount[]): void {
  try {
    if (list.length === 0) {
      localStorage.removeItem(STORAGE_KEY);
    } else {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(list));
    }
  } catch {
    /* storage unavailable */
  }
  window.dispatchEvent(new Event(CHANGE_EVENT));
}

export function loadAccounts(): SwitchableAccount[] {
  return read().sort((a, b) => b.lastActiveAt - a.lastActiveAt);
}

/** Upserts one account, newest first, capped. */
function upsert(entry: SwitchableAccount): void {
  const rest = read().filter(
    (a) => a.userId.toLowerCase() !== entry.userId.toLowerCase()
  );
  const list = [entry, ...rest]
    .sort((a, b) => b.lastActiveAt - a.lastActiveAt)
    .slice(0, MAX_ACCOUNTS);
  write(list);
}

/**
 * Remembers the LIVE session for the signed-in account with the freshest
 * profile bits. Cheap and idempotent — called after every profile load so
 * stored tokens stay current.
 */
export async function rememberCurrentSession(
  profile?: WhisperProfile | null
): Promise<void> {
  const { data } = await supabase.auth.getSession();
  const session = data.session;
  if (!session?.user || (profile && profile.user_id !== session.user.id)) return;
  rememberSession(session, profile ?? null);
}

export function rememberSession(
  session: Session,
  profile: WhisperProfile | null
): void {
  const uid = session.user.id;
  if (profile && profile.user_id !== uid) return;
  const existing = read().find((a) => a.userId.toLowerCase() === uid.toLowerCase());
  const metaUsername =
    (session.user.user_metadata?.username as string | undefined) ??
    session.user.email?.split("@")[0] ??
    "you";
  upsert({
    userId: uid,
    username: profile?.username ?? existing?.username ?? metaUsername,
    displayName: profile?.display_name ?? existing?.displayName ?? null,
    avatarUrl: profile?.profile_image_url ?? existing?.avatarUrl ?? null,
    email: session.user.email ?? existing?.email ?? null,
    accessToken: session.access_token,
    refreshToken: session.refresh_token,
    lastActiveAt: Date.now(),
  });
  try {
    localStorage.removeItem(ADDING_KEY);
  } catch {
    /* ignore */
  }
}

/** Forgets an account on this browser (tokens deleted). */
export function forgetAccount(userId: string): void {
  write(read().filter((a) => a.userId.toLowerCase() !== userId.toLowerCase()));
}

export type SwitchResult =
  | { ok: true }
  | { ok: false; error: string; needsSignIn: boolean };

function isConnectivityError(error: { name?: string; status?: number } | null): boolean {
  if (!error) return false;
  if (typeof error.name === "string" && error.name.includes("Retryable")) return true;
  return error.status === 0;
}

/**
 * Adopts a saved account's session in place — one click, no password.
 * On failure the CURRENT login is restored (a failed refresh makes the SDK
 * drop whatever session it held) and the saved row STAYS so the user can
 * sign back in with one tap. Nothing is ever deleted by a failed switch.
 */
export async function switchToAccount(account: SwitchableAccount): Promise<SwitchResult> {
  // Park the outgoing account's freshest tokens first so we can come back.
  await rememberCurrentSession();
  const { data: before } = await supabase.auth.getSession();
  const outgoing = before.session;

  const { data, error } = await supabase.auth.setSession({
    access_token: account.accessToken,
    refresh_token: account.refreshToken,
  });
  const adopted = data?.session ?? null;
  const wrongUser =
    adopted !== null && adopted.user.id.toLowerCase() !== account.userId.toLowerCase();

  if (error || !adopted || wrongUser) {
    if (outgoing) {
      const { data: now } = await supabase.auth.getSession();
      if (!now.session || now.session.user.id !== outgoing.user.id) {
        await supabase.auth.setSession({
          access_token: outgoing.access_token,
          refresh_token: outgoing.refresh_token,
        });
      }
    }
    const offline = isConnectivityError(error);
    return {
      ok: false,
      needsSignIn: !offline,
      error: offline
        ? "Couldn't reach Whisper — check your connection and try again."
        : `That login expired — sign in to @${account.username} again to bring it back.`,
    };
  }
  rememberSession(adopted, null);
  return { ok: true };
}

/**
 * "Add Whisper account": remembers the current session and steps THIS
 * browser back to sign-in WITHOUT a server sign-out — the stored session is
 * simply dropped, so the parked refresh token stays valid and the next
 * sign-in replaces it. Callers hard-navigate to /auth afterwards so the
 * client boots clean. Pass an account to prefill its email for a re-login.
 */
export async function beginAddAccount(reauth?: SwitchableAccount): Promise<void> {
  await rememberCurrentSession();
  try {
    localStorage.setItem(ADDING_KEY, "1");
    if (reauth?.email) localStorage.setItem(REAUTH_EMAIL_KEY, reauth.email);
    else localStorage.removeItem(REAUTH_EMAIL_KEY);
  } catch {
    /* ignore */
  }
  sharedAuthStorage.removeItem(AUTH_STORAGE_KEY);
}

/** Email to prefill on the auth page after an expired-login retry. */
export function takeReauthEmail(): string | null {
  try {
    const email = localStorage.getItem(REAUTH_EMAIL_KEY);
    localStorage.removeItem(REAUTH_EMAIL_KEY);
    return email;
  } catch {
    return null;
  }
}

/**
 * "Back to @you" from the add-account screen — re-adopts the most recently
 * active saved login. Returns false when there is nothing to return to.
 */
export async function returnToLastAccount(): Promise<boolean> {
  const last = loadAccounts()[0];
  if (!last) {
    clearAddingFlag();
    return false;
  }
  const result = await switchToAccount(last);
  if (result.ok) clearAddingFlag();
  return result.ok;
}

function clearAddingFlag(): void {
  try {
    localStorage.removeItem(ADDING_KEY);
  } catch {
    /* ignore */
  }
}

export function isAddingAccount(): boolean {
  try {
    return localStorage.getItem(ADDING_KEY) === "1";
  } catch {
    return false;
  }
}

/** Called from the real sign-out so the list never advertises a revoked login. */
export function forgetCurrentOnSignOut(userId: string | undefined): void {
  if (userId) forgetAccount(userId);
}

/** Live list of saved accounts for React surfaces. */
export function useSwitchableAccounts(): SwitchableAccount[] {
  const [accounts, setAccounts] = useState<SwitchableAccount[]>(() => loadAccounts());
  useEffect(() => {
    const refresh = (): void => setAccounts(loadAccounts());
    window.addEventListener(CHANGE_EVENT, refresh);
    window.addEventListener("storage", refresh);
    return () => {
      window.removeEventListener(CHANGE_EVENT, refresh);
      window.removeEventListener("storage", refresh);
    };
  }, []);
  return accounts;
}
