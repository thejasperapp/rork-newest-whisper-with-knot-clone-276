/**
 * Shared auth storage — ONE Whisper login across every portal door.
 *
 * Supabase keeps its session in localStorage by default, and localStorage is
 * per-origin: workspace.mydailywhisper.com, meet.mydailywhisper.com,
 * coaches., recruiters., business., ads., brands. and the main domain each
 * get their OWN silo — so every subdomain hop landed on the login wall.
 *
 * This adapter keeps the session in a cookie scoped to .mydailywhisper.com
 * (readable by the apex and every subdomain), base64-encoded and chunked to
 * stay under the ~4 KB per-cookie cap, with localStorage as a fast local
 * mirror. On non-production hosts (previews, localhost) it behaves exactly
 * like plain localStorage — subdomains don't apply there.
 *
 * Sign-out drops a tombstone cookie so another subdomain's localStorage
 * mirror can't resurrect the session it still holds; the next login clears
 * the tombstone.
 */

const APEX_DOMAIN = "mydailywhisper.com";
/** Per-cookie payload — comfortably under the ~4 KB browser cap. */
const CHUNK_SIZE = 3000;
/** Hard cap on chunk count (~24 KB total) so request headers never flood. */
const MAX_CHUNKS = 8;
/** 400 days — the browser ceiling; every token refresh renews it. */
const COOKIE_MAX_AGE = 60 * 60 * 24 * 400;
/** Tombstone lifetime — long enough for every open door to notice. */
const TOMBSTONE_MAX_AGE = 60 * 60 * 24 * 30;

function onSharedDomain(): boolean {
  if (typeof window === "undefined" || typeof document === "undefined") {
    return false;
  }
  const host = window.location.hostname.toLowerCase();
  return host === APEX_DOMAIN || host.endsWith(`.${APEX_DOMAIN}`);
}

/** UTF-8 → base64 (cookie values can't carry raw JSON safely). */
function encodeValue(value: string): string {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  bytes.forEach((byte) => {
    binary += String.fromCharCode(byte);
  });
  return btoa(binary);
}

function decodeValue(encoded: string): string | null {
  try {
    const binary = atob(encoded);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i += 1) {
      bytes[i] = binary.charCodeAt(i);
    }
    return new TextDecoder().decode(bytes);
  } catch {
    return null;
  }
}

function readCookie(name: string): string | null {
  const prefix = `${name}=`;
  const entries = document.cookie.split(";");
  for (const entry of entries) {
    const trimmed = entry.trim();
    if (trimmed.startsWith(prefix)) {
      return trimmed.slice(prefix.length);
    }
  }
  return null;
}

function writeCookie(name: string, value: string): void {
  document.cookie = `${name}=${value}; Domain=.${APEX_DOMAIN}; Path=/; Max-Age=${COOKIE_MAX_AGE}; SameSite=Lax; Secure`;
}

function clearCookie(name: string): void {
  document.cookie = `${name}=; Domain=.${APEX_DOMAIN}; Path=/; Max-Age=0; SameSite=Lax; Secure`;
}

function tombstoneName(key: string): string {
  return `${key}.out`;
}

/** Read a (possibly chunked) shared cookie back into its original string. */
function readShared(key: string): string | null {
  const single = readCookie(key);
  if (single) {
    return decodeValue(single);
  }
  const parts: string[] = [];
  for (let i = 0; i < MAX_CHUNKS; i += 1) {
    const part = readCookie(`${key}.${i}`);
    if (!part) break;
    parts.push(part);
  }
  if (parts.length === 0) return null;
  return decodeValue(parts.join(""));
}

/** Write a value as one shared cookie, or numbered chunks when it's large. */
function writeShared(key: string, value: string): void {
  const encoded = encodeValue(value);
  const total = Math.max(1, Math.ceil(encoded.length / CHUNK_SIZE));
  if (total > MAX_CHUNKS) {
    // Pathologically large value — localStorage still carries it locally.
    return;
  }
  if (total === 1) {
    writeCookie(key, encoded);
    for (let i = 0; i < MAX_CHUNKS; i += 1) {
      clearCookie(`${key}.${i}`);
    }
    return;
  }
  clearCookie(key);
  for (let i = 0; i < total; i += 1) {
    writeCookie(`${key}.${i}`, encoded.slice(i * CHUNK_SIZE, (i + 1) * CHUNK_SIZE));
  }
  for (let i = total; i < MAX_CHUNKS; i += 1) {
    clearCookie(`${key}.${i}`);
  }
}

function clearShared(key: string): void {
  clearCookie(key);
  for (let i = 0; i < MAX_CHUNKS; i += 1) {
    clearCookie(`${key}.${i}`);
  }
}

function readLocal(key: string): string | null {
  try {
    return window.localStorage.getItem(key);
  } catch {
    return null;
  }
}

function writeLocal(key: string, value: string): void {
  try {
    window.localStorage.setItem(key, value);
  } catch {
    // Storage full or blocked — the shared cookie still carries the session.
  }
}

function removeLocal(key: string): void {
  try {
    window.localStorage.removeItem(key);
  } catch {
    // Nothing to clean.
  }
}

/**
 * Storage adapter handed to the Supabase client (sync methods are fine —
 * supabase-js accepts sync or async storage).
 */
export const sharedAuthStorage = {
  getItem(key: string): string | null {
    if (typeof window === "undefined") return null;
    const local = readLocal(key);
    if (!onSharedDomain()) return local;
    try {
      const shared = readShared(key);
      if (shared !== null) {
        // The cookie is the cross-subdomain truth — another door may have
        // refreshed the token more recently than this origin's mirror.
        if (local !== shared) writeLocal(key, shared);
        return shared;
      }
      if (readCookie(tombstoneName(key)) !== null) {
        // Signed out on another subdomain — never resurrect a stale mirror.
        if (local !== null) removeLocal(key);
        return null;
      }
      if (local !== null) {
        // A login from before cookie sharing existed — promote it so the
        // next subdomain hop is already signed in.
        writeShared(key, local);
      }
      return local;
    } catch {
      return local;
    }
  },
  setItem(key: string, value: string): void {
    if (typeof window === "undefined") return;
    writeLocal(key, value);
    if (!onSharedDomain()) return;
    try {
      writeShared(key, value);
      clearCookie(tombstoneName(key));
    } catch {
      // Cookies blocked — localStorage keeps this origin signed in.
    }
  },
  removeItem(key: string): void {
    if (typeof window === "undefined") return;
    removeLocal(key);
    if (!onSharedDomain()) return;
    try {
      clearShared(key);
      document.cookie = `${tombstoneName(key)}=1; Domain=.${APEX_DOMAIN}; Path=/; Max-Age=${TOMBSTONE_MAX_AGE}; SameSite=Lax; Secure`;
    } catch {
      // Cookies blocked — local removal already signed this origin out.
    }
  },
};
