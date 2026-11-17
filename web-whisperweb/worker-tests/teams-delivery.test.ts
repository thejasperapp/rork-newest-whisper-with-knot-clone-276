// @vitest-environment node
import { afterAll, beforeAll, beforeEach, describe, expect, it } from "vitest";
import { PGlite } from "@electric-sql/pglite";
import { readFile } from "node:fs/promises";

const a = "11111111-1111-4111-8111-111111111111";
const b = "22222222-2222-4222-8222-222222222222";
const c = "33333333-3333-4333-8333-333333333333";
const invitationId = "44444444-4444-4444-8444-444444444444";
const eventId = "55555555-5555-4555-8555-555555555555";
const teamId = "66666666-6666-4666-8666-666666666666";
let db: PGlite;
const event = (patch: Record<string, unknown> = {}) => ({ schemaVersion: 1, source: "whisper-teams", eventId, invitationId, invitationVersion: "1", teamId, teamName: "Private team", inviterId: a, recipientId: b, status: "pending", occurredAt: Date.now() - 1000, expiresAt: Date.now() + 3600_000, ...patch });
async function role(role: string, user = ""): Promise<void> {
  await db.query("select set_config('request.jwt.claim.role',$1,false),set_config('request.jwt.claim.sub',$2,false)", [role, user]);
}
async function receive(value: unknown): Promise<{ result: string }> {
  const result = await db.query<{ value: { result: string } }>("select public.whisper_social_teams_receive($1::jsonb) as value", [JSON.stringify(value)]);
  return result.rows[0].value;
}
async function messages(): Promise<Array<{ id: string; body: string; thread_id: string }>> {
  return (await db.query<{ id: string; body: string; thread_id: string }>("select id,body,thread_id from public.whisper_messages")).rows;
}
async function push(id: string): Promise<boolean> {
  await role("service_role");
  return (await db.query<{ value: boolean }>("select public.whisper_social_teams_push_allowed($1) as value", [id])).rows[0].value;
}
async function privacy(privateDM: boolean, approved: string[] = [], denied: string[] = [], revision = 1, installation = c): Promise<void> {
  await role("authenticated", b);
  await db.query("select public.whisper_social_teams_privacy($1,$2,$3,$4,$5::uuid[],$6::uuid[])", [b, installation, revision, privateDM, approved, denied]);
  await role("service_role");
}
beforeAll(async () => {
  db = new PGlite();
  // Isolated synthetic schema only: no production network, auth account or APNs calls.
  await db.exec(`create role anon; create role authenticated; create role service_role;
    create schema auth;
    create function auth.uid() returns uuid language sql as $$ select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid $$;
    create function auth.role() returns text language sql as $$ select current_setting('request.jwt.claim.role',true) $$;
    create table auth.users(id uuid primary key,deleted_at timestamptz,is_anonymous boolean default false,banned_until timestamptz);
    create table public.whisper_profiles(user_id uuid primary key,username text,ghost_enabled boolean default false,is_private boolean default false);
    create table public.whisper_blocks(blocker_id uuid,blocked_user_id uuid);
    create table public.whisper_dm_blocks(blocked_sender_id uuid,protected_user_id uuid);
    create table public.whisper_follows(follower_id uuid,followee_id uuid);
    create table public.whisper_notification_prefs(user_id uuid primary key,master_enabled boolean,quiet_mode boolean,dms boolean);
    create table public.whisper_messages(id uuid primary key,thread_id uuid not null,from_user_id uuid,to_user_id uuid,from_username text,to_username text,body text,created_at timestamptz default now(),read_at timestamptz,embed jsonb,media_url text);`);
  await db.exec(await readFile(new URL("../../supabase/migrations/20261001010000_social_teams_invitations.sql", import.meta.url), "utf8"));
}, 30_000);
afterAll(async () => { await db?.close(); });
beforeEach(async () => {
  await db.exec(`truncate whisper_social_teams_private.events,whisper_social_teams_private.invitations,whisper_social_teams_private.privacy,public.whisper_messages,public.whisper_profiles,public.whisper_blocks,public.whisper_dm_blocks,public.whisper_follows,public.whisper_notification_prefs,public.whisper_social_teams_push_claims;
    insert into auth.users(id) values('${a}'),('${b}'),('${c}') on conflict do nothing;
    insert into public.whisper_profiles(user_id,username) values('${a}','alice'),('${b}','bob'),('${c}','carol');`);
  await role("service_role");
});
describe("actual Social Teams migration", () => {
  it("atomically delivers once, uses the existing thread hash, and acknowledges lost-response retries", async () => {
    const value = event();
    expect((await receive(value)).result).toBe("applied");
    expect((await receive(value)).result).toBe("duplicate");
    const rows = await messages(); expect(rows).toHaveLength(1);
    expect(rows[0].body).toBe(`::whisper-teams-v1::${rows[0].id}`);
    expect(rows[0].body).not.toContain("Private team");
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(`${a}|${b}`));
    const hex = Buffer.from(digest).toString("hex").slice(0,32);
    expect(rows[0].thread_id.replaceAll("-", "")).toBe(hex);
  });
  it("rejects altered duplicate event, changed recipient and reused version with no extra message", async () => {
    const value = event(); await receive(value);
    await expect(receive({ ...value, teamName: "Changed" })).rejects.toMatchObject({ code: "PT409" });
    await expect(receive({ ...value, eventId: c })).rejects.toMatchObject({ code: "PT409" });
    await expect(receive({ ...value, eventId: c, invitationVersion: "2", recipientId: c })).rejects.toMatchObject({ code: "PT409" });
    expect(await messages()).toHaveLength(1);
  });
  it("revocation-first tombstones suppress late pending delivery and resurrection", async () => {
    const value = event({ invitationVersion: "3", status: "revoked" }); await receive(value);
    expect((await receive({ ...value, eventId: c, invitationVersion: "1", status: "pending" })).result).toBe("stale");
    await expect(receive({ ...value, eventId: b, invitationVersion: "4", status: "pending" })).rejects.toMatchObject({ code: "PT409" });
    expect(await messages()).toHaveLength(0);
  });
  it("updates one card in place without inserting lifecycle notifications or granting membership", async () => {
    const value = event(); await receive(value);
    const id = (await messages())[0].id;
    await receive({ ...value, eventId: c, invitationVersion: "2", status: "accepted" });
    await role("authenticated", b);
    const result = await db.query<{ value: { status: string; canOpen: boolean } }>("select public.whisper_social_teams_card($1) as value", [id]);
    expect(result.rows[0].value).toMatchObject({ status: "accepted", canOpen: false });
    expect(await messages()).toHaveLength(1); expect(await push(id)).toBe(false);
  });
  it.each(["platform-forward", "platform-reverse", "dm-forward", "dm-reverse"])("suppresses %s blocks durably without explaining the block", async kind => {
    const reverse = kind.endsWith("reverse");
    await db.query(kind.startsWith("platform") ? "insert into public.whisper_blocks values($1,$2)" : "insert into public.whisper_dm_blocks values($1,$2)", reverse ? [b,a] : [a,b]);
    const value = event(); expect((await receive(value)).result).toBe("suppressed");
    await db.exec("truncate public.whisper_blocks,public.whisper_dm_blocks");
    await receive({ ...value, eventId: c, invitationVersion: "2" });
    expect(await messages()).toHaveLength(0);
  });
  it("rechecks blocks after delivery, and rejects wrong-account/forged message resolution", async () => {
    await receive(event()); const id = (await messages())[0].id;
    await role("authenticated", c);
    await expect(db.query("select public.whisper_social_teams_card($1)", [id])).rejects.toMatchObject({ code: "42501" });
    await role("authenticated", b);
    await expect(db.query("select public.whisper_social_teams_card($1)", [c])).rejects.toMatchObject({ code: "42501" });
    await db.query("insert into public.whisper_blocks values($1,$2)", [b,a]);
    await expect(db.query("select public.whisper_social_teams_card($1)", [id])).rejects.toMatchObject({ code: "42501" });
    expect(await push(id)).toBe(false);
  });
  it("requires privacy evidence, keeps requests silent, applies approval, denial and reordered privacy writes", async () => {
    await receive(event()); const id = (await messages())[0].id;
    expect(await push(id)).toBe(false);
    await privacy(true); expect(await push(id)).toBe(false);
    await privacy(true,[a],[],2); expect(await push(id)).toBe(true);
    await privacy(true,[],[a],3); expect(await push(id)).toBe(false);
    await privacy(false,[a],[],2); expect(await push(id)).toBe(false);
  });
  it.each(["master_enabled", "quiet_mode", "dms"])("honors notification preference %s without deleting the inbox card", async field => {
    await privacy(false); await receive(event()); const id = (await messages())[0].id;
    await db.query(`insert into public.whisper_notification_prefs(user_id,${field}) values($1,$2)`, [b, field === "quiet_mode"]);
    expect(await push(id)).toBe(false); expect(await messages()).toHaveLength(1);
  });
  it("keeps restrictions from another installation and lets read_at suppress alerts", async () => {
    await privacy(false); await receive(event()); const id = (await messages())[0].id;
    await privacy(true,[],[],1,a); expect(await push(id)).toBe(false);
    await privacy(false,[],[],2,a); expect(await push(id)).toBe(true);
    await db.query("update public.whisper_messages set read_at=now() where id=$1", [id]);
    expect(await push(id)).toBe(false);
  });
  it("supports exact bigint versions, expires cards and never delivers already expired first observations", async () => {
    const value = event({ invitationVersion: "9007199254740993" }); await receive(value); const id = (await messages())[0].id;
    await role("authenticated", b);
    const result = await db.query<{ value: { version: string } }>("select public.whisper_social_teams_card($1) as value",[id]);
    expect(result.rows[0].value.version).toBe("9007199254740993");
    await role("service_role");
    await receive(event({ eventId: c, invitationId: c, occurredAt: Date.now()-10_000, expiresAt: Date.now()-1000 }));
    expect(await messages()).toHaveLength(1);
  });
  it("protects provenance but permits normal receipts/deletion; deletion never resurrects", async () => {
    const value = event(); await receive(value); const id = (await messages())[0].id;
    await role("authenticated", a);
    await expect(db.query("update public.whisper_messages set body='changed' where id=$1",[id])).rejects.toMatchObject({ code: "42501" });
    await expect(db.query("insert into public.whisper_messages(id,thread_id,from_user_id,to_user_id,body) values($1,$1,$2,$3,$4)",[c,a,b,`::whisper-teams-v1::${c}`])).rejects.toMatchObject({ code: "42501" });
    await db.query("delete from public.whisper_messages where id=$1",[id]);
    await role("service_role"); await receive({ ...value,eventId:c,invitationVersion:"2" });
    expect(await messages()).toHaveLength(0);
  });
  it("doesn't permit authenticated clients to call delivery or read the private ledger", async () => {
    await role("authenticated", a);
    await expect(receive(event())).rejects.toMatchObject({ code: "42501" });
    await db.exec("set role authenticated");
    await expect(db.query("select * from whisper_social_teams_private.invitations")).rejects.toMatchObject({ code: "42501" });
    await db.exec("reset role");
  });
});
