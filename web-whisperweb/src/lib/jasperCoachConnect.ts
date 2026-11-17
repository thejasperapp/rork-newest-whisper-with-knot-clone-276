import { JasperApiError, jasperFailure, jasperHeaders, tokenRequest, type JasperSharedGrocery } from "@/lib/jasperConnect";
import { assertJasperSession, invalidateJasperSession, jasperCurrentOwner, jasperSession, noteJasperContract, onJasperInvalidated, JASPER_API_BASE, JASPER_NATIVE_REVIEW_MESSAGE, type JasperSession } from "@/lib/jasperSession";

/**
 * Web port of the iOS `JasperCoachConnect` — per-client Jasper Connect access
 * for coaches. Zero-tap: opening a client dashboard silently mints (or
 * reuses) that client's token through the SAME `jasper_connect_authorize`
 * RPC with `p_client` — the active coach grant IS the consent. `app_name` is
 * canonical per holder, so every client gets a distinct name
 * ("Whisper Coach Web · <uid8>") and minting client B's token can never
 * rotate client A's or the coach's own connection.
 *
 * Coach `all` NEVER covers blood; a 403 `missing_scope` is the client's
 * choice — degrade gracefully, never retry-loop. `GET /v1/dashboard` is
 * cached 60s per client (the published ≤1/min polling cap).
 *
 * September 15 2026 guide: sanitized errors (stable code + X-Request-Id),
 * one Idempotency-Key per deliberate coach write, any 401 or 409
 * connection_changed drops the token for good, and — with webhook push
 * paused by Jasper — every dashboard refresh also reads the client's
 * change-feed journal (`GET /v1/events/page`).
 */

const API_BASE = JASPER_API_BASE;
const TOKEN_PREFIX_KEY = "whisper_jasper_coach_token_web_v2:";
const mintFlights = new Map<string, Promise<{ token: string; meta: JasperCoachAccessMeta }>>();
function connectionKey(uid: string, owner = jasperCurrentOwner()): string {
  if (!owner) throw new JasperApiError(401, "Sign in to Whisper first.");
  return TOKEN_PREFIX_KEY + owner + ":" + uid;
}

type Json = Record<string, unknown>;

function asRecord(v: unknown): Json {
  return typeof v === "object" && v !== null ? (v as Json) : {};
}

function str(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}

function numAny(v: unknown): number | null {
  if (typeof v === "number" && Number.isFinite(v)) return v;
  if (typeof v === "string") {
    const n = Number(v);
    if (Number.isFinite(n)) return n;
  }
  return null;
}

/** First present numeric among candidate keys (snake + camel tolerated). */
function pick(o: Json, ...keys: string[]): number | null {
  for (const k of keys) {
    const v = numAny(o[k]);
    if (v !== null) return v;
  }
  return null;
}

/** Reads requested for coach tokens — everything except `read:blood`
 * (sensitive; needs an explicit client opt-in). */
const COACH_READ_SCOPES = [
  "read:profile", "read:workouts", "read:nutrition", "read:sleep",
  "read:vitals", "read:body", "read:bioage", "read:goals",
  "read:events", "read:charts", "read:preferences", "read:photos",
];

/** Phase 2 write scopes — read & write grants mint them (coach tools
 * unlock); read-only grants reject them and we fall back to reads. */
const COACH_WRITE_SCOPES = [
  "write:workouts", "write:nutrition", "write:goals", "write:charts",
];

export interface JasperCoachAccessMeta {
  clientUid: string;
  scopes: string[];
  canWrite: boolean;
  username: string | null;
  linked: boolean | null;
  tokenPrefix: string;
}

function normalize(uid: string): string {
  return uid.trim().toLowerCase();
}

function isReadOnlyGrantMessage(message: string): boolean {
  const lower = message.toLowerCase();
  return (
    lower.includes("read_write") || lower.includes("read-only") ||
    lower.includes("read_only") || lower.includes("readonly")
  );
}

/** Maps raw mint failures to something a coach can act on. */
export function friendlyCoachMessage(error: unknown): string {
  const raw = error instanceof Error ? error.message : String(error);
  const lower = raw.toLowerCase();
  if (lower.includes("missing_scope") || lower.includes("missing scope")) {
    return "The client chose not to share this data — scope choices live on their Jasper consent screen.";
  }
  if (
    lower.includes("grant") || lower.includes("coach") ||
    lower.includes("permission") || lower.includes("not allowed") ||
    lower.includes("forbidden")
  ) {
    return "Jasper reports no active coach grant for this client — ask them to re-grant coach access, then try again.";
  }
  return raw;
}

const metaByClient = new Map<string, JasperCoachAccessMeta>();

async function authorize(uid: string, scopes: string[], context: JasperSession): Promise<Json> {
  assertJasperSession(context);
  const response = await fetch(`${API_BASE}/v1/authorize`, {
    method: "POST", cache: "no-store", redirect: "error",
    headers: jasperHeaders({ bearer: context.jwt, method: "POST", path: "/v1/authorize", hasBody: true }),
    body: JSON.stringify({ app_name: `Whisper Coach Web · ${uid.slice(0, 8)}`, client_user_id: uid, scopes }),
    signal: AbortSignal.any([context.signal, AbortSignal.timeout(30000)]),
  });
  const body = asRecord(await response.json().catch(() => ({})));
  assertJasperSession(context);
  noteJasperContract(response.headers);
  if (!response.ok) throw jasperFailure(response.status, response.headers, body);
  return body;
}

/** One authorize pass, most-capable first: reads + writes → reads-only →
 * unscoped (deployed RPCs that predate `p_scopes`). */
async function mint(uid: string, context: JasperSession): Promise<{ token: string; meta: JasperCoachAccessMeta }> {
  let body: Json;
  try {
    body = await authorize(uid, [...COACH_READ_SCOPES, ...COACH_WRITE_SCOPES], context);
    const answerText = `${str(body.error) ?? ""} ${str(body.hint) ?? ""}`;
    if (body.ok !== true && isReadOnlyGrantMessage(answerText)) {
      body = await authorize(uid, COACH_READ_SCOPES, context);
    }
  } catch (e) {
    const message = e instanceof Error ? e.message : "";
    if (isReadOnlyGrantMessage(message)) {
      body = await authorize(uid, COACH_READ_SCOPES, context);
    } else {
      throw e;
    }
  }
  const token = str(body.token);
  assertJasperSession(context);
  if (body.ok !== true || !token?.startsWith("jc_") || !Array.isArray(body.scopes)) {
    const message = str(body.error) ?? "Jasper didn't return a client token.";
    const hint = str(body.hint);
    throw new JasperApiError(403, [message, hint].filter(Boolean).join(" "));
  }
  const user = asRecord(body.user);
  const scopes = Array.isArray(body.scopes)
    ? (body.scopes as unknown[]).filter((s): s is string => typeof s === "string")
    : [];
  if (!scopes.every((scope) => [...COACH_READ_SCOPES, ...COACH_WRITE_SCOPES].includes(scope))) throw new JasperApiError(502, "Jasper returned unverified permissions. Review coach access in Jasper.");
  const meta: JasperCoachAccessMeta = {
    clientUid: uid,
    scopes,
    canWrite: scopes.some((s) => s === "all" || s.startsWith("write:")),
    username: str(user.username),
    linked: typeof user.linked === "boolean" ? user.linked : null,
    tokenPrefix: str(body.token_prefix) ?? token.slice(0, 11),
  };
  localStorage.setItem(connectionKey(uid, context.ownerId), JSON.stringify({ token, meta }));
  metaByClient.set(uid, meta);
  // A fresh token starts a fresh journal position — the next dashboard read
  // positions the change-feed cursor (guide §06); nothing is replayed.
  forgetJournal(uid, context.ownerId);
  return { token, meta };
}

async function credentials(rawUid: string, context: JasperSession): Promise<{ token: string; meta: JasperCoachAccessMeta }> {
  assertJasperSession(context);
  const uid = normalize(rawUid);
  const key = connectionKey(uid, context.ownerId);
  if (localStorage.getItem(key + ":revoked")) throw new JasperApiError(401, "Jasper access ended. Ask the client to review their grant, then use Reconnect Jasper access.");
  try {
    const cached = JSON.parse(localStorage.getItem(key) ?? "null") as { token: string; meta: JasperCoachAccessMeta } | null;
    if (cached?.token?.startsWith("jc_") && cached.meta?.clientUid === uid && Array.isArray(cached.meta.scopes)) {
      metaByClient.set(uid, cached.meta);
      return cached;
    }
  } catch { localStorage.removeItem(key); }
  const flightKey = `${context.generation}:${key}`;
  const running = mintFlights.get(flightKey);
  if (running) return running;
  const flight = mint(uid, context);
  mintFlights.set(flightKey, flight);
  try { return await flight; } finally { if (mintFlights.get(flightKey) === flight) mintFlights.delete(flightKey); }
}

/** Explicit coach action; the standing client grant is still checked by Jasper. */
export async function reconnectCoachAccess(rawUid: string): Promise<void> {
  const context = await jasperSession();
  const uid = normalize(rawUid);
  localStorage.removeItem(connectionKey(uid, context.ownerId) + ":revoked");
  localStorage.removeItem(connectionKey(uid, context.ownerId));
  invalidateJasperSession();
  await credentials(uid, await jasperSession());
}

export function coachAccessMeta(rawUid: string): JasperCoachAccessMeta | null {
  return metaByClient.get(normalize(rawUid)) ?? null;
}

function drop(uid: string): void {
  const key = connectionKey(uid);
  localStorage.removeItem(key);
  localStorage.setItem(key + ":revoked", "1");
  metaByClient.delete(uid);
  dashboardCache.delete(uid);
  dashboardCache.delete(`${uid}#week`);
  const owner = jasperCurrentOwner();
  if (owner) forgetJournal(uid, owner);
}

/** Forgets the client token locally (call when coaching ends). */
export function forgetCoachAccess(rawUid: string): void {
  drop(normalize(rawUid));
  invalidateJasperSession();
}

async function clientRequest(
  rawUid: string,
  path: string,
  options: { method?: string; body?: Json; idempotencyKey?: string } = {}
): Promise<Json> {
  const context = await jasperSession();
  const uid = normalize(rawUid);
  if (!/^\/v1\/[a-z_]+(?:\/[a-zA-Z0-9_-]+)?(?:\?[^#]*)?$/.test(path)) throw new JasperApiError(400, "Invalid Jasper resource.");
  if (path.split("?")[0] === "/v1/diet_plans/generate") throw new JasperApiError(409, JASPER_NATIVE_REVIEW_MESSAGE);
  const method = options.method ?? "GET";
  const send = async (token: string): Promise<Json> => {
    assertJasperSession(context);
    const res = await fetch(`${API_BASE}${path}`, {
      method,
      cache: "no-store", redirect: "error",
      signal: AbortSignal.any([context.signal, AbortSignal.timeout(30000)]),
      headers: jasperHeaders({ bearer: token, method, path, hasBody: options.body !== undefined, idempotencyKey: options.idempotencyKey }),
      body: options.body ? JSON.stringify(options.body) : undefined,
    });
    const body = asRecord(await res.json().catch(() => ({})));
    assertJasperSession(context);
    noteJasperContract(res.headers);
    if (!res.ok || body.ok === false) throw jasperFailure(res.status, res.headers, body);
    return body;
  };
  const { token } = await credentials(uid, context);
  try {
    return await send(token);
  } catch (e) {
    assertJasperSession(context);
    if (e instanceof JasperApiError && e.isRevocation) {
      // Guide §08: invalid_token / coach_grant_revoked / connection_changed —
      // the token is dead; drop it and never re-mint on our own.
      drop(uid);
      invalidateJasperSession();
      throw new JasperApiError(401, "Jasper access ended. Review the client grant before explicitly reconnecting.", { code: e.code, requestId: e.requestId });
    }
    if (e instanceof JasperApiError && (e.code === "coach_grant_read_only" || isReadOnlyGrantMessage(e.message))) {
      const meta = metaByClient.get(uid);
      if (meta) metaByClient.set(uid, { ...meta, canWrite: false });
      throw new JasperApiError(
        403,
        "This coaching grant is read-only — ask the client to switch coach access to read & write in Jasper, then try again."
      );
    }
    throw e;
  }
}

// MARK: - Reads / writes as the client

export async function coachRead(uid: string, resource: string, limit = 100, extra?: string): Promise<Json[]> {
  const body = await clientRequest(uid, `/v1/${resource}?limit=${limit}${extra ?? ""}`);
  return Array.isArray(body.data) ? (body.data as Json[]) : [];
}

export interface JasperWriteReceipt {
  id: string | null;
  resource: string;
}

/** POST /v1/<resource> as this client — coach tools. One deliberate attempt:
 * `client_id` is record identity (upsert), the Idempotency-Key is the retry
 * protection (guide §05) — a caller letting the coach retry the SAME change
 * passes the key it used first. Nothing here retries on its own. */
export async function coachWrite(uid: string, resource: string, payload: Json, idempotencyKey: string = crypto.randomUUID()): Promise<JasperWriteReceipt> {
  const body = { ...payload };
  if (!body.client_id) body.client_id = crypto.randomUUID().toLowerCase();
  const answer = await clientRequest(uid, `/v1/${resource}`, { method: "POST", body, idempotencyKey });
  const row = asRecord(answer.data ?? answer.row ?? answer);
  return { id: str(row.id) ?? str(answer.id) ?? str(body.client_id as string), resource };
}

/** DELETE — the undo behind every coach write (Jasper emits a deletion
 * event so the client's apps stay truthful). Same one-key-per-attempt rule. */
export async function coachDelete(uid: string, resource: string, id: string, idempotencyKey: string = crypto.randomUUID()): Promise<void> {
  await clientRequest(uid, `/v1/${resource}?id=${encodeURIComponent(id)}`, { method: "DELETE", idempotencyKey });
}

/** GET /v1/grocery_list through the coach-held token — the SAME shared
 * checklist state the client's Jasper app reads and writes. */
export async function coachGroceryList(uid: string): Promise<JasperSharedGrocery> {
  const body = await clientRequest(uid, "/v1/grocery_list");
  const plan = asRecord(body.plan);
  const categories = (Array.isArray(body.categories) ? body.categories : []).map((raw) => {
    const cat = asRecord(raw);
    const items = (Array.isArray(cat.items) ? cat.items : []).map((rawItem) => {
      const item = asRecord(rawItem);
      return {
        id: str(item.id) ?? crypto.randomUUID(),
        name: str(item.name) ?? "Item",
        quantity: str(item.quantity),
        usedInMeals: str(item.used_in_meals),
        checked: item.checked === true,
      };
    });
    return { name: str(cat.name) ?? "Groceries", items };
  });
  return { planId: str(plan.id), planName: str(plan.name), categories };
}

/** Check items off the client's list (write grant required). */
export async function coachSetGroceryChecks(
  uid: string,
  planId: string | null,
  changes: { id: string; checked: boolean }[]
): Promise<void> {
  if (changes.length === 0) return;
  const body: Json = { items: changes };
  if (planId) body.plan_id = planId;
  await clientRequest(uid, "/v1/grocery_list", { method: "POST", body, idempotencyKey: crypto.randomUUID() });
}

/** POST /v1/marketplace/import on THIS client's token — coach attribution,
 * upserts by template id (never duplicates). */
export async function coachMarketplaceImport(uid: string, templateId: string): Promise<void> {
  await clientRequest(uid, "/v1/marketplace/import", {
    method: "POST",
    body: { template_id: templateId },
  });
  dashboardCache.delete(normalize(uid));
  dashboardCache.delete(`${normalize(uid)}#week`);
}

// MARK: - Change feed (GET /v1/events/page — September 15 2026)

/** One change-feed event from Jasper's journal. Hints only: something
 * changed; they never establish complete mutation coverage. */
export interface JasperCoachEvent {
  id: string;
  event: string;
  resource: string | null;
  refId: string | null;
  occurredAt: string | null;
  /** "workout.completed" → "Workout completed". */
  title: string;
}

/** `next_cursor` and `context` travel together; `settled` is false while the
 * first walk to the journal tail is still in progress (nothing seen then is
 * ever shown as live). Retention is 30 days, so an old position is re-established. */
interface JasperJournalPosition {
  cursor: string;
  context: string | null;
  settled: boolean;
  updatedAt: number;
}

export type JasperChangeFeedOutcome = "skipped" | "positioned" | "unchanged" | "fresh" | "unavailable" | "revoked";

const JOURNAL_PREFIX_KEY = "whisper_jasper_coach_journal_v1:";
const JOURNAL_RETENTION_MS = 29 * 86400000;
const JOURNAL_MIN_INTERVAL_MS = 20000;
const JOURNAL_PAGE_LIMIT = 200;
const JOURNAL_MAX_PAGES = 6;
const eventsByClient = new Map<string, JasperCoachEvent[]>();
const seenByClient = new Map<string, Set<string>>();
const journalNotes = new Map<string, string>();
const journalPassAt = new Map<string, number>();
const journalRunning = new Set<string>();

function journalKey(uid: string, owner: string): string {
  return `${JOURNAL_PREFIX_KEY}${owner}:${uid}`;
}

function forgetJournal(uid: string, owner: string): void {
  localStorage.removeItem(journalKey(uid, owner));
  eventsByClient.delete(uid);
  seenByClient.delete(uid);
  journalNotes.delete(uid);
  journalPassAt.delete(uid);
}

function loadJournal(key: string): JasperJournalPosition | null {
  try {
    const stored = JSON.parse(localStorage.getItem(key) ?? "null") as JasperJournalPosition | null;
    if (!stored || typeof stored.cursor !== "string" || typeof stored.updatedAt !== "number") return null;
    return Date.now() - stored.updatedAt > JOURNAL_RETENTION_MS ? null : stored;
  } catch {
    return null;
  }
}

/** Journal positions are decimal strings (`^[0-9]+$`); a numeric answer is
 * tolerated, anything else is not a cursor. */
function decimalString(v: unknown): string | null {
  if (typeof v === "number" && Number.isInteger(v) && v >= 0) return String(v);
  if (typeof v === "string" && /^[0-9]+$/.test(v.trim())) return v.trim();
  return null;
}

function eventTitle(event: string): string {
  const words = event.replace(/[._]/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

function parseEvent(raw: unknown): JasperCoachEvent | null {
  const row = asRecord(raw);
  const id = str(row.id) ?? (typeof row.id === "number" ? String(row.id) : null) ?? decimalString(row.position);
  if (!id) return null;
  const event = str(row.event) ?? str(row.type) ?? str(row.name) ?? "event";
  return {
    id,
    event,
    resource: str(row.resource),
    refId: str(row.ref_id) ?? (typeof row.ref_id === "number" ? String(row.ref_id) : null) ?? str(row.resource_id),
    occurredAt: str(row.occurred_at) ?? str(row.created_at) ?? str(row.at),
    title: eventTitle(event),
  };
}

/**
 * One journal pass for this client through the coach-held token (guide §06).
 * Jasper has paused webhook push (`webhook_egress_unavailable`), so this is
 * how coach dashboards learn that something changed: bounded, deduped,
 * throttled, first pass positions the cursor only. Never throws; `revoked`
 * means the token died (already dropped, never re-minted on its own).
 */
export async function coachReconcileChangeFeed(rawUid: string): Promise<JasperChangeFeedOutcome> {
  const uid = normalize(rawUid);
  if (journalRunning.has(uid)) return "skipped";
  const last = journalPassAt.get(uid);
  if (last !== undefined && Date.now() - last < JOURNAL_MIN_INTERVAL_MS) return "skipped";
  const context = await jasperSession().catch(() => null);
  if (!context) return "skipped";
  journalRunning.add(uid);
  try {
    let meta: JasperCoachAccessMeta;
    try {
      meta = (await credentials(uid, context)).meta;
    } catch (e) {
      return e instanceof JasperApiError && e.status === 401 ? "revoked" : "skipped";
    }
    // Stamp the pass only after credentials: a fresh mint resets the journal
    // (forgetJournal) and must not erase the throttle for this pass.
    journalPassAt.set(uid, Date.now());
    if (!meta.scopes.includes("read:events") && !meta.scopes.includes("all")) {
      journalNotes.set(uid, "Change hints need read:events — this grant doesn't share it.");
      return "unavailable";
    }
    const key = journalKey(uid, context.ownerId);
    const stored = loadJournal(key);
    const positioning = stored?.settled !== true;
    const position: JasperJournalPosition = stored ?? { cursor: "0", context: null, settled: false, updatedAt: Date.now() };
    const fresh: JasperCoachEvent[] = [];
    let reachedTail = false;
    for (let page = 0; page < JOURNAL_MAX_PAGES; page += 1) {
      const query = new URLSearchParams({ cursor: position.cursor, limit: String(JOURNAL_PAGE_LIMIT) });
      if (position.context) query.set("context", position.context);
      let body: Json;
      try {
        body = await clientRequest(uid, `/v1/events/page?${query.toString()}`);
      } catch (e) {
        if (e instanceof JasperApiError && e.status === 401) return "revoked";   // token dropped by clientRequest
        if (context.signal.aborted || !(e instanceof JasperApiError)) return "skipped";
        const code = e.code ?? "";
        if (code === "missing_scope") journalNotes.set(uid, "Change hints need read:events — this grant doesn't share it.");
        else if (code === "unknown_resource") journalNotes.set(uid, "This Jasper host has no change-feed journal yet.");
        else {
          if (/cursor|expired|context/.test(code)) localStorage.removeItem(key);
          journalNotes.set(uid, e.message);
        }
        return "unavailable";
      }
      const rows = Array.isArray(body.events) ? body.events : Array.isArray(body.data) ? body.data : [];
      const events = rows.map(parseEvent).filter((event): event is JasperCoachEvent => event !== null);
      const tail = rows.length > 0 ? asRecord(rows[rows.length - 1]) : null;
      const next = decimalString(body.next_cursor) ?? (tail ? decimalString(tail.position ?? tail.cursor ?? tail.id) : null);
      if (!positioning) fresh.push(...events);
      if (next) position.cursor = next;
      else if (events.length > 0) {
        // Events without a continuation would replay forever — refuse to arm.
        journalNotes.set(uid, "The change feed returned events without a cursor — refresh still works.");
        return "unavailable";
      }
      const ctx = str(body.context);
      if (ctx) position.context = ctx;
      const hasMore = typeof body.has_more === "boolean" ? body.has_more : rows.length >= JOURNAL_PAGE_LIMIT;
      if (!hasMore) { reachedTail = true; break; }
    }
    if (positioning) position.settled = reachedTail;
    position.updatedAt = Date.now();
    localStorage.setItem(key, JSON.stringify(position));
    journalNotes.delete(uid);
    if (positioning) return "positioned";
    const seen = seenByClient.get(uid) ?? new Set<string>();
    const added: JasperCoachEvent[] = [];
    for (const event of fresh) {   // at-least-once → dedupe by id, within and across pages
      if (seen.has(event.id)) continue;
      seen.add(event.id);
      added.push(event);
    }
    seenByClient.set(uid, seen.size > 600 ? new Set(added.map((event) => event.id)) : seen);
    if (added.length === 0) return "unchanged";
    added.sort((a, b) => (b.occurredAt ?? "").localeCompare(a.occurredAt ?? ""));
    eventsByClient.set(uid, [...added, ...(eventsByClient.get(uid) ?? [])].slice(0, 8));
    return "fresh";
  } catch {
    return "skipped";
  } finally {
    journalRunning.delete(uid);
  }
}

/** Most recent journal events for this client, newest first (max 8). */
export function coachRecentEvents(rawUid: string): JasperCoachEvent[] {
  return eventsByClient.get(normalize(rawUid)) ?? [];
}

/** Sanitized reason the last pass produced no hints (code + request id tail). */
export function coachChangeFeedNote(rawUid: string): string | null {
  return journalNotes.get(normalize(rawUid)) ?? null;
}

/** True once the journal cursor sits at the tail — later passes report live changes. */
export function coachChangeFeedArmed(rawUid: string): boolean {
  const owner = jasperCurrentOwner();
  if (!owner) return false;
  return loadJournal(journalKey(normalize(rawUid), owner))?.settled === true;
}

// MARK: - One-call dashboard (GET /v1/dashboard)

export interface JasperDashSection {
  locked: boolean;
  requiredScope?: string;
  rows?: Json[];
}

export interface JasperDashSummary {
  readinessScore: number | null;
  sleepQualityScore: number | null;
  sleepDurationSeconds: number | null;
  biologicalAge: number | null;
  bioageDeltaYears: number | null;
  weightKg: number | null;
  workoutsLast7d: number | null;
  mealsToday: number | null;
  kcalToday: number | null;
  bloodLocked: boolean;
}

export interface JasperDashDigest {
  windowDays: number | null;
  readinessAvg: number | null;
  readinessDelta: number | null;
  sleepQuality: number | null;
  sleepQualityDelta: number | null;
  sleepDurationSeconds: number | null;
  workouts: number | null;
  workoutsDelta: number | null;
  volumeKg: number | null;
  prsThisWeek: number | null;
  kcalPerDay: number | null;
  kcalDelta: number | null;
  mealsLogged: number | null;
  weightKgLatest: number | null;
  weightDeltaKg: number | null;
  highlights: string[];
}

export interface JasperClientDashboard {
  fetchedAt: number;
  summary: JasperDashSummary;
  sections: Record<string, JasperDashSection>;
  digest: JasperDashDigest | null;
}

export function dashRows(dash: JasperClientDashboard, name: string): Json[] {
  const section = dash.sections[name];
  if (!section || section.locked) return [];
  return section.rows ?? [];
}

export function dashLockedScope(dash: JasperClientDashboard, name: string): string | null {
  const section = dash.sections[name];
  if (!section || !section.locked) return null;
  return section.requiredScope ?? `read:${name}`;
}

export function dashLockedNames(dash: JasperClientDashboard): string[] {
  return Object.entries(dash.sections)
    .filter(([, s]) => s.locked)
    .map(([k]) => k)
    .sort();
}

function parseDashboard(body: Json): JasperClientDashboard | null {
  const rawSections = asRecord(body.sections);
  if (Object.keys(rawSections).length === 0 && !body.summary) return null;
  const sections: Record<string, JasperDashSection> = {};
  for (const [key, value] of Object.entries(rawSections)) {
    const dict = asRecord(value);
    if (dict.locked === true) {
      sections[key] = {
        locked: true,
        requiredScope: str(dict.required_scope) ?? str(dict.requiredScope) ?? `read:${key}`,
      };
    } else {
      const rows = Array.isArray(dict.data) ? (dict.data as Json[]) : Array.isArray(value) ? (value as Json[]) : [];
      sections[key] = { locked: false, rows };
    }
  }
  const s = asRecord(body.summary);
  const summary: JasperDashSummary = {
    readinessScore: pick(s, "readiness_score", "readinessScore", "readiness"),
    sleepQualityScore: pick(s, "sleep_quality_score", "sleepQualityScore", "sleep_quality"),
    sleepDurationSeconds: pick(s, "sleep_duration_seconds", "sleepDurationSeconds"),
    biologicalAge: pick(s, "biological_age", "biologicalAge", "bio_age"),
    bioageDeltaYears: pick(s, "bioage_delta_years", "bioageDeltaYears", "bio_age_delta"),
    weightKg: pick(s, "weight_kg", "weightKg"),
    workoutsLast7d: pick(s, "workouts_last_7d", "workoutsLast7d", "workouts_7d"),
    mealsToday: pick(s, "meals_today", "mealsToday"),
    kcalToday: pick(s, "kcal_today", "kcalToday", "calories_today"),
    bloodLocked: s.blood_locked === true || sections["blood_panels"]?.locked === true,
  };
  const d = asRecord(body.digest);
  let digest: JasperDashDigest | null = null;
  if (Object.keys(d).length > 0) {
    const readiness = asRecord(d.readiness);
    const sleep = asRecord(d.sleep);
    const training = asRecord(d.training);
    const nutrition = asRecord(d.nutrition);
    const bodyBlock = asRecord(d.body);
    digest = {
      windowDays: pick(d, "window_days", "windowDays"),
      readinessAvg: pick(readiness, "avg", "average"),
      readinessDelta: pick(readiness, "delta"),
      sleepQuality: pick(sleep, "quality"),
      sleepQualityDelta: pick(sleep, "quality_delta", "qualityDelta"),
      sleepDurationSeconds: pick(sleep, "duration_seconds", "durationSeconds"),
      workouts: pick(training, "workouts"),
      workoutsDelta: pick(training, "workouts_delta", "workoutsDelta"),
      volumeKg: pick(training, "volume_kg", "volumeKg"),
      prsThisWeek: pick(training, "prs_this_week", "prsThisWeek"),
      kcalPerDay: pick(nutrition, "kcal_per_day", "kcalPerDay"),
      kcalDelta: pick(nutrition, "kcal_delta", "kcalDelta"),
      mealsLogged: pick(nutrition, "meals_logged", "mealsLogged"),
      weightKgLatest: pick(bodyBlock, "weight_kg_latest", "weightKgLatest", "weight_kg"),
      weightDeltaKg: pick(bodyBlock, "weight_delta_kg", "weightDeltaKg"),
      highlights: (Array.isArray(d.highlights) ? d.highlights : [])
        .filter((h): h is string => typeof h === "string" && h.trim().length > 0)
        .slice(0, 4),
    };
  }
  return { fetchedAt: Date.now(), summary, sections, digest };
}

const dashboardCache = new Map<string, JasperClientDashboard>();
const dashboardInflight = new Map<string, Promise<JasperClientDashboard>>();

/**
 * The ENTIRE coach dashboard in one request — the same payload Jasper's own
 * in-app coach view renders. Sections are scope-gated INDEPENDENTLY.
 * Cached 60s per client per period (the doc's ≤1/min polling cap).
 * `period: "week"` flips to the weekly digest mode. Throws with an honest,
 * coach-actionable message when the call itself failed.
 */
export async function coachDashboard(
  rawUid: string,
  period?: "week",
  force = false
): Promise<JasperClientDashboard> {
  const context = await jasperSession();
  const uid = normalize(rawUid);
  const key = period ? `${uid}#${period}` : uid;
  const cached = dashboardCache.get(key);
  if (!force && cached && Date.now() - cached.fetchedAt < 60000) return cached;
  const running = dashboardInflight.get(key);
  if (running) return running;
  const task = (async (): Promise<JasperClientDashboard> => {
    try {
      // Guide §06: the change feed rides the same once-a-minute rail as the
      // dashboard — and runs FIRST, so its hints are current when this
      // payload renders.
      const feed = await coachReconcileChangeFeed(uid);
      if (feed === "revoked") throw new JasperApiError(401, "Jasper access ended. Review the client grant before explicitly reconnecting.");
      assertJasperSession(context);
      const body = await clientRequest(uid, `/v1/dashboard${period ? `?period=${period}` : ""}`);
      const dash = parseDashboard(body);
      if (!dash) throw new JasperApiError(500, "Jasper's dashboard reply couldn't be read.");
      assertJasperSession(context);
      dashboardCache.set(key, dash);
      return dash;
    } finally {
      if (!context.signal.aborted) dashboardInflight.delete(key);
    }
  })();
  dashboardInflight.set(key, task);
  return task;
}

/** POST /v1/diet_plans/generate on the client's token — Jasper's OWN
 * generator (15-60s; scope + coach gate verified server-side). */
export async function coachGenerateDietPlan(uid: string, body: Json): Promise<Json> {
  return clientRequest(uid, "/v1/diet_plans/generate", { method: "POST", body });
}

// MARK: - Own one-call dashboard (Jasper Intelligence native data cards)

let ownDashCache: JasperClientDashboard | null = null;
let ownDashInflight: Promise<JasperClientDashboard | null> | null = null;

/**
 * The user's OWN `GET /v1/dashboard` — the exact envelope the coach read
 * parses, through the user's own Connect token. Cached 60s; null when not
 * connected or unreadable (callers render honest empty states, never throw).
 */
export async function ownDashboard(force = false): Promise<JasperClientDashboard | null> {
  const context = await jasperSession();
  if (!force && ownDashCache && Date.now() - ownDashCache.fetchedAt < 60000) return ownDashCache;
  if (ownDashInflight) return ownDashInflight;
  ownDashInflight = (async (): Promise<JasperClientDashboard | null> => {
    try {
      const body = await tokenRequest("/v1/dashboard");
      assertJasperSession(context);
      const dash = parseDashboard(body);
      if (dash) ownDashCache = dash;
      return dash;
    } catch {
      return null;
    } finally {
      if (!context.signal.aborted) ownDashInflight = null;
    }
  })();
  return ownDashInflight;
}

onJasperInvalidated(() => {
  metaByClient.clear(); mintFlights.clear();
  dashboardCache.clear(); dashboardInflight.clear();
  eventsByClient.clear(); seenByClient.clear(); journalNotes.clear(); journalPassAt.clear();
  ownDashCache = null; ownDashInflight = null;
});
