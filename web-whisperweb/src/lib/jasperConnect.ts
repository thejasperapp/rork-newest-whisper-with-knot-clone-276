import { supabase } from "@/lib/supabase";
import { assertJasperSession, invalidateJasperSession, jasperContractNote, jasperCurrentOwner, jasperSession, jasperSupportsIdempotency, noteJasperCompatibilityPatch, noteJasperContract, onJasperInvalidated, JASPER_API_BASE, JASPER_NATIVE_REVIEW_MESSAGE, type JasperSession } from "@/lib/jasperSession";

/**
 * Web port of the iOS Jasper Connect client — the uniform REST surface of the
 * partner Jasper fitness app. Only explicit permission approval creates a
 * token. Credentials belong to one Whisper owner; revocation never mints a
 * replacement automatically.
 *
 * September 15 2026 guide: sanitized errors (stable code + X-Request-Id, never
 * bodies or credentials), one Idempotency-Key per deliberate write attempt
 * (never retried on its own), 429 with Retry-After surfaced, revocation through
 * POST /v1/tokens/revoke with the holder's own session JWT.
 */

const API_BASE = JASPER_API_BASE;
const TOKEN_KEY = "whisper_jasper_connect_v2:";

/** Explicit capabilities offered by Whisper; nothing is granted implicitly. */
export const JASPER_SCOPE_OPTIONS = [
  ["read:profile", "Profile and achievements"], ["read:workouts", "Training and saved programs"],
  ["read:nutrition", "Meals, recipes and hydration"], ["read:sleep", "Sleep records"],
  ["read:vitals", "Heart rate, steps and readiness"], ["read:body", "Body measurements and weight"],
  ["read:bioage", "Exploratory biological-age estimates"], ["read:goals", "Goals"],
  ["read:charts", "Shared cards"], ["read:preferences", "App preferences"],
  ["read:photos", "Progress-photo details (not images)"], ["read:events", "Updates to shared records"],
  ["read:blood", "Blood markers (sensitive)"],
  ["write:nutrition", "Save meals, recipes and grocery checks"], ["write:workouts", "Save workouts and programs"],
  ["write:goals", "Update goals"], ["write:charts", "Send cards to Jasper"],
] as const;

interface StoredConnection { ownerId: string; token: string; tokenId: string; scopes: string[] }
let connectFlight: Promise<string | null> | null = null;
onJasperInvalidated(() => { connectFlight = null; });

function storedConnection(owner: string): StoredConnection | null {
  try {
    const value = JSON.parse(localStorage.getItem(TOKEN_KEY + owner) ?? "null") as StoredConnection | null;
    return value?.ownerId === owner && value.token?.startsWith("jc_") && typeof value.tokenId === "string" && Array.isArray(value.scopes) ? value : null;
  } catch { return null; }
}

function clearConnection(owner: string): void {
  localStorage.removeItem(TOKEN_KEY + owner);
  localStorage.removeItem("whisper_jasper_connect_token_web_v1");
  invalidateJasperSession();
}

type Json = Record<string, unknown>;

function asRecord(v: unknown): Json {
  return typeof v === "object" && v !== null ? (v as Json) : {};
}

function str(v: unknown): string | null {
  return typeof v === "string" && v.length > 0 ? v : null;
}

function num(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

/** Passive token lookup never mints or re-authorizes after revocation. */
export async function jasperToken(): Promise<string | null> {
  const context = await jasperSession();
  assertJasperSession(context);
  return storedConnection(context.ownerId)?.token ?? null;
}

/** Call only after the user reviews the requested permissions. */
export async function jasperConnect(scopes: string[]): Promise<string | null> {
  if (connectFlight) return connectFlight;
  const selected = [...new Set(scopes)].filter((scope) => JASPER_SCOPE_OPTIONS.some(([known]) => known === scope));
  if (selected.length === 0) throw new JasperApiError(400, "Choose at least one permission.");
  const task = (async (): Promise<string | null> => {
    const context = await jasperSession();
    const body = await request("/v1/authorize", { method: "POST", body: { app_name: "Whisper Web", scopes: selected }, bearer: context.jwt, context });
    assertJasperSession(context);
    const token = str(body.token);
    const tokenId = str(body.id);
    if (!token?.startsWith("jc_") || !tokenId || !Array.isArray(body.scopes) || !body.scopes.every((scope) => typeof scope === "string" && selected.includes(scope))) {
      throw new JasperApiError(502, "Jasper returned permissions we couldn't verify. Review your connection in Jasper before trying again.");
    }
    const value: StoredConnection = { ownerId: context.ownerId, token, tokenId, scopes: body.scopes as string[] };
    localStorage.setItem(TOKEN_KEY + context.ownerId, JSON.stringify(value));
    invalidateJasperSession();
    localStorage.removeItem("whisper_jasper_connect_token_web_v1");
    return token;
  })();
  connectFlight = task;
  try { return await task; } finally { if (connectFlight === task) connectFlight = null; }
}

/** Revokes this web connection through POST /v1/tokens/revoke with the user's
 * own session JWT (guide §02). A host without the route falls back to the
 * shared project's `jasper_connect_revoke` RPC. Failure stays retryable; local
 * deletion is never reported as revocation. */
export async function jasperDisconnect(): Promise<void> {
  const context = await jasperSession();
  const value = storedConnection(context.ownerId);
  if (!value) { clearConnection(context.ownerId); return; }
  const unconfirmed = new JasperApiError(503, "Couldn't confirm disconnection. Try again, or revoke Whisper Web in Jasper → Settings → Jasper Connect.");
  let confirmed = false;
  try {
    const body = await request("/v1/tokens/revoke", { method: "POST", body: { token_id: value.tokenId }, bearer: context.jwt, context });
    confirmed = body.ok === true || body.revoked === true;
  } catch (e) {
    assertJasperSession(context);
    if (!(e instanceof JasperApiError) || (e.status !== 404 && e.status !== 405)) throw unconfirmed;
    const { error, data } = await supabase.rpc("jasper_connect_revoke", { p_id: value.tokenId });
    assertJasperSession(context);
    confirmed = !error && asRecord(data).ok === true;
  }
  assertJasperSession(context);
  if (!confirmed) throw unconfirmed;
  clearConnection(context.ownerId);
}

/** One sanitized Jasper failure (guide §08): the stable code, the X-Request-Id
 * to quote in reports and the few structured hints the contract defines.
 * Response bodies and credentials never travel into messages or logs. The
 * message keeps the code as its first word so existing mappers still match. */
export interface JasperFailureDetails {
  code?: string | null;
  requestId?: string | null;
  retryAfter?: number | null;
}

export class JasperApiError extends Error {
  readonly status: number;
  /** Stable contract code (`missing_scope`, `invalid_token`, …) when Jasper sent one. */
  readonly code: string | null;
  /** X-Request-Id — the only thing worth quoting in a report. */
  readonly requestId: string | null;
  /** Seconds from Retry-After on 429; never used to retry a mutation automatically. */
  readonly retryAfter: number | null;
  constructor(status: number, message: string, details: JasperFailureDetails = {}) {
    super(message);
    this.status = status;
    this.code = details.code ?? null;
    this.requestId = details.requestId ?? null;
    this.retryAfter = details.retryAfter ?? null;
    this.name = "JasperApiError";
  }
  /** Any 401 (invalid_token, coach_grant_revoked) or 409 connection_changed:
   * the credential is dead — wipe it and never retry under it. */
  get isRevocation(): boolean {
    return this.status === 401 || this.code === "invalid_token" || this.code === "coach_grant_revoked" || this.code === "connection_changed";
  }
}

/** Builds the sanitized error for a non-2xx (or ok:false) Jasper answer. */
export function jasperFailure(status: number, headers: Headers, body: Json): JasperApiError {
  const details = asRecord(body.error_details);
  const code = str(details.code) ?? str(body.error) ?? `http_${status}`;
  const requestId = headers.get("X-Request-Id") ?? str(body.request_id);
  const retryHeader = headers.get("Retry-After");
  const retryAfter = retryHeader && /^\d+$/.test(retryHeader.trim()) ? Number(retryHeader.trim()) : null;
  const need = str(body.need);
  const hint = str(body.hint);
  const reference = requestId ? ` · request ${requestId.slice(0, 8)}` : "";
  let message: string;
  if (status === 429) {
    message = `rate_limited — Jasper is busy right now.${retryAfter !== null ? ` Try again in ${retryAfter}s.` : " Try again in a minute."}${reference}`;
  } else {
    switch (code) {
      case "missing_scope": message = `missing_scope — this wasn't shared${need ? ` (need ${need})` : ""}.${reference}`; break;
      case "coach_grant_read_only": message = `coach_grant_read_only — this coaching grant is view-only; reads keep working.${reference}`; break;
      case "native_review_required": message = JASPER_NATIVE_REVIEW_MESSAGE; break;
      case "idempotency_conflict": message = `idempotency_conflict — the same change was already sent with a different payload; start a fresh attempt.${reference}`; break;
      case "idempotency_in_progress": message = `idempotency_in_progress — that change is still being applied; wait before retrying.${reference}`; break;
      case "idempotency_expired": message = `idempotency_expired — this retry is older than 24 hours; start a fresh attempt.${reference}`; break;
      case "unknown_resource": message = `unknown_resource — this Jasper deployment doesn't offer that resource.${reference}`; break;
      case "webhook_egress_unavailable": message = `webhook_egress_unavailable — Jasper has paused webhook push; Whisper reads the change feed instead.${reference}`; break;
      default: message = hint ? `${code} — ${hint}${reference}` : `${code} (${status})${reference}`;
    }
  }
  return new JasperApiError(status, message, { code, requestId, retryAfter });
}

/** Request headers for one Jasper call. The Idempotency-Key travels only on
 * mutations to routes that honor it; every call carries a client request id. */
export function jasperHeaders(options: { bearer: string; method: string; path: string; hasBody: boolean; idempotencyKey?: string }): Record<string, string> {
  const headers: Record<string, string> = { Authorization: `Bearer ${options.bearer}`, "X-Client-Request-Id": crypto.randomUUID() };
  if (options.hasBody) headers["Content-Type"] = "application/json";
  if (options.idempotencyKey && options.method !== "GET" && jasperSupportsIdempotency(options.path)) headers["Idempotency-Key"] = options.idempotencyKey;
  return headers;
}

async function request(
  path: string,
  options: { method?: string; body?: Json; bearer: string; context?: JasperSession; idempotencyKey?: string }
): Promise<Json> {
  if (!/^\/v1\/[a-z_]+(?:\/[a-zA-Z0-9_-]+)?(?:\?[^#]*)?$/.test(path)) throw new JasperApiError(400, "Invalid Jasper resource.");
  if (path.split("?")[0] === "/v1/diet_plans/generate") throw new JasperApiError(409, JASPER_NATIVE_REVIEW_MESSAGE);
  if (options.context) assertJasperSession(options.context);
  const method = options.method ?? "GET";
  const res = await fetch(`${API_BASE}${path}`, {
    method,
    signal: options.context ? AbortSignal.any([options.context.signal, AbortSignal.timeout(30000)]) : AbortSignal.timeout(30000),
    cache: "no-store",
    redirect: "error",
    headers: jasperHeaders({ bearer: options.bearer, method, path, hasBody: options.body !== undefined, idempotencyKey: options.idempotencyKey }),
    body: options.body ? JSON.stringify(options.body) : undefined,
  });
  const body = asRecord(await res.json().catch(() => ({})));
  if (options.context) assertJasperSession(options.context);
  noteJasperContract(res.headers);
  if (!res.ok || body.ok === false) throw jasperFailure(res.status, res.headers, body);
  return body;
}

/** Account-bound REST call. Revocation and scope denial never trigger minting
 * or write retries; a mutation carries the caller's Idempotency-Key once. */
export async function tokenRequest(
  path: string,
  options: { method?: string; body?: Json; idempotencyKey?: string } = {}
): Promise<Json> {
  const context = await jasperSession();
  const stored = storedConnection(context.ownerId);
  if (!stored) throw new JasperApiError(401, "Connect Jasper in Settings and choose what to share.");
  try {
    const result = await request(path, { ...options, bearer: stored.token, context });
    if (storedConnection(context.ownerId)?.token !== stored.token) throw new JasperApiError(409, "Your Jasper connection changed. Refresh before continuing.");
    return result;
  } catch (e) {
    assertJasperSession(context);
    if (e instanceof JasperApiError && e.isRevocation) {
      // Guide §09: honor the 401 even if local cleanup fails — and say so.
      let cleanupFailed = false;
      try { clearConnection(context.ownerId); } catch { cleanupFailed = true; }
      throw new JasperApiError(401, cleanupFailed
        ? "Jasper access ended, but the old connection couldn't be cleared from this browser. Sign out and back in, then reconnect in Settings."
        : "Jasper access ended. Review permissions and reconnect in Settings.", { code: e.code, requestId: e.requestId });
    }
    throw e;
  }
}

// MARK: - Connection state (Settings → Sync with Jasper)

export interface JasperMeState {
  username: string | null;
  displayName: string | null;
  linked: boolean | null;
  tokenPrefix: string | null;
  scopes: string[];
  ownerId: string;
}

/** GET /v1/me through the Connect token — proves the pipe and resolves the
 * Linked / Same account / Not linked pill exactly like iOS. */
export async function jasperMe(): Promise<JasperMeState> {
  const context = await jasperSession();
  const body = await tokenRequest("/v1/me");
  assertJasperSession(context);
  const user = asRecord(body.user ?? body.data ?? body);
  const stored = storedConnection(context.ownerId);
  const token = stored?.token;
  return {
    username: str(user.username),
    displayName: str(user.display_name) ?? str(user.displayName),
    linked: typeof user.linked === "boolean" ? user.linked : null,
    tokenPrefix: token ? token.slice(0, 11) : null,
    scopes: Array.isArray(body.scopes) ? body.scopes.filter((scope): scope is string => typeof scope === "string") : stored?.scopes ?? [],
    ownerId: context.ownerId,
  };
}

/** GET /v1/experience (no auth) — confirms the host speaks the revision and
 * compatibility patch this build was written against (guide §01). Never blocks
 * reads: an older host is reported in the returned note, not refused. */
export async function jasperCheckContract(): Promise<string | null> {
  try {
    const res = await fetch(`${API_BASE}/v1/experience`, { cache: "no-store", signal: AbortSignal.timeout(15000) });
    noteJasperContract(res.headers);
    const body = asRecord(await res.json().catch(() => ({})));
    if (res.ok) noteJasperCompatibilityPatch(str(body.compatibility_patch));
  } catch {
    // Offline or blocked — nothing to report; data reads carry their own version header.
  }
  return jasperContractNote();
}

export function jasperHasLocalToken(): boolean {
  const owner = jasperCurrentOwner();
  return owner !== null && storedConnection(owner) !== null;
}

/** Local forgetting is separate from server revocation. */
export function jasperDisconnectLocal(): void {
  const owner = jasperCurrentOwner();
  if (owner) clearConnection(owner);
}

// MARK: - Generic resource reads/writes

export async function jasperRead(resource: string, limit = 100, sinceISO?: string): Promise<Json[]> {
  const query = new URLSearchParams({ limit: String(Math.max(1, Math.min(200, Math.trunc(limit) || 100))) });
  if (sinceISO) query.set("since", sinceISO);
  const body = await tokenRequest(`/v1/${resource}?${query.toString()}`);
  return Array.isArray(body.data) ? (body.data as Json[]) : [];
}

/** One deliberate write. `client_id` in the payload is record identity
 * (upsert); the Idempotency-Key is the retry protection — a caller letting the
 * user retry the SAME change passes the key it used the first time. */
export async function jasperPost(resource: string, payload: Json, idempotencyKey: string = crypto.randomUUID()): Promise<Json> {
  return tokenRequest(`/v1/${resource}`, { method: "POST", body: payload, idempotencyKey });
}

export async function jasperDeleteRow(resource: string, id: string, idempotencyKey: string = crypto.randomUUID()): Promise<void> {
  await tokenRequest(`/v1/${resource}?id=${encodeURIComponent(id)}`, { method: "DELETE", idempotencyKey });
}

/** GET /v1/events/page — the change-feed journal (guide §06). Send the returned
 * `next_cursor` AND `context` back together on the next call. */
export async function jasperEventsPage(cursor: string, context: string | null, limit = 200): Promise<Json> {
  const query = new URLSearchParams({ cursor, limit: String(Math.max(1, Math.min(200, limit))) });
  if (context) query.set("context", context);
  return tokenRequest(`/v1/events/page?${query.toString()}`);
}

/** GET /v1/history/{resource} — UUID-keyset pages for reconciliation, or one
 * exact row by `id`. Continue with the returned cursor and context. */
export async function jasperHistory(resource: string, options: { cursor?: string; context?: string; id?: string; limit?: number } = {}): Promise<Json> {
  const query = new URLSearchParams({ limit: String(Math.max(1, Math.min(200, options.limit ?? 100))) });
  if (options.cursor) query.set("cursor", options.cursor);
  if (options.context) query.set("context", options.context);
  if (options.id) query.set("id", options.id);
  return tokenRequest(`/v1/history/${resource}?${query.toString()}`);
}

// MARK: - Shared grocery checklist (same rows as Jasper's in-app list)

export interface JasperGroceryItem {
  id: string;
  name: string;
  quantity: string | null;
  usedInMeals: string | null;
  checked: boolean;
}

export interface JasperGroceryCategory {
  name: string;
  items: JasperGroceryItem[];
}

export interface JasperSharedGrocery {
  planId: string | null;
  planName: string | null;
  categories: JasperGroceryCategory[];
}

export async function fetchGroceryList(planId?: string): Promise<JasperSharedGrocery> {
  const suffix = planId ? `?plan_id=${encodeURIComponent(planId)}` : "";
  const body = await tokenRequest(`/v1/grocery_list${suffix}`);
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

export async function setGroceryChecks(
  planId: string | null,
  changes: { id: string; checked: boolean }[]
): Promise<void> {
  const body: Json = { items: changes };
  if (planId) body.plan_id = planId;
  await tokenRequest("/v1/grocery_list", { method: "POST", body, idempotencyKey: crypto.randomUUID() });
}

// MARK: - Recipes (ONE shared library with Jasper's Nutrition → Recipes)

export interface JasperRecipeIngredient {
  name: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  servingUnit: string;
  numberOfServings: number;
}

export interface JasperRecipeRow {
  id: string;
  name: string;
  emoji: string;
  servings: number;
  note: string;
  prepTime: string | null;
  cookTime: string | null;
  steps: string[];
  ingredients: JasperRecipeIngredient[];
}

/** Per-serving macros are ALWAYS derived: ingredient totals ÷ servings. */
export function recipePerServing(recipe: JasperRecipeRow): {
  calories: number; protein: number; carbs: number; fat: number;
} {
  const servings = Math.max(1, recipe.servings);
  const total = recipe.ingredients.reduce(
    (acc, ing) => {
      const n = Math.max(0, ing.numberOfServings);
      return {
        calories: acc.calories + ing.calories * n,
        protein: acc.protein + ing.protein * n,
        carbs: acc.carbs + ing.carbs * n,
        fat: acc.fat + ing.fat * n,
      };
    },
    { calories: 0, protein: 0, carbs: 0, fat: 0 }
  );
  return {
    calories: Math.round(total.calories / servings),
    protein: Math.round(total.protein / servings),
    carbs: Math.round(total.carbs / servings),
    fat: Math.round(total.fat / servings),
  };
}

function parseRecipe(row: Json): JasperRecipeRow | null {
  const payload = asRecord(row.payload);
  const name = str(row.name) ?? str(payload.name);
  if (!name) return null;
  const rawIngredients = Array.isArray(row.ingredients)
    ? (row.ingredients as unknown[])
    : Array.isArray(payload.ingredients)
      ? (payload.ingredients as unknown[])
      : [];
  const ingredients = rawIngredients.map((raw) => {
    const ing = asRecord(raw);
    return {
      name: str(ing.name) ?? "Ingredient",
      calories: num(ing.calories) ?? 0,
      protein: num(ing.protein) ?? 0,
      carbs: num(ing.carbs) ?? 0,
      fat: num(ing.fat) ?? 0,
      servingUnit: str(ing.servingUnit) ?? "serving",
      numberOfServings: num(ing.numberOfServings) ?? 1,
    };
  });
  const steps = (Array.isArray(row.steps) ? row.steps : Array.isArray(payload.steps) ? payload.steps : [])
    .filter((s): s is string => typeof s === "string");
  return {
    id: str(row.id) ?? str(row.client_id) ?? crypto.randomUUID(),
    name,
    emoji: str(row.emoji) ?? str(payload.emoji) ?? "",
    servings: num(row.servings) ?? num(payload.servings) ?? 1,
    note: str(row.note) ?? str(payload.note) ?? "",
    prepTime: str(row.prep_time) ?? null,
    cookTime: str(row.cook_time) ?? null,
    steps,
    ingredients,
  };
}

export async function fetchRecipes(): Promise<JasperRecipeRow[]> {
  const rows = await jasperRead("recipes", 100);
  return rows.map(parseRecipe).filter((r): r is JasperRecipeRow => r !== null);
}

/** POST /v1/recipes — write_fields exactly; the worker builds the decode-safe
 * app payload server-side. Upserts by client_id. */
export async function saveRecipe(input: {
  id?: string;
  name: string;
  emoji?: string;
  servings: number;
  note?: string;
  steps?: string[];
  prepTime?: string;
  cookTime?: string;
  ingredients: JasperRecipeIngredient[];
}): Promise<void> {
  const body: Json = {
    client_id: input.id ?? crypto.randomUUID().toLowerCase(),
    name: input.name.trim(),
    servings: Math.max(1, input.servings),
    ingredients: input.ingredients.map((ing) => ({
      name: ing.name,
      calories: ing.calories,
      protein: ing.protein,
      carbs: ing.carbs,
      fat: ing.fat,
      servingUnit: ing.servingUnit,
      numberOfServings: ing.numberOfServings,
    })),
  };
  if (input.emoji?.trim()) body.emoji = input.emoji.trim();
  if (input.note?.trim()) body.note = input.note.trim();
  if (input.prepTime?.trim()) body.prep_time = input.prepTime.trim();
  if (input.cookTime?.trim()) body.cook_time = input.cookTime.trim();
  const steps = (input.steps ?? []).map((s) => s.trim()).filter((s) => s.length > 0);
  if (steps.length > 0) body.steps = steps;
  await jasperPost("recipes", body);
}

export async function deleteRecipe(id: string): Promise<void> {
  await jasperDeleteRow("recipes", id);
}

// MARK: - Diet-plan generation (Jasper's OWN engine over the API)

export const JASPER_DIET_GOALS = [
  "Aggressive Fat Loss", "Fat Loss", "Maintain Weight", "Lean Bulk", "Muscle Gain",
] as const;

export const JASPER_DIET_PREFERENCES = [
  "No Preference", "High Protein", "Keto", "Vegetarian", "Vegan",
  "Pescatarian", "Mediterranean", "Paleo", "Gluten Free", "Dairy Free",
] as const;

export const JASPER_ACTIVITY_LEVELS = [
  "Sedentary", "Lightly Active", "Moderately Active", "Very Active", "Extremely Active",
] as const;

export interface JasperDietGenDay {
  dayName: string;
  mealCount: number;
  kcal: number;
}

export interface JasperDietGenResult {
  saved: boolean;
  planName: string;
  goal: string | null;
  targetCalories: number | null;
  days: JasperDietGenDay[];
  groceryCount: number;
  /** Ready POST /v1/diet_plans body — payload rides VERBATIM. */
  postBody: Json;
}

export async function generateDietPlan(input: {
  goal: string;
  preference: string;
  allergies: string[];
  mealsPerDay: number;
  targets?: { calories?: number; protein?: number; carbs?: number; fat?: number };
  profile?: { age: number; gender: string; weightLbs: number; heightInches: number; activityLevel: string };
  save: boolean;
}): Promise<JasperDietGenResult> {
  const body: Json = {
    goal: input.goal,
    dietary_preference: input.preference,
    meals_per_day: input.mealsPerDay,
    save: input.save,
  };
  if (input.allergies.length > 0) body.allergies = input.allergies;
  if (input.profile) {
    body.profile = {
      age: input.profile.age,
      gender: input.profile.gender,
      weight_lbs: input.profile.weightLbs,
      height_inches: input.profile.heightInches,
      activity_level: input.profile.activityLevel,
    };
  } else if (input.targets) {
    if (input.targets.calories) body.target_calories = input.targets.calories;
    if (input.targets.protein) body.target_protein_g = input.targets.protein;
    if (input.targets.carbs) body.target_carbs_g = input.targets.carbs;
    if (input.targets.fat) body.target_fat_g = input.targets.fat;
  }
  const answer = await tokenRequest("/v1/diet_plans/generate", { method: "POST", body });
  const plan = asRecord(answer.plan);
  const payload = asRecord(plan.payload);
  const days = (Array.isArray(payload.days) ? payload.days : []).map((raw) => {
    const day = asRecord(raw);
    const meals = Array.isArray(day.meals) ? (day.meals as unknown[]) : [];
    const kcal = meals.reduce<number>((acc, m) => acc + (num(asRecord(m).calories) ?? 0), 0);
    return { dayName: str(day.dayName) ?? "Day", mealCount: meals.length, kcal: Math.round(kcal) };
  });
  const groceryCount = (Array.isArray(asRecord(payload.groceryList).categories)
    ? (asRecord(payload.groceryList).categories as unknown[])
    : []
  ).reduce<number>((acc, c) => acc + (Array.isArray(asRecord(c).items) ? (asRecord(c).items as unknown[]).length : 0), 0);
  const postBody: Json = { payload };
  const clientID = str(plan.client_id) ?? str(payload.id);
  if (clientID) postBody.client_id = clientID;
  for (const key of ["name", "goal", "dietary_preference", "target_calories", "target_protein_g", "target_carbs_g", "target_fat_g"]) {
    if (plan[key] !== undefined && plan[key] !== null) postBody[key] = plan[key];
  }
  return {
    saved: answer.saved === true || plan.saved === true,
    planName: str(plan.name) ?? str(payload.name) ?? "Diet plan",
    goal: str(plan.goal) ?? str(payload.goal),
    targetCalories: num(plan.target_calories) ?? num(payload.targetCalories),
    days,
    groceryCount,
    postBody,
  };
}

// MARK: - Own plans (the Programs studio reads THE API)

export interface JasperOwnPlan {
  id: string;
  name: string;
  goal: string;
  detail: string;
  isProgram: boolean;
  topLevel: Json;
  payload: Json;
}

export function parseOwnPlan(row: Json, isProgram: boolean): JasperOwnPlan | null {
  const payload = asRecord(row.payload);
  const name = str(row.name) ?? str(payload.title) ?? str(payload.name);
  if (!name) return null;
  const goal = str(row.goal) ?? str(payload.goal) ?? "";
  const rawDays = isProgram ? payload.workoutDays ?? payload.days : payload.days;
  const days = Array.isArray(rawDays) ? rawDays : [];
  const topLevel: Json = {};
  const parts: string[] = [];
  if (goal) topLevel.goal = goal;
  if (isProgram) {
    const weeks = num(row.weeks) ?? num(payload.weeks);
    if (weeks) { topLevel.weeks = weeks; parts.push(`${weeks} wks`); }
    const daysPerWeek = num(row.days_per_week) ?? num(payload.daysPerWeek);
    if (daysPerWeek !== null) topLevel.days_per_week = daysPerWeek;
    parts.push(`${days.length} day${days.length === 1 ? "" : "s"}`);
    const lifts = days.reduce<number>((acc, d) => acc + (Array.isArray(asRecord(d).exercises) ? (asRecord(d).exercises as unknown[]).length : 0), 0);
    if (lifts > 0) parts.push(`${lifts} lifts`);
  } else {
    const kcal = num(row.target_calories) ?? num(payload.targetCalories);
    if (kcal) { topLevel.target_calories = kcal; parts.push(`${kcal} kcal`); }
    const pref = str(row.dietary_preference) ?? str(payload.dietaryPreference);
    if (pref) { topLevel.dietary_preference = pref; parts.push(pref); }
    for (const key of ["target_protein_g", "target_carbs_g", "target_fat_g"]) {
      const v = num(row[key]);
      if (v) topLevel[key] = v;
    }
    parts.push(`${days.length} day${days.length === 1 ? "" : "s"}`);
  }
  return {
    id: str(row.id) ?? str(row.client_id) ?? str(payload.id) ?? crypto.randomUUID(),
    name,
    goal,
    detail: parts.join(" · "),
    isProgram,
    topLevel,
    payload,
  };
}

export async function fetchOwnPlans(): Promise<{ programs: JasperOwnPlan[]; dietPlans: JasperOwnPlan[] }> {
  const context = await jasperSession();
  const [programRows, dietRows] = await Promise.all([
    jasperRead("programs", 50),
    jasperRead("diet_plans", 50),
  ]);
  assertJasperSession(context);
  return {
    programs: programRows.map((r) => parseOwnPlan(r, true)).filter((p): p is JasperOwnPlan => p !== null),
    dietPlans: dietRows.map((r) => parseOwnPlan(r, false)).filter((p): p is JasperOwnPlan => p !== null),
  };
}

// MARK: - Marketplace (public browse; publish/unpublish with the session JWT)

export interface JasperMarketTemplate {
  id: string;
  kind: string;
  title: string;
  summary: string;
  goal: string;
  coachName: string | null;
  priceUSD: number;
}

export async function marketplaceBrowse(kind?: string, query?: string): Promise<JasperMarketTemplate[]> {
  const params = new URLSearchParams();
  if (kind) params.set("kind", kind);
  if (query) params.set("q", query);
  const qs = params.toString();
  const res = await fetch(`${API_BASE}/v1/marketplace${qs ? `?${qs}` : ""}`, { signal: AbortSignal.timeout(30000) });
  const body = asRecord(await res.json().catch(() => ({})));
  if (!res.ok || body.ok === false) throw new JasperApiError(res.status, "Couldn't load Jasper's marketplace. Try again.");
  const list = Array.isArray(body.templates) ? body.templates : Array.isArray(body.data) ? body.data : [];
  return (list as unknown[]).map((raw) => {
    const t = asRecord(raw);
    return {
      id: str(t.id) ?? "",
      kind: str(t.kind) ?? "program",
      title: str(t.title) ?? "Template",
      summary: str(t.summary) ?? "",
      goal: str(t.goal) ?? "",
      coachName: str(t.coach_name) ?? str(t.coach) ?? null,
      priceUSD: num(t.price_usd) ?? 0,
    };
  }).filter((t) => t.id.length > 0);
}

export async function marketplaceImport(templateId: string): Promise<void> {
  await tokenRequest("/v1/marketplace/import", { method: "POST", body: { template_id: templateId } });
}

export async function marketplacePublish(input: {
  kind: string;
  title: string;
  summary: string;
  goal: string;
  topLevel: Json;
  payload: Json;
}): Promise<void> {
  const context = await jasperSession();
  await request("/v1/marketplace", {
    method: "POST",
    bearer: context.jwt,
    context,
    body: {
      kind: input.kind,
      title: input.title,
      summary: input.summary,
      goal: input.goal,
      price_usd: 0,
      top_level: input.topLevel,
      payload: input.payload,
    },
  });
}

// MARK: - Water (tap-to-log cups, Jasper's own water_cup look)

export interface JasperWaterRow {
  id: string;
  ml: number;
}

export async function fetchWaterToday(): Promise<JasperWaterRow[]> {
  const start = new Date();
  start.setHours(0, 0, 0, 0);
  const rows = await jasperRead("water", 200, start.toISOString());
  return rows
    .map((row) => {
      const ml = num(row.amount_ml) ?? 0;
      const id = str(row.id);
      return id && ml > 0 ? { id, ml } : null;
    })
    .filter((r): r is JasperWaterRow => r !== null);
}

export async function logWaterCup(ml = 250): Promise<void> {
  await jasperPost("water", { amount_ml: ml, logged_at: new Date().toISOString() });
}
