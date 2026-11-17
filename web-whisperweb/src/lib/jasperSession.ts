import { supabase } from "@/lib/supabase";

/** Jasper Connect service base from the September 15, 2026 guide — API
 * revision 2026-09-12.1, compatibility patch 2026-09-14, contract 2026-09-11.
 * Older hosts still answer with earlier revisions and lack /v1/events/page, so
 * every response's X-Jasper-API-Version is checked against `JASPER_API_REVISION`. */
export const JASPER_API_BASE = "https://bpi3d9e8nzz0z8twjpfra-backend.rork.app";
export const JASPER_API_REVISION = "2026-09-12.1";
export const JASPER_COMPATIBILITY_PATCH = "2026-09-14";
export const JASPER_NATIVE_REVIEW_MESSAGE = "Connected meal generation is paused. Create and review your plan in Jasper’s Nutrition screen, then refresh your saved plans here. Nothing was generated or saved.";

/** Routes whose POST/DELETE honor an Idempotency-Key (guide §05): generic data
 * resources, recipes and grocery changes. Connection mint/claim, token
 * revocation, hooks, marketplace, link intents and the paused generation route
 * do not — the header is never sent there. */
export function jasperSupportsIdempotency(path: string): boolean {
  const bare = path.split("?")[0];
  const excluded = ["/v1/authorize", "/v1/requests", "/v1/tokens", "/v1/webhooks", "/v1/marketplace", "/v1/diet_plans/generate", "/v1/link-intents"];
  return !excluded.some((prefix) => bare === prefix || bare.startsWith(prefix + "/"));
}

let observedApiVersion: string | null = null;
let observedPatch: string | null = null;
const contractListeners = new Set<() => void>();

/** Records the revision a Jasper response declared (guide §01 "Version check"). */
export function noteJasperContract(headers: Headers): void {
  const version = headers.get("X-Jasper-API-Version");
  if (version && version !== observedApiVersion) {
    observedApiVersion = version;
    contractListeners.forEach((listener) => listener());
  }
}

/** Records /v1/experience.compatibility_patch once it has been read. */
export function noteJasperCompatibilityPatch(patch: string | null): void {
  if (patch === observedPatch) return;
  observedPatch = patch;
  contractListeners.forEach((listener) => listener());
}

/** Human note when the host answers with an older revision or patch than this
 * build was written for; null when everything matches or nothing was seen yet.
 * An older host is reported, never refused. */
export function jasperContractNote(): string | null {
  const notes: string[] = [];
  if (observedApiVersion && observedApiVersion !== JASPER_API_REVISION) notes.push(`API ${observedApiVersion} (this build expects ${JASPER_API_REVISION})`);
  if (observedPatch && observedPatch < JASPER_COMPATIBILITY_PATCH) notes.push(`compatibility patch ${observedPatch} (this build expects ${JASPER_COMPATIBILITY_PATCH})`);
  return notes.length === 0 ? null : `This Jasper host answers with ${notes.join(" and ")} — fixes from the September 14 patch may be missing.`;
}

export function onJasperContractChanged(listener: () => void): () => void {
  contractListeners.add(listener);
  return () => { contractListeners.delete(listener); };
}

/** An account generation, not just an ID: switching away and back invalidates work. */
export interface JasperSession {
  ownerId: string;
  generation: number;
  jwt: string;
  signal: AbortSignal;
}

let ownerId: string | null = null;
let generation = 0;
let controller = new AbortController();
const listeners = new Set<() => void>();

/** Invalidates pending reads and private caches without changing the Whisper login. */
export function invalidateJasperSession(): void {
  generation += 1;
  controller.abort();
  controller = new AbortController();
  listeners.forEach((listener) => listener());
}

/** Synchronous notification; listeners must never call Supabase auth inside it. */
export function onJasperInvalidated(listener: () => void): () => void {
  listeners.add(listener);
  return () => { listeners.delete(listener); };
}

function adoptOwner(next: string | null): void {
  if (ownerId === next) return;
  ownerId = next;
  invalidateJasperSession();
}

const { data: authListener } = supabase.auth.onAuthStateChange((_event, session) => {
  adoptOwner(session?.user.id.toLowerCase() ?? null);
});
function storageChanged(event: StorageEvent): void {
  if (event.key === null || event.key.startsWith("whisper_jasper_connect_") || event.key.startsWith("whisper_jasper_coach_")) invalidateJasperSession();
}
window.addEventListener("storage", storageChanged);
if (import.meta.hot) import.meta.hot.dispose(() => {
  authListener.subscription.unsubscribe();
  window.removeEventListener("storage", storageChanged);
});

export function jasperCurrentOwner(): string | null { return ownerId; }
export function jasperCurrentGeneration(): number { return generation; }

/** Captures the current signed-in account; refuses stale auth-read completions. */
export async function jasperSession(): Promise<JasperSession> {
  const before = generation;
  const initialOwner = ownerId;
  const { data, error } = await supabase.auth.getSession();
  const session = data.session;
  if (error || !session) throw new Error("Sign in to Whisper first.");
  const next = session.user.id.toLowerCase();
  if (before !== generation && (initialOwner !== null || next !== ownerId || generation !== before + 1)) throw new Error("Your account changed. Open Jasper again.");
  if (ownerId === null) adoptOwner(next);
  if (ownerId !== next) throw new Error("Your account changed. Open Jasper again.");
  return { ownerId: next, generation, jwt: session.access_token, signal: controller.signal };
}

/** Check before sending and after every asynchronous boundary. */
export function assertJasperSession(context: JasperSession): void {
  if (context.ownerId !== ownerId || context.generation !== generation || context.signal.aborted) {
    throw new Error("Your Jasper connection or Whisper account changed. Open it again.");
  }
}
