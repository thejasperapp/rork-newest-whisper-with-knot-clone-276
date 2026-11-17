// @vitest-environment node
import { afterEach, describe, expect, it, vi } from "vitest";
vi.mock("cloudflare:workers", () => ({ DurableObject: class {} }));
import worker from "../../functions/index";

interface SentEmail { html: string; attachments?: { content: string }[] }
afterEach(() => vi.unstubAllGlobals());

describe("ordinary invitation emails", () => {
  it.each(["ABCDEF12-ABCD-4ABC-8ABC-ABCDEF123456", "wsp-Ab12-Cd34"])("uses the exact %s in native and calendar-grade invitations", async (identity) => {
    const emails: SentEmail[] = [];
    const fetcher = vi.fn(async (url: string | URL | Request, options?: RequestInit) => {
      if (String(url).endsWith("/auth/v1/user")) return Response.json({ id: "10000000-0000-4000-8000-000000000001", email: "host@example.test" });
      if (String(url) === "https://api.resend.com/emails") {
        emails.push(JSON.parse(String(options?.body)) as SentEmail);
        return Response.json({ id: "mail-fixture" });
      }
      throw new Error("Unexpected request");
    });
    vi.stubGlobal("fetch", fetcher);
    const env = { SUPABASE_SERVICE_ROLE_KEY: "test-only", RESEND_API_KEY: "test-only" };
    const expectedLink = `https://meet.mydailywhisper.com/meet/${identity}`;
    for (const [path, data] of [
      ["invite", { meetingId: identity, scheduledAt: "2026-10-01T12:00:00Z" }],
      ["invite-email", { link: `https://www.mydailywhisper.com/meet/${identity}?access_token=discard&autoJoin=1`, code: "wsp-WRNG-WRNG", startsAt: "2026-10-01T12:00:00Z" }],
      ["notes-email", { meetingId: identity, link: expectedLink, notes: "Next steps from our meeting." }],
    ] as const) {
      const request = new Request(`https://backend.example/meetings/${path}`, {
        method: "POST", headers: { Authorization: "Bearer fixture-session", "Content-Type": "application/json" },
        body: JSON.stringify({ ...data, title: "Design review", hostUsername: "host", emails: ["guest@example.test"] }),
      });
      const response = await worker.fetch(request, env as never);
      expect(response.status).toBe(200);
      expect(await response.json()).toMatchObject({ ok: true, sent: 1 });
    }
    expect(emails).toHaveLength(3);
    for (const email of emails) {
      expect(email.html).toContain(`href="${expectedLink}"`);
      expect(email.html).not.toContain("access_token");
      expect(email.html).not.toContain("autoJoin");
      expect(email.html).not.toContain("fixture-session");
      expect(email.html).not.toContain("wsp-WRNG-WRNG");
    }
    const ics = Buffer.from(emails[1].attachments?.[0].content ?? "", "base64").toString("utf8").replace(/\r?\n /g, "");
    expect(ics).toContain(expectedLink);
    expect(ics).not.toContain("wsp-WRNG-WRNG");
    // Only authentication and email sending: no replacement room, hash lookup, or participant write.
    expect(fetcher.mock.calls).toHaveLength(6);
  });

  it("rejects a signed-out email send before sending or touching a meeting", async () => {
    const fetcher = vi.fn(); vi.stubGlobal("fetch", fetcher);
    const response = await worker.fetch(new Request("https://backend.example/meetings/invite", { method: "POST", body: "{}" }), { SUPABASE_SERVICE_ROLE_KEY: "test-only" } as never);
    expect(response.status).toBe(401);
    expect(fetcher).not.toHaveBeenCalled();
  });
});
