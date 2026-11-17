import { beforeEach, describe, expect, it, vi } from "vitest";

type Session = { user: { id: string }; access_token: string };
const auth = vi.hoisted(() => ({
  session: null as Session | null,
  listener: null as ((event: string, session: Session | null) => void) | null,
  getSession: vi.fn(),
  rpc: vi.fn(),
}));
vi.mock("@/lib/supabase", () => ({ supabase: {
  auth: {
    getSession: auth.getSession,
    onAuthStateChange: (listener: (event: string, session: Session | null) => void) => {
      auth.listener = listener;
      return { data: { subscription: { unsubscribe: vi.fn() } } };
    },
  },
  rpc: auth.rpc,
} }));

const A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa";
const B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb";
const clientID = "cccccccc-cccc-cccc-cccc-cccccccccccc";
const key = (owner: string): string => `whisper_jasper_connect_v2:${owner}`;
function login(owner: string | null): void {
  auth.session = owner ? { user: { id: owner }, access_token: `jwt-${owner}` } : null;
  auth.listener?.("SIGNED_IN", auth.session);
}
function seed(owner = A): void {
  localStorage.setItem(key(owner), JSON.stringify({ ownerId: owner, token: `jc_${owner}`, tokenId: "token-id", scopes: ["read:profile", "read:workouts", "read:nutrition"] }));
}
function answer(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: { "Content-Type": "application/json" } });
}
function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}
let api: typeof import("./jasperConnect");
let sessionAPI: typeof import("./jasperSession");
let fetchMock: ReturnType<typeof vi.fn>;

beforeEach(async () => {
  vi.resetModules();
  localStorage.clear();
  auth.listener = null;
  auth.session = null;
  auth.getSession.mockReset().mockImplementation(async () => ({ data: { session: auth.session }, error: null }));
  auth.rpc.mockReset().mockResolvedValue({ data: { ok: true }, error: null });
  fetchMock = vi.fn();
  vi.stubGlobal("fetch", fetchMock);
  api = await import("./jasperConnect");
  sessionAPI = await import("./jasperSession");
  login(A);
});

describe("Jasper explicit permission and owner boundaries", () => {
  it("ignores the old unowned token and never authorizes on passive reads", async () => {
    localStorage.setItem("whisper_jasper_connect_token_web_v1", "jc_old");
    expect(await api.jasperToken()).toBeNull();
    await expect(api.jasperRead("workouts")).rejects.toThrow("Connect Jasper");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(auth.rpc).not.toHaveBeenCalled();
  });

  it("uses only explicit scopes, coalesces clicks, and stores actual granted scopes", async () => {
    const pending = deferred<Response>();
    fetchMock.mockReturnValue(pending.promise);
    const first = api.jasperConnect(["read:workouts", "read:nutrition"]);
    const second = api.jasperConnect(["read:workouts", "read:nutrition"]);
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    const [url, init] = fetchMock.mock.calls[0] as [string, RequestInit];
    expect(url).toBe(`${sessionAPI.JASPER_API_BASE}/v1/authorize`);
    expect(JSON.parse(init.body as string)).toEqual({ app_name: "Whisper Web", scopes: ["read:workouts", "read:nutrition"] });
    pending.resolve(answer({ ok: true, token: "jc_new", id: "new-id", scopes: ["read:workouts"] }));
    expect(await first).toBe("jc_new");
    expect(await second).toBe("jc_new");
    expect(JSON.parse(localStorage.getItem(key(A)) ?? "{}").scopes).toEqual(["read:workouts"]);
  });

  it("rejects empty or unexpectedly broad authorization", async () => {
    await expect(api.jasperConnect([])).rejects.toThrow("Choose at least one");
    fetchMock.mockResolvedValue(answer({ ok: true, token: "jc_new", id: "new-id", scopes: ["all"] }));
    await expect(api.jasperConnect(["read:profile"])).rejects.toThrow("permissions we couldn't verify");
    expect(localStorage.getItem(key(A))).toBeNull();
  });

  it("never sends another owner's token after switching accounts", async () => {
    seed();
    expect(await api.jasperToken()).toBe(`jc_${A}`);
    login(B);
    expect(await api.jasperToken()).toBeNull();
    await expect(api.jasperRead("meals")).rejects.toThrow("Connect Jasper");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("rejects late authorization after switching away and back", async () => {
    const pending = deferred<Response>();
    fetchMock.mockReturnValue(pending.promise);
    const operation = api.jasperConnect(["read:profile"]);
    const rejection = expect(operation).rejects.toThrow(/changed/);
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    login(B); login(A);
    pending.resolve(answer({ ok: true, token: "jc_late", id: "late", scopes: ["read:profile"] }));
    await rejection;
    expect(localStorage.getItem(key(A))).toBeNull();
    expect(localStorage.getItem(key(B))).toBeNull();
  });

  it("rejects an auth read spanning A → B → A, even with the same returned ID", async () => {
    const pending = deferred<{ data: { session: Session | null }; error: null }>();
    const old = auth.session;
    auth.getSession.mockReturnValueOnce(pending.promise);
    const operation = sessionAPI.jasperSession();
    const rejection = expect(operation).rejects.toThrow(/changed/);
    login(B); login(A);
    pending.resolve({ data: { session: old }, error: null });
    await rejection;
  });

  it("discards a late resource response and aborts its request after sign-out", async () => {
    seed();
    const pending = deferred<Response>();
    fetchMock.mockReturnValue(pending.promise);
    const read = api.jasperRead("workouts");
    const rejection = expect(read).rejects.toThrow(/changed/);
    await vi.waitFor(() => expect(fetchMock).toHaveBeenCalledTimes(1));
    const init = fetchMock.mock.calls[0][1] as RequestInit;
    login(null);
    expect(init.signal?.aborted).toBe(true);
    pending.resolve(answer({ ok: true, data: [{ private: "old account" }] }));
    await rejection;
  });

  it.each([401, 409])("clears revoked/changed access (%s) without replaying writes or reminting", async (status) => {
    seed();
    fetchMock.mockResolvedValue(answer({ error: status === 401 ? "revoked" : "connection_changed" }, status));
    await expect(api.jasperPost("meals", { name: "Lunch" })).rejects.toThrow("access ended");
    await expect(api.jasperRead("workouts")).rejects.toThrow("Connect Jasper");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(auth.rpc).not.toHaveBeenCalled();
    expect(localStorage.getItem(key(A))).toBeNull();
  });

  it("keeps a scope denial distinct from revocation and does not escalate", async () => {
    seed();
    fetchMock.mockResolvedValue(answer({ error: "missing_scope" }, 403));
    await expect(api.jasperRead("blood_panels")).rejects.toThrow("missing_scope");
    expect(await api.jasperToken()).toBe(`jc_${A}`);
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(auth.rpc).not.toHaveBeenCalled();
  });

  it("doesn't send requests to the paused meal generator", async () => {
    seed();
    await expect(api.tokenRequest("/v1/diet_plans/generate", { method: "POST", body: {} })).rejects.toThrow("paused");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("confirms remote revocation through /v1/tokens/revoke before forgetting credentials and preserves a failed attempt", async () => {
    seed();
    fetchMock.mockResolvedValueOnce(answer({ ok: false, error: "revoke_failed", error_details: { code: "revoke_failed", type: "server_error" } }, 500));
    await expect(api.jasperDisconnect()).rejects.toThrow("Couldn't confirm");
    expect(await api.jasperToken()).toBe(`jc_${A}`);
    fetchMock.mockResolvedValueOnce(answer({ ok: true, revoked: true }));
    await api.jasperDisconnect();
    const [url, init] = fetchMock.mock.calls[1] as [string, RequestInit];
    expect(url).toBe(`${sessionAPI.JASPER_API_BASE}/v1/tokens/revoke`);
    expect(JSON.parse(init.body as string)).toEqual({ token_id: "token-id" });
    expect(init.headers).toMatchObject({ Authorization: `Bearer jwt-${A}` });
    expect(init.headers).not.toHaveProperty("Idempotency-Key");
    expect(auth.rpc).not.toHaveBeenCalled();
    expect(await api.jasperToken()).toBeNull();
  });

  it("falls back to the shared revoke RPC only when the host lacks /v1/tokens/revoke", async () => {
    seed();
    fetchMock.mockResolvedValueOnce(answer({ ok: false, error: "unknown_resource" }, 404));
    await api.jasperDisconnect();
    expect(auth.rpc).toHaveBeenLastCalledWith("jasper_connect_revoke", { p_id: "token-id" });
    expect(await api.jasperToken()).toBeNull();
  });

  it("sends one Idempotency-Key per deliberate write and never on reads or excluded routes", async () => {
    seed();
    fetchMock.mockResolvedValue(answer({ ok: true, id: "row" }));
    await api.jasperPost("meals", { name: "Lunch" }, "attempt-1");
    const post = fetchMock.mock.calls[0][1] as RequestInit;
    expect(post.headers).toMatchObject({ "Idempotency-Key": "attempt-1", Authorization: `Bearer jc_${A}` });
    expect((post.headers as Record<string, string>)["X-Client-Request-Id"]).toBeTruthy();
    await api.jasperDeleteRow("meals", "row", "attempt-2");
    expect((fetchMock.mock.calls[1][1] as RequestInit).headers).toMatchObject({ "Idempotency-Key": "attempt-2" });
    await api.jasperRead("workouts");
    expect((fetchMock.mock.calls[2][1] as RequestInit).headers).not.toHaveProperty("Idempotency-Key");
    await api.tokenRequest("/v1/marketplace/import", { method: "POST", body: { template_id: "t" }, idempotencyKey: "attempt-3" });
    expect((fetchMock.mock.calls[3][1] as RequestInit).headers).not.toHaveProperty("Idempotency-Key");
  });

  it("surfaces the stable code and request id, never the body, and does not retry an idempotency conflict", async () => {
    seed();
    fetchMock.mockResolvedValue(new Response(
      JSON.stringify({ ok: false, error: "idempotency_conflict", request_id: "req-1234-5678", error_details: { code: "idempotency_conflict", type: "conflict" }, secret: "never shown" }),
      { status: 409, headers: { "Content-Type": "application/json", "X-Request-Id": "req-1234-5678" } },
    ));
    const failure = await api.jasperPost("meals", { name: "Lunch" }).catch((e: unknown) => e);
    expect(failure).toBeInstanceOf(api.JasperApiError);
    const error = failure as InstanceType<typeof api.JasperApiError>;
    expect(error.code).toBe("idempotency_conflict");
    expect(error.requestId).toBe("req-1234-5678");
    expect(error.message).toMatch(/^idempotency_conflict/);
    expect(error.message).toContain("req-1234");
    expect(error.message).not.toContain("never shown");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(await api.jasperToken()).toBe(`jc_${A}`);
  });

  it("backs off on 429 with Retry-After instead of retrying", async () => {
    seed();
    fetchMock.mockResolvedValue(new Response(
      JSON.stringify({ ok: false, error: "rate_limited", error_details: { code: "rate_limited", type: "rate_limit" } }),
      { status: 429, headers: { "Content-Type": "application/json", "Retry-After": "17" } },
    ));
    const failure = await api.jasperRead("workouts").catch((e: unknown) => e);
    const error = failure as InstanceType<typeof api.JasperApiError>;
    expect(error.retryAfter).toBe(17);
    expect(error.message).toContain("17s");
    expect(fetchMock).toHaveBeenCalledTimes(1);
    expect(await api.jasperToken()).toBe(`jc_${A}`);
  });

  it("reports an older host from the version header instead of refusing it", async () => {
    seed();
    fetchMock.mockResolvedValue(new Response(JSON.stringify({ ok: true, data: [] }), {
      status: 200, headers: { "Content-Type": "application/json", "X-Jasper-API-Version": "2026-08-17.1" },
    }));
    expect(await api.jasperRead("workouts")).toEqual([]);
    expect(sessionAPI.jasperContractNote()).toContain("2026-08-17.1");
    expect(sessionAPI.jasperContractNote()).toContain(sessionAPI.JASPER_API_REVISION);
  });

  it("keeps all structured plan payload metadata without turning total sessions into days/week", () => {
    const payload = {
      title: "Two weeks", programming: { version: 2, evidenceIDs: ["source"], limitations: ["Review first"] },
      trainingRevision: "revision", weeklyReviews: [{ week: 1 }], generationProfile: { goal: "Strength" },
      workoutDays: [{ weekNumber: 1, weekday: 2, dayName: "A", exercises: [] }, { weekNumber: 2, weekday: 2, dayName: "B", exercises: [] }],
    };
    const plan = api.parseOwnPlan({ id: "plan", payload }, true);
    expect(plan?.payload).toBe(payload);
    expect(plan?.topLevel.days_per_week).toBeUndefined();
    expect(plan?.name).toBe("Two weeks");
  });
});

describe("Jasper coach credentials", () => {
  it("rejects paused coach generation before minting any access", async () => {
    const coach = await import("./jasperCoachConnect");
    await expect(coach.coachGenerateDietPlan(clientID, { save: true })).rejects.toThrow("paused");
    expect(fetchMock).not.toHaveBeenCalled();
    expect(auth.rpc).not.toHaveBeenCalled();
  });

  it("single-flights initial authorization, then refuses to remint a revoked token", async () => {
    const coach = await import("./jasperCoachConnect");
    fetchMock.mockImplementation(async (url: string) => url.endsWith("/authorize")
      ? answer({ ok: true, token: "jc_coach", id: "coach-id", scopes: ["read:workouts"], user: {} })
      : answer({ ok: true, data: [] }));
    await Promise.all([coach.coachRead(clientID, "workouts"), coach.coachRead(clientID, "programs")]);
    expect(fetchMock.mock.calls.filter(([url]) => (url as string).endsWith("/authorize"))).toHaveLength(1);
    fetchMock.mockResolvedValue(answer({ error: "coach_grant_revoked" }, 401));
    await expect(coach.coachWrite(clientID, "programs", { name: "Reviewed" })).rejects.toThrow("access ended");
    fetchMock.mockClear();
    await expect(coach.coachRead(clientID, "workouts")).rejects.toThrow("access ended");
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("positions the change feed first, then reports fresh events sending next_cursor and context together", async () => {
    const coach = await import("./jasperCoachConnect");
    const journalContext = "a".repeat(64);
    fetchMock.mockImplementation(async (url: string) => {
      if (url.endsWith("/authorize")) return answer({ ok: true, token: "jc_coach", id: "coach-id", scopes: ["read:workouts", "read:events"], user: {} });
      if (url.includes("/v1/events/page")) {
        const cursor = new URL(url).searchParams.get("cursor");
        if (cursor === "0") return answer({ ok: true, events: [{ id: "e1", event: "workout.completed", occurred_at: "2026-09-15T08:00:00Z" }], next_cursor: "41", context: journalContext, has_more: false });
        return answer({ ok: true, events: [{ id: "e2", event: "meal.logged", occurred_at: "2026-09-15T09:00:00Z" }, { id: "e2", event: "meal.logged" }], next_cursor: "42", context: journalContext, has_more: false });
      }
      return answer({ ok: true, summary: { readiness_score: 70 }, sections: {} });
    });
    await coach.coachDashboard(clientID);
    expect(coach.coachRecentEvents(clientID)).toEqual([]);   // history is never replayed as live
    expect(coach.coachChangeFeedArmed(clientID)).toBe(true);
    expect(await coach.coachReconcileChangeFeed(clientID)).toBe("skipped");   // throttled behind the dashboard rail
    vi.useFakeTimers({ toFake: ["Date"] });
    try {
      vi.setSystemTime(new Date(Date.now() + 30000));
      expect(await coach.coachReconcileChangeFeed(clientID)).toBe("fresh");
    } finally {
      vi.useRealTimers();
    }
    const events = coach.coachRecentEvents(clientID);
    expect(events.map((event) => event.id)).toEqual(["e2"]);   // at-least-once → deduped by id
    expect(events[0].title).toBe("Meal logged");
    const pages = fetchMock.mock.calls.map(([url]) => url as string).filter((url) => url.includes("/v1/events/page"));
    expect(pages).toHaveLength(2);
    const second = new URL(pages[1]).searchParams;
    expect(second.get("cursor")).toBe("41");
    expect(second.get("context")).toBe(journalContext);
    expect(fetchMock.mock.calls.filter(([url]) => (url as string).includes("/v1/webhooks"))).toHaveLength(0);
  });

  it("doesn't reuse client metadata or tokens for another coach", async () => {
    const coach = await import("./jasperCoachConnect");
    fetchMock.mockImplementation(async (url: string) => url.endsWith("/authorize")
      ? answer({ ok: true, token: "jc_coach_A", scopes: ["read:workouts"], user: {} })
      : answer({ ok: true, data: [] }));
    await coach.coachRead(clientID, "workouts");
    expect(coach.coachAccessMeta(clientID)).not.toBeNull();
    login(B);
    expect(coach.coachAccessMeta(clientID)).toBeNull();
    fetchMock.mockReset().mockResolvedValue(answer({ error: "coach_grant_required" }, 403));
    await expect(coach.coachRead(clientID, "workouts")).rejects.toThrow("coach_grant_required");
    expect((fetchMock.mock.calls[0][1] as RequestInit).headers).toMatchObject({ Authorization: `Bearer jwt-${B}` });
    expect(fetchMock).toHaveBeenCalledTimes(1);
  });
});
